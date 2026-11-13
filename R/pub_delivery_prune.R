###############################################################################
#  pub_delivery_prune — 交付根目录白名单（全项目复用）
#
#  客户交付目录（summary_result / summary_results / 指标级 summary_result）
#  根下只保留（2026-11-13 与规则 pub_delivery_whitelist 对齐；全项目）：
#    Figures/  Tables/
#    Methods_statistical_analysis.md
#    Methods_software_versions.txt
#    *中期*.pdf（中期分析结果）
#
#  Shiny/ShinyApp/code/reports 等一律进同级 *_delivery_workspace/（不进交付面）。
###############################################################################

#' 判断是否为允许留在交付根的条目
#'
#' @param name 根下条目名
#' @param figures_tables_only TRUE 时仅 Figures/Tables（指标级 summary_results）
pub_delivery_keep_name <- function(name, figures_tables_only = FALSE) {
  name <- as.character(name %||% "")[1L]
  if (!nzchar(name)) return(FALSE)
  # 标准 Figures/Tables；兼容交叉滞后历史 figure/table（finalize 会规范为大写）
  if (name %in% c("Figures", "Tables", "figure", "table")) return(TRUE)
  if (isTRUE(figures_tables_only)) return(FALSE)
  if (identical(name, "Methods_statistical_analysis.md")) return(TRUE)
  if (identical(name, "Methods_software_versions.txt")) return(TRUE)
  # 中期 PDF（中英文文件名）
  if (grepl("\u4e2d\u671f", name, fixed = TRUE) && grepl("\\.pdf$", name, ignore.case = TRUE)) {
    return(TRUE)
  }
  if (grepl("(?i)midterm.*\\.pdf$", name, perl = TRUE)) return(TRUE)
  FALSE
}

#' figure/table → Figures/Tables（交付面统一）
#'
#' 注意：WSL/SMB 上对目录 `file.rename` 可能留下幽灵项；一律 copy + unlink。
pub_delivery_normalize_fig_tab_dirs <- function(delivery_root) {
  delivery_root <- as.character(delivery_root %||% "")[1L]
  if (!nzchar(delivery_root) || !dir.exists(delivery_root)) return(invisible(FALSE))
  pairs <- list(c("figure", "Figures"), c("table", "Tables"))
  for (pr in pairs) {
    low <- file.path(delivery_root, pr[[1L]])
    up <- file.path(delivery_root, pr[[2L]])
    if (!dir.exists(low)) next
    dir.create(up, recursive = TRUE, showWarnings = FALSE)
    for (f in list.files(low, full.names = TRUE, all.files = TRUE, no.. = TRUE)) {
      file.copy(f, file.path(up, basename(f)), recursive = TRUE, overwrite = TRUE)
    }
    unlink(low, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}

#' Tables 内只留发表 xlsx（中间 csv/rds 移出）
pub_delivery_clean_tables_xlsx_only <- function(delivery_root) {
  delivery_root <- as.character(delivery_root %||% "")[1L]
  tab <- file.path(delivery_root, "Tables")
  if (!dir.exists(tab)) tab <- file.path(delivery_root, "table")
  if (!dir.exists(tab)) return(invisible(character(0)))
  junk <- list.files(tab, full.names = TRUE, all.files = TRUE, no.. = TRUE)
  junk <- junk[!grepl("\\.xlsx$", junk, ignore.case = TRUE)]
  if (!length(junk)) return(invisible(character(0)))
  arch <- file.path(pub_delivery_archive_dir(delivery_root),
                    paste0("tables_non_xlsx_", format(Sys.time(), "%Y%m%d_%H%M%S")))
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)
  for (f in junk) {
    file.rename(f, file.path(arch, basename(f))) || {
      file.copy(f, file.path(arch, basename(f)), overwrite = TRUE, recursive = TRUE)
      unlink(f, recursive = TRUE)
    }
  }
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info("Tables 非 xlsx 已移出 {length(junk)} 项 -> {arch}")
  }
  invisible(junk)
}

