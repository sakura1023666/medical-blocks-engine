#!/usr/bin/env Rscript
# HHR → summary_results（仅 Figures + Tables）；完整病例显著才晋升附表
options(warn = 1, stringsAsFactors = FALSE)
engine <- "/mnt/e/01block/01Block-new-Final"
proj <- "/mnt/g/02block_result/22_depression/incidence_cute_ran"
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(engine, "R/pub_delivery_prune.R"), local = FALSE)
source(file.path(engine, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(engine, "R/incidence_summary_result.R"), local = FALSE)

cfg_path <- file.path(proj, "config_incidence_dual_batch.R")
env <- new.env(parent = globalenv())
source(cfg_path, local = env)
config <- env$config
config$pub <- modifyList(
  list(
    summary_dirname = "summary_results",
    include_sa_complete_case = TRUE,
    sa_complete_case_require_sig = TRUE
  ),
  config$pub %||% list()
)

ix_root <- list.files(
  file.path(proj, "by_index"),
  pattern = "^\u3010success\u3011HHR$",
  full.names = TRUE
)[[1L]]
sens <- list.files(
  file.path(ix_root, "sensitivity"),
  pattern = "SA_complete_case",
  full.names = TRUE
)
cli::cli_alert_info("index={ix_root}")
cli::cli_alert_info("SA dirs: {paste(basename(sens), collapse=', ')}")
if (length(sens)) {
  ok_sens <- sens[grepl("success", basename(sens), ignore.case = TRUE)]
  gate_dir <- if (length(ok_sens)) ok_sens[[1L]] else sens[[1L]]
  gate <- incidence_complete_case_read_gate(gate_dir)
  cli::cli_alert_info(
    "complete_case dir={basename(gate_dir)}; status={gate$status}; P_nhanes={gate$p_primary}; P_charls={gate$p_secondary}"
  )
}

res <- incidence_finalize_summary_result(
  project_root = proj,
  config = config,
  index = "HHR",
  include_sa_complete_case = TRUE,
  summary_dirname = "summary_results",
  tables_figures_only = TRUE
)
cli::cli_alert_success(
  "summary_root={res$summary_root}; n_tables={res$n_tables}; SA={res$n_sa_complete_case}"
)
cat("\n=== Tables ===\n")
print(sort(list.files(file.path(res$summary_root, "Tables"))))
cat("\n=== Figures/pdf ===\n")
print(sort(list.files(file.path(res$summary_root, "Figures", "pdf"))))
