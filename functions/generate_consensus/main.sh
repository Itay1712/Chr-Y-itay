#!/bin/bash

fastq_prefix() {
  local fastq_file="$1"
  local file_name
  file_name=$(basename "$fastq_file")
  file_name="${file_name%.fastq.gz}"
  file_name="${file_name%.fq.gz}"
  echo "$file_name"
}

has_working_bcftools() {
  if ! command -v bcftools >/dev/null 2>&1; then
    return 1
  fi

  # If bcftools is installed but fails to start because of missing shared
  # libraries (e.g., libgsl), the --version call will exit non-zero. We treat
  # that as unavailable and fall back to the samtools-only consensus path.
  if ! bcftools --version >/dev/null 2>&1; then
    return 1
  fi

  return 0
}

verify_consensus_requirements() {
  local reference_path="$1"

  if [[ -z "$reference_path" ]]; then
    echo "Reference FASTA not specified. Set REFERENCE_FASTA or pass it to the consensus script."
    return 1
  fi

  if [[ ! -f "$reference_path" ]]; then
    echo "Reference FASTA not found for consensus generation: ${reference_path}"
    return 1
  fi

  local missing=()
  for tool in minimap2 samtools; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Missing required tools for consensus generation: ${missing[*]}"
    return 1
  fi

  return 0
}

# Generate a consensus FASTA from a FASTQ using the configured reference genome.
generate_consensus_for_fastq() {
  local fastq_file="$1"
  local reference_path
  reference_path="${2:-${REFERENCE_FASTA:-${CONSENSUS_REFERENCE:-}}}"
  local output_dir="${3:-${2:-$(dirname "$fastq_file")}}"

  if [[ ! -f "$fastq_file" ]]; then
    echo "FASTQ file not found for consensus generation: ${fastq_file}"
    return 1
  fi

  verify_consensus_requirements "$reference_path" || return 1

  mkdir -p "$output_dir"

  local prefix
  prefix="$(fastq_prefix "$fastq_file")"
  local sorted_bam="${output_dir}/${prefix}.sorted.bam"
  local vcf_file="${output_dir}/${prefix}.vcf.gz"
  local consensus_fasta="${output_dir}/${prefix}_consensus.fasta"

  echo "Generating consensus FASTA for '${fastq_file}' using reference '${reference_path}'." >&2

  minimap2 -a "${reference_path}" "${fastq_file}" \
    | samtools view -b \
    | samtools sort -o "${sorted_bam}"

  samtools index "${sorted_bam}"

  if has_working_bcftools; then
    bcftools mpileup -f "${reference_path}" "${sorted_bam}" \
      | bcftools call -m -Oz -o "${vcf_file}"
    bcftools index "${vcf_file}"
    bcftools consensus -f "${reference_path}" "${vcf_file}" > "${consensus_fasta}"

    rm -f "${vcf_file}" "${vcf_file}.csi"
  else
    echo "bcftools is unavailable or cannot start (likely due to missing shared libraries). Falling back to samtools consensus." >&2
    # samtools consensus uses -f to set the output format (not the reference
    # FASTA). The reference sequence is already embedded in the BAM header from
    # minimap2, so request FASTA output explicitly.
    samtools consensus -f fasta "${sorted_bam}" > "${consensus_fasta}"
  fi

  rm -f "${sorted_bam}" "${sorted_bam}.bai"

  echo "Consensus written to ${consensus_fasta}" >&2
  echo "${consensus_fasta}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  generate_consensus_for_fastq "$@"
fi
