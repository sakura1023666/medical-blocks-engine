###############################################################################
#  cox_ml_continuous_batch — ML 连续特征批量 Cox（分位分组，统一协变量）
#
#  register_block: "cox_ml_continuous_batch"
#  前置: ml_feature_selection_bundle（ml_feature_names / feature_selection_final）
#  配置: config$cox_ml_continuous_batch$method = "quartile" | "tertile"
###############################################################################

.cml08_format_p_cells <- function(rt) {
  rt <- as.data.frame(rt, stringsAsFactors = FALSE)
  for (j in c(6L, 9L, 12L)) {
    if (ncol(rt) < j) next
    x <- as.character(rt[[j]])
    x[grepl("[0-9]+\\.?[0-9]*[eE][+-][0-9]+", x) | grepl("^0$", x)] <- "<0.001"
    rt[[j]] <- x
  }
  rt
}

.cml08_group_cutoffs <- function(x, gfac, breaks, method = "quartile") {
  labs <- levels(gfac)
  cutoffs <- setNames(character(length(labs)), labs)
  br <- as.numeric(breaks)
  br_inner <- if (!is.null(br) && length(br) >= 3L) {
    unique(br[-c(1L, length(br))])
  } else {
    numeric(0)
  }
  if (identical(method, "quartile") && length(br_inner) >= 3L && length(labs) == 4L) {
    cutoffs["Q1"] <- paste0("< ", round(br_inner[1L], 3))
    cutoffs["Q2"] <- paste0(round(br_inner[1L], 3), "-< ", round(br_inner[2L], 3))
    cutoffs["Q3"] <- paste0(round(br_inner[2L], 3), "-< ", round(br_inner[3L], 3))
    cutoffs["Q4"] <- paste0("\u2265 ", round(br_inner[3L], 3))
    return(cutoffs)
  }
  if (identical(method, "tertile") && length(br_inner) >= 2L && length(labs) == 3L) {
    cutoffs["T1"] <- paste0("< ", round(br_inner[1L], 3))
    cutoffs["T2"] <- paste0(round(br_inner[1L], 3), "-< ", round(br_inner[2L], 3))
    cutoffs["T3"] <- paste0("\u2265 ", round(br_inner[2L], 3))
    return(cutoffs)
  }
  for (lv in labs) {
    xv <- x[as.character(gfac) == lv & is.finite(x)]
    if (!length(xv)) {
      cutoffs[lv] <- paste0("rank ", method)
    } else {
      cutoffs[lv] <- paste0(round(min(xv), 3), "-", round(max(xv), 3), " (rank)")
    }
  }
  cutoffs
}

