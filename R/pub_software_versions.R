###############################################################################
#  pub_software_versions — 发表 Methods 软件/包版本落盘（全项目复用）
###############################################################################

#' 收集本机 R 与关键分析包版本
#' @param extra_pkgs 额外包名（字符向量）
#' @param exclude_pkgs 从核心清单剔除（如全因死亡课题未做竞争风险则踢 cmprsk）
#' @return named list: r_version, platform, date, packages (named character)
pub_collect_software_versions <- function(
    extra_pkgs = character(0),
    exclude_pkgs = character(0)
) {
  core <- c(
    "survival", "survminer", "mice", "rms", "Hmisc", "jstable",
    "ggplot2", "patchwork", "dplyr", "data.table", "openxlsx",
    "tableone", "cmprsk", "mediation", "car", "glmnet", "pROC"
  )
  pkgs <- unique(c(core, as.character(extra_pkgs %||% character(0))))
  pkgs <- pkgs[nzchar(pkgs)]
  excl <- unique(as.character(exclude_pkgs %||% character(0)))
  excl <- excl[nzchar(excl)]
  if (length(excl)) pkgs <- setdiff(pkgs, excl)
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

#' Collect Python + key scientific package versions (best-effort; omit if unavailable)
#' @return character lines (may be empty)
pub_collect_python_software_lines <- function(extra_modules = NULL, modules_only = FALSE) {
  extra <- as.character(extra_modules %||% character(0))
  extra <- extra[nzchar(extra)]
  if (isTRUE(modules_only) && length(extra)) {
    mods <- unique(extra)
  } else {
    mods <- unique(c(
      "numpy", "pandas", "sklearn", "xgboost", "lightgbm", "shap",
      "imblearn", "joblib", "openpyxl", "matplotlib",
      extra
    ))
  }
  mods <- mods[nzchar(mods)]
  py <- Sys.which("python3")
  if (!nzchar(py)) py <- Sys.which("python")
  if (!nzchar(py)) return(character(0))
  ## Write a temp .py (system2 -c cannot take multiline safely)
  code <- paste0(
    "import sys, importlib\n",
    "print('Python', sys.version.split()[0])\n",
    "mods = ", paste0("['", paste(mods, collapse = "','"), "']"), "\n",
    "disp = {'sklearn':'scikit-learn','imblearn':'imbalanced-learn'}\n",
    "for m in mods:\n",
    "  try:\n",
    "    mod = importlib.import_module(m)\n",
    "    v = getattr(mod, '__version__', None)\n",
    "    if v is None:\n",
    "      import importlib.metadata as md\n",
    "      dist = disp.get(m, m)\n",
    "      try: v = md.version(dist)\n",
    "      except Exception:\n",
    "        try: v = md.version(m)\n",
    "        except Exception: v = 'unknown'\n",
    "    print(disp.get(m, m), v)\n",
    "  except Exception:\n",
    "    try:\n",
    "      import importlib.metadata as md\n",
    "      dist = disp.get(m, m)\n",
    "      try: v = md.version(dist)\n",
    "      except Exception: v = md.version(m)\n",
    "      print(disp.get(m, m), v)\n",
    "    except Exception:\n",
    "      pass\n"
  )
  tf <- tempfile(fileext = ".py")
  on.exit(unlink(tf), add = TRUE)
  writeLines(code, tf, useBytes = TRUE)
  out <- tryCatch(
    system2(py, args = tf, stdout = TRUE, stderr = FALSE),
    error = function(e) character(0)
  )
  out <- as.character(out %||% character(0))
  out <- out[nzchar(trimws(out))]
  if (!length(out)) return(character(0))
  # First line Python x.y.z; rest "pkg ver"
  lines <- character(0)
  if (grepl("^Python\\s", out[[1L]])) {
    lines <- c(out[[1L]], "")
    rest <- out[-1L]
  } else {
    rest <- out
  }
  if (length(rest)) {
    lines <- c(lines, "Python packages:", sprintf("  %s", rest))
  }
  lines
}

#' 将软件版本写到指标根（及可选项目根）
#' @param index_root 指标输出根目录
#' @param project_root 可选课题根；非空时同步一份到 project_root/Methods_software_versions.txt
#' @param config 可选；读 config$software_versions$extra_pkgs / exclude_pkgs / include_python
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
  exclude <- character(0)
  include_python <- FALSE
  py_extra <- character(0)
  python_modules_only <- FALSE
  if (is.list(config)) {
    sv <- config$software_versions %||% list()
    extra <- as.character(sv$extra_pkgs %||% character(0))
    exclude <- as.character(sv$exclude_pkgs %||% character(0))
    include_python <- isTRUE(sv$include_python)
    py_extra <- as.character(sv$python_modules %||% character(0))
    python_modules_only <- isTRUE(sv$python_modules_only) ||
      (length(py_extra) > 0L && !is.null(sv$python_modules))
    ## TCF / sklearn 主链：默认剔除预后模板残留包，并收录 Python
    is_tcf <- isTRUE((config$ml_tcf_sklearn_rscv %||% list())$enable) ||
      identical(tolower(as.character((config$methods %||% list())$kind %||% "")[1L]), "tcf")
    if (isTRUE(is_tcf)) {
      include_python <- TRUE
      exclude <- unique(c(
        exclude,
        "survival", "survminer", "rms", "cmprsk", "mediation",
        "jstable", "tableone", "glmnet", "Hmisc", "car"
      ))
      extra <- unique(c(extra, "mice", "ggplot2", "patchwork", "dplyr",
                        "data.table", "openxlsx", "pROC"))
    }
    ## 发病 / 横断面 ML：剔除未用的 Cox / 竞争风险 / 中介模板包
    st <- tolower(as.character((config$project %||% list())$study_type %||% "")[1L])
    mk <- tolower(as.character((config$methods %||% list())$kind %||% "")[1L])
    is_ml_inc <- !is.null(config$ml_batch) &&
      !identical(st, "survival") &&
      !identical(mk, "survival") &&
      !identical(mk, "prognosis") &&
      is.null(config$survival_batch)
    if (isTRUE(is_ml_inc) && !isTRUE(is_tcf)) {
      exclude <- unique(c(exclude, "survival", "survminer", "cmprsk", "mediation"))
      extra <- unique(c(extra, "forestploter", "glmnet", "pROC", "car"))
    }
    ## ML 分类器 / SHAP / Shiny：必须登记版本（防 Methods_software_versions 只剩 15 包）
    is_ml_kind <- identical(mk, "ml") ||
      !is.null(config$ml_batch) ||
      !is.null(config$ml_models) ||
      isTRUE((config$shiny_ml_app %||% list())$enable)
    if (isTRUE(is_ml_kind) && !isTRUE(is_tcf)) {
      extra <- unique(c(
        extra,
        "xgboost", "lightgbm", "randomForest", "kernlab", "e1071", "rpart",
        "bonsai", "parsnip", "recipes", "workflows", "tune", "dials",
        "yardstick", "rsample", "shapviz", "fastshap", "shiny", "tidymodels",
        "glmnet", "pROC", "forestploter"
      ))
    }
  }
  info <- pub_collect_software_versions(extra_pkgs = extra, exclude_pkgs = exclude)
  lines <- c(
    "Software versions (analysis environment)",
    paste0("Generated: ", info$date),
    paste0("R: ", info$r_version),
    paste0("Platform: ", info$platform),
    "",
    "R packages:",
    sprintf("  %s %s", names(info$packages), unname(info$packages))
  )
  if (isTRUE(include_python)) {
    py_lines <- pub_collect_python_software_lines(
      extra_modules = py_extra,
      modules_only = isTRUE(python_modules_only)
    )
    if (length(py_lines)) {
      lines <- c(lines, "", py_lines)
    } else {
      lines <- c(
        lines, "",
        "Python packages:",
        "  (unavailable on finalize host; record analysis-host versions before delivery)"
      )
    }
  }
  footer <- as.character((config$software_versions %||% list())$footer_lines %||% character(0))
  footer <- footer[nzchar(footer)]
  is_tcf_note <- isTRUE((config$ml_tcf_sklearn_rscv %||% list())$enable) ||
    identical(tolower(as.character((config$methods %||% list())$kind %||% "")[1L]), "tcf")
  note_lines <- c(
    "",
    "Note: Versions reflect the machine that finalized this index;",
    "re-running on another host may change package patch levels."
  )
  if (isTRUE(is_tcf_note)) {
    note_lines <- c(
      note_lines,
      "For TCF studies, list only packages used on the delivered analysis path;",
      "do not retain unused Cox/competing-risk template packages."
    )
  } else {
    note_lines <- c(
      note_lines,
      "List only packages used on the delivered analysis path;",
      "do not retain unused Cox/competing-risk/MICE template packages."
    )
  }
  if (length(footer)) {
    note_lines <- c(note_lines, "", footer)
  }
  lines <- c(lines, note_lines)
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
    exclude_pkgs = character(0),
    append_to = NULL,
    r_note = NULL
) {
  info <- pub_collect_software_versions(
    extra_pkgs = unique(c(
      names(roles %||% character(0)), as.character(extra_pkgs %||% character(0)),
      "gtsummary", "forestploter", "brglm2", "openxlsx"
    )),
    exclude_pkgs = exclude_pkgs
  )
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
      "Figures are exported under `Figures/{pdf,image_information}/` ",
      "(PDF + image_information by default; png/tiff only if explicitly enabled). ",
      "Display labels omit programming underscores; publication fonts use Times New Roman ",
      "(or Times-compatible embedded serif)."
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

#' 方法学 md 缺省正文。课题传入 methods_lines 时用课题稿，否则收口仍落盘这一份。
pub_default_methods_lines <- function(config = NULL) {
  st <- ""
  if (is.list(config)) {
    st <- as.character((config$project %||% list())$study_type %||% "")[1L]
  }
  c(
    "# Statistical analysis",
    "",
    "The analytic sample followed the study inclusion flowchart. Counts in tables are the unweighted number of participants unless a cell is labeled as a weighted percentage.",
    "Where sampling weights were used, models were fit with the survey design (strata, primary sampling units, and weights). Descriptive p values used survey-weighted tests.",
    "The exposure was entered as a continuous variable and as quantiles with the same cut points as the main regression table. The lowest quantile was the reference. Trend tests used the numeric quantile score.",
    if (nzchar(st)) paste0("Study type: ", st, ".") else NULL,
    "Model 1 and Model 2 covariates are those named in the main regression table footnote.",
    "Restricted cubic splines, ROC curves, subgroup forests, and mediation tables were produced when the corresponding blocks were run. Mediation rows list the laboratory indicators in the candidate pool. A negative proportion mediated is suppression, not mediation.",
    "Complete-case (unimputed) sensitivity tables were included in the summary supplementary tables when the SA_complete_case scenario completed successfully.",
    "Software name and package versions are in Methods_software_versions.txt and the Software subsection of this file.",
    ""
  )
}
