#!/usr/bin/env Rscript
## Fig4 双库一页；S1/S2 双库一页；S1 字体 Times New Roman
suppressPackageStartupMessages({
  library(survival); library(survminer); library(ggplot2)
  library(cowplot); library(grid); library(gridExtra)
})

ck <- "/mnt/g/02block_result/36_spesis/prediction_41194138/checkpoints/by_index/WPR"
out_pdf <- "/mnt/g/02block_result/36_spesis/prediction_41194138/by_index/\u3010success\u3011WPR/summary_results/Figures/pdf"
out_info <- "/mnt/g/02block_result/36_spesis/prediction_41194138/by_index/\u3010success\u3011WPR/summary_results/Figures/image_information"
tmpdir <- "/tmp/wpr_jin_onepage"; dir.create(tmpdir, showWarnings = FALSE, recursive = TRUE)
ff <- "Times New Roman"
fill_box <- "#F7E7C7"
adj <- c("Age", "Temperature")
B <- 1000L

prep_ev <- function(x) {
  if (is.numeric(x) || is.integer(x)) return(as.integer(x > 0))
  xl <- tolower(trimws(as.character(x)))
  as.integer(xl %in% c("1", "yes", "dead", "expired", "non-survivor", "nonsurvivor", "death"))
}

## ===================== Fig4 dual mediation =====================
message("== Fig4 dual bootstrap ==")
boot_one <- function(d, time_var, event_var, B = 1000L) {
  need <- c("WPR", "AnionGap", time_var, event_var, adj)
  dd <- as.data.frame(d[, need, drop = FALSE])
  dd[[event_var]] <- prep_ev(dd[[event_var]])
  dd <- dd[stats::complete.cases(dd) & is.finite(dd[[time_var]]) & dd[[time_var]] > 0, , drop = FALSE]
  dd$.M_z <- as.numeric(scale(dd[["AnionGap"]]))
  n <- nrow(dd)
  f_a <- as.formula(paste(".M_z ~ WPR +", paste(adj, collapse = "+")))
  f_full <- as.formula(paste0("Surv(", time_var, ",", event_var, ") ~ WPR + .M_z + ", paste(adj, collapse = "+")))
  m_a <- lm(f_a, data = dd); m_f <- coxph(f_full, data = dd)
  a0 <- unname(coef(m_a)["WPR"]); b0 <- unname(coef(m_f)[".M_z"]); c0 <- unname(coef(m_f)["WPR"])
  ab0 <- a0 * b0
  draws <- matrix(NA_real_, B, 2)
  for (i in seq_len(B)) {
    idx <- sample.int(n, replace = TRUE)
    db <- dd[idx, , drop = FALSE]; db$.M_z <- as.numeric(scale(db[["AnionGap"]]))
    ca <- tryCatch(unname(coef(lm(f_a, data = db))["WPR"]), error = function(e) NA_real_)
    mf <- tryCatch(coxph(f_full, data = db), error = function(e) NULL)
    if (is.null(mf)) next
    cb <- tryCatch(unname(coef(mf)[".M_z"]), error = function(e) NA_real_)
    cc <- tryCatch(unname(coef(mf)["WPR"]), error = function(e) NA_real_)
    if (!is.finite(ca) || !is.finite(cb) || !is.finite(cc)) next
    draws[i, ] <- c(ca * cb, cc)
  }
  list(
    n = n, ab = ab0, cprime = c0,
    indirect = draws[, 1], direct = draws[, 2],
    ab_ci = quantile(draws[, 1], c(0.025, 0.975), na.rm = TRUE),
    c_ci = quantile(draws[, 2], c(0.025, 0.975), na.rm = TRUE)
  )
}

horizons <- list(
  list(code = "B", lab = "In-hospital", time = "futime", event = "fustatus"),
  list(code = "C", lab = "30-day", time = "futime_30d", event = "event_30d"),
  list(code = "D", lab = "365-day", time = "futime_365d", event = "event_365d")
)

