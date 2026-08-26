###############################################################################
#  logistic_subphenotype — 亚型分层（Subphenotype）四模型 Logistic OR 表（Table 2b）
#
#  register_block: "logistic_subphenotype"
#  典型流水线: lca → … → logistic_subphenotype
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#  require_ctx_results = ctx$results$df_final（含 Subphenotype 列）
#
#  # ── 配置 config$logistic_subphenotype ────────────────────────────────────
#  logistic_subphenotype = list(
#    subphenotype_col = "Subphenotype",
#    ref_class        = NULL,           # NULL / "auto" → 按院内死亡粗率选最低风险类；整数则固定参照
#    outcome_col      = NULL,           # NULL → config$data$outcome_column
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
#  结局编码: 院内死亡 = 1（"Expired"/"Non-survivor"/"1"/config$analysis_group）
#  输出: Tables/Table 2b-{db}. Logistic Subphenotype MultiModel.xlsx
#  写: ctx$results$logistic_subphenotype_table（data.frame）
###############################################################################

# ── 格式化工具（前缀 .lsm12_）────────────────────────────────────────────────

.lsm12_fmt_num <- function(x, digits = 3) {
  if (is.na(x) || is.nan(x)) return("NA")
  if (is.infinite(x))         return(if (x > 0) ">1000.000" else "<-1000.000")
  if (x > 0 && x < 0.001)    return("<0.001")
  if (abs(x) > 1000)          return(paste0(">", formatC(1000, format = "f", digits = digits)))
  formatC(x, format = "f", digits = digits)
}

.lsm12_fmt_ci <- function(lo, hi) {
  if (any(is.na(c(lo, hi)))) return("NA")
  paste0(.lsm12_fmt_num(lo), ", ", .lsm12_fmt_num(hi))
}

.lsm12_fmt_p <- function(p) {
  if (is.na(p)) return("NA")
  if (p < 0.001) return("<0.001")
  formatC(p, format = "f", digits = 3)
}

# ── 将结局列转为 0/1 ─────────────────────────────────────────────────────────
.lsm12_coerce_outcome <- function(x, analysis_group) {
  if (is.numeric(x)) {
    ux <- unique(stats::na.omit(as.numeric(x)))
    if (all(ux %in% c(0, 1))) return(as.integer(x))
    stop("logistic_subphenotype: 结局列为数值但非 0/1 编码，请先处理。")
  }
  if (is.logical(x)) return(as.integer(x))
  xc <- tolower(trimws(as.character(x)))
  dead_kw  <- c("dead","death","died","non-survivor","non_survivor",
                "expired","mortality","fatal","1")
  alive_kw <- c("alive","survivor","survive","survived","living","0")
  if (!is.null(analysis_group) && nzchar(analysis_group)) {
    dead_kw  <- c(dead_kw,  tolower(trimws(analysis_group)))
  }
  out <- ifelse(xc %in% dead_kw, 1L,
          ifelse(xc %in% alive_kw, 0L, NA_integer_))
  if (any(is.na(out) & !is.na(x) & nzchar(as.character(x)))) {
    bad_vals <- paste(unique(as.character(x)[is.na(out)]), collapse = ", ")
    stop("logistic_subphenotype: 无法将结局列映射为 0/1，未识别值: ", bad_vals,
         "。请设置 config$project$analysis_group 或先将列改为 0/1。")
  }
  out
}

