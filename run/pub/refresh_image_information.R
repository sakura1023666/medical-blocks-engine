#!/usr/bin/env Rscript
# =============================================================================
#  批量补刷发表图 image_information（详细图面说明；无「标识」「技术」）
#
#  用法（引擎根目录）:
#    Rscript run/pub/refresh_image_information.R --root "/mnt/g/02block_result"
#    Rscript run/pub/refresh_image_information.R --dir ".../by_index/【success】APRI/Figures"
#    Rscript run/pub/refresh_image_information.R --root "/mnt/g/02block_result" --dry-run
#
#  行为:
#    扫描 <root> 下 */Figures（含 pdf/ 子目录）与 summary_result/figure，
#    调用 pub_figure_refresh_image_information 重写 md（不重新栅格化）。
# =============================================================================

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[[1L]])
    return(normalizePath(file.path(dirname(fp), "..", ".."), winslash = "/", mustWork = FALSE))
  }
  normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(root = NULL, dir = NULL, dry_run = FALSE)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--root" && i < length(args)) {
      opts$root <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--dir" && i < length(args)) {
      opts$dir <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--dry-run") {
      opts$dry_run <- TRUE; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  opts
}

.guess_meta <- function(figures_dir) {
  index_root <- dirname(figures_dir)
  ix <- sub("^【[^】]+】", "", basename(index_root))
  meta <- list(
    exposure = if (nzchar(ix) && !identical(ix, "Figures")) ix else "",
    outcome = "",
    databases = character(0),
    combined = FALSE,
    grouping = ""
  )
  # 分库子目录暗示拼图
  dbs <- intersect(c("eICU", "MIMIC", "NHANES", "CHARLS", "ELSA", "HRS"),
                   list.files(index_root))
  if (length(dbs) >= 2L) {
    meta$databases <- dbs
    meta$combined <- TRUE
  } else if (length(dbs) == 1L) {
    meta$databases <- dbs
  }
  st_path <- file.path(index_root, "_batch_status.json")
  if (file.exists(st_path) && requireNamespace("jsonlite", quietly = TRUE)) {
    st <- tryCatch(jsonlite::fromJSON(st_path), error = function(e) NULL)
    if (!is.null(st)) {
      n_e <- suppressWarnings(as.integer(st$n_nhanes_after %||% NA_integer_))
      n_m <- suppressWarnings(as.integer(st$n_mimic_after %||% NA_integer_))
      nb <- integer(0)
      if (is.finite(n_e)) nb[["eICU"]] <- n_e
      if (is.finite(n_m)) nb[["MIMIC"]] <- n_m
      if (length(nb)) {
        meta$n_by_db <- nb
        meta$n_total <- sum(as.integer(nb), na.rm = TRUE)
      }
      if (!length(meta$databases) && length(nb) >= 2L) {
        meta$databases <- names(nb)
        meta$combined <- TRUE
      }
    }
  }
  # 邻近 config：尽量读结局/分位
  study_root <- dirname(dirname(index_root))
  if (basename(dirname(index_root)) == "by_index") {
    study_root <- dirname(dirname(index_root))
  }
  cfgs <- list.files(study_root, pattern = "^config_.*\\.R$", full.names = TRUE)
  if (length(cfgs)) {
    # 不 source（副作用大）；用正则抽字段
    txt <- paste(readLines(cfgs[[1L]], warn = FALSE), collapse = "\n")
    m_ev <- regmatches(txt, regexpr('event_var\\s*=\\s*"([^"]+)"', txt, perl = TRUE))
    if (length(m_ev) && nzchar(m_ev)) {
      meta$outcome <- sub('.*"([^"]+)".*', "\\1", m_ev)
    }
    if (!nzchar(meta$outcome)) {
      m_oc <- regmatches(txt, regexpr('outcome_column\\s*=\\s*"([^"]+)"', txt, perl = TRUE))
      if (length(m_oc) && nzchar(m_oc)) {
        meta$outcome <- sub('.*"([^"]+)".*', "\\1", m_oc)
      }
    }
    if (grepl("quartile", txt, ignore.case = TRUE) &&
        grepl("extend_quartile|cox_quartile|grouping\\s*=\\s*\"quartile\"", txt, ignore.case = TRUE)) {
      meta$grouping <- "quartile"
    } else if (grepl("grouping\\s*=\\s*\"tertile\"", txt, ignore.case = TRUE)) {
      meta$grouping <- "tertile"
    }
  }
  if (!nzchar(meta$grouping) && grepl("quartile", paste(list.files(file.path(figures_dir, "pdf")), collapse = " "), ignore.case = TRUE)) {
    meta$grouping <- "quartile"
  }
  meta
}

.find_figures_dirs <- function(root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  # 用 R 递归但限层：by_index/*/Figures、summary_result/figure、Output/Figures
  out <- character(0)
  # disease → study → by_index → index → Figures
  studies <- list.dirs(root, full.names = TRUE, recursive = FALSE)
  for (dis in studies) {
    subs <- list.dirs(dis, full.names = TRUE, recursive = FALSE)
    for (st in subs) {
      # by_index/<ix>/Figures
      bi <- file.path(st, "by_index")
      if (dir.exists(bi)) {
        for (ix in list.dirs(bi, full.names = TRUE, recursive = FALSE)) {
          fd <- file.path(ix, "Figures")
          if (dir.exists(file.path(fd, "pdf"))) out <- c(out, fd)
        }
      }
      # summary_result/figure
      sf <- file.path(st, "summary_result", "figure")
      if (dir.exists(file.path(sf, "pdf"))) out <- c(out, sf)
      # Output/Figures
      of <- file.path(st, "Output", "Figures")
      if (dir.exists(file.path(of, "pdf"))) out <- c(out, of)
      # 课题根 Figures（少见）
      rf <- file.path(st, "Figures")
      if (dir.exists(file.path(rf, "pdf"))) out <- c(out, rf)
    }
  }
  unique(normalizePath(out, winslash = "/", mustWork = FALSE))
}

root_engine <- .init_root()
opts <- .parse_args(commandArgs(trailingOnly = TRUE))
source(file.path(root_engine, "R", "utils.R"), local = FALSE)
source(file.path(root_engine, "R", "pub_figure_export.R"), local = FALSE)

targets <- character(0)
if (!is.null(opts$dir) && nzchar(opts$dir)) {
  targets <- normalizePath(opts$dir, winslash = "/", mustWork = TRUE)
} else if (!is.null(opts$root) && nzchar(opts$root)) {
  message("扫描: ", opts$root)
  targets <- .find_figures_dirs(opts$root)
} else {
  stop("请指定 --root <02block_result> 或 --dir <Figures 目录>", call. = FALSE)
}

message("待补刷 Figures 目录: ", length(targets))
ok <- 0L
fail <- 0L
for (fd in targets) {
  message("→ ", fd)
  if (isTRUE(opts$dry_run)) next
  meta <- .guess_meta(fd)
  res <- tryCatch(
    pub_figure_refresh_image_information(fd, meta = meta),
    error = function(e) {
      message("  ! ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(res)) {
    fail <- fail + 1L
  } else {
    ok <- ok + 1L
    message("  重写 ", length(res), " 个 md")
  }
}
message("完成: ok=", ok, " fail=", fail, if (isTRUE(opts$dry_run)) " (dry-run)" else "")
