###############################################################################
# pub_gallstone_methods.R — 胆结石液电碎石列线图发表方法文案 + 交付收口
# 挂点：run/pub/finalize_delivery_root.R --study-type gallstone
#       run/gallstone_nomogram/rebuild_all_pub_figures_lit.R 末尾
###############################################################################

#' 胆结石列线图 Methods 正文（对齐 Chen JAD 结构；数字须与产物复核）
pub_gallstone_methods_statistical_lines <- function(config = NULL) {
  c(
    "# Statistical analysis（胆结石碎石成功列线图）",
    "",
    "对齐 Chen JAD（10.1177/13872877261424471）主文 Methods 结构；数字均可从本课题产物复核。",
    "",
    "## 1. Study design and participants",
    "",
    "- 结局为数据集记录的碎石是否成功（1 = 成功，0 = 失败）。未另给残石大小或影像时点。",
    "- Analysis set: complete-case N = **273**.",
    "- Split: training : internal validation = **190 : 83**（约 7:3，seed = 42）。",
    "- 无独立外库。Fig7–9 只有训练集与内部验证两栏，不报告 bootstrap。",
    "",
    "## 2. Variables",
    "",
    "- Nomogram predictors: Age; Diameter, cm; Energy, J; Shots. Volume, cm3 只用于 Table 1 与单变量 Fig2/Fig3。",
    "- Baseline / subgroup: Sex, Shape, Color, Surface, Stone type（Favorable/Unfavorable 塌缩，近分离，见 Methods rebuild notes）。",
    "- Exploratory CT features（Table 1 可展示，不进最终列线图）: CT min, HU; CT max, HU; CT <40 HU, %; CT 40-80 HU, %; CT >80 HU, %.",
    "- Dictionary: Table S1 xlsx.",
    "",
    "## 3. Descriptive statistics",
    "",
    "- Table 1: by Success（Overall / No / Yes）；连续 mean (SD)，分类 n (%).",
    "- Table 2: Training vs Validation，同上。",
    "- 连续变量一律 Welch 两样本 t 检验；分类变量 χ²。不混用等方差 t 检验。",
    "- P 值保留 3 位小数；P < 0.001 写 `<0.001`。",
    "- 连续预指定变量（含仅 5 个取值的 Energy, J）**强制按连续变量**汇总，避免误作分类。",
    "",
    "## 4. Association models",
    "",
    "- Continuous exposures in Fig2 and Table S3: OR per 1 SD on the full set N=273, bias-reduced logistic (brglm2).",
    "- Fig5: training set n=190. Odds ratios use clinical steps (age per 10 years, diameter per 0.5 cm, energy per 0.05 J, shots per 50).",
    "- Model 1 = Age（强制）；Model 2 = Age + Sex；Model 3 = Age + Sex + Shape + Color + Surface + Stone type（UV α = 0.05）。",
    "- 准完全分离时优先 brglm2 / Firth 回退（引擎可用时）。",
    "",
    "## 5. Multicollinearity",
    "",
    "- Table S2: VIF on training-set multivariable model of prespecified predictors.",
    "",
    "## 6. Prediction model",
    "",
    "- Shrinkage: ridge（glmnet α = 0），λ chosen by 10-fold CV **λ.1se**（Fig4）。",
    "- 预测变量：Age、Diameter、Energy、Shots。Volume 只出现在 Table 1 与单变量（Fig2/3）；与直径同时调整时 OR 方向反转，故不进 Fig5/Fig6。",
    "- Multivariable display: Fig5 forest（训练集；临床单位缩放 OR）。",
    "- Nomogram: Fig6，系数与 Fig4 ridge λ.1se 一致。",
    "",
    "## 7. Discrimination, calibration, clinical utility",
    "",
    "- Fig3 RCS：唯一取值不少于 8 个时用 4 个结点，否则 3 个结点（能量只有 5 个取值，为 3 个结点）。",
    "- Fig7 AUC 区间为 DeLong 法。不报告 bootstrap AUC。",
    "- Fig8: DCA（Chen 双轴风格）。",
    "- Fig9: CIC（out of 100）。",
    "- Fig7 只报告训练集与内部验证的 DeLong AUC。",
    "",
    "## 8. Subgroup analyses",
    "",
    "- Supplemental Fig S1: Diameter, cm × subgroups + P for interaction.",
    "- Supplemental Fig S2: Shots × subgroups + P for interaction.",
    "- Energy, J 因近分离不进补充主图。",
    "",
    "## Software",
    "",
    "See Methods_software_versions.txt. Key packages: gtsummary, car, glmnet, brglm2, rms, forestploter, ggplot2, patchwork, pROC, openxlsx.",
    ""
  )
}

