###############################################################################
#  survival_dual_batch_runner.R — 预后双库批量多指标编排引擎 v1
#
#  复用 incidence_dual_batch_runner.R 的共享层、Gate A、worker 派发、飞书同步；
#  差异：per-index 流水线为 Cox 闸门链（非 logistic_gate），两库均为 regular。
###############################################################################

source(file.path(getwd(), "R", "incidence_dual_batch_runner.R"), local = FALSE)

# 将 survival_batch 键合并到 incidence_batch，供底层 runner 复用
.survival_batch_bind_config <- function(config) {
  sb <- config$survival_batch %||% list()
  if (length(sb)) {
    config$incidence_batch <- utils::modifyList(
      config$incidence_batch %||% list(),
      sb
    )
  }
  config
}

survival_batch_index_pub_root <- function(config_ix, ix) {
  bc <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()
  out_base <- bc$output_base %||% config_ix$project$output_dir
  if (exists("incidence_batch_find_index_output_dir", mode = "function")) {
    incidence_batch_find_index_output_dir(out_base, ix, "by_index")
  } else {
    file.path(out_base, "by_index", ix)
  }
}

# Cox 闸门链中 Phase 3 续跑：找实际落盘的最后一个 cox_* checkpoint
survival_batch_last_cox_ck_token <- function(ck_dir, pipeline) {
  blocks <- as.character(pipeline$blocks %||% character(0))
  rcs_pos <- match("rcs_prognosis", blocks)
  end_idx <- if (!is.na(rcs_pos)) rcs_pos - 1L else length(blocks)
  if (end_idx < 1L) return(NULL)
  pre_rcs <- blocks[seq_len(end_idx)]
  cox_blocks <- pre_rcs[
    grepl("^cox_(binary|tertile|quartile)", pre_rcs) & !grepl("_rcs", pre_rcs)
  ]
  if (!length(cox_blocks)) return(NULL)
  for (b in rev(cox_blocks)) {
    idx   <- match(b, blocks)
    ck_id <- pipeline_checkpoint_id(idx, b)
    path  <- file.path(ck_dir, paste0(ck_id, ".rds"))
    alias <- file.path(ck_dir, paste0(b, ".rds"))
    if (file.exists(path) || file.exists(alias)) return(b)
  }
  NULL
}

# Patch config 为单一指标（在 incidence patch 基础上补 survival / Cox / KM）
survival_batch_patch_config_for_index <- function(config, ix) {
  config <- .survival_batch_bind_config(config)
  config <- incidence_batch_patch_config_for_index(config, ix)

  config$survival$index_var <- ix
  config$logistic$index_var <- ix

  for (blk in c("cox_quartile", "cox_tertile", "cox_binary")) {
    if (!is.null(config[[blk]])) config[[blk]]$index_var <- ix
  }
  if (!is.null(config$rcs_prognosis)) config$rcs_prognosis$index_var <- ix
  if (!is.null(config$subgroup_prognosis)) config$subgroup_prognosis$index_var <- ix

  q_col <- paste0(ix, "_quartile")
  t_col <- paste0(ix, "_tertile")
  # 模板若漏配 km_strata，在此兜底注入，避免 time_var 未配置
  if (is.null(config$km_strata)) config$km_strata <- list()
  surv <- config$survival %||% list()
  if (is.null(config$km_strata$time_var) || !nzchar(as.character(config$km_strata$time_var)[1L] %||% "")) {
    config$km_strata$time_var <- surv$time_var %||% "futime"
  }
  if (is.null(config$km_strata$event_var) || !nzchar(as.character(config$km_strata$event_var)[1L] %||% "")) {
    config$km_strata$event_var <- surv$event_var %||% "fustatus"
  }
  if (is.null(config$km_strata$event_value)) {
    config$km_strata$event_value <- surv$event_value %||% 1
  }
  if (is.null(config$km_strata$time_divisor)) {
    config$km_strata$time_divisor <- surv$time_divisor %||% 1
  }
  config$km_strata$strata_vars <- c(q_col)
  config$km_strata$strata_vars_by_branch <- list(
    extend_quartile = c(q_col),
    extend_tertile  = c(t_col)
  )
  config$km_strata$strata_defs <- list()
  config$km_strata$strata_defs[[q_col]] <- list(
    source = ix,
    type   = "quartile_factor",
    labels = c("Q1", "Q2", "Q3", "Q4"),
    levels = c("Q1", "Q2", "Q3", "Q4")
  )
  config$km_strata$strata_defs[[t_col]] <- list(
    source = ix,
    type   = "tertile_factor",
    labels = c("T1", "T2", "T3"),
    levels = c("T1", "T2", "T3")
  )

  if (is.null(config$mediation_prognosis)) config$mediation_prognosis <- list()
  config$mediation_prognosis$exposure <- ix
  # 双库路径图默认锁定统一中介（闸门 E）
  if (is.null(config$mediation_prognosis$dual_db_lock_best_mediator)) {
    config$mediation_prognosis$dual_db_lock_best_mediator <- TRUE
  }

  # 按指标覆盖（仅该 index 生效；其他指标不继承）
  # 例：config$index_overrides$BAR$rcs_prognosis$x_max <- 40
  ov <- (config$index_overrides %||% list())[[ix]] %||%
    (config$index_var_overrides %||% list())[[ix]] %||% list()
  if (is.list(ov) && length(ov)) {
    for (nm in names(ov)) {
      if (is.null(nm) || !nzchar(nm)) next
      if (is.list(ov[[nm]])) {
        config[[nm]] <- utils::modifyList(config[[nm]] %||% list(), ov[[nm]])
      } else {
        config[[nm]] <- ov[[nm]]
      }
    }
    if (exists("cli_alert_info", mode = "function") ||
        requireNamespace("cli", quietly = TRUE)) {
      tryCatch(
        cli::cli_alert_info("index_overrides[{ix}]: {paste(names(ov), collapse = ', ')}"),
        error = function(e) NULL
      )
    }
  }

  config
}

#' 读取 checkpoint 中当前路径图选中的中介（表首行或 preferred）
survival_batch_current_path_mediator <- function(root, config_ix, db) {
  tbl <- dual_db_load_mediation_result_table(root, config_ix, db)
  if (is.null(tbl) || !nrow(tbl)) return(NA_character_)
  as.character(tbl$Mediator[1L])[1L]
}

#' 闸门 E 后重跑中介块：固定 best_mediator（+ 可选 mediators 交集）
survival_batch_realign_mediation_locked <- function(root, config_ix, ix, db,
                                                    locked, pipeline) {
  if (is.null(locked) || !nzchar(as.character(locked$best_mediator %||% "")[1L])) {
    return(invisible(NULL))
  }
  cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
  cfg_db$project$root <- config_ix$project$root %||%
    config_ix$project$output_dir %||% root
  mp <- cfg_db$mediation_prognosis %||% list()
  mp$best_mediator <- as.character(locked$best_mediator)[1L]
  mp$dual_db_lock_best_mediator <- TRUE
  # 强制固定中介集时，两库表行一致；仍各自估计系数
  if (length(locked$mediators %||% character(0))) {
    mp$mediators <- as.character(locked$mediators)
  }
  mp$diagram_palette_random <- FALSE
  if (is.null(mp$diagram_palette) || !nzchar(as.character(mp$diagram_palette)[1L])) {
    mp$diagram_palette <- "matcha"
  }
  cfg_db$mediation_prognosis <- mp

  pipe <- pipeline
  # worker 已将 dual_db$checkpoint_base 设为 per-index 根
  per_ck <- file.path(
    (config_ix$dual_db %||% list())$checkpoint_base %||% "checkpoints",
    dual_db_slot_path_name(config_ix, db)
  )
  pipe <- incidence_batch_set_pipeline_ck(pipe, per_ck)
  blks <- as.character(pipe$blocks %||% character(0))
  mpos <- match("mediation_prognosis", blks)
  from_t <- if (!is.na(mpos) && mpos > 1L) blks[[mpos - 1L]] else "boxplot"
  cli::cli_alert_info(
    "[{ix}] {dual_db_slot_path_name(config_ix, db)} 中介重对齐 → best={locked$best_mediator}（from={from_t}）"
  )
  run_pipeline(
    root, config = cfg_db, pipeline = pipe,
    run_opts = list(from = from_t, to = "mediation_prognosis")
  )
}

