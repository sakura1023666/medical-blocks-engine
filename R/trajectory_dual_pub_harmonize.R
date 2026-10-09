###############################################################################
#  trajectory_dual_pub_harmonize.R — 轨迹双库发表表/图对齐（全项目复用）
#
#  自 AP WPR dual 对话沉淀。新课题走 config$trajectory_pub，勿再堆 fix_ap_*。
#
#  能力：
#    1) 单因素 xlsx 解析连续暴露 HR：优先含 p= 的单元格（避免抓 median IQR）
#    2) 双库 Table1/S1/S2/S3/S5 按 keep 名单或两库变量交集外科删行
#    3) 根目录只保留指定库的 Table3 / 分段 Cox 图
#    4) 去掉 Missing overview 后的默认 figure_stems（无 Missing）
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

#' 表内变量标签规范化（去单位后缀、下划线→空格）
trajectory_pub_norm_var_label <- function(x) {
  x <- trimws(as.character(x %||% ""))
  x[is.na(x)] <- ""
  x <- sub(",.*$", "", x)
  x <- gsub("_", " ", x)
  x <- gsub("\\s+", " ", x)
  trimws(x)
}

.trajectory_pub_default_sections <- function() {
  c(
    "Demographics", "Vital Signs", "Laboratory Tests", "Comorbidities",
    "Exposure", "Outcomes", "Characteristic", "Variable"
  )
}

.trajectory_pub_default_levels <- function() {
  c(
    "Female", "Male", "No", "Yes", "Missing (%)",
    "Asian", "Black", "Hispanic", "Other", "White",
    "Married", "Single/divorced", "English"
  )
}

#' 从单因素回归 xlsx 解析某变量的 HR (lo-hi)
#'
#' 优先选择同行中含 `p=` / `p<` 的单元格，避免把 median (IQR) 当成 HR。
trajectory_parse_uv_hr_cell <- function(xlsx, var_name) {
  if (!file.exists(xlsx)) return(NULL)
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(NULL)
  raw <- tryCatch(
    openxlsx::read.xlsx(xlsx, colNames = FALSE),
    error = function(e) NULL
  )
  if (is.null(raw) || !nrow(raw)) return(NULL)
  vn <- trajectory_pub_norm_var_label(var_name)
  hit <- which(apply(raw, 1L, function(r) {
    any(trajectory_pub_norm_var_label(r) == vn)
  }))
  if (!length(hit)) {
    hit <- which(apply(raw, 1L, function(r) {
      any(grepl(paste0("\\b", gsub("([.|()\\])", "\\\\\\1", vn), "\\b"),
                as.character(r), ignore.case = TRUE))
    }))
  }
  if (!length(hit)) return(NULL)
  row <- as.character(unlist(raw[hit[[1L]], , drop = TRUE]))
  row <- row[!is.na(row) & nzchar(row)]
  cell <- row[grepl("\\bp\\s*[=<>]", row, ignore.case = TRUE)][1L]
  if (is.na(cell) || !nzchar(cell)) {
    cells <- row[grepl("[0-9.]+\\s*\\(", row)]
    cell <- if (length(cells)) cells[[length(cells)]] else NA_character_
  }
  if (is.na(cell) || !nzchar(cell)) return(NULL)
  nums <- as.numeric(unlist(regmatches(
    cell, gregexpr("[0-9]+\\.[0-9]+|[0-9]+", cell)
  )))
  if (length(nums) < 3L) return(NULL)
  list(
    hr = nums[[1L]], lo = nums[[2L]], hi = nums[[3L]],
    cell = cell, var = vn, path = xlsx
  )
}

