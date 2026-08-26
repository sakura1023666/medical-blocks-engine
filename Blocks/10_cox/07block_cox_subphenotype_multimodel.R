###############################################################################
#  cox_subphenotype — 亚型分层（Subphenotype）四模型 Cox HR 表（Table 2a）
#
#  register_block: "cox_subphenotype"
#  典型流水线: lca → … → cox_subphenotype
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = ctx$results$df_final（含 Subphenotype 列）
#
#  # ── 配置 config$cox_subphenotype ─────────────────────────────────────────
#  cox_subphenotype = list(
#    subphenotype_col = "Subphenotype",
#    ref_class        = NULL,           # NULL / "auto" → 按本 block 结局粗事件率选最低风险类；整数则固定参照
#    time_var         = NULL,           # NULL → config$survival$time_var
#    event_var        = NULL,           # NULL → config$survival$event_var
#    model_sets       = list(
#      Crude  = NULL,
#      Model2 = c("Age"),
#      Model3 = c("Age", "BMI"),
#      Model4 = c("Age", "BMI", "BUN", "HR", "Temperature")
#    ),
#    table_filename   = NULL,           # NULL → 自动命名
#    pause_enable     = FALSE
#  ),
#
#  输出: Tables/Table 2a-{db}. Cox Subphenotype MultiModel.xlsx
#  写: ctx$results$cox_subphenotype_table（data.frame）
###############################################################################

# ── 格式化工具（前缀 .csm07_）────────────────────────────────────────────────

.csm07_fmt_num <- function(x, digits = 3) {
  if (is.na(x) || is.nan(x)) return("NA")
  if (is.infinite(x))         return(if (x > 0) ">1000.000" else "<-1000.000")
  if (x > 0 && x < 0.001)    return("<0.001")
  if (abs(x) > 1000)          return(paste0(">", formatC(1000, format = "f", digits = digits)))
  formatC(x, format = "f", digits = digits)
}

.csm07_fmt_ci <- function(lo, hi) {
  if (any(is.na(c(lo, hi)))) return("NA")
  paste0(.csm07_fmt_num(lo), ", ", .csm07_fmt_num(hi))
}

.csm07_fmt_p <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 0.001) return("<0.001")
  formatC(p, format = "f", digits = 3)
}

