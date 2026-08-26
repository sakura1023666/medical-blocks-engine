#!/usr/bin/env Rscript
# =============================================================================
#  SLE → AKI 发病 + 28 天预后 两阶段单库 batch 入口
#  配置: --config <研究 config>；默认模板 configs/templates/config_sle_aki_inc_prog_batch.template.R
#  引擎: R/ip_two_stage_batch_runner.R + R/pipeline_runner.R
#
#  用法（项目根目录）:
#    Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R --config "G:/02block_result/29_SLE/.../config_sle_aki_inc_prog_batch.R"
#    Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R --config ... --workers 4
#    Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R --config ... --shared-only
#    Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R --config ... --only-index NLR --workers 1
#    Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R --config ... --no-skip
#    Rscript run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch.R --config ... --only-index NLR --from rcs_incidence --to subgroup_incidence
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
    only_index    = NULL,
    skip_existing = TRUE,
    from          = NULL,
    to            = NULL
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
    } else if (a == "--only-index" && i < length(args)) {
      opts$only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else if (a == "--from" && i < length(args)) {
      opts$from <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--to" && i < length(args)) {
      opts$to <- trimws(args[[i + 1L]]); i <- i + 2L
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
} else if (basename(script_path) %in% c(
  "environment", "incidence", "survival", "feishu", "hf", "sle_aki_inc_prog"
) && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args     <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)

root_guess <- normalizePath(getwd(), winslash = "/")
if (!is.null(run_opts$root) && nzchar(run_opts$root)) {
  root_guess <- normalizePath(run_opts$root, winslash = "/", mustWork = TRUE)
}

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

config_path <- if (!is.null(run_opts$config) && nzchar(run_opts$config)) {
  normalizePath(run_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_sle_aki_inc_prog_batch.template.R")
}

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/model3_required.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/incidence_sensitivity_suite.R"))
source(file.path(root, "R/incidence_subgroup_fallback.R"))
source(file.path(root, "R/index_code_bundle.R"))
source(file.path(root, "R/ip_two_stage_batch_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

options(cli.hyperlink = FALSE)
options(warn = 1)
if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("请先安装 jsonlite 包: install.packages('jsonlite')", call. = FALSE)
}

ip_two_stage_batch_run(
  root                  = root,
  config                = config,
  pipeline_shared       = pipeline_shared,
  pipeline_stage1       = pipeline_stage1,
  pipeline_stage2       = pipeline_stage2,
  pipeline_regular_batch = if (exists("pipeline_regular_batch")) pipeline_regular_batch else NULL,
  run_opts              = run_opts,
  config_path           = config_path
)
