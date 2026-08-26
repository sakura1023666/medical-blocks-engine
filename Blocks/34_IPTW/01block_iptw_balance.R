###############################################################################
#  iptw_balance — IPTW 加权 + 暴露组间协变量平衡（IPTW 前后宽表）
#
#  register_block: "iptw_balance"
#  典型流水线 (MIMIC): imputation → simple_ROC → … → dual_db_covariate_harmonize
#                      → iptw_balance → iptw_association
#
#  config: config$iptw_balance（ps_covariates、smd_threshold、pause；不含 data_source）
#  读: ctx$data$imputed %||% ctx$data$cleaned（须含或可生成 Index_Group）
#  写: ctx$data$iptw_weighted, ctx$results$iptw_design, iptw_high_smd_vars, iptw_balance_table
#
#  产出:
#    - [main_table] Table 1.*  Jin 同构：Overall / 两组 N(%) / P / SMD未加权 / SMD加权
#      （table_style="jin"，默认）；table_style="wide" 时仍为 before|after 宽表 → supp_table
#    - [supp_figure] Figure S2：PS 分布 + SMD Love（对齐 Jin Fig.S1；项目 S1 为缺失热图）

#    - [固定名]     D01_After_IPTW.RData            → 不占发表序号
#
#  NHANES 加权路径跳过（已有 survey 权重，不走 ipwpoint）。
#  pause: config$iptw_balance$pause_enable
###############################################################################

.ib01_is_nhanes_db <- function(cfg) {
  dt <- tolower(trimws(as.character(cfg$project$database_type %||% "")))
  db <- tolower(trimws(as.character(cfg$project$database %||% "")))
  grepl("nhanes|nhance", dt) || grepl("nhanes|nhance", db)
}

.ib01_should_run <- function(cfg) {
  ib_cfg <- cfg$iptw_balance %||% list()
  if (isFALSE(ib_cfg$enable %||% TRUE)) return(FALSE)
  !.ib01_is_nhanes_db(cfg)
}

.ib01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block         = "iptw_balance",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: IPTW balance anomaly. See ctx$results$pause_point. / ",
    "IPTW 平衡表异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.ib01_resolve_index_var <- function(cfg) {
  ib_cfg <- cfg$iptw_balance %||% list()
  inc_cfg <- cfg$incidence %||% list()
  log_cfg <- cfg$logistic %||% list()
  as.character(
    ib_cfg$index_var %||% inc_cfg$index_var %||% log_cfg$index_var %||% ""
  )[1L]
}

.ib01_resolve_cutoff <- function(ctx, cfg, index_var) {
  ib_cfg <- cfg$iptw_balance %||% list()
  cv <- ib_cfg$cutoff_value %||% NULL
  if (!is.null(cv) && is.finite(as.numeric(cv))) return(as.numeric(cv)[1L])
  cv <- ctx$results$roc_cutoff %||% ctx$results$cutoff_value %||% ctx$results$nhanes_cutoff
  if (!is.null(cv) && is.finite(as.numeric(cv))) return(as.numeric(cv)[1L])
  if (index_var %in% names(ctx$data$imputed %||% list()) ||
      index_var %in% names(ctx$data$cleaned %||% list())) {
    return(NULL)
  }
  NULL
}

.ib01_ensure_index_group <- function(data, cfg, ctx) {
  ib_cfg <- cfg$iptw_balance %||% list()
  exp_var <- as.character(ib_cfg$exposure_var %||% "Index_Group")[1L]
  if (exp_var %in% names(data)) {
    data[[exp_var]] <- factor(data[[exp_var]])
    return(list(data = data, exposure_var = exp_var))
  }

  index_var <- .ib01_resolve_index_var(cfg)
  if (!nzchar(index_var)) {
    stop(
      "iptw_balance: 缺少 Index_Group 且未配置 index_var；",
      "请先运行 simple_ROC/cutoff 或设置 config$iptw_balance$index_var。",
      call. = FALSE
    )
  }
  if (!index_var %in% names(data)) {
    stop("iptw_balance: 暴露列 '", index_var, "' 不在数据中。", call. = FALSE)
  }

  cutoff_val <- .ib01_resolve_cutoff(ctx, cfg, index_var)
  if (is.null(cutoff_val)) {
    stop(
      "iptw_balance: 无法确定 ROC cutoff，无法生成 Index_Group；",
      "请先运行 simple_ROC 或设置 config$iptw_balance$cutoff_value。",
      call. = FALSE
    )
  }

  proj <- cfg$project %||% list()
  lbl_lo <- ib_cfg$group_label_low %||% paste0("<", round(cutoff_val, 4))
  lbl_hi <- ib_cfg$group_label_high %||% paste0(">=", round(cutoff_val, 4))
  data[[exp_var]] <- factor(
    ifelse(as.numeric(data[[index_var]]) < cutoff_val, lbl_lo, lbl_hi),
    levels = c(lbl_lo, lbl_hi)
  )
  cli::cli_alert_info(
    "iptw_balance: 已用 cutoff={round(cutoff_val, 4)} 生成 {exp_var}"
  )
  list(data = data, exposure_var = exp_var)
}

