###############################################################################
#  ipw_overlap_weights — 重叠权重（overlap weights）敏感性分析（对应 Table_Sens_Overlap_Weights）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data    = ctx$data$iptw_weighted %||% ctx$data$imputed %||% ctx$data$cleaned
#  require_results = ctx$results$iptw_ps_covariates（可选；来自 34_IPTW/01block_iptw_balance）
#
#  ipw_diabetes = list(               # 与 01block_ipw_diabetes_exposure 共用
#    exposure_var = "Diabetes_HbA1c",
#    time_var     = "surv_time_28d",
#    event_var    = "surv_event_28d"
#  )
#  ipw_overlap_weights = list(
#    ps_covariates   = NULL,          # NULL → ctx$results$iptw_ps_covariates（沿用 IPTW 分母协变量）
#    use_weightit    = TRUE,          # TRUE 且 WeightIt 可用 → estimand="ATO"；否则回退 e(x)*(1-e(x))
#    table_filename  = "Table_Sens_Overlap_Weights.xlsx",  # 固定名，不占发表表序号
#    table_title     = "Sensitivity analysis: overlap-weighted Cox model for Diabetes_HbA1c and 28-day mortality",
#    pause_enable        = TRUE,
#    pause_on_fit_fail   = TRUE
#  )
#
#  register_block: "ipw_overlap_weights"
#  典型位置: iptw_balance → ... → cox_binary → ipw_overlap_weights
#
#  读: ctx$data$iptw_weighted %||% ctx$data$imputed %||% ctx$data$cleaned
#  写: ctx$results$ipw_overlap_weights（PS、重叠权重、Cox HR/CI/P）
#
#  产出: [固定名] Table_Sens_Overlap_Weights.xlsx（+ .csv）→ export_sci_table
#
#  方法: 若 WeightIt 包可用，用 WeightIt::weightit(..., method = "glm",
#  estimand = "ATO") 直接得到标准重叠权重；否则退化为对同一批协变量拟合
#  logistic PS 后取 e(x)*(1-e(x))（原文/规格给出的简化公式）。两种口径均在
#  ctx$results$ipw_overlap_weights$method 中记录，避免误认为同一算法。
#
#  pause: config$ipw_overlap_weights$pause_enable
###############################################################################

.ow04_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.ow04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "ipw_overlap_weights",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ipw_overlap_weights halted. See ctx$results$pause_point. / ",
    "重叠权重敏感性分析异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.ow04_default_ps_covariates <- function(data) {
  cand <- c(
    "Age", "Gender", "Race", "Language", "Marital_Status",
    "Hypertension", "COPD", "RDW", "Potassium", "PLT"
  )
  cand[cand %in% names(data)]
}

