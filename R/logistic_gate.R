###############################################################################
#  logistic_gate.R — 发病 Logistic 分位闸门（glm + NHANES 加权 Table 2）
#  级联：四分位 → 三分位 → 二分位 → 五分位（末招）
#  降级触发：参照组/分组完全分离，或「最高组」Crude/Model2 不显著
#  显著性口径（全项目）：只看最高暴露组 vs 参照（Q4/T3/高组/Q5），
#    不要求中间各档都显著；连续行不参与闸门。
#  列索引与 03decision_tree_incidence_single 一致：Crude P=第6列，Model2 P=第12列
#  OR=第4列，95%CI=第5列（分离时常出现极大 OR 或 (0,NA)/(0,Inf)）
#
#  汇总策略（交叉滞后 / 发病 summary_result）：
#    闸门确认主分组后，仅主分组 GLM（通常为 tertile → Table 2）进入汇总；
#    binary / quartile / quintile 敏感性表留在 phase step 目录，不进 summary_result
#    （见 Blocks/54_cross_lagged_full/phases/collect_summary_result.sh）。
#  RCS / Table S-XX：
#    图可标全部 OR=1/峰值交点（rcs_cutoffs_all）；
#    FI_RCS_Group 与 logistic_*_glm_rcs 只用主 cutoff 二分
#    （rcs_incidence$group_cutoffs = "primary"；禁止 "all" 进汇总）。
###############################################################################

logistic_gate_extend_branches <- function() {
  c("extend_quartile", "extend_tertile", "extend_binary", "extend_quintile")
}

# 闸门 stop 推迟到 Table 2 落盘之后，避免末档 NS 把主表一并吞掉
logistic_gate_apply_after_table_defer_stop <- function(ctx, bl_cfg, tb, raw_levels, block_name) {
  ctx$results$logistic_gate_pending_stop <- NULL
  tryCatch(
    logistic_gate_apply_after_table(ctx, bl_cfg, tb, raw_levels, block_name),
    error = function(e) {
      msg <- conditionMessage(e)
      if (grepl("^logistic_gate:", msg)) {
        ctx$results$logistic_gate_pending_stop <- msg
        ctx
      } else {
        stop(e)
      }
    }
  )
}

logistic_gate_throw_pending_stop <- function(ctx) {
  msg <- (ctx$results %||% list())$logistic_gate_pending_stop
  if (!is.null(msg) && nzchar(as.character(msg)[1L])) {
    stop(as.character(msg)[1L], call. = FALSE)
  }
  invisible(ctx)
}

#' GLM logistic block 配置：*_rcs 注册名自动切 phase=rcs 并读 rcs_incidence 分组列
logistic_glm_resolve_bl_cfg <- function(ctx, base_block) {
  cfg <- ctx$config %||% list()
  block_name <- as.character(ctx$current_block %||% base_block)[1L]
  # *_rcs 块优先读自身 config（如 logistic_binary_glm_rcs），再回退 base_block
  bl_cfg <- cfg[[block_name]] %||% cfg[[base_block]] %||% list()
  is_rcs <- grepl("_rcs$", block_name) || identical(bl_cfg$phase, "rcs")
  if (is_rcs) {
    bl_cfg$phase <- "rcs"
    bl_cfg$include_continuous_row <- isTRUE(bl_cfg$include_continuous_row %||% FALSE)
    bl_cfg$group_var <- bl_cfg$group_var %||% ctx$results$rcs_cutoff_group_col
    labels <- ctx$results$rcs_cutoff_group_labels
    if (is.null(bl_cfg$group_levels) && length(labels)) {
      bl_cfg$group_levels <- as.character(labels)
    }
  }
  data <- ctx$data$imputed %||% ctx$data$train %||% ctx$data$cleaned %||% ctx$data$mapped
  ix <- bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var %||%
    (cfg$survival %||% list())$index_var
  if (exists("pipeline_apply_categorical_exposure", mode = "function")) {
    bl_cfg <- pipeline_apply_categorical_exposure(bl_cfg, data, ix)
  }
  bl_cfg
}

