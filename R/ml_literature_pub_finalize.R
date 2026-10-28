###############################################################################
#  ml_literature_pub_finalize — ML 文献终稿收口（全项目复用）
#
#  适用：publication_literature_final / summary_result（SOSM+WPR / SAR+CrCV 等）
#  铁律：重编号填空号 → Methods md + 软件版本 txt → 同步 summary_result →
#        四目录 ≥600dpi → pub_qc 骨架。中期 PDF 由 Agent 按 Aiya-NB004 出。
###############################################################################

#' 默认附表顺延：overall-only 撤掉 SOFA PH S7/S8 后，把 S9+ 前移填满空号
#' @return named integer：旧号 → 新号（仅列出需要改动的）
ml_lit_default_supp_renumber_map <- function() {
  # S1–S7 不动；S9→S8 … S16→S15（S11–S16 ML 一并前移，消除 S8/S10 空号）
  stats::setNames(8:15, as.character(9:16))
}

#' 从文件名解析 Table S 号
.ml_lit_parse_s_num <- function(path_or_name) {
  bn <- basename(as.character(path_or_name)[1L])
  m <- regexec("Table\\s*S\\s*([0-9]+)", bn, ignore.case = TRUE, perl = TRUE)
  g <- regmatches(bn, m)[[1]]
  if (length(g) < 2L) return(NA_integer_)
  as.integer(g[[2L]])
}

#' 重编号 Tables 文件名 + A1 标题中的 Table SN（外科改单元格，不整表重写）
#'
#' @param tables_dir Tables 目录
#' @param renumber_map named integer，旧号→新号；NULL 用 ml_lit_default_supp_renumber_map()
#' @param dry_run 只打印不改
#' @return data.frame(old, new, path)
ml_lit_renumber_supp_tables <- function(tables_dir,
                                        renumber_map = NULL,
                                        dry_run = FALSE) {
  if (!exists("pub_xlsx_edit_cells", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    if (!nzchar(root)) root <- getwd()
    src <- file.path(root, "R", "pub_xlsx_surgical.R")
    if (file.exists(src)) source(src, local = FALSE)
  }
  tables_dir <- as.character(tables_dir %||% "")[1L]
  if (!nzchar(tables_dir) || !dir.exists(tables_dir)) {
    stop("ml_lit_renumber_supp_tables: Tables 目录不存在: ", tables_dir)
  }
  if (is.null(renumber_map)) renumber_map <- ml_lit_default_supp_renumber_map()
  map_names <- as.character(names(renumber_map))
  renumber_map <- stats::setNames(as.integer(unname(renumber_map)), map_names)
  if (!length(renumber_map) || !any(nzchar(names(renumber_map)))) {
    stop("ml_lit_renumber_supp_tables: renumber_map 必须是 named integer（旧号→新号）")
  }

  xs <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE)
  plan <- list()
  for (f in xs) {
    old_n <- .ml_lit_parse_s_num(f)
    if (!is.finite(old_n)) next
    key <- as.character(old_n)
    if (!key %in% names(renumber_map)) next
    new_n <- renumber_map[[key]]
    if (!is.finite(new_n) || identical(old_n, new_n)) next
    bn <- basename(f)
    new_bn <- sub(
      sprintf("(?i)(Table\\s*S)\\s*%d", old_n),
      sprintf("\\1%d", new_n),
      bn,
      perl = TRUE
    )
    plan[[length(plan) + 1L]] <- data.frame(
      old_n = old_n, new_n = new_n, old_path = f,
      new_path = file.path(dirname(f), new_bn),
      stringsAsFactors = FALSE
    )
  }
  if (!length(plan)) {
    return(invisible(data.frame(
      old_n = integer(), new_n = integer(),
      old_path = character(), new_path = character()
    )))
  }
  plan <- do.call(rbind, plan)
  # 高号先改，避免 S10→S9 与 S9→S8 撞名
  plan <- plan[order(-plan$old_n), , drop = FALSE]

  if (isTRUE(dry_run)) {
    message("ml_lit_renumber dry_run:\n",
            paste(sprintf("  S%d -> S%d  %s", plan$old_n, plan$new_n,
                          basename(plan$old_path)), collapse = "\n"))
    return(invisible(plan))
  }

  for (i in seq_len(nrow(plan))) {
    op <- plan$old_path[[i]]
    np <- plan$new_path[[i]]
    old_n <- plan$old_n[[i]]
    new_n <- plan$new_n[[i]]
    if (!file.exists(op)) next
    if (!identical(op, np)) {
      if (file.exists(np)) {
        stop("目标已存在，拒绝覆盖: ", np, call. = FALSE)
      }
      if (!file.rename(op, np)) {
        # SMB 偶发 rename 失败：copy+unlink
        ok <- file.copy(op, np, overwrite = FALSE)
        if (!isTRUE(ok)) stop("rename/copy 失败: ", op, " -> ", np)
        unlink(op)
      }
    }
    # A1 标题 Table SN
    if (exists("pub_xlsx_edit_cells", mode = "function") &&
        requireNamespace("openxlsx", quietly = TRUE)) {
      d1 <- tryCatch(
        openxlsx::read.xlsx(np, colNames = FALSE, rows = 1, cols = 1),
        error = function(e) NULL
      )
      if (!is.null(d1) && nrow(d1) >= 1L) {
        title0 <- as.character(d1[1, 1] %||% "")
        title1 <- sub(
          sprintf("(?i)(Table\\s*S)\\s*%d\\b", old_n),
          sprintf("\\1%d", new_n),
          title0,
          perl = TRUE
        )
        if (!identical(title0, title1) && nzchar(title1)) {
          tryCatch(
            pub_xlsx_edit_cells(
              np,
              data.frame(row = 1L, col = 1L, value = title1,
                         stringsAsFactors = FALSE)
            ),
            error = function(e) {
              message("标题未改 (", basename(np), "): ", conditionMessage(e))
            }
          )
        }
      }
    }
    message(sprintf("renumber S%d -> S%d: %s", old_n, new_n, basename(np)))
  }
  invisible(plan)
}

