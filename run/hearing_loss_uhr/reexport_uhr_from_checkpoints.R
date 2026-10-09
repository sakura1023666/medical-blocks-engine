#!/usr/bin/env Rscript
# 从 checkpoint 重导听力 UHR 表图（修复 9p rename 导致的 0 字节文件）
# Gate A 已 keep-all；协变量锁 Age/WBC/Hypertension
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE, warn = 1))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
dual_cfg <- file.path(study, "config_incidence_dual_batch.R")
lil_cfg  <- file.path(study, "config_incidence_liling.R")
lock <- jsonlite::fromJSON(file.path(study, "data/harmonized/covariate_lock.json"))
m1 <- as.character(lock$model1)
m2 <- as.character(lock$model2)
cmf <- as.character(lock$common_model_factors %||% setdiff(m2, m1))
ix <- "UHR"
out_dir <- file.path(study, "by_index", "UHR")
out_copy <- file.path(study, "by_index", "【success】UHR - 副本")

setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))

force_lock_cfg <- function(cfg) {
  cfg$logistic$model1_factors <- m1
  cfg$logistic$model2_factors <- m2
  cfg$logistic$model2_max_covariates <- 20L
  for (nm in c(
    "logistic_nhanes_weighted",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted", "rcs_incidence", "rcs_nhanes"
  )) {
    if (!is.null(cfg[[nm]])) {
      cfg[[nm]]$model1_factors <- m1
      cfg[[nm]]$model2_factors <- m2
      if (!is.null(cfg[[nm]]$random_search)) {
        cfg[[nm]]$random_search$enable <- FALSE
        cfg[[nm]]$random_search$max_outer_attempts <- 1L
      }
    }
  }
  if (!is.null(cfg$dual_db$harmonization)) {
    cfg$dual_db$harmonization$lock_covariates_preset <- TRUE
    cfg$dual_db$harmonization$covariate_source <- "vif_screen"
    cfg$dual_db$harmonization$sync_after_vif_final <- FALSE
    cfg$dual_db$harmonization$require_same_clinical_cols <- TRUE
    cfg$dual_db$harmonization$harmonized_model1_nhanes <- m1
    cfg$dual_db$harmonization$harmonized_model2_nhanes <- m2
    cfg$dual_db$harmonization$harmonized_model1_mimic <- m1
    cfg$dual_db$harmonization$harmonized_model2_mimic <- m2
    cfg$dual_db$harmonization$common_model_factors <- cmf
  }
  cfg$incidence$index_var <- ix
  cfg$logistic$index_var <- ix
  cfg
}

drop_mv_tables <- function(tab_dir) {
  if (!dir.exists(tab_dir)) return(invisible())
  old <- list.files(
    tab_dir,
    pattern = "Multivariable|multivariate|VIF, multivariate|VIF final",
    full.names = TRUE, ignore.case = TRUE
  )
  if (length(old)) unlink(old)
}

# 清掉坏的 0 字节产出；保留 checkpoints
for (p in c(out_dir, out_copy, file.path(study, "by_index", "【success】UHR"),
            file.path(study, "by_index", "【failed】UHR"))) {
  if (dir.exists(p)) {
    unlink(p, recursive = TRUE, force = TRUE)
    cli::cli_alert_info("cleared broken outputs: {p}")
  }
}
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

Sys.setenv(STUDY_CONFIG_DIR = dirname(dual_cfg))
source(dual_cfg)
config <- force_lock_cfg(config)
config$incidence_batch$output_base <- study
config$project$root <- study
config$incidence_batch$sensitivity_suite$enable <- FALSE

rerun_dual <- function(db) {
  cfg_db <- force_lock_cfg(incidence_batch_apply_db_overrides(config, db, root, ix))
  out_db <- file.path(out_dir, dual_db_slot_path_name(cfg_db, db))
  cfg_db$project$output_dir <- out_db
  dir.create(out_db, recursive = TRUE, showWarnings = FALSE)
  if (dual_db_is_weighted(config, db)) {
    pl <- pipeline_nhanes_batch
  } else {
    pl <- pipeline_regular_batch
  }
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir <- file.path(study, "checkpoints", "by_index", ix, dual_db_slot_path_name(config, db))
  # 优先从 obj 续跑（跳过 MICE）；无 obj 则 trim → imputation → index
  ck_dir <- pl$checkpoint$dir
  from_block <- if (file.exists(file.path(ck_dir, "obj.rds"))) {
    "obj"
  } else if (file.exists(file.path(ck_dir, "trim_index_extreme.rds"))) {
    "trim_index_extreme"
  } else if (file.exists(file.path(ck_dir, "imputation.rds"))) {
    "imputation"
  } else {
    "index"
  }
  cli::cli_h2("重导 dual [{toupper(db)}] from={from_block}（跳过已有插补，重写表图）")
  run_pipeline(root, config = cfg_db, pipeline = pl,
               run_opts = list(from = from_block))
  drop_mv_tables(file.path(out_db, "Tables"))
}

