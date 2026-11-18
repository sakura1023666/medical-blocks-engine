#!/usr/bin/env Rscript
# S12：Model1/2/3 均填 Exposure prevalence 与按各模型 HR 的 PAR
suppressPackageStartupMessages(library(data.table))
engine <- "/mnt/e/01block/01Block-new-Final"
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

.ws_ckpt <- function() {
  ws <- paste0(pv2_out_root, "_delivery_workspace")
  stamps <- if (dir.exists(ws)) list.dirs(ws, full.names = TRUE, recursive = FALSE) else character()
  stamps <- stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]
  for (d in c(file.path(stamps, "checkpoints"), stamps, pv2_ckpt_dir)) {
    if (file.exists(file.path(d, "Table S12. RCS cutoff Cox PAR.csv"))) return(d)
  }
  pv2_ckpt_dir
}
ckpt <- .ws_ckpt()
s12 <- fread(file.path(ckpt, "Table S12. RCS cutoff Cox PAR.csv"), data.table = FALSE)
note <- pv2_artifact("Covariate_selection_note.txt", must_exist = FALSE)
if (is.na(note) || !file.exists(note)) {
  cand <- file.path(ckpt, "Covariate_selection_note.txt")
  if (file.exists(cand)) note <- cand
}
m3_cov <- if (!is.na(note) && file.exists(note)) {
  m3_line <- grep("^Model 3 =", readLines(note, warn = FALSE), value = TRUE)[1]
  trimws(strsplit(sub("^Model 3 =\\s*", "", m3_line), "\\s*\\+\\s*")[[1]])
} else c("Age", "Gender", "SBP", "Education", "Diabetes", "Hypertension", "Alcohol", "Smoke", "BMI")

# 用各行 HR 重算 PAR；患病率取该库已有 expos_prev（同库应一致）
for (nm in unique(s12$database)) {
  idx <- which(s12$database == nm)
  p_exp <- unique(na.omit(s12$expos_prev[idx]))[1]
  if (!is.finite(p_exp)) next
  rr <- as.numeric(s12$HR[idx])
  s12$expos_prev[idx] <- round(p_exp, 4)
  s12$PAR[idx] <- round(ifelse(is.finite(rr), (p_exp * (rr - 1)) / (1 + p_exp * (rr - 1)), NA_real_), 4)
}
fwrite(s12, file.path(pv2_ckpt_dir, "Table S12. RCS cutoff Cox PAR.csv"))
# 同步最新 workspace checkpoint（若可写）
if (dir.exists(ckpt) && normalizePath(ckpt) != normalizePath(pv2_ckpt_dir, mustWork = FALSE)) {
  try(fwrite(s12, file.path(ckpt, "Table S12. RCS cutoff Cox PAR.csv")), silent = TRUE)
}

for (nm in unique(s12$database)) {
  sub <- s12[s12$database == nm, ]
  cut_h <- unique(na.omit(sub$cutoff_hours))[1]
  body <- data.frame(
    Model = sub$model,
    `N (deaths)` = sprintf("%d (%d)", sub$n, sub$deaths),
    `HR (95% CI)` = sub$`HR (95% CI)`,
    P = fmt_p(sub$P),
    `Exposure prevalence` = ifelse(is.finite(sub$expos_prev), sprintf("%.1f%%", 100 * sub$expos_prev), ""),
    PAR = ifelse(is.finite(sub$PAR), sprintf("%.1f%%", 100 * sub$PAR), ""),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  sci_xlsx_single_header_booktabs(
    file.path(pv2_tab_dir, sprintf("Table S12-%s. RCS cutoff mortality with PAR.xlsx", nm)),
    title = "Table S12. Cohort-specific RCS minimum-risk cutoff and all-cause mortality, with population attributable risk",
    df_body = body,
    footnotes = c(
      sprintf("Cohort role: %s.", pv2_role_label(nm)),
      sprintf("Exposure uses this cohort's own Model 3 RCS minimum-risk cutoff (%.3f h from Table S10), not an external 465-minute cut-point.", cut_h),
      "Exposure prevalence is the proportion sleeping below the cohort RCS cutoff (survey-weighted in NHANES) and does not depend on the Cox model.",
      "PAR uses the Levin formula with each model's HR and the same exposure prevalence; primary interpretation follows Model 3.",
      "PAR is model-based and should not be read as a causal population fraction. Negative PAR occurs when HR < 1.",
      "Cutoffs differ across cohorts by design; do not pool a single borrowed clinical threshold.",
      paste0("Model 3 covariates: ", paste(m3_cov, collapse = ", "), ".")
    )
  )
  message(nm, ": ", paste(sprintf("%s prev=%s PAR=%s", body$Model, body$`Exposure prevalence`, body$PAR), collapse = " | "))
}
message("S12 refilled for all models")
