#!/usr/bin/env Rscript
## WPR Jin 交付美化：Fig4（文献式 A+B/C/D）+ S1 居中 + S2 美化
suppressPackageStartupMessages({
  library(survival)
  library(survminer)
  library(ggplot2)
  library(grid)
  library(gridExtra)
  library(cowplot)
})

root <- "/mnt/g/02block_result/36_spesis/prediction_41194138/by_index/\u3010success\u3011WPR"
ck   <- "/mnt/g/02block_result/36_spesis/prediction_41194138/checkpoints/by_index/WPR"
out_pdf  <- file.path(root, "summary_results/Figures/pdf")
out_info <- file.path(root, "summary_results/Figures/image_information")
tmpdir <- "/tmp/wpr_jin_beautify"; dir.create(tmpdir, showWarnings = FALSE, recursive = TRUE)

fill_box <- "#F7E7C7"
.q_lab <- c(
  Q1 = "Low WPR + Low SOFA",
  Q2 = "High WPR + Low SOFA",
  Q3 = "Low WPR + High SOFA",
  Q4 = "High WPR + High SOFA"
)
.pal <- c("#2471A3", "#E67E22", "#1E8449", "#C0392B")

prep_ev <- function(x) {
  if (is.numeric(x) || is.integer(x)) return(as.integer(x > 0))
  xl <- tolower(trimws(as.character(x)))
  as.integer(xl %in% c("1", "yes", "dead", "expired", "non-survivor", "nonsurvivor", "death"))
}

## ===================== Fig 4: Jin-style mediation =====================
message("== Fig4 mediation bootstrap (MIMIC, B=1000) ==")
dat_m <- readRDS(file.path(ck, "MIMIC", "derived_grouping.rds"))$ctx$data$imputed
adj <- c("Age", "Temperature")
med <- "AnionGap"
exp <- "WPR"
B <- 1000L
set.seed(42)

horizons <- list(
  list(lab = "B. In-hospital mortality", time = "futime", event = "fustatus"),
  list(lab = "C. 30-day mortality",      time = "futime_30d", event = "event_30d"),
  list(lab = "D. 365-day mortality",     time = "futime_365d", event = "event_365d")
)

boot_one_horizon <- function(d, time_var, event_var, B = 1000L) {
  need <- c(exp, med, time_var, event_var, adj)
  dd <- as.data.frame(d[, need, drop = FALSE])
  dd[[event_var]] <- prep_ev(dd[[event_var]])
  dd <- dd[stats::complete.cases(dd) & is.finite(dd[[time_var]]) & dd[[time_var]] > 0, , drop = FALSE]
  dd$.M_z <- as.numeric(scale(dd[[med]]))
  n <- nrow(dd)
  f_a <- as.formula(paste(".M_z ~", exp, "+", paste(adj, collapse = "+")))
  f_full <- as.formula(paste0("Surv(", time_var, ",", event_var, ") ~ ", exp, " + .M_z + ", paste(adj, collapse = "+")))

  ## point estimates
  m_a <- lm(f_a, data = dd)
  m_f <- coxph(f_full, data = dd)
  a0 <- unname(coef(m_a)[exp])
  b0 <- unname(coef(m_f)[".M_z"])
  c0 <- unname(coef(m_f)[exp])
  ab0 <- a0 * b0

  ## bootstrap draws of a*b and c'
  draws <- matrix(NA_real_, nrow = B, ncol = 2L, dimnames = list(NULL, c("indirect", "direct")))
  for (i in seq_len(B)) {
    idx <- sample.int(n, replace = TRUE)
    db <- dd[idx, , drop = FALSE]
    db$.M_z <- as.numeric(scale(db[[med]]))
    ca <- tryCatch(unname(coef(lm(f_a, data = db))[exp]), error = function(e) NA_real_)
    mf <- tryCatch(coxph(f_full, data = db), error = function(e) NULL)
    if (is.null(mf)) next
    cb <- tryCatch(unname(coef(mf)[".M_z"]), error = function(e) NA_real_)
    cc <- tryCatch(unname(coef(mf)[exp]), error = function(e) NA_real_)
    if (!is.finite(ca) || !is.finite(cb) || !is.finite(cc)) next
    draws[i, 1L] <- ca * cb
    draws[i, 2L] <- cc
  }
  list(
    n = n, a = a0, b = b0, ab = ab0, cprime = c0,
    indirect = draws[, 1L], direct = draws[, 2L],
    ab_ci = quantile(draws[, 1L], c(0.025, 0.975), na.rm = TRUE),
    c_ci  = quantile(draws[, 2L], c(0.025, 0.975), na.rm = TRUE)
  )
}

