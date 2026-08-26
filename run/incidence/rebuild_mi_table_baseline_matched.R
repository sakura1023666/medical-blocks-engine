#!/usr/bin/env Rscript
###############################################################################
#  rebuild_mi_table_baseline_matched.R
#
#  不改动流水线 / 现有表：
#    1) 按 baseline 分析人群 ID 对齐 BeforeMI / AfterMI，在各库首个 baseline
#       步骤 Tables/ 写出 Table MI_baseline_matched-*.xlsx/.tex
#    2) 同步导出 baseline 时的 ctx$data$imputed 到该 baseline 步骤根目录
#       D01_AfterMI_imputed-<DB>.RData / .rds
#
#  用法:
#    Rscript run/incidence/rebuild_mi_table_baseline_matched.R \
#      --study-root /mnt/g/02block_result/15_hearing_loss/incidence_38341157 \
#      --index UHR
#    Rscript run/incidence/rebuild_mi_table_baseline_matched.R \
#      --study-root /mnt/g/02block_result/13_MAFLD/incidence_38341157 \
#      --index LCI
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
.arg_val <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

this_file <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1L])
root_env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(root_env) && dir.exists(root_env)) {
  root <- normalizePath(root_env, mustWork = TRUE)
} else if (length(this_file) && nzchar(this_file) && file.exists(this_file)) {
  # 脚本位于 <root>/run/incidence/ → 上两级为引擎根
  root <- normalizePath(file.path(dirname(this_file), "../.."), mustWork = TRUE)
} else {
  root <- normalizePath(getwd(), mustWork = TRUE)
}

study_root <- .arg_val(
  "--study-root",
  "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
)
index_name <- .arg_val("--index", "UHR")

if (!dir.exists(study_root)) stop("study-root 不存在: ", study_root)
if (!dir.exists(root)) stop("engine root 不存在: ", root)
if (!file.exists(file.path(root, "R/utils.R"))) {
  stop("engine root 无 R/utils.R: ", root)
}

source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/baseline_dictionary_labels.R"), local = FALSE)
source(file.path(root, "R/pipeline_capability_layer.R"), local = FALSE)
source(file.path(root, "Blocks/03_imputation/01block_imputation.R"), local = FALSE)

by_index_pub <- file.path(study_root, "by_index", paste0("【success】", index_name))
if (!dir.exists(by_index_pub)) {
  # 兼容无【success】前缀的目录
  alt <- file.path(study_root, "by_index", index_name)
  if (dir.exists(alt)) by_index_pub <- alt
}
ck_index <- file.path(study_root, "checkpoints", "by_index", index_name)

# 自动发现各库：pub 下的 DB 子目录 + checkpoints
.discover_first_baseline_step <- function(db_pub_dir) {
  if (!dir.exists(db_pub_dir)) return(NULL)
  steps <- list.dirs(db_pub_dir, full.names = TRUE, recursive = FALSE)
  bn <- basename(steps)
  # 优先第一个 baseline_nhanes，其次第一个 baseline_binary
  hit_n <- steps[grepl("^step\\d+_baseline_nhanes$", bn)]
  if (length(hit_n)) return(hit_n[order(bn[grepl("^step\\d+_baseline_nhanes$", bn)])][1L])
  hit_b <- steps[grepl("^step\\d+_baseline_binary$", bn)]
  if (length(hit_b)) return(hit_b[order(bn[grepl("^step\\d+_baseline_binary$", bn)])][1L])
  NULL
}

