###############################################################################
#  IPTW 加权 Logistic 共用（MIMIC）：design 解析、分组、svyglm Table 2。
#  由 pipeline_runner 在 logistic_*_iptw_weighted 前 source（同 NHANES common 模式）。
#  配置键: config$logistic_binary_iptw_weighted / quartile / tertile
###############################################################################

.liw00_is_nhanes_db <- function(cfg) {
  dt <- tolower(trimws(as.character(cfg$project$database_type %||% "")))
  db <- tolower(trimws(as.character(cfg$project$database %||% "")))
  grepl("nhanes|nhance", dt) || grepl("nhanes|nhance", db)
}

.liw00_should_run <- function(cfg, cfg_key) {
  bl_cfg <- cfg[[cfg_key]] %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) return(FALSE)
  !.liw00_is_nhanes_db(cfg)
}

.liw00_pause <- function(ctx, block_name, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = block_name, reason = reason, suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ", block_name, " — ", reason,
    " | See ctx$results$pause_point.",
    call. = FALSE
  )
}

.liw00_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.liw00_pretty_var <- function(v) {
  if (exists("pipeline_var_display_name", mode = "function"))
    return(pipeline_var_display_name(v, cfg = NULL))
  gsub("_", " ", as.character(v), fixed = TRUE)
}

.liw00_resolve_index_var <- function(cfg, bl_cfg) {
  inc_cfg <- cfg$incidence %||% list()
  log_cfg <- cfg$logistic %||% list()
  as.character(
    bl_cfg$index_var %||% inc_cfg$index_var %||% log_cfg$index_var %||% ""
  )[1L]
}

.liw00_resolve_design <- function(ctx, cfg) {
  design <- ctx$results$iptw_design
  if (!is.null(design)) return(design)
  data <- ctx$data$iptw_weighted
  if (is.null(data) || !is.data.frame(data)) return(NULL)
  wt_col <- ctx$results$iptw_weight_col %||%
    (cfg$iptw_balance %||% list())$weight_col %||% "weight"
  if (!wt_col %in% names(data)) return(NULL)
  survey::svydesign(
    ids = ~1,
    data = data,
    weights = stats::as.formula(paste0("~", wt_col))
  )
}

.liw00_resolve_cutoff <- function(ctx, cfg, bl_cfg) {
  cv <- bl_cfg$cutoff_value %||% NULL
  if (!is.null(cv) && is.finite(as.numeric(cv))) return(as.numeric(cv)[1L])
  cv <- ctx$results$roc_cutoff %||% ctx$results$cutoff_value %||% ctx$results$nhanes_cutoff
  if (!is.null(cv) && is.finite(as.numeric(cv))) return(as.numeric(cv)[1L])
  NULL
}

.liw00_weighted_quantiles <- function(design, index_var, probs) {
  qq <- survey::svyquantile(
    stats::as.formula(paste0("~", index_var)),
    design,
    quantiles = probs,
    na.rm = TRUE
  )
  if (index_var %in% names(qq)) {
    mat <- qq[[index_var]]
    if (is.matrix(mat) && "quantile" %in% colnames(mat)) {
      return(as.numeric(mat[, "quantile", drop = TRUE]))
    }
    return(as.numeric(mat))
  }
  if (!is.null(qq$quantiles)) return(as.numeric(qq$quantiles))
  as.numeric(unlist(qq, use.names = FALSE))
}