#' 在文本文件中替换 Table SN / Figure 引用（README、image_information、content.json）
ml_lit_rewrite_table_s_refs <- function(root_dir, renumber_map = NULL) {
  if (is.null(renumber_map)) renumber_map <- ml_lit_default_supp_renumber_map()
  root_dir <- as.character(root_dir %||% "")[1L]
  if (!nzchar(root_dir) || !dir.exists(root_dir)) return(invisible(0L))
  # 高号先替换
  olds <- as.integer(names(renumber_map))
  ord <- order(-olds)
  olds <- olds[ord]
  news <- as.integer(unname(renumber_map))[ord]

  exts <- c("md", "txt", "json", "csv", "Rmd")
  files <- unlist(lapply(exts, function(e) {
    list.files(root_dir, pattern = paste0("\\.", e, "$"),
               recursive = TRUE, full.names = TRUE)
  }), use.names = FALSE)
  # 跳过巨型 dump / 备份
  files <- files[!grepl("_report_dump|__previous__|__archive|_bak_", files)]
  n_touch <- 0L
  for (f in files) {
    raw <- tryCatch(readLines(f, warn = FALSE, encoding = "UTF-8"),
                    error = function(e) NULL)
    if (is.null(raw) || !length(raw)) next
    txt <- paste(raw, collapse = "\n")
    new_txt <- txt
    for (i in seq_along(olds)) {
      new_txt <- gsub(
        sprintf("(?i)(Table\\s*S)\\s*%d\\b", olds[[i]]),
        sprintf("\\1%d", news[[i]]),
        new_txt,
        perl = TRUE
      )
    }
    if (!identical(txt, new_txt)) {
      writeLines(strsplit(new_txt, "\n", fixed = TRUE)[[1]], f, useBytes = TRUE)
      n_touch <- n_touch + 1L
    }
  }
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info("ml_lit_rewrite_table_s_refs: touched {n_touch} files under {root_dir}")
  }
  invisible(n_touch)
}

