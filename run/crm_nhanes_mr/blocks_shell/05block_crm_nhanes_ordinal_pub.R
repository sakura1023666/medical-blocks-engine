###############################################################################
#  crm_nhanes_ordinal_pub — NHANES 加权有序 Logistic 发表级 Table 2
#  （SUA / hyperuricemia / gout[若存在] → CRM_count 有序结局；Crude + Model2）
#
#  依据：Han et al. 2025 JAHA e038723；本仓库设计
#  docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md（Table 2）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data      = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）
#  requires_packages = c("survey")
#
#  说明（横断面口径，与 Cox/RCS/KM 不同）：本块 Table 2 为横断面有序 logistic，
#  按 brief 明确要求"ordinal may use cross-sectional CRM without requiring death"——
#  分析集仅要求暴露变量 + 协变量 + CRM_count 非缺失，**不**施加死亡随访合格
#  （eligstat/futime/fustatus）过滤，与 06/07（Cox/RCS，需死亡随访完整）刻意不同。
#
#  说明（OR 符号与 P 值口径，证据链）：
#    - OR = exp(coef)，与本仓库既有 Blocks/57_dual_incidence_mr_full/09block_crm_nhanes_weighted.R
#      的 svyolr OR 输出口径一致（不做符号翻转）；svyolr 对 ordered factor 结局的系数方向遵循
#      MASS::polr 累积 logit 约定，本块不重新推导/翻转符号，以与既有代码保持一致为准。
#    - survey::svyolr 的 summary() 仅给出 Value/Std.Error/t value，未提供精确 p（复杂抽样设计
#      自由度不唯一定义）。本块采用正态近似 Wald 检验 P = 2*pnorm(-abs(t value))，与
#      MASS::polr 文档"大样本 t 值可按正态近似"的通行做法一致；此为方法学近似，非文献确证的
#      精确 p 值算法——【证据不足，已标注】。
#    - hyperuricemia / gout 为原始 0/1 数值列（非 factor），故 OR 表示"暴露组 vs 非暴露组"，
#      系数行名即变量名本身（不含因子水平后缀），与 09block_crm_nhanes_weighted.R 处理方式一致。
#
#  说明（gout 证据链）：crm_nhanes_derive 默认未派生 gout（NHANES_文献_0722.RData 未见痛风列，
#  见该文件 Task 1 smoke 审计）。本块**不臆造**痛风暴露：仅当数据确有非全缺失的 "gout" 列时才
#  纳入该暴露；否则跳过并在 ctx$results$crm_nhanes_ordinal_pub$gout_available 中记为 FALSE，
#  CSV 中不出现 gout 行（而不是填充 NA 行冒充"已尝试但缺失"）。
#
#  说明（Crude 与 Model2 同一分析集，证据链）：为使同一暴露的 Crude/Model2 OR 可比（同一 N），
#  本块对每个暴露变量，先按 Model2 所需列（暴露 + adjust_vars + CRM_count，非缺失）确定分析集，
#  Crude 与 Model2 均在此相同分析集上拟合——与本仓库 Blocks/70_crm_nhanes_pub/03block（基线表）
#  "先定分析集再各口径共用"的既有实践一致；这不是文献逐字复现的确证做法（原文各模型 N 是否
#  完全一致未在可读文本证据中确认），仅为方法学选择，已在此处明确记录。
#
#  crm_nhanes_ordinal_pub = list(
#    outcome_col   = "CRM_count",
#    exposures     = c("SUA", "hyperuricemia", "gout"),  # gout 缺列时自动跳过，不报错
#    adjust_vars   = NULL,        # NULL → c("Age","Gender","BMI") ∩ 数据列
#    weight_col    = NULL,        # NULL → config$nhanes$survey_weight %||% "new_Weight"
#    cluster_col   = NULL,        # NULL → config$nhanes$survey_strata %||% "SDMVSTRA"（注意：
#    strata_col    = NULL,        #        cluster/strata 命名与下方列名对应，见 R 变量注释）
#    table_filename = "Table_2_Ordinal_NHANES.csv",  # 固定名（文献 Table 2）
#    also_run_thin57 = FALSE,     # TRUE → 额外调用 57 的 block_crm_ordinal_logistic() 做冒烟对照
#                                 # （只读比较，不覆盖本块发表口径产出；见下方实现）
#    pause_enable          = TRUE,
#    pause_on_no_output    = TRUE
#  )
#
#  register_block: "crm_nhanes_ordinal_pub"
#  典型位置: crm_nhanes_derive → ... → crm_nhanes_ordinal_pub（Table 2）→ crm_nhanes_cox_pub → ...
#
#  读: ctx$data$cleaned %||% ctx$data$raw
#  写: ctx$results$crm_nhanes_ordinal_pub（每个暴露×模型的 tidy 系数、gout_available、
#      analytic_n、可选 thin57_comparison）
#
#  产出:
#    - [固定名] Tables/Table_2_Ordinal_NHANES.csv（Exposure/Model/Term/OR/Lower95/Upper95/P/N）
#
#  pause: config$crm_nhanes_ordinal_pub$pause_enable
###############################################################################

