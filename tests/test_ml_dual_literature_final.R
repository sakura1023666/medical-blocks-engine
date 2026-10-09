#!/usr/bin/env Rscript

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
}
script_arg <- commandArgs(FALSE)[grep("^--file=", commandArgs(FALSE))]
script_path <- if (length(script_arg)) sub("^--file=", "", script_arg[[1L]]) else getwd()
engine_root <- Sys.getenv(
  "MEDICAL_BLOCKS_ROOT",
  unset = normalizePath(file.path(dirname(script_path), ".."), mustWork = FALSE)
)
source_path <- file.path(engine_root, "R", "ml_dual_literature_final.R")
if (!file.exists(source_path)) {
  stop("ml_dual_literature_final.R is missing", call. = FALSE)
}
source(source_path)

fig <- ml_dual_literature_figure_spec()
stopifnot(
  identical(fig$order, 1:12),
  identical(
    fig$role,
    c(
      "flowchart", "joint_km", "rcs", "comparator_roc", "landmark",
      "subgroup", "boruta", "three_set_roc", "three_set_calibration",
      "three_set_metrics", "three_set_dca", "shap"
    )
  ),
  fig$db_mode[fig$order == 2L] == "paired",
  fig$db_mode[fig$order == 7L] == "primary",
  fig$db_mode[fig$order == 8L] == "three_set"
)

tab <- ml_dual_literature_table_spec()
stopifnot(
  identical(tab$main_no[!is.na(tab$main_no)], 1:5),
  identical(tab$supp_no[!is.na(tab$supp_no)], 1:10),
  nrow(tab) == 15L
)

cat("ROLE_SPEC_OK figures=12 main_tables=5 supplementary=10\n")

study_root <- Sys.getenv(
  "AKI17_STUDY_ROOT",
  unset = "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/17_AKI_院内28天死亡预测预后_静"
)
index_root <- file.path(study_root, "by_index", "【success】SOSM+WPR")
if (dir.exists(index_root)) {
  resolved <- ml_dual_literature_resolve_sources(index_root)
  stopifnot(
    nrow(resolved$figures) == 12L,
    !length(resolved$missing),
    !length(resolved$duplicates),
    resolved$figures$n_source[resolved$figures$role == "joint_km"] == 2L,
    resolved$figures$n_source[resolved$figures$role == "three_set_roc"] == 1L
  )
  cat("SOURCE_RESOLUTION_OK missing=0 duplicates=0\n")

  dry_fig <- ml_dual_literature_build_figures(
    index_root,
    file.path(index_root, "publication_final.__test__"),
    dry_run = TRUE
  )
  stopifnot(
    nrow(dry_fig) == 12L,
    identical(dry_fig$number, 1:12),
    all(grepl("^Figure (?:[1-9]|1[0-2])\\.", dry_fig$target_name, perl = TRUE)),
    all(dry_fig$status == "planned")
  )
  cat("FIGURE_DRY_RUN_OK figures=12\n")

  dry_tab <- ml_dual_literature_build_tables(
    index_root,
    file.path(index_root, "publication_final.__test__"),
    dry_run = TRUE
  )
  stopifnot(
    nrow(dry_tab) == 15L,
    sum(dry_tab$kind == "Main table") == 5L,
    sum(dry_tab$kind == "Supplementary table") == 10L,
    all(dry_tab$status == "planned"),
    !anyDuplicated(dry_tab$target_name)
  )
  cat("TABLE_DRY_RUN_OK main=5 supplementary=10\n")

  dry_all <- ml_dual_literature_build_final(
    index_root,
    file.path(index_root, "publication_final.__test__"),
    dry_run = TRUE
  )
  stopifnot(
    nrow(dry_all) == 27L,
    sum(dry_all$kind == "Figure") == 12L,
    sum(grepl("table", dry_all$kind, ignore.case = TRUE)) == 15L
  )
  stopifnot(file.exists(file.path(engine_root, "run", "ml", "build_ml_dual_literature_final.R")))
  cat("FINAL_DRY_RUN_OK artifacts=27\n")
}
