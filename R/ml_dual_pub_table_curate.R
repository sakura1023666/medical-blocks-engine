###############################################################################
#  ml_dual_pub_table_curate.R — ML 双库指标汇总表整理
#  主表 Table 1–5 + 附表 S1–S8，其余附表顺延；双库同类表合并为一张
###############################################################################

.ml_ptc_db_slots <- function() c("nhanes", "mimic")

.ml_ptc_db_tags <- function(cfg = list()) {
  unique(vapply(.ml_ptc_db_slots(), function(s) .ml_ptc_slot_tag(cfg, s), character(1L)))
}

.ml_ptc_slot_tag <- function(cfg, slot) {
  if (exists("dual_db_slot_path_name", mode = "function")) {
    return(dual_db_slot_path_name(cfg, slot))
  }
  if (slot == "nhanes") "NHANES" else "MIMIC"
}

.ml_ptc_normalize_bn <- function(bn, cfg = list()) {
  bn <- as.character(bn)[1L]
  for (tag in .ml_ptc_db_tags(cfg)) {
    if (!nzchar(tag)) next
    bn <- sub(paste0("^", tag, "_"), "", bn, ignore.case = TRUE)
    bn <- sub(paste0("-", tag, "\\."), ".", bn, ignore.case = TRUE)
  }
  bn
}

.ml_ptc_strip_db_tag <- function(bn, cfg) {
  .ml_ptc_normalize_bn(bn, cfg)
}

.ml_ptc_extract_db_label <- function(basename, cfg) {
  bn <- as.character(basename)[1L]
  for (tag in .ml_ptc_db_tags(cfg)) {
    if (!nzchar(tag)) next
    if (grepl(paste0("^", tag, "_"), bn, ignore.case = TRUE)) return(tag)
    if (grepl(paste0("-", tag, "\\."), bn, ignore.case = TRUE)) return(tag)
  }
  "Combined"
}

.ml_ptc_db_prefix <- function(cfg, db_tag) {
  if (!.ml_ptc_should_merge_dual_db_tables(cfg) && !identical(db_tag, "Combined") &&
      nzchar(db_tag)) {
    paste0(db_tag, ". ")
  } else {
    ""
  }
}

# 单库已有 Table 1 / Table S4 编号时，只去掉库名标签，不再套一层 Table SX。
# 例：Table S3. Table 1-MIMIC IV. Baseline.xlsx → Table 1. Baseline.xlsx
#     Table 2-MIMIC IV-MIMIC IV. Logistic.xlsx → Table 2. Logistic.xlsx
.ml_ptc_clean_pub_basename <- function(bn) {
  bn <- as.character(bn)[1L]
  if (!nzchar(bn)) return(bn)
  m <- regexec(
    "^(Table|Figure) S?[0-9]+\\. ((Table|Figure) S?[0-9]+[-.].+)$",
    bn
  )
  hit <- regmatches(bn, m)[[1L]]
  if (length(hit) >= 3L) bn <- hit[[2L]]
  sub(
    "^(Table S?[0-9]+|Figure S?[0-9]+)(-[^.]+)?\\.[[:space:]]*",
    "\\1. ",
    bn
  )
}

.ml_ptc_supp_table_no <- function(n) {
  n <- as.integer(n)[1L]
  if (!is.finite(n) || n < 1L) return("S1")
  paste0("S", sprintf("%02d", n))
}

.ml_ptc_rename_keep_original_numbers <- function(tables_dir) {
  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  n <- 0L
  for (f in files) {
    new_bn <- .ml_ptc_clean_pub_basename(basename(f))
    new_bn <- sub("^Table S([1-9])\\.", "Table S0\\1.", new_bn)
    if (identical(new_bn, basename(f))) next
    dest <- file.path(tables_dir, new_bn)
    if (file.exists(dest) && !identical(normalizePath(f, winslash = "/"), normalizePath(dest, winslash = "/", mustWork = FALSE))) {
      unlink(dest)
    }
    if (isTRUE(file.rename(f, dest))) n <- n + 1L
  }
  invisible(n)
}