logistic_gate_parse_pval <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x) || identical(toupper(x), "NA")) return(NA_real_)
  if (grepl("^\\s*<", x)) return(0.0001)
  if (identical(x, "Ref")) return(NA_real_)
  suppressWarnings(as.numeric(x))
}

#' 从 Table 2 矩阵提取非参照组 Crude / Model2 P 值
logistic_gate_extract_group_pvals <- function(tb, raw_levels) {
  if (is.matrix(tb)) tb <- as.data.frame(tb, stringsAsFactors = FALSE)
  glv <- as.character(raw_levels)
  if (length(glv) < 2L) {
    return(list(crude = numeric(0), model2 = numeric(0)))
  }
  non_ref <- glv[-1L]
  crude_ps  <- setNames(rep(NA_real_, length(non_ref)), non_ref)
  model2_ps <- setNames(rep(NA_real_, length(non_ref)), non_ref)
  if (!nrow(tb)) return(list(crude = crude_ps, model2 = model2_ps))
  for (i in seq_len(nrow(tb))) {
    lab <- trimws(as.character(tb[i, 1]))
    if (!lab %in% non_ref) next
    if (ncol(tb) >= 6L)  crude_ps[lab]  <- logistic_gate_parse_pval(tb[i, 6L])
    if (ncol(tb) >= 12L) model2_ps[lab] <- logistic_gate_parse_pval(tb[i, 12L])
  }
  list(crude = crude_ps, model2 = model2_ps)
}

logistic_gate_block_family <- function(block_name) {
  base <- sub("_rcs$", "", as.character(block_name)[1L])
  if (grepl("quintile", base, fixed = TRUE)) return("quintile")
  if (grepl("quartile", base, fixed = TRUE)) return("quartile")
  if (grepl("tertile", base, fixed = TRUE))  return("tertile")
  if (grepl("binary", base, fixed = TRUE))   return("binary")
  NA_character_
}

logistic_gate_rcs_family_for_branch <- function(branch) {
  branch <- as.character(branch)[1L]
  switch(branch,
    extend_quartile = "quartile",
    extend_tertile  = "tertile",
    extend_binary   = "binary",
    extend_quintile = "quintile",
    degrade_binary  = "binary",
    degrade_quintile = "quintile",
    NA_character_
  )
}

#' RCS 主表分位族：优先 config$dual_db$harmonization$rcs_main_family_by_db[[current_db]]
logistic_gate_rcs_family_for_ctx <- function(ctx) {
  cfg  <- ctx$config %||% list()
  dual <- cfg$dual_db %||% list()
  harm <- dual$harmonization %||% list()
  fam_map <- harm$rcs_main_family_by_db %||% list()
  db <- as.character(dual$current_db %||% "")[1L]
  if (nzchar(db) && !is.null(fam_map[[db]]) && nzchar(as.character(fam_map[[db]])[1L])) {
    return(as.character(fam_map[[db]])[1L])
  }
  branch <- as.character(ctx$results$logistic_branch %||% "")[1L]
  logistic_gate_rcs_family_for_branch(branch)
}

logistic_gate_scheme_from_branch <- function(branch) {
  branch <- as.character(branch %||% "")[1L]
  if (!nzchar(branch)) return(NA_character_)
  # 仅 extend_* 锁定主文分位；degrade_* 不得写入 selected_scheme，
  # 否则会误跳过下一档（如 degrade_tertile 曾被映射成 quartile → 跳过三分位、无 Table 2）
  switch(branch,
    extend_quartile   = "quartile",
    extend_tertile    = "tertile",
    extend_binary     = "binary",
    extend_quintile   = "quintile",
    NA_character_
  )
}

#' 最高暴露组标签（分位末档 / 二分高组）
logistic_gate_highest_level <- function(raw_levels) {
  glv <- as.character(raw_levels %||% character(0))
  if (!length(glv)) return(NA_character_)
  glv[[length(glv)]]
}

