###############################################################################
#  trajectory_fcimb_delivery_finalize.R — 轨迹预后 fcimb summary_results 交付收口
#
#  全项目复用：禁下划线 + Times New Roman + 文献小数位口径写进 Methods +
#  软件版本 txt + 中期（客户可配、默认可无日期）+ 白名单五件套 prune。
#
#  入口：
#    trajectory_fcimb_finalize_summary_delivery(summary_root, …)
#    CLI: Rscript run/trajectory_prognosis/finalize_fcimb_summary_delivery.R \
#           --dir ".../summary_results" --index WPR --client 天涯 --no-date
#
#  挂点：build_fcimb_summary_results.R 末尾（每次重排 summary 后自动收口）
###############################################################################

#' 文献对齐小数位口径（fcimb / JLCM+PAMM 轨迹预后）
#'
#' 对标 Frontiers CIMB fcimb-16-1871653 及同类轨迹表：
#' - HR / 95% CI：2 位小数（如 7.19 (3.79, 13.64)）
#' - P：3 位或 <0.001 / >0.999（NEJM 可变位亦可）
#' - 描述 mean/SD、%、中位/IQR：最多 2–3 位，去尾随 0
#' - Entropy：3 位；BIC/AIC：整数或 1 位
#' - AUC / C-index：3 位
#' - 人数：千分位逗号
trajectory_fcimb_pub_digits_defaults <- function() {
  list(
    est = 2L,
    p = 3L,
    desc = 2L,
    cutoff = 3L,
    int_big_mark = TRUE,
    desc_trim = TRUE,
    p_style = "nejm"
  )
}

