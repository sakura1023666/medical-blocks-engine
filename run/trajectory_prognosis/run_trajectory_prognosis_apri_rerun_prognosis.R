#!/usr/bin/env Rscript
# 重跑预后前缀：imputation → index → baseline_binary → 单/多因素 → VIF
# 若单元检查点含 trajectory_jlcm，则续跑 trajectory_baseline_by_class（Table S5）
#
# 用法:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_rerun_prognosis.R \
#     --config configs/templates/config_trajectory_prognosis_batch.template.R --unit NLR

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(unit = "NLR", config = NULL, dbs = c("eicu", "mimic"))
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) { opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--config" && i < length(args)) { opts$config <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--db" && i < length(args)) { opts$dbs <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]; i <- i + 2L }
    else i <- i + 1L
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
opt  <- .parse_args(args)
ix   <- opt$unit

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

config_path <- if (!is.null(opt$config) && nzchar(opt$config)) {
  normalizePath(opt$config, winslash = "/", mustWork = TRUE)
} else file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

config_ix <- trajectory_batch_patch_config_for_index(config, ix)

prognosis_blocks <- c(
  "imputation", "index", "baseline_binary",
  "univariate_prognosis", "multicollinearity_screen",
  "multivariate_prognosis", "multivariate_covariate_resolve", "multicollinearity_final"
)

.attach_jlcm_class <- function(ctx, ck_dir, ix) {
  f <- file.path(ck_dir, "trajectory_jlcm.rds")
  if (!file.exists(f)) return(ctx)
  o <- tryCatch(readRDS(f), error = function(e) NULL)
  if (is.null(o) || is.null(o$ctx)) return(ctx)
  jctx <- o$ctx
  col <- paste0("trajectory_class_", ix)
  if (!col %in% names(jctx$data$imputed %||% list()) &&
      !"trajectory_class" %in% names(jctx$data$imputed %||% list())) return(ctx)
  d_new <- ctx$data$imputed %||% ctx$data$cleaned
  d_old <- jctx$data$imputed %||% jctx$data$cleaned
  idc <- ctx$config$data$id_column %||% "subject_id"
  if (!idc %in% names(d_new) || !idc %in% names(d_old)) return(ctx)
  cls_col <- if (col %in% names(d_old)) col else "trajectory_class"
  tab <- unique(d_old[, c(idc, cls_col), drop = FALSE])
  names(tab) <- c(idc, "trajectory_class")
  d_new[[idc]] <- as.character(d_new[[idc]])
  tab[[idc]] <- as.character(tab[[idc]])
  d_new <- dplyr::left_join(d_new, tab, by = idc)
  ctx$data$imputed <- d_new
  if (!is.null(jctx$results$trajectory_jlcm_models)) {
    ctx$results$trajectory_jlcm_models <- jctx$results$trajectory_jlcm_models
  }
  ctx$results[[paste0("trajectory_class_", ix)]] <- d_new$trajectory_class
  ctx$data$imputed[[paste0("trajectory_class_", ix)]] <- d_new$trajectory_class
  cli::cli_alert_info("已从 JLCM 检查点回写 trajectory_class（Table S5 用）")
  ctx
}

for (db in opt$dbs) {
  cli::cli_h1("[{ix}] {toupper(db)} — 重跑预后前缀（含复合指标 + 生命体征 median IQR）")
  shared_ck <- trajectory_batch_shared_ck_dir(config_ix, db)
  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(shared_ck, "trajectory_calc_28d_index"),
    error = function(e) { cli::cli_alert_danger("载入共享检查点失败: {conditionMessage(e)}"); NULL }
  )
  if (is.null(ctx)) next

  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg_db <- config_ix
  cfg_db$project$database   <- db_cfg$name %||% toupper(db)
  cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, db)
  if (!is.null(cfg_db$trajectory_jlcm$rawdata_path_template)) {
    cfg_db$trajectory_jlcm$rawdata_path_template <- gsub("\\{db\\}", db, cfg_db$trajectory_jlcm$rawdata_path_template)
  }
  ctx$config <- cfg_db
  ctx$root_output_dir <- cfg_db$project$output_dir

  ck_dir <- trajectory_batch_index_ck_dir(config_ix, ix, db)
  traj_util <- file.path(root, "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) {
    source(traj_util, local = FALSE)
    id_col <- cfg_db$data$id_column %||% "subject_id"
    wide_tpl <- cfg_db$trajectory_jlcm$rawdata_path_template %||% NULL
    wide_path <- if (!is.null(wide_tpl)) gsub("\\{Index\\}", ix, wide_tpl) else NULL
    for (slot in c("cleaned", "mapped", "imputed")) {
      if (is.null(ctx$data[[slot]])) next
      d <- ctx$data[[slot]]
      if (exists("trajectory_coerce_vital_numeric", mode = "function"))
        d <- trajectory_coerce_vital_numeric(d)
      if (!is.null(wide_path) && exists("trajectory_merge_wide_baseline_index", mode = "function"))
        d <- trajectory_merge_wide_baseline_index(d, wide_path, ix, id_col, day = 1L)
      ctx$data[[slot]] <- d
    }
  }

  pl <- pipeline_unit
  pl$checkpoint <- list(enable = TRUE, dir = ck_dir)

  ok <- tryCatch({
    run_pipeline(root, config = cfg_db, pipeline = pl,
                 run_opts = list(initial_ctx = ctx, only = prognosis_blocks))
    TRUE
  }, error = function(e) { cli::cli_alert_danger("{conditionMessage(e)}"); FALSE })
  if (!ok) next
  cli::cli_alert_success("[{ix}/{toupper(db)}] 预后前缀完成")

  # Table S5：有 JLCM 检查点时仅重跑 baseline_by_class
  if (file.exists(file.path(ck_dir, "trajectory_jlcm.rds"))) {
    ctx2 <- tryCatch(
      study_batch_load_checkpoint_ctx(ck_dir, "multicollinearity_final"),
      error = function(e) NULL
    )
    if (!is.null(ctx2)) {
      ctx2 <- .attach_jlcm_class(ctx2, ck_dir, ix)
      ctx2$config <- cfg_db
      ctx2$root_output_dir <- cfg_db$project$output_dir
      pl2 <- pipeline_unit
      pl2$checkpoint <- list(enable = TRUE, dir = ck_dir)
      tryCatch({
        run_pipeline(root, config = cfg_db, pipeline = pl2,
                     run_opts = list(initial_ctx = ctx2, only = "trajectory_baseline_by_class"))
        cli::cli_alert_success("[{ix}/{toupper(db)}] Table S5 (baseline_by_class) 已更新")
      }, error = function(e) cli::cli_alert_warning("Table S5 更新失败: {conditionMessage(e)}"))
    }
  }
}
