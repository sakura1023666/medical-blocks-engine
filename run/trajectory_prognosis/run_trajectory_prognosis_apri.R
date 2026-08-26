#!/usr/bin/env Rscript
# 轨迹预后 APRI JLCM（单指标单库调试）— configs/templates/config_trajectory_prognosis_batch.template.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
i <- match("--config", args)
if (!is.na(i) && i < length(args)) config_path <- normalizePath(args[i + 1L], winslash = "/")

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
run_opts <- pipeline_parse_cli(args[args != "--config" & args != config_path])
options(cli.hyperlink = FALSE, warn = 1)

t0 <- Sys.time(); status <- "success"; err_msg <- ""
tryCatch(run_pipeline(root, config, pipeline, run_opts), error = function(e) {
  status <<- "error"; err_msg <<- conditionMessage(e); stop(e)
})
if (isTRUE((config$feishu %||% list())$enable)) {
  tryCatch(incidence_batch_feishu_push_result(config, list(
    index = config$survival$index_var %||% "APRI", status = status, db_mode = config$project$database %||% "eICU",
    disease = config$feishu$disease_label, protocol = config$feishu$protocol_label,
    elapsed_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
    error_message = err_msg
  )), error = function(e) cli::cli_alert_warning("飞书: {conditionMessage(e)}"))
}
