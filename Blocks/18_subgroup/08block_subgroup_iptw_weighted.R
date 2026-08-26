###############################################################################
#  subgroup_iptw_weighted — MIMIC IPTW 加权发病亚组森林图（C01 svyglm + subgroup_incidence 格式）
#
#  register_block: "subgroup_iptw_weighted"
#  典型流水线: iptw_balance → logistic_*_iptw_weighted（可选）→ subgroup_iptw_weighted
#  依赖: 00logistic_iptw_weighted_common.R（pipeline 自动 source）
#
#  config: config$subgroup_iptw_weighted（min_n / var_source 等回退 config$subgroup）
#  读: ctx$results$iptw_design（须先 iptw_balance，含 Index_Group + weight）
#
#  统计（参照 C01_ForestPlot - nolevel-OR.R）:
#    各亚组层 svyglm(Disease_Group ~ exposure, quasibinomial)
#    全样本 svyglm(Disease_Group ~ exposure * sub_var) → P for interaction
#
#  出图/表（参照 02block_subgroup_incidence.R / 03block_subgroup_nhanes_weighted.R）:
#    forestploter 横排；Variable | Events | CI | P | P-interaction；export_sci_table
#
#  NHANES 路径跳过。
###############################################################################

.siw08_canonical_subgroup_order_vec <- function() {
  c(
    "Age_Group", "Gender", "BMI", "Education", "Marital_Status", "Income",
    "Smoking", "Alcohol_drinking", "Race", "Weight", "Height", "Language",
    "Micu_Code", "Insurance", "Ventilation", "Hypertension", "Diabetes",
    "T1DM", "T2DM", "Heart_Failure", "Myocardial_Infarction",
    "Atrial_Fibrillation", "Stroke", "COPD", "CKD", "Acute_Renal_Failure",
    "Liver_cirrhosis", "Hepatitis", "Cancer", "Hyperlipidemia", "Pneumonia",
    "Tuberculosis", "Dementia"
  )
}

.siw08_order_subgroup_vars <- function(v) {
  v <- unique(as.character(v[nzchar(v)]))
  canon <- .siw08_canonical_subgroup_order_vec()
  c(intersect(canon, v), sort(setdiff(v, canon)))
}

.siw08_pretty_label <- function(x) {
  x <- as.character(x %||% "")
  x <- gsub("_", " ", x, fixed = TRUE)
  x <- gsub("\\s+", " ", x)
  x <- gsub("([0-9]{2})\\s+([0-9]{2})", "\\1-\\2", x, perl = TRUE)
  trimws(x)
}

# 将结局列转为 0/1：
# - prognosis / 已是 0-1（或逻辑型）→ 直接用
# - incidence 病例对照 → 与 analysis_group 标签匹配
.siw08_outcome_to_binary <- function(out_raw, disease_lbl, study_type = "incidence") {
  if (is.logical(out_raw)) return(as.numeric(out_raw))
  if (is.numeric(out_raw) || is.integer(out_raw)) {
    u <- sort(unique(stats::na.omit(as.numeric(out_raw))))
    if (length(u) > 0L && length(u) <= 2L && all(u %in% c(0, 1))) {
      return(as.numeric(out_raw))
    }
  }
  # 字符/因子，或 prognosis 下的非标准编码：优先匹配 analysis_group
  lab <- as.character(disease_lbl %||% "1")[1L]
  as.numeric(as.character(out_raw) == lab)
}

.siw08_match_exposure_coef <- function(coef_mat, exp_col, high_level) {
  rn <- rownames(coef_mat)
  hit <- grep(paste0("^", exp_col), rn)
  hit <- hit[!grepl(":", rn[hit], fixed = TRUE)]
  if (!length(hit)) return(integer(0))
  by_level <- hit[grepl(high_level, rn[hit], fixed = TRUE)]
  if (length(by_level)) return(by_level[[length(by_level)]])
  if (length(hit) >= 2L) return(hit[[2L]])
  hit[[1L]]
}

