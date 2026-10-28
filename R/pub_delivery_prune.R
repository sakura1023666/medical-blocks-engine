###############################################################################
#  pub_delivery_prune — 交付根目录白名单（全项目复用）
#
#  客户交付目录（summary_result / summary_results / 指标级 summary_result）
#  根下只保留：
#    Figures/  Tables/
#    Methods_statistical_analysis.md
#    Methods_software_versions.txt
#    *中期*.pdf（中期分析结果）
#
#  其余（README、reports、content.json、_report_dump、项目信息、
#  Methods_software_section、根级 image_information 等）移到交付根的
#  **同级**归档目录 `<basename>_delivery_workspace/`（不进交付面、不删数据）。
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