.discover_jobs <- function() {
  jobs <- list()
  db_candidates <- character(0)
  if (dir.exists(by_index_pub)) {
    db_candidates <- c(db_candidates, basename(list.dirs(by_index_pub, full.names = TRUE, recursive = FALSE)))
  }
  if (dir.exists(ck_index)) {
    db_candidates <- c(db_candidates, basename(list.dirs(ck_index, full.names = TRUE, recursive = FALSE)))
  }
  # 第三方库 Liling 等可能挂在 checkpoints/Liling_<index>
  lil_ck <- file.path(study_root, "checkpoints", paste0("Liling_", index_name))
  if (dir.exists(lil_ck)) db_candidates <- c(db_candidates, "Liling")
  db_candidates <- unique(db_candidates)
  db_candidates <- setdiff(db_candidates, c("Figures", "Tables", "sensitivity", "Data", "harmonization"))

  for (db in db_candidates) {
    imp_ck <- file.path(ck_index, db, "imputation.rds")
    bl_ck <- file.path(ck_index, db, "baseline_nhanes.rds")
    if (!file.exists(bl_ck)) bl_ck <- file.path(ck_index, db, "baseline_binary.rds")
    if (identical(db, "Liling") && (!file.exists(imp_ck) || !file.exists(bl_ck))) {
      imp_ck <- file.path(study_root, "checkpoints", paste0("Liling_", index_name), "imputation.rds")
      bl_ck <- file.path(study_root, "checkpoints", paste0("Liling_", index_name), "baseline_binary.rds")
    }
    if (!file.exists(imp_ck) || !file.exists(bl_ck)) {
      next
    }
    bas_step <- .discover_first_baseline_step(file.path(by_index_pub, db))
    if (is.null(bas_step)) {
      # 无 pub step 时仍可落盘到 by_index/<db>/baseline_export
      bas_step <- file.path(by_index_pub, db, "baseline_export")
      dir.create(bas_step, recursive = TRUE, showWarnings = FALSE)
      cli::cli_alert_warning("{db}: 未找到 step*_baseline_*，将写到 {bas_step}")
    }
    jobs[[length(jobs) + 1L]] <- list(
      db = db,
      bl_ck = bl_ck,
      imp_ck = imp_ck,
      baseline_dir = bas_step,
      tables_dir = file.path(bas_step, "Tables")
    )
  }
  if (!length(jobs)) {
    stop("未发现任何可用的 DB job（检查 checkpoints/by_index/", index_name, " 与 by_index）")
  }
  jobs
}

jobs <- .discover_jobs()
cat("发现 ", length(jobs), " 个库: ", paste(vapply(jobs, `[[`, "", "db"), collapse = ", "), "\n", sep = "")

.pick_id_col <- function(df, prefer = c("ID", "SEQN", "subject_id")) {
  hit <- intersect(prefer, names(df))
  if (!length(hit)) stop("找不到 ID 列: ", paste(prefer, collapse = "/"))
  hit[[1L]]
}

.subset_by_ids <- function(df, id_col, ids) {
  ids <- as.character(ids)
  key <- as.character(df[[id_col]])
  m <- match(ids, key)
  if (anyNA(m)) {
    stop(
      sprintf(
        "有 %d/%d 个 baseline ID 在数据中找不到（id_col=%s）",
        sum(is.na(m)), length(ids), id_col
      )
    )
  }
  df[m, , drop = FALSE]
}

# 固定新文件名（不占用原 Table S1 编号体系）
.out_stem <- function(db, n) {
  sprintf(
    "Table MI_baseline_matched-%s. Characteristics before and after MI (baseline cohort n=%s)",
    db, n
  )
}