trajectory_fcimb_methods_lines <- function(
    index_lab = "WPR",
    ng = 4L,
    covars = c("CHARLSON", "Age", "RDW", "Neutrophil count"),
    formula_line = NULL) {
  ix <- as.character(index_lab %||% "Index")[1L]
  if (exists("pipeline_display_label", mode = "function")) {
    ix_disp <- pipeline_display_label(ix)
  } else {
    ix_disp <- gsub("_", " ", ix, fixed = TRUE)
  }
  ng <- as.integer(ng %||% 4L)[1L]
  .disp_cov <- function(v) {
    v <- as.character(v)[1L]
    if (exists("pipeline_display_label", mode = "function")) {
      v <- pipeline_display_label(v)
    }
    v <- gsub("_", " ", v, fixed = TRUE)
    # CamelCase 临床列 → 空格展示（禁编程味）
    v <- gsub("NeutrophilCount", "Neutrophil count", v, fixed = TRUE)
    v <- gsub("LymphocytePercent", "Lymphocyte percent", v, fixed = TRUE)
    v
  }
  cov_txt <- paste(vapply(as.character(covars %||% character(0)), .disp_cov, character(1)),
                   collapse = ", ")
  if (!nzchar(cov_txt)) cov_txt <- "CHARLSON, Age, RDW, Neutrophil count"
  formula_line <- as.character(formula_line %||% "")[1L]
  if (!nzchar(formula_line)) {
    if (identical(toupper(ix), "WPR")) {
      formula_line <- "WPR = WBC / Platelet count (unitless ratio; components excluded from adjustment models)."
    } else {
      formula_line <- sprintf("%s formula: see composite index library / Methods footnotes.", ix_disp)
    }
  }

  dig <- trajectory_fcimb_pub_digits_defaults()
  c(
    sprintf("# Statistical analysis (%s trajectory — COPD ICU)", ix_disp),
    "",
    "## Study design",
    "This dual-database trajectory–prognosis study used MIMIC-IV as the derivation cohort and eICU-CRD as the external validation cohort. Eligible adults with COPD admitted to ICU were followed for 28-day in-hospital mortality. Longitudinal white-cell–platelet ratio trajectories were modelled with joint latent class mixed models (JLCM); class membership was linked to mortality with piecewise Cox models, landmark dynamic prediction, and piece-wise exponential additive mixed models (PAMM).",
    "",
    "## Exposure",
    formula_line,
    sprintf("Primary JLCM solution used %d latent classes (BIC among high-entropy candidates after dual-database covariate lock; classes <5%% of the derivation cohort are disclosed). Validation applied discovery parameters without re-estimating mean trajectories. Class-stratified displays report assigned membership (derivation class counts sum to the analytic N; external validation may omit a small number of patients without assignable class under the locked discovery model—disclose panel n in Figure 1 legends when the sum is below the analytic N).", ng),
    "",
    "## Covariates",
    sprintf("Adjusted JLCM, PAMM burden models, and class–mortality models used one locked dual-database set: %s. Lymphocyte percent was unavailable in eICU and was excluded so derivation and validation shared an identical adjustment set. Exposure components were not entered as covariates.", cov_txt),
    "",
    "## Statistical models",
    "JLCM (lcmm) estimated class-specific trajectories and posterior class probabilities. Piecewise Cox models summarized time-dependent class–mortality hazard ratios with an optimally searched cut. Dynamic prediction used Weibull landmark models; discrimination compared dynamic versus static AUC by landmark day. PAMM (pammtools + mgcv) estimated continuous time-varying log-hazard surfaces and exposure-burden associations. Sensitivity analyses repeated JLCM / dynpred / PAMM under a 28-day complete follow-up mortality definition.",
    "",
    "## Reporting digits (literature-aligned)",
    sprintf("Numeric display follows the index literature and project publication rules: hazard ratios and 95%% CIs to %d decimal places; P values to %d decimals or <0.001 / >0.999; descriptive continuous statistics and percentages up to %d decimals with trailing zeros trimmed; AUC / C-index to 3 decimals; entropy to 3 decimals; counts with thousands separators. Display labels use Times New Roman (Liberation Serif fallback) and never show programming underscores.",
            dig$est, dig$p, dig$desc),
    "",
    "## Figure and table order",
    "Delivery numbering follows Frontiers CIMB fcimb-16-1871653 where counterparts exist:",
    "",
    "- Figure 1: trajectory classes (derivation + validation)",
    "- Figure 2: Kaplan–Meier by class (derivation + validation)",
    "- Figure 3: dynamic prediction (MIMIC derivation)",
    "- Figure 4: dynamic prediction (eICU external)",
    "- Figure 5–6: PAMM time-varying association panels",
    "- Figure S1: flowchart",
    "- Figure S2: dynamic versus static time-dependent AUC",
    "- Figure S3: PAMM Days × exposure Log(HR) surface",
    "- Figure S4–S6: sensitivity trajectory / dynpred / PAMM",
    "- Tables 1 / S1–S11: baseline, selection metrics, posterior probabilities, time-dependent HR, exposure burden, class–mortality associations",
    "",
    "## Software",
    "Analyses were performed in R. Core packages included lcmm, survival, pammtools, mgcv, survminer, openxlsx, forestploter, data.table, and ggplot2. Exact versions are listed in Methods software versions.txt."
  )
}

trajectory_fcimb_software_versions_txt <- function() {
  pkgs <- c(
    "lcmm", "survival", "pammtools", "mgcv", "survminer",
    "openxlsx", "forestploter", "data.table", "ggplot2",
    "dplyr", "tidyr", "mice", "cli", "jsonlite"
  )
  vers <- vapply(pkgs, function(p) {
    if (requireNamespace(p, quietly = TRUE)) {
      as.character(utils::packageVersion(p))
    } else {
      "not installed"
    }
  }, character(1))
  c(
    paste0("R ", R.version$version.string),
    paste0(pkgs, " ", vers),
    "Figure fonts: Times New Roman / Liberation Serif (serif fallback).",
    "Publication scrub: underscores removed from tables and figure legends; Times forced on xlsx."
  )
}

