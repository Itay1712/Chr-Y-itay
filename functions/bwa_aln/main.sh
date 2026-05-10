#!/bin/bash

set -euo pipefail

fastq_path="$1"
output_dir="${2:-$(dirname "$fastq_path")}"
sample_label="${3:-$(basename "$fastq_path" .fastq.gz)}"
reference="${REF:-${REFERENCE_FASTA:-}}"
threads="${BWA_THREADS:-16}"

if [[ -z "${reference}" ]]; then
  echo "BWA aln function requires REF or REFERENCE_FASTA to be set." >&2
  exit 1
fi

if [[ ! -f "${fastq_path}" ]]; then
  echo "FASTQ file not found: ${fastq_path}" >&2
  exit 1
fi

if [[ ! -f "${reference}" ]]; then
  echo "Reference FASTA not found: ${reference}" >&2
  echo "Set parameters.reference_fasta in config/config.yaml (or export REF) to an existing file." >&2
  exit 1
fi

if command -v module >/dev/null 2>&1; then
  module load bwa/bwa-0.7.17
  module load samtools/samtools-1.19
fi

mkdir -p "${output_dir}"

sample_prefix="${output_dir}/${sample_label}"

# The provided workflow uses bwa samse (single-end), so for paired-end inputs
# we process only read 1 files and skip read 2 mates.
if [[ "${fastq_path}" =~ _2\.fastq(\.gz)?$ ]]; then
  echo "Skipping BWA aln for read 2 mate (samse is single-end): ${fastq_path}" >&2
  exit 0
fi

if [[ ! -f "${reference}.bwt" ]]; then
  bwa index "${reference}"
fi

bwa aln -t "${threads}" "${reference}" "${fastq_path}" > "${sample_prefix}.sai"

bwa samse "${reference}" "${sample_prefix}.sai" "${fastq_path}" \
  | samtools view -@ "${threads}" -bS - \
  | samtools sort -@ "${threads}" -o "${sample_prefix}.sorted.bam" -

samtools index "${sample_prefix}.sorted.bam"

echo "${sample_prefix}.sorted.bam"
