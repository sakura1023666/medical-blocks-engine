###############################################################################
#  cross_lagged_corr_table — 暴露/中介/结局两两回归（Crude / Model1 / Model2）
#  出版：Table S6（库内分区 + Variable / Estimate / 95% CI / P value）
#  register_block: "cross_lagged_corr_table"
###############################################################################

block_cross_lagged_corr_table <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$cross_lagged_corr_table %||% list()
  data <- ctx$data$longitudinal_mediation %||% ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    stop("cross_lagged_corr_table: 无数据", call. = FALSE)

  # 必须用 [[ ]] 精确取名，避免 exposure 部分匹配到 exposure_label
  x <- bl[["exposure"]] %||% cfg$incidence$index_var %||% "FI"
  m <- bl[["mediator"]] %||% "Depression_cont"
  y <- bl[["outcome"]] %||% cfg$data$outcome_column %||% "Disease_Group"
  event <- bl[["outcome_event_level"]] %||% cfg$project$analysis_group %||% "Hip_Fracture"
  x_lab <- bl[["exposure_label"]] %||% "Frailty Index"
  m_lab <- bl[["mediator_label"]] %||% "Depression"
  y_lab <- bl[["outcome_label"]] %||% gsub("_", " ", as.character(event), fixed = TRUE)
  m1 <- bl[["model1"]] %||% ctx$results$Model1Factors %||% c("Age")
  m2 <- bl[["model2"]] %||% ctx$results$Model2Factors %||% m1
  m1 <- intersect(as.character(m1), names(data))
  m2 <- intersect(as.character(m2), names(data))
  db <- as.character(cfg$project$database %||% "DB")[1L]

  need <- c(x, m, y)
  if (length(setdiff(need, names(data))))
    stop("cross_lagged_corr_table: 缺列 ", paste(setdiff(need, names(data)), collapse = ", "), call. = FALSE)

  if (is.numeric(data[[y]]) || is.integer(data[[y]])) {
    data$.y <- as.integer(data[[y]] == 1L)
  } else {
    data$.y <- as.integer(as.character(data[[y]]) == as.character(event))
  }

  .fit_row <- function(resp, pred, covs, family) {
    covs <- setdiff(covs, c(resp, pred))
    rhs <- paste(c(pred, covs), collapse = " + ")
    fml <- stats::as.formula(paste(resp, "~", rhs))
    if (identical(family, "binomial")) {
      fit <- stats::glm(fml, data = data, family = binomial())
      cf <- summary(fit)$coefficients
      if (!pred %in% rownames(cf))
        return(list(est = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, metric = "OR"))
      b <- cf[pred, 1]; se <- cf[pred, 2]; p <- cf[pred, 4]
      list(est = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = p, metric = "OR")
    } else {
      fit <- stats::lm(fml, data = data)
      cf <- summary(fit)$coefficients
      if (!pred %in% rownames(cf))
        return(list(est = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, metric = "beta"))
      b <- cf[pred, 1]; se <- cf[pred, 2]; p <- cf[pred, 4]
      list(est = b, lo = b - 1.96 * se, hi = b + 1.96 * se, p = p, metric = "beta")
    }
  }

  .fmt_est <- function(r) {
    if (!is.finite(r$est)) return("")
    d <- if (identical(r$metric, "OR")) 3L else 4L
    sprintf(paste0("%.", d, "f"), r$est)
  }
  .fmt_ci <- function(r) {
    if (!is.finite(r$lo) || !is.finite(r$hi)) return("")
    d <- if (identical(r$metric, "OR")) 3L else 4L
    sprintf(paste0("(%.", d, "f, %.", d, "f)"), r$lo, r$hi)
  }
  .fmt_p <- function(p) {
    if (!is.finite(p)) return("")
    if (p < 0.001) "<0.001" else sprintf("%.4f", p)
  }

  pairs <- list(
    list(label = paste(x_lab, "and", m_lab), resp = m, pred = x, family = "gaussian",
         cov1 = m1, cov2 = m2),
    list(label = paste(x_lab, "and", y_lab), resp = ".y", pred = x, family = "binomial",
         cov1 = m1, cov2 = m2),
    list(label = paste(m_lab, "and", y_lab), resp = ".y", pred = m, family = "binomial",
         cov1 = unique(c(m1)), cov2 = unique(c(m2)))
  )

  # 长表（原始）
  rows_long <- list()
  # 出版行：pair 标题 + Crude/Model1/Model2
  pub_rows <- list()
  for (pr in pairs) {
    pub_rows[[length(pub_rows) + 1L]] <- data.frame(
      Variable = pr$label, Estimate = "", `95% CI` = "", `P value` = "",
      stringsAsFactors = FALSE, check.names = FALSE
    )
    for (model in c("Crude", "Model 1", "Model 2")) {
      covs <- if (identical(model, "Crude")) character(0)
      else if (identical(model, "Model 1")) pr$cov1 else pr$cov2
      if ("Country" %in% names(data) && !identical(model, "Crude") && !"Country" %in% covs &&
          length(unique(stats::na.omit(as.character(data$Country)))) > 1L) {
        covs <- c(covs, "Country")
      }
      r <- .fit_row(pr$resp, pr$pred, covs, pr$family)
      rows_long[[length(rows_long) + 1L]] <- data.frame(
        Cohort = db, Pair = pr$label, Model = model,
        Estimate = .fmt_est(r), CI = .fmt_ci(r), P = .fmt_p(r$p),
        metric = r$metric, stringsAsFactors = FALSE
      )
      pub_rows[[length(pub_rows) + 1L]] <- data.frame(
        Variable = model,
        Estimate = .fmt_est(r),
        `95% CI` = .fmt_ci(r),
        `P value` = .fmt_p(r$p),
        stringsAsFactors = FALSE, check.names = FALSE
      )
    }
  }
  tab_long <- do.call(rbind, rows_long)
  pub <- do.call(rbind, pub_rows)

  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab_long, file.path(out_dir, "Table3_Correlation_Regression_FI_Depression_Hip.csv"),
                   row.names = FALSE)

  note <- sprintf(
    "Note: Model 1 adjusted for %s. Model 2 adjusted for %s%s. Continuous~continuous = beta; binary outcome = OR.",
    if (length(m1)) paste(m1, collapse = ", ") else "none",
    if (length(m2)) paste(m2, collapse = ", ") else "none",
    if ("Country" %in% names(data) && length(unique(stats::na.omit(as.character(data$Country)))) > 1L)
      " (Pooled + Country)" else ""
  )

  pub_path <- file.path(out_dir, "Table3_Correlation_Regression_FI_Depression_Hip.xlsx")
  if (exists(".sci_xlsx_write_three_line_workbook", mode = "function") && nrow(pub)) {
    body2 <- pub
    for (j in seq_len(ncol(body2))) body2[[j]] <- as.character(body2[[j]])
    hdr <- setNames(as.data.frame(as.list(names(pub)), stringsAsFactors = FALSE), names(pub))
    tbl_df_new <- rbind(hdr, body2)
    pair_names <- vapply(pairs, function(z) z$label, character(1))
    insert_map <- stats::setNames(rep(1L, length(pair_names)), pair_names)
    level_idx <- which(tbl_df_new[[1L]] %in% c("Crude", "Model 1", "Model 2"))
    .sci_xlsx_write_three_line_workbook(
      pub_path,
      title = sprintf("Table. Correlation regression (%s)", db),
      tbl_df_new = tbl_df_new,
      sheet = "Table",
      footnotes = note,
      insert_map = insert_map,
      level_row_idx = level_idx
    )
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(pub, pub_path)
  }

  saveRDS(
    list(db = db, pub = pub, long = tab_long, model1 = m1, model2 = m2, note = note),
    file.path(out_dir, "Table3_Correlation_Regression_pub.rds")
  )
  ctx$results$cross_lagged_corr_table <- list(table = tab_long, pub = pub, path = pub_path)
  cli::cli_alert_success("corr table 写出: {pub_path}")
  ctx
}

