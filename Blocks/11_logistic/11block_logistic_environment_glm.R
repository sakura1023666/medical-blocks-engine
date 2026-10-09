###############################################################################
#  logistic_environment_glm — 环境多暴露四分位 GLM 筛选（C01_GLM 逻辑）。
#                              对 ctx$results$select_vocs 中每个 VOC 做 Q1–Q4 GLM
#                              （Q1 参照）；Model1 / Model2 固定（无随机搜索）；
#                              按 continuous 行 Model2 P 值筛选 select_vocs_glm /
#                              select_vocs_final；export_sci_table 三线表。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data          = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results   = "select_vocs"       # 上游写入候选环境暴露列名向量
#  require_ctx_results  += "Model1Factors"     # Model1 协变量
#  require_ctx_results  += "final_features"    # Model2 全量协变量（对应原 pos.factors）
#
#  logistic_environment_glm = list(
#    skip_first_voc         = TRUE,    # TRUE → 循环 select_vocs[-1]（与原 C01_GLM 一致）
#    exclude_vocs           = character(0),
#    screening_p_threshold  = 0.05,    # continuous 行 Model2 P 筛选阈值
#    model1_factors         = NULL,    # 非 NULL 时覆盖 ctx$results$Model1Factors
#    model2_factors         = NULL,    # 非 NULL 时覆盖 ctx$results$final_features
#    pause_enable           = TRUE,
#    pause_on_no_vocs       = TRUE,
#    pause_on_empty_screen  = FALSE,
#    table_filename         = NULL,
#    table_title            = NULL
#  ),
#
#  不读 data_source / 对照表路径；环境 Labels→Exposure 对照表后补 config$environment。
#  register_block: "logistic_environment_glm"
#  典型流水线: 上游写入 select_vocs；对每个 VOC 四分位 GLM 筛选；写 select_vocs_glm/final
#  块内 bl_cfg <- cfg$logistic_environment_glm
###############################################################################

.lqg11_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqg11_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "logistic_environment_glm", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop("PAUSE_FOR_USER_DECISION: logistic_environment_glm — ", reason,
       " | See ctx$results$pause_point.", call. = FALSE)
}

