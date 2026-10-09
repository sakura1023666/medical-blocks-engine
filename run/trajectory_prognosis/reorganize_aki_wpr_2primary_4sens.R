#!/usr/bin/env Rscript
# Reorganize AKI WPR publication package:
#   Primary = 2-class | Sensitivity = 4-class
#   Target: by_index/【success】WPR  (AP figure/table roles)
#
#   Rscript run/trajectory_prognosis/reorganize_aki_wpr_2primary_4sens.R

suppressPackageStartupMessages({
  library(ggplot2); library(dplyr); library(cli); library(survival)
  library(lcmm); library(splines)
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
source("R/trajectory_paper_tables.R", local = FALSE)
source("R/dual_db_combine_figures.R", local = FALSE)
source("R/pub_figure_export.R", local = FALSE)
source("Blocks/26_trajectory/04block_trajectory_plot_jlcm.R", local = FALSE)

block_root <- if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result" else "G:/02block_result"
proj <- file.path(block_root, "44_AKI_SPESIS_CKD/Prognosis_Trajectory_38882552/tr")
index_root <- file.path(proj, "by_index/【success】WPR")
c4_root <- file.path(proj, "by_index/WPR(class=4)")
stopifnot(dir.exists(index_root))
cfg_path <- file.path(proj, "config.R")
if (file.exists(cfg_path)) source(cfg_path, local = FALSE)

fig_root <- file.path(index_root, "Figures")
tab_root <- file.path(index_root, "Tables")
arch <- file.path(tab_root, "_archive_messy")
dir.create(arch, showWarnings = FALSE, recursive = TRUE)
dir.create(file.path(tab_root, "Summary"), showWarnings = FALSE, recursive = TRUE)

cli_h1("Reorganize 【success】WPR: 2-class primary + 4-class sensitivity")

# ── helpers ─────────────────────────────────────────────────────────────────
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
.map2 <- function(m) {
  m <- .unwrap(m)
  cl <- as.integer(as.data.frame(m$pprob)$class)
  tab <- table(cl)
  maj <- as.integer(names(which.max(tab))[1])
  if (identical(maj, 1L)) stats::setNames(c(1L, 2L), c("1", "2"))
  else stats::setNames(c(2L, 1L), c("1", "2"))
}
# 4-class: Class1=majority low mort both DBs (same as prior align)
.map4 <- list(
  mimic = stats::setNames(c(2L, 3L, 1L, 4L), c("1", "2", "3", "4")),
  eicu  = stats::setNames(c(1L, 3L, 2L, 4L), c("1", "2", "3", "4"))
)
.npar <- function(m) {
  m <- .unwrap(m)
  aic <- as.numeric(m$AIC); ll <- as.numeric(m$loglik)
  if (!is.finite(aic) || !is.finite(ll)) return(NA_real_)
  (aic + 2 * ll) / 2
}
.ave_occ <- function(m, class_map = NULL) {
  m <- .unwrap(m)
  pp <- as.data.frame(m$pprob)
  prob_cols <- grep("^prob", names(pp), value = TRUE)
  cls_raw <- as.integer(pp$class)
  cls <- if (!is.null(class_map)) trajectory_apply_class_swap(cls_raw, class_map) else cls_raw
  ng <- length(prob_cols)
  P <- as.matrix(pp[, prob_cols, drop = FALSE])
  if (!is.null(class_map) && length(class_map) == ng) {
    Pnew <- P
    for (k in seq_along(class_map)) {
      oi <- as.integer(names(class_map)[k]); ni <- as.integer(unname(class_map)[k])
      if (oi <= ncol(P) && ni <= ncol(Pnew)) Pnew[, ni] <- P[, oi]
    }
    P <- Pnew
  }
  tab <- table(factor(cls, levels = seq_len(ng)))
  pi <- as.numeric(prop.table(tab))
  ave <- vapply(seq_len(ng), function(k) {
    idx <- which(cls == k); if (!length(idx)) return(NA_real_)
    mean(P[idx, k], na.rm = TRUE)
  }, numeric(1))
  occ <- vapply(seq_len(ng), function(k) {
    if (!is.finite(ave[k]) || ave[k] >= 1 || pi[k] <= 0 || pi[k] >= 1) return(NA_real_)
    (ave[k] / (1 - ave[k])) / (pi[k] / (1 - pi[k]))
  }, numeric(1))
  data.frame(Class = paste0("Class", seq_len(ng)), n = as.integer(tab),
             Proportion_pct = round(100 * pi, 2), AvePP = round(ave, 5), OCC = round(occ, 2),
             stringsAsFactors = FALSE)
}
.mort <- function(m, base, class_map = NULL) {
  m <- .unwrap(m)
  pp <- as.data.frame(m$pprob)[, c("subject_id_num", "class")]
  d <- merge(base, pp, by = "subject_id_num")
  d$cd <- if (!is.null(class_map)) trajectory_apply_class_swap(d$class, class_map) else as.integer(d$class)
  dplyr::bind_rows(lapply(sort(unique(d$cd)), function(k) {
    x <- d$survival_28d[d$cd == k]
    data.frame(Class = paste0("Class", k), n = length(x),
               Events = sum(x == 1L, na.rm = TRUE),
               Mortality_28d_pct = round(100 * mean(x == 1L, na.rm = TRUE), 1),
               stringsAsFactors = FALSE)
  }))
}
.lrt <- function(label, m_lo, m_hi, n_lo, n_hi) {
  m_lo <- .unwrap(m_lo); m_hi <- .unwrap(m_hi)
  stat <- 2 * (as.numeric(m_hi$loglik) - as.numeric(m_lo$loglik))
  df <- n_hi - n_lo
  p <- if (is.finite(stat) && is.finite(df) && df > 0) pchisq(stat, df, lower.tail = FALSE) else NA_real_
  data.frame(
    Comparison = label,
    LogLik_simpler = round(as.numeric(m_lo$loglik), 1),
    LogLik_complex = round(as.numeric(m_hi$loglik), 1),
    LRT_2deltaLL = round(stat, 2),
    Naive_chisq_P = ifelse(is.finite(p), ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)), "NA"),
    stringsAsFactors = FALSE
  )
}
.parse_s3_hr <- function(xlsx) {
  if (!file.exists(xlsx)) return(NULL)
  raw <- tryCatch(openxlsx::read.xlsx(xlsx, colNames = FALSE), error = function(e) NULL)
  if (is.null(raw) || !nrow(raw)) return(NULL)
  hit <- which(apply(raw, 1L, function(r) any(grepl("^\\s*WPR\\s*$", as.character(r)))))
  if (!length(hit)) hit <- which(apply(raw, 1L, function(r) any(grepl("\\bWPR\\b", as.character(r)))))
  if (!length(hit)) return(NULL)
  row <- as.character(unlist(raw[hit[[1]], ])); row <- row[!is.na(row) & nzchar(row)]
  cell <- row[grepl("\\bp\\s*[=<>]", row, ignore.case = TRUE)][1]
  if (is.na(cell) || !nzchar(cell)) {
    cells <- row[grepl("[0-9.]+\\s*\\(", row)]
    cell <- if (length(cells)) cells[[length(cells)]] else NA_character_
  }
  if (is.na(cell)) return(NULL)
  nums <- as.numeric(unlist(regmatches(cell, gregexpr("[0-9]+\\.[0-9]+|[0-9]+", cell))))
  if (length(nums) < 3) return(NULL)
  list(hr = nums[1], lo = nums[2], hi = nums[3])
}
.flush <- function() {
  ctx <- list(config = list(project = list(database = "MIMIC")))
  if (exists("render_queued_tables", mode = "function")) try(render_queued_tables(ctx), silent = TRUE)
}

