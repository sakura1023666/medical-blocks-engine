#!/usr/bin/env Rscript
# 直接重画 Fig1（真实纳排）+ Fig2（类别对齐、Y 从 1），写入分库正式名并拼到根 pdf/png/tiff

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

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/trajectory_survival_utils.R"))
source(file.path(.root, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"))
source(file.path(.root, "R/pub_figure_export.R"))
if (file.exists(file.path(.root, "R/dual_db_combine_figures.R")))
  source(file.path(.root, "R/dual_db_combine_figures.R"))

suppressPackageStartupMessages({
  library(lcmm); library(splines); library(dplyr); library(ggplot2)
})

ix <- "GPR"; ng <- 3L
out_ix <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
out_ix <- out_ix[dir.exists(out_ix) & grepl("【success】GPR$", basename(out_ix))][[1L]]

.load_pack <- function(db) {
  env <- new.env(parent = emptyenv())
  load(file.path(out_ix, db, "step14_trajectory_jlcm/Data/D01_jlcm_GPR_models.RData"), envir = env)
  list(models = env$models_list_with_cov, md = env$model_data_final)
}

.combine_pair_pdf <- function(left, right, dest, lab_a = "A. eICU", lab_b = "B. MIMIC") {
  if (!requireNamespace("magick", quietly = TRUE)) stop("需要 magick")
  a <- magick::image_read_pdf(left, density = 160)[1]
  b <- magick::image_read_pdf(right, density = 160)[1]
  a <- magick::image_annotate(a, lab_a, size = 26, gravity = "northwest", location = "+16+12")
  b <- magick::image_annotate(b, lab_b, size = 26, gravity = "northwest", location = "+16+12")
  comb <- magick::image_append(c(a, b))
  tmp <- tempfile(fileext = ".png")
  magick::image_write(comb, path = tmp, format = "png")
  img <- png::readPNG(tmp)
  grDevices::pdf(dest, width = 14, height = 5.2, useDingbats = FALSE)
  graphics::par(mar = c(0, 0, 0, 0), xaxs = "i", yaxs = "i")
  graphics::plot.new()
  graphics::rasterImage(img, 0, 0, 1, 1)
  grDevices::dev.off()
  unlink(tmp)
  dest
}

packs <- list(eicu = .load_pack("eicu"), mimic = .load_pack("mimic"))
curves <- list(); obs_means <- list(); obs_all <- numeric(0); pred_all <- numeric(0)
for (db in c("eicu", "mimic")) {
  m <- trajectory_unwrap_jointlcmm(packs[[db]]$models[[paste0("m", ng)]])
  md <- packs[[db]]$md
  cv <- trajectory_jlcm_pred_curves(m, md, 28L, 50L)
  curves[[db]] <- cv
  om <- trajectory_jlcm_obs_class_means(m, md, "scr_std")
  obs_means[[db]] <- om
  pred_all <- c(pred_all, as.numeric(cv)[as.numeric(cv) >= 0.5])
  obs_all <- c(obs_all, md$scr_std)
  cat(db, "obs means", paste(round(om, 3), collapse = ","), "\n")
}
align <- trajectory_align_class_maps(curves, ref = "eicu", obs_means_by_db = obs_means)
ylim <- trajectory_shared_ylim(obs_all, pred_all, ymin = 1)
cat("maps eicu", paste(paste0(names(align$maps$eicu), "->", align$maps$eicu), collapse = " "),
    " mimic", paste(paste0(names(align$maps$mimic), "->", align$maps$mimic), collapse = " "),
    " ylim", ylim, "\n")

for (db in c("eicu", "mimic")) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  pack <- packs[[db]]
  m <- trajectory_unwrap_jointlcmm(pack$models[[paste0("m", ng)]])
  md <- pack$md
  pp <- as.data.frame(m$pprob)
  long <- md |>
    dplyr::left_join(pp[, c("subject_id_num", "class")], by = "subject_id_num") |>
    dplyr::mutate(Class = paste0("Class", class)) |>
    dplyr::rename(Time = time_day, Value = scr_std)
  p <- .tpj04_make_plot(
    m, long, ix, ng, 28L, "subject_id", "sans",
    cov_cols = c("OASIS", "Age", "APSIII", "Temperature"),
    class_map = align$maps[[db]],
    ylim = ylim
  )
  stopifnot(!is.null(p))
  dests <- c(
    file.path(unit, "Figures", sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix)),
    file.path(unit, "Figures", sprintf("Figure Trajectory %s D%d.pdf", ix, ng)),
    file.path(unit, "step16_trajectory_plot_jlcm/Figures", sprintf("Figure Trajectory %s D%d.pdf", ix, ng))
  )
  for (fp in dests) {
    dir.create(dirname(fp), recursive = TRUE, showWarnings = FALSE)
    ggplot2::ggsave(fp, p, width = 10, height = 4.2, device = grDevices::cairo_pdf)
  }
  cli::cli_alert_success("[{db_lab}] Fig2 已重画 ylim=[{ylim[1]}, {ylim[2]}]")

  fc <- file.path(unit, "step24_attrition_flowchart/Figures/Figure 1. Flowchart.pdf")
  if (!file.exists(fc)) {
    hits <- list.files(unit, pattern = "Figure 1\\..*Flowchart.*\\.pdf$", recursive = TRUE, full.names = TRUE)
    hits <- hits[!grepl("patient selection|PLACEHOLDER", hits, ignore.case = TRUE)]
    hits <- hits[file.exists(hits)]
    if (length(hits)) fc <- hits[which.max(file.info(hits)$size)]
  }
  dest1 <- file.path(unit, "Figures", sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab))
  if (file.exists(fc)) {
    file.copy(fc, dest1, overwrite = TRUE)
    file.copy(fc, file.path(unit, "Figures/Figure 1. Flowchart.pdf"), overwrite = TRUE)
    cli::cli_alert_success("[{db_lab}] Fig1 已替换为真实纳排图")
  } else {
    cli::cli_alert_warning("[{db_lab}] 未找到真实纳排图")
  }
}

