#!/usr/bin/env Rscript
# 修复：Fig4 标题截断；Fig6 亚组森林（对齐原文双面板全亚组）；
#       Fig7 恢复 SOFA 三层 Boruta（原文三块）。
args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
index_root <- get_arg(
  "--index-root",
  "/mnt/g/02block_result/33_AKI/prognosis_ml_40346649/by_index/\u3010success\u3011SAR+CrCV"
)
indices <- trimws(strsplit(get_arg("--indices", "SAR,CrCV"), ",", TRUE)[[1]])
ia <- indices[[1]]; ib <- indices[[2]]

engine <- "/mnt/e/01block/01Block-new-Final"
setwd(engine)
suppressWarnings(suppressMessages({
  source("R/utils.R")
  source("R/ml_assoc_covariate_rule.R")
  source("R/ml_stratified_ctx.R")
  source("R/prognosis_reference_assoc.R")
  source("R/prognosis_landmark_ph.R")
  source("R/ml_reference_assoc_figures.R")
  source("R/ml_external_frozen_shap.R")
  source("R/ml_frozen_model_bundle.R")
  source("R/pub_figure_export.R")
}))
.ref_assoc_set_indices(indices)

mi_ckpt <- "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/checkpoints/by_index/SAR+CrCV/MIMIC_IV/ml_assoc_bundle.rds"
mi <- readRDS(mi_ckpt)
ctx <- mi$ctx
config <- ctx$config
analysis <- ctx$data$imputed
train <- ctx$data$train

derived_path <- file.path(
  index_root, "publication_literature_final/authority/checkpoints/by_index",
  "SAR+CrCV_REF/MIMIC_IV/step01_reference_derived.rds"
)
train_aug <- readRDS(derived_path)$ctx$data$train
provenance <- reference_trusted_development(train_aug, checkpoint_path = derived_path)
joint_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ib, provenance)
sosm_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ia, provenance)
wpr_lock <- reference_lock_tertile_cutpoints(train_aug, ib, ib, provenance)

# 文献 Model1/2/3 显式挂上，避免 models=NULL 只出 Overall
m_age_sex <- c("Age", "Gender")
m3 <- unique(c(
  m_age_sex,
  as.character(ctx$results$Model2Factors %||% character(0)),
  as.character(ctx$results$Model3Factors %||% character(0)),
  as.character(ctx$results$assoc_model2_factors %||% character(0))
))
m3 <- setdiff(m3, c(ia, ib, "SOFA", "SOFA_layer", "futime", "fustatus", "ID"))
models <- list(Model1 = character(0), Model2 = m_age_sex, Model3 = m3)
message("Model2=", paste(models$Model2, collapse = "+"),
        " Model3 n=", length(models$Model3))

db_frames <- list(list(
  name = "MIMIC_IV", short = "MIMIC-IV", data = analysis,
  outcome_cfg = config, joint_lock = joint_lock,
  sosm_lock = sosm_lock, wpr_lock = wpr_lock,
  rcs_locks = NULL, assoc_ctx = ctx, train_ref = train_aug,
  models = models
))

tmp <- tempfile("fix467_")
dir.create(tmp)
built <- character(0)

# ---- Fig4 ----
f4 <- file.path(tmp, sprintf("Figure 4. ROC %s %s joint scores.pdf", ia, ib))
r4 <- ref_assoc_fig4_roc(db_frames, cutoff = NULL, out_pdf = f4)
stopifnot(file.exists(r4$path))
built <- c(built, r4$path)
message("Fig4 OK")

# ---- Fig6 ----
f6 <- file.path(tmp, "Figure 6. Forest tertile association.pdf")
r6 <- ref_assoc_fig6_forest(db_frames, cutoff = NULL, out_pdf = f6)
fr <- r6$rows
message("Fig6 rows=", nrow(fr),
        " estimable=", sum(grepl("^estimable", fr$status)),
        " subgroups=", paste(unique(fr$subgroup[fr$subgroup != "Overall"]),
                             collapse = ","))
print(as.data.frame(table(fr$subgroup, fr$status)))
stopifnot(!is.null(r6$path), file.exists(r6$path))
built <- c(built, r6$path)
message("Fig6 OK ", r6$path)

