#!/usr/bin/env Rscript
# 修复：1) Liling Fig2 RCS（lock 协变量 + x 轴 P1–P99）
#       2) NHANES Fig3 Quartile 亚组补回 Age_Group
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))

ix <- "UHR"
dual_dir <- file.path(study, "by_index", "【success】UHR")
lock <- jsonlite::fromJSON(file.path(study, "data/harmonized/covariate_lock.json"))
m1 <- as.character(lock$model1)
m2 <- as.character(lock$model2)
cmf <- as.character(lock$common_model_factors)
lock_sg <- c("Age_Group", "Gender", "Marital_Status", "Hypertension")

# ── 1) Liling RCS ────────────────────────────────────────────────────────────
cli::cli_h1("Liling RCS 重跑（lock + plot_x_quantiles）")
source(file.path(study, "config_incidence_liling.R"))
config$project$output_dir <- file.path(dual_dir, "Liling")
config$incidence$index_var <- ix
config$logistic$index_var <- ix
config$rcs_incidence$model1_factors <- m1
config$rcs_incidence$model2_factors <- m2
config$rcs_incidence$nk_range <- 3L
config$rcs_incidence$plot_x_quantiles <- c(0.01, 0.99)
# 写入 ctx 协变量，避免旧 Model2Factors 残留
ck_lil <- file.path(study, "checkpoints", "Liling_UHR")
pipeline$checkpoint$dir <- ck_lil
# 从 logistic_quartile 之后重跑 RCS（保留分组列）
from_tok <- if (file.exists(file.path(ck_lil, "logistic_quartile_glm.rds"))) {
  "logistic_quartile_glm"
} else {
  "multicollinearity_screen"
}
# 清理旧 Fig2
unlink(list.files(file.path(dual_dir, "Liling"), pattern = "Figure 2", recursive = TRUE, full.names = TRUE))
run_pipeline(
  root, config = config, pipeline = pipeline,
  run_opts = list(from = from_tok, only = c("rcs_incidence"))
)

# ── 2) NHANES Quartile Fig3 补 Age_Group ─────────────────────────────────────
cli::cli_h1("NHANES 亚组重跑（强制 Age_Group）")
source(file.path(study, "config_incidence_dual_batch.R"))
config$incidence_batch$sensitivity_suite$enable <- FALSE
config$subgroup$var_source <- "required"
config$subgroup$required_subgroup_vars <- lock_sg
config$subgroup$locked_subgroup_vars <- lock_sg
config$dual_db$harmonization$lock_covariates_preset <- TRUE
config$dual_db$harmonization$harmonized_model1_nhanes <- m1
config$dual_db$harmonization$harmonized_model2_nhanes <- m2
config$dual_db$harmonization$harmonized_model1_mimic <- m1
config$dual_db$harmonization$harmonized_model2_mimic <- m2
config$dual_db$harmonization$common_model_factors <- cmf
config$incidence$index_var <- ix
config$logistic$index_var <- ix

# 同步 gate_b 为 lock，避免后续块读到旧协变量
harm_ix <- file.path(study, "checkpoints", "by_index", ix, "harmonization")
dir.create(harm_ix, recursive = TRUE, showWarnings = FALSE)
gate_b <- list(
  common_model_factors = cmf,
  harmonized_model1_nhanes = m1,
  harmonized_model2_nhanes = m2,
  harmonized_model1_mimic = m1,
  harmonized_model2_mimic = m2,
  covariate_source_used = "lock_preset"
)
saveRDS(gate_b, file.path(harm_ix, "gate_b_covariates.rds"))
# Gate D 亚组变量
harm_g <- file.path(study, "checkpoints", "_global_harmonization")
dir.create(harm_g, recursive = TRUE, showWarnings = FALSE)
saveRDS(
  list(vars = lock_sg, eligible_by_db = list(nhanes = lock_sg, mimic = lock_sg), saved_at = Sys.time()),
  file.path(harm_g, "gate_d_subgroup_vars.rds")
)

cfg_n <- incidence_batch_apply_db_overrides(config, "nhanes", root, ix)
cfg_n$subgroup$var_source <- "required"
cfg_n$subgroup$required_subgroup_vars <- lock_sg
cfg_n$subgroup$locked_subgroup_vars <- lock_sg
cfg_n$project$output_dir <- file.path(dual_dir, "NHANES")
unlink(list.files(file.path(dual_dir, "NHANES"), pattern = "Figure 3.*Quartile", recursive = TRUE, full.names = TRUE))

pl <- pipeline_nhanes_batch
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- file.path(study, "checkpoints", "by_index", ix, "NHANES")
# 从 RCS 之后重跑 subgroup（保证 Index_Group_Quartile 已在数据中）
run_pipeline(
  root, config = cfg_n, pipeline = pl,
  run_opts = list(from = "logistic_quartile_nhanes_weighted_rcs", only = "subgroup_nhanes_weighted")
)

# ── 3) 收集到 summary_result/figure ──────────────────────────────────────────
sum_fig <- file.path(study, "summary_result", "figure")
dir.create(sum_fig, recursive = TRUE, showWarnings = FALSE)
for (src in c(
  list.files(file.path(dual_dir, "Liling"), pattern = "Figure 2.*RCS.*\\.pdf$", recursive = TRUE, full.names = TRUE),
  list.files(file.path(dual_dir, "NHANES"), pattern = "Figure 3.*Quartile.*\\.pdf$", recursive = TRUE, full.names = TRUE),
  list.files(file.path(dual_dir, "NHANES"), pattern = "Figure 3.*Subgroup.*\\.pdf$", recursive = TRUE, full.names = TRUE)
)) {
  if (!length(src) || !nzchar(src)) next
  # 优先最新 mtime
  src <- src[order(file.info(src)$mtime, decreasing = TRUE)]
  for (f in src) {
    file.copy(f, file.path(sum_fig, basename(f)), overwrite = TRUE)
    cli::cli_alert_success("copied {basename(f)}")
  }
}

cli::cli_alert_success("修复完成")
