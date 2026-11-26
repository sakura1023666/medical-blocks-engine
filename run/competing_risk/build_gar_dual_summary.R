#!/usr/bin/env Rscript
# Build dual-db summary_results for GAR (MIMIC + eICU), Lai Table1–4 + S1–S6
root <- "/mnt/e/01block/01Block-new-Final"
setwd(root)
source("R/utils.R")
source("R/pub_figure_export.R")
source("R/dual_db_combine_figures.R")
source("R/pub_delivery_prune.R")
if (file.exists("R/pub_xlsx_surgical.R")) source("R/pub_xlsx_surgical.R")

proj <- "/mnt/g/02block_result/33_AKI/Competing_risk_CRRT_28d"
mimic <- file.path(proj, "MIMIC/by_unit/\u3010success\u3011GAR")
eicu <- file.path(proj, "eICU/by_unit/\u3010success\u3011GAR")
if (!dir.exists(eicu)) eicu <- file.path(proj, "eICU/by_unit/GAR")
stopifnot(dir.exists(mimic), dir.exists(eicu))

# archive prior dual summary then recreate
sum_root <- file.path(proj, "summary_results/\u3010success\u3011GAR")
if (dir.exists(sum_root)) {
  arch <- file.path(
    proj, "summary_results",
    sprintf("_archive_GAR_dual_%s", format(Sys.time(), "%Y%m%d_%H%M%S"))
  )
  dir.create(dirname(arch), recursive = TRUE, showWarnings = FALSE)
  file.rename(sum_root, arch)
  message("archived prior summary → ", arch)
}
fig_dir <- file.path(sum_root, "Figures")
tab_dir <- file.path(sum_root, "Tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

# Lai role → S number (by title fragment; ignore source S#)
.lai_s_roles <- c(
  "Subgroup analysis by quartile" = 1L,
  "Standard Cox by quartile (sensitivity)" = 2L,
  "Competing-risk Cox sensitivity" = 3L,
  "Standard Cox sensitivity (extremes handled)" = 4L,
  "Subgroup analysis by trajectory" = 5L,
  "Standard Cox by trajectory" = 6L
)

.role_s <- function(bn) {
  for (nm in names(.lai_s_roles)) {
    if (grepl(nm, bn, fixed = TRUE)) return(.lai_s_roles[[nm]])
  }
  NA_integer_
}

.copy_xlsx_lai <- function(src_dir, dest_dir, db) {
  fs <- list.files(src_dir, pattern = "\\.xlsx$", full.names = TRUE)
  copied <- character(0)
  for (f in fs) {
    bn <- basename(f)
    # main Table 1–4 with db tag
    if (grepl(sprintf("^Table [1-4]-%s\\.", db), bn)) {
      file.copy(f, file.path(dest_dir, bn), overwrite = TRUE)
      copied <- c(copied, bn)
      next
    }
    # Supplementary Material N- → role map
    bn2 <- sub("^Supplementary Material ([1-6])-", "Table S\\1-", bn)
    s_n <- .role_s(bn2)
    if (is.na(s_n)) next
    # require db tag OR bare Table S* with role (eICU mis-number)
    if (!grepl(paste0("-", db, "\\."), bn2) && !grepl("^Table S[0-9]+\\.", bn2)) next
    # skip imputation / UV leftovers without role match already handled
    title_rest <- sub("^Table S[0-9]+(-[A-Za-z0-9_]+)?\\.\\s*", "", bn2)
    title_rest <- sub("\\.xlsx$", "", title_rest)
    out_bn <- sprintf("Table S%d-%s. %s.xlsx", s_n, db, title_rest)
    # normalize known titles to MIMIC wording
    if (s_n == 3L) out_bn <- sprintf("Table S3-%s. Competing-risk Cox sensitivity (extremes handled).xlsx", db)
    if (s_n == 4L) out_bn <- sprintf("Table S4-%s. Standard Cox sensitivity (extremes handled).xlsx", db)
    if (s_n == 2L) out_bn <- sprintf("Table S2-%s. Standard Cox by quartile (sensitivity).xlsx", db)
    if (s_n == 1L) out_bn <- sprintf("Table S1-%s. Subgroup analysis by quartile.xlsx", db)
    if (s_n == 5L) out_bn <- sprintf("Table S5-%s. Subgroup analysis by trajectory.xlsx", db)
    if (s_n == 6L) out_bn <- sprintf("Table S6-%s. Standard Cox by trajectory.xlsx", db)
    file.copy(f, file.path(dest_dir, out_bn), overwrite = TRUE)
    copied <- c(copied, out_bn)
  }
  invisible(unique(copied))
}

.copy_pdfs <- function(src_dir, dest_dir) {
  pdf_dir <- if (dir.exists(file.path(src_dir, "pdf"))) file.path(src_dir, "pdf") else src_dir
  fs <- list.files(pdf_dir, pattern = "^Figure [1-9]-.*\\.pdf$", full.names = TRUE, recursive = FALSE)
  for (f in fs) file.copy(f, file.path(dest_dir, basename(f)), overwrite = TRUE)
  invisible(basename(fs))
}

message("copy MIMIC tables...")
.print_m <- .copy_xlsx_lai(file.path(mimic, "Tables"), tab_dir, "MIMIC")
message(paste(" ", .print_m, collapse = "\n"))
message("copy eICU tables...")
.print_e <- .copy_xlsx_lai(file.path(eicu, "Tables"), tab_dir, "eICU")
message(paste(" ", .print_e, collapse = "\n"))
message("copy figures...")
.copy_pdfs(file.path(mimic, "Figures"), fig_dir)
.copy_pdfs(file.path(eicu, "Figures"), fig_dir)

cfg <- list(
  project = list(database = "MIMIC", root = root),
  dual_db = list(enable = TRUE, databases = c("MIMIC", "eICU")),
  pub_figures = list(export_png = FALSE, export_tiff = FALSE)
)
tryCatch(
  dual_db_combine_paired_figures(sum_root, cfg, figures_dir = fig_dir),
  error = function(e) message("combine warn: ", conditionMessage(e))
)

tryCatch(
  export_pub_figures(
    fig_dir,
    meta = list(
      exposure = "GAR",
      outcome = "CRRT / Overall mortality",
      databases = c("MIMIC", "eICU"),
      combined = TRUE
    ),
    config = cfg
  ),
  error = function(e) message("export_pub_figures warn: ", conditionMessage(e))
)

if (exists("pub_xlsx_edit_cells", mode = "function")) {
  for (f in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
    stem <- sub("\\.xlsx$", "", basename(f))
    try(
      pub_xlsx_edit_cells(f, data.frame(row = 1L, col = 1L, value = stem, stringsAsFactors = FALSE)),
      silent = TRUE
    )
  }
}

for (nm in c("Methods_statistical_analysis.md", "Methods_software_versions.txt")) {
  src <- file.path(mimic, nm)
  if (!file.exists(src)) src <- file.path(mimic, "summary_results", nm)
  if (!file.exists(src)) {
    # minimal stub
    if (nm == "Methods_statistical_analysis.md") {
      writeLines(c(
        "# Statistical analysis",
        "",
        "Dual-database competing-risk analysis (MIMIC development; eICU external validation).",
        "Primary event: CRRT within 28 days; competing event: death.",
        "Exposure: GAR quartile and trajectory. Fine-Gray and cause-specific Cox models.",
        "",
        "## Software",
        "",
        "See Methods_software_versions.txt."
      ), file.path(sum_root, nm))
    }
    next
  }
  file.copy(src, file.path(sum_root, nm), overwrite = TRUE)
}

if (exists("pub_prune_delivery_root", mode = "function")) {
  try(pub_prune_delivery_root(sum_root), silent = TRUE)
}

message("summary_results ready: ", sum_root)
message("Tables:\n", paste(sort(list.files(tab_dir)), collapse = "\n"))
pdf_out <- file.path(fig_dir, "pdf")
if (dir.exists(pdf_out)) {
  message("Figures/pdf:\n", paste(sort(list.files(pdf_out)), collapse = "\n"))
} else {
  message("Figures:\n", paste(sort(list.files(fig_dir, pattern = "\\.pdf$")), collapse = "\n"))
}
