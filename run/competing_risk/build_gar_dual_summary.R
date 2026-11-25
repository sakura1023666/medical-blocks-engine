#!/usr/bin/env Rscript
# Build dual-db summary_results for GAR (MIMIC + eICU)
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

sum_root <- file.path(proj, "summary_results/\u3010success\u3011GAR")
fig_dir <- file.path(sum_root, "Figures")
tab_dir <- file.path(sum_root, "Tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

.copy_xlsx <- function(src_dir, dest_dir) {
  fs <- list.files(src_dir, pattern = "\\.xlsx$", full.names = TRUE)
  keep <- grepl("^Table [1-4]-|^Table S[1-6]-|^Supplementary Material [1-6]-", basename(fs))
  fs <- fs[keep]
  for (f in fs) {
    bn <- basename(f)
    # normalize Supplementary Material → Table S
    bn <- sub("^Supplementary Material ([1-6])-", "Table S\\1-", bn)
    file.copy(f, file.path(dest_dir, bn), overwrite = TRUE)
  }
  invisible(basename(fs))
}

.copy_pdfs <- function(src_dir, dest_dir) {
  # prefer pdf/ subdir
  pdf_dir <- if (dir.exists(file.path(src_dir, "pdf"))) file.path(src_dir, "pdf") else src_dir
  fs <- list.files(pdf_dir, pattern = "^Figure .*\\.pdf$", full.names = TRUE, recursive = FALSE)
  for (f in fs) file.copy(f, file.path(dest_dir, basename(f)), overwrite = TRUE)
  invisible(basename(fs))
}

message("copy MIMIC tables...")
.print_m <- .copy_xlsx(file.path(mimic, "Tables"), tab_dir)
message("copy eICU tables...")
.print_e <- .copy_xlsx(file.path(eicu, "Tables"), tab_dir)
message("copy figures...")
.copy_pdfs(file.path(mimic, "Figures"), fig_dir)
.copy_pdfs(file.path(eicu, "Figures"), fig_dir)

# dual combine paired figures (needs -MIMIC / -eICU tags in same dir)
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

# A1 外科对齐文件名（避免 openpyxl 整表往返弄坏 Supp）
if (exists("pub_xlsx_edit_cells", mode = "function")) {
  for (f in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
    stem <- sub("\\.xlsx$", "", basename(f))
    try(
      pub_xlsx_edit_cells(f, data.frame(row = 1L, col = 1L, value = stem, stringsAsFactors = FALSE)),
      silent = TRUE
    )
  }
}

# Methods stub from MIMIC if present
for (nm in c("Methods_statistical_analysis.md", "Methods_software_versions.txt")) {
  src <- file.path(mimic, nm)
  if (!file.exists(src)) src <- file.path(mimic, "summary_results", nm)
  if (file.exists(src)) file.copy(src, file.path(sum_root, nm), overwrite = TRUE)
}

if (exists("pub_prune_delivery_root", mode = "function")) {
  try(pub_prune_delivery_root(sum_root), silent = TRUE)
}

message("summary_results ready: ", sum_root)
message("Tables:\n", paste(list.files(tab_dir), collapse = "\n"))
message("Figures/pdf:\n", paste(list.files(file.path(fig_dir, "pdf"), full.names = FALSE), collapse = "\n"))
