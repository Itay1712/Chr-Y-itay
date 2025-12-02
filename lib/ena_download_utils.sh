#!/bin/bash

# Utilities for downloading ENA FASTQ files using filter parameters.

# Determine repository directory if not provided by the caller. This ensures
# path expansion in configuration values works even when the library is sourced
# without the main entrypoint script.
if [[ -z "${REPO_DIR:-}" ]]; then
  if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  else
    REPO_DIR="$(pwd)"
  fi
fi

RULE_DELIM=$'\x1f'

declare -ag CONDITION_NAMES=()
declare -ag FILTER_CONDITIONS=()
declare -Ag CONDITION_RULES=()
declare -ag PROJECTS_TO_DOWNLOAD=()

initialize_defaults() {
  DEFAULT_DOWNLOAD="fastq_ftp"
  DEFAULT_RENAME_PATTERN='SAMPLE_${sample_alias}_LIB_${library_name}_RUN-${run_accession}'
  BASE_FIELDS="study_accession,sample_accession,submitted_ftp,scientific_name,library_layout,sample_alias,library_name,fastq_bytes,secondary_study_accession"

  OUTPUT_DIR="${REPO_DIR}/output"
  METADATA_DIR="${OUTPUT_DIR}"

  KEEP_FASTQ="yes"
  GENERATE_CONSENSUS="no"
  PALEOMIX_BAM="no"
  TRIM_UNKNOWN_ADAPTERS="no"
  REFERENCE_FASTA=""
  CUSTOM_FUNCTION="no"
  RUN_EAGER="no"
}

trim_whitespace() {
  local value="$1"
  value="${value#${value%%[![:space:]]*}}"
  value="${value%${value##*[![:space:]]}}"
  echo "$value"
}

normalize_condition_value() {
  local key="$1"
  local value
  value="$(trim_whitespace "$2")"

  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"

  if [[ "$key" != "rename_pattern" && "$key" != "download" ]]; then
    value="${value//,/|}"
  fi

  echo "$value"
}

normalize_plain_value() {
  local value
  value="$(trim_whitespace "$1")"

  value="${value#\"}"
  value="${value%\"}"
  value="${value#\'}"
  value="${value%\'}"

  echo "$value"
}

resolve_path_value() {
  local raw_value="$1"
  local expanded
  local nounset_disabled=0

  # Temporarily disable nounset to allow optional placeholders to expand to
  # empty strings instead of triggering errors when set -u is enabled.
  if [[ $- == *u* ]]; then
    set +u
    nounset_disabled=1
  fi

  expanded="$(REPO_DIR="${REPO_DIR:-}" OUTPUT_DIR="${OUTPUT_DIR:-}" METADATA_DIR="${METADATA_DIR:-}" eval "echo \"${raw_value}\"")"

  if [[ ${nounset_disabled} -eq 1 ]]; then
    set -u
  fi

  echo "$expanded"
}

append_condition_rule() {
  local cond_name="$1"
  local entry="$2"

  if [[ -z "${CONDITION_RULES[$cond_name]:-}" ]]; then
    CONDITION_RULES[$cond_name]="$entry"
  else
    CONDITION_RULES[$cond_name]+=$'\n'"$entry"
  fi
}