.lqg11_Tb_ModelGroup3_OR <- function(ResultName, ContinuousName, FactorName, TrendName,
                                      Data, Model1Factors, Model2Factors,
                                      cutoffs, group_labels, include_continuous = TRUE) {
  fml_f01 <- as.formula(paste0(ResultName, "~", FactorName))
  fml_f02 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model1Factors), collapse = "+")))
  fml_f03 <- as.formula(paste0(ResultName, "~", paste(c(FactorName, Model2Factors), collapse = "+")))
  fml_t01 <- as.formula(paste0(ResultName, "~", TrendName))
  fml_t02 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model1Factors), collapse = "+")))
  fml_t03 <- as.formula(paste0(ResultName, "~", paste(c(TrendName, Model2Factors), collapse = "+")))

  mf  <- glm(fml_f01, data = Data, family = binomial)
  mf2 <- glm(fml_f02, data = Data, family = binomial)
  mf3 <- glm(fml_f03, data = Data, family = binomial)
  mt  <- glm(fml_t01, data = Data, family = binomial)
  mt2 <- glm(fml_t02, data = Data, family = binomial)
  mt3 <- glm(fml_t03, data = Data, family = binomial)

  n_total <- nrow(Data); cnt <- table(Data[[FactorName]])
  .ci <- function(m, row) {
    ci <- logistic_safe_confint(m)
    paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")")
  }
  .pct <- function(lv) { n <- as.numeric(cnt[lv]); paste0(n, "(", round(n/n_total*100, 2), "%)") }

  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c("Characteristic", "Exposure cutoff", "N (%)",
             "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value")
  Line5 <- c(paste0(ContinuousName, " groups"), rep("", 11))

  ref_lv   <- group_labels[1]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv),
                "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")

  non_ref_lvs  <- group_labels[-1]
  lines_nonref <- lapply(seq_along(non_ref_lvs), function(i) {
    lv <- non_ref_lvs[i]; idx <- i + 1L
    c(lv, cutoffs[lv], .pct(lv),
      round(exp(coef(mf)[idx]),  3), .ci(mf,  idx), pub_format_p_cell(summary(mf)$coefficients[idx, 4]),
      round(exp(coef(mf2)[idx]), 3), .ci(mf2, idx), pub_format_p_cell(summary(mf2)$coefficients[idx, 4]),
      round(exp(coef(mf3)[idx]), 3), .ci(mf3, idx), pub_format_p_cell(summary(mf3)$coefficients[idx, 4]))
  })

  Line_trend <- c("p for trend", rep("", 4),
                  pub_format_p_cell(summary(mt)$coefficients[2, 4]), "", "",
                  pub_format_p_cell(summary(mt2)$coefficients[2, 4]), "", "",
                  pub_format_p_cell(summary(mt3)$coefficients[2, 4]))

  if (include_continuous) {
    fml_c01 <- as.formula(paste0(ResultName, "~", ContinuousName))
    fml_c02 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model1Factors), collapse = "+")))
    fml_c03 <- as.formula(paste0(ResultName, "~", paste(c(ContinuousName, Model2Factors), collapse = "+")))
    mc <- glm(fml_c01, data = Data, family = binomial)
    mc2 <- glm(fml_c02, data = Data, family = binomial)
    mc3 <- glm(fml_c03, data = Data, family = binomial)
    .ci_c <- function(m) { ci <- logistic_safe_confint(m); paste0("(", round(exp(ci[2,1]),3), ",", round(exp(ci[2,2]),3), ")") }
    Line3 <- c(ContinuousName, rep("", 11))
    Line4 <- c(paste0(ContinuousName, " continuous"), "", "",
               round(exp(coef(mc)[2]),  3), .ci_c(mc),  pub_format_p_cell(summary(mc)$coefficients[2, 4]),
               round(exp(coef(mc2)[2]), 3), .ci_c(mc2), pub_format_p_cell(summary(mc2)$coefficients[2, 4]),
               round(exp(coef(mc3)[2]), 3), .ci_c(mc3), pub_format_p_cell(summary(mc3)$coefficients[2, 4]))
    rt <- do.call(rbind, c(list(Line1, Line2, Line3, Line4, Line5, Line_ref), lines_nonref, list(Line_trend)))
  } else {
    rt <- do.call(rbind, c(list(Line1, Line2, Line5, Line_ref), lines_nonref, list(Line_trend)))
  }
  rownames(rt) <- NULL; rt
}

.lqg11_format_p_cols <- function(rt) {
  for (col in c("X6", "X9", "X12")) {
    if (col %in% names(rt)) rt[[col]][rt[[col]] == "0"] <- "P < 0.001"
  }
  rt
}

.lqg11_prepare_outcome <- function(data, outcome_col, ref_label, case_label) {
  y <- data[[outcome_col]]
  if (is.numeric(y) && all(na.omit(unique(y)) %in% c(0, 1))) {
    data[[outcome_col]] <- as.integer(y)
    return(data)
  }
  y_chr <- as.character(y)
  data[[outcome_col]] <- ifelse(y_chr == case_label, 1L,
                                ifelse(y_chr == ref_label, 0L, NA_integer_))
  if (anyNA(data[[outcome_col]])) {
    data[[outcome_col]] <- as.integer(as.numeric(y))
  }
  data
}

.lqg11_screen_continuous_p <- function(tab_df, p_thr) {
  if (is.null(tab_df) || !nrow(tab_df)) return(character(0))
  x1 <- as.character(tab_df[[1L]])
  cont <- grepl("continuous", x1, fixed = TRUE)
  if (!any(cont)) return(character(0))
  pvals <- as.character(tab_df[[12L]][cont])
  hit <- pvals == "P < 0.001" |
    grepl("e", pvals, ignore.case = TRUE) |
    suppressWarnings(as.numeric(pvals) < p_thr)
  vocs <- x1[cont][hit]
  gsub(" continuous", "", vocs, fixed = TRUE)
}

