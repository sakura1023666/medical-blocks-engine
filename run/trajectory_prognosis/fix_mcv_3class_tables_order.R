#!/usr/bin/env Rscript
# 定点修复 MCV_3class：S1(N=3119+MCV末位)、S7(MCV末位)、根目录表对齐最新 step 产物
.ca <- commandArgs(trailingOnly = FALSE)
.f <- grep("^--file=", .ca, value = TRUE)
script_dir <- if (length(.f)) dirname(normalizePath(sub("^--file=", "", .f[[1]]), winslash = "/")) else getwd()
root <- if (basename(script_dir) == "trajectory_prognosis") {
  normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
} else {
  normalizePath(getwd(), winslash = "/")
}
setwd(root)

source("R/utils.R")
source("R/study_batch_runner.R")
source("R/trajectory_survival_utils.R")
source("R/trajectory_prognosis_batch_runner.R")
source("R/trajectory_pub_curate.R")
source("Blocks/03_imputation/01block_imputation.R")
source("Blocks/53_trajectory_prognosis_full/07block_trajectory_baseline_by_class.R")
source("configs/indices/composite_index_vars.R")

cfg_path <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/config_trajectory_prognosis_stroke_batch.R"
source(cfg_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, pipeline.database_name = "MIMIC")

ix <- "MCV"
out_root <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/by_index/MCV_3class/mimic"
out_ck <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/checkpoints/by_index/MCV_3class/mimic"
tab <- file.path(out_root, "Tables")
ck_jlcm <- "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/checkpoints/by_index/MCV/mimic"

config_ix <- trajectory_batch_patch_config_for_index(config, ix)
config_ix$project$output_dir <- out_root
config_ix$project$database <- "MIMIC"
config_ix$trajectory_baseline_by_class$vars_from <- "table1"
config_ix$trajectory_baseline_by_class$index_vars <- c(ix)
config_ix$trajectory_baseline_by_class$pause_enable <- FALSE

ctx <- study_batch_load_checkpoint_ctx(out_ck, "baseline_binary")
ctx$config <- config_ix
ctx$root_output_dir <- out_root
ctx$output_dir <- file.path(out_root, "step_fix_tables")
ctx$output_dir_tables <- file.path(ctx$output_dir, "Tables")
ctx$output_dir_figures <- file.path(ctx$output_dir, "Figures")
dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
if (exists("pub_reset_counters", mode = "function")) pub_reset_counters(ctx)

cli::cli_alert_info("imputed n={nrow(ctx$data$imputed)}; before_mi n={nrow(ctx$results$data_before_mi)}")
stopifnot(nrow(ctx$data$imputed) == 3119L)
stopifnot(identical(tail(ctx$results$table1_var_order, 1L), "MCV"))

idc <- config_ix$data$id_column %||% "subject_id"
if (!"MCV" %in% names(ctx$results$data_before_mi)) {
  ctx$results$data_before_mi <- dplyr::left_join(
    ctx$results$data_before_mi,
    ctx$data$imputed[, c(idc, "MCV"), drop = FALSE],
    by = idc
  )
}

other_ix <- trajectory_batch_other_index_vars(config_ix, ix)
ctx$config$imputation$export_table_s1 <- TRUE
ctx$config$imputation$force_keep_columns <- c(ix)
ctx$config$survival$index_var <- ix
ctx$config$prediction$index_vars <- c(ix)
ctx$config$imputation$table_s1_exclude_vars <- unique(c(
  setdiff(as.character(ctx$config$imputation$table_s1_exclude_vars %||% character(0)), ix),
  other_ix, "trajectory_class", "trajectory_class_MCV"
))
ctx$config$baseline_binary$exclude_vars <- unique(c(
  as.character(ctx$config$baseline_binary$exclude_vars %||% character(0)),
  other_ix, "trajectory_class", "trajectory_class_MCV"
))

strata <- ctx$config$baseline$table_strata %||% ctx$config$survival$exposure %||% "survival_28d"
ag <- ctx$config$project$analysis_group %||% "Non-survivor"
rg <- ctx$config$project$reference_group %||% "Survivor"
ctx <- .imp01_build_table_s1(
  ctx, ctx$config, ctx$results$data_before_mi, ctx$data$imputed,
  strata, ag, rg, ctx$config$imputation %||% list()
)
ctx <- flush_pub_output_queues(ctx)
cli::cli_alert_success("Table S1 rebuilt")

# 确保 trajectory_class
if (!"trajectory_class" %in% names(ctx$data$imputed)) {
  ctxj <- study_batch_load_checkpoint_ctx(ck_jlcm, "trajectory_jlcm")
  pack <- ctxj$results$trajectory_jlcm_models$MCV
  m <- pack$models$m3
  if (is.list(m) && inherits(m$best, "Jointlcmm")) m <- m$best
  pprob <- as.data.frame(m$pprob)
  md <- unique(pack$model_data_final[, c(idc, "subject_id_num")])
  sc <- dplyr::left_join(md, pprob[, c("subject_id_num", "class")], by = "subject_id_num")
  sc$trajectory_class <- as.integer(sc$class)
  sc$trajectory_class_MCV <- sc$trajectory_class
  for (slot in c("imputed", "cleaned", "mapped")) {
    if (is.null(ctx$data[[slot]])) next
    d <- ctx$data[[slot]]
    d[[idc]] <- as.character(d[[idc]])
    d$trajectory_class <- NULL
    d$trajectory_class_MCV <- NULL
    d <- dplyr::left_join(
      d,
      dplyr::mutate(sc[, c(idc, "trajectory_class", "trajectory_class_MCV")],
                    !!idc := as.character(.data[[idc]])),
      by = idc
    )
    ctx$data[[slot]] <- d
  }
  ctx$results$trajectory_jlcm_models <- ctxj$results$trajectory_jlcm_models
}

