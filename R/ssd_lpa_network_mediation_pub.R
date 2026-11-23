###############################################################################
#  SSD LPA / network / mediation 发表收口（引擎级）
#
#  挂点：run/ssd_lpa_network_mediation/finalize_ssd_summary_delivery.R
#  每次跑完本课题 summary_results 必须：
#    1) 展示层禁下划线 + Times New Roman（pub_delivery_scrub_display）
#    2) 小数位对齐寄望文献 Ma 2026 Acta Psychologica（见 ssd_pub_digits）
#    3) 写 Methods_statistical_analysis.md + Methods_software_versions.txt（无日期戳）
#    4) pub_prune_delivery_root：根目录只留 Figures/Tables/Methods*/中期 PDF
###############################################################################

#' 寄望文献（Ma 2026 Acta Psychologica）发表数字口径
#'
#' 对标原文 Table 1–6：
#' - 百分比 / 描述：最多 2 位（如 41.36）；整数人数不写 .00
#' - OR / 效应量 / CI：固定 3 位（如 0.202）
#' - P：固定 3 位；极小写 <0.001（优于原文 0.000）
#' - AIC/BIC：2 位；Entropy / AUC / ACME：3 位
#' - 人数：默认不加千分位逗号（与门诊 n<1000 原文一致）
ssd_pub_digits <- function() {
  list(
    est = 3L,
    p = 3L,
    desc = 2L,
    cutoff = 3L,
    int_big_mark = FALSE,
    desc_trim = TRUE,
    p_style = "fixed"
  )
}

#' 应用 SSD 发表数字口径到全局 / config
ssd_apply_pub_digits <- function(config = NULL) {
  dig <- ssd_pub_digits()
  if (exists("pipeline_apply_pub_digits", mode = "function")) {
    if (is.null(config)) config <- list()
    config$pub_digits <- dig
    pipeline_apply_pub_digits(config)
  } else {
    options(
      medical_blocks.pub_digits.est = dig$est,
      medical_blocks.pub_digits.p = dig$p,
      medical_blocks.pub_digits.desc = dig$desc,
      medical_blocks.pub_digits.cutoff = dig$cutoff,
      medical_blocks.pub_digits.int_big_mark = dig$int_big_mark,
      medical_blocks.pub_digits.desc_trim = dig$desc_trim,
      medical_blocks.pub_digits.p_style = dig$p_style
    )
  }
  invisible(dig)
}

#' 写软件版本清单（不含生成日期，避免交付面日期漂移）
ssd_write_software_versions <- function(path) {
  pkgs <- c(
    "poLCA", "lavaan", "mediation", "bootnet", "qgraph", "pROC",
    "ggplot2", "openxlsx", "mice", "cli"
  )
  lines <- c(
    paste0("R: ", R.version$version.string),
    "",
    "Packages:"
  )
  for (p in pkgs) {
    lines <- c(lines, paste0(
      "  ", p, ": ",
      tryCatch(as.character(utils::packageVersion(p)), error = function(e) "NA")
    ))
  }
  lines <- c(
    lines,
    "",
    "Display / publication:",
    "  Tables font: Times New Roman (pub_delivery_scrub_display)",
    "  Figures font: Times / Liberation Serif (resolve_plot_font_family)",
    "  Digits: ssd_pub_digits() aligned with Ma 2026 Acta Psychologica"
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path)
  invisible(path)
}

