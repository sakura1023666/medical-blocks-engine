#!/usr/bin/env Rscript
# 修复听力 UHR 描述 Table1：
# 1) CHARLS：把误编号为 Table 2 的全变量基线表提升为 Table 1
# 2) NHANES：从 trim/obj 检查点重跑加权 baseline（CONUT 类型已修）
# 3) 同步 summary_result / 副本
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE, warn = 1))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
success <- file.path(study, "by_index", "【success】UHR")
copy_dir <- file.path(study, "by_index", "【success】UHR - 副本")
ix <- "UHR"
desc_ck_root <- file.path(study, "checkpoints", "by_index", "UHR_desc_fullvars")
dual_cfg <- file.path(study, "config_incidence_dual_batch.R")

setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))

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
  if (!is.null(cfg$imputation)) {
    cfg$imputation$missing_col_threshold <- 0.4
    cfg$imputation$export_table_s1 <- TRUE
  }
  if (!is.null(cfg$dual_db$harmonization)) {
    cfg$dual_db$harmonization$require_same_clinical_cols <- FALSE
    cfg$dual_db$harmonization$common_non_demo_cols <- NULL
    cfg$dual_db$harmonization$column_keep_nhanes <- NULL
    cfg$dual_db$harmonization$column_keep_mimic <- NULL
  }
  cfg$incidence$index_var <- ix
  cfg$logistic$index_var <- ix
  cfg
}

promote_charls_table1 <- function() {
  src <- file.path(success, "CHARLS", "Tables",
                   "Table 2-CHARLS. Baseline characteristics of hearing loss.xlsx")
  stopifnot(file.exists(src))
  dests <- c(
    file.path(success, "CHARLS", "Tables",
              "Table 1-CHARLS. Baseline characteristics of hearing loss.xlsx"),
    file.path(success, "Tables",
              "Table 1-CHARLS. Baseline characteristics of hearing loss.xlsx")
  )
  suppressPackageStartupMessages(library(openxlsx))
  for (dest in dests) {
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    file.copy(src, dest, overwrite = TRUE)
    wb <- openxlsx::loadWorkbook(dest)
    sh <- names(wb)[1L]
    # 标题行改为 Table 1
    v <- openxlsx::read.xlsx(dest, sheet = 1, colNames = FALSE)
    if (nrow(v) >= 1L && grepl("^Table 2\\.", as.character(v[1, 1]) %||% "")) {
      openxlsx::writeData(
        wb, sh,
        gsub("^Table 2\\.", "Table 1.", as.character(v[1, 1]), perl = TRUE),
        startCol = 1, startRow = 1, colNames = FALSE
      )
      openxlsx::saveWorkbook(wb, dest, overwrite = TRUE)
    }
    cli::cli_alert_success("CHARLS promoted → {dest} (size={file.info(dest)$size})")
  }
}

# ── CHARLS promote ──────────────────────────────────────────────────────────
cli::cli_h1("1/3 CHARLS Table2 → Table1")
promote_charls_table1()

# ── NHANES re-export baseline ───────────────────────────────────────────────
cli::cli_h1("2/3 NHANES weighted Table1 re-export")
Sys.setenv(STUDY_CONFIG_DIR = dirname(dual_cfg))
source(dual_cfg)
config <- patch_desc_cfg(config)
config$incidence_batch$output_base <- study
config$project$root <- study

cfg_db <- patch_desc_cfg(incidence_batch_apply_db_overrides(config, "nhanes", root, ix))
out_db <- file.path(success, "NHANES")
cfg_db$project$output_dir <- out_db
cfg_db$project$mirror_pub_outputs_to_root <- TRUE

ck_dst <- file.path(desc_ck_root, "NHANES")
pl <- pipeline_nhanes_batch
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- ck_dst

# 清掉旧短 Table1，避免编号/镜像污染
old_t1 <- list.files(
  file.path(out_db, "Tables"),
  pattern = "^Table 1-NHANES\\..*Baseline",
  full.names = TRUE
)
if (length(old_t1)) file.remove(old_t1)

# 重置发表主表计数，确保写出 Table 1
if (exists(".pub_state", inherits = TRUE)) {
  tryCatch({
    .pub_state$main_table <- 0L
    .pub_state$supp_table <- max(0L, as.integer(.pub_state$supp_table %||% 0L))
  }, error = function(e) NULL)
}

run_pipeline(
  root, config = cfg_db, pipeline = pl,
  run_opts = list(
    from = "obj",
    only = c("baseline_nhanes")
  )
)

# 同步到聚合 Tables
nh_t1 <- list.files(
  file.path(out_db, "Tables"),
  pattern = "^Table 1-NHANES\\..*Baseline.*\\.xlsx$",
  full.names = TRUE
)[1]
if (!is.na(nh_t1) && file.exists(nh_t1)) {
  file.copy(nh_t1, file.path(success, "Tables", basename(nh_t1)), overwrite = TRUE)
  cli::cli_alert_success("NHANES Table1 synced to agg Tables")
} else {
  cli::cli_alert_danger("NHANES Table1 still missing after re-export")
}

# ── sync + 验收 ─────────────────────────────────────────────────────────────
cli::cli_h1("3/3 sync + 验收")
system(sprintf("rm -rf %s && cp -a %s %s", shQuote(copy_dir), shQuote(success), shQuote(copy_dir)))
sh <- file.path(root, "run/hearing_loss_uhr/collect_hearing_uhr_summary_result.sh")
if (file.exists(sh)) system2("bash", c(sh, study))

suppressPackageStartupMessages(library(readxl))
for (db in c("NHANES", "CHARLS", "Single")) {
  f <- list.files(file.path(success, "Tables"), pattern = paste0("^Table 1-", db), full.names = TRUE)[1]
  if (is.na(f)) { cli::cli_alert_danger("{db} Table1 missing"); next }
  x <- as.data.frame(read_excel(f, col_names = FALSE), stringsAsFactors = FALSE)
  labs <- unique(trimws(as.character(x[[1]])))
  labs <- labs[!is.na(labs) & nzchar(labs)]
  cli::cli_alert_info(
    "{db}: Table1 labels≈{length(labs)} rows={nrow(x)} size={file.info(f)$size}"
  )
}
cli::cli_alert_success("Table1 fullvars promote/repair done")
