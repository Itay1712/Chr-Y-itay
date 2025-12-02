# ENA download workflow

This repository downloads FASTQ files from the ENA based on project filters. The workflow is split across a small entrypoint, shared configuration, and reusable utilities.

## Quick start
1. Adjust the filters, defaults, and paths you want to run in `config/config.yaml` (edit the `projects_to_download` list, condition blocks, and
   the `defaults`/`paths`/`parameters`/`functions` sections).
2. Run the workflow:
   ```bash
   bash ENA_download.sh
   ```

The script prints the output and metadata cache directories, then processes each condition and creates a subfolder per condition underneath `OUTPUT_DIR`.

### Important
Running `bash -n ENA_download.sh ...` only performs a syntax check and **will not** start any downloads. Use the command above without `-n` to actually run the workflow.

## Files
- `ENA_download.sh` — entrypoint that loads configuration and runs all configured conditions.
- `config/config.yaml` — defaults, filesystem paths (including `OUTPUT_DIR`), parameters (e.g., `reference_fasta`), project filters, function settings, and condition definitions.
- `functions/generate_consensus/main.sh` — consensus generator invoked after downloads when enabled; takes a FASTQ input and writes a consensus FASTA.
- `functions/paleomix_bam/main.sh` — runs the PALEOMIX BAM pipeline for a FASTQ (pairing R1/R2 mates when available) using the renamed file as the sample/library name and emits a per-file YAML.
- `functions/eager/main.sh` — renders nf-core/eager samplesheet/config templates from downloaded FASTQs and launches the pipeline when enabled.
- `functions/trim_adapters/main.sh` — trims unknown adapters from FASTQ files using `fastp` when `functions.trim_unknown_adapters` is enabled.
- `functions/custom_function/main.sh` — placeholder script to add bespoke FASTQ processing, enabled via `functions.custom_function` in the config.
- `lib/ena_download_utils.sh` — helper functions for metadata retrieval, filtering, downloading, and renaming.
- `lib/fastq_management.sh` — FASTQ helpers including consensus and optional custom function execution.

## Custom FASTQ functions

The workflow has a `custom_function` toggle under `functions` in `config/config.yaml`. When set to `yes`, the workflow will execute `functions/custom_function/main.sh` for every renamed FASTQ. The script receives the FASTQ path as the first argument and the output directory as the second so you can drop in any bespoke processing logic between the marked sections without altering the rest of the workflow.

## PALEOMIX BAM generation

Set `functions.paleomix_bam: yes` in `config/config.yaml` to run the PALEOMIX BAM pipeline for each renamed FASTQ. When R1/R2 mates exist, the workflow renders a paired-end lane in the per-file PALEOMIX YAML using the configured rename pattern for sample/library naming and runs `paleomix bam_pipeline` via `functions/paleomix_bam/main.sh`.

## nf-core/eager support

Enable `functions.run_eager: yes` in `config/config.yaml` to prepare an nf-core/eager samplesheet and config per FASTQ and run the pipeline via `functions/eager/main.sh`. The script fills the provided templates with the renamed FASTQ paths, uses the configured `parameters.reference_fasta`, and writes outputs under `<condition>/eager/<sample>/` alongside the rendered templates.
Set `EAGER_PIPELINE_REV` to pin a different nf-core/eager release (defaults to `2.5.3`), or `EAGER_PIPELINE_REF` to point at a fork.