#' 闸门显著性：默认只看最高组 P（crude / model2）
logistic_gate_highest_sig <- function(pvals, raw_levels, p_thresh = 0.05) {
  p_thresh <- as.numeric(p_thresh %||% 0.05)[1L]
  if (!is.finite(p_thresh) || p_thresh <= 0 || p_thresh >= 1) p_thresh <- 0.05
  high <- logistic_gate_highest_level(raw_levels)
  if (!nzchar(high) || is.na(high)) return(FALSE)
  pv <- suppressWarnings(as.numeric(pvals[[high]] %||% NA_real_))
  if (!is.finite(pv)) {
    # 名称对不上时退回向量末个有限 P（仍表示「最高组」位置）
    finite <- suppressWarnings(as.numeric(pvals))
    finite <- finite[is.finite(finite)]
    if (!length(finite)) return(FALSE)
    pv <- finite[[length(finite)]]
  }
  isTRUE(pv < p_thresh)
}

#' 级联深度：四分位=1 → 三分位=2 → 二分位=3 → 五分位=4（末招；越深表示越降级）
logistic_gate_scheme_depth <- function(scheme) {
  scheme <- as.character(scheme %||% "")[1L]
  switch(scheme, quartile = 1L, tertile = 2L, binary = 3L, quintile = 4L, 0L)
}

#' 双库统一分位：取更深级联层（两库都能过闸的共有方案）
#' 例：NHANES=tertile、MIMIC=quartile → 统一 tertile（与
#' Blocks/00_dual_db/04block_dual_db_logistic_scheme_harmonize.R 一致）。
#' 深度：quartile=1 < tertile=2 < binary=3 < quintile=4
logistic_gate_unify_schemes <- function(scheme_a, scheme_b) {
  da <- logistic_gate_scheme_depth(scheme_a)
  db <- logistic_gate_scheme_depth(scheme_b)
  depth <- max(da, db, na.rm = TRUE)
  if (!is.finite(depth) || depth < 1L) return(NA_character_)
  switch(as.character(depth),
         "1" = "quartile", "2" = "tertile", "3" = "binary", "4" = "quintile",
         NA_character_)
}

#' 解析 Table 单元格为数值 OR（极大值保留）
logistic_gate_parse_or <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x) || identical(toupper(x), "NA") || identical(x, "Ref")) return(NA_real_)
  suppressWarnings(as.numeric(x))
}

#' 检测分位 logistic 表是否完全/准完全分离
#' 规则（满足任一即判定分离）：
#'   1) 非参照组 Crude/Model2 OR ≥ or_huge（默认 1e4）
#'   2) 对应 95%CI 含 Inf/NA 且 OR 异常大（≥ 100）
#'   3) 非参照组 P≈1 且 OR 极大（典型分离假象）
logistic_gate_detect_separation <- function(tb, raw_levels, or_huge = 1e4) {
  if (is.matrix(tb)) tb <- as.data.frame(tb, stringsAsFactors = FALSE)
  glv <- as.character(raw_levels)
  out <- list(separated = FALSE, reasons = character(0), or_max = NA_real_)
  if (length(glv) < 2L || !nrow(tb) || ncol(tb) < 5L) return(out)
  non_ref <- glv[-1L]
  or_vals <- numeric(0)
  for (i in seq_len(nrow(tb))) {
    lab <- trimws(as.character(tb[i, 1]))
    if (!lab %in% non_ref) next
    or_v <- logistic_gate_parse_or(tb[i, 4L])
    ci_s <- trimws(as.character(tb[i, 5L] %||% ""))
    p6 <- if (ncol(tb) >= 6L) logistic_gate_parse_pval(tb[i, 6L]) else NA_real_
    p12 <- if (ncol(tb) >= 12L) logistic_gate_parse_pval(tb[i, 12L]) else NA_real_
    if (is.finite(or_v)) or_vals <- c(or_vals, or_v)
    ci_bad <- grepl("Inf|NA|\\(0,\\s*NA\\)|\\(0,\\s*Inf\\)", ci_s, ignore.case = TRUE)
    if (is.finite(or_v) && or_v >= or_huge) {
      out$separated <- TRUE
      out$reasons <- c(out$reasons, paste0(lab, " OR=", signif(or_v, 3), " ≥ ", or_huge))
    } else if (ci_bad && is.finite(or_v) && or_v >= 100) {
      out$separated <- TRUE
      out$reasons <- c(out$reasons, paste0(lab, " CI 异常且 OR=", signif(or_v, 3)))
    } else if (ci_bad && (!is.finite(or_v) || or_v >= 100)) {
      out$separated <- TRUE
      out$reasons <- c(out$reasons, paste0(lab, " CI=", ci_s))
    } else if (is.finite(or_v) && or_v >= or_huge / 10 &&
               ((is.finite(p6) && p6 > 0.9) || (is.finite(p12) && p12 > 0.9))) {
      out$separated <- TRUE
      out$reasons <- c(out$reasons, paste0(lab, " 极大 OR + P≈1（分离假象）"))
    }
  }
  if (length(or_vals)) out$or_max <- max(or_vals, na.rm = TRUE)
  out$reasons <- unique(out$reasons)
  out
}

