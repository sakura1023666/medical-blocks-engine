###############################################################################
#  ipw_jin_composite_risk — Jin 式 STEPP 横轴：预后 Cox 线性预测值
#
#  对齐 Jin 2026：用一组预后因子拟合 Cox，composite_risk = LP（不含暴露）。
#  方案 C：因子默认 = VIF 后 Model2Factors（± Model1）。
#
#  ipw_jin_composite_risk = list(
#    factors = "from_model2",          # 或字符向量
#    exclude_vars = c("Diabetes_HbA1c"),
#    time_var = "surv_time_28d",
#    event_var = "surv_event_28d",
#    out_var = "composite_risk",
#    table_caption = "Definition of the composite risk",
#    pause_enable = FALSE
#  )
###############################################################################

block_ipw_jin_composite_risk <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$ipw_jin_composite_risk %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    stop("ipw_jin_composite_risk: 无 imputed/cleaned 数据", call. = FALSE)
  }

  time_var  <- as.character(bl$time_var %||% cfg$survival$time_var %||% "surv_time_28d")[1L]
  event_var <- as.character(bl$event_var %||% cfg$survival$event_var %||% "surv_event_28d")[1L]
  out_var   <- as.character(bl$out_var %||% "composite_risk")[1L]
  if (!all(c(time_var, event_var) %in% names(data))) {
    stop("ipw_jin_composite_risk: 缺少时间/事件列", call. = FALSE)
  }

  fac_spec <- bl$factors %||% "from_model2"
  if (is.character(fac_spec) && length(fac_spec) == 1L &&
      tolower(fac_spec) %in% c("from_model2", "from_vif")) {
    covars <- unique(c(
      as.character(ctx$results$Model1Factors %||% character(0)),
      as.character(ctx$results$Model2Factors %||% character(0))
    ))
  } else {
    covars <- as.character(fac_spec)
  }
  excl <- unique(c(
    as.character(bl$exclude_vars %||% character(0)),
    as.character(cfg$iptw_balance$exposure_var %||% "Diabetes_HbA1c"),
    "Diabetes_HbA1c", "HbA1c", "T1DM", "T2DM", "Diabetes",
    time_var, event_var, out_var,
    "ID", "subject_id", "weight"
  ))
  covars <- setdiff(covars[nzchar(covars)], excl)
  covars <- covars[covars %in% names(data)]
  if (length(covars) < 2L) {
    stop(
      "ipw_jin_composite_risk: 有效预后因子 < 2（当前: ",
      paste(covars, collapse = ", "),
      "）。请检查 univariate → VIF。",
      call. = FALSE
    )
  }

  d <- data
  d$.time <- suppressWarnings(as.numeric(d[[time_var]]))
  d$.event01 <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) == 1L)
  ok <- is.finite(d$.time) & d$.time > 0 & !is.na(d$.event01)
  d <- d[ok, , drop = FALSE]
  if (!nrow(d)) stop("ipw_jin_composite_risk: 无有效随访行", call. = FALSE)

  # 因子完整病例用于拟合；预测回写全表（缺失因子 → NA risk）
  fml <- stats::as.formula(
    paste("survival::Surv(.time, .event01) ~", paste(covars, collapse = " + "))
  )
  fit <- tryCatch(survival::coxph(fml, data = d, model = TRUE, x = TRUE), error = function(e) e)
  if (inherits(fit, "error")) {
    stop("ipw_jin_composite_risk: Cox 拟合失败: ", conditionMessage(fit), call. = FALSE)
  }

  lp_fit <- as.numeric(stats::predict(fit, type = "lp"))
  # 对全数据预测（与拟合列对齐）
  lp_all <- tryCatch(
    as.numeric(stats::predict(fit, newdata = data, type = "lp")),
    error = function(e) {
      # newdata 因子水平问题时回退：仅写拟合行
      out <- rep(NA_real_, nrow(data))
      out[which(ok)] <- lp_fit
      out
    }
  )
  data[[out_var]] <- lp_all
  if (!is.null(ctx$data$imputed)) ctx$data$imputed <- data
  if (!is.null(ctx$data$cleaned)) {
    ctx$data$cleaned[[out_var]] <- lp_all
    # 若 cleaned 行数不同则跳过整表替换
    if (nrow(ctx$data$cleaned) == nrow(data)) ctx$data$cleaned <- data
  }

  coef_tab <- as.data.frame(summary(fit)$coefficients, stringsAsFactors = FALSE)
  coef_tab$term <- rownames(coef_tab)
  rownames(coef_tab) <- NULL
  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- file.path(out_dir, "Table_S1_STEPP_CompositeRisk_Definition.csv")
  utils::write.csv(coef_tab, csv_path, row.names = FALSE)

  # 发表表（若 pub 工具可用）
  if (exists("pub_save_table", mode = "function")) {
    tryCatch(
      pub_save_table(
        coef_tab,
        ctx = ctx,
        role = "supp_table",
        caption = as.character(bl$table_caption %||% "Definition of the composite risk")[1L],
        filename_stem = "Table_S1_STEPP_CompositeRisk_Definition"
      ),
      error = function(e) cli::cli_alert_warning("pub_save_table: {e$message}")
    )
  }

  ctx$results$ipw_jin_composite_risk <- list(
    n_fit = nrow(d),
    covars = covars,
    out_var = out_var,
    median_risk = stats::median(lp_fit, na.rm = TRUE),
    csv = csv_path
  )
  cli::cli_alert_success(
    "ipw_jin_composite_risk: {out_var} 已生成（拟合 n={nrow(d)}, 因子={length(covars)}）"
  )
  ctx
}

register_block(
  "ipw_jin_composite_risk",
  block_ipw_jin_composite_risk,
  "Jin-style Cox LP composite risk for STEPP x-axis"
)
