#!/usr/bin/env bash

# Master script to run the full UniProt Variant Annotation Pipeline
# Usage: ./run_pipeline.sh <variants_file.txt> <assembly> <job_label>

set -e

# Variables
input_file=$1
assembly=$2   # GRCh37 or GRCh38
job_label=$3

# Validate arguments
if [ -z "$input_file" ] || [ -z "$assembly" ] || [ -z "$job_label" ]; then
    echo "Error: Missing arguments."
    echo "Usage: $0 <variants_file.txt> <assembly> <job_label>"
    if [ -z "$assembly" ]; then
        echo "Note: The <assembly> argument can take the values: GRCh37 or GRCh38."
    fi
    exit 1
fi

if [ "$assembly" != "GRCh37" ] && [ "$assembly" != "GRCh38" ]; then
    echo "Error: Invalid assembly value '$assembly'."
    echo "Allowed values for <assembly>: GRCh37 or GRCh38."
    echo "Usage: $0 <variants_file.txt> <assembly> <job_label>"
    exit 1
fi

# Define intermediate and final output files
RESULTS_DIR="results/${job_label}"
RAW_RESULTS="${RESULTS_DIR}/ProtVarAPIoutput_${job_label}.tsv"
PARSED_RESULTS="${RESULTS_DIR}/ProtVarAnnot_${job_label}.tsv"
PTM_RESULTS="${RESULTS_DIR}/${job_label}_ptm.tsv"
FINAL_RESULTS="${RESULTS_DIR}/UniProtAnnot_${job_label}.tsv"

echo "========================================================="
echo "Step 1: Launching ProtVar API querying..."
echo "========================================================="
./launch_ProtVar.sh "$input_file" "$assembly" "$job_label"

if [ ! -f "$RAW_RESULTS" ]; then
    echo "Error: Step 1 failed to generate $RAW_RESULTS."
    exit 1
fi

echo "========================================================="
echo "Step 2: Parsing ProtVar results..."
echo "========================================================="
./parse_AnnotProtVar.sh "$RAW_RESULTS" "$PARSED_RESULTS"

echo "========================================================="
echo "Step 3: Annotating Post-Translational Modifications (PTMs)..."
echo "========================================================="
./annotate_ptm.sh "$PARSED_RESULTS" "$PTM_RESULTS"

echo "========================================================="
echo "Step 4: Annotating Humsavar curated classifications..."
echo "========================================================="
./annotate_humsavar.sh "$PTM_RESULTS" "$FINAL_RESULTS"

echo "========================================================="
echo "Pipeline execution completed successfully!"
echo "Final annotated file: $FINAL_RESULTS"
echo "========================================================="

# Clean up intermediate steps (optional)
rm -f "$PARSED_RESULTS" "$PTM_RESULTS"