.ml_ptc_classify_table <- function(basename, cfg = NULL) {
  bn <- .ml_ptc_normalize_bn(basename, cfg)
  core <- bn
  core_l <- tolower(core)


  if (grepl("Cox quartile|\\(Cox quartile\\)", core, ignore.case = TRUE)) {
    return("t2_cox_quartile")
  }
  if (grepl("Cox tertile|\\(Cox tertile\\)", core, ignore.case = TRUE)) {
    return("t3_cox_tertile")
  }
  if (grepl("Cox binary|\\(Cox binary\\)|Multivariable Cox", core, ignore.case = TRUE)) {
    return("t4_cox_binary")
  }
  if (grepl("Cox regression", core, fixed = TRUE) &&
      grepl("quartile|tertile|binary", core_l, ignore.case = TRUE)) {
    if (grepl("quartile", core_l, ignore.case = TRUE)) return("t2_cox_quartile")
    if (grepl("tertile", core_l, ignore.case = TRUE)) return("t3_cox_tertile")
    return("t4_cox_binary")
  }
  if (grepl("ML performance wide training", core, fixed = TRUE)) return("t5_ml_train")
  if (grepl("ML performance wide validation", core, fixed = TRUE)) return("t6_ml_val")
  if (grepl("Hyperparameters", core, fixed = TRUE)) return("s6_hyper")
  if (grepl("before and after.*imputation|Comparison of characteristics before and after",
            core_l, ignore.case = TRUE)) return("s1_imputation")
  if (grepl("Univariate Regression", core, fixed = TRUE)) return("s2_univariate")
  if (grepl("Multicollinearity", core, fixed = TRUE) &&
      grepl("univariate p", core_l, ignore.case = TRUE)) return("s3_vif_screen")
  if (grepl("Multivariable Regression", core, fixed = TRUE)) return("s4_multivariate")
  if (grepl("Multicollinearity", core, fixed = TRUE) &&
      grepl("multivariate p", core_l, ignore.case = TRUE)) return("s5_vif_final")
  if (grepl("Weighted logistic regression", core, fixed = TRUE) &&
      grepl("dual-DB unified|\\[dual-DB unified\\]", core, ignore.case = TRUE)) {
    return("t3_logistic")
  }
  if (grepl("Weighted logistic regression", core, fixed = TRUE) &&
      !grepl("RCS groups", core, fixed = TRUE) &&
      grepl("quartile|tertile|binary", core_l, ignore.case = TRUE)) {
    return("t3_logistic")
  }
  if (grepl("Weighted Baseline Characteristics", core, fixed = TRUE)) {
    if (grepl("Q1|Q2|Q3|Q4|T1|T2|T3|quartile|tertile|median|index group|exposure group",
              core_l, ignore.case = TRUE)) {
      return("t2_quantile_baseline")
    }
    if (grepl("Categorized by|Psoriasis|Disease|Status", core, ignore.case = TRUE)) {
      return("t1_baseline")
    }
    return("t2_quantile_baseline")
  }
  if (grepl("^Table 1\\.", core) && grepl("Baseline", core, fixed = TRUE)) {
    return("t1_baseline")
  }
  if (grepl("Logistic regression analysis", core, fixed = TRUE) &&
      !grepl("Weighted", core, fixed = TRUE)) {
    if (grepl("screen|RCS", core_l, ignore.case = TRUE)) return("drop")
    if (grepl("quartile", core_l, ignore.case = TRUE)) return("t3_logistic")
    return("s8_unweighted_logistic")
  }
  if (grepl("Normality test", core, ignore.case = TRUE)) return("drop")
  if (grepl("^Table_FeatureSelection_|Table_ML_ModelPerformance|train_val_split|_reticulate_export",
            bn, ignore.case = TRUE)) return("drop")
  if (grepl("ROC", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Log-Loss|DeLong|NRI|IDI", core, ignore.case = TRUE)) return("s_extra")
  if (grepl("logistic regression", core_l, ignore.case = TRUE) &&
      grepl("screen|RCS", core_l, ignore.case = TRUE)) return("drop")
  "s_extra"
}

.ml_ptc_target_basename <- function(role, src_bn, cfg, s_extra_idx = NULL, db_tag = NULL) {
  if (is.null(db_tag) || !nzchar(db_tag)) {
    db_tag <- .ml_ptc_extract_db_label(src_bn, cfg)
  }
  dbp <- .ml_ptc_db_prefix(cfg, db_tag)
  cap <- .ml_ptc_clean_pub_basename(.ml_ptc_normalize_bn(src_bn, cfg))
  cap <- sub("^Table S?[0-9]+\\.[[:space:]]*", "", cap)
  cap <- sub("\\.xlsx$", "", cap, ignore.case = TRUE)
  switch(role,
    t1_baseline = paste0("Table 1. ", dbp, cap, ".xlsx"),
    t2_cox_quartile = paste0("Table 2. ", dbp, cap, ".xlsx"),
    t3_cox_tertile = paste0("Table 3. ", dbp, cap, ".xlsx"),
    t4_cox_binary = paste0("Table 4. ", dbp, cap, ".xlsx"),
    t2_quantile_baseline = paste0("Table 2. ", dbp, cap, ".xlsx"),
    t3_logistic = paste0("Table 3. ", dbp, cap, ".xlsx"),
    t5_ml_train = paste0("Table 5. ", dbp, "ML performance wide training.xlsx"),
    t6_ml_val = paste0("Table 6. ", dbp, "ML performance wide validation.xlsx"),
    t4_ml_train = paste0("Table 4. ", dbp, "ML performance wide training.xlsx"),
    t5_ml_val = paste0("Table 5. ", dbp, "ML performance wide validation.xlsx"),
    s1_imputation = paste0("Table ", .ml_ptc_supp_table_no(1L), ". ", dbp, cap, ".xlsx"),
    s2_univariate = paste0("Table ", .ml_ptc_supp_table_no(2L), ". ", dbp, cap, ".xlsx"),
    s3_vif_screen = paste0("Table ", .ml_ptc_supp_table_no(3L), ". ", dbp, cap, ".xlsx"),
    s4_multivariate = paste0("Table ", .ml_ptc_supp_table_no(4L), ". ", dbp, cap, ".xlsx"),
    s5_vif_final = paste0("Table ", .ml_ptc_supp_table_no(5L), ". ", dbp, cap, ".xlsx"),
    s6_hyper = paste0("Table ", .ml_ptc_supp_table_no(6L), ". ", dbp, "ML hyperparameters.xlsx"),
    s7_unweighted_baseline = paste0("Table ", .ml_ptc_supp_table_no(7L), ". ", dbp, cap, ".xlsx"),
    s8_unweighted_logistic = paste0("Table ", .ml_ptc_supp_table_no(8L), ". ", dbp, cap, ".xlsx"),
    s_extra = paste0("Table ", .ml_ptc_supp_table_no(s_extra_idx), ". ", dbp, cap, ".xlsx"),
    src_bn
  )
}

.ml_ptc_should_merge_dual_db_tables <- function(cfg = list()) {
  dual <- cfg$dual_db %||% list()
  batch <- cfg$ml_batch %||% cfg$incidence_batch %||% list()
  if ("merge_dual_db_tables" %in% names(dual)) {
    return(isTRUE(dual$merge_dual_db_tables))
  }
  if ("merge_dual_db_tables" %in% names(batch)) {
    return(isTRUE(batch$merge_dual_db_tables))
  }
  TRUE
}

.ml_ptc_merge_role <- function(role, cfg = list()) {
  if (!.ml_ptc_should_merge_dual_db_tables(cfg)) return(FALSE)
  role %in% c("t4_ml_train", "t5_ml_train", "t5_ml_val", "t6_ml_val", "s6_hyper")
}

.ml_ptc_read_xlsx_df <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("ml_dual_pub_table_curate: 需要 openxlsx 包。", call. = FALSE)
  }
  as.data.frame(openxlsx::read.xlsx(path), stringsAsFactors = FALSE, check.names = FALSE)
}