#' 提取发表表第一列的「当前变量」序列（跳过标题/分区/水平）
trajectory_xlsx_extract_var_labels <- function(path,
                                               kind = c("table1", "s1", "s2", "s3", "s5"),
                                               sections = NULL,
                                               levels = NULL) {
  kind <- match.arg(kind)
  if (!file.exists(path) || !requireNamespace("openxlsx", quietly = TRUE))
    return(character(0))
  d <- openxlsx::read.xlsx(path, colNames = FALSE)
  if (is.null(d) || !nrow(d)) return(character(0))
  sections <- sections %||% .trajectory_pub_default_sections()
  levels <- levels %||% .trajectory_pub_default_levels()
  c1 <- trajectory_pub_norm_var_label(d[[1L]])
  out <- character(0)
  current <- NA_character_
  for (i in seq_along(c1)) {
    lab <- c1[[i]]
    if (i == 1L || grepl("^Table ", lab, ignore.case = TRUE)) next
    if (lab %in% c("Characteristic", "Variable")) next
    if (grepl("^(Continuous variables|Statistical comparisons|Normality)", lab))
      next
    if (lab %in% sections) {
      current <- NA_character_
      next
    }
    is_level <- lab %in% levels || (identical(lab, "") && kind %in% c("s3", "s2"))
    if (kind == "s1" && identical(lab, "Missing (%)")) is_level <- TRUE
    if (!is_level && nzchar(lab)) {
      current <- lab
      out <- c(out, current)
    }
  }
  unique(out[nzchar(out)])
}

#' 外科删行：保留 keep_vars 上的变量块（及分区/标题行）
trajectory_xlsx_keep_var_rows <- function(path,
                                          keep_vars,
                                          kind = c("table1", "s1", "s2", "s3", "s5"),
                                          sections = NULL,
                                          levels = NULL,
                                          engine_root = NULL) {
  kind <- match.arg(kind)
  if (!file.exists(path)) return(invisible(integer(0)))
  keep_vars <- unique(trajectory_pub_norm_var_label(keep_vars))
  keep_vars <- keep_vars[nzchar(keep_vars)]
  if (!length(keep_vars)) return(invisible(integer(0)))
  if (!exists("pub_xlsx_delete_rows", mode = "function")) {
    root <- engine_root %||% getwd()
    fp <- file.path(root, "R/pub_xlsx_surgical.R")
    if (file.exists(fp)) source(fp, local = FALSE)
  }
  if (!exists("pub_xlsx_delete_rows", mode = "function")) {
    warning("pub_xlsx_delete_rows 不可用，跳过: ", basename(path))
    return(invisible(integer(0)))
  }
  if (!requireNamespace("openxlsx", quietly = TRUE)) return(invisible(integer(0)))
  sections <- sections %||% .trajectory_pub_default_sections()
  levels <- levels %||% .trajectory_pub_default_levels()
  d <- openxlsx::read.xlsx(path, colNames = FALSE)
  n <- nrow(d)
  c1 <- trajectory_pub_norm_var_label(d[[1L]])
  current <- NA_character_
  drop <- logical(n)
  for (i in seq_len(n)) {
    lab <- c1[[i]]
    if (i == 1L || grepl("^Table ", lab, ignore.case = TRUE)) next
    if (lab %in% c("Characteristic", "Variable")) next
    if (grepl("^(Continuous variables|Statistical comparisons|Normality)", lab))
      next
    if (lab %in% sections) {
      current <- NA_character_
      next
    }
    is_level <- lab %in% levels || (identical(lab, "") && kind %in% c("s3", "s2"))
    if (kind == "s1" && identical(lab, "Missing (%)")) is_level <- TRUE
    if (!is_level && nzchar(lab)) current <- lab
    if (is.na(current) || !nzchar(current)) next
    if (!current %in% keep_vars) drop[i] <- TRUE
  }
  rows <- which(drop)
  if (!length(rows)) return(invisible(integer(0)))
  pub_xlsx_delete_rows(path, rows, root = engine_root %||% getwd())
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "{basename(path)} 外科删 {length(rows)} 行（keep={length(keep_vars)} 变量）"
    )
  }
  invisible(rows)
}