#' 归档目录：交付根同级，避免客户打开 summary_result 仍看到工作区
pub_delivery_archive_dir <- function(delivery_root) {
  delivery_root <- normalizePath(delivery_root, winslash = "/", mustWork = TRUE)
  file.path(
    dirname(delivery_root),
    paste0(basename(delivery_root), "_delivery_workspace")
  )
}

#' 修剪交付根：非白名单移出到同级 `_delivery_workspace`
#'
#' @param delivery_root summary_result 等目录
#' @param dry_run 只列计划
#' @return list(kept, moved, archive)
pub_prune_delivery_root <- function(delivery_root,
                                    dry_run = FALSE,
                                    figures_tables_only = FALSE) {
  delivery_root <- as.character(delivery_root %||% "")[1L]
  if (!nzchar(delivery_root) || !dir.exists(delivery_root)) {
    stop("pub_prune_delivery_root: 目录不存在: ", delivery_root)
  }
  ents <- list.files(delivery_root, all.files = TRUE, no.. = TRUE)
  keep <- character(0)
  move <- character(0)
  for (nm in ents) {
    if (isTRUE(pub_delivery_keep_name(nm, figures_tables_only = figures_tables_only))) {
      keep <- c(keep, nm)
    } else {
      move <- c(move, nm)
    }
  }
  if (isTRUE(dry_run)) {
    message(
      "pub_prune_delivery_root dry_run\n  keep: ",
      paste(keep, collapse = ", "),
      "\n  move: ", paste(move, collapse = ", ")
    )
    return(invisible(list(kept = keep, moved = move, dry_run = TRUE)))
  }
  # 默认交付：Figures 内去掉遗留 png/tiff（与 pub_figure 默认一致）
  fig_dir <- file.path(delivery_root, "Figures")
  if (dir.exists(fig_dir)) {
    for (sub in c("png", "tiff")) {
      d <- file.path(fig_dir, sub)
      if (dir.exists(d)) unlink(d, recursive = TRUE, force = TRUE)
    }
    man <- file.path(fig_dir, "_rebuild_wang2025_manifest.json")
    if (file.exists(man)) {
      # 课题重建草稿不进交付面
      unlink(man)
    }
  }
  if (!length(move)) {
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_success("交付白名单已干净: {delivery_root}")
    }
    return(invisible(list(kept = keep, moved = character(0))))
  }
  arch <- pub_delivery_archive_dir(delivery_root)
  dir.create(arch, recursive = TRUE, showWarnings = FALSE)
  stamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  dest_batch <- file.path(arch, stamp)
  dir.create(dest_batch, recursive = TRUE, showWarnings = FALSE)
  for (nm in move) {
    from <- file.path(delivery_root, nm)
    to <- file.path(dest_batch, nm)
    if (file.rename(from, to)) next
    if (dir.exists(from)) {
      ok <- file.copy(from, dest_batch, recursive = TRUE, overwrite = TRUE)
      if (isTRUE(ok) || dir.exists(file.path(dest_batch, nm))) {
        unlink(from, recursive = TRUE)
      } else {
        warning("无法移动目录: ", from, call. = FALSE)
      }
    } else {
      ok <- file.copy(from, to, overwrite = TRUE)
      if (isTRUE(ok)) unlink(from) else warning("无法移动文件: ", from, call. = FALSE)
    }
  }
  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      "交付修剪: 移出 {length(move)} 项 -> {dest_batch}"
    )
  }
  invisible(list(kept = keep, moved = move, archive = dest_batch))
}

