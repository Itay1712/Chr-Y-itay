#!/bin/bash

# Custom FASTQ processing function.
# This script is invoked by the workflow when `functions.custom_function` is enabled
# in `config/config.yaml`. It receives the FASTQ path and an optional output
# directory, allowing users to add bespoke processing without altering the
# workflow.

set -euo pipefail

fastq_path="$1"
output_dir="${2:-$(dirname "$fastq_path")}" 

echo "Running custom function for ${fastq_path}" >&2

errexit_was_set=0
if [[ $- == *e* ]]; then
  errexit_was_set=1
  set +e
fi

# === BEGIN CUSTOM CODE ===
# Replace the commands below with your own processing steps. Use "$fastq_path"
# as the FASTQ input and "$output_dir" for any outputs you want to place next
# to the FASTQ. Remember to keep the exit codes meaningful so the workflow can
# report success or failure.
#
# Example placeholder (does nothing by default):
# echo "Custom processing for ${fastq_path} writing results to ${output_dir}" >&2
#
# Add your commands here.
# === END CUSTOM CODE ===

custom_status=$?

if [[ ${errexit_was_set} -eq 1 ]]; then
  set -e
else
  set +e
fi

if [[ ${custom_status} -ne 0 ]]; then
  echo "Custom function failed for ${fastq_path} (exit code: ${custom_status})." >&2
  exit ${custom_status}
fi

echo "Custom function completed for ${fastq_path}" >&2
