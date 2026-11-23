#!/usr/bin/env Rscript
# SSD LPA/network/mediation — 发表收口（引擎级）
# 每次跑完本课题必须执行本脚本：
#   scrub（禁下划线 + Times）→ Methods md → 软件版本 txt（无日期）→
#   结构 QC（进 workspace）→ prune 白名单（只留图/表/Methods/中期）
#
# 用法:
#   Rscript run/ssd_lpa_network_mediation/finalize_ssd_summary_delivery.R
#   Rscript run/ssd_lpa_network_mediation/finalize_ssd_summary_delivery.R --project <main_full_sample>

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
root <- if (basename(script_path) == "ssd_lpa_network_mediation") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  normalizePath(getwd(), winslash = "/")
}
setwd(root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)

source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/ssd_lpa_network_mediation_pub.R"), local = FALSE)

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}
sr <- file.path(proj, "summary_results")
if (!dir.exists(sr)) stop("missing summary_results: ", sr)

# optional midterm already in root
mt <- list.files(sr, pattern = "\u4e2d\u671f.*\\.pdf$", full.names = TRUE)
mt_arg <- if (length(mt)) mt[[1]] else NULL

ssd_finalize_summary_delivery(
  summary_root = sr,
  engine_root = root,
  midterm_pdf = mt_arg,
  run_struct_qc = TRUE
)

message("OK SSD finalize → ", sr)
message("root entries: ", paste(list.files(sr), collapse = "; "))
