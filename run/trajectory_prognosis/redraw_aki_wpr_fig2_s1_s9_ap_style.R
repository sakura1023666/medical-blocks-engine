#!/usr/bin/env Rscript
# Redraw AKI WPR Fig2 / S1 / S9 to match AP publication style exactly:
#   Fig2 / S9: engine .tpj04_make_plot (spaghetti + mean, facet Class side-by-side / 2x2)
#   S1: ggsurvplot legend=top + risk table, print(newpage=FALSE)
#   Dual compose: A=eICU (primary), B=MIMIC
#
#   Rscript run/trajectory_prognosis/redraw_aki_wpr_fig2_s1_s9_ap_style.R

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(cli); library(survival)
  library(lcmm); library(splines); library(survminer)
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
source("R/utils.R", local = FALSE)
source("R/trajectory_survival_utils.R", local = FALSE)
source("R/dual_db_combine_figures.R", local = FALSE)
source("R/pub_figure_export.R", local = FALSE)
source("Blocks/26_trajectory/04block_trajectory_plot_jlcm.R", local = FALSE)

block_root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
proj <- file.path(block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr")
index_root <- file.path(proj, "by_index/【success】WPR")
fig_root <- file.path(index_root, "Figures")
if (file.exists(file.path(proj, "config.R"))) source(file.path(proj, "config.R"), local = FALSE)
font_ff <- plot_font_from_config(if (exists("config")) config else list())

cli_h1("Redraw Fig2 / S1 / S9 — AP style (primary=eICU)")

.unwrap <- function(m) trajectory_unwrap_jointlcmm(m)
.load_models <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData"), envir = e)
  list(models = e$models_list_with_cov, md = as.data.frame(e$model_data_final))
}
.load_long <- function(db, ng) {
  e <- new.env(parent = emptyenv())
  f <- file.path(index_root, db, "step14_trajectory_jlcm/Data",
                 sprintf("D01_long_WPR_D_%d.RData", as.integer(ng)))
  if (!file.exists(f))
    f <- file.path(index_root, db, "step14_trajectory_jlcm/Data", "D01_long_WPR_D_1.RData")
  load(f, envir = e)
  e$long
}
.map2 <- function(m) {
  m <- .unwrap(m)
  cl <- as.integer(as.data.frame(m$pprob)$class)
  tab <- table(cl)
  maj <- as.integer(names(which.max(tab))[1])
  if (identical(maj, 1L)) stats::setNames(c(1L, 2L), c("1", "2"))
  else stats::setNames(c(2L, 1L), c("1", "2"))
}
.map4_mort <- function(m, md) {
  m <- .unwrap(m)
  pp <- as.data.frame(m$pprob)
  base <- md[!duplicated(md$subject_id_num), c("subject_id_num", "survival_28d")]
  d <- merge(base, pp[, c("subject_id_num", "class")], by = "subject_id_num")
  raws <- sort(unique(as.integer(d$class)))
  mort <- vapply(raws, function(k) mean(d$survival_28d[d$class == k] == 1L, na.rm = TRUE), numeric(1))
  ord <- raws[order(mort)]
  stats::setNames(as.integer(seq_along(ord)), as.character(ord))
}

.attach_class_surv <- function(long, md, m) {
  m <- .unwrap(m)
  pp <- as.data.frame(m$pprob)
  id <- unique(md[, intersect(names(md),
                              c("subject_id", "subject_id_num", "survival_28d", "survival_time_28d"))])
  id$class_raw <- as.integer(pp$class[match(id$subject_id_num, pp$subject_id_num)])
  long$Class <- id$class_raw[match(as.character(long$subject_id), as.character(id$subject_id))]
  if (all(is.na(long$Class))) {
    long$Class <- suppressWarnings(as.integer(gsub("\\D+", "", as.character(long$Class))))
  }
  surv <- id[, c("subject_id", "survival_28d", "survival_time_28d")]
  names(surv) <- c("subject_id", "surv_event", "surv_time")
  long$surv_event <- surv$surv_event[match(as.character(long$subject_id), as.character(surv$subject_id))]
  long$surv_time  <- surv$surv_time[match(as.character(long$subject_id), as.character(surv$subject_id))]
  if (!"Time" %in% names(long) && "time_day" %in% names(long)) long$Time <- long$time_day
  if (!"Value" %in% names(long) && "scr_std" %in% names(long)) long$Value <- long$scr_std
  long
}

