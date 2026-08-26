###############################################################################
#  mediation_ers_environment — 环境混合物 ERS 中介效应分析
#
#  register_block: "mediation_ers_environment"
#  典型流水线: glm_environment_quartile → mediation_ers_environment
#
#  分析结构（"混合"中介）：
#    环境混合暴露（VOC 向量）
#      → 弹性网络拟合 ERS（Environmental Risk Score）
#      → ERS 作为暴露
#      → 中介变量（临床衍生指标：SII/TyG/AUR/Mets_score/FI_Lab 等）
#      → 二分类结局（Disease）
#
#  与现有 mediation_incidence/prognosis block 的核心区别：
#    1. 暴露是 ERS（由 VOC 混合物通过弹性网络计算的复合分），而非单个临床指标
#    2. 包含 ERS 计算步骤（cv.glmnet, alpha=0.5）
#    3. 支持 FI_Lab（实验室脆弱指数）自动计算
#    4. 中介变量为衍生临床指标
#
#  # ── Bug 修复说明（相对原 C01_Mediation-混合.R）────────────────────────────
#  Bug 1: ERS 计算时 y 未二值化（原代码在 glmnet 之后才 ifelse 编码）
#         修复: 先构建 y_numeric(0/1)，再传入 cv.glmnet
#  Bug 2: rt_clean$X7 < 0.05 对字符 "P<0.001" 比较失败
#         修复: 重构结果表，直接用数值 p 值列，字符格式化为独立列
#  Bug 3: rt[-c(seq(1,n,3))] 行删除逻辑脆弱，假设每中介恰好 3 行
#         修复: 用 mediation::mediate() 直接输出，每中介一行，结构清晰
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data        = ctx$data$imputed %||% ctx$data$cleaned
#                        （需同时含 VOC 列 + 临床指标列 + 结局列）
#  require_ctx_results = select_vocs_final（或 select_vocs）
#  可选 ctx_results    = final_features / Model2Factors（协变量）
#
#  # ── 配置 config$mediation_ers_environment ────────────────────────────────
#  mediation_ers_environment = list(
#    # ── 数据 ────────────────────────────────────────────────────────────────
#    select_vocs     = NULL,   # VOC 列名；NULL = ctx$results$select_vocs_final
#    mediators       = NULL,   # 中介变量列名向量；NULL = 见下方默认值
#    covariates      = NULL,   # 协变量；NULL = ctx$results$final_features
#    outcome_col     = NULL,   # 结局列名；NULL = config$data$outcome_column
#    analysis_group  = NULL,   # 病例组标签（编码为 1）
#    reference_group = NULL,   # 对照组标签（编码为 0）
#    # ── ERS 参数 ────────────────────────────────────────────────────────────
#    ers_alpha       = 0.5,    # 弹性网络参数：0=Ridge, 1=Lasso, 0.5=默认ElasticNet
#    ers_s           = "lambda.min",  # 系数提取用的 lambda
#    ers_col         = "current_ers", # ERS 写入数据的列名
#    # ── 中介分析参数 ─────────────────────────────────────────────────────────
#    sims            = 100L,   # bootstrap 次数（100 快速验证，1000 正式发表）
#    seed            = 123L,
#    p_threshold     = 0.05,   # 显著性阈值（筛选有效中介）
#    # ── FI_Lab 计算（可选，需 Gender + 检验指标列）────────────────────────
#    compute_fi_lab  = FALSE,  # 是否自动计算 FI_Lab
#    fi_lab_col      = "FI_Lab",
#    # ── 输出 ────────────────────────────────────────────────────────────────
#    table_filename  = NULL,
#    table_title     = NULL,
#    label_mapping   = NULL    # 命名向量 c(变量名 = "中文名")，可选
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$ers_coefs               — 弹性网络系数（命名数值向量）
#      ctx$results$mediation_ers_table     — 中介结果表（每中介一行）
#      ctx$results$mediation_significant   — 显著中介变量名向量
#      ctx$results$mediation_message_text  — 中文结果描述文本
#  文件: Tables/Table_Mediation_ERS.xlsx
###############################################################################