.ib01_resolve_balance_vars <- function(data, cfg) {
  ib_cfg <- cfg$iptw_balance %||% list()
  exp_var <- as.character(ib_cfg$exposure_var %||% "Index_Group")[1L]
  out_col <- cfg$data$outcome_column %||% "Disease_Group"
  id_col <- cfg$data$id_column %||% NULL
  idx_excl <- pipeline_index_exclude_vars(cfg)
  extra_excl <- as.character(ib_cfg$exclude_vars %||% character(0))
  never <- character(0)
  if (exists("pipeline_never_predictor_names", mode = "function")) {
    never <- pipeline_never_predictor_names(cfg)
  }
  std_excl <- unique(c(
    id_col, "subject_id", "SEQN", "ID", "patient_id", "hadm_id",
    out_col, exp_var, "Index_Group_Tertile", "Index_Group_Quartile",
    "lgb_pred", "weight", idx_excl, extra_excl, never,
    # 结局/暴露泄漏 + 非语法列名（tableone/survey 公式会炸）
    "Diabetes_HbA1c", "HbA1c", "T1DM", "T2DM", "Diabetes",
    "surv_time_28d", "surv_event_28d", "hosp_survival_day", "hosp_day",
    "death_within_hosp_28days", "is_hosp_dead", "in-hospital mortality"
  ))
  std_excl <- std_excl[nzchar(std_excl)]
  vars <- setdiff(names(data), std_excl)
  # 再滤：含空格/连字符的非语法名、明显结局泄漏
  vars <- vars[!grepl(" |/", vars)]
  vars <- vars[!grepl("mortality|surv_(time|event)|survival_day", vars, ignore.case = TRUE)]
  inc <- ib_cfg$include_vars %||% NULL
  if (!is.null(inc) && length(inc)) {
    inc <- as.character(inc)
    vars <- inc[inc %in% vars]
  }
  if (!length(vars)) {
    stop("iptw_balance: 平衡表变量池为空，请检查 exclude_vars / include_vars。", call. = FALSE)
  }
  vars
}

.ib01_resolve_ps_covariates <- function(data, cfg, ctx = NULL) {
  ib_cfg <- cfg$iptw_balance %||% list()
  ps <- ib_cfg$ps_covariates %||% NULL
  from_fs <- identical(ps, "from_feature_selection") ||
    isTRUE(ib_cfg$use_selected_covariates %||% FALSE)
  from_m2 <- identical(ps, "from_model2") || identical(ps, "from_vif") ||
    isTRUE(ib_cfg$use_model2_covariates %||% FALSE)

  if (from_fs || from_m2) {
    ps <- NULL
  }
  if (is.null(ps) || !length(ps)) {
    for (key in c(
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
      "multivariate_incidence_binary"
    )) {
      blk <- cfg[[key]] %||% NULL
      if (!is.null(blk)) {
        ps <- c(
          as.character(blk$model2_factors %||% character(0)),
          as.character(blk$model1_factors %||% character(0))
        )
        ps <- ps[nzchar(ps)]
        if (length(ps)) break
      }
    }
  }

  idx_cur <- as.character(
    (cfg$analysis_exclusion %||% list())$index_var %||%
      cfg$active_unit %||%
      (cfg$incidence %||% list())$index_var %||%
      character(0)
  )[1L]
  if (!nzchar(idx_cur %||% "")) idx_cur <- character(0)

  # 单因素 → VIF 后 Model2Factors（± Model1）；仅当当前指标列真实存在时并入
  if (!is.null(ctx) && isTRUE(from_m2)) {
    m2 <- as.character(ctx$results$Model2Factors %||% character(0))
    m1 <- as.character(ctx$results$Model1Factors %||% character(0))
    idx_add <- if (length(idx_cur) && nzchar(idx_cur) && idx_cur %in% names(data) &&
                     !idx_cur %in% c("(none)", "main")) idx_cur else character(0)
    ps <- unique(c(m1, m2, idx_add))
    ps <- ps[nzchar(ps)]
    if (!length(ps)) {
      stop(
        "iptw_balance: ps_covariates='from_model2' 但 Model1/Model2Factors 为空；",
        "请先运行 univariate_prognosis → multicollinearity_screen。",
        call. = FALSE
      )
    }
    if (length(idx_add)) {
      cli::cli_alert_info(
        "iptw_balance: PS 协变量来自 VIF 后 Model2（n={length(setdiff(ps, idx_add))}）+ 当前指标 {idx_add}"
      )
    } else {
      cli::cli_alert_info(
        "iptw_balance: PS 协变量来自 VIF 后 Model2（n={length(ps)}；未并入复合指标）"
      )
    }
  }

  # 可选：合并特征选择入选变量 + 当前复合指标（糖尿病 IPW batch 旧路径）
  if (!is.null(ctx) && isTRUE(from_fs)) {
    by_m <- ctx$results$feature_selection_by_model %||% list()
    sel <- unique(c(
      as.character(by_m$random_forest %||% character(0)),
      as.character(by_m$lasso %||% character(0)),
      as.character(ctx$results$feature_selection_final %||% character(0))
    ))
    base_demo <- c(
      "Age", "Gender", "Race", "Language", "Marital_Status",
      "Hypertension", "COPD", "RDW", "Potassium", "SOFA", "GCS",
      "APSIII", "SAPSII", "OASIS", "SIRS"
    )
    ps <- unique(c(as.character(ps %||% character(0)), sel, idx_cur, base_demo))
    ps <- ps[nzchar(ps)]
  }
  if (is.null(ps) || !length(ps)) {
    ps <- c(
      "Age", "Gender", "Race", "Language", "Marital_Status",
      "Hypertension", "T2DM", "COPD", "RDW", "Potassium", "PLT"
    )
  }
  ps <- unique(as.character(ps))
  # 排除暴露、结局与 never-predictor
  exp_var <- as.character(ib_cfg$exposure_var %||% "Index_Group")[1L]
  never <- character(0)
  if (exists("pipeline_never_predictor_names", mode = "function")) {
    never <- pipeline_never_predictor_names(cfg)
  }
  leak <- c(
    exp_var, "Diabetes_HbA1c", "HbA1c", "T1DM", "T2DM", "Diabetes",
    "surv_time_28d", "surv_event_28d", "hosp_survival_day", "hosp_day",
    "death_within_hosp_28days", "is_hosp_dead", "in-hospital mortality",
    "weight", never
  )
  ps <- setdiff(ps, unique(leak[nzchar(leak)]))
  # 结局泄漏列名变体（含空格/连字符）再滤一层
  ps <- ps[!grepl("mortality|survival_day|surv_(time|event)", ps, ignore.case = TRUE)]
  ps <- ps[ps %in% names(data)]
  if (length(ps) < 1L) {
    stop(
      "iptw_balance: 倾向得分分母协变量在数据中均不存在；",
      "请设置 config$iptw_balance$ps_covariates。",
      call. = FALSE
    )
  }
  ps
}

