###############################################################################
#  trajectory_paper_tables.R — 轨迹预后论文 Table 2 / Table 3 / 后验分类表
###############################################################################

trajectory_unwrap_jointlcmm <- function(m) {
  if (inherits(m, "Jointlcmm")) return(m)
  if (is.list(m) && inherits(m$best, "Jointlcmm")) return(m$best)
  m
}

trajectory_jlcm_entropy <- function(m) {
  m <- trajectory_unwrap_jointlcmm(m)
  if (is.null(m$pprob) || is.null(m$ng) || as.integer(m$ng) <= 1L) return(1)
  pprob <- as.data.frame(m$pprob)
  prob_cols <- grep("^prob", names(pprob), value = TRUE)
  if (!length(prob_cols)) return(NA_real_)
  P <- as.matrix(pprob[, prob_cols, drop = FALSE])
  P <- pmax(P, .Machine$double.eps)
  round(1 - (-sum(P * log(P), na.rm = TRUE) / (nrow(P) * log(m$ng))), 6)
}

trajectory_jlcm_sabic <- function(m, n_subj) {
  m <- trajectory_unwrap_jointlcmm(m)
  loglik <- m$loglik %||% NA_real_
  aic    <- m$AIC    %||% NA_real_
  if (!is.finite(loglik) || !is.finite(aic) || !is.finite(n_subj)) return(NA_real_)
  n_params <- (aic + 2 * loglik) / 2
  round(-2 * loglik + n_params * log((n_subj + 2) / 24), 1)
}

trajectory_jlcm_class_props_pct <- function(m, max_classes = 6L, class_map = NULL) {
  m <- trajectory_unwrap_jointlcmm(m)
  ng <- as.integer(m$ng %||% NA_integer_)
  out <- rep("", max_classes)
  if (!is.finite(ng) || ng < 1L) return(out)
  if (ng == 1L) {
    out[1] <- "100.00"
    return(out)
  }
  pprob <- tryCatch(as.data.frame(m$pprob), error = function(e) NULL)
  if (is.null(pprob) || !"class" %in% names(pprob)) return(out)
  cl <- as.integer(pprob$class)
  if (!is.null(class_map) && length(class_map) && ng == length(class_map)) {
    cl <- trajectory_apply_class_swap(cl, class_map)
  }
  tab <- table(factor(cl, levels = seq_len(ng)))
  props <- round(100 * as.numeric(prop.table(tab)), 2)
  for (k in seq_len(min(ng, max_classes))) out[k] <- sprintf("%.2f", props[k])
  out
}