.liw00_resolve_models <- function(ctx, cfg, bl_cfg, design, index_var, extra_excl = character(0)) {
  dv <- names(design$variables)
  excl <- unique(c(
    index_var, extra_excl,
    cfg$data$outcome_column %||% "Disease_Group",
    cfg$data$id_column %||% character(0),
    "subject_id", "SEQN", "Group", "Num",
    "Index_Group", "Index_Group_Tertile", "Index_Group_Quartile",
    ctx$results$iptw_weight_col %||% "weight", "weight",
    pipeline_index_exclude_vars(cfg)
  ))
  excl <- excl[nzchar(excl)]

  m1 <- as.character(bl_cfg$model1_factors %||% character(0))
  m2 <- as.character(bl_cfg$model2_factors %||% character(0))
  if (length(m1) && length(m2)) {
    m1 <- setdiff(intersect(m1, dv), excl)
    m2 <- setdiff(intersect(m2, dv), excl)
    m2 <- unique(c(m1, m2))
    return(list(M1 = m1, M2 = m2))
  }

  pool <- as.character(
    ctx$results$Model1Factors %||%
      ctx$results$vif_final_pass %||%
      ctx$results$Model2Factors %||%
      character(0)
  )
  pool <- intersect(setdiff(unique(pool[nzchar(pool)]), excl), dv)
  if (!length(pool)) {
    pool <- intersect(
      setdiff(as.character(ctx$results$iptw_high_smd_vars %||% character(0)), excl),
      dv
    )
  }
  if (!length(pool)) return(list(M1 = character(0), M2 = character(0)))

  n_m1 <- as.integer(bl_cfg$model1_n %||% 4L)[1L]
  m1 <- pool[seq_len(min(max(n_m1, 1L), length(pool)))]
  m2 <- pool
  list(M1 = m1, M2 = unique(c(m1, m2)))
}

.liw00_prepare_outcome <- function(design, outcome_col, disease_lbl) {
  stats::update(
    design,
    .outcome_bin = as.numeric(
      as.character(design$variables[[outcome_col]]) == as.character(disease_lbl)
    )
  )
}

.liw00_apply_predefined_group <- function(design, bl_cfg) {
  src_var <- as.character(bl_cfg$group_var %||% "Group")[1L]
  if (!src_var %in% names(design$variables)) {
    stop("predefined 分组列 '", src_var, "' 不在 iptw_design 中。", call. = FALSE)
  }
  raw <- as.character(design$variables[[src_var]])
  levs <- bl_cfg$group_levels %||% NULL
  if (is.null(levs) || !length(levs)) levs <- sort(unique(raw[!is.na(raw)]))
  levs <- as.character(levs)
  cutoffs <- bl_cfg$group_cutoffs %||% setNames(rep("", length(levs)), levs)
  if (length(cutoffs) != length(levs)) cutoffs <- setNames(rep("", length(levs)), levs)
  design <- stats::update(
    design,
    Group = factor(raw, levels = levs),
    Num = as.numeric(factor(raw, levels = levs))
  )
  list(
    design = design,
    levels = levs,
    cutoffs = cutoffs,
    predefined = TRUE
  )
}

.liw00_apply_binary_group <- function(design, index_var, bl_cfg, ctx, cfg) {
  mode <- tolower(as.character(bl_cfg$group_mode %||% "median")[1L])

  if (identical(mode, "predefined")) {
    out <- .liw00_apply_predefined_group(design, bl_cfg)
    if (length(out$levels) != 2L) {
      stop("binary predefined 分组须恰好 2 水平，当前 ", length(out$levels), "。", call. = FALSE)
    }
    return(out)
  }

  xv <- design$variables[[index_var]]

  if (identical(mode, "cutoff")) {
    cv <- .liw00_resolve_cutoff(ctx, cfg, bl_cfg)
    if (is.null(cv)) {
      stop(
        "group_mode=cutoff 但未找到 cutoff；请设置 cutoff_value 或先运行 simple_ROC。",
        call. = FALSE
      )
    }
    lbl_lo <- bl_cfg$group_label_low %||% paste0("<", fmt_num(cv, 4))
    lbl_hi <- bl_cfg$group_label_high %||% paste0(">=", fmt_num(cv, 4))
    grp_chr <- ifelse(is.na(xv), NA_character_, ifelse(as.numeric(xv) < cv, lbl_lo, lbl_hi))
    levs <- c(lbl_lo, lbl_hi)
    cutoffs <- setNames(c("", ""), levs)
    cutoffs[[1L]] <- paste0("< ", fmt_num(cv, 4))
    cutoffs[[2L]] <- paste0("\u2265 ", fmt_num(cv, 4))
  } else {
    q_med <- .liw00_weighted_quantiles(design, index_var, 0.5)
    if (!is.finite(q_med)) stop("binary 加权中位数计算失败。", call. = FALSE)
    grp_chr <- rep(NA_character_, length(xv))
    grp_chr[!is.na(xv) & xv < q_med] <- "Q1"
    grp_chr[!is.na(xv) & xv >= q_med] <- "Q2"
    levs <- c("Q1", "Q2")
    cutoffs <- c(
      Q1 = paste0("< ", fmt_num(q_med)),
      Q2 = paste0("\u2265 ", fmt_num(q_med))
    )
  }

  design <- stats::update(
    design,
    Group = factor(grp_chr, levels = levs),
    Num = as.numeric(factor(grp_chr, levels = levs))
  )
  list(design = design, levels = levs, cutoffs = cutoffs, predefined = FALSE)
}