.cml08_grouped_table <- function(time_var, event_var, index_var, data,
                                 model1, model2, breaks = NULL, method = "quartile",
                                 ctx = NULL) {
  method <- match.arg(method, c("quartile", "tertile"))
  if (!exists("pipeline_quantile_group_factor", mode = "function")) {
    stop("缺少 pipeline_quantile_group_factor（请加载 pipeline_capability_layer.R）", call. = FALSE)
  }
  d <- data
  # Surv() 需要 0/1 事件；因子结局（如 No…/…Recurrence）会触发 multi-state 报错
  if (exists(".mlsurv_coerce_event01", mode = "function")) {
    d[[event_var]] <- .mlsurv_coerce_event01(d[[event_var]])
  } else if (is.factor(d[[event_var]]) || is.character(d[[event_var]])) {
    xc <- trimws(as.character(d[[event_var]]))
    d[[event_var]] <- if (all(xc[!is.na(xc)] %in% c("0", "1"))) {
      suppressWarnings(as.integer(xc))
    } else if (is.factor(d[[event_var]]) && nlevels(d[[event_var]]) == 2L) {
      as.integer(as.integer(d[[event_var]]) == 2L)
    } else {
      as.integer(grepl("(?i)recurr|relaps|death|dead|event|case|yes", xc))
    }
  } else {
    d[[event_var]] <- suppressWarnings(as.integer(d[[event_var]]))
  }
  gfac <- pipeline_quantile_group_factor(d[[index_var]], method = method, breaks = breaks)
  group_labels <- levels(gfac)
  d$Group <- gfac
  d$Num <- as.numeric(d$Group)
  cutoffs <- .cml08_group_cutoffs(as.numeric(d[[index_var]]), gfac, breaks, method)

  m1 <- setdiff(intersect(model1, names(d)), index_var)
  m2 <- setdiff(intersect(model2, names(d)), index_var)
  id_col <- as.character(((ctx$config$data %||% list())$id_column %||% "ID"))[1L]
  need <- unique(c(time_var, event_var, index_var, "Group", "Num", m1, m2))
  if (!is.null(ctx) && nzchar(id_col) && id_col %in% names(d)) {
    need <- unique(c(need, id_col))
  }
  dt <- stats::na.omit(d[, need, drop = FALSE])
  if (nrow(dt) < 20L) {
    stop(sprintf("%s: 有效样本 < 20，无法拟合 Cox", index_var), call. = FALSE)
  }
  if (nlevels(droplevels(dt$Group)) < 2L) {
    stop(sprintf("%s: %s 后有效组 < 2", index_var, method), call. = FALSE)
  }

  surv_lhs <- paste0("Surv(", time_var, ", ", event_var, ")")
  rhs_c <- function(vars) paste(c(vars), collapse = " + ")
  # 分位切点/Group/Num 锁在操作层模板；协变量缺失跨 m 用 mi_coxph + Rubin
  .fit <- function(rhs) {
    fml <- as.formula(paste0(surv_lhs, " ~ ", rhs_c(rhs)))
    if (exists("mi_coxph", mode = "function") && !is.null(ctx)) {
      mi_coxph(ctx, fml, dt, keep_vars = c(time_var, event_var, rhs))
    } else {
      survival::coxph(fml, data = dt)
    }
  }
  mc1 <- .fit(index_var)
  mc2 <- .fit(c(index_var, m1))
  mc3 <- .fit(c(index_var, m2))
  mf1 <- .fit("Group")
  mf2 <- .fit(c("Group", m1))
  mf3 <- .fit(c("Group", m2))
  mt1 <- .fit("Num")
  mt2 <- .fit(c("Num", m1))
  mt3 <- .fit(c("Num", m2))

  .hr_ci_p <- function(m, row) {
    if (exists("pub_hr_ci_p", mode = "function")) return(pub_hr_ci_p(m, row))
    sm <- summary(m); ci <- suppressMessages(confint(m))
    list(hr = round(exp(coef(m))[row], 3),
         ci = paste0("(", round(exp(ci[row, 1]), 3), ",", round(exp(ci[row, 2]), 3), ")"),
         p = pub_format_p_cell(sm$coefficients[row, "Pr(>|z|)"]))
  }
  n_total <- nrow(dt); cnt <- table(dt$Group)
  .pct <- function(lv) paste0(as.numeric(cnt[lv]), "(", round(as.numeric(cnt[lv]) / n_total * 100, 2), "%)")
  c1 <- .hr_ci_p(mc1, 1L); c2 <- .hr_ci_p(mc2, 1L); c3 <- .hr_ci_p(mc3, 1L)
  Line3 <- c(index_var, rep("", 11L))
  Line4 <- c(paste0(index_var, " continuous"), "", "", c1$hr, c1$ci, c1$p, c2$hr, c2$ci, c2$p, c3$hr, c3$ci, c3$p)
  Line5 <- c(paste0(index_var, " groups"), rep("", 11L))
  ref_lv <- group_labels[1L]
  Line_ref <- c(paste0(ref_lv, " (Ref)"), cutoffs[ref_lv], .pct(ref_lv), "Ref", "Ref", "", "Ref", "Ref", "", "Ref", "Ref", "")
  non_ref <- group_labels[-1L]
  lines_nonref <- lapply(seq_along(non_ref), function(i) {
    lv <- non_ref[i]; r <- .hr_ci_p(mf1, i); r2 <- .hr_ci_p(mf2, i); r3 <- .hr_ci_p(mf3, i)
    c(lv, cutoffs[lv], .pct(lv), r$hr, r$ci, r$p, r2$hr, r2$ci, r2$p, r3$hr, r3$ci, r3$p)
  })
  Line_trend <- c("p for trend", rep("", 4L),
                  pub_format_p_cell(summary(mt1)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt2)$coefficients[1, "Pr(>|z|)"]), "", "",
                  pub_format_p_cell(summary(mt3)$coefficients[1, "Pr(>|z|)"]))
  mat <- do.call(rbind, c(list(Line3, Line4, Line5, Line_ref), lines_nonref, list(Line_trend)))
  colnames(mat) <- c("V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "V11", "V12")
  as.data.frame(mat, stringsAsFactors = FALSE)
}

