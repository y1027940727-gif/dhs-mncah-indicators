# DHS MNCAH indicator pipeline: fetch -> clean -> quality checks -> visualize
# Data: DHS Program public indicator API (https://api.dhsprogram.com), no login needed.
# Run from the project folder:  Rscript dhs_mncah_indicators.R

required <- c("jsonlite", "dplyr", "purrr", "readr", "tibble", "ggplot2")
to_install <- setdiff(required, rownames(installed.packages()))
if (length(to_install)) install.packages(to_install)
invisible(lapply(required, library, character.only = TRUE))

# ---- 1. Settings ------------------------------------------------------------
countries  <- c("KE", "SL", "ML", "SO")   # Kenya, Sierra Leone, Mali, Somalia (edit freely)
indicators <- c(
  DPT3 = "CH_VACC_C_DP3",   # Children with DPT3 vaccination (%)
  ANC4 = "RH_ANCN_W_N4P",   # Women with 4+ antenatal care visits (%)
  U5MR = "CM_ECMR_C_U5M"    # Under-5 mortality rate (per 1,000 live births)
)
dir.create("data/raw",   recursive = TRUE, showWarnings = FALSE)
dir.create("data/clean", recursive = TRUE, showWarnings = FALSE)
dir.create("output",     recursive = TRUE, showWarnings = FALSE)

# ---- 2. Fetch from the DHS API ----------------------------------------------
fetch_indicator <- function(ind_id) {
  url <- paste0(
    "https://api.dhsprogram.com/rest/dhs/data?indicatorIds=", ind_id,
    "&countryIds=", paste(countries, collapse = ","),
    "&breakdown=national&perpage=1000&f=json"
  )
  res <- tryCatch(jsonlite::fromJSON(url), error = function(e) {
    message("Request failed for ", ind_id, ": ", conditionMessage(e)); NULL
  })
  if (is.null(res) || length(res$Data) == 0) {
    message("No data returned for ", ind_id); return(tibble::tibble())
  }
  # Force every column to character so results from different indicators can be bound together
  tibble::as_tibble(res$Data) |>
    dplyr::mutate(dplyr::across(dplyr::everything(), ~ as.character(.x)))
}
raw <- purrr::map_dfr(indicators, fetch_indicator)
if (nrow(raw) == 0) stop("No data downloaded. Check your internet connection and the indicator IDs.")
readr::write_csv(raw, "data/raw/dhs_raw.csv")

# ---- 3. Clean ---------------------------------------------------------------
keep <- c("CountryName", "DHS_CountryCode", "SurveyId", "SurveyYear", "IndicatorId",
          "Indicator", "ByVariableLabel", "Value", "CILow", "CIHigh", "DenominatorWeighted")
clean <- raw |>
  dplyr::select(dplyr::any_of(keep)) |>
  dplyr::mutate(dplyr::across(dplyr::any_of(
    c("SurveyYear", "Value", "CILow", "CIHigh", "DenominatorWeighted")), as.numeric)) |>
  dplyr::distinct()

# DHS reports some indicators for several recall periods per survey (e.g. births in the
# last 2, 3 or 5 years). Mixing them would give several points per survey and break trends,
# so keep ONE reference period per indicator. This is a methodological choice: edit it here.
#   - Under-5 mortality: the 5 years before the survey (standard DHS reporting period)
#   - ANC 4+ visits: births in the 2 years before the survey (older surveys that only report
#     other periods drop out; check the README note)
#   - DPT3: no recall period
period_pattern <- c(CH_VACC_C_DP3 = "", RH_ANCN_W_N4P = "^Two years", CM_ECMR_C_U5M = "^Five years")
n_before <- nrow(clean)
keep_row <- mapply(function(id, lab) grepl(period_pattern[[id]], lab),
                   clean$IndicatorId, clean$ByVariableLabel)
clean <- clean[unname(keep_row), ]
rows_removed_by_period_filter <- n_before - nrow(clean)

# Countries that were requested but returned nothing
returned <- unique(clean$DHS_CountryCode)
missing_countries <- setdiff(countries, returned)
if (length(missing_countries)) message("No data for: ", paste(missing_countries, collapse = ", "))

# ---- 4. Data quality checks -------------------------------------------------
checked <- clean |>
  dplyr::mutate(
    flag_missing_value   = is.na(Value),
    flag_ci_inconsistent = !is.na(CILow) & !is.na(CIHigh) & !is.na(Value) &
                           !(CILow <= Value & Value <= CIHigh),
    flag_out_of_range    = !is.na(Value) & IndicatorId != "CM_ECMR_C_U5M" &
                           (Value < 0 | Value > 100),
    flag_small_denom     = !is.na(DenominatorWeighted) & DenominatorWeighted < 300
  )
dup_n <- sum(duplicated(checked[, c("SurveyId", "IndicatorId")]))

qc_summary <- checked |>
  dplyr::summarise(
    rows = dplyr::n(), rows_removed_by_period_filter = rows_removed_by_period_filter,
    duplicated_survey_indicator = dup_n,
    missing_value = sum(flag_missing_value), ci_inconsistent = sum(flag_ci_inconsistent),
    out_of_range = sum(flag_out_of_range), small_denominator = sum(flag_small_denom)
  )
print(qc_summary)
readr::write_csv(qc_summary, "output/qc_summary.csv")
readr::write_csv(checked,    "data/clean/dhs_clean.csv")

# ---- 5. Visualize -----------------------------------------------------------
plot_data <- dplyr::filter(checked, !flag_missing_value, !flag_out_of_range)
p <- ggplot2::ggplot(plot_data,
       ggplot2::aes(SurveyYear, Value, colour = CountryName, group = CountryName)) +
  ggplot2::geom_line() +
  ggplot2::geom_point() +
  ggplot2::geom_errorbar(ggplot2::aes(ymin = CILow, ymax = CIHigh), width = 0.4, alpha = 0.5) +
  ggplot2::facet_wrap(~Indicator, scales = "free_y", ncol = 1,
                      labeller = ggplot2::label_wrap_gen(60)) +
  ggplot2::labs(title = "MNCAH indicators from DHS surveys",
                subtitle = "National estimates with 95% confidence intervals",
                x = "Survey year", y = NULL, colour = NULL,
                caption = "Source: DHS Program API") +
  ggplot2::theme_minimal(base_size = 11) +
  ggplot2::theme(legend.position = "bottom")
print(p)
ggplot2::ggsave("output/mncah_trends.png", p, width = 8, height = 10, dpi = 150)
message("Done. See data/clean/, output/qc_summary.csv and output/mncah_trends.png")
