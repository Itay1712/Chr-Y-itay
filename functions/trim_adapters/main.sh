#!/bin/bash

# Adapter trimming helper that auto-detects unknown adapters using fastp.
# Accepts a FASTQ path and optional output directory. When a mate FASTQ exists
# with the same prefix ("_1"/"_2"), it will run paired-end trimming; otherwise
# it trims as single-end. The script prints the trimmed FASTQ path(s) so callers
# can use them for downstream processing.

set -euo pipefail

fastq_path="$1"
output_dir="${2:-$(dirname "$fastq_path")}" 

if [[ ! -f "$fastq_path" ]]; then
  echo "FASTQ file not found for trimming: ${fastq_path}" >&2
  exit 1
fi

if ! command -v fastp >/dev/null 2>&1; then
  echo "fastp is required for adapter trimming but is not available in PATH." >&2
  exit 1
fi

mkdir -p "$output_dir"

fastq_filename="$(basename "$fastq_path")"
fastq_prefix="${fastq_filename%.fastq.gz}"
fastq_prefix="${fastq_prefix%.fq.gz}"
fastq_prefix="${fastq_prefix%.fastq}"
fastq_prefix="${fastq_prefix%.fq}"

threads="${FASTP_THREADS:-4}"

# Default to skipping trimming when no adapters are detected to avoid rewriting large FASTQs.
skip_if_no_adapter="${FASTP_SKIP_WHEN_NO_ADAPTER:-1}"
detect_sample_size="${FASTP_DETECT_SAMPLE:-200000}"

detect_adapters() {
  local json_out
  json_out="$(mktemp)"

  local cmd=(
    fastp --detect_adapter_for_pe --thread "$threads"
    --sample_size "$detect_sample_size"
    -j "$json_out" -h /dev/null
    "$@"
  )

  "${cmd[@]}" >/dev/null 2>&1

  python - "$json_out" <<'PY'
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

ac = data.get("adapter_cutting", {}) or {}
print(ac.get("adapter_sequence", ""))
print(ac.get("adapter_sequence_r2", ""))
PY
}

mate_fastq=""
if [[ "$fastq_prefix" =~ (.*)_([12])$ ]]; then
  mate_fastq_candidate="${BASH_REMATCH[1]}_$((3 - BASH_REMATCH[2])).fastq.gz"
  mate_fastq_path="$(dirname "$fastq_path")/${mate_fastq_candidate}"
  if [[ -f "$mate_fastq_path" ]]; then
    mate_fastq="$mate_fastq_path"
  else
    # Try alternative extensions when gzip extension is absent
    mate_fastq_candidate_no_gz="${mate_fastq_candidate%.gz}"
    mate_fastq_path="$(dirname "$fastq_path")/${mate_fastq_candidate_no_gz}"
    if [[ -f "$mate_fastq_path" ]]; then
      mate_fastq="$mate_fastq_path"
    fi
  fi
fi

trimmed_files=()

if [[ -n "$mate_fastq" ]]; then
  pair_prefix="${fastq_prefix%_1}"
  if [[ "$pair_prefix" == "$fastq_prefix" ]]; then
    pair_prefix="${fastq_prefix%_2}"
  fi
  out_r1="${output_dir}/${pair_prefix}_trimmed_1.fastq.gz"
  out_r2="${output_dir}/${pair_prefix}_trimmed_2.fastq.gz"
  if [[ "$skip_if_no_adapter" == "1" ]]; then
    echo "Checking for adapters before trimming (sample size: ${detect_sample_size})" >&2
    mapfile -t adapters < <(detect_adapters -i "$fastq_path" -I "$mate_fastq" -o /dev/null -O /dev/null)
    if [[ -z "${adapters[0]}" && -z "${adapters[1]}" ]]; then
      echo "No adapters detected in sample; skipping adapter trimming entirely (behaves as if trim_unknown_adapters is disabled)." >&2
      exit 0
    fi
  fi

  echo "Running paired-end adapter trimming for ${fastq_path} and ${mate_fastq}" >&2
  fastp --detect_adapter_for_pe --thread "$threads" \
    -i "$fastq_path" -I "$mate_fastq" \
    -o "$out_r1" -O "$out_r2"
  trimmed_files+=("$out_r1" "$out_r2")
else
  out_se="${output_dir}/${fastq_prefix}_trimmed.fastq.gz"
  if [[ "$skip_if_no_adapter" == "1" ]]; then
    echo "Checking for adapters before trimming (sample size: ${detect_sample_size})" >&2
    mapfile -t adapters < <(detect_adapters -i "$fastq_path" -o /dev/null)
    if [[ -z "${adapters[0]}" ]]; then
      echo "No adapters detected in sample; skipping adapter trimming entirely (behaves as if trim_unknown_adapters is disabled)." >&2
      exit 0
    fi
  fi

  echo "Running single-end adapter trimming for ${fastq_path}" >&2
  fastp --thread "$threads" -i "$fastq_path" -o "$out_se"
  trimmed_files+=("$out_se")
fi

printf '%s\n' "${trimmed_files[@]}"