.ib01_format_tableone_side <- function(tab_matrix, index_var, g1_lab, g2_lab,
                                       n_one, n_two) {
  tab_df <- as.data.frame(tab_matrix)
  for (i in seq_len(min(2L, ncol(tab_df)))) {
    tab_df[, i] <- ifelse(
      grepl("\\(.*\\)", tab_df[, i]) & !grepl("mean", rownames(tab_df)),
      gsub("\\(([[0-9].]+)\\)", "(\\1%)", tab_df[, i]),
      tab_df[, i]
    )
  }
  tab_df <- tab_df[-1, , drop = FALSE]
  tab_df <- cbind(Variable = rownames(tab_df), tab_df)
  if ("level" %in% names(tab_df)) names(tab_df)[names(tab_df) == "level"] <- "Level"
  # 空列名会导致后续 export/prepare_df 中 df[[""]] <- character(0) 崩溃
  empty_nm <- !nzchar(trimws(names(tab_df)))
  if (any(empty_nm)) {
    names(tab_df)[empty_nm] <- paste0("Level", seq_len(sum(empty_nm)))
  }
  if ("p" %in% names(tab_df)) names(tab_df)[names(tab_df) == "p"] <- "P-value"
  tab_df <- tab_df[, !colnames(tab_df) %in% c("test"), drop = FALSE]

  if (g1_lab %in% colnames(tab_df)) {
    colnames(tab_df)[colnames(tab_df) == g1_lab] <- paste0(
      index_var, " ", g1_lab, " (N=", n_one, ")"
    )
  }
  if (g2_lab %in% colnames(tab_df)) {
    colnames(tab_df)[colnames(tab_df) == g2_lab] <- paste0(
      index_var, " ", g2_lab, " (N=", n_two, ")"
    )
  }

  tab_df$Variable <- gsub("X\\.\\d+$", "", tab_df$Variable)
  tab_df$Variable <- gsub("X", "", tab_df$Variable)
  tab_df$Variable <- gsub("\\.\\.mean\\.\\.SD\\.\\.", ",mean[SD]", tab_df$Variable)
  tab_df$Variable <- gsub("\\.\\.\\.\\.", ",n[%]", tab_df$Variable)
  tab_df$Variable <- gsub("_", " ", tab_df$Variable, fixed = TRUE)
  tab_df <- rbind(Variable = colnames(tab_df), tab_df)
  tab_df
}

.ib01_extract_high_smd_vars <- function(tab_df, threshold) {
  if (is.null(tab_df) || !"SMD" %in% names(tab_df)) return(character(0))
  smd_num <- suppressWarnings(as.numeric(gsub("<", "", as.character(tab_df$SMD))))
  vars <- rownames(tab_df)[which(!is.na(smd_num) & smd_num > threshold)]
  vars <- gsub("\\.\\.mean\\.\\.SD\\.\\.", "", vars)
  vars <- gsub("\\.{2,}", "", vars)
  vars <- vars[nzchar(vars) & !vars %in% c("n", "Variable")]
  unique(vars)
}

.ib01_build_wide_table <- function(tab_before, tab_after, before_lab, after_lab) {
  n_before <- ncol(tab_before)
  n_after <- ncol(tab_after)
  hdr_before <- rep("", n_before)
  hdr_before[min(4L, n_before)] <- before_lab
  tab_before <- rbind(hdr_before, tab_before)
  hdr_after <- rep("", n_after)
  hdr_after[min(2L, n_after)] <- after_lab
  tab_after <- rbind(hdr_after, tab_after)
  names(tab_before) <- make.unique(as.character(names(tab_before)), sep = "_")
  names(tab_after) <- make.unique(
    paste0(as.character(names(tab_after)), "_after"),
    sep = "_"
  )
  tab <- cbind(tab_before, tab_after)
  rownames(tab) <- NULL
  names(tab) <- make.unique(as.character(names(tab)), sep = "_")
  empty_nm <- !nzchar(trimws(names(tab)))
  if (any(empty_nm)) names(tab)[empty_nm] <- paste0("col", which(empty_nm))
  as.data.frame(tab, stringsAsFactors = FALSE)
}

