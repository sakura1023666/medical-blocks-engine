###############################################################################
#  crm_nhanes_baseline_weighted — NHANES 复杂抽样加权基线特征表（对应文献 Table S4）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data      = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）
#  requires_packages = c("survey")
#
#  说明（变量口径证据链）：本块不臆造原文 Table S4 的确切变量清单——默认变量池为
#  常见人口学/暴露候选（Age/Gender/Race/Education/... + SUA/hyperuricemia/gout/eGFR）
#  与当前数据列名求交集；若交集不足 2 个，退化为自动探测数据中除 ID/权重/设计/
#  死亡链接/结局/CRM 分层变量外的前 max_auto_vars 列，并在
#  ctx$results$crm_nhanes_baseline_weighted$auto_detected 中标记 TRUE，供下游/报告
#  识别为"自动探测口径，非文献确证清单"。CVD/CKD/Diabetes 三个 CRM_count 的直接
#  构成分量默认从变量池中剔除，避免与分层变量同义重复。
#
#  crm_nhanes_baseline_weighted = list(
#    strata_var       = "CRM_count",   # 分层变量（原文 Table S4 口径；也可设为暴露变量）
#    weight_col       = NULL,          # NULL → config$nhanes$survey_weight %||% "new_Weight"
#    cluster_col      = NULL,          # NULL → config$nhanes$survey_cluster %||% "SDMVPSU"
#    strata_col       = NULL,          # NULL → config$nhanes$survey_strata %||% "SDMVSTRA"
#    vars             = NULL,          # NULL → 默认候选池 ∩ 数据列；不足则自动探测
#    max_auto_vars    = 40L,
#    categorical_max_levels = 10L,
#    table_filename   = "Table_S4_Baseline_NHANES.csv",   # 固定名（文献 Table S4）
#    table_title      = NULL,          # NULL → 默认标题
#    pause_enable            = TRUE,
#    pause_on_missing_design = TRUE,
#    pause_on_no_vars        = TRUE
#  )
#
#  register_block: "crm_nhanes_baseline_weighted"
#  典型位置: crm_nhanes_derive → crm_nhanes_flowchart → crm_nhanes_baseline_weighted → ...
#
#  读: ctx$data$cleaned %||% ctx$data$raw；config$nhanes（权重/聚类/分层列名）
#  写: ctx$results$crm_nhanes_baseline_weighted
#
#  产出: [固定名] Tables/Table_S4_Baseline_NHANES.csv（+ 尝试 export_sci_table 生成 .xlsx）
#
#  方法: survey::svydesign(ids=SDMVPSU, strata=SDMVSTRA, weights=new_Weight, nest=TRUE)
#  （聚类/分层列缺失时退化为仅权重设计）；分层子集用 subset() 做域估计（domain
#  estimation），复用完整设计的方差结构，避免子集重建设计导致 lonely PSU 问题。
#  连续变量: svymean/svyvar 或 svyquantile（按 test_variable_normality 判定 Mean\u00b1SD
#  或 Median (Q1,Q3)）；分类变量: svymean 加权百分比 + 未加权 n。组间比较：连续变量用
#  svyglm + regTermTest（因子化分层变量的整体 F 检验）；分类变量用 svychisq
#  （Rao-Scott 调整）。
#
#  pause: config$crm_nhanes_baseline_weighted$pause_enable
###############################################################################

.crm70b_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70b_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_baseline_weighted",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_baseline_weighted halted. See ctx$results$pause_point. / ",
    "NHANES 加权基线表异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

.crm70b_default_vars <- function() {
  c(
    "Age", "Gender", "Race", "Education", "Marital_Status", "Income",
    "Smoking", "Alcohol_drinking", "BMI", "Hypertension",
    "SUA", "hyperuricemia", "gout", "eGFR"
  )
}

