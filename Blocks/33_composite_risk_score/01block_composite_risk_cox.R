###############################################################################
#  composite_risk_cox — Cox 拟合 + 线性预测值 (LP) 作为综合风险分
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$cleaned
#  require_study  = config$project$study_type == "prognosis"
#  require_config = config$survival（time_var / event_var / event_value 必填）
#                   config$composite_risk_cox
#
#  预测变量（二选一，由 pipeline / config 决定，块内不绑定具体上游块）:
#    - config$composite_risk_cox$predictor_vars   非空字符向量
#    - ctx$results$composite_risk_predictors      上游块或 run 脚本写入
#  示例（仅文档，非默认）: feature_selection_lasso → 写入 predictors；
#                         multicollinearity → Model2Factors 映射到该槽位；
#                         或在 config 中直接列出 predictor_vars。
#
#  composite_risk_cox = list(
#    predictor_vars     = NULL,              # 非 NULL 时优先；NULL → ctx$composite_risk_predictors
#    score_var          = "composite_risk",  # 写入 data 的列名；下游 survival$index_var 由项目 config 对齐
#    table_caption      = NULL,              # NULL → 自动生成补充表 caption
#    csv_filename       = "Cox_Model_Results.csv",
#    data_rdata_name    = "D01_Composite_Risk_Index.RData",  # NULL 则不另存 RData
#    pause_enable       = TRUE,
#    pause_on_no_predictors = TRUE,
#    pause_on_fit_fail  = TRUE
#  ),
#
#  产出:
#    - [supp_table] Table Sn.* Cox 系数表
#    - [固定名]     Cox_Model_Results.csv（可 config 覆盖）
#    - [固定名]     D01_Composite_Risk_Index.RData（可选）
#
#  写: ctx$data$imputed（追加 score_var）
#      ctx$results$composite_risk_cox_model, composite_risk_cox_coef_table,
#      composite_risk_score_var, composite_risk_predictors（实际使用的变量名）
#
#  register_block: "composite_risk_cox"
###############################################################################

.crc01_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crc01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "composite_risk_cox",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: composite_risk_cox — ", reason,
    " | See ctx$results$pause_point.",
    call. = FALSE
  )
}

.crc01_coerce_event01 <- function(x, event_value) {
  if (is.logical(x)) return(as.integer(x))
  if (is.numeric(x) || is.integer(x)) {
    return(suppressWarnings(as.integer(x == event_value)))
  }
  if (is.factor(x)) {
    lab <- tolower(trimws(as.character(x)))
    ev_chr <- tolower(trimws(as.character(event_value)))
    v <- rep(0L, length(lab))
    if (nzchar(ev_chr)) v[lab == ev_chr] <- 1L
    v[grepl("^(yes|y|1|recurrence|是|复发)", lab, perl = TRUE)] <- 1L
    return(v)
  }
  xc <- tolower(trimws(as.character(x)))
  ev_chr <- tolower(trimws(as.character(event_value)))
  v <- rep(0L, length(xc))
  if (nzchar(ev_chr)) v[xc == ev_chr] <- 1L
  v[xc %in% c("1", "yes", "y", "recurrence", "true", "t", "是", "复发")] <- 1L
  v[grepl("^yes", xc, perl = TRUE)] <- 1L
  v
}

.crc01_backtick_vars <- function(vars) {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[nzchar(vars)]
  vapply(vars, function(v) {
    if (grepl("^[A-Za-z.][A-Za-z0-9._]*$", v)) v else paste0("`", v, "`")
  }, character(1L), USE.NAMES = FALSE)
}

.crc01_resolve_predictors <- function(bl_cfg, ctx) {
  cfg_vars <- bl_cfg$predictor_vars
  if (!is.null(cfg_vars) && length(cfg_vars)) {
    return(unique(as.character(cfg_vars)[nzchar(as.character(cfg_vars))]))
  }
  ctx_vars <- ctx$results$composite_risk_predictors
  if (!is.null(ctx_vars) && length(ctx_vars)) {
    return(unique(as.character(ctx_vars)[nzchar(as.character(ctx_vars))]))
  }
  character(0)
}