res_h <- lapply(horizons, function(h) {
  message("  ", h$lab, " ...")
  boot_one_horizon(dat_m, h$time, h$event, B = B)
})

## Panel A: conceptual DAG
panel_a <- local({
  nodes <- data.frame(
    x = c(1.0, 3.0, 5.0),
    y = c(1.0, 2.35, 1.0),
    lab = c("WPR", "AnionGap", "Mortality risk"),
    fill = c("#F5CBA7", "#AED6F1", "#F5B7B1"),
    stringsAsFactors = FALSE
  )
  ## arrow segments (shortened to box edges)
  segs <- data.frame(
    x = c(1.55, 3.55, 1.75),
    y = c(1.45, 1.85, 1.0),
    xend = c(2.45, 4.45, 4.25),
    yend = c(2.0, 1.35, 1.0),
    lbl = c("a1", "b1", "c1"),
    lx = c(1.75, 4.15, 3.0),
    ly = c(1.95, 1.85, 0.72),
    stringsAsFactors = FALSE
  )
  ggplot() +
    geom_segment(
      data = segs, aes(x = x, y = y, xend = xend, yend = yend),
      arrow = arrow(length = unit(0.18, "cm"), type = "closed"),
      color = "#1E8449", linewidth = 0.9, lineend = "round"
    ) +
    geom_label(
      data = nodes, aes(x = x, y = y, label = lab, fill = fill),
      label.size = 0.35, label.r = unit(1.5, "pt"),
      size = 4.2, fontface = "bold", color = "black",
      label.padding = unit(0.35, "lines"), show.legend = FALSE
    ) +
    scale_fill_identity() +
    geom_text(data = segs, aes(x = lx, y = ly, label = lbl),
              size = 3.6, fontface = "bold", color = "#145A32") +
    coord_cartesian(xlim = c(0.3, 5.7), ylim = c(0.35, 2.85), expand = FALSE) +
    labs(title = "A. Mediation model") +
    theme_void(base_family = "sans") +
    theme(
      plot.title = element_text(face = "bold", size = 11, hjust = 0, margin = margin(b = 4)),
      plot.margin = margin(4, 8, 2, 8)
    )
})

dens_panel <- function(vals, est, ci, title, fill_col, subtitle) {
  vals <- vals[is.finite(vals)]
  df <- data.frame(x = vals)
  lo <- unname(ci[1]); hi <- unname(ci[2])
  ann <- sprintf("Estimate = %.3f\n95%% CI (%.3f, %.3f)", est, lo, hi)
  ggplot(df, aes(x = x)) +
    geom_histogram(aes(y = after_stat(density)), bins = 30,
                   fill = fill_col, color = "grey30", alpha = 0.85, linewidth = 0.2) +
    geom_density(color = "grey20", linewidth = 0.55) +
    geom_vline(xintercept = est, color = "#C0392B", linewidth = 0.8) +
    geom_vline(xintercept = c(lo, hi), color = "#C0392B", linetype = "dashed", linewidth = 0.55) +
    annotate("text", x = Inf, y = Inf, label = ann, hjust = 1.05, vjust = 1.2,
             size = 2.7, color = "grey15") +
    labs(title = title, subtitle = subtitle, x = NULL, y = "Density") +
    theme_bw(base_size = 8) +
    theme(
      plot.title = element_text(face = "bold", size = 8.5, margin = margin(b = 1)),
      plot.subtitle = element_text(size = 6.5, color = "grey30", margin = margin(b = 2)),
      panel.grid.minor = element_blank(),
      axis.title.y = element_text(size = 7),
      plot.margin = margin(3, 4, 2, 4)
    )
}

