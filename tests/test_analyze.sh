#!/usr/bin/env bash
# Small, independent fixture test for Eric's first-pass analysis.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash "$ROOT/analyze.sh" "$ROOT/tests/fixtures/clean_crimes_sample.csv" "$TMP/out"

awk -F'\t' '
NR==2 && ($1!="2020" || $2!=3 || $3!="N/A") {exit 1}
NR==3 && ($1!="2021" || $2!=1 || $3!="-66.67") {exit 1}
NR==4 && ($1!="2022" || $2!=1 || $3!="0.00") {exit 1}
NR==5 && ($1!="2023" || $2!=2 || $3!="100.00") {exit 1}
END {if(NR!=5) exit 1}
' "$TMP/out/yearly.tsv"

awk -F'\t' '
$1=="ROWS_IN_2020_TO_2023" && $2==7 {seen=1}
END {if(!seen) exit 1}
' "$TMP/out/summary.tsv"

awk -F'\t' '
$1=="REJECTED_MALFORMED_RECORDS" && $2==1 {seen=1}
END {if(!seen) exit 1}
' "$TMP/out/run_log.tsv"

# A repeat run must not append duplicate results.
cp "$TMP/out/yearly.tsv" "$TMP/first.tsv"
bash "$ROOT/analyze.sh" "$ROOT/tests/fixtures/clean_crimes_sample.csv" "$TMP/out" >/dev/null
diff -u "$TMP/first.tsv" "$TMP/out/yearly.tsv"

# A missing input must cause a nonzero exit status.
if bash "$ROOT/analyze.sh" "$TMP/missing.csv" "$TMP/out" >/dev/null 2>&1; then
    echo 'FAIL: Missing input was accepted' >&2
    exit 1
fi

echo 'PASS: Yearly counts, malformed-row logging, rerun, and missing-input behavior'
