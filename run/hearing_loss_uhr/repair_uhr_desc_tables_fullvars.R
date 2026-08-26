#!/usr/bin/env Rscript
# 听力 UHR：Table1/S1–S4 各库全变量（不按双库交集裁列）
# 从 _shared/column_mapping（全列）起步，NHANES 限 Age 45–69；跳过 dual_db_column_harmonize
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE, warn = 1))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
dual_cfg <- file.path(study, "config_incidence_dual_batch.R")
lil_cfg  <- file.path(study, "config_incidence_liling.R")
success <- file.path(study, "by_index", "【success】UHR")
copy_dir <- file.path(study, "by_index", "【success】UHR - 副本")
ix <- "UHR"
desc_ck_root <- file.path(study, "checkpoints", "by_index", "UHR_desc_fullvars")
shared <- file.path(study, "checkpoints", "_shared")

setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))

# 禁用双库缺失并集删列
pipeline_dual_db_partner_high_missing_cols <<- function(cfg, threshold = 0.4) character(0)
pipeline_dual_db_partner_unusable_cols <<- function(cfg) character(0)

patch_desc_cfg <- function(cfg) {
  if (!is.null(cfg$baseline_nhanes)) cfg$baseline_nhanes$include_vars <- NULL
  if (!is.null(cfg$baseline_binary)) {
    cfg$baseline_binary$include_vars <- NULL
    cfg$baseline_binary$exclude_vars <- c(
      "ID", "SEQN", "subject_id", "Age_Group",
      "SDMVPSU", "SDMVSTRA", "new_Weight",
      "WTINT2YR", "WTMEC2YR", "WTMEC4YR", "WTSAF2YR", "WTSAF4YR",
      "WTDRD1", "WTDR2D", "Source_File"
    )
  }
  if (!is.null(cfg$baseline_nhanes))
    cfg$baseline_nhanes$exclude_vars <- cfg$baseline_binary$exclude_vars
  for (nm in c("univariate_nhanes", "univariate_incidence_binary")) {
    if (!is.null(cfg[[nm]])) {
      cfg[[nm]]$excluded_predictors <- NULL
      cfg[[nm]]$required_predictors <- NULL
    }
  }
  if (!is.null(cfg$imputation)) {
    # 铁律：列缺失率 >40% 删列；三库各自判定（不因伙伴库并集对齐互删）
    cfg$imputation$missing_col_threshold <- 0.4
    cfg$imputation$export_table_s1 <- TRUE
  }
  if (!is.null(cfg$dual_db$harmonization)) {
    cfg$dual_db$harmonization$require_same_clinical_cols <- FALSE
    cfg$dual_db$harmonization$common_non_demo_cols <- NULL
    # 全列 keep：避免闸门 A 再裁
    cfg$dual_db$harmonization$column_keep_nhanes <- NULL
    cfg$dual_db$harmonization$column_keep_mimic <- NULL
  }
  cfg$incidence$index_var <- ix
  cfg$logistic$index_var <- ix
  cfg
}

age_filter_ctx <- function(ctx, lo = 45, hi = 69) {
  for (slot in c("raw", "cleaned", "mapped", "imputed")) {
    d <- ctx$data[[slot]]
    if (is.null(d) || !is.data.frame(d) || !"Age" %in% names(d)) next
    keep <- !is.na(d$Age) & d$Age >= lo & d$Age <= hi
    ctx$data[[slot]] <- d[keep, , drop = FALSE]
  }
  ctx
}

