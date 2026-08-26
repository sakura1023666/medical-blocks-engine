#!/usr/bin/env Rscript
# =============================================================================
#  SAE + RAR 预后流水线入口
#  配置: configs/templates/config_survival_sae.template.R（默认）或 --config <外部路径>
#  引擎: R/pipeline_runner.R
#
#  用法（项目根目录）:
#    Rscript run_survival_sae.R
#    Rscript run_survival_sae.R --to multicollinearity_final
#    Rscript run_survival_sae.R --only cox_quartile
#    Rscript run_survival_sae.R --from step09_cox_quartile
#    Rscript run_survival_sae.R --list-checkpoints
#    Rscript run_survival_sae.R --config "Output/my_study/config.R"
#
#  引擎路径可通过环境变量固定:
#    MEDICAL_BLOCKS_ROOT=/opt/medical-blocks Rscript run_survival_sae.R --config ...
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
  script_path <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
           basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args_raw <- commandArgs(trailingOnly = TRUE)

root_guess <- normalizePath(getwd(), winslash = "/")
if (length(args_raw) >= 1L && !startsWith(args_raw[[1L]], "--")) {
  root_guess <- normalizePath(args_raw[[1L]], winslash = "/", mustWork = TRUE)
}

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

cfg_result  <- .extract_config_arg(args_raw, file.path(root, "configs/templates/config_survival_sae.template.R"))
config_path <- cfg_result$config_path
args        <- cfg_result$args

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(config_path)

run_opts <- pipeline_parse_cli(args)
if (!is.null(run_opts$root) && nzchar(run_opts$root)) {
  root <- normalizePath(run_opts$root, winslash = "/", mustWork = TRUE)
  setwd(root)
}

options(cli.hyperlink = FALSE)
options(warn = 1)

run_opts$list_ck <- isTRUE(run_opts$list_ck)
run_pipeline(root, config = config, pipeline = pipeline, run_opts = run_opts)