.ib01_build_jin_style_table1 <- function(tab_uw, tab_wt, g1_lab, g2_lab,
                                         overall_lab = "Overall",
                                         smd_uw_lab = "SMD Unweighted",
                                         smd_wt_lab = "SMD Weighted") {
  # Jin 同构：Characteristic | Overall | G1 | G2 | P | SMD Unweighted | SMD Weighted
  as_df <- function(m) {
    d <- as.data.frame(m, stringsAsFactors = FALSE)
    d$.row <- rownames(m)
    d
  }
  uw <- as_df(tab_uw)
  wt <- as_df(tab_wt)
  nm <- names(uw)
  smd_col <- nm[tolower(nm) %in% c("smd", "std.diff")][1L]
  p_col <- nm[tolower(nm) %in% c("p", "p-value", "pvalue")][1L]
  lvl_col <- nm[tolower(nm) %in% c("level")][1L]
  ov_col <- nm[tolower(nm) == "overall"][1L]
  g1_col <- if (g1_lab %in% nm) g1_lab else NA_character_
  g2_col <- if (g2_lab %in% nm) g2_lab else NA_character_

  wt_smd_col <- names(wt)[tolower(names(wt)) %in% c("smd", "std.diff")][1L]
  wt_smd <- if (!is.na(wt_smd_col) && length(wt_smd_col)) {
    setNames(as.character(wt[[wt_smd_col]]), wt$.row)
  } else {
    character(0)
  }

  out <- data.frame(
    Characteristic = uw$.row,
    Level = if (!is.na(lvl_col)) as.character(uw[[lvl_col]]) else "",
    Overall = if (!is.na(ov_col)) as.character(uw[[ov_col]]) else "",
    Group1 = if (!is.na(g1_col)) as.character(uw[[g1_col]]) else "",
    Group2 = if (!is.na(g2_col)) as.character(uw[[g2_col]]) else "",
    P = if (!is.na(p_col)) as.character(uw[[p_col]]) else "",
    SMD_Unweighted = if (!is.na(smd_col)) as.character(uw[[smd_col]]) else "",
    SMD_Weighted = unname(wt_smd[uw$.row]),
    stringsAsFactors = FALSE
  )
  out$SMD_Weighted[is.na(out$SMD_Weighted)] <- ""
  for (col in c("Overall", "Group1", "Group2")) {
    out[[col]] <- ifelse(
      grepl("\\(.*\\)", out[[col]]) & !grepl("mean", out[[col]], ignore.case = TRUE),
      gsub("\\(([[0-9].]+)\\)", "(\\1%)", out[[col]]),
      out[[col]]
    )
  }
  names(out) <- c(
    "Characteristic", "Level", overall_lab, g1_lab, g2_lab, "P",
    smd_uw_lab, smd_wt_lab
  )
  out
}

.ib01_relabel_exposure_for_table <- function(data, exp_var, ib_cfg) {
  labs <- ib_cfg$exposure_level_labels %||% ib_cfg$strata_level_labels %||% NULL
  if (is.null(labs) || !length(labs) || !exp_var %in% names(data)) {
    return(list(data = data, g1 = NULL, g2 = NULL))
  }
  x <- as.character(data[[exp_var]])
  for (nm in names(labs)) {
    x[x == as.character(nm)] <- as.character(labs[[nm]])[1L]
  }
  lev <- unique(as.character(unlist(labs, use.names = FALSE)))
  data[[exp_var]] <- factor(x, levels = lev)
  list(data = data, g1 = lev[1L], g2 = lev[2L])
}



.ib01_extract_smd_vector <- function(tab_matrix) {
  if (is.null(tab_matrix) || !nrow(tab_matrix)) return(NULL)
  smd_col <- which(tolower(colnames(tab_matrix)) %in% c("smd", "std.diff"))
  if (!length(smd_col)) return(NULL)
  smd_col <- smd_col[1L]
  rn <- rownames(tab_matrix)
  vals <- suppressWarnings(as.numeric(gsub("<", "", as.character(tab_matrix[, smd_col]))))
  keep <- !is.na(rn) & nzchar(rn) & !tolower(rn) %in% c("n", "smiles") & !is.na(vals)
  if (!any(keep)) return(NULL)
  data.frame(variable = rn[keep], smd = vals[keep], stringsAsFactors = FALSE)
}

