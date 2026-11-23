# CS 131, Eric's initial crime analysis stage

## What this work adds

`analyze.sh` is an independent first-pass analysis of the 2020-2023 subset of LAPD crime data. It operates on the **13-column cleaned file** written by Frank's `scripts/02_clean.sh`, not on the raw instructor-provided CSV.

Default input: `data/interim/02_clean_crimes.csv`

Default output folder: `output/analysis/`

Outputs:
- `yearly.tsv`: annual count and percentage change from preceding year
- `monthly.tsv`: total for each calendar month across 2020-2023 (not a monthly time series)
- `hourly.tsv`: total for each local reported hour across 2020-2023
- `top_areas.tsv`: top 10 LAPD police-area names by record count
- `top_crime_types.tsv`: top 10 reported offense descriptions by count
- `summary.tsv`: analysis denominators and excluded/missing-value counts
- `run_log.tsv`: input and malformed row totals
- `rejected_rows.tsv`: line numbers/IDs for records with an unexpected number of fields

## Data decisions and limits

- Analyze occurrences in 2020-2023, not report dates. 2024 is excluded from this analysis deliberately.
- Count one *record* as one reported crime-data record. This is not a claim that every event has one unique victim or offense.
- An unknown month or hour excludes the record only from the corresponding monthly or hourly report. A known year can still contribute to the annual total.
- The area's name represents an LAPD policing area, not necessarily a city neighborhood.
- Raw quoted CSV is **not** supported as input. Frank's cleaning stage is responsible for delivering comma-safe, one-line records without embedded commas. The fact that Frank replaced commas within quoted fields with `|` should be documented and reviewed for fidelity.
- No deduplication is applied here. Duplicate `DR_NO` validation should be agreed upon with the inspection/cleaning teammates.
- Counts are descriptive and not adjusted for resident population, reporting frequency, or the unequal sizes of policing areas.
- No claims about causes of crime trends, true danger, or solved crimes follow from these counts alone.

## Run locally (WSL/Linux Bash)

From the repository root:

```bash
bash analyze.sh
bash tests/test_analyze.sh
```

To test the sample without the full dataset:

```bash
bash analyze.sh tests/fixtures/clean_crimes_sample.csv output/analysis-sample
```

Optional input and output paths:

```bash
bash analyze.sh /path/to/02_clean_crimes.csv /path/to/reports
```

## Class tools exercised

Bash `set -euo pipefail`, command arguments, checking file readability, stderr errors, safe temporary directory with `mktemp` and `trap`, `awk` field selection/conditions/arrays/`END`, `sort` numeric keys, `head`, `wc` concepts, output redirection and deterministic report creation.

## Integration to check with the team

1. Frank must confirm that the cleaned file continues to have these 13 exact columns.
2. All `.sh` files should use LF, not Windows CRLF, line endings.
3. The master `run.sh` (another teammate's responsibility) should call `analyze.sh` only after successful cleaning.
4. The instructor's altered dataset must be the final analysis input. Do not substitute the public portal file for grading.
5. Compare final yearly counts to an independent calculation on the cleaned dataset.
