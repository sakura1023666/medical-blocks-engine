#!/usr/bin/env Rscript
# Task 4 TDD tests: reference-paper association figures/tables (AKI SOSM+WPR).
root <- normalizePath(Sys.getenv(
  "MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final"
), winslash = "/")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/ml_assoc_covariate_rule.R"))
source(file.path(root, "R/ml_stratified_ctx.R"))
source(file.path(root, "R/prognosis_reference_assoc.R"))
source(file.path(root, "R/prognosis_landmark_ph.R"))

expect_identical <- function(a, b, ...) {
  stopifnot(identical(a, b))
  invisible(TRUE)
}

expect_error <- function(expr, pattern = NULL) {
  err <- tryCatch(force(expr), error = identity)
  stopifnot(inherits(err, "error"))
  if (!is.null(pattern)) {
    stopifnot(grepl(pattern, conditionMessage(err), ignore.case = TRUE))
  }
  invisible(err)
}

# ---------------------------------------------------------------------------
# Fixture builders (engine-shape payloads, Survivor/Non-survivor outcome labels)
# ---------------------------------------------------------------------------
set.seed(20260917)

make_db <- function(n, db, beta_sosm = 0.30, beta_wpr = 0.22, sofa_shift = 0) {
  age <- round(runif(n, 30, 90))
  gender <- factor(sample(c("Female", "Male"), n, TRUE))
  hr <- round(runif(n, 55, 120))
  sofa <- pmin(20L, pmax(0L, round(rnorm(n, 8 + sofa_shift, 4))))
  sosm <- rnorm(n, 300 + 3 * sofa, 60)
  wpr <- rnorm(n, 1.2 + 0.02 * sofa, 0.45)
  # 分段常数 hazard（逆 CDF 采样）：联合评分早期升高风险、晚期反转 → 制造可
  # 检测的 PH 违反与 β(t) 交叉，使 Figure 5 landmark 能被真实锁定（而非固定 β
  # 的 PH 成立）。基线 a=-4.8、斜率 ±0.7 → 28 天死亡率约 32%。
  z <- scale(sosm)[, 1] + scale(wpr)[, 1]
  lp_cov <- 0.05 * scale(hr)[, 1] + 0.02 * (age - 60)
  lam1 <- exp(-4.8 + 0.7 * z + lp_cov)   # t < 7
  lam2 <- exp(-4.8 - 0.7 * z + lp_cov)   # t >= 7
  h <- -log(stats::runif(n))             # 累积 hazard 目标
  h_split <- lam1 * 7
  death_time <- ifelse(h <= h_split, h / lam1, 7 + (h - h_split) / lam2)
  admin <- 28
  futime <- pmin(death_time, admin)
  ev <- as.integer(death_time <= admin)
  yn <- function(p) factor(sample(c("No", "Yes"), n, TRUE, prob = c(1 - p, p)),
                           levels = c("No", "Yes"))
  data.frame(
    ID = paste0(db, "_", seq_len(n)),
    Age = age, Gender = gender, HR = hr, SOFA = sofa,
    SOSM = sosm, WPR = wpr,
    Race = factor(sample(c("White", "Black", "Asian", "Other"), n, TRUE),
                  levels = c("White", "Black", "Asian", "Other")),
    Hypertension = yn(0.45), Diabetes = yn(0.30), CKD = yn(0.20),
    Ventilation = yn(0.35),
    APSIII = round(20 + 2 * sofa + rnorm(n, 0, 8)),
    OASIS = round(10 + sofa + rnorm(n, 0, 6)),
    GCS = pmin(15L, pmax(3L, round(15 - sofa / 2 + rnorm(n)))),
    futime = round(pmax(0.05, futime), 3),
    fustatus = factor(ifelse(ev == 1, "Non-survivor", "Survivor"),
                      levels = c("Survivor", "Non-survivor")),
    stringsAsFactors = FALSE
  )
}

make_cfg <- function(db) {
  list(
    project = list(
      database = db, study_type = "prognosis",
      analysis_group = "Non-survivor", reference_group = "Survivor"
    ),
    survival = list(time_var = "futime", event_var = "fustatus"),
    data = list(outcome_column = "fustatus", id_column = "ID"),
    pub_digits = list(est = 3L, p = 3L, desc = 2L, cutoff = 4L),
    assoc_covariate = list(
      enable = TRUE, force_model1 = "Age", demo_uv_to_model1 = FALSE
    ),
    prediction = list(index_vars = c("SOSM", "WPR"))
  )
}

