#!/usr/bin/env Rscript
# Re-run subgroup_iptw_weighted + stepp_prognosis into 【success】 units (Fig3/Fig5 fix)
suppressPackageStartupMessages({
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli")
})

args <- commandArgs(trailingOnly = TRUE)
.arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

proj <- .arg("--project", "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw")
unit <- .arg("--unit", "main") # main | eICU
if (!dir.exists(proj)) {
  proj <- "/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
}
stopifnot(dir.exists(proj))

engine <- {
  cands <- c(Sys.getenv("BLOCK_REPO_ROOT", ""), "E:/01block/01Block-new-Final",
             "/mnt/e/01block/01Block-new-Final")
  hit <- cands[nzchar(cands) & dir.exists(cands)]
  hit[[1L]]
}
setwd(engine)

cfg_path <- if (identical(unit, "eICU")) {
  file.path(proj, "config_ipw_pe_alteplase_eICU.R")
} else {
  file.path(proj, "config_ipw_pe_alteplase_MIMIC.R")
}
stopifnot(file.exists(cfg_path))

source(file.path(engine, "R/utils.R"), local = TRUE)
source(file.path(engine, "R/pipeline_runner.R"), local = TRUE)
source(cfg_path)

unit_tag <- if (identical(unit, "eICU")) "\u3010success\u3011eICU" else "\u3010success\u3011main"
out_dir <- file.path(proj, "by_unit", unit_tag)
ck_dir <- file.path(out_dir, "checkpoints")
stopifnot(dir.exists(out_dir), dir.exists(ck_dir))

# start from KM pub checkpoint (immediate predecessor of subgroup_iptw)
ck_km <- file.path(ck_dir, "step10_ipw_weighted_km_pub.rds")
if (!file.exists(ck_km)) {
  # fallback: any *ipw_weighted_km*
  hits <- list.files(ck_dir, pattern = "ipw_weighted_km", full.names = TRUE)
  if (!length(hits)) stop("no ipw_weighted_km checkpoint in ", ck_dir)
  ck_km <- hits[[1L]]
}
initial_ctx <- readRDS(ck_km)$ctx
if (is.null(initial_ctx)) stop("checkpoint ctx empty: ", ck_km)

config$project$output_dir <- out_dir
config$feishu$enable <- FALSE
# ensure subgroup lock present (also in config files)
config$subgroup <- modifyList(config$subgroup %||% list(), list(
  var_source = "required",
  required_subgroup_vars = c(
    "Age_Group", "Gender", "Hypertension", "Heart_Failure", "CKD", "COPD"
  ),
  age_cutoff = 65L,
  forest_xlim = c(0.05, 5)
))
config$subgroup_iptw_weighted <- modifyList(
  config$subgroup_iptw_weighted %||% list(),
  config$subgroup
)

blocks <- c("subgroup_iptw_weighted", "stepp_prognosis")
pl <- list(
  name = paste0("ipw_pe_fig35_", unit),
  blocks = blocks,
  checkpoint = list(enable = TRUE, dir = ck_dir)
)

cli::cli_h1("rerun Fig3/Fig5 blocks: {unit}")
final_ctx <- run_pipeline(
  engine,
  config = config,
  pipeline = pl,
  run_opts = list(initial_ctx = initial_ctx, only = blocks)
)
cli::cli_alert_success("done {unit} -> {out_dir}")
invisible(final_ctx)
