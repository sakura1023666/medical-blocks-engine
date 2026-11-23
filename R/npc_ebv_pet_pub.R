###############################################################################
#  npc_ebv_pet_pub — EBV×PET 联合预后发表收口（引擎级）
#
#  交付面：summary_results/ 仅留
#    Figures/ Tables/ Methods_statistical_analysis.md
#    Methods_software_versions.txt / *中期*.pdf
#
#  展示铁律：禁下划线、Times New Roman、pub_digits 口径
###############################################################################

#' EBV×PET 联合分析 Methods 文案（与本课题重建口径一致）
npc_ebv_pet_methods_statistical_lines <- function(config = NULL) {
  cfg <- if (is.list(config)) config else list()
  n_a <- suppressWarnings(as.integer(cfg$n_cohort_a %||% 412L)[1L])
  n_b <- suppressWarnings(as.integer(cfg$n_cohort_b %||% 391L)[1L])
  lam_a <- as.character(cfg$lambda_a %||% "0.03")[1L]
  lam_b <- as.character(cfg$lambda_b %||% "5")[1L]
  c(
    "# Statistical analysis",
    "",
    "## Study design and cohorts",
    paste0(
      "This delivery is an independent R rebuild of EBV DNA × PET/CT joint prognostic analyses ",
      "for nasopharyngeal carcinoma. Cohort A included all spreadsheet-eligible patients ",
      "(N = ", format(n_a, big.mark = ","), ", including IVB/M1). ",
      "Cohort B restricted to include==1 non-metastatic analytic patients ",
      "(N = ", format(n_b, big.mark = ","), "). ",
      "Primary endpoints were overall survival (OS), progression-free survival (PFS), ",
      "distant metastasis (DM; competing death), DM or death (DM+D), and locoregional relapse (LR)."
    ),
    "",
    "## EBV DNA coding and PET markers",
    paste0(
      "Baseline circulating EBV DNA used assay-specific limit of detection (LOD)–relative coding: ",
      "below-LOD values were coded as 0 on the LOD-relative score; detectable values were scaled ",
      "relative to the assay LOD. Binary T0 positivity (T0+) and continuous T0 score were analysed ",
      "alongside PET volumetric/metabolic markers (including log2(1+x) transforms of nodal MTV, ",
      "TLG, and related measures as labelled in table footnotes). Sensitivity coding used BLQ=LOD/2 ",
      "and unified-LOD variants where tabulated."
    ),
    "",
    "## Regression and nested discrimination",
    paste0(
      "Associations used Cox models (Breslow ties). Penalised ridge Cox nested models ",
      "(clinical / EBV / PET / joint families; EP2X included an EBV×PET interaction) used ",
      "cohort-specific ridge penalties (Cohort A λ = ", lam_a, "; Cohort B λ = ", lam_b, "). ",
      "Out-of-fold (OOF) discrimination used event-stratified 5-fold × 8 repeats ",
      "(induction-chemotherapy leave-one-out ×6 where applicable). ",
      "Time-dependent discrimination and calibration used inverse-probability-of-censoring ",
      "weighted (IPCW) AUC and Brier scores at 24 and 36 months. ",
      "Paired bootstrap contrasts used 800 resamples (landmark trajectory increments 1000) ",
      "with re-estimated censoring weights."
    ),
    "",
    "## Competing risk, landmark, holdout, and utility",
    paste0(
      "For DM/LR, cumulative incidence functions and cause-specific versus Fine–Gray hazard ",
      "ratios were reported. Quadrant analyses crossed EBV-high with PET thresholds ",
      "(TLG > 65 or NTR > 0.64) with RERI tabulation. Landmark analyses evaluated +T2 and ",
      "trajectory-tier increments at 6/9/12 months. Temporal holdout trained on diagnosis ",
      "year ≤2022 and tested 2023–2025. A 6-parameter Cox linear predictor was min–max ",
      "scaled to a 0–100 risk score (cuts 45.9 / 58.71) for strata and decision-curve panels. ",
      "Additional sensitivities covered stage III–IVA restriction, TLG checks, R–D leakage, ",
      "and induction-chemotherapy leave-one-out."
    ),
    "",
    "## Publication digits, fonts, and display",
    paste0(
      "Reporting digits follow the engine `pub_digits` defaults: hazard ratios / OR / CI to ",
      "3 decimal places (trailing zeros retained); AUC / Brier / probability metrics to 3 ",
      "decimals (values with |x| < 0.001 shown as <0.001); P values use fixed 3 decimals with ",
      "<0.001 / >0.999 (never bare 0 or 0.000); descriptive means/SD/% use up to 3 decimals ",
      "with trailing-zero trim; integers use thousands separators in published tables. ",
      "Display labels omit programming underscores. Figure text and table fonts use ",
      "Times New Roman (Times-family fallback on Linux)."
    ),
    "",
    "## Software",
    "Analyses were performed in R. Package versions are listed in Methods_software_versions.txt and the Software subsection below.",
    "",
    "## Limitations",
    paste0(
      "This is a single-centre observational rebuild; external multi-centre validation was not ",
      "performed here. Digits are recomputed from the analysis workbook and are not forced to ",
      "match prior report headlines. Temporal holdout and OOF metrics should be interpreted as ",
      "internal validation under the stated sampling scheme."
    ),
    ""
  )
}