#' 写 Methods + 软件版本（覆盖交付根）
trajectory_fcimb_write_methods_software <- function(
    summary_root,
    index_lab = "WPR",
    ng = 4L,
    covars = NULL,
    formula_line = NULL) {
  sr <- as.character(summary_root %||% "")[1L]
  stopifnot(dir.exists(sr))
  md <- trajectory_fcimb_methods_lines(
    index_lab = index_lab, ng = ng, covars = covars, formula_line = formula_line
  )
  writeLines(md, file.path(sr, "Methods_statistical_analysis.md"), useBytes = TRUE)
  writeLines(
    trajectory_fcimb_software_versions_txt(),
    file.path(sr, "Methods_software_versions.txt"),
    useBytes = TRUE
  )
  invisible(list(
    methods = file.path(sr, "Methods_statistical_analysis.md"),
    software = file.path(sr, "Methods_software_versions.txt")
  ))
}

#' 中期：客户可配；默认不写日期
trajectory_fcimb_write_midterm_report <- function(
    summary_root,
    index_lab = "WPR",
    client = "天涯",
    no_date = TRUE,
    ng = 4L,
    outcome_lab = "28天院内死亡",
    methods_lab = "JLCM轨迹、分段Cox、动态预测、PAMM",
    database = "MIMIC-IV、eICU",
    formula_lines = NULL) {
  sr <- as.character(summary_root %||% "")[1L]
  stopifnot(dir.exists(sr))
  ix <- as.character(index_lab %||% "WPR")[1L]
  ix_disp <- if (exists("pipeline_display_label", mode = "function")) {
    pipeline_display_label(ix)
  } else {
    gsub("_", " ", ix, fixed = TRUE)
  }
  client <- as.character(client %||% "天涯")[1L]
  if (!nzchar(client)) client <- "天涯"
  if (is.null(formula_lines) || !length(formula_lines)) {
    formula_lines <- if (identical(toupper(ix), "WPR")) {
      "WPR = WBC / Platelet count"
    } else {
      sprintf("%s（见 Methods）", ix_disp)
    }
  }
  info <- file.path(sr, "项目信息-中期.md")
  .info_lines <- c(
    sprintf("客户: %s", client),
    sprintf("暴露指标: %s", ix_disp),
    sprintf("结局: %s", outcome_lab),
    sprintf("报告标题: %s轨迹类别与%s的关联分析", ix_disp, outcome_lab),
    "标题副题: 中期分析结果",
    sprintf("研究人群: COPD ICU 患者（发现集 MIMIC-IV；外验 eICU）"),
    sprintf("分析方法: %s（主分析 %d 类）", methods_lab, as.integer(ng)[1L]),
    sprintf("数据集: %s", database),
    "类型: 中期分析结果",
    sprintf("指标计算公式: %s", paste(formula_lines, collapse = "；")),
    if (isTRUE(no_date)) "分析日期: 无" else NULL,
    if (isTRUE(no_date)) "日期: 无" else NULL,
    ""
  )
  .txt_body <- paste(enc2utf8(as.character(.info_lines)), collapse = "\n")
  if (!grepl("\n$", .txt_body)) .txt_body <- paste0(.txt_body, "\n")
  writeBin(charToRaw(.txt_body), info)

  # 校验（若有 CKM helper）
  .py_v <- Sys.which("python3")
  if (!nzchar(.py_v)) .py_v <- Sys.which("python")
  .helper <- file.path(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final"),
    "python", "ckm_midterm_validate_info.py"
  )
  if (nzchar(.py_v) && file.exists(.helper)) {
    .st_v <- tryCatch(
      system2(.py_v, c(.helper, info, if (isTRUE(no_date)) "--no-date" else NULL),
              stdout = TRUE, stderr = TRUE),
      error = function(e) structure(conditionMessage(e), status = 1L)
    )
    .v_ok <- is.null(attr(.st_v, "status")) || identical(as.integer(attr(.st_v, "status")), 0L)
    if (!isTRUE(.v_ok)) {
      warning("midterm info validate: ", paste(utils::tail(.st_v, 4), collapse = " | "))
    }
  }

  tabs <- list.files(file.path(sr, "Tables"), pattern = "\\.xlsx$", full.names = FALSE)
  pdf_dir <- file.path(sr, "Figures", "pdf")
  figs <- if (dir.exists(pdf_dir)) {
    list.files(pdf_dir, pattern = "\\.pdf$", full.names = FALSE)
  } else {
    list.files(file.path(sr, "Figures"), pattern = "\\.pdf$", full.names = FALSE)
  }
  .pick <- function(pats, pool) {
    for (p in pats) {
      hit <- pool[grepl(p, pool, ignore.case = TRUE)]
      if (length(hit)) return(hit[[1L]])
    }
    NA_character_
  }
  sec <- function(title, table = NULL, figure = NULL, caption = "", annotation = "") {
    out <- list(title = title, caption = caption, annotation = annotation)
    if (!is.null(table) && !is.na(table)) out$table <- table
    if (!is.null(figure) && !is.na(figure)) out$figure <- figure
    out
  }
  body <- list()
  f1 <- .pick("^Figure 1\\.", figs)
  f2 <- .pick("^Figure 2\\.", figs)
  f3 <- .pick("^Figure 3\\.", figs)
  f4 <- .pick("^Figure 4\\.", figs)
  f5 <- .pick("^Figure 5\\.", figs)
  f6 <- .pick("^Figure 6\\.", figs)
  t1 <- .pick("^Table 1\\.", tabs)
  if (!is.na(f1)) body[[length(body) + 1L]] <- sec("轨迹类别", figure = f1, caption = sprintf("%s 潜类别轨迹", ix_disp), annotation = sprintf("主分析 %d 类；发现集+外验。", as.integer(ng)[1L]))
  if (!is.na(t1)) body[[length(body) + 1L]] <- sec("基线特征", table = t1, caption = "基线特征", annotation = "发现集与外验队列对照。")
  if (!is.na(f2)) body[[length(body) + 1L]] <- sec("生存曲线", figure = f2, caption = "按轨迹类 KM", annotation = "28 天院内死亡；分段 landmark。")
  if (!is.na(f3)) body[[length(body) + 1L]] <- sec("动态预测（发现集）", figure = f3, caption = "动态预测", annotation = "MIMIC landmark 动态预测。")
  if (!is.na(f4)) body[[length(body) + 1L]] <- sec("动态预测（外验）", figure = f4, caption = "动态预测", annotation = "eICU 外验。")
  if (!is.na(f5)) body[[length(body) + 1L]] <- sec("PAMM（发现集）", figure = f5, caption = "PAMM 时变关联", annotation = "发现集四面板。")
  if (!is.na(f6)) body[[length(body) + 1L]] <- sec("PAMM（外验）", figure = f6, caption = "PAMM 时变关联", annotation = "外验四面板。")
  for (lab in c("S7", "S8", "S9", "S10", "S11")) {
    tb <- .pick(sprintf("^Table %s\\.", lab), tabs)
    if (!is.na(tb)) {
      body[[length(body) + 1L]] <- sec(
        sprintf("补充表 %s", lab), table = tb, caption = lab,
        annotation = "数值口径见 Methods（HR 2 位小数）。"
      )
    }
  }
  supp <- list()
  for (k in 1:6) {
    fs <- .pick(sprintf("^Figure S%d\\.", k), figs)
    if (!is.na(fs)) {
      supp[[length(supp) + 1L]] <- sec(
        sprintf("附图 S%d", k), figure = fs, caption = sprintf("Figure S%d", k),
        annotation = "敏感性或补充图。"
      )
    }
  }
  chapters <- list(
    list(
      title = "研究背景与方法摘要",
      intro = list(
        sprintf("基于 MIMIC-IV（发现）与 eICU（外验），评估 COPD ICU 患者 %s 纵向轨迹类别与 28 天院内死亡的关联。主分析 JLCM 锁定 %d 类。", ix_disp, as.integer(ng)[1L]),
        sprintf("调整集：%s。非人工智能预测模型。", "CHARLSON、Age、RDW、Neutrophil count")
      ),
      formula = as.list(formula_lines)
    ),
    list(title = "主要结果", sections = body)
  )
  if (length(supp)) chapters[[length(chapters) + 1L]] <- list(title = "补充分析", sections = supp)
  content <- list(
    exclude_figures = list(),
    abbreviations = list(
      list(缩写词 = "WPR", 对应英文 = "White blood cell to Platelet Ratio", 对应中文 = "白细胞/血小板比值", 单位 = ""),
      list(缩写词 = "JLCM", 对应英文 = "Joint Latent Class Mixed model", 对应中文 = "联合潜类别混合模型", 单位 = ""),
      list(缩写词 = "PAMM", 对应英文 = "Piece-wise exponential Additive Mixed Model", 对应中文 = "分段指数可加混合模型", 单位 = ""),
      list(缩写词 = "HR", 对应英文 = "Hazard Ratio", 对应中文 = "风险比", 单位 = ""),
      list(缩写词 = "CI", 对应英文 = "Confidence Interval", 对应中文 = "置信区间", 单位 = ""),
      list(缩写词 = "MIMIC", 对应英文 = "Medical Information Mart for Intensive Care", 对应中文 = "重症监护医学信息集市", 单位 = ""),
      list(缩写词 = "eICU", 对应英文 = "eICU Collaborative Research Database", 对应中文 = "eICU 协作研究数据库", 单位 = "")
    ),
    chapters = chapters
  )
  cj <- file.path(sr, "content.json")
  jsonlite::write_json(content, cj, auto_unbox = TRUE, pretty = TRUE)

  root_eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
  eng <- file.path(root_eng, ".cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py")
  launcher <- file.path(root_eng, "python", "ckm_midterm_build.py")
  if (!file.exists(eng)) {
    warning("midterm engine missing: ", eng)
    return(invisible(list(info = info, content = cj, pdf = NA_character_)))
  }
  ix_fn <- gsub("[[:space:]]+", "-", ix_disp)
  out_pdf <- file.path(
    sr,
    sprintf("%s_%s_中期分析结果.pdf", ix_fn, gsub("[[:space:]]+", "", outcome_lab))
  )
  .old_mid <- list.files(sr, pattern = "\u4e2d\u671f.*\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (length(.old_mid)) unlink(.old_mid, force = TRUE)
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  .run_mid <- function(mode) {
    .old <- Sys.getenv(c(
      "CKM_MIDTERM_ENGINE", "CKM_MIDTERM_PROJECT",
      "CKM_MIDTERM_CONTENT", "CKM_MIDTERM_OUT"
    ), unset = NA_character_)
    on.exit({
      for (nm in names(.old)) {
        if (is.na(.old[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, setNames(list(.old[[nm]]), nm))
      }
    }, add = TRUE)
    Sys.setenv(
      CKM_MIDTERM_ENGINE = eng,
      CKM_MIDTERM_PROJECT = sr,
      CKM_MIDTERM_CONTENT = cj,
      CKM_MIDTERM_OUT = out_pdf
    )
    if (file.exists(launcher)) {
      system2(py, c(launcher, mode), stdout = TRUE, stderr = TRUE)
    } else {
      system2(py, c(eng, paste0("--", mode), "--project", sr, "--content", cj, "--out", out_pdf),
              stdout = TRUE, stderr = TRUE)
    }
  }
  try(.run_mid("inspect"), silent = TRUE)
  st <- .run_mid("build")
  ok <- file.exists(out_pdf)
  if (!ok) {
    warning("midterm build failed: ", paste(utils::tail(st, 40), collapse = "\n"))
  } else {
    message("midterm PDF → ", out_pdf)
    # 封面硬检：no_date 时禁止「分析日期」；禁止退化「与的」
    .pdftotext <- Sys.which("pdftotext")
    if (nzchar(.pdftotext)) {
      .cover <- tryCatch(
        paste(system2(.pdftotext, c("-f", "1", "-l", "1", "-layout", out_pdf, "-"),
                      stdout = TRUE, stderr = FALSE), collapse = "\n"),
        error = function(e) ""
      )
      if (grepl("与的", .cover, fixed = TRUE)) {
        warning("midterm cover looks degraded (与的); check 项目信息-中期.md")
      }
      if (isTRUE(no_date) && grepl("分析日期", .cover, fixed = TRUE)) {
        warning("midterm cover still shows 分析日期 despite no_date=TRUE")
      }
    }
  }
  invisible(list(info = info, content = cj, pdf = if (ok) out_pdf else NA_character_, log = st))
}

#' 一键交付收口（scrub → Methods/software → 可选中期 → prune）
trajectory_fcimb_finalize_summary_delivery <- function(
    summary_root,
    index_lab = "WPR",
    ng = 4L,
    covars = c("CHARLSON", "Age", "RDW", "NeutrophilCount"),
    client = "天涯",
    no_date = TRUE,
    write_midterm = TRUE,
    formula_line = NULL,
    root = NULL) {
  sr <- as.character(summary_root %||% "")[1L]
  stopifnot(dir.exists(sr))
  eng <- as.character(root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""))[1L]
  if (!nzchar(eng) || !dir.exists(file.path(eng, "R"))) {
    eng <- "/mnt/e/01block/01Block-new-Final"
  }
  Sys.setenv(MEDICAL_BLOCKS_ROOT = eng)
  for (f in c(
    "R/utils.R", "R/pub_delivery_prune.R", "R/pub_figure_export.R",
    "R/pub_xlsx_surgical.R", "R/pub_xlsx_force_times.R"
  )) {
    p <- file.path(eng, f)
    if (file.exists(p)) try(source(p, local = FALSE), silent = TRUE)
  }

  # 1) 图四目录
  fig <- file.path(sr, "Figures")
  if (dir.exists(fig) && exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(
        fig,
        config = list(pub_figures = list(export_png = FALSE, export_tiff = FALSE))
      ),
      error = function(e) warning("ensure_formats: ", conditionMessage(e))
    )
  }

  # 2) 展示 scrub（禁下划线 + Times）
  scrub <- list()
  if (exists("pub_delivery_scrub_display", mode = "function")) {
    scrub <- tryCatch(
      pub_delivery_scrub_display(sr, root = eng),
      error = function(e) list(error = conditionMessage(e))
    )
  }

  # 3) Methods + software
  meth <- trajectory_fcimb_write_methods_software(
    sr, index_lab = index_lab, ng = ng, covars = covars, formula_line = formula_line
  )

  # 4) 中期
  mid <- NULL
  if (isTRUE(write_midterm)) {
    mid <- tryCatch(
      trajectory_fcimb_write_midterm_report(
        sr, index_lab = index_lab, client = client, no_date = no_date, ng = ng
      ),
      error = function(e) {
        warning("midterm: ", conditionMessage(e))
        list(error = conditionMessage(e))
      }
    )
  }

  # 5) 白名单 prune（中期后再剪一次）
  pruned <- NULL
  if (exists("pub_prune_delivery_root", mode = "function")) {
    pruned <- tryCatch(
      pub_prune_delivery_root(sr),
      error = function(e) list(error = conditionMessage(e))
    )
  }

  invisible(list(
    summary_root = normalizePath(sr, winslash = "/", mustWork = FALSE),
    scrub = scrub,
    methods = meth,
    midterm = mid,
    pruned = pruned
  ))
}