.liw00_apply_quartile_group <- function(design, index_var, bl_cfg) {
  mode <- tolower(as.character(bl_cfg$group_mode %||% "quantile")[1L])
  if (identical(mode, "predefined")) {
    bl2 <- modifyList(bl_cfg, list(group_var = bl_cfg$group_var %||% "Index_Group_Quartile"))
    return(.liw00_apply_predefined_group(design, bl2))
  }

  xv <- design$variables[[index_var]]
  qs <- .liw00_weighted_quantiles(design, index_var, c(0.25, 0.5, 0.75))
  if (length(qs) < 3L || any(!is.finite(qs))) {
    stop("quartile 加权分位点计算失败。", call. = FALSE)
  }
  qs <- c(qs[1L], max(qs[1L], qs[2L], na.rm = TRUE), max(qs[2L], qs[3L], na.rm = TRUE))
  if (qs[2L] <= qs[1L]) qs[2L] <- qs[1L] + .Machine$double.eps
  if (qs[3L] <= qs[2L]) qs[3L] <- qs[2L] + .Machine$double.eps
  grp_chr <- rep("Q4", length(xv))
  grp_chr[is.na(xv)] <- NA_character_
  grp_chr[!is.na(xv) & xv < qs[1L]] <- "Q1"
  grp_chr[!is.na(xv) & xv >= qs[1L] & xv < qs[2L]] <- "Q2"
  grp_chr[!is.na(xv) & xv >= qs[2L] & xv < qs[3L]] <- "Q3"
  levs <- c("Q1", "Q2", "Q3", "Q4")
  cutoffs <- c(
    Q1 = paste0("< ", fmt_num_cutoff(qs[1L])),
    Q2 = paste0(fmt_num_cutoff(qs[1L]), " -< ", fmt_num_cutoff(qs[2L])),
    Q3 = paste0(fmt_num_cutoff(qs[2L]), " -< ", fmt_num_cutoff(qs[3L])),
    Q4 = paste0("\u2265 ", fmt_num_cutoff(qs[3L]))
  )
  design <- stats::update(
    design,
    Group = factor(grp_chr, levels = levs),
    Num = as.numeric(factor(grp_chr, levels = levs))
  )
  list(design = design, levels = levs, cutoffs = cutoffs, predefined = FALSE)
}

.liw00_apply_tertile_group <- function(design, index_var, bl_cfg) {
  mode <- tolower(as.character(bl_cfg$group_mode %||% "quantile")[1L])
  if (identical(mode, "predefined")) {
    bl2 <- modifyList(bl_cfg, list(group_var = bl_cfg$group_var %||% "Index_Group_Tertile"))
    return(.liw00_apply_predefined_group(design, bl2))
  }

  xv <- design$variables[[index_var]]
  qs <- .liw00_weighted_quantiles(design, index_var, c(1 / 3, 2 / 3))
  if (length(qs) < 2L || any(!is.finite(qs))) {
    stop("tertile 加权分位点计算失败。", call. = FALSE)
  }
  grp_chr <- rep(NA_character_, length(xv))
  grp_chr[!is.na(xv) & xv < qs[1L]] <- "T1"
  grp_chr[!is.na(xv) & xv >= qs[1L] & xv < qs[2L]] <- "T2"
  grp_chr[!is.na(xv) & xv >= qs[2L]] <- "T3"
  levs <- c("T1", "T2", "T3")
  cutoffs <- c(
    T1 = paste0("< ", fmt_num(qs[1L])),
    T2 = paste0(fmt_num(qs[1L]), " \u2013 ", fmt_num(qs[2L])),
    T3 = paste0("\u2265 ", fmt_num(qs[2L]))
  )
  design <- stats::update(
    design,
    Group = factor(grp_chr, levels = levs),
    Num = as.numeric(factor(grp_chr, levels = levs))
  )
  list(design = design, levels = levs, cutoffs = cutoffs, predefined = FALSE)
}

