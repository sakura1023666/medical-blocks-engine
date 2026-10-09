# =============================================================================
#  IPW 阿替普酶 × 肺栓塞批量 — Worker 子进程
#
#  用法:
#    Rscript run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch_worker.R \
#      --unit main --config ".../config_ipw_pe_alteplase_MIMIC.R"
#
#  unit_mode = "fixed" / unit = "main"：
#    无复合指标窄化；STEPP 横轴保持 config 中的 composite_risk。
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
if (basename(script_path) == "ipw_pe_alteplase" && basename(dirname(script_path)) == "run") {
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
alias       <- sb$shared_ck_alias %||% "column_mapping"
unit_mode   <- as.character(sb$unit_mode %||% "index")[1L]
fixed_main  <- identical(unit_mode, "fixed") || identical(unit, "main") ||
  isTRUE((config$analysis_exclusion %||% list())$allow_no_index)

config_unit <- config
output_unit <- study_batch_unit_output_dir(config, unit)
config_unit$project$output_dir       <- output_unit
config_unit$study_batch$active_unit  <- unit
config_unit$study_batch$row_filter   <- NULL
config_unit$study_batch$worker_blocks <- NULL

.write_status <- function(status, error_message = NULL, ctx = NULL) {
  elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
  failed_stage <- if (!identical(status, "success")) {
    study_batch_infer_failed_stage(error_message)
  } else {
    NA_character_
  }
  n_exposed <- NA_integer_
  n_event   <- NA_integer_
  univar_cov <- character(0)
  lasso_cov  <- character(0)
  final_cov  <- character(0)
  if (!is.null(ctx)) {
    exposure_info <- ctx$results$ipw_alteplase_exposure %||%
      ctx$results$ipw_diabetes_exposure %||% list()
    n_exposed <- suppressWarnings(as.integer(
      exposure_info$n_exposed %||% exposure_info$n_diabetes %||% NA_integer_
    ))[1L]
    n_event <- suppressWarnings(as.integer(exposure_info$n_event %||% NA_integer_))[1L]
    univar_cov <- as.character(ctx$results$univar_features %||% character(0))
    lasso_cov  <- as.character(ctx$results$feature_selection_by_model$lasso %||% character(0))
    final_cov  <- as.character(ctx$results$feature_selection_by_model$random_forest %||% character(0))
  }
  fields <- list(
    unit                  = unit,
    index                 = if (fixed_main) "composite_risk" else unit,
    status                = status,
    db_mode               = config_unit$project$database %||% "batch",
    error_message         = error_message,
    failed_stage          = failed_stage,
    n_exposed             = n_exposed,
    n_alteplase           = n_exposed,
    n_event               = n_event,
    univariate_covariates = univar_cov,
    lasso_covariates      = lasso_cov,
    final_covariates      = final_cov,
    elapsed_sec           = elapsed,
    disease               = (config_unit$feishu %||% list())$disease_label %||%
      config_unit$project$disease %||% "",
    protocol              = (config_unit$feishu %||% list())$protocol_label %||% ""
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

cli::cli_h1("IPW PE Alteplase Worker: {unit} (mode={unit_mode})")

# ---- 1) 复制共享层 checkpoint ----------------------------------------------
if (!study_batch_copy_shared_ck(shared_ck, unit_ck, alias)) {
  .write_status("failed", paste0("复制共享 checkpoint 失败 (alias=", alias, ")"))
  quit(save = "no", status = 1)
}

initial_ctx <- tryCatch(
  study_batch_load_checkpoint_ctx(unit_ck, alias),
  error = function(e) {
    tryCatch(
      study_batch_load_checkpoint_ctx(unit_ck, "index"),
      error = function(e2) {
        .write_status("failed", conditionMessage(e2))
        quit(save = "no", status = 1)
      }
    )
  }
)

# ---- 2) 指标窄化（仅旧 index 模式）------------------------------------------
if (!fixed_main) {
  all_units <- as.character(sb$units %||% character(0))
  other_units <- setdiff(all_units, unit)

  .narrow_ctx_to_unit <- function(d, unit, other_units) {
    if (is.null(d) || !is.data.frame(d) || !nrow(d)) return(d)
    drop_cols <- intersect(other_units, names(d))
    if (length(drop_cols)) d <- d[, setdiff(names(d), drop_cols), drop = FALSE]
    if (unit %in% names(d)) {
      d <- d[!is.na(d[[unit]]), , drop = FALSE]
    }
    d
  }

  for (slot in c("raw", "cleaned", "imputed")) {
    if (!is.null(initial_ctx$data[[slot]])) {
      n_before <- nrow(initial_ctx$data[[slot]])
      initial_ctx$data[[slot]] <- .narrow_ctx_to_unit(initial_ctx$data[[slot]], unit, other_units)
      n_after <- nrow(initial_ctx$data[[slot]])
      if (n_before != n_after) {
        cli::cli_alert_info(
          "[{unit}] data${slot}: 丢弃其它指标列 + 滤 NA，{n_before} -> {n_after} 行"
        )
      }
    }
  }
  main_slot_n <- nrow(initial_ctx$data$imputed %||% initial_ctx$data$cleaned %||% initial_ctx$data$raw %||% data.frame())
  if (!is.finite(main_slot_n) || main_slot_n <= 0L) {
    .write_status("failed", paste0("BASELINE_INDEX_NS_STOP: ", unit, " 滤 NA 后样本量为 0"))
    quit(save = "no", status = 1)
  }
}

# ---- 3) patch config -------------------------------------------------------
config_unit$analysis_exclusion <- config_unit$analysis_exclusion %||% list()
config_unit$study_batch <- config_unit$study_batch %||% list()
config_unit$study_batch$active_unit <- unit

if (fixed_main) {
  config_unit$analysis_exclusion$allow_no_index <- TRUE
  config_unit$analysis_exclusion$index_var <- NULL
  config_unit$incidence <- config_unit$incidence %||% list()
  config_unit$incidence$index_var <- NULL
  config_unit$stepp_prognosis <- config_unit$stepp_prognosis %||% list()
  if (!nzchar(as.character(config_unit$stepp_prognosis$index_var %||% "")[1L])) {
    config_unit$stepp_prognosis$index_var <- "composite_risk"
  }
} else {
  config_unit$incidence <- config_unit$incidence %||% list()
  config_unit$incidence$index_var <- unit
  config_unit$analysis_exclusion$index_var <- unit
  config_unit$stepp_prognosis <- config_unit$stepp_prognosis %||% list()
  config_unit$stepp_prognosis$index_var <- unit
  config_unit$stepp_prognosis$hist_x_label <- unit
  config_unit$stepp_prognosis$x_axis_label <- paste0(unit, " (Subpopulation Median)")

  config_unit$imputation <- config_unit$imputation %||% list()
  all_units <- as.character(sb$units %||% character(0))
  other_units <- setdiff(all_units, unit)
  config_unit$imputation$force_keep_columns <- unique(c(
    as.character(config_unit$imputation$force_keep_columns %||% character(0)),
    unit
  ))
  config_unit$imputation$table_s1_exclude_vars <- unique(c(
    as.character(config_unit$imputation$table_s1_exclude_vars %||% character(0)),
    other_units
  ))
  config_unit$univariate_prognosis <- config_unit$univariate_prognosis %||% list()
  config_unit$univariate_prognosis$excluded_predictors <- unique(c(
    as.character(config_unit$univariate_prognosis$excluded_predictors %||% character(0)),
    other_units
  ))
}

initial_ctx <- study_batch_apply_row_filter(initial_ctx, config_unit)

# ---- 4) 跑 pipeline_unit ----------------------------------------------------
worker_blocks <- as.character(config_unit$study_batch$worker_blocks %||% character(0))
if (!length(worker_blocks) && !is.null(pipeline_unit)) {
  worker_blocks <- as.character(pipeline_unit$blocks %||% character(0))
}
if (!length(worker_blocks)) stop("未配置 worker_blocks", call. = FALSE)

pl <- pipeline_unit %||% list(
  name = paste0(config$pipeline$name %||% "ipw_pe_alteplase", "_unit"),
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
  failed_ctx <- tryCatch({
    ck_files <- list.files(unit_ck, pattern = "\\.rds$", full.names = TRUE)
    if (!length(ck_files)) {
      NULL
    } else {
      ck_files <- ck_files[order(file.info(ck_files)$mtime, decreasing = TRUE)]
      readRDS(ck_files[[1L]])$ctx
    }
  }, error = function(e2) NULL)
  .write_status("failed", conditionMessage(e), ctx = failed_ctx)
  cli::cli_alert_danger("{unit}: {conditionMessage(e)}")
  quit(save = "no", status = 1)
})