col_plots <- lapply(seq_along(horizons), function(i) {
  r <- res_h[[i]]
  hlab <- horizons[[i]]$lab
  ## strip leading "B. "/"C. "/"D. "
  hshort <- sub("^[A-Z]\\.\\s*", "", hlab)
  p_ind <- dens_panel(
    r$indirect, r$ab, r$ab_ci,
    title = paste0(substr(hlab, 1, 1), ". Indirect effect (a \u00d7 b)"),
    fill_col = "#82E0AA",
    subtitle = paste0(hshort, "\nBootstrap distributions (B=1000)")
  )
  p_dir <- dens_panel(
    r$direct, r$cprime, r$c_ci,
    title = "Direct effect (c')",
    fill_col = "#F5CBA7",
    subtitle = "Solid red: estimate; dashed: 95% CI"
  )
  plot_grid(p_ind, p_dir, ncol = 1, align = "v", rel_heights = c(1, 1))
})

fig4 <- plot_grid(
  panel_a,
  plot_grid(plotlist = col_plots, ncol = 3, align = "h"),
  ncol = 1, rel_heights = c(0.28, 0.72)
)

fig4_path <- file.path(tmpdir, "fig4.pdf")
ggsave(fig4_path, fig4, width = 10.5, height = 8.2, device = cairo_pdf)
message("Fig4 saved: ", fig4_path)

## save numeric summary
sink(file.path(tmpdir, "fig4_mediation_summary.txt"))
for (i in seq_along(horizons)) {
  r <- res_h[[i]]
  cat(horizons[[i]]$lab, " n=", r$n, "\n", sep = "")
  cat(sprintf("  a=%.4f  b=%.4f  a*b=%.4f (%.4f, %.4f)\n",
              r$a, r$b, r$ab, r$ab_ci[1], r$ab_ci[2]))
  cat(sprintf("  c'=%.4f (%.4f, %.4f)  prop=%.1f%%\n\n",
              r$cprime, r$c_ci[1], r$c_ci[2], 100 * r$ab / r$cprime))
}
sink()