.cml08_table_footnotes <- function(time_var, event_var, event_label, model1, ml_pool,
                                   method = "quartile", model2_exclude_by_index = NULL,
                                   model2_factors = NULL, exposure_cont = NULL,
                                   excl_cont_exp = FALSE) {
  pretty <- function(v) gsub("_", " ", as.character(v), fixed = TRUE)
  m1_txt <- if (length(model1)) paste(vapply(model1, pretty, character(1L)), collapse = ", ") else "none"
  m2_set <- if (length(model2_factors)) {
    unique(as.character(model2_factors))
  } else if (isTRUE(excl_cont_exp)) {
    unique(c(model1, setdiff(ml_pool, exposure_cont %||% character(0))))
  } else {
    unique(c(ml_pool, model1))
  }
  m2_set <- m2_set[nzchar(m2_set)]
  if (isTRUE(excl_cont_exp) && length(exposure_cont)) {
    m2_set <- setdiff(m2_set, exposure_cont)
  }
  m2_txt <- if (length(m2_set)) paste(vapply(m2_set, pretty, character(1L)), collapse = ", ") else "none"
  grp_note <- if (identical(method, "tertile")) {
    "Exposure tertiles (T1–T3) were defined by sample-specific tertiles of each continuous ML-selected feature; if quantile cutpoints were non-unique, equal-frequency rank tertiles were used."
  } else {
    "Exposure quartiles (Q1–Q4) were defined by sample-specific quartiles of each continuous ML-selected feature; if quantile cutpoints were non-unique, equal-frequency rank quartiles were used."
  }
  grp_word <- if (identical(method, "tertile")) "tertiles" else "quartiles"
  excl_note <- NULL
  if (is.list(model2_exclude_by_index) && length(model2_exclude_by_index)) {
    bits <- vapply(names(model2_exclude_by_index), function(ix) {
      ex <- as.character(model2_exclude_by_index[[ix]] %||% character(0))
      ex <- ex[nzchar(ex)]
      if (!length(ex)) return(NA_character_)
      paste0(pretty(ix), " Model 2 omitted ", paste(vapply(ex, pretty, character(1L)), collapse = ", "),
             " (same clinical construct / over-adjustment)")
    }, character(1L))
    bits <- bits[!is.na(bits)]
    if (length(bits)) excl_note <- paste0(paste(bits, collapse = "; "), ".")
  }
  m2_line <- if (isTRUE(excl_cont_exp)) {
    paste0(
      "Model 2 adjusted for clinical/categorical covariates only (continuous ML exposures were not used as covariates): ",
      m2_txt, "."
    )
  } else {
    paste0(
      "Model 2 adjusted for all other ML-selected features plus Model 1 covariates ",
      "(excluding the index variable of each section): ", m2_txt, "."
    )
  }
  c(
    sprintf(
      "Survival outcome: time-to-event variable %s (months); event indicator %s (1 = %s).",
      time_var, event_var, event_label
    ),
    grp_note,
    paste0("Crude Model: index variable only (continuous, grouped ", grp_word, ", or ordinal trend)."),
    paste0(
      "Model 1 adjusted for: ", m1_txt,
      if (isTRUE(excl_cont_exp)) " (continuous ML exposures excluded from covariates)" else "",
      "."
    ),
    m2_line,
    if (!is.null(excl_note)) excl_note else NULL,
    "Continuous ML features entered Cox models on their original scale (no additional log transformation).",
    paste0(
      "SHAP waterfall annotations (Figure 6): link-scale f(x) and baseline E[f(x)] from the surrogate ",
      "explainer were mapped to predicted recurrence probability via plogis(); SHAP contributions are ",
      "not used in this Cox table."
    )
  )
}