.liw00_svyglm_fit <- function(design, rhs_terms) {
  rhs <- paste(rhs_terms, collapse = " + ")
  fml <- stats::as.formula(paste0(".outcome_bin ~ ", rhs))
  tryCatch(
    survey::svyglm(fml, design = design, family = stats::quasibinomial()),
    error = function(e) NULL
  )
}

.liw00_summary_coefs <- function(fit) {
  if (is.null(fit)) return(NULL)
  summary(fit)$coefficients
}

.liw00_coef_row <- function(fit, row_name) {
  if (is.null(fit)) return(rep("", 3L))
  sm <- .liw00_summary_coefs(fit)
  if (is.null(sm) || !row_name %in% rownames(sm)) return(rep("", 3L))
  est <- sm[row_name, "Estimate", drop = TRUE]
  se  <- sm[row_name, "Std. Error", drop = TRUE]
  pr_i <- grep("^Pr\\(", colnames(sm))
  pv <- if (length(pr_i)) suppressWarnings(as.numeric(sm[row_name, pr_i[1L]])) else NA_real_
  if (exists(".lnw00_pvalue_from_coef", mode = "function")) {
    pv <- .lnw00_pvalue_from_coef(est, se, pv)
  } else if (!is.finite(pv) && is.finite(est) && is.finite(se) && isTRUE(se > 0)) {
    pv <- 2 * stats::pnorm(-abs(est / se))
  }
  ci <- tryCatch(
    exp(suppressMessages(stats::confint(fit)[row_name, , drop = FALSE])),
    error = function(e) c(exp(est - 1.96 * se), exp(est + 1.96 * se))
  )
  c(
    fmt_num(exp(est)),
    paste0("(", fmt_num(ci[1L]), ",", fmt_num(ci[2L]), ")"),
    fmt_pval(pv)
  )
}

.liw00_group_pct <- function(design, level) {
  pub_svy_group_events_n_cell(design, level, outcome_col = "Disease_Group", group_col = "Group")
}

.liw00_build_table <- function(design, index_var, M1, M2, cutoffs, levels, include_cont = TRUE) {
  fj <- function(t) paste(c(t), collapse = "+")
  mf  <- .liw00_svyglm_fit(design, "Group")
  mf2 <- .liw00_svyglm_fit(design, c("Group", M1))
  mf3 <- .liw00_svyglm_fit(design, c("Group", M2))
  mt  <- .liw00_svyglm_fit(design, "Num")
  mt2 <- .liw00_svyglm_fit(design, c("Num", M1))
  mt3 <- .liw00_svyglm_fit(design, c("Num", M2))

  ref <- levels[1L]
  non_ref <- levels[-1L]
  Line1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  Line2 <- c(
    "Characteristic", "Exposure cutoff", "Events / N (%)",
    "OR", "95%CI", "P-value", "OR", "95%CI", "P-value", "OR", "95%CI", "P-value"
  )
  Line5 <- c(paste0(index_var, " groups"), rep("", 11L))
  Line_ref <- c(
    paste0(ref, " (Ref)"), cutoffs[[ref]], .liw00_group_pct(design, ref),
    "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", ""
  )
  lines_nr <- lapply(non_ref, function(lv) {
    rn <- paste0("Group", lv)
    c1 <- .liw00_coef_row(mf, rn)
    c2 <- .liw00_coef_row(mf2, rn)
    c3 <- .liw00_coef_row(mf3, rn)
    c(
      lv, cutoffs[[lv]], .liw00_group_pct(design, lv),
      c1[1L], c1[2L], c1[3L], c2[1L], c2[2L], c2[3L], c3[1L], c3[2L], c3[3L]
    )
  })
  t1 <- .liw00_coef_row(mt, "Num")
  t2 <- .liw00_coef_row(mt2, "Num")
  t3 <- .liw00_coef_row(mt3, "Num")
  Line_trend <- c("p for trend", rep("", 4L), t1[3L], "", "", t2[3L], "", "", t3[3L])

  if (isTRUE(include_cont)) {
    mc  <- .liw00_svyglm_fit(design, index_var)
    mc2 <- .liw00_svyglm_fit(design, c(index_var, M1))
    mc3 <- .liw00_svyglm_fit(design, c(index_var, M2))
    cc1 <- .liw00_coef_row(mc, index_var)
    cc2 <- .liw00_coef_row(mc2, index_var)
    cc3 <- .liw00_coef_row(mc3, index_var)
    rt <- do.call(rbind, c(
      list(
        Line1, Line2, c(index_var, rep("", 11L)),
        c(
          paste0(index_var, " continuous"), "", "",
          cc1[1L], cc1[2L], cc1[3L],
          cc2[1L], cc2[2L], cc2[3L],
          cc3[1L], cc3[2L], cc3[3L]
        ),
        Line5, Line_ref
      ),
      lines_nr,
      list(Line_trend)
    ))
  } else {
    rt <- do.call(rbind, c(list(Line1, Line2, Line5, Line_ref), lines_nr, list(Line_trend)))
  }
  rownames(rt) <- NULL
  colnames(rt) <- NULL
  rt
}

