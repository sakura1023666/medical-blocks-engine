###############################################################################
#  cross_lagged_delivery_finalize.R — 交叉滞后交付收口（全项目复用）
#
#  对 summary_result / summary_results（含 Age 切点交付根）：
#    1) 表题 A1 = 文件名；表展示禁下划线
#    2) Figures：ensure_formats（PDF + image_information；几何 ≤ max_edge）
#    3) Methods_statistical_analysis.md + Methods_software_versions.txt
#    4) 结构 QC（pub_qc_run_after_project）
#    5) 交付白名单 prune（只留 Figures/Tables/Methods*/中期.pdf）
#
#  挂点：summary collect 末尾；CLI --phase finalize|delivery
###############################################################################

#' 解析交叉滞后交付根（引擎 summary_result 或课题盘 Age 切点根）
cross_lagged_resolve_delivery_roots <- function(study_root, sync_root = NULL) {
  study_root <- as.character(study_root %||% "")[1L]
  out <- character(0)
  if (nzchar(study_root)) {
    cand <- file.path(study_root, "summary_result")
    if (dir.exists(cand)) out <- c(out, normalizePath(cand, winslash = "/", mustWork = FALSE))
  }
  sync_root <- as.character(
    sync_root %||% Sys.getenv("CROSS_LAGGED_SYNC_ROOT", "")
  )[1L]
  if (nzchar(sync_root) && dir.exists(sync_root)) {
    # Age 切点交付：summary_result（50）/（65）等
    kids <- list.files(sync_root, full.names = TRUE)
    kids <- kids[dir.exists(kids)]
    kids <- kids[grepl("summary_result", basename(kids), fixed = TRUE)]
    # 排除 delivery_workspace / pre_align 备份
    kids <- kids[!grepl("delivery_workspace|pre_align|_bak", basename(kids), ignore.case = TRUE)]
    if (length(kids)) out <- c(out, normalizePath(kids, winslash = "/", mustWork = FALSE))
  }
  unique(out[nzchar(out) & dir.exists(out)])
}

#' 写交叉滞后 Methods + Software 到交付根
cross_lagged_write_methods_bundle <- function(delivery_root, config = NULL, study_root = NULL) {
  delivery_root <- as.character(delivery_root)[1L]
  if (!dir.exists(delivery_root)) {
    stop("cross_lagged_write_methods_bundle: 目录不存在: ", delivery_root, call. = FALSE)
  }
  if (!exists("cross_lagged_methods_statistical_lines", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ".")
    fn <- file.path(root, "R/cross_lagged_methods_pub.R")
    if (file.exists(fn)) source(fn, local = FALSE)
  }
  lines <- cross_lagged_methods_statistical_lines(config)
  # 展示层禁下划线（保护文件名 token）
  .cl_scrub <- function(x) {
    x <- as.character(x)
    keep <- grepl("Methods_software_versions\\.txt|Methods_statistical_analysis\\.md", x)
    if (exists("pipeline_scrub_pub_text", mode = "function")) {
      y <- pipeline_scrub_pub_text(x)
    } else {
      y <- gsub("Alcohol_drinking", "Alcohol drinking", x, fixed = TRUE)
      y <- gsub("_", " ", y, fixed = TRUE)
    }
    # 还原被误伤的软件清单文件名
    y <- gsub("Methods software versions\\.txt", "Methods_software_versions.txt", y)
    y <- gsub("Methods statistical analysis\\.md", "Methods_statistical_analysis.md", y)
    if (isTRUE(keep)) return(x)
    y
  }
  lines <- vapply(lines, .cl_scrub, character(1), USE.NAMES = FALSE)
  md_path <- file.path(delivery_root, "Methods_statistical_analysis.md")
  writeLines(lines, md_path, useBytes = TRUE)

  if (!exists("pub_write_software_versions", mode = "function")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ".")
    fn <- file.path(root, "R/pub_software_versions.R")
    if (file.exists(fn)) source(fn, local = FALSE)
  }
  if (exists("pub_write_software_versions", mode = "function")) {
    tryCatch(
      pub_write_software_versions(delivery_root, project_root = NULL, config = config),
      error = function(e) cli::cli_alert_warning("software versions: {conditionMessage(e)}")
    )
  }
  # 合并 Software 小节进 Methods（与其它课题一致）
  soft <- file.path(delivery_root, "Methods_software_versions.txt")
  if (file.exists(soft) && file.exists(md_path)) {
    md <- readLines(md_path, warn = FALSE, encoding = "UTF-8")
    if (!any(grepl("^## Software\\s*$", md))) {
      soft_lines <- readLines(soft, warn = FALSE, encoding = "UTF-8")
      writeLines(
        c(md, "", "## Software", "", soft_lines, ""),
        md_path,
        useBytes = TRUE
      )
    }
  }
  invisible(list(methods = md_path, software = soft))
}