block_logistic_environment_glm <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- cfg$logistic_environment_glm %||% list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    .lqg11_pause(ctx, "未找到分析数据", "请先运行上游数据准备 block（imputation 等）")
  }

  select_vocs <- as.character(ctx$results$select_vocs %||% character(0))
  if (length(select_vocs) == 0L) {
    if (.lqg11_should_pause(bl_cfg, "pause_on_no_vocs", TRUE)) {
      .lqg11_pause(ctx, "ctx$results$select_vocs 为空",
                   "请由上游 block 写入 select_vocs（如 Lasso / 环境筛选）")
    }
    stop("logistic_environment_glm: select_vocs 为空。")
  }

  exclude_vocs <- as.character(bl_cfg$exclude_vocs %||% character(0))
  select_vocs  <- setdiff(select_vocs, exclude_vocs)
  if (isTRUE(bl_cfg$skip_first_voc %||% TRUE) && length(select_vocs) > 1L) {
    voc_loop <- select_vocs[-1L]
  } else {
    voc_loop <- select_vocs
  }
  voc_loop <- voc_loop[voc_loop %in% names(data)]
  if (length(voc_loop) == 0L) {
    stop("logistic_environment_glm: 无有效 VOC 列（select_vocs 与数据列无交集）。")
  }

  outcome_col <- bl_cfg$outcome_column %||% cfg$data$outcome_column %||% "Group"
  if (!outcome_col %in% names(data)) {
    stop("logistic_environment_glm: outcome 列 '", outcome_col, "' 不在数据中。")
  }
  ref_label  <- cfg$project$reference_group %||% cfg$project$control %||% "0"
  case_label <- cfg$project$analysis_group %||% cfg$project$disease %||% "1"

  index_for_cov <- as.character(
    (cfg$logistic %||% list())$index_var %||%
      (cfg$incidence %||% list())$index_var %||% "BMI"
  )[1L]
  if (!is.null(bl_cfg$model1_factors) && !is.null(bl_cfg$model2_factors)) {
    Model1Factors <- as.character(bl_cfg$model1_factors)
    Model2Factors <- as.character(bl_cfg$model2_factors)
  } else {
    resolved <- logistic_resolve_models(ctx, cfg, data, index_for_cov, bl_cfg)
    Model1Factors <- resolved$M1
    Model2Factors <- resolved$M2
  }
  if (!length(Model1Factors) || !length(Model2Factors)) {
    .lqg11_pause(ctx, "Model1/Model2 协变量为空",
                 "请先运行 multicollinearity_nhanes_final 或指定 model1/model2_factors")
  }
  if ("Age_Years" %in% Model1Factors && "Age_Group" %in% Model1Factors) {
    Model1Factors <- Model1Factors[Model1Factors != "Age_Group"]
  }
  Model1Factors <- intersect(Model1Factors, colnames(data))
  Model2Factors <- intersect(Model2Factors, colnames(data))
  Model1Factors <- intersect(Model1Factors, Model2Factors)
  cli::cli_alert_info("logistic_environment_glm Model1: {paste(Model1Factors, collapse = ', ')}")
  cli::cli_alert_info("logistic_environment_glm Model2: {paste(Model2Factors, collapse = ', ')}")

  p_thr <- as.numeric(bl_cfg$screening_p_threshold %||% 0.05)[1L]

  data2 <- .lqg11_prepare_outcome(data, outcome_col, ref_label, case_label)
  tab   <- NULL

  cli::cli_alert_info("logistic_environment_glm: 开始 {length(voc_loop)} 个 VOC 四分位 GLM")

  for (i in voc_loop) {
    cli::cli_alert_info("logistic_environment_glm: VOC = {i}")
    qs <- as.numeric(stats::quantile(data2[[i]], na.rm = TRUE))
    wg <- rep("Q", nrow(data2))
    wg[data2[[i]] < qs[2]] <- "Q1"
    wg[data2[[i]] >= qs[2] & data2[[i]] < qs[3]] <- "Q2"
    wg[data2[[i]] >= qs[3] & data2[[i]] < qs[4]] <- "Q3"
    wg[data2[[i]] >= qs[4]] <- "Q4"
    data2$NewGroup <- factor(wg, levels = c("Q1", "Q2", "Q3", "Q4"))
    data2$NewNum   <- as.numeric(data2$NewGroup)
    cutoffs <- c(
      Q1 = paste0("< ", round(qs[2], 2)),
      Q2 = paste0(round(qs[2], 2), " -< ", round(qs[3], 2)),
      Q3 = paste0(round(qs[3], 2), " -< ", round(qs[4], 2)),
      Q4 = paste0("\u2265 ", round(qs[4], 2))
    )
    m1_use <- setdiff(Model1Factors, c(i, "NewGroup", "NewNum"))
    m2_use <- setdiff(Model2Factors, c(i, "NewGroup", "NewNum"))

    tb01 <- tryCatch(
      .lqg11_Tb_ModelGroup3_OR(outcome_col, i, "NewGroup", "NewNum",
                                data2, m1_use, m2_use, cutoffs, c("Q1","Q2","Q3","Q4"), TRUE),
      error = function(e) {
        cli::cli_alert_warning("logistic_environment_glm: {i} 失败 — {e$message}")
        NULL
      }
    )
    if (is.null(tb01)) next
    rt <- .lqg11_format_p_cols(data.frame(tb01, stringsAsFactors = FALSE))
    rownames(rt) <- NULL
    tab <- if (is.null(tab)) rt else rbind(tab, rt)
  }

  if (is.null(tab) || nrow(tab) == 0L) {
    stop("logistic_environment_glm: 未产生任何有效 GLM 表行。")
  }

  select_vocs_glm <- .lqg11_screen_continuous_p(tab, p_thr)
  select_vocs_glm <- unique(select_vocs_glm[nzchar(select_vocs_glm)])
  select_vocs_final <- intersect(select_vocs, select_vocs_glm)
  if (length(select_vocs_final) == 0L || all(select_vocs_final == "")) {
    select_vocs_final <- select_vocs
    cli::cli_alert_warning("logistic_environment_glm: GLM 筛选为空，select_vocs_final 回退为全部 select_vocs")
  }

  if (length(select_vocs_glm) == 0L && .lqg11_should_pause(bl_cfg, "pause_on_empty_screen", FALSE)) {
    .lqg11_pause(ctx, "GLM continuous 行筛选后无显著 VOC",
                 "放宽 screening_p_threshold 或检查 Model2 协变量", as.data.frame(tab))
  }

  tbl_fn <- bl_cfg$table_filename %||% "Table_Environment_Logistic_GLM.xlsx"
  filepath <- file.path(ctx$output_dir_tables, tbl_fn)
  title <- bl_cfg$table_title %||% "Table. Environment exposure logistic regression (quartile GLM, stacked)"

  h1 <- as.character(tab[1, ]); h2 <- as.character(tab[2, ])
  tab_body <- tab[-c(1L, 2L), , drop = FALSE]
  rownames(tab_body) <- NULL
  colnames(tab_body) <- paste0("V", seq_len(ncol(tab_body)))

  tryCatch(
    export_sci_table(tab_body, filepath, title = title,
                     header_row1 = h1, header_row2 = h2, latex_include_colnames = FALSE),
    error = function(e) cli::cli_alert_warning("logistic_environment_glm: export 失败: {e$message}")
  )

  ctx$results$logistic_environment_table <- tab
  ctx$results$select_vocs_glm            <- select_vocs_glm
  ctx$results$select_vocs_final          <- select_vocs_final
  ctx$results$logistic_model1_factors    <- Model1Factors
  ctx$results$logistic_model2_factors    <- Model2Factors

  ctx <- save_result(ctx, "select_vocs_glm", select_vocs_glm, "select_vocs_glm.csv")
  ctx <- save_result(ctx, "select_vocs_final", select_vocs_final, "select_vocs_final.csv")
  ctx <- save_result(ctx, "logistic_environment_glm_table", tab, "logistic_environment_glm_table.csv")

  cli::cli_alert_success(
    "logistic_environment_glm 完成：GLM 显著 {length(select_vocs_glm)} / final {length(select_vocs_final)}"
  )
  ctx
}

register_block("logistic_environment_glm", block_logistic_environment_glm,
               "环境多暴露四分位 GLM 筛选（无随机搜索，无对照表；select_vocs 来自 ctx）")