block_ipw_overlap_weights <- function(ctx, ...) {
  cfg <- ctx$config
  bl_cfg <- cfg$ipw_overlap_weights %||% list()
  ipw_cfg <- cfg$ipw_diabetes %||% list()

  data <- ctx$data$iptw_weighted %||% ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.ow04_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .ow04_pause(ctx, "未找到分析数据（iptw_weighted / imputed / cleaned 均为空）。",
                 "请先运行 imputation / iptw_balance。", NULL)
    }
    stop("ipw_overlap_weights: 无分析数据。", call. = FALSE)
  }

  exp_var <- as.character(ipw_cfg$exposure_var %||% cfg$iptw_balance$exposure_var %||% "Diabetes_HbA1c")[1L]
  tvar <- as.character(ipw_cfg$time_var %||% cfg$survival$time_var %||% "surv_time_28d")[1L]
  yvar <- as.character(ipw_cfg$event_var %||% cfg$survival$event_var %||% "surv_event_28d")[1L]
  if (!all(c(exp_var, tvar, yvar) %in% names(data))) {
    msg <- paste0(
      "ipw_overlap_weights: 数据缺少列: ",
      paste(setdiff(c(exp_var, tvar, yvar), names(data)), collapse = ", ")
    )
    if (.ow04_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .ow04_pause(ctx, msg, "检查 ipw_diabetes_exposure 是否已运行。", data)
    }
    stop(msg, call. = FALSE)
  }

  ps_cov <- as.character(bl_cfg$ps_covariates %||% ctx$results$iptw_ps_covariates %||% character(0))
  ps_cov <- ps_cov[nzchar(ps_cov) & ps_cov %in% names(data)]
  if (!length(ps_cov)) ps_cov <- .ow04_default_ps_covariates(data)
  if (!length(ps_cov)) {
    msg <- "ipw_overlap_weights: 倾向得分协变量池为空（config$ipw_overlap_weights$ps_covariates 或 iptw_ps_covariates 均不可用）。"
    if (.ow04_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .ow04_pause(ctx, msg, "设置 config$ipw_overlap_weights$ps_covariates。", data)
    }
    stop(msg, call. = FALSE)
  }

  keep_cols <- unique(c(exp_var, tvar, yvar, ps_cov))
  d <- data[, keep_cols, drop = FALSE]
  d[[tvar]] <- suppressWarnings(as.numeric(d[[tvar]]))
  d[[yvar]] <- suppressWarnings(as.numeric(d[[yvar]]))
  d[[exp_var]] <- suppressWarnings(as.numeric(d[[exp_var]]))
  d <- d[stats::complete.cases(d) & is.finite(d[[tvar]]) & d[[tvar]] >= 0, , drop = FALSE]
  d[[exp_var]] <- as.integer(d[[exp_var]] == 1L)

  if (!nrow(d) || length(unique(d[[exp_var]])) < 2L) {
    msg <- "ipw_overlap_weights: 有效样本不足或暴露组不足 2 个水平。"
    if (.ow04_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .ow04_pause(ctx, msg, "检查协变量完整性与暴露分布。", d)
    }
    stop(msg, call. = FALSE)
  }

  ps_formula <- stats::as.formula(paste0(exp_var, " ~ ", paste(ps_cov, collapse = " + ")))
  method_used <- "logistic_ps_e1_minus_e"
  overlap_w <- NULL

  use_weightit <- isTRUE(bl_cfg$use_weightit %||% TRUE) && requireNamespace("WeightIt", quietly = TRUE)
  if (isTRUE(use_weightit)) {
    fit_wi <- tryCatch(
      WeightIt::weightit(ps_formula, data = d, method = "glm", estimand = "ATO"),
      error = function(e) NULL
    )
    if (!is.null(fit_wi) && !is.null(fit_wi$weights) && length(fit_wi$weights) == nrow(d)) {
      overlap_w <- as.numeric(fit_wi$weights)
      method_used <- "WeightIt::weightit(method='glm', estimand='ATO')"
    }
  }

  ps_fit <- tryCatch(
    stats::glm(ps_formula, data = d, family = stats::binomial()),
    error = function(e) NULL
  )
  if (is.null(ps_fit)) {
    msg <- "ipw_overlap_weights: 倾向得分 logistic 模型拟合失败。"
    if (.ow04_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .ow04_pause(ctx, msg, "检查协变量是否共线或样本量不足。", d)
    }
    stop(msg, call. = FALSE)
  }
  ps <- stats::fitted(ps_fit)

  if (is.null(overlap_w)) {
    overlap_w <- ps * (1 - ps)
  }
  d$.ps <- ps
  d$.overlap_weight <- overlap_w

  cox_formula <- stats::as.formula(paste0("survival::Surv(", tvar, ", ", yvar, ") ~ ", exp_var))
  cox_fit <- tryCatch(
    survival::coxph(cox_formula, data = d, weights = d$.overlap_weight, robust = TRUE),
    error = function(e) NULL
  )
  if (is.null(cox_fit)) {
    msg <- "ipw_overlap_weights: 重叠权重加权 Cox 模型拟合失败。"
    if (.ow04_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .ow04_pause(ctx, msg, "检查权重是否存在极端值或 0 事件。", d)
    }
    stop(msg, call. = FALSE)
  }
  s <- summary(cox_fit)
  ci <- s$conf.int
  coefs <- s$coefficients
  p_col <- if ("Pr(>|z|)" %in% colnames(coefs)) "Pr(>|z|)" else colnames(coefs)[ncol(coefs)]
  hr <- unname(ci[1L, "exp(coef)"])
  lower <- unname(ci[1L, grep("lower", colnames(ci))[1L]])
  upper <- unname(ci[1L, grep("upper", colnames(ci))[1L]])
  pval <- unname(coefs[1L, p_col])

  hr_tab <- data.frame(
    Analysis = "Overlap-weighted Cox (sensitivity)",
    Covariates = paste(ps_cov, collapse = "; "),
    Method = method_used,
    N = cox_fit$n,
    Events = cox_fit$nevent,
    HR = hr,
    Lower95 = lower,
    Upper95 = upper,
    P = pub_format_p(pval),
    stringsAsFactors = FALSE
  )

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_Sens_Overlap_Weights.xlsx")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tbl_title <- as.character(bl_cfg$table_title %||%
    "Sensitivity analysis: overlap-weighted Cox model for Diabetes_HbA1c and 28-day mortality")[1L]
  tryCatch(
    export_sci_table(hr_tab, tbl_path, title = tbl_title),
    error = function(e) cli::cli_alert_warning("重叠权重表导出排队失败: {e$message}")
  )
  csv_path <- sub("\\.xlsx$", ".csv", tbl_path, ignore.case = TRUE)
  tryCatch(
    utils::write.csv(hr_tab, csv_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("重叠权重 CSV 写出失败: {e$message}")
  )

  ctx$results$ipw_overlap_weights <- list(
    ps_covariates = ps_cov,
    method = method_used,
    hr_table = hr_tab,
    ps_summary = summary(ps),
    overlap_weight_summary = summary(overlap_w),
    n = nrow(d)
  )
  cli::cli_alert_success(
    "ipw_overlap_weights 完成（method={method_used}, HR={round(hr, 2)}, P={pub_format_p(pval)}）"
  )
  ctx
}

register_block(
  "ipw_overlap_weights",
  block_ipw_overlap_weights,
  "重叠权重（overlap weights）敏感性分析 Cox HR"
)
