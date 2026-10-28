###############################################################################
#  pub_qc_after_finalize — 结构层发表 QC（全项目复用）
#
#  挂点：run_pipeline 收尾 / dual-batch finalize / CLI run/pub/run_pub_qc_after_project.R
#  只做结构扫描 + 骨架报告；Nature Layer D 仍由 Agent 按 skills 填实并修 P0。
###############################################################################

.pub_qc_today <- function() format(Sys.Date(), "%Y-%m-%d")

.pub_qc_find_figure_roots <- function(project_root) {
  project_root <- as.character(project_root)[1L]
  # 优先定稿发表根（summary_* / 课题根 Figures）；有定稿则不扫 by_unit 草稿
  pub_cands <- c(
    file.path(project_root, "summary_result", "Figures"),
    file.path(project_root, "summary_results", "Figures"),
    file.path(project_root, "Figures")
  )
  pub_hit <- unique(pub_cands[dir.exists(pub_cands)])
  # 仅当尚无 summary 定稿时，才扫 【success】 指标/单元（避免双库 unit 草稿 DPI 拖垮定稿 QC）
  has_summary <- any(dir.exists(c(
    file.path(project_root, "summary_result", "Figures"),
    file.path(project_root, "summary_results", "Figures")
  )))
  if (isTRUE(has_summary)) return(pub_hit)

  cands <- pub_hit
  by_index <- file.path(project_root, "by_index")
  if (dir.exists(by_index)) {
    hits <- list.files(by_index, pattern = "^\u3010success\u3011", full.names = TRUE)
    cands <- c(cands, file.path(hits, "Figures"))
  }
  by_unit <- file.path(project_root, "by_unit")
  if (dir.exists(by_unit)) {
    hits <- list.files(by_unit, pattern = "^\u3010success\u3011", full.names = TRUE)
    cands <- c(cands, file.path(hits, "Figures"))
  }
  unique(cands[dir.exists(cands)])
}

.pub_qc_scan_figures <- function(figures_dir) {
  if (!exists("pub_figure_formats_status", mode = "function")) {
    return(list(ok = NA, note = "pub_figure_export not loaded"))
  }
  pub_figure_formats_status(figures_dir)
}

