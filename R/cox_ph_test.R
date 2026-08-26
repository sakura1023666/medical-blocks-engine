###############################################################################
#  cox_ph_test.R — Cox 比例风险假设检验（Schoenfeld / cox.zph）
#
#  预后 Cox 分组块在拟合 Crude / Model1 / Model2（及 Model3）后调用。
#  默认导出附表；可用 config$cox_quartile$ph_test_enable = FALSE 关闭。
###############################################################################

cox_ph_model_label <- function(nm) {
  switch(
    as.character(nm %||% "")[1L],
    crude = "Crude",
    model1 = "Model 1",
    model2 = "Model 2",
    model3 = "Model 3",
    as.character(nm)[1L]
  )
}

cox_ph_fits_to_table <- function(fits, include_model3 = FALSE) {
  if (!is.list(fits) || !length(fits)) return(NULL)
  if (!requireNamespace("survival", quietly = TRUE)) return(NULL)
  want <- c("crude", "model1", "model2")
  if (isTRUE(include_model3)) want <- c(want, "model3")
  keep <- intersect(want, names(fits))
  if (!length(keep)) keep <- setdiff(names(fits), if (!isTRUE(include_model3)) "model3" else character(0))
  rows <- list()
  for (nm in keep) {
    fit <- fits[[nm]]
    if (is.null(fit) || inherits(fit, "try-error")) next
    z <- tryCatch(survival::cox.zph(fit), error = function(e) NULL)
    if (is.null(z) || is.null(z$table)) next
    tb <- as.data.frame(z$table, stringsAsFactors = FALSE)
    tb$Term <- rownames(z$table)
    names(tb)[seq_len(3L)] <- c("Chi-square", "df", "P value")
    tb$Model <- cox_ph_model_label(nm)
    tb$N <- tryCatch(as.integer(fit$n)[1L], error = function(e) NA_integer_)
    tb$Events <- tryCatch(as.integer(fit$nevent)[1L], error = function(e) NA_integer_)
    rows[[length(rows) + 1L]] <- tb[, c("Model", "Term", "Chi-square", "df", "P value", "N", "Events")]
  }
  if (!length(rows)) return(NULL)
  df <- do.call(rbind, rows)
  rownames(df) <- NULL
  df$`Chi-square` <- sprintf("%.3f", as.numeric(df$`Chi-square`))
  df$df <- as.integer(round(as.numeric(df$df)))
  pnum <- as.numeric(df$`P value`)
  df$`P value` <- ifelse(
    !is.finite(pnum),
    NA_character_,
    ifelse(pnum < 0.001, "<0.001", sprintf("%.4f", pnum))
  )
  df$N <- as.integer(df$N)
  df$Events <- as.integer(df$Events)
  df
}

cox_ph_patch_queued_filepath <- function(filepath, title) {
  if (!exists(".table_queue_env") || !is.list(.table_queue_env$items) ||
      !length(.table_queue_env$items)) {
    return(invisible(NULL))
  }
  i <- length(.table_queue_env$items)
  .table_queue_env$items[[i]]$filepath <- filepath
  .table_queue_env$items[[i]]$title <- title
  invisible(NULL)
}

#' PH 附表脚注协变量：与 Table 2 同源（本次 Cox 拟合因子，而非 stale Model2Factors）
cox_ph_resolve_footnote_factors <- function(ctx, model1_factors = NULL,
                                            model2_factors = NULL,
                                            model3_factors = NULL) {
  m1 <- as.character(model1_factors %||% character(0))
  m1 <- m1[nzchar(m1)]
  if (!length(m1)) {
    m1 <- as.character(
      ctx$results$cox_model1_covariates %||%
        ctx$results$Model1Factors %||%
        character(0)
    )
    m1 <- m1[nzchar(m1)]
  }
  m2 <- as.character(model2_factors %||% character(0))
  m2 <- m2[nzchar(m2)]
  if (!length(m2)) {
    m2_extra <- as.character(ctx$results$cox_model2_covariates %||% character(0))
    m2_extra <- m2_extra[nzchar(m2_extra)]
    if (length(m2_extra)) {
      m2 <- unique(c(m1, setdiff(m2_extra, m1)))
    } else {
      m2 <- as.character(ctx$results$Model2Factors %||% character(0))
      m2 <- unique(m2[nzchar(m2)])
    }
  }
  m3 <- as.character(model3_factors %||% ctx$results$Model3Factors %||% character(0))
  m3 <- unique(m3[nzchar(m3)])
  list(M1 = m1, M2 = m2, M3 = m3)
}

