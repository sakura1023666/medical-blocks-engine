#!/usr/bin/env Rscript
# =============================================================================
#  DKD × 环境 VOC 批量流水线入口（NHANES + 并行 RCS + 飞书）
#  配置: configs/templates/config_environment_dkd_batch.template.R（默认）或 --config <外部路径>
#  引擎: R/environment_voc_batch_runner.R + R/pipeline_runner.R
#
#  阶段:
#    共享层 Step01–06 + Step11（1 次）
#    并行 Step07 rcs_nhanes（每 VOC 1 worker）
#    尾段 Step08–10 qgcomp → mediation → subgroup → Results_Summary 汇总
#
#  用法（项目根目录）:
#    Rscript run_environment_dkd_batch.R
#    Rscript run_environment_dkd_batch.R --workers auto
#    Rscript run_environment_dkd_batch.R --workers 4
#    Rscript run_environment_dkd_batch.R --shared-only
#    Rscript run_environment_dkd_batch.R --tail-only
#    Rscript run_environment_dkd_batch.R --rcs-only
#    Rscript run_environment_dkd_batch.R --only-voc DHBMA,HPMMA
#    Rscript run_environment_dkd_batch.R --no-skip
#    Rscript run_environment_dkd_batch.R --config "Output/my_study/config.R"
#
#  飞书凭证: 项目根 .env.feishu（见 R/feishu_env.R）
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

.parse_batch_args <- function(args) {
  opts <- list(
    config        = NULL,
    root          = NULL,
    workers       = NULL,
    shared_only   = FALSE,
    tail_only     = FALSE,
    rcs_only      = FALSE,
    only_voc      = NULL,
    skip_existing = TRUE,
    from          = NULL
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--workers" && i < length(args)) {
      raw_w <- trimws(args[[i + 1L]])
      opts$workers <- if (tolower(raw_w) == "auto") "auto" else as.integer(raw_w)
      i <- i + 2L
    } else if (a == "--shared-only") {
      opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--tail-only") {
      opts$tail_only <- TRUE; i <- i + 1L
    } else if (a == "--rcs-only") {
      opts$rcs_only <- TRUE; i <- i + 1L
    } else if (a == "--only-voc" && i < length(args)) {
      opts$only_voc <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else if (a == "--from" && i < length(args)) {
      opts$from <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else if (startsWith(a, "--")) {
      stop("未知参数: ", a, call. = FALSE)
    } else {
      i <- i + 1L
    }
  }
  opts
}

script_path <- .init_script_dir()
env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  script_path <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
           basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args     <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)

root_guess <- normalizePath(getwd(), winslash = "/")
if (!is.null(run_opts$root) && nzchar(run_opts$root))
  root_guess <- normalizePath(run_opts$root, winslash = "/", mustWork = TRUE)

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

config_path <- if (!is.null(run_opts$config) && nzchar(run_opts$config)) {
  normalizePath(run_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_environment_dkd_batch.template.R")
}

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
source(file.path(root, "R/environment_collect_results.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

source(file.path(root, "R/pipeline_extension_guard.R"))
.study_dir <- dirname(config_path)
pipeline_extension_guard_check(
  routine = "environment",
  pipelines = list(
    pipeline_shared = if (exists("pipeline_shared")) pipeline_shared else NULL,
    pipeline_voc_batch = if (exists("pipeline_voc_batch")) pipeline_voc_batch else NULL,
    pipeline_tail = if (exists("pipeline_tail")) pipeline_tail else NULL
  ),
  study_dir = .study_dir,
  root = root
)

options(cli.hyperlink = FALSE, warn = 1)

if (!requireNamespace("jsonlite", quietly = TRUE))
  stop("请先安装 jsonlite: install.packages('jsonlite')", call. = FALSE)

batch_run_opts <- list(
  shared_only   = run_opts$shared_only,
  tail_only     = run_opts$tail_only,
  rcs_only      = run_opts$rcs_only,
  only_voc      = run_opts$only_voc,
  skip_existing = run_opts$skip_existing,
  workers       = run_opts$workers,
  from          = run_opts$from
)

run_environment_voc_batch(
  root              = root,
  config            = config,
  pipeline_shared   = pipeline_shared,
  pipeline_voc_batch = pipeline_voc_batch,
  pipeline_tail     = pipeline_tail,
  run_opts          = batch_run_opts,
  config_path       = config_path
)
