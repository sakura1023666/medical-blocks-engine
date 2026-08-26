#!/usr/bin/env Rscript
# =============================================================================
#  预后双库批量多指标流水线入口
#  配置: configs/templates/config_survival_dual_batch.template.R（默认）或 --config <外部路径>
#  引擎: R/survival_dual_batch_runner.R + R/pipeline_runner.R
#
#  用法（项目根目录）:
#    Rscript run/survival/run_survival_dual_batch.R
#    Rscript run/survival/run_survival_dual_batch.R --workers auto
#    Rscript run/survival/run_survival_dual_batch.R --workers 8
#    Rscript run/survival/run_survival_dual_batch.R --shared-only
#    Rscript run/survival/run_survival_dual_batch.R --only-index NLR,SII,RAR
#    Rscript run/survival/run_survival_dual_batch.R --no-skip
#    Rscript run/survival/run_survival_dual_batch.R --sensitivity-only
#    Rscript run/survival/run_survival_dual_batch.R --sensitivity-only --only-scenario SA_complete_case
#    Rscript run/survival/run_survival_dual_batch.R --subgroup-fallback-only
#    Rscript run/survival/run_survival_dual_batch.R --config "G:/02block_result/.../config.R"
#
#  定向重跑某块（复用已有 checkpoint，不重跑全链，适合改完引擎后补刷结果表）:
#    # 用 worker 直调（无 orchestrator 开销，最常用）:
#    Rscript run/survival/run_survival_dual_batch_worker.R \
#            --config "G:/02block_result/11_ischemic stroke/prognosis_38902748/config_survival.R" \
#            --index APRI --from km_strata --to segmented_cox_binary
#    # --from <ck名>  = 从该 checkpoint 之后开始（不含该块本身）
#    # --to   <块名>  = 跑到该块为止（含）
#    # --blocks A,B,C = 只跑逗号列表中的块（优先于 --from/--to）
#    # 典型场景：引擎改了 segmented_cox_binary 后补刷全研究 S11：
#    # for ix in APRI BAR NLR ...; do
#    #   Rscript run/survival/run_survival_dual_batch_worker.R \
#    #     --config ".../config_survival.R" --index $ix \
#    #     --from km_strata --to segmented_cox_binary; done
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
    db_mode       = NULL,
    shared_only   = FALSE,
    only_index    = NULL,
    skip_existing = TRUE,
    # NULL = 沿用 config$survival_batch$trim_quantile（未设时 runner 再回退默认）
    p_trim        = NULL,
    subgroup_fallback_only = FALSE,
    sfb_only_index = NULL,
    sensitivity_only = FALSE,
    only_scenario = NULL
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
    } else if (a == "--db" && i < length(args)) {
      opts$db_mode <- tolower(trimws(args[[i + 1L]])); i <- i + 2L
    } else if (a == "--shared-only") {
      opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--only-index" && i < length(args)) {
      opts$only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else if (a == "--ptrim" && i < length(args)) {
      opts$p_trim <- as.numeric(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--subgroup-fallback-only") {
      opts$subgroup_fallback_only <- TRUE
      if (i < length(args) && !startsWith(args[[i + 1L]], "--")) {
        opts$sfb_only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
        i <- i + 2L
      } else {
        i <- i + 1L
      }
    } else if (a == "--sensitivity-only") {
      opts$sensitivity_only <- TRUE
      i <- i + 1L
    } else if (a == "--only-scenario" && i < length(args)) {
      opts$only_scenario <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
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
  file.path(root, "configs/templates/config_survival_dual_batch.template.R")
}

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/model3_required.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/cox_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/survival_dual_batch_runner.R"))
source(file.path(root, "R/incidence_subgroup_fallback.R"))
source(file.path(root, "R/incidence_sensitivity_suite.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

source(file.path(root, "R/pipeline_extension_guard.R"))
.study_dir <- dirname(config_path)
pipeline_extension_guard_check(
  routine = "survival",
  pipelines = list(
    pipeline_regular_batch = if (exists("pipeline_regular_batch")) pipeline_regular_batch else NULL,
    pipeline_shared_regular = if (exists("pipeline_shared_regular")) pipeline_shared_regular else NULL
  ),
  study_dir = .study_dir,
  root = root
)

options(cli.hyperlink = FALSE)
options(warn = 1)
if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("请先安装 jsonlite 包: install.packages('jsonlite')", call. = FALSE)
}

config <- .survival_batch_bind_config(config)
survival_worker <- "run/survival/run_survival_dual_batch_worker.R"

if (isTRUE(run_opts$sensitivity_only)) {
  incidence_sensitivity_pass(
    root          = root,
    config        = config,
    indices       = NULL,
    config_path   = config_path,
    only_index    = run_opts$only_index,
    only_labels   = run_opts$only_scenario,
    worker_script = survival_worker,
    force         = !isTRUE(run_opts$skip_existing)
  )
  quit(save = "no", status = 0)
}

if (isTRUE(run_opts$subgroup_fallback_only)) {
  bc <- config$survival_batch %||% config$incidence_batch %||% list()
  output_base <- bc$output_base %||% config$project$output_dir
  failed_ix <- if (!is.null(run_opts$sfb_only_index) && length(run_opts$sfb_only_index)) {
    run_opts$sfb_only_index
  } else {
    incidence_subgroup_find_failed_indices(output_base)
  }
  incidence_subgroup_fallback_pass(
    root, config, failed_ix, config_path,
    worker_script = survival_worker
  )
  quit(save = "no", status = 0)
}

run_survival_dual_batch(
  root                   = root,
  config                 = config,
  pipeline_regular_batch = pipeline_regular_batch,
  pipeline_shared_regular = pipeline_shared_regular,
  run_opts               = run_opts,
  config_path            = config_path
)