# ── 1) Rebuild primary 2-class Fig2 / KM / Table3 / Table2 props / S6 ────────
.make_traj_plot <- function(m, long, cmap, ng, ylim, title_suffix = "") {
  class_colors <- c("Class 1"="#D55E00","Class 2"="#E69F00","Class 3"="#56B4E9","Class 4"="#009E73")
  levels <- paste0("Class ", seq_len(ng))
  md_cov <- long
  if (!"time_day" %in% names(md_cov)) md_cov$time_day <- md_cov$Time
  cov <- trajectory_jlcm_cov_cols(list(), m)
  grid <- trajectory_jlcm_cov_grid(md_cov, cov, time_var = "time_day", cycle = 28L, n = 100L)
  pred <- lcmm::predictY(m, newdata = grid, var.time = "time_day", draws = FALSE)
  pred_tidy <- as.data.frame(pred$pred) |>
    mutate(time = grid$time_day) |>
    tidyr::pivot_longer(cols = starts_with("Ypred"), names_to = "class",
                        names_prefix = "Ypred_class", values_to = "Value") |>
    mutate(class_num = trajectory_apply_class_swap(class, cmap),
           class_label = factor(paste0("Class ", class_num), levels = levels))

  # patient labels from long Class raw
  pp <- as.data.frame(m$pprob)
  # rebuild id map from long unique + pprob order via subject
  # use Class column as raw if present after attach
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

  ncol_f <- if (ng <= 2L) ng else 2L
  ggplot() +
    geom_line(data = pred_tidy, aes(x = time, y = Value, color = class_label), linewidth = 1.5) +
    geom_text(data = outcome, aes(x = x_pos, y = y_pos, label = label_text),
              hjust = 1, vjust = 1, size = 3.2, lineheight = 0.95) +
    facet_wrap(~ class_label, ncol = ncol_f) +
    scale_color_manual(values = class_colors[levels], guide = "none") +
    scale_x_continuous(breaks = seq(0, 28, 7)) +
    coord_cartesian(xlim = c(0, 28), ylim = ylim, expand = FALSE) +
    labs(title = paste0("WPR Trajectories by Latent Class (ng = ", ng, ")", title_suffix),
         x = "Day in ICU", y = "WPR") +
    theme_classic(base_size = 11) +
    theme(legend.position = "none",
          plot.title = element_text(hjust = 0.5, face = "bold", size = 13),
          strip.text = element_text(face = "bold", size = 11),
          strip.background = element_rect(fill = "grey96", color = "grey80"),
          panel.border = element_rect(fill = NA, color = "grey45"),
          panel.spacing = grid::unit(0.8, "lines"))
}

