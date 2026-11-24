#!/usr/bin/env bash
# inspect.sh - Stage 1: inspect the raw dataset and record evidence

# Writes one report: output/inspection.txt
# Does not modify the raw file. Safe to run more than once.

set -euo pipefail # stops errors, unset vars, and failed pipes

SCRIPT_DIR="$(dirname "$0")"                     #  ./scripts
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"      #  full path to project folder
RAW="$PROJECT_DIR/data/raw/crimes.csv"
OUT="$PROJECT_DIR/output"
REPORT="$OUT/inspection.txt"

# check that dataset exists
if [[ ! -f "$RAW" ]]; then
    echo "Error - missing $RAW" >&2
    exit 1
fi
mkdir -p "$OUT"

EXPECTED_FIELDS=28

# temporary tab-separated copy for checking columns
TSV="$(mktemp)"
trap 'rm -f "$TSV" "$TSV.tmp"' EXIT     # delete temp when script ends

# function that prints blank line + section name
section() { echo; echo "~~~ $1 ~~~~"; }

# function that shows every code + name pair with its count
pair_table() {
    tail -n +2 "$TSV" | cut -f"$1","$2" | sort | uniq -c |  # group identical pairs and count them
        awk -F'\t' '{ print $1 "\t[" $2 "]" }'              # brackets to show any hidden spaces
}

# function that show only codes that appear with more than one name
pair_diff() {
    pairs=$(pair_table "$1" "$2")                               # store every code/name combo with its count
    codes=$(tail -n +2 "$TSV" | cut -f"$1","$2" | sort -u |     # save codes that have more than one name
        cut -f1 | uniq -d)
    echo "codes with more than one name: $(echo "$codes" | grep -c . || true)"  # count non empty lines in codes
    for code in $codes; do
        echo "$pairs" | grep " $code"$'\t' || true              # space before + tab after --> exact code match
    done | awk 'NR <= 30'
}