.siw08_match_interaction_p <- function(coef_mat, exp_col, sub_var) {
  rn <- rownames(coef_mat)
  hit <- grep(":", rn, fixed = TRUE)
  if (!length(hit)) return(NA_real_)
  sub_hit <- hit[
    grepl(sub_var, rn[hit], fixed = TRUE) &
      grepl(exp_col, rn[hit], fixed = TRUE)
  ]
  if (length(sub_hit)) return(coef_mat[sub_hit[1L], 4])
  sub_hit <- hit[grepl(sub_var, rn[hit], fixed = TRUE)]
  if (length(sub_hit)) return(coef_mat[sub_hit[1L], 4])
  NA_real_
}

.siw08_ensure_age_bmi <- function(design, sub_cfg) {
  d <- design$variables
  upd <- list()
  age_cut <- sub_cfg$age_cutoff %||% 65
  age_col <- if ("Age" %in% names(d)) {
    "Age"
  } else if ("Age_Years" %in% names(d)) {
    "Age_Years"
  } else {
    NULL
  }
  if (!is.null(age_col) && !"Age_Group" %in% names(d)) {
    age_lo <- paste0("< ", age_cut)
    age_hi <- paste0("\u2265 ", age_cut)
    upd$Age_Group <- factor(
      ifelse(d[[age_col]] < age_cut, age_lo, age_hi),
      levels = c(age_lo, age_hi)
    )
    cli::cli_alert_info("IPTW subgroup Age_Group from {age_col} (cutoff {age_cut})")
  }
  if ("BMI" %in% names(d)) {
    bmi_num <- suppressWarnings(as.numeric(d$BMI))
    if (sum(is.finite(bmi_num)) > 0L && !is.factor(d$BMI)) {
      bmi_chr <- rep(NA_character_, length(bmi_num))
      bmi_chr[bmi_num < 25] <- "< 25"
      bmi_chr[bmi_num >= 25 & bmi_num < 30] <- "25-30"
      bmi_chr[bmi_num >= 30] <- "\u2265 30"
      upd$BMI <- factor(bmi_chr, levels = c("< 25", "25-30", "\u2265 30"))
      cli::cli_alert_info("IPTW subgroup BMI trichotomy applied")
    }
  }
  if (!length(upd)) return(design)
  do.call(stats::update, c(list(design), upd))
}

.siw08_one_subgroup <- function(sub_var, design, exp_col, high_level, min_n) {
  levs <- levels(factor(design$variables[[sub_var]]))
  sub_list <- lapply(levs, function(l) {
    sub_d <- tryCatch(
      subset(design, design$variables[[sub_var]] == l),
      error = function(e) NULL
    )
    if (is.null(sub_d) || nrow(sub_d$variables) < min_n) return(NULL)
    fit <- tryCatch(
      survey::svyglm(
        stats::as.formula(paste0("Disease_Group ~ ", exp_col)),
        design = sub_d,
        family = stats::quasibinomial()
      ),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)
    co <- summary(fit)$coefficients
    tgt <- .siw08_match_exposure_coef(co, exp_col, high_level)
    if (!length(tgt)) return(NULL)
    est <- co[tgt, "Estimate"]
    se <- co[tgt, "Std. Error"]
    pv <- co[tgt, 4]
    n_ev <- sum(sub_d$variables$Disease_Group == 1, na.rm = TRUE)
    n_tot <- nrow(sub_d$variables)
    data.frame(
      Subgroup = sub_var,
      Levels = l,
      Events = paste0(n_ev, "/", n_tot),
      OR = exp(est),
      Lower = exp(est - 1.96 * se),
      Upper = exp(est + 1.96 * se),
      P.value = pv,
      stringsAsFactors = FALSE
    )
  })
  res_df <- do.call(rbind, Filter(Negate(is.null), sub_list))
  if (is.null(res_df) || !nrow(res_df)) return(NULL)

  fit_i <- tryCatch(
    survey::svyglm(
      stats::as.formula(paste0("Disease_Group ~ ", exp_col, " * ", sub_var)),
      design = design,
      family = stats::quasibinomial()
    ),
    error = function(e) NULL
  )
  res_df$P.inter <- if (!is.null(fit_i)) {
    .siw08_match_interaction_p(summary(fit_i)$coefficients, exp_col, sub_var)
  } else {
    NA_real_
  }
  res_df
}

