###############################################################################
#  obj — NHANES 复杂抽样 svydesign：基础 + Binary/Tertile/Quartile 四套设计对象。
#
#  register_block: "obj"
#  典型流水线: imputation → cutoff → obj → baseline_nhanes / rcs_nhanes / 加权分析
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data    = ctx$data$imputed %||% ctx$data$cleaned
#  require_results = cutoff 写入的 nhanes_data_binary / _tert / _quart
#  门控            = database_type 含 nhanes/nhance，否则空操作返回 ctx
#
#  # ── 配置 config$nhanes（权重列名，块内只读）────────────────────────────────
#  survey_weight  = "new_Weight" 等；survey_cluster = "SDMVPSU"；survey_strata = "SDMVSTRA"
#  auto_new_weight = TRUE（默认）：survey_weight 为 new_Weight 时在 svydesign 前自动计算
#  weight_index_var / cutoff_index_var / incidence$index_var — 决定 WTMEC vs WTSAF
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: ctx$data$imputed；ctx$results$nhanes_data_*
#  写: nhanes_design, nhanes_design_binary, nhanes_design_tert, nhanes_design_quart
#  源: Blocks/block_obj.R / C01_obj.R；依赖 survey、R/nhanes_survey_weight.R、R/utils.R
###############################################################################

.block_obj_ensure_weight_helper <- function(root) {
  if (exists("compute_nhanes_new_weight", mode = "function", inherits = FALSE)) {
    return(invisible(TRUE))
  }
  path <- file.path(root, "R", "nhanes_survey_weight.R")
  if (!file.exists(path)) {
    stop("block_obj: 未找到 R/nhanes_survey_weight.R", call. = FALSE)
  }
  source(path, local = FALSE)
  invisible(TRUE)
}

.block_obj_apply_new_weight <- function(df, cfg, nhanes_cfg, wt_col, root) {
  if (is.null(df)) return(df)
  auto <- isTRUE(nhanes_cfg$auto_new_weight %||% TRUE)
  if (!auto || wt_col != "new_Weight") return(df)

  inc_cfg     <- cfg$incidence %||% list()
  index_var   <- as.character(
    nhanes_cfg$weight_index_var %||%
      nhanes_cfg$cutoff_index_var %||%
      inc_cfg$index_var %||%
      ""
  )[1L]
  if (!nzchar(index_var)) {
    stop(
      "block_obj: survey_weight='new_Weight' 但未指定暴露变量；",
      "请设置 config$nhanes$cutoff_index_var 或 config$incidence$index_var。",
      call. = FALSE
    )
  }

  .block_obj_ensure_weight_helper(root)
  fasting_only <- nhanes_cfg$fasting_only_index %||% NULL
  recompute    <- isTRUE(nhanes_cfg$recompute_new_weight %||% FALSE)

  reuse <- wt_col %in% names(df) && !recompute &&
    any(is.finite(df[[wt_col]]) & df[[wt_col]] > 0, na.rm = TRUE)

  out <- compute_nhanes_new_weight(
    df,
    target_var   = index_var,
    wt_col       = wt_col,
    fasting_only = fasting_only,
    recompute    = recompute
  )

  if (reuse) {
    cli::cli_alert_info(
      "block_obj: 复用已有 {wt_col}（设 config$nhanes$recompute_new_weight=TRUE 可重算）"
    )
  } else {
    is_fasting <- index_var %in% (fasting_only %||% nhanes_fasting_only_indices())
    n_cyc <- if ("Source_File" %in% names(out)) length(unique(out[["Source_File"]])) else NA_integer_
    cli::cli_alert_info(
      "block_obj: 已计算 {wt_col}（暴露={index_var}，{if (is_fasting) 'WTSAF' else 'WTMEC'}，周期数={n_cyc}）"
    )
  }

  # 权重元信息（供纳排图脚注：用了哪个权重、周期数、是否因权重删人）
  .block_obj_record_weight_info <- function(out, wt_col, index_var) {
    if (is.null(out) || !wt_col %in% names(out)) return(NULL)
    w <- suppressWarnings(as.numeric(out[[wt_col]]))
    src <- if ("Source_File" %in% names(out)) as.character(out$Source_File) else character(0)
    src_pool <- if (index_var %in% (fasting_only %||% nhanes_fasting_only_indices())) {
      c("WTSAF2YR", "WTSAF4YR")
    } else {
      c("WTMEC2YR", "WTMEC4YR")
    }
    scale_4yr <- any(grepl("1999|2001", stats::na.omit(src)))
    n_drop_wt <- sum(!is.finite(w) | w <= 0, na.rm = TRUE)
    list(
      weight_col   = wt_col,
      index_var    = index_var,
      source       = if (length(src_pool) == 1L) src_pool[[1L]] else
        paste0(src_pool, collapse = " / "),
      source_desc  = paste0(
        if (length(src_pool) > 1L && scale_4yr) "4-year cycles" else "2-year cycles",
        ", scaled by 1/number of cycles"
      ),
      n_cycles     = if (length(src)) length(unique(stats::na.omit(src))) else NA_integer_,
      cycles       = paste(sort(unique(stats::na.omit(src))), collapse = ", "),
      n_used       = sum(is.finite(w) & w > 0, na.rm = TRUE),
      n_dropped    = n_drop_wt,
      dropped_any  = n_drop_wt > 0L
    )
  }

  attr(out, "nhanes_weight_info") <- .block_obj_record_weight_info(out, wt_col, index_var)
  out
}

