###############################################################################
#  environment_voc_extreme_trim — GLM 后 VOC 仍不足 BKMR 时，在全队列 raw 上逐波删极端值
#
#  register_block: "environment_voc_extreme_trim"
#  位置: glm_environment_quartile → environment_subgroup_search 之后（亚组 recovery 仍不足时）
#  成功标准: select_vocs_final 数量达到 BKMR 下限（默认 ≥3），而非临床门禁 VOC 数
###############################################################################

block_environment_voc_extreme_trim <- function(ctx, ...) {
  cfg <- ctx$config
  bl  <- cfg$environment_voc_extreme_trim %||% list()
  if (!isTRUE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("environment_voc_extreme_trim: enable=FALSE，跳过。")
    return(ctx)
  }

  root <- cfg$project$root %||% getwd()
  helper <- file.path(root, "R", "environment_voc_recovery_utils.R")
  if (file.exists(helper)) source(helper, local = FALSE)

  min_target <- environment_recovery_min_glm_vocs(cfg)
  cnt0 <- environment_count_glm_final_vocs(ctx)
  if (environment_recovery_pipeline_ok(ctx, cfg)) {
    cli::cli_alert_success(
      "environment_voc_extreme_trim: GLM 后已有 {cnt0$n} 个 VOC（≥{min_target}），跳过极端值 recovery。"
    )
    return(ctx)
  }

  raw_base <- ctx$results$environment_raw_snapshot %||% ctx$data$raw
  if (is.null(raw_base) || !nrow(raw_base)) {
    stop("environment_voc_extreme_trim: 无全队列 raw 快照。", call. = FALSE)
  }
  ctx$results$environment_raw_snapshot <- raw_base

  drop_frac  <- as.numeric(bl$drop_frac_per_wave %||% 0.005)[1L]
  n_per_wave <- bl$drop_per_wave %||% NULL
  if (!is.null(n_per_wave)) n_per_wave <- as.integer(n_per_wave)[1L]
  max_waves  <- as.integer(bl$max_waves %||% 20L)[1L]
  min_n      <- as.integer(bl$min_sample_n %||% 100L)[1L]
  drop_label <- if (is.null(n_per_wave)) {
    sprintf("%.2f%%", drop_frac * 100)
  } else {
    as.character(n_per_wave)
  }

  recovery_root <- file.path(environment_recovery_base(ctx), "extreme_trim")
  dir.create(recovery_root, recursive = TRUE, showWarnings = FALSE)

  excluded <- as.numeric(ctx$results$environment_excluded_seqn %||% integer(0))
  wave_log <- list()
  best_n <- cnt0$n
  best_ctx <- ctx
  score_ctx <- ctx

  cli::cli_h2(
    "environment_voc_extreme_trim: GLM 后 {cnt0$n} 个 VOC，全队列每波删 {drop_label} 极端暴露者（目标 ≥{min_target}）"
  )

  for (wave in seq_len(max_waves)) {
    if (environment_recovery_pipeline_ok(best_ctx, cfg)) break

    raw_remain <- environment_filter_raw_by_seqn(
      raw_base, keep_seqn = raw_base$SEQN, exclude_seqn = excluded
    )
    wave_n <- nrow(raw_remain)
    if (wave_n < min_n) {
      cli::cli_alert_warning(
        "environment_voc_extreme_trim: 剩余样本 {wave_n} < {min_n}，停止。"
      )
      break
    }

    data_ref <- environment_extreme_trim_scoring_data(raw_base, excluded, cfg)
    cur_clinical <- environment_count_sig_univariate_vocs(score_ctx, cfg)
    drop_ids <- environment_pick_extreme_trim_candidates(
      data_ref, cur_clinical$voc_pool, cur_clinical$vocs,
      n_drop = if (is.null(n_per_wave)) NULL else n_per_wave,
      drop_frac = drop_frac,
      exclude_seqn = excluded
    )
    if (!length(drop_ids)) {
      cli::cli_alert_warning("environment_voc_extreme_trim: 第 {wave} 波无可剔除 ID，停止。")
      break
    }

    excluded <- unique(c(excluded, drop_ids))
    raw_trim <- environment_filter_raw_by_seqn(
      raw_base, keep_seqn = raw_base$SEQN, exclude_seqn = excluded
    )
    if (nrow(raw_trim) < min_n) {
      cli::cli_alert_warning(
        "environment_voc_extreme_trim: 剩余样本 {nrow(raw_trim)} < {min_n}，停止。"
      )
      break
    }

    cli::cli_alert_info(
      "第 {wave} 波: 本波剔除 {length(drop_ids)} 人 ({drop_label}，剩余队列 n={wave_n}) → 累计剔除 {length(excluded)} 人 → 重跑 n={nrow(raw_trim)}"
    )
    trial_dir <- file.path(recovery_root, sprintf("wave%02d_n%d", wave, nrow(raw_trim)))

    trial_ctx <- tryCatch(
      environment_rerun_through_glm(
        ctx, root, raw_df = raw_trim,
        trial_output_dir = trial_dir, clear_subgroup = TRUE
      ),
      error = function(e) {
        cli::cli_alert_warning("第 {wave} 波重跑失败（累计已剔除 {length(excluded)} 人）: {conditionMessage(e)}")
        NULL
      }
    )

    wave_status <- if (is.null(trial_ctx)) "failed" else "ok"
    cnt_glm <- if (!is.null(trial_ctx)) {
      environment_count_glm_final_vocs(trial_ctx)
    } else {
      list(n = NA_integer_, vocs = character(0))
    }

    environment_write_trial_summary(trial_dir, list(
      kind = "extreme_trim",
      wave = wave,
      status = wave_status,
      drop_n = length(drop_ids),
      drop_frac = if (is.null(n_per_wave)) drop_frac else NA_real_,
      n_before = wave_n,
      cumulative_excluded = length(excluded),
      dropped_seqn = paste(drop_ids, collapse = ";"),
      n_sample = nrow(raw_trim),
      glm_final_vocs_n = cnt_glm$n,
      glm_final_vocs = paste(cnt_glm$vocs, collapse = ";"),
      pipeline_ok = !is.null(trial_ctx) && environment_recovery_pipeline_ok(trial_ctx, cfg)
    ))

    wave_log[[wave]] <- data.frame(
      wave = wave,
      status = wave_status,
      drop_n = length(drop_ids),
      drop_frac = if (is.null(n_per_wave)) drop_frac else NA_real_,
      n_before = wave_n,
      cumulative_excluded = length(excluded),
      dropped = paste(drop_ids, collapse = ","),
      n_sample = nrow(raw_trim),
      glm_final_vocs = cnt_glm$n,
      trial_dir = trial_dir,
      stringsAsFactors = FALSE
    )

    if (is.null(trial_ctx)) next

    if (cnt_glm$n >= best_n) {
      best_n <- cnt_glm$n
      best_ctx <- trial_ctx
      best_ctx$results$environment_excluded_seqn <- excluded
      best_ctx$results$environment_extreme_trim_waves <- wave
      score_ctx <- trial_ctx
    }

    if (environment_recovery_pipeline_ok(trial_ctx, cfg)) {
      cli::cli_alert_success(
        "environment_voc_extreme_trim: 第 {wave} 波后 GLM final {cnt_glm$n} 个 VOC，达标。"
      )
      best_ctx <- trial_ctx
      best_ctx$results$environment_excluded_seqn <- excluded
      best_ctx$results$environment_extreme_trim_waves <- wave
      break
    }
  }

  if (environment_recovery_pipeline_ok(best_ctx, cfg)) {
    ctx <- best_ctx
    ctx$results$environment_excluded_seqn <- excluded
    if (length(wave_log)) {
      ctx$results$environment_extreme_trim_log <- do.call(rbind, wave_log)
      tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
      dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
      log_path <- file.path(
        tbl_dir,
        as.character(bl$log_filename %||% "Table_Environment_Extreme_Trim_Log.csv")
      )
      tryCatch(
        utils::write.csv(ctx$results$environment_extreme_trim_log, log_path, row.names = FALSE),
        error = function(e) NULL
      )
    }
    final_cnt <- environment_count_glm_final_vocs(ctx)
    cli::cli_alert_success(
      "environment_voc_extreme_trim: 最终 GLM {final_cnt$n} 个 VOC（累计剔除 {length(excluded)} 人）"
    )
    return(ctx)
  }

  final_cnt <- environment_count_glm_final_vocs(best_ctx)
  if (length(wave_log)) {
    best_ctx$results$environment_excluded_seqn <- excluded
    best_ctx$results$environment_extreme_trim_log <- do.call(rbind, wave_log)
    tbl_dir <- best_ctx$output_dir_tables %||% file.path(best_ctx$output_dir %||% ".", "Tables")
    dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
    log_path <- file.path(
      tbl_dir,
      as.character(bl$log_filename %||% "Table_Environment_Extreme_Trim_Log.csv")
    )
    tryCatch(
      utils::write.csv(best_ctx$results$environment_extreme_trim_log, log_path, row.names = FALSE),
      error = function(e) NULL
    )
  }
  cli::cli_alert_warning(
    "environment_voc_extreme_trim: 极端值 recovery 耗尽（{max_waves} 波），GLM 仅 {final_cnt$n} 个 VOC（目标 ≥{min_target}，累计剔除 {length(excluded)} 人）。返回最优结果，由下游 WQS/BKMR 按其 skip_if_vocs_lte / min_select_vocs 决定是否跳过。"
  )
  best_ctx$results$environment_extreme_trim_failed   <- TRUE
  best_ctx$results$environment_extreme_trim_best_n   <- final_cnt$n
  best_ctx$results$environment_excluded_seqn         <- excluded
  if (length(wave_log)) {
    best_ctx$results$environment_extreme_trim_log <- do.call(rbind, wave_log)
    tbl_dir <- best_ctx$output_dir_tables %||% file.path(best_ctx$output_dir %||% ".", "Tables")
    dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
    log_path <- file.path(
      tbl_dir,
      as.character(bl$log_filename %||% "Table_Environment_Extreme_Trim_Log.csv")
    )
    tryCatch(
      utils::write.csv(best_ctx$results$environment_extreme_trim_log, log_path, row.names = FALSE),
      error = function(e) NULL
    )
  }
  best_ctx
}

register_block(
  "environment_voc_extreme_trim",
  block_environment_voc_extreme_trim,
  "GLM 后 VOC 不足时在全队列上分波剔除极端暴露并重跑至 GLM"
)
