#!/usr/bin/env bash

# writes results to output/inspection
# does not modify raw file

set -euo pipefail # stops errors, unset vars, and failed pipes

SCRIPT_DIR="$(dirname "$0")"      #  ./sscripts
PROJECT_DIR="$SCRIPT_DIR/.."      #  project folder
RAW="$PROJECT_DIR/data/crimes.csv"
OUT="$PROJECT_DIR/output"

if [[ ! -f "$RAW" ]]; then
    echo "Error - missing $RAW" >&2
    exit 1
fi
mkdir -p "$OUT"

{
    echo "--- File Type ---"
    file "$RAW"

    echo; echo "--- Line Count ---"
    wc -l "$RAW"

    echo; echo "--- Columns ---"
    head -1 "$RAW" | tr ',' '\n' | cat -n

    echo; echo "--- Rows containing quotes ---"
    grep -c '"' "$RAW"

    echo; echo "--- Field Counts (rows w/o quotes) ---"
    grep -v '"' "$RAW" | awk -F',' '{print NF}' | sort | uniq -c

    echo; echo "--- Exact duplicate lines ---"
    sort "$RAW" | uniq -d | wc -l
} > "$OUT/inspection.txt"

echo "Inspection done. See $OUT/inspection.txt" >&2