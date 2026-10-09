#!/usr/bin/env Rscript
# 仅重画 GPR 2 类 Fig2（上下拼、横宽、双库已对齐），不重跑下游。
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
suppressPackageStartupMessages({ library(dplyr); library(ggplot2); library(splines) })

ix <- "GPR"; ng <- 2L
out_ix <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
out_ix <- out_ix[dir.exists(out_ix) & grepl("【success】GPR$", basename(out_ix))][[1L]]
.unwrap <- trajectory_unwrap_jointlcmm
.load <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(out_ix, db, "step14_trajectory_jlcm/Data/D01_jlcm_GPR_models.RData"), envir = e)
  list(models = e$models_list_with_cov, md = e$model_data_final)
}
packs <- list(eicu = .load("eicu"), mimic = .load("mimic"))
curves <- list(); obs_means <- list(); obs_all <- numeric(0); pred_all <- numeric(0)
for (db in c("eicu", "mimic")) {
  m <- .unwrap(packs[[db]]$models$m2)
  md <- packs[[db]]$md
  curves[[db]] <- trajectory_jlcm_pred_curves(m, md, 28L, 50L)
  obs_means[[db]] <- trajectory_jlcm_obs_class_means(m, md, "scr_std")
  pred_all <- c(pred_all, as.numeric(curves[[db]])[as.numeric(curves[[db]]) >= 0.5])
  obs_all <- c(obs_all, md$scr_std)
}
align <- trajectory_align_class_maps(curves, ref = "eicu", obs_means_by_db = obs_means)
ylim <- trajectory_shared_ylim(obs_all, pred_all, ymin = 1)
.make_one <- function(db) {
  m <- .unwrap(packs[[db]]$models$m2)
  md <- packs[[db]]$md
  pp <- as.data.frame(m$pprob)
  long <- md |>
    dplyr::left_join(pp[, c("subject_id_num", "class")], by = "subject_id_num") |>
    dplyr::mutate(Class = paste0("Class", class)) |>
    dplyr::rename(Time = time_day, Value = scr_std)
  .tpj04_make_plot(m, long, ix, ng, 28L, "subject_id", "sans",
                   cov_cols = c("OASIS", "Age", "APSIII", "Temperature"),
                   class_map = align$maps[[db]], ylim = ylim)
}
th <- ggplot2::theme(
  plot.title = ggplot2::element_text(face = "bold", size = 10, hjust = 0,
                                     margin = ggplot2::margin(0, 0, 2, 0)),
  plot.margin = ggplot2::margin(1, 4, 1, 4)
)
p_e <- .make_one("eicu") + ggplot2::labs(title = "A. eICU", x = NULL) + th
p_m <- .make_one("mimic") + ggplot2::labs(title = "B. MIMIC") + th
fig2 <- patchwork::wrap_plots(p_e, p_m, ncol = 1) +
  patchwork::plot_annotation(
    title = "Figure 2. Trajectory of GPR latent classes",
    theme = ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 11, hjust = 0))
  )
.save <- function(p, fp, w, h) {
  dir.create(dirname(fp), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(fp, p, width = w, height = h, device = grDevices::cairo_pdf)
}
w <- 7.8; h <- 6.2
.save(fig2, file.path(out_ix, "Figures/Figure 2. Trajectory of GPR latent classes.pdf"), w, h)
dir.create(file.path(out_ix, "Figures/pdf"), recursive = TRUE, showWarnings = FALSE)
.save(fig2, file.path(out_ix, "Figures/pdf/Figure 2. Trajectory of GPR latent classes.pdf"), w, h)
for (db in c("eicu", "mimic")) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  pp <- if (db == "eicu") p_e else p_m
  .save(pp, file.path(out_ix, db, "Figures",
                      sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix)), 7.8, 2.9)
}
if (exists(".pub_figure_rasterize_one", mode = "function")) {
  tryCatch(.pub_figure_rasterize_one(
    file.path(out_ix, "Figures/pdf/Figure 2. Trajectory of GPR latent classes.pdf"),
    file.path(out_ix, "Figures/png/Figure 2. Trajectory of GPR latent classes.png"),
    file.path(out_ix, "Figures/tiff/Figure 2. Trajectory of GPR latent classes.tiff"),
    300L, root_hint = .root
  ), error = function(e) message(e$message))
}
cat("Fig2 redrawn 7.8 x 6.2 in\n")
