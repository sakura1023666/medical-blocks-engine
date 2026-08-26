###############################################################################
#  subgroup_prognosis_continuous — 预后亚组森林图（Index 连续暴露，Cox HR per unit + forestploter）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_config = config$subgroup, survival$time_var/event_var, logistic$index_var
#
#  读 config$subgroup；Index 不做 high/low 二分（对齐 C01_Subgroup analysis.R）。
#  启用: config$subgroup$index_exposure = "continuous"
###############################################################################

.sgpc04_canonical_subgroup_order_vec <- function() {
  c(
    "Age_Group",
    "Gender",
    "BMI",
    "Education",
    "Marital_Status",
    "Income",
    "Smoking",
    "Alcohol_drinking",
    "Race",
    "Weight",
    "Height",
    "Language",
    "Micu_Code",
    "Insurance",
    "Ventilation",
    "Hypertension",
    "Diabetes",
    "T1DM",
    "T2DM",
    "Heart_Failure",
    "Myocardial_Infarction",
    "Atrial_Fibrillation",
    "Stroke",
    "COPD",
    "CKD",
    "Acute_Renal_Failure",
    "Liver_cirrhosis",
    "Hepatitis",
    "Cancer",
    "Hyperlipidemia",
    "Pneumonia",
    "Tuberculosis",
    "Dementia"

  )
}

.sgpc04_order_subgroup_vars_clinical <- function(v, req_ord) {
  v <- unique(as.character(v))
  canon <- .sgpc04_canonical_subgroup_order_vec()
  in_canon <- intersect(canon, v)
  loose <- sort(setdiff(v, canon))
  c(in_canon, loose)
}

.sgpc04_pretty_subgroup_label <- function(x) {
  x <- as.character(x %||% "")
  # 仅下划线→空格；勿把区间连字符「30-44」抹成「30 44」（Fig 6 等森林图标签）
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- gsub("([0-9]{2})\\s+([0-9]{2})", "\\1-\\2", x, perl = TRUE)
  trimws(x)
}

