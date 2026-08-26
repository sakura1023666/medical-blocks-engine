#!/usr/bin/env Rscript
# 昼夜三库 Table 1 对齐重出：Age + 同一 include 顺序。
# 用 step03（exclusion 之前，Age/BMI/实验室还在）+ NHANES 从 D04 补 Education/Smoking/HbA1c。
# 不改 imputed，Model1/2 仍不含 Age。
root <- "/mnt/e/01block/01Block-new-Final"
study <- "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747"
setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/cross_lagged_covariate_lock.R"))
source(file.path(root, "R/cross_lagged_study_meta.R"))
source(file.path(root, "Blocks/04_baseline/01block_baseline_binary.R"))
sys.source(file.path(study, "config_phase1_common.R"), envir = environment())

inc <- .CIRCADIAN_TABLE1_INCLUDE
exc <- .CIRCADIAN_TABLE1_EXCLUDE
labs <- .CIRCADIAN_TABLE1_LABELS
lock <- list(
  vars = c("Education", "Smoking"),
  level_order = list(
    Gender = c("Female", "Male"),
    Education = c("Below High school", "Above High school"),
    Marital_Status = c("Unmarried", "Married"),
    Smoking = c("Never", "Current"),
    Alcohol_drinking = c("No", "Yes"),
    Hypertension = c("No", "Yes"),
    Diabetes = c("No", "Yes")
  )
)

for (db in c("CHARLS", "ELSA", "NHANES")) {
  cli::cli_h1("Table 1 aligned: {db}")
  if (exists("pub_reset_counters", mode = "function")) pub_reset_counters()
  options(pipeline.database_name = db)
  cdir <- file.path(cross_lagged_phase1_dir(study, db), "checkpoints")
  p3 <- file.path(cdir, "step03_index.rds")
  ck <- readRDS(p3)
  if (!is.null(ck$ctx)) ck <- ck$ctx
  d <- ck$data$imputed %||% ck$data$cleaned
  d <- as.data.frame(d)
  d$ID <- as.character(d$ID)
  if ("Smoke" %in% names(d) && !"Smoking" %in% names(d)) d$Smoking <- d$Smoke
  if ("TC" %in% names(d) && !"Total_Cholesterol" %in% names(d))
    d$Total_Cholesterol <- d$TC
  if ("TG" %in% names(d) && !"Triglycerides" %in% names(d))
    d$Triglycerides <- d$TG
  extra_lock <- lock
  extra_lock$vars <- unique(c(
    lock$vars, inc, "Education", "Smoking", "HbA1c", "Age", "Height", "BMI",
    "Waist_circumference", "Triglycerides", "Hemoglobin", "WBC", "HDL",
    "Total_Cholesterol"
  ))
  d <- cross_lagged_attach_harmonize_fig3(d, study, db, extra_lock)
  if ("Smoke" %in% names(d) && !"Smoking" %in% names(d)) d$Smoking <- d$Smoke
  out_dir <- file.path(study, paste0("phase1_", db))
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
  ctx <- list(
    data = list(imputed = d, cleaned = d),
    results = list(),
    output_dir = out_dir,
    output_dir_tables = file.path(out_dir, "Tables"),
    output_dir_figures = file.path(out_dir, "Figures"),
    config = list(
      project = list(
        database = db,
        disease = "Circadian_rhythm",
        analysis_group = "Circadian_Disorder",
        reference_group = "No_Disorder",
        output_dir = out_dir,
        classification_mode = "binary"
      ),
      data = list(outcome_column = "Disease_Group", id_column = "ID"),
      force_continuous_vars = c(
        "Age", "Weight", "Height", "BMI", "Waist_circumference",
        "HbA1c", "HDL", "Total_Cholesterol", "Triglycerides",
        "Hemoglobin", "WBC", "ePWV"
      ),
      baseline_binary = list(
        sig_cutoff = 0.05,
        strata = "Disease_Group",
        include_vars = inc,
        exclude_vars = exc,
        table1_label_overrides = labs,
        table1_append_units_from_dictionary = FALSE,
        pad_missing_include_vars = TRUE,
        pause_enable = FALSE,
        pause_on_table1_fail = FALSE,
        pause_on_min_sig_vars = FALSE,
        export_train_val_baseline = FALSE
      )
    )
  )
  ctx <- block_baseline_binary(ctx)
  tbl_dir <- file.path(out_dir, "Tables")
  srcs <- list.files(tbl_dir, pattern = "^Table 1-.*\\.xlsx$", full.names = TRUE)
  wrong <- srcs[!grepl(paste0("^Table 1-", db, "\\."), basename(srcs))]
  if (length(wrong)) unlink(wrong, force = TRUE)
  cli::cli_alert_info("{db} wrote: {paste(basename(list.files(tbl_dir, pattern='^Table 1-.*xlsx$')), collapse=', ')}")
}

# collect into summary_result/table
collect_sh <- file.path(root, "Blocks/54_cross_lagged_full/phases/collect_summary_result.sh")
if (!dir.exists(study)) stop("study root not found: ", study)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study)
status <- system2("bash", shQuote(c(collect_sh, study)), stdout = TRUE, stderr = TRUE)
if (!is.null(attr(status, "status")) && attr(status, "status") != 0L) {
  stop("collect_summary_result failed:\n", paste(status, collapse = "\n"))
}
cli::cli_alert_success("summary_result updated")
