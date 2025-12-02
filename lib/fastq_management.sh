#!/bin/bash

# Helper functions for managing FASTQ files after download.

if [[ -z "${REPO_DIR:-}" ]]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

FUNCTIONS_DIR="${FUNCTIONS_DIR:-${REPO_DIR}/functions}"

trim_unknown_adapters_for_fastq() {
  local fastq_file="$1"
  local output_dir="${2:-$(dirname "$fastq_file")}"
  local trim_script
  trim_script="${ADAPTER_TRIMMING_SCRIPT:-${FUNCTIONS_DIR}/trim_adapters/main.sh}"

  if [[ ! -f "$fastq_file" ]]; then
    echo "FASTQ file not found for adapter trimming: ${fastq_file}" >&2
    return 1
  fi

  if [[ ! -f "$trim_script" ]]; then
    echo "Adapter trimming script not found: ${trim_script}" >&2
    return 1
  fi

  local -a trim_command
  if [[ -x "$trim_script" ]]; then
    trim_command=("${trim_script}")
  else
    echo "Adapter trimming script is not executable; invoking with bash: ${trim_script}" >&2
    trim_command=(bash "${trim_script}")
  fi

  "${trim_command[@]}" "${fastq_file}" "${output_dir}"
}

# Generate a consensus FASTA from a FASTQ using the external consensus generation script.
generate_consensus_from_fastq() {
  local fastq_file="$1"
  local reference_path
  reference_path="${2:-${REFERENCE_FASTA:-${CONSENSUS_REFERENCE:-}}}"
  local output_dir="${3:-${2:-$(dirname "$fastq_file")}}"
  local consensus_script
  consensus_script="${CONSENSUS_GENERATION_SCRIPT:-${FUNCTIONS_DIR}/generate_consensus/main.sh}"

  if [[ ! -f "$fastq_file" ]]; then
    echo "FASTQ file not found for consensus generation: ${fastq_file}"
    return 1
  fi

  if [[ ! -f "$consensus_script" ]]; then
    echo "Consensus generation script not found: ${consensus_script}"
    return 1
  fi

  local -a consensus_command
  if [[ -x "$consensus_script" ]]; then
    consensus_command=("${consensus_script}")
  else
    echo "Consensus generation script is not executable; invoking with bash: ${consensus_script}" >&2
    consensus_command=(bash "${consensus_script}")
  fi

  local consensus_output
  if ! consensus_output="$("${consensus_command[@]}" "${fastq_file}" "${reference_path}" "${output_dir}")"; then
    echo "Consensus generation failed for ${fastq_file}"
    return 1
  fi

  echo "${consensus_output}"
}

run_paleomix_pipeline_for_fastq() {
  local fastq_file="$1"
  local output_dir="${2:-$(dirname "$fastq_file")}" 
  local sample_label="${3:-}"
  local paleomix_script
  paleomix_script="${PALEOMIX_PIPELINE_SCRIPT:-${FUNCTIONS_DIR}/paleomix_bam/main.sh}"

  if [[ ! -f "$fastq_file" ]]; then
    echo "FASTQ file not found for PALEOMIX: ${fastq_file}"
    return 1
  fi

  if [[ ! -f "$paleomix_script" ]]; then
    echo "PALEOMIX pipeline script not found: ${paleomix_script}"
    return 1
  fi

  local -a paleomix_command
  if [[ -x "$paleomix_script" ]]; then
    paleomix_command=("${paleomix_script}")
  else
    echo "PALEOMIX pipeline script is not executable; invoking with bash: ${paleomix_script}" >&2
    paleomix_command=(bash "${paleomix_script}")
  fi

  "${paleomix_command[@]}" "${fastq_file}" "${output_dir}" "${sample_label}"
}

run_eager_pipeline_for_fastq() {
  local fastq_file="$1"
  local output_dir="${2:-$(dirname "$fastq_file")}" 
  local sample_label="${3:-}"
  local eager_script
  eager_script="${EAGER_PIPELINE_SCRIPT:-${FUNCTIONS_DIR}/eager/main.sh}"

  if [[ ! -f "$fastq_file" ]]; then
    echo "FASTQ file not found for EAGER: ${fastq_file}" >&2
    return 1
  fi

  if [[ ! -f "$eager_script" ]]; then
    echo "EAGER pipeline script not found: ${eager_script}" >&2
    return 1
  fi

  local -a eager_command
  if [[ -x "$eager_script" ]]; then
    eager_command=("${eager_script}")
  else
    echo "EAGER pipeline script is not executable; invoking with bash: ${eager_script}" >&2
    eager_command=(bash "${eager_script}")
  fi

  "${eager_command[@]}" "${fastq_file}" "${output_dir}" "${sample_label}"
}

run_custom_function_for_fastq() {
  local fastq_file="$1"
  local output_dir="${2:-$(dirname "$fastq_file")}"
  local custom_script
  custom_script="${FUNCTIONS_DIR}/custom_function/main.sh"

  if [[ "${CUSTOM_FUNCTION:-no}" != "yes" ]]; then
    return 0
  fi

  if [[ ! -f "${custom_script}" ]]; then
    echo "Custom function is enabled but the script is missing: ${custom_script}"
    return 1
  fi

  local -a custom_command
  if [[ -x "${custom_script}" ]]; then
    custom_command=("${custom_script}")
  else
    echo "Custom function script is not executable; invoking with bash: ${custom_script}" >&2
    custom_command=(bash "${custom_script}")
  fi

  "${custom_command[@]}" "${fastq_file}" "${output_dir}"
}

# Delete a FASTQ file safely, logging the removal.
delete_fastq_file() {
  local fastq_path="$1"
  if [[ -f "$fastq_path" ]]; then
    rm -f "$fastq_path"
    echo "Deleted FASTQ file: ${fastq_path}"
  else
    echo "FASTQ file not found for deletion: ${fastq_path}"
  fi
}
