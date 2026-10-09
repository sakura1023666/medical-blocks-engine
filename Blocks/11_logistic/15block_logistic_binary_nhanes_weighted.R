###############################################################################
#  logistic_binary_nhanes_weighted — NHANES 加权二分位 Logistic（svyglm Table 2）。
#
#  register_block: "logistic_binary_nhanes_weighted"
#  cascade 第 3 步: 若已选定分组则跳过；否则以二分位为主 Table 2（兜底）
###############################################################################

.lqb09_cascade_cfg <- function(cfg) {
  cc <- (cfg$logistic_nhanes_weighted %||% list())$cascade %||% list()
  list(
    threshold = as.numeric(cc$crude_p_threshold %||% 0.05)[1L],
    method = cc$crude_sig_method %||% "trend_or_any_group"
  )
}

.lqb09_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lqb09_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(block = "logistic_binary_nhanes_weighted", reason = reason, suggestion = suggestion, data_snapshot = snap)
  stop("PAUSE_FOR_USER_DECISION: logistic_binary_nhanes_weighted — ", reason, call. = FALSE)
}

.lqb09_coef_row <- function(fit, row_name) {
  .lnw00_coef_row(fit, row_name)
}

.lqb09_svyglm_fit <- function(design, formula_str) {
  tryCatch(survey::svyglm(stats::as.formula(formula_str), design = design, family = stats::quasibinomial()), error = function(e) NULL)
}

.lqb09_group_pct <- function(design, level) {
  pub_svy_group_events_n_cell(design, level, outcome_col = "Disease_Group", group_col = "Group")
}

.lqb09_weighted_quantiles <- function(design, index_var, probs) {
  qq <- survey::svyquantile(stats::as.formula(paste0("~", index_var)), design, quantiles = probs, na.rm = TRUE)
  if (index_var %in% names(qq)) {
    mat <- qq[[index_var]]
    if (is.matrix(mat) && "quantile" %in% colnames(mat)) return(as.numeric(mat[, "quantile", drop = TRUE]))
    return(as.numeric(mat))
  }
  if (!is.null(qq$quantiles)) return(as.numeric(qq$quantiles))
  as.numeric(unlist(qq, use.names = FALSE))
}

.lqb09_apply_native <- function(design, index_var) {
  raw <- design$variables[[index_var]]
  raw_levels <- sort(unique(as.character(raw[!is.na(raw)])))
  grp <- factor(as.character(raw), levels = raw_levels)
  list(
    design = stats::update(design, Group = grp, Num = as.numeric(grp)),
    raw_levels = raw_levels,
    cutoffs = setNames(rep("", length(raw_levels)), raw_levels)
  )
}

.lqb09_apply_binary <- function(design, index_var) {
  design <- .lnw00_design_index_as_numeric(design, index_var)
  xv <- design$variables[[index_var]]
  q_med <- .lqb09_weighted_quantiles(design, index_var, 0.5)
  if (!is.finite(q_med)) stop("binary 加权中位数计算失败", call. = FALSE)
  grp_chr <- ifelse(is.na(xv), NA_character_, ifelse(xv < q_med, "Q1", "Q2"))
  raw_levels <- c("Q1", "Q2")
  cutoffs <- c(Q1 = paste0("< ", fmt_num_cutoff(q_med)), Q2 = paste0("\u2265 ", fmt_num_cutoff(q_med)))
  list(
    design = stats::update(design, Group = factor(grp_chr, levels = raw_levels), Num = as.numeric(factor(grp_chr, levels = raw_levels))),
    raw_levels = raw_levels, cutoffs = cutoffs
  )
}

