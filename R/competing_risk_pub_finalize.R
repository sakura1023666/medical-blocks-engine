# Competing-risk (Lai-style) unit-level summary_results finalize
# 单库：文件名/表题去 -DB；禁下划线；Times；Methods + 软件版本；白名单 prune
# 小数位对齐 Lai Cardiovasc Diabetol 2025（PMID 40119388 / 12933_2025_2687）

#' Lai 竞争风险发表小数位（引擎默认，可被 config$pub_digits 覆盖）
#'
#' 文献口径（摘要 + MOESM）：
#' - HR / 95% CI：保留 **2** 位（如 2.40 (1.35-3.28)）；偶见补表 1 位不强制
#' - P 值：固定 **3** 位；极小写成 `<0.001`（禁止裸 0 / 0.000）
#' - 描述统计（连续）：最多 **1** 位 + trim（如 Age 74.0；整数可不写 .0）
#' - 百分比：通常 **1** 位（如 39.9%）
#' - 人数：整数；≥4 位千分位逗号（与全项目 int_big_mark 一致）
competing_lai_pub_digits <- function() {
  list(
    est = 2L,
    p = 3L,
    p_style = "fixed",
    desc = 1L,
    desc_trim = TRUE,
    cutoff = 3L,
    int_big_mark = TRUE,
    pct = 1L,
    source = "Lai_CardiovascDiabetol_2025_PMID40119388"
  )
}

#' 将 Lai 小数位写入 config（缺省补齐；不覆盖用户显式 pub_digits）
competing_apply_lai_pub_digits <- function(config) {
  if (!is.list(config)) return(config)
  d <- competing_lai_pub_digits()
  user <- config$pub_digits %||% list()
  for (nm in names(d)) {
    if (is.null(user[[nm]])) user[[nm]] <- d[[nm]]
  }
  config$pub_digits <- user
  if (exists("pipeline_apply_pub_digits", mode = "function")) {
    pipeline_apply_pub_digits(config)
  }
  config
}