# ── p for trend（亚型作连续数值）────────────────────────────────────────────
.csm07_trend_p <- function(df, time_var, event_var, sub_col,
                            class_levels, covariates) {
  df$.__cls_num__ <- as.numeric(factor(df[[sub_col]], levels = class_levels))
  keep <- unique(c(time_var, event_var, ".__cls_num__",
                   intersect(covariates %||% character(0), names(df))))
  df   <- stats::na.omit(df[, keep, drop = FALSE])
  if (nrow(df) < 10 || length(unique(stats::na.omit(df[[event_var]]))) < 2) return("NA")

  rhs <- ".__cls_num__"
  cov_avail <- intersect(covariates %||% character(0), names(df))
  if (length(cov_avail)) rhs <- paste(c(rhs, cov_avail), collapse = " + ")

  fml <- stats::as.formula(
    paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", rhs))
  fit <- tryCatch(survival::coxph(fml, data = df), error = function(e) NULL)
  if (is.null(fit)) return("NA")
  sm <- summary(fit)$coefficients
  if (!".__cls_num__" %in% rownames(sm)) return("NA")
  .csm07_fmt_p(sm[".__cls_num__", "Pr(>|z|)"])
}

# ── 主 block ─────────────────────────────────────────────────────────────────
block_cox_subphenotype <- function(ctx, ...) {
  suppressPackageStartupMessages(library(survival))
  `%||%` <- function(a, b) if (!is.null(a)) a else b

  cfg    <- ctx$config
  bl_cfg <- cfg$cox_subphenotype %||% list()

  # ── 数据 + 合并亚型列 ────────────────────────────────────────────────────
  data    <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    stop("cox_subphenotype: 未找到数据，请先运行 imputation。")

  sub_col <- bl_cfg$subphenotype_col %||% "Subphenotype"
  df_lca  <- ctx$results$df_final

  if (!sub_col %in% names(data) &&
      !is.null(df_lca) && is.data.frame(df_lca) && sub_col %in% names(df_lca)) {
    extra <- setdiff(names(df_lca), names(data))
    rn_d  <- rownames(data); rn_l <- rownames(df_lca)
    if (length(intersect(rn_d, rn_l)) > 0) {
      data <- merge(data, df_lca[, extra, drop = FALSE],
                    by = "row.names", all.x = TRUE)
      rownames(data) <- data$Row.names; data$Row.names <- NULL
    } else if (nrow(df_lca) == nrow(data)) {
      data <- cbind(data, df_lca[, extra, drop = FALSE])
    }
  }
  if (!sub_col %in% names(data))
    stop("cox_subphenotype: '", sub_col, "' 列不在数据中，请先运行 lca block。")

  # ── 生存变量 ─────────────────────────────────────────────────────────────
  surv_cfg  <- cfg$survival %||% list()
  time_var  <- bl_cfg$time_var  %||% surv_cfg$time_var  %||% "survival_time_28d"
  event_var <- bl_cfg$event_var %||% surv_cfg$event_var %||% "survival_28d"
  for (v in c(time_var, event_var)) {
    if (!v %in% names(data)) stop("cox_subphenotype: 变量 '", v, "' 不在数据中。")
  }
  # 事件列 → 0/1
  ev <- data[[event_var]]
  if (!is.numeric(ev)) {
    dead_kw  <- c("dead","death","died","non-survivor","non_survivor","expired","1")
    alive_kw <- c("alive","survivor","survived","0")
    evc  <- tolower(trimws(as.character(ev)))
    data[[event_var]] <- ifelse(evc %in% dead_kw, 1L,
                          ifelse(evc %in% alive_kw, 0L,
                                 suppressWarnings(as.integer(as.numeric(evc)))))
    cli::cli_alert_info("cox_subphenotype: 已将 {event_var} 转换为 0/1")
  }
  data[[time_var]]  <- as.numeric(data[[time_var]])
  data[[event_var]] <- as.numeric(data[[event_var]])

  # ── 亚型水平 + 参照组（默认：本 block 结局粗事件率最低者）────────────────
  raw_ints     <- sort(unique(as.integer(stats::na.omit(data[[sub_col]]))))
  class_levels <- as.character(raw_ints)
  if (length(class_levels) < 2) stop("cox_subphenotype: 亚型水平不足 2。")
  ref_class <- pipeline_resolve_subphenotype_ref_class(
    bl_cfg, data, sub_col, class_levels, data[[event_var]],
    block_label = "cox_subphenotype"
  )
  cli::cli_alert_info(
    "cox_subphenotype: k={length(class_levels)} 类，参照 = Class {ref_class}")

  # ── 模型集合 ─────────────────────────────────────────────────────────────
  default_sets <- list(
    Crude  = NULL,
    Model2 = c("Age"),
    Model3 = c("Age", "BMI"),
    Model4 = c("Age", "BMI", "BUN", "HR", "Temperature")
  )
  model_sets  <- bl_cfg$model_sets %||% default_sets
  model_names <- names(model_sets)

  # ── 内层：单次拟合 + 提取 ────────────────────────────────────────────────
  .fit_cox <- function(covariates) {
    df <- data
    df[[sub_col]] <- factor(df[[sub_col]], levels = class_levels)
    df[[sub_col]] <- relevel(df[[sub_col]], ref = ref_class)
    cov_ok <- intersect(covariates %||% character(0), names(df))
    keep   <- unique(c(time_var, event_var, sub_col, cov_ok))
    df     <- stats::na.omit(df[, keep, drop = FALSE])
    if (nrow(df) < 10 || length(unique(stats::na.omit(df[[event_var]]))) < 2) return(NULL)

    rhs <- sub_col
    if (length(cov_ok)) rhs <- paste(c(rhs, cov_ok), collapse = " + ")
    fml <- stats::as.formula(
      paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", rhs))
    tryCatch(survival::coxph(fml, data = df),
             error = function(e) {
               cli::cli_alert_warning("  拟合失败: {e$message}"); NULL })
  }

  .extract_one <- function(fit, cls) {
    blank <- c(hr = "NA", ci = "NA", p = "NA")
    ref_r <- c(hr = "Ref", ci = "",  p = "")
    if (cls == ref_class) return(ref_r)
    if (is.null(fit)) return(blank)

    sm <- summary(fit)$coefficients
    # 匹配行名：如 "SubphenotypeN" 末尾数字 == cls
    rn <- rownames(sm)[grep(paste0(cls, "$"), rownames(sm))]
    if (!length(rn)) return(blank)
    rn <- rn[1]

    beta <- sm[rn, "coef"];      se <- sm[rn, "se(coef)"]
    pval <- sm[rn, "Pr(>|z|)"]
    hr   <- exp(beta)
    ci_m <- tryCatch(suppressMessages(confint(fit)), error = function(e) NULL)
    lo   <- if (!is.null(ci_m) && rn %in% rownames(ci_m)) exp(ci_m[rn, 1]) else exp(beta - 1.96*se)
    hi   <- if (!is.null(ci_m) && rn %in% rownames(ci_m)) exp(ci_m[rn, 2]) else exp(beta + 1.96*se)
    c(hr = .csm07_fmt_num(hr), ci = .csm07_fmt_ci(lo, hi), p = .csm07_fmt_p(pval))
  }

  # ── 逐模型拟合 ───────────────────────────────────────────────────────────
  fits <- lapply(model_sets, function(covs) .fit_cox(covs))

  # ── 构建输出 data.frame ──────────────────────────────────────────────────
  rows <- lapply(class_levels, function(cls) {
    lbl <- if (cls == ref_class) paste0("Class ", cls, " (Ref)") else paste0("Class ", cls)
    vals <- lbl
    for (mn in model_names) vals <- c(vals, .extract_one(fits[[mn]], cls))
    unname(vals)
  })

  # p for trend 行
  trend_row <- c("p for trend")
  for (mn in model_names) {
    covs <- intersect(model_sets[[mn]] %||% character(0), names(data))
    tp   <- .csm07_trend_p(data, time_var, event_var, sub_col, class_levels, covs)
    trend_row <- c(trend_row, "", "", tp)
  }
  rows[[length(rows) + 1]] <- trend_row

  out_df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  colnames(out_df) <- c("Characteristic",
                        as.vector(outer(model_names, c("_HR","_CI","_P"), paste0)))

  cli::cli_alert_success("cox_subphenotype: 表格构建完成（{nrow(out_df)} 行）")

  # ── 导出 ─────────────────────────────────────────────────────────────────
  ctx$results$cox_subphenotype_table <- out_df
  ctx <- save_result(ctx, "cox_subphenotype_table", out_df,
                     "Table_Cox_Subphenotype_MultiModel.csv")

  db_name   <- cfg$project$database %||% ""
  tbl_title <- paste0("Table 2a-", db_name,
                      ". Cox: Subphenotype vs 28-day mortality")
  tbl_fname <- bl_cfg$table_filename %||%
    file.path(ctx$output_dir_tables %||% ctx$output_dir,
              paste0("Table 2a-", db_name, ". Cox Subphenotype MultiModel"))

  h1_vec <- c("Characteristic")
  for (mn in model_names) h1_vec <- c(h1_vec, mn, "", "")
  h2_vec <- c("Characteristic")
  for (mn in model_names) h2_vec <- c(h2_vec, "HR", "95% CI", "P-value")

  tryCatch(
    export_sci_table(out_df, filepath = tbl_fname, title = tbl_title,
                     header_row1 = h1_vec, header_row2 = h2_vec),
    error = function(e)
      cli::cli_alert_warning("cox_subphenotype: export_sci_table 失败: {e$message}")
  )

  cli::cli_alert_success("cox_subphenotype block 完成。")
  ctx
}

register_block("cox_subphenotype", block_cox_subphenotype,
               description = "四模型 Cox HR 表（亚型分层，可配参照组与协变量集）")