.lqb09_crude_significance <- function(design, outcome_col, disease_lbl, method, threshold) {
  des <- stats::update(design, Disease_Group = pipeline_outcome_as_01(design$variables[[outcome_col]], case_label = disease_lbl))
  fit_g <- .lqb09_svyglm_fit(des, "Disease_Group ~ Group")
  fit_t <- .lqb09_svyglm_fit(des, "Disease_Group ~ Num")
  sm_t <- if (!is.null(fit_t)) summary(fit_t)$coefficients else NULL
  pr_i <- if (!is.null(sm_t)) grep("^Pr\\(", colnames(sm_t)) else integer(0)
  p_trend <- if (length(pr_i) && "Num" %in% rownames(sm_t)) suppressWarnings(as.numeric(sm_t["Num", pr_i[1L]])) else NA_real_
  p_groups <- numeric(0)
  if (!is.null(fit_g)) {
    sm_g <- summary(fit_g)$coefficients; pr_g <- grep("^Pr\\(", colnames(sm_g))
    if (length(pr_g)) {
      pn <- rownames(sm_g)[grepl("^Group", rownames(sm_g))]
      p_groups <- suppressWarnings(as.numeric(sm_g[pn, pr_g[1L]])); names(p_groups) <- pn
    }
  }
  p_regterm <- if (!is.null(fit_g)) tryCatch(survey::regTermTest(fit_g, ~Group)$p, error = function(e) NA_real_) else NA_real_
  sig <- switch(tolower(method),
    trend = is.finite(p_trend) && p_trend < threshold,
    any_group = any(is.finite(p_groups) & p_groups < threshold, na.rm = TRUE),
    regterm = is.finite(p_regterm) && p_regterm < threshold,
    (is.finite(p_trend) && p_trend < threshold) || any(is.finite(p_groups) & p_groups < threshold, na.rm = TRUE))
  list(significant = isTRUE(sig), p_trend = p_trend, p_regterm = p_regterm)
}

