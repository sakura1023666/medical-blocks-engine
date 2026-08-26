#!/usr/bin/env Rscript
# 交叉滞后 summary_result/figure：多库拼图 + 四目录发表导出
args <- commandArgs(trailingOnly = TRUE)
study_root <- as.character(args[[1L]] %||% "")[1L]
if (!nzchar(study_root) || !dir.exists(study_root)) {
  stop("need existing study_root as first argument", call. = FALSE)
}

eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(eng)) {
  cand <- normalizePath(file.path(study_root, "../.."), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "R/utils.R"))) {
    eng <- cand
  } else {
    eng <- normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
}

source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
if (file.exists(file.path(eng, "R/cross_lagged_study_meta.R"))) {
  source(file.path(eng, "R/cross_lagged_study_meta.R"), local = FALSE)
}

fig <- file.path(study_root, "summary_result", "figure")
if (!dir.exists(fig)) {
  message("summary_result/figure 不存在，跳过 mosaic/export")
  quit(save = "no", status = 0)
}
dir.create(fig, recursive = TRUE, showWarnings = FALSE)

meta_g <- ""
if (exists("cross_lagged_study_meta", mode = "function")) {
  meta_g <- tryCatch(
    as.character(cross_lagged_study_meta(study_root)$grouping %||% "")[1L],
    error = function(e) ""
  )
}
if (!nzchar(meta_g)) {
  acc <- file.path(study_root, "phase3_relock_acceptance.txt")
  if (file.exists(acc)) {
    mg <- grep("^main_grouping=", readLines(acc, warn = FALSE), value = TRUE)
    if (length(mg)) meta_g <- sub("^main_grouping=", "", mg[1L])
  }
}

known_dbs <- c("CHARLS", "ELSA", "HRS", "NHANES", "CLHLS", "SHARE")
pdfs <- list.files(fig, pattern = "\\.pdf$", ignore.case = TRUE)
dbs <- character(0)
for (db in known_dbs) {
  if (any(grepl(paste0("-", db, "\\."), pdfs, ignore.case = TRUE))) {
    dbs <- c(dbs, db)
  }
}
if (exists("cross_lagged_study_meta", mode = "function")) {
  sm <- tryCatch(cross_lagged_study_meta(study_root), error = function(e) NULL)
  if (!is.null(sm)) {
    pref <- unique(c(sm$cohorts_xs %||% character(0), sm$cohorts_long %||% character(0)))
    pref <- pref[pref %in% dbs]
    dbs <- unique(c(pref, setdiff(dbs, pref)))
  }
}
dbs <- dbs[nzchar(dbs)]

cfg <- list(
  dual_db = list(
    combine_figures = list(enable = length(dbs) >= 2L, remove_singles = TRUE, dpi = 200L),
    databases = dbs,
    primary = list(name = if (length(dbs)) dbs[[1L]] else "primary"),
    secondary = list(name = if (length(dbs) >= 2L) dbs[[2L]] else "secondary"),
    tertiary = list(name = if (length(dbs) >= 3L) dbs[[3L]] else "")
  ),
  pub_figures = list(formats_dir = TRUE, dpi = 300L, write_image_information = TRUE)
)

tryCatch(
  dual_db_combine_paired_figures(study_root, cfg, figures_dir = fig),
  error = function(e) message("combine 跳过: ", conditionMessage(e))
)

tryCatch(
  export_pub_figures(
    fig,
    # n_by_db / n_total 可选：交叉滞后 collect 暂无 attrition 注入，md 常显示「未记录」
    meta = list(
      databases = dbs,
      combined = length(dbs) >= 2L,
      grouping = meta_g
    ),
    config = cfg
  ),
  error = function(e) message("export 跳过: ", conditionMessage(e))
)

message("export_summary_figures: ", fig)