.ib01_draw_love_plot <- function(
    smd_before,
    smd_after,
    thr = 0.1,
    title = NULL,
    style = c("jin", "classic")
) {
  if (is.null(smd_before) || is.null(smd_after)) return(NULL)
  style <- match.arg(style)
  df <- merge(smd_before, smd_after, by = "variable", suffixes = c("_before", "_after"), all = TRUE)
  df$smd_before[is.na(df$smd_before)] <- 0
  df$smd_after[is.na(df$smd_after)] <- 0
  df$variable <- gsub("\\.\\.mean\\.\\.SD\\.\\.|\\.{2,}", "", df$variable)
  df$variable <- gsub("_", " ", df$variable, fixed = TRUE)
  # 按未加权 |SMD| 降序（高失衡在上，贴近 Jin Love）
  df <- df[order(abs(df$smd_before), decreasing = TRUE), , drop = FALSE]
  df$variable <- factor(df$variable, levels = rev(unique(df$variable)))
  long <- rbind(
    data.frame(
      variable = df$variable,
      smd = abs(df$smd_before),
      stage = if (identical(style, "jin")) "Unweighted" else "Before IPTW",
      stringsAsFactors = FALSE
    ),
    data.frame(
      variable = df$variable,
      smd = abs(df$smd_after),
      stage = if (identical(style, "jin")) "Weighted" else "After IPTW",
      stringsAsFactors = FALSE
    )
  )
  if (identical(style, "jin")) {
    long$stage <- factor(long$stage, levels = c("Unweighted", "Weighted"))
    long <- long[order(long$stage, as.integer(long$variable)), , drop = FALSE]
    xmax <- max(0.4, max(long$smd, na.rm = TRUE) * 1.05, thr * 1.2)
    # 图例必须可辨：未加权=虚线+空心黄点；加权=实线+实心蓝点
    ggplot2::ggplot(long, ggplot2::aes(x = smd, y = variable, group = stage)) +
      ggplot2::geom_vline(xintercept = 0, color = "#C0392B", linewidth = 0.5) +
      ggplot2::geom_vline(xintercept = thr, color = "#C0392B", linewidth = 0.5) +
      ggplot2::geom_path(
        ggplot2::aes(linetype = stage, color = stage),
        linewidth = 0.7
      ) +
      ggplot2::geom_point(
        ggplot2::aes(shape = stage, fill = stage, color = stage),
        size = 2.6,
        stroke = 0.7
      ) +
      ggplot2::scale_color_manual(
        name = "Method",
        values = c(Unweighted = "#2C5F8A", Weighted = "#1A5276")
      ) +
      ggplot2::scale_fill_manual(
        name = "Method",
        values = c(Unweighted = "#F4C95F", Weighted = "#1A5276")
      ) +
      ggplot2::scale_linetype_manual(
        name = "Method",
        values = c(Unweighted = "dashed", Weighted = "solid")
      ) +
      ggplot2::scale_shape_manual(
        name = "Method",
        values = c(Unweighted = 21, Weighted = 16)
      ) +
      ggplot2::scale_x_continuous(limits = c(0, xmax), expand = ggplot2::expansion(mult = c(0, 0.02))) +
      ggplot2::labs(
        title = title,
        x = "Standardized Mean Difference",
        y = NULL
      ) +
      ggplot2::guides(
        color = ggplot2::guide_legend(
          override.aes = list(
            linetype = c("dashed", "solid"),
            shape = c(21, 16),
            fill = c("#F4C95F", "#1A5276"),
            size = 3
          )
        ),
        fill = "none",
        linetype = "none",
        shape = "none"
      ) +
      ggplot2::theme_classic(base_size = 11) +
      ggplot2::theme(
        legend.position = "right",
        legend.title = ggplot2::element_text(face = "bold"),
        plot.title = ggplot2::element_text(face = "bold", hjust = 0)
      )
  } else {
    ggplot2::ggplot(long, ggplot2::aes(x = smd, y = variable, color = stage, shape = stage)) +
      ggplot2::geom_vline(xintercept = thr, linetype = "dashed", color = "grey40") +
      ggplot2::geom_point(size = 2.2) +
      ggplot2::scale_color_manual(values = c("Before IPTW" = "#A0353B", "After IPTW" = "#4E79A7")) +
      ggplot2::labs(
        title = title,
        x = "|Standardized Mean Difference|",
        y = NULL,
        color = NULL,
        shape = NULL
      ) +
      ggplot2::theme_classic(base_size = 11) +
      ggplot2::theme(
        legend.position = "bottom",
        plot.title = ggplot2::element_text(face = "bold", hjust = 0.5)
      )
  }
}

# Jin Fig.S1 Panel A：倾向评分分布（重叠直方图）
.ib01_draw_ps_hist <- function(ps, group, group_labels = NULL, legend_title = "Exposure", title = "A") {
  g <- as.character(group)
  if (!is.null(group_labels) && length(group_labels)) {
    map <- as.character(group_labels)
    names(map) <- names(group_labels)
    g <- ifelse(g %in% names(map), map[g], g)
  }
  d <- data.frame(ps = as.numeric(ps), group = factor(g), stringsAsFactors = FALSE)
  d <- d[is.finite(d$ps), , drop = FALSE]
  fill_vals <- c("#4A306D", "#D9D9D9")
  if (nlevels(d$group) >= 2L) {
    names(fill_vals) <- levels(d$group)[seq_len(min(2L, nlevels(d$group)))]
  }
  ggplot2::ggplot(d, ggplot2::aes(x = .data$ps, fill = .data$group)) +
    ggplot2::geom_histogram(
      position = "identity",
      alpha = 0.72,
      bins = 30,
      color = "grey20",
      linewidth = 0.2
    ) +
    ggplot2::scale_fill_manual(values = fill_vals, drop = FALSE) +
    ggplot2::labs(
      title = title,
      x = "Propensity score",
      y = "Count",
      fill = legend_title
    ) +
    ggplot2::theme_classic(base_size = 11) +
    ggplot2::theme(
      legend.position = "right",
      plot.title = ggplot2::element_text(face = "bold", hjust = 0)
    )
}

.ib01_default_footnotes <- function() {
  c(
    "Mean (sd) or Frequency (%)",
    "Wilcoxon rank sum test; Pearson's Chi-squared test",
    "Continuous variables are presented as the mean and 95% confidence interval",
    "Category variables are described as the percentage and 95% confidence interval."
  )
}

