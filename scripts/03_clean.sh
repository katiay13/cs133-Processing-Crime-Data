#!/usr/bin/env bash

#  normalizes text fields and status codes, checks code/description pairs
#  does not modify raw file

set -euo pipefail # stops errors, unset vars, and failed pipes

#  Directories
SCRIPT_DIR="$(dirname "$0")"      #  ./scripts
PROJECT_DIR="$SCRIPT_DIR/.."      #  project folder

#  Data paths
IN="$PROJECT_DIR/data/interim/02_clean_crimes.csv"
TEMP="$PROJECT_DIR/data/interim/temp.csv"
FLAGGED="$PROJECT_DIR/data/interim/03_flagged_rows_crimes.csv"
REJECTED="$PROJECT_DIR/data/interim/03_rejected_rows_crimes.csv"
OUT="$PROJECT_DIR/data/interim/03_clean_crimes.csv"

LOG="$PROJECT_DIR/output/log/"      #  Log path

HEADER="DR_NO,DATE OCC,TIME OCC,AREA NAME,Crm Cd Desc,Weapon Used Cd,Weapon Desc,Status,Status Desc,YEAR OCC,MONTH OCC,DAY OCC,CLEAN TIME OCC"
RESULT=FAIL

mkdir -p "$LOG"

if [ ! -s "$IN" ]; then      #  input has to exist and not be empty
	echo "Error. Missing or empty $IN (run 01_clean.sh and 02_clean.sh first)" | tee -a "$LOG/err.log" >&2
	exit 1
fi

if [ "$(head -n 1 "$IN")" != "$HEADER" ]; then      #  columns have to match 02_clean output
	echo "Error. Header in $IN does not match 02_clean.sh output" | tee -a "$LOG/err.log" >&2
	exit 1
fi