#' Phase1 后：两库 imputed 列取交集并重跑 baseline→VIF，保证后续全部表/图列对齐
survival_batch_dual_lock_analysis_columns <- function(root, config_ix, ix, db_seq,
                                                     pipeline) {
  if (length(db_seq) < 2L) return(invisible(NULL))
  pol <- if (exists("pipeline_sparse_categorical_policy", mode = "function")) {
    pipeline_sparse_categorical_policy(config_ix)
  } else {
    list(dual_db_lock = TRUE)
  }
  if (!isTRUE((config_ix$dual_db %||% list())$enable %||% FALSE)) return(invisible(NULL))
  if (isFALSE(pol$dual_db_lock %||% TRUE)) return(invisible(NULL))
  if (!exists("pipeline_dual_db_common_imputed_colnames", mode = "function")) {
    cli::cli_alert_warning("dual_db 列对齐：缺少 pipeline_dual_db_common_imputed_colnames，跳过")
    return(invisible(NULL))
  }

  cli::cli_h2("[{ix}] 双库分析列交集锁定（后续全部表/图对齐）")
  common <- pipeline_dual_db_common_imputed_colnames(root, config_ix, ix, db_seq)
  if (!length(common)) {
    cli::cli_alert_warning("未能计算两库 imputed 列交集，跳过对齐")
    return(invisible(NULL))
  }
  cli::cli_alert_success("共同分析列 {length(common)} 个")

  # 若两库 imputed 已完全一致，无需删检查点重跑（避免 from 语义/checkpoint 关闭踩坑）
  already_aligned <- TRUE
  for (db in db_seq) {
    slot <- dual_db_slot_path_name(config_ix, db)
    bc0 <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()
    out_base <- bc0$output_base %||% (config_ix$project %||% list())$output_dir %||% root
    d01 <- file.path(survival_batch_index_pub_root(config_ix, ix), slot, "step05_imputation", "D01_AfterMI_Data.RData")
    cols <- character(0)
    if (file.exists(d01)) {
      e <- new.env(parent = emptyenv())
      tryCatch(load(d01, envir = e), error = function(err) NULL)
      if (length(ls(e))) {
        d <- e[[ls(e)[1L]]]
        if (is.data.frame(d)) cols <- names(d)
      }
    }
    if (!length(cols) || !setequal(cols, common)) {
      already_aligned <- FALSE
      break
    }
  }
  if (isTRUE(already_aligned)) {
    cli::cli_alert_success("两库 imputed 列已一致（n={length(common)}），跳过 baseline→VIF 重跑")
    return(invisible(common))
  }

  for (db in db_seq) {
    if (exists("pipeline_dual_db_trim_imputed_to_common", mode = "function")) {
      pipeline_dual_db_trim_imputed_to_common(root, config_ix, ix, db, common)
    }
  }

  # 删掉 baseline 及之后的 per-index 检查点，强制用对齐后的 imputed 重跑到 VIF_final
  bc <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()
  ck_base <- (config_ix$dual_db %||% list())$checkpoint_base %||%
    file.path(bc$index_ck_base %||% "checkpoints/by_index", ix)
  if (!grepl("^(?:[A-Za-z]:)?[/\\\\]", as.character(ck_base)[1L])) {
    ck_base <- file.path(root, ck_base)
  }
  drop_pat <- paste0(
    "step0([6-9]|1[0-9]|2[0-9])_|",
    "baseline_|univariate_|multicollinearity_|multivariate_|",
    "dual_db_covariate|cox_|rcs_|plot_cutoff|km_|segmented_|subgroup_|",
    "simple_ROC|boxplot|mediation_"
  )
  for (db in db_seq) {
    slot <- dual_db_slot_path_name(config_ix, db)
    ck_dir <- file.path(ck_base, slot)
    if (!dir.exists(ck_dir)) next
    rds <- list.files(ck_dir, pattern = "\\.rds$", full.names = TRUE)
    kill <- rds[grepl(drop_pat, basename(rds), ignore.case = TRUE)]
    # keep imputation / index / earlier
    keep_ok <- grepl(
      "step0[1-5]_|data_clean|column_mapping|dual_db_column|index\\.rds$|imputation",
      basename(kill),
      ignore.case = TRUE
    )
    kill <- kill[!keep_ok]
    if (length(kill)) {
      unlink(kill)
      cli::cli_alert_info(
        "[{slot}] 已清除对齐后需重跑的检查点 {length(kill)} 个"
      )
    }
  }

  for (db in db_seq) {
    cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
    pipe <- pipeline
    if (exists("dual_db_is_weighted", mode = "function") &&
        exists("pipeline_nhanes_batch") &&
        isTRUE(dual_db_is_weighted(config_ix, db))) {
      pipe <- pipeline_nhanes_batch
    }
    per_ck <- file.path(ck_base, dual_db_slot_path_name(config_ix, db))
    # 必须开启检查点：from= 表示「该步之后续跑」，需能恢复 imputation 检查点
    pipe <- incidence_batch_set_pipeline_ck(pipe, per_ck)
    pipe$checkpoint$enable <- TRUE
    blks <- as.character(pipe$blocks %||% character(0))
    # from 语义 = 从该 block 之后继续 → 要用 baseline 的前一步
    from_prev <- if ("baseline_binary" %in% blks) {
      "imputation"
    } else if ("baseline_nhanes" %in% blks) {
      idx <- match("baseline_nhanes", blks)
      if (!is.na(idx) && idx > 1L) blks[[idx - 1L]] else "imputation"
    } else if ("imputation" %in% blks) {
      "imputation"
    } else {
      "index"
    }
    to_bl <- if ("multicollinearity_final" %in% blks) {
      "multicollinearity_final"
    } else {
      .vif_final <- blks[grepl("multicollinearity_final|vif_final", blks)][1L]
      .vif_final %||% "multicollinearity_final"
    }
    # 确认 imputation 检查点仍在（列裁剪后）
    imp_ck <- file.path(per_ck, c("step05_imputation.rds", "imputation.rds"))
    if (!any(file.exists(imp_ck))) {
      stop(
        "dual_db 列对齐重跑失败：缺少 imputation 检查点 (", per_ck, ")。",
        call. = FALSE
      )
    }
    cli::cli_alert_info(
      "[{ix}/{dual_db_slot_path_name(config_ix, db)}] 重跑 {from_prev} 之后 → {to_bl}（含 baseline）"
    )
    run_pipeline(
      root, config = cfg_db, pipeline = pipe,
      run_opts = list(from = from_prev, to = to_bl)
    )
  }
  invisible(common)
}

#' 闸门 E（内置）：双库 mediation_prognosis 路径图必须同一中介
#'
#' Phase 3 跑完后由 survival dual-batch worker 自动调用；无需独立 repair 脚本。
#' 默认 config$mediation_prognosis$dual_db_lock_best_mediator = TRUE。
#'
#' @return locked list 或 NULL
survival_batch_apply_gate_e_mediation <- function(root, config_ix, ix, db_seq,
                                                  pipeline,
                                                  result_ctx = NULL) {
  blks <- as.character(pipeline$blocks %||% character(0))
  if (!("mediation_prognosis" %in% blks)) return(invisible(NULL))
  if (length(db_seq) < 2L) return(invisible(NULL))
  mp <- config_ix$mediation_prognosis %||% list()
  if (!isTRUE(mp$dual_db_lock_best_mediator %||% TRUE)) return(invisible(NULL))
  if (!exists("dual_db_lock_shared_best_mediator", mode = "function")) {
    cli::cli_alert_warning("闸门 E：dual_db_lock_shared_best_mediator 不可用，跳过")
    return(invisible(NULL))
  }

  cli::cli_h2("[{ix}] Gate E — 中介路径图中介对齐（两库统一）")
  bc <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()
  config_ix$project$root <- config_ix$project$root %||%
    config_ix$project$output_dir %||%
    (bc$output_base %||% root)

  locked <- dual_db_lock_shared_best_mediator(
    root, config_ix, db_seq, exposure = ix
  )
  if (is.null(locked)) {
    cli::cli_alert_warning("[{ix}] 闸门 E 无法锁定统一中介（缺结果或缺交集）")
    return(invisible(NULL))
  }

  need_rerun <- FALSE
  for (db in db_seq) {
    cur <- survival_batch_current_path_mediator(root, config_ix, db)
    if (!identical(as.character(cur %||% ""), as.character(locked$best_mediator))) {
      need_rerun <- TRUE
    }
  }
  force_rerun <- isTRUE(mp$dual_db_force_rerun_mediation %||% TRUE)
  if (!need_rerun && !force_rerun) {
    cli::cli_alert_info(
      "[{ix}] 两库路径图中介已是 {locked$best_mediator}，跳过重跑"
    )
    return(invisible(locked))
  }

  out_ctx <- result_ctx %||% list()
  for (db in db_seq) {
    out_ctx[[db]] <- survival_batch_realign_mediation_locked(
      root, config_ix, ix, db, locked, pipeline
    )
  }
  attr(locked, "result_ctx") <- out_ctx
  invisible(locked)
}

#' 删除 per-index Cox 检查点（用于双库分位对齐后重跑）
survival_batch_clear_cox_checkpoints <- function(ck_dir) {
  if (!dir.exists(ck_dir)) return(invisible(0L))
  n <- 0L
  for (blk in c("cox_quartile", "cox_tertile", "cox_binary")) {
    for (pat in c(
      paste0(blk, ".rds"),
      paste0("*_", blk, ".rds")
    )) {
      hits <- Sys.glob(file.path(ck_dir, pat))
      for (f in hits) {
        if (file.exists(f) && unlink(f) == 0L) n <- n + 1L
      }
    }
  }
  invisible(n)
}

