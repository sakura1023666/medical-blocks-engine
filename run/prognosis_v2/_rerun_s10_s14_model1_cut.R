#!/usr/bin/env Rscript
# 二分切点改为各库 Table S10 Model 1 RCS 最低风险小时；重跑扩展表 S9–S14。
suppressPackageStartupMessages({
  library(data.table); library(survival); library(survey); library(pROC)
})
engine <- "/mnt/e/01block/01Block-new-Final"
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine, PV2_PROFILE = "sleep_dyslipidemia")
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
source(file.path(engine, "R/utils.R"), local = FALSE)
pv2_ensure_dirs()
options(survey.lonely.psu = "adjust")

.ws_latest <- function() {
  ws <- paste0(pv2_out_root, "_delivery_workspace")
  if (!dir.exists(ws)) return(NA_character_)
  stamps <- list.dirs(ws, full.names = TRUE, recursive = FALSE)
  stamps <- stamps[order(file.info(stamps)$mtime, decreasing = TRUE)]
  for (d in c(file.path(stamps, "checkpoints"), stamps)) {
    if (file.exists(file.path(d, "imputed_dbs.rds"))) return(d)
  }
  NA_character_
}
if (is.na(tryCatch(pv2_artifact("imputed_dbs.rds", must_exist = FALSE), error = function(e) NA))) {
  w <- .ws_latest()
  if (!is.na(w)) {
    for (f in c("imputed_dbs.rds", "imputed_mids.rds", "Covariate_selection_note.txt",
                "Table S10. RCS cutoffs.csv")) {
      src <- file.path(w, f)
      if (!file.exists(src) && dir.exists(file.path(dirname(w), "checkpoints"))) {
        src <- file.path(dirname(w), "checkpoints", f)
      }
      if (file.exists(src)) {
        dir.create(pv2_ckpt_dir, recursive = TRUE, showWarnings = FALSE)
        file.copy(src, file.path(pv2_ckpt_dir, basename(src)), overwrite = TRUE)
        message("restored ", basename(src))
      }
    }
  }
}

message("==== Extension (binary cut = Model 1) ====")
source(file.path(engine, "run/prognosis_v2/pv2_mainval_extension.R"), local = FALSE)

cut_df <- data.table::fread(file.path(pv2_ckpt_dir, "Table S10. RCS cutoffs.csv"))
s10 <- data.table::fread(file.path(pv2_ckpt_dir, "Table S10. RCS cutoff Cox.csv"))
s12 <- data.table::fread(file.path(pv2_ckpt_dir, "Table S12. RCS cutoff Cox PAR.csv"))
m1 <- cut_df[cut_df$model == "Model 1", ]
message("Model1 cuts: ", paste(sprintf("%s=%.3f", m1$database, m1$min_risk_hours), collapse = "; "))
message("S10 used: ", paste(unique(sprintf("%s=%.3f", s10$database, s10$cutoff_hours)), collapse = "; "))
message("S12 used: ", paste(unique(sprintf("%s=%.3f", s12$database, s12$cutoff_hours)), collapse = "; "))
# assert binary uses Model 1
for (nm in unique(s10$database)) {
  expect <- m1$min_risk_hours[m1$database == nm][1]
  got <- unique(s10$cutoff_hours[s10$database == nm])[1]
  stopifnot(is.finite(expect), abs(got - expect) < 1e-6)
}
message("ALL DONE model1-cut")