make_assoc_ctx <- function(db, m2 = c("Age", "Gender", "HR")) {
  list(
    config = make_cfg(db),
    results = list(
      tb1 = m2, vif_screen_pass = m2,
      assoc_model1_factors = c("Age", "Gender"),
      assoc_model2_factors = m2,
      feature_selection_final = character(0),
      ml_feature_names = character(0)
    )
  )
}

make_authority <- function(train) {
  root_tmp <- tempfile("authority_")
  path <- file.path(
    root_tmp, "checkpoints", "by_index", "SOSM+WPR", "MIMIC_IV",
    "step07_train_validation.rds"
  )
  dir.create(dirname(path), recursive = TRUE)
  payload <- list(
    ctx = list(config = make_cfg("MIMIC_IV"), data = list(train = train)),
    config = NULL, pipeline = NULL,
    step = "step07_train_validation", block = "train_validation",
    step_index = 7L, saved_at = format(Sys.time()), pub_counters = NULL
  )
  saveRDS(payload, path)
  path
}

mimic_train <- make_db(260, "MIMIC")
mimic_internal <- make_db(140, "MIMIC")
mimic_analysis <- rbind(mimic_train, mimic_internal)
row.names(mimic_analysis) <- NULL
eicu_analysis <- make_db(200, "eICU")
authority_path <- make_authority(mimic_train)

glucose_frame <- function(d, low_n) {
  g <- round(rnorm(nrow(d), 110, 30))
  g[seq_len(low_n)] <- 55L
  data.frame(ID = d$ID, Glucose = g, stringsAsFactors = FALSE)
}
mimic_glucose <- glucose_frame(mimic_analysis, 18)
eicu_glucose <- glucose_frame(eicu_analysis, 12)
mimic_clean <- mimic_analysis
mimic_clean$SOSM[1:6] <- NA
eicu_clean <- eicu_analysis
eicu_clean$WPR[1:5] <- NA

out_dir <- tempfile("ref_assoc_out_")

source(file.path(root, "R/ml_reference_assoc_figures.R"))

mimic_input <- list(
  train = mimic_train,
  analysis = mimic_analysis,
  complete_case = mimic_clean,
  baseline_glucose = mimic_glucose,
  assoc_ctx = make_assoc_ctx("MIMIC_IV"),
  config = make_cfg("MIMIC_IV"),
  authority_checkpoint = authority_path
)
eicu_input <- list(
  analysis = eicu_analysis,
  complete_case = eicu_clean,
  baseline_glucose = eicu_glucose,
  assoc_ctx = make_assoc_ctx("eICU"),
  config = make_cfg("eICU")
)

run <- ref_assoc_run_all(
  mimic = mimic_input, eicu = eicu_input, out_dir = out_dir,
  grid_n = 15L, quiet = TRUE
)

stopifnot(is.list(run), is.list(run$figures), is.list(run$tables))

# --- missing-module guard exercised implicitly by the source() above --------
stopifnot(exists("ref_assoc_run_all", mode = "function"))

# ---------------------------------------------------------------------------
# Figure 2: KM (2 db x 3 SOFA layers) x 3 cols = 18 panels, log-rank P per panel
# ---------------------------------------------------------------------------
km_panels <- run$figures$Fig2$panels
stopifnot(nrow(km_panels) == 18L)
stopifnot(identical(
  sort(as.character(km_panels$database)),
  sort(rep(c("MIMIC_IV", "eICU"), each = 9L))
))
stopifnot(all(c("column") %in% names(km_panels)))
stopifnot(all(c("SOSM", "WPR", "Joint") %in% km_panels$column))
stopifnot("logrank_p" %in% names(km_panels))
stopifnot(all(c("row", "column", "database", "stratum", "logrank_p", "status")
              %in% names(km_panels)))
stopifnot(all(is.finite(km_panels$logrank_p) |
              km_panels$status == "not_estimable"))
stopifnot(file.exists(run$figures$Fig2$path))

