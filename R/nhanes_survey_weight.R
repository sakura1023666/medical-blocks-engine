###############################################################################
#  nhanes_survey_weight.R — NHANES 多周期合并 pooled 权重 new_Weight
#
#  依据 Source_File 周期数、暴露是否为空腹子样本指标，选择 WTMEC* / WTSAF* 并缩放。
#  由 block_obj 在 svydesign 前调用；数据若已有 new_Weight 则默认跳过。
###############################################################################

#' 需使用空腹子样本权重的复合指标（WTSAF*）
nhanes_fasting_only_indices <- function() {
  c(
    "HOMA_IR",
    "TyG", "TyG_BMI", "TyG_WHtR", "TyG_WC", "TyG_WWI", "TyG_ABSI",
    "AIP", "AIP_BMI", "AIP_WC", "AIP_WHtR", "WTI",
    "METSIR", "METS_VF",
    "CTI", "MCMI",
    "LAP", "VAI", "ZJU", "TCBI",
    "GLR", "SHR", "HGI", "GPR"
  )
}

#' Gate A / harmonize 须保留的 NHANES 权重源列（供 block_obj 计算 new_Weight）
nhanes_survey_weight_source_cols <- function(cfg = NULL) {
  nh <- if (!is.null(cfg)) (cfg$nhanes %||% list()) else list()
  unique(c(
    nh$survey_weight %||% "new_Weight",
    nh$survey_cluster %||% "SDMVPSU",
    nh$survey_strata %||% "SDMVSTRA",
    "Source_File", "SDDSRVYR",
    "WTINT2YR", "WTMEC2YR", "WTINT4YR", "WTMEC4YR",
    "WTSAF2YR", "WTSAF4YR", "WTSA2YR",
    "WTDRD1", "WTDR2D", "WTSOG2YR"
  ))
}

#' 计算或补全 new_Weight 列
#'
#' @param df 数据框，需含 Source_File 及 WTMEC/WTSAF 权重列
#' @param target_var 当前分析暴露（决定 WTMEC vs WTSAF）
#' @param wt_col 输出列名，默认 new_Weight
#' @param source_file_col 周期列名
#' @param fasting_only 空腹指标名向量；NULL 则用默认列表
#' @param recompute 是否覆盖已有 new_Weight
compute_nhanes_new_weight <- function(
    df,
    target_var,
    wt_col            = "new_Weight",
    source_file_col   = "Source_File",
    fasting_only      = NULL,
    recompute         = FALSE
) {
  if (is.null(df) || !nrow(df)) return(df)
  target_var <- as.character(target_var)[1L]
  wt_col     <- as.character(wt_col)[1L]
  if (!nzchar(target_var)) {
    stop("compute_nhanes_new_weight: target_var 为空。", call. = FALSE)
  }

  if (wt_col %in% names(df) && !recompute) {
    w <- df[[wt_col]]
    if (any(is.finite(w) & w > 0, na.rm = TRUE)) {
      return(df)
    }
  }

  if (!source_file_col %in% names(df)) {
    stop(
      "compute_nhanes_new_weight: 缺少 ", source_file_col,
      "，无法计算 ", wt_col, "。", call. = FALSE
    )
  }

  fasting_only   <- fasting_only %||% nhanes_fasting_only_indices()
  is_fasting_var <- target_var %in% fasting_only

  wtmec2 <- "WTMEC2YR"
  wtmec4 <- "WTMEC4YR"
  wtsaf2 <- "WTSAF2YR"
  wtsaf4 <- "WTSAF4YR"

  # 先读 Source_File，判断当前子集是否真的含 4 年期周期（1999-2000 / 2001-2002）
  src        <- as.character(df[[source_file_col]])
  cycles     <- unique(stats::na.omit(src))
  num_cycles <- length(cycles)
  if (num_cycles < 1L) {
    stop("compute_nhanes_new_weight: Source_File 无有效周期。", call. = FALSE)
  }
  has_four_year <- any(grepl("1999|2001", cycles))

  # 只有当前数据真正含 4 年期行时才需要 4YR 权重列
  wt2_col <- if (is_fasting_var) wtsaf2 else wtmec2
  wt4_col <- if (is_fasting_var) wtsaf4 else wtmec4
  need <- if (has_four_year) c(wt2_col, wt4_col) else wt2_col
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    stop(
      "compute_nhanes_new_weight: 缺少权重列 ",
      paste(miss, collapse = ", "),
      "（暴露 '", target_var, "' ",
      if (is_fasting_var) "为空腹指标" else "为非空腹指标",
      "）。", call. = FALSE
    )
  }

  wt2 <- if (wt2_col %in% names(df)) df[[wt2_col]] else rep(NA_real_, nrow(df))
  wt4 <- if (has_four_year && wt4_col %in% names(df)) df[[wt4_col]] else rep(NA_real_, nrow(df))

  has_both_early <- all(c("1999-2000", "2001-2002") %in% cycles)

  if (has_both_early) {
    is_early <- src %in% c("1999-2000", "2001-2002")
    df[[wt_col]] <- ifelse(
      is_early,
      wt4 * (2 / num_cycles),
      wt2 * (1 / num_cycles)
    )
  } else {
    is_four_year <- grepl("1999|2001", src)
    df[[wt_col]] <- ifelse(
      is_four_year,
      wt4 * (2 / num_cycles),
      wt2 * (1 / num_cycles)
    )
  }

  df
}
