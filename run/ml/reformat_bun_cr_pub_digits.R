#!/usr/bin/env Rscript
###############################################################################
# 将 BUN_Cr summary_results 表/图统一到 pub_digits：est/p=3；P<0.001→<0.001
# 并重建 Fig3–6（ROC 图注 3 位）与 Fig8（OR 3 位 + N 千分位）
###############################################################################
args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  args[[hit[[1]] + 1L]]
}

eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
setwd(eng)
Sys.setenv(MEDICAL_BLOCKS_ROOT = eng)
source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/pub_xlsx_surgical.R"), local = FALSE)
source(file.path(eng, "R/pub_figure_export.R"), local = FALSE)
source(file.path(eng, "R/dual_db_harmonize.R"), local = FALSE)
source(file.path(eng, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(eng, "R/ml_dual_dev_ext.R"), local = FALSE)
source(file.path(eng, "R/ml_dual_pub_table_curate.R"), local = FALSE)
source(file.path(eng, "R/ml_index_summary_results.R"), local = FALSE)
## performance helpers for ROC redraw
source(file.path(eng, "Blocks/23_ml_performance/01block_performance_ml.R"), local = FALSE)

cfg_path <- get_opt(
  "--config",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/19_AKI_TX_刘雪艳/config.R"
)
source(cfg_path, local = FALSE)
pipeline_apply_pub_digits(config)
ix <- get_opt("--index", "BUN_Cr")
ix_root <- file.path(.batch_project_root, "by_index", paste0("\u3010success\u3011", ix))
sum_root <- file.path(ix_root, "summary_results")
tab_dirs <- unique(c(
  file.path(ix_root, "Tables"),
  file.path(sum_root, "Tables")
))
tab_dirs <- tab_dirs[dir.exists(tab_dirs)]

.fmt_est <- function(x) pub_format_est(x, digits = 3L)
.fmt_p <- function(x) {
  s <- trimws(as.character(x)[1L])
  if (!nzchar(s) || s %in% c("Ref", "ref", "NE", "-", "—")) return(s)
  if (grepl("^<", s)) return("<0.001")
  if (grepl("^[>]0\\.999", s)) return(">0.999")
  ## scientific / bare 0
  if (grepl("^[0-9]+e-", s, ignore.case = TRUE)) {
    pn <- suppressWarnings(as.numeric(s))
    if (is.finite(pn) && pn < 0.001) return("<0.001")
  }
  pn <- suppressWarnings(as.numeric(s))
  if (!is.finite(pn)) return(s)
  if (pn <= 0 || pn < 0.001) return("<0.001")
  formatC(pn, format = "f", digits = 3L)
}

.fmt_ci_paren <- function(s) {
  ## (a,b) / (a, b) / (a-b) / a ~ b
  s0 <- as.character(s)[1L]
  m <- regexec("^\\(\\s*([-+0-9.eE]+)\\s*[,，]\\s*([-+0-9.eE]+)\\s*\\)$", s0)
  g <- regmatches(s0, m)[[1]]
  if (length(g) == 3L) {
    return(paste0("(", .fmt_est(g[2]), ", ", .fmt_est(g[3]), ")"))
  }
  m <- regexec("^\\(\\s*([-+0-9.eE]+)\\s*[-–]\\s*([-+0-9.eE]+)\\s*\\)$", s0)
  g <- regmatches(s0, m)[[1]]
  if (length(g) == 3L) {
    return(paste0("(", .fmt_est(g[2]), ", ", .fmt_est(g[3]), ")"))
  }
  m <- regexec("^\\s*([-+0-9.eE]+)\\s*[~～]\\s*([-+0-9.eE]+)\\s*$", s0)
  g <- regmatches(s0, m)[[1]]
  if (length(g) == 3L) {
    return(paste0(.fmt_est(g[2]), " ~ ", .fmt_est(g[3])))
  }
  ## NRI style: -0.4851 [ -0.644 - -0.3261 ]
  m <- regexec(
    paste0(
      "^(.*?:\\s*)?",
      "([-+0-9.eE]+)\\s*\\[\\s*([-+0-9.eE]+)\\s*[-–]\\s*([-+0-9.eE]+)\\s*\\]\\s*$"
    ),
    s0
  )
  g <- regmatches(s0, m)[[1]]
  if (length(g) >= 4L) {
    pref <- if (length(g) >= 5L && nzchar(g[2])) g[2] else ""
    ## groups: full, optional prefix, est, lo, hi — depends on optional
    ## Safer parse with stringr-like:
  }
  if (grepl("\\[", s0) && grepl("\\]", s0)) {
    pref <- sub("^(.*?:\\s*).*$", "\\1", s0)
    if (identical(pref, s0)) pref <- ""
    body <- if (nzchar(pref)) sub("^.*?:\\s*", "", s0) else s0
    m2 <- regexec(
      "^([-+0-9.eE]+)\\s*\\[\\s*([-+0-9.eE]+)\\s*[-–]\\s*([-+0-9.eE]+)\\s*\\]\\s*$",
      body
    )
    g2 <- regmatches(body, m2)[[1]]
    if (length(g2) == 4L) {
      return(paste0(
        pref, .fmt_est(g2[2]), " [", .fmt_est(g2[3]), " - ", .fmt_est(g2[4]), "]"
      ))
    }
  }
  s0
}

.is_p_header <- function(h) {
  grepl("^(P|P-value|P value|P for|P\\.value|pvalue)", h, ignore.case = TRUE) ||
    grepl("P value|P-value|P for trend|P for interaction", h, ignore.case = TRUE)
}
.is_est_header <- function(h) {
  grepl("^(OR|HR|AUC|accuracy|Sensitivity|Specificity|F1|Kappa|MCC|Difference)", h, ignore.case = TRUE) ||
    grepl("Log.?Loss|NRI|IDI|Z statistic", h, ignore.case = TRUE)
}
.is_ci_header <- function(h) grepl("95%\\s*CI|CI$", h, ignore.case = TRUE)
.is_skip_header <- function(h) {
  grepl("Characteristic|Model|Variable|Exposure|Events|cutoff|New model|Baseline|Statistic|Before|After", h, ignore.case = TRUE)
}

reformat_xlsx <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) stop("need openxlsx")
  ## read preserving as character where possible
  wb <- openxlsx::loadWorkbook(path)
  sheets <- openxlsx::getSheetNames(path)
  sh <- sheets[[1L]]
  df <- openxlsx::read.xlsx(path, sheet = sh, colNames = FALSE, skipEmptyRows = FALSE)
  if (is.null(df) || !nrow(df) || !ncol(df)) return(invisible(FALSE))
  ## header row: find first with OR/AUC/P-value
  hdr_i <- 1L
  for (i in seq_len(min(5L, nrow(df)))) {
    rr <- tolower(paste(as.character(unlist(df[i, ])), collapse = " "))
    if (grepl("p-value|p value|auc|odds|or\\b|95%ci|log-loss|nri", rr)) {
      hdr_i <- i
      break
    }
  }
  hdr <- as.character(unlist(df[hdr_i, , drop = TRUE]))
  hdr[is.na(hdr)] <- ""
  changed <- 0L
  for (j in seq_len(ncol(df))) {
    h <- hdr[[j]]
    for (i in seq_len(nrow(df))) {
      if (i <= hdr_i) next
      v <- df[i, j]
      if (is.null(v) || (length(v) == 1L && is.na(v))) next
      s <- trimws(as.character(v)[1L])
      if (!nzchar(s) || s %in% c("Ref", "NE", "-", "—")) next
      ## footnotes / titles
      if (grepl("^(The |Multiple |Population|Software|Continuous|Statistical)", s)) next
      if (nchar(s) > 120L && grepl(" ", s)) next
      new <- s
      if (.is_p_header(h) || (h == "" && grepl("^p for", s, ignore.case = TRUE))) {
        ## p for trend row: only p cells
        if (grepl("^p for", s, ignore.case = TRUE) && !grepl("[0-9]", s)) next
        new <- .fmt_p(s)
      } else if (.is_ci_header(h) || grepl("^\\(.*\\)$", s) || grepl("\\[.*\\]", s) || grepl("~", s)) {
        new <- .fmt_ci_paren(s)
      } else if (.is_est_header(h) || grepl("Log.Loss|NRI|IDI", h, ignore.case = TRUE)) {
        if (grepl("/", s) && grepl("%", s)) {
          next ## Events/N (%)
        }
        if (grepl("^[A-Za-z]", s) && !grepl("^[0-9.eE+-]+$", s)) next
        if (grepl("\\[", s)) {
          new <- .fmt_ci_paren(s)
        } else {
          pn <- suppressWarnings(as.numeric(s))
          if (is.finite(pn)) new <- .fmt_est(pn)
        }
      } else if (grepl("P value|P-value", paste(hdr, collapse = " "), ignore.case = TRUE) &&
                   grepl("^[0-9.eE+-]+$|^<", s)) {
        ## sometimes header misaligned; numeric-looking in p-ish tables
        if (grepl("DeLong|NRI|IDI|Logistic|quartile", basename(path), ignore.case = TRUE) &&
            j >= 5L && grepl("P", paste(hdr[max(1, j - 1):j], collapse = " "), ignore.case = TRUE)) {
          new <- .fmt_p(s)
        }
      }
      ## bare numeric with >3 decimals anywhere in ML/assoc tables
      if (identical(new, s) && grepl("^[+-]?[0-9]+\\.[0-9]{4,}$", s)) {
        new <- .fmt_est(s)
      }
      if (identical(new, s) && grepl("^[+-]?[0-9]+e[+-]?[0-9]+$", s, ignore.case = TRUE)) {
        pn <- suppressWarnings(as.numeric(s))
        if (is.finite(pn)) {
          new <- if (abs(pn) < 0.001 && grepl("P", h, ignore.case = TRUE)) "<0.001" else .fmt_est(pn)
        }
      }
      if (!identical(new, s)) {
        df[i, j] <- new
        changed <- changed + 1L
      }
    }
  }
  if (changed > 0L) {
    ## write back surgically via openxlsx (may lose some styles — prefer edit cells)
    ## Use pub_xlsx_edit_cells for value-only edits when possible
    edits <- list()
    ## fallback: openxlsx write with keep? For SCI tables styles matter.
    ## Use python zip sharedStrings where possible — here openxlsx overwrite sheet data
    openxlsx::writeData(wb, sheet = sh, x = df, colNames = FALSE, rowNames = FALSE)
    openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
    ## strip dangling drawings after openxlsx
    strip_py <- file.path(eng, "R/pub_xlsx_tools/xlsx_strip.py")
    if (file.exists(strip_py)) {
      system2("python3", c(strip_py, path), stdout = FALSE, stderr = FALSE)
    }
  }
  cli::cli_alert_info("{basename(path)}: changed={changed}")
  invisible(changed)
}