block_cox_ml_continuous_batch <- function(ctx, ...) {
  suppressPackageStartupMessages(library(survival))
  cfg <- ctx$config
  bl <- cfg$cox_ml_continuous_batch %||% list()
  if (isFALSE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("cox_ml_continuous_batch: enable=FALSE，跳过。")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("cox_ml_continuous_batch: 无分析数据。", call. = FALSE)
  }

  surv <- cfg$survival %||% list()
  time_var <- as.character(bl$time_var %||% surv$time_var %||% "")[1L]
  event_var <- as.character(bl$event_var %||% surv$event_var %||% cfg$data$outcome_column %||% "")[1L]
  if (!nzchar(time_var) || !time_var %in% names(data)) {
    stop("cox_ml_continuous_batch: time_var 未设置或不在数据中。", call. = FALSE)
  }
  if (!nzchar(event_var) || !event_var %in% names(data)) {
    stop("cox_ml_continuous_batch: event_var 未设置或不在数据中。", call. = FALSE)
  }

  feats <- as.character(bl$features %||% ctx$results$ml_feature_names %||%
                          ctx$results$feature_selection_final %||% character(0))
  feats <- unique(feats[nzchar(feats)])
  if (!length(feats)) {
    stop("cox_ml_continuous_batch: 无 ML 特征（请先运行特征选择）。", call. = FALSE)
  }

  method <- as.character(bl$method %||% "quartile")[1L]
  if (!method %in% c("quartile", "tertile")) {
    cli::cli_alert_warning("cox_ml_continuous_batch: method={method} 不支持，改用 quartile。")
    method <- "quartile"
  }

  cont_feats <- feats[vapply(feats, function(v) {
    x <- data[[v]]
    # 真连续：水平数须 > discrete_max（默认 5）；分期/等级等低基数勿做分位 Cox
    nlev <- length(unique(stats::na.omit(x)))
    disc_max <- as.integer(bl$discrete_max_levels %||% cfg$cox_ml_continuous_batch$discrete_max_levels %||% 5L)[1L]
    if (!is.finite(disc_max) || disc_max < 2L) disc_max <- 5L
    is.numeric(x) && !is.factor(x) && nlev > disc_max
  }, logical(1L))]
  exclude_feats <- unique(c(
    as.character(bl$exclude_features %||% character(0)),
    as.character(cfg$force_factor_vars %||% character(0))
  ))
  exclude_feats <- exclude_feats[nzchar(exclude_feats)]
  if (length(exclude_feats)) {
    dropped <- intersect(cont_feats, exclude_feats)
    cont_feats <- setdiff(cont_feats, exclude_feats)
    if (length(dropped)) {
      cli::cli_alert_info(
        "cox_ml_continuous_batch: 已排除分类/指定变量: {paste(dropped, collapse = ', ')}"
      )
    }
  }
  if (!length(cont_feats)) {
    cli::cli_alert_warning("cox_ml_continuous_batch: ML 特征中无连续变量，跳过。")
    return(ctx)
  }

  disease_label <- cfg$project$analysis_group %||% cfg$project$disease
  data2 <- data
  if (is.character(data2[[event_var]]) || is.factor(data2[[event_var]])) {
    data2[[event_var]] <- ifelse(data2[[event_var]] == disease_label, 1, 0)
  }
  data2[[event_var]] <- as.numeric(data2[[event_var]])
  data2[[time_var]] <- as.numeric(data2[[time_var]])

  model1 <- as.character(bl$model1_factors %||% ctx$results$Model1Factors %||% character(0))
  ml_pool <- as.character(ctx$results$feature_selection_final %||% ctx$results$ml_feature_names %||% feats)
  ml_pool <- unique(ml_pool[nzchar(ml_pool)])
  model1 <- unique(model1[nzchar(model1)])
  if (!length(model1)) model1 <- character(0)
  ## 显式 Model2（课题可锁「协变量 ≠ 连续暴露」）；未设则回退：其它 ML 特征 + Model1 − 当前暴露
  model2_fixed <- unique(as.character(bl$model2_factors %||% character(0)))
  model2_fixed <- model2_fixed[nzchar(model2_fixed)]
  exposure_cont <- cont_feats
  excl_cont_exp <- isTRUE(bl$covariates_exclude_continuous_exposures %||% length(model2_fixed) > 0)

  cli::cli_alert_info(
    paste0(
      "cox_ml_continuous_batch: ", length(cont_feats), " 个连续 ML 特征；method=", method,
      "；time=", time_var,
      "；M1=", if (length(model1)) paste(model1, collapse = ", ") else "none",
      "；M2=", if (length(model2_fixed)) paste(model2_fixed, collapse = ", ") else "ML池-当前暴露",
      if (excl_cont_exp) "（连续暴露不进协变量）" else "", "."
    )
  )

  model2_exclude_by_index <- bl$model2_exclude_by_index %||% list()
  if (!is.list(model2_exclude_by_index)) model2_exclude_by_index <- list()

  parts <- list()
  ok_feats <- character(0)
  for (vi in seq_along(cont_feats)) {
    v <- cont_feats[vi]
    if (length(model2_fixed)) {
      model2 <- model2_fixed
    } else if (isTRUE(excl_cont_exp)) {
      cat_ml <- setdiff(ml_pool, exposure_cont)
      model2 <- unique(c(model1, cat_ml))
    } else {
      model2 <- unique(c(setdiff(ml_pool, v), model1))
    }
    ## 当前暴露永不进调整集；若锁定口径则所有连续暴露都不进
    model2 <- setdiff(model2, v)
    if (isTRUE(excl_cont_exp)) model2 <- setdiff(model2, exposure_cont)
    model1_use <- setdiff(model1, v)
    if (isTRUE(excl_cont_exp)) model1_use <- setdiff(model1_use, exposure_cont)

    ex_v <- unique(as.character(model2_exclude_by_index[[v]] %||% character(0)))
    ex_v <- ex_v[nzchar(ex_v)]
    if (length(ex_v)) {
      model2 <- setdiff(model2, ex_v)
      cli::cli_alert_info(
        "cox_ml_continuous_batch: {v} Model2 剔除过度校正变量: {paste(ex_v, collapse = ', ')}"
      )
    }
    br <- if (exists("pipeline_quantile_breaks", mode = "function")) {
      pipeline_quantile_breaks(data2[[v]], method = method)
    } else if (identical(method, "tertile")) {
      as.numeric(stats::quantile(data2[[v]], probs = c(0, 1 / 3, 2 / 3, 1), na.rm = TRUE, type = 7))
    } else {
      as.numeric(stats::quantile(data2[[v]], probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE, type = 7))
    }
    if (is.null(br) || !length(br)) {
      stop("cox_ml_continuous_batch: ", v, " 无法计算 ", method, " 切点。", call. = FALSE)
    }
    if (exists("pipeline_store_continuous_km_cutpoints", mode = "function")) {
      ctx <- pipeline_store_continuous_km_cutpoints(ctx, v, br, method = method)
    }
    tb <- tryCatch(
      .cml08_grouped_table(
        time_var, event_var, v, data2, model1_use, model2,
        breaks = br, method = method, ctx = ctx
      ),
      error = function(e) {
        stop("cox_ml_continuous_batch: ", v, " 未能生成 ", method, "/连续 Cox 表 — ", e$message, call. = FALSE)
      }
    )
    parts[[length(parts) + 1L]] <- .cml08_format_p_cells(tb)
    ok_feats <- c(ok_feats, v)
    if (vi < length(cont_feats)) {
      spacer <- tb[1L, , drop = FALSE]
      spacer[] <- ""
      parts[[length(parts) + 1L]] <- spacer
    }
  }
  if (!length(parts)) {
    stop("cox_ml_continuous_batch: 未生成任何 Cox 表。", call. = FALSE)
  }
  if (all(parts[[length(parts)]] == "", na.rm = TRUE)) parts <- parts[-length(parts)]
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  ncol_out <- ncol(out)
  h1 <- c("", "", "", "", "Crude Model", "", "", "Model1", "", "", "Model2", "")
  h2 <- c(
    "Characteristic", "Exposure cutoff", "N (%)", "HR", "95%CI", "P-value",
    "HR", "95%CI", "P-value", "HR", "95%CI", "P-value"
  )
  if (length(h1) != ncol_out) h1 <- c(h1, rep("", ncol_out - length(h1)))[seq_len(ncol_out)]
  if (length(h2) != ncol_out) h2 <- c(h2, rep("", ncol_out - length(h2)))[seq_len(ncol_out)]
  colnames(out) <- paste0("V", seq_len(ncol_out))

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  cap <- bl$table_title %||% paste0(
    "Cox regression for ML continuous features (", method, ") — ", cfg$project$disease
  )
  event_label <- cfg$project$analysis_group %||% cfg$project$disease %||% "event"
  footnotes <- .cml08_table_footnotes(
    time_var, event_var, event_label, model1, ml_pool,
    method = method, model2_exclude_by_index = model2_exclude_by_index,
    model2_factors = model2_fixed, exposure_cont = exposure_cont,
    excl_cont_exp = excl_cont_exp
  )
  if (exists("mi_append_table_footnotes", mode = "function")) {
    footnotes <- mi_append_table_footnotes(footnotes, ctx)
  }
  ctx$results$cox_ml_continuous_model2_factors <- if (length(model2_fixed)) model2_fixed else NULL
  pub <- pub_paths(ctx, tbl_dir, "supp_table", cap, "xlsx")
  export_sci_table(
    out, pub$filepath, title = pub$title, table_footnotes = footnotes,
    header_row1 = h1, header_row2 = h2, latex_include_colnames = FALSE
  )
  ctx$results$cox_ml_continuous_batch_table <- out
  ctx$results$cox_ml_continuous_batch_features <- ok_feats
  ctx$results$cox_ml_continuous_model1 <- model1
  ctx$results$cox_ml_continuous_model2_pool <- ml_pool
  cli::cli_alert_success(
    "cox_ml_continuous_batch: 已导出 {length(ok_feats)} 个连续特征的 Cox 表（{paste(ok_feats, collapse = ', ')}）。"
  )
  ctx
}

register_block(
  "cox_ml_continuous_batch",
  block_cox_ml_continuous_batch,
  "ML 连续特征批量 Cox（分位分组，统一 Model1/Model2 协变量）"
)
