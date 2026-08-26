###############################################################################
#  cox_interaction — Cox 主效应 vs 含交互嵌套模型；并排补充表 + LRT
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$cleaned
#  require_study  = config$project$study_type == "prognosis"
#  require_config = config$survival（time_var / event_var / event_value 必填）
#                   config$cox_interaction（modifier_var 必填）
#
#  模型:
#    Model without interaction: Surv ~ index + modifier
#    Model with interaction:    Surv ~ index * modifier
#    LRT: anova(fit_main, fit_int, test = "LRT")
#
#  cox_interaction = list(
#    index_var           = NULL,   # NULL → survival$index_var
#    modifier_var        = NULL,   # 必填，分类调节变量
#    reference_level     = NULL,   # NULL → factor 第一水平
#    index_label         = NULL,   # NULL → index_var 美化名
#    modifier_labels     = NULL,   # 命名 list：水平名 → 显示标签
#    table_title_caption = "Sensitivity Analysis Cox Proportional Hazards Models with and without Treatment Interaction",
#    table_file_caption  = "Sensitivity Analysis Cox Interaction",
#    table_footnotes     = NULL,   # NULL → 块内默认脚注
#    coef_csv            = "Cox_Interaction_coefficients.csv",
#    slope_csv           = "Cox_Interaction_slope_by_group.csv",
#    lrt_txt             = "Cox_Interaction_LRT_summary.txt",
#    export_coef_csv     = TRUE,
#    export_slope_csv    = TRUE,
#    export_lrt_txt      = TRUE,
#    run_emtrends        = TRUE,
#    hr_digits           = 3L,
#    pause_enable        = TRUE,
#    pause_on_fit_fail   = TRUE,
#    pause_on_low_events = TRUE,
#    min_events          = 5L,
#    min_events_stratum  = 2L
#  ),
#
#  产出:
#    - [supp_table] Table Sn.*  有/无交互并排 Cox 表 → pub_pair + export_sci_table
#    - [固定名]     Cox_Interaction_coefficients.csv（交互模型系数）
#    - [固定名]     Cox_Interaction_slope_by_group.csv（emtrends，可选）
#    - [固定名]     Cox_Interaction_LRT_summary.txt
#
#  register_block: "cox_interaction"
###############################################################################

.cxi06_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.cxi06_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "cox_interaction",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: cox_interaction — ", reason,
    " | See ctx$results$pause_point.",
    call. = FALSE
  )
}

.cxi06_coerce_event01 <- function(x, event_value) {
  if (is.logical(x)) return(as.integer(x))
  if (is.numeric(x) || is.integer(x)) {
    return(suppressWarnings(as.integer(x == event_value)))
  }
  if (is.factor(x)) {
    lab <- tolower(trimws(as.character(x)))
    ev_chr <- tolower(trimws(as.character(event_value)))
    v <- rep(0L, length(lab))
    if (nzchar(ev_chr)) v[lab == ev_chr] <- 1L
    v[grepl("^(yes|y|1|recurrence|是|复发)", lab, perl = TRUE)] <- 1L
    return(v)
  }
  xc <- tolower(trimws(as.character(x)))
  ev_chr <- tolower(trimws(as.character(event_value)))
  v <- rep(0L, length(xc))
  if (nzchar(ev_chr)) v[xc == ev_chr] <- 1L
  v[xc %in% c("1", "yes", "y", "recurrence", "true", "t", "是", "复发")] <- 1L
  v[grepl("^yes", xc, perl = TRUE)] <- 1L
  v
}

.cxi06_pretty_name <- function(x) {
  gsub("_", " ", as.character(x))
}

.cxi06_mod_label <- function(level, modifier_var, label_map) {
  lv <- as.character(level)[1L]
  if (!is.null(label_map) && length(label_map)) {
    if (!is.null(label_map[[lv]]) && nzchar(as.character(label_map[[lv]])[1L])) {
      return(as.character(label_map[[lv]])[1L])
    }
  }
  .cxi06_pretty_name(lv)
}

