#!/usr/bin/env Rscript
# CLHLS 症状网络流水线入口 — configs/config_clhls_symptom_network.R
# 推荐 Windows R: "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "clhls_symptom_network" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- file.path(root, "configs/config_clhls_symptom_network.R")
i <- match("--config", args)
if (!is.na(i) && i < length(args)) config_path <- normalizePath(args[i + 1L], winslash = "/")

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
# 冒烟次数：WSL 环境变量不一定进 Windows R，同时写进 config
.nboot <- suppressWarnings(as.integer(Sys.getenv("CLHLS_NBOOTS", "")))
.nct <- suppressWarnings(as.integer(Sys.getenv("CLHLS_NCT_IT", "")))
if (!is.na(.nboot) && .nboot > 0L) config$clhls_network$n_boots <- .nboot
if (!is.na(.nct) && .nct > 0L) config$clhls_network$nct_it <- .nct
# 兼容 Windows Rscript 从 WSL 启动时读不到 env：也认 --n-boots / --nct-it
.ib <- match("--n-boots", args)
if (!is.na(.ib) && .ib < length(args)) {
  config$clhls_network$n_boots <- as.integer(args[.ib + 1L])
}
.ic <- match("--nct-it", args)
if (!is.na(.ic) && .ic < length(args)) {
  config$clhls_network$nct_it <- as.integer(args[.ic + 1L])
}
run_opts <- pipeline_parse_cli(args[!(args %in% c("--config", config_path, "--n-boots", "--nct-it")) &
  !(seq_along(args) %in% c(.ib + 1L, .ic + 1L))])
options(cli.hyperlink = FALSE, warn = 1)

t0 <- Sys.time(); status <- "success"; err_msg <- ""
tryCatch(run_pipeline(root, config, pipeline, run_opts), error = function(e) {
  status <<- "error"; err_msg <<- conditionMessage(e); stop(e)
})
if (isTRUE((config$feishu %||% list())$enable) && exists("incidence_batch_feishu_push_result", mode = "function")) {
  tryCatch(incidence_batch_feishu_push_result(config, list(
    index = "CLHLS_Symptom_Network", status = status, db_mode = "CLHLS",
    disease = config$feishu$disease_label, protocol = config$feishu$protocol_label,
    elapsed_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
    error_message = err_msg
  )), error = function(e) message("飞书推送失败: ", conditionMessage(e)))
}