#' Methods 文案（竞争风险 · Fine-Gray / 轨迹）
competing_write_methods_md <- function(path,
                                       exposure = "index",
                                       primary_event = "CRRT",
                                       competing_event = "death",
                                       horizon_days = 28L,
                                       database = "MIMIC",
                                       digits_note = TRUE) {
  exposure <- as.character(exposure %||% "index")[1L]
  primary_event <- as.character(primary_event %||% "primary event")[1L]
  competing_event <- as.character(competing_event %||% "death")[1L]
  horizon_days <- as.integer(horizon_days %||% 28L)[1L]
  database <- as.character(database %||% "MIMIC")[1L]
  dig <- competing_lai_pub_digits()
  lines <- c(
    "# Statistical analysis",
    "",
    sprintf(
      "This competing-risk analysis used the %s database. The primary event was %s within %d days; %s was treated as a competing event. Exposure was modeled as baseline %s quartiles and as longitudinal %s trajectory classes derived from linear mixed models / clustering.",
      database, primary_event, horizon_days, competing_event, exposure, exposure
    ),
    "",
    "Fine-Gray subdistribution hazard models and cause-specific Cox models were fit at pre-specified horizons (typically 7, 14, and 28 days). Model 1 was unadjusted; Model 2 adjusted for age; Model 3 further adjusted for severity and clinical covariates selected by the analysis pipeline (reported in table/figure footnotes). Cumulative incidence functions with risk tables, restricted cubic splines, and subgroup analyses were generated as supporting outputs. Standard Cox models (ignoring competing risks) were reported as sensitivity analyses.",
    "",
    "Missing covariates were handled with multiple imputation by chained equations (MICE; m = 5). Operational tables and figures used the first completed dataset; inferential regressions pooled across imputations with Rubin's rules when enabled.",
    ""
  )
  if (isTRUE(digits_note)) {
    lines <- c(
      lines,
      "## Numeric reporting",
      "",
      sprintf(
        "Reporting digits follow the Lai competing-risk template (Cardiovasc Diabetol 2025): hazard ratios and confidence intervals to %d decimal places; P values to %d decimal places (values <0.001 reported as <0.001); continuous descriptive statistics up to %d decimal place with trailing zeros trimmed; percentages typically 1 decimal place; counts as integers with thousands separators when ≥4 digits.",
        dig$est, dig$p, dig$desc
      ),
      ""
    )
  }
  lines <- c(
    lines,
    "## Software",
    "",
    "See Methods_software_versions.txt."
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(enc2utf8(lines), path, useBytes = TRUE)
  invisible(path)
}

#' 从单库 unit 成功目录组装 summary_results（去库名、展示 scrub、Methods、prune）
#'
#' @param unit_root 如 .../MIMIC/by_unit/【success】GAR
#' @param config 课题 config（读 database / exposure / midterm / pub）
#' @param summary_dirname 默认 "summary_results"
competing_finalize_unit_summary_results <- function(unit_root,
                                                    config = NULL,
                                                    summary_dirname = "summary_results",
                                                    strip_db_tags = TRUE,
                                                    write_methods = TRUE,
                                                    prune = TRUE) {
  unit_root <- as.character(unit_root %||% "")[1L]
  if (!nzchar(unit_root) || !dir.exists(unit_root)) {
    stop("competing_finalize_unit_summary_results: unit_root missing: ", unit_root, call. = FALSE)
  }
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(eng) || !dir.exists(file.path(eng, "R"))) {
    eng <- "/mnt/e/01block/01Block-new-Final"
  }
  for (rel in c(
    "R/utils.R", "R/pub_delivery_prune.R", "R/pub_figure_export.R",
    "R/pub_xlsx_surgical.R", "R/ml_index_summary_results.R",
    "R/pub_software_versions.R", "R/pub_xlsx_force_times.R"
  )) {
    p <- file.path(eng, rel)
    if (file.exists(p)) try(source(p, local = FALSE), silent = TRUE)
  }

  config <- competing_apply_lai_pub_digits(config %||% list())
  cr <- config$competing %||% list()
  pr <- config$project %||% list()
  db <- as.character(pr$database %||% "MIMIC")[1L]
  exposure <- as.character(
    config$project$exposure_var %||%
      cr$index_var %||%
      basename(gsub("【success】|【failed】", "", unit_root))
  )[1L]
  primary <- as.character(cr$primary_event_label %||% "CRRT")[1L]
  competing_ev <- as.character(cr$competing_event_label %||% "death")[1L]
  horizon <- as.integer(cr$horizon_days %||% config$competing_risk$horizon %||% 28L)[1L]

  sum_root <- file.path(unit_root, as.character(summary_dirname %||% "summary_results")[1L])
  tab_src <- file.path(unit_root, "Tables")
  fig_src <- file.path(unit_root, "Figures")
  if (!dir.exists(tab_src)) stop("no Tables under unit_root: ", unit_root, call. = FALSE)

  tab_dest <- file.path(sum_root, "Tables")
  fig_dest <- file.path(sum_root, "Figures")
  if (dir.exists(sum_root)) {
    unlink(sum_root, recursive = TRUE)
  }
  dir.create(tab_dest, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dest, recursive = TRUE, showWarnings = FALSE)

  # Tables: Lai whitelist Table 1–4 + S1–S6
  tabs <- list.files(tab_src, pattern = "\\.xlsx$", full.names = TRUE)
  keep_tab <- grepl("^Table [1-4]-|^Table S[1-6]-|^Table [1-4]\\.|^Table S[1-6]\\.", basename(tabs))
  tabs <- tabs[keep_tab]
  for (f in tabs) {
    file.copy(f, file.path(tab_dest, basename(f)), overwrite = TRUE)
  }

  # Figures: prefer pdf/ subdir Figure 1–9
  pdf_src <- if (dir.exists(file.path(fig_src, "pdf"))) file.path(fig_src, "pdf") else fig_src
  figs <- list.files(pdf_src, pattern = "^Figure [1-9].*\\.pdf$", full.names = TRUE)
  for (f in figs) {
    file.copy(f, file.path(fig_dest, basename(f)), overwrite = TRUE)
  }

  # 单库去 -DB 标签
  if (isTRUE(strip_db_tags) && exists("pub_strip_db_tags_from_delivery", mode = "function")) {
    tryCatch(
      pub_strip_db_tags_from_delivery(sum_root, config = config, db_tags = db),
      error = function(e) warning("strip db tags: ", conditionMessage(e), call. = FALSE)
    )
  }

  # 四目录 + image_information
  if (exists("export_pub_figures", mode = "function")) {
    tryCatch(
      export_pub_figures(
        fig_dest,
        meta = list(
          exposure = exposure,
          outcome = paste(primary, "/", competing_ev),
          databases = db,
          combined = FALSE
        ),
        config = config
      ),
      error = function(e) warning("export_pub_figures: ", conditionMessage(e), call. = FALSE)
    )
  } else if (exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(fig_dest, config = config),
      error = function(e) warning("pub_figure_ensure_formats: ", conditionMessage(e), call. = FALSE)
    )
  }

  # A1 = 文件名 stem
  if (exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
    try(pub_sync_xlsx_a1_titles_to_filenames(tab_dest), silent = TRUE)
  } else if (exists("pub_xlsx_edit_cells", mode = "function")) {
    for (f in list.files(tab_dest, pattern = "\\.xlsx$", full.names = TRUE)) {
      stem <- sub("\\.xlsx$", "", basename(f))
      try(
        pub_xlsx_edit_cells(f, data.frame(row = 1L, col = 1L, value = stem, stringsAsFactors = FALSE)),
        silent = TRUE
      )
    }
  }

  if (isTRUE(write_methods)) {
    competing_write_methods_md(
      file.path(sum_root, "Methods_statistical_analysis.md"),
      exposure = exposure,
      primary_event = primary,
      competing_event = competing_ev,
      horizon_days = horizon,
      database = db
    )
    if (exists("pub_write_software_versions", mode = "function")) {
      tryCatch(
        pub_write_software_versions(sum_root, project_root = NULL, config = config),
        error = function(e) {
          writeLines(
            c("R / survival / cmprsk / mice / ggplot2 (see session at analysis time)"),
            file.path(sum_root, "Methods_software_versions.txt")
          )
        }
      )
    }
  }

  # 禁下划线 + Times
  if (exists("pub_delivery_scrub_display", mode = "function")) {
    tryCatch(
      pub_delivery_scrub_display(sum_root, root = eng),
      error = function(e) warning("pub_delivery_scrub_display: ", conditionMessage(e), call. = FALSE)
    )
  }
  if (exists("pub_delivery_force_tables_times", mode = "function")) {
    tryCatch(
      pub_delivery_force_tables_times(sum_root),
      error = function(e) warning("Times force: ", conditionMessage(e), call. = FALSE)
    )
  }

  if (isTRUE(prune) && exists("pub_prune_delivery_root", mode = "function")) {
    try(pub_prune_delivery_root(sum_root), silent = TRUE)
  }

  message("competing summary_results ready: ", sum_root)
  invisible(sum_root)
}

