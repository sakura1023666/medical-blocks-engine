#!/usr/bin/env Rscript
# Fix blank S1 (ggsurvplot 2-page) + regenerate S3 subgroup with flush.
# Panel A = eICU (primary), B = MIMIC.

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(cli); library(survival)
  library(survminer); library(patchwork)
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
source("Blocks/53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R", local = FALSE)

block_root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
proj <- file.path(block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr")
index_root <- file.path(proj, "by_index/【success】WPR")
fig_root <- file.path(index_root, "Figures")
if (file.exists(file.path(proj, "config.R"))) source(file.path(proj, "config.R"), local = FALSE)
font_ff <- plot_font_from_config(if (exists("config")) config else list())

.unwrap <- function(m) trajectory_unwrap_jointlcmm(m)
.load_models <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData"), envir = e)
  list(models = e$models_list_with_cov, md = as.data.frame(e$model_data_final))
}
.map2 <- function(m) {
  m <- .unwrap(m)
  cl <- as.integer(as.data.frame(m$pprob)$class)
  tab <- table(cl)
  maj <- as.integer(names(which.max(tab))[1])
  if (identical(maj, 1L)) stats::setNames(c(1L, 2L), c("1", "2"))
  else stats::setNames(c(2L, 1L), c("1", "2"))
}
.patient_df <- function(db, m, cmap) {
  x <- .load_models(db)
  m <- .unwrap(m)
  pp <- as.data.frame(m$pprob)
  base <- x$md[!duplicated(x$md$subject_id_num),
               intersect(names(x$md), c("subject_id_num", "subject_id", "survival_28d", "survival_time_28d"))]
  d <- merge(base, pp[, c("subject_id_num", "class")], by = "subject_id_num")
  d$class_disp <- trajectory_apply_class_swap(as.integer(d$class), cmap)
  d$time <- pmin(as.numeric(d$survival_time_28d), 28)
  d$event <- as.integer(d$survival_28d == 1L)
  d
}

cli_h1("Fix S1 single-page KM + S3 compact subgroup")

# ── S1 ──────────────────────────────────────────────────────────────────────
for (db in c("eicu", "mimic")) {
  db_lab <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  x <- .load_models(db)
  m2 <- .unwrap(x$models$m2)
  cmap <- .map2(m2)
  dd <- .patient_df(db, m2, cmap)
  dd <- dd[is.finite(dd$time) & dd$time > 0 & !is.na(dd$event), ]
  dd$class_f <- factor(paste0("Class ", dd$class_disp), levels = paste0("Class ", 1:2))
  fit <- survfit(Surv(time, event) ~ class_f, data = dd)
  cols <- c("#D55E00", "#E69F00")
  sp <- ggsurvplot(
    fit, data = dd,
    xlim = c(0, 28), break.time.by = 7,
    pval = TRUE, pval.coord = c(6, 0.25),
    conf.int = TRUE,
    legend.title = "Latent Class",
    legend.labs = levels(dd$class_f),
    palette = cols,
    xlab = "Time (Days, 28-day follow-up)",
    ylab = "Survival Probability",
    ggtheme = theme_bw(base_size = 12, base_family = font_ff),
    risk.table = TRUE, risk.table.col = "strata",
    risk.table.y.text.col = TRUE, risk.table.y.text = FALSE,
    risk.table.height = 0.28, ncensor.plot = FALSE
  )
  sp$plot <- sp$plot +
    theme(text = element_text(family = font_ff),
          legend.position = c(0.18, 0.22),
          legend.background = element_rect(fill = alpha("white", 0.75), color = NA))
  if (!is.null(sp$table))
    sp$table <- sp$table + theme(text = element_text(family = font_ff),
                                 plot.title = element_blank())
  # ONE page: plot over risk table (avoid blank page-1 from print(ggsurvplot))
  combined <- if (!is.null(sp$table)) {
    (sp$plot / sp$table) + plot_layout(heights = c(2.6, 1))
  } else sp$plot

  out <- file.path(index_root, db, "Figures",
                   sprintf("Figure S1-%s. Kaplan Meier survival by trajectory class.pdf", db_lab))
  grDevices::cairo_pdf(out, width = 7.2, height = 6.4, family = font_ff)
  print(combined)
  grDevices::dev.off()
  # verify 1 page
  cli_alert_success("S1 {db_lab} rewritten (single page)")
}

