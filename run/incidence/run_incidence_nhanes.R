#!/usr/bin/env Rscript
# =============================================================================
#  NHANES 加权单库发病入口 — 31 CRC × TyGWHtR
#  配置: config_incidence_nhanes.R（或 --config 指定）
# =============================================================================

.init_script_dir <- function() {
  sp <- tryCatch(
    normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path), winslash = "/"),
    error = function(e) NA_character_
  )
  if (!is.na(sp) && nzchar(sp)) return(sp)
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[1L])
    if (nzchar(fp)) return(normalizePath(dirname(fp), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

.extract_config_arg <- function(args, default) {
  config_val <- default
  out <- character(0)
  i <- 1L
  while (i <= length(args)) {
    if (identical(args[[i]], "--config") && i < length(args)) {
      config_val <- trimws(args[[i + 1L]]); i <- i + 2L
    } else {
      out <- c(out, args[[i]]); i <- i + 1L
    }
  }
  list(config_path = config_val, args = out)
}

script_path <- .init_script_dir()
env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  root <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) == "incidence" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

args_raw <- commandArgs(trailingOnly = TRUE)
cfg_result <- .extract_config_arg(args_raw, "")
config_path <- cfg_result$config_path
args <- cfg_result$args

if (!nzchar(config_path)) {
  stop("请指定 --config <config_incidence_nhanes.R>", call. = FALSE)
}
if (!file.exists(config_path)) {
  stop("配置文件不存在: ", config_path, call. = FALSE)
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/knhanes_survey_weight.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/index_canonical.R"))
source(file.path(root, "Blocks/00_index/01block_index.R"))
source(file.path(root, "R/pub_figure_export.R"))
source(file.path(root, "R/subgroup_forest_plot.R"))
source(file.path(root, "R/subgroup_vars.R"))
source(file.path(root, "Blocks/20_mediation/00mediation_common.R"))
source(file.path(root, "Blocks/11_logistic/00logistic_nhanes_weighted_common.R"))
source(file.path(root, "R/cross_lagged_table1_harmonize.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/pipeline_capability_layer.R"))
source(normalizePath(config_path, winslash = "/", mustWork = TRUE))
config <- cross_lagged_apply_table1_harmonized(config, root)

study_root <- normalizePath(
  config$project$root %||% dirname(config_path),
  winslash = "/",
  mustWork = TRUE
)
config$project$root <- study_root
config$project$output_dir <- config$project$output_dir %||% study_root

run_opts <- pipeline_parse_cli(args)
if (!is.null(run_opts$root) && nzchar(run_opts$root)) {
  study_root <- normalizePath(run_opts$root, winslash = "/", mustWork = TRUE)
  config$project$root <- study_root
  config$project$output_dir <- study_root
}

options(warn = 1, cli.hyperlink = FALSE)
# 保持 cwd=引擎根（Blocks/R 相对路径）；输出/checkpoint 由 config$project$output_dir 指向课题根
run_pipeline(root = root, config = config, pipeline = pipeline, run_opts = run_opts)

# ── 单库收尾：始终物化 by_index/【success】；敏感性默认开（显式 FALSE 才关）──
tryCatch({
  source(file.path(root, "R/incidence_subgroup_fallback.R"), local = FALSE)
  source(file.path(root, "R/incidence_sensitivity_suite.R"), local = FALSE)
  source(file.path(root, "R/incidence_dual_batch_runner.R"), local = FALSE)
  mat <- incidence_materialize_nhanes_success_index(
    config = config,
    pipeline = pipeline,
    study_root = study_root,
    config_path = config_path
  )
  config$incidence_batch$index_ck_base <- file.path(mat$output_base, "checkpoints", "_by_index")
  config$incidence_batch$output_base <- mat$output_base
  # 缺省/NULL → 开；仅 enable=FALSE 跳过
  if (incidence_sensitivity_suite_enabled(config)) {
    cli::cli_h1("单库发病敏感性分析（sensitivity_suite）")
    incidence_sensitivity_pass(
      root = root,
      config = config,
      indices = mat$index,
      config_path = config_path,
      only_index = mat$index,
      worker_script = "run/incidence/run_incidence_dual_batch_worker.R",
      force = TRUE
    )
  } else {
    cli::cli_alert_info("sensitivity_suite$enable=FALSE，已物化 success 目录但跳过敏感性")
  }
}, error = function(e) {
  cli::cli_alert_warning("单库 success 物化/敏感性失败: {e$message}")
})
