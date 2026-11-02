#!/usr/bin/env Rscript
# 修复 fmt_p 非向量化导致 S9/S10/S12 xlsx 的 P 列被回收成 Model1 的值。
# 从已有 checkpoint CSV 重导交付表，不重跑 Cox。
suppressPackageStartupMessages(library(data.table))
engine <- if (dir.exists("/mnt/e/01block/01Block-new-Final")) {
  "/mnt/e/01block/01Block-new-Final"
} else "E:/01block/01Block-new-Final"
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine, PV2_PROFILE = "sleep_dyslipidemia")
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "R/utils.R"), local = FALSE)
pv2_ensure_dirs()

fmt_p <- function(p) {
  p <- suppressWarnings(as.numeric(p))
  out <- character(length(p))
  for (i in seq_along(p)) {
    if (!is.finite(p[i])) out[i] <- ""
    else if (p[i] < 0.001) out[i] <- "<0.001"
    else out[i] <- sprintf("%.3f", p[i])
  }
  out
}

# restore checkpoints if pruned
.ws_ckpt <- function() {
  ws <- paste0(pv2_out_root, "_delivery_workspace")
  stamps <- if (dir.exists(ws)) list.dirs(ws, full.names = TRUE, recursive = FALSE) else character()
  stamps <- stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]
  for (d in c(file.path(stamps, "checkpoints"), stamps, pv2_ckpt_dir)) {
    if (file.exists(file.path(d, "Table S10. RCS cutoff Cox.csv"))) return(d)
  }
  pv2_ckpt_dir
}
ckpt <- .ws_ckpt()
tab_dir <- pv2_tab_dir
message("ckpt: ", ckpt)
message("tab_dir: ", tab_dir)

note <- pv2_artifact("Covariate_selection_note.txt", must_exist = FALSE)
if (is.na(note) || !file.exists(note)) {
  cand <- file.path(ckpt, "Covariate_selection_note.txt")
  if (file.exists(cand)) note <- cand
}
m3_cov <- if (!is.na(note) && file.exists(note)) {
  m3_line <- grep("^Model 3 =", readLines(note, warn = FALSE), value = TRUE)[1]
  trimws(strsplit(sub("^Model 3 =\\s*", "", m3_line), "\\s*\\+\\s*")[[1]])
} else c("Age", "Gender", "SBP", "Education", "Diabetes", "Hypertension", "Alcohol", "Smoke", "BMI")

# ---- S9 ----
s9 <- fread(file.path(ckpt, "Table S9. Extreme short sleep Cox.csv"), data.table = FALSE)
for (nm in unique(s9$database)) {
  sub <- s9[s9$database == nm, ]
  body <- data.frame(
    Contrast = sub$contrast, Model = sub$model,
    `N (deaths)` = sprintf("%d (%d)", sub$n, sub$deaths),
    `HR (95% CI)` = sub$`HR (95% CI)`, P = fmt_p(sub$P),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  stopifnot(length(unique(body$P)) >= 2 || nrow(body) < 2)
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S9-%s. Extreme short sleep and all-cause mortality.xlsx", nm)),
    title = "Table S9. Extreme short sleep (<5 h, <6 h) versus 7-<9 h and all-cause mortality",
    df_body = body,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Each contrast keeps the 7-<9 h reference group (sleep duration in [7, 9) hours) and participants below the short-sleep cut.",
      "The Model 1 was non-adjusted.",
      "The Model 2 was adjusted by: Age, Gender.",
      paste0("The Model 3 was adjusted by: ", paste(m3_cov, collapse = ", "), "."),
      "NHANES models are survey-weighted when applicable. CHARLS is validation only."
    )
  )
  message("S9 ", nm, " P: ", paste(body$P, collapse = " | "))
}

# ---- S10 ----
cut_df <- fread(file.path(ckpt, "Table S10. RCS cutoffs.csv"), data.table = FALSE)
s10 <- fread(file.path(ckpt, "Table S10. RCS cutoff Cox.csv"), data.table = FALSE)
for (nm in unique(cut_df$database)) {
  c1 <- cut_df[cut_df$database == nm, ]
  c2 <- s10[s10$database == nm, ]
  cox_body <- data.frame(
    Contrast = c2$contrast, Model = c2$model,
    `N (deaths)` = sprintf("%d (%d)", c2$n, c2$deaths),
    `HR (95% CI)` = c2$`HR (95% CI)`, P = fmt_p(c2$P),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  stopifnot(length(unique(cox_body$P)) == nrow(cox_body) || length(unique(round(c2$P, 6))) == 1L)
  top <- data.frame(
    Contrast = "RCS minimum-risk cutoffs (Model 1 / Model 3)",
    Model = "", `N (deaths)` = "",
    `HR (95% CI)` = paste(sprintf("%s: %.3f h", c1$model, c1$min_risk_hours), collapse = "; "),
    P = "", check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S10-%s. RCS cutoff and binary Cox.xlsx", nm)),
    title = "Table S10. RCS-derived sleep cutoffs and binary Cox models",
    df_body = rbind(top, cox_body),
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      "Minimum-risk hour is the sleep duration with the lowest HR on the spline grid (reference 7.5 h).",
      "Binary Cox compares sleep below versus at/above the Model 3 minimum-risk hour.",
      "This binary contrast supplements the main five-level grouping (<5 / 5-6 / 6-7 / 7-<9 / >=9 h).",
      paste0("Model 3 covariates: ", paste(m3_cov, collapse = ", "), ".")
    )
  )
  message("S10 ", nm, " P: ", paste(cox_body$P, collapse = " | "))
}

# ---- S12 ----
s12 <- fread(file.path(ckpt, "Table S12. RCS cutoff Cox PAR.csv"), data.table = FALSE)
for (nm in unique(s12$database)) {
  sub <- s12[s12$database == nm, ]
  cut_h <- unique(na.omit(sub$cutoff_hours))[1]
  body <- data.frame(
    Model = sub$model,
    `N (deaths)` = sprintf("%d (%d)", sub$n, sub$deaths),
    `HR (95% CI)` = sub$`HR (95% CI)`,
    P = fmt_p(sub$P),
    `Exposure prevalence` = if ("expos_prev" %in% names(sub)) ifelse(sub$model == "Model3", sprintf("%.1f%%", 100 * sub$expos_prev), "") else "",
    PAR = if ("PAR" %in% names(sub)) ifelse(sub$model == "Model3" & is.finite(sub$PAR), sprintf("%.1f%%", 100 * sub$PAR), "") else "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(tab_dir, sprintf("Table S12-%s. RCS cutoff mortality with PAR.xlsx", nm)),
    title = "Table S12. Cohort-specific RCS minimum-risk cutoff and all-cause mortality, with population attributable risk",
    df_body = body,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      sprintf("Exposure uses this cohort's own Model 3 RCS minimum-risk cutoff (%.3f h from Table S10), not an external 465-minute cut-point.", cut_h),
      "PAR uses Levin formula with Model 3 HR and the exposure prevalence (survey-weighted in NHANES).",
      "PAR is model-based and should not be read as a causal population fraction.",
      "Cutoffs differ across cohorts by design; do not pool a single borrowed clinical threshold.",
      paste0("Model 3 covariates: ", paste(m3_cov, collapse = ", "), ".")
    )
  )
  message("S12 ", nm, " P: ", paste(body$P, collapse = " | "))
}
message("FIXED S9/S10/S12 P columns")