for (db in c("nhanes", "mimic")) {
  rerun_dual(db)
}
tryCatch(
  incidence_batch_finalize_index_outputs(root, config, ix, c("nhanes", "mimic")),
  error = function(e) cli::cli_alert_warning("finalize: {e$message}")
)

# Liling：检查点在 Liling_UHR
Sys.setenv(STUDY_CONFIG_DIR = dirname(lil_cfg))
rm(list = intersect(c("pipeline", "config", "pipeline_nhanes_batch", "pipeline_regular_batch"),
                    ls(envir = .GlobalEnv)), envir = .GlobalEnv)
source(lil_cfg)
config <- force_lock_cfg(config)
lil_out <- file.path(out_dir, "Single")
config$project$output_dir <- lil_out
dir.create(lil_out, recursive = TRUE, showWarnings = FALSE)
pl <- pipeline
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- file.path(study, "checkpoints", "Liling_UHR")
cli::cli_h2("重导 Liling from=column_mapping")
run_pipeline(
  root, config = config, pipeline = pl,
  run_opts = list(from = "column_mapping")
)

# 打标 success（不 rename 到带空格副本；副本用 PowerShell 复制）
success_dir <- file.path(study, "by_index", "【success】UHR")
if (dir.exists(success_dir)) unlink(success_dir, recursive = TRUE, force = TRUE)
# 用系统 mv（路径无空格）
ok <- file.rename(out_dir, success_dir)
if (!isTRUE(ok)) stop("rename UHR → 【success】UHR failed")

writeLines(
  c(
    paste0("reexport_at=", Sys.time()),
    "mode=no_gate_a_feature_union; covariate_lock_3db; reexport_from_checkpoint",
    paste0("model1=", paste(m1, collapse = ",")),
    paste0("model2=", paste(m2, collapse = ","))
  ),
  file.path(success_dir, "_rerun_meta.txt")
)

# PowerShell 复制到「副本」（正确处理空格/中文）
ps <- paste0(
  "$src = '", gsub("/", "\\\\", success_dir), "'; ",
  "$dst = '", gsub("/", "\\\\", out_copy), "'; ",
  "if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }; ",
  "Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force; ",
  "Write-Output ('COPIED_OK size_table2=' + ((Get-Item -LiteralPath (Join-Path $dst 'Tables')).GetFiles('Table 2*') | Measure-Object Length -Sum).Sum)"
)
ps_file <- tempfile(fileext = ".ps1")
writeLines(ps, ps_file, useBytes = TRUE)
# Convert path for Windows
ps_win <- tempfile(fileext = ".ps1")
# Write via powershell here-string from bash
system2(
  "powershell.exe",
  c("-NoProfile", "-Command",
    sprintf(
      "$src='G:\\02block_result\\15_hearing_loss\\incidence_38341157\\by_index\\【success】UHR'; $dst='G:\\02block_result\\15_hearing_loss\\incidence_38341157\\by_index\\【success】UHR - 副本'; if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }; Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force; $z=(Get-ChildItem -LiteralPath (Join-Path $dst 'Tables') -Filter 'Table 2*' -File | Measure-Object Length -Sum).Sum; Write-Output ('COPIED bytes_table2=' + $z)"
    )),
  stdout = TRUE, stderr = TRUE
)

sh <- file.path(root, "run/hearing_loss_uhr/collect_hearing_uhr_summary_result.sh")
if (file.exists(sh)) system2("bash", c(sh, study))

# 验收：表必须 >0 字节
t2 <- list.files(file.path(success_dir, "Tables"), pattern = "^Table 2", full.names = TRUE)
sz <- sum(file.info(t2)$size, na.rm = TRUE)
cli::cli_alert_info("success Table2 total bytes={sz}")
if (sz < 1000) stop("Table 2 still empty after reexport")
cli::cli_alert_success("重导完成 → {success_dir} 与 {out_copy}")