.cxi06_coef_table <- function(fit) {
  s <- summary(fit)
  ci <- as.data.frame(s$conf.int, stringsAsFactors = FALSE)
  cf <- as.data.frame(s$coefficients, stringsAsFactors = FALSE)
  if (!nrow(ci)) {
    return(data.frame(
      term = character(0), hr = numeric(0), lo = numeric(0),
      hi = numeric(0), p = numeric(0), stringsAsFactors = FALSE
    ))
  }
  data.frame(
    term = rownames(ci),
    hr = ci[["exp(coef)"]],
    lo = ci[["lower .95"]],
    hi = ci[["upper .95"]],
    p = cf[["Pr(>|z|)"]],
    stringsAsFactors = FALSE,
    row.names = NULL
  )
}

.cxi06_fmt_hr <- function(hr, lo, hi, digits) {
  if (any(is.na(c(hr, lo, hi)))) return("\u2014")
  sprintf(
    paste0("%.", digits, "f (%.", digits, "f to %.", digits, "f)"),
    hr, lo, hi
  )
}

.cxi06_fmt_p <- function(p) {
  if (length(p) != 1L || is.na(p)) return("\u2014")
  fmt_pval(p)
}

.cxi06_pick_term <- function(terms, patterns) {
  patterns <- as.character(patterns)
  patterns <- patterns[nzchar(patterns)]
  for (pat in patterns) {
    if (pat %in% terms) return(pat)
  }
  for (pat in patterns) {
    hit <- terms[terms == pat]
    if (length(hit)) return(hit[[1L]])
  }
  for (pat in patterns) {
    hit <- grep(paste0("^", gsub("([.|()\\[\\]{}^$*+?\\\\-])", "\\\\\\1", pat, perl = TRUE)), terms, value = TRUE)
    if (length(hit)) return(hit[[1L]])
  }
  for (pat in patterns) {
    hit <- grep(pat, terms, fixed = TRUE, value = TRUE)
    if (length(hit) == 1L) return(hit[[1L]])
  }
  NA_character_
}

.cxi06_lookup_row <- function(tbl, term) {
  if (is.na(term) || !nzchar(term) || !nrow(tbl)) {
    return(list(hr = "\u2014", p = "\u2014"))
  }
  hit <- tbl[tbl$term == term, , drop = FALSE]
  if (!nrow(hit)) {
    return(list(hr = "\u2014", p = "\u2014"))
  }
  list(
    hr = .cxi06_fmt_hr(hit$hr[1L], hit$lo[1L], hit$hi[1L], attr(tbl, "hr_digits") %||% 3L),
    p = .cxi06_fmt_p(hit$p[1L])
  )
}