#' 写中期项目信息（客户名 + 无日期）并可选调用外部 midterm skill
competing_write_midterm_project_info <- function(summary_root,
                                                 exposure = "GAR",
                                                 client = "静",
                                                 no_date = TRUE,
                                                 database = "MIMIC",
                                                 outcome_lab = "28-day CRRT (competing with death)",
                                                 formula_txt = NULL) {
  sr <- as.character(summary_root %||% "")[1L]
  stopifnot(dir.exists(sr))
  exposure <- as.character(exposure %||% "index")[1L]
  client <- as.character(client %||% "静")[1L]
  if (!nzchar(client)) client <- "静"
  if (is.null(formula_txt) || !nzchar(as.character(formula_txt)[1L])) {
    formula_txt <- sprintf("%s = glucose / albumin (see Methods)", exposure)
  }
  info <- file.path(sr, "项目信息-中期.md")
  lines <- c(
    sprintf("客户: %s", client),
    sprintf("暴露指标: %s", exposure),
    sprintf("结局: %s", outcome_lab),
    sprintf("报告标题: %s与AKI患者28天CRRT竞争风险分析", exposure),
    "标题副题: 中期分析结果",
    sprintf("研究人群: ICU成人AKI患者"),
    "分析方法: Fine-Gray竞争风险、轨迹聚类、Cox敏感性",
    sprintf("数据集: %s", database),
    "类型: 中期分析结果",
    sprintf("指标计算公式: %s", formula_txt),
    if (isTRUE(no_date)) "分析日期: 无" else NULL,
    if (isTRUE(no_date)) "日期: 无" else NULL,
    ""
  )
  txt <- paste(enc2utf8(as.character(lines)), collapse = "\n")
  if (!grepl("\n$", txt)) txt <- paste0(txt, "\n")
  writeBin(charToRaw(txt), info)
  invisible(info)
}
