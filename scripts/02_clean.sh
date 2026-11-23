#!/usr/bin/env bash

#  fixes date and time formatting
#  does not modify raw file

set -euo pipefail # stops errors, unset vars, and failed pipes

#  Directories
SCRIPT_DIR="$(dirname "$0")"      #  ./scripts
PROJECT_DIR="$SCRIPT_DIR/.."      #  project folder

#  Data paths
IN="$PROJECT_DIR/data/interim/01_unquoted_crimes.csv"
WORK="$PROJECT_DIR/data/interim/work.csv"
TEMP="$PROJECT_DIR/data/interim/temp.csv"
BAD_ROWS="$PROJECT_DIR/data/interim/02_invalid_rows_crimes.csv"
OUT="$PROJECT_DIR/data/interim/02_clean_crimes.csv"

LOG="$PROJECT_DIR/output/log/"      #  Log path

RESULT=FAIL

{

cp "$IN" "$WORK" 

: > "$BAD_ROWS"      #  resets file so displayed unknowns are exclusive to each run

awk -F','  -v BAD_ROWS="$BAD_ROWS" '
BEGIN {
	OFS=","
	months["jan"]=1;      days_in_month["jan"]=31
	months["feb"]=2;      days_in_month["feb"]=28
	months["mar"]=3;      days_in_month["mar"]=31
	months["apr"]=4;      days_in_month["apr"]=30
	months["may"]=5;      days_in_month["may"]=31
	months["jun"]=6;      days_in_month["jun"]=30
	months["jul"]=7;      days_in_month["jul"]=31
	months["aug"]=8;      days_in_month["aug"]=31
	months["sep"]=9;      days_in_month["sep"]=30
	months["oct"]=10;      days_in_month["oct"]=31
	months["nov"]=11;      days_in_month["nov"]=30
	months["dec"]=12;      days_in_month["dec"]=31
YEAR_TARGET="^202[0-4]$"      #  correct years
DAY_TARGET="^(0?[1-9]|[1-2][0-9]|3[0-1])$"      #  valid day
TIME_TARGET="^([01][0-9]|2[0-3])[0-5][0-9]$"      #  correct military time format

}

NR == 1 {
print $0, "YEAR OCC", "MONTH OCC", "DAY OCC", "CLEAN TIME OCC"
print $0, "YEAR OCC", "MONTH OCC", "DAY OCC", "CLEAN TIME OCC", "ISSUES" > BAD_ROWS

next
}

{
year="UNKNOWN"
month="UNKNOWN"
day="UNKNOWN"
time="UNKNOWN"

split($2, date, " ")

if (date[1] ~ YEAR_TARGET) {      #  validate year
	year=date[1] + 0      #  remove leading zero
}
if (tolower(date[2]) in months) {      #  validate month
	month=months[tolower(date[2])]
}
if (date[3] ~ DAY_TARGET) {      #  validate day
	day=date[3] + 0      #  remove leading zero
}

if (year != "UNKNOWN" && month != "UNKNOWN" && day != "UNKNOWN") {      #  check month lengths and leap years
max_days=days_in_month[tolower(date[2])]
if (month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)){      #  change max day for leap year
	max_days=29
}
	if (day>max_days) {
		day="UNKNOWN"
	}
}

if ($3 ~ /^[0-9]+$/ && length($3) <= 4){      #  zero pad time
	padded_time=$3
	while (length(padded_time)<4) {
		padded_time= "0"padded_time
		}
	if (padded_time ~ TIME_TARGET) {
		time=padded_time
	}
}

issues=""      #  output for log
separator=""
if (year == "UNKNOWN")      { issues=issues separator "YEAR_UNKNOWN"; separator="|" }
if (month == "UNKNOWN")      { issues=issues separator "MONTH_UNKNOWN"; separator="|" }
if (day == "UNKNOWN")      { issues=issues separator "DAY_UNKNOWN"; separator="|" }
if (time == "UNKNOWN")      { issues=issues separator "TIME_UNKNOWN"; separator="|" }

print $0, year, month, day, time

if (issues != "")      {print $0, year, month, day, time, issues >> BAD_ROWS} 

} ' "$WORK" > "$TEMP"

NUMFIELDS=$(awk -F',' '{print NF}' "$TEMP" | sort -u)
echo "--- Distinct Field Counts (Want 13) ---"
awk -F',' '{print NF}' "$TEMP" | sort | uniq -c

if [ "$NUMFIELDS" -eq 13 ]; then      #  validate for correct number of fields
	echo "PASS"
mv "$TEMP" "$OUT"
	rm -f "$WORK" "$TEMP"
RESULT=PASS
else
	echo "FAIL: Incorrect number of fields"
	echo "FAIL: Incorrect number of fields" >&2
fi

echo; echo "--- Diagnostics ---"
ROWS_IN=$(awk 'END{print NR-1}' "$IN")
ROWS_BAD=$(awk 'END{print NR-1}' "$BAD_ROWS")
echo "Total rows: $ROWS_IN"
echo "Rows with an unknown date or time: $ROWS_BAD"

echo; echo "--- Rows with issues (DR_NO: Issues)---"
if [ "$ROWS_BAD" -gt 0 ]; then
	if [ "$ROWS_BAD" -gt 10 ]; then
		awk -F"," 'NR>1 {print $1": "$14}' "$BAD_ROWS" | head -10 || true
		echo "..."
		echo "+$((ROWS_BAD-10)) more"
	else
		awk -F"," 'NR>1 {print $1": "$14}' "$BAD_ROWS"
	fi
else
	echo "No rows with unknown date/time"
fi


} > "$LOG/02_clean.log" 2>> "$LOG/err.log"

if [ "$RESULT" =  "PASS" ]; then     
echo "Cleaning part 2 done. See $OUT"
else
	echo "Error. See ${LOG}err.log"
	exit 1
fi