.cxi06_build_comparison <- function(
    fit_main,
    fit_int,
    lrt,
    index_var,
    modifier_var,
    ref_level,
    non_ref_levels,
    index_label,
    modifier_labels,
    hr_digits
) {
  tbl_main <- .cxi06_coef_table(fit_main)
  tbl_int <- .cxi06_coef_table(fit_int)
  attr(tbl_main, "hr_digits") <- hr_digits
  attr(tbl_int, "hr_digits") <- hr_digits

  rows <- list()

  term_index <- .cxi06_pick_term(tbl_main$term, index_var)
  row_index <- c(
    index_label,
    .cxi06_lookup_row(tbl_main, term_index)$hr,
    .cxi06_lookup_row(tbl_main, term_index)$p,
    .cxi06_lookup_row(tbl_int, term_index)$hr,
    .cxi06_lookup_row(tbl_int, term_index)$p
  )
  rows[[length(rows) + 1L]] <- row_index

  for (lv in non_ref_levels) {
    mod_lab <- .cxi06_mod_label(lv, modifier_var, modifier_labels)
    term_mod <- .cxi06_pick_term(
      unique(c(tbl_main$term, tbl_int$term)),
      c(
        paste0(modifier_var, lv),
        paste0("`", modifier_var, "`", lv),
        lv
      )
    )
    rm <- .cxi06_lookup_row(tbl_main, term_mod)
    ri <- .cxi06_lookup_row(tbl_int, term_mod)
    rows[[length(rows) + 1L]] <- c(mod_lab, rm$hr, rm$p, ri$hr, ri$p)
  }

  for (lv in non_ref_levels) {
    mod_lab <- .cxi06_mod_label(lv, modifier_var, modifier_labels)
    int_lab <- paste0(index_label, " \u00d7 ", mod_lab)
    term_int <- .cxi06_pick_term(
      tbl_int$term,
      c(
        paste0(index_var, ":", modifier_var, lv),
        paste0(modifier_var, lv, ":", index_var),
        paste0(index_var, ":`", modifier_var, "`", lv),
        paste0("`", modifier_var, "`", lv, ":", index_var)
      )
    )
    ri <- .cxi06_lookup_row(tbl_int, term_int)
    rows[[length(rows) + 1L]] <- c(int_lab, "\u2014", "\u2014", ri$hr, ri$p)
  }

  lrt_p <- NA_real_
  lrt_chi <- NA_real_
  lrt_df <- NA_integer_
  if (!is.null(lrt) && nrow(lrt) >= 2L) {
    lrt_chi <- suppressWarnings(as.numeric(lrt[2L, "Chisq"]))
    lrt_df <- suppressWarnings(as.integer(lrt[2L, "Df"]))
    lrt_p <- suppressWarnings(as.numeric(lrt[2L, "Pr(>|Chi|)"]))
  }
  lrt_hr <- if (is.finite(lrt_chi) && !is.na(lrt_df)) {
    sprintf(
      "Chi-square = %.2f, df = %d, P = %s",
      lrt_chi, lrt_df, .cxi06_fmt_p(lrt_p)
    )
  } else {
    "\u2014"
  }
  rows[[length(rows) + 1L]] <- c(
    "Likelihood ratio test (without vs with interaction)",
    lrt_hr, "\u2014", "\u2014", "\u2014"
  )

  body <- do.call(rbind, rows)
  body <- as.data.frame(body, stringsAsFactors = FALSE)
  colnames(body) <- paste0("V", seq_len(ncol(body)))

  h1 <- c(
    "Characteristic",
    "Model without interaction", "",
    "Model with interaction", ""
  )
  h2 <- c("", "HR (95% CI)", "P value", "HR (95% CI)", "P value")

  list(body = body, header_row1 = h1, header_row2 = h2, lrt_p = lrt_p)
}

.cxi06_default_footnotes <- function(ref_level, modifier_var, index_label) {
  c(
    paste0(
      "Model without interaction: ", index_label,
      " and ", .cxi06_pretty_name(modifier_var), " (main effects only)."
    ),
    paste0(
      "Model with interaction: ", index_label,
      " \u00d7 ", .cxi06_pretty_name(modifier_var), "."
    ),
    paste0(
      "Reference level for ", .cxi06_pretty_name(modifier_var), ": ", ref_level, "."
    ),
    "Likelihood ratio test compares nested Cox models (without vs with interaction terms)."
  )
}

.cxi06_tidy_int_export <- function(fit_int, hr_digits) {
  if (requireNamespace("broom", quietly = TRUE)) {
    return(
      broom::tidy(fit_int, exponentiate = TRUE, conf.int = TRUE) |>
        dplyr::mutate(
          `HR (95% CI)` = sprintf(
            paste0("%.", hr_digits, "f (%.", hr_digits, "f to %.", hr_digits, "f)"),
            .data$estimate, .data$conf.low, .data$conf.high
          )
        )
    )
  }
  tbl <- .cxi06_coef_table(fit_int)
  tbl$`HR (95% CI)` <- mapply(
    .cxi06_fmt_hr, tbl$hr, tbl$lo, tbl$hi,
    MoreArgs = list(digits = hr_digits)
  )
  tbl
}