#' 交叉滞后单个交付根收口
cross_lagged_finalize_one_delivery <- function(delivery_root,
                                              config = NULL,
                                              study_root = NULL,
                                              run_qc = TRUE,
                                              prune = TRUE,
                                              ensure_figures = TRUE) {
  delivery_root <- normalizePath(as.character(delivery_root)[1L], winslash = "/", mustWork = TRUE)
  cli::cli_h2("Cross-lagged delivery finalize: {delivery_root}")

  tab <- file.path(delivery_root, "Tables")
  if (!dir.exists(tab)) tab <- file.path(delivery_root, "table")
  fig <- file.path(delivery_root, "Figures")
  if (!dir.exists(fig)) fig <- file.path(delivery_root, "figure")

  # 1) 表题 + 禁下划线
  if (dir.exists(tab)) {
    if (!exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
      root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ".")
      source(file.path(root, "R/pub_xlsx_surgical.R"), local = FALSE)
    }
    tryCatch(
      pub_sync_xlsx_a1_titles_to_filenames(tab),
      error = function(e) cli::cli_alert_warning("A1 sync: {conditionMessage(e)}")
    )
    if (!exists("pub_delivery_scrub_tables_underscores", mode = "function")) {
      root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ".")
      source(file.path(root, "R/pub_delivery_prune.R"), local = FALSE)
    }
    tryCatch(
      pub_delivery_scrub_tables_underscores(delivery_root),
      error = function(e) cli::cli_alert_warning("underscore scrub: {conditionMessage(e)}")
    )
  }

  # 2) 图四目录 / 几何
  if (isTRUE(ensure_figures) && dir.exists(fig)) {
    if (!exists("pub_figure_ensure_formats", mode = "function")) {
      root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ".")
      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    }
    tryCatch(
      pub_figure_ensure_formats(
        fig,
        config = list(pub_figures = list(
          export_png = FALSE, export_tiff = FALSE, max_edge_in = 11
        )),
        purge = TRUE
      ),
      error = function(e) cli::cli_alert_warning("ensure_formats: {conditionMessage(e)}")
    )
  }

  # 3) Methods + software
  cross_lagged_write_methods_bundle(delivery_root, config = config, study_root = study_root)

  # 4) 结构 QC（报告写到交付根 reports/，随后 prune 挪走）
  if (isTRUE(run_qc)) {
    if (!exists("pub_qc_run_after_project", mode = "function")) {
      root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ".")
      fn <- file.path(root, "R/pub_qc_after_finalize.R")
      if (file.exists(fn)) source(fn, local = FALSE)
    }
    if (exists("pub_qc_run_after_project", mode = "function")) {
      tryCatch(
        pub_qc_run_after_project(delivery_root),
        error = function(e) cli::cli_alert_warning("pub_qc: {conditionMessage(e)}")
      )
    }
  }

  # 5) 白名单 prune
  if (isTRUE(prune)) {
    if (!exists("pub_prune_delivery_root", mode = "function")) {
      root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ".")
      source(file.path(root, "R/pub_delivery_prune.R"), local = FALSE)
    }
    tryCatch(
      pub_prune_delivery_root(delivery_root),
      error = function(e) cli::cli_alert_warning("prune: {conditionMessage(e)}")
    )
  }

  invisible(delivery_root)
}