#' 写统计分析 Methods（正文 + 补充编号；Common-Sense Model）
ssd_write_methods_md <- function(path, n_total = 699L, n_lca = 698L, best_k = 3L, entropy = NA_real_) {
  ent_txt <- if (is.finite(entropy)) sprintf(" (relative entropy ≈ %.3f)", entropy) else ""
  lines <- c(
    "# Statistical analysis",
    "",
    "## Study design and cohort",
    "",
    paste0(
      "This was a cross-sectional analysis of general-hospital outpatient questionnaire data ",
      "(N = ", format(n_total, big.mark = ","), " after cleaning). ",
      "The analytic goal was to evaluate whether the association between somatic symptom burden ",
      "(PHQ-15; SSS-8 in sensitivity analyses) and functional disability (WHO-DAS 12) is accounted for ",
      "by parallel mediators of illness-related cognitive–affective representations (SSD-12 and Whiteley-8), ",
      "alongside latent class analysis (LCA) of WHO-DAS items and class-stratified psychological networks. ",
      "Estimates are associations under the stated models; causal language is avoided."
    ),
    "",
    "## Theoretical framing (Common-Sense Model)",
    "",
    paste0(
      "Analyses are interpreted under a Common-Sense / symptom-perception framework: ",
      "somatic symptom burden may impair functioning directly and/or via illness-related cognitive paths. ",
      "The scientific claim emphasizes which cognitive path dominates (SSD-12 vs Whiteley-8) and for whom ",
      "(class and moderator heterogeneity), not merely that mediation exists."
    ),
    "",
    "## Measures and scoring",
    "",
    paste0(
      "Likert responses were mapped to numeric scores and summed: PHQ-15 (0–2), SSS-8 (0–4), ",
      "SSD-12 (0–4), Whiteley-8 (0–4), WHO-DAS 12 (0–4), PHQ-9 and GAD-7 (0–3). ",
      "Item-level category codes were retained for LCA and CFA. ",
      "All twelve WHO-DAS items (DAS1–DAS12) were available for LCA; domain summaries used the standard six-domain pairing."
    ),
    "",
    "## Latent class analysis",
    "",
    paste0(
      "Primary classification used polytomous latent class analysis (R package poLCA) on WHO-DAS ",
      "items (complete cases; n = ", format(n_lca, big.mark = ","), "), treating Likert responses as categorical indicators. ",
      "Candidate solutions K = 1–5 were fitted with multiple random starts. Model selection combined BIC ",
      "(lower better) with minimum class size (n ≥ 30; proportion ≥ 0.04) and rejection of degenerate solutions. ",
      "The selected solution was K = ", best_k, ent_txt, ". ",
      "Subsequent baseline, network, and stratified displays used this LCA membership."
    ),
    "",
    "## Psychological networks",
    "",
    paste0(
      "EBICglasso networks (qgraph; γ = 0.5) were estimated within each LCA class using seven scale totals ",
      "(PHQ-15, SSS-8, SSD-12, Whiteley-8, WHO-DAS, PHQ-9, GAD-7). Node centrality indices ",
      "(Betweenness, Closeness, Strength, Expected Influence) were computed as z-scores within class. ",
      "Case-drop bootstrap summarized correlation stability (CS) for strength."
    ),
    "",
    "## Parallel competing mediation",
    "",
    paste0(
      "Two paths were estimated: PHQ-15 → SSD-12 → WHO-DAS and PHQ-15 → Whiteley-8 → WHO-DAS, ",
      "adjusted for age, sex, education, marriage, income, and livingsite. Rare factor levels (n < 15) ",
      "were collapsed. Primary inference used nonparametric bootstrap of the product-of-coefficients ",
      "(percentile 95% CI). The contrast ACME(SSD-12) − ACME(Whiteley-8) used the same bootstrap scheme. ",
      "Class-specific ACMEs were compared for path diagrams (Figure 4)."
    ),
    "",
    "## Supplementary analyses",
    "",
    paste0(
      "Supplementary tables/figures (not main text) cover: WHO-DAS domain profiles; CFA discriminant validity ",
      "and measurement invariance; multi-group path SEM; formal moderated mediation and stratified ACME; ",
      "SSS-8 exposure and ±depression/anxiety sensitivity; competing/reverse models; ROC/DCA; ",
      "objective visit burden (N12AA) and employment-related outcomes; FIML/MICE sensitivity; ",
      "FDR-adjusted correlations; and qualitative functional subtypes from domain k-means. ",
      "Named instruments for alexithymia, catastrophizing, and childhood trauma were unavailable."
    ),
    "",
    "## Clinical threshold analyses",
    "",
    "ROC curves (pROC) and decision-curve analysis treated WHO-DAS median split as the binary label; ",
    "predictors were SSD-12, Whiteley-8, PHQ-15, and SSS-8.",
    "",
    "## Missing data",
    "",
    "Primary analyses used complete cases. Supplementary sensitivity used lavaan FIML and mice (m = 5) with Rubin pooling for path-defined effects.",
    "",
    "## Numerical reporting",
    "",
    paste0(
      "Display digits follow the index-style reporting of Ma et al. (2026, Acta Psychologica): ",
      "effect estimates and confidence intervals to three decimals; P values to three decimals ",
      "(values <0.001 reported as <0.001); descriptive percentages up to two decimals; ",
      "information criteria to two decimals; entropy/AUC/ACME to three decimals. ",
      "Engine lock: ssd_pub_digits()."
    ),
    "",
    "## Software",
    "",
    paste0(
      "Analyses were run in ", R.version$version.string, ". ",
      "Key packages: poLCA, lavaan, mediation, bootnet, qgraph, pROC, ggplot2, openxlsx, mice. ",
      "See the accompanying software versions file."
    ),
    "",
    "## Main-text versus supplementary numbering",
    "",
    "Main text: Tables 1–6 and Figures 1–4. All other tables/figures are supplementary (Tables S1–S7; Figures S1–S3).",
    ""
  )
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(lines, path)
  invisible(path)
}