#' 从已拟合 Cox 对象导出 PH 检验附表，写入 ctx$results$cox_ph_test
#' 默认仅 Crude / Model1 / Model2（不含 Model3）；脚注亦不写 Model3。
#' 需要 Model3 时设 bl_cfg$ph_test_include_model3 = TRUE。
cox_ph_export_supp_table <- function(ctx, fits, index_var, bl_cfg = list(),
                                     model1_factors = NULL,
                                     model2_factors = NULL,
                                     model3_factors = NULL,
                                     m3_significant = NULL) {
  cfg <- ctx$config %||% list()
  cox_legacy <- cfg$cox %||% list()
  enable <- bl_cfg$ph_test_enable %||% cox_legacy$ph_test_enable %||% TRUE
  if (!isTRUE(enable)) return(ctx)
  include_m3 <- isTRUE(
    bl_cfg$ph_test_include_model3 %||%
      cox_legacy$ph_test_include_model3 %||%
      FALSE
  )
  tab <- cox_ph_fits_to_table(fits, include_model3 = include_m3)
  if (is.null(tab) || !nrow(tab)) {
    cli::cli_alert_warning("cox_ph_test: 无法计算 Schoenfeld 检验")
    return(ctx)
  }
  ctx$results$cox_ph_test <- tab
  n_use <- suppressWarnings(as.integer(tab$N[tab$Model == "Model 2"][1L]))
  if (!is.finite(n_use)) n_use <- suppressWarnings(as.integer(tab$N[1L]))
  ev_use <- suppressWarnings(as.integer(tab$Events[tab$Model == "Model 2"][1L]))
  if (!is.finite(ev_use)) ev_use <- suppressWarnings(as.integer(tab$Events[1L]))

  disease <- cfg$project$disease %||% "Outcome"
  ix <- as.character(index_var %||% cfg$survival$index_var %||% "index")[1L]
  cap <- paste0(
    "Proportional hazards assumption test (Schoenfeld residuals) for ",
    ix, " and ", disease
  )
  tables_dir <- ctx$output_dir_tables %||% ctx$output_dir
  if (is.null(tables_dir) || !nzchar(as.character(tables_dir)[1L])) {
    cli::cli_alert_warning("cox_ph_test: 缺少 output_dir_tables，仅写入 ctx$results")
    return(ctx)
  }
  dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)

  fixed_sno <- suppressWarnings(as.integer(
    bl_cfg$ph_table_number %||% cox_legacy$ph_table_number %||% NA_integer_
  )[1L])
  if (is.finite(fixed_sno) && fixed_sno >= 1L) {
    pref <- pub_prefix("supp_table", fixed_sno)
    title <- paste(pref, cap)
    filepath <- .inject_db_into_pub_filepath(
      file.path(tables_dir, paste0(title, ".xlsx"))
    )
    if (exists("pub_bump_supp_table_min", mode = "function")) {
      pub_bump_supp_table_min(fixed_sno)
    }
  } else {
    pub <- pub_pair(ctx, tables_dir, "supp_table", cap, cap, "xlsx")
    title <- pub$title
    filepath <- pub$filepath
  }

  fac <- cox_ph_resolve_footnote_factors(
    ctx,
    model1_factors = model1_factors,
    model2_factors = model2_factors,
    model3_factors = if (include_m3) model3_factors else character(0)
  )
  m1 <- fac$M1
  m2 <- fac$M2
  # PH 默认不报 Model3：脚注只写 Crude / Model1 / Model2
  footnotes <- c(
    "The Crude Model was non-adjusted.",
    paste0(
      "The Model 1 was adjusted by: ",
      if (length(m1)) paste(m1, collapse = ", ") else "None",
      "."
    ),
    paste0(
      "The Model 2 was adjusted by: ",
      if (length(m2)) paste(m2, collapse = ", ") else "None",
      "."
    ),
    sprintf(
      "PH tests were run on the same cohort as the corresponding Cox table: N = %s, events = %s.",
      ifelse(is.finite(n_use), as.character(n_use), "NA"),
      ifelse(is.finite(ev_use), as.character(ev_use), "NA")
    ),
    "Proportional hazards assumption was assessed using Schoenfeld residuals (cox.zph).",
    "P value > 0.05 indicates no evidence against proportional hazards for the corresponding term/model."
  )
  tryCatch({
    export_sci_table(tab, filepath, title = title, table_footnotes = footnotes)
    cox_ph_patch_queued_filepath(filepath, title)
    cli::cli_alert_success("PH 检验附表: {.file {basename(filepath)}}")
  }, error = function(e) {
    cli::cli_alert_warning("cox_ph_test: 导出失败: {e$message}")
  })
  global_p <- suppressWarnings(as.numeric(
    gsub("^<", "0", tab$`P value`[tab$Model == "Model 2" & tab$Term == "GLOBAL"][1L])
  ))
  if (is.finite(global_p) && global_p < 0.05) {
    cli::cli_alert_warning(
      "cox_ph_test: Model 2 GLOBAL p = {sprintf('%.4f', global_p)}，比例风险假设可能违反"
    )
  }
  ctx
}