.crm70b_is_categorical <- function(x, max_levels = 10L) {
  if (is.factor(x) || is.character(x) || is.logical(x)) return(TRUE)
  if (is.numeric(x)) {
    ux <- unique(x[!is.na(x)])
    return(length(ux) <= max_levels)
  }
  FALSE
}

.crm70b_subset_by_level <- function(design, strata_var, level) {
  expr <- bquote(subset(design, .(as.name(strata_var)) == .(level)))
  eval(expr)
}

.crm70b_pvalue_continuous <- function(design, var, strata_var) {
  form <- stats::as.formula(paste0(var, " ~ factor(", strata_var, ")"))
  fit <- tryCatch(survey::svyglm(form, design = design), error = function(e) NULL)
  if (is.null(fit)) return(NA_real_)
  rt <- tryCatch(
    survey::regTermTest(fit, paste0("factor(", strata_var, ")")),
    error = function(e) NULL
  )
  if (is.null(rt) || is.null(rt$p)) return(NA_real_)
  as.numeric(rt$p)[1L]
}

.crm70b_pvalue_categorical <- function(design, var, strata_var) {
  form <- stats::as.formula(paste0("~", var, "+", strata_var))
  res <- tryCatch(survey::svychisq(form, design = design), error = function(e) NULL)
  if (is.null(res) || is.null(res$p.value)) return(NA_real_)
  as.numeric(res$p.value)[1L]
}