# ---- Fig7：SOFA 三层 Boruta（对齐原文三块）----
SOFA_SPEC <- ml_stratum_spec_sofa(breaks = c(4L, 10L))
# 候选特征：与 ML train 列对齐（剔除结局/ID/暴露本身可保留评分）
cand0 <- setdiff(
  names(train),
  c("futime", "fustatus", "ID", "Group", "JointGroup", "Joint_score",
    ia, ib, "SOFA_layer")
)
# Group 需 0/1
mk_group <- function(df) {
  g <- tryCatch(pipeline_outcome_as_01(df$fustatus, cfg = config),
                error = function(e) NA)
  if (all(is.na(g))) {
    s <- trimws(as.character(df$fustatus))
    g <- ifelse(s %in% c("1", "Non-survivor", "AKI", "Yes"), 1L, 0L)
  }
  as.integer(g)
}
boruta_by <- list()
for (key in names(SOFA_SPEC$strata)) {
  spec <- SOFA_SPEC$strata[[key]]
  lab <- spec$label
  message("Boruta stratum ", key, " (", lab, ") ...")
  keep <- ml_stratum_member(train$SOFA %||% train[["SOFA"]], spec)
  if (!length(keep) || !any(keep)) {
    # SOFA 可能在 train 里是数值列
    sv <- suppressWarnings(as.numeric(train$SOFA))
    keep <- ml_stratum_member(sv, spec)
  }
  tr <- train[keep, , drop = FALSE]
  cand <- intersect(cand0, names(tr))
  cand <- setdiff(cand, "SOFA")  # 分层键不进候选
  d <- data.frame(Group = factor(mk_group(tr)), tr[, cand, drop = FALSE],
                  check.names = FALSE)
  d <- d[stats::complete.cases(d), , drop = FALSE]
  # 去近零方差 / 全常量
  keepc <- vapply(d, function(x) {
    if (is.factor(x) || is.character(x)) length(unique(x)) >= 2L
    else length(unique(x[!is.na(x)])) >= 2L
  }, logical(1))
  d <- d[, keepc, drop = FALSE]
  message("  n=", nrow(d), " p=", ncol(d) - 1L)
  if (nrow(d) < 80L || ncol(d) < 4L) {
    message("  skip: too small")
    next
  }
  boruta_by[[lab]] <- ml_ref_boruta_run(d, max_runs = 50L, seed = 42L,
                                        database = "MIMIC_IV")
}
stopifnot(length(boruta_by) >= 2L)
f7 <- file.path(tmp, "Figure 7. Stratified Boruta feature selection in MIMIC-IV.pdf")
# 也写总体命名的主文 Fig7（课题现用 Overall 文件名时，改为分层文件名）
r7 <- ml_ref_fig7_boruta(boruta_by, out_pdf = f7)
# 同步一份用项目当前主文名，避免 summary 缺 Figure 7
f7_alias <- file.path(tmp, "Figure 7. Overall Boruta feature selection in MIMIC-IV.pdf")
# 实际是分层三块；文件名仍挂主文 Figure 7（替换原先单 Overall 残缺版）
file.copy(r7$path, f7_alias, overwrite = TRUE)
built <- c(built, f7_alias)
# 删除易混的「Overall」旧语义：主文 Fig7 = 分层三块
message("Fig7 OK panels=", length(boruta_by), " -> ", f7_alias)

# ---- 分发 ----
dests <- unique(c(
  file.path(index_root, "publication_literature_final", "Figures"),
  file.path(index_root, "summary_result", "Figures"),
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/publication_literature_final/Figures",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/summary_result/Figures"
))
for (fr in dests) {
  if (!dir.exists(dirname(fr))) next
  pdf_dir <- file.path(fr, "pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  for (src in built) {
    file.copy(src, file.path(pdf_dir, basename(src)), overwrite = TRUE)
    message("wrote ", file.path(pdf_dir, basename(src)))
  }
  # 若存在旧「Stratified」副本一并写入
  if (file.exists(f7)) {
    file.copy(f7, file.path(pdf_dir, basename(f7)), overwrite = TRUE)
  }
  tryCatch(
    pub_figure_ensure_formats(fr, config = list(pub_figures = list(dpi = 600L))),
    error = function(e) message("ensure: ", conditionMessage(e))
  )
}
message("DONE fix fig4/6/7")
