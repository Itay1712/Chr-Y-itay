#!/bin/bash

# Entry point for downloading ENA FASTQ files using filter parameters.
# The workflow is split across configuration and utility files for clarity.

set -euo pipefail

print_usage() {
  cat <<'USAGE'
Usage: bash ENA_download.sh

Runs the ENA download workflow using the parameters and conditions defined in
config/config.yaml.

Notes:
- Running "bash -n ENA_download.sh ..." only performs a syntax check and will NOT
  execute the workflow. Omit "-n" to actually download data.
- The output directory is defined in config/config.yaml (paths.output_dir). A
  subfolder is created per condition listed in the "projects_to_download" list (or all
  conditions when the list is omitted).
- The functions.keep_fastq and functions.generate_consensus options control post-download
  FASTQ retention and consensus FASTA creation, respectively.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${REPO_DIR}/config"
LIB_DIR="${REPO_DIR}/lib"
source "${LIB_DIR}/fastq_management.sh"
source "${LIB_DIR}/ena_download_utils.sh"

load_config_from_yaml "${CONFIG_DIR}/config.yaml"

mkdir -p "${OUTPUT_DIR}" "${METADATA_DIR}"

echo "Starting ENA download workflow"
echo "Output directory: ${OUTPUT_DIR}"
echo "Metadata cache directory: ${METADATA_DIR}"
echo "Conditions to process: ${PROJECTS_TO_DOWNLOAD[*]:-<none>}"
echo "keep_fastq: ${KEEP_FASTQ}"
echo "generate_consensus: ${GENERATE_CONSENSUS}"
echo "trim_unknown_adapters: ${TRIM_UNKNOWN_ADAPTERS}"
echo "paleomix_bam: ${PALEOMIX_BAM}"
echo "run_eager: ${RUN_EAGER}"
echo "reference_fasta: ${REFERENCE_FASTA:-<not set>}"
echo "custom_function: ${CUSTOM_FUNCTION}"

process_all_conditions "${PROJECTS_TO_DOWNLOAD[@]}"