.liw00_table_footnotes <- function(M1, M2) {
  m1_txt <- if (length(M1)) {
    paste(vapply(M1, .liw00_pretty_var, character(1L)), collapse = ", ")
  } else "none"
  m2_txt <- if (length(M2)) {
    paste(vapply(M2, .liw00_pretty_var, character(1L)), collapse = ", ")
  } else "none"
  c(
    "The Crude Model was non-adjusted.",
    paste0("The Model 1 was adjusted by ", m1_txt, "."),
    paste0("The Model 2 was adjusted by ", m2_txt, ".")
  )
}

.liw00_export_table <- function(ctx, cfg, bl_cfg, rt, M1, M2, label_suffix) {
  rt2 <- format_logistic_table2_pvalues(rt, p_cols = c(6L, 9L, 12L))
  h1 <- as.character(rt2[1L, ])
  h2 <- as.character(rt2[2L, ])
  body <- rt2[-c(1L, 2L), , drop = FALSE]
  rownames(body) <- NULL
  colnames(body) <- paste0("V", seq_len(ncol(body)))

  index_var <- .liw00_resolve_index_var(cfg, bl_cfg)
  if (nzchar(index_var) && "V1" %in% names(body)) {
    body <- body[!as.character(body$V1) %in% index_var, , drop = FALSE]
  }

  disease <- (cfg$project %||% list())$disease %||%
    (cfg$project %||% list())$analysis_group %||% "outcome"
  db_name <- (cfg$project %||% list())$database %||% "MIMIC-IV"
  cap <- bl_cfg$table_caption %||% paste0(
    "IPTW-adjusted association between ", index_var, " and ", disease,
    " risk in ", db_name, " (", label_suffix, ", svyglm)"
  )
  cap <- sub("^Table\\s+\\d+[a-z]?\\.\\s*", "", cap)

  kind <- bl_cfg$table_pub_kind %||% "main_table"
  pub <- pub_paths(ctx, ctx$output_dir_tables, kind, cap, "xlsx")
  tryCatch(
    export_sci_table(
      body,
      pub$filepath,
      title = pub$title,
      header_row1 = h1,
      header_row2 = h2,
      table_footnotes = bl_cfg$table_footnotes %||% .liw00_table_footnotes(M1, M2),
      latex_include_colnames = FALSE
    ),
    error = function(e) cli::cli_alert_warning("IPTW logistic export failed: {e$message}")
  )
  cli::cli_alert_success("Table queued: {.file {basename(pub$filepath)}}")
  invisible(pub)
}