#' 将草稿交付同步到 summary_results 并完成 scrub / Methods / 软件 / 白名单
#'
#' @param draft_root 通常为 summary（new）
#' @param summary_root 客户交付根 summary_results
npc_ebv_pet_finalize_summary_delivery <- function(
    draft_root,
    summary_root = NULL,
    project_root = NULL,
    rewrite_methods = TRUE,
    prune = TRUE,
    sync_draft = TRUE
) {
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(eng) || !dir.exists(file.path(eng, "R"))) {
    eng <- "/mnt/e/01block/01Block-new-Final"
  }
  for (f in c(
    "R/utils.R", "R/pub_delivery_prune.R", "R/pub_software_versions.R",
    "R/pub_figure_export.R", "R/pub_xlsx_surgical.R", "R/pub_xlsx_force_times.R"
  )) {
    p <- file.path(eng, f)
    if (file.exists(p)) {
      tryCatch(source(p, local = FALSE), error = function(e) NULL)
    }
  }

  draft_root <- normalizePath(as.character(draft_root)[1L], winslash = "/", mustWork = TRUE)
  if (is.null(summary_root) || !nzchar(as.character(summary_root)[1L])) {
    summary_root <- file.path(dirname(draft_root), "summary_results")
  }
  summary_root <- as.character(summary_root)[1L]
  dir.create(summary_root, FALSE, TRUE)
  summary_root <- normalizePath(summary_root, winslash = "/", mustWork = TRUE)

  if (isTRUE(sync_draft) && !identical(draft_root, summary_root)) {
    # archive prior summary_results non-whitelist noise via prune later; refresh Figs/Tables
    for (sub in c("Figures", "Tables")) {
      src <- file.path(draft_root, sub)
      dst <- file.path(summary_root, sub)
      if (!dir.exists(src)) next
      if (dir.exists(dst)) unlink(dst, recursive = TRUE)
      dir.create(dirname(dst), FALSE, TRUE)
      ok <- FALSE
      if (nzchar(Sys.which("rsync"))) {
        st <- system2("rsync", c("-a", "--delete", paste0(src, "/"), paste0(dst, "/")))
        ok <- identical(as.integer(st), 0L)
      }
      if (!isTRUE(ok)) {
        dir.create(dst, FALSE, TRUE)
        file.copy(list.files(src, full.names = TRUE), dst, recursive = TRUE, overwrite = TRUE)
      }
    }
  }

  # scrub display on both roots (draft stays aligned)
  for (root_i in unique(c(draft_root, summary_root))) {
    if (exists("pub_delivery_normalize_fig_tab_dirs", mode = "function")) {
      tryCatch(pub_delivery_normalize_fig_tab_dirs(root_i), error = function(e) NULL)
    }
    if (exists("pub_delivery_scrub_display", mode = "function")) {
      tryCatch(
        pub_delivery_scrub_display(root_i, root = eng),
        error = function(e) warning("scrub: ", conditionMessage(e), call. = FALSE)
      )
    }
    if (exists("pub_delivery_force_tables_times", mode = "function")) {
      tryCatch(pub_delivery_force_tables_times(root_i), error = function(e) NULL)
    } else if (exists("pub_xlsx_force_times_fonts", mode = "function")) {
      tabs <- list.files(file.path(root_i, "Tables"), pattern = "\\.xlsx$", full.names = TRUE)
      for (tb in tabs) {
        tryCatch(pub_xlsx_force_times_fonts(tb), error = function(e) NULL)
      }
    }
    if (exists("pub_figure_ensure_formats", mode = "function")) {
      fig <- file.path(root_i, "Figures")
      if (dir.exists(fig)) {
        tryCatch(
          pub_figure_ensure_formats(
            fig,
            config = list(pub_figures = list(
              export_png = FALSE, export_tiff = FALSE, dpi = 600L,
              max_edge_in = 16, require_vector_pdf = TRUE
            ))
          ),
          error = function(e) NULL
        )
      }
    }
  }

  soft_cfg <- list(
    project = list(study_type = "npc_ebv_pet"),
    software_versions = list(
      extra_pkgs = c(
        "survival", "glmnet", "cmprsk", "ggplot2", "patchwork",
        "openxlsx", "dplyr", "scales", "timeROC"
      ),
      include_python = FALSE,
      exclude_pkgs = c(
        "mice", "survminer", "mediation", "Boruta", "tableone",
        "jstable", "Hmisc", "forestploter", "pROC"
      )
    )
  )

  if (isTRUE(rewrite_methods)) {
    md <- npc_ebv_pet_methods_statistical_lines(list(
      n_cohort_a = 412L, n_cohort_b = 391L, lambda_a = "0.03", lambda_b = "5"
    ))
    writeLines(md, file.path(summary_root, "Methods_statistical_analysis.md"), useBytes = TRUE)
    writeLines(md, file.path(draft_root, "Methods_statistical_analysis.md"), useBytes = TRUE)
  }

  if (exists("pub_write_software_versions", mode = "function")) {
    pub_write_software_versions(index_root = summary_root, project_root = project_root, config = soft_cfg)
    soft_src <- file.path(summary_root, "Methods_software_versions.txt")
    soft_dst <- file.path(draft_root, "Methods_software_versions.txt")
    if (file.exists(soft_src) &&
        !identical(normalizePath(soft_src, winslash = "/", mustWork = FALSE),
                   normalizePath(soft_dst, winslash = "/", mustWork = FALSE))) {
      file.copy(soft_src, soft_dst, overwrite = TRUE)
    }
  }
  if (exists("pub_write_methods_software_section", mode = "function")) {
    soft_tmp <- tempfile(fileext = ".md")
    roles <- c(
      survival = "Cox / Kaplan-Meier",
      glmnet = "Ridge / penalised Cox",
      cmprsk = "Competing-risk CIF / Fine-Gray",
      timeROC = "IPCW time-dependent AUC",
      ggplot2 = "Publication figures",
      patchwork = "Multi-panel layout",
      openxlsx = "SCI three-line tables"
    )
    tryCatch(
      pub_write_methods_software_section(
        soft_tmp,
        roles = roles,
        extra_pkgs = soft_cfg$software_versions$extra_pkgs,
        exclude_pkgs = soft_cfg$software_versions$exclude_pkgs
      ),
      error = function(e) NULL
    )
    if (file.exists(soft_tmp)) {
      for (root_i in unique(c(summary_root, draft_root))) {
        md_path <- file.path(root_i, "Methods_statistical_analysis.md")
        if (!file.exists(md_path)) next
        body <- readLines(md_path, warn = FALSE, encoding = "UTF-8")
        # drop prior Software subsection if present
        hit <- grep("^## Software\\s*$", body)
        if (length(hit)) {
          # keep through Limitations if Software was injected mid-file; rewrite cleanly
          lim <- grep("^## Limitations\\s*$", body)
          if (length(lim) && lim[[1]] > hit[[1]]) {
            body <- c(body[seq_len(hit[[1]] - 1L)], body[lim[[1]]:length(body)])
          } else {
            body <- body[seq_len(hit[[1]] - 1L)]
          }
        }
        soft_md <- readLines(soft_tmp, warn = FALSE, encoding = "UTF-8")
        # insert Software before Limitations
        lim2 <- grep("^## Limitations\\s*$", body)
        if (length(lim2)) {
          body <- c(body[seq_len(lim2[[1]] - 1L)], soft_md, "", body[lim2[[1]]:length(body)])
        } else {
          body <- c(body, "", soft_md)
        }
        writeLines(body, md_path, useBytes = TRUE)
      }
    }
  }

  # midterm 项目信息模板（不进白名单交付根；供 Aiya-NB004 中期合成）
  ws <- file.path(dirname(summary_root), "summary_results_delivery_workspace")
  dir.create(ws, FALSE, TRUE)
  mid_info <- file.path(ws, "项目信息-中期.md")
  if (!file.exists(mid_info)) {
    writeLines(
      c(
        "客户: 马晶鑫",
        "暴露指标: EBV DNA × PET/CT 联合指标",
        "结局: OS / PFS / DM / DM+D / LR",
        "研究人群: 鼻咽癌患者（队列A含IVB/M1；队列B非转移分析集）",
        "数据集: 自有数据",
        "分析方法: Ridge Cox / OOF IPCW-AUC / 竞争风险 / Landmark / 时间外验",
        "类型: 中期分析结果",
        "报告标题: EBV DNA与PET/CT联合指标对鼻咽癌预后的关联与预测分析",
        "标题副题: 无",
        "分析日期: ",
        "指标计算公式: T0 score = LOD-relative EBV DNA coding（低于LOD记0；可检出值相对assay LOD缩放）；PET体积代谢指标对连续变量使用 log2(1+x) 变换（见表注）",
        "表格路径: Tables",
        "图片路径: Figures"
      ),
      mid_info,
      useBytes = TRUE
    )
  }

  # drop non-whitelist docs from summary_results (PUBLICATION_LAYOUT etc.)
  if (isTRUE(prune) && exists("pub_prune_delivery_root", mode = "function")) {
    pub_prune_delivery_root(summary_root, dry_run = FALSE)
  }

  invisible(list(
    draft = draft_root,
    summary = summary_root,
    methods = file.exists(file.path(summary_root, "Methods_statistical_analysis.md")),
    software = file.exists(file.path(summary_root, "Methods_software_versions.txt")),
    midterm_info = mid_info
  ))
}