panel_a_dag <- function(title) {
  nodes <- data.frame(
    x = c(1, 3, 5), y = c(1, 2.2, 1),
    lab = c("WPR", "AnionGap", "Mortality risk"),
    fill = c("#F5CBA7", "#AED6F1", "#F5B7B1")
  )
  segs <- data.frame(
    x = c(1.55, 3.55, 1.75), y = c(1.4, 1.75, 1),
    xend = c(2.45, 4.45, 4.25), yend = c(1.9, 1.35, 1),
    lbl = c("a1", "b1", "c1"),
    lx = c(1.75, 4.15, 3), ly = c(1.85, 1.75, 0.72)
  )
  ggplot() +
    geom_segment(data = segs, aes(x = x, y = y, xend = xend, yend = yend),
                 arrow = arrow(length = unit(0.14, "cm"), type = "closed"),
                 color = "#1E8449", linewidth = 0.75) +
    geom_label(data = nodes, aes(x = x, y = y, label = lab, fill = fill),
               linewidth = 0.3, label.r = unit(1.2, "pt"),
               size = 3.2, fontface = "bold", family = ff, show.legend = FALSE,
               label.padding = unit(0.28, "lines")) +
    scale_fill_identity() +
    geom_text(data = segs, aes(x = lx, y = ly, label = lbl),
              size = 2.8, fontface = "bold", color = "#145A32", family = ff) +
    coord_cartesian(xlim = c(0.4, 5.6), ylim = c(0.4, 2.7), expand = FALSE) +
    labs(title = title) +
    theme_void(base_family = ff) +
    theme(
      plot.title = element_text(face = "bold", size = 10, hjust = 0, family = ff,
                                margin = margin(b = 2)),
      plot.margin = margin(2, 4, 1, 4)
    )
}

dens_panel <- function(vals, est, ci, title, fill_col, subtitle) {
  vals <- vals[is.finite(vals)]
  df <- data.frame(x = vals)
  lo <- unname(ci[1]); hi <- unname(ci[2])
  ann <- sprintf("Estimate = %.3f\n95%% CI (%.3f, %.3f)", est, lo, hi)
  ggplot(df, aes(x = x)) +
    geom_histogram(aes(y = after_stat(density)), bins = 28,
                   fill = fill_col, color = "grey35", alpha = 0.85, linewidth = 0.15) +
    geom_density(color = "grey20", linewidth = 0.45) +
    geom_vline(xintercept = est, color = "#C0392B", linewidth = 0.65) +
    geom_vline(xintercept = c(lo, hi), color = "#C0392B", linetype = "dashed", linewidth = 0.45) +
    annotate("text", x = Inf, y = Inf, label = ann, hjust = 1.05, vjust = 1.15,
             size = 2.2, family = ff, color = "grey15") +
    labs(title = title, subtitle = subtitle, x = NULL, y = "Density") +
    theme_bw(base_size = 7, base_family = ff) +
    theme(
      plot.title = element_text(face = "bold", size = 7.5, family = ff, margin = margin(b = 0)),
      plot.subtitle = element_text(size = 5.8, color = "grey30", family = ff, margin = margin(b = 1)),
      panel.grid.minor = element_blank(),
      axis.title.y = element_text(size = 6.5, family = ff),
      axis.text = element_text(size = 5.8, family = ff),
      plot.margin = margin(2, 3, 1, 3)
    )
}

db_block <- function(db, panel_letter) {
  message("  ", db, " ...")
  set.seed(42)
  dat <- readRDS(file.path(ck, db, "derived_grouping.rds"))$ctx$data$imputed
  res <- lapply(horizons, function(h) boot_one(dat, h$time, h$event, B = B))
  dag <- panel_a_dag(sprintf("%s. %s — Mediation model", panel_letter, db))
  cols <- lapply(seq_along(horizons), function(i) {
    r <- res[[i]]; h <- horizons[[i]]
    p1 <- dens_panel(r$indirect, r$ab, r$ab_ci,
                     paste0(h$code, ". Indirect (a\u00d7b)"), "#82E0AA",
                     paste0(h$lab, " mortality | B=1000"))
    p2 <- dens_panel(r$direct, r$cprime, r$c_ci,
                     "Direct (c')", "#F5CBA7",
                     "Solid=estimate; dashed=95% CI")
    plot_grid(p1, p2, ncol = 1, align = "v")
  })
  dens <- plot_grid(plotlist = cols, ncol = 3, align = "h")
  list(
    plot = plot_grid(dag, dens, ncol = 1, rel_heights = c(0.26, 0.74)),
    summary = res
  )
}

