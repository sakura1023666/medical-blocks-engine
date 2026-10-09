#!/usr/bin/env Rscript
# =============================================================================
#  环境 VOC：剔除吸烟人群敏感性（GLM/WQS/BKMR/Qgcomp）+ 方法 FDR 表
#
#  敏感性结果写入 <project>/Sensitivity/（独立文件夹）
#  全人群方法 FDR：Results_Summary/Tables Table S20–S23（GLM/WQS/BKMR/QGC）
#  敏感性方法 FDR：Sensitivity/Tables Table SA5–SA8
#
#  用法:
#    Rscript run/environment/run_environment_sensitivity_fdr.R \
#      --config "G:/02block_result/12_Female infertility/environment_37419158/data/config_environment_infertility_batch.R"
#    Rscript ... --only fdr
#    Rscript ... --only sensitivity
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[1L])
    if (nzchar(fp)) return(normalizePath(dirname(fp), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(config = NULL, only = "all", glm_only = FALSE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--only" && i < length(args)) {
      opts$only <- tolower(trimws(args[[i + 1L]])); i <- i + 2L
    } else if (a == "--glm-only") {
      opts$glm_only <- TRUE; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$config) || !nzchar(opts$config)) {
    stop("--config 必填", call. = FALSE)
  }
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "environment" && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args <- commandArgs(trailingOnly = TRUE)
opts <- .parse_args(args)
root <- script_path
config_path <- normalizePath(opts$config, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R"))
if (exists("feishu_load_dotenv", mode = "function")) feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/environment_display_utils.R"))
source(file.path(root, "R/environment_mixture_utils.R"))
source(file.path(root, "R/environment_voc_recovery_utils.R"))
source(file.path(root, "R/environment_voc_preprocess_utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/environment_voc_batch_runner.R"))
source(file.path(root, "R/environment_voc_pub_tables.R"))
source(file.path(root, "R/environment_collect_results.R"))
source(file.path(root, "R/pub_figure_export.R"))
source(file.path(root, "R/environment_sensitivity_fdr.R"))
source(config_path)

options(cli.hyperlink = FALSE, warn = 1)
only <- opts$only

run_sens <- only %in% c("all", "sensitivity", "sens", "sa", "glm")
run_fdr  <- only %in% c("all", "fdr")
if (identical(only, "glm") || isTRUE(opts$glm_only)) {
  if (is.null(config$environment_sensitivity)) config$environment_sensitivity <- list()
  config$environment_sensitivity$glm_only <- TRUE
}

if (run_sens) {
  environment_run_exclude_smoke_sensitivity(
    root = root,
    config = config,
    pipeline_shared = if (exists("pipeline_shared")) pipeline_shared else NULL,
    pipeline_tail = if (exists("pipeline_tail")) pipeline_tail else NULL
  )
}

if (run_fdr) {
  environment_batch_collect_results_summary(config, root)
}

cli::cli_alert_success("run_environment_sensitivity_fdr 完成（only={only}）")