#' 从 JLCM models_list 构建 Table 2 正文（对齐轨迹预后.pdf / Fig2A）
#' @param class_map named int map old→new；仅对 ng==length(class_map) 的行重排占比（与 Fig2 对齐）
trajectory_build_table2_from_models <- function(models_list, max_classes = 6L,
                                               class_map = NULL) {
  if (is.null(models_list) || !length(models_list)) return(NULL)
  nms <- names(models_list)
  ngs <- suppressWarnings(as.integer(gsub("^m", "", nms)))
  ok  <- is.finite(ngs)
  if (!any(ok)) return(NULL)
  nms <- nms[ok]
  ngs <- ngs[ok]
  ord <- order(ngs)
  map_ng <- if (!is.null(class_map) && length(class_map)) length(class_map) else NA_integer_
  rows <- list()
  for (ii in ord) {
    ng <- ngs[ii]
    m  <- trajectory_unwrap_jointlcmm(models_list[[nms[ii]]])
    if (is.null(m) || !is.list(m)) next
    pprob  <- tryCatch(as.data.frame(m$pprob), error = function(e) NULL)
    n_subj <- if (!is.null(pprob) && nrow(pprob)) nrow(pprob) else NA_integer_
    use_map <- if (is.finite(map_ng) && identical(as.integer(ng), as.integer(map_ng)))
      class_map else NULL
    props  <- trajectory_jlcm_class_props_pct(m, max_classes, class_map = use_map)
    ll  <- suppressWarnings(as.numeric(m$loglik)[1L])
    aic <- suppressWarnings(as.numeric(m$AIC)[1L])
    bic <- suppressWarnings(as.numeric(m$BIC)[1L])
    sab <- if (is.finite(n_subj)) trajectory_jlcm_sabic(m, n_subj) else NA_real_
    ent <- trajectory_jlcm_entropy(m)
    row <- data.frame(
      `No. of classes` = ng,
      `Log likelihood` = if (is.finite(ll)) sprintf("%.1f", ll) else "",
      `AIC`   = if (is.finite(aic)) sprintf("%.1f", aic) else "",
      `BIC`   = if (is.finite(bic)) sprintf("%.1f", bic) else "",
      `SABIC` = if (is.finite(sab)) sprintf("%.1f", sab) else "",
      `Entropy` = if (is.finite(ent)) sprintf("%.6f", ent) else "",
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    for (k in seq_len(max_classes)) row[[paste0("Class ", k)]] <- props[k]
    rows[[length(rows) + 1L]] <- row
  }
  if (!length(rows)) return(NULL)
  dplyr::bind_rows(rows)
}

trajectory_table2_header_rows <- function(max_classes = 6L) {
  cls <- paste0("Class ", seq_len(max_classes))
  h1  <- c("No. of classes", "Log likelihood", "AIC", "BIC", "SABIC", "Entropy",
           "Proportion of people (%)", rep("", max_classes - 1L))
  h2  <- c(rep("", 6L), cls)
  list(header_row1 = h1, header_row2 = h2)
}

#' Table 2：SCI 三线表（与 Table 1 同 export_sci_table 管线）
trajectory_export_table2_sci <- function(ctx, models_list, file_out, title,
                                         max_classes = 6L, class_map = NULL) {
  body <- trajectory_build_table2_from_models(
    models_list, max_classes, class_map = class_map
  )
  if (is.null(body) || !nrow(body)) return(invisible(FALSE))
  hdr  <- trajectory_table2_header_rows(max_classes)
  export_sci_table(
    body, file_out, title = title, sheet = "Table2",
    header_row1 = hdr$header_row1, header_row2 = hdr$header_row2,
    blank_na_cells = TRUE
  )
  if (exists("render_queued_tables", mode = "function")) {
    render_queued_tables(ctx)
  }
  invisible(TRUE)
}

#' 后验分类表：按最终分配类别求各类平均后验概率（对齐 FigS3 / Table S4）
trajectory_build_posterior_classification_df <- function(model, class_map = NULL) {
  m <- trajectory_unwrap_jointlcmm(model)
  if (is.null(m$pprob)) return(NULL)
  pprob <- as.data.frame(m$pprob)
  if (!"class" %in% names(pprob)) return(NULL)
  prob_cols <- grep("^prob", names(pprob), value = TRUE)
  if (!length(prob_cols)) return(NULL)
  old_cl <- as.integer(pprob$class)
  new_cl <- if (!is.null(class_map) && length(class_map))
    trajectory_apply_class_swap(old_cl, class_map) else old_cl
  pprob$Class <- paste0("Class", new_cl)
  agg <- stats::aggregate(
    pprob[, prob_cols, drop = FALSE],
    by = list(Class = pprob$Class),
    FUN = mean, na.rm = TRUE
  )
  names(agg) <- c("Class", paste0("prob", seq_along(prob_cols)))
  agg <- agg[order(as.integer(gsub("\\D+", "", agg$Class))), , drop = FALSE]
  if (!is.null(class_map) && length(class_map) && length(prob_cols) == length(class_map)) {
    P <- as.matrix(agg[, paste0("prob", seq_along(prob_cols)), drop = FALSE])
    Pnew <- P
    old_idx <- as.integer(names(class_map))
    new_idx <- as.integer(unname(class_map))
    for (k in seq_along(old_idx)) {
      if (old_idx[k] <= ncol(P) && new_idx[k] <= ncol(Pnew))
        Pnew[, new_idx[k]] <- P[, old_idx[k]]
    }
    for (j in seq_len(ncol(Pnew))) agg[[paste0("prob", j)]] <- Pnew[, j]
  }
  for (j in seq_along(prob_cols)) {
    cn <- paste0("prob", j)
    agg[[cn]] <- sprintf("%.5f", as.numeric(agg[[cn]]))
  }
  agg
}

trajectory_export_posterior_classification_sci <- function(ctx, model, file_out, title, class_map = NULL) {
  body <- trajectory_build_posterior_classification_df(model, class_map = class_map)
  if (is.null(body) || !nrow(body)) return(invisible(FALSE))
  prob_n <- sum(grepl("^prob", names(body)))
  h1 <- c("Class", "DATA", rep("", max(0L, prob_n - 1L)))
  h2 <- c("", paste0("prob", seq_len(prob_n)))
  export_sci_table(
    body, file_out, title = title, sheet = "TableS4",
    header_row1 = h1, header_row2 = h2,
    blank_na_cells = TRUE
  )
  if (exists("render_queued_tables", mode = "function")) {
    render_queued_tables(ctx)
  }
  invisible(TRUE)
}

#' Table 3：SCI 三线表（双行表头，与 Table 1 统一）
trajectory_export_table3_sci <- function(ctx, tab_all, cut_global, file_out, title,
                                         end_day = 28L) {
  if (is.null(tab_all) || !nrow(tab_all)) return(invisible(FALSE))
  left_col  <- paste0("(0,", cut_global, "]")
  right_col <- paste0("(", cut_global, ",", end_day, "]")
  body <- tab_all
  if ("dataset" %in% names(body)) {
    body$Database <- body$dataset
  } else if (!"Database" %in% names(body)) {
    body$Database <- ""
  }
  if (!"class_label" %in% names(body) && "class" %in% names(body)) {
    ref <- body$ref_class[1] %||% "2"
    body$`Trajectory class` <- paste0("Class ", body$class, " (ref = Class ", ref, ")")
  } else {
    body$`Trajectory class` <- body$class_label
  }
  disp <- data.frame(
    Database = body$Database,
    `Trajectory class` = body$`Trajectory class`,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  disp[[left_col]]  <- body[[left_col]]  %||% body[["HR_before"]] %||% ""
  disp[[right_col]] <- body[[right_col]] %||% body[["HR_after"]]  %||% ""
  # 历史脏值兜底：已落盘的 10^9 级 HR / Inf CI 一律改写为 NE
  for (cn in c(left_col, right_col)) {
    if (!cn %in% names(disp)) next
    v <- as.character(disp[[cn]])
    hr_num <- suppressWarnings(as.numeric(sub("\\s*\\(.*$", "", v)))
    # \u2021 = Firth \u6807\u6ce8\uff08\u5927 HR/\u5bbd CI \u5c5e\u51c6\u5206\u79bb\u672c\u8d28\uff0c\u52ff\u518d\u6539\u5199\u4e3a NE\uff09
    is_firth <- grepl("\u2021", v, fixed = TRUE)
    bad <- (grepl("Inf", v, ignore.case = TRUE) |
      grepl("^NE", v) |
      (!is.na(hr_num) & hr_num >= 1e4)) & !is_firth
    v[bad] <- "NE\u2020"
    disp[[cn]] <- v
  }
  t3_cells <- as.character(unlist(disp[c(left_col, right_col)]))
  has_ne <- any(grepl("^NE", t3_cells, perl = TRUE), na.rm = TRUE)
  has_firth <- any(grepl("\u2021", t3_cells, fixed = TRUE), na.rm = TRUE)
  footnotes <- list()
  if (has_ne) {
    footnotes <- c(footnotes, list(
      "\u2020NE = not estimable (quasi-complete separation; e.g. zero events in a class within the interval)."
    ))
  }
  if (has_firth) {
    footnotes <- c(footnotes, list(
      paste0(
        "\u2021Firth penalized-likelihood Cox regression with profile penalized-likelihood ",
        "95% CI, used where the interval shows quasi-complete separation (e.g. zero events in ",
        "the reference class); the CI is wide by nature."
      )
    ))
  }
  if (!length(footnotes)) footnotes <- NULL
  h1 <- c("Database", "Trajectory class", "HR (95% CI)", "")
  h2 <- c("", "", left_col, right_col)
  export_sci_table(
    disp, file_out, title = title, sheet = "Table3",
    header_row1 = h1, header_row2 = h2,
    blank_na_cells = TRUE,
    table_footnotes = footnotes
  )
  if (exists("render_queued_tables", mode = "function")) {
    render_queued_tables(ctx)
  }
  invisible(TRUE)
}

#' 兼容旧调用：openxlsx 直写（保留给合并脚本内部备用）
trajectory_prepare_table2_df <- function(ic_table, max_classes = 6L) {
  if (is.null(ic_table) || !nrow(ic_table)) return(NULL)
  if (is.list(ic_table) && !is.data.frame(ic_table) && all(grepl("^m", names(ic_table)))) {
    return(trajectory_build_table2_from_models(ic_table, max_classes))
  }
  trajectory_build_table2_from_models(ic_table, max_classes)
}

trajectory_export_table2_xlsx <- function(ic_table, file_out, index_name = "NLR") {
  body <- if (is.list(ic_table) && all(grepl("^m", names(ic_table)))) {
    trajectory_build_table2_from_models(ic_table)
  } else {
    trajectory_prepare_table2_df(ic_table)
  }
  if (is.null(body) || !nrow(body)) return(invisible(FALSE))
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(invisible(FALSE))
  hdr <- trajectory_table2_header_rows()
  nc  <- ncol(body)
  wb  <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Table2", gridLines = FALSE)
  title_txt <- paste0("Table 2. Metrics for determining the optimal number of classes (", index_name, ")")
  openxlsx::writeData(wb, "Table2", title_txt, startRow = 1, startCol = 1)
  openxlsx::mergeCells(wb, "Table2", rows = 1, cols = 1:nc)
  openxlsx::writeData(wb, "Table2", t(hdr$header_row1), startRow = 2, startCol = 1, colNames = FALSE)
  openxlsx::writeData(wb, "Table2", t(hdr$header_row2), startRow = 3, startCol = 1, colNames = FALSE)
  openxlsx::writeData(wb, "Table2", body, startRow = 4, startCol = 1, colNames = FALSE)
  openxlsx::saveWorkbook(wb, file_out, overwrite = TRUE)
  invisible(TRUE)
}

trajectory_export_table3_xlsx <- function(tab_all, cut_global, file_out, end_day = 28L,
                                          index_name = "Index", ctx = NULL) {
  title <- paste0(
    "Table 3. Time-dependent HR for trajectory classes of ", index_name,
    " in the eICU-CRD and MIMIC-IV database"
  )
  if (!is.null(ctx) && exists("trajectory_export_table3_sci", mode = "function")) {
    return(trajectory_export_table3_sci(ctx, tab_all, cut_global, file_out, title, end_day))
  }
  invisible(FALSE)
}

trajectory_db_tables_dir <- function(base_root, index_name, db) {
  p_flat <- file.path(base_root, db, "Tables")
  if (dir.exists(p_flat)) return(p_flat)
  file.path(base_root, "by_index", index_name, db, "Tables")
}

trajectory_merged_tables_dir <- function(base_root, index_name) {
  p_flat <- file.path(base_root, "Tables_merged")
  if (dir.exists(dirname(p_flat)) || dir.exists(base_root)) {
    if (dir.exists(file.path(base_root, "eicu")) || dir.exists(file.path(base_root, "mimic"))) {
      return(p_flat)
    }
  }
  file.path(base_root, "by_index", index_name, "Tables_merged")
}

#' 合并双库 Table 3（MIMIC 扫描定 cut，两库共用）
trajectory_merge_table3_dual_db <- function(base_root, index_name = "NLR",
                                            cut_from_db = "mimic", end_day = 28L,
                                            ctx = NULL) {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("trajectory_merge_table3_dual_db: 需要 dplyr", call. = FALSE)
  }
  db_labels <- list(eicu = "eICU-CRD", mimic = "MIMIC-IV")
  scans <- list()
  tabs  <- list()
  for (db in c("eicu", "mimic")) {
    tab_dir <- trajectory_db_tables_dir(base_root, index_name, db)
    p <- file.path(tab_dir, "Table_Piecewise_Cox_By_Class.csv")
    if (!file.exists(p)) next
    tab <- utils::read.csv(p, stringsAsFactors = FALSE)
    tab$dataset <- db_labels[[db]] %||% toupper(db)
    tabs[[db]] <- tab
    sp <- file.path(tab_dir, paste0("Table_Piecewise_Cox_CutScan_", db, ".csv"))
    if (file.exists(sp)) scans[[db]] <- utils::read.csv(sp, stringsAsFactors = FALSE)
  }
  if (!length(tabs)) {
    cli::cli_alert_warning("trajectory_merge_table3_dual_db: 未找到分段 Cox 表")
    return(invisible(NULL))
  }
  cut_global <- NA_integer_
  if (!is.null(scans[[cut_from_db]])) {
    sr <- scans[[cut_from_db]]
    sr <- sr[!is.na(sr$loglik), , drop = FALSE]
    if (nrow(sr)) cut_global <- as.integer(sr$cut[which.max(sr$loglik)])
  }
  if (is.na(cut_global)) {
    for (db in names(tabs)) {
      if ("cut" %in% names(tabs[[db]])) {
        cut_global <- as.integer(tabs[[db]]$cut[1])
        break
      }
    }
  }
  if (is.na(cut_global)) cut_global <- 3L

  combined <- dplyr::bind_rows(lapply(tabs, function(x) {
    out <- x
    if (!"class_label" %in% names(out) && "class" %in% names(out)) {
      ref <- out$ref_class[1] %||% "2"
      out$class_label <- paste0("Class ", out$class, " (ref = Class ", ref, ")")
    }
    out
  }))
  rownames(combined) <- NULL

  out_dir <- trajectory_merged_tables_dir(base_root, index_name)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_csv  <- file.path(out_dir, paste0("Table3_", index_name, "_cut", cut_global, ".csv"))
  out_xlsx <- file.path(out_dir, paste0("Table 3-", index_name, " cut", cut_global, ".xlsx"))
  out_xlsx_alt <- file.path(out_dir, paste0("Table3_", index_name, "_cut", cut_global, ".xlsx"))
  utils::write.csv(combined, out_csv, row.names = FALSE)
  if (!is.null(ctx)) {
    trajectory_export_table3_sci(
      ctx, combined, cut_global, out_xlsx,
      paste0("Table 3. Time-dependent HR for trajectory classes of ", index_name),
      end_day = end_day
    )
    trajectory_export_table3_sci(
      ctx, combined, cut_global, out_xlsx_alt,
      paste0("Table 3. Time-dependent HR for trajectory classes of ", index_name),
      end_day = end_day
    )
  } else {
    trajectory_export_table3_xlsx(combined, cut_global, out_xlsx, end_day = end_day, index_name = index_name)
    trajectory_export_table3_xlsx(combined, cut_global, out_xlsx_alt, end_day = end_day, index_name = index_name)
  }
  cli::cli_alert_success("双库 Table 3 已合并: {.file {basename(out_xlsx)}}（cut={cut_global}）")
  invisible(list(cut = cut_global, csv = out_csv, xlsx = out_xlsx, xlsx_alt = out_xlsx_alt, table = combined))
}

#' 从 JLCM 检查点仅重导出 Table 2 / Table 3 / 后验表（不重跑单因素/多因素）
trajectory_reexport_paper_tables <- function(ctx, cfg_db, Index,
                                           models_list = NULL,
                                           selected_ng = NULL) {
  bl_cfg <- cfg_db$trajectory_jlcm %||% list()
  db_lab <- cfg_db$project$database %||% "Study"
  old_db_opt <- getOption("pipeline.database_name")
  on.exit(options(pipeline.database_name = old_db_opt), add = TRUE)
  options(pipeline.database_name = db_lab)
  pack   <- ctx$results$trajectory_jlcm_models[[Index]] %||% list()
  if (is.null(models_list)) models_list <- pack$models
  if (is.null(models_list)) return(ctx)

  if (is.null(selected_ng)) {
    selected_ng <- ctx$results[[paste0("trajectory_optimal_ng_", Index)]] %||%
      ctx$results$trajectory_optimal_ng %||% 2L
  }
  selected_ng <- suppressWarnings(as.integer(selected_ng)[1L])
  if (!is.finite(selected_ng)) selected_ng <- 2L

  t2_title <- paste0("Table 2. Metrics for determining the optimal number of classes (", Index, ")")
  fp_t2 <- file.path(
    ctx$output_dir_tables,
    paste0("Table 2-", db_lab, ". Metrics for determining the optimal number of classes.xlsx")
  )
  trajectory_export_table2_sci(ctx, models_list, fp_t2, t2_title)
  trajectory_export_table2_sci(
    ctx, models_list,
    file.path(ctx$output_dir_tables, "Table_Trajectory_IC_JLCM.xlsx"),
    t2_title
  )

  m_sel <- models_list[[paste0("m", selected_ng)]]
  s8_title <- paste0("Table S8. Posterior classification table (", Index, ", ", db_lab, ")")
  fp_s8 <- file.path(
    ctx$output_dir_tables,
    paste0("Table S8-", db_lab, ". Posterior classification table.xlsx")
  )
  trajectory_export_posterior_classification_sci(ctx, m_sel, fp_s8, s8_title)

  pcox <- ctx$results$trajectory_piecewise_cox$combined_table %||% NULL
  if (is.null(pcox)) {
    p_csv <- file.path(ctx$output_dir_tables, "Table_Piecewise_Cox_By_Class.csv")
    if (file.exists(p_csv)) pcox <- utils::read.csv(p_csv, stringsAsFactors = FALSE)
  }
  if (!is.null(pcox) && nrow(pcox)) {
    cut_best <- pcox$cut[1] %||% NA
    if (!is.na(cut_best)) {
      t3_title <- paste0("Table 3. Time-dependent HR for trajectory classes of ", Index)
      fp_t3 <- file.path(
        ctx$output_dir_tables,
        paste0("Table 3-", db_lab, ". Time-dependent HR for trajectory classes.xlsx")
      )
      trajectory_export_table3_sci(ctx, pcox, as.integer(cut_best), fp_t3, t3_title,
                                   end_day = bl_cfg$max_followup %||% 28L)
    }
  }
  ctx
}

#' 从 step14 JLCM RData 补写 Table 2 / Table S8（不重拟合、不编造）
#' @param force 为 TRUE 时即使已有表也按 class_map 重导（用于占比与 Fig2 对齐）
#' @param class_map named int old→new；写入最优 ng 行的 Class 占比
trajectory_rebuild_jlcm_pub_tables <- function(unit_root, index_name, db_lab = "MIMIC",
                                              ng = NULL, ctx = NULL,
                                              force = FALSE, class_map = NULL) {
  unit_root <- as.character(unit_root)[1L]
  index_name <- as.character(index_name)[1L]
  db_lab <- as.character(db_lab)[1L]
  tab_dir <- file.path(unit_root, "Tables")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

  dest_t2 <- file.path(
    tab_dir, paste0("Table 2-", db_lab, ". Metrics for determining the optimal number of classes.xlsx")
  )
  dest_s8 <- file.path(
    tab_dir, paste0("Table S8-", db_lab, ". Posterior classification table.xlsx")
  )
  need_t2 <- isTRUE(force) || !file.exists(dest_t2)
  need_s8 <- isTRUE(force) || !file.exists(dest_s8)
  if (!need_t2 && !need_s8) return(invisible(list(ok = TRUE, skipped = TRUE)))

  if (is.null(class_map) || !length(class_map)) {
    class_map <- trajectory_read_class_align_map(
      unit_root, index_name = index_name, db_lab = db_lab
    )
  }

  rds <- list.files(
    file.path(unit_root, "step14_trajectory_jlcm", "Data"),
    pattern = paste0("jlcm_", index_name, "_models\\.RData$"),
    full.names = TRUE
  )
  if (!length(rds)) {
    rds <- list.files(
      unit_root, pattern = paste0("jlcm_", index_name, "_models\\.RData$"),
      recursive = TRUE, full.names = TRUE
    )
  }
  if (!length(rds)) {
    cli::cli_alert_warning("未找到 JLCM RData，无法补写 Table 2 / S8: {index_name}")
    return(invisible(list(ok = FALSE, reason = "no_rdata")))
  }

  e <- new.env(parent = emptyenv())
  load(rds[[1L]], envir = e)
  models <- NULL
  if (!is.null(e$models_list_with_cov) && is.list(e$models_list_with_cov)) {
    models <- e$models_list_with_cov
  } else if (!is.null(e$pack) && is.list(e$pack) && !is.null(e$pack$models)) {
    models <- e$pack$models
  } else if (!is.null(e$models) && is.list(e$models)) {
    models <- e$models
  }
  if (is.null(models) || !length(models)) {
    cli::cli_alert_warning("JLCM RData 无 models 列表: {basename(rds[[1L]])}")
    return(invisible(list(ok = FALSE, reason = "no_models")))
  }

  if (is.null(ng) || !is.finite(suppressWarnings(as.integer(ng)[1L]))) {
    ng_files <- c(
      file.path(tab_dir, "Summary", paste0("optimal_ng_", index_name, ".txt")),
      file.path(unit_root, "step14_trajectory_jlcm", "Tables", "Summary",
                paste0("optimal_ng_", index_name, ".txt"))
    )
    ng <- NA_integer_
    for (nf in ng_files) {
      if (!file.exists(nf)) next
      ng <- suppressWarnings(as.integer(readLines(nf, warn = FALSE)[1L]))
      if (is.finite(ng)) break
    }
    if (!is.finite(ng)) ng <- 2L
  }
  ng <- as.integer(ng)[1L]

  if (is.null(ctx)) {
    ctx <- list(
      config = list(project = list(database = db_lab)),
      output_dir = unit_root,
      output_dir_tables = tab_dir,
      root_output_dir = unit_root
    )
  }
  if (exists(".table_queue_env") && is.environment(.table_queue_env)) {
    .table_queue_env$items <- list()
  }

  wrote <- character(0)
  if (need_t2 && exists("trajectory_export_table2_sci", mode = "function")) {
    t2_title <- paste0(
      "Table 2. Metrics for determining the optimal number of classes (", index_name, ")"
    )
    ok <- isTRUE(tryCatch({
      trajectory_export_table2_sci(
        ctx, models, dest_t2, t2_title, class_map = class_map
      )
      TRUE
    }, error = function(e) {
      cli::cli_alert_warning("Table 2 SCI 导出失败，改用直写 xlsx: {e$message}")
      FALSE
    }))
    if (!ok && exists("trajectory_export_table2_xlsx", mode = "function")) {
      ok <- isTRUE(tryCatch(
        trajectory_export_table2_xlsx(models, dest_t2, index_name = index_name),
        error = function(e) FALSE
      ))
    }
    if (ok && file.exists(dest_t2)) wrote <- c(wrote, dest_t2)
  }

  if (need_s8 && exists("trajectory_export_posterior_classification_sci", mode = "function")) {
    m_sel <- models[[paste0("m", ng)]]
    if (is.null(m_sel) && length(models)) m_sel <- models[[length(models)]]
    if (!is.null(m_sel)) {
      s8_title <- paste0("Table S8. Posterior classification table (", index_name, ", ", db_lab, ")")
      ok <- isTRUE(tryCatch({
        trajectory_export_posterior_classification_sci(
          ctx, m_sel, dest_s8, s8_title, class_map = class_map
        )
        TRUE
      }, error = function(e) {
        cli::cli_alert_warning("Table S8 SCI 导出失败: {e$message}")
        FALSE
      }))
      if (ok && file.exists(dest_s8)) wrote <- c(wrote, dest_s8)
    }
  }

  if (length(wrote)) {
    cli::cli_alert_success(
      "已从 JLCM RData 补写: {paste(basename(wrote), collapse = '; ')}"
    )
  }
  invisible(list(ok = length(wrote) > 0L, wrote = wrote, ng = ng, rdata = rds[[1L]]))
}

#' 读 Tables/Summary/class_align_{Index}.csv → named int map（单库）
trajectory_read_class_align_map <- function(unit_or_index_root, index_name,
                                            db_lab = NULL, db_slug = NULL) {
  index_name <- as.character(index_name)[1L]
  cands <- c(
    file.path(unit_or_index_root, "Tables", "Summary",
              paste0("class_align_", index_name, ".csv")),
    file.path(unit_or_index_root, "Summary",
              paste0("class_align_", index_name, ".csv")),
    file.path(dirname(unit_or_index_root), "Tables", "Summary",
              paste0("class_align_", index_name, ".csv"))
  )
  fp <- cands[file.exists(cands)][1L]
  if (is.na(fp) || !nzchar(fp)) return(NULL)
  al <- tryCatch(
    utils::read.csv(fp, stringsAsFactors = FALSE),
    error = function(e) NULL
  )
  if (is.null(al) || !nrow(al)) return(NULL)
  need <- c("db", "old_class", "new_class")
  if (!all(need %in% names(al))) return(NULL)
  slug <- tolower(as.character(db_slug %||% db_lab %||% "")[1L])
  if (!nzchar(slug)) return(NULL)
  if (grepl("eicu", slug)) slug <- "eicu"
  else if (grepl("mimic", slug)) slug <- "mimic"
  sub <- al[tolower(as.character(al$db)) == slug, , drop = FALSE]
  if (!nrow(sub)) return(NULL)
  stats::setNames(as.integer(sub$new_class), as.character(sub$old_class))
}