{

awk -F',' -v FLAGGED="$FLAGGED" -v REJECTED="$REJECTED" '
BEGIN {
OFS=","
}

NR == 1 {
print $0
print $0, "ISSUES" > FLAGGED
print "LINE", "FIELDS", "ROW" > REJECTED
next
}

NF != 13 {      #  wrong field count means shifted columns, move row out
print NR, NF, $0 > REJECTED
next
}

{
issues=""
separator=""

spaces=0
for (i = 4; i <= 9; i++) {      #  trim and squeeze spaces in area, crime, weapon, status fields
	before=$i
	gsub(/^ +| +$/, "", $i)
	gsub(/  +/, " ", $i)
	if ($i != before) { spaces=1 }
}
if (spaces)      { issues=issues separator "SPACES_FIXED"; separator="|" }

if ($8 != toupper($8)) {      #  status codes should be uppercase
	$8=toupper($8)
	issues=issues separator "STATUS_UPPERCASED"; separator="|"
}
if ($8 == "") {      #  blank status becomes unknown
	issues=issues separator "STATUS_BLANK"; separator="|"
	$8="UNK"; $9="Unknown"
} else if ($8 == "CC") {      #  CC is not a documented code, also unknown
	issues=issues separator "STATUS_CC"; separator="|"
	$8="UNK"; $9="Unknown"
} else if ($8 !~ /^(AA|AO|IC|JA|JO|UNK)$/) {      #  anything else gets flagged but kept
	issues=issues separator "STATUS_UNEXPECTED"; separator="|"
}

if (($6 == "") != ($7 == ""))      { issues=issues separator "WEAPON_MISMATCH"; separator="|" }      #  code and desc should both be blank or both filled
if ($6 != "" && $6 !~ /^[0-9]+$/)      { issues=issues separator "WEAPON_CODE_NOT_NUMERIC"; separator="|" }
if ($4 == "")      { issues=issues separator "AREA_BLANK"; separator="|" }
if ($5 == "")      { issues=issues separator "CRIME_DESC_BLANK"; separator="|" }

if (issues != "")      { print $0, issues > FLAGGED }      #  row stays in output, copy goes to flagged file
print $0
} ' "$IN" > "$TEMP"

NUMFIELDS=$(awk -F',' '{print NF}' "$TEMP" | sort -u)
echo "--- Distinct Field Counts (Want 13) ---"
awk -F',' '{print NF}' "$TEMP" | sort | uniq -c

echo; echo "--- Diagnostics ---"
ROWS_IN=$(awk 'END{print NR-1}' "$IN")
ROWS_OUT=$(awk 'END{print NR-1}' "$TEMP")
ROWS_REJECTED=$(awk 'END{print NR-1}' "$REJECTED")
ROWS_FLAGGED=$(awk 'END{print NR-1}' "$FLAGGED")
echo "Total rows: $ROWS_IN"
echo "Rows kept: $ROWS_OUT"
echo "Rows removed for wrong field count: $ROWS_REJECTED"
echo "Rows flagged (kept, see 03_flagged_rows_crimes.csv): $ROWS_FLAGGED"

echo; echo "--- Issue Counts ---"
for ISSUE in SPACES_FIXED STATUS_UPPERCASED STATUS_BLANK STATUS_CC STATUS_UNEXPECTED WEAPON_MISMATCH WEAPON_CODE_NOT_NUMERIC AREA_BLANK CRIME_DESC_BLANK; do
	echo "$ISSUE: $(grep -c "$ISSUE" "$FLAGGED" || true)"
done

echo; echo "--- Rows with issues (DR_NO: Issues) ---"
if [ "$ROWS_FLAGGED" -gt 0 ]; then
	if [ "$ROWS_FLAGGED" -gt 10 ]; then
		awk -F"," 'NR>1 {print $1": "$14}' "$FLAGGED" | head -10 || true
		echo "..."
		echo "+$((ROWS_FLAGGED-10)) more"
	else
		awk -F"," 'NR>1 {print $1": "$14}' "$FLAGGED"
	fi
else
	echo "No rows with issues"
fi

echo; echo "--- Status Codes (Count, Code, Description) ---"
tail -n +2 "$TEMP" | cut -d',' -f8,9 | sort | uniq -c
echo "--- Status Codes With More Than One Description (Want 0) ---"
tail -n +2 "$TEMP" | cut -d',' -f8,9 | sort -u | cut -d',' -f1 | uniq -d | wc -l

echo; echo "--- Distinct Weapon Codes ---"
awk -F',' 'NR>1 && $6 != "" {print $6}' "$TEMP" | sort -u | wc -l
echo "--- Weapon Codes With More Than One Description (Want 0) ---"
awk -F',' 'NR>1 && $6 != "" {print $6","$7}' "$TEMP" | sort -u | cut -d',' -f1 | uniq -d | wc -l

echo; echo "--- Distinct Area Names (Want 21) ---"
tail -n +2 "$TEMP" | cut -d',' -f4 | sort -u | wc -l
echo "--- Rows Per Area ---"
tail -n +2 "$TEMP" | cut -d',' -f4 | sort | uniq -c | sort -rn

echo; echo "--- Distinct Crime Descriptions ---"
tail -n +2 "$TEMP" | cut -d',' -f5 | sort -u | wc -l
echo "--- Crime Descriptions Containing | (commas replaced in 01_clean) ---"
awk -F',' 'NR>1 && $5 ~ /\|/' "$TEMP" | wc -l

echo; echo "--- Cleaning Validation ---"
if [ "$NUMFIELDS" -eq 13 ] && [ $((ROWS_OUT + ROWS_REJECTED)) -eq "$ROWS_IN" ]; then      #  13 fields and no rows lost
	echo "PASS"
	mv "$TEMP" "$OUT"
	RESULT=PASS
else
	echo "FAIL: Incorrect number of fields or rows missing"
	echo "FAIL: Incorrect number of fields or rows missing" >&2
	rm -f "$TEMP"
fi

} > "$LOG/03_clean.log" 2>> "$LOG/err.log"

if [ "$RESULT" =  "PASS" ]; then
	echo "Cleaning part 3 done. See $OUT"
else
	echo "Error. See ${LOG}err.log"
	exit 1
fi
