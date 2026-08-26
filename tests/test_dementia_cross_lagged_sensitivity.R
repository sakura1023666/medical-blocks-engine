# tests/test_dementia_cross_lagged_sensitivity.R
source("R/utils.R", local = FALSE)
source("R/cross_lagged_sensitivity.R", local = FALSE)

bn <- cross_lagged_sens_table_basename(
  "exclude_chronic_ge2", "logistic", "ELSA",
  index_display = "Leisure_activities", disease_display = "Dementia"
)
stopifnot(grepl("Leisure_activities and Dementia", bn, fixed = TRUE))
stopifnot(grepl("Table S10-ELSA", bn, fixed = TRUE))
stopifnot(!grepl("FI and Hip", bn, fixed = TRUE))

df <- data.frame(Disease = c("Dementia", "Normal", "Dementia"), stringsAsFactors = FALSE)
out <- cross_lagged_sens_normalize_disease_group(df)
stopifnot(identical(as.character(out$Disease_Group), c("Dementia", "Normal", "Dementia")))
cat("Task1 tests OK\n")

# --- Task 2: Dementia data loaders ---
study <- "/mnt/g/02block_result/20_Dementia/cross-laged_40595747"

imp <- cross_lagged_sens_load_imputed(study, "ELSA")
stopifnot(nrow(imp) == 5049L)
stopifnot("Leisure_activities" %in% names(imp))
stopifnot("Disease_Group" %in% names(imp))

dab <- cross_lagged_sens_load_dabiao(study, "ELSA")
stopifnot(nrow(dab) == nrow(imp) || nrow(dab) > 0L)
stopifnot("Disease_Group" %in% names(dab))

pack <- cross_lagged_sens_load_long(study, "ELSA")
stopifnot(!is.null(pack$wide) || !is.null(pack$long_all))
stopifnot(!is.null(pack$long_all))
stopifnot(!is.null(pack$wide))

expected_n <- c(CLHLS = 1032L, SHARE = 14682L, HRS = 5361L, ELSA = 5049L)
for (db in names(expected_n)) {
  d <- cross_lagged_sens_load_imputed(study, db)
  stopifnot(nrow(d) == expected_n[[db]])
  cat(db, nrow(d), "\n")
}

cat("Task2 loader tests OK\n")

# --- Task 3: logistic tertile cut (T1/T2/T3, right=FALSE) ---
register_block <- function(...) invisible(NULL)
source("Blocks/11_logistic/05block_logistic_tertile_glm.R", local = FALSE)

x <- c(1, 2, 3, 4, 5, 6, 7, 8, 9)
qs <- as.numeric(quantile(x, probs = c(1 / 3, 2 / 3)))
g_main <- cut(
  x,
  breaks = c(-Inf, qs[1], qs[2], Inf),
  labels = c("T1", "T2", "T3"),
  right = FALSE,
  include.lowest = TRUE
)
g_block <- cut(
  x,
  breaks = c(-Inf, qs, Inf),
  labels = c("Q1", "Q2", "Q3"),
  right = TRUE
)
stopifnot(is.factor(g_main))

tert_main <- .lqg05_tertile_from_cfg(
  x,
  list(tertile_right = FALSE, tertile_labels = c("T1", "T2", "T3"))
)
stopifnot(identical(as.character(tert_main$group), as.character(g_main)))
stopifnot(identical(levels(tert_main$group), c("T1", "T2", "T3")))
stopifnot(grepl("-<", tert_main$cutoffs[["T2"]], fixed = TRUE))

tert_default <- .lqg05_tertile_from_cfg(x, list())
stopifnot(identical(levels(tert_default$group), c("Q1", "Q2", "Q3")))
stopifnot(identical(as.character(tert_default$group), as.character(g_block)))

tert_empty_cfg <- .lqg05_tertile_from_cfg(x, list(tertile_right = NULL))
stopifnot(identical(levels(tert_empty_cfg$group), c("Q1", "Q2", "Q3")))

cat("Task3 tertile cut tests OK\n")

# --- Fix after Task4: Dementia Change wide prep (ID + T2_Disease) ---
pack_ch <- cross_lagged_sens_load_long(study, "ELSA")
w_ch <- pack_ch$wide
stopifnot(!is.null(w_ch))
stopifnot(nrow(w_ch) == 3038L)
stopifnot("ID" %in% names(w_ch))
stopifnot("T1_le" %in% names(w_ch), "T2_le" %in% names(w_ch))
stopifnot("T2_Disease" %in% names(w_ch) || "T2_Disease_Group" %in% names(w_ch))
if ("T2_Disease" %in% names(w_ch)) {
  stopifnot(all(as.character(unique(stats::na.omit(w_ch$T2_Disease))) %in%
                  c("Normal", "Dementia")))
}
if ("T2_Disease_Group" %in% names(w_ch)) {
  stopifnot(all(as.character(unique(stats::na.omit(w_ch$T2_Disease_Group))) %in%
                  c("Normal", "Dementia")))
}
# ID 来自 long wave1 行对齐
if (!is.null(pack_ch$long_all) && "wave" %in% names(pack_ch$long_all)) {
  lw1 <- pack_ch$long_all[as.integer(pack_ch$long_all$wave) == 1L, , drop = FALSE]
  stopifnot(nrow(lw1) == nrow(w_ch))
  stopifnot(identical(as.character(w_ch$ID), as.character(lw1$ID)))
}
cat("Change wide prep tests OK\n")

# --- Task 5: dementia wave years + early-event long ---
stopifnot(cross_lagged_sens_dementia_wave_years("HRS")$baseline == 2010L)
stopifnot(identical(cross_lagged_sens_dementia_wave_years("ELSA")$fu, 2014L))
stopifnot(cross_lagged_sens_dementia_wave_years("SHARE")$baseline == 2015L)
stopifnot(identical(
  cross_lagged_sens_dementia_wave_years("CLHLS")$fu, c(2012L, 2014L)
))
pack_ev <- cross_lagged_sens_load_long(study, "ELSA")
stopifnot(!is.null(pack_ev$long_all))
stopifnot(any(c("year", "Year") %in% names(pack_ev$long_all)))
stopifnot(any(c("Disease", "Disease_Group") %in% names(pack_ev$long_all)))
wy_elsa <- cross_lagged_sens_dementia_wave_years("ELSA")
early_elsa <- cross_lagged_sens_ids_early_event(
  pack_ev$long_all,
  within_years = 2L,
  baseline_year = wy_elsa$baseline
)
stopifnot(is.character(early_elsa))
cat("Task5 wave years + early-event tests OK\n")
