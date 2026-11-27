#!/usr/bin/env Rscript
# =============================================================================
#  AHF 血钠/eGFR 轨迹预后 batch（MIMIC 发现 → eICU 外验 + PAMM）
#
#  先准备数据:
#    Rscript run/trajectory_prognosis/prepare_ahf_trajectory_data.R
#
#  再跑:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_ahf_jlcm_batch.R --shared-only
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_ahf_jlcm_batch.R --workers 2
# =============================================================================

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
# 默认指向 AHF config；其余参数透传 COPD batch 入口
cfg <- "configs/config_trajectory_prognosis_ahf_jlcm_batch.R"
if (!"--config" %in% args) {
  args <- c("--config", cfg, args)
}

Sys.setenv(SMOKE_NO_FEISHU = Sys.getenv("SMOKE_NO_FEISHU", "1"))

cmd <- c(
  file.path(root, "run/trajectory_prognosis/run_trajectory_prognosis_copd_jlcm_batch.R"),
  args
)
status <- system2("Rscript", cmd)
quit(save = "no", status = if (is.null(status)) 0L else as.integer(status))