m_blk <- db_block("MIMIC", "A")
e_blk <- db_block("eICU", "B")

fig4 <- plot_grid(
  ggdraw() + draw_label("Figure 4. Mediation analysis of WPR via AnionGap",
                        fontface = "bold", size = 12, fontfamily = ff),
  m_blk$plot,
  e_blk$plot,
  ncol = 1, rel_heights = c(0.035, 0.482, 0.483)
)
fig4_path <- file.path(out_pdf, "Figure 4. Mediation analysis of WPR via AnionGap.pdf")
ggsave(fig4_path, fig4, width = 10.8, height = 11.0, device = cairo_pdf, limitsize = FALSE)
message("Fig4 one-page dual saved")

## summary txt for md
sink(file.path(tmpdir, "fig4_summary.txt"))
for (db in c("MIMIC", "eICU")) {
  blk <- if (db == "MIMIC") m_blk else e_blk
  cat("===", db, "===\n")
  for (i in seq_along(horizons)) {
    r <- blk$summary[[i]]
    cat(sprintf("%s: a*b=%.3f (%.3f, %.3f); c'=%.3f (%.3f, %.3f); n=%d\n",
                horizons[[i]]$lab, r$ab, r$ab_ci[1], r$ab_ci[2],
                r$cprime, r$c_ci[1], r$c_ci[2], r$n))
  }
  cat("\n")
}
sink()

## ===================== S1 one-page Times =====================
message("== S1 one-page Times ==")

