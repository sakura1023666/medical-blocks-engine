###############################################################################
#  logistic_rcs_cutoff_nhanes_weighted — 按 RCS Model2 切点分组的 NHANES 加权 Logistic Table。
#
#  register_block: "logistic_rcs_cutoff_nhanes_weighted"
#  前置: rcs_nhanes（ctx$results$nhanes_rcs_cutoffs_all）
#        multicollinearity_nhanes_final（Model1/2Factors）
#
#  逻辑对齐 02block_rcs_incidence.R → 用 RCS 曲线切点分组，再跑 Crude/Model1/Model2 svyglm。
#
#  config$logistic_rcs_cutoff_nhanes_weighted = list(
#    index_var = "BMI",
#    include_continuous_row = TRUE,
#    cutoffs_from = "model2",   # 固定读 nhanes_rcs_cutoffs_all
#    pause_enable = TRUE,
#    pause_on_missing_cutoffs = TRUE
#  )
###############################################################################

.lrc16_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lrc16_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "logistic_rcs_cutoff_nhanes_weighted", reason = reason,
    suggestion = suggestion, data_snapshot = snap
  )
  stop("PAUSE_FOR_USER_DECISION: logistic_rcs_cutoff_nhanes_weighted — ", reason, call. = FALSE)
}

.lrc16_coef_row <- function(fit, row_name) {
  .lnw00_coef_row(fit, row_name)
}

.lrc16_svyglm_fit <- function(design, formula_str) {
  tryCatch(survey::svyglm(stats::as.formula(formula_str), design = design, family = stats::quasibinomial()), error = function(e) NULL)
}

.lrc16_group_pct <- function(design, level) {
  pub_svy_group_events_n_cell(design, level, outcome_col = "Disease_Group", group_col = "Group")
}

.lrc16_apply_rcs_cutoffs <- function(design, index_var, cutoffs) {
  grp <- rcs_cutoff_factor(design$variables[[index_var]], cutoffs, index_var)
  raw_levels <- levels(grp$factor)
  if (length(raw_levels) < 2L) {
    stop("RCS 切点分组不足 2 组，无法做分组 Logistic。", call. = FALSE)
  }
  grp_num <- as.numeric(factor(as.character(grp$factor), levels = raw_levels))
  list(
    design = stats::update(design, Group = factor(grp$factor, levels = raw_levels), Num = grp_num),
    raw_levels = raw_levels,
    cutoffs = grp$cutoffs_named,
    cutoffs_numeric = grp$cutoffs
  )
}

