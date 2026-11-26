#!/usr/bin/env bash
# CS 131 semester project: LAPD reported-crime analysis, occurrences 2020-2023.
# Input is Kenny's 15-column normalized data (scripts/03_clean.sh output).
# Usage: bash analyze.sh [03_clean_crimes.csv] [OUTPUT_DIRECTORY]
# All analysis outputs are TSV; the source CSV and teammates' scripts are unchanged.
set -euo pipefail
export LC_ALL=C

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INPUT="${1:-$PROJECT_DIR/data/interim/03_clean_crimes.csv}"
OUT_DIR="${2:-$PROJECT_DIR/output/analysis}"

if [[ ! -s "$INPUT" || ! -r "$INPUT" ]]; then
    printf 'ERROR: Missing, empty, or unreadable normalized input: %s\n' "$INPUT" >&2
    exit 2
fi
mkdir -p "$OUT_DIR"
TEMP_DIR="$(mktemp -d "$OUT_DIR/.analyze.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

# 03_clean.sh removes/normalizes embedded commas before this stage.
# Do not use awk -F, directly on the original 28-column quoted CSV.
# Check the complete column order so later changes cannot silently shift counts.
awk -F',' -v bad="$TEMP_DIR/rejected_rows.tsv" '
BEGIN {
    OFS="\t"
    expected="DR_NO,DATE OCC,TIME OCC,AREA NAME,Crm Cd Desc,Weapon Used Cd,Weapon Desc,Status,Status Desc,YEAR OCC,MONTH OCC,DAY OCC,CLEAN TIME OCC,CLEAN STATUS,CLEAN STATUS DESC"
    print "SOURCE_LINE", "DR_NO", "FIELD_COUNT", "ISSUE" > bad
}
NR == 1 {
    sub(/\r$/, "")
    if ($0 != expected) {
        print "ERROR: Expected the exact 15-column header from scripts/03_clean.sh" > "/dev/stderr"
        exit 2
    }
    print $0
    next
}
{
    sub(/\r$/, "")
    if (NF != 15) {
        print NR, $1, NF, "EXPECTED_15_FIELDS" >> bad
        next
    }
    print $0
}
' "$INPUT" > "$TEMP_DIR/validated.csv"

# Q1. Reported crime records by occurrence year, with previous-year change.
awk -F',' '
BEGIN { OFS="\t"; print "YEAR", "CRIME_COUNT", "CHANGE_FROM_PREVIOUS_YEAR_PCT" }
NR > 1 && $10 ~ /^202[0-3]$/ { count[$10]++ }
END {
    for (y=2020; y<=2023; y++) {
        current=count[y]+0
        if (y==2020 || previous==0) change="N/A"
        else change=sprintf("%.2f", 100*(current-previous)/previous)
        print y, current, change
        previous=current
    }
}
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/yearly.tsv"

# Q2. Calendar-month totals aggregated across the four analysis years.
awk -F',' '
BEGIN { OFS="\t"; print "MONTH", "CRIME_COUNT" }
NR>1 && $10 ~ /^202[0-3]$/ && $11 ~ /^(0?[1-9]|1[0-2])$/ { count[$11+0]++ }
END { for (m=1; m<=12; m++) printf "%02d\t%d\n", m, count[m]+0 }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/monthly.tsv"

# Q2b. Separate chronological month-by-month data to identify specific peaks.
awk -F',' '
BEGIN { OFS="\t"; print "YEAR", "MONTH", "CRIME_COUNT" }
NR>1 && $10 ~ /^202[0-3]$/ && $11 ~ /^(0?[1-9]|1[0-2])$/ {
    count[($10+0) SUBSEP ($11+0)]++
}
END {
    for (y=2020; y<=2023; y++)
        for (m=1; m<=12; m++)
            printf "%d\t%02d\t%d\n", y, m, count[y SUBSEP m]+0
}
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/year_month.tsv"

# Q3. Time-of-occurrence distribution by hour, using CLEAN TIME OCC (HHMM).
awk -F',' '
BEGIN { OFS="\t"; print "HOUR", "CRIME_COUNT" }
NR>1 && $10 ~ /^202[0-3]$/ && $13 ~ /^([01][0-9]|2[0-3])[0-5][0-9]$/ {
    count[substr($13,1,2)+0]++
}
END { for (h=0; h<24; h++) printf "%02d\t%d\n", h, count[h]+0 }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/hourly.tsv"

# Q4. Top 10 LAPD police areas (not a neighborhood-adjusted risk ranking).
awk -F',' '
NR>1 && $10 ~ /^202[0-3]$/ && $4!="" && $4!="UNKNOWN" { count[$4]++ }
END { for (a in count) printf "%s\t%d\n", a, count[a] }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/areas_unsorted.tsv"
{
    printf 'AREA_NAME\tCRIME_COUNT\n'
    # awk reads the full sorted stream, avoiding head/SIGPIPE under pipefail.
    sort -t $'\t' -k2,2nr -k1,1 "$TEMP_DIR/areas_unsorted.tsv" | awk 'NR<=10'
} > "$TEMP_DIR/top_areas.tsv"