.lqb09_build_table <- function(design, outcome_col, disease_lbl, index_var, M1, M2, cutoffs, levels, include_cont, M3 = NULL) {
  des <- stats::update(design, Disease_Group = pipeline_outcome_as_01(design$variables[[outcome_col]], case_label = disease_lbl))
  fj <- function(t) paste0("Disease_Group ~ ", paste(t, collapse = "+"))
  include_m3 <- length(as.character(M3 %||% character(0))) > 0L
  mf <- .lqb09_svyglm_fit(des, fj("Group")); mf2 <- .lqb09_svyglm_fit(des, fj(c("Group", M1))); mf3 <- .lqb09_svyglm_fit(des, fj(c("Group", M2)))
  mf4 <- if (include_m3) .lqb09_svyglm_fit(des, fj(c("Group", M3))) else NULL
  mt <- .lqb09_svyglm_fit(des, fj("Num")); mt2 <- .lqb09_svyglm_fit(des, fj(c("Num", M1))); mt3 <- .lqb09_svyglm_fit(des, fj(c("Num", M2)))
  mt4 <- if (include_m3) .lqb09_svyglm_fit(des, fj(c("Num", M3))) else NULL
  ref <- levels[1L]; non_ref <- levels[-1L]
  hdr <- pipeline_sci_with_model3_header(
    c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", ""),
    c("Characteristic", "Exposure cutoff", "Events / N (%)", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value"),
    include_m3, "OR"
  )
  Line1 <- hdr$line1; Line2 <- hdr$line2; n_pad <- hdr$n_pad
  Line5 <- c(paste0(index_var, " groups"), rep("", n_pad))
  Line_ref <- c(paste0(ref, " (Ref)"), cutoffs[[ref]], .lqb09_group_pct(des, ref), "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "", pipeline_sci_model3_ref_cells(include_m3))
  lines_nr <- lapply(non_ref, function(lv) {
    rn <- paste0("Group", lv)
    c1 <- .lqb09_coef_row(mf, rn); c2 <- .lqb09_coef_row(mf2, rn); c3 <- .lqb09_coef_row(mf3, rn)
    c4 <- if (include_m3) .lqb09_coef_row(mf4, rn) else character(0)
    c(lv, cutoffs[[lv]], .lqb09_group_pct(des, lv), c1[1L], c1[2L], c1[3L], c2[1L], c2[2L], c2[3L], c3[1L], c3[2L], c3[3L], c4)
  })
  t1 <- .lqb09_coef_row(mt, "Num"); t2 <- .lqb09_coef_row(mt2, "Num"); t3 <- .lqb09_coef_row(mt3, "Num")
  t4 <- if (include_m3) .lqb09_coef_row(mt4, "Num") else NULL
  # RCS cutoff 分组表不放 p for trend
  Line_trend <- if (isTRUE(attr(cutoffs, "is_rcs_group") %||% FALSE)) NULL else {
    c("p for trend", rep("", 4L), t1[3L], "", "", t2[3L], "", "", t3[3L], if (include_m3) c("", "", t4[3L]) else character(0))
  }
  if (include_cont) {
    mc <- .lqb09_svyglm_fit(des, fj(index_var)); mc2 <- .lqb09_svyglm_fit(des, fj(c(index_var, M1))); mc3 <- .lqb09_svyglm_fit(des, fj(c(index_var, M2)))
    mc4 <- if (include_m3) .lqb09_svyglm_fit(des, fj(c(index_var, M3))) else NULL
    cc1 <- .lqb09_coef_row(mc, index_var); cc2 <- .lqb09_coef_row(mc2, index_var); cc3 <- .lqb09_coef_row(mc3, index_var)
    cc4 <- if (include_m3) .lqb09_coef_row(mc4, index_var) else character(0)
    parts <- c(list(Line1, Line2, c(index_var, rep("", n_pad)),
      c(paste0(index_var, " continuous"), "", "", cc1[1L], cc1[2L], cc1[3L], cc2[1L], cc2[2L], cc2[3L], cc3[1L], cc3[2L], cc3[3L], cc4),
      Line5, Line_ref), lines_nr)
  } else {
    parts <- c(list(Line1, Line2, Line5, Line_ref), lines_nr)
  }
  if (!is.null(Line_trend)) parts <- c(parts, list(Line_trend))
  rt <- do.call(rbind, parts)
  rownames(rt) <- NULL
  colnames(rt) <- NULL
  rt
}

.lqb09_export_table <- function(ctx, cfg, bl_cfg, rt, caption_suffix = "", as_main = FALSE, M1 = NULL, M2 = NULL, M3 = NULL, m3_significant = NULL) {
  is_rcs <- grepl("RCS", as.character(caption_suffix %||% ""), ignore.case = TRUE) ||
    identical(as.character(bl_cfg$phase %||% "")[1L], "rcs")
  ix <- as.character(bl_cfg$index_var %||% "exposure")[1L]
  # 「RCS cutoff」须在括号外，否则 shorten 剥括号后无法归入 Table S-XX
  if (is_rcs) {
    cap <- paste0("Weighted logistic regression of ", ix, " RCS cutoff")
  } else {
    cap <- paste0(
      "Weighted logistic regression of ", ix, " and ",
      cfg$project$disease, " (NHANES binary, svyglm", caption_suffix, ")"
    )
  }
  footnotes <- .lnw00_table_footnotes(M1 %||% character(0), M2 %||% character(0), M3, m3_significant)
  .lnw00_export_table2(ctx, cfg, bl_cfg, rt, cap, as_main = as_main, table_footnotes = footnotes,
                       family = if (is_rcs) "rcs" else "binary")
}

block_logistic_binary_nhanes_weighted <- function(ctx, ...) {
  options(survey.lonely.psu = "adjust")
  cfg <- ctx$config
  bl_cfg <- cfg$logistic_binary_nhanes_weighted %||% list()
  block_name <- ctx$current_block %||% "logistic_binary_nhanes_weighted"
  is_rcs <- grepl("_rcs$", block_name) || identical(bl_cfg$phase, "rcs")
  if (is_rcs) {
    bl_cfg$phase <- "rcs"
    bl_cfg$include_continuous_row <- isTRUE(bl_cfg$include_continuous_row %||% FALSE)
    bl_cfg$group_var <- bl_cfg$group_var %||% ctx$results$nhanes_rcs_group_col
    p_nl_rcs <- suppressWarnings(
      as.numeric(((ctx$results$nhanes_rcs %||% list())$model2 %||% list())$p_nonlin)
    )
    pc_rcs <- suppressWarnings(
      as.numeric(ctx$results$nhanes_rcs_primary_cutoff %||% NA_real_)[1L]
    )
    if (!is.finite(p_nl_rcs) || !is.finite(pc_rcs)) {
      ctx$results$logistic_rcs_ns_skipped <- TRUE
      cli::cli_alert_warning(
        "logistic_binary_nhanes_weighted_rcs: RCS 未得到有效非线性 P/切点，跳过。"
      )
      return(ctx)
    }
  }
  if (!is_rcs && !.lnw00_gate_active(ctx)) {
    selected <- as.character(ctx$results$nhanes_logistic_selected_scheme %||% "")
    if (nzchar(selected)) {
      cli::cli_alert_info("logistic_binary_nhanes_weighted: 已选定 {selected}，跳过二分位")
      return(ctx)
    }
  }
  if (!.is_nhanes_db(cfg)) stop("logistic_binary_nhanes_weighted 仅用于 NHANES。", call. = FALSE)
  if (!requireNamespace("survey", quietly = TRUE)) stop("需要 survey 包。", call. = FALSE)
  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))

  design <- if (is_rcs) {
    ctx$results$nhanes_design_rcs %||% ctx$results$nhanes_design
  } else {
    ctx$results$nhanes_design
  }
  if (is.null(design)) {
    if (.lqb09_should_pause(bl_cfg, "pause_on_missing_design")) .lqb09_pause(ctx, "nhanes_design 为空", "先 run_block(obj)", NULL)
    return(ctx)
  }

  outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
  disease_lbl <- (cfg$project %||% list())$analysis_group %||% (cfg$project %||% list())$disease %||% "Case"
  index_var <- as.character(bl_cfg$index_var %||% (cfg$logistic %||% list())$index_var %||% (cfg$incidence %||% list())$index_var %||% "BMI")[1L]
  bl_cfg$index_var <- index_var
  if (exists("pipeline_apply_categorical_exposure", mode = "function")) {
    bl_cfg <- pipeline_apply_categorical_exposure(bl_cfg, design$variables, index_var)
  }
  if (!isTRUE(bl_cfg$categorical_exposure)) {
    design <- .lnw00_design_index_as_numeric(design, index_var)
  }
  cascade <- .lqb09_cascade_cfg(cfg)

  models <- .lnw00_resolve_models(ctx, cfg, bl_cfg, design, index_var)
  M1 <- models$M1
  M2 <- models$M2
  if (!length(M1)) .lqb09_pause(ctx, "Model1Factors 为空", "检查 config$logistic_nhanes_weighted$model1_factors", NULL)
  if (!length(M2)) .lqb09_pause(ctx, "Model2Factors 为空", "检查 config$logistic_nhanes_weighted$model2_factors", NULL)

  if (is_rcs) {
    cli::cli_h2("logistic_binary_nhanes_weighted_rcs: RCS 分组加权 Table 2（{index_var}）")
    rcs_grp <- .lnw00_design_from_rcs_groups(ctx, design, bl_cfg)
    cutoffs_rcs <- rcs_grp$cutoffs
    attr(cutoffs_rcs, "is_rcs_group") <- TRUE
    grp <- list(design = rcs_grp$design, raw_levels = rcs_grp$raw_levels, cutoffs = cutoffs_rcs)
    crude <- list(significant = TRUE, p_trend = NA_real_, p_regterm = NA_real_)
  } else {
    cli::cli_h2("logistic_binary_nhanes_weighted: 加权二分位 Table 2（{index_var}）")
    grp <- if (isTRUE(bl_cfg$categorical_exposure)) {
      .lqb09_apply_native(design, index_var)
    } else {
      .lqb09_apply_binary(design, index_var)
    }
    crude <- .lqb09_crude_significance(grp$design, outcome_col, disease_lbl, cascade$method, cascade$threshold)
    cli::cli_alert_info("二分位 crude: p_trend={fmt_pval(crude$p_trend)}, regTerm={fmt_pval(crude$p_regterm)}, sig={crude$significant}")
  }

  tb <- .lqb09_build_table(grp$design, outcome_col, disease_lbl, index_var, M1, M2, grp$cutoffs, grp$raw_levels,
                           isTRUE(bl_cfg$include_continuous_row %||% FALSE) &&
                             !isTRUE(bl_cfg$categorical_exposure))

  if (isTRUE(crude$significant)) {
    inc_cont <- isTRUE(bl_cfg$include_continuous_row %||% FALSE) &&
      !isTRUE(bl_cfg$categorical_exposure)
    sr <- .lnw00_maybe_search_covariates(
      ctx, cfg, grp$design, index_var, M1, M2, tb, crude$significant,
      build_table_fn = function(m1, m2) {
        .lqb09_build_table(
          grp$design, outcome_col, disease_lbl, index_var, m1, m2,
          grp$cutoffs, grp$raw_levels, inc_cont
        )
      },
      bl_cfg = bl_cfg
    )
    ctx <- sr$ctx
    M1 <- sr$M1
    M2 <- sr$M2
    if (!is.null(sr$tb)) tb <- sr$tb
    if (isTRUE(sr$searched) || isTRUE(sr$fallback)) ctx <- .lnw00_store_models(ctx, M1, M2)
  }

  if (!is_rcs && exists("logistic_gate_apply_after_table_defer_stop", mode = "function")) {
    ctx <- logistic_gate_apply_after_table_defer_stop(
      ctx, bl_cfg, tb, grp$raw_levels, block_name
    )
  } else if (!is_rcs && exists("logistic_gate_apply_after_table", mode = "function")) {
    ctx <- logistic_gate_apply_after_table(ctx, bl_cfg, tb, grp$raw_levels, block_name)
  }

  m3a <- .lnw00_attach_model3_table(
    ctx, cfg, grp$design, M1, M2, grp$raw_levels,
    build_table_fn = function(m1, m2, m3) {
      .lqb09_build_table(
        grp$design, outcome_col, disease_lbl, index_var, m1, m2,
        grp$cutoffs, grp$raw_levels,
        isTRUE(bl_cfg$include_continuous_row %||% FALSE) && !isTRUE(bl_cfg$categorical_exposure),
        M3 = m3
      )
    },
    method = cascade$method, threshold = cascade$threshold, index_var = index_var
  )
  ctx <- m3a$ctx
  if (!is.null(m3a$tb)) tb <- m3a$tb

  ctx$results$logistic_table2_binary_nhanes <- tb
  ctx$results$nhanes_logistic_binary_crude_sig <- crude$significant
  ctx$results$nhanes_logistic_binary_p_trend <- crude$p_trend

  branch <- as.character(ctx$results$logistic_branch %||% "")[1L]
  # RCS → 附表；主文 Table 2 = 选中档，或闸门未选出时 binary 末档兜底
  as_main <- isTRUE(.lnw00_weighted_export_as_main(
    ctx, "binary", is_rcs = is_rcs,
    gate_enable = isTRUE(bl_cfg$gate_enable),
    crude_significant = isTRUE(crude$significant)
  ))

  ctx$results$nhanes_logistic_selected_scheme <- "binary"
  if (isTRUE(as_main) || isTRUE(crude$significant)) {
    ctx$results$nhanes_logistic_table2 <- tb
    ctx$results$logistic_table2_weighted <- tb
    ctx$results$logistic_table2_nhanes <- tb
    ctx$results$nhanes_logistic_grouping_scheme <- "binary"
    ctx$results$nhanes_logistic_grouping_cutoffs <- grp$cutoffs
    if (isTRUE(as_main)) ctx$results$nhanes_logistic_exported_main <- TRUE
  }
  ctx$results$nhanes_logistic_crude_significant <- crude$significant
  ctx$results$nhanes_logistic_crude_p_trend <- crude$p_trend
  ctx$results$nhanes_logistic_crude_p_regterm <- crude$p_regterm
  ctx <- .lnw00_store_models(ctx, M1, M2, m3a$M3, m3a$m3_sig, m3a$final)

  cap_suffix <- if (is_rcs) ", RCS groups" else ""
  .lqb09_export_table(
    ctx, cfg, bl_cfg, tb, cap_suffix, as_main = isTRUE(as_main),
    M1 = M1, M2 = M2, M3 = m3a$M3, m3_significant = m3a$m3_sig
  )
  if (exists("logistic_gate_throw_pending_stop", mode = "function")) {
    logistic_gate_throw_pending_stop(ctx)
  }
  if (is_rcs) {
    cli::cli_alert_success("logistic_binary_nhanes_weighted_rcs 完成")
  } else if (isTRUE(crude$significant)) {
    cli::cli_alert_success("二分位 crude 显著")
  } else {
    cli::cli_alert_warning("二分位 crude 不显著（gate 已处理终止或降级）")
  }
  ctx
}

register_block("logistic_binary_nhanes_weighted", block_logistic_binary_nhanes_weighted,
               "NHANES 加权二分位 Logistic Table 2（logistic_gate 初筛）")
register_block("logistic_binary_nhanes_weighted_rcs", block_logistic_binary_nhanes_weighted,
               "NHANES 加权二分位 Logistic（RCS 分组复跑）")
