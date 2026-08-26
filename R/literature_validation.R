###############################################################################
#  literature_validation.R — 文献 Table/Figure 目标值对照
###############################################################################

literature_compare_metric <- function(computed, target, tol_pct = 15, label = "metric") {
  computed <- suppressWarnings(as.numeric(computed))
  target <- suppressWarnings(as.numeric(target))
  if (length(computed) != 1L || length(target) != 1L || is.na(computed) || is.na(target) ||
      !is.finite(computed) || !is.finite(target) || target == 0) {
    return(data.frame(
      label = label, computed = computed, literature = target,
      abs_diff = NA_real_, pct_diff = NA_real_, within_tol = NA,
      stringsAsFactors = FALSE
    ))
  }
  abs_diff <- abs(computed - target)
  pct_diff <- abs_diff / abs(target) * 100
  data.frame(
    label = label, computed = round(computed, 4), literature = round(target, 4),
    abs_diff = round(abs_diff, 4), pct_diff = round(pct_diff, 2),
    within_tol = pct_diff <= tol_pct,
    stringsAsFactors = FALSE
  )
}

literature_write_validation <- function(rows, out_path, meta = list()) {
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "empty")
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out_path, row.names = FALSE)
  if (length(meta)) {
    meta_path <- sub("\\.csv$", "_meta.json", out_path)
    tryCatch(jsonlite::write_json(meta, meta_path, auto_unbox = TRUE, pretty = TRUE),
             error = function(e) invisible(NULL))
  }
  tab
}

literature_fdr_adjust <- function(p, method = "BH") {
  p <- as.numeric(p)
  stats::p.adjust(p, method = method)
}

literature_batch_output_base <- function(ctx) {
  cfg <- ctx$config %||% list()
  sb <- cfg$study_batch %||% list()
  out <- cfg$project$output_dir %||% "Output"
  if (nzchar(sb$output_base %||% "")) out <- sb$output_base
  normalizePath(out, winslash = "/", mustWork = FALSE)
}

literature_find_table <- function(output_dir, filename, by_unit = TRUE) {
  output_dir <- normalizePath(output_dir, winslash = "/", mustWork = FALSE)
  candidates <- character(0)
  direct <- file.path(output_dir, "Tables", filename)
  if (file.exists(direct)) candidates <- c(candidates, direct)
  if (by_unit) {
    unit_root <- file.path(output_dir, "by_unit")
    if (dir.exists(unit_root)) {
      for (u in list.dirs(unit_root, recursive = FALSE, full.names = TRUE)) {
        for (sub in c("", "AI_QA_CoT", "CfTraj", "CfTraj/LCMM", "NetworkTemp")) {
          p <- if (nzchar(sub)) file.path(u, "Tables", sub, filename) else file.path(u, "Tables", filename)
          if (file.exists(p)) candidates <- c(candidates, p)
        }
      }
    }
    shared <- file.path(output_dir, "_shared", "Tables")
    if (dir.exists(shared)) {
      hits <- list.files(shared, pattern = paste0("^", gsub("\\.", "\\\\.", filename), "$"),
                         recursive = TRUE, full.names = TRUE)
      candidates <- c(candidates, hits)
    }
  }
  unique(candidates[file.exists(candidates)])
}

literature_read_batch_csvs <- function(output_dir, filename, by_unit = TRUE) {
  paths <- literature_find_table(output_dir, filename, by_unit = by_unit)
  if (!length(paths)) return(data.frame())
  tabs <- lapply(paths, function(p) {
    df <- utils::read.csv(p, stringsAsFactors = FALSE)
    df$.source_path <- p
    df
  })
  do.call(rbind, tabs)
}