#' 双库一对表：按显式 keep 或两库变量交集对齐行
trajectory_align_dual_table_pair <- function(path_a,
                                             path_b,
                                             keep_vars = NULL,
                                             kind = c("table1", "s1", "s2", "s3", "s5"),
                                             engine_root = NULL) {
  kind <- match.arg(kind)
  if (!file.exists(path_a) || !file.exists(path_b)) {
    return(invisible(list(ok = FALSE, keep = character(0))))
  }
  if (is.null(keep_vars) || !length(keep_vars)) {
    va <- trajectory_xlsx_extract_var_labels(path_a, kind = kind)
    vb <- trajectory_xlsx_extract_var_labels(path_b, kind = kind)
    keep_vars <- intersect(va, vb)
  } else {
    keep_vars <- trajectory_pub_norm_var_label(keep_vars)
  }
  if (!length(keep_vars)) {
    return(invisible(list(ok = FALSE, keep = character(0))))
  }
  trajectory_xlsx_keep_var_rows(
    path_a, keep_vars, kind = kind, engine_root = engine_root
  )
  trajectory_xlsx_keep_var_rows(
    path_b, keep_vars, kind = kind, engine_root = engine_root
  )
  invisible(list(ok = TRUE, keep = keep_vars))
}

#' 在指标根 Tables/ 上批量对齐双库同角色表
trajectory_align_dual_root_tables <- function(index_root,
                                              db_labs = c("MIMIC", "eICU"),
                                              kinds = c("table1", "s1", "s2", "s3", "s5"),
                                              keep_vars = NULL,
                                              patterns = NULL,
                                              engine_root = NULL) {
  tab <- file.path(index_root, "Tables")
  if (!dir.exists(tab)) return(invisible(list()))
  patterns <- patterns %||% list(
    table1 = "^Table 1-%s\\.",
    s1 = "^Table S1-%s\\.",
    s2 = "^Table S2-%s\\.",
    s3 = "^Table S3-%s\\.",
    s5 = "^Table S5-%s\\."
  )
  out <- list()
  for (kind in kinds) {
    pat_tpl <- patterns[[kind]]
    if (is.null(pat_tpl)) next
    files <- lapply(db_labs, function(lab) {
      hits <- list.files(tab, pattern = sprintf(pat_tpl, lab), full.names = TRUE)
      hits <- hits[!grepl("_archive", hits)]
      if (length(hits)) hits[[1L]] else NA_character_
    })
    if (anyNA(unlist(files))) next
    res <- trajectory_align_dual_table_pair(
      files[[1L]], files[[2L]],
      keep_vars = keep_vars, kind = kind, engine_root = engine_root
    )
    out[[kind]] <- res
  }
  invisible(out)
}

#' 根目录只保留指定库的 Table3（及其它可选模式）
trajectory_pub_keep_db_root_tables <- function(index_root,
                                               keep_db_lab = "MIMIC",
                                               patterns = c("^Table 3-")) {
  tab <- file.path(index_root, "Tables")
  if (!dir.exists(tab)) return(invisible(character(0)))
  removed <- character(0)
  for (pat in patterns) {
    hits <- list.files(tab, pattern = pat, full.names = TRUE)
    hits <- hits[!grepl("_archive", hits)]
    for (f in hits) {
      if (!grepl(paste0("-", keep_db_lab, "\\."), basename(f))) {
        unlink(f)
        removed <- c(removed, basename(f))
      }
    }
  }
  if (length(removed) && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "根 Tables 仅保留 {keep_db_lab}: 已删 {paste(removed, collapse = ', ')}"
    )
  }
  invisible(removed)
}

#' 无 Missing overview 的默认发表图白名单（主文 1–4 + 补图 KM 起编）
trajectory_paper_figure_stems_no_missing <- function(index_name = "Index",
                                                    extra = character(0)) {
  ix <- as.character(index_name %||% "Index")[1L]
  base <- c(
    "Figure 1. Flowchart of patient selection",
    sprintf("Figure 2. Trajectory of %s latent classes", ix),
    sprintf("Figure 3. Dynamic prediction of %s trajectory", ix),
    "Figure 4. Individual dynamic prediction",
    "Figure S1. Kaplan Meier survival by trajectory class",
    "Figure S2. Piecewise Cox cut point search",
    "Figure S3. Subgroup analysis by trajectory class",
    "Figure S4. Weibull dynamic model comparison AUC",
    "Figure S5. Weibull dynamic model comparison C index",
    "Figure S6. Weibull dynamic model comparison Accuracy",
    "Figure S7. Weibull dynamic model comparison Sensitivity",
    "Figure S8. Weibull dynamic model comparison Specificity"
  )
  extra <- as.character(extra %||% character(0))
  unique(c(base, extra))
}