# ── 辅助：计算 ERS（弹性网络，修复 Bug 1：先二值化 y）────────────────────────
.mers04_compute_ers <- function(data, select_vocs, outcome_col,
                                 analysis_grp, reference_grp,
                                 alpha, s_type, ers_col) {
  X <- as.matrix(data[, select_vocs, drop = FALSE])

  # 修复 Bug 1：先构建数值型 y，再传入 glmnet
  y_raw <- data[[outcome_col]]
  if (is.numeric(y_raw) && all(stats::na.omit(unique(y_raw)) %in% c(0, 1))) {
    y_numeric <- as.integer(y_raw)
  } else {
    yc <- trimws(as.character(y_raw))
    y_numeric <- ifelse(yc == trimws(analysis_grp), 1L,
                        ifelse(yc == trimws(reference_grp), 0L, NA_integer_))
  }
  ok <- !is.na(y_numeric)
  X_ok <- X[ok, , drop = FALSE]
  y_ok <- y_numeric[ok]

  cv_fit <- glmnet::cv.glmnet(X_ok, y_ok, alpha = alpha, family = "binomial")
  coefs  <- glmnet::coef.glmnet(cv_fit, s = s_type)[-1L]  # 去截距
  ers    <- as.numeric(stats::predict(cv_fit, newx = X, s = s_type, type = "link"))
  if (length(unique(stats::na.omit(ers))) < 2L) {
    z <- scale(X_ok)
    z[is.na(z)] <- 0
    ers_ok <- rowSums(z, na.rm = TRUE)
    ers <- rep(NA_real_, nrow(X))
    ers[ok] <- ers_ok
    cli::cli_alert_warning(
      "mediation_ers_environment: glmnet ERS 无变异，回退为 VOC z-score 行和。"
    )
  }
  list(ers = ers, coefs = coefs, cv_fit = cv_fit)
}

# ── 辅助：计算 FI_Lab（按性别参考范围统计异常指标比例）─────────────────────
.mers04_compute_fi_lab <- function(data, reference_ranges, gender_col = "Gender") {
  if (!gender_col %in% names(data)) {
    cli::cli_alert_warning("mediation_ers_environment: 缺少 '{gender_col}' 列，无法计算 FI_Lab。")
    return(rep(NA_real_, nrow(data)))
  }
  target_indicators <- names(reference_ranges)
  available <- intersect(target_indicators, names(data))
  if (!length(available)) {
    cli::cli_alert_warning("mediation_ers_environment: 无可用参考范围指标，FI_Lab 设为 NA。")
    return(rep(NA_real_, nrow(data)))
  }
  total_n <- length(available)

  apply(data, 1L, function(row) {
    row_lst <- as.list(row)
    gender  <- tolower(trimws(as.character(row_lst[[gender_col]])))
    gender  <- if (gender %in% c("male", "m")) "male" else "female"
    count   <- 0L
    for (ind in available) {
      val <- suppressWarnings(as.numeric(row_lst[[ind]]))
      if (is.na(val)) next
      rng <- reference_ranges[[ind]][[gender]]
      if (!is.null(rng) && length(rng) == 2L) {
        if (val < rng[1L] || val > rng[2L]) count <- count + 1L
      }
    }
    count / total_n
  })
}

# ── 辅助：列名别名选取 ────────────────────────────────────────────────────────
.mers04_pick_col <- function(data, candidates) {
  hit <- intersect(as.character(candidates), names(data))
  if (length(hit)) hit[1L] else NULL
}

# ── 辅助：补全 TyG / SII / AUR 等衍生中介列 ─────────────────────────────────
.mers04_ensure_derived_mediators <- function(data) {
  glc <- .mers04_pick_col(data, c("Glucose", "Fasting_Glucose"))
  tg  <- .mers04_pick_col(data, c("Triglycerides", "TG"))
  if (!is.null(glc) && !is.null(tg) && !"TyG" %in% names(data)) {
    data$TyG <- log(pmax(as.numeric(data[[glc]]), 1e-6) *
                      pmax(as.numeric(data[[tg]]), 1e-6) / 2)
  }

  neu <- .mers04_pick_col(data, c(
    "Neutrophil_Count", "Neutrophil_count", "Neutrophil", "Neutrophils"
  ))
  lym <- .mers04_pick_col(data, c(
    "Lymphocytes", "lymphocyte_count", "Lymphocyte", "Lymphocyte_Count"
  ))
  plt <- .mers04_pick_col(data, c(
    "Platelet_Count", "platelet_count", "PlateletCount", "Platelets"
  ))
  if (!is.null(neu) && !is.null(lym) && !is.null(plt) && !"SII" %in% names(data)) {
    lym_v <- pmax(as.numeric(data[[lym]]), 1e-6)
    data$SII <- as.numeric(data[[plt]]) * as.numeric(data[[neu]]) / lym_v
  }

  # AUR = Albumin / Uric_Acid（尿酸白蛋白比）；禁止把 AUR 设成尿酸本身（会与协变量共线）
  alb  <- .mers04_pick_col(data, c("Albumin", "Serum_Albumin"))
  uric <- .mers04_pick_col(data, c("Uric_Acid", "Uric_acid", "UricAcid"))
  if (!is.null(alb) && !is.null(uric) && !"AUR" %in% names(data)) {
    uric_v <- pmax(as.numeric(data[[uric]]), 1e-6)
    data$AUR <- as.numeric(data[[alb]]) / uric_v
  }

  data
}