{
    echo "Inspection of: $RAW"

    section "FILE FORMAT & STRUCTURE"
    echo "--- file type ---"
    file "$RAW"

    echo "--- ends with newline? ---"
    if [[ $(tail -c 1 "$RAW" | wc -l) -eq 1 ]]; then    # last char is newline if wc outputs 1
        echo "yes"
    else
        echo "no"
    fi

    echo "--- lines with carriage returns (\\r) ---"
    grep -c $'\r' "$RAW" || true    # grep exits 1 if counted 0; || true continues the script

    echo "--- lines ending with carriage return ---"
    awk '/\r$/ { n++ } END { print n + 0 }' "$RAW"

    echo "--- lines with tab characters ---"
    grep -c $'\t' "$RAW" || true

    echo "--- lines with | characters ---"
    grep -c '|' "$RAW" || true

    echo "--- lines containing quotes ---"
    grep -c '"' "$RAW" || true

    echo "--- lines containing \"\" (empty quotes) ---"
    grep -c '""' "$RAW" || true

    # with " as separator, complete quotes would give odd num of fields
    echo "--- lines with an odd number of quotes ---"
    awk -F'"' 'NF > 0 && NF % 2 == 0 { bad++ } END { print bad + 0 }' "$RAW"    

    section "NUMBER OF RECORDS & FIELDS"

    echo "--- line counts: wc -l vs awk ---"
    wc_lines=$(wc -l < "$RAW")
    awk_lines=$(awk 'END { print NR }' "$RAW")
    echo "wc -l: $wc_lines      awk: $awk_lines"

    echo "--- data rows (excluding header) ---"
    echo $((awk_lines - 1))

    echo "--- fields per line, splitting on every comma (count, fields) ---"
    awk -F',' '{ print NF }' "$RAW" | sort -n | uniq -c

    # prepare temp file with quote/comma fixing
    tr -d '\r' < "$RAW" > "$TSV"            # copy raw into temp without \r
    passes=0
    while grep -q ',"[^",]*,' "$TSV"; do    # check if commas exist within quotes
        passes=$((passes + 1))
        if [[ $passes -gt 20 ]]; then       # check if stuck in loop
            echo "Error - quote fixing didn't finish" >&2
            exit 1
        fi
        sed -E 's/(,"[^",]*),/\1|/g' "$TSV" > "$TSV.tmp"    # replace ',' with '|' within quoted field
        mv "$TSV.tmp" "$TSV"
    done

    tr ',' '\t' < "$TSV" | tr -d '"' | tr '|' ',' > "$TSV.tmp"  # make file tab separated, replace '|' with ','
    mv "$TSV.tmp" "$TSV"

    section "VERIFY QUOTE SPLITTING"

    echo "--- passes needed to convert file to tsv ---"
    echo "$passes"

    # check field counts
    echo "--- fields per line after quote splitting (count, fields) ---"
    awk -F'\t' '{ print NF }' "$TSV" | sort -n | uniq -c

    # count number of rows w/o 28 fields
    bad_rows=$(awk -F'\t' -v n="$EXPECTED_FIELDS" 'NF != n { bad++ } END { print bad + 0 }' "$TSV")
    if [[ $bad_rows -ne 0 ]]; then
        echo "Error - $bad_rows rows do not have $EXPECTED_FIELDS fields after conversion" >&2
        exit 1
    fi
    echo "All rows have $EXPECTED_FIELDS fields."

    section "FIELD NAMES, TYPES, & MISSING VALUES"
    echo "(MISSING = empty or only spaces; NUMERIC = number value; TEXT = anything else)"

    awk -F'\t' -v n="$EXPECTED_FIELDS" '
        NR==1 { for (i=1; i <= n; i++) name[i] = $i; next }  # save column names
        NR==2 { for (i=1; i <= n; i++) example[i] = $i }    # save first row as example
        {                                                   # for every row, sort value
            for (i=1; i<=n; i++) {
                if ($i ~ /^ *$/)                        missing[i]++
                else if ($i ~ /^-?[0-9]+(\.[0-9]+)?$/)  num[i]++
                else                                    text[i]++
            }
        }
        # print table of stats
        END {
            printf "%-3s %-15s %9s %9s %9s %s\n", "#", "COLUMN", "MISSING", "NUMERIC", "TEXT", "EXAMPLE"
            for (i = 1; i <= n; i++)
                printf "%-3d %-15s %9d %9d %9d %s\n", i, name[i], missing[i], num[i], text[i], substr(example[i], 1, 30)
        }' "$TSV"

    section "DUPLICATE RECORDS"

    echo "--- exact duplicate lines ---"
    tail -n +2 "$TSV" | sort | uniq -c |
        awk '$1 > 1 { groups++; extra += $1 - 1 }   # count num of copies (excluding original)
            END { print groups + 0 " lines repeated, " extra + 0 " extra copies to delete" }'

    echo "--- duplicate DR_NO (same record ID on more than one row) ---"
    tail -n +2 "$TSV" | cut -f1 | sort | uniq -c |
        awk '$1 > 1 { ids++; extra += $1 - 1 } END { print ids + 0 " DR_NOs repeated, " extra + 0 " extra rows to delete" }'

    echo "--- DR_NO formats (0 = any digit) ---"    # used to inspect length of IDs
    tail -n +2 "$TSV" | cut -f1 | sed 's/[0-9]/0/g' | sort | uniq -c

    echo "--- rows identical except DR_NO ---"
    tail -n +2 "$TSV" | cut -f2- | sort | uniq -c | 
        awk '$1 > 1 { groups++; extra += $1 - 1 } END { print groups + 0 " repeated, " extra + 0 " extra rows" }'

    echo "--- DR_NOs that are not 9 digits ---"
    awk -F'\t' 'NR > 1 && length($1) != 9 { print "line " NR ": [" $1 "]" }' "$TSV"

    echo "--- 3 sample groups of identical rows except DR_NO (columns 1-14) ---"
    tail -n +2 "$TSV" | 
        cut -f2- |          # drop the ID column
        sort | uniq -d |    # keep rows that appear more than once
        awk 'NR <= 3' |     # first 3 only
        while IFS= read -r row; do              # read one repeated row at a time
            grep -F "$row" "$TSV" | cut -f1-14  # search file for repeated row & prints matches
            echo
        done

        echo "--- crime types among identical rows except DR_NO (top 10) ---"
        tail -n +2 "$TSV" |
            cut -f2- |          # drop ID column
            sort | uniq -d |    # one copy of each repeated row
            cut -f9 |           # crime code description
            sort | uniq -c | sort -rn | awk 'NR <= 10'

    section "SPELLING, CAPITALIZATION, & FORMATTING"

    echo "--- AREA + AREA NAME (count, code, [name]) ---"
    pair_table 5 6

    echo "--- Status + Status Desc (count, code, [description]) ---"
    pair_table 19 20

    echo "--- Crm Cd codes with more than one Crm Cd Desc ---"
    pair_diff 9 10

    echo "--- Weapon Used Cd codes with more than one Weapon Desc ---"
    pair_diff 17 18

    section "DATES & TIMES"

    echo "--- DATE OCC formats (count, shape: 0=digit, Z=letter) ---"
    tail -n +2 "$TSV" | cut -f3 |
        sed 's/[0-9]/0/g' | sed 's/[A-Za-z]/Z/g' | # turn all num to 0; all letters to Z
        sort | uniq -c | sort -rn
    
    echo "--- DATE OCC years (count, first part of date) ---"
    tail -n +2 "$TSV" | cut -f3 |
        awk '{ print $1 }' |                # print first part before whitespace
        sort | uniq -c

    echo "--- DATE OCC months (count, second part of date) ---"
    tail -n +2 "$TSV" | cut -f3 |
        awk '{ print $2 }' |                # print second part
        sort | uniq -c

    echo "--- TIME OCC formats (count, shape: 0=digit) ---"
    tail -n +2 "$TSV" | cut -f4 |
        sed 's/[0-9]/0/g' | sort | uniq -c | sort -rn

    echo "--- TIME OCC impossible times (hour > 23 or minute > 59) ---"
    awk -F'\t' '
        NR > 1 && ($4 > 2359 || $4 % 100 > 59) {    # hour past 23, or last 2 digits (min) past 59
            bad++
            if (bad <= 5) print "line " NR ": [" $4 "]"     # show first 5
        }
        END { print bad + 0 " impossible times" }
    ' "$TSV"

} > "$REPORT"

echo "Inspection done. See $REPORT" >&2