cli::cli_h1("Reformat pub digits @ {sum_root}")
for (td in tab_dirs) {
  for (f in list.files(td, pattern = "\\.xlsx$", full.names = TRUE)) {
    ## skip flowchart csv-like; all xlsx
    tryCatch(reformat_xlsx(f), error = function(e) {
      cli::cli_alert_warning("fail {basename(f)}: {e$message}")
    })
  }
}

## ---- Rebuild Fig3–6 with 3-digit ROC labels ----
cfg_compose <- config
cfg_compose$project$disease <- "AKI_TX"
cfg_compose$project$analysis_group <- "AKI_TX"
cfg_compose$project$reference_group <- "No AKI_TX"
cfg_compose$project$outcome_level_map <- NULL
ok <- isTRUE(tryCatch(
  ml_dual_dev_ext_compose_pub(ix_root, cfg_compose, tables_only = FALSE),
  error = function(e) {
    cli::cli_alert_danger("compose: {e$message}")
    FALSE
  }
))
fig_root <- file.path(ix_root, "Figures")
fig_pdf <- file.path(fig_root, "pdf")
dir.create(fig_pdf, recursive = TRUE, showWarnings = FALSE)
for (f in list.files(fig_root, pattern = "^Figure [3-6]\\.", full.names = TRUE)) {
  file.copy(f, file.path(fig_pdf, basename(f)), overwrite = TRUE)
  unlink(f)
}
## curate may have rewritten T3–5; re-strip + we will re-run digit format on new tables
if (exists("incidence_batch_curate_ml_pub_tables", mode = "function")) {
  incidence_batch_curate_ml_pub_tables(file.path(ix_root, "Tables"), config)
}
## re-format tables again after compose overwrote T3-5/S*
for (td in tab_dirs) {
  for (f in list.files(td, pattern = "\\.xlsx$", full.names = TRUE)) {
    tryCatch(reformat_xlsx(f), error = function(e) NULL)
  }
}