load_config_from_yaml() {
  local yaml_file="$1"

  if [[ ! -f "$yaml_file" ]]; then
    echo "Error: YAML config file '$yaml_file' not found."
    return 1
  fi

  initialize_defaults

  CONDITION_NAMES=()
  FILTER_CONDITIONS=()
  CONDITION_RULES=()
  PROJECTS_TO_DOWNLOAD=()

  local current_condition=""
  local section=""

  while IFS= read -r line || [[ -n "$line" ]]; do
    local trimmed
    trimmed="$(trim_whitespace "$line")"

    if [[ -z "$trimmed" || "${trimmed:0:1}" == "#" ]]; then
      continue
    fi

    case "$trimmed" in
      defaults:)
        section="defaults"
        current_condition=""
        continue
        ;;
      paths:)
        section="paths"
        current_condition=""
        continue
        ;;
      conditions:)
        section="conditions"
        current_condition=""
        continue
        ;;
      projects_to_download:)
        section="projects_to_download"
        current_condition=""
        continue
        ;;
      functions:)
        section="functions"
        current_condition=""
        continue
        ;;
      parameters:)
        section="parameters"
        current_condition=""
        continue
        ;;
    esac

    if [[ "$trimmed" =~ ^base_fields:[[:space:]]*(.*)$ ]]; then
      BASE_FIELDS="$(normalize_plain_value "${BASH_REMATCH[1]}")"
      continue
    fi

    if [[ "$section" == "defaults" && "$trimmed" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local raw_value="${BASH_REMATCH[2]}"
      local value
      value="$(normalize_plain_value "$raw_value")"
      case "$key" in
        download)
          DEFAULT_DOWNLOAD="$value"
          ;;
        rename_pattern)
          DEFAULT_RENAME_PATTERN="$value"
          ;;
      esac
      continue
    fi

    if [[ "$section" == "paths" && "$trimmed" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local raw_value="${BASH_REMATCH[2]}"
      local value
      value="$(resolve_path_value "$(normalize_plain_value "$raw_value")")"
      case "$key" in
        output_dir)
          OUTPUT_DIR="$value"
          ;;
        metadata_dir)
          METADATA_DIR="$value"
          ;;
      esac
      continue
    fi

    if [[ "$section" == "functions" && "$trimmed" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local raw_value="${BASH_REMATCH[2]}"
      local value
      value="$(normalize_plain_value "$raw_value")"
      case "$key" in
        keep_fastq)
          value="${value,,}"
          KEEP_FASTQ="$value"
          ;;
        generate_consensus)
          value="${value,,}"
          GENERATE_CONSENSUS="$value"
          ;;
        trim_unknown_adapters)
          value="${value,,}"
          TRIM_UNKNOWN_ADAPTERS="$value"
          ;;
        custom_function)
          value="${value,,}"
          CUSTOM_FUNCTION="$value"
          ;;
        paleomix_bam)
          value="${value,,}"
          PALEOMIX_BAM="$value"
          ;;
        run_eager)
          value="${value,,}"
          RUN_EAGER="$value"
          ;;
      esac
      continue
    fi

    if [[ "$section" == "parameters" && "$trimmed" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local raw_value="${BASH_REMATCH[2]}"
      local value
      value="$(normalize_plain_value "$raw_value")"
      case "$key" in
        reference_fasta)
          REFERENCE_FASTA="$(resolve_path_value "$value")"
          ;;
      esac
      continue
    fi

    if [[ "$section" == "projects_to_download" && "$trimmed" =~ ^-[[:space:]]*(.+)$ ]]; then
      FILTER_CONDITIONS+=( "${BASH_REMATCH[1]}" )
      continue
    fi

    if [[ "$section" == "conditions" && "$trimmed" =~ ^([^[:space:]].*):$ ]]; then
      current_condition="${trimmed%%:*}"
      CONDITION_NAMES+=( "$current_condition" )
      CONDITION_RULES["$current_condition"]=""
      continue
    fi

    if [[ "$section" == "conditions" && -n "$current_condition" && "$trimmed" =~ ^([A-Za-z0-9_]+):[[:space:]]*(.*)$ ]]; then
      local item_key="${BASH_REMATCH[1]}"
      local raw_value="${BASH_REMATCH[2]}"
      local value
      value="$(normalize_condition_value "$item_key" "$raw_value")"
      append_condition_rule "$current_condition" "${item_key}=${value}"
    fi
  done < "$yaml_file"

    if [[ -z "$METADATA_DIR" ]]; then
      METADATA_DIR="$OUTPUT_DIR"
    fi

    # Export parameters that downstream helper scripts expect so they are
    # available when invoked in separate processes (e.g., PALEOMIX helper).
    if [[ -n "${REFERENCE_FASTA}" ]]; then
      export REFERENCE_FASTA
    fi

  if [[ ${#FILTER_CONDITIONS[@]} -gt 0 ]]; then
    PROJECTS_TO_DOWNLOAD=( "${FILTER_CONDITIONS[@]}" )
  else
    PROJECTS_TO_DOWNLOAD=( "${CONDITION_NAMES[@]}" )
  fi

  if [[ ${#PROJECTS_TO_DOWNLOAD[@]} -eq 0 ]]; then
    echo "Error: No conditions defined in ${yaml_file}."
    return 1
  fi

  if [[ "${GENERATE_CONSENSUS}" == "yes" && -z "${REFERENCE_FASTA}" ]]; then
    echo "Warning: generate_consensus is enabled but no reference_fasta is set under parameters; consensus steps may fail."
  fi
}

add_column() {
  local col="$1"
  if [[ ! ",$BASE_FIELDS," =~ ",$col," ]]; then
    BASE_FIELDS="${BASE_FIELDS},${col}"
  fi
}

parse_item() {
  local item="$1"

  if [[ "$item" == rename_pattern=* ]]; then
    local rename_pattern
    rename_pattern="${item#rename_pattern=}"
    local placeholders
    placeholders="$(grep -oP '(?<=\${)[^}]+' <<< "${rename_pattern}" | sort -u)"
    for p in $placeholders; do
      add_column "$p"
    done
  elif [[ "$item" == download=* ]]; then
    local download
    download="${item#download=}"
    add_column "$download"
  elif [[ "$item" =~ ^([^=<>!]+)(=|<|<=|>|>=|!=).*$ ]]; then
    local col="${BASH_REMATCH[1]}"
    col="$(echo "$col" | xargs)"
    add_column "$col"
  fi
}

prepare_base_fields() {
  local -a filter_names=($(printf '%s ' "$@"))

  parse_item "rename_pattern=$DEFAULT_RENAME_PATTERN"
  parse_item "download=$DEFAULT_DOWNLOAD"

  for cond_name in "${filter_names[@]}"; do
    local cond_rules="${CONDITION_RULES[$cond_name]:-}"
    if [[ -z "$cond_rules" ]]; then
      echo "Warning: Condition '${cond_name}' not found while preparing base fields."
      continue
    fi
    while IFS= read -r item; do
      [[ -z "$item" ]] && continue
      parse_item "$item"
    done <<< "$cond_rules"
  done
}

load_condition() {
  local cond_name="$1"
  local cond_rules="${CONDITION_RULES[$cond_name]:-}"

  if [[ -z "$cond_rules" ]]; then
    echo "Error: Condition '${cond_name}' not found in configuration."
    return 1
  fi

  mapfile -t conds <<< "$cond_rules"
}

fetch_metadata() {
  local project_id="$1"
  local metadata_file="$2"

  if [[ ! -s "${metadata_file}" ]]; then
    echo "Fetching metadata for project ${project_id}..."
    wget -O "${metadata_file}" "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${project_id}&result=read_run&fields=${BASE_FIELDS}&format=tsv&download=true"
    if [[ ! -s "${metadata_file}" ]]; then
      echo "Error: Failed to download metadata for ${project_id}."
      return 1
    fi
  else
    echo "Using cached metadata for project ${project_id}"
  fi
}

build_header_index() {
  local header_line="$1"
  IFS=$'\t' read -r -a HEADER_ARRAY <<< "$header_line"
  declare -gA COL_INDEX=()
  for i in "${!HEADER_ARRAY[@]}"; do
    local colName="${HEADER_ARRAY[$i]}"
    COL_INDEX["$colName"]=$((i+1))
  done
}

build_filter_expression() {
  local -a rules=($(printf '%s ' "$@"))
  AWK_JOINED_FILTER=""

  for rule_str in "${rules[@]}"; do
    IFS="$RULE_DELIM" read -r col op val <<< "$rule_str"
    local idx="${COL_INDEX[$col]}"
    if [[ -z "$idx" ]]; then
      echo "Warning: Column '${col}' not found in metadata; skipping rule."
      continue
    fi
    if [[ "$op" == "=" ]]; then
      if [[ "$val" == *"|"* ]]; then
        expr_part="\$${idx} ~ /^(${val})\$/"
      else
        expr_part="\$${idx} == \"${val}\""
      fi
    else
      expr_part="\$${idx} ${op} ${val}"
    fi
    if [[ -z "$AWK_JOINED_FILTER" ]]; then
      AWK_JOINED_FILTER="${expr_part}"
    else
      AWK_JOINED_FILTER="${AWK_JOINED_FILTER} && ${expr_part}"
    fi
  done

  # Quote and wrap in an explicit conditional to avoid unintended expansion and
  # to prevent `set -e` from exiting when the filter is non-empty.
  if [[ -z "${AWK_JOINED_FILTER}" ]]; then
    AWK_JOINED_FILTER="1"
  fi
}

extract_rename_columns() {
  local rename_pattern="$1"
  RENAME_COLS=()
  while read -r var; do
    if [[ ! " ${RENAME_COLS[*]} " =~ " ${var} " ]]; then
      RENAME_COLS+=( "$var" )
    fi
  done < <(echo "$rename_pattern" | grep -oE '\$\{[^}]+\}' | sed 's/[${}]//g')
}

generate_mapping_files() {
  local filtered_metadata="$1"
  local dcol_index="$2"
  local rename_pattern="$3"
  local condition_name="$4"

  extract_rename_columns "$rename_pattern"
  echo "Rename columns extracted from pattern: ${RENAME_COLS[*]}"

  local build_rename_expr=""
  for col in "${RENAME_COLS[@]}"; do
    local idx="${COL_INDEX[$col]}"
    if [[ -n "$idx" ]]; then
      build_rename_expr+='tmp = $'"$idx"';'
      build_rename_expr+='rstr = (rstr=="" ? tmp : rstr "\t" tmp);'
    else
      echo "Warning: Rename column '${col}' not found in metadata; using empty value."
      build_rename_expr+='rstr = (rstr=="" ? "" : rstr "\t");'
    fi
  done

  MAPPING_FILE="${OUTPUT_DIR}/download_mapping_${condition_name}.txt"
  awk -F'\t' -v dcol="${dcol_index}" -v OFS='\t' '
    NR>1 {
      split($dcol, urls, ";");
      for(i in urls) {
        if(urls[i] != "") {
          rstr="";
          '"${build_rename_expr}"'
          print "ftp://" urls[i], rstr;
        }
      }
    }
  ' "${filtered_metadata}" > "${MAPPING_FILE}"

  URL_LIST_FILE="${OUTPUT_DIR}/download_urls_${condition_name}.txt"
  cut -f1 "${MAPPING_FILE}" > "${URL_LIST_FILE}"
  echo "Created mapping file: ${MAPPING_FILE}"
  echo "Created URL list: ${URL_LIST_FILE}"
}

download_and_rename() {
  local condition_name="$1"
  local rename_pattern="$2"
  local condition_dir="$3"

  echo "Downloading files for condition ${condition_name} into ${condition_dir}..."

  echo "Renaming downloaded files for condition ${condition_name} using pattern: ${rename_pattern}"
  # ENA_download.sh enables `set -e`, so we disable it locally to keep a single
  # failed download/rename from aborting the whole condition. Errors are logged
  # and processing continues with the next row, after which we restore the
  # previous errexit state.
  local errexit_was_set=0
  if [[ $- == *e* ]]; then
    errexit_was_set=1
    set +e
  fi

  process_downloaded_fastq() {
    local renamed_path="$1"
    local sample_label="$2"

    local processed_fastqs=("${renamed_path}")
    local primary_fastq="${renamed_path}"

    if [[ "${TRIM_UNKNOWN_ADAPTERS:-no}" == "yes" ]]; then
      local trim_errexit_was_set=0
      if [[ $- == *e* ]]; then
        trim_errexit_was_set=1
        set +e
      fi

      local trimmed_output
      local trim_status=0
      if trimmed_output="$(trim_unknown_adapters_for_fastq "${renamed_path}" "${condition_dir}")"; then
        if [[ -n "${trimmed_output}" ]]; then
          mapfile -t processed_fastqs <<< "${trimmed_output}"
          if [[ ${#processed_fastqs[@]} -gt 0 ]]; then
            primary_fastq="${processed_fastqs[0]}"
          fi
        fi
      else
        trim_status=$?
        echo "Adapter trimming failed for '${renamed_path}' (exit code: ${trim_status}). Continuing with untrimmed FASTQ." >&2
        processed_fastqs=("${renamed_path}")
        primary_fastq="${renamed_path}"
      fi

      if [[ ${trim_errexit_was_set} -eq 1 ]]; then
        set -e
      else
        set +e
      fi
    fi

    if [[ "${GENERATE_CONSENSUS}" == "yes" ]]; then
      # Allow consensus generation to fail without aborting the entire workflow
      # (e.g., due to toolchain issues or problematic input). This ensures the
      # downloaded FASTQ remains renamed even when consensus cannot be
      # produced. Preserve the caller's errexit state while doing so.
      local consensus_errexit_was_set=0
      if [[ $- == *e* ]]; then
        consensus_errexit_was_set=1
        set +e
      fi

      generate_consensus_from_fastq "${primary_fastq}" "${REFERENCE_FASTA}" "${condition_dir}"
      local consensus_status=$?

      if [[ ${consensus_errexit_was_set} -eq 1 ]]; then
        set -e
      else
        set +e
      fi

      if [[ ${consensus_status} -ne 0 ]]; then
        echo "Consensus generation failed for '${renamed_path}' (exit code: ${consensus_status}). Skipping consensus for this file."
      fi
    fi

    if [[ "${PALEOMIX_BAM:-no}" == "yes" ]]; then
      local paleomix_errexit_was_set=0
      if [[ $- == *e* ]]; then
        paleomix_errexit_was_set=1
        set +e
      fi

      run_paleomix_pipeline_for_fastq "${primary_fastq}" "${condition_dir}" "${sample_label}"
      local paleomix_status=$?

      if [[ ${paleomix_errexit_was_set} -eq 1 ]]; then
        set -e
      else
        set +e
      fi

      if [[ ${paleomix_status} -ne 0 ]]; then
        echo "PALEOMIX BAM generation failed for '${renamed_path}' (exit code: ${paleomix_status}). Skipping PALEOMIX for this file."
      fi
    fi

    if [[ "${RUN_EAGER:-no}" == "yes" ]]; then
      local eager_errexit_was_set=0
      if [[ $- == *e* ]]; then
        eager_errexit_was_set=1
        set +e
      fi

      run_eager_pipeline_for_fastq "${primary_fastq}" "${condition_dir}" "${sample_label}"
      local eager_status=$?

      if [[ ${eager_errexit_was_set} -eq 1 ]]; then
        set -e
      else
        set +e
      fi

      if [[ ${eager_status} -ne 0 ]]; then
        echo "EAGER run failed for '${renamed_path}' (exit code: ${eager_status}). Skipping EAGER for this file."
      fi
    fi

    if [[ "${CUSTOM_FUNCTION:-no}" == "yes" ]]; then
      local custom_errexit_was_set=0
      if [[ $- == *e* ]]; then
        custom_errexit_was_set=1
        set +e
      fi

      run_custom_function_for_fastq "${primary_fastq}" "${condition_dir}"
      local custom_status=$?

      if [[ ${custom_errexit_was_set} -eq 1 ]]; then
        set -e
      else
        set +e
      fi

      if [[ ${custom_status} -ne 0 ]]; then
        echo "Custom function failed for '${renamed_path}' (exit code: ${custom_status}). Skipping further processing for this file."
        return
      fi
    fi

    if [[ "${KEEP_FASTQ}" == "no" ]]; then
      local fastqs_to_remove=("${processed_fastqs[@]}")
      if [[ "${primary_fastq}" != "${renamed_path}" ]]; then
        fastqs_to_remove+=("${renamed_path}")
        if [[ "${renamed_path}" =~ ^(.*)_([12])\.fastq\.gz$ ]]; then
          local mate_guess
          mate_guess="${BASH_REMATCH[1]}_$((3 - BASH_REMATCH[2])).fastq.gz"
          mate_guess="${condition_dir}/$(basename "${mate_guess}")"
          if [[ -f "${mate_guess}" ]]; then
            fastqs_to_remove+=("${mate_guess}")
          fi
        fi
      fi

      if [[ "${GENERATE_CONSENSUS}" == "yes" ]]; then
        echo "Removing FASTQ after consensus generation: ${fastqs_to_remove[*]}"
      else
        echo "Removing FASTQ as keep_fastq is set to 'no': ${fastqs_to_remove[*]}"
      fi

      for fastq_to_remove in "${fastqs_to_remove[@]}"; do
        delete_fastq_file "${fastq_to_remove}"
      done
    fi
  }

  cleanup_rename_vars() {
    for var in "${RENAME_COLS[@]}"; do
      unset "$var"
    done
  }

  declare -Ag PENDING_PAIRED_FASTQS=()
  declare -Ag PROCESSED_PAIRED_FASTQS=()

  process_or_queue_fastq() {
    local renamed_path="$1"
    local sample_label="$2"

    local base_name
    base_name="$(basename "${renamed_path}")"

    local paired_prefix=""
    local read_number=""
    if [[ "${base_name}" =~ ^(.*)_([12])\.fastq\.gz$ ]]; then
      paired_prefix="${BASH_REMATCH[1]}"
      read_number="${BASH_REMATCH[2]}"
    fi

    if [[ -n "${paired_prefix}" ]]; then
      local mate_suffix
      mate_suffix="$((3 - read_number))"
      local mate_fastq="${condition_dir}/${paired_prefix}_${mate_suffix}.fastq.gz"

      if [[ -n "${PROCESSED_PAIRED_FASTQS[${paired_prefix}]:-}" ]]; then
        return
      fi

      if [[ -f "${mate_fastq}" && -s "${mate_fastq}" ]]; then
        local primary_fastq="${condition_dir}/${paired_prefix}_1.fastq.gz"
        if [[ ! -f "${primary_fastq}" ]]; then
          primary_fastq="${renamed_path}"
        fi

        process_downloaded_fastq "${primary_fastq}" "${paired_prefix}"
        PROCESSED_PAIRED_FASTQS["${paired_prefix}"]=1
      else
        PENDING_PAIRED_FASTQS["${paired_prefix}"]="${renamed_path}"
      fi
    else
      process_downloaded_fastq "${renamed_path}" "${sample_label}"
    fi
  }

  while IFS=$'\t' read -r file_url rename_vals; do
    [[ -z "$file_url" ]] && continue

    local file_name
    file_name=$(basename "${file_url}")
    local download_target="${condition_dir}/${file_name}"

    IFS=$'\t' read -r -a rename_values_array <<< "$rename_vals"
    for i in "${!RENAME_COLS[@]}"; do
      local var_name="${RENAME_COLS[$i]}"
      local var_value="${rename_values_array[$i]-}"

      if [[ -z "${rename_values_array[$i]+set}" ]]; then
        echo "Warning: Rename column '${var_name}' missing in mapping row; using empty value."
      fi

      export "${var_name}=${var_value}"
    done

    eval "new_name=\"$rename_pattern\""
    local suffix
    suffix=$(echo "$file_name" | grep -oE "_[12]\.fastq\.gz$")
    if [[ -n "$suffix" ]]; then
      final_name="${new_name}${suffix}"
    else
      final_name="${new_name}.fastq.gz"
    fi
    local renamed_path="${condition_dir}/${final_name}"

    if [[ -f "${renamed_path}" ]]; then
      if [[ ! -s "${renamed_path}" ]]; then
        echo "Existing renamed FASTQ is empty; removing and re-downloading: ${renamed_path}"
        rm -f "${renamed_path}"
      else
        echo "Skipping ${file_name}: renamed FASTQ already exists at ${renamed_path}"
        process_or_queue_fastq "${renamed_path}" "${new_name}"
        cleanup_rename_vars
        continue
      fi
    fi

    echo "Downloading ${file_name}..."
    if ! wget --wait=20 --random-wait --continue --no-clobber -O "${download_target}" "${file_url}"; then
      if [[ -f "${download_target}" && -s "${download_target}" ]]; then
        echo "Download reported an error for ${file_url}, but '${download_target}' exists; proceeding with rename."
      else
        echo "Download failed for ${file_url}; skipping rename and consensus for this entry."
        cleanup_rename_vars
        continue
      fi
    fi

    if [[ -f "$download_target" ]]; then
      echo "Renaming '${file_name}' to '${final_name}'"
      if ! mv "${download_target}" "${renamed_path}"; then
        echo "Failed to rename '${file_name}' to '${final_name}'; leaving original download in place."
        cleanup_rename_vars
        continue
      fi

      process_or_queue_fastq "${renamed_path}" "${new_name}"
    else
      echo "Warning: File '${download_target}' not found; skipping renaming."
    fi

    cleanup_rename_vars
  done < "${OUTPUT_DIR}/download_mapping_${condition_name}.txt"

  for paired_prefix in "${!PENDING_PAIRED_FASTQS[@]}"; do
    if [[ -n "${PROCESSED_PAIRED_FASTQS[${paired_prefix}]:-}" ]]; then
      continue
    fi

    local mate_fastq
    mate_fastq="${condition_dir}/${paired_prefix}_2.fastq.gz"
    if [[ ! -f "${mate_fastq}" || ! -s "${mate_fastq}" ]]; then
      mate_fastq="${condition_dir}/${paired_prefix}_1.fastq.gz"
    fi

    if [[ ! -f "${mate_fastq}" || ! -s "${mate_fastq}" ]]; then
      mate_fastq="${PENDING_PAIRED_FASTQS[${paired_prefix}]}"
    fi

    process_downloaded_fastq "${mate_fastq}" "${paired_prefix}"
    PROCESSED_PAIRED_FASTQS["${paired_prefix}"]=1
  done

  if [[ ${errexit_was_set} -eq 1 ]]; then
    set -e
  fi
}

process_condition() {
  local cond_name="$1"

  echo "============================================="
  echo "Processing condition: ${cond_name}"

  if ! load_condition "$cond_name"; then
    echo "Skipping condition: ${cond_name}"
    return
  fi

  local DOWNLOAD_COLUMN_SPEC=""
  local RENAME_PATTERN=""
  local PROJECT_ID=""
  local RULES=()

  for rule in "${conds[@]}"; do
    if [[ "$rule" =~ ^download= ]]; then
      DOWNLOAD_COLUMN_SPEC="${rule#download=}"
      echo "Download column specified as: ${DOWNLOAD_COLUMN_SPEC}"
    elif [[ "$rule" =~ ^rename_pattern= ]]; then
      RENAME_PATTERN="${rule#rename_pattern=}"
      echo "Rename pattern specified as: ${RENAME_PATTERN}"
    else
      if [[ "$rule" =~ ^([^<>=]+)(<=|>=|<|>|=)(.+)$ ]]; then
        col="$(echo "${BASH_REMATCH[1]}" | xargs)"
        op="${BASH_REMATCH[2]}"
        val="$(echo "${BASH_REMATCH[3]}" | xargs)"
        echo "Adding filter: ${col} ${op} ${val}"
        RULES+=( "${col}${RULE_DELIM}${op}${RULE_DELIM}${val}" )
        if [[ "$col" == *"study_accession"* && -z "$PROJECT_ID" ]]; then
          PROJECT_ID="$val"
          echo "Project accession set to: ${PROJECT_ID} (from column: ${col})"
        fi
      else
        echo "Warning: Could not parse rule: $rule"
      fi
    fi
  done

  [[ -z "$DOWNLOAD_COLUMN_SPEC" ]] && DOWNLOAD_COLUMN_SPEC="${DEFAULT_DOWNLOAD}" && echo "No download specification provided. Using default: ${DOWNLOAD_COLUMN_SPEC}"
  [[ -z "$RENAME_PATTERN" ]] && RENAME_PATTERN="${DEFAULT_RENAME_PATTERN}" && echo "No rename pattern provided. Using default: ${RENAME_PATTERN}"

  if [[ -z "$PROJECT_ID" ]]; then
    echo "Error: No accession rule provided in condition ${cond_name}. Skipping."
    return
  fi

  local METADATA_FILE="${METADATA_DIR}/metadata_${PROJECT_ID}.tsv"
  fetch_metadata "$PROJECT_ID" "$METADATA_FILE" || return

  local HEADER_LINE
  HEADER_LINE=$(head -n1 "${METADATA_FILE}")
  build_header_index "$HEADER_LINE"

  local dcol_index="${COL_INDEX[${DOWNLOAD_COLUMN_SPEC}]}"
  if [[ -z "$dcol_index" ]]; then
    echo "Error: Download column '${DOWNLOAD_COLUMN_SPEC}' not found in metadata for project ${PROJECT_ID}. Skipping condition ${cond_name}."
    return
  fi

  build_filter_expression "${RULES[@]}"
  echo "AWK filter: ${AWK_JOINED_FILTER}"

  local FILTERED_METADATA="${METADATA_FILE%.tsv}_filtered_${cond_name}.tsv"
  awk -F'\t' -v OFS='\t' 'NR==1 {print; next} '"${AWK_JOINED_FILTER}"' {print}' "${METADATA_FILE}" > "${FILTERED_METADATA}"

  local DATA_LINES
  DATA_LINES=$(wc -l < "${FILTERED_METADATA}")
  if [[ "${DATA_LINES}" -le 1 ]]; then
    echo "Warning: No data rows passed filters for condition ${cond_name}."
    : > "${OUTPUT_DIR}/download_urls_${cond_name}.txt"
    : > "${OUTPUT_DIR}/download_mapping_${cond_name}.txt"
    return
  fi

  generate_mapping_files "$FILTERED_METADATA" "$dcol_index" "$RENAME_PATTERN" "$cond_name"

  local CONDITION_OUTPUT_DIR="${OUTPUT_DIR}/${cond_name}"
  mkdir -p "${CONDITION_OUTPUT_DIR}"
  download_and_rename "$cond_name" "$RENAME_PATTERN" "$CONDITION_OUTPUT_DIR"

  echo "Condition ${cond_name} processing complete."
  echo "Files downloaded and renamed in: ${CONDITION_OUTPUT_DIR}"
}

process_all_conditions() {
  local -a filter_names=($(printf '%s ' "$@"))
  prepare_base_fields "${filter_names[@]}"

  for cond_name in "${filter_names[@]}"; do
    process_condition "$cond_name"
  done

  echo "============================================="
  echo "All conditions processed."
}
