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
  file_name="${file_name%_R1}"
  file_name="${file_name%_R2}"
  file_name="${file_name%_1}"
  file_name="${file_name%_2}"
  echo "$file_name"
}

render_eager_files() {
  local template_dir="$1"
  local samplesheet_path="$2"
  local config_path="$3"

  if ! command -v envsubst >/dev/null 2>&1; then
    echo "envsubst is required to render EAGER templates; please install gettext-base." >&2
    return 1
  fi

  envsubst <"${template_dir}/samplesheet_template.tsv" >"${samplesheet_path}"
  envsubst <"${template_dir}/eager_template.config" >"${config_path}"
}

run_eager_for_fastq() {
  local fastq_file="$1"
  local output_dir="${2:-$(dirname "$fastq_file")}" 
  local sample_label="${3:-}"
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  local template_dir="${script_dir}"

  if [[ -z "$sample_label" ]]; then
    sample_label="$(fastq_prefix "$fastq_file")"
  fi

  local fastq_dir="$(dirname "$fastq_file")"
  local fastq_filename="$(basename "$fastq_file")"
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
  if [[ "$fastq_basename_without_ext" =~ (.*)_R([12])$ ]]; then
    fastq_basename_without_ext="${BASH_REMATCH[1]}"
    read_number="${BASH_REMATCH[2]}"
    mate_suffix="_R$((3 - read_number))"
  elif [[ "$fastq_basename_without_ext" =~ (.*)_([12])$ ]]; then
    fastq_basename_without_ext="${BASH_REMATCH[1]}"
    read_number="${BASH_REMATCH[2]}"
    mate_suffix="_$((3 - read_number))"
  fi

  local mate_fastq=""
  if [[ -n "$mate_suffix" && -n "$fastq_extension" ]]; then
    mate_fastq="${fastq_dir}/${fastq_basename_without_ext}${mate_suffix}.${fastq_extension}"
  fi

  if [[ ! -f "$fastq_file" ]]; then
    echo "FASTQ file not found for EAGER: ${fastq_file}" >&2
    return 1
  fi

  local reference_path="${REFERENCE_FASTA:-${EAGER_REFERENCE:-}}"
  if [[ -z "$reference_path" ]]; then
    echo "Reference FASTA not specified. Set parameters.reference_fasta in config/config.yaml." >&2
    return 1
  fi

  if [[ ! -f "$reference_path" ]]; then
    echo "Reference FASTA not found for EAGER: ${reference_path}" >&2
    return 1
  fi

  mkdir -p "${output_dir}" "${output_dir}/eager"
  local sample_output_dir="${output_dir}/eager/${sample_label}"
  mkdir -p "${sample_output_dir}"

  local primary_read="$fastq_file"
  local secondary_read="NA"
  local paired_flag=false

  if [[ -n "$mate_fastq" && -f "$mate_fastq" ]]; then
    paired_flag=true
    if [[ "$read_number" == "2" ]]; then
      primary_read="$mate_fastq"
      secondary_read="$fastq_file"
    else
      secondary_read="$mate_fastq"
    fi
  fi

  local samplesheet_path="${sample_output_dir}/samplesheet.tsv"
  local config_path="${sample_output_dir}/eager_rendered.config"
  local eager_results_dir="${sample_output_dir}/results_eager_run"

  if [[ "$read_number" == "2" && -f "$samplesheet_path" ]]; then
    echo "EAGER samplesheet already exists for '${sample_label}'. Skipping duplicate invocation for mate read '${fastq_file}'." >&2
    return 0
  fi

  export EAGER_SAMPLE_NAME="$sample_label"
  export EAGER_LIBRARY_ID="${sample_label}_Lib1"
  export EAGER_SEQTYPE=$([[ "${paired_flag}" == true ]] && echo "PE" || echo "SE")
  export EAGER_ORGANISM="${EAGER_ORGANISM:-Canis_lupus}"
  export EAGER_STRANDEDNESS="${EAGER_STRANDEDNESS:-double}"
  export EAGER_UDG_TREATMENT="${EAGER_UDG_TREATMENT:-none}"
  export EAGER_R1="$primary_read"
  export EAGER_R2=$([[ "${paired_flag}" == true ]] && echo "$secondary_read" || echo "NA")
  export EAGER_INPUT="$samplesheet_path"
  export EAGER_FASTA="$reference_path"
  export EAGER_PAIRED=$([[ "${paired_flag}" == true ]] && echo true || echo false)
  export EAGER_OUTDIR="$eager_results_dir"
  export EAGER_ALIGNER="${EAGER_ALIGNER:-bwaaln}"
  export EAGER_DEDUPPER="${EAGER_DEDUPPER:-markduplicates}"

  render_eager_files "$template_dir" "$samplesheet_path" "$config_path" || return 1

  if ! command -v nextflow >/dev/null 2>&1; then
    echo "Nextflow is required to run nf-core/eager. Please install Nextflow." >&2
    return 1
  fi

  local pipeline_ref="${EAGER_PIPELINE_REF:-nf-core/eager}"
  local pipeline_rev="${EAGER_PIPELINE_REV:-2.5.3}"
  local profile="${EAGER_NEXTFLOW_PROFILE:-standard}"
  local -a extra_args=()
  if [[ -n "${EAGER_NEXTFLOW_ARGS:-}" ]]; then
    read -ra extra_args <<<"${EAGER_NEXTFLOW_ARGS}"
  fi

  local -a nextflow_cmd=("nextflow" "run" "${pipeline_ref}" "-r" "${pipeline_rev}" "-c" "${config_path}" "-profile" "${profile}")
  nextflow_cmd+=("${extra_args[@]}")

  echo "Running ${pipeline_ref} for '${sample_label}' (config: ${config_path}, samplesheet: ${samplesheet_path})." >&2
  (cd "${sample_output_dir}" && "${nextflow_cmd[@]}")
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  run_eager_for_fastq "$@"
fi