logistic_gate_record_natural_branch <- function(ctx, branch) {
  branch <- as.character(branch %||% "")[1L]
  if (!nzchar(branch) || !grepl("^extend_", branch)) return(ctx)
  scheme <- logistic_gate_scheme_from_branch(branch)
  ctx$results$logistic_natural_branch <- branch
  if (!is.na(scheme)) ctx$results$logistic_natural_scheme <- scheme
  ctx
}

logistic_gate_sync_nhanes_scheme <- function(ctx) {
  if (isTRUE(ctx$results$dual_db_logistic_unified_locked)) {
    scheme <- as.character(ctx$results$nhanes_logistic_selected_scheme %||% "")[1L]
    if (nzchar(scheme)) {
      ctx$results$nhanes_logistic_grouping_scheme <- scheme
      ctx$results$logistic_grouping_scheme <- scheme
      return(ctx)
    }
  }
  branch <- as.character(ctx$results$logistic_branch %||% "")[1L]
  scheme <- logistic_gate_scheme_from_branch(branch)
  if (!is.na(scheme)) {
    ctx$results$nhanes_logistic_selected_scheme <- scheme
    ctx$results$nhanes_logistic_grouping_scheme <- scheme
    ctx$results$logistic_grouping_scheme <- scheme
  }
  ctx
}

logistic_glm_export_as_main <- function(ctx, family, is_rcs = FALSE) {
  # RCS 分组 logistic → 附表（Table S），主文仅保留初筛 Table 2
  if (is_rcs) return(FALSE)
  # NHANES 加权主分析后的未加权 GLM = 敏感性 → 附表
  if (!is.null(ctx$results$logistic_table2_weighted) ||
      !is.null(ctx$results$nhanes_logistic_table2)) {
    return(FALSE)
  }
  if (exists(".lnw00_weighted_export_as_main", mode = "function")) {
    return(isTRUE(.lnw00_weighted_export_as_main(
      ctx, family, is_rcs = FALSE, gate_enable = TRUE
    )))
  }
  scheme <- as.character(
    ctx$results$nhanes_logistic_selected_scheme %||%
      ctx$results$logistic_grouping_scheme %||% ""
  )[1L]
  if (isTRUE(ctx$results$dual_db_logistic_unified_locked) && nzchar(scheme)) {
    return(identical(scheme, family))
  }
  branch <- as.character(ctx$results$logistic_branch %||% "")[1L]
  if (identical(branch, paste0("extend_", family))) return(TRUE)
  identical(as.character(family)[1L], "binary") &&
    !grepl("^extend_(quartile|tertile|quintile)$", branch)
}

