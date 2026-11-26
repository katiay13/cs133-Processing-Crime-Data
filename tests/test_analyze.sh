#!/usr/bin/env bash
# Synthetic 15-column input matching Kenny's 03_clean.sh output.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$ROOT/analyze.sh" "$ROOT/tests/fixtures/clean_crimes_sample.csv" "$TMP/out"

# Exact annual counts and year-over-year percentage calculations.
awk -F'\t' '
NR==2 && ($1!="2020" || $2!=4 || $3!="N/A") {exit 1}
NR==3 && ($1!="2021" || $2!=2 || $3!="-50.00") {exit 1}
NR==4 && ($1!="2022" || $2!=2 || $3!="0.00") {exit 1}
NR==5 && ($1!="2023" || $2!=3 || $3!="50.00") {exit 1}
END {if(NR!=5) exit 1}
' "$TMP/out/yearly.tsv"

# New outputs should count known, unknown and arrest statuses correctly.
awk -F'\t' '
$1=="ROWS_IN_2020_TO_2023" && $2==11 {period=1}
$1=="PERIOD_ROWS_WITH_ARREST_STATUS" && $2==3 {arrests=1}
$1=="PERIOD_ROWS_WITH_UNKNOWN_STATUS" && $2==2 {unknown=1}
$1=="PERIOD_ROWS_WITH_NON9_DIGIT_ID" && $2==1 {bad_id=1}
$1=="PERIOD_ROWS_WITH_WEAPON_DESC_WITHOUT_CODE" && $2==1 {mismatch=1}
END {if(!(period && arrests && unknown && bad_id && mismatch)) exit 1}
' "$TMP/out/summary.tsv"

awk -F'\t' '
$1=="REJECTED_MALFORMED_RECORDS" && $2==1 {seen=1}
END {if(!seen) exit 1}
' "$TMP/out/run_log.tsv"

# Central has 7 records, 3 weapon codes and 2 AA/JA arrests. Its 09 hour
# is the most common (2 records), even though an unknown month is present.
awk -F'\t' '
NR==2 && ($1!="Central" || $2!=7 || $3!=3 || $4!="42.86" ||
          $5!=2 || $6!="28.57" || $7!=5 || $8!="40.00" || $9!=2) {exit 1}
END {if(NR<2) exit 1}
' "$TMP/out/area_metrics.tsv"
awk -F'\t' '
NR==2 && ($1!="Central" || $2!="09" || $3!=2 || $4!=7) {exit 1}
END {if(NR<2) exit 1}
' "$TMP/out/top_area_peak_hours.tsv"
awk -F'\t' '$1=="AA" && $3==2 {aa=1} $1=="JA" && $3==1 {ja=1}
END {if(!(aa && ja)) exit 1}' "$TMP/out/status_counts.tsv"

# 2024 records must not contribute; 48 rows plus header in monthly timeline.
awk -F'\t' '
$1=="2023" && $2=="06" && $3==1 {seen=1}
END {if(NR!=49 || !seen) exit 1}
' "$TMP/out/year_month.tsv"

# A rerun is deterministic and never appends to an old report.
for name in yearly monthly year_month hourly top_areas top_crime_types \
            area_metrics top_area_peak_hours status_counts summary rejected_rows; do
    cp "$TMP/out/$name.tsv" "$TMP/$name.first"
done
bash "$ROOT/analyze.sh" "$ROOT/tests/fixtures/clean_crimes_sample.csv" "$TMP/out" >/dev/null
for name in yearly monthly year_month hourly top_areas top_crime_types \
            area_metrics top_area_peak_hours status_counts summary rejected_rows; do
    diff -u "$TMP/$name.first" "$TMP/out/$name.tsv"
done

# Reject a 13-column legacy header, and reject a missing input file.
head -n 2 "$ROOT/tests/fixtures/clean_crimes_sample.csv" | \
    cut -d',' -f1-13 > "$TMP/old_schema.csv"
if bash "$ROOT/analyze.sh" "$TMP/old_schema.csv" "$TMP/old_out" >/dev/null 2>&1; then
    echo 'FAIL: Old 13-column schema accepted' >&2; exit 1
fi
if bash "$ROOT/analyze.sh" "$TMP/missing.csv" "$TMP/old_out" >/dev/null 2>&1; then
    echo 'FAIL: Missing input accepted' >&2; exit 1
fi

echo 'PASS: 15-column input, yearly/monthly counts, weapon/status metrics, area peaks,'
echo '      row audit, old-header rejection, rerun, and missing-input behavior'
