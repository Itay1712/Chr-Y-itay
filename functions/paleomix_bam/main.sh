#!/bin/bash

set -euo pipefail

fastq_prefix() {
  local fastq_file="$1"
  local file_name
  file_name=$(basename "$fastq_file")
  file_name="${file_name%.fastq.gz}"
  file_name="${file_name%.fq.gz}"
  file_name="${file_name%.fastq}"
  file_name="${file_name%.fq}"
  file_name="${file_name%_1}"
  file_name="${file_name%_2}"
  echo "$file_name"
}

run_paleomix_for_fastq() {
  local fastq_file="$1"
  local output_dir="${2:-$(dirname "$fastq_file")}" 
  local sample_label="${3:-}"
  local fastq_dir="$(dirname "$fastq_file")"
  local fastq_filename="$(basename "$fastq_file")"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local template_yaml="${script_dir}/paleomix_template.yaml"
  local reference_path="${REFERENCE_FASTA:-}"

  if [[ -z "$sample_label" ]]; then
    sample_label="$(fastq_prefix "$fastq_file")"
  fi

  local fastq_extension=""
  local fastq_basename_without_ext=""
  for ext in fastq.gz fq.gz fastq fq; do
    if [[ "$fastq_filename" == *.${ext} ]]; then
      fastq_extension="$ext"
      fastq_basename_without_ext="${fastq_filename%.$ext}"
      break
    fi
  done

  local read_number=""
  local mate_suffix=""
  local pair_placeholder_pattern=""
  if [[ "$fastq_basename_without_ext" =~ (.*)_R([12])$ ]]; then
    fastq_basename_without_ext="${BASH_REMATCH[1]}"
    read_number="${BASH_REMATCH[2]}"
    mate_suffix="_R$((3 - read_number))"
    pair_placeholder_pattern="_R{Pair}"
  elif [[ "$fastq_basename_without_ext" =~ (.*)_([12])$ ]]; then
    fastq_basename_without_ext="${BASH_REMATCH[1]}"
    read_number="${BASH_REMATCH[2]}"
    mate_suffix="_$((3 - read_number))"
    pair_placeholder_pattern="_{Pair}"
  fi

  local mate_fastq=""
  if [[ -n "$mate_suffix" && -n "$fastq_extension" ]]; then
    mate_fastq="${fastq_dir}/${fastq_basename_without_ext}${mate_suffix}.${fastq_extension}"
  fi

  if [[ ! -f "$fastq_file" ]]; then
    echo "FASTQ file not found for PALEOMIX: ${fastq_file}" >&2
    return 1
  fi

  if ! command -v paleomix >/dev/null 2>&1; then
    echo "PALEOMIX is not available in PATH. Please install paleomix before enabling paleomix_bam." >&2
    return 1
  fi

  if [[ -z "$reference_path" ]]; then
    echo "Reference FASTA not specified. Set parameters.reference_fasta in config/config.yaml." >&2
    return 1
  fi

  if [[ ! -f "$reference_path" ]]; then
    echo "Reference FASTA not found: ${reference_path}" >&2
    return 1
  fi

  local reference_name="${REFERENCE_PREFIX_NAME:-}"
  if [[ -z "$reference_name" ]]; then
    reference_name="$(basename "${reference_path}")"
    reference_name="${reference_name%.fasta}"
    reference_name="${reference_name%.fa}"
    reference_name="${reference_name%.gz}"
  fi

  mkdir -p "$output_dir"

  if [[ ! -f "$template_yaml" ]]; then
    echo "PALEOMIX template YAML not found: ${template_yaml}" >&2
    return 1
  fi

  if ! command -v envsubst >/dev/null 2>&1; then
    echo "envsubst is required to render the PALEOMIX template; please install gettext-base." >&2
    return 1
  fi

  local lane_entry
  local primary_read="$fastq_file"
  local secondary_read=""
  if [[ -n "$mate_fastq" && -f "$mate_fastq" ]]; then
    if [[ "$read_number" == "2" ]]; then
      primary_read="$mate_fastq"
      secondary_read="$fastq_file"
    else
      secondary_read="$mate_fastq"
    fi
    if [[ -n "$pair_placeholder_pattern" && -n "$fastq_extension" ]]; then
      local pair_placeholder_path="${fastq_dir}/${fastq_basename_without_ext}${pair_placeholder_pattern}.${fastq_extension}"
      lane_entry="      Lane1: ${pair_placeholder_path}"
    else
      lane_entry="      Lane1: [${primary_read}, ${secondary_read}]"
    fi
    echo "Detected paired-end FASTQ files for '${sample_label}': ${primary_read} and ${secondary_read}." >&2
  else
    if [[ -n "$mate_fastq" ]]; then
      echo "Paired-end naming detected for '${fastq_file}' but mate FASTQ not found at '${mate_fastq}'. Running single-end." >&2
    fi
    lane_entry="      Lane1: ${fastq_file}"
  fi

  local yaml_file="${output_dir}/${sample_label}_paleomix.yaml"

  if [[ "$read_number" == "2" && -f "$yaml_file" && -n "$secondary_read" ]]; then
    echo "PALEOMIX YAML already exists for '${sample_label}'. Skipping duplicate invocation for mate read '${fastq_file}'." >&2
    return 0
  fi

  REFERENCE_PREFIX_NAME="$reference_name" \
  REFERENCE_FASTA="$reference_path" \
    envsubst '${REFERENCE_PREFIX_NAME}${REFERENCE_FASTA}' < "$template_yaml" > "$yaml_file"
  {
    printf '\n'
    cat <<EOF2
Project:
  ${sample_label}:
    ${sample_label}_Library:
${lane_entry}
EOF2
  } >>"${yaml_file}"

  echo "Running PALEOMIX BAM pipeline for '${fastq_file}' (YAML: ${yaml_file})." >&2
  (cd "$output_dir" && paleomix bam_pipeline run "${yaml_file}")
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_paleomix_for_fastq "$@"
fi
