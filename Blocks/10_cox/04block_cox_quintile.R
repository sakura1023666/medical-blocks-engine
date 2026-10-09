###############################################################################
#  cox_quintile — 预后五分位 Cox HR（Q1 参照 + p for trend），Crude / Model1 / Model2。
#
#  register_block: "cox_quintile"
#  前置: prognosis + imputed；固定协变量；对齐 logistic_quintile_glm
#  配置: config$cox_quintile（index_var、group_var、model*_factors、pause_*）
###############################################################################

.cq04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.cq04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "cox_quintile", reason = reason,
                                   suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: cox_quintile — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.cq04_format_p_cells <- function(rt) {
  rt <- as.data.frame(rt, stringsAsFactors = FALSE)
  for (j in c(6L, 9L, 12L)) {
    if (ncol(rt) < j) next
    x <- as.character(rt[[j]])
    x[grepl("[0-9]+\\.?[0-9]*[eE][+-][0-9]+", x) | grepl("^0$", x)] <- "<0.001"
    rt[[j]] <- x
  }
  rt
}

.cq04_Tb_ModelGroupNg_HR <- function(time_var, event_var, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors, group_labels, cutoffs) {
  surv_lhs <- paste0("Surv(", time_var, ", ", event_var, ")")
  rhs_c <- function(vars) paste(c(vars), collapse = " + ")
  mc1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(ContinuousName))), data = Data)
  mc2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model1Factors)))), data = Data)
  mc3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(ContinuousName, Model2Factors)))), data = Data)
  mf1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(FactorName))), data = Data)
  mf2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model1Factors)))), data = Data)
  mf3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(FactorName, Model2Factors)))), data = Data)
  mt1 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(TrendName))), data = Data)
  mt2 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(TrendName, Model1Factors)))), data = Data)
  mt3 <- coxph(as.formula(paste0(surv_lhs, " ~ ", rhs_c(c(TrendName, Model2Factors)))), data = Data)
  .hr_ci_p <- function(m, row) {
    sm <- summary(m); ci <- suppressMessages(confint(m))
    list(hr = round(exp(coef(m))[row], 3),
         ci = paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")"),
         p = pub_format_p_cell(sm$coefficients[row, "Pr(>|z|)"]))
  }
  n_total <- nrow(Data); cnt <- table(Data[[FactorName]])
  .pct <- function(lv) paste0(as.numeric(cnt[lv]), "(", round(as.numeric(cnt[lv]) / n_total * 100, 2), "%)")
  c1 <- .hr_ci_p(mc1, 1L); c2 <- .hr_ci_p(mc2, 1L); c3 <- .hr_ci_p(mc3, 1L)
  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "Exposure cutoff", "N (%)", "HR", "95%CI", "P-value",
             "HR", "95%CI", "P-value", "HR", "95%CI", "P-value")
  Line3 <- c(ContinuousName, rep("", 11L))
  Line4 <- c(paste0(ContinuousName, " continuous"), "", "", c1$hr, c1$ci, c1$p, c2$hr, c2$ci, c2$p, c3$hr, c3$ci, c3$p)
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", 11L))
  ref_lv <- group_labels[1L]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv), "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")
  non_ref <- group_labels[-1L]
  lines_nonref <- lapply(seq_along(non_ref), function(i) {
    lv <- non_ref[i]; r <- .hr_ci_p(mf1, i); r2 <- .hr_ci_p(mf2, i); r3 <- .hr_ci_p(mf3, i)
    c(lv, cutoffs[lv], .pct(lv), r$hr, r$ci, r$p, r2$hr, r2$ci, r2$p, r3$hr, r3$ci, r3$p)
  })
  Line_trend <- c("p for trend", rep("", 4L),
                  pub_format_p_cell(summary(mt1)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt2)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt3)$coefficients[1, "Pr(>|z|)"]))
  rt <- do.call(rbind, c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref, list(Line_trend)))
  rownames(rt) <- NULL
  list(table = rt, fits = list(grouped = list(crude = mf1, model1 = mf2, model2 = mf3)))
}

