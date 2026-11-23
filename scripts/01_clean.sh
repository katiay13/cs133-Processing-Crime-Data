#!/usr/bin/env bash

#  fixes quoting and line ending issues
#  does not modify raw file

set -euo pipefail # stops errors, unset vars, and failed pipes

#  Directories
SCRIPT_DIR="$(dirname "$0")"      #  ./scripts
PROJECT_DIR="$SCRIPT_DIR/.."      #  project folder

#  Data paths
RAW="$PROJECT_DIR/data/raw/crimes.csv"
NOCR="$PROJECT_DIR/data/interim/crimes_no_cr.csv"
WORK="$PROJECT_DIR/data/interim/work.csv"
TEMP="$PROJECT_DIR/data/interim/temp.csv"
OUT="$PROJECT_DIR/data/interim/01_unquoted_crimes.csv"

LOG="$PROJECT_DIR/output/log/"      #  Log path

mkdir -p "$PROJECT_DIR/data/raw" "$PROJECT_DIR/data/interim" "$PROJECT_DIR/data/processed" "$LOG"      #  create directories

if [ -f "$PROJECT_DIR/data/crimes.csv" ]; then 
mv "$PROJECT_DIR/data/crimes.csv" "$RAW"      #  moves dataset into raw directory
fi

TARGET=',"[^",]*'      #  opening quote and text till first comma within double quotes
MAX_PASSES=20
RESULT=FAIL

{
echo "--- Existing | Characters ---"
grep -c '|' "$RAW" || true      #  check for |
echo '--- Lines Containing Escaped Quotes ("") ---'
grep -c '""' "$RAW"  || true    #  check for escaped double quotes

tr -d '\r' < "$RAW" > "$NOCR"      #  remove carriage return
mv "$NOCR" "$WORK"      #  move non carriage return to working dataset

PASSES=0      #  count loop passes
while grep -q "$TARGET," "$WORK"; do
	PASSES=$((PASSES+1))
	if [ "$PASSES" -gt "$MAX_PASSES" ]; then      #  prevent infinite loop
		echo "Loop did not finish after $MAX_PASSES passes" >&2
		break
	fi
sed -E "s/($TARGET),/\1|/g" "$WORK" > "$TEMP"      #  replace first comma inside double quotes with | (repeat until none left)
mv "$TEMP" "$WORK"      #  move temp to work for while loop validation
done

sed 's/"//g' "$WORK" > "$TEMP"      #  remove double quotes
sed -E "s/(^|,)\'/\1/g" "$TEMP" > "$WORK"      #  removes leading single quotes
cut -s -d',' -f1,3,4,6,10,17,18,19,20 "$WORK" > "$OUT"      #  keeps only needed fields

HASQUOTES=$(grep -c '"' "$OUT" || true)
echo "--- Lines Still Containing Quotes ---"
echo "$HASQUOTES"
NUMFIELDS=$(awk -F',' '{print NF}' "$OUT" | sort -u)
echo "--- Distinct Field Counts (Want 9) ---"
awk -F',' '{print NF}' "$OUT" | sort | uniq -c

echo; echo "--- Cleaning Validation ---"
if [ "$HASQUOTES" -eq 0 ] && [ "$NUMFIELDS" -eq 9 ]; then      #  validate for no quotes and correct number of fields
	echo "PASS"
	rm -f "$NOCR" "$WORK" "$TEMP"
RESULT=PASS
else
	echo "FAIL: Quotes still contained in dataset or incorrect number of fields"
	echo "FAIL: Quotes still contained in dataset or incorrect number of fields" >&2
fi

} > "$LOG/01_clean.log" 2>> "$LOG/err.log"

if [ "$RESULT" =  "PASS" ]; then     
echo "Cleaning part 1 done. See $OUT"
else
	echo "Error. See ${LOG}err.log"
	exit 1
fi
