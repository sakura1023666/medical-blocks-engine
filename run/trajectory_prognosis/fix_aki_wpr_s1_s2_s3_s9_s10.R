#!/usr/bin/env Rscript
# Fix AKI success WPR pub figures after 2-primary/4-sens reorg:
#   S1 KM → survminer+risk table (AP style), panel A=eICU (primary)
#   S2 → eICU primary cut search (shared_cut=3), not MIMIC day-26
#   S3 → AP-like short subgroup list + Times + tighter layout
#   S9/S10 → 4-class labels by ascending 28d mortality within each DB
#
#   Rscript run/trajectory_prognosis/fix_aki_wpr_s1_s2_s3_s9_s10.R

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(cli); library(survival)
  library(lcmm); library(splines); library(survminer); library(patchwork)
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
source("Blocks/53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R", local = FALSE)

block_root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
proj <- file.path(block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr")
index_root <- file.path(proj, "by_index/【success】WPR")
fig_root <- file.path(index_root, "Figures")
tab_root <- file.path(index_root, "Tables")
cfg_path <- file.path(proj, "config.R")
if (file.exists(cfg_path)) source(cfg_path, local = FALSE)
font_ff <- plot_font_from_config(if (exists("config")) config else list())
cli_h1("Fix S1/S2/S3/S9/S10 — primary DB = eICU")

.unwrap <- function(m) trajectory_unwrap_jointlcmm(m)
.load_models <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData"), envir = e)
  list(models = e$models_list_with_cov, md = as.data.frame(e$model_data_final))
}
.load_long <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(index_root, db, "step14_trajectory_jlcm/Data/D01_long_WPR_D_1.RData"), envir = e)
  e$long
}
.load_imputed <- function(db) {
  # analysis table with IDs + comorbidities (AfterMI 可能无 subject_id)
  f <- file.path(proj, "data", db, "D02_rt_SAKI_surv28.RData")
  if (file.exists(f)) {
    e <- new.env(parent = emptyenv())
    load(f, envir = e)
    if (exists("rt", envir = e) && is.data.frame(e$rt)) return(e$rt)
  }
  cands <- c(
    file.path(index_root, db, "step06_imputation", "D01_AfterMI_Data.RData"),
    list.files(file.path(index_root, db, "step06_imputation"), pattern = "\\.RData$", full.names = TRUE)
  )
  for (f in unique(unlist(cands))) {
    if (!file.exists(f)) next
    e <- new.env(parent = emptyenv())
    try(load(f, envir = e), silent = TRUE)
    for (nm in ls(e)) {
      obj <- e[[nm]]
      if (is.data.frame(obj) && "Age" %in% names(obj) &&
          any(c("subject_id", "subject_id_num") %in% names(obj))) {
        if (!"subject_id" %in% names(obj) && "subject_id_num" %in% names(obj))
          obj$subject_id <- as.character(obj$subject_id_num)
        return(obj)
      }
    }
  }
  NULL
}