.save_cairo <- function(p, path, width, height) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  ggplot2::ggsave(path, p, width = width, height = height,
                  device = grDevices::cairo_pdf, family = font_ff)
}

# ── KM (AP style) ───────────────────────────────────────────────────────────
.regen_km <- function(db, db_lab, m, cmap) {
  x <- .load_models(db)
  m <- .unwrap(m)
  pp <- as.data.frame(m$pprob)
  base <- x$md[!duplicated(x$md$subject_id_num),
               intersect(names(x$md), c("subject_id_num", "survival_28d", "survival_time_28d"))]
  d <- merge(base, pp[, c("subject_id_num", "class")], by = "subject_id_num")
  d$class_disp <- trajectory_apply_class_swap(as.integer(d$class), cmap)
  max_fu <- 28
  d$event <- as.integer(d$survival_28d == 1L)
  d$raw_time <- as.numeric(d$survival_time_28d)
  d$survival_time <- ifelse(d$event == 0L, max_fu, pmin(d$raw_time, max_fu))
  d <- d[is.finite(d$survival_time) & d$survival_time > 0 & !is.na(d$event) & !is.na(d$class_disp), ]
  # endpoint death epsilon (engine)
  eps <- 1e-3
  d$time_plot <- ifelse(d$event == 1L & d$survival_time >= max_fu, max_fu - eps, d$survival_time)
  d$class_f <- factor(paste0("Class ", d$class_disp), levels = paste0("Class ", sort(unique(d$class_disp))))

  fit <- survfit(Surv(time_plot, event) ~ class_f, data = d)
  ng <- nlevels(d$class_f)
  cols <- c("#D55E00", "#E69F00", "#56B4E9", "#009E73")[seq_len(ng)]
  sp <- ggsurvplot(
    fit, data = d,
    xlim = c(0, max_fu), break.time.by = 7,
    pval = TRUE, pval.coord = c(max_fu * 0.18, 0.18),
    conf.int = TRUE,
    legend = "top",
    legend.title = "Latent Class",
    legend.labs = levels(d$class_f),
    palette = cols,
    xlab = paste0("Time (Days, ", max_fu, "-day follow-up)"),
    ylab = "Survival Probability",
    ggtheme = theme_bw(base_size = 12, base_family = font_ff),
    risk.table = TRUE,
    risk.table.col = "strata",
    risk.table.y.text.col = TRUE,
    risk.table.y.text = FALSE,
    risk.table.height = 0.28,
    tables.theme = theme_cleantable(),
    ncensor.plot = FALSE,
    censor = TRUE
  )
  sp$plot <- sp$plot +
    theme(
      text = element_text(family = font_ff),
      legend.position = "top"
    )
  # do not touch sp$table theme (ggplot2 4.x merge clash with survminer)

  out <- file.path(index_root, db, "Figures",
                   sprintf("Figure S1-%s. Kaplan Meier survival by trajectory class.pdf", db_lab))
  grDevices::cairo_pdf(out, width = 8, height = 6, family = font_ff)
  print(sp, newpage = FALSE)
  grDevices::dev.off()
  raw <- file.path(index_root, db, "Figures", "_raw")
  dir.create(raw, showWarnings = FALSE, recursive = TRUE)
  file.copy(out, file.path(raw, "Figure KM TrajectoryClass WPR.pdf"), overwrite = TRUE)
  cli_alert_success("S1 KM {db_lab}")
  invisible(out)
}

