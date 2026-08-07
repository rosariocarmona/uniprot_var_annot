#!/usr/bin/env bash

# Annotate PTMs from EBI ProtVar API
# Usage: ./annotate_ptm.sh <input_parsed.tsv> [<output_ptm.tsv>]

set -e

if [ $# -lt 1 ]; then
    echo "Usage: $0 <input_parsed.tsv> [<output_ptm.tsv>]"
    exit 1
fi

input_file="$1"
output_file=${2:-"ptm_${input_file}"}

if [ ! -f "$input_file" ]; then
    echo "Error: Input file '$input_file' does not exist."
    exit 1
fi

# Create temporary file
tmp_out=$(mktemp)
trap 'rm -f "$tmp_out"' EXIT

# Read header
header=$(head -n 1 "$input_file")

# Insert 'ptm' as the 18th column (before diseases)
new_header=$(echo "$header" | awk -F'\t' '{
    for(i=1; i<=17; i++) printf "%s\t", $i;
    printf "ptm\t";
    for(i=18; i<=NF; i++) {
        printf "%s", $i;
        if(i<NF) printf "\t";
    }
    print "";
}')

echo "$new_header" > "$tmp_out"

# Process each line
tail -n +2 "$input_file" | while read -r line; do
    if [ -z "$line" ]; then
        continue
    fi

    uniprot_id=$(echo "$line" | cut -f 4)
    aa_change_col=$(echo "$line" | cut -f 7)
    
    # Extract position and new AA from format like p.W1242C
    aa_acid_position=$(echo "$aa_change_col" | grep -o '[0-9]\+')
    new_aa_acid=$(echo "$aa_change_col" | grep -o '[a-zA-Z*]$')

    ptm_info="Not ptm"

    # Only query if we have valid uniprot_id, position and new amino acid
    if [ -n "$uniprot_id" ] && [ "$uniprot_id" != "-" ] && [ -n "$aa_acid_position" ] && [ -n "$new_aa_acid" ]; then
        ptm_url="https://www.ebi.ac.uk/ProtVar/api/function/${uniprot_id}/${aa_acid_position}?variantAA=${new_aa_acid}"
        
        # -s silent, -f fail silently on HTTP errors
        if response=$(curl -s -f -X 'GET' "$ptm_url" -H 'accept: application/json'); then
            ptm_extracted=$(echo "$response" | jq -r '
              [
                .comments[]? 
                | select(.type == "PTM") 
                | .text[]? 
                | .value + " (" + ([.evidences[]?.source | .name + ", " + .id] | join("; ")) + ")"
              ] 
              | if length > 0 then join("; ") else "Not ptm" end
            ')
            if [ -n "$ptm_extracted" ]; then
                ptm_info="$ptm_extracted"
            fi
        else
            ptm_info="Not url"
        fi
    fi

    # Construct new line with ptm inserted at column 18
    new_line=$(echo "$line" | awk -F'\t' -v ptm="$ptm_info" '{
        for(i=1; i<=17; i++) printf "%s\t", $i;
        printf "%s\t", ptm;
        for(i=18; i<=NF; i++) {
            printf "%s", $i;
            if(i<NF) printf "\t";
        }
        print "";
    }')

    echo "$new_line" >> "$tmp_out"
done

mv "$tmp_out" "$output_file"
echo "PTM annotation completed: ${output_file}"