block_crm_nhanes_baseline_weighted <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(cli)
  })
  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_baseline_weighted %||% list()
  nh_cfg <- cfg$nhanes %||% list()

  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    if (.crm70b_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .crm70b_pause(ctx, "未找到分析数据（ctx$data$cleaned 与 raw 均为空）。",
                   "请先运行 crm_nhanes_derive。", NULL)
    }
    stop("crm_nhanes_baseline_weighted: 无分析数据。", call. = FALSE)
  }

  if (!requireNamespace("survey", quietly = TRUE)) {
    if (.crm70b_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .crm70b_pause(ctx, "缺少 R 包 survey，无法构建加权基线表。",
                   "安装 survey 后重试，或设 pause_on_missing_design = FALSE。", NULL)
    }
    stop("crm_nhanes_baseline_weighted: 缺少 survey 包。", call. = FALSE)
  }
  suppressPackageStartupMessages(library(survey, warn.conflicts = FALSE))
  options(survey.lonely.psu = "adjust")

  strata_var <- as.character(bl_cfg$strata_var %||% "CRM_count")[1L]
  wt_col <- as.character(bl_cfg$weight_col %||% nh_cfg$survey_weight %||% "new_Weight")[1L]
  psu_col <- as.character(bl_cfg$cluster_col %||% nh_cfg$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(bl_cfg$strata_col %||% nh_cfg$survey_strata %||% "SDMVSTRA")[1L]
  cat_max_levels <- suppressWarnings(as.integer(bl_cfg$categorical_max_levels %||% 10L))[1L]
  if (!is.finite(cat_max_levels) || cat_max_levels < 2L) cat_max_levels <- 10L

  if (!strata_var %in% names(data) || !wt_col %in% names(data)) {
    msg <- paste0(
      "crm_nhanes_baseline_weighted: 数据缺少分层变量 ", strata_var,
      " 或权重列 ", wt_col, "。"
    )
    if (.crm70b_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .crm70b_pause(ctx, msg, "请先运行 crm_nhanes_derive；检查 config$nhanes$survey_weight。", data)
    }
    stop(msg, call. = FALSE)
  }

  d <- data
  d[[wt_col]] <- suppressWarnings(as.numeric(d[[wt_col]]))
  d <- d[!is.na(d[[strata_var]]) & is.finite(d[[wt_col]]) & !is.na(d[[wt_col]]), , drop = FALSE]
  d[[strata_var]] <- factor(d[[strata_var]])

  if (!nrow(d) || nlevels(d[[strata_var]]) < 2L) {
    msg <- "crm_nhanes_baseline_weighted: 有效样本不足或分层变量水平不足 2 个。"
    if (.crm70b_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .crm70b_pause(ctx, msg, "检查 CRM_count 分布与权重缺失情况。", d)
    }
    stop(msg, call. = FALSE)
  }

  crm_components <- c("CVD", "CKD", "Diabetes")
  exclude_cols <- unique(c(
    "SEQN", "seqn", wt_col, psu_col, str_col, "WTMEC2YR", "WTINT2YR",
    "eligstat", "mortstat", "permth_int", "futime", "fustatus",
    strata_var, if (identical(strata_var, "CRM_count")) crm_components else character(0)
  ))

  vars_cfg <- bl_cfg$vars
  auto_detected <- FALSE
  if (!is.null(vars_cfg) && length(vars_cfg)) {
    vars <- intersect(as.character(vars_cfg), names(d))
  } else {
    vars <- setdiff(intersect(.crm70b_default_vars(), names(d)), exclude_cols)
    if (length(vars) < 2L) {
      auto_detected <- TRUE
      cand <- setdiff(names(d), exclude_cols)
      max_auto <- suppressWarnings(as.integer(bl_cfg$max_auto_vars %||% 40L))[1L]
      if (!is.finite(max_auto) || max_auto < 1L) max_auto <- 40L
      vars <- utils::head(cand, max_auto)
      cli::cli_alert_warning(
        "crm_nhanes_baseline_weighted: 默认候选变量池与数据交集不足，退化为自动探测前 {length(vars)} 列（非文献确证 Table S4 清单，见 auto_detected）。"
      )
    }
  }
  vars <- vars[vars %in% names(d) & !vars %in% exclude_cols]
  vars <- vars[!vapply(vars, function(v) all(is.na(d[[v]])), logical(1L))]

  if (!length(vars)) {
    msg <- "crm_nhanes_baseline_weighted: 未能解析任何基线变量。"
    if (.crm70b_should_pause(bl_cfg, "pause_on_no_vars", TRUE)) {
      .crm70b_pause(ctx, msg, "在 config$crm_nhanes_baseline_weighted$vars 中显式指定变量。", d)
    }
    stop(msg, call. = FALSE)
  }

  is_cat <- stats::setNames(
    vapply(vars, function(v) .crm70b_is_categorical(d[[v]], cat_max_levels), logical(1L)),
    vars
  )
  for (v in vars[is_cat]) d[[v]] <- factor(d[[v]])

  has_design_cols <- all(c(psu_col, str_col) %in% names(d))
  design <- tryCatch({
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
  if (is.null(design)) {
    msg <- "crm_nhanes_baseline_weighted: survey::svydesign 构建失败。"
    if (.crm70b_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .crm70b_pause(ctx, msg, "检查权重/聚类/分层列格式是否为数值/因子。", d)
    }
    stop(msg, call. = FALSE)
  }

  lvls <- levels(d[[strata_var]])
  sub_designs <- lapply(lvls, function(l) {
    tryCatch(.crm70b_subset_by_level(design, strata_var, l), error = function(e) NULL)
  })
  names(sub_designs) <- lvls
  ok_lvls <- lvls[!vapply(sub_designs, is.null, logical(1L))]
  if (length(ok_lvls) < 2L) {
    msg <- "crm_nhanes_baseline_weighted: 分层子集设计构建失败（<2 个可用水平）。"
    if (.crm70b_should_pause(bl_cfg, "pause_on_missing_design", TRUE)) {
      .crm70b_pause(ctx, msg, "检查分层变量取值与样本量。", d)
    }
    stop(msg, call. = FALSE)
  }

  n_unw_by_lvl <- table(d[[strata_var]])

  rows <- vector("list", length(vars))
  for (i in seq_along(vars)) {
    v <- vars[i]
    if (isTRUE(is_cat[[v]])) {
      lv <- levels(d[[v]])
      pval <- suppressWarnings(.crm70b_pvalue_categorical(design, v, strata_var))
      for (j in seq_along(lv)) {
        overall_cell <- tryCatch(
          fmt_categorical_level_svy(design, v, lv[j]),
          error = function(e) NA_character_
        )
        grp_cells <- lapply(ok_lvls, function(l) {
          tryCatch(fmt_categorical_level_svy(sub_designs[[l]], v, lv[j]), error = function(e) NA_character_)
        })
        names(grp_cells) <- ok_lvls
        rows[[length(rows) + 1L]] <- data.frame(
          Variable = v,
          Level = lv[j],
          Type = "categorical",
          Overall = overall_cell,
          stats::setNames(as.list(unlist(grp_cells)), paste0(strata_var, "_", ok_lvls)),
          P_value = if (j == 1L) pub_format_p(pval) else "",
          stringsAsFactors = FALSE
        )
      }
    } else {
      is_normal <- tryCatch(test_variable_normality(d[[v]]), error = function(e) TRUE)
      overall_cell <- tryCatch(
        fmt_continuous_svy(design, v, is_normal),
        error = function(e) NA_character_
      )
      grp_cells <- lapply(ok_lvls, function(l) {
        tryCatch(fmt_continuous_svy(sub_designs[[l]], v, is_normal), error = function(e) NA_character_)
      })
      names(grp_cells) <- ok_lvls
      pval <- suppressWarnings(.crm70b_pvalue_continuous(design, v, strata_var))
      rows[[length(rows) + 1L]] <- data.frame(
        Variable = v,
        Level = if (isTRUE(is_normal)) "Mean (SD)" else "Median (Q1, Q3)",
        Type = "continuous",
        Overall = overall_cell,
        stats::setNames(as.list(unlist(grp_cells)), paste0(strata_var, "_", ok_lvls)),
        P_value = pub_format_p(pval),
        stringsAsFactors = FALSE
      )
    }
  }
  rows <- rows[!vapply(rows, is.null, logical(1L))]
  out_tab <- do.call(rbind, rows)

  header_row <- data.frame(
    Variable = "N (unweighted)",
    Level = "",
    Type = "header",
    Overall = as.character(nrow(d)),
    stats::setNames(
      as.list(as.character(vapply(ok_lvls, function(l) as.integer(n_unw_by_lvl[[l]] %||% 0L), integer(1L)))),
      paste0(strata_var, "_", ok_lvls)
    ),
    P_value = "",
    stringsAsFactors = FALSE
  )
  out_tab <- rbind(header_row, out_tab)

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_S4_Baseline_NHANES.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tbl_title <- as.character(bl_cfg$table_title %||%
    paste0(
      "Table S4. Weighted baseline characteristics of NHANES participants by ",
      strata_var
    ))[1L]

  if (exists("export_sci_table", mode = "function")) {
    xlsx_path <- sub("\\.csv$", ".xlsx", tbl_path, ignore.case = TRUE)
    tryCatch(
      export_sci_table(out_tab, xlsx_path, title = tbl_title),
      error = function(e) cli::cli_alert_warning("crm_nhanes_baseline_weighted xlsx 导出失败: {e$message}")
    )
  }
  tryCatch(
    utils::write.csv(out_tab, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_baseline_weighted CSV 写出失败: {e$message}")
  )
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
  }

  ctx$results$crm_nhanes_baseline_weighted <- list(
    table = out_tab,
    strata_var = strata_var,
    vars = vars,
    auto_detected = auto_detected,
    weight_col = wt_col,
    design_cols_available = has_design_cols,
    n = nrow(d),
    table_path = tbl_path
  )
  cli::cli_alert_success(
    "crm_nhanes_baseline_weighted 完成（n={nrow(d)}, vars={length(vars)}, strata={strata_var}, auto_detected={auto_detected}）"
  )
  ctx
}

register_block(
  "crm_nhanes_baseline_weighted",
  block_crm_nhanes_baseline_weighted,
  "NHANES 复杂抽样加权基线特征表（Table S4）"
)