.siw08_build_forest_df <- function(dt_raw) {
  plot_rows <- list()
  for (sub in unique(dt_raw$Subgroup)) {
    body <- dt_raw[dt_raw$Subgroup == sub, , drop = FALSE]
    p_inter <- body$P.inter[1]
    hdr <- data.frame(
      Variable = .siw08_pretty_label(sub),
      Events = "",
      `Point Estimate` = NA_real_,
      Lower = NA_real_,
      Upper = NA_real_,
      Lower_plot = NA_real_,
      Upper_plot = NA_real_,
      `P value` = "",
      `P for interaction` = if (is.na(p_inter)) "" else {
        ifelse(p_inter < 0.001, "<0.001", sprintf("%.3f", p_inter))
      },
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    body_df <- data.frame(
      Variable = paste0("    ", .siw08_pretty_label(body$Levels)),
      Events = body$Events,
      `Point Estimate` = body$OR,
      Lower = body$Lower,
      Upper = body$Upper,
      Lower_plot = body$Lower_plot,
      Upper_plot = body$Upper_plot,
      `P value` = ifelse(body$P.value < 0.001, "<0.001", sprintf("%.3f", body$P.value)),
      `P for interaction` = "",
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
    plot_rows[[sub]] <- rbind(hdr, body_df)
  }
  do.call(rbind, plot_rows)
}

block_subgroup_iptw_weighted <- function(ctx, ...) {
  cfg <- ctx$config
  if (!.liw00_should_run(cfg, "subgroup_iptw_weighted")) {
    cli::cli_alert_info("subgroup_iptw_weighted: 已跳过（NHANES 或 enable=FALSE）。")
    return(ctx)
  }

  study_type <- tolower(trimws(cfg$project$study_type %||% ""))
  # incidence：经典发病 OR；prognosis：允许以二分类结局（如 28 天死亡）做加权亚组森林
  if (!study_type %in% c("incidence", "prognosis")) {
    cli::cli_alert_info("subgroup_iptw_weighted: study_type 非 incidence/prognosis，跳过。")
    return(ctx)
  }

  for (pkg in c("survey", "forestploter", "grid")) {
    if (!requireNamespace(pkg, quietly = TRUE)) {
      stop("subgroup_iptw_weighted: 需要 ", pkg, " 包。", call. = FALSE)
    }
  }
  suppressPackageStartupMessages({
    library(survey, warn.conflicts = FALSE)
    library(forestploter)
    library(grid)
  })

  bl_cfg <- cfg$subgroup_iptw_weighted %||% list()
  sub_cfg <- modifyList(cfg$subgroup %||% list(), bl_cfg)
  proj_cfg <- cfg$project %||% list()
  outcome_col <- cfg$data$outcome_column %||% "Disease_Group"
  disease_lbl <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"
  ref_grp <- proj_cfg$reference_group %||% "Control"
  index_var <- as.character(
    bl_cfg$index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||% ""
  )[1L]
  exp_col <- as.character(
    bl_cfg$exposure_var %||%
      (cfg$iptw_balance %||% list())$exposure_var %||% "Index_Group"
  )[1L]

  design <- .liw00_resolve_design(ctx, cfg)
  if (is.null(design)) {
    msg <- "ctx$results$iptw_design 为空（请先运行 iptw_balance）。"
    if (.liw00_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .liw00_pause(ctx, "subgroup_iptw_weighted", msg, "在 pipeline 中加入 iptw_balance。", NULL)
    }
    stop("subgroup_iptw_weighted: ", msg, call. = FALSE)
  }
  if (!exp_col %in% names(design$variables)) {
    stop(
      "subgroup_iptw_weighted: 暴露列 '", exp_col,
      "' 不在 iptw_design 中（请先 iptw_balance）。",
      call. = FALSE
    )
  }
  if (!outcome_col %in% names(design$variables)) {
    stop("subgroup_iptw_weighted: 结局列 '", outcome_col, "' 不在 iptw_design 中。", call. = FALSE)
  }

  # 结局 → Disease_Group(0/1)
  # prognosis 二分类（0/1 或 TRUE/FALSE）直接用；incidence 才按 analysis_group 标签匹配
  # 否则会出现 surv_event_28d 与疾病名字符串比较 → Events 全 0/N、OR≈1 的假结果
  out_raw <- design$variables[[outcome_col]]
  dg <- .siw08_outcome_to_binary(out_raw, disease_lbl, study_type)
  n_ev_all <- sum(dg == 1, na.rm = TRUE)
  n_tot_all <- sum(!is.na(dg))
  if (n_ev_all < 1L) {
    stop(
      "subgroup_iptw_weighted: 结局 '", outcome_col, "' 编码后事件数为 0（",
      n_ev_all, "/", n_tot_all, "）。",
      " prognosis 请保证 outcome 为 0/1；incidence 请设 project$analysis_group 与病例标签一致。",
      " 当前 analysis_group='", disease_lbl, "'。",
      call. = FALSE
    )
  }
  cli::cli_alert_info(
    "subgroup_iptw_weighted: 结局 {outcome_col} → Disease_Group 事件 {n_ev_all}/{n_tot_all}"
  )
  design <- stats::update(design, Disease_Group = dg)
  design <- .siw08_ensure_age_bmi(design, sub_cfg)

  exp_levs <- levels(factor(design$variables[[exp_col]]))
  if (length(exp_levs) != 2L) {
    stop(
      "subgroup_iptw_weighted: 暴露 '", exp_col, "' 须为 2 水平，当前 ",
      length(exp_levs), "。",
      call. = FALSE
    )
  }
  high_level <- tail(exp_levs, 1L)
  low_level <- exp_levs[1L]

  min_group_size <- subgroup_resolve_min_n(sub_cfg, nrow(design$variables))
  forbid_extra <- unique(c(
    exp_col, outcome_col, "Disease_Group", index_var,
    as.character(bl_cfg$extra_forbid_vars %||% character(0))
  ))
  if (!exists("subgroup_build_variable_pool", mode = "function")) {
    suppressWarnings(source(file.path(getwd(), "R", "subgroup_vars.R"), local = FALSE))
  }
  pool_built <- subgroup_build_variable_pool(
    ctx, design$variables, cfg, db_name = "mimic"
  )
  var_subgroups <- setdiff(pool_built$vars, forbid_extra)
  var_subgroups <- subgroup_vars_pass_min_n(
    design$variables, var_subgroups, min_group_size
  )
  var_subgroups <- .siw08_order_subgroup_vars(var_subgroups)
  if (!length(var_subgroups)) {
    cli::cli_alert_warning("subgroup_iptw_weighted: 无可用亚组变量，跳过。")
    return(ctx)
  }

  cli::cli_h2("subgroup_iptw_weighted: IPTW svyglm subgroup forest")
  cli::cli_alert_info("Exposure={exp_col} ({low_level} ref vs {high_level})")
  cli::cli_alert_info("Subgroup vars: {paste(var_subgroups, collapse = ', ')}")

  all_res <- list()
  for (v in var_subgroups) {
    cli::cli_alert_info("Analyzing subgroup: {v}")
    r <- tryCatch(
      .siw08_one_subgroup(v, design, exp_col, high_level, min_group_size),
      error = function(e) {
        cli::cli_alert_warning("subgroup '{v}' failed: {e$message}")
        NULL
      }
    )
    if (!is.null(r) && nrow(r) > 0L) all_res[[v]] <- r
  }
  if (!length(all_res)) {
    cli::cli_alert_warning("subgroup_iptw_weighted: 所有亚组均无有效结果，跳过。")
    return(ctx)
  }

  dt_raw <- do.call(rbind, all_res)
  finite_upper <- dt_raw$Upper[is.finite(dt_raw$Upper) & dt_raw$Upper > 0]
  fx <- sub_cfg$forest_xlim %||% c(0, 5)
  fx <- suppressWarnings(as.numeric(fx))
  if (length(fx) != 2L || any(!is.finite(fx)) || fx[2] <= fx[1]) {
    fx <- c(0, 5)
  }
  xlim_cap <- if (length(finite_upper)) {
    max(fx[2], min(max(ceiling(quantile(finite_upper, 0.95, na.rm = TRUE) * 1.3), 3), fx[2]))
  } else {
    fx[2]
  }
  dt_raw$Upper_plot <- pmin(dt_raw$Upper, xlim_cap)
  dt_raw$Lower_plot <- pmax(dt_raw$Lower, max(fx[1], 0.05))

  plot_df <- .siw08_build_forest_df(dt_raw)
  plot_df$` ` <- paste(rep(" ", 14), collapse = " ")
  ci_lab <- "OR (95% CI)"
  plot_df[[ci_lab]] <- ifelse(
    is.na(plot_df$`Point Estimate`), "",
    sprintf(
      "%.2f (%.2f to %.2f)",
      plot_df$`Point Estimate`, plot_df$Lower, plot_df$Upper
    )
  )

  plot_ff <- plot_font_from_config(cfg)
  tm <- forest_theme(
    base_size = 12,
    base_family = plot_ff,
    refline_gp = gpar(lty = "dashed", col = "black"),
    ci_pch = c(15),
    ci_col = "black",
    ci_alpha = 0.8,
    ci_lty = 1,
    ci_lwd = 1.5,
    ci_Theight = 0
  )

  ft <- sub_cfg$forest_ticks_at
  if (is.null(ft) || !length(ft)) {
    ft <- seq(fx[1], xlim_cap, length.out = 3L)
  } else {
    ft <- suppressWarnings(as.numeric(ft))
    ft <- ft[is.finite(ft)]
    if (!length(ft)) ft <- seq(fx[1], xlim_cap, length.out = 3L)
  }
  f_arrow <- sub_cfg$forest_arrow_length
  if (is.null(f_arrow) || !is.finite(suppressWarnings(as.numeric(f_arrow)))) {
    f_arrow <- xlim_cap
  } else {
    f_arrow <- as.numeric(f_arrow)
  }

  forest_cols <- c("Variable", "Events", " ", ci_lab, "P value", "P for interaction")
  ci_col_idx <- 3L
  arrow_lab <- c(
    paste0(.siw08_pretty_label(low_level), " (ref)"),
    paste0(.siw08_pretty_label(high_level), " vs ref")
  )
  if (!is.null(bl_cfg$forest_arrow_lab) && length(bl_cfg$forest_arrow_lab) == 2L) {
    arrow_lab <- as.character(bl_cfg$forest_arrow_lab)
  }

  fp_plot <- tryCatch(
    forest(
      plot_df[, forest_cols, drop = FALSE],
      est = list(plot_df$`Point Estimate`),
      lower = list(plot_df$Lower_plot),
      upper = list(plot_df$Upper_plot),
      ci_column = ci_col_idx,
      sizes = 0.6,
      ref_line = 1,
      arrow_lab = arrow_lab,
      xlim = c(fx[1], xlim_cap),
      ticks_at = ft,
      arrow_length = f_arrow,
      theme = tm
    ),
    error = function(e) {
      cli::cli_alert_warning("IPTW 亚组森林图构建失败: {e$message}")
      NULL
    }
  )

  var_labels_bold <- .siw08_pretty_label(var_subgroups)
  if (!is.null(fp_plot)) {
    hdr_rows <- which(trimws(as.character(plot_df$Variable)) %in% var_labels_bold)
    if (length(hdr_rows)) {
      fp_plot <- edit_plot(fp_plot, row = hdr_rows, gp = gpar(fontface = "bold"))
    }
  }

  fig_h <- max(10, nrow(plot_df) * 0.4 + 2)
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
  fig_caption <- paste0(
    "Subgroup analysis of ", gsub("_", " ", index_var, fixed = TRUE),
    " and ", gsub("_", " ", proj_cfg$disease %||% "outcome", fixed = TRUE),
    " (IPTW-adjusted)"
  )
  fig_name <- if (!is.null(bl_cfg$figure_filename) && nzchar(bl_cfg$figure_filename)) {
    bl_cfg$figure_filename
  } else {
    pub_figure_file(ctx, "main_figure", fig_caption)
  }
  fig_path <- file.path(fig_dir, fig_name)
  if (exists(".pub_figure_filename", mode = "function")) {
    fig_path <- file.path(fig_dir, .pub_figure_filename(
      .inject_db_into_pub_label(fig_name, sanitize_for_file = TRUE)
    ))
  }

  if (!is.null(fp_plot)) {
    wh <- tryCatch({
      grDevices::pdf(NULL)
      on.exit(try(grDevices::dev.off(), silent = TRUE), add = TRUE)
      forestploter::get_wh(fp_plot, unit = "in")
    }, error = function(e) NULL)
    fig_w <- suppressWarnings(as.numeric(wh[["width"]] %||% 12)[1L])
    fig_h_auto <- suppressWarnings(as.numeric(wh[["height"]] %||% fig_h)[1L])
    if (!is.finite(fig_w) || fig_w < 4) fig_w <- 10
    if (is.finite(fig_h_auto) && fig_h_auto > 3) fig_h <- fig_h_auto
    fig_w <- min(14, max(5.5, fig_w + 0.2))
    fig_h <- min(36, max(4.0, fig_h + 0.2))
    tryCatch({
      grDevices::cairo_pdf(fig_path, width = fig_w, height = fig_h, family = plot_ff)
      on.exit(grDevices::dev.off(), add = TRUE)
      print(fp_plot)
      cli::cli_alert_success(
        "IPTW 亚组森林图保存: {.file {basename(fig_path)}} ({round(fig_w,1)}×{round(fig_h,1)} in)"
      )
      mirror_pub_output_to_root(ctx, fig_path)
      ctx$results$subgroup_iptw_figure <- fig_path
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("IPTW 亚组图保存失败: {e$message}")
    })
  }

  tbl_export <- plot_df[, c(
    "Variable", "Events", "Point Estimate", "Lower", "Upper",
    "P value", "P for interaction"
  ), drop = FALSE]
  names(tbl_export)[names(tbl_export) == "Point Estimate"] <- "OR"
  if (all(c("OR", "Lower", "Upper") %in% names(tbl_export))) {
    tbl_export[["OR (95% CI)"]] <- ifelse(
      is.na(suppressWarnings(as.numeric(tbl_export$OR))), "",
      sprintf(
        "%s (%s\u2013%s)",
        fmt_num(as.numeric(tbl_export$OR)),
        fmt_num(as.numeric(tbl_export$Lower)),
        fmt_num(as.numeric(tbl_export$Upper))
      )
    )
  }

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  tbl_pub <- pub_pair(
    ctx, tbl_dir, "main_table",
    title_caption = paste0(
      "IPTW Subgroup Analysis of ", index_var,
      " on ", proj_cfg$disease %||% "Outcome", " (OR, incidence)"
    ),
    file_caption = paste0("IPTW Subgroup Analysis of ", index_var),
    ext = "xlsx"
  )
  tryCatch(
    export_sci_table(tbl_export, tbl_pub$filepath, title = tbl_pub$title),
    error = function(e) cli::cli_alert_warning("IPTW 亚组表格导出失败: {e$message}")
  )

  ctx$results$subgroup_iptw <- dt_raw
  ctx$results$subgroup_iptw_table <- tbl_export
  ctx$results$subgroup_iptw_vars_used <- var_subgroups
  ctx$results$subgroup_iptw_exposure <- exp_col
  ctx$results$subgroup_iptw_exposure_levels <- exp_levs
  ctx$results$subgroup_iptw_study_type <- "incidence"
  ctx$results$subgroup_iptw_effect <- "OR"
  ctx$results$subgroup_vars_used <- var_subgroups

  cli::cli_alert_success(
    "subgroup_iptw_weighted 完成（{nrow(dt_raw)} 行 OR，{length(var_subgroups)} 个亚组变量）。"
  )
  ctx
}

register_block(
  "subgroup_iptw_weighted",
  block_subgroup_iptw_weighted,
  "MIMIC IPTW 亚组森林图：C01 svyglm OR + subgroup_incidence forestploter 格式"
)