.crc01_tidy_cox_table <- function(cox_model) {
  if (requireNamespace("broom", quietly = TRUE)) {
    return(
      broom::tidy(cox_model, exponentiate = FALSE, conf.int = TRUE) |>
        dplyr::mutate(
          HR = exp(.data$estimate),
          conf.low = exp(.data$conf.low),
          conf.high = exp(.data$conf.high),
          `Hazard Ratio (95% CI)` = sprintf(
            "%.2f (%.2f to %.2f)", .data$HR, .data$conf.low, .data$conf.high
          )
        ) |>
        dplyr::select(
          Characteristic = .data$term,
          `Parameter Estimate` = .data$estimate,
          SE = .data$std.error,
          `Hazard Ratio (95% CI)`,
          `P value` = .data$p.value
        )
    )
  }
  s <- summary(cox_model)
  cf <- as.data.frame(s$coefficients, stringsAsFactors = FALSE)
  ci <- as.data.frame(s$conf.int, stringsAsFactors = FALSE)
  data.frame(
    Characteristic = rownames(cf),
    `Parameter Estimate` = cf[, "coef"],
    SE = cf[, "se(coef)"],
    `Hazard Ratio (95% CI)` = sprintf(
      "%.2f (%.2f to %.2f)", ci[, "exp(coef)"], ci[, "lower .95"], ci[, "upper .95"]
    ),
    `P value` = cf[, "Pr(>|z|)"],
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

block_composite_risk_cox <- function(ctx, ...) {
  cfg <- ctx$config
  bl_cfg <- cfg$composite_risk_cox %||% list()
  surv_cfg <- cfg$survival %||% list()

  time_var <- as.character(surv_cfg$time_var)[1L]
  event_var <- as.character(surv_cfg$event_var)[1L]
  event_value <- surv_cfg$event_value
  if (is.null(event_value)) event_value <- 1L

  if (!nzchar(time_var) || !nzchar(event_var)) {
    stop("composite_risk_cox: config$survival$time_var / event_var 必填。", call. = FALSE)
  }

  score_var <- as.character(bl_cfg$score_var %||% "composite_risk")[1L]
  if (!nzchar(score_var)) score_var <- "composite_risk"

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.crc01_should_pause(bl_cfg, "pause_on_no_data", TRUE)) {
      .crc01_pause(ctx, "缺少分析数据", "请先运行 imputation 或 data_clean")
    }
    stop("composite_risk_cox: 无可用 data.frame。", call. = FALSE)
  }

  predictors <- .crc01_resolve_predictors(bl_cfg, ctx)
  predictors <- intersect(predictors, names(data))

  if (!length(predictors)) {
    if (.crc01_should_pause(bl_cfg, "pause_on_no_predictors", TRUE)) {
      .crc01_pause(
        ctx,
        "预测变量为空或均不在数据中",
        paste0(
          "在 config$composite_risk_cox$predictor_vars 中指定变量，",
          "或由上游写入 ctx$results$composite_risk_predictors"
        )
      )
    }
    stop("composite_risk_cox: 无可用预测变量。", call. = FALSE)
  }

  if (!all(c(time_var, event_var) %in% names(data))) {
    stop(
      "composite_risk_cox: 缺少结局列 ",
      paste(setdiff(c(time_var, event_var), names(data)), collapse = ", "),
      call. = FALSE
    )
  }

  if (!requireNamespace("survival", quietly = TRUE)) {
    stop("composite_risk_cox: 需要 survival 包。", call. = FALSE)
  }
  suppressPackageStartupMessages(library(survival))

  data2 <- data
  data2$.crc01_event01 <- .crc01_coerce_event01(data2[[event_var]], event_value)
  if (all(is.na(data2$.crc01_event01))) {
    stop("composite_risk_cox: 结局列无法转换为 0/1 事件。", call. = FALSE)
  }

  rhs <- paste(.crc01_backtick_vars(predictors), collapse = " + ")
  fml <- stats::as.formula(
    paste0("Surv(", time_var, ", .crc01_event01) ~ ", rhs)
  )

  keep_cols <- unique(c(time_var, event_var, predictors, ".crc01_event01"))
  fit_df <- stats::na.omit(data2[, keep_cols, drop = FALSE])
  if (nrow(fit_df) < 10L) {
    if (.crc01_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .crc01_pause(ctx, "完整病例数过少", "检查预测变量与结局缺失", utils::head(fit_df, 5L))
    }
    stop("composite_risk_cox: 完整病例 < 10。", call. = FALSE)
  }

  cox_model <- tryCatch(
    survival::coxph(fml, data = fit_df, x = TRUE, y = TRUE),
    error = function(e) {
      if (.crc01_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
        .crc01_pause(ctx, paste0("Cox 拟合失败: ", conditionMessage(e)), "检查共线或样本量")
      }
      stop("composite_risk_cox: ", conditionMessage(e), call. = FALSE)
    }
  )

  res_table <- .crc01_tidy_cox_table(cox_model)

  lp <- stats::predict(cox_model, newdata = data2, type = "lp")
  data2[[score_var]] <- as.numeric(lp)
  data2$.crc01_event01 <- NULL

  ctx$data$imputed <- data2

  ctx$results$composite_risk_cox_model <- cox_model
  ctx$results$composite_risk_cox_coef_table <- res_table
  ctx$results$composite_risk_score_var <- score_var
  ctx$results$composite_risk_predictors <- predictors

  disease <- cfg$project$disease %||% "Outcome"
  cap <- bl_cfg$table_caption %||%
    paste0("Cox Proportional Hazards Model (composite score, ", disease, ")")
  pub <- pub_pair(
    ctx, ctx$output_dir_tables, "supp_table",
    cap, "Cox Proportional Hazards Model", "xlsx"
  )
  tryCatch(
    export_sci_table(res_table, pub$filepath, title = pub$title),
    error = function(e) cli::cli_alert_warning("composite_risk_cox: 表导出失败: {e$message}")
  )

  csv_fn <- bl_cfg$csv_filename %||% "Cox_Model_Results.csv"
  ctx <- save_result(ctx, "composite_risk_cox_coef_csv", res_table, csv_fn)

  rdata_fn <- bl_cfg$data_rdata_name %||% "D01_Composite_Risk_Index.RData"
  if (!is.null(rdata_fn) && nzchar(as.character(rdata_fn)[1L])) {
    ctx <- save_result(ctx, "composite_risk_data_export", data2, as.character(rdata_fn)[1L])
  }

  cli::cli_alert_success(
    "composite_risk_cox: 已写入 {score_var}（n={nrow(data2)}, predictors={length(predictors)}）"
  )
  ctx
}

register_block(
  "composite_risk_cox",
  block_composite_risk_cox,
  "Cox LP 综合风险分（predictor_vars 或 ctx$composite_risk_predictors）"
)