#' 将统一 Cox 分位写入 per-index 目录下全部检查点 ctx
survival_batch_patch_all_ck_unified <- function(per_ck, unified_info) {
  if (!dir.exists(per_ck) || is.null(unified_info)) return(invisible(0L))
  n <- 0L
  for (f in Sys.glob(file.path(per_ck, "*.rds"))) {
    obj <- tryCatch(readRDS(f), error = function(e) NULL)
    if (is.null(obj$ctx)) next
    obj$ctx <- dual_db_patch_ctx_cox_unified(obj$ctx, unified_info)
    saveRDS(obj, f)
    n <- n + 1L
  }
  invisible(n)
}

#' 删除 per-index Cox 步骤产出（Table 2 等）
survival_batch_clear_cox_step_outputs <- function(output_db_dir) {
  if (!dir.exists(output_db_dir)) return(invisible(0L))
  n <- 0L
  for (d in Sys.glob(file.path(output_db_dir, "step*cox*"))) {
    if (dir.exists(d)) {
      unlink(d, recursive = TRUE)
      n <- n + 1L
    }
  }
  survival_batch_clear_stale_cox_tables(output_db_dir)
  invisible(n)
}

#' 曾误删镜像根 Table 2 / Figure 4（KM）；对齐重跑仅清 step*cox*。
survival_batch_clear_stale_cox_tables <- function(output_db_dir) {
  invisible(0L)
}

survival_batch_cox_block_for_scheme <- function(scheme) {
  switch(as.character(scheme)[1L],
    quartile = "cox_quartile",
    tertile  = "cox_tertile",
    binary   = "cox_binary",
    "cox_binary"
  )
}

survival_batch_assert_unified_cox_ck <- function(per_ck, pipeline, unified_info) {
  if (is.null(unified_info)) return(invisible(TRUE))
  want <- survival_batch_cox_block_for_scheme(unified_info$scheme)
  last <- survival_batch_last_cox_ck_token(per_ck, pipeline)
  if (!identical(last, want)) {
    stop(
      "COX_UNIFIED_MISMATCH: 检查点末块=", last %||% "NULL",
      "，统一分位要求=", want, "，已停止。",
      call. = FALSE
    )
  }
  invisible(TRUE)
}

#' 双库 Cox 分位对齐：更粗分位的库按统一方案重跑 Cox 链
survival_batch_realign_cox_to_unified <- function(root, config_ix, ix, db, unified_info, pipeline) {
  if (is.null(unified_info) || !nzchar(unified_info$scheme %||% "")) return(invisible(FALSE))
  bc <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()
  per_ck <- file.path(
    bc$index_ck_base %||% "checkpoints/_by_index", ix,
    dual_db_slot_path_name(config_ix, db)
  )
  output_db <- file.path(
    survival_batch_index_pub_root(config_ix, ix),
    dual_db_slot_path_name(config_ix, db)
  )
  natural <- dual_db_read_cox_natural_branch(root, config_ix, db)
  if (is.null(natural)) return(invisible(FALSE))
  uni_d <- logistic_gate_scheme_depth(unified_info$scheme)
  nat_d <- logistic_gate_scheme_depth(natural$scheme)
  if (!is.finite(uni_d) || !is.finite(nat_d) || nat_d >= uni_d) {
    survival_batch_patch_all_ck_unified(per_ck, unified_info)
    return(invisible(FALSE))
  }
  cli::cli_alert_warning(
    "[{ix}] {dual_db_slot_path_name(config_ix, db)} Cox 自然终态={natural$scheme}，对齐为 {unified_info$scheme}，重跑 Cox 链"
  )
  survival_batch_clear_cox_checkpoints(per_ck)
  survival_batch_clear_cox_step_outputs(output_db)
  survival_batch_patch_all_ck_unified(per_ck, unified_info)
  seed_blk <- "dual_db_covariate_harmonize"
  if (!file.exists(file.path(per_ck, paste0(seed_blk, ".rds")))) {
    seed_blk <- "multicollinearity_final"
  }
  cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
  pipe <- incidence_batch_set_pipeline_ck(pipeline, per_ck)
  run_pipeline(root, config = cfg_db, pipeline = pipe,
               run_opts = list(from = seed_blk, to = "cox_binary"))
  survival_batch_assert_unified_cox_ck(per_ck, pipeline, unified_info)
  survival_batch_patch_all_ck_unified(per_ck, unified_info)
  invisible(TRUE)
}

#' 将统一 Cox 分位写入 ctx（Phase 3 续跑前）
survival_batch_seed_cox_unified_ctx <- function(root, config_ix, ix, db, unified_info) {
  if (is.null(unified_info)) return(invisible(FALSE))
  bc <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()
  per_ck <- file.path(
    bc$index_ck_base %||% "checkpoints/_by_index", ix,
    dual_db_slot_path_name(config_ix, db)
  )
  survival_batch_patch_all_ck_unified(per_ck, unified_info)
  last <- survival_batch_last_cox_ck_token(per_ck, pipeline_regular_batch)
  want <- survival_batch_cox_block_for_scheme(unified_info$scheme)
  if (!identical(last, want)) {
    cli::cli_alert_warning(
      "[{ix}] {dual_db_slot_path_name(config_ix, db)} Cox 检查点 {last %||% 'NULL'} 与统一分位 {want} 不一致"
    )
    return(invisible(FALSE))
  }
  path <- file.path(per_ck, paste0(last, ".rds"))
  if (!file.exists(path)) return(invisible(FALSE))
  obj <- tryCatch(readRDS(path), error = function(e) NULL)
  if (is.null(obj$ctx)) return(invisible(FALSE))
  obj$ctx <- dual_db_patch_ctx_cox_unified(obj$ctx, unified_info)
  obj$ctx$results$cox_branch <- paste0("extend_", unified_info$scheme)
  saveRDS(obj, path)
  invisible(TRUE)
}

