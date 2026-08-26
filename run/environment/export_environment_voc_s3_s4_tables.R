#!/usr/bin/env Rscript
# =============================================================================
#  从共享层 checkpoint 导出环境毒物 Table S3-VOC / S4-VOC
#
#  用法:
#    Rscript run/environment/export_environment_voc_s3_s4_tables.R \
#      --config "/path/config_environment_osteo_fuben_batch.R"
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[1L])
    if (nzchar(fp)) return(normalizePath(dirname(fp), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

args <- commandArgs(trailingOnly = TRUE)
config_path <- NULL
i <- 1L
while (i <= length(args)) {
  if (args[[i]] == "--config" && i < length(args)) {
    config_path <- trimws(args[[i + 1L]]); i <- i + 2L
  } else {
    i <- i + 1L
  }
}
if (is.null(config_path) || !nzchar(config_path)) {
  stop("--config 必填", call. = FALSE)
}

script_path <- .init_script_dir()
if (basename(script_path) == "environment" && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)
config_path <- normalizePath(config_path, winslash = "/", mustWork = TRUE)

source(file.path(script_path, "R/utils.R"))
source(file.path(script_path, "R/nhanes_survey_weight.R"))
source(file.path(script_path, "R/environment_display_utils.R"))
source(file.path(script_path, "R/environment_mixture_utils.R"))
source(file.path(script_path, "R/environment_voc_recovery_utils.R"))
source(file.path(script_path, "R/environment_voc_batch_runner.R"))
source(file.path(script_path, "R/environment_voc_pub_tables.R"))
source(file.path(script_path, "Blocks/12_obj/01block_obj.R"))
source(config_path)

environment_batch_export_voc_pub_tables(config, script_path)
