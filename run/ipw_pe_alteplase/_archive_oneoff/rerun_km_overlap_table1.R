#!/usr/bin/env Rscript
# Fix exposure factor coding → re-run Table1 + KM + subgroup KM + overlap
# Usage:
#   Rscript rerun_km_overlap_table1.R --unit main
#   Rscript rerun_km_overlap_table1.R --unit eICU

suppressPackageStartupMessages(library(cli))
args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
proj <- .arg("--project", "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw")
unit <- .arg("--unit", "main")
if (!dir.exists(proj)) proj <- "/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
engine <- c("E:/01block/01Block-new-Final", "/mnt/e/01block/01Block-new-Final")
engine <- engine[dir.exists(engine)][[1L]]
setwd(engine)

cfg_path <- if (identical(unit, "eICU")) {
  file.path(proj, "config_ipw_pe_alteplase_eICU.R")
} else {
  file.path(proj, "config_ipw_pe_alteplase_MIMIC.R")
}
source(file.path(engine, "R/utils.R"), local = TRUE)
source(file.path(engine, "R/pipeline_runner.R"), local = TRUE)
source(cfg_path)

unit_tag <- if (identical(unit, "eICU")) "\u3010success\u3011eICU" else "\u3010success\u3011main"
out_dir <- file.path(proj, "by_unit", unit_tag)
ck_dir <- file.path(out_dir, "checkpoints")
# start after composite risk (before iptw_balance)
ck0 <- file.path(ck_dir, "step06_ipw_jin_composite_risk.rds")
if (!file.exists(ck0)) ck0 <- file.path(ck_dir, "ipw_jin_composite_risk.rds")
stopifnot(file.exists(ck0))
initial_ctx <- readRDS(ck0)$ctx

config$project$output_dir <- out_dir
config$feishu$enable <- FALSE

blocks <- c(
  "iptw_balance",
  "ipw_weighted_km_pub",
  "ipw_subgroup_km_pub",
  "ipw_overlap_weights"
)
pl <- list(
  name = paste0("ipw_pe_fix_", unit),
  blocks = blocks,
  checkpoint = list(enable = TRUE, dir = ck_dir)
)
cli::cli_h1("rerun Table1/KM/overlap: {unit}")
run_pipeline(engine, config = config, pipeline = pl,
             run_opts = list(initial_ctx = initial_ctx, only = blocks))
cli::cli_alert_success("done {unit}")