## ===================== S1 centered flowchart =====================
message("== S1 redraw ==")
draw_s1_one <- function(path, db, n0, n_ex, n_an, qn, gns, panel) {
  cairo_pdf(path, width = 8.4, height = 6.6)
  grid.newpage()
  grid.text("Figure S1. The study flowchart",
            x = 0.5, y = 0.975, gp = gpar(fontsize = 12, fontface = "bold"))
  grid.text(sprintf("(%s. %s)", panel, db),
            x = 0.5, y = 0.948, gp = gpar(fontsize = 10, col = "grey25"))

  rr <- function(x, y, w, h, lab, fs = 8) {
    grid.roundrect(
      x = unit(x, "npc"), y = unit(y, "npc"),
      width = unit(w, "npc"), height = unit(h, "npc"),
      r = unit(1.5, "pt"),
      gp = gpar(fill = fill_box, col = "black", lwd = 1.05)
    )
    grid.text(lab, x = unit(x, "npc"), y = unit(y, "npc"),
              gp = gpar(fontsize = fs, lineheight = 1.08), just = "center")
  }
  vline <- function(x, y0, y1, arrow = TRUE) {
    grid.lines(
      x = unit(c(x, x), "npc"), y = unit(c(y0, y1), "npc"),
      gp = gpar(lwd = 1.05),
      arrow = if (arrow) arrow(length = unit(4.5, "pt"), type = "closed") else NULL
    )
  }
  hline <- function(x0, x1, y, arrow = TRUE) {
    grid.lines(
      x = unit(c(x0, x1), "npc"), y = unit(c(y, y), "npc"),
      gp = gpar(lwd = 1.05),
      arrow = if (arrow) arrow(length = unit(4.5, "pt"), type = "closed") else NULL
    )
  }

  ## centered trunk at x=0.48
  cx <- 0.48
  rr(cx, 0.86, 0.58, 0.10, sprintf(
    "Adult patients with sepsis, aged >= 18 years, with ICU\nadmission were extracted from the %s database (N=%s)",
    db, format(n0, big.mark = ",")
  ), fs = 7.8)

  vline(cx, 0.81, 0.74, arrow = FALSE)
  hline(cx, 0.74, 0.775)
  rr(0.88, 0.775, 0.22, 0.11, sprintf(
    "Excluding patients with\nmissing WPR components\n(WBC or platelet) (N=%s)",
    format(n_ex, big.mark = ",")
  ), fs = 6.8)
  vline(cx, 0.74, 0.66)

  rr(cx, 0.62, 0.34, 0.07, sprintf("Analysis cohort (N=%s)", format(n_an, big.mark = ",")), fs = 8.5)

  ## split
  vline(cx, 0.585, 0.545, arrow = FALSE)
  hline(0.24, 0.72, 0.545, arrow = FALSE)
  vline(0.24, 0.545, 0.505)
  vline(0.72, 0.545, 0.505)

  rr(0.24, 0.47, 0.28, 0.055, "Patients categorized by WPR", fs = 7.5)
  rr(0.72, 0.47, 0.34, 0.055, "Stratification by WPR and SOFA", fs = 7.5)

  ## quartiles — evenly spaced under left branch, centered on 0.24
  xs <- c(0.09, 0.19, 0.29, 0.39)
  hline(min(xs), max(xs), 0.435, arrow = FALSE)
  for (i in seq_along(xs)) {
    vline(xs[i], 0.435, 0.395)
    rr(xs[i], 0.30, 0.092, 0.13,
       sprintf("Quartile %d\n(N=%s)", i, format(qn[[paste0("Q", i)]], big.mark = ",")),
       fs = 6.6)
  }

  ## right 2x2 — centered under 0.72, more padding
  vline(0.72, 0.442, 0.40)
  grid.rect(
    x = unit(0.72, "npc"), y = unit(0.22, "npc"),
    width = unit(0.40, "npc"), height = unit(0.30, "npc"),
    gp = gpar(fill = NA, col = "black", lwd = 1.1)
  )
  ## Group order matches Jin ESM (not Q code order)
  rr(0.60, 0.30, 0.165, 0.095, sprintf("Group 1:\nLow WPR + Low SOFA\n(N=%s)", format(gns[["Q1"]], big.mark = ",")), 6.2)
  rr(0.84, 0.30, 0.165, 0.095, sprintf("Group 2:\nLow WPR + High SOFA\n(N=%s)", format(gns[["Q3"]], big.mark = ",")), 6.2)
  rr(0.60, 0.15, 0.165, 0.095, sprintf("Group 3:\nHigh WPR + Low SOFA\n(N=%s)", format(gns[["Q2"]], big.mark = ",")), 6.2)
  rr(0.84, 0.15, 0.165, 0.095, sprintf("Group 4:\nHigh WPR + High SOFA\n(N=%s)", format(gns[["Q4"]], big.mark = ",")), 6.2)

  grid.text(
    "SOFA cutoff = 5; Groups 1-4 use tertile extremes of WPR (T1/T3) \u00d7 SOFA; middle tertile excluded from Groups",
    x = 0.5, y = 0.025, gp = gpar(fontsize = 6.5, col = "grey35")
  )
  dev.off()
}

gn_for <- function(db) {
  d <- readRDS(file.path(ck, db, "derived_grouping.rds"))$ctx$data$imputed
  tab <- table(d$Index_SOFA_Q, useNA = "no")
  setNames(as.integer(tab[c("Q1", "Q2", "Q3", "Q4")]), c("Q1", "Q2", "Q3", "Q4"))
}

specs <- list(
  MIMIC = list(n0 = 8245L, n_an = 8218L, q = c(Q1 = 2055L, Q2 = 2054L, Q3 = 2053L, Q4 = 2056L), lab = "A"),
  eICU  = list(n0 = 13946L, n_an = 13635L, q = c(Q1 = 3393L, Q2 = 3413L, Q3 = 3415L, Q4 = 3414L), lab = "B")
)
s1_parts <- c()
for (db in names(specs)) {
  sp <- specs[[db]]
  p <- file.path(tmpdir, paste0("s1_", db, ".pdf"))
  draw_s1_one(p, db, sp$n0, sp$n0 - sp$n_an, sp$n_an, as.list(sp$q), gn_for(db), sp$lab)
  s1_parts <- c(s1_parts, p)
}
## stack with python later
message("S1 parts ok")

## ===================== S2 beautified KM =====================
message("== S2 redraw ==")
hz <- list(
  list(title = "A. In-hospital mortality", time = "futime", event = "fustatus", xmax = 90),
  list(title = "B. 30-day mortality", time = "futime_30d", event = "event_30d", xmax = 30),
  list(title = "C. 365-day mortality", time = "futime_365d", event = "event_365d", xmax = 365)
)