#' 交付 Tables 展示层禁下划线兜底（全项目收口统一入口）
#'
#' 导表路径应已走 `pipeline_scrub_pub_df`；本函数给已落盘 xlsx 做外科 scrub，
#' 挂在 `ml_finalize_index_summary_results` / `finalize_delivery_root` 等收口。
pub_delivery_scrub_tables_underscores <- function(delivery_root, root = NULL) {
  delivery_root <- as.character(delivery_root %||% "")[1L]
  if (!nzchar(delivery_root) || !dir.exists(delivery_root)) {
    return(invisible(list(n = 0L, skipped = TRUE)))
  }
  tab <- file.path(delivery_root, "Tables")
  if (!dir.exists(tab)) tab <- file.path(delivery_root, "table")
  if (!dir.exists(tab)) return(invisible(list(n = 0L, skipped = TRUE)))
  if (!exists("pub_xlsx_scrub_underscores_dir", mode = "function")) {
    eng <- as.character(root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""))[1L]
    if (!nzchar(eng)) eng <- getwd()
    sx <- file.path(eng, "R", "pub_xlsx_surgical.R")
    if (file.exists(sx)) {
      try(source(sx, local = FALSE), silent = TRUE)
    }
  }
  if (!exists("pub_xlsx_scrub_underscores_dir", mode = "function")) {
    return(invisible(list(n = 0L, error = "pub_xlsx_scrub_underscores_dir missing")))
  }
  out <- tryCatch(
    pub_xlsx_scrub_underscores_dir(tab, root = root),
    error = function(e) list(n = 0L, error = conditionMessage(e))
  )
  invisible(out)
}

#' 在指标根下的 summary_result / 课题 summary_result / summary_results 上修剪
pub_prune_project_delivery_roots <- function(project_root) {
  project_root <- as.character(project_root %||% "")[1L]
  if (!nzchar(project_root) || !dir.exists(project_root)) {
    return(invisible(list()))
  }
  cands <- c(
    file.path(project_root, "summary_result"),
    file.path(project_root, "summary_results")
  )
  by_ix <- file.path(project_root, "by_index")
  if (dir.exists(by_ix)) {
    for (d in list.files(by_ix, pattern = "^\u3010success\u3011", full.names = TRUE)) {
      cands <- c(
        cands,
        file.path(d, "summary_result"),
        file.path(d, "summary_results")
      )
    }
    ## 裸名指标根（finalize 前）
    for (d in list.files(by_ix, full.names = TRUE)) {
      if (!dir.exists(d)) next
      if (grepl("^\u3010", basename(d))) next
      cands <- c(
        cands,
        file.path(d, "summary_result"),
        file.path(d, "summary_results")
      )
    }
  }
  cands <- unique(cands[dir.exists(cands)])
  out <- lapply(cands, pub_prune_delivery_root)
  names(out) <- cands
  invisible(out)
}

message("loaded R/pub_delivery_prune.R")

