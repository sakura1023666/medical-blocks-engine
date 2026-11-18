suppressPackageStartupMessages({
  library(survival)
  library(survminer)
  library(grid)
  library(ggplot2)
})

root <- "/mnt/g/02block_result/36_spesis/prediction_41194138/by_index/\u3010success\u3011WPR"
ck <- "/mnt/g/02block_result/36_spesis/prediction_41194138/checkpoints/by_index/WPR"
out_pdf <- file.path(root, "summary_results/Figures/pdf")
out_info <- file.path(root, "summary_results/Figures/image_information")
tmpdir <- "/tmp/wpr_jin_final"; dir.create(tmpdir, showWarnings = FALSE)

fill <- "#F7E7C7"

## ===================== S1: match Jin layout, quartile =====================
draw_s1_one <- function(path, db, n0, n_ex, n_an, qn, panel) {
  cairo_pdf(path, width = 8.2, height = 7.0)
  grid.newpage()
  ## title like literature
  grid.text("Figure S1. The study flowchart",
            x = 0.5, y = 0.975, gp = gpar(fontsize = 13, fontface = "bold"))
  grid.text(sprintf("(%s. %s)", panel, db),
            x = 0.5, y = 0.945, gp = gpar(fontsize = 10, col = "grey25"))

  rr <- function(x, y, w, h, lab, fs = 8.5) {
    grid.roundrect(
      x = unit(x, "npc"), y = unit(y, "npc"),
      width = unit(w, "npc"), height = unit(h, "npc"),
      r = unit(1, "pt"),
      gp = gpar(fill = fill, col = "black", lwd = 1.1)
    )
    grid.text(lab, x = unit(x, "npc"), y = unit(y, "npc"),
              gp = gpar(fontsize = fs, lineheight = 1.05), just = "center")
  }
  vline <- function(x, y0, y1, arrow = TRUE) {
    grid.lines(
      x = unit(c(x, x), "npc"), y = unit(c(y0, y1), "npc"),
      gp = gpar(lwd = 1.15),
      arrow = if (arrow) arrow(length = unit(5, "pt"), type = "closed") else NULL
    )
  }
  hline <- function(x0, x1, y, arrow = TRUE) {
    grid.lines(
      x = unit(c(x0, x1), "npc"), y = unit(c(y, y), "npc"),
      gp = gpar(lwd = 1.15),
      arrow = if (arrow) arrow(length = unit(5, "pt"), type = "closed") else NULL
    )
  }

  ## Top extract — centered like lit
  rr(0.42, 0.84, 0.62, 0.12, sprintf(
    "Adult patients with sepsis, aged >= 18 years, with ICU\nadmission were extracted from the %s database (N=%s)",
    db, format(n0, big.mark = ",")
  ), fs = 8)

  ## vertical trunk
  vline(0.42, 0.78, 0.70, arrow = FALSE)
  ## side exclude
  hline(0.42, 0.72, 0.74)
  rr(0.86, 0.74, 0.26, 0.13, sprintf(
    "Excluding patients with\nmissing WPR components\n(WBC or platelet) (N=%s)",
    format(n_ex, big.mark = ",")
  ), fs = 7.5)
  vline(0.42, 0.70, 0.62)

  ## analysis cohort
  rr(0.42, 0.57, 0.36, 0.08, sprintf("Analysis cohort (N=%s)", format(n_an, big.mark = ",")), fs = 9)

  ## split to two branches
  vline(0.42, 0.53, 0.49, arrow = FALSE)
  hline(0.22, 0.68, 0.49, arrow = FALSE)
  vline(0.22, 0.49, 0.45)
  vline(0.68, 0.49, 0.45)

  rr(0.22, 0.41, 0.30, 0.07, "Patients categorized by WPR", fs = 8)
  rr(0.68, 0.41, 0.36, 0.07, "Stratification by WPR and SOFA", fs = 8)

  ## quartiles 4 boxes
  xs <- c(0.07, 0.17, 0.27, 0.37)
  for (i in seq_along(xs)) {
    vline(xs[i], 0.375, 0.33)
    qlab <- paste0("Q", i)
    rr(xs[i], 0.26, 0.095, 0.12,
       sprintf("Quartile %d\n(N=%s)", i, format(qn[[qlab]], big.mark = ",")), fs = 7)
  }
  ## connector from center branch to 4
  hline(0.07, 0.37, 0.375, arrow = FALSE)
  vline(0.22, 0.375, 0.375, arrow = FALSE)

  ## right 2x2 in outer box
  vline(0.68, 0.375, 0.34)
  grid.rect(
    x = unit(0.68, "npc"), y = unit(0.20, "npc"),
    width = unit(0.42, "npc"), height = unit(0.26, "npc"),
    gp = gpar(fill = NA, col = "black", lwd = 1.2)
  )
  ## literature group order
  rr(0.55, 0.26, 0.18, 0.09, "Group 1:\nLow WPR + Low SOFA", 6.5)
  rr(0.81, 0.26, 0.18, 0.09, "Group 2:\nLow WPR + High SOFA", 6.5)
  rr(0.55, 0.14, 0.18, 0.09, "Group 3:\nHigh WPR + Low SOFA", 6.5)
  rr(0.81, 0.14, 0.18, 0.09, "Group 4:\nHigh WPR + High SOFA", 6.5)

  grid.text(
    "SOFA cutoff = 5; Low/High WPR from tertile extremes (T1/T3) for Groups 1-4",
    x = 0.5, y = 0.025, gp = gpar(fontsize = 7, col = "grey35")
  )
  dev.off()
}