run_one <- function(job) {
  cat("\n========== ", job$db, " ==========\n", sep = "")
  for (p in c(job$bl_ck, job$imp_ck)) {
    if (!file.exists(p)) stop("checkpoint 缺失: ", p)
  }
  if (!dir.exists(job$tables_dir)) {
    dir.create(job$tables_dir, recursive = TRUE)
  }

  bl <- readRDS(job$bl_ck)$ctx
  im <- readRDS(job$imp_ck)$ctx

  bl_df <- bl$data$imputed
  if (is.null(bl_df) || !is.data.frame(bl_df) || !nrow(bl_df)) {
    stop(job$db, ": baseline checkpoint 无 data$imputed")
  }
  before_full <- im$results$data_before_mi
  after_full <- im$data$imputed
  if (is.null(before_full) || is.null(after_full)) {
    stop(job$db, ": imputation checkpoint 缺少 data_before_mi 或 imputed")
  }

  id_bl <- .pick_id_col(bl_df)
  id_bf <- .pick_id_col(before_full)
  id_af <- .pick_id_col(after_full)
  ids <- as.character(bl_df[[id_bl]])
  cat(
    "  baseline n=", length(ids),
    " (unique=", length(unique(ids)), ")",
    "  BeforeMI n=", nrow(before_full),
    "  AfterMI n=", nrow(after_full), "\n",
    sep = ""
  )

  # 统一 ID 列名再匹配
  if (!identical(id_bf, id_bl)) {
    names(before_full)[names(before_full) == id_bf] <- id_bl
  }
  if (!identical(id_af, id_bl)) {
    names(after_full)[names(after_full) == id_af] <- id_bl
  }

  data_before <- .subset_by_ids(before_full, id_bl, ids)
  data_after  <- .subset_by_ids(after_full, id_bl, ids)
  stopifnot(nrow(data_before) == length(ids), nrow(data_after) == length(ids))
  cat("  ID 对齐后 n=", nrow(data_before), "\n", sep = "")

  cfg <- bl$config %||% im$config
  # 写表时注入库名，便于文件名带 NHANES/CHARLS/Liling
  cfg$project$database <- job$db

  outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
  study_type <- tolower(cfg$project$study_type %||% "incidence")
  outcome_lbl <- pipeline_resolve_outcome_display_labels(cfg)
  table_strata <- if (identical(study_type, "prognosis")) {
    cfg$survival$event_var %||% outcome_col
  } else {
    outcome_col
  }

  # 小样本库（如 Liling n=411）避免把连续协变量误判为 ID-like 而剔除
  force_keep <- unique(c(
    as.character((cfg$imputation %||% list())$force_keep_columns %||% character(0)),
    "UHR", "Age", "Weight", "Height", "BMI",
    "Total_Cholesterol", "Triglycerides", "LDL", "HDL", "BUN", "WBC",
    "Creatinine", "Hematocrit", "Platelet_Count", "Uric_Acid", "Hemoglobin"
  ))
  imp_cfg <- cfg$imputation %||% list()
  imp_cfg$force_keep_columns <- force_keep
  imp_cfg$table_s1_title <- sprintf(
    "Characteristics before and after MI restricted to baseline analysis cohort (ID-matched, n=%s)",
    length(ids)
  )

  # 假 ctx：仅用于构造 Table S1（导出到最终固定文件名，不占用原 S 号）
  ctx <- bl
  ctx$config <- cfg
  ctx$config$project$database <- job$db
  ctx$config$project$mirror_pub_outputs_to_root <- FALSE
  ctx$root_output_dir <- dirname(job$tables_dir)
  ctx$output_dir <- dirname(job$tables_dir)
  # 先让 build 写到临时目录，避免中间 Table S* 污染正式 Tables
  tmp_tables <- file.path(tempdir(), paste0("mi_bl_match_", job$db, "_", as.integer(Sys.time())))
  dir.create(tmp_tables, recursive = TRUE, showWarnings = FALSE)
  ctx$output_dir_tables <- tmp_tables
  ctx$output_dir_figures <- file.path(dirname(job$tables_dir), "Figures")
  ctx$results$mi_quality_exclude_vars <- character(0)

  if (exists(".table_queue_env", mode = "environment")) {
    .table_queue_env$items <- list()
  }

  ctx <- .imp01_build_table_s1(
    ctx, cfg, data_before, data_after,
    table_strata,
    outcome_lbl$analysis, outcome_lbl$reference,
    imp_cfg
  )
  # 丢弃 build 内部入队项；改用固定文件名写出
  if (exists(".table_queue_env", mode = "environment")) {
    .table_queue_env$items <- list()
  }

  stem <- .out_stem(job$db, length(ids))
  title <- paste0(
    "Table MI_baseline_matched-", job$db, ". ",
    "Characteristics before and after MI restricted to baseline analysis cohort (ID-matched, n=",
    length(ids), ")"
  )
  if (is.null(ctx$results$table_s1) || !nrow(ctx$results$table_s1)) {
    stop(job$db, ": table_s1 为空，无法导出")
  }
  fp_xlsx <- file.path(job$tables_dir, paste0(stem, ".xlsx"))
  # 清除同目录下本任务可能残留的中间命名
  leftovers <- list.files(
    job$tables_dir, full.names = TRUE,
    pattern = "(before and after MI restricted to baseline|MI baseline matched|MI_baseline_matched)"
  )
  if (length(leftovers)) unlink(leftovers)

  export_sci_table(ctx$results$table_s1, fp_xlsx, title = title)
  if (exists("flush_pub_output_queues", mode = "function")) {
    ctx$output_dir_tables <- job$tables_dir
    ctx <- flush_pub_output_queues(ctx)
  } else if (exists("render_queued_tables", mode = "function")) {
    ctx$output_dir_tables <- job$tables_dir
    ctx <- render_queued_tables(ctx)
  }

  # flush 可能因 inject_db 改文件名：统一改成 stem
  produced <- list.files(
    job$tables_dir, full.names = TRUE,
    pattern = "MI_baseline_matched|MI baseline matched|before and after MI restricted"
  )
  renamed <- character(0)
  for (f in produced) {
    if (!file.exists(f)) next
    if (grepl("Normality test", basename(f), ignore.case = TRUE)) next
    ext <- tools::file_ext(f)
    dest <- file.path(job$tables_dir, paste0(stem, ".", ext))
    if (!identical(
      normalizePath(f, winslash = "/", mustWork = FALSE),
      normalizePath(dest, winslash = "/", mustWork = FALSE)
    )) {
      if (file.exists(dest)) unlink(dest)
      if (!isTRUE(file.rename(f, dest))) {
        file.copy(f, dest, overwrite = TRUE)
        unlink(f)
      }
    }
    if (file.exists(dest)) {
      renamed <- c(renamed, dest)
      cat("  wrote: ", dest, " size=", file.info(dest)$size %||% NA, "\n", sep = "")
    }
  }
  unlink(tmp_tables, recursive = TRUE)

  # ── 同步导出 baseline 时的 ctx$data$imputed ─────────────────────────────
  baseline_dir <- job$baseline_dir %||% dirname(job$tables_dir)
  if (!dir.exists(baseline_dir)) dir.create(baseline_dir, recursive = TRUE)
  imputed <- bl_df
  rdata_path <- file.path(baseline_dir, paste0("D01_AfterMI_imputed-", job$db, ".RData"))
  rds_path   <- file.path(baseline_dir, paste0("D01_AfterMI_imputed-", job$db, ".rds"))
  save(imputed, file = rdata_path)
  saveRDS(imputed, file = rds_path)
  cat("  imputed data: ", rdata_path, " (n=", nrow(imputed), " p=", ncol(imputed), ")\n", sep = "")
  cat("                 ", rds_path, "\n", sep = "")

  # 注记
  note <- file.path(job$tables_dir, paste0("Table MI_baseline_matched-", job$db, ".README.txt"))
  writeLines(
    c(
      paste0("Database: ", job$db),
      paste0("Index: ", index_name),
      paste0("Baseline population source: ", job$bl_ck, " → ctx$data$imputed (ID)"),
      paste0("Before MI source: ", job$imp_ck, " → ctx$results$data_before_mi"),
      paste0("After MI source: ", job$imp_ck, " → ctx$data$imputed"),
      paste0("ID column: ", id_bl),
      paste0("n_baseline / matched: ", length(ids)),
      paste0("n_before_mi_full: ", nrow(before_full)),
      paste0("n_after_mi_full: ", nrow(after_full)),
      paste0("Imputed data export: ", rdata_path),
      paste0("Imputed data export: ", rds_path),
      "Note: existing Table 1 / original imputation Table S1 files were not modified.",
      paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    ),
    note
  )
  note2 <- file.path(baseline_dir, paste0("D01_AfterMI_imputed-", job$db, ".README.txt"))
  writeLines(
    c(
      paste0("Database: ", job$db),
      paste0("Index: ", index_name),
      paste0("Source: ", job$bl_ck, " → ctx$data$imputed"),
      paste0("n=", nrow(imputed), ", p=", ncol(imputed)),
      paste0("columns: ", paste(names(imputed), collapse = ", ")),
      "Load: load(...RData)  # object: imputed",
      "      readRDS(...rds)",
      paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    ),
    note2
  )
  cat("  note: ", note, "\n", sep = "")
  invisible(renamed)
}

all_out <- lapply(jobs, function(j) {
  tryCatch(run_one(j), error = function(e) {
    cat("ERROR ", j$db, ": ", conditionMessage(e), "\n", sep = "")
    NULL
  })
})
cat("\nDone.\n")
invisible(all_out)