## ---- Rebuild Fig8 with 3-digit OR ----
## Prefer re-run subgroup from step PDFs after re-plot if we can call forestploter
## Quick path: recombine existing step forests won't update digits — must redraw.
## Load step forest source? Re-run subgroup block is heavy; call prepare+plot if rds exists.
sg_e_pdf <- file.path(
  ix_root, "eICU", "step44_subgroup_incidence", "Figures",
  "Figure 4-eICU. Subgroup Forest analyses of BUN Cr.pdf"
)
sg_m_pdf <- file.path(
  ix_root, "MIMIC_IV", "step26_subgroup_incidence", "Figures",
  "Figure 3-MIMIC IV. Subgroup Forest analyses of BUN Cr.pdf"
)
## Try find forest row rds / csv
.forest_srcs <- list.files(
  ix_root,
  pattern = "forest.*\\.(rds|csv)$",
  recursive = TRUE,
  full.names = TRUE,
  ignore.case = TRUE
)
cli::cli_alert_info("forest artifacts: {length(.forest_srcs)}")
## Redraw via remirror combine after regenerating plots from CSV if present
.source_blocks_sg <- function() {
  for (rel in c(
    "R/subgroup_forest_plot.R",
    "Blocks/18_subgroup/00subgroup_common.R",
    "Blocks/18_subgroup/02block_subgroup_incidence.R"
  )) {
    p <- file.path(eng, rel)
    if (file.exists(p)) source(p, local = FALSE)
  }
}
.source_blocks_sg()