.crm70o_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70o_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_ordinal_pub",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_ordinal_pub halted. See ctx$results$pause_point. / ",
    "NHANES 有序 Logistic 发表表异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.crm70o_build_design <- function(d, wt_col, psu_col, str_col) {
  has_design_cols <- all(c(psu_col, str_col) %in% names(d))
  tryCatch({
    if (has_design_cols) {
      survey::svydesign(
        ids = stats::as.formula(paste0("~", psu_col)),
        strata = stats::as.formula(paste0("~", str_col)),
        weights = stats::as.formula(paste0("~", wt_col)),
        data = d, nest = TRUE
      )
    } else {
      survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", wt_col)), data = d)
    }
  }, error = function(e) NULL)
}

#' 拟合一个 svyolr 并提取指定暴露项 term 的 tidy 行（OR/CI/P/N）
#' n_unweighted: 由调用方传入的未加权行数（nrow(d)），而非 fit$n/fit$nobs（后两者是
#' svyolr 内部的"加权有效样本量"，与未加权行数不同——为避免混淆报表读者，本函数不使用
#' fit$n 作为 N 列，见调用处 nrow(d)）。
.crm70o_fit_and_tidy <- function(design, y, x, covs, model_label, n_unweighted) {
  fml <- stats::as.formula(paste0(
    y, " ~ ", x, if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
  ))
  fit <- tryCatch(survey::svyolr(fml, design = design), error = function(e) {
    cli::cli_alert_warning("crm_nhanes_ordinal_pub: svyolr({x}, {model_label}) 拟合失败: {e$message}")
    NULL
  })
  if (is.null(fit)) {
    return(data.frame(
      Term = x, OR = NA_real_, Lower95 = NA_real_, Upper95 = NA_real_,
      P = NA_real_, N = n_unweighted, stringsAsFactors = FALSE
    ))
  }
  s <- summary(fit)
  ct <- s$coefficients
  if (!x %in% rownames(ct)) {
    return(data.frame(
      Term = x, OR = NA_real_, Lower95 = NA_real_, Upper95 = NA_real_,
      P = NA_real_, N = n_unweighted, stringsAsFactors = FALSE
    ))
  }
  val <- ct[x, "Value"]
  se <- ct[x, "Std. Error"]
  tval <- ct[x, "t value"]
  # 正态近似 Wald 检验（复杂抽样设计自由度不唯一定义，见文件头说明【证据不足，方法学近似】）
  pval <- 2 * stats::pnorm(-abs(tval))
  data.frame(
    Term = x,
    OR = exp(val),
    Lower95 = exp(val - 1.96 * se),
    Upper95 = exp(val + 1.96 * se),
    P = pval,
    N = n_unweighted,
    stringsAsFactors = FALSE
  )
}