root_fig <- file.path(out_ix, "Figures")
dir.create(file.path(root_fig, "pdf"), recursive = TRUE, showWarnings = FALSE)
pairs <- list(
  list(
    a = file.path(out_ix, "eicu/Figures/Figure 1-eICU. Flowchart of patient selection.pdf"),
    b = file.path(out_ix, "mimic/Figures/Figure 1-MIMIC. Flowchart of patient selection.pdf"),
    dest = "Figure 1. Flowchart of patient selection.pdf"
  ),
  list(
    a = file.path(out_ix, "eicu/Figures/Figure 2-eICU. Trajectory of GPR latent classes.pdf"),
    b = file.path(out_ix, "mimic/Figures/Figure 2-MIMIC. Trajectory of GPR latent classes.pdf"),
    dest = "Figure 2. Trajectory of GPR latent classes.pdf"
  )
)
for (pr in pairs) {
  dest <- file.path(root_fig, "pdf", pr$dest)
  .combine_pair_pdf(pr$a, pr$b, dest)
  file.copy(dest, file.path(root_fig, pr$dest), overwrite = TRUE)
  cli::cli_alert_success("已拼 {pr$dest}")
}

# 刷新 Fig1/2 的 png/tiff（不 purge 其它图）
cfg <- list(pub_figures = list(formats_dir = TRUE, dpi = 300L, write_image_information = TRUE))
for (stem in c("Figure 1. Flowchart of patient selection",
               "Figure 2. Trajectory of GPR latent classes")) {
  pdf_src <- file.path(root_fig, "pdf", paste0(stem, ".pdf"))
  if (!file.exists(pdf_src)) next
  dest_png <- file.path(root_fig, "png", paste0(stem, ".png"))
  dest_tiff <- file.path(root_fig, "tiff", paste0(stem, ".tiff"))
  dir.create(dirname(dest_png), recursive = TRUE, showWarnings = FALSE)
  dir.create(dirname(dest_tiff), recursive = TRUE, showWarnings = FALSE)
  tryCatch(
    .pub_figure_rasterize_one(pdf_src, dest_png, dest_tiff, 300L, root_hint = .root),
    error = function(e) cli::cli_alert_warning("栅格化 {stem}: {e$message}")
  )
}

cli::cli_alert_success("Fig1 / Fig2 已覆盖正式文件。")
