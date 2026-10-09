###############################################################################
#  knhanes_survey_weight.R — KNHANES 多年度合并 pooled 权重（≠ NHANES ÷K）
#
#  KDCA：合并权重按各调查年度样本量成比例归一：
#    W_i = wt_itvex_i × n_{cycle(i)} / Σ_c n_c
#  层 / PSU 跨周期码值会复用，必须拼 cycle 全局唯一化。
#
#  由 block_obj 在 weight_builder="knhanes" 时调用；与 R/nhanes_survey_weight.R 并列。
#  操作说明：Blocks/12_obj/knhanes/
###############################################################################

#' Gate A / imputation 须保留的 KNHANES 设计列
knhanes_survey_weight_source_cols <- function(cfg = NULL) {
  nh <- if (!is.null(cfg)) (cfg$nhanes %||% list()) else list()
  kn <- if (!is.null(cfg)) (cfg$knhanes %||% list()) else list()
  unique(c(
    nh$survey_weight %||% kn$survey_weight %||% "W_pooled",
    nh$survey_cluster %||% kn$survey_cluster %||% "PSU",
    nh$survey_strata %||% kn$survey_strata %||% "STRATA",
    kn$raw_weight %||% "wt_itvex",
    kn$raw_weight_alt %||% "wt_tot",
    kn$cycle_col %||% "cycle",
    kn$raw_cluster %||% "psu",
    kn$raw_strata %||% "kstrata",
    "wt_bhvex", "wt_bhvex_t", "wt_ex", "wt_itv",
    "psu", "kstrata", "cycle", "W_pooled", "PSU", "STRATA"
  ))
}

#' 在定型分析集上计算 KNHANES 合并权重并唯一化层/PSU
#'
#' @param df 一人一行；须含 cycle + 原始权重 + 原始层/PSU
#' @param wt_col 写出合并权重列名（默认 W_pooled）
#' @param cycle_col 周期列
#' @param raw_weight_col 主分析原始权重（问卷+体检 wt_itvex）
#' @param raw_strata_col 原始层
#' @param raw_cluster_col 原始 PSU
#' @param strata_col / cluster_col 写出唯一化后的层/PSU 列名
#' @param recompute 是否覆盖已有 wt_col
compute_knhanes_pooled_weight <- function(
    df,
    wt_col           = "W_pooled",
    cycle_col        = "cycle",
    raw_weight_col   = "wt_itvex",
    raw_strata_col   = "kstrata",
    raw_cluster_col  = "psu",
    strata_col       = "STRATA",
    cluster_col      = "PSU",
    recompute        = FALSE
) {
  if (is.null(df) || !nrow(df)) return(df)

  wt_col <- as.character(wt_col)[1L]
  cycle_col <- as.character(cycle_col)[1L]
  raw_weight_col <- as.character(raw_weight_col)[1L]
  raw_strata_col <- as.character(raw_strata_col)[1L]
  raw_cluster_col <- as.character(raw_cluster_col)[1L]
  strata_col <- as.character(strata_col)[1L]
  cluster_col <- as.character(cluster_col)[1L]

  if (wt_col %in% names(df) && !isTRUE(recompute)) {
    w <- suppressWarnings(as.numeric(df[[wt_col]]))
    if (any(is.finite(w) & w > 0, na.rm = TRUE) &&
        strata_col %in% names(df) && cluster_col %in% names(df)) {
      return(df)
    }
  }

  need <- c(cycle_col, raw_weight_col, raw_strata_col, raw_cluster_col)
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    stop(
      "compute_knhanes_pooled_weight: 缺少列 ",
      paste(miss, collapse = ", "),
      "（KNHANES ≠ NHANES，不可用 WTMEC*/SDMV*）。",
      call. = FALSE
    )
  }

  cyc <- as.character(df[[cycle_col]])
  raw_w <- suppressWarnings(as.numeric(df[[raw_weight_col]]))
  if (any(!is.finite(raw_w) | raw_w <= 0)) {
    n_bad <- sum(!is.finite(raw_w) | raw_w <= 0)
    warning(
      "compute_knhanes_pooled_weight: ", n_bad,
      " 行 ", raw_weight_col, " 为 NA/非正；svydesign 前将剔除。",
      call. = FALSE
    )
  }

  # 按当前分析集各周期样本量等比（定型后 Σn 会变；禁止手填 ÷K）
  n_cyc <- as.numeric(stats::ave(rep(1, nrow(df)), cyc, FUN = length))
  sum_n <- as.numeric(nrow(df))
  df[[wt_col]] <- raw_w * n_cyc / sum_n

  df[[strata_col]] <- factor(paste(cyc, as.character(df[[raw_strata_col]]), sep = "_"))
  df[[cluster_col]] <- factor(paste(cyc, as.character(df[[raw_cluster_col]]), sep = "_"))

  n_strata <- length(unique(stats::na.omit(as.character(df[[strata_col]]))))
  n_psu <- length(unique(stats::na.omit(as.character(df[[cluster_col]]))))
  n_cycles <- length(unique(stats::na.omit(cyc)))

  attr(df, "knhanes_weight_info") <- list(
    weight_col   = wt_col,
    source       = raw_weight_col,
    source_desc  = "KDCA pooled: wt_itvex × n_cycle / Σn (analytic dataset); strata/PSU prefixed by cycle",
    n_cycles     = n_cycles,
    cycles       = paste(sort(unique(stats::na.omit(cyc))), collapse = ", "),
    n_strata     = n_strata,
    n_psu        = n_psu,
    n_used       = sum(is.finite(df[[wt_col]]) & df[[wt_col]] > 0, na.rm = TRUE),
    n_dropped    = sum(!is.finite(df[[wt_col]]) | df[[wt_col]] <= 0, na.rm = TRUE),
    dropped_any  = any(!is.finite(df[[wt_col]]) | df[[wt_col]] <= 0),
    formula      = "W = wt_itvex * n_cycle / sum(n_cycle)"
  )
  df
}

#' 从 config$nhanes / config$knhanes 读取列名后计算合并权重
compute_knhanes_pooled_weight_from_config <- function(df, cfg, recompute = FALSE) {
  nh <- (cfg$nhanes %||% list())
  kn <- (cfg$knhanes %||% list())
  compute_knhanes_pooled_weight(
    df,
    wt_col          = as.character(nh$survey_weight %||% kn$survey_weight %||% "W_pooled")[1L],
    cycle_col       = as.character(kn$cycle_col %||% "cycle")[1L],
    raw_weight_col  = as.character(kn$raw_weight %||% "wt_itvex")[1L],
    raw_strata_col  = as.character(kn$raw_strata %||% "kstrata")[1L],
    raw_cluster_col = as.character(kn$raw_cluster %||% "psu")[1L],
    strata_col      = as.character(nh$survey_strata %||% kn$survey_strata %||% "STRATA")[1L],
    cluster_col     = as.character(nh$survey_cluster %||% kn$survey_cluster %||% "PSU")[1L],
    recompute       = recompute
  )
}