# ── p for trend ──────────────────────────────────────────────────────────────
.lsm12_trend_p <- function(df, outcome_col, sub_col,
                             class_levels, covariates) {
  df$.__cls_num__ <- as.numeric(factor(df[[sub_col]], levels = class_levels))
  keep <- unique(c(outcome_col, ".__cls_num__",
                   intersect(covariates %||% character(0), names(df))))
  df   <- stats::na.omit(df[, keep, drop = FALSE])
  if (nrow(df) < 10 || length(unique(df[[outcome_col]])) < 2) return("NA")

  rhs <- ".__cls_num__"
  cov_avail <- intersect(covariates %||% character(0), names(df))
  if (length(cov_avail)) rhs <- paste(c(rhs, cov_avail), collapse = " + ")

  fml <- stats::as.formula(paste0(outcome_col, " ~ ", rhs))
  fit <- tryCatch(
    stats::glm(fml, data = df, family = binomial()),
    error = function(e) NULL)
  if (is.null(fit)) return("NA")
  sm <- summary(fit)$coefficients
  if (!".__cls_num__" %in% rownames(sm)) return("NA")
  .lsm12_fmt_p(sm[".__cls_num__", "Pr(>|z|)"])
}

# ── 主 block ─────────────────────────────────────────────────────────────────
block_logistic_subphenotype <- function(ctx, ...) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b

  cfg    <- ctx$config
  bl_cfg <- cfg$logistic_subphenotype %||% list()

  # ── 数据 + 合并亚型列 ────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data))
    stop("logistic_subphenotype: 未找到数据，请先运行 imputation。")

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
    stop("logistic_subphenotype: '", sub_col, "' 列不在数据中，请先运行 lca block。")

  # ── 结局变量 ─────────────────────────────────────────────────────────────
  outcome_col    <- bl_cfg$outcome_col %||% cfg$data$outcome_column %||% "in-hospital mortality"
  analysis_group <- cfg$project$analysis_group %||% NULL
  if (!outcome_col %in% names(data))
    stop("logistic_subphenotype: 结局列 '", outcome_col, "' 不在数据中。")

  # 转 0/1（不在数据列里改名，使用临时列）
  data$.outcome_01 <- tryCatch(
    .lsm12_coerce_outcome(data[[outcome_col]], analysis_group),
    error = function(e) stop(e$message)
  )
  outcome_col_use <- ".outcome_01"

  n_event <- sum(data$.outcome_01 == 1, na.rm = TRUE)
  cli::cli_alert_info(
    "logistic_subphenotype: 结局='{outcome_col}'，事件数={n_event}/{nrow(data)}")

  if (n_event < 5 || (nrow(data) - n_event) < 5)
    stop("logistic_subphenotype: 事件数或非事件数不足 5，无法拟合。")

  # ── 亚型水平 + 参照组（默认：院内死亡粗率最低者）────────────────────────
  raw_ints     <- sort(unique(as.integer(stats::na.omit(data[[sub_col]]))))
  class_levels <- as.character(raw_ints)
  if (length(class_levels) < 2) stop("logistic_subphenotype: 亚型水平不足 2。")
  ref_class <- pipeline_resolve_subphenotype_ref_class(
    bl_cfg, data, sub_col, class_levels, data$.outcome_01,
    block_label = "logistic_subphenotype"
  )
  cli::cli_alert_info(
    "logistic_subphenotype: k={length(class_levels)} 类，参照 = Class {ref_class}")

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
  .fit_logit <- function(covariates) {
    df <- data
    df[[sub_col]] <- factor(df[[sub_col]], levels = class_levels)
    df[[sub_col]] <- relevel(df[[sub_col]], ref = ref_class)
    cov_ok <- intersect(covariates %||% character(0), names(df))
    keep   <- unique(c(outcome_col_use, sub_col, cov_ok))
    df     <- stats::na.omit(df[, keep, drop = FALSE])
    if (nrow(df) < 10 || length(unique(df[[outcome_col_use]])) < 2) return(NULL)

    rhs <- sub_col
    if (length(cov_ok)) rhs <- paste(c(rhs, cov_ok), collapse = " + ")
    fml <- stats::as.formula(paste0(outcome_col_use, " ~ ", rhs))
    tryCatch(
      stats::glm(fml, data = df, family = binomial()),
      error = function(e) {
        cli::cli_alert_warning("  拟合失败: {e$message}"); NULL })
  }

  .extract_one <- function(fit, cls) {
    blank <- c(or = "NA", ci = "NA", p = "NA")
    ref_r <- c(or = "Ref", ci = "",  p = "")
    if (cls == ref_class) return(ref_r)
    if (is.null(fit)) return(blank)

    sm <- summary(fit)$coefficients
    rn <- rownames(sm)[grep(paste0(cls, "$"), rownames(sm))]
    if (!length(rn)) return(blank)
    rn <- rn[1]

    beta <- sm[rn, "Estimate"]; se <- sm[rn, "Std. Error"]
    pval <- sm[rn, "Pr(>|z|)"]
    or   <- exp(beta)
    ci_m <- tryCatch(suppressMessages(confint(fit)), error = function(e) NULL)
    lo   <- if (!is.null(ci_m) && rn %in% rownames(ci_m)) exp(ci_m[rn, 1]) else exp(beta - 1.96*se)
    hi   <- if (!is.null(ci_m) && rn %in% rownames(ci_m)) exp(ci_m[rn, 2]) else exp(beta + 1.96*se)
    c(or = .lsm12_fmt_num(or), ci = .lsm12_fmt_ci(lo, hi), p = .lsm12_fmt_p(pval))
  }

  # ── 逐模型拟合 ───────────────────────────────────────────────────────────
  fits <- lapply(model_sets, function(covs) .fit_logit(covs))

  # ── 构建输出 data.frame ──────────────────────────────────────────────────
  rows <- lapply(class_levels, function(cls) {
    lbl  <- if (cls == ref_class) paste0("Class ", cls, " (Ref)") else paste0("Class ", cls)
    vals <- lbl
    for (mn in model_names) vals <- c(vals, .extract_one(fits[[mn]], cls))
    unname(vals)
  })

  # p for trend 行
  trend_row <- c("p for trend")
  for (mn in model_names) {
    covs <- intersect(model_sets[[mn]] %||% character(0), names(data))
    tp   <- .lsm12_trend_p(data, outcome_col_use, sub_col, class_levels, covs)
    trend_row <- c(trend_row, "", "", tp)
  }
  rows[[length(rows) + 1]] <- trend_row

  out_df <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  colnames(out_df) <- c("Characteristic",
                        as.vector(outer(model_names, c("_OR","_CI","_P"), paste0)))

  cli::cli_alert_success("logistic_subphenotype: 表格构建完成（{nrow(out_df)} 行）")

  # ── 导出 ─────────────────────────────────────────────────────────────────
  ctx$results$logistic_subphenotype_table <- out_df
  ctx <- save_result(ctx, "logistic_subphenotype_table", out_df,
                     "Table_Logistic_Subphenotype_MultiModel.csv")

  db_name   <- cfg$project$database %||% ""
  tbl_title <- paste0("Table 2b-", db_name,
                      ". Logistic: Subphenotype vs In-hospital Mortality")
  tbl_fname <- bl_cfg$table_filename %||%
    file.path(ctx$output_dir_tables %||% ctx$output_dir,
              paste0("Table 2b-", db_name, ". Logistic Subphenotype MultiModel"))

  h1_vec <- c("Characteristic")
  for (mn in model_names) h1_vec <- c(h1_vec, mn, "", "")
  h2_vec <- c("Characteristic")
  for (mn in model_names) h2_vec <- c(h2_vec, "OR", "95% CI", "P-value")

  tryCatch(
    export_sci_table(out_df, filepath = tbl_fname, title = tbl_title,
                     header_row1 = h1_vec, header_row2 = h2_vec),
    error = function(e)
      cli::cli_alert_warning("logistic_subphenotype: export_sci_table 失败: {e$message}")
  )

  cli::cli_alert_success("logistic_subphenotype block 完成。")
  ctx
}

register_block("logistic_subphenotype", block_logistic_subphenotype,
               description = "四模型 Logistic OR 表（亚型分层，可配参照组与协变量集）")
