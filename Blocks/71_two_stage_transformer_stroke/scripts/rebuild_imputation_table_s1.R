#!/usr/bin/env Rscript
# 重建插补前后 Table S1（SCI 三线表），并与时序删人后的分析队列对齐。
#
# 用法（任意 TST 课题可复用）:
#   Rscript Blocks/71_two_stage_transformer_stroke/scripts/rebuild_imputation_table_s1.R \
#     --project-root /path/to/study_output \
#     [--repo /path/to/01Block-new-Final] \
#     [--copy-summary TRUE]
#
# 为何旁路脚本而不是只靠 imputation block:
#   tst_timeseries 会按患者缺失阈值裁剪 imputed，但插补块若
#   export_table_s1=FALSE，则需在汇总阶段用「分析队列 ID」重出 S1。
#   新流水线顺序：tst_split → imputation(fit_on=train) → tst_timeseries；
#   checkpoint 步号随 blocks 变化，本脚本按目录名匹配 step*imputation / step*tst_timeseries。

args <- commandArgs(trailingOnly = TRUE)
`.arg` <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && !nzchar(as.character(a)[1L]))) b else a

project_root <- as.character(.arg("--project-root", Sys.getenv("TST_PROJECT_ROOT", "")))[1L]
repo <- as.character(.arg("--repo", Sys.getenv("MEDICAL_BLOCKS_ROOT", "")))[1L]
copy_summary <- toupper(as.character(.arg("--copy-summary", "TRUE")[1L])) %in% c("TRUE", "1", "YES")

if (!nzchar(project_root) || !dir.exists(project_root)) {
  stop("Need --project-root pointing to study output_dir", call. = FALSE)
}
if (!nzchar(repo) || !dir.exists(repo)) {
  cmd_args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", cmd_args[grepl("^--file=", cmd_args)])
  if (length(file_arg) && nzchar(file_arg[1L])) {
    # .../Blocks/71_.../scripts/this.R → engine root = ../../..
    repo <- normalizePath(file.path(dirname(file_arg[1L]), "..", "..", ".."), winslash = "/", mustWork = FALSE)
  } else {
    repo <- getwd()
  }
}
if (!file.exists(file.path(repo, "R/utils.R"))) {
  stop("Cannot locate engine root (R/utils.R). Pass --repo.", call. = FALSE)
}

setwd(repo)
source("R/utils.R")
env <- new.env(parent = globalenv())
env$register_block <- function(...) invisible(NULL)
sys.source("Blocks/03_imputation/01block_imputation.R", envir = env)
suppressPackageStartupMessages(library(data.table))

ck_dir <- file.path(project_root, "checkpoints/_shared/main")
ck4_cands <- list.files(ck_dir, pattern = "step\\d+_imputation\\.rds$", full.names = TRUE)
ck5_cands <- list.files(ck_dir, pattern = "step\\d+_tst_timeseries\\.rds$", full.names = TRUE)
ck4_path <- if (length(ck4_cands)) ck4_cands[[length(ck4_cands)]] else
  file.path(ck_dir, "step04_imputation.rds")
ck5_path <- if (length(ck5_cands)) ck5_cands[[length(ck5_cands)]] else
  file.path(ck_dir, "step05_tst_timeseries.rds")
hourly_cands <- list.files(
  file.path(project_root, "_shared"),
  pattern = "_tst_hourly_long\\.csv$",
  recursive = TRUE, full.names = TRUE
)
hourly <- if (length(hourly_cands)) {
  hit <- hourly_cands[grepl("tst_timeseries", hourly_cands)]
  if (length(hit)) hit[[1L]] else hourly_cands[[1L]]
} else {
  file.path(project_root, "_shared/step05_tst_timeseries/Tables/_tst_hourly_long.csv")
}
if (!file.exists(ck4_path) || !file.exists(ck5_path)) {
  stop("Missing imputation/timeseries checkpoints under ", ck_dir, call. = FALSE)
}

ck4 <- readRDS(ck4_path)
ck5 <- readRDS(ck5_path)
cfg <- ck5$ctx$config

elig <- character(0)
if (file.exists(hourly)) {
  elig <- unique(as.character(data.table::fread(hourly, select = "patient")$patient))
} else {
  # fallback: timeseries result ids
  elig <- as.character(ck5$ctx$results$tst_timeseries$eligible_ids %||% character(0))
}
if (!length(elig)) {
  stop("No eligible analysis-cohort IDs (hourly long / eligible_ids empty)", call. = FALSE)
}

after <- as.data.frame(ck5$ctx$data$imputed)
idc <- if ("tst_patient_id" %in% names(after)) "tst_patient_id" else if ("stay_id" %in% names(after)) "stay_id" else names(after)[1L]
after <- after[as.character(after[[idc]]) %in% elig, , drop = FALSE]