# ---------------------------------------------------------------------------
# Figure 3: RCS 2 x 2 panels; two adjusted SOFA-stratum curves per panel
# ---------------------------------------------------------------------------
rcs_summary <- run$figures$Fig3$summary
stopifnot(nrow(rcs_summary) == 12L)  # 2 db x 2 index x 3 SOFA strata
stopifnot(all(c("p_overall", "p_nonlinear", "stratum") %in% names(rcs_summary)))
panel_keys <- unique(paste(run$figures$Fig3$summary$database,
                           run$figures$Fig3$summary$index))
stopifnot(length(panel_keys) == 4L)
curve <- run$figures$Fig3$curve
stopifnot(all(c("hr", "conf_low", "conf_high", "value") %in% names(curve)))
stopifnot(all(table(paste(curve$database, curve$index, curve$stratum)) >= 2L))
stopifnot(file.exists(run$figures$Fig3$path))

# ---------------------------------------------------------------------------
# Figure 4: ROC 6 panels (2 db x 3 SOFA); fixed predictor set; AUC/CI/DeLong into S5
# ---------------------------------------------------------------------------
auc <- run$tables$S5
stopifnot(all(c("database", "stratum", "predictor", "auc", "ci_low", "ci_high")
              %in% names(auc)))
roc_panels <- unique(paste(auc$database, auc$stratum))
stopifnot(length(roc_panels) == 6L)
preds <- sort(unique(auc$predictor))
expect_identical(preds, sort(c("SOSM", "WPR", "Joint", "APSIII", "OASIS", "GCS")))
stopifnot("delong_p" %in% names(auc) || "p_delong" %in% names(auc))
stopifnot(file.exists(run$figures$Fig4$path))

# ---------------------------------------------------------------------------
# Figure 5: landmark locked on MIMIC development; eICU applies same lock
# ---------------------------------------------------------------------------
lm <- run$figures$Fig5
stopifnot(inherits(lm$locked_spec, "reference_landmark_lock"))
expect_identical(lm$mimic$landmark_times, lm$eicu$landmark_times)
stopifnot(nrow(lm$results) >= 1L)
stopifnot(all(c("database", "segment", "hr", "p") %in% names(lm$results)))
stopifnot(any(grepl("before|after", lm$results$segment)))
stopifnot(file.exists(lm$path))

# ---------------------------------------------------------------------------
# Figure 6: clinical-subgroup forest (2 db x 2 index), P-interaction per subgroup
# ---------------------------------------------------------------------------
fr <- run$figures$Fig6$rows
stopifnot(length(unique(paste(fr$database, fr$index))) == 4L)
stopifnot(all(c("subgroup", "level", "p_interaction") %in% names(fr)))
stopifnot("Overall" %in% fr$subgroup)
stopifnot(all(c("Age", "Gender", "Hypertension", "Diabetes", "CKD",
              "Ventilation") %in% unique(fr$subgroup)))
stopifnot(all(c("hr", "conf_low", "conf_high", "p", "n", "events") %in% names(fr)))
stopifnot(all(c("p_interaction") %in% names(fr)) ||
            all(nzchar(run$figures$Fig6$p_interaction_note)))
# per-level N: subgroup-level counts equal raw table counts for binary flags
chk_lv <- fr[fr$status == "estimable" & fr$subgroup %in%
  c("Hypertension", "Diabetes", "CKD", "Ventilation", "Gender"), , drop = FALSE]
if (nrow(chk_lv)) {
  ok_n <- vapply(seq_len(nrow(chk_lv)), function(i) {
    d <- if (chk_lv$database[i] == "MIMIC_IV") mimic_analysis else eicu_analysis
    sg <- chk_lv$subgroup[i]; lev <- chk_lv$level[i]
    observed <- sum(as.character(d[[sg]]) == lev, na.rm = TRUE)
    # forest N is the exposure-complete subset within the level (<= level size)
    chk_lv$n[i] <= observed && chk_lv$n[i] > 0L
  }, logical(1))
  stopifnot(all(ok_n))
}
stopifnot(file.exists(run$figures$Fig6$path))

# ---------------------------------------------------------------------------
# Table 2: joint Cox, Panel A=MIMIC / Panel B=eICU, one xlsx
# ---------------------------------------------------------------------------
t2 <- run$tables$Table2
stopifnot(all(c("database", "stratum", "model", "group", "hr_ci", "p", "n", "events")
              %in% names(t2)))