#' 从两库统一分位 Cox 检查点读取 Model1/Model2，取交集后锁定重跑 Table 2
#' 使 eICU/MIMIC 表注协变量一致；搜索仅在 Gate B 池内完成后再收敛。
survival_batch_align_cox_covariates_dual <- function(root, config_ix, ix, db_seq,
                                                     unified_cox, pipeline) {
  if (is.null(unified_cox) || length(db_seq) < 2L) return(invisible(NULL))
  if (!isTRUE(((config_ix$dual_db %||% list())$harmonization %||% list())$lock_cox_to_gate_b %||% TRUE)) {
    return(invisible(NULL))
  }
  scheme <- as.character(unified_cox$scheme %||% "")[1L]
  if (!nzchar(scheme)) return(invisible(NULL))
  want_blk <- survival_batch_cox_block_for_scheme(scheme)
  bc <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()

  read_m <- function(db) {
    per_ck <- file.path(
      bc$index_ck_base %||% "checkpoints/_by_index", ix,
      dual_db_slot_path_name(config_ix, db)
    )
    path <- file.path(per_ck, paste0(want_blk, ".rds"))
    if (!file.exists(path)) {
      # 兼容 stepN 命名
      hits <- Sys.glob(file.path(per_ck, paste0("*_", want_blk, ".rds")))
      path <- if (length(hits)) hits[[1L]] else path
    }
    if (!file.exists(path)) return(NULL)
    obj <- tryCatch(readRDS(path), error = function(e) NULL)
    if (is.null(obj$ctx$results)) return(NULL)
    r <- obj$ctx$results
    m1 <- as.character(r$cox_model1_covariates %||% r$Model1Factors %||% character(0))
    m2_extra <- as.character(r$cox_model2_covariates %||% character(0))
    m2_full <- if (length(m2_extra)) {
      unique(c(m1, m2_extra))
    } else {
      as.character(r$Model2Factors %||% m1)
    }
    list(m1 = unique(m1[nzchar(m1)]), m2 = unique(m2_full[nzchar(m2_full)]), path = path, ctx = obj$ctx)
  }

  packs <- lapply(db_seq, read_m)
  names(packs) <- as.character(db_seq)
  if (any(vapply(packs, is.null, logical(1)))) {
    cli::cli_alert_warning("[{ix}] Cox 协变量对齐：两库均无完整 {want_blk} 检查点，跳过")
    return(invisible(NULL))
  }

  m1_common <- packs[[1L]]$m1
  m2_common <- packs[[1L]]$m2
  for (i in seq_along(packs)[-1L]) {
    m1_common <- intersect(m1_common, packs[[i]]$m1)
    m2_common <- intersect(m2_common, packs[[i]]$m2)
  }
  # Model2 须为 Model1 真超集
  if (!length(m1_common)) m1_common <- "Age"
  if (!length(setdiff(m2_common, m1_common))) {
    # 回退：取两库并集再与 Gate B Model2 交集
    m2_union <- character(0)
    for (p in packs) m2_union <- unique(c(m2_union, p$m2))
    gate_b <- dual_db_load_gate_b(root, config_ix)
    gb2 <- if (!is.null(gate_b)) {
      unique(c(
        as.character(gate_b$harmonized_model2_nhanes %||% character(0)),
        as.character(gate_b$harmonized_model2_mimic %||% character(0))
      ))
    } else character(0)
    m2_common <- if (length(gb2)) intersect(m2_union, gb2) else m2_union
    m2_common <- unique(c(m1_common, setdiff(m2_common, m1_common)))
  } else {
    m2_common <- unique(c(m1_common, setdiff(m2_common, m1_common)))
  }
  if (!length(setdiff(m2_common, m1_common))) {
    cli::cli_alert_warning(
      "[{ix}] Cox 协变量对齐：交集后 Model2=Model1（{paste(m1_common, collapse=', ')}），改用各自并集 ∩ Gate B"
    )
    return(invisible(NULL))
  }

  prune_on <- isTRUE(
    ((config_ix$dual_db %||% list())$harmonization %||% list())$prune_highest_group_dual %||% TRUE
  )
  if (prune_on && exists("cox_prune_dual_highest_group", mode = "function")) {
    prepared <- lapply(as.character(db_seq), function(db) {
      cox_prepare_grouped_data_for_scheme(packs[[db]]$ctx, config_ix, ix, scheme)
    })
    names(prepared) <- as.character(db_seq)
    pr <- cox_prune_dual_highest_group(
      prepared, m1_common, m2_common, config_ix, ix, p_threshold = 0.05
    )
    if (length(pr$M2)) {
      m1_common <- pr$M1
      m2_common <- unique(c(pr$M1, setdiff(pr$M2, pr$M1)))
    }
  }

  cli::cli_h2("[{ix}] Gate C+ — Cox 协变量对齐（两库交集）")
  cli::cli_alert_info("Model1: {paste(m1_common, collapse = ', ')}")
  cli::cli_alert_info("Model2: {paste(m2_common, collapse = ', ')}")

  for (db in db_seq) {
    # 写入 factors 到 checkpoint
    p0 <- packs[[as.character(db)]]
    if (is.null(p0)) next
    per_ck <- file.path(
      bc$index_ck_base %||% "checkpoints/_by_index", ix,
      dual_db_slot_path_name(config_ix, db)
    )
    output_db <- file.path(
      survival_batch_index_pub_root(config_ix, ix),
      dual_db_slot_path_name(config_ix, db)
    )
    # 清除该分位 Cox 产出后用锁定因素重跑
    for (pat in c(
      paste0(want_blk, ".rds"),
      paste0("*_", want_blk, ".rds")
    )) {
      for (f in Sys.glob(file.path(per_ck, pat))) unlink(f)
    }
    survival_batch_clear_cox_step_outputs(output_db)

    # 解析 seed 检查点（兼容 stepN_*.rds / 裸名别名）
    .ck_hit <- function(dir, blk) {
      hits <- c(
        file.path(dir, paste0(blk, ".rds")),
        Sys.glob(file.path(dir, paste0("*_", blk, ".rds")))
      )
      hits <- hits[file.exists(hits)]
      if (length(hits)) hits[[1L]] else NA_character_
    }
    seed <- NA_character_
    for (cand in c(
      "multivariate_prognosis_harmonized",
      "dual_db_covariate_harmonize",
      "multicollinearity_final"
    )) {
      if (!is.na(.ck_hit(per_ck, cand))) {
        seed <- cand
        break
      }
    }
    if (is.na(seed)) {
      stop(
        "Gate C+ 重跑失败：缺少 seed 检查点（", per_ck, "）。",
        call. = FALSE
      )
    }

    # 补丁 seed ck 的 Model factors + 关搜索（stepN 与裸名都写）
    seed_paths <- unique(c(
      .ck_hit(per_ck, seed),
      file.path(per_ck, paste0(seed, ".rds"))
    ))
    seed_paths <- seed_paths[file.exists(seed_paths) | endsWith(seed_paths, paste0(seed, ".rds"))]
    for (seed_path in unique(seed_paths)) {
      so <- if (file.exists(seed_path)) {
        tryCatch(readRDS(seed_path), error = function(e) NULL)
      } else {
        hit0 <- .ck_hit(per_ck, seed)
        if (is.na(hit0)) NULL else tryCatch(readRDS(hit0), error = function(e) NULL)
      }
      if (is.null(so$ctx)) next
      so$ctx$results$Model1Factors <- m1_common
      so$ctx$results$Model2Factors <- m2_common
      so$ctx$results$dual_db_covariate_harmonized <- TRUE
      so$ctx$results$dual_db_cox_covariates_locked <- TRUE
      for (blk in c("cox_quartile", "cox_tertile", "cox_binary")) {
        if (is.null(so$ctx$config[[blk]])) so$ctx$config[[blk]] <- list()
        so$ctx$config[[blk]]$model1_factors <- m1_common
        so$ctx$config[[blk]]$model2_factors <- m2_common
        sc <- so$ctx$config[[blk]]$covariate_search %||% list()
        sc$enable <- FALSE
        so$ctx$config[[blk]]$covariate_search <- sc
        so$ctx$config[[blk]]$require_both_models_sig <- FALSE
      }
      for (blk in c("rcs_prognosis", "segmented_cox_quartile", "segmented_cox_tertile",
                    "segmented_cox_binary")) {
        if (!is.null(so$ctx$config[[blk]])) {
          so$ctx$config[[blk]]$model1_factors <- m1_common
          so$ctx$config[[blk]]$model2_factors <- m2_common
        }
      }
      saveRDS(so, seed_path)
    }

    cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
    cfg_db$survival$index_var <- ix
    for (blk in c("cox_quartile", "cox_tertile", "cox_binary")) {
      if (is.null(cfg_db[[blk]])) cfg_db[[blk]] <- list()
      cfg_db[[blk]]$model1_factors <- m1_common
      cfg_db[[blk]]$model2_factors <- m2_common
      sc <- cfg_db[[blk]]$covariate_search %||% list()
      sc$enable <- FALSE
      cfg_db[[blk]]$covariate_search <- sc
      # 对齐后允许 Model2 非同时显著也不中断（协变量优先一致）
      cfg_db[[blk]]$require_both_models_sig <- FALSE
    }
    pipe <- incidence_batch_set_pipeline_ck(pipeline, per_ck)
    pipe$checkpoint$enable <- TRUE
    cli::cli_alert_info(
      "[{ix}] {dual_db_slot_path_name(config_ix, db)} 重跑 {want_blk}（锁定协变量）"
    )
    run_pipeline(
      root, config = cfg_db, pipeline = pipe,
      run_opts = list(from = seed, to = want_blk)
    )
    # 必须落盘后再进入 Phase 3
    want_hit <- .ck_hit(per_ck, want_blk)
    if (is.na(want_hit)) {
      stop(
        "Gate C+ 后仍缺少检查点: ", want_blk, ".rds（", per_ck, "）",
        call. = FALSE
      )
    }
  }

  # Table S7：用最终锁定的 Cox Model2（如 Age+Gender+Ventilation_Hour）再出多因素，覆盖 Gate B 全池中间结果
  survival_batch_export_table_s7_locked_covariates(
    root, config_ix, ix, db_seq, m1_common, m2_common, pipeline
  )

  invisible(list(Model1 = m1_common, Model2 = m2_common, scheme = scheme))
}