#' 写出本课题 Methods（统计正文 + Software 小节）
ml_lit_write_methods <- function(out_dir, config = NULL, methods_lines = NULL) {
  out_dir <- as.character(out_dir %||% "")[1L]
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  if (!exists("pub_write_software_versions", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    source(file.path(root, "R", "pub_software_versions.R"), local = FALSE)
  }
  pub_write_software_versions(out_dir, config = config)
  # 也写到 Tables/
  tab <- file.path(out_dir, "Tables")
  if (dir.exists(tab)) {
    file.copy(
      file.path(out_dir, "Methods_software_versions.txt"),
      file.path(tab, "Methods_software_versions.txt"),
      overwrite = TRUE
    )
  }

  if (is.null(methods_lines) || !length(methods_lines)) {
    methods_lines <- .ml_lit_default_methods_lines(config)
  }
  md_path <- file.path(out_dir, "Methods_statistical_analysis.md")
  writeLines(as.character(methods_lines), md_path, useBytes = TRUE)

  roles <- c(
    survival = "Cox proportional hazards models and Schoenfeld tests",
    mice = "Multiple imputation (train-fit / apply)",
    rms = "Restricted cubic splines",
    pROC = "ROC / AUC / DeLong",
    Boruta = "Feature selection",
    xgboost = "Gradient boosting (when used)",
    lightgbm = "Gradient boosting (when used)",
    randomForest = "Random forest",
    ggplot2 = "Publication figures",
    patchwork = "Multi-panel layout",
    openxlsx = "SCI three-line tables",
    forestploter = "Subgroup forest plots"
  )
  pub_write_methods_software_section(
    out_path = out_dir,
    roles = roles,
    extra_pkgs = names(roles),
    append_to = md_path
  )
  invisible(list(
    methods = md_path,
    software_txt = file.path(out_dir, "Methods_software_versions.txt"),
    software_md = file.path(out_dir, "Methods_software_section.md")
  ))
}

.ml_lit_default_methods_lines <- function(config = NULL) {
  c(
    "# Statistical analysis",
    "",
    "## Study design and cohorts",
    "",
    "Adult ICU admissions with acute kidney injury were analysed in MIMIC-IV (development and internal validation) with eICU used for external validation of machine-learning models and for Table 1 / imputation baseline tables. The primary clinical outcome was 28-day all-cause mortality (Survivor / Non-survivor). Follow-up was administratively censored at 28 days.",
    "",
    "## Exposures",
    "",
    "The primary exposures were the composite indices named in the study configuration (for example SAR and CrCV). Continuous values and tertiles used cut-points frozen on the MIMIC-IV development set. A four-level joint group was formed from the two upper-tertile indicators (Group1 = both below the frozen cut-point).",
    "",
    "## Missing data",
    "",
    "Multiple imputation was fitted on the MIMIC-IV training partition and applied to held-out MIMIC and eICU analysis frames without refitting the imputation model on external data. Table S7 reports baseline characteristics before and after imputation for MIMIC-IV training and eICU external validation.",
    "",
    "## Association analyses (MIMIC-IV)",
    "",
    "Unless otherwise labelled, Cox association tables (Table 2, Table S2–S6) report MIMIC-IV only. Model 1 was unadjusted; Model 2 adjusted for age and sex; Model 3 further adjusted for univariate-significant clinical covariates with variance inflation factor < 5. Proportional-hazards diagnostics used Schoenfeld residuals (Table S6). Discrimination used ROC AUC with DeLong tests versus the primary index (Table S5). Sensitivity analyses excluded baseline glucose < 70 mg/dL (Table S8) and restricted to complete cases (Table S9).",
    "",
    "## Machine learning",
    "",
    "Candidate predictors included the exposure indices when configured (composite indices forced into the Boruta / model feature pool). Feature selection (Boruta) and five models (logistic regression, decision tree, random forest, XGBoost, LightGBM) were trained on MIMIC-IV only. Frozen model assets were applied to eICU without refit (provenance no_refit). Performance tables (Table S10–S15) and Figure 8 report train / internal / external metrics as labelled.",
    "",
    "## Software",
    "",
    "See Methods_software_section.md and Methods_software_versions.txt generated at finalize.",
    ""
  )
}

#' 同步 publication_literature_final → summary_result（表图 + Methods）
ml_lit_sync_summary_result <- function(pub_root, summary_root = NULL) {
  pub_root <- as.character(pub_root %||% "")[1L]
  if (!nzchar(pub_root) || !dir.exists(pub_root)) {
    stop("ml_lit_sync_summary_result: pub_root 无效")
  }
  if (is.null(summary_root) || !nzchar(as.character(summary_root)[1L])) {
    summary_root <- file.path(dirname(pub_root), "summary_result")
  }
  summary_root <- as.character(summary_root)[1L]
  dir.create(file.path(summary_root, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(summary_root, "Figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(summary_root, "reports"), recursive = TRUE, showWarnings = FALSE)

  # Tables: 清空旧 xlsx 后整目录对齐（保留 Methods_*）
  dst_tab <- file.path(summary_root, "Tables")
  old_x <- list.files(dst_tab, pattern = "\\.xlsx$", full.names = TRUE)
  if (length(old_x)) unlink(old_x)
  src_tab <- file.path(pub_root, "Tables")
  for (f in list.files(src_tab, full.names = TRUE)) {
    file.copy(f, file.path(dst_tab, basename(f)), overwrite = TRUE)
  }
  # Figures 四目录
  src_fig <- file.path(pub_root, "Figures")
  dst_fig <- file.path(summary_root, "Figures")
  if (dir.exists(src_fig)) {
    for (sub in c("pdf", "png", "tiff", "image_information")) {
      s <- file.path(src_fig, sub)
      d <- file.path(dst_fig, sub)
      if (!dir.exists(s)) next
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      # 清旧再拷，避免旧图号残留
      oldf <- list.files(d, full.names = TRUE)
      if (length(oldf)) unlink(oldf, recursive = TRUE)
      for (f in list.files(s, full.names = TRUE)) {
        if (dir.exists(f)) {
          file.copy(f, d, recursive = TRUE, overwrite = TRUE)
        } else {
          file.copy(f, file.path(d, basename(f)), overwrite = TRUE)
        }
      }
    }
  }
  for (nm in c(
    "Methods_statistical_analysis.md",
    "Methods_software_versions.txt"
  )) {
    sp <- file.path(pub_root, nm)
    if (file.exists(sp)) file.copy(sp, file.path(summary_root, nm), overwrite = TRUE)
  }
  # 中期 PDF 若已在 pub_root 根目录则拷入交付面
  mid <- list.files(pub_root, pattern = "\u4e2d\u671f.*\\.pdf$", full.names = TRUE)
  for (f in mid) {
    file.copy(f, file.path(summary_root, basename(f)), overwrite = TRUE)
  }
  if (!exists("pub_prune_delivery_root", mode = "function")) {
    pr <- file.path(
      Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."),
      "R", "pub_delivery_prune.R"
    )
    if (file.exists(pr)) source(pr, local = FALSE)
  }
  if (exists("pub_prune_delivery_root", mode = "function")) {
    pub_prune_delivery_root(summary_root)
  }
  invisible(summary_root)
}

#' overall-only：Figure S3–S9 → S2–S8（Boruta 已升主文 Fig7，原 S2 空号）
ml_lit_renumber_supp_figures <- function(figures_dir, dry_run = FALSE) {
  figures_dir <- as.character(figures_dir %||% "")[1L]
  if (!nzchar(figures_dir) || !dir.exists(figures_dir)) return(invisible(NULL))
  mapping <- stats::setNames(2:8, as.character(3:9))
  plan <- list()
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    d <- file.path(figures_dir, sub)
    if (!dir.exists(d)) next
    for (f in list.files(d, full.names = TRUE)) {
      bn <- basename(f)
      m <- regexec("Figure\\s*S\\s*([0-9]+)", bn, ignore.case = TRUE, perl = TRUE)
      g <- regmatches(bn, m)[[1]]
      if (length(g) < 2L) next
      old_n <- as.integer(g[[2L]])
      key <- as.character(old_n)
      if (!key %in% names(mapping)) next
      new_n <- as.integer(mapping[[key]])
      new_bn <- sub(
        sprintf("(?i)(Figure\\s*S)\\s*%d", old_n),
        sprintf("\\1%d", new_n),
        bn,
        perl = TRUE
      )
      plan[[length(plan) + 1L]] <- data.frame(
        sub = sub, old_n = old_n, new_n = new_n,
        old_path = f, new_path = file.path(d, new_bn),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(plan)) return(invisible(NULL))
  plan <- do.call(rbind, plan)
  plan <- plan[order(-plan$old_n, plan$sub), , drop = FALSE]
  if (isTRUE(dry_run)) {
    message("ml_lit_renumber_supp_figures dry_run n=", nrow(plan))
    return(invisible(plan))
  }
  for (i in seq_len(nrow(plan))) {
    op <- plan$old_path[[i]]
    np <- plan$new_path[[i]]
    if (!file.exists(op) || identical(op, np)) next
    if (file.exists(np)) stop("figure target exists: ", np)
    if (!file.rename(op, np)) {
      stopifnot(file.copy(op, np, overwrite = FALSE))
      unlink(op)
    }
    if (grepl("\\.md$", np, ignore.case = TRUE)) {
      raw <- readLines(np, warn = FALSE, encoding = "UTF-8")
      txt <- paste(raw, collapse = "\n")
      for (on in sort(unique(plan$old_n), decreasing = TRUE)) {
        nn <- as.integer(mapping[[as.character(on)]])
        txt <- gsub(
          sprintf("(?i)(Figure\\s*S)\\s*%d\\b", on),
          sprintf("\\1%d", nn),
          txt,
          perl = TRUE
        )
      }
      writeLines(strsplit(txt, "\n", fixed = TRUE)[[1]], np, useBytes = TRUE)
    }
  }
  invisible(plan)
}

#' 文献 ML 终稿一键收口
#'
#' @param pub_root publication_literature_final
#' @param summary_root 默认同级 summary_result
#' @param renumber TRUE 时执行默认 S9+→前移
#' @param renumber_figures TRUE 时 overall-only 附图 S3–S9→S2–S8
#' @param run_qc TRUE 时调用 pub_qc_run_after_project（结构层）
#' @param ensure_figures TRUE 时 pub_figure_ensure_formats
ml_lit_finalize_delivery <- function(pub_root,
                                     summary_root = NULL,
                                     config = NULL,
                                     renumber = TRUE,
                                     renumber_map = NULL,
                                     renumber_figures = TRUE,
                                     rewrite_refs = TRUE,
                                     write_methods = TRUE,
                                     ensure_figures = TRUE,
                                     run_qc = TRUE,
                                     project_root_for_qc = NULL) {
  pub_root <- as.character(pub_root %||% "")[1L]
  stopifnot(dir.exists(pub_root))
  if (is.null(renumber_map)) renumber_map <- ml_lit_default_supp_renumber_map()

  tab_dir <- file.path(pub_root, "Tables")
  plan <- NULL
  if (isTRUE(renumber)) {
    plan <- ml_lit_renumber_supp_tables(tab_dir, renumber_map = renumber_map)
    if (isTRUE(rewrite_refs) && nrow(plan)) {
      ml_lit_rewrite_table_s_refs(pub_root, renumber_map = renumber_map)
    }
  }
  fig_plan <- NULL
  if (isTRUE(renumber_figures)) {
    fig_plan <- ml_lit_renumber_supp_figures(file.path(pub_root, "Figures"))
  }

  methods_paths <- NULL
  if (isTRUE(write_methods)) {
    methods_paths <- ml_lit_write_methods(pub_root, config = config)
  }

  if (isTRUE(ensure_figures) &&
      exists("pub_figure_ensure_formats", mode = "function")) {
    fig <- file.path(pub_root, "Figures")
    if (dir.exists(fig)) {
      tryCatch(
        pub_figure_ensure_formats(fig, config = config),
        error = function(e) message("pub_figure_ensure_formats: ", conditionMessage(e))
      )
    }
  }

  summary_root <- ml_lit_sync_summary_result(pub_root, summary_root)

  if (isTRUE(run_qc) && exists("pub_qc_run_after_project", mode = "function")) {
    pr <- project_root_for_qc %||% dirname(dirname(pub_root))
    # pub_root = .../by_index/【success】X/publication_literature_final
    # project often = .../prognosis_ml_xxx
    tryCatch(
      pub_qc_run_after_project(pr),
      error = function(e) message("pub_qc_run_after_project: ", conditionMessage(e))
    )
  }

  # 收口清单写在 pub_root/reports（不进 summary_result 交付面）
  checklist <- file.path(pub_root, "reports", "ml_lit_finalize_checklist.md")
  dir.create(dirname(checklist), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    "# ML literature finalize checklist",
    "",
    paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
    paste0("pub_root: `", pub_root, "`"),
    paste0("summary_result: `", summary_root, "`"),
    "",
    "## Done by engine",
    "- [x] Supp table renumber (fill gaps)",
    "- [x] Methods_statistical_analysis.md",
    "- [x] Methods_software_versions.txt",
    "- [x] summary_result sync + delivery whitelist prune",
    "- [x] Figure four-directory / dpi check (ensure_formats)",
    "- [x] Structural pub_qc stub (if enabled)",
    "",
    "## Agent must complete",
    "- [ ] nature-statistics / nature-figure Layer D（报告写 project `reports/`，勿堆进 summary_result）",
    "- [ ] H1 Methods P0 按推荐勾满",
    "- [ ] Aiya-NB004 midterm PDF → 写入 summary_result 根目录后再次 `pub_prune_delivery_root(summary_result)`",
    "",
    "## summary_result 交付白名单（铁律）",
    "- `Figures/` `Tables/`",
    "- `Methods_statistical_analysis.md`",
    "- `Methods_software_versions.txt`",
    "- `*中期*.pdf`",
    "- 其它一律进同级 `summary_result_delivery_workspace/`（不进交付面）",
    ""
  ), checklist, useBytes = TRUE)
  if (exists("pub_prune_delivery_root", mode = "function")) {
    pub_prune_delivery_root(summary_root)
  }

  invisible(list(
    pub_root = pub_root,
    summary_root = summary_root,
    renumber_plan = plan,
    methods = methods_paths,
    checklist = checklist
  ))
}

message("loaded R/ml_literature_pub_finalize.R")