block_cox_quintile <- function(ctx, ...) {
  suppressPackageStartupMessages(library(survival))
  cfg <- ctx$config; cox_legacy <- cfg$cox %||% list(); bl_cfg <- cfg$cox_quintile %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) .cq04_pause(ctx, "未找到分析数据", "请先运行 data_clean / imputation")

  surv_cfg <- cfg$survival %||% list()
  time_var <- surv_cfg$time_var %||% "futime"
  event_var <- surv_cfg$event_var %||% "fustatus"
  index_var <- bl_cfg$index_var %||% surv_cfg$index_var %||% (cfg$logistic %||% list())$index_var
  if (is.null(index_var) || !nzchar(index_var)) stop("cox_quintile: index_var 未设置。")
  for (v in c(time_var, event_var, index_var)) if (!v %in% names(data)) stop("cox_quintile: '", v, "' 不在数据中。")

  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  data2 <- data
  if (is.character(data2[[event_var]]) || is.factor(data2[[event_var]])) {
    if (is.null(disease_label) || !nzchar(disease_label)) stop("cox_quintile: 需 config$project$analysis_group。")
    data2[[event_var]] <- ifelse(data2[[event_var]] == disease_label, 1, 0)
  }
  data2[[event_var]] <- as.numeric(data2[[event_var]])

  group_var_name <- bl_cfg$group_var
  predefined <- !is.null(group_var_name) && nzchar(group_var_name) && group_var_name %in% names(data2)
  raw_levels <- c("Q1", "Q2", "Q3", "Q4", "Q5")

  if (predefined) {
    lv <- bl_cfg$group_levels %||% raw_levels
    data2$Group <- factor(data2[[group_var_name]], levels = lv)
    if (any(is.na(data2$Group))) stop("cox_quintile: group_var 水平不一致。")
    cutoffs <- setNames(rep("", length(lv)), lv)
    raw_levels <- lv
  } else {
    quintiles <- stats::quantile(data2[[index_var]], probs = c(0.2, 0.4, 0.6, 0.8), na.rm = TRUE)
    data2$Group <- "Q"
    data2$Group[data2[[index_var]] < quintiles[1]] <- "Q1"
    data2$Group[data2[[index_var]] >= quintiles[1] & data2[[index_var]] < quintiles[2]] <- "Q2"
    data2$Group[data2[[index_var]] >= quintiles[2] & data2[[index_var]] < quintiles[3]] <- "Q3"
    data2$Group[data2[[index_var]] >= quintiles[3] & data2[[index_var]] < quintiles[4]] <- "Q4"
    data2$Group[data2[[index_var]] >= quintiles[4]] <- "Q5"
    data2$Group <- factor(data2$Group, levels = raw_levels)
    cutoffs <- c(
      Q1 = paste0("\u2264 ", round(quintiles[1], 2)),
      Q2 = paste0(round(quintiles[1], 2), " - ", round(quintiles[2], 2)),
      Q3 = paste0(round(quintiles[2], 2), " - ", round(quintiles[3], 2)),
      Q4 = paste0(round(quintiles[3], 2), " - ", round(quintiles[4], 2)),
      Q5 = paste0("\u2265 ", round(quintiles[4], 2))
    )
  }
  data2$Num <- as.numeric(data2$Group)

  cfg_m1 <- as.character(cox_legacy$model1_covariates %||% character(0))
  cfg_m2 <- as.character(cox_legacy$model2_covariates %||% character(0))
  Model1Factors <- as.character(
    bl_cfg$model1_factors %||%
      ctx$results$assoc_model1_factors %||%
      ctx$results$Model1Factors %||% cfg_m1
  )
  Model2Factors <- as.character(
    bl_cfg$model2_factors %||%
      ctx$results$assoc_model2_factors %||%
      ctx$results$Model2Factors %||% cfg_m2
  )
  if (length(Model1Factors) == 0L) .cq04_pause(ctx, "Model1Factors 为空", "请先运行 multicollinearity")
  if ("Glucose" %in% Model1Factors && "A1c" %in% Model1Factors) Model1Factors <- Model1Factors[Model1Factors != "A1c"]
  Model1Factors <- intersect(Model1Factors, names(data2))
  if (length(Model2Factors) == 0L) Model2Factors <- Model1Factors
  else Model2Factors <- unique(c(Model1Factors, intersect(Model2Factors, names(data2))))

  dt <- stats::na.omit(data2[, unique(c(time_var, event_var, index_var, "Group", "Num", Model2Factors)), drop = FALSE])
  if (nrow(dt) < 10L) .cq04_pause(ctx, "完整病例数过少", "检查缺失", utils::head(dt, 5L))

  res <- tryCatch(
    .cq04_Tb_ModelGroupNg_HR(time_var, event_var, index_var, "Group", "Num", dt,
                             Model1Factors, Model2Factors, raw_levels, cutoffs),
    error = function(e) {
      if (.cq04_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) .cq04_pause(ctx, conditionMessage(e), "检查协变量")
      stop("cox_quintile: ", conditionMessage(e), call. = FALSE)
    }
  )

  rt_df <- data.frame(.cq04_format_p_cells(res$table), stringsAsFactors = FALSE)
  rownames(rt_df) <- NULL
  h1 <- as.character(rt_df[1, ]); h2 <- as.character(rt_df[2, ])
  rt_body <- rt_df[-c(1L, 2L), , drop = FALSE]
  colnames(rt_body) <- paste0("V", seq_len(ncol(rt_body)))
  caption <- paste0("The Association Between ", index_var, " and ",
                    cfg$project$disease %||% "Outcome", " (Cox quintile)")
  if (is.null(bl_cfg$table_filename) || !nzchar(bl_cfg$table_filename)) {
    pub <- pub_paths(ctx, ctx$output_dir_tables, "main_table", caption, "xlsx")
    title <- pub$title
    filepath <- pub$filepath
  } else {
    title <- pub_title(ctx, "main_table", caption)
    filepath <- file.path(ctx$output_dir_tables, bl_cfg$table_filename)
  }
  footnotes <- c("Crude Model was non-adjusted;",
                 paste0("Model 1 was adjusted by: ", paste(Model1Factors, collapse = ", ")),
                 paste0("Model 2 was adjusted by: ", paste(Model2Factors, collapse = ", ")))
  tryCatch(export_sci_table(rt_body, filepath, title = title, header_row1 = h1, header_row2 = h2,
                            latex_include_colnames = FALSE, table_footnotes = footnotes),
           error = function(e) cli::cli_alert_warning("cox_quintile: export 失败: {e$message}"))

  glv_c5 <- levels(dt$Group)
  top_c5 <- glv_c5[length(glv_c5)]
  hr_top_c5 <- NA_real_
  mf3_c5 <- tryCatch(res$fits$grouped$model2, error = function(e) NULL)
  if (!is.null(mf3_c5)) {
    cf_c5 <- tryCatch(stats::coef(mf3_c5), error = function(e) NULL)
    if (!is.null(cf_c5) && length(cf_c5) >= 1L) {
      hr_top_c5 <- round(exp(as.numeric(cf_c5[length(cf_c5)])), 4)
    }
  }
  ctx$results$cox_highest_group_model2_hr <- hr_top_c5
  ctx$results$cox_highest_group_level <- top_c5
  if (!predefined) ctx$results$cox_index_breaks <- as.numeric(quintiles)

  ctx$results$cox_hr <- rt_df
  ctx$results$cox_models <- res$fits$grouped
  ctx$results$cox_model1_covariates <- Model1Factors
  ctx$results$cox_model2_covariates <- setdiff(Model2Factors, Model1Factors)
  ctx$results$cox_grouping <- list(method = "quintile", n_groups = nlevels(dt$Group), group_levels = levels(dt$Group))
  if (exists("cox_ph_export_supp_table", mode = "function")) {
    ctx <- cox_ph_export_supp_table(ctx, res$fits$grouped, index_var, bl_cfg)
  }
  cli::cli_alert_success("cox_quintile 完成: {.file {basename(filepath)}}")
  ctx
}

register_block("cox_quintile", block_cox_quintile, "五分位 Cox HR 表（固定 Model1/Model2 + trend）")