draw_s1_panel <- function(db, n0, n_ex, n_an, qn, gns, panel, vp) {
  pushViewport(vp)
  grid.text(sprintf("(%s. %s)", panel, db),
            x = 0.5, y = 0.985, gp = gpar(fontsize = 10, fontface = "bold", fontfamily = ff))

  put <- function(x, y, w, h, lab, fs = 7.2) {
    grid.roundrect(
      x = unit(x, "npc"), y = unit(y, "npc"),
      width = unit(w, "npc"), height = unit(h, "npc"),
      r = unit(1, "pt"),
      gp = gpar(fill = fill_box, col = "black", lwd = 1.15)
    )
    grid.text(lab, x = unit(x, "npc"), y = unit(y, "npc"),
              gp = gpar(fontsize = fs, lineheight = 1.05, fontfamily = ff), just = "center")
  }
  ah <- function(x0, tip_x, y) {
    tip <- 0.012
    grid.lines(x = unit(c(x0, tip_x - tip * 0.85), "npc"), y = unit(c(y, y), "npc"),
               gp = gpar(lwd = 1.2, lineend = "butt"))
    grid.polygon(
      x = unit(c(tip_x, tip_x - tip, tip_x - tip), "npc"),
      y = unit(c(y, y + tip * 0.55, y - tip * 0.55), "npc"),
      gp = gpar(fill = "black", col = NA)
    )
  }
  av <- function(x, y0, tip_y) {
    tip <- 0.014
    grid.lines(x = unit(c(x, x), "npc"), y = unit(c(y0, tip_y + tip * 0.85), "npc"),
               gp = gpar(lwd = 1.2, lineend = "butt"))
    grid.polygon(
      x = unit(c(x, x - tip * 0.55, x + tip * 0.55), "npc"),
      y = unit(c(tip_y, tip_y + tip, tip_y + tip), "npc"),
      gp = gpar(fill = "black", col = NA)
    )
  }

  cx <- 0.46
  top_y <- 0.90; top_h <- 0.10; top_w <- 0.56
  an_y <- 0.58; an_h <- 0.075; an_w <- 0.34
  top_bot <- top_y - top_h / 2
  an_top <- an_y + an_h / 2
  y_ex <- top_bot * 0.28 + an_top * 0.72
  ex_x <- 0.86; ex_w <- 0.24; ex_h <- 0.12

  ## boxes
  put(cx, top_y, top_w, top_h, sprintf(
    "Adult patients with sepsis, aged >= 18 years, with ICU\nadmission were extracted from the %s database (N=%s)",
    db, format(n0, big.mark = ",")
  ), 6.8)
  put(ex_x, y_ex, ex_w, ex_h, sprintf(
    "Excluding patients with\nmissing WPR components\n(WBC or platelet) (N=%s)",
    format(n_ex, big.mark = ",")
  ), 6.2)
  put(cx, an_y, an_w, an_h, sprintf("Analysis cohort (N=%s)", format(n_an, big.mark = ",")), 7.5)

  left_x <- 0.22; left_y <- 0.43; left_w <- 0.28; left_h <- 0.06
  right_x <- 0.70; right_y <- 0.43; right_w <- 0.34; right_h <- 0.06
  put(left_x, left_y, left_w, left_h, "Patients categorized by WPR", 6.8)
  put(right_x, right_y, right_w, right_h, "Stratification by WPR and SOFA", 6.8)

  xs <- c(0.08, 0.17, 0.27, 0.36)
  qy <- 0.24; qw <- 0.088; qh <- 0.13
  for (i in seq_along(xs)) {
    put(xs[i], qy, qw, qh,
        sprintf("Quartile %d\n(N=%s)", i, format(qn[[paste0("Q", i)]], big.mark = ",")), 6.0)
  }
  grid.rect(x = unit(0.70, "npc"), y = unit(0.175, "npc"),
            width = unit(0.48, "npc"), height = unit(0.30, "npc"),
            gp = gpar(fill = "white", col = "black", lwd = 1.1))
  put(0.58, 0.24, 0.18, 0.095, sprintf("Group 1:\nLow WPR + Low SOFA\n(N=%s)", format(gns[["Q1"]], big.mark = ",")), 5.5)
  put(0.82, 0.24, 0.18, 0.095, sprintf("Group 2:\nLow WPR + High SOFA\n(N=%s)", format(gns[["Q3"]], big.mark = ",")), 5.5)
  put(0.58, 0.11, 0.18, 0.095, sprintf("Group 3:\nHigh WPR + Low SOFA\n(N=%s)", format(gns[["Q2"]], big.mark = ",")), 5.5)
  put(0.82, 0.11, 0.18, 0.095, sprintf("Group 4:\nHigh WPR + High SOFA\n(N=%s)", format(gns[["Q4"]], big.mark = ",")), 5.5)

  ## arrows on top
  grid.lines(x = unit(c(cx, cx), "npc"), y = unit(c(top_bot, y_ex), "npc"), gp = gpar(lwd = 1.2))
  ah(cx, ex_x - ex_w / 2 + 0.006, y_ex)
  av(cx, y_ex, an_top - 0.006)

  an_bot <- an_y - an_h / 2
  left_top <- left_y + left_h / 2
  y_split <- (an_bot + left_top) / 2
  grid.lines(x = unit(c(cx, cx), "npc"), y = unit(c(an_bot, y_split), "npc"), gp = gpar(lwd = 1.2))
  grid.lines(x = unit(c(left_x, right_x), "npc"), y = unit(c(y_split, y_split), "npc"), gp = gpar(lwd = 1.2))
  av(left_x, y_split, left_top - 0.005)
  av(right_x, y_split, (right_y + right_h / 2) - 0.005)

  left_bot <- left_y - left_h / 2
  y_qbar <- left_bot - 0.015
  grid.lines(x = unit(c(left_x, left_x), "npc"), y = unit(c(left_bot, y_qbar), "npc"), gp = gpar(lwd = 1.2))
  grid.lines(x = unit(c(min(xs), max(xs)), "npc"), y = unit(c(y_qbar, y_qbar), "npc"), gp = gpar(lwd = 1.2))
  for (xi in xs) av(xi, y_qbar, (qy + qh / 2) - 0.005)

  right_bot <- right_y - right_h / 2
  frame_top <- 0.175 + 0.30 / 2
  av(right_x, right_bot, frame_top - 0.004)

  grid.text(
    "SOFA cutoff = 5; Groups 1-4 = WPR tertile extremes (T1/T3) x SOFA; middle tertile excluded",
    x = 0.5, y = 0.015, gp = gpar(fontsize = 5.8, col = "grey35", fontfamily = ff)
  )
  popViewport()
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

s1_path <- file.path(out_pdf, "Figure S1. Inclusion exclusion flowchart.pdf")
cairo_pdf(s1_path, width = 8.6, height = 11.0)
grid.newpage()
grid.text("Figure S1. The study flowchart", x = 0.5, y = 0.985,
          gp = gpar(fontsize = 12, fontface = "bold", fontfamily = ff))
## top half MIMIC, bottom half eICU
draw_s1_panel("MIMIC", specs$MIMIC$n0, specs$MIMIC$n0 - specs$MIMIC$n_an, specs$MIMIC$n_an,
              as.list(specs$MIMIC$q), gn_for("MIMIC"), "A",
              viewport(x = 0.5, y = 0.74, width = 1, height = 0.48, just = "centre"))
draw_s1_panel("eICU", specs$eICU$n0, specs$eICU$n0 - specs$eICU$n_an, specs$eICU$n_an,
              as.list(specs$eICU$q), gn_for("eICU"), "B",
              viewport(x = 0.5, y = 0.26, width = 1, height = 0.48, just = "centre"))
## divider
grid.lines(x = unit(c(0.05, 0.95), "npc"), y = unit(c(0.50, 0.50), "npc"),
           gp = gpar(lwd = 0.6, col = "grey70", lty = 2))
dev.off()
message("S1 one-page saved")

## ===================== S2 one-page dual =====================
message("== S2 one-page ==")
pal_ord <- c("#2471A3", "#E67E22", "#1E8449", "#C0392B")
ord <- c("Q1", "Q3", "Q2", "Q4")
labs4 <- c("Low WPR + Low SOFA", "Low WPR + High SOFA",
           "High WPR + Low SOFA", "High WPR + High SOFA")

nice_xmax <- function(tt) {
  m <- max(tt, na.rm = TRUE)
  if (m <= 100) return(ceiling(m / 10) * 10)
  if (m <= 200) return(ceiling(m / 25) * 25)
  ceiling(m / 50) * 50
}

one_km_panel <- function(dat, h) {
  d <- dat[!is.na(dat$Index_SOFA_Q), , drop = FALSE]
  d$strata <- factor(as.character(d$Index_SOFA_Q), levels = ord, labels = labs4)
  tt <- as.numeric(d[[h$time]]); ev <- prep_ev(d[[h$event]])
  ok <- is.finite(tt) & tt > 0 & !is.na(ev) & !is.na(d$strata)
  d <- d[ok, , drop = FALSE]; tt <- tt[ok]; ev <- ev[ok]
  xmax <- if (is.null(h$xmax) || !is.finite(h$xmax)) nice_xmax(tt) else h$xmax
  br <- if (xmax <= 30) 5 else if (xmax <= 100) 20 else if (xmax <= 200) 25 else 50
  sdf <- data.frame(tt = tt, ev = ev, strata = d$strata)
  sf <- survfit(Surv(tt, ev) ~ strata, data = sdf)
  g <- ggsurvplot(
    sf, data = sdf, conf.int = FALSE, risk.table = TRUE, risk.table.col = "strata",
    risk.table.height = 0.34, xlim = c(0, xmax), break.time.by = br,
    xlab = "Follow-up day", ylab = "Survival probability", title = h$title,
    legend = "none", palette = pal_ord, censor = TRUE, censor.size = 1.2, size = 0.8,
    ggtheme = theme_classic(base_size = 8, base_family = ff) + theme(
      plot.title = element_text(face = "bold", size = 8.5, hjust = 0.5, family = ff),
      axis.title = element_text(size = 7, family = ff),
      axis.text = element_text(size = 6, family = ff),
      plot.margin = margin(2, 3, 1, 2)
    ),
    tables.theme = theme_cleantable() + theme(
      axis.text.y = element_text(size = 5, family = ff),
      plot.title = element_text(size = 6.5, face = "bold", family = ff)
    ),
    risk.table.fontsize = 2.0, risk.table.title = "Number at risk",
    pval = TRUE, pval.size = 2.8, pval.coord = c(0.02 * xmax, 0.06)
  )
  g$table <- g$table + scale_y_discrete(labels = function(x) {
    x <- gsub("Low WPR \\+ Low SOFA", "Low+Low", x)
    x <- gsub("Low WPR \\+ High SOFA", "Low+High", x)
    x <- gsub("High WPR \\+ Low SOFA", "High+Low", x)
    x <- gsub("High WPR \\+ High SOFA", "High+High", x)
    x
  })
  plot_grid(g$plot, g$table, ncol = 1, rel_heights = c(0.66, 0.34), align = "v")
}

make_db_row <- function(db, row_letter) {
  dat <- readRDS(file.path(ck, db, "derived_grouping.rds"))$ctx$data$imputed
  hz <- list(
    list(title = "In-hospital", time = "futime", event = "fustatus", xmax = NA_real_),
    list(title = "30-day", time = "futime_30d", event = "event_30d", xmax = 30),
    list(title = "365-day", time = "futime_365d", event = "event_365d", xmax = 365)
  )
  panels <- lapply(seq_along(hz), function(i) {
    h <- hz[[i]]
    h$title <- sprintf("%s%s. %s", row_letter, letters[i], h$title)
    one_km_panel(dat, h)
  })
  body <- plot_grid(plotlist = panels, ncol = 3, align = "h")
  title <- ggdraw() + draw_label(sprintf("%s. %s", row_letter, db),
                                 fontface = "bold", size = 10, fontfamily = ff)
  plot_grid(title, body, ncol = 1, rel_heights = c(0.06, 0.94))
}

s2 <- plot_grid(
  ggdraw() + draw_label("Figure S2. Kaplan-Meier by WPR x SOFA strata",
                        fontface = "bold", size = 11, fontfamily = ff),
  make_db_row("MIMIC", "A"),
  make_db_row("eICU", "B"),
  ggdraw() + draw_label(
    "Colors: blue=Low+Low; orange=Low+High; green=High+Low; red=High+High  |  In-hospital x-axis = full observed LOS",
    size = 7, color = "grey35", fontfamily = ff
  ),
  ncol = 1, rel_heights = c(0.03, 0.475, 0.475, 0.02)
)
s2_path <- file.path(out_pdf, "Figure S2. Kaplan-Meier curves of WPR Index SOFA Q and multi-horizon mortality.pdf")
ggsave(s2_path, s2, width = 12.5, height = 11.0, device = cairo_pdf, limitsize = FALSE)
message("S2 one-page saved")

## image_information refresh
dir.create(out_info, showWarnings = FALSE, recursive = TRUE)
sumtxt <- paste(readLines(file.path(tmpdir, "fig4_summary.txt")), collapse = "\n")
writeLines(c(
  "# Figure 4. Mediation analysis of WPR via AnionGap",
  "",
  "## 图面说明",
  "单页双库拼图：上半 **A. MIMIC**、下半 **B. eICU**。每库均为 Jin 式版式——概念路径图（WPR→AnionGap→Mortality，a1/b1/c1）+ 院内/30天/365天间接(a×b)与直接(c′) Bootstrap 分布（B=1000）。红实线=点估计，红虚线=95% CI。协变量 Age+Temperature；中介 1-SD 标准化。",
  "",
  "图上标注：",
  sumtxt,
  "",
  "## 分析上下文",
  "暴露：WPR。中介：AnionGap。结局：院内/30天/365天全因死亡。数据库：MIMIC + eICU（单页上下拼图）。"
), file.path(out_info, "Figure 4. Mediation analysis of WPR via AnionGap.md"))

writeLines(c(
  "# Figure S1. Inclusion exclusion flowchart",
  "",
  "## 图面说明",
  "单页双库拼图：上 **A. MIMIC**、下 **B. eICU**。字体 Times New Roman。提取→排除（框在两主框中间）→Analysis cohort；左四分位、右 WPR×SOFA 四组（含 N）。",
  "",
  "## 分析上下文",
  "样本量：MIMIC N=8,218；eICU N=13,635。数据库：MIMIC + eICU（单页拼图）。"
), file.path(out_info, "Figure S1. Inclusion exclusion flowchart.md"))

writeLines(c(
  "# Figure S2. Kaplan-Meier curves of WPR Index SOFA Q and multi-horizon mortality",
  "",
  "## 图面说明",
  "单页双库拼图：上 **A. MIMIC**、下 **B. eICU**；每行三列院内/30天/365天 KM + Number at risk。院内横轴为完整观测住院随访。字体 Times New Roman。",
  "",
  "## 分析上下文",
  "暴露：WPR×SOFA 四组。数据库：MIMIC + eICU（单页拼图）。"
), file.path(out_info, "Figure S2. Kaplan-Meier curves of WPR Index SOFA Q and multi-horizon mortality.md"))

message("DONE")