#' 胆结石 summary_results 交付收口：方法 + 软件版本 + PDF-only 图 + 白名单 prune
gallstone_finalize_summary_delivery <- function(summary_root,
                                                project_root = NULL,
                                                config = NULL,
                                                rewrite_methods = TRUE,
                                                prune = TRUE) {
  summary_root <- as.character(summary_root %||% "")[1L]
  if (!nzchar(summary_root) || !dir.exists(summary_root)) {
    stop("gallstone_finalize_summary_delivery: summary_root 无效: ", summary_root)
  }
  engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(engine) || !dir.exists(file.path(engine, "R"))) {
    engine <- "/mnt/e/01block/01Block-new-Final"
  }
  if (!exists("pub_prune_delivery_root", mode = "function")) {
    source(file.path(engine, "R/pub_delivery_prune.R"), local = FALSE)
  }
  if (!exists("pub_write_software_versions", mode = "function")) {
    source(file.path(engine, "R/pub_software_versions.R"), local = FALSE)
  }
  if (!exists("pub_figure_ensure_formats", mode = "function")) {
    source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
  }

  cfg <- config %||% list()
  if (is.null(cfg$software_versions)) {
    cfg$software_versions <- list(
      extra_pkgs = c(
        "gtsummary", "car", "glmnet", "brglm2", "rms", "forestploter",
        "ggplot2", "patchwork", "pROC", "openxlsx", "png"
      )
    )
  }
  if (is.null(cfg$pub_figures)) {
    cfg$pub_figures <- list(export_png = FALSE, export_tiff = FALSE, dpi = 600L)
  }

  methods_path <- file.path(summary_root, "Methods_statistical_analysis.md")
  if (isTRUE(rewrite_methods) || !file.exists(methods_path)) {
    writeLines(
      pub_gallstone_methods_statistical_lines(cfg),
      methods_path,
      useBytes = TRUE
    )
  }

  std_soft <- file.path(summary_root, "Methods_software_versions.txt")
  proj_soft <- if (nzchar(as.character(project_root %||% "")[1L])) {
    file.path(project_root, "reports", "Methods_software_versions.txt")
  } else {
    ""
  }
  if (nzchar(proj_soft) && file.exists(proj_soft) && !file.exists(std_soft)) {
    file.copy(proj_soft, std_soft, overwrite = FALSE)
  }
  pub_write_software_versions(
    index_root = summary_root,
    project_root = project_root,
    config = cfg
  )

  fig_dir <- file.path(summary_root, "Figures")
  if (dir.exists(fig_dir)) {
    tryCatch(
      pub_figure_ensure_formats(fig_dir, config = cfg),
      error = function(e) message("gallstone ensure_formats: ", conditionMessage(e))
    )
    if (exists("pub_figure_drop_raster_dirs", mode = "function")) {
      tryCatch(
        pub_figure_drop_raster_dirs(fig_dir),
        error = function(e) message("drop_raster: ", conditionMessage(e))
      )
    }
  }

  # Tables 内非 xlsx（Methods_*.txt 等）移出交付面
  if (exists("pub_delivery_clean_tables_xlsx_only", mode = "function")) {
    pub_delivery_clean_tables_xlsx_only(summary_root)
  }
  if (exists("pub_delivery_normalize_fig_tab_dirs", mode = "function")) {
    pub_delivery_normalize_fig_tab_dirs(summary_root)
  }

  # 旧名 Methods_software_section.md 不进白名单
  sec <- file.path(summary_root, "Methods_software_section.md")
  if (file.exists(sec)) unlink(sec)

  res <- NULL
  if (isTRUE(prune) && exists("pub_prune_delivery_root", mode = "function")) {
    res <- pub_prune_delivery_root(summary_root)
  }
  invisible(list(
    summary_root = summary_root,
    methods = file.exists(methods_path),
    software = file.exists(std_soft),
    prune = res
  ))
}