# ── 辅助：因子/字符协变量数值化（避免 bootstrap 中 rare level 报错）──────────
.mers04_encode_mediate_data <- function(data, model_cols) {
  out <- data
  for (col in model_cols) {
    if (!col %in% names(out)) next
    x <- out[[col]]
    if (is.factor(x) || is.character(x)) {
      xc <- trimws(as.character(x))
      xc[xc == ""] <- NA_character_
      tb <- table(xc, useNA = "no")
      rare <- names(tb)[tb < 5L]
      if (length(rare)) xc[xc %in% rare] <- "Other"
      out[[col]] <- as.numeric(factor(xc))
    }
  }
  out
}

# ── 辅助：运行单个中介效应（mediation::mediate）─────────────────────────────
.mers04_run_one_mediation <- function(data, outcome_col, ers_col, mediator,
                                      covariates, sims, seed, use_boot = FALSE) {
  if (!mediator %in% names(data)) return(NULL)
  if (any(is.na(data[[mediator]]))) {
    data <- data[!is.na(data[[mediator]]), , drop = FALSE]
  }
  if (nrow(data) < 30L) return(NULL)

  cov_use <- setdiff(covariates, mediator)
  # 衍生中介与源列共线时剔除源列（如 AUR 与 Albumin/Uric_Acid）
  if (identical(mediator, "AUR")) {
    cov_use <- setdiff(cov_use, c("Albumin", "Uric_Acid", "Uric_acid", "UricAcid", "Serum_Albumin"))
  }
  if (identical(mediator, "TyG")) {
    cov_use <- setdiff(cov_use, c("Glucose", "Fasting_Glucose", "Triglycerides", "TG"))
  }
  if (identical(mediator, "SII")) {
    cov_use <- setdiff(cov_use, c(
      "Neutrophil", "Neutrophils", "Neutrophil_Count", "Lymphocytes",
      "Lymphocyte", "Platelet_Count", "PlateletCount"
    ))
  }
  model_cols <- unique(c(outcome_col, ers_col, mediator, cov_use))
  d <- .mers04_encode_mediate_data(data, model_cols)
  d <- d[stats::complete.cases(d[, intersect(model_cols, names(d)), drop = FALSE]), , drop = FALSE]
  if (nrow(d) < 30L) return(NULL)

  rhs_cov <- if (length(cov_use)) paste(" + ", paste(cov_use, collapse = " + ")) else ""
  fml_m <- stats::as.formula(paste0(mediator, " ~ ", ers_col, rhs_cov))
  fml_y <- stats::as.formula(paste0(outcome_col, " ~ ", ers_col, " + ", mediator, rhs_cov))

  model_m <- tryCatch(
    stats::lm(fml_m, data = d),
    error = function(e) NULL
  )
  model_y <- tryCatch(
    stats::glm(fml_y, data = d, family = stats::binomial()),
    error = function(e) NULL
  )
  if (is.null(model_m) || is.null(model_y)) return(NULL)

  set.seed(seed)
  med_args <- list(
    model.m  = model_m,
    model.y  = model_y,
    treat    = ers_col,
    mediator = mediator,
    sims     = sims,
    boot     = isTRUE(use_boot)
  )
  if (isTRUE(use_boot)) med_args$boot.ci.type <- "perc"

  med_fit <- tryCatch(
    do.call(mediation::mediate, med_args),
    error = function(e) {
      if (!isTRUE(use_boot)) {
        cli::cli_alert_warning("  [{mediator}] mediate 失败: {e$message}")
        return(NULL)
      }
      cli::cli_alert_warning(
        "  [{mediator}] boot mediate 失败，回退 quasi-Bayesian: {e$message}"
      )
      tryCatch(
        mediation::mediate(
          model.m = model_m, model.y = model_y,
          treat = ers_col, mediator = mediator,
          sims = sims, boot = FALSE
        ),
        error = function(e2) {
          cli::cli_alert_warning("  [{mediator}] quasi-Bayesian 仍失败: {e2$message}")
          NULL
        }
      )
    }
  )
  if (is.null(med_fit)) return(NULL)
  med_fit
}

