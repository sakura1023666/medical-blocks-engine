#!/usr/bin/env Rscript
###############################################################################
# retrain_bun_cr_xgboost_shap_shiny.R
#
# P0：BUN_Cr eICU 用当前 xgboost 重训 → SHAP Fig7 → Shiny（ml_tag=xgboost）
#
# 背景：旧 evalresult_xgboost.RData 与 xgboost 3.x 不兼容；定向 --blocks shap
# 会跳过 ml_xgboost；--from ml_xgboost 在短 pipeline 里解析失败。本脚本从
# step07 train/validation + LASSO 最终特征最小重建 ctx，直接调 block。
#
# 用法（引擎根）：
#   MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#   Rscript run/ml/retrain_bun_cr_xgboost_shap_shiny.R \
#     --config "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/19_AKI_TX_刘雪艳/config.R" \
#     --index BUN_Cr
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  args[[hit[[1]] + 1L]]
}
has_flag <- function(flag) flag %in% args

eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(eng) || !dir.exists(file.path(eng, "R"))) {
  eng <- "/mnt/e/01block/01Block-new-Final"
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = eng)
setwd(eng)

suppressPackageStartupMessages({
  source(file.path(eng, "R/utils.R"), local = FALSE)
  source(file.path(eng, "R/pipeline_runner.R"), local = FALSE)
  if (file.exists(file.path(eng, "R/pub_figure_export.R"))) {
    source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
  }
})

cfg_path <- normalizePath(
  get_opt(
    "--config",
    "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/19_AKI_TX_刘雪艳/config.R"
  ),
  winslash = "/",
  mustWork = TRUE
)
source(cfg_path, local = FALSE)
if (!exists("config") || !is.list(config)) {
  stop("config.R 未定义 config list", call. = FALSE)
}

study_root <- if (exists(".batch_project_root") && nzchar(.batch_project_root %||% "")) {
  normalizePath(.batch_project_root, winslash = "/", mustWork = TRUE)
} else {
  normalizePath(dirname(cfg_path), winslash = "/", mustWork = TRUE)
}
ix <- as.character(get_opt("--index", "BUN_Cr"))[1L]
ix_root <- file.path(study_root, "by_index", paste0("\u3010success\u3011", ix))
if (!dir.exists(ix_root)) {
  alt <- file.path(study_root, "by_index", ix)
  if (dir.exists(alt)) ix_root <- alt
}
if (!dir.exists(ix_root)) stop("找不到指标根: ", ix_root, call. = FALSE)
ix_root <- normalizePath(ix_root, winslash = "/", mustWork = TRUE)
eicu_root <- file.path(ix_root, "eICU")
if (!dir.exists(eicu_root)) stop("找不到 eICU 目录: ", eicu_root, call. = FALSE)

