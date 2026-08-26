#!/usr/bin/env Rscript
# =============================================================================
#  通用 Study Batch Worker — 单 unit 并行子进程
#
#  用法:
#    Rscript run/study/run_study_batch_worker.R --unit CHARLS
#    Rscript run/study/run_study_batch_worker.R --unit rcs --config configs/...
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_worker_args <- function(args) {
  opts <- list(unit = NULL, root = NULL, config = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) {
      opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$unit) || !nzchar(opts$unit)) stop("--unit 参数必填", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "study" && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

root_guess <- normalizePath(getwd(), winslash = "/")
if (!is.null(wk_opts$root) && nzchar(wk_opts$root))
  root_guess <- normalizePath(wk_opts$root, winslash = "/", mustWork = TRUE)

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

unit    <- wk_opts$unit
t_start <- proc.time()

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/mi_rubin_pool.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "R/rscript_study.R"))

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  stop("Worker 需要 --config 指定 batch 配置文件", call. = FALSE)
}
source(config_path)

if (!requireNamespace("jsonlite", quietly = TRUE))
  stop("请先安装 jsonlite", call. = FALSE)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

sb          <- config$study_batch %||% list()
output_base <- sb$output_base %||% config$project$output_dir
shared_ck   <- study_batch_shared_ck_dir(config)
unit_ck     <- study_batch_unit_ck_dir(config, unit)
alias       <- sb$shared_ck_alias %||% "index"

config_unit <- study_batch_patch_config_for_unit(config, unit)
output_unit <- study_batch_unit_output_dir(config, unit)

.write_status <- function(status, error_message = NULL, ctx = NULL) {
  elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
  failed_stage <- if (!identical(status, "success")) {
    study_batch_infer_failed_stage(error_message)
  } else {
    NA_character_
  }
  traj_k <- NA_character_
  m2 <- character(0)
  m3 <- character(0)
  final_cov <- character(0)
  if (!is.null(ctx)) {
    traj_k <- as.character(
      ctx$results$competing_trajectory_class$optimal_K %||%
        ctx$results$competing_index_exposure$trajectory$optimal_K %||%
        NA_character_
    )[1L]
    covs <- ctx$results$competing_model_covs %||% list()
    m2 <- as.character(covs$m2 %||% character(0))
    m3 <- as.character(covs$m3 %||% character(0))
    final_cov <- as.character(
      ctx$results$feature_selection_by_model$random_forest %||% m3
    )
  }
  fields  <- list(
    unit               = unit,
    index              = unit,
    status             = status,
    db_mode            = config_unit$project$database %||% "batch",
    error_message      = error_message,
    failed_stage       = failed_stage,
    trajectory_k       = traj_k,
    model2_covariates  = m2,
    model3_covariates  = m3,
    final_covariates   = final_cov,
    elapsed_sec        = elapsed,
    disease            = (config_unit$feishu %||% list())$disease_label %||%
      config_unit$project$disease %||% "",
    protocol           = (config_unit$feishu %||% list())$protocol_label %||% ""
  )
  study_batch_write_status(output_unit, fields)
  if (isTRUE((config_unit$feishu %||% list())$enable) &&
      exists("incidence_batch_feishu_push_result", mode = "function")) {
    tryCatch(
      incidence_batch_feishu_push_result(config_unit, fields),
      error = function(e) cli::cli_alert_warning("飞书推送异常: {e$message}")
    )
  }
}

cli::cli_h1("Study Worker: {unit}")

if (!study_batch_copy_shared_ck(shared_ck, unit_ck, alias)) {
  .write_status("failed", "复制共享 checkpoint 失败")
  quit(save = "no", status = 1)
}

initial_ctx <- tryCatch(
  study_batch_load_checkpoint_ctx(unit_ck, alias),
  error = function(e) {
    .write_status("failed", conditionMessage(e))
    quit(save = "no", status = 1)
  }
)
initial_ctx <- study_batch_apply_row_filter(initial_ctx, config_unit)

worker_blocks <- as.character(config_unit$study_batch$worker_blocks %||% character(0))
if (!length(worker_blocks) && !is.null(pipeline_unit)) {
  worker_blocks <- as.character(pipeline_unit$blocks %||% character(0))
}
if (!length(worker_blocks)) stop("未配置 worker_blocks", call. = FALSE)

pl <- pipeline_unit %||% list(
  name = paste0(config$pipeline$name %||% "study", "_unit"),
  blocks = worker_blocks,
  checkpoint = list(enable = TRUE, dir = unit_ck)
)
if (!length(pl$blocks)) pl$blocks <- worker_blocks
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir    <- unit_ck

tryCatch({
  final_ctx <- run_pipeline(
    root,
    config   = config_unit,
    pipeline = pl,
    run_opts = list(initial_ctx = initial_ctx, only = worker_blocks)
  )
  .write_status("success", ctx = final_ctx)
  cli::cli_alert_success("{unit}: 完成")
  quit(save = "no", status = 0)
}, error = function(e) {
  # 早停/失败时尽量从最近 checkpoint 回填轨迹 K 与协变量元数据
  failed_ctx <- tryCatch({
    ck_files <- list.files(unit_ck, pattern = "\\.rds$", full.names = TRUE)
    if (!length(ck_files)) {
      NULL
    } else {
      ck_files <- ck_files[order(file.info(ck_files)$mtime, decreasing = TRUE)]
      readRDS(ck_files[[1L]])
    }
  }, error = function(e2) NULL)
  .write_status("failed", conditionMessage(e), ctx = failed_ctx)
  cli::cli_alert_danger("{unit}: {conditionMessage(e)}")
  quit(save = "no", status = 1)
})