#' 若交付根已有 content.json，调用 Aiya-NB004 引擎重出中期 PDF（可复用）
cross_lagged_try_build_midterm_pdf <- function(study_root, sync_root = NULL) {
  roots <- cross_lagged_resolve_delivery_roots(study_root, sync_root = sync_root)
  if (!length(roots)) return(invisible(NULL))
  skill <- file.path(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."),
    ".cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py"
  )
  if (!file.exists(skill)) {
    cli::cli_alert_info("未找到 Aiya-NB004 build_report.py，跳过自动中期")
    return(invisible(NULL))
  }
  for (d in roots) {
    cj <- file.path(d, "content.json")
    if (!file.exists(cj)) {
      # prune 后可能在同级 workspace
      ws <- paste0(d, "_delivery_workspace")
      cands <- character(0)
      if (dir.exists(ws)) {
        cands <- list.files(ws, pattern = "^content\\.json$", recursive = TRUE, full.names = TRUE)
      }
      if (!length(cands)) {
        cli::cli_alert_info("无 content.json，跳过自动中期: {basename(d)}（Agent 按 Aiya-NB004 撰写后可 --phase midterm）")
        next
      }
      cj <- cands[[1L]]
    }
    out_pdf <- file.path(d, "中期报告.pdf")
    # 保留已有中文文件名若存在
    exist <- list.files(d, pattern = "中期.*\\.pdf$", full.names = TRUE)
    if (length(exist)) out_pdf <- exist[[1L]]
    cmd <- sprintf(
      'python3 %s --build --project %s --content %s --out %s',
      shQuote(skill), shQuote(d), shQuote(cj), shQuote(out_pdf)
    )
    cli::cli_alert_info("build midterm: {basename(d)}")
    st <- tryCatch(system(cmd, intern = FALSE), error = function(e) 1L)
    if (!identical(as.integer(st), 0L)) {
      cli::cli_alert_warning("midterm build 非零退出: {d}")
    }
  }
  invisible(TRUE)
}

#' 交叉滞后：对引擎 + 课题盘全部交付根收口
cross_lagged_finalize_delivery <- function(study_root,
                                           sync_root = NULL,
                                           config = NULL,
                                           run_qc = TRUE,
                                           prune = TRUE,
                                           ensure_figures = TRUE) {
  if (is.null(sync_root) || !nzchar(as.character(sync_root)[1L])) {
    if (exists("cross_lagged_resolve_sync_root", mode = "function")) {
      sync_root <- tryCatch(
        cross_lagged_resolve_sync_root(study_root),
        error = function(e) Sys.getenv("CROSS_LAGGED_SYNC_ROOT", "")
      )
    } else {
      sync_root <- Sys.getenv("CROSS_LAGGED_SYNC_ROOT", "")
    }
  }
  # Hip Age≥50 交付常用 config 缺省
  if (is.null(config)) {
    config <- list(
      project = list(
        analysis_group = "hip fracture",
        exposure = "Frailty Index",
        databases = c("CHARLS", "ELSA", "HRS"),
        age_filter = "Age >= 50"
      ),
      data_clean = list(age_filter = "Age >= 50"),
      mediation = list(shared_model2 = c("Age", "Alcohol drinking"))
    )
  }
  roots <- cross_lagged_resolve_delivery_roots(study_root, sync_root = sync_root)
  if (!length(roots)) {
    cli::cli_alert_warning("未找到 summary_result 交付根")
    return(invisible(character(0)))
  }
  for (d in roots) {
    # Age 切点交付根：按目录名覆写 age_filter 文案
    cfg_one <- config
    bn <- basename(d)
    if (grepl("（50）|\\(50\\)|age.?50", bn, ignore.case = TRUE)) {
      cfg_one$data_clean$age_filter <- "Age >= 50"
      cfg_one$project$age_filter <- "Age >= 50"
    } else if (grepl("（65）|\\(65\\)|age.?65", bn, ignore.case = TRUE)) {
      cfg_one$data_clean$age_filter <- "Age >= 65"
      cfg_one$project$age_filter <- "Age >= 65"
    }
    cross_lagged_finalize_one_delivery(
      d,
      config = cfg_one,
      study_root = study_root,
      run_qc = run_qc,
      prune = prune,
      ensure_figures = ensure_figures
    )
  }
  invisible(roots)
}