specs <- list(
  MIMIC = list(n0=8245L, n_an=8218L, q=c(Q1=2055L,Q2=2054L,Q3=2053L,Q4=2056L), lab="A"),
  eICU  = list(n0=13946L, n_an=13635L, q=c(Q1=3393L,Q2=3413L,Q3=3415L,Q4=3414L), lab="B")
)
s1p <- c()
for (db in names(specs)) {
  sp <- specs[[db]]
  p <- file.path(tmpdir, paste0("s1_", db, ".pdf"))
  draw_s1_one(p, db, sp$n0, sp$n0-sp$n_an, sp$n_an, sp$q, sp$lab)
  s1p <- c(s1p, p)
}

## stack S1
library(purrr) # may not exist - use python after
cat("S1 parts ok\n")

## ===================== S2 with risk tables =====================
.q_lab <- c(
  Q1 = "Low WPR + Low SOFA",
  Q2 = "High WPR + Low SOFA",
  Q3 = "Low WPR + High SOFA",
  Q4 = "High WPR + High SOFA"
)
prep_ev <- function(x) {
  if (is.numeric(x) || is.integer(x)) as.integer(x) else
    as.integer(tolower(as.character(x)) %in% c("1","yes","dead","expired","non-survivor","nonsurvivor"))
}
hz <- list(
  list(title="A. In-hospital mortality", time="futime", event="fustatus", xmax=NA_real_),
  list(title="B. 30-day mortality", time="futime_30d", event="event_30d", xmax=30),
  list(title="C. 365-day mortality", time="futime_365d", event="event_365d", xmax=365)
)

make_db_km <- function(db, path) {
  dat <- readRDS(file.path(ck, db, "derived_grouping.rds"))$ctx$data$imputed
  plots <- lapply(hz, function(h) {
    d <- dat[!is.na(dat$Index_SOFA_Q), ]
    d$strata <- factor(as.character(d$Index_SOFA_Q), levels=names(.q_lab), labels=unname(.q_lab))
    tt <- as.numeric(d[[h$time]]); ev <- prep_ev(d[[h$event]])
    ok <- is.finite(tt) & tt > 0 & !is.na(ev) & !is.na(d$strata)
    d <- d[ok,]; tt <- tt[ok]; ev <- ev[ok]
    xmax <- if (is.finite(h$xmax)) h$xmax else min(max(tt, na.rm=TRUE), 300)
    br <- if (xmax <= 30) 5 else if (xmax <= 120) 20 else 50
    sf <- survfit(Surv(tt, ev) ~ strata, data=data.frame(tt=tt,ev=ev,strata=d$strata))
    ggsurvplot(
      sf, data=data.frame(tt=tt,ev=ev,strata=d$strata),
      conf.int=FALSE, risk.table=TRUE, risk.table.col="strata",
      risk.table.height=0.32, xlim=c(0,xmax), break.time.by=br,
      xlab="Follow-up day", ylab="Survival Probability",
      title=h$title, legend.title="",
      palette=c("#2E86C1","#E67E22","#27AE60","#C0392B"),
      ggtheme=theme_classic(base_size=8),
      font.main=c(9,"bold"), risk.table.fontsize=2.5,
      legend="none", pval=TRUE, pval.size=3.2, pval.coord=c(0,0.08)
    )
  })
  ## one page tall enough for risk tables
  pdf(path, width=13.2, height=6.8)
  print(arrange_ggsurvplots(plots, print=FALSE, ncol=3, nrow=1, risk.table.height=0.32))
  grid.text(sprintf("Figure S2. %s — Kaplan-Meier by WPR and SOFA strata", db),
            x=0.5, y=0.995, gp=gpar(fontsize=11, fontface="bold"), just="top")
  dev.off()
  invisible(path)
}

s2_m <- make_db_km("MIMIC", file.path(tmpdir, "s2_MIMIC.pdf"))
s2_e <- make_db_km("eICU", file.path(tmpdir, "s2_eICU.pdf"))
cat("S2 parts:", file.info(s2_m)$size, file.info(s2_e)$size, "\n")
writeLines(c(s1p, s2_m, s2_e), file.path(tmpdir, "parts.txt"))
cat("tmpdir", tmpdir, "\n")