#' 是否应 export_sci_table（双库闸门可压掉非主方案；ML assoc force_export 强制全导出）
logistic_glm_should_export <- function(ctx, family, is_rcs = FALSE, bl_cfg = list()) {
  if (isTRUE(bl_cfg$force_export %||% FALSE)) return(TRUE)
  if (isTRUE(is_rcs)) return(TRUE)
  if (exists("logistic_glm_export_as_main", mode = "function") &&
      isTRUE(logistic_glm_export_as_main(ctx, family, is_rcs = is_rcs))) {
    return(TRUE)
  }
  # 已锁定最终分位时：非选中档（如选了 tertile 的 binary）不得进发表 Tables
  selected <- tolower(as.character(
    ctx$results$nhanes_logistic_selected_scheme %||%
      ctx$results$logistic_grouping_scheme %||%
      ((ctx$config %||% list())$logistic_gate %||% list())$grouping %||%
      ((ctx$config %||% list())$cox_gate %||% list())$grouping %||%
      ""
  )[1L])
  fam <- tolower(as.character(family %||% "")[1L])
  if (nzchar(selected) && nzchar(fam) &&
      selected %in% c("quartile", "tertile", "binary", "quintile", "median") &&
      !identical(selected, fam)) {
    return(FALSE)
  }
  cfg <- ctx$config %||% list()
  if (!isTRUE((cfg$dual_db %||% list())$enable)) return(TRUE)
  if (!is.null(ctx$results$logistic_table2_weighted) ||
      !is.null(ctx$results$nhanes_logistic_table2)) {
    # 有加权主表时：仅导出与主文分位一致的未加权敏感性表（附表）；
    # export_as_main 对此恒为 FALSE，故不可依赖「主表放行」分支。
    if (nzchar(selected) && identical(selected, fam)) return(TRUE)
    return(FALSE)
  }
  # dual_db 开启但无闸门分支时仍应出表；仅当尚未锁定分位时 binary 末档兜底
  branch <- as.character(ctx$results$logistic_branch %||% "")[1L]
  if (!nzchar(branch) && !isTRUE(ctx$results$dual_db_logistic_unified_locked)) {
    return(TRUE)
  }
  if (nzchar(selected)) return(FALSE)
  identical(fam, "binary")
}

logistic_gate_maybe_save_dual_db_branch <- function(ctx) {
  cfg <- ctx$config %||% list()
  dual <- cfg$dual_db %||% list()
  if (!isTRUE(dual$enable)) return(invisible(NULL))
  db_name <- as.character(dual$current_db %||% "")[1L]
  primary <- as.character((dual$primary %||% list())$db_type %||% "nhanes")[1L]
  if (!identical(db_name, primary)) return(invisible(NULL))
  branch <- as.character(ctx$results$logistic_branch %||% "")[1L]
  if (!nzchar(branch) || !grepl("^extend_", branch)) return(invisible(NULL))
  if (!exists("dual_db_save_logistic_branch", mode = "function")) return(invisible(NULL))
  root <- normalizePath(cfg$project$root %||% getwd(), winslash = "/", mustWork = FALSE)
  scheme <- as.character(ctx$results$nhanes_logistic_grouping_scheme %||% "")[1L]
  if (!nzchar(scheme)) scheme <- logistic_gate_scheme_from_branch(branch)
  dual_db_save_logistic_branch(
    root, cfg, branch = branch, scheme = scheme,
    detail = ctx$results$logistic_gate_detail %||% NULL
  )
  invisible(TRUE)
}

