#!/usr/bin/env Rscript
# 缺血性脑卒中两阶段 Transformer（单跑）— configs/templates/config_two_stage_transformer_stroke.template.R
#
# 用法:
#   Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke.R
#   Rscript run/two_stage_transformer_stroke/run_two_stage_transformer_stroke.R --config <path>
#
# 注意: Blocks/71_two_stage_transformer_stroke/*（tst_cohort…tst_pub_export）由
# Task4-6 交付；在其落地前，全链路执行会在遇到未注册 block 时报错，这是预期行为。

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "two_stage_transformer_stroke" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else root <- script_path
setwd(root)

args <- commandArgs(trailingOnly = TRUE)
config_path <- if (length(args) >= 2L && args[1L] == "--config") {
  normalizePath(args[2L], winslash = "/", mustWork = TRUE)
} else normalizePath(file.path(root, "configs/templates/config_two_stage_transformer_stroke.template.R"), winslash = "/", mustWork = TRUE)

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R")); source(file.path(root, "R/pipeline_runner.R")); source(file.path(root, "R/rscript_study.R"))
source(config_path)

# 飞书 app_token：进程内临时覆盖，不改写 .env.feishu 密钥正文
if (nzchar(as.character(config$feishu$app_token %||% "")[1L])) {
  Sys.setenv(FEISHU_BITABLE_APP_TOKEN = config$feishu$app_token)
}
if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

run_pipeline(root, config = config, pipeline = pipeline)