# Q5. Most frequently reported crime descriptions.
awk -F',' '
NR>1 && $10 ~ /^202[0-3]$/ && $5!="" && $5!="UNKNOWN" { count[$5]++ }
END { for (crime in count) printf "%s\t%d\n", crime, count[crime] }
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/types_unsorted.tsv"
{
    printf 'CRIME_TYPE\tCRIME_COUNT\n'
    sort -t $'\t' -k2,2nr -k1,1 "$TEMP_DIR/types_unsorted.tsv" | awk 'NR<=10'
} > "$TEMP_DIR/top_crime_types.tsv"

# Q6. Compare areas: weapon-code presence and arrest statuses AA/JA.
# A weapon code may describe bodily force; a blank may mean unknown, not no weapon.
# Arrest recorded is NOT the same as case solved / convicted.
awk -F',' '
BEGIN { OFS="\t" }
NR>1 && $10 ~ /^202[0-3]$/ && $4!="" && $4!="UNKNOWN" {
    a=$4; total[a]++
    if ($6!="") weapon[a]++
    if ($14=="AA" || $14=="JA") arrest[a]++
    if ($14 ~ /^(AA|AO|IC|JA|JO)$/) known[a]++
    else unknown[a]++
}
END {
    for (a in total) {
        among_known=(known[a] ? sprintf("%.2f",100*arrest[a]/known[a]) : "N/A")
        printf "%s\t%d\t%d\t%.2f\t%d\t%.2f\t%d\t%s\t%d\n", \
            a, total[a], weapon[a]+0, 100*(weapon[a]+0)/total[a], \
            arrest[a]+0, 100*(arrest[a]+0)/total[a], known[a]+0, \
            among_known, unknown[a]+0
    }
}
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/area_metrics_unsorted.tsv"
{
    printf 'AREA_NAME\tCRIME_COUNT\tWEAPON_CODE_PRESENT\tWEAPON_CODE_PRESENT_PCT\tARREST_RECORDED\tARREST_RECORDED_PCT\tKNOWN_STATUS_ROWS\tARREST_AMONG_KNOWN_STATUS_PCT\tUNKNOWN_STATUS_ROWS\n'
    sort -t $'\t' -k2,2nr -k1,1 "$TEMP_DIR/area_metrics_unsorted.tsv"
} > "$TEMP_DIR/area_metrics.tsv"

# Q7. Peak reported hour within each of the top 10 areas. Only valid HHMM used.
# For ties, the earlier hour wins. If no valid times, PEAK_HOUR is N/A.
awk -F',' '
FNR==NR {
    if (FNR>1) {
        split($0, field, "\t")
        n++; area[n]=field[1]; rank[field[1]]=n
    }
    next
}
FNR>1 && $10 ~ /^202[0-3]$/ && ($4 in rank) &&
    $13 ~ /^([01][0-9]|2[0-3])[0-5][0-9]$/ {
    i=rank[$4]; h=substr($13,1,2)+0
    counts[i SUBSEP h]++
    valid_times[i]++
}
END {
    print "AREA_NAME\tPEAK_HOUR\tCRIME_COUNT_AT_PEAK_HOUR\tRECORDS_WITH_VALID_TIME"
    for (i=1; i<=n; i++) {
        best_hour="N/A"; best_count=0
        for (h=0; h<24; h++) {
            c=counts[i SUBSEP h]+0
            if (c>best_count) { best_hour=sprintf("%02d",h); best_count=c }
        }
        print area[i] "\t" best_hour "\t" best_count "\t" (valid_times[i]+0)
    }
}
' "$TEMP_DIR/top_areas.tsv" "$TEMP_DIR/validated.csv" > "$TEMP_DIR/top_area_peak_hours.tsv"

# Q8. Normalize status labels for a concise frequency table. CC and UNK are
# unknown labels, not statuses that should be counted as resolved cases.
awk -F',' '
BEGIN { OFS="\t"; print "CLEAN_STATUS", "MEANING", "CRIME_COUNT" }
NR>1 && $10 ~ /^202[0-3]$/ { count[$14]++ }
END {
    code[1]="AA"; desc[1]="ADULT ARREST"
    code[2]="AO"; desc[2]="ADULT OTHER"
    code[3]="IC"; desc[3]="INVEST CONT"
    code[4]="JA"; desc[4]="JUV ARREST"
    code[5]="JO"; desc[5]="JUV OTHER"
    code[6]="CC"; desc[6]="UNKNOWN (02_clean fallback)"
    code[7]="UNK"; desc[7]="UNKNOWN"
    for (i=1; i<=7; i++) {
        print code[i], desc[i], count[code[i]]+0
        seen[code[i]]=1
    }
    for (s in count) if (!(s in seen)) print s, "UNEXPECTED / REVIEW", count[s]
}
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/status_counts.tsv"