.ml_ptc_merge_xlsx_files <- function(files, db_labels, out_path, title = NULL) {
  parts <- list()
  for (i in seq_along(files)) {
    df <- .ml_ptc_read_xlsx_df(files[[i]])
    if (nrow(df)) {
      df$Database <- db_labels[[i]]
      parts[[length(parts) + 1L]] <- df
    }
  }
  if (!length(parts)) return(invisible(FALSE))
  if (requireNamespace("dplyr", quietly = TRUE)) {
    merged <- dplyr::bind_rows(parts)
  } else {
    merged <- do.call(rbind, parts)
  }
  cols <- c("Database", setdiff(names(merged), "Database"))
  merged <- merged[, cols, drop = FALSE]
  if (!exists("export_sci_table", mode = "function")) {
    openxlsx::write.xlsx(merged, out_path, overwrite = TRUE)
  } else {
    export_sci_table(merged, out_path, title = title %||% sub("\\.xlsx$", "", basename(out_path)))
  }
  invisible(TRUE)
}

incidence_batch_curate_ml_pub_tables <- function(tables_dir, cfg = list()) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  # 单库：保留流水线 Table 1–6 / S1–S12，只去掉 MIMIC IV 库名，避免 Table S3. Table 1-…
  if (!isTRUE(.ml_ptc_should_merge_dual_db_tables(cfg))) {
    n <- .ml_ptc_rename_keep_original_numbers(tables_dir)
    cli::cli_alert_success(
      "ML 汇总表已去重编号（单库保留原 Table/S 号）: {.file {basename(tables_dir)}}（{n} 张重命名）"
    )
    return(invisible(n))
  }
  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))

  roles <- vapply(basename(files), .ml_ptc_classify_table, character(1L), cfg = cfg)
  drop_idx <- roles == "drop"
  if (any(drop_idx)) {
    unlink(files[drop_idx])
    files <- files[!drop_idx]
    roles <- roles[!drop_idx]
  }
  if (!length(files)) return(invisible(sum(drop_idx)))

  keyed <- split(files, roles)
  renames <- list()
  merged_out <- list()
  s_extra_start <- 9L
  s_extra_i <- 0L

  role_order <- c(
    "t1_baseline", "t2_cox_quartile", "t3_cox_tertile", "t4_cox_binary",
    "t2_quantile_baseline", "t3_logistic",
    "t5_ml_train", "t6_ml_val", "t4_ml_train", "t5_ml_val",
    "s1_imputation", "s2_univariate", "s3_vif_screen", "s4_multivariate",
    "s5_vif_final", "s6_hyper", "s7_unweighted_baseline", "s8_unweighted_logistic"
  )

  for (role in role_order) {
    grp <- keyed[[role]]
    if (is.null(grp) || !length(grp)) next
    src_bn <- basename(grp[[1L]])
    if (.ml_ptc_merge_role(role, cfg) && length(grp) >= 2L) {
      tgt_bn <- .ml_ptc_target_basename(role, src_bn, cfg)
      tgt <- file.path(tables_dir, tgt_bn)
      db_labels <- vapply(basename(grp), .ml_ptc_extract_db_label, character(1L), cfg = cfg)
      ok <- .ml_ptc_merge_xlsx_files(grp, db_labels, tgt, title = sub("\\.xlsx$", "", tgt_bn))
      if (isTRUE(ok)) {
        merged_out[[tgt]] <- grp
        unlink(grp)
      } else {
        renames[[grp[[1L]]]] <- tgt
      }
    } else {
      used <- character(0)
      for (f in grp) {
        db_tag <- .ml_ptc_extract_db_label(basename(f), cfg)
        tgt <- file.path(tables_dir, .ml_ptc_target_basename(role, basename(f), cfg, db_tag = db_tag))
        if (tgt %in% used) next
        renames[[f]] <- tgt
        used <- c(used, tgt)
      }
      drop_extra <- setdiff(grp, names(renames))
      if (length(drop_extra)) unlink(drop_extra)
    }
  }

  extra_files <- keyed[["s_extra"]]
  if (!is.null(extra_files) && length(extra_files)) {
    extra_files <- extra_files[order(basename(extra_files))]
    for (f in extra_files) {
      s_extra_i <- s_extra_i + 1L
      tgt <- file.path(
        tables_dir,
        .ml_ptc_target_basename("s_extra", basename(f), cfg, s_extra_idx = s_extra_start + s_extra_i - 1L)
      )
      renames[[f]] <- tgt
    }
  }

  if (!length(renames)) {
    cli::cli_alert_info("ML 汇总表已整理（无需重命名）: {.file {basename(tables_dir)}}")
    return(invisible(length(merged_out)))
  }

  tmp_map <- list()
  i <- 0L
  for (old in names(renames)) {
    i <- i + 1L
    tmp <- file.path(tables_dir, sprintf(".ml_tbl_curate_%03d.xlsx", i))
    if (file.exists(tmp)) unlink(tmp)
    file.rename(old, tmp)
    tmp_map[[renames[[old]]]] <- tmp
  }
  for (new in names(tmp_map)) {
    if (file.exists(new)) unlink(new)
    file.rename(tmp_map[[new]], new)
  }

  n_merged <- length(merged_out)
  cli::cli_alert_success(
    paste0(
      "ML 汇总表已整理（T1 基线 → T5 验证集；S1 插补 → S8 非加权逻辑回归；合并双库 ",
      n_merged, " 张）: ", basename(tables_dir)
    )
  )
  invisible(n_merged + length(renames))
}

