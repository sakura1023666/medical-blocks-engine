###############################################################################
#  IBD 轨迹预后 — 单指标 Hemoglobin（与复合指标同流水线）
#
#  用法:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
#      --config configs/config_trajectory_prognosis_ibd_hemoglobin.R \
#      --only-index Hemoglobin --workers 1 --no-skip
#
#  说明:
#    - 继承 config_trajectory_prognosis_ibd_batch.R
#    - index_vars = dual_safe ∪ Hemoglobin，保证 other_ix 仍排除全部复合指标
#    - 共享层已算完 dual_safe；本 config 仅补算 / 派发 Hemoglobin
###############################################################################

source("configs/config_trajectory_prognosis_ibd_batch.R")

.hb_ix <- unique(c(
  as.character(
    get0(".composite_index_vars_dual_safe", inherits = TRUE) %||%
      get0(".composite_index_vars", inherits = TRUE) %||%
      character(0)
  ),
  "Hemoglobin"
))

config$trajectory_batch$index_vars <- .hb_ix
config$trajectory_batch$index_group <- NULL
# 共享层若重跑，只补 Hemoglobin（不重写其它 12_*.RData）
config$trajectory_calc_28d_index$index_vars <- "Hemoglobin"

# 基线插补：当前暴露不进 MICE（与其它复合指标一致）
config$imputation$exclude_from_mice_cols <- unique(c(
  as.character(config$imputation$exclude_from_mice_cols %||% character(0)),
  "Hemoglobin"
))
config$imputation$table_s1_exclude_vars <- unique(c(
  as.character(config$imputation$table_s1_exclude_vars %||% character(0)),
  "Hemoglobin"
))

# 小样本 IBD：eICU n≈79 时 survival 协变量宜 ≤3；与 MCHC 成功 run 对齐
config$trajectory_jlcm$survival_covariate_max <- 3L
config$trajectory_jlcm$covariate_vars <- c("INR", "Age", "DBP")
config$trajectory_jlcm$covariate_vars_from_vif <- FALSE
# 加速 gridsearch；类别上限仍由 adaptive_class_cap 控制
config$trajectory_jlcm$gridsearch_rep <- 30L

rm(.hb_ix)