# ── Trajectory via engine plot ──────────────────────────────────────────────
.regen_traj <- function(db, db_lab, m, cmap, ng, out_name, ylim = NULL, width = NULL, height = NULL) {
  x <- .load_models(db)
  m <- .unwrap(m)
  long <- .attach_class_surv(.load_long(db, ng), x$md, m)
  # drop rows without class
  long <- long[!is.na(long$Class), , drop = FALSE]
  p <- .tpj04_make_plot(
    model_obj = m, long_data = long, Index = "WPR", D = ng,
    cycle = 28L, id_col = "subject_id", font_family = font_ff,
    cov_cols = character(0), class_map = cmap, ylim = ylim
  )
  if (is.null(p)) stop("traj plot NULL for ", db_lab, " ng=", ng)
  # 2-class: wide short like AP; 4-class: taller 2x2
  if (is.null(width)) width <- if (ng <= 2L) 7.8 else 7.4
  if (is.null(height)) height <- if (ng <= 2L) 3.45 else 5.5
  out <- file.path(index_root, db, "Figures", out_name)
  .save_cairo(p, out, width, height)
  raw <- file.path(index_root, db, "Figures", "_raw")
  dir.create(raw, showWarnings = FALSE, recursive = TRUE)
  if (ng <= 2L) {
    file.copy(out, file.path(raw, sprintf("Figure Trajectory WPR D2-%s.pdf", db_lab)), overwrite = TRUE)
  } else {
    file.copy(out, file.path(raw, "Figure Trajectory WPR four latent classes.pdf"), overwrite = TRUE)
  }
  cli_alert_success("Traj ng={ng} {db_lab}")
  invisible(out)
}

# shared ylim for 2-class / 4-class across DBs (AP-like)
ylim2 <- c(0, 0.55)
ylim4 <- c(0, 1.02)

for (db in c("eicu", "mimic")) {
  db_lab <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  x <- .load_models(db)
  m2 <- .unwrap(x$models$m2)
  m4 <- .unwrap(x$models$m4)
  map2 <- .map2(m2)
  map4 <- .map4_mort(m4, x$md)
  cli_alert_info("{db_lab} map2={paste(names(map2), map2, sep='→', collapse=', ')} | map4={paste(names(map4), map4, sep='→', collapse=', ')}")

  .regen_traj(db, db_lab, m2, map2, 2L,
              sprintf("Figure 2-%s. Trajectory of WPR latent classes.pdf", db_lab),
              ylim = ylim2, width = 7.8, height = 3.45)
  .regen_km(db, db_lab, m2, map2)
  .regen_traj(db, db_lab, m4, map4, 4L,
              sprintf("Figure S9-%s. Trajectory of WPR four latent classes.pdf", db_lab),
              ylim = ylim4, width = 7.6, height = 5.6)
}

# compose A=eICU B=MIMIC
.compose <- function(stem, layout = "stack") {
  a <- file.path(index_root, "eicu", "Figures",
                 sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  b <- file.path(index_root, "mimic", "Figures",
                 sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  out <- file.path(fig_root, stem)
  if (!file.exists(a) || !file.exists(b)) {
    cli_alert_danger("缺 {stem}")
    return(invisible(FALSE))
  }
  .dual_db_compose_pair_pdf(
    a, b, out, layout = layout,
    label_a = "A. eICU", label_b = "B. MIMIC",
    dpi = 220L, label_cex = 1.15
  )
  cli_alert_success("拼好 {stem}")
  invisible(TRUE)
}

.compose("Figure 2. Trajectory of WPR latent classes.pdf", "stack")
.compose("Figure S1. Kaplan Meier survival by trajectory class.pdf", "stack")
.compose("Figure S9. Trajectory of WPR four latent classes.pdf", "stack")

pub_figure_ensure_formats(fig_root, config = if (exists("config")) config else list())
cli_alert_success("Done AP-style Fig2 / S1 / S9")