#' 多库并列合并为 Table S6（按 Cohort 分区）
cross_lagged_corr_build_table_s6 <- function(
    rds_paths,
    outfile,
    cohorts = c("CHARLS", "ELSA", "HRS"),
    title = "Table S6. Correlation regression of Frailty Index, Depression and Hip fracture"
) {
  objs <- list()
  for (p in rds_paths) {
    if (!file.exists(p)) next
    o <- readRDS(p)
    db <- as.character(o$db %||% NA_character_)[1L]
    if (!nzchar(db) || is.na(db)) next
    objs[[db]] <- o
  }
  cohorts <- cohorts[cohorts %in% names(objs)]
  if (!length(cohorts)) stop("cross_lagged_corr_build_table_s6: 无可用结果", call. = FALSE)

  body_rows <- list()
  for (db in cohorts) {
    body_rows[[length(body_rows) + 1L]] <- data.frame(
      Variable = db, Estimate = "", `95% CI` = "", `P value` = "",
      stringsAsFactors = FALSE, check.names = FALSE
    )
    pub <- objs[[db]]$pub
    for (i in seq_len(nrow(pub))) {
      body_rows[[length(body_rows) + 1L]] <- pub[i, , drop = FALSE]
    }
  }
  body <- do.call(rbind, body_rows)
  rownames(body) <- NULL

  m1 <- unique(unlist(lapply(objs[cohorts], function(o) o$model1 %||% character(0))))
  m2 <- unique(unlist(lapply(objs[cohorts], function(o) o$model2 %||% character(0))))
  note <- sprintf(
    "Note: Model 1 adjusted for %s. Model 2 adjusted for %s%s. Continuous associations reported as beta; associations with binary outcome as OR (95%% CI).",
    if (length(m1)) paste(m1, collapse = ", ") else "none",
    if (length(m2)) paste(setdiff(m2, "Country"), collapse = ", ") else "none",
    if ("Pooled" %in% cohorts) "; Pooled additionally adjusted for Country" else ""
  )

  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  if (exists(".sci_xlsx_write_three_line_workbook", mode = "function")) {
    body2 <- body
    for (j in seq_len(ncol(body2))) body2[[j]] <- as.character(body2[[j]])
    hdr <- setNames(as.data.frame(as.list(names(body)), stringsAsFactors = FALSE), names(body))
    tbl_df_new <- rbind(hdr, body2)
    sec <- c(cohorts, unique(as.character(unlist(lapply(objs[cohorts], function(o) {
      as.character(o$pub$Variable)[!as.character(o$pub$Variable) %in% c("Crude", "Model 1", "Model 2")]
    })))))
    insert_map <- stats::setNames(rep(1L, length(sec)), sec)
    level_idx <- which(tbl_df_new[[1L]] %in% c("Crude", "Model 1", "Model 2"))
    .sci_xlsx_write_three_line_workbook(
      outfile, title = title, tbl_df_new = tbl_df_new, sheet = "Table S6",
      footnotes = note, insert_map = insert_map, level_row_idx = level_idx
    )
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(body, outfile)
  }
  invisible(list(path = outfile, cohorts = cohorts))
}

register_block("cross_lagged_corr_table", block_cross_lagged_corr_table, "Table S6 相关回归")
