# ProtVar API Tools

Small CLI tools for working with the ProtVar API.

## Setup

We manage the environment using [`pixi`](https://pixi.sh). To set up the environment and install dependencies, simply run:

```bash
pixi install
```

You can then run the pipeline directly within the pixi environment. For example:
```bash
pixi run bash run_pipeline.sh data/test.txt GRCh37 test_run
```

## Overview

- `submit.py` uploads a variant file and writes the ProtVar upload `resultId`.
- `create_download.py` creates a download job from that `resultId`.
- `poll.py` checks the download job status.
- `retrieve.py` downloads one or more finished result files and keeps the ProtVar filenames.

## Input data

Sample input is in `data/test.txt`.

## Output locations

- `submit.py` writes the upload `resultId` to `--jobid-file`.
- `create_download.py` writes the download job ID to `--jobid-file`.
- `retrieve.py` writes downloaded files to `--outdir` while preserving the ProtVar filenames.
- Parent directories for output paths are created automatically.

## HPC / Slurm Usage

If you are running on an HPC cluster with Slurm, you can submit the pipeline using an `sbatch` script. Below is a minimal example using a small dataset included in the repository (`data/test.txt`). You can save this as `submit_pipeline.slurm` (which is git-ignored) and submit it with `sbatch submit_pipeline.slurm`:

```bash
#!/bin/bash
#SBATCH --job-name=uniprot_annot
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=30
#SBATCH --mem=90G
#SBATCH --time=24:00:00
#SBATCH --output=uniprot_annot_%j.log
#SBATCH --error=uniprot_annot_%j.err

# Exit if any command fails
set -e

# Define input parameters
INPUT_FILE="data/test.txt"
ASSEMBLY="GRCh37"
JOB_LABEL="test_job"

echo "========================================================="
echo "Starting UniProt Annotation Pipeline"
echo "========================================================="

# Ensure the environment is ready and run the pipeline
pixi run bash run_pipeline.sh "$INPUT_FILE" "$ASSEMBLY" "$JOB_LABEL"

echo "Pipeline finished successfully!"
```

## ID flow

1. `submit.py` returns the upload `resultId`.
2. Pass that same `resultId` to `create_download.py`.
3. `create_download.py` returns a separate download job ID.
4. Pass that download job ID to `poll.py`.
5. When ready, use `retrieve.py` with the remote download ID/filename returned by ProtVar.

## `submit.py`

Upload a plain-text variant file, one variant per line.

Options:
- `--input` required, path to the variant file.
- `--assembly` optional, one of `AUTO`, `GRCh37`, `GRCh38`. Default: `GRCh37`.
- `--jobid-file` optional, output file for the returned upload `resultId`.
- `--timeout` optional, request timeout in seconds.

Example:

```bash
python submit.py --input data/test.txt --assembly GRCh37 --jobid-file results/jobid.txt
```

This writes the upload `resultId` to `results/jobid.txt`.

## `create_download.py`

Create a ProtVar download job from the upload `resultId`.

Options:
- `--result-id` required, the upload `resultId` from `submit.py`, or a file containing it.
- `--assembly` optional, one of `AUTO`, `GRCh37`, `GRCh38`. Default: `GRCh37`.
- `--annotations` required, one of `structure`, `function`, `population`, or `full`.
- `--jobid-file` optional, output file for the returned download job ID.
- `--timeout` optional, request timeout in seconds.

Example*:

```bash
python create_download.py --result-id results/jobid.txt --assembly AUTO --annotations full --jobid-file results/download_jobid.txt
```

This writes the download job ID to `results/download_jobid.txt`.
That file is local state only, not the remote download filename.

**Note: In local assembly testing, explicit `--assembly GRCh37` during the download step returned unexpectedly few rows for both the small and large GRCh37 inputs. Using `--assembly AUTO` during the download step produced the expected row counts. For the larger input, `AUTO` submit plus `AUTO` download was not text-identical to `GRCh37` submit plus `AUTO` download because one `Alternative_isoform_mappings` field had the same mappings in a different order. See `assembly_auto_vs_grch37_notes.txt`.**

## `poll.py`

Check the status of a ProtVar download job.

Options:
- `--job-id` required, either the download job ID itself or a file containing it.
- `--timeout` optional, request timeout in seconds.

Example:

```bash
python poll.py --job-id results/download_jobid.txt
```

`poll.py` accepts either the job ID itself or a file containing it.

Status meanings:
- `queued`
- `processing`
- `ready`
- `failed`
- `expired`

## `retrieve.py`

Download one or more ready result files.

Downloads are streamed to disk in chunks rather than loaded fully into memory.
This is safer for large ProtVar zip files, such as full-annotation downloads or
downloads created from large variant lists.

Options:
- `--download-id` required, one or more download IDs, or one file containing one or more download IDs, one per line.
- `--outdir` optional, local output directory. The ProtVar filename is preserved.
- `--timeout` optional, request timeout in seconds.

Single-ID example:

```bash
python retrieve.py --download-id results/download_jobid.txt --outdir results/
```

Multiple IDs on the command line:

```bash
python retrieve.py --download-id id1 id2 id3 --outdir results/
```

Multiple IDs from a file:

```text
id1
id2
id3
```

```bash
python retrieve.py --download-id results/download_jobids.txt --outdir results/
```

Use either literal IDs on the command line or one ID file. Do not mix literal IDs and an ID file in the same command.

`results/download_jobid.txt` contains the same download job ID you check with `poll.py`.
Downloaded files are saved as `results/<ProtVar filename>`.

## Example workflow

```bash
python submit.py --input data/test.txt --assembly GRCh37 --jobid-file results/jobid.txt
python create_download.py --result-id results/jobid.txt --assembly AUTO --annotations full --jobid-file results/download_jobid.txt
python poll.py --job-id results/download_jobid.txt
python retrieve.py --download-id results/download_jobid.txt --outdir results/
```

* `create_download.py ... --assembly AUTO` See Note above.

## Notes

- `results/` is a suggested output folder in the examples.
- The scripts can write wherever you point `--jobid-file` and `--outdir`.
- `submit.py` and `create_download.py` write IDs to text files so later scripts can reuse them.
- Assembly comparison details are recorded in `assembly_auto_vs_grch37_notes.txt`.
  - For the 6-variant test input, `AUTO` submit plus `AUTO` download matched `GRCh37` submit plus `AUTO` download.
  - For the larger GRCh37 input, `AUTO` submit plus `AUTO` download did not produce text-identical output compared with `GRCh37` submit plus `AUTO` download. The observed difference was ordering within `Alternative_isoform_mappings`.
  - This behavior has been flagged to the ProtVar team for clarification.
  - Until clarified, use `--assembly AUTO` for the download step for these GRCh37 inputs.