block_obj <- function(ctx, ...) {
  cfg <- ctx$config

  if (!.is_nhanes_db(cfg)) {
    cli::cli_alert_info("block_obj: database_type 非 NHANES，跳过。")
    return(ctx)
  }

  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("block_obj: 需要 survey 包，请执行 install.packages('survey')。")
  }
  library(survey, warn.conflicts = FALSE)
  # 单 PSU 分层（数据子集后可能出现）：用邻近分层均值填充，避免所有 svyglm 返回 P=1
  options(survey.lonely.psu = "adjust")

  nhanes_cfg <- cfg$nhanes %||% list()
  wt_col     <- as.character(nhanes_cfg$survey_weight  %||% "new_Weight")[1L]
  psu_col    <- as.character(nhanes_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col    <- as.character(nhanes_cfg$survey_strata  %||% "SDMVSTRA")[1L]
  root       <- cfg$project$root %||% getwd()

  .make_design <- function(df, label) {
    need <- c(psu_col, str_col, wt_col)
    miss <- setdiff(need, names(df))
    if (length(miss) > 0L) {
      cli::cli_alert_warning("block_obj [{label}]: 缺少列 {paste(miss, collapse=', ')}，跳过。")
      return(NULL)
    }
    w <- suppressWarnings(as.numeric(df[[wt_col]]))
    keep <- is.finite(w) & w > 0
    if (!all(keep)) {
      n_drop <- sum(!keep)
      if (n_drop > 0L) {
        cli::cli_alert_warning(
          "block_obj [{label}]: 剔除 {n_drop} 行权重 NA/非正（{wt_col}）"
        )
        df <- df[keep, , drop = FALSE]
      }
    }
    if (!nrow(df)) {
      cli::cli_alert_warning("block_obj [{label}]: 权重可用行数为 0，跳过。")
      return(NULL)
    }
    tryCatch(
      survey::svydesign(
        id      = stats::as.formula(paste0("~", psu_col)),
        strata  = stats::as.formula(paste0("~", str_col)),
        weights = stats::as.formula(paste0("~", wt_col)),
        data    = df,
        nest    = TRUE
      ),
      error = function(e) {
        cli::cli_alert_warning("block_obj [{label}]: svydesign 失败：{e$message}")
        NULL
      }
    )
  }

  # ── 基础设计（使用原始插补后数据）────────────────────────────────────────
  base_data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(base_data)) stop("block_obj: 无插补数据，请先运行 imputation。")

  base_data <- pipeline_ensure_outcome_group_column(base_data, cfg)
  if (exists("pipeline_relabel_binary_outcome_column", mode = "function")) {
    outcome_col <- as.character((cfg$data %||% list())$outcome_column %||% "Disease")[1L]
    base_data <- pipeline_relabel_binary_outcome_column(base_data, cfg, col = outcome_col)
  }

  base_data <- .block_obj_apply_new_weight(base_data, cfg, nhanes_cfg, wt_col, root)
  ctx$data$imputed <- base_data
  if (!is.null(ctx$data$cleaned)) {
    ctx$data$cleaned <- .block_obj_apply_new_weight(ctx$data$cleaned, cfg, nhanes_cfg, wt_col, root)
  }
  # 权重元信息存入 results（纳排图脚注引用）
  winfo <- attr(base_data, "nhanes_weight_info") %||% NULL
  if (!is.null(winfo)) {
    ctx$results$nhanes_weight_info <- winfo
    cli::cli_alert_info(
      "block_obj: 权重 {winfo$weight_col} <- {winfo$source}（{winfo$n_cycles} 周期）；因权重缺失/非正剔除 {winfo$n_dropped} 人"
    )
  }

  for (res_key in c("nhanes_data_binary", "nhanes_data_tert", "nhanes_data_quart")) {
    if (!is.null(ctx$results[[res_key]])) {
      ctx$results[[res_key]] <- .block_obj_apply_new_weight(
        ctx$results[[res_key]], cfg, nhanes_cfg, wt_col, root
      )
    }
  }

  design_base <- .make_design(base_data, "base")
  if (!is.null(design_base)) {
    ctx$results$nhanes_design <- design_base
    cli::cli_alert_success("block_obj: 基础 svydesign 已构建（n = {nrow(design_base$variables)}）")
  }

  # ── Binary 分组设计 ───────────────────────────────────────────────────────
  data_bin <- ctx$results$nhanes_data_binary
  if (!is.null(data_bin) && "Index_Group" %in% names(data_bin)) {
    d <- .make_design(data_bin, "binary")
    if (!is.null(d)) {
      ctx$results$nhanes_design_binary <- d
      cli::cli_alert_success("block_obj: Binary svydesign 已构建（n = {nrow(d$variables)}）")
    }
  } else {
    cli::cli_alert_warning("block_obj: ctx$results$nhanes_data_binary 为空或缺少 Index_Group，跳过 binary design。请先运行 block_cutoff。")
  }

  # ── Tertile 分组设计 ──────────────────────────────────────────────────────
  data_tert <- ctx$results$nhanes_data_tert
  if (!is.null(data_tert) && "Index_Group_Tertile" %in% names(data_tert)) {
    d <- .make_design(data_tert, "tertile")
    if (!is.null(d)) {
      ctx$results$nhanes_design_tert <- d
      cli::cli_alert_success("block_obj: Tertile svydesign 已构建（n = {nrow(d$variables)}）")
    }
  } else {
    cli::cli_alert_warning("block_obj: nhanes_data_tert 为空或缺少 Index_Group_Tertile，跳过。")
  }

  # ── Quartile 分组设计 ─────────────────────────────────────────────────────
  data_quart <- ctx$results$nhanes_data_quart
  if (!is.null(data_quart) && "Index_Group_Quartile" %in% names(data_quart)) {
    d <- .make_design(data_quart, "quartile")
    if (!is.null(d)) {
      ctx$results$nhanes_design_quart <- d
      cli::cli_alert_success("block_obj: Quartile svydesign 已构建（n = {nrow(d$variables)}）")
    }
  } else {
    cli::cli_alert_warning("block_obj: nhanes_data_quart 为空或缺少 Index_Group_Quartile，跳过。")
  }

  cli::cli_alert_success("block_obj 完成。")
  ctx
}

register_block("obj", block_obj,
               "NHANES svydesign construction (base + Binary/Tertile/Quartile) from block_cutoff results (C01_obj style)")