#' 交付表禁中文：命中 CJK 的 sharedStrings 替换为英文占位或清空非 ASCII 段落
#'
#' 默认策略：用预置词典替换；未命中词典的 CJK 串改为 ASCII 说明 "[Chinese text removed]".
#' 发表交付面禁止中文（用户 2026-11-13）。
pub_xlsx_scrub_chinese <- function(path, dict = NULL) {
  path <- as.character(path %||% "")[1L]
  if (!nzchar(path) || !file.exists(path)) {
    stop("pub_xlsx_scrub_chinese: missing ", path, call. = FALSE)
  }
  if (is.null(dict)) {
    dict <- c(
      "AKI \u961f\u5217\u8bc6\u522b" = "AKI cohort identification",
      "\u4e3b\u5e93\u542b Acute Renal Failure \u65d7\u6807\u5217\uff08\u53d6\u503c Yes/No\uff09\uff0c\u636e\u6b64\u8bc6\u522b AKI \u961f\u5217" =
        "Primary database includes Acute Renal Failure flag (Yes/No) used to identify the AKI cohort",
      "D02 result MIMIC.RData\uff08\u5b9e\u6d4b\uff09" = "D02 result MIMIC.RData (verified)",
      "\u5df2\u8bc1\u5b9e" = "Verified",
      "Acute Renal Failure \u65d7\u6807\uff08Yes/No\uff09\uff1b\u5df2\u6838\u5b9e\u5b58\u5728\uff0cn=26,055" =
        "Acute Renal Failure flag (Yes/No); verified present, n=26,055",
      "\u968f\u8bbf/\u7ed3\u5c40" = "Follow-up / outcome",
      "\u7ed3\u5c40=28 \u5929\u5168\u56e0\u6b7b\u4ea1\uff08Survivor / Non-survivor\uff09\uff1b\u968f\u8bbf\u4e0a\u9650 28 \u5929\uff0c\u4e0d\u5b58\u5728\u4efb\u4f55\u66f4\u957f\u968f\u8bbf\u7a97" =
        "Outcome = 28-day all-cause mortality (Survivor / Non-survivor); follow-up censored at 28 days",
      "config \u7ed3\u5c40\u5217 fustatus / \u5f15\u64ce 0-1 \u6620\u5c04" =
        "Config outcome column fustatus / engine 0-1 mapping",
      "\u4e24\u5e93 fustatus 0/1 \u7ecf pipeline outcome as 01 \u6b63\u786e\u6620\u5c04\u6b7b\u4ea1=1\uff08Non-survivor\uff09" =
        "Both databases: fustatus 0/1 mapped via pipeline_outcome_as_01 (death=1, Non-survivor)",
      "eICU \u65e0 Acute Renal Failure \u5217\uff1b\u4f9d\u8d56\u4e0a\u6e38 D02 \u9884\u7b5b\u961f\u5217" =
        "eICU has no Acute Renal Failure column; cohort relies on upstream D02 pre-screen",
      "D02 result eICU.RData\uff08\u5b9e\u6d4b\uff09" = "D02 result eICU.RData (verified)",
      "\u8bc1\u636e\u4e0d\u8db3" = "Insufficient evidence",
      "\u65e0 Acute Renal Failure \u5217\uff1beICU \u961f\u5217\u4f9d\u8d56\u4e0a\u6e38 D02 \u9884\u7b5b\uff08\u7528\u6237\u786e\u8ba4\u5168\u90e8\u4e3a AKI\uff09\uff0c\u4f46\u4e0a\u6e38 ICD/KDIGO \u63d0\u53d6\u4ee3\u7801\u672a\u968f\u6570\u636e\u63d0\u4f9b\uff0c\u65e0\u6cd5\u5728\u6570\u636e\u5c42\u590d\u6838 \u2192 \u8bc1\u636e\u4e0d\u8db3\uff0c\u4e0d\u7f16\u9020 ICD" =
        "No Acute Renal Failure column; eICU cohort depends on upstream D02 pre-screen (user-confirmed AKI). Upstream ICD/KDIGO extraction code was not shipped with the data, so cohort definition cannot be re-verified at the data layer (insufficient evidence; no ICD codes invented).",
      "eICU \u4e0e MIMIC-IV \u540c\u7528 28 \u5929\u53e3\u5f84\uff1b\u5916\u9a8c\u51bb\u7ed3\u4e3b\u5e93\u8d44\u4ea7\u3001\u4e0d\u91cd\u8bad" =
        "eICU uses the same 28-day horizon as MIMIC-IV; external validation freezes primary-database assets without refitting",
      "\u7ee7\u627f\u81ea MIMIC-IV \u51bb\u7ed3\u8d44\u4ea7" = "Inherited from MIMIC-IV frozen assets"
    )
  }
  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("need openxlsx")
  if (exists("pub_xlsx_strip", mode = "function")) pub_xlsx_strip(path)
  wb <- openxlsx::loadWorkbook(path)
  n_edit <- 0L
  cjk_re <- "[\u4e00-\u9fff]"
  for (sh in openxlsx::sheets(wb)) {
    d <- tryCatch(openxlsx::read.xlsx(path, sheet = sh, colNames = FALSE),
                  error = function(e) NULL)
    if (is.null(d) || !nrow(d)) next
    for (i in seq_len(nrow(d))) {
      for (j in seq_len(ncol(d))) {
        v <- d[i, j]
        if (is.na(v) || (!is.character(v) && !is.factor(v))) next
        s0 <- as.character(v)
        if (!grepl(cjk_re, s0, perl = TRUE)) next
        s1 <- s0
        for (k in names(dict)) {
          if (grepl(k, s1, fixed = TRUE)) s1 <- gsub(k, dict[[k]], s1, fixed = TRUE)
        }
        if (grepl(cjk_re, s1, perl = TRUE)) {
          s1 <- gsub(cjk_re, "", s1, perl = TRUE)
          s1 <- gsub("\\s{2,}", " ", s1)
          s1 <- trimws(s1)
          if (!nzchar(s1)) s1 <- "[Chinese text removed]"
        }
        if (!identical(s0, s1)) {
          openxlsx::writeData(wb, sh, s1, startCol = j, startRow = i, colNames = FALSE)
          n_edit <- n_edit + 1L
        }
      }
    }
  }
  if (n_edit > 0L) {
    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
    if (exists("pub_xlsx_strip", mode = "function")) pub_xlsx_strip(path)
  }
  invisible(list(path = path, n_edit = n_edit))
}