# ── S3 ──────────────────────────────────────────────────────────────────────
.ap_vars <- c("Gender", "Hypertension", "CKD", "Hepatitis", "Pneumonia", "COPD")
for (db in c("eicu", "mimic")) {
  db_lab <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  x <- .load_models(db)
  m2 <- .unwrap(x$models$m2)
  cmap <- .map2(m2)
  pd <- .patient_df(db, m2, cmap)
  e <- new.env(parent = emptyenv())
  load(file.path(proj, "data", db, "D02_rt_SAKI_surv28.RData"), envir = e)
  base <- e$rt
  base$subject_id <- as.character(base$subject_id)
  pd$subject_id <- as.character(pd$subject_id)
  dat <- merge(base, pd[, c("subject_id", "class_disp")], by = "subject_id")
  dat$trajectory_class <- as.integer(dat$class_disp)
  if (!"survival_time_28d" %in% names(dat)) {
    dat$survival_time_28d <- pd$time[match(dat$subject_id, pd$subject_id)]
  }
  if (!"survival_28d" %in% names(dat)) {
    dat$survival_28d <- pd$event[match(dat$subject_id, pd$subject_id)]
  }

  tmp <- file.path(index_root, db, "_tmp_sg")
  unlink(tmp, recursive = TRUE)
  dir.create(file.path(tmp, "Figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(tmp, "Tables"), recursive = TRUE, showWarnings = FALSE)
  ctx <- list(
    data = list(imputed = dat),
    config = list(
      project = list(output_dir = tmp, root = .root),
      survival = list(time_var = "survival_time_28d", event_var = "survival_28d"),
      plot = list(font_family = font_ff),
      trajectory_subgroup_class = list(
        class_col = "trajectory_class",
        age_var = "Age", age_cutoff = 65L,
        auto_scan_categorical = FALSE,
        subgroup_vars = .ap_vars,
        min_n_per_subgroup = 5L
      )
    ),
    results = list()
  )
  ctx <- block_trajectory_subgroup_class(ctx)
  # Prefer direct ggsave from result plot (queue path can break with temp output_dir)
  res_list <- ctx$results$trajectory_subgroup_class %||% list()
  pobj <- NULL
  if (length(res_list)) {
    first <- res_list[[1]]
    if (!is.null(first$plot)) pobj <- first$plot
  }
  out <- file.path(index_root, db, "Figures",
                   sprintf("Figure S3-%s. Subgroup analysis by trajectory class.pdf", db_lab))
  if (!is.null(pobj)) {
    # compact height for few rows (~15)
    ggsave(out, pobj, width = 8.2, height = 5.8, device = grDevices::cairo_pdf, family = font_ff)
    file.copy(out, file.path(index_root, db, "Figures", "_raw", "Figure Subgroup TrajectoryClass WPR.pdf"),
              overwrite = TRUE)
    cli_alert_success("S3 {db_lab} ggsave direct")
  } else {
    ctx <- tryCatch(render_queued_figures(ctx), error = function(e) ctx)
    produced <- list.files(file.path(tmp, "Figures"), pattern = "\\.pdf$", full.names = TRUE)
    if (!length(produced)) stop("no subgroup pdf for ", db_lab)
    file.copy(produced[[1]], out, overwrite = TRUE)
    cli_alert_success("S3 {db_lab} from queue")
  }
  for (tf in list.files(file.path(tmp, "Tables"), pattern = "\\.csv$", full.names = TRUE)) {
    file.copy(tf, file.path(index_root, db, "Tables", basename(tf)), overwrite = TRUE)
  }
  unlink(tmp, recursive = TRUE)
}

.compose <- function(stem, layout = "stack") {
  a <- file.path(index_root, "eicu", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  b <- file.path(index_root, "mimic", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  out <- file.path(fig_root, stem)
  .dual_db_compose_pair_pdf(a, b, out, layout = layout,
                            label_a = "A. eICU", label_b = "B. MIMIC",
                            dpi = 220L, label_cex = 1.15)
  cli_alert_success("composed {stem}")
}
.compose("Figure S1. Kaplan Meier survival by trajectory class.pdf", "stack")
.compose("Figure S3. Subgroup analysis by trajectory class.pdf", "stack")
pub_figure_ensure_formats(fig_root, config = if (exists("config")) config else list())
cli_alert_success("S1/S3 fix done")