.attach_raw_class <- function(long, md, m) {
  pp <- as.data.frame(.unwrap(m)$pprob)
  id <- unique(md[, c("subject_id", "subject_id_num")])
  id$class_raw <- pp$class[match(id$subject_id_num, pp$subject_id_num)]
  long$Class <- id$class_raw[match(as.character(long$subject_id), as.character(id$subject_id))]
  # ensure survival cols
  if (!"survival_28d" %in% names(long) && "surv_event" %in% names(long))
    long$survival_28d <- long$surv_event
  if (!"survival_time_28d" %in% names(long) && "surv_time" %in% names(long))
    long$survival_time_28d <- long$surv_time
  long
}

.regen_km2 <- function(db, db_lab, m, cmap) {
  x <- .load_models(db); long <- .attach_raw_class(.load_long(db), x$md, m)
  id <- long |>
    distinct(subject_id, survival_28d, survival_time_28d, Class) |>
    mutate(class = trajectory_apply_class_swap(Class, cmap),
           time = pmin(as.numeric(survival_time_28d), 28),
           event = as.integer(survival_28d == 1),
           class_f = factor(paste0("Class ", class), levels = paste0("Class ", 1:2)))
  id <- id[is.finite(id$time) & id$time > 0 & !is.na(id$event), ]
  fit <- survfit(Surv(time, event) ~ class_f, data = id)
  cols <- c("#D55E00", "#E69F00")
  out <- file.path(index_root, db, "Figures",
                   sprintf("Figure S1-%s. Kaplan Meier survival by trajectory class.pdf", db_lab))
  grDevices::cairo_pdf(out, width = 7.2, height = 5.2)
  plot(fit, col = cols, lwd = 2.2, conf.int = FALSE, mark.time = TRUE,
       xlab = "Days since ICU admission", ylab = "Survival probability",
       main = sprintf("%s — KM by WPR class (2-class primary)", db_lab),
       xlim = c(0, 28), ylim = c(0, 1))
  legend("bottomleft", legend = levels(id$class_f), col = cols, lwd = 2.2, bty = "n")
  sd <- survdiff(Surv(time, event) ~ class_f, data = id)
  pval <- 1 - pchisq(sd$chisq, length(sd$n) - 1)
  mtext(sprintf("Log-rank P %s", ifelse(pval < 0.001, "< 0.001", sprintf("= %.3f", pval))),
        side = 3, line = 0.2)
  grDevices::dev.off()
  out
}