pub_xlsx_scrub_chinese_dir <- function(tab_dir) {
  tab_dir <- as.character(tab_dir %||% "")[1L]
  if (!nzchar(tab_dir) || !dir.exists(tab_dir)) return(invisible(list(n = 0L)))
  files <- list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)
  out <- lapply(files, function(f) tryCatch(pub_xlsx_scrub_chinese(f),
                                            error = function(e) list(path = f, error = e$message)))
  invisible(list(n = length(files), results = out))
}

#' image_information 展示层禁下划线（不改章节标题结构）
pub_delivery_scrub_image_information <- function(delivery_root) {
  delivery_root <- as.character(delivery_root %||% "")[1L]
  imd <- file.path(delivery_root, "Figures", "image_information")
  if (!dir.exists(imd)) return(invisible(list(n = 0L)))
  files <- list.files(imd, pattern = "\\.md$", full.names = TRUE)
  n <- 0L
  for (f in files) {
    t0 <- readLines(f, warn = FALSE, encoding = "UTF-8")
    t1 <- gsub("_", " ", t0, fixed = TRUE)
    # 恢复统计标注白名单
    t1 <- gsub("P linear", "P_linear", t1, fixed = TRUE)
    t1 <- gsub("P nonlinear", "P_nonlinear", t1, fixed = TRUE)
    t1 <- gsub("P overall", "P_overall", t1, fixed = TRUE)
    if (!identical(t0, t1)) {
      writeLines(t1, f, useBytes = TRUE)
      n <- n + 1L
    }
  }
  invisible(list(n = n, dir = imd))
}

#' 交付面一键展示层 scrub（下划线 + 中文表 + image_information）
#'
#' 优先走 `python/pub_xlsx_scrub_display.py`（处理标题行 / 悬空 drawing / CJK 词典）；
#' 失败时回退 R 外科 scrub。
pub_delivery_scrub_display <- function(delivery_root, root = NULL) {
  delivery_root <- as.character(delivery_root %||% "")[1L]
  tab <- file.path(delivery_root, "Tables")
  py_res <- NULL
  if (dir.exists(tab)) {
    eng <- as.character(root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""))[1L]
    if (!nzchar(eng)) eng <- getwd()
    py_script <- file.path(eng, "python", "pub_xlsx_scrub_display.py")
    py <- Sys.which("python3")
    if (!nzchar(py)) py <- Sys.which("python")
    if (nzchar(py) && file.exists(py_script)) {
      st <- tryCatch(
        system2(
          py,
          vapply(c(py_script, "--dir", tab), shQuote, character(1L)),
          stdout = TRUE, stderr = TRUE
        ),
        error = function(e) structure(conditionMessage(e), status = 1L)
      )
      py_res <- list(ok = is.null(attr(st, "status")) || identical(as.integer(attr(st, "status")), 0L),
                     log = st)
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_info("pub_xlsx_scrub_display.py: {paste(utils::tail(st, 3), collapse = ' | ')}")
      }
    }
  }
  u <- list(n = 0L)
  cjk <- list(n = 0L)
  if (!isTRUE(py_res$ok)) {
    u <- if (dir.exists(tab) && exists("pub_xlsx_scrub_underscores_dir", mode = "function")) {
      pub_xlsx_scrub_underscores_dir(tab, root = root)
    } else list(n = 0L)
    cjk <- if (dir.exists(tab)) pub_xlsx_scrub_chinese_dir(tab) else list(n = 0L)
  }
  im <- pub_delivery_scrub_image_information(delivery_root)
  invisible(list(python = py_res, underscore = u, chinese = cjk, image_information = im))
}