.lrc16_build_table <- function(design, outcome_col, disease_lbl, index_var, M1, M2, cutoffs, levels, include_cont, M3 = NULL) {
  des <- stats::update(design, Disease_Group = pipeline_outcome_as_01(design$variables[[outcome_col]], case_label = disease_lbl))
  fj <- function(t) paste0("Disease_Group ~ ", paste(t, collapse = "+"))
  include_m3 <- length(as.character(M3 %||% character(0))) > 0L
  mf <- .lrc16_svyglm_fit(des, fj("Group")); mf2 <- .lrc16_svyglm_fit(des, fj(c("Group", M1))); mf3 <- .lrc16_svyglm_fit(des, fj(c("Group", M2)))
  mf4 <- if (include_m3) .lrc16_svyglm_fit(des, fj(c("Group", M3))) else NULL
  mt <- .lrc16_svyglm_fit(des, fj("Num")); mt2 <- .lrc16_svyglm_fit(des, fj(c("Num", M1))); mt3 <- .lrc16_svyglm_fit(des, fj(c("Num", M2)))
  mt4 <- if (include_m3) .lrc16_svyglm_fit(des, fj(c("Num", M3))) else NULL
  ref <- levels[1L]; non_ref <- levels[-1L]
  hdr <- pipeline_sci_with_model3_header(
    c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", ""),
    c("Characteristic", "Exposure cutoff", "Events / N (%)", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value"),
    include_m3, "OR"
  )
  Line1 <- hdr$line1; Line2 <- hdr$line2; n_pad <- hdr$n_pad
  Line5 <- c(paste0(index_var, " groups (RCS cutoffs)"), rep("", n_pad))
  Line_ref <- c(paste0(ref, " (Ref)"), cutoffs[[ref]] %||% "", .lrc16_group_pct(des, ref), "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "", pipeline_sci_model3_ref_cells(include_m3))
  lines_nr <- lapply(non_ref, function(lv) {
    rn <- paste0("Group", lv)
    c1 <- .lrc16_coef_row(mf, rn); c2 <- .lrc16_coef_row(mf2, rn); c3 <- .lrc16_coef_row(mf3, rn)
    c4 <- if (include_m3) .lrc16_coef_row(mf4, rn) else character(0)
    c(lv, cutoffs[[lv]] %||% "", .lrc16_group_pct(des, lv), c1[1L], c1[2L], c1[3L], c2[1L], c2[2L], c2[3L], c3[1L], c3[2L], c3[3L], c4)
  })
  t1 <- .lrc16_coef_row(mt, "Num"); t2 <- .lrc16_coef_row(mt2, "Num"); t3 <- .lrc16_coef_row(mt3, "Num")
  t4 <- if (include_m3) .lrc16_coef_row(mt4, "Num") else NULL
  # 规则：S8（RCS cutoff 分组）不放 p for trend，仅组间 OR
  if (include_cont) {
    mc <- .lrc16_svyglm_fit(des, fj(index_var)); mc2 <- .lrc16_svyglm_fit(des, fj(c(index_var, M1))); mc3 <- .lrc16_svyglm_fit(des, fj(c(index_var, M2)))
    mc4 <- if (include_m3) .lrc16_svyglm_fit(des, fj(c(index_var, M3))) else NULL
    cc1 <- .lrc16_coef_row(mc, index_var); cc2 <- .lrc16_coef_row(mc2, index_var); cc3 <- .lrc16_coef_row(mc3, index_var)
    cc4 <- if (include_m3) .lrc16_coef_row(mc4, index_var) else character(0)
    rt <- do.call(rbind, c(list(Line1, Line2, c(index_var, rep("", n_pad)),
      c(paste0(index_var, " continuous"), "", "", cc1[1L], cc1[2L], cc1[3L], cc2[1L], cc2[2L], cc2[3L], cc3[1L], cc3[2L], cc3[3L], cc4),
      Line5, Line_ref), lines_nr))
  } else {
    rt <- do.call(rbind, c(list(Line1, Line2, Line5, Line_ref), lines_nr))
  }
  rownames(rt) <- NULL
  colnames(rt) <- NULL
  rt
}

.lrc16_export_table <- function(ctx, cfg, bl_cfg, rt, cutoffs_txt, M1, M2, M3 = NULL, m3_significant = NULL) {
  ix <- as.character(bl_cfg$index_var %||% "exposure")[1L]
  # 「RCS cutoff」须在括号外，否则 shorten 剥括号后无法归入 Table S-XX
  cap <- paste0("Weighted logistic regression of ", ix, " RCS cutoff")
  footnotes <- .lnw00_table_footnotes(M1, M2, M3, m3_significant)
  .lnw00_export_table2(ctx, cfg, bl_cfg, rt, cap, as_main = FALSE, table_footnotes = footnotes,
                       family = "rcs")
}

block_logistic_rcs_cutoff_nhanes_weighted <- function(ctx, ...) {
  options(survey.lonely.psu = "adjust")
  cfg <- ctx$config
  bl_cfg <- cfg$logistic_rcs_cutoff_nhanes_weighted %||% list()
  if (!.is_nhanes_db(cfg)) {
    cli::cli_alert_info("logistic_rcs_cutoff_nhanes_weighted: 非 NHANES，跳过。")
    return(ctx)
  }
  if (!requireNamespace("survey", quietly = TRUE)) stop("需要 survey 包。", call. = FALSE)
  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    if (.lrc16_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .lrc16_pause(ctx, "nhanes_design 为空", "先 run_block(obj)", NULL)
    }
    return(ctx)
  }

  outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
  disease_lbl <- (cfg$project %||% list())$analysis_group %||% (cfg$project %||% list())$disease %||% "Case"
  index_var <- as.character(
    bl_cfg$index_var %||%
    ctx$results$nhanes_rcs_cutoff_index %||%
    (cfg$logistic %||% list())$index_var %||%
    (cfg$incidence %||% list())$index_var %||% "BMI"
  )[1L]
  bl_cfg$index_var <- index_var
  design <- .lnw00_design_index_as_numeric(design, index_var)

  cut_use <- list(
    all = as.numeric(ctx$results[["nhanes_rcs_cutoffs_all"]] %||% numeric(0)),
    or1 = as.numeric(ctx$results$nhanes_rcs_cutoff_or1 %||% numeric(0)),
    peak = as.numeric(ctx$results$nhanes_rcs_cutoff_peak %||% numeric(0))
  )
  primary <- suppressWarnings(as.numeric(ctx$results$nhanes_rcs_primary_cutoff %||% NA_real_)[1L])
  rn_cfg <- cfg$rcs_nhanes %||% list()
  group_mode <- tolower(as.character(rn_cfg$group_cutoffs %||% "primary")[1L])
  cutoffs <- rcs_table_group_cutoffs(cut_use, primary = primary, mode = group_mode)
  if (!length(cutoffs)) {
    msg <- "未找到 RCS 切点（nhanes_rcs_primary_cutoff / nhanes_rcs_cutoffs_all 为空）。"
    if (.lrc16_should_pause(bl_cfg, "pause_on_missing_cutoffs", TRUE)) {
      .lrc16_pause(ctx, msg, "先 run_block(rcs_nhanes)", NULL)
    }
    cli::cli_alert_warning("logistic_rcs_cutoff_nhanes_weighted: {msg} 已跳过。")
    return(ctx)
  }

  # 规则：单库默认要求非线性显著才导出 RCS cutoff 表。
  # 双库发病：为与对侧 S-XX 对齐，只要有切点就导出（脚注可反映非线性 P）。
  require_nl <- isTRUE(bl_cfg$require_nonlinear_sig %||% TRUE)
  if (isTRUE((cfg$dual_db %||% list())$enable) &&
      !isFALSE(bl_cfg$dual_db_export_even_if_linear %||% TRUE)) {
    require_nl <- FALSE
  }
  if (isTRUE(require_nl)) {
    p_nl <- suppressWarnings(
      as.numeric(((ctx$results$nhanes_rcs %||% list())$model2 %||% list())$p_nonlin)
    )
    if (!is.finite(p_nl)) {
      p_nl <- suppressWarnings(as.numeric(
        ((ctx$results$rcs_nhanes_panel_stats %||% list())$Model2 %||% list())$p_nonlinear
      ))
    }
    if (is.finite(p_nl) && p_nl >= 0.05) {
      ctx$results$logistic_rcs_cutoff_nhanes_ns_skipped <- TRUE
      cli::cli_alert_warning(
        "logistic_rcs_cutoff_nhanes_weighted: RCS 非线性 P={round(p_nl,3)} >= 0.05，按规则不导出 Table S8（cutoff 分组 Logistic）。"
      )
      return(ctx)
    }
  } else if (isTRUE((cfg$dual_db %||% list())$enable)) {
    p_nl <- suppressWarnings(as.numeric(
      ((ctx$results$rcs_nhanes_panel_stats %||% list())$Model2 %||% list())$p_nonlinear %||%
        ((ctx$results$nhanes_rcs %||% list())$model2 %||% list())$p_nonlin
    ))
    if (is.finite(p_nl) && p_nl >= 0.05) {
      cli::cli_alert_info(
        "logistic_rcs_cutoff_nhanes_weighted: 双库对齐仍导出 RCS cutoff 表（非线性 P={round(p_nl, 3)}）"
      )
    }
  }

  models <- .lnw00_resolve_models(ctx, cfg, bl_cfg, design, index_var)
  M1 <- models$M1
  M2 <- models$M2
  if (!length(M1)) .lrc16_pause(ctx, "Model1Factors 为空", "检查 config$logistic_nhanes_weighted$model1_factors", NULL)
  if (!length(M2)) .lrc16_pause(ctx, "Model2Factors 为空", "检查 config$logistic_nhanes_weighted$model2_factors", NULL)
  cli::cli_alert_info("Model1: {paste(M1, collapse = ', ')}")
  cli::cli_alert_info("Model2: {paste(M2, collapse = ', ')}")

  cli::cli_h2("logistic_rcs_cutoff_nhanes_weighted: RCS 切点分组 Logistic（{index_var}）")
  cutoffs_txt <- paste(rcs_format_cutoff(cutoffs), collapse = ", ")
  cli::cli_alert_info(
    "Table S-XX 使用 primary cutoff（mode={group_mode}，{length(cutoffs)} 个）: {cutoffs_txt}"
  )

  grp <- .lrc16_apply_rcs_cutoffs(design, index_var, cutoffs)
  tb <- .lrc16_build_table(
    grp$design, outcome_col, disease_lbl, index_var, M1, M2,
    grp$cutoffs, grp$raw_levels,
    isTRUE(bl_cfg$include_continuous_row %||% TRUE)
  )
  m3a <- .lnw00_attach_model3_table(
    ctx, cfg, grp$design, M1, M2, grp$raw_levels,
    build_table_fn = function(m1, m2, m3) {
      .lrc16_build_table(
        grp$design, outcome_col, disease_lbl, index_var, m1, m2,
        grp$cutoffs, grp$raw_levels,
        isTRUE(bl_cfg$include_continuous_row %||% TRUE),
        M3 = m3
      )
    },
    index_var = index_var
  )
  ctx <- m3a$ctx
  if (!is.null(m3a$tb)) tb <- m3a$tb

  ctx$results$logistic_table2_rcs_cutoff_nhanes <- tb
  ctx$results$nhanes_logistic_rcs_cutoffs <- cutoffs
  ctx$results$nhanes_logistic_rcs_group_labels <- grp$raw_levels
  .lrc16_export_table(ctx, cfg, bl_cfg, tb, cutoffs_txt, M1, M2, m3a$M3, m3a$m3_sig)

  ctx <- .lnw00_store_models(ctx, M1, M2, m3a$M3, m3a$m3_sig, m3a$final)
  cli::cli_alert_success(
    "logistic_rcs_cutoff_nhanes_weighted 完成（{length(grp$raw_levels)} 组，切点 = {cutoffs_txt}）。"
  )
  ctx
}

register_block(
  "logistic_rcs_cutoff_nhanes_weighted",
  block_logistic_rcs_cutoff_nhanes_weighted,
  "NHANES 加权 RCS 切点分组 Logistic Table 2（svyglm，须在 rcs_nhanes 之后）"
)