block_crm_nhanes_ordinal_pub <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_ordinal_pub %||% list()
  nh_cfg <- cfg$nhanes %||% list()

  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    if (.crm70o_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70o_pause(ctx, "未找到分析数据（ctx$data$cleaned 与 raw 均为空）。",
                   "请先运行 crm_nhanes_derive。", NULL)
    }
    stop("crm_nhanes_ordinal_pub: 无分析数据。", call. = FALSE)
  }
  if (!requireNamespace("survey", quietly = TRUE)) {
    if (.crm70o_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70o_pause(ctx, "缺少 R 包 survey，无法构建加权有序 Logistic。",
                   "安装 survey 后重试，或设 pause_on_no_output = FALSE。", NULL)
    }
    stop("crm_nhanes_ordinal_pub: 缺少 survey 包。", call. = FALSE)
  }
  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))
  options(survey.lonely.psu = "adjust")

  y <- as.character(bl_cfg$outcome_col %||% "CRM_count")[1L]
  wt_col <- as.character(bl_cfg$weight_col %||% nh_cfg$survey_weight %||% "new_Weight")[1L]
  psu_col <- as.character(bl_cfg$cluster_col %||% nh_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(bl_cfg$strata_col %||% nh_cfg$survey_strata %||% "SDMVSTRA")[1L]

  if (!y %in% names(data) || !wt_col %in% names(data)) {
    msg <- paste0("crm_nhanes_ordinal_pub: 数据缺少结局列 ", y, " 或权重列 ", wt_col, "。")
    if (.crm70o_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70o_pause(ctx, msg, "请先运行 crm_nhanes_derive。", data)
    }
    stop(msg, call. = FALSE)
  }

  exposures_cfg <- as.character(bl_cfg$exposures %||% c("SUA", "hyperuricemia", "gout"))
  gout_requested <- "gout" %in% exposures_cfg
  gout_available <- gout_requested && "gout" %in% names(data) && !all(is.na(data$gout))
  if (gout_requested && !gout_available) {
    cli::cli_alert_warning(
      "crm_nhanes_ordinal_pub: 数据无 gout 列（或全缺失），跳过 gout 暴露（不臆造痛风数据）。"
    )
  }
  exposures <- exposures_cfg[exposures_cfg != "gout" | gout_available]
  exposures <- exposures[exposures %in% names(data)]
  if (!length(exposures)) {
    msg <- "crm_nhanes_ordinal_pub: 配置的暴露变量均不在数据中。"
    if (.crm70o_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70o_pause(ctx, msg, "检查 config$crm_nhanes_ordinal_pub$exposures。", data)
    }
    stop(msg, call. = FALSE)
  }

  # 原文 Table 2：Crude / Model 1 / Model 2
  # Model 1 = age, sex, race
  # Model 2 = age, sex, race, education, poverty, BMI, hypertension, smoking, triglyceride
  # 本库列名映射：Gender←sex，PIR←poverty，Smoke←smoking，TG←triglyceride
  # 若上游 multicollinearity_final 已写入 Model2Factors，优先采用（预后式筛选）
  model1_default <- c("Age", "Gender", "Race")
  model2_default <- c(
    "Age", "Gender", "Race", "Education", "PIR", "BMI",
    "Hypertension", "Smoke", "TG"
  )
  strip_exp <- c("SUA", "hyperuricemia", "gout", "CRM_count", "Group", "UricAcid")
  m1_ctx <- setdiff(intersect(as.character(ctx$results$Model1Factors %||% character(0)), names(data)), strip_exp)
  m2_ctx <- setdiff(intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(data)), strip_exp)
  model1_vars <- if (!is.null(bl_cfg$model1_vars) && length(bl_cfg$model1_vars)) {
    intersect(as.character(bl_cfg$model1_vars), names(data))
  } else if (length(m1_ctx)) {
    m1_ctx
  } else {
    intersect(model1_default, names(data))
  }
  # 兼容旧键 adjust_vars → 仅覆盖 Model2；优先 Model2Factors
  model2_vars <- if (!is.null(bl_cfg$model2_vars) && length(bl_cfg$model2_vars)) {
    intersect(as.character(bl_cfg$model2_vars), names(data))
  } else if (!is.null(bl_cfg$adjust_vars) && length(bl_cfg$adjust_vars)) {
    intersect(as.character(bl_cfg$adjust_vars), names(data))
  } else if (length(m2_ctx)) {
    m2_ctx
  } else {
    intersect(model2_default, names(data))
  }
  if (length(m2_ctx)) {
    cli::cli_alert_info(
      "crm_nhanes_ordinal_pub: 使用筛选 Model2Factors ({length(model2_vars)}): {paste(model2_vars, collapse=', ')}"
    )
  }
  miss_m1 <- setdiff(model1_default, model1_vars)
  miss_m2 <- setdiff(model2_default, model2_vars)
  if (length(miss_m1) && !length(m1_ctx)) {
    cli::cli_alert_warning(
      "crm_nhanes_ordinal_pub: Model1 缺列（原文 age/sex/race）: {paste(miss_m1, collapse=', ')}"
    )
  }
  if (length(miss_m2) && !length(m2_ctx)) {
    cli::cli_alert_warning(
      "crm_nhanes_ordinal_pub: Model2 缺列（相对原文协变量池）: {paste(miss_m2, collapse=', ')}；用可得列拟合。"
    )
  }
  adjust_vars <- model2_vars  # 向后兼容 results 字段

  .crm70o_fmt_or_stars <- function(or, lo, hi, p) {
    or <- suppressWarnings(as.numeric(or))
    lo <- suppressWarnings(as.numeric(lo))
    hi <- suppressWarnings(as.numeric(hi))
    p <- suppressWarnings(as.numeric(p))
    if (!is.finite(or) || !is.finite(lo) || !is.finite(hi)) return("")
    stars <- if (is.finite(p) && p < 0.01) "**" else if (is.finite(p) && p < 0.05) "*" else ""
    sprintf("%.3f (%.3f–%.3f)%s", or, lo, hi, stars)
  }

  .crm70o_cell_from_tab <- function(tab, exposure, model) {
    hit <- tab[tab$Exposure == exposure & tab$Model == model, , drop = FALSE]
    if (!nrow(hit)) return("")
    .crm70o_fmt_or_stars(hit$OR[1L], hit$Lower95[1L], hit$Upper95[1L], hit$P_raw[1L])
  }

  rows <- vector("list", 0L)
  analytic_n_by_exposure <- list()
  for (x in exposures) {
    # Crude/Model1/Model2 共用 Model2 完整病例集，保证三模型可比
    need_cols <- unique(c(y, x, model2_vars, model1_vars, wt_col, psu_col, str_col))
    need_cols <- intersect(need_cols, names(data))
    d <- data[, need_cols, drop = FALSE]
    d[[wt_col]] <- suppressWarnings(as.numeric(d[[wt_col]]))
    d[[x]] <- suppressWarnings(as.numeric(d[[x]]))
    complete_cols <- intersect(c(y, x, model2_vars, wt_col), names(d))
    keep <- stats::complete.cases(d[, complete_cols, drop = FALSE]) & is.finite(d[[wt_col]])
    d <- d[keep, , drop = FALSE]
    d[[y]] <- factor(d[[y]], ordered = TRUE)

    if (!nrow(d) || nlevels(d[[y]]) < 2L) {
      cli::cli_alert_warning(
        "crm_nhanes_ordinal_pub: 暴露 {x} 有效样本不足或 {y} 水平不足 2 个，跳过。"
      )
      next
    }
    design <- .crm70o_build_design(d, wt_col, psu_col, str_col)
    if (is.null(design)) {
      cli::cli_alert_warning("crm_nhanes_ordinal_pub: 暴露 {x} 的 svydesign 构建失败，跳过。")
      next
    }
    analytic_n_by_exposure[[x]] <- nrow(d)

    crude <- .crm70o_fit_and_tidy(design, y, x, character(0), "Crude", nrow(d))
    crude$Exposure <- x; crude$Model <- "Crude"
    model1 <- .crm70o_fit_and_tidy(design, y, x, model1_vars, "Model1", nrow(d))
    model1$Exposure <- x; model1$Model <- "Model1"
    model2 <- .crm70o_fit_and_tidy(design, y, x, model2_vars, "Model2", nrow(d))
    model2$Exposure <- x; model2$Model <- "Model2"
    rows[[length(rows) + 1L]] <- crude
    rows[[length(rows) + 1L]] <- model1
    rows[[length(rows) + 1L]] <- model2
  }

  if (!length(rows)) {
    msg <- "crm_nhanes_ordinal_pub: 所有暴露均未能拟合有效模型。"
    if (.crm70o_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70o_pause(ctx, msg, "检查暴露/协变量/权重列的缺失情况。", data)
    }
    stop(msg, call. = FALSE)
  }

  out_tab <- do.call(rbind, rows)
  out_tab <- out_tab[, c("Exposure", "Model", "Term", "OR", "Lower95", "Upper95", "P", "N")]
  out_tab$OR <- round(out_tab$OR, 3)
  out_tab$Lower95 <- round(out_tab$Lower95, 3)
  out_tab$Upper95 <- round(out_tab$Upper95, 3)
  out_tab$P_raw <- out_tab$P
  out_tab$P <- pub_format_p(out_tab$P)

  # 原文宽表：Characteristic × (Crude / Model 1 / Model 2)，含参考行（无分组标题行）
  ref_cell <- "1.0 (ref)"
  wide_rows <- list()
  if ("SUA" %in% out_tab$Exposure) {
    wide_rows[[length(wide_rows) + 1L]] <- data.frame(
      Characteristic = "Serum uric acid (mg/dL)",
      Crude = .crm70o_cell_from_tab(out_tab, "SUA", "Crude"),
      `Model 1` = .crm70o_cell_from_tab(out_tab, "SUA", "Model1"),
      `Model 2` = .crm70o_cell_from_tab(out_tab, "SUA", "Model2"),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  if ("hyperuricemia" %in% out_tab$Exposure) {
    wide_rows[[length(wide_rows) + 1L]] <- data.frame(
      Characteristic = "Normal control",
      Crude = ref_cell, `Model 1` = ref_cell, `Model 2` = ref_cell,
      check.names = FALSE, stringsAsFactors = FALSE
    )
    wide_rows[[length(wide_rows) + 1L]] <- data.frame(
      Characteristic = "Asymptomatic Hyperuricemia",
      Crude = .crm70o_cell_from_tab(out_tab, "hyperuricemia", "Crude"),
      `Model 1` = .crm70o_cell_from_tab(out_tab, "hyperuricemia", "Model1"),
      `Model 2` = .crm70o_cell_from_tab(out_tab, "hyperuricemia", "Model2"),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  if ("gout" %in% out_tab$Exposure) {
    wide_rows[[length(wide_rows) + 1L]] <- data.frame(
      Characteristic = "Nongout",
      Crude = ref_cell, `Model 1` = ref_cell, `Model 2` = ref_cell,
      check.names = FALSE, stringsAsFactors = FALSE
    )
    wide_rows[[length(wide_rows) + 1L]] <- data.frame(
      Characteristic = "Gout",
      Crude = .crm70o_cell_from_tab(out_tab, "gout", "Crude"),
      `Model 1` = .crm70o_cell_from_tab(out_tab, "gout", "Model1"),
      `Model 2` = .crm70o_cell_from_tab(out_tab, "gout", "Model2"),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  wide_tab <- do.call(rbind, wide_rows)
  rownames(wide_tab) <- NULL

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_2_Ordinal_NHANES.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(out_tab[, setdiff(names(out_tab), "P_raw")], tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_ordinal_pub CSV 写出失败: {e$message}")
  )
  wide_csv <- file.path(tbl_dir, "Table_1_Ordinal_NHANES_wide.csv")
  tryCatch(
    utils::write.csv(wide_tab, wide_csv, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_ordinal_pub wide CSV 写出失败: {e$message}")
  )

  # 正表 Table 1（NHANES-only 连续编号；对应原文 Table 2 宽表）
  pub_xlsx <- as.character(
    bl_cfg$pub_xlsx_filename %||%
      "Table 1-NHANES. Ordinal logistic OR SUA HU gout.xlsx"
  )[1L]
  pub_title <- as.character(
    bl_cfg$pub_title %||%
      "Table 1-NHANES. Association of serum uric acid and gout with CRM conditions"
  )[1L]
  footnotes <- bl_cfg$table_footnotes %||% c(
    "CRM indicates cardiac, renal, and metabolic; NHANES, National Health and Nutrition Examination Survey.",
    paste0(
      "Model 1: Adjusted for age, sex, and race",
      if (length(model1_vars)) paste0(" (used: ", paste(model1_vars, collapse = ", "), ")") else "",
      "."
    ),
    paste0(
      "Model 2: Adjusted for age, sex, race, education, poverty, body mass index, hypertension, smoking status, and triglyceride",
      if (length(model2_vars)) paste0(" (used: ", paste(model2_vars, collapse = ", "), ")") else "",
      "."
    ),
    "*P<0.05; **P<0.01."
  )
  xlsx_path <- file.path(tbl_dir, pub_xlsx)
  if (exists("export_sci_table", mode = "function")) {
    h1 <- c("", "CRM conditions", NA_character_, NA_character_)
    h2 <- c("", "Crude", "Model 1", "Model 2")
    tryCatch(
      export_sci_table(
        wide_tab, xlsx_path, title = pub_title,
        header_row1 = h1, header_row2 = h2,
        latex_include_colnames = FALSE,
        excel_use_prepared = FALSE,
        table_footnotes = footnotes
      ),
      error = function(e) cli::cli_alert_warning("crm_nhanes_ordinal_pub xlsx 导出失败: {e$message}")
    )
  }
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
    mirror_pub_output_to_root(ctx, wide_csv)
    if (file.exists(xlsx_path)) mirror_pub_output_to_root(ctx, xlsx_path)
  }

  # 冒烟对照（默认关闭）：只读调用 57 的薄实现，不影响本块发表产出/不回写 ctx$data
  thin57 <- NULL
  if (isTRUE(bl_cfg$also_run_thin57 %||% FALSE) &&
      exists("block_crm_ordinal_logistic", mode = "function")) {
    thin57 <- tryCatch({
      ctx_copy <- ctx
      ctx_copy <- block_crm_ordinal_logistic(ctx_copy)
      ctx_copy$results$crm_ordinal
    }, error = function(e) {
      cli::cli_alert_warning("crm_nhanes_ordinal_pub: also_run_thin57 冒烟对照失败: {e$message}")
      NULL
    })
  }

  ctx$results$crm_nhanes_ordinal_pub <- list(
    table = out_tab[, setdiff(names(out_tab), "P_raw")],
    table_wide = wide_tab,
    table_raw_p = out_tab,
    exposures = exposures,
    model1_vars = model1_vars,
    model2_vars = model2_vars,
    adjust_vars = adjust_vars,
    gout_available = gout_available,
    analytic_n = analytic_n_by_exposure,
    table_path = tbl_path,
    wide_csv_path = wide_csv,
    pub_xlsx_path = xlsx_path,
    thin57_comparison = thin57
  )
  cli::cli_alert_success(
    "crm_nhanes_ordinal_pub 完成（exposures={paste(exposures, collapse=',')}, model1={paste(model1_vars, collapse=',')}, model2={paste(model2_vars, collapse=',')}, gout_available={gout_available}）"
  )
  ctx
}

register_block(
  "crm_nhanes_ordinal_pub",
  block_crm_nhanes_ordinal_pub,
  "NHANES 加权有序 Logistic 发表宽表（正表 Table 1 / 原文 Table 2：Crude+Model1+Model2）"
)