.liw00_run_iptw_logistic <- function(ctx, cfg_key, block_name, group_fn, label_suffix, result_key) {
  cfg <- ctx$config
  if (!.liw00_should_run(cfg, cfg_key)) {
    cli::cli_alert_info("{block_name}: 已跳过（NHANES 或 enable=FALSE）。")
    return(ctx)
  }

  bl_cfg <- cfg[[cfg_key]] %||% list()
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop(block_name, ": 需要 survey 包。", call. = FALSE)
  }
  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))

  design <- .liw00_resolve_design(ctx, cfg)
  if (is.null(design)) {
    msg <- "ctx$results$iptw_design 为空（请先运行 iptw_balance）。"
    if (.liw00_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .liw00_pause(ctx, block_name, msg, "在 pipeline 中于本 block 之前加入 iptw_balance。", NULL)
    }
    stop(block_name, ": ", msg, call. = FALSE)
  }

  index_var <- .liw00_resolve_index_var(cfg, bl_cfg)
  outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
  disease_lbl <- (cfg$project %||% list())$analysis_group %||%
    (cfg$project %||% list())$disease %||% "Case"

  if (!nzchar(index_var)) stop(block_name, ": index_var 未设置。", call. = FALSE)
  if (!index_var %in% names(design$variables)) {
    stop(block_name, ": index_var '", index_var, "' 不在 iptw_design 中。", call. = FALSE)
  }
  if (exists("pipeline_apply_categorical_exposure", mode = "function")) {
    bl_cfg <- pipeline_apply_categorical_exposure(bl_cfg, design$variables, index_var)
  }
  if (isTRUE(bl_cfg$categorical_exposure)) {
    bl_cfg$group_mode <- "predefined"
    bl_cfg$group_var <- bl_cfg$group_var %||% index_var
    if (grepl("quartile|tertile|quintile|sextile", block_name)) {
      cli::cli_alert_info("分类暴露：跳过 {block_name}，仅回归变量本身")
      return(ctx)
    }
  }
  if (!outcome_col %in% names(design$variables)) {
    stop(block_name, ": outcome '", outcome_col, "' 不在 iptw_design 中。", call. = FALSE)
  }

  design <- .liw00_prepare_outcome(design, outcome_col, disease_lbl)
  grp <- group_fn(design, index_var, bl_cfg, ctx, cfg)
  design <- grp$design

  models <- .liw00_resolve_models(ctx, cfg, bl_cfg, design, index_var)
  M1 <- models$M1
  M2 <- models$M2
  if (!length(M1) || !length(M2)) {
    msg <- "Model1/Model2 协变量为空；请设置 model1_factors 或先运行 IPTW 后 VIF。"
    if (.liw00_should_pause(bl_cfg, "pause_on_empty_models", TRUE)) {
      .liw00_pause(ctx, block_name, msg, "检查 ctx$results$vif_final_pass。", NULL)
    }
    stop(block_name, ": ", msg, call. = FALSE)
  }

  include_cont <- if (is.null(bl_cfg$include_continuous_row)) {
    !isTRUE(grp$predefined)
  } else {
    isTRUE(bl_cfg$include_continuous_row)
  }

  cli::cli_h2("{block_name}: IPTW Table 2（{index_var}, {label_suffix}）")
  cli::cli_alert_info("group_mode={bl_cfg$group_mode %||% 'default'}; Model1 ({length(M1)}): {paste(M1, collapse = ', ')}")
  cli::cli_alert_info("Model2 ({length(M2)}): {paste(M2, collapse = ', ')}")

  tb <- .liw00_build_table(design, index_var, M1, M2, grp$cutoffs, grp$levels, include_cont)

  ctx$results$Model1Factors <- M1
  ctx$results$Model2Factors <- M2
  ctx$results$logistic_model1_factors <- M1
  ctx$results$logistic_model2_factors <- M2
  ctx$results[[result_key]] <- tb

  .liw00_export_table(ctx, cfg, bl_cfg, tb, M1, M2, label_suffix)

  tryCatch({
    write.csv(M1, file.path(ctx$output_dir, paste0("Model1Factors_", cfg_key, ".csv")), row.names = FALSE)
    write.csv(M2, file.path(ctx$output_dir, paste0("Model2Factors_", cfg_key, ".csv")), row.names = FALSE)
  }, error = function(e) NULL)

  cli::cli_alert_success("{block_name} 完成。")
  ctx
}