#' Gate C+ 后：按最终统一协变量重出 Table S7（仅这些变量 + 暴露指标）
#' 协变量优先取各库 cox_* 检查点的 cox_final_factors（与 Table 2 全调整一致：
#' Model3 显著用 Model3，否则回退 Model2）；无终模时再回退 Gate C 的 m1/m2。
survival_batch_export_table_s7_locked_covariates <- function(
    root, config_ix, ix, db_seq, m1, m2, pipeline) {
  m1 <- unique(as.character(m1)[nzchar(as.character(m1))])
  m2 <- unique(as.character(m2)[nzchar(as.character(m2))])
  if (!length(m2)) {
    cli::cli_alert_warning("[{ix}] Table S7 跳过：锁定 Model2 为空")
    return(invisible(FALSE))
  }
  bc <- config_ix$survival_batch %||% config_ix$incidence_batch %||% list()
  cli::cli_h2("[{ix}] Table S7 — 最终统一协变量多因素（与 Table 2 全调整对齐）")

  for (db in db_seq) {
    per_ck <- file.path(
      bc$index_ck_base %||% "checkpoints/_by_index", ix,
      dual_db_slot_path_name(config_ix, db)
    )
    output_db <- file.path(
      survival_batch_index_pub_root(config_ix, ix),
      dual_db_slot_path_name(config_ix, db)
    )
    # 清理旧 S7 / Final 锁定多因素表，避免与全池多因素（S5）混号
    for (tdir in c(
      file.path(output_db, "Tables"),
      file.path(output_db),
      file.path(survival_batch_index_pub_root(config_ix, ix), "Tables"),
      file.path(bc$output_base %||% config_ix$project$output_dir, "Tables")
    )) {
      if (!dir.exists(tdir)) next
      all_x <- list.files(tdir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
      if (!length(all_x)) next
      bn <- basename(all_x)
      drop <- all_x[
        grepl("Final multivariable model", bn, ignore.case = TRUE) |
          grepl("dual-database harmonized", bn, ignore.case = TRUE) |
          grepl("^Table S7-.*Multivariable Regression Analysis\\.xlsx$", bn, ignore.case = TRUE)
      ]
      if (length(drop)) unlink(drop)
    }

    # 各库 Table 2 终模协变量（Model3 显著则含学术必调，否则 Model2）
    m1_db <- m1
    m2_db <- unique(c(m1, m2))
    cox_final <- character(0)
    m3_fac <- character(0)
    m3_sig <- FALSE
    for (cb in c("cox_quartile", "cox_tertile", "cox_binary")) {
      cpath <- file.path(per_ck, paste0(cb, ".rds"))
      if (!file.exists(cpath)) next
      cox_obj <- tryCatch(readRDS(cpath), error = function(e) NULL)
      if (is.null(cox_obj$ctx)) next
      cr <- cox_obj$ctx$results %||% list()
      cox_final <- unique(as.character(
        cr$cox_final_factors %||% cr$logistic_final_factors %||% character(0)
      ))
      cox_final <- cox_final[nzchar(cox_final)]
      m3_fac <- unique(as.character(cr$Model3Factors %||% character(0)))
      m3_sig <- isTRUE(cr$model3_significant)
      if (length(cr$Model1Factors)) {
        m1_db <- unique(as.character(cr$Model1Factors))
      }
      if (length(cox_final)) {
        m2_db <- cox_final
        break
      }
      if (length(cr$Model2Factors)) {
        m2_db <- unique(c(m1_db, as.character(cr$Model2Factors)))
      }
    }
    cli::cli_alert_info(
      "[{ix}] {dual_db_slot_path_name(config_ix, db)} Table S7 协变量={paste(m2_db, collapse = ', ')} (Model3_sig={m3_sig})"
    )

    seed <- "dual_db_covariate_harmonize"
    if (!file.exists(file.path(per_ck, paste0(seed, ".rds")))) {
      seed <- "multicollinearity_final"
    }
    if (!file.exists(file.path(per_ck, paste0(seed, ".rds")))) {
      # 用最近 cox ck 作为数据源亦可
      want <- NULL
      for (b in c("cox_quartile", "cox_tertile", "cox_binary")) {
        if (file.exists(file.path(per_ck, paste0(b, ".rds")))) {
          want <- b
          break
        }
      }
      if (is.null(want)) {
        cli::cli_alert_warning("[{ix}] {dual_db_slot_path_name(config_ix, db)} 无检查点，跳过 Table S7")
        next
      }
      seed <- want
    }

    obj <- tryCatch(readRDS(file.path(per_ck, paste0(seed, ".rds"))), error = function(e) NULL)
    if (is.null(obj$ctx)) {
      hits <- Sys.glob(file.path(per_ck, paste0("*_", seed, ".rds")))
      if (length(hits)) obj <- tryCatch(readRDS(hits[[1L]]), error = function(e) NULL)
    }
    if (is.null(obj$ctx)) {
      cli::cli_alert_warning("[{ix}] {dual_db_slot_path_name(config_ix, db)} seed 检查点无效，跳过 Table S7")
      next
    }
    obj$ctx$results$Model1Factors <- m1_db
    obj$ctx$results$Model2Factors <- m2_db
    if (length(cox_final)) {
      obj$ctx$results$cox_final_factors <- cox_final
      obj$ctx$results$logistic_final_factors <- cox_final
    }
    if (length(m3_fac)) obj$ctx$results$Model3Factors <- m3_fac
    obj$ctx$results$model3_significant <- m3_sig
    obj$ctx$results$dual_db_covariate_harmonized <- TRUE
    obj$ctx$results$dual_db_cox_covariates_locked <- TRUE
    obj$ctx$results$dual_db_force_export_harmonized_multivar <- TRUE
    saveRDS(obj, file.path(per_ck, paste0(seed, ".rds")))

    # 也写一份 multivariate_prognosis_harmonized 别名，便于 from/to 定位
    saveRDS(obj, file.path(per_ck, "multivariate_prognosis_harmonized.rds"))

    # 同步 patch 所有 dual_db / multi_harmonized / step12 别名（resume 常读 stepN_*.rds）
    for (pat in c(
      "dual_db_covariate_harmonize.rds", "*_dual_db_covariate_harmonize.rds",
      "multivariate_prognosis_harmonized.rds", "*_multivariate_prognosis_harmonized.rds"
    )) {
      for (fp in Sys.glob(file.path(per_ck, pat))) {
        o2 <- tryCatch(readRDS(fp), error = function(e) NULL)
        if (is.null(o2$ctx)) next
        o2$ctx$results$Model1Factors <- m1_db
        o2$ctx$results$Model2Factors <- m2_db
        if (length(cox_final)) {
          o2$ctx$results$cox_final_factors <- cox_final
          o2$ctx$results$logistic_final_factors <- cox_final
        }
        if (length(m3_fac)) o2$ctx$results$Model3Factors <- m3_fac
        o2$ctx$results$model3_significant <- m3_sig
        o2$ctx$results$dual_db_covariate_harmonized <- TRUE
        o2$ctx$results$dual_db_cox_covariates_locked <- TRUE
        o2$ctx$results$dual_db_force_export_harmonized_multivar <- TRUE
        saveRDS(o2, fp)
      }
    }

    cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
    # 输出必须落在 by_index/<ix>/<DB>/，勿覆写为研究根目录（否则 S7 进根 Tables 而汇总缺失）
    out_base <- bc$output_base %||% config_ix$project$output_dir %||% root
    db_slot <- dual_db_slot_path_name(config_ix, db)
    cfg_db$project$output_dir <- file.path(survival_batch_index_pub_root(config_ix, ix), db_slot)
    cfg_db$project$root <- out_base
    cfg_db$survival$index_var <- ix
    m2_full <- m2_db
    cfg_db$multivariate_prognosis_harmonized <- utils::modifyList(
      cfg_db$multivariate_prognosis_harmonized %||% list(),
      list(
        force_export = TRUE,
        defer_until_cox_lock = FALSE,
        table_number = 7L,
        input_from = "Model2Factors",
        write_model_factors = FALSE,
        fixed_model1_factors = m1_db,
        fixed_model2_factors = m2_full,
        table_file_caption = if (exists("locked_multivariable_table_caption", mode = "function")) {
          locked_multivariable_table_caption(cfg_db, n_db = length(db_seq))
        } else {
          "Multivariable Regression Analysis harmonized"
        },
        table_title_caption = if (exists("locked_multivariable_table_caption", mode = "function")) {
          locked_multivariable_table_caption(cfg_db, n_db = length(db_seq))
        } else {
          "Multivariable Regression Analysis harmonized"
        }
      )
    )
    # 确保 pipeline 含 multi block
    pipe <- incidence_batch_set_pipeline_ck(pipeline, per_ck)
    blks <- as.character(pipe$blocks %||% character(0))
    if (!("multivariate_prognosis_harmonized" %in% blks)) {
      ins <- match("dual_db_covariate_harmonize", blks)
      if (is.na(ins)) ins <- match("multicollinearity_final", blks)
      if (is.na(ins)) ins <- length(blks)
      blks <- append(blks, "multivariate_prognosis_harmonized", after = ins)
      pipe$blocks <- blks
    }
    # dual_db 之后写 S7；from=seed 表示从 seed 续跑
    from_seed <- if (identical(seed, "multivariate_prognosis_harmonized") ||
                     grepl("^cox_", seed)) {
      # 用 dual_db / vif 作起点
      if (file.exists(file.path(per_ck, "dual_db_covariate_harmonize.rds"))) {
        "dual_db_covariate_harmonize"
      } else {
        "multicollinearity_final"
      }
    } else {
      seed
    }
    cli::cli_alert_info(
      "[{ix}] {dual_db_slot_path_name(config_ix, db)} 写出 Table S7（协变量={paste(m2_db, collapse = ', ')}）from={from_seed}"
    )
    # 再写 dual_db 别名 ck，保证 resume Model2=锁定集
    if (file.exists(file.path(per_ck, "dual_db_covariate_harmonize.rds"))) {
      o2 <- tryCatch(readRDS(file.path(per_ck, "dual_db_covariate_harmonize.rds")), error = function(e) NULL)
      if (!is.null(o2$ctx)) {
        o2$ctx$results$Model1Factors <- m1_db
        o2$ctx$results$Model2Factors <- m2_db
        if (length(cox_final)) {
          o2$ctx$results$cox_final_factors <- cox_final
          o2$ctx$results$logistic_final_factors <- cox_final
        }
        if (length(m3_fac)) o2$ctx$results$Model3Factors <- m3_fac
        o2$ctx$results$model3_significant <- m3_sig
        o2$ctx$results$dual_db_covariate_harmonized <- TRUE
        o2$ctx$results$dual_db_cox_covariates_locked <- TRUE
        o2$ctx$results$dual_db_force_export_harmonized_multivar <- TRUE
        saveRDS(o2, file.path(per_ck, "dual_db_covariate_harmonize.rds"))
      }
    }
    run_pipeline(
      root, config = cfg_db, pipeline = pipe,
      run_opts = list(from = from_seed, to = "multivariate_prognosis_harmonized")
    )
  }
  invisible(TRUE)
}

# ── 主函数 ────────────────────────────────────────────────────────────────────
run_survival_dual_batch <- function(root,
                                    config,
                                    pipeline_regular_batch,
                                    pipeline_shared_regular,
                                    run_opts = list(),
                                    config_path = NULL) {
  root   <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- .survival_batch_bind_config(config)
  bc     <- config$survival_batch %||% config$incidence_batch %||% list()

  shared_only    <- isTRUE(run_opts$shared_only)
  only_index     <- run_opts$only_index %||% NULL
  workers_raw    <- run_opts$workers %||% bc$parallel_workers
  auto_workers   <- is.null(workers_raw) ||
    identical(tolower(trimws(as.character(workers_raw))), "auto")
  workers        <- if (!auto_workers) max(1L, as.integer(workers_raw)) else NA_integer_
  db_mode        <- run_opts$db_mode %||% bc$db_mode %||% "both"
  skip_exist     <- isTRUE(run_opts$skip_existing %||% bc$skip_existing %||% TRUE)
  # 未显式 --ptrim 时：用配置；未写则 0（只剔 index 缺失，不硬开极端值）
  p_trim_raw     <- run_opts$p_trim
  if (is.null(p_trim_raw) || (length(p_trim_raw) == 1L && is.na(p_trim_raw)))
    p_trim_raw <- bc$trim_quantile %||% 0
  p_trim         <- as.numeric(p_trim_raw)
  if (!is.finite(p_trim) || p_trim < 0) p_trim <- 0

  candidate_vars <- incidence_batch_resolve_index_vars(config)
  cli::cli_h1("Survival Dual Batch — 候选 {length(candidate_vars)} 个指标")
  cli::cli_alert_info("db_mode={db_mode}, workers={workers_raw %||% 'auto'}, skip_existing={skip_exist}, trim={p_trim*100}%")

  db_seq <- switch(db_mode, nhanes = "nhanes", mimic = "mimic", c("nhanes", "mimic"))

  if (isTRUE(config$dual_db$enable)) {
    config <- tryCatch(
      incidence_batch_ensure_gate_a(config, root, force = !skip_exist)$config,
      error = function(e) {
        cli::cli_alert_warning("Gate A 失败: {e$message}，共享层将跳过列限制")
        config
      }
    )
  }

  for (db in db_seq) {
    shared_read  <- incidence_batch_shared_ck_dir(config, db)
    shared_write <- incidence_batch_shared_ck_canonical_dir(config, db)
    alias_path   <- file.path(shared_read, "index.rds")

    if (file.exists(alias_path) && isTRUE(skip_exist)) {
      cli::cli_alert_info("共享层 [{dual_db_slot_path_name(config, db)}] 已存在，跳过")
    } else {
      cli::cli_h2("运行共享层 [{dual_db_slot_path_name(config, db)}]")
      incidence_batch_run_shared_layer(
        root, config, db, pipeline_shared_regular, shared_write
      )
    }
  }

  if (shared_only) {
    avail <- tryCatch(
      incidence_batch_resolve_from_shared_ck(config, candidate_vars, db_mode),
      error = function(e) { cli::cli_alert_warning(e$message); candidate_vars }
    )
    cli::cli_alert_success("--shared-only 完成，实际可用指标: {length(avail)} 个")
    return(invisible(avail))
  }

  for (db in db_seq) {
    p <- file.path(incidence_batch_shared_ck_dir(config, db), "index.rds")
    if (!file.exists(p)) p <- .batch_wsl_to_win(p)
    if (!file.exists(p))
      stop("共享层检查点缺失: ", p, "\n请先运行 --shared-only", call. = FALSE)
  }

  cli::cli_h2("从共享层 checkpoint 筛查实际可用指标")
  index_vars <- tryCatch(
    incidence_batch_resolve_from_shared_ck(config, candidate_vars, db_mode),
    error = function(e) {
      cli::cli_alert_warning("读取 checkpoint 失败: {e$message}，使用候选全量")
      candidate_vars
    }
  )
  cli::cli_alert_success("最终批量指标: {length(index_vars)} 个")

  effective_n <- if (!is.null(only_index) && length(only_index))
    length(intersect(index_vars, only_index)) else length(index_vars)

  if (auto_workers) {
    workers <- incidence_batch_auto_workers(
      n_indices       = effective_n,
      ram_per_worker  = bc$ram_per_worker_gb %||% 2.0,
      cpu_headroom    = bc$cpu_headroom %||% 2L,
      ram_headroom_gb = bc$ram_headroom_gb %||% 4.0,
      max_workers     = bc$max_workers %||% NULL
    )
  } else {
    cli::cli_alert_info(
      "Worker 数: {workers}（手动）| 指标数: {effective_n} | CPU: {parallel::detectCores(logical=TRUE)}"
    )
  }

  incidence_batch_dispatch_workers(
    root          = root,
    config        = config,
    index_vars    = index_vars,
    workers       = workers,
    log_dir       = file.path(bc$output_base %||% config$project$output_dir, "logs"),
    db_mode       = db_mode,
    only          = only_index,
    skip_existing = skip_exist,
    p_trim        = p_trim,
    config_path   = config_path,
    worker_script = "run/survival/run_survival_dual_batch_worker.R"
  )

  output_base <- bc$output_base %||% config$project$output_dir
  statuses    <- incidence_batch_read_all_status(output_base, index_vars)
  incidence_batch_print_summary(statuses)

  out_dir <- file.path(output_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Batch_summary_all_indices.csv")
  tryCatch(
    utils::write.csv(statuses, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("汇总 CSV 写入失败: {e$message}")
  )
  cli::cli_alert_success("汇总表: {.file {csv_path}}")

  fs <- config$feishu %||% list()
  if (isTRUE(fs$push_on_batch_summary) &&
      exists("incidence_batch_feishu_update_summary", mode = "function")) {
    tryCatch(
      incidence_batch_feishu_update_summary(config, statuses),
      error = function(e) cli::cli_alert_warning("飞书汇总行更新失败: {e$message}")
    )
  }

  survival_worker <- "run/survival/run_survival_dual_batch_worker.R"

  if (!isTRUE(run_opts$shared_only)) {
    sgfb <- (config$survival_batch %||% config$incidence_batch %||% list())$subgroup_fallback %||% list()
    if (isTRUE(sgfb$enable) && exists("incidence_subgroup_fallback_pass", mode = "function")) {
      failed_ix <- as.character(statuses$index[statuses$status %in% c("error", "failed")])
      failed_ix <- failed_ix[nzchar(failed_ix)]
      if (length(failed_ix)) {
        tryCatch(
          incidence_subgroup_fallback_pass(root, config, failed_ix, config_path,
                                        worker_script = survival_worker),
          error = function(e) cli::cli_alert_warning("亚组补救阶段出错: {e$message}")
        )
      }
    }

    sens <- (config$survival_batch %||% config$incidence_batch %||% list())$sensitivity_suite %||% list()
    if (isTRUE(sens$enable) && exists("incidence_sensitivity_pass", mode = "function")) {
      success_ix <- as.character(statuses$index[statuses$status == "success"])
      success_ix <- success_ix[nzchar(success_ix)]
      if (!is.null(only_index) && length(only_index))
        success_ix <- intersect(success_ix, only_index)
      if (length(success_ix)) {
        tryCatch(
          incidence_sensitivity_pass(root, config, success_ix, config_path,
                                   only_index = only_index,
                                   worker_script = survival_worker,
                                   force = !skip_exist),
          error = function(e) cli::cli_alert_warning("敏感性分析阶段出错: {e$message}")
        )
      }
    }
  }

  invisible(statuses)
}

# ── 预后指标 Figure 1：纳排 + 指标缺失（+ 仅当实际做过时的极端值）────────────
survival_batch_pick_filter_row <- function(fs_db) {
  if (is.null(fs_db) || !is.list(fs_db)) {
    return(list(n_before = NA_integer_, n_na = NA_integer_,
                n_trim = NA_integer_, n_after = NA_integer_))
  }
  slot <- fs_db$mapped %||% fs_db$imputed %||% fs_db$cleaned %||% list()
  list(
    n_before = as.integer(slot$n_before %||% NA_integer_),
    n_na     = as.integer(slot$n_na %||% NA_integer_),
    n_trim   = as.integer(slot$n_trim %||% NA_integer_),
    n_after  = as.integer(slot$n_after %||% NA_integer_)
  )
}

#' 从 trim_index_extreme checkpoint / D02 README 读取极端值裁剪人数
#' （共享层 survival_batch$trim_quantile=0 时 filter_stats$n_trim 恒为 0，须从此处补）
survival_batch_load_trim_extreme_meta <- function(project_root, ix, db,
                                                   config = NULL,
                                                   index_root = NULL) {
  project_root <- as.character(project_root %||% "")[1L]
  ix <- as.character(ix %||% "")[1L]
  db <- as.character(db %||% "")[1L]
  if (!nzchar(project_root) || !nzchar(ix) || !nzchar(db)) return(NULL)

  db_disp <- if (!is.null(config) && exists("dual_db_slot_path_name", mode = "function")) {
    tryCatch(dual_db_slot_path_name(config, db), error = function(e) db)
  } else {
    db
  }
  db_cands <- unique(c(db_disp, db, if (grepl("eicu|nhanes", db, ignore.case = TRUE)) c("eICU", "nhanes") else c("MIMIC", "mimic")))

  # 1) checkpoint rds
  for (d in db_cands) {
    ck <- file.path(project_root, "checkpoints", "by_index", ix, d, "trim_index_extreme.rds")
    if (!file.exists(ck)) next
    obj <- tryCatch(readRDS(ck), error = function(e) NULL)
    meta <- obj$ctx$results$trim_index_extreme$meta %||% obj$results$trim_index_extreme$meta
    if (is.list(meta) && length(meta)) {
      return(list(
        n_trim  = suppressWarnings(as.integer(meta$n_trim %||% NA_integer_)),
        n_after = suppressWarnings(as.integer(meta$n_after %||% NA_integer_)),
        n_after_na = suppressWarnings(as.integer(meta$n_after_na %||% NA_integer_)),
        source = ck
      ))
    }
  }

  # 2) step Data/README under index_root
  ix_root <- as.character(index_root %||% file.path(project_root, "by_index", ix))[1L]
  for (d in db_cands) {
    db_dir <- file.path(ix_root, d)
    if (!dir.exists(db_dir)) next
    steps <- list.dirs(db_dir, full.names = TRUE, recursive = FALSE)
    steps <- steps[grepl("trim_index_extreme", basename(steps), fixed = TRUE)]
    for (st in steps) {
      readme <- file.path(st, "Data", "D02_AfterTrim_Data.README.txt")
      if (!file.exists(readme)) next
      lines <- tryCatch(readLines(readme, warn = FALSE), error = function(e) character(0))
      if (!length(lines)) next
      kv <- list()
      for (ln in lines) {
        if (!grepl("=", ln, fixed = TRUE)) next
        parts <- strsplit(ln, "=", fixed = TRUE)[[1L]]
        if (length(parts) >= 2L) kv[[parts[1L]]] <- paste(parts[-1L], collapse = "=")
      }
      n_trim <- suppressWarnings(as.integer(kv$n_trim %||% NA_integer_))
      n_after <- suppressWarnings(as.integer(kv$n_after %||% NA_integer_))
      if (is.finite(n_trim) || is.finite(n_after)) {
        return(list(n_trim = n_trim, n_after = n_after, n_after_na = NA_integer_, source = readme))
      }
    }
  }
  NULL
}

#' 把 trim_index_extreme 人数并入 filter_stats（改 n_trim / n_after）
survival_batch_enrich_filter_stats_with_trim <- function(filter_stats, project_root, ix,
                                                          db_seq, config = NULL,
                                                          index_root = NULL) {
  filter_stats <- filter_stats %||% list()
  for (db in db_seq) {
    meta <- survival_batch_load_trim_extreme_meta(
      project_root, ix, db, config = config, index_root = index_root
    )
    if (is.null(meta)) next
    n_trim <- suppressWarnings(as.integer(meta$n_trim %||% NA_integer_))
    n_after <- suppressWarnings(as.integer(meta$n_after %||% NA_integer_))
    n_after_na <- suppressWarnings(as.integer(meta$n_after_na %||% NA_integer_))
    if (!is.finite(n_trim) || n_trim <= 0L) next
    if (is.null(filter_stats[[db]])) filter_stats[[db]] <- list()
    if (is.null(filter_stats[[db]]$imputed)) filter_stats[[db]]$imputed <- list()
    imp <- filter_stats[[db]]$imputed
    # 若 status 缺 n_before/n_na：用 trim 前人数兜底（n_after_na = 删缺失后、裁极端值前）
    if ((!is.finite(suppressWarnings(as.integer(imp$n_before %||% NA_integer_)))) &&
        is.finite(n_after_na)) {
      imp$n_before <- n_after_na
    }
    if ((!is.finite(suppressWarnings(as.integer(imp$n_na %||% NA_integer_)))) &&
        is.finite(suppressWarnings(as.integer(imp$n_before %||% NA_integer_))) &&
        is.finite(n_after_na)) {
      imp$n_na <- max(0L, as.integer(imp$n_before) - n_after_na)
    }
    # 有完整 before/na 时，删缺失后的 N 应对齐 n_after_na
    if (is.finite(suppressWarnings(as.integer(imp$n_before %||% NA_integer_))) &&
        is.finite(suppressWarnings(as.integer(imp$n_na %||% NA_integer_))) &&
        is.finite(n_after_na)) {
      # 保持 status 的 before/na；仅校正 after/trim
    } else if (is.finite(n_after_na) &&
               !is.finite(suppressWarnings(as.integer(imp$n_before %||% NA_integer_)))) {
      imp$n_before <- n_after_na
      imp$n_na <- 0L
    }
    imp$n_trim <- n_trim
    if (is.finite(n_after)) imp$n_after <- n_after
    filter_stats[[db]]$imputed <- imp
    for (slot in c("mapped", "cleaned")) {
      if (!is.null(filter_stats[[db]][[slot]])) {
        filter_stats[[db]][[slot]]$n_trim <- n_trim
        if (is.finite(n_after)) filter_stats[[db]][[slot]]$n_after <- n_after
      }
    }
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_info(
        "Figure 1: [{db}] 并入 trim_index_extreme n_trim={n_trim}, n_after={n_after}"
      )
    }
  }
  filter_stats
}

survival_batch_load_cohort_flow_rows <- function(project_root, db_label) {
  csv <- file.path(project_root, "Tables", "Flowchart_attrition_dual.csv")
  if (!file.exists(csv)) return(NULL)
  dt <- tryCatch(utils::read.csv(csv, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(dt) || !nrow(dt)) return(NULL)
  lab <- tolower(as.character(db_label)[1L])
  want <- if (grepl("eicu|nhanes", lab)) "eicu" else "mimic"
  dbcol <- tolower(as.character(dt$database %||% character(0)))
  keep <- grepl(want, dbcol, fixed = TRUE)
  if (!any(keep)) return(NULL)
  data.frame(
    step = as.character(dt$step[keep]),
    n = as.integer(dt$n[keep]),
    stringsAsFactors = FALSE
  )
}

#' 绘制单库纳排流程图（Times 系字体）
survival_batch_draw_flowchart_pdf <- function(rows, title, pdf_path,
                                              font_family = "Times New Roman") {
  if (is.null(rows) || !nrow(rows)) return(invisible(FALSE))
  dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)
  n_box <- nrow(rows)
  if (exists("pipeline_pdf_device", mode = "function")) {
    ff <- pipeline_pdf_device(
      pdf_path, width = 8.5, height = max(6.5, 1.15 * n_box + 1.8),
      family = font_family
    )
  } else {
    ff <- if (exists("resolve_plot_font_family", mode = "function")) {
      resolve_plot_font_family(font_family)
    } else font_family
    if (identical(ff, "Times New Roman") && !isTRUE(capabilities("cairo"))) ff <- "Times"
    grDevices::pdf(pdf_path, width = 8.5, height = max(6.5, 1.15 * n_box + 1.8),
                   family = ff)
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- graphics::par(mar = c(0.4, 0.4, 2.2, 0.4), family = ff)
  on.exit(graphics::par(op), add = TRUE)
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1))
  graphics::title(main = title, cex.main = 1.05, family = ff)
  y_top <- 0.94
  box_h <- min(0.11, 0.82 / (n_box * 1.35))
  gap <- box_h * 0.32
  for (i in seq_len(n_box)) {
    y1 <- y_top - (i - 1) * (box_h + gap)
    y0 <- y1 - box_h
    graphics::rect(0.16, y0, 0.84, y1, border = "black", col = "#F7F7F7", lwd = 1.4)
    lab <- sprintf("%s\nN = %s", rows$step[i],
                   format(as.integer(rows$n[i]), big.mark = ","))
    graphics::text(0.5, (y0 + y1) / 2, lab, cex = 0.85, family = ff)
    if (i < n_box) {
      graphics::arrows(0.5, y0 - 0.004, 0.5, y0 - gap + 0.008, length = 0.07, lwd = 1.1)
      drop_n <- as.integer(rows$n[i]) - as.integer(rows$n[i + 1L])
      if (is.finite(drop_n) && drop_n > 0L) {
        graphics::text(
          0.87, y0 - gap / 2,
          sprintf("-%s", format(drop_n, big.mark = ",")),
          cex = 0.72, col = "#555555", adj = 0, family = ff
        )
      }
    }
  }
  invisible(TRUE)
}

#' 为某预后指标写出双库 Figure 1 流程图
#' - 前缀：项目级纳排（Tables/Flowchart_attrition_dual.csv）
#' - 必：指标缺失剔除人数（即使为 0 也写明）
#' - 极端值：仅当 n_trim>0 才加框（不做就从不假装删了）
survival_batch_write_index_flowcharts <- function(project_root, index_root, ix,
                                                   filter_stats, db_seq,
                                                   font_family = "Times New Roman",
                                                   config = NULL) {
  project_root <- normalizePath(project_root, winslash = "/", mustWork = FALSE)
  index_root   <- normalizePath(index_root, winslash = "/", mustWork = FALSE)
  fig_root <- file.path(index_root, "Figures")
  tab_root <- file.path(index_root, "Tables")
  dir.create(fig_root, recursive = TRUE, showWarnings = FALSE)
  dir.create(tab_root, recursive = TRUE, showWarnings = FALSE)
  proj_fig <- file.path(project_root, "Figures")
  dir.create(proj_fig, recursive = TRUE, showWarnings = FALSE)

  # 并入插补后 trim_index_extreme 实际删极端值人数（共享层 ptrim=0 时 filter_stats 不含）
  filter_stats <- survival_batch_enrich_filter_stats_with_trim(
    filter_stats, project_root, ix, db_seq,
    config = config, index_root = index_root
  )

  all_rows <- list()
  for (db in db_seq) {
    db_disp <- if (!is.null(config) && exists("dual_db_slot_path_name", mode = "function")) {
      tryCatch(dual_db_slot_path_name(config, db), error = function(e) NA_character_)
    } else NA_character_
    if (is.na(db_disp) || !nzchar(db_disp)) {
      db_disp <- if (identical(db, "nhanes") || grepl("eicu", db, ignore.case = TRUE))
        "eICU" else "MIMIC"
    }

    base_flow <- survival_batch_load_cohort_flow_rows(project_root, db_disp)
    fr <- survival_batch_pick_filter_row(filter_stats[[db]])

    extra <- list()
    # 指标分析起点：若纳排末行已是同一 N 则不再重复
    n_base_end <- if (!is.null(base_flow) && nrow(base_flow))
      as.integer(utils::tail(base_flow$n, 1L)) else NA_integer_
    if (is.finite(fr$n_before) &&
        !(is.finite(n_base_end) && n_base_end == fr$n_before)) {
      extra[[length(extra) + 1L]] <- data.frame(
        step = "Analytic cohort entering index analysis",
        n = fr$n_before, stringsAsFactors = FALSE
      )
    }

    # 缺失：始终展示 n excluded（含 0）
    if (is.finite(fr$n_before) && is.finite(fr$n_na)) {
      n_after_na <- fr$n_before - fr$n_na
      extra[[length(extra) + 1L]] <- data.frame(
        step = sprintf("After exclude missing %s (n excluded = %s)",
                       ix, format(as.integer(fr$n_na), big.mark = ",")),
        n = n_after_na, stringsAsFactors = FALSE
      )
    } else if (is.finite(fr$n_before) && is.finite(fr$n_after) &&
               (is.na(fr$n_trim) || fr$n_trim == 0L) &&
               fr$n_after <= fr$n_before) {
      n_ex <- fr$n_before - fr$n_after
      extra[[length(extra) + 1L]] <- data.frame(
        step = sprintf("After exclude missing %s (n excluded = %s)",
                       ix, format(as.integer(n_ex), big.mark = ",")),
        n = fr$n_after, stringsAsFactors = FALSE
      )
    }

    # 极端值：仅实际 n_trim>0
    if (is.finite(fr$n_trim) && fr$n_trim > 0L && is.finite(fr$n_after)) {
      extra[[length(extra) + 1L]] <- data.frame(
        step = sprintf("After exclude extreme %s (n excluded = %s)",
                       ix, format(as.integer(fr$n_trim), big.mark = ",")),
        n = fr$n_after, stringsAsFactors = FALSE
      )
    }

    if (is.finite(fr$n_after)) {
      extra[[length(extra) + 1L]] <- data.frame(
        step = sprintf("Final analytic population for %s", ix),
        n = fr$n_after, stringsAsFactors = FALSE
      )
    }

    extra_df <- if (length(extra)) do.call(rbind, extra) else NULL
    rows <- if (!is.null(base_flow) && nrow(base_flow)) {
      if (!is.null(extra_df)) rbind(base_flow, extra_df) else base_flow
    } else {
      extra_df
    }
    if (is.null(rows) || !nrow(rows)) next

    rows$database <- db_disp
    all_rows[[db_disp]] <- rows

    title <- sprintf(
      "Figure 1. %s inclusion/exclusion flowchart (%s, %s)",
      db_disp, ix,
      as.character(config$project$disease %||% config$project$analysis_group %||% "Outcome")[1L]
    )
    # 分库 Figure 1 只写各库子目录底稿；汇总 Figures / 项目根仅保留双库 Figure 1. Flowchart.pdf
    pdf_db2 <- file.path(index_root, db_disp, "Figures",
                         sprintf("Figure 1-%s. Inclusion exclusion flowchart.pdf", db_disp))
    dir.create(dirname(pdf_db2), recursive = TRUE, showWarnings = FALSE)
    survival_batch_draw_flowchart_pdf(rows, title, pdf_db2, font_family)
    if (file.exists(pdf_db2)) {
      cli::cli_alert_success("Figure 1 flowchart [{db_disp}]: {.file {basename(pdf_db2)}}")
    }
  }

  if (length(all_rows)) {
    comb <- do.call(rbind, all_rows)
    utils::write.csv(comb, file.path(tab_root, sprintf("Flowchart_attrition_%s_dual.csv", ix)),
                     row.names = FALSE)
    utils::write.csv(comb, file.path(project_root, "Tables",
                                     sprintf("Flowchart_attrition_%s_dual.csv", ix)),
                     row.names = FALSE)

    pdf_dual <- file.path(fig_root, "Figure 1. Flowchart.pdf")
    if (exists("pipeline_pdf_device", mode = "function")) {
      ff <- pipeline_pdf_device(pdf_dual, width = 11, height = 8.5, family = font_family)
    } else {
      ff <- if (exists("resolve_plot_font_family", mode = "function")) {
        resolve_plot_font_family(font_family)
      } else font_family
      if (identical(ff, "Times New Roman") && !isTRUE(capabilities("cairo"))) ff <- "Times"
      grDevices::pdf(pdf_dual, width = 11, height = 8.5, family = ff)
    }
    on.exit(grDevices::dev.off(), add = TRUE)
    graphics::par(mfrow = c(1, 2), mar = c(0.6, 0.4, 2.2, 0.4), family = ff)
    for (db_disp in names(all_rows)) {
      rows <- all_rows[[db_disp]]
      n_box <- nrow(rows)
      graphics::plot.new()
      graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1))
      graphics::title(main = paste0(db_disp, " - ", ix), cex.main = 1, family = ff)
      y_top <- 0.92
      box_h <- min(0.10, 0.8 / (n_box * 1.3))
      gap <- box_h * 0.28
      for (i in seq_len(n_box)) {
        y1 <- y_top - (i - 1) * (box_h + gap)
        y0 <- y1 - box_h
        graphics::rect(0.08, y0, 0.92, y1, border = "black", col = "#F7F7F7")
        graphics::text(
          0.5, (y0 + y1) / 2,
          sprintf("%s\nN = %s", rows$step[i], format(as.integer(rows$n[i]), big.mark = ",")),
          cex = 0.62, family = ff
        )
        if (i < n_box)
          graphics::arrows(0.5, y0 - 0.002, 0.5, y0 - gap + 0.006, length = 0.05)
      }
    }
    grDevices::dev.off()
    on.exit(NULL)
    # 指标级双库图只写 by_index/<ix>/Figures；不得覆盖课题根 Figure 1（课题级纳排）
    cli::cli_alert_success("Figure 1 dual flowchart: {.file {basename(pdf_dual)}}")
  }
  # 兜底：指标汇总目录不留分库 Figure 1 纳排单图（课题根 Figures 的分库底稿可保留）
  if (dir.exists(fig_root)) {
    stale <- list.files(
      fig_root,
      pattern = "^Figure 1-.+\\. Inclusion exclusion flowchart\\.pdf$",
      full.names = TRUE,
      ignore.case = TRUE
    )
    if (length(stale)) unlink(stale)
  }
  invisible(TRUE)
}
