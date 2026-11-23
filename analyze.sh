#!/usr/bin/env bash
# CS 131 semester project: first-pass LAPD crime analysis (2020-2023)
# Input: Frank's 13-column cleaned CSV (scripts/02_clean.sh output).
# Output: reproducible TSV summaries, counts, and a malformed-row log.
# Usage: bash analyze.sh [CLEANED.csv] [OUTPUT_DIRECTORY]

set -euo pipefail
export LC_ALL=C

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="${1:-$PROJECT_DIR/data/interim/02_clean_crimes.csv}"
OUT_DIR="${2:-$PROJECT_DIR/output/analysis}"

if [[ ! -s "$INPUT" || ! -r "$INPUT" ]]; then
    printf 'ERROR: Cleaned input does not exist or cannot be read: %s\n' "$INPUT" >&2
    exit 2
fi
mkdir -p "$OUT_DIR"
TEMP_DIR="$(mktemp -d "$OUT_DIR/.analyze.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

# Check the input format once. Preserve malformed rows for review instead of
# letting a shifted column silently produce incorrect statistics.
awk -F',' -v bad="$TEMP_DIR/rejected_rows.tsv" '
BEGIN { OFS="\t"; print "SOURCE_LINE", "DR_NO", "FIELD_COUNT", "ISSUE" > bad }
NR == 1 {
    sub(/\r$/, "")
    if (NF != 13 || $1 != "DR_NO" || $4 != "AREA NAME" ||
        $10 != "YEAR OCC" || $11 != "MONTH OCC" ||
        $12 != "DAY OCC" || $13 != "CLEAN TIME OCC") {
        print "ERROR: Expected the 13-column output of 02_clean.sh" > "/dev/stderr"
        exit 2
    }
    print $0
    next
}
{
    sub(/\r$/, "")
    if (NF != 13) {
        print NR, $1, NF, "EXPECTED_13_FIELDS" >> bad
        next
    }
    print $0
}
' "$INPUT" > "$TEMP_DIR/validated.csv"

# Q1: Annual crime counts and percentage change from the previous year.
awk -F',' '
BEGIN { OFS="\t"; print "YEAR", "CRIME_COUNT", "CHANGE_FROM_PREVIOUS_YEAR_PCT" }
NR > 1 && $10 ~ /^202[0-3]$/ { count[$10]++ }
END {
    for (y = 2020; y <= 2023; y++) {
        current = count[y] + 0
        if (y == 2020 || previous == 0) change = "N/A"
        else change = sprintf("%.2f", 100 * (current - previous) / previous)
        print y, current, change
        previous = current
    }
}
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/yearly.tsv"

# Q2: Monthly crime counts across all four years (only known months).
awk -F',' '
BEGIN { OFS="\t"; print "MONTH", "CRIME_COUNT" }
NR > 1 && $10 ~ /^202[0-3]$/ && $11 ~ /^(0?[1-9]|1[0-2])$/ {
    count[$11 + 0]++
}
END { for (m = 1; m <= 12; m++) printf "%02d\t%d\n", m, count[m] + 0 }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/monthly.tsv"

# Q3: Hourly crime counts. Frank's CLEAN TIME OCC is HHMM (e.g. 0930).
awk -F',' '
BEGIN { OFS="\t"; print "HOUR", "CRIME_COUNT" }
NR > 1 && $10 ~ /^202[0-3]$/ &&
    $13 ~ /^([01][0-9]|2[0-3])[0-5][0-9]$/ {
    count[substr($13, 1, 2) + 0]++
}
END { for (h = 0; h < 24; h++) printf "%02d\t%d\n", h, count[h] + 0 }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/hourly.tsv"

# Q4: Top 10 police areas by number of records.
awk -F',' '
NR > 1 && $10 ~ /^202[0-3]$/ && $4 != "" && $4 != "UNKNOWN" { count[$4]++ }
END { for (area in count) printf "%s\t%d\n", area, count[area] }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/areas_unsorted.tsv"
{
    printf 'AREA_NAME\tCRIME_COUNT\n'
    sort -t $'\t' -k2,2nr -k1,1 "$TEMP_DIR/areas_unsorted.tsv" | head -n 10
} > "$TEMP_DIR/top_areas.tsv"

# Q5: Top 10 reported crime categories.
awk -F',' '
NR > 1 && $10 ~ /^202[0-3]$/ && $5 != "" && $5 != "UNKNOWN" { count[$5]++ }
END { for (crime in count) printf "%s\t%d\n", crime, count[crime] }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/types_unsorted.tsv"
{
    printf 'CRIME_TYPE\tCRIME_COUNT\n'
    sort -t $'\t' -k2,2nr -k1,1 "$TEMP_DIR/types_unsorted.tsv" | head -n 10
} > "$TEMP_DIR/top_crime_types.tsv"

# Report how many records each analysis includes or excludes.
awk -F',' '
BEGIN { OFS="\t"; print "METRIC", "COUNT" }
NR > 1 {
    valid++
    if ($10 !~ /^202[0-3]$/) {
        outside++
        if ($10 == "UNKNOWN") unknown_year++
        next
    }
    period++
    if ($11 !~ /^(0?[1-9]|1[0-2])$/) bad_month++
    if ($13 !~ /^([01][0-9]|2[0-3])[0-5][0-9]$/) bad_time++
    if ($4 == "" || $4 == "UNKNOWN") missing_area++
    if ($5 == "" || $5 == "UNKNOWN") missing_type++
}
END {
    print "STRUCTURALLY_VALID_ROWS", valid + 0
    print "ROWS_IN_2020_TO_2023", period + 0
    print "ROWS_OUTSIDE_PERIOD_OR_UNKNOWN_YEAR", outside + 0
    print "ROWS_WITH_UNKNOWN_YEAR", unknown_year + 0
    print "PERIOD_ROWS_WITH_INVALID_MONTH", bad_month + 0
    print "PERIOD_ROWS_WITH_INVALID_TIME", bad_time + 0
    print "PERIOD_ROWS_WITH_MISSING_AREA", missing_area + 0
    print "PERIOD_ROWS_WITH_MISSING_CRIME_TYPE", missing_type + 0
}
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/summary.tsv"

# Add source totals and malformed records to an auditable run log.
TOTAL=$(awk 'END { print NR - 1 }' "$INPUT")
VALID=$(awk 'END { print NR - 1 }' "$TEMP_DIR/validated.csv")
REJECTED=$((TOTAL - VALID))
{
    printf 'INPUT_FILE\t%s\n' "$INPUT"
    printf 'INPUT_RECORDS\t%d\n' "$TOTAL"
    printf 'STRUCTURALLY_VALID_RECORDS\t%d\n' "$VALID"
    printf 'REJECTED_MALFORMED_RECORDS\t%d\n' "$REJECTED"
    printf 'ANALYSIS_YEARS\t2020-2023\n'
} > "$TEMP_DIR/run_log.tsv"

# Publish only after every step has completed successfully.
for name in yearly monthly hourly top_areas top_crime_types summary run_log rejected_rows; do
    mv "$TEMP_DIR/$name.tsv" "$OUT_DIR/$name.tsv"
done
printf 'Analysis complete: %s\n' "$OUT_DIR"
printf 'Input records: %d; malformed rows: %d\n' "$TOTAL" "$REJECTED"
