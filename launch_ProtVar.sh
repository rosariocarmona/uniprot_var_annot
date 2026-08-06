#!/usr/bin/env bash

# CLI ProtVar API Tools
# https://github.com/tgttunstall/protvar_api_tools
# Variants file (without header) should be in data/
# Assembly refers to the reference genome for the coordinates of the user-provided variants
# Example execution line:
# ./launch_ProtVar.sh variants_file.txt assembly job_label

# Variables
input_file=$1
assembly=$2   # GRCh37 or GRCh38
job_label=$3

# Validate that required arguments are provided
if [ -z "$input_file" ] || [ -z "$job_label" ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 <variants_file.txt> <job_label>"
    exit 1
fi

# Setup
#########################################################
python3 -m venv ~/my_envs/pv_api_env/
source ~/my_envs/pv_api_env/bin/activate
# Only for the first time it is run
#pip install -r requirements.txt

# Prepares batches
#########################################################
echo "========================================================="
echo "Preparing batches of 100000 variants..."
echo "========================================================="

# Temporary directory for the split file chunks
tmp_dir=$(mktemp -d -t "protvar_${job_label}_XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

# Split the original file into chunks of 100 lines each
# This will generate files with a 2-digit numeric suffix: batch_00, batch_01, etc.
split -l 100000 -d -a 3 "data/${input_file}" "${tmp_dir}/batch_"

# Loop to process each batch sequentially
for batch_path in "${tmp_dir}"/batch_*; do
    # Extract only the filename (e.g., batch_00)
    batch_name=$(basename "$batch_path")
    
    echo "========================================================="
    echo "Processing sub-batch: ${batch_name}"
    echo "========================================================="

    # Define the specific output directory for this batch
    batch_outdir="results/${job_label}/${batch_name}"
    mkdir -p "$batch_outdir"

    # 1. Uploads a variant file
    #########################################################
    # Use the split chunk file instead of the original file
    python submit.py --input "$batch_path" --assembly "${assembly}" --jobid-file "${batch_outdir}/jobid.txt"

    # 2. Creates a download job
    #########################################################
    python create_download.py --result-id "${batch_outdir}/jobid.txt" --assembly "${assembly}" --annotations full --jobid-file "${batch_outdir}/download_jobid.txt"

    # 3. Checks the download job status & Polling loop
    #########################################################
    echo "Waiting for the job ${batch_name} to be ready..."

    until python poll.py --job-id "${batch_outdir}/download_jobid.txt"; do 
        status_code=$?
        if [ $status_code -eq 2 ]; then
            echo "The job ${batch_name} has failed (failed/expired state). Aborting workflow."
            exit 1
        fi
        echo "Not ready yet. Waiting 10 seconds..."
        sleep 10
    done

    echo "Ready! Downloading results for ${batch_name}..."

    # 4. Downloads results
    #########################################################
    python retrieve.py --download-id "${batch_outdir}/download_jobid.txt" --outdir "${batch_outdir}/"

    # 5. Unzips results
    #########################################################
    unzip "${batch_outdir}"/*.zip -d "${batch_outdir}/"

done



# 6. Aggregates all batch results into a single CSV file
#########################################################
echo "========================================================="
echo "Aggregates all batch results into a single CSV file..."
echo "========================================================="

final_output="results/${job_label}/${job_label}_results.csv"
first_file=true

# Loop through all unzipped .csv files in the batch directories
for csv_file in results/"${job_label}"/batch_*/*.csv; do
    # Check if the file exists to avoid errors if no CSVs were found
    if [ -f "$csv_file" ]; then
        if [ "$first_file" = true ]; then
            # Copy the entire first file (including the header)
            cat "$csv_file" > "$final_output"
            first_file=false
        else
            # Append subsequent files, skipping the first line (header)
            tail -n +2 "$csv_file" >> "$final_output"
        fi
    fi
done

echo "Merged file created at: $final_output"

# Converts csv in tsv
final_output_tsv="results/${job_label}/${job_label}_results.tsv"
python3 -c "import csv, sys; w=csv.writer(sys.stdout, delimiter='\t'); w.writerows(csv.reader(sys.stdin))" < "$final_output" > "$final_output_tsv"

# Clean up the intermediate CSV file (temporary directory is cleaned up by EXIT trap)
rm -f "$final_output"

echo "========================================================="
echo "Process completed for all batches!"
echo "========================================================="

deactivate