make_db_km <- function(db, path) {
  dat <- readRDS(file.path(ck, db, "derived_grouping.rds"))$ctx$data$imputed
  short_lab <- c(Q1 = "G1 Low+Low", Q2 = "G3 High+Low", Q3 = "G2 Low+High", Q4 = "G4 High+High")
  ## display order matching Jin Group 1-4 for legend clarity: Q1,Q3,Q2,Q4
  ord <- c("Q1", "Q3", "Q2", "Q4")
  pal_ord <- c("#2471A3", "#E67E22", "#1E8449", "#C0392B") ## Low+Low, Low+High, High+Low, High+High

  plots <- lapply(hz, function(h) {
    d <- dat[!is.na(dat$Index_SOFA_Q), , drop = FALSE]
    d$strata <- factor(
      as.character(d$Index_SOFA_Q),
      levels = ord,
      labels = c("Low WPR + Low SOFA", "Low WPR + High SOFA",
                 "High WPR + Low SOFA", "High WPR + High SOFA")
    )
    tt <- as.numeric(d[[h$time]])
    ev <- prep_ev(d[[h$event]])
    ok <- is.finite(tt) & tt > 0 & !is.na(ev) & !is.na(d$strata)
    d <- d[ok, , drop = FALSE]; tt <- tt[ok]; ev <- ev[ok]
    xmax <- h$xmax
    br <- if (xmax <= 30) 5 else if (xmax <= 120) 15 else 60
    sdf <- data.frame(tt = tt, ev = ev, strata = d$strata)
    sf <- survfit(Surv(tt, ev) ~ strata, data = sdf)
    ggsurvplot(
      sf, data = sdf,
      conf.int = FALSE,
      risk.table = TRUE,
      risk.table.col = "strata",
      risk.table.height = 0.30,
      xlim = c(0, xmax),
      break.time.by = br,
      xlab = "Follow-up day",
      ylab = "Survival probability",
      title = h$title,
      legend.title = "",
      legend = "none",
      palette = pal_ord,
      censor = TRUE,
      censor.size = 1.8,
      size = 0.95,
      ggtheme = theme_classic(base_size = 9) +
        theme(
          plot.title = element_text(face = "bold", size = 10, hjust = 0.5),
          axis.title = element_text(size = 8.5),
          axis.text = element_text(size = 7.5),
          plot.margin = margin(4, 6, 2, 4)
        ),
      tables.theme = theme_cleantable() +
        theme(
          axis.text.y = element_text(size = 6.2, color = "grey20"),
          plot.title = element_text(size = 8, face = "bold")
        ),
      risk.table.fontsize = 2.6,
      risk.table.title = "Number at risk",
      pval = TRUE,
      pval.size = 3.4,
      pval.coord = c(0.02 * xmax, 0.06),
      pval.method = FALSE
    )
  })

  ## combine
  combined <- arrange_ggsurvplots(
    plots, print = FALSE, ncol = 3, nrow = 1, risk.table.height = 0.30
  )
  pdf(path, width = 13.5, height = 6.6)
  print(combined)
  grid.text(
    sprintf("Figure S2. %s — Kaplan-Meier by WPR \u00d7 SOFA strata", db),
    x = 0.5, y = 0.992, gp = gpar(fontsize = 11, fontface = "bold"), just = "top"
  )
  grid.text(
    "Group order (colors): blue=Low WPR+Low SOFA; orange=Low WPR+High SOFA; green=High WPR+Low SOFA; red=High WPR+High SOFA",
    x = 0.5, y = 0.012, gp = gpar(fontsize = 7, col = "grey35"), just = "bottom"
  )
  dev.off()
  path
}

s2_m <- make_db_km("MIMIC", file.path(tmpdir, "s2_MIMIC.pdf"))
s2_e <- make_db_km("eICU",  file.path(tmpdir, "s2_eICU.pdf"))
message("S2 ok")

writeLines(c(fig4_path, s1_parts, s2_m, s2_e), file.path(tmpdir, "parts.txt"))
message("DONE tmpdir=", tmpdir)