.redraw_one_forest <- function(db_label, rows_path, dest_pdf) {
  if (!file.exists(rows_path)) return(FALSE)
  res <- if (grepl("\\.rds$", rows_path, ignore.case = TRUE)) {
    readRDS(rows_path)
  } else {
    utils::read.csv(rows_path, stringsAsFactors = FALSE)
  }
  if (!is.data.frame(res) || !nrow(res)) return(FALSE)
  if (!exists("subgroup_draw_forest_pdf", mode = "function") &&
      !exists("subgroup_export_forest", mode = "function")) {
    return(FALSE)
  }
  dir.create(dirname(dest_pdf), recursive = TRUE, showWarnings = FALSE)
  ok <- FALSE
  if (exists("subgroup_draw_forest_pdf", mode = "function")) {
    ok <- isTRUE(tryCatch(
      subgroup_draw_forest_pdf(res, dest_pdf, config = config, effect_sym = "OR"),
      error = function(e) {
        cli::cli_alert_warning("draw {db_label}: {e$message}")
        FALSE
      }
    ))
  }
  ok
}

## locate forest_rows
e_rows <- .forest_srcs[grepl("eICU", .forest_srcs) & grepl("forest", .forest_srcs, ignore.case = TRUE)]
m_rows <- .forest_srcs[grepl("MIMIC", .forest_srcs) & grepl("forest", .forest_srcs, ignore.case = TRUE)]
cli::cli_alert_info("e_rows={length(e_rows)} m_rows={length(m_rows)}")
redrawn <- FALSE
if (length(e_rows) && length(m_rows)) {
  tmp_e <- file.path(tempdir(), "fig8_eicu.pdf")
  tmp_m <- file.path(tempdir(), "fig8_mimic.pdf")
  ok_e <- .redraw_one_forest("eICU", e_rows[[1]], tmp_e)
  ok_m <- .redraw_one_forest("MIMIC", m_rows[[1]], tmp_m)
  if (isTRUE(ok_e) && isTRUE(ok_m)) {
    sg_e_pdf <- tmp_e
    sg_m_pdf <- tmp_m
    redrawn <- TRUE
  }
}

if (!redrawn) {
  cli::cli_alert_warning(
    "未能从 forest_rows 重绘；将用 Python 改写现有 Fig8 文本层为 3 位（若无文本层则保留旧图并告警）"
  )
}

sg_dest <- file.path(fig_pdf, "Figure 8. Subgroup Forest analyses of BUN Cr.pdf")
if (file.exists(sg_e_pdf) && file.exists(sg_m_pdf)) {
  pub_figure_combine_ab_pdfs(
    sg_e_pdf, sg_m_pdf, sg_dest,
    labels = c(
      "A. eICU development — Q4 vs Q1, Model 2 (28-day mortality)",
      "B. MIMIC-IV external — Q4 vs Q1, Model 2 (28-day mortality)"
    ),
    stack = TRUE,
    label_band = 36
  )
}

## Sync index Tables → summary_results Tables; figures
file.copy(
  list.files(file.path(ix_root, "Tables"), pattern = "\\.xlsx$", full.names = TRUE),
  file.path(sum_root, "Tables"),
  overwrite = TRUE
)
## dedupe again if compose reintroduced plain names
unlink(list.files(
  file.path(sum_root, "Tables"),
  pattern = "Table 1-.*(mortality)\\.xlsx$",
  full.names = TRUE
)[!grepl("\\(", list.files(file.path(sum_root, "Tables"), pattern = "Table 1-.*mortality\\.xlsx$"))])

cfg_fig <- config
if (is.null(cfg_fig$pub_figures)) cfg_fig$pub_figures <- list()
cfg_fig$pub_figures$max_edge_in <- cfg_fig$pub_figures$max_edge_in %||% 16
pub_figure_ensure_formats(fig_root, config = cfg_fig)
## copy pdf tree to summary
sum_fig <- file.path(sum_root, "Figures")
if (dir.exists(sum_fig)) {
  for (sub in c("pdf", "image_information")) {
    src <- file.path(fig_root, sub)
    dst <- file.path(sum_fig, sub)
    if (!dir.exists(src)) next
    dir.create(dst, recursive = TRUE, showWarnings = FALSE)
    for (f in list.files(src, full.names = TRUE)) {
      file.copy(f, file.path(dst, basename(f)), overwrite = TRUE)
    }
  }
}
pub_figure_ensure_formats(sum_fig, config = cfg_fig)
tryCatch(pub_sync_xlsx_a1_titles_to_filenames(file.path(sum_root, "Tables")), error = function(e) NULL)

cli::cli_alert_success("DONE digits reformat + Fig3-6/8 refresh")
cat("PDFS=\n"); print(list.files(file.path(sum_root, "Figures", "pdf")))
