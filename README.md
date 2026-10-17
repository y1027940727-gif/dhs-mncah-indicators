# DHS MNCAH indicators: a small reproducible R pipeline

Downloads national-level maternal, newborn and child health indicators from the
public DHS Program API, cleans them, runs basic data quality checks, and plots
trends by country with confidence intervals.

## Indicators
| Code | Indicator |
|---|---|
| CH_VACC_C_DP3 | Children with DPT3 vaccination (%) |
| RH_ANCN_W_N4P | Women with 4+ antenatal care visits (%) |
| CM_ECMR_C_U5M | Under-5 mortality rate (per 1,000 live births) |

## Run
```
Rscript dhs_mncah_indicators.R
```
Edit `countries` and `indicators` at the top of the script to change the scope.

## Outputs
- `data/raw/dhs_raw.csv`: raw API response
- `data/clean/dhs_clean.csv`: cleaned data with quality flags
- `output/qc_summary.csv`: counts of missing values, inconsistent CIs, out-of-range values, small denominators, duplicates
- `output/mncah_trends.png`: trend plot

## Data quality finding
The first run flagged 49 duplicated survey-indicator rows. Cause: DHS reports some indicators for several recall periods per survey (e.g. 2, 3 or 5 years before the survey). The script keeps one period per indicator so trends are comparable (see `period_pattern`); the number of rows removed is reported in `output/qc_summary.csv`. Older surveys that report ANC4+ only for a different period do not appear in the plot.

## Scope and limits
Training project using aggregated survey indicators, not microdata, and not DHIS2.
Not every requested country has a DHS survey for every indicator; the script reports what is missing.
