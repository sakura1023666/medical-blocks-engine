#!/usr/bin/env Rscript
# Fix Table S9: parser previously grabbed WPR median (IQR) instead of HR cell.
#   Rscript run/trajectory_prognosis/fix_ap_wpr_dual_table_s9.R

suppressPackageStartupMessages({
  library(dplyr)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/trajectory_survival_utils.R"), local = FALSE)

block_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
index_root <- file.path(
  block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual/by_index/WPR"
)
tab_root <- file.path(index_root, "Tables")
stopifnot(dir.exists(index_root))

.parse_s3_wpr_hr <- function(xlsx) {
  if (!file.exists(xlsx)) return(NULL)
  raw <- tryCatch(
    openxlsx::read.xlsx(xlsx, colNames = FALSE),
    error = function(e) NULL
  )
  if (is.null(raw) || !nrow(raw)) return(NULL)
  hit <- which(apply(raw, 1L, function(r) any(grepl("^\\s*WPR\\s*$", as.character(r)))))
  if (!length(hit)) {
    hit <- which(apply(raw, 1L, function(r) any(grepl("\\bWPR\\b", as.character(r)))))
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
  list(hr = nums[[1L]], lo = nums[[2L]], hi = nums[[3L]], cell = cell)
}

.rebuild_s9 <- function(db, db_lab) {
  s3_cands <- c(
    file.path(tab_root, sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab)),
    file.path(index_root, db, "Tables",
              sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab))
  )
  s3_path <- s3_cands[file.exists(s3_cands)][1L]
  stopifnot(nzchar(s3_path), file.exists(s3_path))
  hr <- .parse_s3_wpr_hr(s3_path)
  stopifnot(!is.null(hr))

  jlcm_path <- file.path(
    index_root, db, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData"
  )
  index_path <- file.path(
    block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual/data", db, "12_WPR.RData"
  )
  stopifnot(file.exists(jlcm_path), file.exists(index_path))
  e <- new.env(parent = emptyenv())
  load(jlcm_path, envir = e)
  model_data_final <- e$model_data_final
  e_ix <- new.env(parent = emptyenv())
  load(index_path, envir = e_ix)
  index_df <- e_ix$index_df
  ids <- unique(as.character(model_data_final$subject_id))
  w1 <- as.numeric(index_df$WPR_1[as.character(index_df$subject_id) %in% ids])
  sdw <- stats::sd(w1, na.rm = TRUE)

  rescale <- function(delta, label) {
    data.frame(
      Contrast = label,
      HR_CI = sprintf("%.3f (%.3f-%.3f)", hr$hr^delta, hr$lo^delta, hr$hi^delta),
      stringsAsFactors = FALSE
    )
  }
  s9 <- dplyr::bind_rows(
    data.frame(
      Contrast = "Per +1.00 unit (as in Table S3)",
      HR_CI = sprintf("%.3f (%.3f-%.3f)", hr$hr, hr$lo, hr$hi),
      stringsAsFactors = FALSE
    ),
    rescale(0.01, "Per +0.01 unit"),
    rescale(0.05, "Per +0.05 unit"),
    rescale(sdw, sprintf("Per +1 SD (SD=%.4f of baseline WPR_1)", sdw))
  )
  s9_title <- sprintf(
    "Table S9-%s. Rescaled univariable HRs for continuous baseline WPR",
    db_lab
  )
  s9_fp <- file.path(tab_root, paste0(s9_title, ".xlsx"))
  export_sci_table(
    s9, s9_fp, title = s9_title, sheet = "TableS9",
    table_footnotes = list(
      sprintf(
        "Source: univariable Cox HR for WPR in Table S3-%s (per +1 unit = %.3f, 95%%CI %.3f-%.3f).",
        db_lab, hr$hr, hr$lo, hr$hi
      ),
      "Rescaling uses HR(delta)=HR(1)^delta.",
      sprintf(
        "Baseline WPR_1 SD in JLCM analysis set (n=%d): %.4f.",
        sum(is.finite(w1)), sdw
      ),
      "Prefer reporting per +0.01 or per 1 SD in the main text; per +1 unit retained for audit."
    )
  )
  db_tab <- file.path(index_root, db, "Tables")
  dir.create(db_tab, recursive = TRUE, showWarnings = FALSE)
  file.copy(s9_fp, file.path(db_tab, basename(s9_fp)), overwrite = TRUE)
  cli::cli_alert_success(
    "[{db_lab}] S9 from S3 cell={hr$cell} → {basename(s9_fp)}"
  )
  print(s9)
  invisible(list(hr = hr, sdw = sdw, s9 = s9, path = s9_fp))
}

res_m <- .rebuild_s9("mimic", "MIMIC")
res_e <- .rebuild_s9("eicu", "eICU")

if (exists("render_queued_tables", mode = "function")) {
  ctx <- list(config = list(project = list(database = "eICU+MIMIC")))
  tryCatch(render_queued_tables(ctx), error = function(e) {
    cli::cli_alert_warning("render_queued_tables: {e$message}")
  })
}

cli::cli_alert_info(
  "MIMIC HR={res_m$hr$hr} vs eICU HR={res_e$hr$hr} — tables must differ"
)
