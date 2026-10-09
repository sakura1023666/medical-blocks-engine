#!/usr/bin/env Rscript
# ML 双库批量 — 固定 Windows R 4.5.1
{
  skip_win <- identical(Sys.getenv("MEDICAL_BLOCKS_SKIP_WIN_R", unset = ""), "1")
  rscript_ml <- "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
  if (!skip_win && file.exists(rscript_ml) && .Platform$OS.type != "windows") {
    ca <- commandArgs(trailingOnly = FALSE)
    self <- grep("^--file=", ca, value = TRUE)
    if (length(self)) {
      self <- sub("^--file=", "", self[1L])
      status <- system2(rscript_ml, c(self, commandArgs(trailingOnly = TRUE)))
      quit(save = "no", status = status)
    }
  }
}

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
    config = NULL, root = NULL, workers = NULL, db_mode = NULL,
    shared_only = FALSE, phase2_only = FALSE,
    only_index = NULL, skip_existing = TRUE, p_trim = 0.01
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
    } else if (a == "--phase2-only") {
      opts$phase2_only <- TRUE; i <- i + 1L
    } else if (a == "--only-index" && i < length(args)) {
      opts$only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else if (a == "--ptrim" && i < length(args)) {
      opts$p_trim <- as.numeric(args[[i + 1L]]); i <- i + 2L
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
} else if (basename(script_path) %in% c("environment", "incidence", "survival", "ml", "feishu", "hf") &&
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
  file.path(root, "configs/templates/config_ml_dual_batch.template.R")
}

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/ml_dual_pipeline_helpers.R"))
source(file.path(root, "R/ml_cross_db_split.R"))
source(file.path(root, "R/ml_assoc_data_slots.R"))
source(file.path(root, "R/ml_dual_batch_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(config_path)
if (exists("ml_dual_apply_baseline_index_ns_fail_rule", mode = "function")) {
  config <- ml_dual_apply_baseline_index_ns_fail_rule(config)
}
if (exists("ml_dual_audit_study_inherited_excludes", mode = "function")) {
  ml_dual_audit_study_inherited_excludes(config)
}

source(file.path(root, "R/pipeline_extension_guard.R"))
.study_dir <- dirname(config_path)
## 预后 ML 会把 univariate_incidence_binary → univariate_prognosis，相对发病基线有合法替换；
## 在 baseline 分型落地前，可用 MEDICAL_BLOCKS_SKIP_PIPELINE_GUARD=1 跳过（单课题显式开启）。
if (!identical(Sys.getenv("MEDICAL_BLOCKS_SKIP_PIPELINE_GUARD", unset = ""), "1")) {
  pipeline_extension_guard_check(
    routine = "ml",
    pipelines = list(
      pipeline_nhanes_batch = if (exists("pipeline_nhanes_batch")) pipeline_nhanes_batch else NULL,
      pipeline_regular_primary_ml_batch = if (exists("pipeline_regular_primary_ml_batch")) pipeline_regular_primary_ml_batch else NULL,
      pipeline_mimic_ml_batch = if (exists("pipeline_mimic_ml_batch")) pipeline_mimic_ml_batch else NULL,
      pipeline_shared_nhanes = if (exists("pipeline_shared_nhanes")) pipeline_shared_nhanes else NULL,
      pipeline_shared_regular = if (exists("pipeline_shared_regular")) pipeline_shared_regular else NULL
    ),
    study_dir = .study_dir,
    root = root
  )
} else {
  message("跳过 pipeline_extension_guard（MEDICAL_BLOCKS_SKIP_PIPELINE_GUARD=1）")
}

options(cli.hyperlink = FALSE, warn = 1)
if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("请先安装 jsonlite", call. = FALSE)
}

if (isTRUE(run_opts$phase2_only)) {
  run_ml_dual_batch_phase2_only(
    root = root,
    config = config,
    run_opts = run_opts,
    config_path = config_path
  )
} else {
  run_ml_dual_batch(
    root = root,
    config = config,
    pipeline_nhanes_batch = pipeline_nhanes_batch,
    pipeline_mimic_ml_batch = pipeline_mimic_ml_batch,
    pipeline_shared_nhanes = pipeline_shared_nhanes,
    pipeline_shared_regular = pipeline_shared_regular,
    run_opts = run_opts,
    config_path = config_path
  )
}