ctx <- block_trajectory_baseline_by_class(ctx)
ctx <- flush_pub_output_queues(ctx)
cli::cli_alert_success("Table S7 rebuilt")

# 拷贝正式命名到根 Tables
copy_one <- function(src, dest) {
  if (!file.exists(src)) {
    cli::cli_alert_warning("缺失: {src}")
    return(FALSE)
  }
  file.copy(src, dest, overwrite = TRUE)
  cli::cli_alert_info("copied {basename(src)} -> {basename(dest)}")
  TRUE
}

s1_files <- list.files(
  c(ctx$output_dir_tables, file.path(out_root, "step_fix_tables/Tables")),
  pattern = "before and after multiple imputation.*\\.xlsx$",
  full.names = TRUE, recursive = TRUE
)
s1_files <- s1_files[file.exists(s1_files)]
s1_pick <- NULL
for (f in s1_files[order(file.info(s1_files)$mtime, decreasing = TRUE)]) {
  d <- tryCatch(openxlsx::read.xlsx(f, 1), error = function(e) NULL)
  if (is.null(d)) next
  if (!any(grepl("^MCV$", as.character(d[[1]])))) next
  s1_pick <- f
  break
}
if (!is.null(s1_pick)) {
  copy_one(s1_pick, file.path(tab, "Table S1-MIMIC. Baseline characteristics of patients before and after multiple imputation.xlsx"))
}

s7_files <- list.files(
  c(ctx$output_dir_tables, file.path(out_root, "step_fix_tables")),
  pattern = "Baseline_By_Class|by trajectory class",
  full.names = TRUE, recursive = TRUE
)
s7_files <- s7_files[grepl("\\.xlsx$", s7_files) & file.exists(s7_files)]
s7_files <- s7_files[order(file.info(s7_files)$mtime, decreasing = TRUE)]
if (length(s7_files)) {
  copy_one(s7_files[[1]], file.path(tab, "Table S7-MIMIC. Baseline characteristics by trajectory class (MCV).xlsx"))
}

copy_one(
  file.path(out_root, "step13_baseline_binary/Tables/Table 1-MIMIC. Baseline characteristics of ischemic stroke.xlsx"),
  file.path(tab, "Table 1-MIMIC. Baseline characteristics of ischemic stroke.xlsx")
)
copy_one(
  file.path(out_root, "step13_baseline_binary/Tables/Table S1-MIMIC. Normality test results for continuous variables (n=3119).xlsx"),
  file.path(tab, "Table S2-MIMIC. Normality test results for continuous variables.xlsx")
)
copy_one(
  file.path(out_root, "step14_univariate_prognosis/Tables/Table S2-MIMIC. Univariate Regression Analysis.xlsx"),
  file.path(tab, "Table S3-MIMIC. Univariate Regression Analysis.xlsx")
)
copy_one(
  file.path(out_root, "step15_multicollinearity_screen/Tables/Table S3-MIMIC. Multicollinearity Analysis (VIF, univariate screen) for ischemic_stroke.xlsx"),
  file.path(tab, "Table S4-MIMIC. Multicollinearity Analysis (VIF, univariate screen).xlsx")
)
copy_one(
  file.path(out_root, "step16_multivariate_prognosis/Tables/Table S4-MIMIC. Multivariable Regression Analysis.xlsx"),
  file.path(tab, "Table S5-MIMIC. Multivariable Regression Analysis.xlsx")
)
copy_one(
  file.path(out_root, "step18_multicollinearity_final/Tables/Table S5-MIMIC. Multicollinearity Analysis (VIF, multivariate final) for ischemic_stroke.xlsx"),
  file.path(tab, "Table S6-MIMIC. Multicollinearity Analysis (VIF, multivariate final).xlsx")
)

ctxj <- study_batch_load_checkpoint_ctx(ck_jlcm, "trajectory_jlcm")
cov <- ctxj$results$trajectory_jlcm_models$MCV$covariate_vars_used
sum_dir <- file.path(tab, "Summary")
dir.create(sum_dir, recursive = TRUE, showWarnings = FALSE)
writeLines(
  c(
    "# Final covariates (JLCM survival submodel) — MCV / MIMIC",
    paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    cov
  ),
  file.path(sum_dir, "FinalCovariates_MCV_mimic.txt")
)

arch <- file.path(tab, "_archive")
dir.create(arch, recursive = TRUE, showWarnings = FALSE)
junk <- list.files(tab, pattern = "^Table S(9|10|11|12)-|^Table_S5_|^Table Weibull|^Table_Trajectory", full.names = TRUE)
for (f in junk) {
  file.copy(f, file.path(arch, basename(f)), overwrite = TRUE)
  unlink(f)
}

cli::cli_alert_success("定点修复完成")