# ── 辅助：从 mediation 结果提取一行 data.frame ─────────────────────────────
.mers04_extract_row <- function(med_fit, mediator) {
  sm <- summary(med_fit)
  .sm_val <- function(base) {
    coef_nm <- paste0(base, ".coef")
    if (!is.null(sm[[coef_nm]]) && length(sm[[coef_nm]])) return(as.numeric(sm[[coef_nm]]))
    as.numeric(sm[[base]])
  }
  .sm_ci <- function(base) {
    ci_nm <- paste0(base, ".ci")
    as.numeric(sm[[ci_nm]])
  }
  .fmt_est_ci <- function(est, ci) {
    paste0(round(est, 4L), "(", round(ci[1L], 4L), ",", round(ci[2L], 4L), ")")
  }
  .fmt_p <- function(p) {
    if (is.null(p) || is.na(p)) return(NA_character_)
    if (p < 0.001) "P<0.001" else as.character(round(p, 4L))
  }
  tau_est <- .sm_val("tau")
  z_est   <- .sm_val("z.avg")
  d_est   <- .sm_val("d.avg")
  n_prop  <- as.numeric(sm$n.avg)
  data.frame(
    Mediator         = mediator,
    Total_Effect     = .fmt_est_ci(tau_est, .sm_ci("tau")),
    Total_Effect_P   = .fmt_p(sm$tau.p),
    Total_Effect_p_num = as.numeric(sm$tau.p),
    Total_Effect_est_num = tau_est,
    Direct_Effect    = .fmt_est_ci(z_est, .sm_ci("z.avg")),
    Direct_Effect_P  = .fmt_p(sm$z.avg.p),
    Direct_Effect_p_num = as.numeric(sm$z.avg.p),
    Direct_Effect_est_num = z_est,
    Indirect_Effect  = .fmt_est_ci(d_est, .sm_ci("d.avg")),
    Indirect_Effect_P = .fmt_p(sm$d.avg.p),
    Indirect_Effect_p_num = as.numeric(sm$d.avg.p),
    Indirect_Effect_est_num = d_est,
    Prop_Mediated    = paste0(round(n_prop * 100, 2L), "%"),
    stringsAsFactors = FALSE
  )
}

# ── 辅助：生成中文中介结果文本 ───────────────────────────────────────────────
.mers04_generate_message <- function(filtered_table, label_map = NULL) {
  if (!nrow(filtered_table)) return("")
  parts <- vapply(seq_len(nrow(filtered_table)), function(i) {
    row <- filtered_table[i, ]
    med_label <- row$Mediator
    if (!is.null(label_map) && length(label_map) && med_label %in% names(label_map)) {
      med_label <- as.character(label_map[[med_label]])
    } else {
      med_label <- gsub("_", "", med_label)
    }
    lbl <- if (nrow(filtered_table) == 1L) "" else LETTERS[i]
    paste0(
      "\u5728", med_label, "\u4ecb\u5bfc\u7684\u4e2d\u4ecb\u4f5c\u7528\u4e2d\uff0c",
      "\u76f4\u63a5\u6548\u5e94\u4e3a", sub("\\(.*", "", row$Direct_Effect), "\uff0c",
      "\u95f4\u63a5\u6548\u5e94\u4e3a", sub("\\(.*", "", row$Indirect_Effect), "\uff0c",
      "\u603b\u6548\u5e94\u4e3a", sub("\\(.*", "", row$Total_Effect), "\uff0c",
      "\u4e2d\u4ecb\u7684\u6bd4\u4f8b\u4e3a", row$Prop_Mediated,
      "\uff08Figure ", lbl, "\uff09\u3002"
    )
  }, character(1L))
  paste(parts, collapse = "")
}