#' SSD summary_results 发表收口（scrub → Methods → versions → prune）
#'
#' @param summary_root summary_results 绝对路径
#' @param engine_root Medical Blocks 仓库根
#' @param midterm_pdf 可选：已生成的中期 PDF 路径（复制进 summary_root）
#' @param run_struct_qc 是否调用结构 QC CLI（报告写入同级 workspace，不进交付根）
ssd_finalize_summary_delivery <- function(summary_root,
                                          engine_root = NULL,
                                          midterm_pdf = NULL,
                                          run_struct_qc = TRUE) {
  summary_root <- normalizePath(as.character(summary_root)[1L], winslash = "/", mustWork = TRUE)
  eng <- as.character(engine_root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""))[1L]
  if (!nzchar(eng)) eng <- getwd()
  for (f in c(
    "R/utils.R", "R/pub_figure_export.R", "R/pub_delivery_prune.R",
    "R/pub_xlsx_surgical.R", "R/pub_xlsx_force_times.R"
  )) {
    p <- file.path(eng, f)
    if (file.exists(p)) tryCatch(source(p, local = FALSE), error = function(e) NULL)
  }
  ssd_apply_pub_digits()

  # scrub underscores + Times + three-line
  if (exists("pub_delivery_scrub_display", mode = "function")) {
    tryCatch(
      pub_delivery_scrub_display(summary_root, root = eng),
      error = function(e) warning("pub_delivery_scrub_display: ", conditionMessage(e))
    )
  }

  # HTML entity cleanup in xlsx / md (arrows, dashes).
  # NEVER unescape &lt;/&gt; into raw < > — that breaks OOXML sharedStrings / sheet XML.
  .scrub_entities <- function(txt) {
    txt <- gsub("&#8594;", " to ", txt, fixed = TRUE)
    txt <- gsub("&#8211;", "-", txt, fixed = TRUE)
    txt <- gsub("&#20840;&#38754;&#21463;&#25439;&#21462;&#21521;", "pervasive high disability", txt, fixed = TRUE)
    txt
  }
  tab <- file.path(summary_root, "Tables")
  if (dir.exists(tab) && exists("pub_xlsx_edit_cells", mode = "function")) {
    for (xf in list.files(tab, pattern = "\\.xlsx$", full.names = TRUE)) {
      a1 <- tryCatch(
        as.character(openxlsx::read.xlsx(xf, colNames = FALSE, rows = 1, cols = 1)[1, 1]),
        error = function(e) NA_character_
      )
      if (!is.na(a1) && grepl("&#|&lt;|&gt;", a1)) {
        tryCatch(
          pub_xlsx_edit_cells(xf, data.frame(row = 1L, col = 1L, value = .scrub_entities(a1), stringsAsFactors = FALSE)),
          error = function(e) NULL
        )
      }
    }
  }
  md_dir <- file.path(summary_root, "Figures", "image_information")
  if (dir.exists(md_dir)) {
    for (mf in list.files(md_dir, pattern = "\\.md$", full.names = TRUE)) {
      lines <- readLines(mf, warn = FALSE)
      lines2 <- vapply(lines, .scrub_entities, character(1), USE.NAMES = FALSE)
      lines2 <- gsub("centrality_auto", "centrality auto", lines2, fixed = TRUE)
      lines2 <- gsub("_", " ", lines2, fixed = FALSE) # last-resort display scrub in md only if leftover programming tokens
      # undo over-scrub of markdown headers? only replace known bad tokens above; revert blanket _
      # safer: only known tokens
      lines2 <- readLines(mf, warn = FALSE)
      lines2 <- vapply(lines2, .scrub_entities, character(1), USE.NAMES = FALSE)
      lines2 <- gsub("centrality_auto", "centrality auto", lines2, fixed = TRUE)
      writeLines(lines2, mf)
    }
  }

  # Methods + software versions (no date stamp)
  ssd_write_methods_md(file.path(summary_root, "Methods_statistical_analysis.md"))
  ssd_write_software_versions(file.path(summary_root, "Methods_software_versions.txt"))

  # ensure figure formats
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(file.path(summary_root, "Figures"), config = list(
        pub_figures = list(export_png = FALSE, export_tiff = FALSE)
      )),
      error = function(e) NULL
    )
  }

  # optional midterm copy-in (skip if already in summary_root)
  if (!is.null(midterm_pdf) && file.exists(midterm_pdf)) {
    dest_mt <- file.path(summary_root, basename(midterm_pdf))
    if (!identical(normalizePath(midterm_pdf, winslash = "/", mustWork = FALSE),
                   normalizePath(dest_mt, winslash = "/", mustWork = FALSE))) {
      file.copy(midterm_pdf, dest_mt, overwrite = TRUE)
    }
  }

  # structural QC → archive dir (not delivery root)
  if (isTRUE(run_struct_qc)) {
    qc <- file.path(eng, "run/pub/run_pub_qc_after_project.R")
    if (file.exists(qc)) {
      ws <- paste0(summary_root, "_delivery_workspace")
      dir.create(ws, recursive = TRUE, showWarnings = FALSE)
      out <- tryCatch(
        system2("Rscript", c(qc, "--project", summary_root), stdout = TRUE, stderr = TRUE),
        error = function(e) conditionMessage(e)
      )
      writeLines(as.character(out), file.path(ws, "pub_qc_stdout.txt"))
    }
  }

  # prune whitelist
  if (exists("pub_prune_delivery_root", mode = "function")) {
    tryCatch(
      pub_prune_delivery_root(summary_root),
      error = function(e) warning("pub_prune_delivery_root: ", conditionMessage(e))
    )
  }

  invisible(summary_root)
}