copy_desc_tables <- function(out_db, dest_agg, db_label) {
  dest_db <- file.path(out_db, "Tables")
  dir.create(dest_db, recursive = TRUE, showWarnings = FALSE)
  dir.create(dest_agg, recursive = TRUE, showWarnings = FALSE)
  pat <- paste0(
    "(^Table 1-)|",
    "(Table S1-.*imputation|before and after)|",
    "(Table S2-.*Normality)|",
    "(Table S3-.*Univariate)|",
    "(Table S4-.*(Multicollinearity|VIF).*screen|Table S4-.*Multicollinearity Analysis\\.xlsx)"
  )
  files <- list.files(out_db, pattern = "\\.xlsx$", recursive = TRUE, full.names = TRUE)
  files <- files[grepl("/Tables/", files)]
  keep <- files[grepl(pat, basename(files), ignore.case = TRUE)]
  keep <- keep[!grepl("Multivariable|multivariate p", basename(keep), ignore.case = TRUE)]
  n <- 0L
  for (f in keep) {
    if (isTRUE(file.info(f)$size < 100)) next
    bn <- gsub("-Liling\\.", "-Single.", basename(f))
    for (dest in unique(c(file.path(dest_db, bn), file.path(dest_agg, bn)))) {
      same <- tryCatch(
        identical(normalizePath(f, mustWork = TRUE), normalizePath(dest, mustWork = FALSE)),
        error = function(e) FALSE
      )
      if (!isTRUE(same)) file.copy(f, dest, overwrite = TRUE)
    }
    n <- n + 1L
  }
  cli::cli_alert_info("{db_label}: copied {n} desc tables → agg")
  invisible(n)
}

# ── Dual ────────────────────────────────────────────────────────────────────
Sys.setenv(STUDY_CONFIG_DIR = dirname(dual_cfg))
source(dual_cfg)
config <- patch_desc_cfg(config)
config$incidence_batch$output_base <- study
config$project$root <- study
config$incidence_batch$sensitivity_suite$enable <- FALSE

run_dual_desc <- function(db) {
  slot <- dual_db_slot_path_name(config, db)
  cfg_db <- patch_desc_cfg(incidence_batch_apply_db_overrides(config, db, root, ix))
  out_db <- file.path(success, slot)
  cfg_db$project$output_dir <- out_db
  dir.create(out_db, recursive = TRUE, showWarnings = FALSE)

  map_rds <- file.path(shared, slot, "column_mapping.rds")
  stopifnot(file.exists(map_rds))
  ctx0 <- readRDS(map_rds)$ctx
  if (identical(slot, "NHANES")) {
    ctx0 <- age_filter_ctx(ctx0, 45, 69)
    cli::cli_alert_info("NHANES Age 45-69 → n={nrow(ctx0$data$cleaned)}")
  }
  ctx0$config <- cfg_db
  ctx0$root_output_dir <- out_db
  ctx0$config$project$mirror_pub_outputs_to_root <- TRUE

  ck_dst <- file.path(desc_ck_root, slot)
  pl <- if (dual_db_is_weighted(config, db)) pipeline_nhanes_batch else pipeline_regular_batch
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir <- ck_dst

  # 跳过 dual_db_column_harmonize：保留全列
  only_blocks <- if (dual_db_is_weighted(config, db)) {
    c("index", "imputation", "trim_index_extreme", "cutoff", "obj",
      "baseline_nhanes", "univariate_nhanes", "multicollinearity_nhanes_screen")
  } else {
    c("index", "imputation", "trim_index_extreme",
      "baseline_binary", "univariate_incidence_binary", "multicollinearity_screen")
  }

  # NHANES：若已有 trim 检查点则从其后续跑（避免重做 MICE）
  trim_ck <- file.path(ck_dst, "trim_index_extreme.rds")
  resume_from_trim <- dual_db_is_weighted(config, db) && file.exists(trim_ck)

  if (resume_from_trim) {
    only_blocks <- c(
      "cutoff", "obj",
      "baseline_nhanes", "univariate_nhanes", "multicollinearity_nhanes_screen"
    )
    cli::cli_h2("DESC fullvars [{slot}] resume after trim_index_extreme only=...")
    run_pipeline(
      root, config = cfg_db, pipeline = pl,
      run_opts = list(from = "trim_index_extreme", only = only_blocks)
    )
  } else {
    if (dir.exists(ck_dst)) unlink(ck_dst, recursive = TRUE, force = TRUE)
    dir.create(ck_dst, recursive = TRUE, showWarnings = FALSE)
    cli::cli_h2("DESC fullvars [{slot}] ncol={ncol(ctx0$data$cleaned)} only=...")
    run_pipeline(
      root, config = cfg_db, pipeline = pl,
      run_opts = list(initial_ctx = ctx0, only = only_blocks)
    )
  }
  copy_desc_tables(out_db, file.path(success, "Tables"), slot)
}