# fit_on=train 时 data_before_mi 只有训练集；分析队列 S1 必须用插补前全宽表
before <- ck4$ctx$data$mapped
if (is.null(before)) before <- ck4$ctx$data$cleaned
if (is.null(before)) before <- ck4$ctx$results$data_before_mi
before <- as.data.frame(before)
idb <- if (idc %in% names(before)) idc else if ("tst_patient_id" %in% names(before)) "tst_patient_id" else "stay_id"
before <- before[as.character(before[[idb]]) %in% elig, , drop = FALSE]
common <- intersect(names(before), names(after))
# 结局 / 时间 / 预测标签不得进 Table S1（否则 After MI 会出现假水平名）
outcome_drop <- unique(c(
  as.character(cfg$data$outcome_column %||% character(0)),
  as.character((cfg$survival %||% list())$event_var %||% character(0)),
  as.character((cfg$survival %||% list())$time_var %||% character(0)),
  "is_hosp_dead", "is hosp dead", "fustatus", "futime",
  "is_icu_dead", "is_dead", "is_hosp_dead",
  "death_within_hosp_28days", "death_within_icu_28days",
  "death_within_hosp_28d", "death_within_icu_28d",
  "Disease", "AKI TwoStageTransformer", "No AKI TwoStageTransformer"
))
outcome_drop <- outcome_drop[nzchar(outcome_drop)]
common <- setdiff(common, outcome_drop)
# 大小写不敏感再扫一轮
common_lc <- tolower(common)
drop_lc <- tolower(outcome_drop)
common <- common[!common_lc %in% drop_lc]
# 名称含 hosp dead / fustatus 的列
common <- common[!grepl("hosp.?dead|fustatus|futime", common, ignore.case = TRUE)]
before <- before[, common, drop = FALSE]
after <- after[, common, drop = FALSE]
cli::cli_alert_info("S1 rebuild: before={nrow(before)} after={nrow(after)} cols={length(common)} (outcome dropped)")

# 表题：分析队列描述；若 fit_on=train，脚注式写明 MICE 仅在训练集拟合
imp_cfg <- cfg$imputation %||% list()
fit_on <- tolower(trimws(as.character(imp_cfg$fit_on %||% "all")[1L]))
imp_cfg$table_s1_title <- if (identical(fit_on, "train")) {
  "Baseline characteristics before and after imputation (analysis cohort; MICE fitted on training split only)"
} else {
  "Baseline characteristics before and after imputation (analysis cohort)"
}
imp_cfg$table_s1_exclude_vars <- unique(c(
  as.character(imp_cfg$table_s1_exclude_vars %||% character(0)),
  outcome_drop
))
cfg$imputation <- imp_cfg

ctx <- ck5$ctx
ctx$config <- cfg
options(pipeline.database_name = as.character(cfg$project$database %||% cfg$project$database_type %||% "MIMIC")[1L])
imp_dirs <- list.files(
  file.path(project_root, "_shared"),
  pattern = "^step\\d+_imputation$",
  full.names = TRUE
)
ctx$output_dir <- if (length(imp_dirs)) imp_dirs[[length(imp_dirs)]] else
  file.path(project_root, "_shared/step05_imputation")
ctx$output_dir_tables <- file.path(ctx$output_dir, "Tables")
ctx$output_dir_figures <- file.path(ctx$output_dir, "Figures")
dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
old_unk <- list.files(ctx$output_dir_tables, pattern = "UnknownDB.*imputation", full.names = TRUE)
if (length(old_unk)) unlink(old_unk)

imp_cfg <- cfg$imputation %||% list()
ctx <- env$.imp01_build_table_s1(
  ctx, cfg, before, after,
  table_strata = NULL,
  analysis_grp = NULL,
  reference_grp = NULL,
  imp_cfg = imp_cfg
)
ctx <- render_queued_tables(ctx)
if (exists("flush_pub_output_queues", mode = "function")) {
  ctx <- flush_pub_output_queues(ctx)
}

outs <- list.files(ctx$output_dir_tables, pattern = "before and after imputation.*\\.xlsx$", full.names = TRUE)
cli::cli_alert_info("produced: {paste(basename(outs), collapse = ', ')}")
if (!length(outs)) stop("no imputation xlsx written", call. = FALSE)
# 禁止按字母序误拷 validation S1b（(validation 会排在无括号文件前面）
prefer <- outs[grepl("analysis cohort", basename(outs), ignore.case = TRUE)]
if (!length(prefer)) {
  prefer <- outs[!grepl("validation set", basename(outs), ignore.case = TRUE)]
}
src_xlsx <- if (length(prefer)) prefer[[length(prefer)]] else outs[[length(outs)]]

if (isTRUE(copy_summary)) {
  db <- as.character(cfg$project$database %||% "MIMIC")[1L]
  dest_dir <- file.path(project_root, "summary_results", "Tables")
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  dest <- file.path(
    dest_dir,
    sprintf("Table S1-%s. Baseline characteristics before and after imputation (analysis cohort).xlsx", db)
  )
  # 清理旧 training-set / 误拷 validation 文件名
  old_train <- list.files(
    dest_dir,
    pattern = "^Table S1-.*imputation \\((training set|validation set).*\\)\\.xlsx$",
    full.names = TRUE
  )
  if (length(old_train)) unlink(old_train)
  file.copy(src_xlsx, dest, overwrite = TRUE)
  cli::cli_alert_success("copied {basename(src_xlsx)} -> {dest}")
}
invisible(outs[[1]])
