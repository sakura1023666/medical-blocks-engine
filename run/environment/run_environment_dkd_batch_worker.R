#!/usr/bin/env Rscript
# =============================================================================
#  DKD × 环境 VOC 批量 — 单 VOC Worker（Step07 rcs_nhanes）
#
#  用法:
#    Rscript run_environment_dkd_batch_worker.R --voc DHBMA
#    Rscript run_environment_dkd_batch_worker.R --voc DHBMA --config configs/...
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

.parse_worker_args <- function(args) {
  opts <- list(voc = NULL, root = NULL, config = NULL, opts_file = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (grepl("^--voc=", a)) {
      opts$voc <- trimws(sub("^--voc=", "", a)); i <- i + 1L
    } else if (a == "--voc" && i < length(args)) {
      opts$voc <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (grepl("^--config=", a)) {
      opts$config <- trimws(sub("^--config=", "", a)); i <- i + 1L
    } else if (a == "--config" && i < length(args)) {
      # 兼容旧式 --config <path>；路径含空格时合并后续非 flag 片段
      cfg_parts <- character(0)
      j <- i + 1L
      while (j <= length(args) && !grepl("^--", args[[j]])) {
        cfg_parts <- c(cfg_parts, args[[j]])
        j <- j + 1L
      }
      opts$config <- trimws(paste(cfg_parts, collapse = " "))
      i <- j
    } else if (grepl("^--opts=", a)) {
      opts$opts_file <- trimws(sub("^--opts=", "", a)); i <- i + 1L
    } else if (a == "--opts" && i < length(args)) {
      opts$opts_file <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (grepl("^--root=", a)) {
      opts$root <- trimws(sub("^--root=", "", a)); i <- i + 1L
    } else if (a == "--root" && i < length(args)) {
      root_parts <- character(0)
      j <- i + 1L
      while (j <= length(args) && !grepl("^--", args[[j]])) {
        root_parts <- c(root_parts, args[[j]])
        j <- j + 1L
      }
      opts$root <- trimws(paste(root_parts, collapse = " "))
      i <- j
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$voc) || !nzchar(opts$voc))
    stop("--voc 参数必填", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
    basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)
if (!is.null(wk_opts$opts_file) && nzchar(wk_opts$opts_file) && file.exists(wk_opts$opts_file)) {
  opt_obj <- readRDS(wk_opts$opts_file)
  if (!is.null(opt_obj$config) && nzchar(opt_obj$config)) wk_opts$config <- opt_obj$config
  if (!is.null(opt_obj$root) && nzchar(opt_obj$root)) wk_opts$root <- opt_obj$root
}
env_cfg <- Sys.getenv("ENVIRONMENT_DKD_WORKER_CONFIG", unset = "")
env_root <- Sys.getenv("ENVIRONMENT_DKD_WORKER_ROOT", unset = "")
if (nzchar(env_cfg)) wk_opts$config <- env_cfg
if (nzchar(env_root)) wk_opts$root <- env_root

root_guess <- normalizePath(getwd(), winslash = "/")
if (!is.null(wk_opts$root) && nzchar(wk_opts$root))
  root_guess <- normalizePath(wk_opts$root, winslash = "/", mustWork = TRUE)

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

voc     <- wk_opts$voc
t_start <- proc.time()

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_environment_dkd_batch.template.R")
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))
source(file.path(root, "R/environment_mixture_utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/environment_voc_batch_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

if (!requireNamespace("jsonlite", quietly = TRUE))
  stop("请先安装 jsonlite", call. = FALSE)

options(cli.hyperlink = FALSE, warn = 1)

bc          <- config$environment_batch %||% list()
output_base <- bc$output_base %||% config$project$output_dir
output_voc  <- environment_batch_voc_output_dir(config, voc)
voc_ck      <- environment_batch_voc_ck_dir(config, voc)
shared_ck   <- environment_batch_shared_ck_dir(config)

.write_status <- function(status, error_message = NULL) {
  elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
  fields  <- list(
    index         = voc,
    status        = status,
    db_mode       = "nhanes_only",
    error_message = error_message,
    elapsed_sec   = elapsed,
    disease       = (config_voc$feishu %||% list())$disease_label %||%
      config_voc$project$disease %||% "DKD",
    protocol      = (config_voc$feishu %||% list())$protocol_label %||% ""
  )
  environment_batch_write_status(output_voc, fields)
  if (exists("incidence_batch_feishu_push_result", mode = "function")) {
    tryCatch(
      incidence_batch_feishu_push_result(config_voc, fields),
      error = function(e) cli::cli_alert_warning("飞书推送异常: {e$message}")
    )
  }
}

cli::cli_h1("VOC Worker: {voc}")

config_voc <- environment_batch_patch_config_for_voc(config, voc)

if (!environment_batch_copy_shared_ck(shared_ck, voc_ck)) {
  .write_status("failed", "复制共享 checkpoint 失败")
  quit(save = "no", status = 1)
}

initial_ctx <- tryCatch(
  environment_batch_load_checkpoint_ctx(voc_ck, "bkmr_analysis"),
  error = function(e) {
    .write_status("failed", conditionMessage(e))
    quit(save = "no", status = 1)
  }
)

pl <- pipeline_voc_batch
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir    <- voc_ck

tryCatch({
  run_pipeline(
    root,
    config   = config_voc,
    pipeline = pl,
    run_opts = list(initial_ctx = initial_ctx, only = "rcs_nhanes")
  )
  .write_status("success")
  cli::cli_alert_success("{voc}: rcs_nhanes 完成")
  quit(save = "no", status = 0)
}, error = function(e) {
  .write_status("failed", conditionMessage(e))
  cli::cli_alert_danger("{voc}: {conditionMessage(e)}")
  quit(save = "no", status = 1)
})