block_subgroup_prognosis_continuous <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(jstable)
    library(forestploter)
    library(grid)
  })

  cfg <- ctx$config
  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp)) stop("No data found. Run 'imputation' or 'data_clean' first.")
  data_imp <- as.data.frame(data_imp)

  log_idx <- cfg$logistic$index_var
  if (is.null(log_idx)) stop("index_var is required in config$logistic")

  study_type <- "prognosis"

  sub_cfg <- cfg$subgroup %||% list()
  surv <- cfg$survival %||% list()
  inc_cfg <- cfg$incidence %||% list()
  time_col <- surv$time_var %||% surv$time_column %||% "futime"
  status_col <- surv$event_var %||% surv$status_column %||% surv$event_column %||% "fustatus"

  index_var <- surv$index_var %||% log_idx
  disease_col <- cfg$data$outcome_column %||% "fustatus"

  analysis_grp <- cfg$project$analysis_group %||% cfg$project$disease
  ref_grp <- cfg$project$reference_group %||% "Control"
  disease_label <- analysis_grp

  cli::cli_alert_info("Subgroup mode: {study_type}, continuous index (outcome column: {.field {disease_col}})")
  cli::cli_alert_info("Index variable: {index_var}")
  cli::cli_alert_info("Case / positive label: {disease_label}")

  raw_min_n <- sub_cfg$min_n %||% 20
  if (!is.numeric(raw_min_n) || length(raw_min_n) != 1L || is.na(raw_min_n)) {
    stop("config$subgroup$min_n 必须是数值（绝对人数，或 0~1 之间比例）。", call. = FALSE)
  }
  if (raw_min_n > 0 && raw_min_n < 1) {
    min_group_size <- max(1L, as.integer(ceiling(nrow(data_imp) * raw_min_n)))
    cli::cli_alert_info(
      "Subgroup min_n 使用比例模式: {raw_min_n} × {nrow(data_imp)} = {min_group_size}"
    )
  } else {
    min_group_size <- max(1L, as.integer(raw_min_n))
  }
  age_cut <- sub_cfg$age_cutoff %||% 65
  forbid <- unique(c(
    sub_cfg$forbid_subgroup_vars %||% character(0),
    sub_cfg$exclude_vars %||% character(0)
  ))
  req <- sub_cfg$required_subgroup_vars %||% sub_cfg$vars %||% character(0)
  if (length(intersect(req, forbid))) {
    stop(
      "config$subgroup: required_subgroup_vars 与 forbid/exclude 冲突: ",
      paste(intersect(req, forbid), collapse = ", ")
    )
  }

  age_lo <- paste0("< ", age_cut)
  age_hi <- paste0("\u2265 ", age_cut)
  if (!"Age" %in% names(data_imp)) {
    cli::cli_alert_warning("Age column not found, skipping Age_Group")
    data_imp$Age_Group <- NA_character_
  } else {
    data_imp$Age_Group <- ifelse(data_imp$Age < age_cut, age_lo, age_hi)
    data_imp$Age_Group <- factor(data_imp$Age_Group, levels = c(age_lo, age_hi))
    agt <- table(data_imp$Age_Group, useNA = "ifany")
    cli::cli_alert_info(
      "Age grouping (cutoff {age_cut}): {paste(paste0(names(agt), '=', as.integer(agt)), collapse=', ')}"
    )
  }

  if ("BMI" %in% names(data_imp)) {
    data_imp$BMI <- ifelse(data_imp$BMI < 25, "< 25", data_imp$BMI)
    data_imp$BMI <- ifelse(data_imp$BMI >= 25 & data_imp$BMI < 30, "25-30", data_imp$BMI)
    data_imp$BMI <- ifelse(data_imp$BMI >= 30, "≥ 30", data_imp$BMI)
    data_imp$BMI <- factor(data_imp$BMI, levels = c("< 25", "25-30", "≥ 30"))
    cli::cli_alert_info("BMI grouping: {table(data_imp$BMI)}")
    has_bmi <- TRUE
  } else {
    cli::cli_alert_warning("BMI column not found in data, skipping BMI grouping")
    has_bmi <- FALSE
  }

  id_col <- cfg$data$id_column %||% character(0)
  non_cat <- unique(c(index_var, disease_col, id_col, time_col, status_col))

  suf <- sub_cfg$continuous_subgroup_suffix %||% "_subg"
  cont_vars <- sub_cfg$continuous_subgroup_vars %||% character(0)
  cont_only <- isTRUE(sub_cfg$continuous_subgroup_only)
  cont_cuts <- sub_cfg$continuous_subgroup_cutoffs %||% list()
  keep_ab <- !isFALSE(sub_cfg$continuous_subgroup_keep_age_bmi)

  new_cont_sub <- character(0)
  if (length(cont_vars)) {
    for (v in cont_vars) {
      if (!nzchar(v)) next
      if (!v %in% names(data_imp)) {
        cli::cli_alert_warning("continuous_subgroup_vars: {.field {v}} not in data, skip")
        next
      }
      if (v %in% non_cat) {
        cli::cli_alert_warning("continuous_subgroup_vars: {.field {v}} is index/outcome/id/time/status, skip")
        next
      }
      xv <- suppressWarnings(as.numeric(data_imp[[v]]))
      if (all(is.na(xv))) {
        cli::cli_alert_warning("continuous_subgroup_vars: {.field {v}} has no usable numeric values, skip")
        next
      }
      cu <- cont_cuts[[v]]
      if (is.null(cu)) {
        cu <- stats::median(xv, na.rm = TRUE)
      } else {
        cu <- suppressWarnings(as.numeric(cu))
        if (length(cu) < 1L || !is.finite(cu[[1L]])) {
          cu <- stats::median(xv, na.rm = TRUE)
        } else {
          cu <- cu[[1L]]
        }
      }
      newnm <- paste0(v, suf)
      if (newnm %in% names(data_imp)) {
        cli::cli_alert_warning("Column {.field {newnm}} already exists, reuse if categorical")
        if (is.factor(data_imp[[newnm]]) || is.character(data_imp[[newnm]])) {
          new_cont_sub <- c(new_cont_sub, newnm)
        }
        next
      }
      hi <- paste0("\u2265 ", cu)
      lo <- paste0("< ", cu)
      gv <- ifelse(is.na(xv), NA_character_, ifelse(xv >= cu, hi, lo))
      data_imp[[newnm]] <- factor(gv, levels = c(lo, hi))
      new_cont_sub <- c(new_cont_sub, newnm)
      cli::cli_alert_info("Continuous→subgroup {.field {newnm}} (cutoff={round(cu, 4)}) from {.field {v}}")
    }
  }

  if (cont_only && length(new_cont_sub) == 0L) {
    cli::cli_alert_warning(
      "continuous_subgroup_only=TRUE but no valid continuous_subgroup_vars; fallback to auto categorical pool"
    )
    cont_only <- FALSE
  }

  if (length(req)) {
    req <- vapply(req, function(r) {
      if (r %in% cont_vars && paste0(r, suf) %in% names(data_imp)) paste0(r, suf) else r
    }, character(1))
    req <- unique(req)
  }

  if (isTRUE(cont_only)) {
    prefix_ab <- c()
    if (isTRUE(keep_ab)) {
      if ("Age_Group" %in% names(data_imp) && !all(is.na(data_imp$Age_Group))) prefix_ab <- c(prefix_ab, "Age_Group")
      if (isTRUE(has_bmi)) prefix_ab <- c(prefix_ab, "BMI")
    }
    categorical_vars <- unique(c(prefix_ab, new_cont_sub))
    cli::cli_alert_info("continuous_subgroup_only=TRUE: subgroup pool = {paste(categorical_vars, collapse=', ')}")
  } else {
    categorical_vars <- names(data_imp)[sapply(data_imp, function(x) is.factor(x) || is.character(x))]
    categorical_vars <- categorical_vars[!categorical_vars %in% non_cat]
    if (length(new_cont_sub)) {
      categorical_vars <- unique(c(categorical_vars, new_cont_sub))
    }
  }

  if (length(forbid)) {
    categorical_vars <- setdiff(categorical_vars, forbid)
    cli::cli_alert_info("Forbid subgroup vars (removed from pool): {paste(forbid, collapse=', ')}")
  }
  if (length(req)) {
    miss <- setdiff(req, names(data_imp))
    if (length(miss)) {
      stop("config$subgroup$required_subgroup_vars 不在数据中: ", paste(miss, collapse = ", "))
    }
    for (rv in req) {
      if (!is.factor(data_imp[[rv]]) && !is.character(data_imp[[rv]])) {
        stop("config$subgroup$required_subgroup_vars 须为因子或字符型列: ", rv)
      }
    }
    cli::cli_alert_info("Required subgroup vars: {paste(req, collapse=', ')}")
  }
  cli::cli_alert_info("Categorical variables found: {paste(categorical_vars, collapse=', ')}")

  prefix_demo <- c()
  if ("Age_Group" %in% categorical_vars) prefix_demo <- c(prefix_demo, "Age_Group")
  if (isTRUE(has_bmi) && "BMI" %in% categorical_vars) prefix_demo <- c(prefix_demo, "BMI")
  cat_rest <- setdiff(categorical_vars, prefix_demo)
  subgroup_vars <- unique(c(prefix_demo, cat_rest))
  cli::cli_alert_info("Subgroup variables: {paste(subgroup_vars, collapse=', ')}")

  vars_to_keep <- c()
  for (v in subgroup_vars) {
    if (v == "Age_Group" && all(is.na(data_imp[[v]]))) next
    if (v %in% names(data_imp)) {
      if (is.factor(data_imp[[v]]) || is.character(data_imp[[v]])) {
        if (is.character(data_imp[[v]])) {
          data_imp[[v]] <- as.factor(data_imp[[v]])
        }
        group_counts <- table(data_imp[[v]])
        valid_levels <- names(group_counts[group_counts >= min_group_size])
        # TableSubgroupMultiCox / TableSubgroupMultiGLM 需要每个亚组变量至少 2 个水平，否则易报
        # "incorrect number of dimensions" 等内部错误，且无法生成森林图
        if (length(valid_levels) >= 2L) {
          data_imp[[v]] <- factor(data_imp[[v]], levels = valid_levels)
          data_imp <- data_imp[!is.na(data_imp[[v]]), ]
          vars_to_keep <- c(vars_to_keep, v)
          cli::cli_alert_info("Variable {v}: keeping levels {paste(valid_levels, collapse=', ')} (min size >= {min_group_size})")
        } else if (length(valid_levels) == 1L) {
          cli::cli_alert_warning(
            "Variable {v}: 仅 1 个水平满足 min_n={min_group_size}（{valid_levels}），无法做亚组交互，已剔除"
          )
        } else {
          cli::cli_alert_warning("Variable {v}: all groups have less than {min_group_size} subjects, removing")
        }
      }
    }
  }

  subgroup_vars <- vars_to_keep
  if (length(req)) {
    dropped_req <- setdiff(req, subgroup_vars)
    if (length(dropped_req)) {
      stop(
        "下列 required_subgroup_vars 在 min_n={min_group_size} 过滤后未能保留: ",
        paste(dropped_req, collapse = ", ")
      )
    }
  }
  subgroup_vars <- .sgpc04_order_subgroup_vars_clinical(subgroup_vars, req)
  if (length(subgroup_vars) == 0) {
    cli::cli_alert_warning("No valid subgroup variables after filtering")
    return(ctx)
  }
  cli::cli_alert_info("Final subgroup variables: {paste(subgroup_vars, collapse=', ')}")

  if (!index_var %in% names(data_imp)) {
    cli::cli_alert_warning("Index variable '{index_var}' not found in data")
    return(ctx)
  }

  rt <- data_imp

  if (!time_col %in% names(rt)) {
    cli::cli_alert_warning("Time column '{time_col}' not found, skipping subgroup analysis")
    return(ctx)
  }
  if (!status_col %in% names(rt)) {
    cli::cli_alert_warning("Status column '{status_col}' not found, skipping subgroup analysis")
    return(ctx)
  }
  rt[[time_col]] <- as.numeric(rt[[time_col]])
  if (is.character(rt[[status_col]]) || is.factor(rt[[status_col]])) {
    status_values <- unique(rt[[status_col]])
    event_value <- surv$event_value %||% disease_label
    if (!(event_value %in% status_values)) {
      event_value <- status_values[2]
    }
    rt[[status_col]] <- ifelse(rt[[status_col]] == event_value, 1, 0)
    cli::cli_alert_info("Converting {status_col} to numeric: '{event_value}' = 1, others = 0")
  }
  rt[[status_col]] <- as.numeric(rt[[status_col]])

  rt[[index_var]] <- suppressWarnings(as.numeric(as.character(rt[[index_var]])))
  n_before <- nrow(rt)
  rt <- rt[!is.na(rt[[index_var]]), , drop = FALSE]
  if (nrow(rt) < n_before) {
    cli::cli_alert_info("Dropped {n_before - nrow(rt)} rows with non-numeric/missing {index_var}")
  }
  if (nrow(rt) < 10L) {
    cli::cli_alert_warning("Too few rows after numeric index filter, skipping subgroup analysis")
    return(ctx)
  }
  cli::cli_alert_info("Index analyzed as continuous (per 1-unit HR)")

  final_subgroup_vars <- subgroup_vars
  index_cut_col <- paste0(index_var, "_index_cut")
  if (index_cut_col %in% final_subgroup_vars) {
    cli::cli_alert_warning(
      "Excluding {.field {index_cut_col}}: 与连续 index 暴露可能共线，已从亚组变量中剔除。"
    )
    final_subgroup_vars <- setdiff(final_subgroup_vars, index_cut_col)
  }
  if (length(final_subgroup_vars) == 0L) {
    cli::cli_alert_warning("No subgroup variables left after exclusions")
    return(ctx)
  }
  final_subgroup_vars <- .sgpc04_order_subgroup_vars_clinical(final_subgroup_vars, req)
  cli::cli_alert_info("Subgroup table variables: {paste(final_subgroup_vars, collapse=', ')}")

  # 再次剔除调用 jstable 前仍只有 1 个水平的因子（如上游步骤改过 rt）
  ok_lvl <- vapply(final_subgroup_vars, function(v) {
    if (!v %in% names(rt)) return(FALSE)
    x <- rt[[v]]
    if (is.factor(x)) nlevels(droplevels(x)) >= 2L
    else if (is.character(x)) length(unique(stats::na.omit(x))) >= 2L
    else FALSE
  }, logical(1))
  dropped_1lev <- final_subgroup_vars[!ok_lvl]
  if (length(dropped_1lev)) {
    cli::cli_alert_warning(
      "剔除亚组变量（当前数据上有效水平 <2）: {paste(dropped_1lev, collapse=', ')}"
    )
  }
  final_subgroup_vars <- final_subgroup_vars[ok_lvl]
  if (length(final_subgroup_vars) == 0L) {
    cli::cli_alert_warning("无可用亚组变量（均需至少 2 水平），跳过亚组表与森林图")
    return(ctx)
  }

  final_subgroup_vars <- .sgpc04_order_subgroup_vars_clinical(final_subgroup_vars, req)
  cli::cli_alert_info("Subgroup table variables (final): {paste(final_subgroup_vars, collapse=', ')}")

  rt <- droplevels(as.data.frame(rt, stringsAsFactors = FALSE))
  for (vv in final_subgroup_vars) {
    if (vv %in% names(rt) && (is.character(rt[[vv]]) || is.factor(rt[[vv]]))) {
      rt[[vv]] <- factor(rt[[vv]])
    }
  }
  rt <- droplevels(rt)

  cox_formula <- as.formula(paste("Surv(", time_col, ", ", status_col, ") ~ ", index_var, sep = ""))
  cli::cli_alert_info("Running TableSubgroupMultiCox...")
  res <- tryCatch(
    TableSubgroupMultiCox(
      formula = cox_formula,
      var_subgroups = final_subgroup_vars,
      data = rt
    ),
    error = function(e) {
      cli::cli_alert_danger("TableSubgroupMultiCox error: {e$message}")
      NULL
    }
  )
  effect_sym <- "HR"
  arrow_lab <- c(
    paste("Decreased Risk for", disease_label),
    paste("Increased Risk for", disease_label)
  )

  if (!is.null(res) && is.data.frame(res) && !"Point Estimate" %in% names(res) && "OR" %in% names(res)) {
    io <- which(names(res) == "OR")[[1L]]
    names(res)[io] <- "Point Estimate"
    res[[io]] <- suppressWarnings(as.numeric(as.character(res[[io]])))
  }

  need_cols <- c("Lower", "Upper", "Variable", "Point Estimate")
  res_ok <- !is.null(res) && is.data.frame(res) && nrow(res) > 1L && all(need_cols %in% names(res))
  if (!isTRUE(res_ok)) {
    cli::cli_alert_warning("No valid subgroup table (empty, wrong shape, or error above)")
    return(ctx)
  }

  res <- res[-1, , drop = FALSE]
  if (nrow(res) == 0L) {
    cli::cli_alert_warning("Subgroup table dropped to zero rows after header removal")
    return(ctx)
  }
  if (ncol(res) < 10L) {
    cli::cli_alert_warning("Subgroup table has {ncol(res)} columns (forest 需要 >= 10)")
    return(ctx)
  }

  plot_df <- res[, 1:10]
  plot_df[, c(2, 3, 9, 10)][is.na(plot_df[, c(2, 3, 9, 10)])] <- " "
  plot_df$` ` <- paste(rep(" ", nrow(plot_df)), collapse = " ")
  plot_df[, 4:6] <- apply(plot_df[, 4:6], 2, as.numeric)
  ci_lab <- paste0(effect_sym, " (95% CI)")
  plot_df[[ci_lab]] <- ifelse(is.na(plot_df$"Point Estimate"), "",
    sprintf("%.2f (%.2f to %.2f)",
      plot_df$"Point Estimate", plot_df$Lower, plot_df$Upper
    )
  )

  .lbl_no_us <- function(x) gsub("_", " ", as.character(x), fixed = TRUE)
  txt_cols <- intersect(c(1L, 2L, 3L, 9L, 10L), seq_len(ncol(plot_df)))
  for (ci in txt_cols) {
    plot_df[[ci]] <- .lbl_no_us(plot_df[[ci]])
  }

  plot_ff <- plot_font_from_config(ctx$config)

  forest_ci_col <- "black"
  if (exists("is_pub_profile", mode = "function") &&
      is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki")) {
    ov <- if (exists("pub_figure_profile_forest_overrides", mode = "function")) {
      pub_figure_profile_forest_overrides(ctx$config)
    } else {
      list(ci_col = "#1B4F72", highlight_interaction_sig = TRUE)
    }
    if (!is.null(ov$ci_col)) forest_ci_col <- ov$ci_col
    if (isTRUE(ov$highlight_interaction_sig)) {
      sub_cfg$forest_highlight_interaction_sig <- TRUE
    }
  }

  tm <- forest_theme(
    base_size = 12,
    base_family = plot_ff,
    refline_gp = gpar(lty = "dashed", col = "black"),
    ci_pch = c(15),
    ci_col = forest_ci_col,
    ci_alpha = 0.8,
    ci_lty = 1,
    ci_lwd = 1.5,
    ci_Theight = 0,
    vertline_lty = c("dashed", "dotted"),
    vertline_col = c("#d6604d", "#bababa")
  )

  fx <- sub_cfg$forest_xlim_continuous %||% sub_cfg$forest_xlim %||% c(0.5, 1.5)
  fx <- suppressWarnings(as.numeric(fx))
  if (length(fx) != 2L || any(!is.finite(fx)) || fx[2] <= fx[1]) {
    cli::cli_alert_warning("config$subgroup$forest_xlim_continuous / forest_xlim 无效，改用 c(0.5, 1.5)")
    fx <- c(0.5, 1.5)
  }
  ft <- sub_cfg$forest_ticks_at_continuous %||% sub_cfg$forest_ticks_at
  if (is.null(ft) || !length(ft)) {
    ft <- c(0.5, 1, 1.5)
    ft <- ft[ft >= fx[1] & ft <= fx[2]]
    if (!length(ft)) ft <- seq(fx[1], fx[2], length.out = 3L)
  } else {
    ft <- suppressWarnings(as.numeric(ft))
    ft <- ft[is.finite(ft)]
    if (!length(ft)) ft <- seq(fx[1], fx[2], length.out = 3L)
  }
  f_arrow <- sub_cfg$forest_arrow_length
  if (is.null(f_arrow) || !is.finite(suppressWarnings(as.numeric(f_arrow)))) {
    f_arrow <- fx[2]
  } else {
    f_arrow <- as.numeric(f_arrow)
  }

  dt <- plot_df
  p <- forest(
    dt[, c(1, 2, 3, 11, 12, 9, 10)],
    est = list(dt$`Point Estimate`),
    lower = list(dt$Lower),
    upper = list(dt$Upper),
    ci_column = c(4),
    sizes = 0.6,
    ref_line = 1,
    arrow_lab = arrow_lab,
    xlim = fx,
    ticks_at = ft,
    arrow_length = f_arrow,
    theme = tm
  )

  var_labels_for_bold <- .lbl_no_us(final_subgroup_vars)
  subgroup_row_indices <- which(trimws(as.character(plot_df$Variable)) %in% var_labels_for_bold)
  if (length(subgroup_row_indices) > 0) {
    p <- edit_plot(p, row = subgroup_row_indices, gp = gpar(fontface = "bold"))
  }
  if (isTRUE(sub_cfg$forest_highlight_interaction_sig)) {
    pint_col <- grep("interaction", names(plot_df), ignore.case = TRUE)[1L]
    if (is.finite(pint_col)) {
      pv_num <- suppressWarnings(as.numeric(gsub("[^0-9.eE+-]", "", as.character(plot_df[[pint_col]]))))
      sig_rows <- which(is.finite(pv_num) & pv_num < 0.05)
      # forest() used cols 1,2,3,11,12,9,10 — P for interaction is last of those
      forest_pint <- 7L
      if (length(sig_rows)) {
        p <- edit_plot(p, row = sig_rows, col = forest_pint,
                       gp = gpar(fontface = "bold", col = "#C0392B"))
      }
    }
  }
  fig_h <- max(10, nrow(plot_df) * 0.4 + 2)
  fig_name <- pub_figure_file(ctx, "main_figure", paste0(
    "Subgroup Forest analyses of ", index_var, " (continuous index)"
  ))
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  fig_path <- file.path(fig_dir, fig_name)
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
  ff <- plot_ff
  # 自适应画布（forestploter::get_wh）
  wh <- tryCatch({
    grDevices::pdf(NULL)
    on.exit(try(grDevices::dev.off(), silent = TRUE), add = TRUE)
    forestploter::get_wh(p, unit = "in")
  }, error = function(e) NULL)
  fig_w <- suppressWarnings(as.numeric(wh[["width"]] %||% 12)[1L])
  fig_h_auto <- suppressWarnings(as.numeric(wh[["height"]] %||% fig_h)[1L])
  if (!is.finite(fig_w) || fig_w < 4) fig_w <- 10
  if (is.finite(fig_h_auto) && fig_h_auto > 3) fig_h <- fig_h_auto
  fig_w <- min(14, max(5.5, fig_w + 0.2))
  fig_h <- min(36, max(4.0, fig_h + 0.2))
  tryCatch(
    {
      grDevices::cairo_pdf(fig_path, width = fig_w, height = fig_h, family = ff)
      on.exit(grDevices::dev.off(), add = TRUE)
      print(p)
      cli::cli_alert_success("Figure saved: {.file {fig_path}} ({round(fig_w,1)}×{round(fig_h,1)} in)")
    },
    error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("cairo_pdf failed ({e$message}); retrying with pdf()…")
      tryCatch(
        {
          grDevices::pdf(fig_path, width = fig_w, height = fig_h, family = ff)
          on.exit(grDevices::dev.off(), add = TRUE)
          print(p)
          cli::cli_alert_success("Figure saved: {.file {fig_path}}")
        },
        error = function(e2) {
          try(grDevices::dev.off(), silent = TRUE)
          cli::cli_alert_danger("Forest figure not saved: {e2$message}")
        }
      )
    }
  )

  # ── 导出亚组分析表格（默认关闭；export_table=TRUE 时导出）────────────────
  if (!isTRUE(sub_cfg$export_table %||% FALSE)) {
    cli::cli_alert_info("subgroup_prognosis_continuous: export_table=FALSE，跳过亚组数值表")
  } else {
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)

  tbl_export <- res
  # 将下划线替换为空格，与森林图标签保持一致
  if ("Variable" %in% names(tbl_export)) {
    tbl_export$Variable <- gsub("_", " ", as.character(tbl_export$Variable), fixed = TRUE)
  }
  # 格式化数值列（Point Estimate / Lower / Upper / P）
  fmt_tbl_num <- function(x) ifelse(is.na(suppressWarnings(as.numeric(x))), as.character(x),
                                    fmt_num(as.numeric(x)))
  for (cn in c("Point Estimate", "Lower", "Upper")) {
    if (cn %in% names(tbl_export)) {
      tbl_export[[cn]] <- fmt_tbl_num(tbl_export[[cn]])
    }
  }
  # P 值格式化
  for (cn in grep("^[Pp]", names(tbl_export), value = TRUE)) {
    pv <- suppressWarnings(as.numeric(tbl_export[[cn]]))
    tbl_export[[cn]] <- ifelse(is.na(pv), as.character(tbl_export[[cn]]),
                               ifelse(pv < 0.001, "<0.001",
                                      formatC(round(pv, 3), format = "f", digits = 3)))
  }
  # 添加 HR/OR (95% CI) 合并列（若原始结果包含置信区间列）
  if (all(c("Point Estimate", "Lower", "Upper") %in% names(tbl_export))) {
    tbl_export[[paste0(effect_sym, " (95% CI)")]] <- ifelse(
      is.na(suppressWarnings(as.numeric(res$`Point Estimate`))), "",
      sprintf("%s (%s\u2013%s)",
              fmt_num(as.numeric(res$`Point Estimate`)),
              fmt_num(as.numeric(res$Lower)),
              fmt_num(as.numeric(res$Upper)))
    )
  }

  tbl_pub <- pub_pair(
    ctx, tbl_dir, "main_table",
    title_caption = paste0(
      "Subgroup Analysis of ", index_var,
      " on ", cfg$project$disease %||% "Outcome",
      " (", effect_sym, " per unit, ", study_type, ", continuous index)"
    ),
    file_caption = paste0("Subgroup Analysis of ", index_var, " (continuous index)"),
    ext = "xlsx"
  )
  tryCatch(
    export_sci_table(tbl_export, tbl_pub$filepath, title = tbl_pub$title),
    error = function(e) cli::cli_alert_warning("亚组表格导出失败: {e$message}")
  )
  cli::cli_alert_success("Subgroup table saved: {.file {basename(tbl_pub$filepath)}}")
  } # end export_table

  ctx$results$subgroup <- res
  ctx$results$subgroup_vars_used <- final_subgroup_vars
  ctx$results$subgroup_study_type <- study_type
  ctx$results$subgroup_effect <- effect_sym
  ctx$results$subgroup_index_exposure <- "continuous"
  cli::cli_alert_success("Subgroup analysis completed ({study_type}, {effect_sym}, continuous index)")

  ctx
}
