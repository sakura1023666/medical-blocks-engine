###############################################################################
#  trim_index_extreme — 删除当前复合指标的前后 p% 极端值
#
#  register_block: "trim_index_extreme"
#  位置: 紧接 imputation 之后、analysis blocks 之前
#
#  config 依赖:
#    config$incidence$index_var         — 当前指标名（batch runner patch）
#    config$incidence_batch$trim_quantile — 小样本前后各裁剪比例（默认 0.01 = 1%）
#    有效样本 > 10000 时自动改为前后各 5%（见 trim_index_quantile_for_n）
#
#  写出:
#    <step>/Data/D02_AfterTrim_Data.RData  — 插补后再裁极端值的分析数据（object）
#    <step>/Data/D02_AfterTrim_Data.rds
#    Table S1 重导 — After MI 与裁极端值后分析队列人数一致
###############################################################################

block_trim_index_extreme <- function(ctx) {
  cfg   <- ctx$config
  ix    <- as.character(
    (cfg$incidence %||% list())$index_var %||%
    (cfg$competing_risk %||% list())$index_var %||%
    (cfg$logistic  %||% list())$index_var %||%
    (cfg$survival  %||% list())$index_var %||% ""
  )[1L]

  if (!nzchar(ix)) {
    cli::cli_alert_warning("trim_index_extreme: config$incidence$index_var 未设置，跳过")
    return(ctx)
  }

  bc     <- cfg$incidence_batch %||% cfg$study_batch %||% cfg$competing_risk %||% list()
  # 优先独立开关：避免 survival_batch$trim_quantile=0（仅用于共享层复制不裁极端值）
  # 被 merge 进 incidence_batch 后，误关 trim_index_extreme。
  p_trim <- as.numeric(
    (cfg$trim_index_extreme %||% list())$trim_quantile %||%
      bc$trim_quantile %||%
      (cfg$survival_batch %||% list())$trim_quantile %||%
      0.01
  )
  if (p_trim <= 0) {
    cli::cli_alert_info("trim_index_extreme: trim_quantile=0，跳过极端值裁剪")
    return(ctx)
  }

  trim_meta <- list(index_var = ix, p_trim_base = p_trim)

  for (slot in c("imputed", "cleaned")) {
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df) || !ix %in% names(df)) next

    vals   <- suppressWarnings(as.numeric(df[[ix]]))
    n_na   <- sum(is.na(vals))
    keep_v <- !is.na(vals)
    df     <- df[keep_v, , drop = FALSE]
    vals   <- vals[keep_v]
    n_after_na <- length(vals)

    # 供补充表 “No handle extreme values” 复用：仅去 NA，未做百分位裁剪
    if (identical(slot, "imputed")) {
      ctx$results$trim_index_extreme <- ctx$results$trim_index_extreme %||% list()
      ctx$results$trim_index_extreme$before_percentile_imputed <- df
      ctx$results$trim_index_extreme$index_var <- ix
    }

    p_use  <- trim_index_quantile_for_n(length(vals), base_trim = p_trim)
    cli::cli_alert_info(
      "trim_index_extreme [{ix}] [{slot}]: n={length(vals)}, 前后各裁剪 {p_use * 100}%"
    )

    n_trim <- 0L
    q_lo <- NA_real_
    q_hi <- NA_real_
    if (length(vals) >= 20) {
      q_lo   <- as.numeric(quantile(vals, probs = p_use,     na.rm = TRUE))
      q_hi   <- as.numeric(quantile(vals, probs = 1 - p_use, na.rm = TRUE))
      mask   <- vals >= q_lo & vals <= q_hi
      n_trim <- sum(!mask)
      df     <- df[mask, , drop = FALSE]
    }

    ctx$data[[slot]] <- df
    if (identical(slot, "imputed")) {
      trim_meta$n_na <- n_na
      trim_meta$n_after_na <- n_after_na
      trim_meta$p_use <- p_use
      trim_meta$q_lo <- q_lo
      trim_meta$q_hi <- q_hi
      trim_meta$n_trim <- n_trim
      trim_meta$n_after <- nrow(df)
    }
    cli::cli_alert_success(
      "  [{slot}] {ix}: 删极端值 {n_trim} 行 → 剩余 {nrow(df)} 行"
    )
  }

  # Table S1 人数对齐：After MI 须与裁极端值后分析队列一致（Before MI 同步子集）
  imp_cfg <- cfg$imputation %||% list()
  data_imputed_trim <- ctx$data$imputed
  if (!is.null(data_imputed_trim) && is.data.frame(data_imputed_trim) && nrow(data_imputed_trim) > 0L) {
    before_mi <- ctx$results$data_before_mi
    if (!is.null(before_mi) && is.data.frame(before_mi) && nrow(before_mi) > 0L) {
      id_col <- as.character(cfg$data$id_column %||% "ID")[1L]
      if (id_col %in% names(before_mi) && id_col %in% names(data_imputed_trim)) {
        keep_ids <- unique(as.character(data_imputed_trim[[id_col]]))
        before_mi <- before_mi[as.character(before_mi[[id_col]]) %in% keep_ids, , drop = FALSE]
        ctx$results$data_before_mi <- before_mi
        cli::cli_alert_info(
          "trim_index_extreme: data_before_mi aligned to post-trim IDs (n={nrow(before_mi)})"
        )
      }
    }
    if (isTRUE(imp_cfg$export_table_s1 %||% TRUE) &&
        exists(".imp01_build_table_s1", mode = "function") &&
        !is.null(ctx$results$data_before_mi)) {
      # 复用 S1 编号，避免裁极端值后重导变成 S2
      if (isTRUE(ctx$results$table_s1_exported) &&
          exists(".pub_state", inherits = TRUE)) {
        cur_s <- as.integer(get("supp_table", envir = .pub_state, inherits = FALSE) %||% 0L)
        if (cur_s >= 1L) .pub_state$supp_table <- cur_s - 1L
      }
      table_strata <- cfg$baseline$table_strata %||% cfg$survival$exposure %||%
        (cfg$survival$event_var %||% cfg$data$outcome_column %||% "fustatus")
      analysis_grp <- cfg$baseline$analysis_group %||% cfg$project$analysis_group %||% "Case"
      reference_grp <- cfg$baseline$reference_group %||% cfg$project$reference_group %||% "Control"
      ctx <- .imp01_build_table_s1(
        ctx, cfg, ctx$results$data_before_mi, data_imputed_trim,
        table_strata, analysis_grp, reference_grp, imp_cfg
      )
      ctx$results$table_s1_post_trim <- TRUE
      cli::cli_alert_info("Table S1 re-exported after trim (n aligned with analysis cohort)")
    }
  }

  # 写出「插补 → 裁极端值」后的分析数据到 step Data/
  to_save <- ctx$data$imputed %||% ctx$data$cleaned
  if (!is.null(to_save) && is.data.frame(to_save) && nrow(to_save) > 0L) {
    data_dir <- file.path(ctx$output_dir %||% ".", "Data")
    dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)
    out_rdata <- file.path(data_dir, "D02_AfterTrim_Data.RData")
    if (exists("save_result", mode = "function")) {
      ctx <- save_result(ctx, "trimmed_index_data", to_save, out_rdata)
    } else {
      object <- to_save
      save(object, file = out_rdata)
      ctx$results$trimmed_index_data <- to_save
    }
    tryCatch(
      saveRDS(to_save, file.path(data_dir, "D02_AfterTrim_Data.rds")),
      error = function(e) NULL
    )
    meta <- c(
      paste0("index=", ix),
      paste0("p_trim_base=", trim_meta$p_trim_base %||% p_trim),
      paste0("p_use_each_tail=", trim_meta$p_use %||% NA),
      paste0("q_lo=", trim_meta$q_lo %||% NA),
      paste0("q_hi=", trim_meta$q_hi %||% NA),
      paste0("n_na_removed=", trim_meta$n_na %||% NA),
      paste0("n_trim=", trim_meta$n_trim %||% NA),
      paste0("n_after=", nrow(to_save)),
      paste0("rule=impute_then_trim; n>10000 -> 5% else base_trim"),
      paste0("object_name_in_RData=object"),
      paste0("generated_at=", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
    )
    tryCatch(
      writeLines(meta, file.path(data_dir, "D02_AfterTrim_Data.README.txt")),
      error = function(e) NULL
    )
    ctx$results$trim_index_extreme <- ctx$results$trim_index_extreme %||% list()
    ctx$results$trim_index_extreme$meta <- trim_meta
    cli::cli_alert_success(
      "D02_AfterTrim_Data.RData saved under Data/ (post-trim, n={nrow(to_save)})"
    )
    if (exists("attrition_record", mode = "function")) {
      ctx <- attrition_record(
        ctx, "after_trim_index", "After trimming index extremes",
        as.integer(nrow(to_save)), meta = list(block = "trim_index_extreme")
      )
    }
  }

  ctx
}

register_block(
  "trim_index_extreme",
  block_trim_index_extreme,
  "Trim extreme values (top/bottom p%) of the current index variable after imputation"
)