.regen_table3_2 <- function(db, db_lab, m, cmap, cut = 3L) {
  x <- .load_models(db); long <- .attach_raw_class(.load_long(db), x$md, m)
  dd <- long |>
    distinct(subject_id, survival_28d, survival_time_28d, Class) |>
    mutate(class = factor(as.character(trajectory_apply_class_swap(Class, cmap)), levels = c("1", "2")),
           time = pmin(as.numeric(survival_time_28d), 28),
           event = as.integer(survival_28d == 1))
  dd$class <- stats::relevel(dd$class, ref = "1")
  fit_piece <- function(which) {
    d <- dd
    if (which == 1L) {
      d$event2 <- ifelse(d$time <= cut, d$event, 0L); d$time2 <- pmin(d$time, cut)
    } else {
      d <- d[d$time > cut, , drop = FALSE]
      if (!nrow(d)) return(NULL)
      d$time2 <- d$time - cut; d$event2 <- d$event
    }
    d <- d[d$time2 > 0, , drop = FALSE]
    tryCatch(coxph(Surv(time2, event2) ~ class, data = d), error = function(e) NULL)
  }
  fmt <- function(fit) {
    if (is.null(fit)) return("NE†")
    s <- summary(fit)
    if (!nrow(s$conf.int)) return("NE†")
    hr <- s$conf.int[1, 1]; lo <- s$conf.int[1, 3]; hi <- s$conf.int[1, 4]
    if (!is.finite(hr) || hr > 1e6) "NE†" else sprintf("%.2f (%.2f, %.2f)", hr, lo, hi)
  }
  body <- data.frame(
    Database = db_lab,
    `Trajectory class` = "Class 2 (ref = Class 1)",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  body[[sprintf("(0,%s]", cut)]] <- fmt(fit_piece(1L))
  body[[sprintf("(%s,28]", cut)]] <- fmt(fit_piece(2L))
  title <- sprintf("Table 3-%s. Time-dependent HR for trajectory classes", db_lab)
  fp <- file.path(tab_root, paste0(title, ".xlsx"))
  export_sci_table(body, fp, title = title, sheet = "Table3",
    table_footnotes = list(
      "Primary analysis: 2-class WPR (Class1 = majority low-risk; Class2 = high-risk).",
      sprintf("Shared piecewise cut = day %s.", cut),
      "†NE = not estimable."
    ))
  .flush()
  file.copy(fp, file.path(index_root, db, "Tables", basename(fp)), overwrite = TRUE)
  fp
}

# shared ylim for 2-class
ylim2 <- c(0, 0.55)
maps2 <- list(); mort2_all <- list(); mort4_all <- list()

for (db in c("mimic", "eicu")) {
  db_lab <- if (db == "mimic") "MIMIC" else "eICU"
  x <- .load_models(db)
  m2 <- .unwrap(x$models$m2); m4 <- .unwrap(x$models$m4)
  map2 <- .map2(m2); maps2[[db]] <- map2
  map4 <- .map4[[db]]
  long <- .attach_raw_class(.load_long(db), x$md, m2)

  # Fig2 primary 2-class
  p2 <- .make_traj_plot(m2, long, map2, 2L, ylim2)
  out2 <- file.path(index_root, db, "Figures",
                    sprintf("Figure 2-%s. Trajectory of WPR latent classes.pdf", db_lab))
  ggsave(out2, p2, width = 9.0, height = 4.6, device = grDevices::cairo_pdf)

  # Fig S9 sensitivity 4-class (2x2, mean only)
  long4 <- .attach_raw_class(.load_long(db), x$md, m4)
  p4 <- .make_traj_plot(m4, long4, map4, 4L, c(0, 1.0), title_suffix = "")
  # retitle inside plot already says ng=4; save as S9
  out9 <- file.path(index_root, db, "Figures",
                    sprintf("Figure S9-%s. Trajectory of WPR four latent classes.pdf", db_lab))
  ggsave(out9, p4, width = 9.5, height = 7.6, device = grDevices::cairo_pdf)

  .regen_km2(db, db_lab, m2, map2)
  .regen_table3_2(db, db_lab, m2, map2, cut = 3L)

  # Table2 with class_map for ng=2 row props
  ctx <- list(config = list())
  t2_title <- sprintf("Table 2-%s. Metrics for determining the optimal number of classes", db_lab)
  t2_fp <- file.path(tab_root, paste0(t2_title, ".xlsx"))
  trajectory_export_table2_sci(ctx, x$models, t2_fp, t2_title, class_map = map2)
  .flush()
  file.copy(t2_fp, file.path(index_root, db, "Tables", basename(t2_fp)), overwrite = TRUE)

  # S6 posterior 2-class
  s6_title <- sprintf("Table S6-%s. Posterior classification table", db_lab)
  s6_fp <- file.path(tab_root, paste0(s6_title, ".xlsx"))
  trajectory_export_posterior_classification_sci(ctx, m2, s6_fp, s6_title, class_map = map2)
  .flush()
  file.copy(s6_fp, file.path(index_root, db, "Tables", basename(s6_fp)), overwrite = TRUE)

  # S5: prefer existing by-class from success S7, or copy from c4 after reorder — use success S7 renamed
  s7_old <- file.path(tab_root, sprintf("Table S7-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab))
  s5_fp <- file.path(tab_root, sprintf("Table S5-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab))
  if (file.exists(s7_old)) {
    file.copy(s7_old, s5_fp, overwrite = TRUE)
    # fix A1 title if helper exists
    if (exists("trajectory_sync_xlsx_a1_from_filename", mode = "function"))
      try(trajectory_sync_xlsx_a1_from_filename(s5_fp), silent = TRUE)
  } else if (file.exists(file.path(c4_root, "Tables", basename(s5_fp)))) {
    # c4 S5 is 4-class columns — don't use; leave if missing
    cli_alert_warning("S5 by-class 2-class source missing for {db_lab}; keep existing if any")
  }

  base <- x$md[!duplicated(x$md$subject_id_num),
               c("subject_id_num", "subject_id", "survival_28d", "survival_time_28d")]
  mort2_all[[db]] <- .mort(m2, base, map2); mort2_all[[db]]$Model <- "2-class (primary)"
  mort4_all[[db]] <- .mort(m4, base, map4); mort4_all[[db]]$Model <- "4-class (sensitivity)"

  # —— S7 / S8 / S9 ——
  s7 <- bind_rows(
    mutate(.ave_occ(m2, map2), Model = "2-class (primary)"),
    mutate(.ave_occ(m4, map4), Model = "4-class (sensitivity)")
  )[, c("Model", "Class", "n", "Proportion_pct", "AvePP", "OCC")]
  s7_title <- sprintf("Table S7-%s. Average posterior probability and OCC for 2-class and 4-class WPR models", db_lab)
  s7_fp <- file.path(tab_root, paste0(s7_title, ".xlsx"))
  export_sci_table(s7, s7_fp, title = s7_title, sheet = "TableS7",
    table_footnotes = list(
      "AvePP = mean posterior probability; OCC = odds of correct classification (Nagin).",
      "Primary = 2-class (min class size / entropy / dual-db phenotype consistency).",
      "4-class shown as sensitivity (information criteria favor more classes but smallest classes are unstable)."
    ))

  s8a <- bind_rows(mort2_all[[db]], mort4_all[[db]])
  s8b <- bind_rows(
    .lrt("2-class vs 1-class", x$models$m1, m2, .npar(x$models$m1), .npar(m2)),
    .lrt("4-class vs 2-class", m2, m4, .npar(m2), .npar(m4))
  )
  s8_body <- bind_rows(
    data.frame(Section = "A. 28-day in-hospital mortality by latent class",
               Col1 = "Model", Col2 = "Class", Col3 = "n", Col4 = "Events", Col5 = "Mortality (%)",
               stringsAsFactors = FALSE),
    data.frame(Section = "", Col1 = s8a$Model, Col2 = s8a$Class, Col3 = as.character(s8a$n),
               Col4 = as.character(s8a$Events), Col5 = as.character(s8a$Mortality_28d_pct),
               stringsAsFactors = FALSE),
    data.frame(Section = "", Col1 = "", Col2 = "", Col3 = "", Col4 = "", Col5 = "", stringsAsFactors = FALSE),
    data.frame(Section = "B. Approximate nested LRT (exploratory)",
               Col1 = "Comparison", Col2 = "LL simpler", Col3 = "LL complex", Col4 = "2ΔLL", Col5 = "Naive P",
               stringsAsFactors = FALSE),
    data.frame(Section = "", Col1 = s8b$Comparison, Col2 = as.character(s8b$LogLik_simpler),
               Col3 = as.character(s8b$LogLik_complex), Col4 = as.character(s8b$LRT_2deltaLL),
               Col5 = s8b$Naive_chisq_P, stringsAsFactors = FALSE)
  )
  names(s8_body) <- c("Section", "V1", "V2", "V3", "V4", "V5")
  s8_title <- sprintf("Table S8-%s. Class-specific 28-day mortality and approximate likelihood-ratio comparisons", db_lab)
  s8_fp <- file.path(tab_root, paste0(s8_title, ".xlsx"))
  export_sci_table(s8_body, s8_fp, title = s8_title, sheet = "TableS8",
    table_footnotes = list(
      "Primary class solution is 2-class; 4-class is sensitivity.",
      "Naive LRT P is exploratory (not formal BLRT)."
    ))

  s3 <- file.path(index_root, db, "Tables", sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab))
  if (!file.exists(s3)) s3 <- file.path(tab_root, basename(s3))
  hr <- .parse_s3_hr(s3)
  s9_title <- sprintf("Table S9-%s. Rescaled univariable HRs for continuous baseline WPR", db_lab)
  s9_fp <- file.path(tab_root, paste0(s9_title, ".xlsx"))
  if (!is.null(hr)) {
    idx_path <- file.path(proj, "data", db, "12_WPR.RData")
    sdw <- NA_real_; n_w <- 0L
    if (file.exists(idx_path)) {
      eix <- new.env(parent = emptyenv()); load(idx_path, envir = eix)
      ids <- unique(as.character(x$md$subject_id))
      w1 <- as.numeric(eix$index_df$WPR_1[as.character(eix$index_df$subject_id) %in% ids])
      sdw <- sd(w1, na.rm = TRUE); n_w <- sum(is.finite(w1))
    }
    rescale <- function(d, lab) data.frame(Contrast = lab,
      HR_CI = sprintf("%.3f (%.3f-%.3f)", hr$hr^d, hr$lo^d, hr$hi^d), stringsAsFactors = FALSE)
    s9 <- bind_rows(
      data.frame(Contrast = "Per +1.00 unit (as in Table S3)",
                 HR_CI = sprintf("%.3f (%.3f-%.3f)", hr$hr, hr$lo, hr$hi), stringsAsFactors = FALSE),
      rescale(0.01, "Per +0.01 unit"),
      rescale(0.05, "Per +0.05 unit"),
      if (is.finite(sdw)) rescale(sdw, sprintf("Per +1 SD (SD=%.4f of baseline WPR_1)", sdw)) else NULL
    )
    export_sci_table(s9, s9_fp, title = s9_title, sheet = "TableS9",
      table_footnotes = list(
        sprintf("Source: Table S3-%s univariable Cox HR for WPR.", db_lab),
        "HR(delta)=HR(1)^delta.",
        if (is.finite(sdw)) sprintf("WPR_1 SD in analysis set (n=%d): %.4f.", n_w, sdw) else "SD NA"
      ))
  }

  # Fig S10 mortality bars
  plot_df <- bind_rows(mort2_all[[db]], mort4_all[[db]])
  plot_df$Model <- factor(plot_df$Model, levels = c("2-class (primary)", "4-class (sensitivity)"))
  plot_df$label <- sprintf("%.1f%%\n(%d/%d)", plot_df$Mortality_28d_pct, plot_df$Events, plot_df$n)
  p10 <- ggplot(plot_df, aes(x = Class, y = Mortality_28d_pct, fill = Class)) +
    geom_col(width = 0.7, color = "grey20", linewidth = 0.2) +
    geom_text(aes(label = label), vjust = -0.15, size = 2.8, lineheight = 0.9) +
    facet_wrap(~ Model, scales = "free_x") +
    scale_fill_manual(values = c("Class1"="#D55E00","Class2"="#E69F00","Class3"="#56B4E9","Class4"="#009E73"), guide = "none") +
    scale_y_continuous(limits = c(0, 100), breaks = seq(0, 100, 20)) +
    labs(title = "28-day in-hospital mortality by WPR latent class", x = NULL, y = "Mortality (%)") +
    theme_classic(base_size = 11) +
    theme(strip.background = element_blank(), strip.text = element_text(face = "bold"),
          plot.title = element_text(face = "bold", hjust = 0.5))
  out10 <- file.path(index_root, db, "Figures",
                     sprintf("Figure S10-%s. Twenty-eight day mortality by WPR trajectory class.pdf", db_lab))
  ggsave(out10, p10, width = 9.0, height = 4.6, device = grDevices::cairo_pdf)

  .flush()
  for (fp in c(s7_fp, s8_fp, s9_fp)) {
    if (file.exists(fp)) file.copy(fp, file.path(index_root, db, "Tables", basename(fp)), overwrite = TRUE)
  }
  cli_alert_success("{db_lab}: primary 2-class + sensitivity 4-class tables/figs written")
}

# save class maps
utils::write.csv(
  rbind(
    data.frame(db = "mimic", model = "m2", old_class = as.integer(names(maps2$mimic)), new_class = as.integer(unname(maps2$mimic))),
    data.frame(db = "eicu", model = "m2", old_class = as.integer(names(maps2$eicu)), new_class = as.integer(unname(maps2$eicu)))
  ),
  file.path(tab_root, "Summary", "class_align_2class_WPR.csv"), row.names = FALSE
)
utils::write.csv(
  data.frame(db = c(rep("mimic",4), rep("eicu",4)),
             old_class = c(3,1,2,4,1,3,2,4), new_class = c(1,2,3,4,1,2,3,4),
             note = "4-class sensitivity; Class1=majority low-risk"),
  file.path(tab_root, "Summary", "class_align_4class_WPR.csv"), row.names = FALSE
)

# ── 2) Figure renumber + compose dual panels ──────────────────────────────────
# Rebuild db tagged names for AP roles from _raw where needed
.rebuild_db_tags <- function(db, db_lab) {
  fdir <- file.path(index_root, db, "Figures")
  raw <- file.path(fdir, "_raw")
  # keep only regenerated primary/sens figs (exact stems — not any S1/S9)
  keep_re <- sprintf(
    paste0(
      "^Figure 2-%s\\. Trajectory of WPR latent classes\\.pdf$",
      "|^Figure S1-%s\\. Kaplan Meier survival by trajectory class\\.pdf$",
      "|^Figure S9-%s\\. Trajectory of WPR four latent classes\\.pdf$",
      "|^Figure S10-%s\\. Twenty-eight day mortality by WPR trajectory class\\.pdf$"
    ),
    db_lab, db_lab, db_lab, db_lab
  )
  all_pdf <- list.files(fdir, pattern = "\\.pdf$", full.names = TRUE)
  keep <- all_pdf[grepl(keep_re, basename(all_pdf))]
  unlink(setdiff(all_pdf, keep))
  unlink(list.files(fdir, pattern = "Missing value overview", full.names = TRUE))

  # 2-class primary dynpred is D2 (not D4)
  dyn_raw <- if (file.exists(file.path(raw, "Figure Dynpred WPR D2.pdf")))
    "Figure Dynpred WPR D2.pdf" else "Figure Dynpred WPR D4.pdf"
  map_raw <- list(
    list(raw = "Figure 1. Flowchart.pdf", out = sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab)),
    list(raw = dyn_raw, out = sprintf("Figure 3-%s. Dynamic prediction of WPR trajectory.pdf", db_lab)),
    list(raw = "Figure Dynpred Individual WPR.pdf", out = sprintf("Figure 4-%s. Individual dynamic prediction.pdf", db_lab)),
    list(raw = "Figure Piecewise Cox CutSearch WPR.pdf", out = sprintf("Figure S2-%s. Piecewise Cox cut point search.pdf", db_lab)),
    list(raw = "Figure Subgroup TrajectoryClass WPR.pdf", out = sprintf("Figure S3-%s. Subgroup analysis by trajectory class.pdf", db_lab)),
    list(raw = "Figure Weibull Dynamic Compare WPR AUC.pdf", out = sprintf("Figure S4-%s. Weibull dynamic model comparison AUC.pdf", db_lab)),
    list(raw = "Figure Weibull Dynamic Compare WPR Cindex.pdf", out = sprintf("Figure S5-%s. Weibull dynamic model comparison C index.pdf", db_lab)),
    list(raw = "Figure Weibull Dynamic Compare WPR Accuracy.pdf", out = sprintf("Figure S6-%s. Weibull dynamic model comparison Accuracy.pdf", db_lab)),
    list(raw = "Figure Weibull Dynamic Compare WPR Sensitivity.pdf", out = sprintf("Figure S7-%s. Weibull dynamic model comparison Sensitivity.pdf", db_lab)),
    list(raw = "Figure Weibull Dynamic Compare WPR Specificity.pdf", out = sprintf("Figure S8-%s. Weibull dynamic model comparison Specificity.pdf", db_lab))
  )
  for (m in map_raw) {
    src <- file.path(raw, m$raw)
    if (file.exists(src)) file.copy(src, file.path(fdir, m$out), overwrite = TRUE)
  }
  cli_alert_info("{db} tagged figures: {paste(basename(list.files(fdir, pattern='\\\\.pdf$')), collapse='; ')}")
}
.rebuild_db_tags("mimic", "MIMIC")
.rebuild_db_tags("eicu", "eICU")

# Clear root figs and compose
unlink(list.files(fig_root, pattern = "\\.pdf$", full.names = TRUE))
for (sub in c("pdf", "png", "tiff")) {
  d <- file.path(fig_root, sub)
  if (dir.exists(d)) unlink(list.files(d, full.names = TRUE))
}

.compose <- function(stem, layout = "stack", mimic_only = FALSE) {
  a <- file.path(index_root, "mimic", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-MIMIC. ", stem))
  b <- file.path(index_root, "eicu", "Figures", sub("^Figure ([0-9S]+)\\. ", "Figure \\1-eICU. ", stem))
  out <- file.path(fig_root, stem)
  if (mimic_only) {
    if (file.exists(a)) file.copy(a, out, overwrite = TRUE)
    return(invisible(file.exists(out)))
  }
  if (!file.exists(a) || !file.exists(b)) {
    cli_alert_warning("缺配对 {stem}")
    return(invisible(FALSE))
  }
  ok <- tryCatch({
    .dual_db_compose_pair_pdf(a, b, out, layout = layout,
                              label_a = "A. MIMIC", label_b = "B. eICU",
                              dpi = 220L, label_cex = 1.2)
    TRUE
  }, error = function(e) { cli_alert_danger("{stem}: {e$message}"); FALSE })
  if (isTRUE(ok)) cli_alert_success("拼好 {stem}")
  invisible(isTRUE(ok))
}

.compose("Figure 1. Flowchart of patient selection.pdf", "side")
.compose("Figure 2. Trajectory of WPR latent classes.pdf", "stack")
.compose("Figure 3. Dynamic prediction of WPR trajectory.pdf", "stack")
.compose("Figure 4. Individual dynamic prediction.pdf", "stack")
.compose("Figure S1. Kaplan Meier survival by trajectory class.pdf", "stack")
.compose("Figure S2. Piecewise Cox cut point search.pdf", mimic_only = TRUE)
.compose("Figure S3. Subgroup analysis by trajectory class.pdf", "stack")
.compose("Figure S4. Weibull dynamic model comparison AUC.pdf", "side")
.compose("Figure S5. Weibull dynamic model comparison C index.pdf", "side")
.compose("Figure S6. Weibull dynamic model comparison Accuracy.pdf", "side")
.compose("Figure S7. Weibull dynamic model comparison Sensitivity.pdf", "side")
.compose("Figure S8. Weibull dynamic model comparison Specificity.pdf", "side")
.compose("Figure S9. Trajectory of WPR four latent classes.pdf", "stack")
.compose("Figure S10. Twenty-eight day mortality by WPR trajectory class.pdf", "stack")

# ── 3) Tables cleanup to AP roles (root + per-db) ───────────────────────────
wanted_re <- c(
  "^Table 1-", "^Table 2-", "^Table 3-",
  "^Table S1-.*after multiple imputation",
  "^Table S2-.*Normality",
  "^Table S3-.*Univariate",
  "^Table S4-.*univariate screen",
  "^Table S5-.*by trajectory class",
  "^Table S6-.*Posterior",
  "^Table S7-.*AvePP|^Table S7-.*OCC|^Table S7-.*2-class and 4-class",
  "^Table S8-.*mortality",
  "^Table S9-.*Rescaled"
)
.clean_tables_dir <- function(tdir, arch_dir) {
  dir.create(arch_dir, showWarnings = FALSE, recursive = TRUE)
  # promote S7 by-class → S5
  for (db_lab in c("MIMIC", "eICU")) {
    s7_bc <- file.path(tdir, sprintf("Table S7-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab))
    s5_bc <- file.path(tdir, sprintf("Table S5-%s. Baseline characteristics by trajectory class (WPR).xlsx", db_lab))
    if (file.exists(s7_bc) && !file.exists(s5_bc)) {
      file.copy(s7_bc, s5_bc, overwrite = TRUE)
      if (exists("trajectory_sync_xlsx_a1_from_filename", mode = "function"))
        try(trajectory_sync_xlsx_a1_from_filename(s5_bc), silent = TRUE)
    }
  }
  for (fp in list.files(tdir, pattern = "\\.xlsx$", full.names = TRUE)) {
    bn <- basename(fp)
    ok <- any(vapply(wanted_re, function(p) grepl(p, bn, ignore.case = TRUE), logical(1)))
    if (!ok) {
      file.copy(fp, file.path(arch_dir, bn), overwrite = TRUE)
      unlink(fp)
    }
  }
}
.clean_tables_dir(tab_root, arch)
for (db in c("mimic", "eicu")) {
  tdir <- file.path(index_root, db, "Tables")
  # mirror rebuilt root tables into db
  for (fp in list.files(tab_root, pattern = "\\.xlsx$", full.names = TRUE)) {
    bn <- basename(fp)
    db_lab <- if (identical(db, "mimic")) "MIMIC" else "eICU"
    if (!grepl(db_lab, bn, fixed = TRUE)) next
    file.copy(fp, file.path(tdir, bn), overwrite = TRUE)
  }
  .clean_tables_dir(tdir, file.path(tdir, "_archive"))
}

pub_figure_ensure_formats(fig_root, config = if (exists("config")) config else list())

# README
readme <- c(
  "# Tables / Figures（WPR）— 主文 2 类 · 敏感性 4 类",
  "",
  "角色对齐 AP `41_AP/.../by_index/WPR`。",
  "",
  "## 主分析（2 类）",
  "| 编号 | 内容 |",
  "|---|---|",
  "| Figure 1 | 纳排流程图 |",
  "| Figure 2 | 2 类 WPR 轨迹 |",
  "| Figure 3–4 | 动态预测 / 个体预测 |",
  "| Figure S1 | KM by class |",
  "| Figure S2 | 分段 Cox 切点（仅 MIMIC） |",
  "| Figure S3 | 亚组 |",
  "| Figure S4–S8 | Weibull 比较 |",
  "| Table 1–3 | 基线 / 选类指标 / 分段 HR |",
  "| Table S1–S4 | 插补 / 正态 / 单因素 / VIF screen |",
  "| Table S5 | 按轨迹类基线（2 类） |",
  "| Table S6 | 后验分类（2 类） |",
  "",
  "## 敏感性（4 类）",
  "| 编号 | 内容 |",
  "|---|---|",
  "| Table S7 | 2 类(主)+4 类(敏) AvePP/OCC |",
  "| Table S8 | 类间死亡 + 近似 LRT |",
  "| Table S9 | 连续 WPR HR 换算 |",
  "| Figure S9 | 4 类轨迹（敏感性） |",
  "| Figure S10 | 28 天死亡率柱图（2 vs 4） |",
  "",
  "## 选类依据",
  "主文 2 类：最小类占比 / Entropy / 双库表型一致。",
  "4 类：信息准则更优，但最小类过小且外验形态不完全同构，仅敏感性。",
  "",
  sprintf("整理时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
writeLines(readme, file.path(tab_root, "README.md"), useBytes = TRUE)
dir.create(file.path(fig_root, "image_information"), showWarnings = FALSE, recursive = TRUE)
writeLines(readme, file.path(fig_root, "image_information", "README.md"), useBytes = TRUE)

# brief note in class=4 folder
note <- c(
  "# 说明",
  "",
  "本目录 `WPR(class=4)` 为强制 4 类探索/旧稿。",
  "**发表终稿请用** `../【success】WPR/`（主文 2 类，敏感性 4 类，已对齐 AP 角色）。",
  sprintf("标注时间: %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
)
if (dir.exists(c4_root)) {
  writeLines(note, file.path(c4_root, "README_USE_SUCCESS_INSTEAD.md"), useBytes = TRUE)
}

cli_alert_success("Done: {index_root}")
cli_alert_info("Figures: {paste(list.files(file.path(fig_root,'pdf')), collapse='; ')}")
cli_alert_info("Tables: {paste(basename(list.files(tab_root, pattern='\\\\.xlsx$')), collapse='; ')}")