#' Table 2 跑完后应用闸门（gate_enable=FALSE 或 phase=rcs 时无操作）
logistic_gate_apply_after_table <- function(ctx, bl_cfg, tb, raw_levels, block_name) {
  if (!isTRUE(bl_cfg$gate_enable %||% FALSE)) return(ctx)
  phase <- as.character(bl_cfg$phase %||% "screen")[1L]
  if (identical(phase, "rcs")) return(ctx)

  if (isTRUE(ctx$results$dual_db_logistic_unified_locked)) {
    ctx <- logistic_gate_sync_nhanes_scheme(ctx)
    return(ctx)
  }

  existing <- as.character(ctx$results$logistic_branch %||% "")[1L]
  if (nzchar(existing) && existing %in% logistic_gate_extend_branches()) {
    cli::cli_alert_info("logistic_gate: 保留已有扩展分支 {.val {existing}}")
    ctx <- logistic_gate_sync_nhanes_scheme(ctx)
    logistic_gate_maybe_save_dual_db_branch(ctx)
    return(ctx)
  }

  p_thresh <- as.numeric(bl_cfg$p_threshold %||% 0.05)[1L]
  if (!is.finite(p_thresh) || p_thresh <= 0 || p_thresh >= 1) p_thresh <- 0.05
  or_huge <- as.numeric(bl_cfg$separation_or_huge %||% 1e4)[1L]
  if (!is.finite(or_huge) || or_huge <= 0) or_huge <- 1e4

  glv <- as.character(raw_levels)
  pv  <- logistic_gate_extract_group_pvals(tb, glv)
  crude_ps  <- pv$crude
  model2_ps <- pv$model2

  # 兼容旧字段：any_sig；闸门决策改用最高组
  crude_any_sig <- any(is.finite(crude_ps) & crude_ps < p_thresh, na.rm = TRUE)
  model2_any_sig <- any(is.finite(model2_ps) & model2_ps < p_thresh, na.rm = TRUE)
  high_lab <- logistic_gate_highest_level(glv)
  crude_high_sig <- logistic_gate_highest_sig(crude_ps, glv, p_thresh)
  model2_high_sig <- logistic_gate_highest_sig(model2_ps, glv, p_thresh)
  crude_high_p <- suppressWarnings(as.numeric(crude_ps[[high_lab]] %||% NA_real_))
  if (!is.finite(crude_high_p)) {
    finite_crude <- crude_ps[is.finite(crude_ps)]
    if (length(finite_crude)) crude_high_p <- finite_crude[[length(finite_crude)]]
  }
  sep <- logistic_gate_detect_separation(tb, glv, or_huge = or_huge)

  is_binary <- length(glv) == 2L ||
    grepl("binary", block_name, fixed = TRUE)
  is_quintile <- length(glv) >= 5L ||
    grepl("quintile", block_name, fixed = TRUE)

  extend_branch  <- as.character(bl_cfg$extend_branch %||% "")[1L]
  degrade_branch <- as.character(bl_cfg$degrade_branch %||% "")[1L]

  force_degrade <- isTRUE(sep$separated)

  if (is_binary) {
    binary_fail <- force_degrade || !crude_high_sig || !model2_high_sig
    if (binary_fail && nzchar(degrade_branch)) {
      ctx$results$logistic_branch <- degrade_branch
      why <- if (force_degrade) {
        paste0("分离: ", paste(sep$reasons, collapse = "; "))
      } else if (!crude_high_sig) {
        paste0("Crude 最高组(", high_lab, ") P=",
               if (is.finite(crude_high_p)) format(round(crude_high_p, 4), scientific = FALSE) else "NA")
      } else {
        "Model2 最高组不显著"
      }
      cli::cli_alert_info("logistic_gate: 二分位失败（{why}）→ {degrade_branch}")
    } else if (binary_fail && isTRUE(bl_cfg$stop_if_crude_highest_ns %||% FALSE) && !nzchar(degrade_branch)) {
      stop(
        "logistic_gate: 二分位失败且无进一步降级（五分位）。Crude 最高组 (", high_lab, ") P=",
        if (is.finite(crude_high_p)) format(round(crude_high_p, 4), scientific = FALSE) else "NA",
        if (force_degrade) paste0("; 分离: ", paste(sep$reasons, collapse = "; ")) else "",
        "，终止项目。",
        call. = FALSE
      )
    } else if (nzchar(extend_branch) && !binary_fail) {
      ctx$results$logistic_branch <- extend_branch
      ctx <- logistic_gate_record_natural_branch(ctx, extend_branch)
      cli::cli_alert_success("logistic_gate: 二分位 → {extend_branch}")
    }
  } else if (force_degrade) {
    if (nzchar(degrade_branch)) {
      ctx$results$logistic_branch <- degrade_branch
      cli::cli_alert_warning(
        "logistic_gate: 检测到分离（{paste(sep$reasons, collapse = '; ')}）→ {degrade_branch}"
      )
    } else if (is_quintile && isTRUE(bl_cfg$stop_if_separation %||% TRUE)) {
      stop(
        "logistic_gate: 五分位仍分离（", paste(sep$reasons, collapse = "; "),
        "），终止分位级联。",
        call. = FALSE
      )
    }
  } else if (!crude_high_sig) {
    if (isTRUE(bl_cfg$stop_if_crude_all_ns %||% FALSE) && !nzchar(degrade_branch)) {
      stop(
        "logistic_gate: Crude 最高组(", high_lab, ") P >= ", p_thresh, "，终止项目。",
        call. = FALSE
      )
    }
    if (nzchar(degrade_branch)) {
      ctx$results$logistic_branch <- degrade_branch
      cli::cli_alert_info(
        "logistic_gate: Crude 最高组({high_lab}) 不显著 (P={format(round(crude_high_p, 4), scientific = FALSE)}) → {degrade_branch}"
      )
    }
  } else if (model2_high_sig && nzchar(extend_branch)) {
    ctx$results$logistic_branch <- extend_branch
    ctx <- logistic_gate_record_natural_branch(ctx, extend_branch)
    cli::cli_alert_success("logistic_gate: 最高组 Model2 显著 → {extend_branch}")
  } else if (nzchar(degrade_branch)) {
    ctx$results$logistic_branch <- degrade_branch
    cli::cli_alert_info("logistic_gate: 最高组 Model2 不显著 → {degrade_branch}")
  } else if (is_quintile && nzchar(extend_branch) && model2_high_sig) {
    ctx$results$logistic_branch <- extend_branch
    ctx <- logistic_gate_record_natural_branch(ctx, extend_branch)
    cli::cli_alert_success("logistic_gate: 五分位最高组 Model2 显著 → {extend_branch}")
  }

  ctx$results$logistic_gate_detail <- list(
    block = block_name,
    raw_levels = glv,
    highest_level = high_lab,
    crude_ps = crude_ps,
    model2_ps = model2_ps,
    crude_any_sig = crude_any_sig,
    model2_any_sig = model2_any_sig,
    crude_high_sig = crude_high_sig,
    model2_high_sig = model2_high_sig,
    separation = sep,
    p_threshold = p_thresh,
    branch = ctx$results$logistic_branch %||% NA_character_
  )
  ctx <- logistic_gate_sync_nhanes_scheme(ctx)
  logistic_gate_maybe_save_dual_db_branch(ctx)
  ctx
}