# ── 辅助：openxlsx SCI 三线表导出 ─────────────────────────────────────────────
.mers04_export_xlsx <- function(df, filepath, title) {
  library(openxlsx)
  # 只展示格式化列（去掉 _p_num 数值列）
  display_cols <- grep("_p_num$", names(df), value = TRUE, invert = TRUE)
  df_out <- df[, display_cols, drop = FALSE]

  wb <- createWorkbook()
  addWorksheet(wb, "Sheet1")
  writeData(wb, "Sheet1", df_out,  startRow = 2L, startCol = 1L, rowNames = FALSE)
  writeData(wb, "Sheet1", title,   startRow = 1L, startCol = 1L)

  n_col <- ncol(df_out)
  title_style  <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold", border = "bottom",
                               halign = "center", valign = "center")
  header_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold")
  body_style   <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               halign = "center", valign = "center")
  bottom_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               border = "bottom")

  mergeCells(wb, "Sheet1", cols = 1:n_col, rows = 1L)
  addStyle(wb, "Sheet1", title_style,  rows = 1L, cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", header_style, rows = 2L, cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", body_style,
           rows = 3L:(nrow(df_out) + 2L), cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", bottom_style,
           rows = nrow(df_out) + 3L, cols = 1:(n_col + 1L), gridExpand = FALSE)
  showGridLines(wb, "Sheet1", showGridLines = FALSE)
  setColWidths(wb, "Sheet1", cols = 1:(n_col + 1L), widths = "auto")
  setColWidths(wb, "Sheet1", cols = 1L, widths = 30)
  saveWorkbook(wb, filepath, overwrite = TRUE)
}

