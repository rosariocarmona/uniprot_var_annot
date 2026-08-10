#!/usr/bin/env bash

# Annotate PTMs from EBI ProtVar API using local parallelization
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

# Export function for xargs parallel execution
export_fetch_ptm() {
    local uniprot_id=$1
    local aa_pos=$2
    local new_aa=$3
    if [ -z "$uniprot_id" ] || [ "$uniprot_id" == "-" ] || [ -z "$aa_pos" ] || [ -z "$new_aa" ]; then
        printf "%s\t%s\t%s\t%s\n" "$uniprot_id" "$aa_pos" "$new_aa" "Not ptm"
        return
    fi
    
    local ptm_url="https://www.ebi.ac.uk/ProtVar/api/function/${uniprot_id}/${aa_pos}?variantAA=${new_aa}"
    local ptm_info="Not url"
    
    local response
    if response=$(curl -s -f -X 'GET' "$ptm_url" -H 'accept: application/json'); then
        local ptm_extracted
        ptm_extracted=$(echo "$response" | jq -r '
          [
            .comments[]? 
            | select(.type == "PTM") 
            | .text[]? 
            | .value + " (" + ([.evidences[]?.source | .name + ", " + .id] | join("; ")) + ")"
          ] 
          | if length > 0 then join("; ") else "Not ptm" end
        ' | tr '\n' ' ' | tr '\r' ' ' | sed 's/  */ /g' | sed 's/ $//')
        if [ -n "$ptm_extracted" ]; then
            ptm_info="$ptm_extracted"
        else
            ptm_info="Not ptm"
        fi
    fi
    
    printf "%s\t%s\t%s\t%s\n" "$uniprot_id" "$aa_pos" "$new_aa" "$ptm_info"
}
export -f export_fetch_ptm

# 1. Temporary files setup
tmp_dir=$(mktemp -d -t "ptm_parallel_XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

queries_file="${tmp_dir}/unique_queries.txt"
results_file="${tmp_dir}/ptm_results.txt"
mkdir -p "${tmp_dir}/results"

echo "Extracting unique queries..."
# 2. Extract unique (uniprot_id, position, new_aa)
awk -F'\t' 'NR>1 {
    uniprot_id = $4
    aa_change = $7
    
    if (match(aa_change, /[0-9]+/)) {
        aa_pos = substr(aa_change, RSTART, RLENGTH)
    } else { aa_pos = "" }
    
    if (match(aa_change, /[a-zA-Z*]$/)) {
        new_aa = substr(aa_change, RSTART, RLENGTH)
    } else { new_aa = "" }
    
    if (uniprot_id != "" && uniprot_id != "-" && aa_pos != "" && new_aa != "") {
        print uniprot_id " " aa_pos " " new_aa
    }
}' "$input_file" | sort -u > "$queries_file"

total_queries=$(wc -l < "$queries_file")
echo "Found $total_queries unique queries. Fetching from API in parallel..."

# 3. Parallel Fetching using xargs -P (20 concurrent connections)
export tmp_dir
xargs -P 20 -n 3 -a "$queries_file" bash -c 'export_fetch_ptm "$1" "$2" "$3" > "${tmp_dir}/results/${1}_${2}_${3}.txt"' _
cat "${tmp_dir}/results"/*.txt > "$results_file"

echo "API fetching complete. Merging results into TSV..."

# 4. In-Memory Merge using awk
awk -F'\t' -v OFS='\t' '
    # Load ptm_results into map
    FNR==NR {
        key = $1 ":" $2 ":" $3
        
        # PTM output can be multi-word, so we need to collect everything from column 4 onwards
        val = $4
        for (i=5; i<=NF; i++) {
            val = val "\t" $i
        }
        
        ptm_map[key] = val
        next
    }
    
    # Process original TSV
    FNR!=NR {
        if (FNR == 1) {
            # Header
            for(i=1; i<=17; i++) printf "%s\t", $i
            printf "ptm\t"
            for(i=18; i<=NF; i++) {
                printf "%s", $i
                if(i<NF) printf "\t"
            }
            print ""
            next
        }
        
        # Data rows
        uniprot_id = $4
        aa_change = $7
        
        aa_pos = ""
        new_aa = ""
        if (match(aa_change, /[0-9]+/)) {
            aa_pos = substr(aa_change, RSTART, RLENGTH)
        }
        if (match(aa_change, /[a-zA-Z*]$/)) {
            new_aa = substr(aa_change, RSTART, RLENGTH)
        }
        
        key = uniprot_id ":" aa_pos ":" new_aa
        ptm = "Not ptm"
        if (key in ptm_map) {
            ptm = ptm_map[key]
        }
        
        # Inject ptm column
        for(i=1; i<=17; i++) printf "%s\t", $i
        printf "%s\t", ptm
        for(i=18; i<=NF; i++) {
            printf "%s", $i
            if(i<NF) printf "\t"
        }
        print ""
    }
' "$results_file" "$input_file" > "${tmp_dir}/final_output.tsv"

mv "${tmp_dir}/final_output.tsv" "$output_file"
echo "PTM annotation completed: ${output_file}"
