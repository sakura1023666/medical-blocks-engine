###############################################################################
#  pub_software_versions — 发表 Methods 软件/包版本落盘（全项目复用）
###############################################################################

#' 收集本机 R 与关键分析包版本
#' @param extra_pkgs 额外包名（字符向量）
#' @return named list: r_version, platform, date, packages (named character)
pub_collect_software_versions <- function(extra_pkgs = character(0)) {
  core <- c(
    "survival", "survminer", "mice", "rms", "Hmisc", "jstable",
    "ggplot2", "patchwork", "dplyr", "data.table", "openxlsx",
    "tableone", "cmprsk", "mediation", "car", "glmnet", "pROC"
  )
  pkgs <- unique(c(core, as.character(extra_pkgs %||% character(0))))
  pkgs <- pkgs[nzchar(pkgs)]
  vers <- vapply(pkgs, function(p) {
    if (!requireNamespace(p, quietly = TRUE)) return(NA_character_)
    as.character(utils::packageVersion(p))
  }, character(1), USE.NAMES = TRUE)
  vers <- vers[!is.na(vers)]
  list(
    r_version = R.version.string,
    platform = R.version$platform,
    date = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"),
    packages = vers
  )
}

#' 将软件版本写到指标根（及可选项目根）
#' @param index_root 指标输出根目录
#' @param project_root 可选课题根；非空时同步一份到 project_root/Methods_software_versions.txt
#' @param config 可选；读 config$software_versions$extra_pkgs
#' @return 写出的主路径（不可见）
pub_write_software_versions <- function(index_root, project_root = NULL, config = NULL) {
  if (is.null(index_root) || !nzchar(as.character(index_root)[1L])) {
    return(invisible(NULL))
  }
  index_root <- as.character(index_root)[1L]
  if (!dir.exists(index_root)) {
    dir.create(index_root, recursive = TRUE, showWarnings = FALSE)
  }
  extra <- character(0)
  if (is.list(config)) {
    extra <- as.character((config$software_versions %||% list())$extra_pkgs %||% character(0))
  }
  info <- pub_collect_software_versions(extra_pkgs = extra)
  lines <- c(
    "Software versions (analysis environment)",
    paste0("Generated: ", info$date),
    paste0("R: ", info$r_version),
    paste0("Platform: ", info$platform),
    "",
    "R packages:",
    sprintf("  %s %s", names(info$packages), unname(info$packages)),
    "",
    "Note: Versions reflect the machine that finalized this index;",
    "re-running on another host may change package patch levels."
  )
  out1 <- file.path(index_root, "Methods_software_versions.txt")
  writeLines(lines, out1, useBytes = TRUE)
  if (!is.null(project_root) && nzchar(as.character(project_root)[1L])) {
    pr <- as.character(project_root)[1L]
    if (!dir.exists(pr)) dir.create(pr, recursive = TRUE, showWarnings = FALSE)
    out2 <- file.path(pr, "Methods_software_versions.txt")
    # 项目根保留最近一次 finalize 的版本（便于 Methods 引用）
    writeLines(lines, out2, useBytes = TRUE)
  }
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("Software versions: {out1}")
  }
  invisible(out1)
}

#' 写出 Methods「Software」小节 Markdown（全项目复用）
#'
#' @param out_path 目标 md 路径；若为目录则写 Methods_software_section.md
#' @param roles named character：包名 → 用途说明（可含 Fig/Table 对应）
#' @param extra_pkgs 额外收录版本的包
#' @param append_to 可选：已有 Methods_statistical_analysis.md，追加/替换 ## Software 节
#' @return 写出路径（不可见）
pub_write_methods_software_section <- function(
    out_path,
    roles = NULL,
    extra_pkgs = character(0),
    append_to = NULL,
    r_note = NULL
) {
  info <- pub_collect_software_versions(extra_pkgs = unique(c(
    names(roles %||% character(0)), as.character(extra_pkgs %||% character(0)),
    "gtsummary", "forestploter", "brglm2", "openxlsx"
  )))
  if (is.null(roles) || !length(roles)) {
    roles <- c(
      gtsummary = "Baseline / stratified descriptive tables",
      car = "Variance inflation factors",
      glmnet = "Penalized regression / shrinkage",
      rms = "RCS and regression prediction helpers",
      forestploter = "Forest plots",
      ggplot2 = "Publication figures",
      patchwork = "Multi-panel figure layout",
      pROC = "ROC / AUC / CI",
      openxlsx = "SCI three-line xlsx export"
    )
  }
  roles <- roles[names(roles) %in% names(info$packages) | names(roles) %in% names(roles)]
  lines_tbl <- vapply(names(roles), function(p) {
    ver <- if (p %in% names(info$packages)) info$packages[[p]] else "—"
    sprintf("| %s | %s | %s |", p, ver, roles[[p]])
  }, character(1))
  body <- c(
    "## Software",
    "",
    sprintf(
      "Analyses were performed in **%s** (%s). Key packages and roles:",
      info$r_version, info$platform
    ),
    "",
    "| Package | Version | Role |",
    "|---------|---------|------|",
    lines_tbl,
    "",
    paste0(
      "Publication tables use the engine SCI three-line xlsx entry ",
      "(`sci_xlsx_single_header_booktabs` / `write_table1_xlsx_guan_style`). ",
      "Figures are exported under `Figures/{pdf,png,tiff,image_information}/`. ",
      "Display labels omit programming underscores."
    ),
    "",
    paste0(
      "Package versions at finalize: see `Methods_software_versions.txt` ",
      "(generated ", info$date, "). ",
      if (!is.null(r_note) && nzchar(r_note)) r_note else
        "Re-running on another host may change patch levels."
    ),
    ""
  )
  out_path <- as.character(out_path %||% "")[1L]
  if (!nzchar(out_path)) stop("pub_write_methods_software_section: out_path 必填")
  if (dir.exists(out_path)) {
    out_path <- file.path(out_path, "Methods_software_section.md")
  }
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  writeLines(body, out_path, useBytes = TRUE)

  ap <- as.character(append_to %||% "")[1L]
  if (nzchar(ap) && file.exists(ap)) {
    old <- readLines(ap, warn = FALSE, encoding = "UTF-8")
    # 替换已有 ## Software / ## 9. Software 节，否则追加
    hit <- grep("^##[[:space:]]*([0-9]+\\.[[:space:]]*)?Software\\b", old)
    if (length(hit)) {
      start <- hit[[1L]]
      nxt <- grep("^##[[:space:]]+", old)
      nxt <- nxt[nxt > start]
      end <- if (length(nxt)) nxt[[1L]] - 1L else length(old)
      old <- old[-(start:end)]
      # 插回原位置
      old <- append(old, body, after = start - 1L)
    } else {
      old <- c(old, "", body)
    }
    writeLines(old, ap, useBytes = TRUE)
  }
  invisible(out_path)
}