# 2-class: Class1 = majority
.map2 <- function(m) {
  m <- .unwrap(m)
  cl <- as.integer(as.data.frame(m$pprob)$class)
  tab <- table(cl)
  maj <- as.integer(names(which.max(tab))[1])
  if (identical(maj, 1L)) stats::setNames(c(1L, 2L), c("1", "2"))
  else stats::setNames(c(2L, 1L), c("1", "2"))
}
# 4-class sensitivity: ascending 28d mortality within each DB (Class1 lowest … Class4 highest)
.map4_mort <- function(m, md) {
  m <- .unwrap(m)
  pp <- as.data.frame(m$pprob)
  base <- md[!duplicated(md$subject_id_num), c("subject_id_num", "survival_28d")]
  d <- merge(base, pp[, c("subject_id_num", "class")], by = "subject_id_num")
  raws <- sort(unique(as.integer(d$class)))
  mort <- vapply(raws, function(k) mean(d$survival_28d[d$class == k] == 1L, na.rm = TRUE), numeric(1))
  ord <- raws[order(mort)]  # low → high
  # names = old raw, values = new display
  stats::setNames(as.integer(seq_along(ord)), as.character(ord))
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

.save_ggsurv <- function(surv_plot, path, width = 7.2, height = 6.2) {
  dir.create(dirname(path), showWarnings = FALSE, recursive = TRUE)
  grDevices::cairo_pdf(path, width = width, height = height, family = font_ff)
  print(surv_plot)
  grDevices::dev.off()
}

# ── S1: survminer KM (2-class primary) ──────────────────────────────────────
.regen_km <- function(db, db_lab, m, cmap) {
  dd <- .patient_df(db, m, cmap)
  dd <- dd[is.finite(dd$time) & dd$time > 0 & !is.na(dd$event) & !is.na(dd$class_disp), ]
  dd$class_f <- factor(paste0("Class ", dd$class_disp), levels = paste0("Class ", 1:2))
  fit <- survfit(Surv(time, event) ~ class_f, data = dd)
  cols <- c("#D55E00", "#E69F00")
  sp <- ggsurvplot(
    fit, data = dd,
    xlim = c(0, 28), break.time.by = 7,
    pval = TRUE, pval.coord = c(5.5, 0.22),
    conf.int = TRUE,
    legend.title = "Latent Class",
    legend.labs = levels(dd$class_f),
    palette = cols,
    xlab = "Time (Days, 28-day follow-up)",
    ylab = "Survival Probability",
    ggtheme = theme_bw(base_size = 12, base_family = font_ff),
    risk.table = TRUE, risk.table.col = "strata",
    risk.table.y.text.col = TRUE, risk.table.y.text = FALSE,
    risk.table.height = 0.28, ncensor.plot = FALSE,
    title = NULL
  )
  sp$plot <- sp$plot +
    theme(text = element_text(family = font_ff),
          plot.title = element_blank(),
          legend.position = c(0.18, 0.22),
          legend.background = element_rect(fill = alpha("white", 0.7), color = NA))
  if (!is.null(sp$table)) {
    sp$table <- sp$table + theme(text = element_text(family = font_ff))
  }
  out <- file.path(index_root, db, "Figures",
                   sprintf("Figure S1-%s. Kaplan Meier survival by trajectory class.pdf", db_lab))
  .save_ggsurv(sp, out)
  cli_alert_success("S1 KM {db_lab}")
  out
}

# ── S3: compact AP-like subgroup ────────────────────────────────────────────
.ap_subgroup_vars <- c("Gender", "Hypertension", "CKD", "Hepatitis", "Pneumonia", "COPD")

.regen_subgroup <- function(db, db_lab, m, cmap) {
  # Build analysis frame: imputed/baseline + class
  base <- .load_imputed(db)
  if (is.null(base)) stop("no baseline/imputed for ", db)
  pd <- .patient_df(db, m, cmap)
  id_map <- pd[, c("subject_id", "class_disp")]
  # subject_id may be character
  base$subject_id <- as.character(base$subject_id)
  id_map$subject_id <- as.character(id_map$subject_id)
  dat <- merge(base, id_map, by = "subject_id")
  dat$trajectory_class <- as.integer(dat$class_disp)
  # survival cols
  if (!"survival_time_28d" %in% names(dat)) dat$survival_time_28d <- pd$time[match(dat$subject_id, pd$subject_id)]
  if (!"survival_28d" %in% names(dat)) dat$survival_28d <- pd$event[match(dat$subject_id, pd$subject_id)]

  ctx <- list(
    data = list(imputed = dat),
    config = list(
      project = list(output_dir = file.path(index_root, db), root = .root),
      survival = list(time_var = "survival_time_28d", event_var = "survival_28d"),
      plot = list(font_family = font_ff),
      trajectory_subgroup_class = list(
        class_col = "trajectory_class",
        age_var = "Age", age_cutoff = 65L,
        auto_scan_categorical = FALSE,
        subgroup_vars = .ap_subgroup_vars,
        min_n_per_subgroup = 5L,
        index_vars = NULL
      )
    )
  )
  # run one via internal helper path: block expects class col
  bl <- ctx$config$trajectory_subgroup_class
  # call block function pieces
  res <- tryCatch({
    # Directly invoke block with forced class
    source("Blocks/53_trajectory_prognosis_full/06block_trajectory_subgroup_class.R", local = TRUE)
    # Use .tsc06_run_one if available after source — re-source in this env
    NULL
  }, error = function(e) NULL)

  # Inline compact forest using block's runner by temporarily setting output
  out_fig_dir <- file.path(index_root, db, "Figures")
  dir.create(out_fig_dir, showWarnings = FALSE, recursive = TRUE)
  # Build via block API
  ctx2 <- ctx
  ctx2$config$project$output_dir <- file.path(index_root, db, "_tmp_subgroup_fix")
  dir.create(file.path(ctx2$config$project$output_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(ctx2$config$project$output_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
  ctx2 <- block_trajectory_subgroup_class(ctx2)
  # find produced pdf
  produced <- list.files(file.path(ctx2$config$project$output_dir, "Figures"),
                         pattern = "Subgroup.*\\.pdf$", full.names = TRUE)
  out <- file.path(out_fig_dir, sprintf("Figure S3-%s. Subgroup analysis by trajectory class.pdf", db_lab))
  if (length(produced)) {
    file.copy(produced[[1]], out, overwrite = TRUE)
    # also update _raw
    file.copy(produced[[1]], file.path(out_fig_dir, "_raw", "Figure Subgroup TrajectoryClass WPR.pdf"), overwrite = TRUE)
  } else {
    cli_alert_danger("subgroup plot missing for {db_lab}")
  }
  unlink(ctx2$config$project$output_dir, recursive = TRUE)
  cli_alert_success("S3 subgroup {db_lab} (AP-like vars)")
  out
}

# ── S9 traj 4-class ─────────────────────────────────────────────────────────
.make_traj4 <- function(m, long, cmap, ylim) {
  class_colors <- c("Class 1"="#D55E00","Class 2"="#E69F00","Class 3"="#56B4E9","Class 4"="#009E73")
  levels <- paste0("Class ", 1:4)
  md_cov <- long
  if (!"time_day" %in% names(md_cov)) md_cov$time_day <- md_cov$Time
  cov <- trajectory_jlcm_cov_cols(list(), m)
  grid <- trajectory_jlcm_cov_grid(md_cov, cov, time_var = "time_day", cycle = 28L, n = 100L)
  pred <- lcmm::predictY(m, newdata = grid, var.time = "time_day", draws = FALSE)
  pred_tidy <- as.data.frame(pred$pred) |>
    mutate(time = grid$time_day) |>
    tidyr::pivot_longer(cols = starts_with("Ypred"), names_to = "class",
                        names_prefix = "Ypred_class", values_to = "Value") |>
    mutate(class_num = trajectory_apply_class_swap(as.integer(class), cmap),
           class_label = factor(paste0("Class ", class_num), levels = levels))
  idu <- long |>
    distinct(subject_id, survival_28d, survival_time_28d, Class) |>
    mutate(class_num = trajectory_apply_class_swap(Class, cmap))
  outcome <- idu |>
    group_by(class_num) |>
    summarise(n = n(), death_rate = 100 * mean(survival_28d == 1, na.rm = TRUE), .groups = "drop")
  outcome$median_text <- vapply(outcome$class_num, function(cl) {
    sub <- idu[idu$class_num == cl, ]
    ev <- as.integer(sub$survival_28d == 1)
    tm <- pmin(as.numeric(sub$survival_time_28d), 28); tm <- ifelse(ev == 0, 28, tm)
    fit <- tryCatch(survfit(Surv(tm, ev) ~ 1), error = function(e) NULL)
    med <- if (!is.null(fit)) as.numeric(summary(fit)$table["median"]) else NA_real_
    if (is.finite(med)) sprintf("%.1f days", med) else "NR (>28 d)"
  }, character(1))
  outcome <- outcome |>
    mutate(class_label = factor(paste0("Class ", class_num), levels = levels),
           label_text = sprintf("N = %d\nDeath: %.1f%%\nMedian Survival: %s", n, death_rate, median_text),
           x_pos = 27.2, y_pos = ylim[2] - 0.03 * diff(ylim))
  ggplot() +
    geom_line(data = pred_tidy, aes(x = time, y = Value, color = class_label), linewidth = 1.35) +
    geom_text(data = outcome, aes(x = x_pos, y = y_pos, label = label_text),
              hjust = 1, vjust = 1, size = 2.9, lineheight = 0.95, family = font_ff) +
    facet_wrap(~ class_label, ncol = 2) +
    scale_color_manual(values = class_colors[levels], guide = "none") +
    scale_x_continuous(breaks = seq(0, 28, 7)) +
    coord_cartesian(xlim = c(0, 28), ylim = ylim, expand = FALSE) +
    labs(title = "WPR Trajectories by Latent Class (ng = 4, sensitivity)",
         x = "Day in ICU", y = "WPR",
         subtitle = "Class 1–4 ordered by ascending 28-day mortality within database") +
    theme_classic(base_size = 11, base_family = font_ff) +
    theme(legend.position = "none",
          plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          plot.subtitle = element_text(hjust = 0.5, size = 8.5, color = "grey35"),
          strip.text = element_text(face = "bold", size = 10),
          strip.background = element_rect(fill = "grey96", color = "grey80"),
          panel.border = element_rect(fill = NA, color = "grey45"),
          panel.spacing = grid::unit(0.55, "lines"))
}

.attach_raw <- function(long, md, m) {
  pp <- as.data.frame(.unwrap(m)$pprob)
  id <- unique(md[, c("subject_id", "subject_id_num")])
  id$class_raw <- pp$class[match(id$subject_id_num, pp$subject_id_num)]
  long$Class <- id$class_raw[match(as.character(long$subject_id), as.character(id$subject_id))]
  long
}

.mort_bars <- function(db, m2, map2, m4, map4) {
  d2 <- .patient_df(db, m2, map2)
  d4 <- .patient_df(db, m4, map4)
  mk <- function(d, ng, lab) {
    d %>%
      filter(!is.na(class_disp)) %>%
      group_by(Class = paste0("Class", class_disp)) %>%
      summarise(n = n(), Events = sum(event == 1L), 
                Mortality_28d_pct = round(100 * mean(event == 1L), 1), .groups = "drop") %>%
      mutate(Model = lab)
  }
  bind_rows(mk(d2, 2, "2-class (primary)"), mk(d4, 4, "4-class (sensitivity)"))
}

# ── main loop ───────────────────────────────────────────────────────────────
maps4 <- list(); maps2 <- list(); mort_rows <- list()
ylim4 <- c(0, 1.02)

for (db in c("eicu", "mimic")) {
  db_lab <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  x <- .load_models(db)
  m2 <- .unwrap(x$models$m2); m4 <- .unwrap(x$models$m4)
  map2 <- .map2(m2); maps2[[db]] <- map2
  map4 <- .map4_mort(m4, x$md); maps4[[db]] <- map4
  cli_alert_info("{db_lab} map4 (raw→disp): {paste(names(map4), map4, sep='→', collapse=', ')}")

  .regen_km(db, db_lab, m2, map2)
  .regen_subgroup(db, db_lab, m2, map2)

  long4 <- .attach_raw(.load_long(db), x$md, m4)
  p9 <- .make_traj4(m4, long4, map4, ylim4)
  out9 <- file.path(index_root, db, "Figures",
                    sprintf("Figure S9-%s. Trajectory of WPR four latent classes.pdf", db_lab))
  ggsave(out9, p9, width = 7.4, height = 5.6, device = grDevices::cairo_pdf, family = font_ff)

  mr <- .mort_bars(db, m2, map2, m4, map4)
  mort_rows[[db]] <- mr
  mr$Class <- factor(mr$Class, levels = paste0("Class", 1:4))
  mr$Model <- factor(mr$Model, levels = c("2-class (primary)", "4-class (sensitivity)"))
  mr$label <- sprintf("%.1f%%\n(%d/%d)", mr$Mortality_28d_pct, mr$Events, mr$n)
  cols <- c("Class1"="#D55E00","Class2"="#E69F00","Class3"="#56B4E9","Class4"="#009E73")
  p10 <- ggplot(mr, aes(x = Class, y = Mortality_28d_pct, fill = Class)) +
    geom_col(width = 0.72, color = "grey20", linewidth = 0.2) +
    geom_text(aes(label = label), vjust = -0.12, size = 2.7, lineheight = 0.9, family = font_ff) +
    facet_wrap(~ Model, scales = "free_x", nrow = 1) +
    scale_fill_manual(values = cols, guide = "none") +
    coord_cartesian(ylim = c(0, max(mr$Mortality_28d_pct, na.rm = TRUE) * 1.22)) +
    labs(title = "28-day in-hospital mortality by WPR latent class",
         x = NULL, y = "Mortality (%)",
         subtitle = "4-class: Class1–4 = ascending mortality within database") +
    theme_bw(base_size = 11, base_family = font_ff) +
    theme(plot.title = element_text(hjust = 0.5, face = "bold", size = 12),
          plot.subtitle = element_text(hjust = 0.5, size = 8.5, color = "grey35"),
          strip.text = element_text(face = "bold"),
          panel.grid.minor = element_blank(),
          axis.text.x = element_text(size = 9))
  out10 <- file.path(index_root, db, "Figures",
                     sprintf("Figure S10-%s. Twenty-eight day mortality by WPR trajectory class.pdf", db_lab))
  ggsave(out10, p10, width = 7.6, height = 4.4, device = grDevices::cairo_pdf, family = font_ff)
  cli_alert_success("{db_lab}: S9/S10 rewritten")
}

# save maps
utils::write.csv(
  rbind(
    data.frame(db = "eicu", model = "m4",
               old_class = as.integer(names(maps4$eicu)), new_class = as.integer(unname(maps4$eicu)),
               note = "ascending 28d mortality"),
    data.frame(db = "mimic", model = "m4",
               old_class = as.integer(names(maps4$mimic)), new_class = as.integer(unname(maps4$mimic)),
               note = "ascending 28d mortality")
  ),
  file.path(tab_root, "Summary", "class_align_4class_WPR.csv"), row.names = FALSE
)

# ── S2: primary eICU cut search only ────────────────────────────────────────
src_s2 <- file.path(index_root, "eicu", "Figures", "_raw", "Figure Piecewise Cox CutSearch WPR.pdf")
if (!file.exists(src_s2))
  src_s2 <- file.path(index_root, "eicu", "step20_trajectory_piecewise_cox", "Figures",
                      "Figure Piecewise Cox CutSearch WPR.pdf")
out_s2_e <- file.path(index_root, "eicu", "Figures", "Figure S2-eICU. Piecewise Cox cut point search.pdf")
out_s2_root <- file.path(fig_root, "Figure S2. Piecewise Cox cut point search.pdf")
if (file.exists(src_s2)) {
  file.copy(src_s2, out_s2_e, overwrite = TRUE)
  file.copy(src_s2, out_s2_root, overwrite = TRUE)
  # remove misleading MIMIC-as-S2 at root (keep db copy archived name optional)
  cli_alert_success("S2 = eICU primary cut search (shared_cut=3; MIMIC best was 26 — not used)")
} else {
  cli_alert_danger("eICU CutSearch PDF missing")
}

# ── Compose dual panels: A=eICU (primary), B=MIMIC ─────────────────────────
.compose_ab <- function(stem, layout = "stack", eicu_only = FALSE) {
  a <- file.path(index_root, "eicu", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  b <- file.path(index_root, "mimic", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  out <- file.path(fig_root, stem)
  if (eicu_only) {
    if (file.exists(a)) file.copy(a, out, overwrite = TRUE)
    return(invisible(file.exists(out)))
  }
  if (!file.exists(a) || !file.exists(b)) {
    cli_alert_warning("缺配对 {stem} a={file.exists(a)} b={file.exists(b)}")
    return(invisible(FALSE))
  }
  ok <- tryCatch({
    .dual_db_compose_pair_pdf(
      a, b, out, layout = layout,
      label_a = "A. eICU", label_b = "B. MIMIC",
      dpi = 220L, label_cex = 1.15
    )
    TRUE
  }, error = function(e) { cli_alert_danger("{stem}: {e$message}"); FALSE })
  if (isTRUE(ok)) cli_alert_success("拼好 {stem} (A=eICU primary)")
  invisible(isTRUE(ok))
}

# clear old flat copies of targets
for (stem in c(
  "Figure S1. Kaplan Meier survival by trajectory class.pdf",
  "Figure S3. Subgroup analysis by trajectory class.pdf",
  "Figure S9. Trajectory of WPR four latent classes.pdf",
  "Figure S10. Twenty-eight day mortality by WPR trajectory class.pdf"
)) unlink(file.path(fig_root, stem))

.compose_ab("Figure S1. Kaplan Meier survival by trajectory class.pdf", "stack")
.compose_ab("Figure S2. Piecewise Cox cut point search.pdf", eicu_only = TRUE)
.compose_ab("Figure S3. Subgroup analysis by trajectory class.pdf", "stack")
.compose_ab("Figure S9. Trajectory of WPR four latent classes.pdf", "stack")
.compose_ab("Figure S10. Twenty-eight day mortality by WPR trajectory class.pdf", "stack")

# Also fix Fig2/others panel order if currently MIMIC-first? User asked primary — refresh Fig2/S1-related stack figs
# Refresh main dual figs to A=eICU as well (Fig1–4, S4–S8) for consistency
for (stem in c(
  "Figure 1. Flowchart of patient selection.pdf",
  "Figure 2. Trajectory of WPR latent classes.pdf",
  "Figure 3. Dynamic prediction of WPR trajectory.pdf",
  "Figure 4. Individual dynamic prediction.pdf",
  "Figure S4. Weibull dynamic model comparison AUC.pdf",
  "Figure S5. Weibull dynamic model comparison C index.pdf",
  "Figure S6. Weibull dynamic model comparison Accuracy.pdf",
  "Figure S7. Weibull dynamic model comparison Sensitivity.pdf",
  "Figure S8. Weibull dynamic model comparison Specificity.pdf"
)) {
  lay <- if (grepl("Flowchart|Weibull", stem)) "side" else "stack"
  .compose_ab(stem, lay)
}

pub_figure_ensure_formats(fig_root, config = if (exists("config")) config else list())

# README note
readme_extra <- c(
  "",
  "## 本次修正（主库 = eICU）",
  "- Figure S1：survminer KM + 风险表（对齐 AP 风格）；拼图 A=eICU / B=MIMIC",
  "- Figure S2：仅 eICU 切点搜索（shared_cut=3）；MIMIC 单库最优为 day 26，不作主图",
  "- Figure S3：亚组变量收窄为 Age + Gender/Hypertension/CKD/Hepatitis/Pneumonia/COPD（对齐 AP）",
  "- Figure S9–S10：4 类按库内 28 天死亡率升序编号（Class1 最低 → Class4 最高）；双库表型非同构，仅敏感性",
  sprintf("- 修正时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
rp <- file.path(tab_root, "README.md")
if (file.exists(rp)) writeLines(c(readLines(rp, warn = FALSE), readme_extra), rp, useBytes = TRUE)

cli_alert_success("Done fix S1/S2/S3/S9/S10")