block_cox_interaction <- function(ctx, ...) {
  cfg <- ctx$config
  bl_cfg <- cfg$cox_interaction %||% list()
  surv_cfg <- cfg$survival %||% list()

  time_var <- as.character(surv_cfg$time_var)[1L]
  event_var <- as.character(surv_cfg$event_var)[1L]
  event_value <- surv_cfg$event_value
  if (is.null(event_value)) event_value <- 1L

  index_var <- as.character(bl_cfg$index_var %||% surv_cfg$index_var)[1L]
  modifier_var <- as.character(bl_cfg$modifier_var)[1L]
  hr_digits <- as.integer(bl_cfg$hr_digits %||% 3L)[1L]
  if (is.na(hr_digits) || hr_digits < 1L) hr_digits <- 3L

  if (!nzchar(time_var) || !nzchar(event_var)) {
    stop("cox_interaction: config$survival$time_var / event_var 必填。", call. = FALSE)
  }
  if (is.null(modifier_var) || !nzchar(modifier_var)) {
    stop("cox_interaction: config$cox_interaction$modifier_var 必填。", call. = FALSE)
  }
  if (is.null(index_var) || !nzchar(index_var)) {
    stop("cox_interaction: index_var 未设置（config$cox_interaction$index_var 或 survival$index_var）。", call. = FALSE)
  }

  index_label <- as.character(bl_cfg$index_label %||% .cxi06_pretty_name(index_var))[1L]
  modifier_labels <- bl_cfg$modifier_labels

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.cxi06_should_pause(bl_cfg, "pause_on_no_data", TRUE)) {
      .cxi06_pause(ctx, "缺少分析数据", "请先运行 imputation 或 data_clean")
    }
    stop("cox_interaction: 无可用 data.frame。", call. = FALSE)
  }

  need_cols <- c(time_var, event_var, index_var, modifier_var)
  miss <- setdiff(need_cols, names(data))
  if (length(miss)) {
    stop("cox_interaction: 数据缺少列: ", paste(miss, collapse = ", "), call. = FALSE)
  }

  if (!requireNamespace("survival", quietly = TRUE)) {
    stop("cox_interaction: 需要 survival 包。", call. = FALSE)
  }
  suppressPackageStartupMessages(library(survival))

  data2 <- data
  data2[[modifier_var]] <- droplevels(as.factor(data2[[modifier_var]]))
  mod_levels <- levels(data2[[modifier_var]])
  if (length(mod_levels) < 2L) {
    if (.cxi06_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .cxi06_pause(ctx, paste0(modifier_var, " 有效水平 < 2"), "检查分类变量水平")
    }
    stop("cox_interaction: modifier 水平不足。", call. = FALSE)
  }

  ref_level <- as.character(bl_cfg$reference_level %||% mod_levels[1L])[1L]
  if (!ref_level %in% mod_levels) {
    stop(
      "cox_interaction: reference_level '", ref_level,
      "' 不在 ", modifier_var, " 的水平中。", call. = FALSE
    )
  }
  data2[[modifier_var]] <- factor(
    data2[[modifier_var]],
    levels = c(ref_level, setdiff(mod_levels, ref_level))
  )
  non_ref_levels <- setdiff(mod_levels, ref_level)

  data2$.cxi06_event01 <- .cxi06_coerce_event01(data2[[event_var]], event_value)
  data2 <- data2[!is.na(data2$.cxi06_event01), , drop = FALSE]
  n_events <- sum(data2$.cxi06_event01 == 1L, na.rm = TRUE)
  min_events <- as.integer(bl_cfg$min_events %||% 5L)[1L]
  if (isTRUE(bl_cfg$pause_on_low_events %||% TRUE) && n_events < min_events) {
    if (.cxi06_should_pause(bl_cfg, "pause_on_low_events", TRUE)) {
      .cxi06_pause(
        ctx,
        paste0("事件数过少 (", n_events, " < ", min_events, ")"),
        "扩大样本或降低 min_events"
      )
    }
  }

  min_ev_str <- as.integer(bl_cfg$min_events_stratum %||% 2L)[1L]
  for (lv in mod_levels) {
    sub_ev <- sum(
      data2$.cxi06_event01 == 1L & data2[[modifier_var]] == lv,
      na.rm = TRUE
    )
    if (sub_ev < min_ev_str) {
      cli::cli_alert_warning(
        "cox_interaction: {modifier_var}={lv} 事件数={sub_ev} (< {min_ev_str})"
      )
    }
  }

  keep_cols <- unique(c(time_var, event_var, index_var, modifier_var, ".cxi06_event01"))
  fit_df <- stats::na.omit(data2[, keep_cols, drop = FALSE])
  if (nrow(fit_df) < 10L) {
    if (.cxi06_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .cxi06_pause(ctx, "完整病例数过少", "检查缺失", utils::head(fit_df, 5L))
    }
    stop("cox_interaction: 完整病例 < 10。", call. = FALSE)
  }

  idx_sd <- stats::sd(fit_df[[index_var]], na.rm = TRUE)
  if (!is.finite(idx_sd) || idx_sd < 1e-10) {
    if (.cxi06_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
      .cxi06_pause(ctx, paste0(index_var, " 无变异"), "检查 index 列")
    }
    stop("cox_interaction: index 近似常数。", call. = FALSE)
  }

  f_main <- stats::as.formula(paste0(
    "Surv(", time_var, ", .cxi06_event01) ~ ",
    index_var, " + ", modifier_var
  ))
  f_int <- stats::as.formula(paste0(
    "Surv(", time_var, ", .cxi06_event01) ~ ",
    index_var, " * ", modifier_var
  ))

  fit_main <- tryCatch(
    survival::coxph(f_main, data = fit_df, x = TRUE, y = TRUE),
    error = function(e) {
      if (.cxi06_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
        .cxi06_pause(ctx, paste0("主效应 Cox 失败: ", conditionMessage(e)), "检查共线")
      }
      stop("cox_interaction: ", conditionMessage(e), call. = FALSE)
    }
  )
  fit_int <- tryCatch(
    survival::coxph(f_int, data = fit_df, x = TRUE, y = TRUE),
    error = function(e) {
      if (.cxi06_should_pause(bl_cfg, "pause_on_fit_fail", TRUE)) {
        .cxi06_pause(ctx, paste0("交互 Cox 失败: ", conditionMessage(e)), "检查共线")
      }
      stop("cox_interaction: ", conditionMessage(e), call. = FALSE)
    }
  )

  lrt <- tryCatch(
    stats::anova(fit_main, fit_int, test = "LRT"),
    error = function(e) NULL
  )

  cmp <- .cxi06_build_comparison(
    fit_main = fit_main,
    fit_int = fit_int,
    lrt = lrt,
    index_var = index_var,
    modifier_var = modifier_var,
    ref_level = ref_level,
    non_ref_levels = non_ref_levels,
    index_label = index_label,
    modifier_labels = modifier_labels,
    hr_digits = hr_digits
  )

  title_cap <- bl_cfg$table_title_caption %||%
    "Sensitivity Analysis Cox Proportional Hazards Models with and without Treatment Interaction"
  file_cap <- bl_cfg$table_file_caption %||% "Sensitivity Analysis Cox Interaction"
  pub <- pub_pair(
    ctx, ctx$output_dir_tables, "supp_table",
    title_caption = title_cap,
    file_caption = file_cap,
    ext = "xlsx"
  )

  footnotes <- bl_cfg$table_footnotes
  if (is.null(footnotes) || !length(footnotes)) {
    footnotes <- .cxi06_default_footnotes(ref_level, modifier_var, index_label)
  }

  tryCatch(
    export_sci_table(
      cmp$body,
      pub$filepath,
      title = pub$title,
      header_row1 = cmp$header_row1,
      header_row2 = cmp$header_row2,
      latex_include_colnames = FALSE,
      table_footnotes = as.character(footnotes)
    ),
    error = function(e) cli::cli_alert_warning("cox_interaction: 表导出失败: {e$message}")
  )

  if (isTRUE(bl_cfg$export_coef_csv %||% TRUE)) {
    coef_tbl <- .cxi06_tidy_int_export(fit_int, hr_digits)
    coef_fn <- bl_cfg$coef_csv %||% "Cox_Interaction_coefficients.csv"
    ctx <- save_result(ctx, "cox_interaction_coef_csv", coef_tbl, coef_fn)
  }

  slope_tbl <- NULL
  if (isTRUE(bl_cfg$run_emtrends %||% TRUE) && requireNamespace("emmeans", quietly = TRUE)) {
    slope_tbl <- tryCatch(
      {
        tr <- emmeans::emtrends(
          fit_int,
          specs = modifier_var,
          var = index_var,
          infer = c(TRUE, TRUE)
        )
        as.data.frame(tr)
      },
      error = function(e) {
        cli::cli_alert_warning("cox_interaction: emtrends 失败: {e$message}")
        NULL
      }
    )
    if (isTRUE(bl_cfg$export_slope_csv %||% TRUE) && is.data.frame(slope_tbl)) {
      slope_fn <- bl_cfg$slope_csv %||% "Cox_Interaction_slope_by_group.csv"
      ctx <- save_result(ctx, "cox_interaction_slope_csv", slope_tbl, slope_fn)
    }
  } else if (isTRUE(bl_cfg$run_emtrends %||% TRUE)) {
    cli::cli_alert_info("cox_interaction: 未安装 emmeans，跳过分组斜率表")
  }

  if (isTRUE(bl_cfg$export_lrt_txt %||% TRUE)) {
    lrt_fn <- bl_cfg$lrt_txt %||% "Cox_Interaction_LRT_summary.txt"
    lrt_path <- file.path(ctx$output_dir, lrt_fn)
    tryCatch({
      con <- file(lrt_path, open = "wt", encoding = "UTF-8")
      on.exit(close(con), add = TRUE)
      cat("N = ", nrow(fit_df), ", events = ", n_events, "\n", sep = "", file = con)
      cat("Reference ", modifier_var, " = ", ref_level, "\n\n", sep = "", file = con)
      cat("--- LRT: main vs interaction model ---\n", file = con)
      if (!is.null(lrt)) writeLines(capture.output(print(lrt)), con) else cat("(LRT unavailable)\n", file = con)
      cat("\n--- Interaction model summary ---\n", file = con)
      writeLines(capture.output(print(summary(fit_int))), con)
      cli::cli_alert_success("Saved: {.file {lrt_fn}}")
    }, error = function(e) {
      cli::cli_alert_warning("cox_interaction: LRT txt 失败: {e$message}")
    })
  }

  ctx$results$cox_interaction_fit_main <- fit_main
  ctx$results$cox_interaction_fit_int <- fit_int
  ctx$results$cox_interaction_lrt <- lrt
  ctx$results$cox_interaction_lrt_p <- cmp$lrt_p
  ctx$results$cox_interaction_comparison_table <- cmp$body
  ctx$results$cox_interaction_pub_table <- pub
  ctx$results$cox_interaction_ref_level <- ref_level
  ctx$results$cox_interaction_n <- nrow(fit_df)
  ctx$results$cox_interaction_n_events <- n_events
  ctx$results$cox_interaction_slope <- slope_tbl

  cli::cli_alert_success(
    "cox_interaction 完成: {.file {basename(pub$filepath)}} (ref={ref_level}, events={n_events})"
  )
  ctx
}

register_block(
  "cox_interaction",
  block_cox_interaction,
  "Cox 交互敏感性：有/无交互并排表 + LRT + 可选 emtrends"
)
