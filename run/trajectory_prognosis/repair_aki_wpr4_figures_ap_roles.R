#!/usr/bin/env Rscript
# Repair figure naming after cascading rename; rebuild dual panels to AP roles (≤S8).
suppressPackageStartupMessages({
  library(cli)
})
`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)
source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)
cfg_path <- "/mnt/g/02block_result/44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr/config.R"
if (file.exists(cfg_path)) source(cfg_path, local = FALSE)

index_root <- "/mnt/g/02block_result/44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr/by_index/WPR(class=4)"
fig_root <- file.path(index_root, "Figures")

# Desired role stems (no DB tag)
wanted <- c(
  "Figure 1. Flowchart of patient selection.pdf",
  "Figure 2. Trajectory of WPR latent classes.pdf",
  "Figure 3. Dynamic prediction of WPR trajectory.pdf",
  "Figure 4. Individual dynamic prediction.pdf",
  "Figure S1. Kaplan Meier survival by trajectory class.pdf",
  "Figure S2. Piecewise Cox cut point search.pdf",
  "Figure S3. Subgroup analysis by trajectory class.pdf",
  "Figure S4. Weibull dynamic model comparison AUC.pdf",
  "Figure S5. Weibull dynamic model comparison C index.pdf",
  "Figure S6. Weibull dynamic model comparison Accuracy.pdf",
  "Figure S7. Weibull dynamic model comparison Sensitivity.pdf",
  "Figure S8. Weibull dynamic model comparison Specificity.pdf"
)

.rebuild_db <- function(db, db_lab) {
  fdir <- file.path(index_root, db, "Figures")
  raw <- file.path(fdir, "_raw")
  # wipe all tagged PDFs except keep regenerated Fig2 / S1 if present
  keep_fig2 <- file.path(fdir, sprintf("Figure 2-%s. Trajectory of WPR latent classes.pdf", db_lab))
  keep_s1 <- file.path(fdir, sprintf("Figure S1-%s. Kaplan Meier survival by trajectory class.pdf", db_lab))
  tmp2 <- tempfile(fileext = ".pdf"); tmp1 <- tempfile(fileext = ".pdf")
  has2 <- file.exists(keep_fig2); has1 <- file.exists(keep_s1)
  if (has2) file.copy(keep_fig2, tmp2, overwrite = TRUE)
  if (has1) file.copy(keep_s1, tmp1, overwrite = TRUE)
  unlink(list.files(fdir, pattern = "\\.pdf$", full.names = TRUE))

  map_raw <- list(
    "Figure 1" = list(raw = "Figure 1. Flowchart.pdf", out = sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab)),
    "Figure 3" = list(raw = "Figure Dynpred WPR D4.pdf", out = sprintf("Figure 3-%s. Dynamic prediction of WPR trajectory.pdf", db_lab)),
    "Figure 4" = list(raw = "Figure Dynpred Individual WPR.pdf", out = sprintf("Figure 4-%s. Individual dynamic prediction.pdf", db_lab)),
    "S2" = list(raw = "Figure Piecewise Cox CutSearch WPR.pdf", out = sprintf("Figure S2-%s. Piecewise Cox cut point search.pdf", db_lab)),
    "S3" = list(raw = "Figure Subgroup TrajectoryClass WPR.pdf", out = sprintf("Figure S3-%s. Subgroup analysis by trajectory class.pdf", db_lab)),
    "S4" = list(raw = "Figure Weibull Dynamic Compare WPR AUC.pdf", out = sprintf("Figure S4-%s. Weibull dynamic model comparison AUC.pdf", db_lab)),
    "S5" = list(raw = "Figure Weibull Dynamic Compare WPR Cindex.pdf", out = sprintf("Figure S5-%s. Weibull dynamic model comparison C index.pdf", db_lab)),
    "S6" = list(raw = "Figure Weibull Dynamic Compare WPR Accuracy.pdf", out = sprintf("Figure S6-%s. Weibull dynamic model comparison Accuracy.pdf", db_lab)),
    "S7" = list(raw = "Figure Weibull Dynamic Compare WPR Sensitivity.pdf", out = sprintf("Figure S7-%s. Weibull dynamic model comparison Sensitivity.pdf", db_lab)),
    "S8" = list(raw = "Figure Weibull Dynamic Compare WPR Specificity.pdf", out = sprintf("Figure S8-%s. Weibull dynamic model comparison Specificity.pdf", db_lab))
  )
  for (m in map_raw) {
    src <- file.path(raw, m$raw)
    if (!file.exists(src)) {
      cli_alert_warning("missing raw {m$raw} for {db}")
      next
    }
    file.copy(src, file.path(fdir, m$out), overwrite = TRUE)
  }
  # restore aligned Fig2 / S1
  if (has2) file.copy(tmp2, keep_fig2, overwrite = TRUE)
  else {
    # fallback raw trajectory (may be unaligned)
    src <- file.path(raw, "Figure Trajectory WPR latent classes.pdf")
    if (file.exists(src)) file.copy(src, keep_fig2, overwrite = TRUE)
  }
  if (has1) file.copy(tmp1, keep_s1, overwrite = TRUE)
  else {
    src <- file.path(raw, "Figure KM TrajectoryClass WPR.pdf")
    if (file.exists(src)) file.copy(src, keep_s1, overwrite = TRUE)
  }
  cli_alert_success("Rebuilt db figures: {db}")
}

.rebuild_db("mimic", "MIMIC")
.rebuild_db("eicu", "eICU")

# Clear root figure flat + four-dir pdfs
unlink(list.files(fig_root, pattern = "\\.pdf$", full.names = TRUE))
for (sub in c("pdf", "png", "tiff")) {
  d <- file.path(fig_root, sub)
  if (dir.exists(d)) unlink(list.files(d, full.names = TRUE))
}

# Stage tagged (skip Fig1 per-db; skip eICU S2 cut)
for (db in c("mimic", "eicu")) {
  db_lab <- if (db == "mimic") "MIMIC" else "eICU"
  srcs <- list.files(
    file.path(index_root, db, "Figures"),
    pattern = sprintf("^Figure .+-%s\\. .+\\.pdf$", db_lab),
    full.names = TRUE
  )
  srcs <- srcs[!grepl("^Figure 1-", basename(srcs))]
  if (identical(db, "eicu")) {
    srcs <- srcs[!grepl("^Figure S2-eICU\\. Piecewise", basename(srcs))]
  }
  for (fp in srcs) file.copy(fp, file.path(fig_root, basename(fp)), overwrite = TRUE)
}

# Compose dual Fig1 from db
fig1_m <- file.path(index_root, "mimic", "Figures", "Figure 1-MIMIC. Flowchart of patient selection.pdf")
fig1_e <- file.path(index_root, "eicu", "Figures", "Figure 1-eICU. Flowchart of patient selection.pdf")
if (file.exists(fig1_m) && file.exists(fig1_e)) {
  .dual_db_compose_pair_pdf(
    fig1_m, fig1_e,
    file.path(fig_root, "Figure 1. Flowchart of patient selection.pdf"),
    layout = "side", label_a = "A. MIMIC", label_b = "B. eICU"
  )
}

cfg <- if (exists("config")) config else list()
cfg$dual_db <- list(combine_figures = list(
  enable = TRUE, remove_singles = TRUE, panel_order = "secondary_first",
  layout_by_role = list(
    Trajectory = "stack", Dynpred = "stack", "Dynamic prediction" = "stack",
    "Kaplan Meier" = "stack", "latent classes" = "stack", Subgroup = "stack",
    Weibull = "stack"
  )
))
dual_db_combine_paired_figures(index_root, cfg, figures_dir = fig_root)

# Force MIMIC-only S2 cut
cut_src <- file.path(index_root, "mimic", "Figures", "Figure S2-MIMIC. Piecewise Cox cut point search.pdf")
if (file.exists(cut_src)) {
  file.copy(cut_src, file.path(fig_root, "Figure S2. Piecewise Cox cut point search.pdf"), overwrite = TRUE)
}
unlink(list.files(fig_root, pattern = "-MIMIC\\.|-eICU\\.", full.names = TRUE))
unlink(list.files(fig_root, pattern = "Figure S9|Missing", full.names = TRUE))

# Keep only wanted stems
have <- list.files(fig_root, pattern = "\\.pdf$", full.names = TRUE)
for (fp in have) {
  if (!(basename(fp) %in% wanted)) {
    cli_alert_warning("Removing unexpected {basename(fp)}")
    unlink(fp)
  }
}

# Four-dir export
tryCatch(
  pub_figure_ensure_formats(fig_root, config = if (exists("config")) config else list()),
  error = function(e) cli_alert_warning("{e$message}")
)

cli_alert_success("Figure repair done")
cli_alert_info("pdf/: {paste(list.files(file.path(fig_root,'pdf')), collapse='; ')}")
