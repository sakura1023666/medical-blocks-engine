###############################################################################
#  remove_outliers — 基于 Q10/Q90 + 1.5×IQR 的异常值行移除
#
#  register_block: "remove_outliers"
#  典型流水线: imputation / process_environment_data → remove_outliers → 分析 block
#
#  算法（针对每个指定列）：
#    1. 计算第 low_prob 和第 high_prob 百分位数（默认 Q10 / Q90）
#    2. 异常上下界 = 分位数 ± iqr_factor × IQR（默认 1.5×IQR）
#    3. 目标列超出 [下界, 上界] 的行整行移除
#    4. 目标列本身为 NA 的行**保留**（不视为异常值）
#    5. 其他列已有的 NA 不受影响（原 Remove_outliers.R v1 用 na.omit 会意外删除这些行）
#
#  # ── 版本对比说明 ──────────────────────────────────────────────────────────
#  Remove_outliers.R (v1) 的两处 bug（已在此 block 修复）：
#    Bug 1: df[,Num] 使用位置/字符串索引，数值索引时可能误操作；
#           修复: 统一使用 df[[col]] 安全取列
#    Bug 2: 将异常值设为 NA 后用 na.omit(df) 删行，会把其他列本来有 NA 的行也一并删除；
#           修复: 直接计算有效行索引（valid_rows），只移除目标列越界的行
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data[[data_slot]]（优先 imputed，回退 cleaned）
#
#  # ── 配置 config$remove_outliers ──────────────────────────────────────────
#  remove_outliers = list(
#    cols       = NULL,       # 要处理的列名向量；NULL = 自动选取所有数值列
#    data_slot  = "imputed",  # 处理哪个数据槽："imputed" 或 "cleaned"
#    low_prob   = 0.1,        # 下分位概率（默认 Q10）
#    high_prob  = 0.9,        # 上分位概率（默认 Q90）
#    iqr_factor = 1.5         # IQR 倍数
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data[[data_slot]] — 移除异常值行后的数据（原槽就地替换）
###############################################################################

# ── 独立工具函数（可在 Block 流水线外直接调用）──────────────────────────────
#
#  用法示例:
#    df_clean <- remove_outliers_col(df, "BMI")
#    df_clean <- remove_outliers_col(df, "BMI", low_prob = 0.05, high_prob = 0.95)
#
remove_outliers_col <- function(df, col, low_prob = 0.1, high_prob = 0.9,
                                iqr_factor = 1.5, na.rm = TRUE) {
  if (!col %in% names(df)) {
    warning("remove_outliers_col: column '", col, "' not found in data frame.")
    return(df)
  }

  x   <- df[[col]]
  qnt <- quantile(x, probs = c(low_prob, high_prob), na.rm = na.rm)
  H   <- iqr_factor * IQR(x, na.rm = na.rm)
  lo  <- qnt[1L] - H
  hi  <- qnt[2L] + H

  # 保留 NA 行（NA 不是异常值）；移除目标列值超出 (lo, hi) 的行
  valid_rows <- is.na(x) | (x > lo & x < hi)
  df[valid_rows, , drop = FALSE]
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_remove_outliers <- function(ctx, ...) {
  cfg    <- ctx$config
  ol_cfg <- cfg$remove_outliers %||% list()

  if (!isTRUE(ol_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("remove_outliers: enable=FALSE，跳过。")
    return(ctx)
  }

  data_slot <- as.character(ol_cfg$data_slot %||% "imputed")
  df        <- ctx$data[[data_slot]]

  # 若首选槽为空则回退另一槽
  if (is.null(df) || !is.data.frame(df)) {
    fallback  <- if (data_slot == "imputed") "cleaned" else "imputed"
    df        <- ctx$data[[fallback]]
    if (!is.null(df) && is.data.frame(df)) {
      cli::cli_alert_info(
        "remove_outliers: '{data_slot}' \u4e3a\u7a7a\uff0c\u56de\u9000\u4f7f\u7528 '{fallback}'\u3002"
      )
      data_slot <- fallback
    }
  }
  if (is.null(df) || !is.data.frame(df)) {
    stop("remove_outliers: \u672a\u627e\u5230\u6570\u636e\uff0c\u8bf7\u5148\u8fd0\u884c\u4e0a\u6e38\u6570\u636e\u51c6\u5907 block\u3002")
  }

  cols <- ol_cfg$cols
  if (is.null(cols)) {
    env_cfg <- cfg$environment %||% list()
    pat <- as.character(env_cfg$voc_col_pattern %||% "^URX")[1L]
    cols <- names(df)[grepl(pat, names(df), ignore.case = TRUE)]
    if (exists("environment_voc_exclude_fixed", mode = "function")) {
      cols <- setdiff(cols, environment_voc_exclude_fixed(cfg))
    }
    wt_cols <- c(
      cfg$nhanes$survey_weight %||% character(0),
      cfg$nhanes$survey_cluster %||% character(0),
      cfg$nhanes$survey_strata %||% character(0),
      cfg$data$id_column %||% character(0),
      "SEQN", "ID", "WTMEC2YR", "WTINT2YR", "SDMVPSU", "SDMVSTRA"
    )
    cols <- setdiff(cols, as.character(wt_cols))
  }
  cols <- intersect(as.character(cols), names(df))

  if (length(cols) == 0L) {
    cli::cli_alert_warning("remove_outliers: \u65e0\u53ef\u5904\u7406\u7684\u6570\u503c\u5217\uff0c\u8df3\u8fc7\u3002")
    return(ctx)
  }

  low_prob   <- as.numeric(ol_cfg$low_prob   %||% 0.1)
  high_prob  <- as.numeric(ol_cfg$high_prob  %||% 0.9)
  iqr_factor <- as.numeric(ol_cfg$iqr_factor %||% 1.5)

  n_before <- nrow(df)

  for (col in cols) {
    n_before_col <- nrow(df)
    df           <- remove_outliers_col(df, col, low_prob, high_prob, iqr_factor)
    n_removed    <- n_before_col - nrow(df)
    if (n_removed > 0L) {
      cli::cli_alert_info("  [{col}] \u79fb\u9664 {n_removed} \u884c\u5f02\u5e38\u503c")
    }
  }

  n_total_removed <- n_before - nrow(df)
  ctx$data[[data_slot]] <- df

  cli::cli_alert_success(
    "remove_outliers: \u5904\u7406 {length(cols)} \u5217\uff0c\u5171\u79fb\u9664 {n_total_removed} \u884c \u2192 \u5269\u4f59 {nrow(df)} \u884c"
  )

  ctx
}

register_block(
  "remove_outliers",
  block_remove_outliers,
  "\u57fa\u4e8e Q10/Q90 + 1.5\u00d7IQR \u79fb\u9664\u5f02\u5e38\u503c\u884c\uff08\u4fdd\u7559\u5176\u4ed6\u5217\u539f\u6709 NA\uff09"
)