for (db in c("nhanes", "mimic")) run_dual_desc(db)

# ── Single ──────────────────────────────────────────────────────────────────
Sys.setenv(STUDY_CONFIG_DIR = dirname(lil_cfg))
rm(list = intersect(c("pipeline", "config", "pipeline_nhanes_batch", "pipeline_regular_batch"),
                    ls(envir = .GlobalEnv)), envir = .GlobalEnv)
source(lil_cfg)
config <- patch_desc_cfg(config)
config$project$database <- "Single"
config$project$output_dir <- file.path(success, "Single")
dir.create(config$project$output_dir, recursive = TRUE, showWarnings = FALSE)

lil_map <- file.path(study, "_archive/checkpoints_before_unify_20260729_134507/Liling_UHR/column_mapping.rds")
if (!file.exists(lil_map))
  lil_map <- file.path(study, "checkpoints/Liling_UHR/column_mapping.rds")
ctx0 <- readRDS(lil_map)$ctx
ctx0$config <- config
ctx0$root_output_dir <- config$project$output_dir
ctx0$config$project$database <- "Single"
ctx0$config$project$mirror_pub_outputs_to_root <- TRUE

ck_single <- file.path(desc_ck_root, "Single")
if (dir.exists(ck_single)) unlink(ck_single, recursive = TRUE, force = TRUE)
dir.create(ck_single, recursive = TRUE, showWarnings = FALSE)

pl <- pipeline
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- ck_single
only_blocks <- c("index", "imputation", "baseline_binary",
                 "univariate_incidence_binary", "multicollinearity_screen")

cli::cli_h2("DESC fullvars [Single] ncol={ncol(ctx0$data$cleaned)}")
run_pipeline(
  root, config = config, pipeline = pl,
  run_opts = list(initial_ctx = ctx0, only = only_blocks)
)
for (f in list.files(file.path(success, "Single", "Tables"), pattern = "Liling", full.names = TRUE)) {
  file.rename(f, gsub("Liling", "Single", f, fixed = TRUE))
}
copy_desc_tables(config$project$output_dir, file.path(success, "Tables"), "Single")

# sync
cli::cli_h1("sync")
system(sprintf("rm -rf %s && cp -a %s %s", shQuote(copy_dir), shQuote(success), shQuote(copy_dir)))
sh <- file.path(root, "run/hearing_loss_uhr/collect_hearing_uhr_summary_result.sh")
if (file.exists(sh)) system2("bash", c(sh, study))

# 验收
suppressPackageStartupMessages(library(readxl))
cli::cli_h2("验收")
for (db in c("NHANES", "CHARLS", "Single")) {
  f <- list.files(file.path(success, "Tables"), pattern = paste0("^Table 1-", db), full.names = TRUE)[1]
  if (is.na(f)) { cli::cli_alert_danger("{db} Table1 missing"); next }
  x <- as.data.frame(read_excel(f, col_names = FALSE), stringsAsFactors = FALSE)
  labs <- unique(trimws(as.character(x[[1]])))
  labs <- labs[!is.na(labs) & nzchar(labs)]
  cells <- unlist(lapply(x, as.character), use.names = FALSE)
  hit <- cells[grepl("N\\s*=|Unweighted N", cells)]
  cli::cli_alert_info(
    "{db}: Table1 labels≈{length(labs)} size={file.info(f)$size} | {paste(utils::head(hit, 2), collapse=' ; ')}"
  )
}
imp <- readRDS(file.path(desc_ck_root, "NHANES", "imputation.rds"))
cli::cli_alert_info("NHANES imputed ncol={ncol(imp$ctx$data$imputed)} n={nrow(imp$ctx$data$imputed)}")
cli::cli_alert_success("描述表全变量重导完成")