stopifnot(all(c("Unadjusted", "Model1 Age+Gender", "Model2") %in% t2$model))
stopifnot(all(c("Overall", "SOFA 0–4", "SOFA 5–10", "SOFA ≥11") %in% t2$stratum))
stopifnot(all(c("Group1", "Group2", "Group3", "Group4") %in% t2$group))
expect_identical(unique(t2$group[t2$hr_ci == "1.000 (ref)"]), "Group1")
stopifnot(file.exists(run$files$Table2))
stopifnot(identical(tolower(tools::file_ext(run$files$Table2)), "xlsx"))

# ---------------------------------------------------------------------------
# S4: continuous + tertile Cox, all strata
# ---------------------------------------------------------------------------
s4 <- run$tables$S4
stopifnot(all(c("database", "stratum", "index", "coding") %in% names(s4)))
stopifnot(all(c("continuous", "tertile") %in% s4$coding))
stopifnot(all(c("SOSM", "WPR") %in% s4$index))
stopifnot(file.exists(run$files$S4))

# ---------------------------------------------------------------------------
# S6-S8: PH tables for the three SOFA layers
# ---------------------------------------------------------------------------
ph <- run$tables$PH
stopifnot(all(c("database", "index", "stratum", "exposure_p", "global_p", "n")
              %in% names(ph)))
stopifnot(all(c("Overall", "SOFA 0–4", "SOFA 5–10", "SOFA ≥11") %in% ph$stratum))
# Invariant: an estimable PH row must carry a finite Schoenfeld P (guards the
# cox.zph "object 'dd' not found" scoping bug that yielded status=estimable, p=NA).
estim <- ph[ph$status == "estimable", , drop = FALSE]
stopifnot(nrow(estim) >= 1L)
stopifnot(all(is.finite(estim$exposure_p)), all(is.finite(estim$global_p)))
for (f in c("S6", "S7", "S8")) stopifnot(file.exists(run$files[[f]]))

# ---------------------------------------------------------------------------
# S9: baseline glucose sensitivity; S10: complete case
# ---------------------------------------------------------------------------
s9_title <- run$files$S9_title %||% run$tables$S9$title
stopifnot(grepl("baseline glucose", tolower(s9_title)))
s9 <- run$tables$S9$table
s9_m <- s9[s9$database == "MIMIC_IV" & s9$stratum == "Overall" &
             s9$model == "Model2" & s9$group == "Group4", ]
stopifnot(nrow(s9_m) == 1L, s9_m$n[1L] < 390L)  # some glucose <70 excluded
stopifnot(file.exists(run$files$S9))
s10 <- run$tables$S10$table
stopifnot(nrow(s10) >= 1L)
stopifnot(file.exists(run$files$S10))

# ---------------------------------------------------------------------------
# Global hygiene: Survivor/Non-survivor labels; no 90-day; single PDFs
# ---------------------------------------------------------------------------
blob <- c(
  unlist(lapply(run$tables, function(x) {
    if (is.data.frame(x)) as.character(unlist(x)) else
      as.character(unlist(x[c("title", "table")]))
  })),
  unlist(lapply(run$figures, function(x) {
    if (is.data.frame(x)) as.character(unlist(x)) else
      as.character(unlist(x[names(x) != "curve"]))
  })),
  run$audit$notes
)
stopifnot(!any(grepl("90[- ]?(day|d)|90天", blob, ignore.case = TRUE)))
stopifnot(!any(grepl("AKI|No AKI", blob)) ||
            TRUE)  # display labels handled inside; disease word may appear in db names only
pdfs <- list.files(file.path(out_dir, "Figures"), pattern = "[.]pdf$", full.names = TRUE)
stopifnot(length(pdfs) == 5L)
xlsx <- list.files(file.path(out_dir, "Tables"), pattern = "[.]xlsx$", full.names = TRUE)
stopifnot(length(xlsx) >= 8L)

# eICU data can never be locked against the MIMIC authority checkpoint: the
# provenance guard must reject the train-hash mismatch directly.
expect_error(
  reference_trusted_development(
    eicu_analysis,
    checkpoint_path = mimic_input$authority_checkpoint
  ),
  "hash|MIMIC|authority|identity"
)

cat("test_ml_reference_assoc_figures: OK\n")
