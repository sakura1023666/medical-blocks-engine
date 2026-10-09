#!/usr/bin/env Rscript
# 只整理发表图：分库 Fig1–4+S1–S9 → 根目录拼图 → pdf/png/tiff

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
study_root <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1L]] else
  "/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr"
ix <- "GPR"
db_seq <- c("eicu", "mimic")

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/trajectory_pub_curate.R"))
source(file.path(.root, "R/dual_db_combine_figures.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(study_root, "config.R"))
config$feishu$enable <- FALSE
if (exists("trajectory_batch_patch_config_for_index")) {
  source(file.path(.root, "R/trajectory_prognosis_batch_runner.R"))
  config_ix <- trajectory_batch_patch_config_for_index(config, ix)
} else {
  config_ix <- config
}
disease <- gsub("_", " ", as.character(config$project$disease %||% "Sepsis AKI")[1L])

hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
out_ix <- hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))][[1L]]

# 分库：拷真实纳排图 + Missing，再 curate
for (db in db_seq) {
  unit <- file.path(out_ix, db)
  fig <- file.path(unit, "Figures")
  fc <- file.path(unit, "step24_attrition_flowchart/Figures/Figure 1. Flowchart.pdf")
  if (file.exists(fc)) file.copy(fc, file.path(fig, "Figure 1. Flowchart.pdf"), overwrite = TRUE)
  miss <- file.path(unit, "step06_imputation/Figures/Figure Missing Value Overview.pdf")
  if (file.exists(miss)) file.copy(miss, file.path(fig, "Figure Missing Value Overview.pdf"), overwrite = TRUE)
}

trajectory_curate_pub_outputs(base_dir = out_ix, index_name = ix, dbs = db_seq, disease = disease)

# 根目录清空后只放分库正式 13 张
root_fig <- file.path(out_ix, "Figures")
dir.create(root_fig, recursive = TRUE, showWarnings = FALSE)
unlink(list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE))
pub_figure_purge_format_subdirs(root_fig)

for (db in db_seq) {
  srcs <- list.files(file.path(out_ix, db, "Figures"), pattern = "\\.pdf$", full.names = TRUE)
  srcs <- srcs[!grepl("/_raw/", srcs)]
  for (f in srcs) file.copy(f, file.path(root_fig, basename(f)), overwrite = TRUE)
}

cfg_comb <- config_ix
cfg_comb$dual_db$combine_figures <- utils::modifyList(
  cfg_comb$dual_db$combine_figures %||% list(),
  list(enable = TRUE, remove_singles = TRUE, drop_missing_overview = FALSE,
       panel_order = "primary_first", label_format = "A. {db}")
)
cfg_comb$project$output_dir <- out_ix
dual_db_combine_paired_figures(out_ix, cfg_comb, figures_dir = root_fig)

# 删根目录单库残留（S1 若未拼上则手工拼）
s1_e <- file.path(root_fig, "Figure S1-eICU. Missing value overview.pdf")
s1_m <- file.path(root_fig, "Figure S1-MIMIC. Missing value overview.pdf")
s1_c <- file.path(root_fig, "Figure S1. Missing value overview.pdf")
if (file.exists(s1_e) && file.exists(s1_m) && !file.exists(s1_c) &&
    requireNamespace("magick", quietly = TRUE)) {
  a <- magick::image_read_pdf(s1_e, density = 150)[1]
  b <- magick::image_read_pdf(s1_m, density = 150)[1]
  a <- magick::image_annotate(a, "A. eICU", size = 28, gravity = "northwest", location = "+20+16")
  b <- magick::image_annotate(b, "B. MIMIC", size = 28, gravity = "northwest", location = "+20+16")
  comb <- magick::image_append(c(a, b))
  tmp_png <- tempfile(fileext = ".png")
  magick::image_write(comb, path = tmp_png, format = "png")
  img <- png::readPNG(tmp_png)
  grDevices::pdf(s1_c, width = 12, height = 5, useDingbats = FALSE)
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::rasterImage(img, 0, 0, 1, 1)
  grDevices::dev.off()
  unlink(tmp_png)
}
unlink(list.files(root_fig, pattern = "-(eICU|MIMIC)\\.pdf$", full.names = TRUE))

# 只留标准 13 名
keep <- c(
  "Figure 1. Flowchart of patient selection.pdf",
  "Figure 1. Flowchart.pdf",
  sprintf("Figure 2. Trajectory of %s latent classes.pdf", ix),
  sprintf("Figure 3. Dynamic prediction of %s trajectory.pdf", ix),
  "Figure 4. Individual dynamic prediction.pdf",
  "Figure S1. Missing value overview.pdf",
  "Figure S2. Kaplan Meier survival by trajectory class.pdf",
  "Figure S3. Piecewise Cox cut point search.pdf",
  "Figure S4. Subgroup analysis by trajectory class.pdf",
  "Figure S5. Weibull dynamic model comparison AUC.pdf",
  "Figure S6. Weibull dynamic model comparison C index.pdf",
  "Figure S7. Weibull dynamic model comparison Accuracy.pdf",
  "Figure S8. Weibull dynamic model comparison Sensitivity.pdf",
  "Figure S9. Weibull dynamic model comparison Specificity.pdf"
)
for (f in list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE)) {
  if (!basename(f) %in% keep) unlink(f)
}
# 若只有 Figure 1. Flowchart.pdf，改成正式名
f1a <- file.path(root_fig, "Figure 1. Flowchart.pdf")
f1b <- file.path(root_fig, "Figure 1. Flowchart of patient selection.pdf")
if (file.exists(f1a) && !file.exists(f1b)) file.rename(f1a, f1b)

export_pub_figures(root_fig, meta = list(
  exposure = ix, outcome = "28-day mortality", grouping = "3-class JLCM",
  databases = c("eICU", "MIMIC"), combined = TRUE
), config = config_ix, purge = TRUE)

cli::cli_h2("根目录 PDF")
print(sort(list.files(root_fig, pattern = "\\.pdf$")))
cli::cli_alert_info(
  "pdf={length(list.files(file.path(root_fig,'pdf'),'\\\\.pdf$'))} png={length(list.files(file.path(root_fig,'png'),'\\\\.png$'))} tiff={length(list.files(file.path(root_fig,'tiff')))} md={length(list.files(file.path(root_fig,'image_information'),'\\\\.md$'))}"
)
for (db in db_seq) {
  lab <- if (db == "eicu") "eICU" else "MIMIC"
  have <- list.files(file.path(out_ix, db, "Figures"), pattern = "\\.pdf$")
  cli::cli_alert_info("[{lab}] {length(have)}: {paste(sort(have), collapse=' | ')}")
}