block_iptw_balance <- function(ctx, ...) {
  cfg <- ctx$config
  if (!.ib01_should_run(cfg)) {
    cli::cli_alert_info("iptw_balance: 已跳过（NHANES 或 enable=FALSE）。")
    return(ctx)
  }

  ib_cfg <- cfg$iptw_balance %||% list()
  suppressPackageStartupMessages({
    if (!requireNamespace("tableone", quietly = TRUE)) {
      stop("iptw_balance: 需要 tableone 包。", call. = FALSE)
    }
    if (!requireNamespace("survey", quietly = TRUE)) {
      stop("iptw_balance: 需要 survey 包。", call. = FALSE)
    }
    if (!requireNamespace("ipw", quietly = TRUE)) {
      stop("iptw_balance: 需要 ipw 包（install.packages('ipw')）。", call. = FALSE)
    }
    if (!requireNamespace("ggplot2", quietly = TRUE)) {
      stop("iptw_balance: 需要 ggplot2 包（Love plot）。", call. = FALSE)
    }
    library(tableone, warn.conflicts = FALSE)
    library(survey, warn.conflicts = FALSE)
  })

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (isTRUE(ib_cfg$pause_enable %||% TRUE)) {
      .ib01_pause(
        ctx,
        "未找到分析数据（ctx$data$imputed 与 cleaned 均为空）。",
        "请先运行 imputation 或 data_clean。",
        NULL
      )
    }
    stop("iptw_balance: 无分析数据。", call. = FALSE)
  }
  data <- as.data.frame(data)

  idx_info <- .ib01_ensure_index_group(data, cfg, ctx)
  data <- idx_info$data
  exp_var <- idx_info$exposure_var
  index_var <- .ib01_resolve_index_var(cfg)
  if (!nzchar(index_var)) index_var <- exp_var

  # 数据列保持 0/1（供下游 KM/Cox）；Table 1 表头用展示标签
  exp_levs <- levels(factor(data[[exp_var]]))
  if (length(exp_levs) != 2L) {
    # 尝试规范为 0/1
    if (is.numeric(data[[exp_var]]) || all(unique(stats::na.omit(data[[exp_var]])) %in% c(0, 1, "0", "1"))) {
      data[[exp_var]] <- factor(as.character(as.integer(as.numeric(as.character(data[[exp_var]])))), levels = c("0", "1"))
      exp_levs <- c("0", "1")
    }
  }
  if (length(exp_levs) != 2L) {
    msg <- paste0("iptw_balance: 暴露列 '", exp_var, "' 须恰好 2 个水平，当前为 ", length(exp_levs), "。")
    if (isTRUE(ib_cfg$pause_enable %||% TRUE)) {
      .ib01_pause(ctx, msg, "检查 cutoff 或 Index_Group 定义。", utils::head(data, 5L))
    }
    stop(msg, call. = FALSE)
  }
  g1_code <- exp_levs[1L]
  g2_code <- exp_levs[2L]
  labs_map <- ib_cfg$exposure_level_labels %||% ib_cfg$strata_level_labels %||% list()
  g1_lab <- as.character(labs_map[[g1_code]] %||% labs_map[[as.character(g1_code)]] %||% g1_code)[1L]
  g2_lab <- as.character(labs_map[[g2_code]] %||% labs_map[[as.character(g2_code)]] %||% g2_code)[1L]
  # tableone 列名用实际水平码
  g1_col <- g1_code
  g2_col <- g2_code

  variables <- .ib01_resolve_balance_vars(data, cfg)
  ps_cov <- .ib01_resolve_ps_covariates(data, cfg, ctx)
  weight_col <- as.character(ib_cfg$weight_col %||% "weight")[1L]
  smd_thr <- as.numeric(ib_cfg$smd_threshold %||% 0.1)[1L]
  table_style <- tolower(as.character(ib_cfg$table_style %||% "jin")[1L])

  cli::cli_alert_info(
    "iptw_balance: 暴露={exp_var} ({g1_lab}/{g2_lab}), PS 协变量 {length(ps_cov)} 个, 平衡变量 {length(variables)} 个, table_style={table_style}"
  )

  if (weight_col %in% names(data)) data[[weight_col]] <- NULL
  ctx$data$imputed <- data

  tab1 <- tableone::CreateTableOne(
    vars = variables, strata = exp_var, data = data, test = TRUE,
    addOverall = TRUE
  )
  tab_matrix <- print(
    tab1,
    showAllLevels = TRUE,
    smd = TRUE,
    printToggle = FALSE,
    quote = FALSE,
    noSpaces = TRUE
  )
  tab_matrix_df <- as.data.frame(tab_matrix)
  n_overall <- if ("Overall" %in% colnames(tab_matrix_df)) tab_matrix_df["n", "Overall"] else NA
  n_one <- tab_matrix_df["n", g1_col]
  n_two <- tab_matrix_df["n", g2_col]
  tab_before <- .ib01_format_tableone_side(
    tab_matrix, index_var, g1_col, g2_col, n_one, n_two
  )

  data_ps <- data
  g1_ref <- g1_col
  g2_ref <- g2_col
  data_ps[[exp_var]] <- ifelse(as.character(data_ps[[exp_var]]) == g1_ref, 0L, 1L)
  # ipw::ipwpoint 要求 exposure 为 data 中的列名（非标准求值），不可传数值向量；
  # denominator 用 bquote 注入已构造的 formula，避免 denom_f 名称查找失败。
  # 非语法列名（如 in-hospital mortality）必须用 backticks。
  ps_terms <- vapply(
    ps_cov,
    function(v) {
      if (grepl("^[A-Za-z.][A-Za-z0-9._]*$", v)) v else paste0("`", v, "`")
    },
    character(1L)
  )
  denom_f <- stats::as.formula(
    paste("~", paste(ps_terms, collapse = " + "))
  )
  w_obj <- tryCatch(
    eval(bquote(ipw::ipwpoint(
      exposure = .(as.name(exp_var)),
      family = "binomial",
      link = "logit",
      numerator = ~1,
      denominator = .(denom_f),
      data = data_ps
    ))),
    error = function(e) {
      if (isTRUE(ib_cfg$pause_enable %||% TRUE) &&
          isTRUE(ib_cfg$pause_on_ipw_fail %||% TRUE)) {
        .ib01_pause(
          ctx,
          paste0("ipwpoint 拟合失败：", e$message),
          "检查 ps_covariates 是否共线或样本量不足。",
          utils::head(data_ps, 5L)
        )
      }
      stop("iptw_balance: ipwpoint 失败：", e$message, call. = FALSE)
    }
  )

  data[[weight_col]] <- w_obj$ipw.weights
  data[[exp_var]] <- factor(
    ifelse(data_ps[[exp_var]] == 0L, g1_ref, g2_ref),
    levels = c(g1_ref, g2_ref)
  )

  dt_iptw <- survey::svydesign(ids = ~1, data = data, weights = stats::as.formula(paste0("~", weight_col)))
  tab1_iptw <- tableone::svyCreateTableOne(
    vars = variables, strata = exp_var, data = dt_iptw, test = TRUE,
    addOverall = TRUE
  )
  tab_matrix1 <- print(
    tab1_iptw,
    showAllLevels = TRUE,
    smd = TRUE,
    printToggle = FALSE,
    quote = FALSE,
    noSpaces = TRUE
  )
  iptw_side <- .ib01_format_tableone_side(
    tab_matrix1, index_var, g1_col, g2_col, n_one, n_two
  )
  after_cols <- seq(3L, min(6L, ncol(iptw_side)))
  tab_after <- iptw_side[, after_cols, drop = FALSE]

  before_lab <- ib_cfg$before_section_label %||% "Before matching"
  after_lab <- ib_cfg$after_section_label %||% "After matching"

  if (identical(table_style, "jin")) {
    ov_hdr <- paste0(
      "Overall (N=", if (!is.na(n_overall)) n_overall else nrow(data), ")"
    )
    g1_hdr <- paste0(g1_lab, " (N=", n_one, ")")
    g2_hdr <- paste0(g2_lab, " (N=", n_two, ")")
    tab_pub <- .ib01_build_jin_style_table1(
      tab_matrix, tab_matrix1, g1_col, g2_col,
      overall_lab = ov_hdr
    )
    nm <- names(tab_pub)
    nm[nm == g1_col] <- g1_hdr
    nm[nm == g2_col] <- g2_hdr
    names(tab_pub) <- nm
    tab_wide <- tab_pub
  } else {
    tab_wide <- .ib01_build_wide_table(tab_before, tab_after, before_lab, after_lab)
  }

  ctx$data$iptw_weighted <- data
  ctx$results$iptw_weight_col <- weight_col
  ctx$results$iptw_ps_covariates <- ps_cov
  ctx$results$iptw_design <- dt_iptw

  if (isTRUE(ib_cfg$export_high_smd %||% TRUE)) {
    high_smd <- .ib01_extract_high_smd_vars(as.data.frame(tab_matrix1), smd_thr)
    ctx$results$iptw_high_smd_vars <- high_smd
    if (length(high_smd)) {
      cli::cli_alert_info(
        "iptw_balance: IPTW 后 SMD>{smd_thr} 变量 {length(high_smd)} 个 → ctx$results$iptw_high_smd_vars"
      )
    }
  }

  # Figure S2（项目编号）：对齐原文 Fig.S1 = PS 分布 (A) + SMD Love (B)
  # 缺失热图为 Figure S1；未加权 KM 为 Figure S3
  if (!isFALSE(ib_cfg$export_love_plot %||% TRUE)) {
    smd_b <- .ib01_extract_smd_vector(tab_matrix)
    smd_a <- .ib01_extract_smd_vector(tab_matrix1)
    love_vars_mode <- tolower(as.character(ib_cfg$love_plot_vars %||% "ps_covariates")[1L])
    if (identical(love_vars_mode, "ps_covariates") && length(ps_cov)) {
      # tableone 行名常带 "mean (SD)" / 水平后缀；用子串匹配保留 PS 协变量
      keep_b <- vapply(smd_b$variable, function(vn) {
        any(vapply(ps_cov, function(pc) grepl(pc, vn, fixed = TRUE) ||
          grepl(gsub("_", " ", pc, fixed = TRUE), vn, fixed = TRUE), logical(1L)))
      }, logical(1L))
      keep_a <- vapply(smd_a$variable, function(vn) {
        any(vapply(ps_cov, function(pc) grepl(pc, vn, fixed = TRUE) ||
          grepl(gsub("_", " ", pc, fixed = TRUE), vn, fixed = TRUE), logical(1L)))
      }, logical(1L))
      if (any(keep_b) && any(keep_a)) {
        smd_b <- smd_b[keep_b, , drop = FALSE]
        smd_a <- smd_a[keep_a, , drop = FALSE]
      }
    }

    fig_style <- tolower(as.character(ib_cfg$supp_balance_fig_style %||% "jin")[1L])
    combined_cap <- as.character(
      ib_cfg$ps_smd_figure_caption %||%
        "The distribution of propensity score and standardized mean difference before and after weighting"
    )[1L]
    love_style <- if (identical(fig_style, "jin")) "jin" else "classic"

    p_love <- tryCatch(
      .ib01_draw_love_plot(
        smd_b, smd_a,
        thr = smd_thr,
        title = if (identical(fig_style, "jin")) "B" else combined_cap,
        style = love_style
      ),
      error = function(e) {
        cli::cli_alert_warning("Love plot 构建失败: {e$message}")
        NULL
      }
    )

    p_ps <- NULL
    ps_vals <- tryCatch(
      as.numeric(stats::predict(w_obj$den.mod, type = "response")),
      error = function(e) NULL
    )
    if (!is.null(ps_vals) && length(ps_vals) == nrow(data_ps)) {
      grp_labs <- c()
      grp_labs[g1_code] <- g1_lab
      grp_labs[g2_code] <- g2_lab
      # data_ps 暴露已是 0/1
      grp_raw <- ifelse(data_ps[[exp_var]] == 0L, g1_code, g2_code)
      p_ps <- tryCatch(
        .ib01_draw_ps_hist(
          ps = ps_vals,
          group = grp_raw,
          group_labels = grp_labs,
          legend_title = as.character(ib_cfg$ps_hist_legend_title %||% "Diabetes")[1L],
          title = "A"
        ),
        error = function(e) {
          cli::cli_alert_warning("PS 直方图构建失败: {e$message}")
          NULL
        }
      )
      ctx$results$iptw_ps_range <- c(
        min = min(ps_vals, na.rm = TRUE),
        max = max(ps_vals, na.rm = TRUE)
      )
    }

    p_combo <- NULL
    if (!is.null(p_ps) && !is.null(p_love) && requireNamespace("patchwork", quietly = TRUE)) {
      p_combo <- p_ps + p_love + patchwork::plot_layout(widths = c(1, 1.15))
    } else if (!is.null(p_love)) {
      p_combo <- p_love
    }

    if (!is.null(p_combo)) {
      # 本块产出应为 Figure S2（S1 留给缺失热图）；保护计数器
      if (exists(".pub_state", mode = "environment", inherits = TRUE)) {
        cur_s <- suppressWarnings(as.integer(get0("supp_figure", envir = .pub_state, ifnotfound = 0L)))
        if (is.na(cur_s)) cur_s <- 0L
        if (cur_s < 1L) assign("supp_figure", 1L, envir = .pub_state)
      }
      love_fn <- if (exists("pub_figure_file", mode = "function")) {
        pub_figure_file(ctx, "supp_figure", combined_cap)
      } else {
        "Figure S2. The distribution of propensity score and standardized mean difference before and after weighting.pdf"
      }
      # 审计：文件名需命中 PS/SMD/Love
      if (!grepl("propensity|PS|SMD|Love|standardized mean", love_fn, ignore.case = TRUE)) {
        love_fn <- sub(
          "\\.pdf$",
          " propensity score and SMD Love.pdf",
          love_fn,
          ignore.case = TRUE
        )
        if (!grepl("\\.pdf$", love_fn, ignore.case = TRUE)) love_fn <- paste0(love_fn, ".pdf")
      }
      n_vars_love <- length(unique(c(smd_b$variable, smd_a$variable)))
      fig_h <- max(5.5, min(16, 0.28 * n_vars_love + 2.5))
      fig_w <- if (!is.null(p_ps)) 11 else 8
      if (exists("save_figure", mode = "function")) {
        ctx <- save_figure(ctx, love_fn, function() {
          print(p_combo)
          invisible(NULL)
        }, width = fig_w, height = fig_h)
      } else {
        fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
        dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
        ggplot2::ggsave(file.path(fig_dir, basename(love_fn)), p_combo, width = fig_w, height = fig_h)
      }
      ctx$results$iptw_love_plot <- love_fn
      ctx$results$iptw_ps_smd_figure <- love_fn
      cli::cli_alert_success(
        "iptw_balance: PS+SMD Figure S2 queued/saved → {.file {basename(love_fn)}}"
      )
    }
  }

  rdata_fn <- ib_cfg$rdata_filename %||% "D01_After_IPTW.RData"
  rdata_path <- file.path(ctx$output_dir, rdata_fn)
  data_imp <- data
  tryCatch(
    {
      save(data_imp, file = rdata_path)
      cli::cli_alert_success("Saved: {.file {basename(rdata_path)}}")
    },
    error = function(e) cli::cli_alert_warning("IPTW RData 保存失败: {e$message}")
  )

  cap <- ib_cfg$table_caption %||% paste0(
    "Baseline characteristics before and after sIPTW in the ",
    cfg$project$database %||% "cohort", " cohort"
  )
  cap <- sub("^Table S\\d+[a-z]?\\.\\s*", "", cap)
  # Jin 同构正式 Table 1；legacy wide 可用 table_pub_role="supp_table"
  pub_role <- as.character(
    ib_cfg$table_pub_role %||% if (identical(table_style, "jin")) "main_table" else "supp_table"
  )[1L]
  if (!nzchar(pub_role)) pub_role <- "main_table"
  paths <- pub_paths(ctx, ctx$output_dir_tables, pub_role, cap, "xlsx")
  footnotes <- ib_cfg$table_footnotes %||% .ib01_default_footnotes()
  if (identical(table_style, "jin") && identical(footnotes, .ib01_default_footnotes())) {
    footnotes <- c(
      paste0(
        "\u00b9 P values from unweighted tests ",
        "(Pearson chi-squared / t or Wilcoxon as applicable)."
      ),
      paste0(
        "\u00b2 Weighted: standardized mean difference after IPTW; ",
        "Unweighted: before IPTW."
      ),
      paste0("SMD threshold for imbalance: ", smd_thr, ".")
    )
  }

  h1 <- NULL
  h2 <- NULL
  if (identical(table_style, "jin") && ncol(tab_wide) >= 8L) {
    # 对齐 Jin Table 1 双行表头：
    # Characteristic | Overall(N) | G1(N) | G2(N) | P¹ | Standardized Mean Difference
    #                  No.(%) spanning groups              Unweighted | Weighted²
    nm <- names(tab_wide)
    h1 <- c(
      "Characteristic", "",
      nm[3L], nm[4L], nm[5L],
      "P\u00b9",
      "Standardized Mean Difference", "Standardized Mean Difference"
    )
    h2 <- c(
      "", "Level",
      "No. (%)", "No. (%)", "No. (%)",
      "",
      "Unweighted", "Weighted\u00b2"
    )
  }

  export_sci_table(
    tab_wide,
    paths$filepath,
    title = paths$title,
    table_footnotes = footnotes,
    header_row1 = h1,
    header_row2 = h2,
    latex_include_colnames = is.null(h1),
    excel_use_prepared = FALSE
  )
  ctx$results$iptw_balance_table <- tab_wide
  cli::cli_alert_success(
    "iptw_balance 完成（{pub_role}: {.file {basename(paths$filepath)}}）"
  )
  ctx
}

register_block(
  "iptw_balance",
  block_iptw_balance,
  "IPTW weighting + before/after covariate balance table (MIMIC-style sIPTW)"
)
