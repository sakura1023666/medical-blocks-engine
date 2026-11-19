#!/usr/bin/env Rscript
# SSD LPA × 网络 × 平行竞争中介 — 单流水线入口
# 决策树: Decisiontree/decision_tree_ssd_lpa_network_mediation.md
#
# 用法:
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/ssd_lpa_network_mediation/run_ssd_lpa_network_mediation.R
#   SSD_MED_SIMS=50 SSD_NET_BOOTS=20 SMOKE_NO_FEISHU=1 同上   # 冒烟
#   ... --config "/mnt/g/.../configs/config_ssd_lpa_network_mediation.R"
#   ... --from latent_profile_tidylpa --to parallel_competing_mediation

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

script_path <- .init_script_dir()
if (basename(script_path) == "ssd_lpa_network_mediation" &&
    basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
default_cfg <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "configs",
  "config_ssd_lpa_network_mediation.R"
)
config_path <- default_cfg
i <- match("--config", args)
if (!is.na(i) && i < length(args)) {
  config_path <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}
if (!file.exists(config_path)) {
  config_path <- file.path(
    root, "configs/study_ssd_lpa_network_mediation/config_ssd_lpa_network_mediation.R"
  )
}
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
if (file.exists(file.path(root, "R/feishu_bitable.R"))) {
  source(file.path(root, "R/feishu_bitable.R"))
}
source(config_path)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) {
  config$feishu$enable <- FALSE
}

# 保证行级 ID（原始 number 非唯一）
.config_ensure_row_id <- function(cfg) {
  cfg$data$id_column <- cfg$data$id_column %||% "row_id"
  cfg
}
config <- .config_ensure_row_id(config)

run_opts <- pipeline_parse_cli(args[!(args %in% c("--config", config_path))])
options(cli.hyperlink = FALSE, warn = 1)

cli::cli_h1("SSD LPA × Network × Parallel mediation")
cli::cli_alert_info("config: {.file {config_path}}")
cli::cli_alert_info("output: {.file {config$project$output_dir}}")

t0 <- Sys.time()
status <- "success"
err_msg <- ""
tryCatch(
  run_pipeline(root, config, pipeline, run_opts),
  error = function(e) {
    status <<- "error"
    err_msg <<- conditionMessage(e)
    stop(e)
  }
)

if (isTRUE((config$feishu %||% list())$enable) &&
    exists("incidence_batch_feishu_push_result", mode = "function")) {
  tryCatch(
    incidence_batch_feishu_push_result(config, list(
      index = "SSD_LPA_Network_Mediation",
      status = status,
      db_mode = "outpatient",
      disease = config$feishu$disease_label,
      protocol = config$feishu$protocol_label,
      elapsed_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
      error_message = err_msg
    )),
    error = function(e) cli::cli_alert_warning("飞书: {conditionMessage(e)}")
  )
}

cli::cli_alert_success(
  "完成 status={status}; elapsed={round(as.numeric(difftime(Sys.time(), t0, units = 'mins')), 1)} min"
)