incidence_batch_collect_index_shiny_outputs <- function(index_root, cfg, db_seq = character(0)) {
  if (is.null(index_root) || !nzchar(index_root) || !dir.exists(index_root)) {
    return(invisible(0L))
  }
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (!length(db_seq)) return(invisible(0L))

  shiny_root <- file.path(index_root, "Shiny")
  dir.create(shiny_root, recursive = TRUE, showWarnings = FALSE)
  n <- 0L

  for (db in db_seq) {
    db_dir <- if (exists("dual_db_slot_path_name", mode = "function")) {
      dual_db_slot_path_name(cfg, db)
    } else {
      db
    }
    db_out <- file.path(index_root, db_dir)
    if (!dir.exists(db_out)) next
    all_dirs <- list.dirs(db_out, recursive = TRUE, full.names = TRUE)
    hits <- all_dirs[grepl("ShinyApp$", basename(all_dirs), ignore.case = TRUE)]
    if (!length(hits)) next
    src <- hits[[1L]]
    dest <- file.path(shiny_root, db_dir)
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    if (dir.exists(file.path(dest, "ShinyApp"))) {
      unlink(file.path(dest, "ShinyApp"), recursive = TRUE, force = TRUE)
    }
    ok <- file.copy(src, dest, recursive = TRUE, overwrite = TRUE)
    if (isTRUE(ok)) {
      n <- n + 1L
      cli::cli_alert_info("Shiny 已汇总: {.file {file.path(dest, 'ShinyApp')}}")
    } else {
      cli::cli_alert_warning("Shiny 汇总失败 [{db_dir}]: {.file {src}}")
    }
  }
  if (n > 0L) {
    cli::cli_alert_success("Shiny 产出已写入 {.file {shiny_root}}（{n} 个库）")
  }
  invisible(n)
}