#' pipeline 是否跳过该 block（须 pipeline$logistic_gate$enable = TRUE）
pipeline_logistic_gate_should_skip <- function(block_name, ctx, pipeline) {
  if (exists("pipeline_categorical_exposure_should_skip_block", mode = "function") &&
      isTRUE(pipeline_categorical_exposure_should_skip_block(block_name, ctx))) {
    return(TRUE)
  }
  gate_cfg <- pipeline$logistic_gate %||% list()
  if (!isTRUE(gate_cfg$enable)) return(FALSE)

  branch <- as.character(ctx$results$logistic_branch %||% "")[1L]
  if (!nzchar(branch)) return(FALSE)

  is_rcs <- grepl("_rcs$", block_name)
  family <- logistic_gate_block_family(block_name)

  if (is_rcs) {
    want <- logistic_gate_rcs_family_for_ctx(ctx)
    if (!is.na(want) && !is.na(family) && !identical(family, want)) {
      return(TRUE)
    }
    return(FALSE)
  }

  # 双库初筛未锁定统一方案前：真双库须三档都跑；单库 ML 仍按闸门跳过更粗分位
  dual <- ctx$config$dual_db %||% list()
  if (isTRUE(dual$enable) && !isTRUE(ctx$results$dual_db_logistic_unified_locked)) {
    single_primary <- FALSE
    if (exists("ml_dual_is_single_primary_db", mode = "function")) {
      single_primary <- isTRUE(ml_dual_is_single_primary_db(ctx))
    } else {
      batch <- ctx$config$ml_batch %||% ctx$config$incidence_batch %||% list()
      db_mode <- tolower(as.character(batch$db_mode %||% "")[1L])
      sec <- trimws(as.character((dual$secondary %||% list())$name %||% ""))[1L]
      single_primary <- identical(db_mode, "nhanes") ||
        identical(toupper(sec), "UNUSED") || !nzchar(sec)
    }
    if (!single_primary) return(FALSE)
  }

  screen_skip <- list(
    extend_quartile = c(
      "logistic_tertile_nhanes_weighted", "logistic_binary_nhanes_weighted",
      "logistic_quintile_nhanes_weighted",
      "logistic_tertile_glm", "logistic_binary_glm", "logistic_quintile_glm"
    )
  )
  skip_list <- screen_skip[[branch]] %||% character(0)
  if (isTRUE(ctx$results$dual_db_logistic_unified_locked)) {
    follower_skip <- list(
      extend_quartile = c(
        "logistic_tertile_nhanes_weighted", "logistic_binary_nhanes_weighted",
        "logistic_quintile_nhanes_weighted",
        "logistic_tertile_glm", "logistic_binary_glm", "logistic_quintile_glm"
      ),
      extend_tertile = c(
        "logistic_binary_nhanes_weighted", "logistic_quintile_nhanes_weighted",
        "logistic_binary_glm", "logistic_quintile_glm"
      ),
      extend_binary = c(
        "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
        "logistic_quintile_nhanes_weighted",
        "logistic_quartile_glm", "logistic_tertile_glm", "logistic_quintile_glm"
      ),
      extend_quintile = c(
        "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
        "logistic_binary_nhanes_weighted",
        "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm"
      )
    )
    skip_list <- unique(c(skip_list, follower_skip[[branch]] %||% character(0)))
  }
  # 单库：一旦锁定扩展分支，跳过更粗/末招级联块
  if (!isTRUE(dual$enable) || isTRUE(ctx$results$dual_db_logistic_unified_locked)) {
    single_skip <- list(
      extend_quartile = c(
        "logistic_tertile_glm", "logistic_binary_glm", "logistic_quintile_glm",
        "logistic_tertile_nhanes_weighted", "logistic_binary_nhanes_weighted"
      ),
      extend_tertile = c(
        "logistic_binary_glm", "logistic_quintile_glm",
        "logistic_binary_nhanes_weighted"
      ),
      extend_binary = c("logistic_quintile_glm", "logistic_quintile_nhanes_weighted"),
      extend_quintile = character(0)
    )
    skip_list <- unique(c(skip_list, single_skip[[branch]] %||% character(0)))
  }
  isTRUE(block_name %in% skip_list)
}