# Audit counts / denominators, including anomalies still present in the
# provided teammate scripts. This does NOT deduplicate or reject bad IDs.
awk -F',' '
BEGIN { OFS="\t"; print "METRIC", "COUNT" }
NR>1 {
    valid++
    if ($10 !~ /^202[0-3]$/) {
        outside++
        if ($10=="UNKNOWN") unknown_year++
        next
    }
    period++
    if ($11 !~ /^(0?[1-9]|1[0-2])$/) bad_month++
    if ($13 !~ /^([01][0-9]|2[0-3])[0-5][0-9]$/) bad_time++
    if ($4=="" || $4=="UNKNOWN") missing_area++
    if ($5=="" || $5=="UNKNOWN") missing_type++
    if ($14 ~ /^(AA|AO|IC|JA|JO)$/) known_status++
    else unknown_status++
    if ($14=="AA" || $14=="JA") arrest++
    if ($6!="") weapon++
    if ($6=="" && $7!="") desc_no_code++
    if ($6!="" && $7=="") code_no_desc++
    if (length($1)!=9 || $1 !~ /^[0-9]+$/) nonstandard_id++
    if ($14 !~ /^(AA|AO|IC|JA|JO|CC|UNK)$/) unexpected_status++
}
END {
    print "STRUCTURALLY_VALID_ROWS", valid+0
    print "ROWS_IN_2020_TO_2023", period+0
    print "ROWS_OUTSIDE_PERIOD_OR_UNKNOWN_YEAR", outside+0
    print "ROWS_WITH_UNKNOWN_YEAR", unknown_year+0
    print "PERIOD_ROWS_WITH_INVALID_MONTH", bad_month+0
    print "PERIOD_ROWS_WITH_INVALID_TIME", bad_time+0
    print "PERIOD_ROWS_WITH_MISSING_AREA", missing_area+0
    print "PERIOD_ROWS_WITH_MISSING_CRIME_TYPE", missing_type+0
    print "PERIOD_ROWS_WITH_KNOWN_STATUS", known_status+0
    print "PERIOD_ROWS_WITH_UNKNOWN_STATUS", unknown_status+0
    print "PERIOD_ROWS_WITH_ARREST_STATUS", arrest+0
    print "PERIOD_ROWS_WITH_WEAPON_CODE", weapon+0
    print "PERIOD_ROWS_WITH_WEAPON_DESC_WITHOUT_CODE", desc_no_code+0
    print "PERIOD_ROWS_WITH_WEAPON_CODE_WITHOUT_DESC", code_no_desc+0
    print "PERIOD_ROWS_WITH_NON9_DIGIT_ID", nonstandard_id+0
    print "PERIOD_ROWS_WITH_UNEXPECTED_STATUS", unexpected_status+0
}
' "$TEMP_DIR/validated.csv" > "$TEMP_DIR/summary.tsv"

TOTAL=$(awk 'END { print NR-1 }' "$INPUT")
VALID=$(awk 'END { print NR-1 }' "$TEMP_DIR/validated.csv")
REJECTED=$((TOTAL-VALID))
{
    printf 'INPUT_FILE\t%s\n' "$INPUT"
    printf 'INPUT_RECORDS\t%d\n' "$TOTAL"
    printf 'STRUCTURALLY_VALID_RECORDS\t%d\n' "$VALID"
    printf 'REJECTED_MALFORMED_RECORDS\t%d\n' "$REJECTED"
    printf 'ANALYSIS_YEARS\t2020-2023\n'
    printf 'INPUT_STAGE\t03_clean.sh / 15-column normalized data\n'
    printf 'DEDUPLICATION_BY_ANALYSIS\tnone (upstream decision pending implementation)\n'
} > "$TEMP_DIR/run_log.tsv"

# Publish reports only if all processing above succeeded. Reruns overwrite
# these files rather than appending counts from an earlier execution.
for name in yearly monthly year_month hourly top_areas top_crime_types \
            area_metrics top_area_peak_hours status_counts summary run_log rejected_rows; do
    mv "$TEMP_DIR/$name.tsv" "$OUT_DIR/$name.tsv"
done
printf 'Analysis complete: %s\n' "$OUT_DIR"
printf 'Input records: %d; malformed rows: %d\n' "$TOTAL" "$REJECTED"
printf 'Reminder: duplicate-like records and short DR_NOs are not yet filtered by upstream scripts.\n'