log_dir <- file.path(study_root, "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)
stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
log_path <- file.path(log_dir, paste0("retrain_bun_cr_xgb_shap_shiny_", stamp, ".log"))
.log <- function(...) {
  msg <- paste0(...)
  cat(msg, "\n", sep = "")
  cat(msg, "\n", file = log_path, append = TRUE, sep = "")
}
.log("=== retrain_bun_cr_xgboost_shap_shiny @ ", stamp, " ===")
.log("study=", study_root)
.log("ix_root=", ix_root)
.log("xgboost=", as.character(utils::packageVersion("xgboost")))

## ---- 路径 ----
tv_dir <- file.path(eicu_root, "step07_train_validation", "Data")
xgb_step <- file.path(eicu_root, "step26_ml_xgboost")
shap_step <- file.path(eicu_root, "step42_shap")
shiny_step <- file.path(eicu_root, "step43_shiny_ml_app")
lasso_freq <- file.path(
  eicu_root, "step16_feature_selection_lasso", "Tables",
  "Lasso_feature_frequency.csv"
)
arch_dir <- file.path(ix_root, "_archive_p0_repair", "shap_tabpfn_variants")
dir.create(arch_dir, recursive = TRUE, showWarnings = FALSE)
sum_fig_pdf <- file.path(ix_root, "summary_results", "Figures", "pdf")
sum_fig_md <- file.path(ix_root, "summary_results", "Figures", "image_information")
sum_shiny <- file.path(ix_root, "summary_results", "Shiny", "eICU")
ix_shiny <- file.path(ix_root, "Shiny", "eICU")
dir.create(sum_fig_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(sum_fig_md, recursive = TRUE, showWarnings = FALSE)

stopifnot(dir.exists(tv_dir), file.exists(file.path(tv_dir, "df_train_RData.RData")))

## ---- 读 train/test（轻量，避免巨大 checkpoint RDS）----
e_tr <- new.env(parent = emptyenv())
load(file.path(tv_dir, "df_train_RData.RData"), envir = e_tr)
e_te <- new.env(parent = emptyenv())
val_path <- file.path(tv_dir, "df_validation_RData.RData")
if (!file.exists(val_path)) val_path <- file.path(tv_dir, "df_val_RData.RData")
load(val_path, envir = e_te)
df_train <- e_tr$df_train
df_test <- e_te$df_validation %||% e_te$df_val %||% e_te$df_test
if (!is.data.frame(df_train) || !is.data.frame(df_test)) {
  stop("train/validation 未加载到 data.frame", call. = FALSE)
}
if (!"Group" %in% names(df_train)) stop("df_train 无 Group 列", call. = FALSE)

## Group 水平与历史 ML 一致（AKI_TX / No AKI_TX）；与现行发表 disease 名可不同
grp_lv <- levels(as.factor(df_train$Group))
if (!all(c("AKI_TX", "No AKI_TX") %in% grp_lv) && length(grp_lv) >= 2L) {
  .log("WARN: Group levels = ", paste(grp_lv, collapse = " | "))
}
ana_g <- if ("AKI_TX" %in% grp_lv) "AKI_TX" else as.character(grp_lv[[length(grp_lv)]])
ref_g <- if ("No AKI_TX" %in% grp_lv) "No AKI_TX" else as.character(grp_lv[[1L]])
.log("Group ana=", ana_g, " ref=", ref_g)

## Final features：优先 shiny_staging，其次 LASSO freq≥cutoff
feats <- character(0)
ss_path <- file.path(sum_shiny, "ShinyApp", "shiny_staging.RData")
if (!file.exists(ss_path)) {
  ss_path <- file.path(shiny_step, "ShinyApp", "shiny_staging.RData")
}
if (file.exists(ss_path)) {
  e_ss <- new.env(parent = emptyenv())
  tryCatch(load(ss_path, envir = e_ss), error = function(e) NULL)
  if (exists("shiny_staging", envir = e_ss)) {
    feats <- as.character(e_ss$shiny_staging$Final_Features %||% character(0))
  }
}
if (!length(feats) && file.exists(lasso_freq)) {
  ff <- utils::read.csv(lasso_freq, stringsAsFactors = FALSE)
  cut_n <- suppressWarnings(as.integer(ff$freq_cutoff_n[[1L]]))
  if (!is.finite(cut_n) || cut_n < 1L) cut_n <- 850L
  keep <- ff[as.integer(ff$frequency) >= cut_n, , drop = FALSE]
  feats <- as.character(keep$feature)
}
feats <- unique(feats[nzchar(feats)])
feats <- intersect(feats, names(df_train))
if (!length(feats)) stop("无法解析 Final_Features", call. = FALSE)
.log("Final_Features (", length(feats), "): ", paste(feats, collapse = ", "))

## ---- 组装最小 ctx ----
config$project$analysis_group <- ana_g
config$project$reference_group <- ref_g
## Shiny pred_col 跟 disease 走；与训练 Group 病例水平对齐
config$project$disease <- ana_g
config$data$outcome_column <- "Group"
config$shap <- modifyList(config$shap %||% list(), list(
  enable = TRUE,
  ml_model = "xgboost",
  allow_fixed_xgboost = TRUE,
  force_kernel_best_model = TRUE,
  prefer_tree_shapviz = TRUE,
  pin_index_importance_top = TRUE,
  combine = TRUE
))
config$shiny_ml_app <- modifyList(config$shiny_ml_app %||% list(), list(
  enable = TRUE,
  export_app = TRUE,
  run_interactive = FALSE,
  ml_model_tag = "xgboost",
  app_subdir = "ShinyApp"
))
config$shiny <- modifyList(config$shiny %||% list(), list(
  enable = TRUE, export_app = TRUE, run_interactive = FALSE
))
config$ml_xgboost <- modifyList(config$ml_xgboost %||% list(), list(enable = TRUE))
if (!is.null(config$pipeline$checkpoint)) {
  config$pipeline$checkpoint$enable <- FALSE
}

imputed <- rbind(df_train, df_test)
## 发表命名库标签（Figure N-eICU.…）
config$project$database <- "eICU"
config$project$database_type <- "eICU"
ctx <- list(
  config = config,
  data = list(
    imputed = imputed,
    cleaned = imputed,
    train = df_train,
    test = df_test
  ),
  results = list(
    feature_selection_final = feats,
    ml_feature_names = feats,
    ml_best_model_tag = "xgboost",
    ml_models = list(),
    Model2Factors = feats
  ),
  log = list(
    ## run_block 会 +1 后拼 stepNN_<block>；预置使落盘对齐既有 step26/42/43
    block_step_counter = 25L,
    block_output_dirs = list(
      train_validation = file.path(eicu_root, "step07_train_validation"),
      ml_xgboost = xgb_step,
      ml_models_bundle = file.path(eicu_root, "step23_ml_models_bundle")
    )
  ),
  root_output_dir = eicu_root,
  output_dir = eicu_root,
  output_dir_figures = file.path(eicu_root, "Figures"),
  output_dir_tables = file.path(eicu_root, "Tables")
)
options(pipeline.database_name = "eICU")

## ---- 1) 重训 XGBoost ----
skip_train <- has_flag("--skip-train")
xgb_models_dir <- file.path(xgb_step, "Models")
xgb_eval <- file.path(xgb_models_dir, "evalresult_xgboost.RData")
if (!skip_train) {
  .log("--- block_ml_xgboost ---")
  dir.create(file.path(xgb_step, "Data"), recursive = TRUE, showWarnings = FALSE)
  dir.create(xgb_models_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(xgb_step, "Figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(xgb_step, "Tables"), recursive = TRUE, showWarnings = FALSE)
  ## 备份旧 booster
  if (file.exists(xgb_eval)) {
    bak <- file.path(
      xgb_models_dir,
      paste0("evalresult_xgboost_incompat_", stamp, ".RData.bak")
    )
    file.copy(xgb_eval, bak, overwrite = TRUE)
    .log("archived old booster -> ", bak)
  }
  ctx$log$block_step_counter <- 25L  # → step26_ml_xgboost
  pipeline_source_block(eng, "ml_eval_common")
  pipeline_source_block(eng, "ml_xgboost")
  ctx <- run_block(ctx, "ml_xgboost")
  ## run_block 可能写到 step26；若计数漂移则定位实际 Models
  xgb_out <- ctx$log$block_output_dirs[["ml_xgboost"]] %||% xgb_step
  xgb_models_dir <- file.path(xgb_out, "Models")
  xgb_eval <- file.path(xgb_models_dir, "evalresult_xgboost.RData")
  if (!file.exists(xgb_eval) && !identical(xgb_out, xgb_step)) {
    ## 兜底：拷回标准 step26
    dir.create(file.path(xgb_step, "Models"), recursive = TRUE, showWarnings = FALSE)
    alt <- list.files(eicu_root, pattern = "evalresult_xgboost\\.RData$", recursive = TRUE, full.names = TRUE)
    alt <- alt[grepl("ml_xgboost", alt)]
    if (length(alt)) {
      file.copy(alt[[1L]], file.path(xgb_step, "Models", "evalresult_xgboost.RData"), overwrite = TRUE)
      xgb_models_dir <- file.path(xgb_step, "Models")
      xgb_eval <- file.path(xgb_models_dir, "evalresult_xgboost.RData")
    }
  }
  if (!file.exists(xgb_eval)) stop("重训后未找到 ", xgb_eval, call. = FALSE)
  ## 校验 booster 可读
  e_chk <- new.env(parent = emptyenv())
  load(xgb_eval, envir = e_chk)
  booster <- tryCatch(
    workflows::extract_fit_engine(e_chk$final_xgboost),
    error = function(e) stop("extract_fit_engine 失败: ", e$message, call. = FALSE)
  )
  inv <- tryCatch(
    xgboost::xgb.importance(model = booster),
    error = function(e) stop("新 booster 仍不兼容: ", e$message, call. = FALSE)
  )
  .log("xgboost importance top: ", paste(utils::head(inv$Feature, 5L), collapse = ", "))
  ## 同步到 ml_models/Models（shiny 部分路径期望）
  ml_models_dir <- file.path(eicu_root, "ml_models", "Models")
  dir.create(ml_models_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(xgb_eval, file.path(ml_models_dir, "evalresult_xgboost.RData"), overwrite = TRUE)
  ctx$results[["ml_models_models_dir"]] <- xgb_models_dir
  ctx$results$ml_models[["xgboost"]] <- e_chk$final_xgboost
  ctx$log$block_output_dirs$ml_xgboost <- xgb_step
  .log("OK retrain -> ", xgb_eval)
} else {
  .log("--- skip-train: load existing evalresult_xgboost ---")
  if (!file.exists(xgb_eval)) stop("无 ", xgb_eval, call. = FALSE)
  e_chk <- new.env(parent = emptyenv())
  load(xgb_eval, envir = e_chk)
  booster <- tryCatch(
    workflows::extract_fit_engine(e_chk$final_xgboost),
    error = function(e) stop("extract_fit_engine 失败: ", e$message, call. = FALSE)
  )
  inv <- tryCatch(
    xgboost::xgb.importance(model = booster),
    error = function(e) stop("booster 仍不兼容: ", e$message, call. = FALSE)
  )
  .log("xgboost importance top: ", paste(utils::head(inv$Feature, 5L), collapse = ", "))
  ml_models_dir <- file.path(eicu_root, "ml_models", "Models")
  dir.create(ml_models_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(xgb_eval, file.path(ml_models_dir, "evalresult_xgboost.RData"), overwrite = TRUE)
  ctx$results$ml_models[["xgboost"]] <- e_chk$final_xgboost
  ctx$results[["ml_models_models_dir"]] <- xgb_models_dir
  ctx$log$block_output_dirs$ml_xgboost <- xgb_step
}

## ---- 2) SHAP ----
.log("--- block_shap ---")
dir.create(file.path(shap_step, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(shap_step, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(shap_step, "Data"), recursive = TRUE, showWarnings = FALSE)
ctx$root_output_dir <- eicu_root
ctx$results[["ml_models_models_dir"]] <- xgb_models_dir
ctx$log$block_output_dirs[["ml_xgboost"]] <- dirname(xgb_models_dir)
ctx$log$block_step_counter <- 41L  # → step42_shap
pipeline_source_block(eng, "shap")
ctx <- run_block(ctx, "shap")
shap_step_actual <- ctx$log$block_output_dirs[["shap"]] %||% shap_step

## 找到新 SHAP PDF（须含 XGBoost）
shap_figs <- list.files(
  file.path(shap_step_actual, "Figures"),
  pattern = "SHAP.*\\.pdf$",
  full.names = TRUE
)
shap_xgb <- shap_figs[grepl("XGBoost|xgboost", basename(shap_figs), ignore.case = TRUE)]
if (!length(shap_xgb)) {
  ## 也扫 eICU/Figures（mirror）与标准 step42
  shap_figs2 <- c(
    list.files(file.path(eicu_root, "Figures"), pattern = "SHAP.*\\.pdf$", full.names = TRUE),
    list.files(file.path(shap_step, "Figures"), pattern = "SHAP.*\\.pdf$", full.names = TRUE)
  )
  shap_xgb <- shap_figs2[grepl("XGBoost|xgboost", basename(shap_figs2), ignore.case = TRUE)]
}
if (!length(shap_xgb)) {
  .log("SHAP figures present: ", paste(basename(shap_figs), collapse = " | "))
  stop("未产出带 XGBoost 标题的 SHAP PDF", call. = FALSE)
}
shap_src <- shap_xgb[[1L]]
## G: 路径 + em-dash 文件名上 pdftotext 可能 status 99；经 /tmp 副本校验
.tmp_pdf <- tempfile(fileext = ".pdf")
file.copy(shap_src, .tmp_pdf, overwrite = TRUE)
.txt <- tryCatch(
  system2("pdftotext", c("-layout", .tmp_pdf, "-"), stdout = TRUE, stderr = FALSE),
  error = function(e) character(0)
)
unlink(.tmp_pdf)
if (!any(grepl("XGBoost", .txt, ignore.case = TRUE))) {
  stop("pdftotext 未在 SHAP PDF 中读到 XGBoost: ", shap_src, call. = FALSE)
}
.log("SHAP PDF OK: ", shap_src)

## 归档 TabPFN 变体 + 写入 Figure 7
.archive_tabpfn <- function(paths) {
  for (f in paths) {
    if (!file.exists(f)) next
    if (grepl("TabPFN", basename(f), ignore.case = TRUE) ||
        (grepl("SHAP", basename(f), ignore.case = TRUE) &&
           !grepl("XGBoost|xgboost", basename(f), ignore.case = TRUE) &&
           !grepl("^Figure 7-eICU\\. SHAP\\.pdf$", basename(f)))) {
      dest <- file.path(arch_dir, basename(f))
      if (grepl("^Figure 7-eICU\\. SHAP\\.pdf$", basename(f))) next
      file.copy(f, dest, overwrite = TRUE)
      if (grepl("TabPFN", basename(f), ignore.case = TRUE)) {
        unlink(f)
        .log("archived+removed TabPFN: ", f)
      }
    }
  }
}
fig7_name <- "Figure 7-eICU. SHAP.pdf"
targets <- c(
  file.path(sum_fig_pdf, fig7_name),
  file.path(eicu_root, "Figures", "pdf", fig7_name),
  file.path(eicu_root, "Figures", fig7_name),
  file.path(ix_root, "Figures", "pdf", fig7_name)
)
## 先归档旧 TabPFN（含 step42 残留，防 mirror 再拷回根 Figures）
.archive_tabpfn(c(
  list.files(file.path(shap_step_actual, "Figures"), pattern = "SHAP|TabPFN", full.names = TRUE),
  list.files(file.path(shap_step, "Figures"), pattern = "SHAP|TabPFN", full.names = TRUE),
  list.files(sum_fig_pdf, pattern = "SHAP|TabPFN", full.names = TRUE),
  list.files(file.path(eicu_root, "Figures"), pattern = "SHAP|TabPFN", full.names = TRUE),
  list.files(file.path(eicu_root, "Figures", "pdf"), pattern = "SHAP|TabPFN", full.names = TRUE),
  list.files(file.path(ix_root, "Figures", "pdf"), pattern = "SHAP|TabPFN", full.names = TRUE)
))
for (dst in targets) {
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  file.copy(shap_src, dst, overwrite = TRUE)
  .log("copied Fig7 -> ", dst)
}
## 根目录若仍有 TabPFN 命名文件，再清一次
.archive_tabpfn(list.files(
  file.path(eicu_root, "Figures"),
  pattern = "TabPFN",
  full.names = TRUE
))

## image_information
md_path <- file.path(sum_fig_md, "Figure 7-eICU. SHAP.md")
md_txt <- paste(
  c(
    "# Figure 7-eICU. SHAP",
    "",
    "## 图面说明",
    paste0(
      "本图为 eICU 开发队列上、对预指定主模型 XGBoost",
      "（primary_model_rule = external_validation_auc）的 SHAP 解释：",
      "左栏 mean(|SHAP|) 重要性，右栏 bee swarm。",
      "图面标题为「SHAP importance — XGBoost」与「SHAP bee swarm — XGBoost」。",
      "禁止残留 TabPFN 标题。"
    ),
    "",
    "图上标注：",
    paste0("- 面板标题含 XGBoost（pdftotext 可核）"),
    paste0("- 特征（与 Final ML 集一致）: ", paste(feats, collapse = ", ")),
    "",
    "## 分析上下文",
    "- 暴露/特征: Final ML 特征集（含 BUN Cr）",
    "- 被解释模型: XGBoost（与 Shiny ml_tag=xgboost 同模型）",
    "- 结局: 28-day in-hospital mortality（训练 Group=AKI_TX）",
    "- 库/集: eICU（开发侧）",
    "- 是否拼图: 否"
  ),
  collapse = "\n"
)
writeLines(md_txt, md_path)
## 镜像到 eICU / 指标根 image_information
for (imd in c(
  file.path(eicu_root, "Figures", "image_information"),
  file.path(ix_root, "Figures", "image_information")
)) {
  dir.create(imd, recursive = TRUE, showWarnings = FALSE)
  file.copy(md_path, file.path(imd, "Figure 7-eICU. SHAP.md"), overwrite = TRUE)
}
.log("wrote image_information: ", md_path)

## ---- 3) Shiny ----
.log("--- block_shiny_ml_app ---")
dir.create(file.path(shiny_step, "ShinyApp"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(shiny_step, "Data"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(shiny_step, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(shiny_step, "Tables"), recursive = TRUE, showWarnings = FALSE)
ctx$results$ml_best_model_tag <- "xgboost"
ctx$config$shiny_ml_app$ml_model_tag <- "xgboost"
ctx$results[["ml_models_models_dir"]] <- xgb_models_dir
ctx$log$block_output_dirs$train_validation <- file.path(eicu_root, "step07_train_validation")
ctx$log$block_output_dirs$ml_xgboost <- dirname(xgb_models_dir)
ctx$log$block_step_counter <- 42L  # → step43_shiny_ml_app
pipeline_source_block(eng, "shiny_ml_app")
ctx <- run_block(ctx, "shiny_ml_app")
shiny_step_actual <- ctx$log$block_output_dirs[["shiny_ml_app"]] %||% shiny_step

app_dir <- file.path(shiny_step_actual, "ShinyApp")
ss_new <- file.path(app_dir, "shiny_staging.RData")
eval_new <- file.path(app_dir, "evalresult_xgboost.RData")
if (!file.exists(ss_new)) stop("未写出 shiny_staging.RData", call. = FALSE)
if (!file.exists(eval_new)) {
  file.copy(xgb_eval, eval_new, overwrite = TRUE)
}
## 若落到非标准 step，同步回 step43
if (!identical(normalizePath(shiny_step_actual, mustWork = FALSE),
               normalizePath(shiny_step, mustWork = FALSE))) {
  dir.create(file.path(shiny_step, "ShinyApp"), recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(app_dir, full.names = TRUE)) {
    file.copy(f, file.path(shiny_step, "ShinyApp", basename(f)), overwrite = TRUE)
  }
  app_dir <- file.path(shiny_step, "ShinyApp")
  ss_new <- file.path(app_dir, "shiny_staging.RData")
}
e_ss2 <- new.env(parent = emptyenv())
load(ss_new, envir = e_ss2)
ml_tag <- as.character(e_ss2$shiny_staging$ml_tag %||% "")[1L]
.log("shiny ml_tag=", ml_tag)
if (!identical(tolower(ml_tag), "xgboost")) {
  stop("shiny ml_tag 不是 xgboost: ", ml_tag, call. = FALSE)
}
## 清理 ShinyApp 内 TabPFN 部署件
for (bad in list.files(app_dir, pattern = "tabpfn", full.names = TRUE, ignore.case = TRUE)) {
  file.copy(bad, file.path(arch_dir, basename(bad)), overwrite = TRUE)
  unlink(bad)
  .log("archived TabPFN from ShinyApp: ", basename(bad))
}

## sync summary_results/Shiny + 指标根 Shiny
.sync_shiny <- function(dst_root) {
  dst_app <- file.path(dst_root, "ShinyApp")
  dir.create(dst_app, recursive = TRUE, showWarnings = FALSE)
  for (f in list.files(app_dir, full.names = TRUE)) {
    file.copy(f, file.path(dst_app, basename(f)), overwrite = TRUE)
  }
  ## 删目标内 tabpfn
  for (bad in list.files(dst_app, pattern = "tabpfn", full.names = TRUE, ignore.case = TRUE)) {
    unlink(bad)
  }
  .log("synced Shiny -> ", dst_app)
}
.sync_shiny(sum_shiny)
.sync_shiny(ix_shiny)

## ---- 4) 验证 ----
.log("--- verify ---")
fig7 <- file.path(sum_fig_pdf, fig7_name)
.tmp_v <- tempfile(fileext = ".pdf")
file.copy(fig7, .tmp_v, overwrite = TRUE)
ver_txt <- system2("pdftotext", c("-layout", .tmp_v, "-"), stdout = TRUE, stderr = FALSE)
unlink(.tmp_v)
has_xgb <- any(grepl("XGBoost", ver_txt, ignore.case = TRUE))
has_tab <- any(grepl("TabPFN", ver_txt, ignore.case = TRUE))
.log("Fig7 pdftotext XGBoost=", has_xgb, " TabPFN=", has_tab)
.log("Fig7 sample:\n", paste(utils::head(ver_txt[nzchar(ver_txt)], 8L), collapse = "\n"))

e_v <- new.env(parent = emptyenv())
load(file.path(sum_shiny, "ShinyApp", "shiny_staging.RData"), envir = e_v)
.log("summary Shiny ml_tag=", e_v$shiny_staging$ml_tag)
.log("summary Shiny evalresult=", e_v$shiny_staging$evalresult_basename)
has_eval_xgb <- file.exists(file.path(sum_shiny, "ShinyApp", "evalresult_xgboost.RData"))
has_eval_tab <- file.exists(file.path(sum_shiny, "ShinyApp", "evalresult_tabpfn.RData"))
.log("evalresult_xgboost=", has_eval_xgb, " evalresult_tabpfn=", has_eval_tab)

if (!isTRUE(has_xgb) || isTRUE(has_tab)) {
  stop("Fig7 验证失败（须有 XGBoost 且无 TabPFN）", call. = FALSE)
}
if (!identical(tolower(as.character(e_v$shiny_staging$ml_tag)[1L]), "xgboost")) {
  stop("summary Shiny ml_tag 验证失败", call. = FALSE)
}
if (!has_eval_xgb || has_eval_tab) {
  stop("Shiny 部署件验证失败（须有 xgboost、无 tabpfn）", call. = FALSE)
}

.log("=== DONE ===")
cat("\nPATHS:\n")
cat("  Fig7:  ", fig7, "\n")
cat("  Shiny: ", file.path(sum_shiny, "ShinyApp", "shiny_staging.RData"), "\n")
cat("  Log:   ", log_path, "\n")
invisible(TRUE)