#' 写入标准分位级联默认值：四分位→三分位→二分位→五分位
#' 分离或不显著则降级；五分位为末招
logistic_gate_apply_cascade_defaults <- function(config, index_var = NULL) {
  index_var <- as.character(
    index_var %||%
      (config$incidence %||% list())$index_var %||%
      (config$logistic %||% list())$index_var %||% "Index"
  )[1L]
  rs <- list(
    max_outer_attempts = 100L, max_inner_attempts = 10L,
    initial_factors_n = 1L, p_threshold = 0.05, seed = NULL
  )
  base <- list(
    index_var = index_var,
    include_continuous_row = TRUE,
    gate_enable = TRUE,
    p_threshold = 0.05,
    phase = "screen",
    random_search = rs,
    pause_enable = FALSE,
    pause_on_search_fail = FALSE
  )
  patch <- function(nm, extra) {
    cur <- config[[nm]] %||% list()
    # 级联字段覆盖旧 config 中 gate_enable=FALSE 等
    config[[nm]] <<- utils::modifyList(cur, utils::modifyList(base, extra))
  }
  patch("logistic_quartile_glm", list(
    stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_quartile",
    degrade_branch = "degrade_tertile"
  ))
  patch("logistic_tertile_glm", list(
    stop_if_crude_all_ns = FALSE,
    extend_branch = "extend_tertile",
    degrade_branch = "degrade_binary"
  ))
  patch("logistic_binary_glm", list(
    stop_if_crude_highest_ns = FALSE,
    extend_branch = "extend_binary",
    degrade_branch = "degrade_quintile"
  ))
  patch("logistic_quintile_glm", list(
    stop_if_crude_all_ns = TRUE,
    stop_if_separation = TRUE,
    extend_branch = "extend_quintile",
    degrade_branch = character(0)
  ))
  # RCS 复跑块：继承 gate_enable=FALSE（不改 branch），仅复用分组
  for (nm in c(
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs",
    "logistic_binary_glm_rcs", "logistic_quintile_glm_rcs"
  )) {
    cur <- config[[nm]] %||% list()
    if (is.null(config[[nm]])) {
      stem <- sub("_rcs$", "", nm)
      config[[nm]] <- utils::modifyList(config[[stem]] %||% base, list(phase = "rcs", gate_enable = FALSE))
    } else {
      config[[nm]]$phase <- cur$phase %||% "rcs"
      config[[nm]]$gate_enable <- FALSE
    }
  }
  config
}

