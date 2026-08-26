#!/usr/bin/env Rscript
# =============================================================================
#  骨质疏松环境暴露 — 两阶段全量重跑
#    阶段1: BKMR iter=100 + 全流程；按 config 中 RCS 模型（默认 crude）筛查
#    阶段2: 剔除 RCS 不显著 VOC 后，BKMR iter=1000（或 config 终跑值）从头重跑
#    跑完自动导出 VOC Table S3/S4（与临床表同版式）
#
#  用法:
#    Rscript run/environment/run_environment_osteo_fuben_orchestrated.R \
#      --config "/mnt/g/02block_result/10_osteoporosis - 副本/environment_37419158/config_environment_osteo_fuben_batch.R"
#    Rscript ... --phase clean-only
#    Rscript ... --phase 1
#    Rscript ... --phase 2
#    Rscript ... --phase auto   # 默认
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

.parse_orch_args <- function(args) {
  opts <- list(config = NULL, phase = "auto", workers = "auto")
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--phase" && i < length(args)) {
      opts$phase <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--workers" && i < length(args)) {
      opts$workers <- trimws(args[[i + 1L]]); i <- i + 2L
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

args  <- commandArgs(trailingOnly = TRUE)
opts  <- .parse_orch_args(args)
root  <- script_path
config_path <- normalizePath(opts$config, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)
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
source(file.path(root, "R/environment_fuben_orchestrator.R"))
source(file.path(root, "R/environment_collect_results.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

options(cli.hyperlink = FALSE, warn = 1)

run_environment_fuben_orchestrated(
  root               = root,
  config             = config,
  pipeline_shared    = pipeline_shared,
  pipeline_voc_batch = pipeline_voc_batch,
  pipeline_tail      = pipeline_tail,
  config_path        = config_path,
  phase              = opts$phase,
  workers            = opts$workers
)