#' 单个中介变量的效应条形图
.mers04_plot_mediator_figure <- function(med_fit, mediator, label_map, fig_path) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible(FALSE))
  sm <- summary(med_fit)
  .val <- function(nm) as.numeric(sm[[paste0(nm, ".coef")]] %||% sm[[nm]])
  .ci  <- function(nm) as.numeric(sm[[paste0(nm, ".ci")]])
  df <- data.frame(
    effect = factor(c("Total effect", "Direct effect", "Indirect effect"),
                    levels = c("Total effect", "Direct effect", "Indirect effect")),
    est = c(.val("tau"), .val("z.avg"), .val("d.avg")),
    lo  = c(.ci("tau")[1L], .ci("z.avg")[1L], .ci("d.avg")[1L]),
    hi  = c(.ci("tau")[2L], .ci("z.avg")[2L], .ci("d.avg")[2L]),
    stringsAsFactors = FALSE
  )
  med_lbl <- if (exists("environment_display_label", mode = "function")) {
    environment_display_label(mediator, label_map)
  } else gsub("_", " ", mediator, fixed = TRUE)
  p <- ggplot2::ggplot(df, ggplot2::aes(x = .data$effect, y = .data$est, fill = .data$effect)) +
    ggplot2::geom_col(width = 0.55, show.legend = FALSE) +
    ggplot2::geom_errorbar(
      ggplot2::aes(ymin = .data$lo, ymax = .data$hi),
      width = 0.15
    ) +
    ggplot2::scale_fill_manual(values = c("#FFD121", "#223D6C", "#D20A13")) +
    ggplot2::labs(
      title = paste0("Mediation: ", med_lbl),
      x = NULL, y = "Effect estimate"
    ) +
    ggplot2::theme_minimal(base_family = "serif") +
    ggplot2::theme(plot.title = ggplot2::element_text(size = 11, face = "bold"))
  tryCatch({
    ggplot2::ggsave(fig_path, plot = p, width = 6, height = 4.5)
    invisible(TRUE)
  }, error = function(e) {
    cli::cli_alert_warning("  [{mediator}] 中介图保存失败: {e$message}")
    invisible(FALSE)
  })
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_mediation_ers_environment <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(glmnet)
    library(mediation)
    library(dplyr)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$mediation_ers_environment %||% list()

  # ── 读取数据 ─────────────────────────────────────────────────────────────
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("mediation_ers_environment: 未找到数据，请先运行上游数据准备 block。")
  }

  outcome_col   <- as.character(bl_cfg$outcome_col    %||% cfg$data$outcome_column %||% "Group")
  analysis_grp  <- as.character(bl_cfg$analysis_group %||% cfg$project$analysis_group  %||% "Case")
  reference_grp <- as.character(bl_cfg$reference_group %||% cfg$project$reference_group %||% "Control")
  if (!outcome_col %in% names(data)) {
    stop("mediation_ers_environment: 结局列 '", outcome_col, "' 不在数据中。")
  }

  # ── 二值化结局 ───────────────────────────────────────────────────────────
  y_raw <- data[[outcome_col]]
  if (!(is.numeric(y_raw) && all(stats::na.omit(unique(y_raw)) %in% c(0, 1)))) {
    yc <- trimws(as.character(y_raw))
    data[[outcome_col]] <- as.integer(
      ifelse(yc == trimws(analysis_grp), 1L,
             ifelse(yc == trimws(reference_grp), 0L, NA_integer_))
    )
  } else {
    data[[outcome_col]] <- as.integer(y_raw)
  }

  # ── 读取 VOC 和协变量 ─────────────────────────────────────────────────────
  select_vocs <- as.character(
    bl_cfg$select_vocs %||%
    ctx$results$select_vocs_final %||%
    ctx$results$select_vocs %||%
    character(0)
  )
  select_vocs <- intersect(select_vocs, names(data))
  if (length(select_vocs) < 2L) {
    fallback_vocs <- as.character(
      ctx$results$select_vocs_clinical_gate %||%
      ctx$results$select_vocs_lasso %||%
      ctx$results$select_vocs_lod %||%
      character(0)
    )
    fallback_vocs <- intersect(fallback_vocs, names(data))
    if (length(fallback_vocs) >= 2L) {
      cli::cli_alert_info(
        "mediation_ers_environment: select_vocs_final 不足，回退临床门禁 VOC（{length(fallback_vocs)} 个）"
      )
      select_vocs <- fallback_vocs
    }
  }
  if (length(select_vocs) < 2L) {
    cli::cli_alert_warning("mediation_ers_environment: select_vocs 有效列不足 2 个，跳过。")
    return(ctx)
  }

  covariates <- if (exists("pipeline_mediation_resolve_path_covariates", mode = "function")) {
    pipeline_mediation_resolve_path_covariates(cfg, bl_cfg, names(data), ctx = ctx)
  } else {
    character(0)
  }
  # 兼容旧行为：仅当显式开启 path_use_covariates 且未给 covariates 时，才回退 Model2/final_features
  if (exists("pipeline_mediation_path_use_covariates", mode = "function") &&
      pipeline_mediation_path_use_covariates(cfg, bl_cfg) && !length(covariates)) {
    covariates <- as.character(
      bl_cfg$covariates %||%
        ctx$results$final_features %||%
        ctx$results$Model2Factors %||%
        character(0)
    )
    covariates <- intersect(covariates, names(data))
  }

  # ── 衍生中介指标（TyG / SII / AUR）────────────────────────────────────────
  data <- .mers04_ensure_derived_mediators(data)

  # ── 可选：计算 FI_Lab ────────────────────────────────────────────────────
  if (isTRUE(bl_cfg$compute_fi_lab)) {
    fi_lab_col <- as.character(bl_cfg$fi_lab_col %||% "FI_Lab")
    ref_ranges <- bl_cfg$fi_lab_reference_ranges
    if (is.null(ref_ranges)) {
      cli::cli_alert_warning(
        "mediation_ers_environment: compute_fi_lab=TRUE 但未提供 fi_lab_reference_ranges，跳过 FI_Lab 计算。"
      )
    } else {
      cli::cli_alert_info("mediation_ers_environment: 计算 FI_Lab...")
      data[[fi_lab_col]] <- .mers04_compute_fi_lab(data, ref_ranges)
      cli::cli_alert_success("FI_Lab 已写入列 '{fi_lab_col}'")
    }
  }

  # ── 计算 ERS（修复 Bug 1）────────────────────────────────────────────────
  ers_alpha  <- as.numeric(bl_cfg$ers_alpha %||% 0.5)
  ers_s      <- as.character(bl_cfg$ers_s   %||% "lambda.min")
  ers_col    <- as.character(bl_cfg$ers_col %||% "current_ers")
  seed       <- as.integer(bl_cfg$seed      %||% 123L)

  cli::cli_h2("mediation_ers_environment: 计算 ERS（alpha={ers_alpha}, s='{ers_s}'）")
  set.seed(seed)
  ers_res <- tryCatch(
    .mers04_compute_ers(data, select_vocs, outcome_col,
                        analysis_grp, reference_grp,
                        ers_alpha, ers_s, ers_col),
    error = function(e) {
      stop("mediation_ers_environment: ERS 计算失败: ", e$message, call. = FALSE)
    }
  )
  data[[ers_col]]                 <- ers_res$ers
  ctx$results$ers_coefs           <- ers_res$coefs
  cli::cli_alert_success("ERS 已计算并写入列 '{ers_col}'（range=[{round(min(ers_res$ers),3)}, {round(max(ers_res$ers),3)}]）")

  # ── 确定中介变量 ─────────────────────────────────────────────────────────
  default_mediators <- c("SII", "TyG", "AUR", "Mets_score", "FI_Lab")
  mediators <- as.character(bl_cfg$mediators %||% default_mediators)
  mediators <- intersect(mediators, names(data))
  if (!length(mediators)) {
    stop(
      "mediation_ers_environment: 未找到中介变量列（配置或默认列：",
      paste(default_mediators, collapse = ", "), "）。"
    )
  }
  cli::cli_alert_info(
    "mediation_ers_environment: 中介变量 ({length(mediators)} 个): {paste(mediators, collapse=', ')}"
  )

  # ── 自动协变量搜索（默认关；须 path_use_covariates=TRUE）────────────────────
  auto_cov_search <- if (exists("pipeline_mediation_auto_covariate_search", mode = "function")) {
    pipeline_mediation_auto_covariate_search(cfg, bl_cfg)
  } else {
    FALSE
  }
  if (auto_cov_search) {
    search_sets <- bl_cfg$covariate_search_sets
    if (is.null(search_sets) || !length(search_sets)) {
      search_sets <- (cfg$rcs_nhanes %||% list())$model2_factor_sets
    }
    if (is.null(search_sets) || !length(search_sets)) {
      pool <- bl_cfg$covariate_search_pool %||% ctx$results$Model2Factors %||% character(0)
      search_sets <- list(intersect(as.character(pool), names(data)))
    }
    path_alpha <- as.numeric(bl_cfg$mediation_path_alpha %||% bl_cfg$p_threshold %||% 0.05)
    require_pos <- isTRUE(bl_cfg$require_positive_indirect %||% TRUE)
    sims_search <- as.integer(bl_cfg$covariate_search_sims %||% min(100L, bl_cfg$sims %||% 100L))

    probe_cols <- unique(c(outcome_col, ers_col, mediators, unlist(search_sets), covariates))
    data_probe <- data[, intersect(probe_cols, names(data)), drop = FALSE]
    data_probe <- data_probe[
      stats::complete.cases(data_probe[, c(outcome_col, ers_col), drop = FALSE]), ,
      drop = FALSE
    ]

    found_cov <- NULL
    for (adj in search_sets) {
      adj_vec <- intersect(as.character(unlist(adj, use.names = FALSE)), names(data_probe))
      for (m in mediators) {
        fit <- .mers04_run_one_mediation(
          data_probe, outcome_col, ers_col, m, adj_vec, sims_search, seed, use_boot = FALSE
        )
        if (is.null(fit)) next
        row <- tryCatch(.mers04_extract_row(fit, m), error = function(e) NULL)
        if (is.null(row)) next
        ok_p <- is.finite(row$Indirect_Effect_p_num) && row$Indirect_Effect_p_num < path_alpha
        ok_pos <- !require_pos || (is.finite(row$Indirect_Effect_est_num) && row$Indirect_Effect_est_num > 0)
        if (ok_p && ok_pos) {
          found_cov <- list(cov = adj_vec, hit = m)
          break
        }
      }
      if (!is.null(found_cov)) break
    }
    if (!is.null(found_cov)) {
      covariates <- found_cov$cov
      ctx$results$mediation_ers_auto_covariates <- found_cov$cov
      cli::cli_alert_success(
        "mediation_ers_environment: 自动协变量 ({paste(found_cov$cov, collapse=', ')})，命中 [{found_cov$hit}]"
      )
    } else {
      cli::cli_alert_warning(
        "mediation_ers_environment: 自动协变量搜索未命中，沿用 Model2/配置协变量"
      )
    }
  }

  # ── 完整样本 ─────────────────────────────────────────────────────────────
  keep_cols <- unique(c(outcome_col, ers_col, mediators, covariates))
  data_med  <- data[, intersect(keep_cols, names(data)), drop = FALSE]
  data_med  <- data_med[stats::complete.cases(data_med[, c(outcome_col, ers_col)]), , drop = FALSE]
  cli::cli_alert_info("mediation_ers_environment: n = {nrow(data_med)}")

  # ── 中介分析主循环 ────────────────────────────────────────────────────────
  sims        <- as.integer(bl_cfg$sims        %||% 100L)
  use_boot    <- isTRUE(bl_cfg$boot            %||% FALSE)
  p_threshold <- as.numeric(bl_cfg$p_threshold %||% 0.05)

  cli::cli_h2(
    "mediation_ers_environment: 对 {length(mediators)} 个中介变量运行 mediate() (sims={sims})"
  )

  rows <- list()
  med_fits <- list()
  label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl_cfg$label_mapping)
  } else {
    bl_cfg$label_mapping
  }
  export_figs <- isTRUE(bl_cfg$export_mediator_figures %||% TRUE)
  fig_prefix <- as.character(bl_cfg$fig_filename_prefix %||% "Figure 9. Mediation plot for ")
  fig_dir <- file.path(ctx$output_dir %||% ".", "Figures")
  if (export_figs && !dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)

  for (med in mediators) {
    cli::cli_alert_info("  [{med}]...")
    med_fit <- .mers04_run_one_mediation(
      data_med, outcome_col, ers_col, med, covariates, sims, seed, use_boot
    )
    if (is.null(med_fit)) {
      cli::cli_alert_warning("  [{med}] 跳过（拟合失败或样本不足）")
      next
    }
    row_df <- tryCatch(
      .mers04_extract_row(med_fit, med),
      error = function(e) {
        cli::cli_alert_warning("  [{med}] 结果提取失败: {e$message}")
        NULL
      }
    )
    if (!is.null(row_df)) {
      rows[[length(rows) + 1L]] <- row_df
      med_fits[[med]] <- med_fit
      if (export_figs) {
        med_lbl <- environment_display_label(med, label_map)
        fig_name <- paste0(fig_prefix, med_lbl, ".pdf")
        fig_path <- file.path(fig_dir, fig_name)
        .mers04_plot_mediator_figure(med_fit, med, label_map, fig_path)
      }
      cli::cli_alert_success(
        "  [{med}] Indirect P={round(row_df$Indirect_Effect_p_num, 4)}"
      )
    }
  }

  if (!length(rows)) {
    if (isTRUE(bl_cfg$allow_empty_results)) {
      cli::cli_alert_warning(
        "mediation_ers_environment: 所有中介变量均未产生有效结果（allow_empty_results=TRUE，跳过）。"
      )
      return(ctx)
    }
    stop("mediation_ers_environment: 所有中介变量均未产生有效结果。")
  }

  rt_full <- do.call(rbind, rows)
  require_pos <- isTRUE(bl_cfg$require_positive_indirect %||% TRUE)
  if (require_pos && "Indirect_Effect_est_num" %in% names(rt_full)) {
    pos_ok <- is.finite(rt_full$Indirect_Effect_est_num) & rt_full$Indirect_Effect_est_num > 0
    if (any(!pos_ok)) {
      cli::cli_alert_info(
        "mediation_ers_environment: 剔除 {sum(!pos_ok)} 行非正间接效应"
      )
      rt_full <- rt_full[pos_ok, , drop = FALSE]
    }
  }
  if (!nrow(rt_full)) {
    stop("mediation_ers_environment: 过滤非正间接效应后无有效行。", call. = FALSE)
  }
  if (exists("environment_prettify_df_cols", mode = "function")) {
    rt_full <- environment_prettify_df_cols(rt_full, "Mediator", label_map)
  }

  # ── 筛选显著中介（修复 Bug 2：用数值列比较，而非字符列）───────────────────
  is_sig <- !is.na(rt_full$Indirect_Effect_p_num) &
            rt_full$Indirect_Effect_p_num < p_threshold
  rt_sig <- rt_full[is_sig, , drop = FALSE]

  sig_mediators <- rt_sig$Mediator
  cli::cli_alert_success(
    "mediation_ers_environment: 显著中介（Indirect P<{p_threshold}）: {length(sig_mediators)} 个"
  )

  ctx$results$mediation_ers_table   <- rt_full
  ctx$results$mediation_significant <- sig_mediators

  # ── 生成中文文本 ─────────────────────────────────────────────────────────
  msg_text <- .mers04_generate_message(rt_sig, label_map)
  ctx$results$mediation_message_text <- msg_text
  if (nzchar(msg_text)) {
    cli::cli_alert_info("mediation_message_text 已生成")
  }

  # ── 导出 Excel ────────────────────────────────────────────────────────────
  tbl_dir  <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  tbl_fn   <- as.character(bl_cfg$table_filename %||% "Table_Mediation_ERS.xlsx")
  tbl_path <- file.path(tbl_dir, tbl_fn)
  disease_name <- as.character(
    cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"
  )
  tbl_title <- as.character(
    bl_cfg$table_title %||%
    paste0("Table. Mediation analysis of Environmental Risk Score and ", disease_name)
  )
  tryCatch({
    .mers04_export_xlsx(rt_full, tbl_path, tbl_title)
    cli::cli_alert_success("{tbl_fn} 已展存")
  }, error = function(e) {
    cli::cli_alert_warning("mediation_ers_environment: Excel 展存失败: {e$message}")
  })

  cli::cli_alert_success("mediation_ers_environment 完成。")
  ctx
}

register_block(
  "mediation_ers_environment",
  block_mediation_ers_environment,
  "环境混合物 ERS 中介分析：弹性网络计算 ERS → 临床衍生指标中介 → 结局"
)