#' 结构 QC：四目录 + DPI≥600；写 reports/pub_qc_*.md（已有正式报告不覆盖正文时可 append stub）
#' @param project_root 课题根
#' @param config 可选；`config$pub$auto_qc = FALSE` 跳过
#' @param force 强制写出（忽略 auto_qc 关）
#' @return list(ok, report_path, scans)
pub_qc_run_after_project <- function(project_root, config = NULL, force = FALSE) {
  project_root <- as.character(project_root %||% "")[1L]
  if (!nzchar(project_root) || !dir.exists(project_root)) {
    return(invisible(list(ok = FALSE, reason = "missing_project")))
  }
  if (identical(Sys.getenv("MEDICAL_BLOCKS_AUTO_PUB_QC", "1"), "0") && !isTRUE(force)) {
    return(invisible(list(ok = NA, reason = "env_disabled")))
  }
  pub_cfg <- if (is.list(config)) (config$pub %||% list()) else list()
  if (isFALSE(pub_cfg$auto_qc) && !isTRUE(force)) {
    return(invisible(list(ok = NA, reason = "config_disabled")))
  }

  # 确保能读 DPI
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(eng)) {
    for (cand in c("E:/01block/01Block-new-Final", "/mnt/e/01block/01Block-new-Final")) {
      if (dir.exists(cand)) { eng <- cand; break }
    }
  }
  if (nzchar(eng) && !exists("pub_figure_formats_status", mode = "function")) {
    try(source(file.path(eng, "R/pub_figure_export.R"), local = FALSE), silent = TRUE)
  }

  fig_roots <- .pub_qc_find_figure_roots(project_root)
  # Layer D 机器半边：DPI<600 时从 PDF 重导，不整目录 purge。叙述仍由 Agent 填。
  if (nzchar(eng)) {
    scan_py <- file.path(eng, "python", "nature_two_aspect_scan.py")
    if (file.exists(scan_py)) {
      py <- Sys.which("python3")
      if (!nzchar(py)) py <- Sys.which("python")
      if (nzchar(py)) {
        try(system2(py, c(scan_py, "--project", project_root, "--repair"),
                    stdout = FALSE, stderr = FALSE), silent = TRUE)
      }
    }
  }
  scans <- lapply(fig_roots, function(d) {
    st <- tryCatch(.pub_qc_scan_figures(d), error = function(e) list(ok = FALSE, error = e$message))
    list(dir = d, status = st)
  })

  n_fail <- sum(vapply(scans, function(x) {
    st <- x$status
    isFALSE(st$ok) || length(st$bad_dpi %||% character(0)) > 0 ||
      length(st$missing_png %||% character(0)) > 0 ||
      length(st$missing_tiff %||% character(0)) > 0
  }, logical(1)))

  reports <- file.path(project_root, "reports")
  dir.create(reports, recursive = TRUE, showWarnings = FALSE)
  day <- .pub_qc_today()
  report_path <- file.path(reports, paste0("pub_qc_", day, ".md"))
  nature_fig <- file.path(reports, paste0("nature_figure_qc_", day, ".md"))
  nature_stat <- file.path(reports, paste0("nature_statistics_qc_", day, ".md"))

  lines <- c(
    "# 发表质控报告（结构 AUTO）",
    "",
    paste0("- 项目根：`", project_root, "`"),
    paste0("- 日期：", day),
    paste0("- 审阅结论：**", if (n_fail == 0L) "STRUCT_OK" else "STRUCT_FAIL", "**（仅 Layer A 结构；Nature Layer D 须 Agent 填实）"),
    paste0("- Figures 根数：", length(fig_roots), "；结构失败：", n_fail),
    "",
    "## Layer A — 四目录 + DPI≥600",
    ""
  )
  for (sc in scans) {
    st <- sc$status
    bad <- length(st$bad_dpi %||% character(0))
    lines <- c(
      lines,
      paste0("### `", sc$dir, "`"),
      paste0("- ok=", st$ok %||% NA, "; stems=", length(st$stems %||% character(0)),
             "; bad_dpi=", bad, "; require_dpi=", st$require_dpi %||% 600L),
      if (bad > 0L) paste0("- bad_dpi 样例：", paste(utils::head(st$bad_dpi, 5L), collapse = "; ")) else NULL,
      ""
    )
  }
  lines <- c(
    lines,
    "## Layer D stubs",
    "",
    paste0("- 若尚无正式报告，请按 `.cursor/skills/pub-qc-after-project` 填实："),
    paste0("  - `", basename(nature_fig), "`"),
    paste0("  - `", basename(nature_stat), "`"),
    "- **png/tiff 嵌入 DPI < 600 或缺元数据 = P0**，当场 `pub_figure_ensure_formats`。",
    ""
  )

  # 不覆盖已有非 AUTO 正式报告
  write_main <- TRUE
  if (file.exists(report_path)) {
    old <- paste(readLines(report_path, warn = FALSE, n = 5L), collapse = "\n")
    if (!grepl("结构 AUTO|AUTO_STUB", old)) {
      write_main <- FALSE
      alt <- file.path(reports, paste0("pub_qc_", day, "_struct_auto.md"))
      writeLines(lines, alt, useBytes = TRUE)
      report_path <- alt
    }
  }
  if (write_main) writeLines(lines, report_path, useBytes = TRUE)

  .write_stub <- function(path, title) {
    if (file.exists(path)) return(FALSE)
    writeLines(c(
      paste0("# ", title),
      "",
      "<!-- AUTO_STUB: Agent 须按 nature-* skill 填实；未填实不得宣称 PASS -->",
      "",
      paste0("- 项目：`", project_root, "`"),
      paste0("- 日期：", day),
      "- 结论：PENDING",
      ""
    ), path, useBytes = TRUE)
    TRUE
  }
  .write_stub(nature_fig, "Nature Figure QC (AUTO_STUB)")
  .write_stub(nature_stat, "Nature Statistics QC (AUTO_STUB)")

  if (requireNamespace("cli", quietly = TRUE)) {
    if (n_fail == 0L) {
      cli::cli_alert_success("pub-qc 结构 OK -> {report_path}")
    } else {
      cli::cli_alert_danger("pub-qc 结构 FAIL (n={n_fail}) -> {report_path}")
    }
  }

  # Phase 7 排队：结构通过后写下一批中期目录。叙述仍由 Agent 按
  # Aiya-NB004-midterm-report 填写；此处只保证收口后队列存在，不在 R 里编造正文。
  if (n_fail == 0L) {
    qpath <- file.path(reports, "phase7_midterm_queue.txt")
    qdirs <- unique(c(
      fig_roots,
      file.path(project_root, "summary_result"),
      file.path(project_root, "summary_results"),
      if (basename(project_root) %in% c("summary_result", "summary_results")) project_root else character(0)
    ))
    qdirs <- qdirs[dir.exists(qdirs)]
    writeLines(c(
      paste0("project=", project_root),
      paste0("date=", day),
      "note=Nature Layer D P0 must be cleared before build_report.py",
      paste0("dir=", qdirs)
    ), qpath, useBytes = TRUE)
  }

  invisible(list(
    ok = n_fail == 0L,
    report_path = report_path,
    n_fail = n_fail,
    scans = scans
  ))
}
