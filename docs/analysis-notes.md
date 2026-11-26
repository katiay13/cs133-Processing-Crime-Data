# Eric's CS 131 crime analysis (2020-2023)

## Integration status (updated after comparing all five branch ZIPs)

This is Eric's analysis contribution. Run it on the normalized **15-column** file
produced by Kenny's `scripts/03_clean.sh`, after Frank's `scripts/01_clean.sh`
and `scripts/02_clean.sh`:

```text
data/raw/crimes.csv
  -> bash scripts/01_clean.sh  -> data/interim/01_unquoted_crimes.csv
  -> bash scripts/02_clean.sh  -> data/interim/02_clean_crimes.csv
  -> bash scripts/03_clean.sh  -> data/interim/03_clean_crimes.csv
  -> bash analyze.sh           -> output/analysis/*.tsv
```

The `03_clean.sh` file is on Kenny's branch in the provided snapshots. Do not
copy teammates' scripts into your branch without coordinating the merge. For
now, the analysis tests run independently using a synthetic 15-column fixture.

### Exact input contract

| # | Column | Used for |
|---|---|---|
| 1 | DR_NO | audit of unusually formatted IDs |
| 2 | DATE OCC | preserved source occurrence date |
| 3 | TIME OCC | preserved original time |
| 4 | AREA NAME | police-area comparisons |
| 5 | Crm Cd Desc | top offense types |
| 6 | Weapon Used Cd | code-present proxy |
| 7 | Weapon Desc | inconsistency audit |
| 8 | Status | preserved source status |
| 9 | Status Desc | preserved source description |
| 10 | YEAR OCC | 2020-2023 filter |
| 11 | MONTH OCC | calendar month and timeline |
| 12 | DAY OCC | preserved normalized day |
| 13 | CLEAN TIME OCC | HHMM hour of occurrence |
| 14 | CLEAN STATUS | AA/JA arrest counts |
| 15 | CLEAN STATUS DESC | preserved normalized status description |

The script rejects a different header or an unreadable input. Rows with a
non-15 field count are counted in `rejected_rows.tsv` and omitted from analysis;
all other rows are passed through, with unknown values counted separately.

### Generated files

| File | Purpose |
|---|---|
| `yearly.tsv` | 2020-2023 counts and year-over-year percentage changes |
| `monthly.tsv` | Jan-Dec counts aggregated across all four years |
| `year_month.tsv` | 48 chronological year-month counts for finding actual monthly peaks |
| `hourly.tsv` | Occurrence counts by 24-hour time (unknown times excluded) |
| `top_areas.tsv` | 10 LAPD areas with the most reported records |
| `top_crime_types.tsv` | 10 most frequent offense descriptions |
| `area_metrics.tsv` | Area counts, weapon-code presence and AA/JA arrest percentages |
| `top_area_peak_hours.tsv` | Most frequent valid occurrence hour in each top-ten area |
| `status_counts.tsv` | Records per normalized status code |
| `summary.tsv` | Included/excluded row counts and quality diagnostics |
| `rejected_rows.tsv` | Source line numbers of structurally malformed 15-column rows |
| `run_log.tsv` | Source path, input/rejected totals and assumptions |

### Important interpretation rules

- Study occurrence years **2020 through 2023**, not report dates. 2024 is
  deliberately excluded from the analysis.
- Annual area counts represent *reported crime records*, not unique incidents
  proven after deduplication. These are not population-adjusted risk rates.
- `CLEAN STATUS` values `AA` and `JA` indicate **adult arrest** and **juvenile
  arrest** respectively. This is an *arrest-recorded proportion*, not a solved
  case or conviction rate. `AO`, `IC`, `JO` are known non-arrest statuses.
  `CC` is the unknown fallback from the provided `02_clean.sh`; `UNK` is also
  treated as unknown. `area_metrics.tsv` reports percent of **all** area rows
  and, separately, percent among **known-status** area rows.
- `Weapon Used Cd` nonblank is only **weapon-code presence**. It may include
  bodily force or classifications that are not a physical weapon. Conversely,
  a blank code is not evidence that no weapon was involved. We do not label
  this a verified weapon-involvement or danger rate.
- Missing month and time exclude a record only from that particular breakdown,
  while a valid year still contributes to the annual count.
- A police area is not the same as a neighborhood. Raw frequency is influenced
  by area size, policing, and reporting. No causal inference is warranted.
- Tied area/crime totals sort alphabetically. Tied peak hours select the
  earliest hour. Status unknown rows are retained in overall totals.
- Commas inside quoted fields were converted to `|` by the upstream cleaning
  script. This `awk -F,` analysis therefore **must not** read the original
  28-column quoted CSV.

### Outstanding integration question: duplicates and DR_NO

Katia's latest uploaded inspection log reports **2,965 extra rows** that are
identical across all raw columns except `DR_NO`, across 2,357 groups, plus
**five** four-digit `DR_NO` values. These figures are inspection findings,
not evidence that all duplicates are erroneous. The group discussed rejecting
them, but the uploaded `01_clean.sh`, `02_clean.sh` and `03_clean.sh` do not
implement this deduplication or ID rejection. In particular, `03_clean.sh`
rejects only incorrect field-count rows, and *flags* (keeps) other anomalies.

**Do not remove rows again inside `analyze.sh`.** Coordinate with the cleaning
team to apply any agreed rule upstream on the original full-width records,
*before dropping fields*, with a rejected-rows file and documented rationale.
Dropping duplicates after the initial 9-column selection could mistakenly
collapse distinct incidents sharing only those selected attributes. When
upstream cleaning changes, rerun these summaries and reconcile counts.

## Run and test in VS Code Ubuntu/WSL

From the repository root:

```bash
bash tests/test_analyze.sh
bash analyze.sh
ls -lh output/analysis/
column -t -s $'\t' output/analysis/top_areas.tsv
column -t -s $'\t' output/analysis/area_metrics.tsv
```

To run on any already-produced 15-column normalized file:

```bash
bash analyze.sh /path/to/03_clean_crimes.csv /path/to/output/analysis
```

The automated tests use entirely **synthetic data**. They do not validate
actual LA crime totals. Before final report submission, run the complete
teammate cleaning sequence on the *instructor-provided modified CSV*, inspect
all cleaning logs, and reconcile actual input, retained, and rejected counts.

## Course tools used

Bash `set -euo pipefail`, parameter defaults, input/schema checks, exit codes,
stdout/stderr, `mktemp` and `trap`, `awk` conditions and grouped arrays, `sort`
numeric ranking, pipelines, TSV output redirection, `diff` regression tests,
and rerunnable deterministic reports.
