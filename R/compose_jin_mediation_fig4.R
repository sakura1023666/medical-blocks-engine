#!/usr/bin/env Rscript
###############################################################################
# Jin Fig4：A 路径图（a1/b1/c1）+ B/C/D 三时点 bootstrap 间接/直接效应分布
# 用法（示例）：
#   Rscript R/compose_jin_mediation_fig4.R \
#     --ck .../checkpoints/by_index/WPR/MIMIC/mediation_prognosis.rds \
#     --exposure WPR --mediator RDW --out Figure4.pdf --B 1000
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && is.na(a))) b else a

.args <- commandArgs(trailingOnly = TRUE)
.opt <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}
.has <- function(flag) flag %in% .args

ck_path   <- .opt("--ck")
exposure  <- .opt("--exposure", "WPR")
mediator  <- .opt("--mediator", "RDW")
out_pdf   <- .opt("--out", "Figure 4. Mediation path and bootstrap.pdf")
B         <- as.integer(.opt("--B", "1000"))
seed      <- as.integer(.opt("--seed", "42"))
covars_s  <- .opt("--covariates", "Age,Temperature")
db_label  <- .opt("--db-label", "MIMIC")
title_txt <- .opt("--title", "Figure 4. Mediation analysis of WPR via RDW")

if (is.null(ck_path) || !file.exists(ck_path)) {
  stop("--ck mediation_prognosis.rds required", call. = FALSE)
}
if (!is.finite(B) || B < 50L) B <- 1000L

suppressPackageStartupMessages({
  library(survival)
  library(ggplot2)
  library(grid)
  library(gridExtra)
})

covars <- trimws(unlist(strsplit(as.character(covars_s), ",", fixed = TRUE)))
covars <- covars[nzchar(covars)]

obj <- readRDS(ck_path)
ctx <- obj$ctx %||% obj
data <- ctx$data$imputed %||% ctx$data$cleaned
if (is.null(data) || !is.data.frame(data)) stop("checkpoint 无 imputed/cleaned 数据", call. = FALSE)

hz <- list(
  hosp = list(
    time = "futime", event = "fustatus",
    label = "In-hospital", panel = "B"
  ),
  d30 = list(
    time = if ("time_d30" %in% names(data)) "time_d30" else "futime_30d",
    event = if ("event_d30" %in% names(data)) "event_d30" else "event_30d",
    label = "30-day", panel = "C"
  ),
  d365 = list(
    time = if ("time_d365" %in% names(data)) "time_d365" else "futime_365d",
    event = if ("event_d365" %in% names(data)) "event_d365" else "event_365d",
    label = "365-day", panel = "D"
  )
)

.event01 <- function(x) {
  if (is.numeric(x)) return(as.integer(x > 0))
  xc <- as.character(x)
  as.integer(tolower(xc) %in% c(
    "1", "yes", "dead", "death", "expired", "non-survivor", "nonsurvivor"
  ) | grepl("non.?survivor|dead|death|expired", xc, ignore.case = TRUE))
}

.fit_one <- function(df, time_var, event_var, exposure, mediator, covars, use_z = TRUE) {
  need <- unique(c(time_var, event_var, exposure, mediator, covars))
  need <- need[need %in% names(df)]
  d <- df[, need, drop = FALSE]
  d[[event_var]] <- .event01(d[[event_var]])
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 50L) return(NULL)
  if (use_z) d$.M_z <- as.numeric(scale(d[[mediator]]))
  med_in <- if (use_z) ".M_z" else mediator
  adj <- intersect(covars, names(d))
  f_a <- if (length(adj)) {
    stats::as.formula(paste(med_in, "~", exposure, "+", paste(adj, collapse = "+")))
  } else {
    stats::as.formula(paste(med_in, "~", exposure))
  }
  f_full <- if (length(adj)) {
    stats::as.formula(paste0(
      "Surv(", time_var, ",", event_var, ")~", exposure, "+", med_in, "+",
      paste(adj, collapse = "+")
    ))
  } else {
    stats::as.formula(paste0(
      "Surv(", time_var, ",", event_var, ")~", exposure, "+", med_in
    ))
  }
  ma <- tryCatch(stats::lm(f_a, data = d), error = function(e) NULL)
  mf <- tryCatch(survival::coxph(f_full, data = d), error = function(e) NULL)
  if (is.null(ma) || is.null(mf)) return(NULL)
  ca <- unname(stats::coef(ma)[exposure])
  cb <- unname(stats::coef(mf)[med_in])
  cp <- unname(stats::coef(mf)[exposure])
  if (!is.finite(ca) || !is.finite(cb) || !is.finite(cp)) return(NULL)
  list(data = d, f_a = f_a, f_full = f_full, med_in = med_in,
       a = ca, b = cb, c_prime = cp, indirect = ca * cb, n = nrow(d))
}

.boot_draws <- function(fit0, B, seed, mediator_name) {
  set.seed(seed)
  d0 <- fit0$data
  n <- nrow(d0)
  ind <- numeric(B)
  dir <- numeric(B)
  for (i in seq_len(B)) {
    idx <- sample.int(n, replace = TRUE)
    db <- d0[idx, , drop = FALSE]
    if (identical(fit0$med_in, ".M_z") && mediator_name %in% names(db)) {
      db$.M_z <- as.numeric(scale(db[[mediator_name]]))
    }
    ca <- tryCatch(
      unname(stats::coef(stats::lm(fit0$f_a, data = db))[exposure]),
      error = function(e) NA_real_
    )
    mf <- tryCatch(survival::coxph(fit0$f_full, data = db), error = function(e) NULL)
    cb <- if (!is.null(mf)) {
      tryCatch(unname(stats::coef(mf)[fit0$med_in]), error = function(e) NA_real_)
    } else {
      NA_real_
    }
    cp <- if (!is.null(mf)) {
      tryCatch(unname(stats::coef(mf)[exposure]), error = function(e) NA_real_)
    } else {
      NA_real_
    }
    ind[i] <- if (is.finite(ca) && is.finite(cb)) ca * cb else NA_real_
    dir[i] <- if (is.finite(cp)) cp else NA_real_
  }
  list(indirect = ind[is.finite(ind)], direct = dir[is.finite(dir)])
}

.message <- function(...) cat(sprintf(...), "\n")

.hist_panel <- function(draws, est, title, fill, ylab = "Density") {
  lo <- as.numeric(stats::quantile(draws, 0.025, names = FALSE))
  hi <- as.numeric(stats::quantile(draws, 0.975, names = FALSE))
  df <- data.frame(x = draws)
  ann <- sprintf(
    "Estimate = %.3f\n95%% CI: (%.3f, %.3f)",
    est, lo, hi
  )
  ggplot2::ggplot(df, ggplot2::aes(x = .data$x)) +
    ggplot2::geom_histogram(
      ggplot2::aes(y = ggplot2::after_stat(density)),
      bins = 40, fill = fill, color = "white", linewidth = 0.15, alpha = 0.9
    ) +
    ggplot2::geom_density(color = grDevices::adjustcolor(fill, red.f = 0.5, green.f = 0.5, blue.f = 0.5), linewidth = 0.7) +
    ggplot2::geom_vline(xintercept = est, color = "#C41E3A", linewidth = 0.9) +
    ggplot2::geom_vline(xintercept = c(lo, hi), color = "#C41E3A", linetype = "dashed", linewidth = 0.7) +
    ggplot2::annotate(
      "text", x = est, y = Inf, label = ann, vjust = 1.3, hjust = 0.5,
      size = 2.6, fontface = "bold", color = "#222222"
    ) +
    ggplot2::labs(title = title, x = NULL, y = ylab) +
    ggplot2::theme_bw(base_size = 9) +
    ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 9, hjust = 0.5),
      panel.grid.minor = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(4, 6, 2, 6)
    )
}

.path_diagram_grob <- function(exposure, mediator, outcome_lab = "Mortality risk",
                                db_lab = "MIMIC") {
  grobTree <- grid::grobTree
  rectGrob <- grid::rectGrob
  textGrob <- grid::textGrob
  linesGrob <- grid::linesGrob
  gList <- grid::gList
  unit <- grid::unit
  gpar <- grid::gpar
  arrow <- grid::arrow

  ex <- 0.18; ey <- 0.32
  mx <- 0.50; my <- 0.78
  ox <- 0.82; oy <- 0.32
  bw <- 0.16; bh <- 0.14

  .box <- function(x, y, w, h, fill, col) {
    if (exists("roundrectGrob", envir = asNamespace("grid"), mode = "function")) {
      grid::roundrectGrob(
        x = x, y = y, width = w, height = h,
        r = unit(0.08, "snpc"),
        gp = gpar(fill = fill, col = col, lwd = 1.5)
      )
    } else {
      rectGrob(x, y, w, h, gp = gpar(fill = fill, col = col, lwd = 1.5))
    }
  }
  boxes <- gList(
    .box(ex, ey, bw, bh, "#F4A261", "#E07A3D"),
    textGrob(exposure, ex, ey, gp = gpar(fontsize = 12, fontface = "bold", col = "white")),
    .box(mx, my, bw, bh, "#4C78A8", "#2F5A86"),
    textGrob(mediator, mx, my, gp = gpar(fontsize = 12, fontface = "bold", col = "white")),
    .box(ox, oy, bw * 1.15, bh, "#E07A7A", "#C45C5C"),
    textGrob(outcome_lab, ox, oy, gp = gpar(fontsize = 11, fontface = "bold", col = "white"))
  )
  arr <- arrow(type = "closed", length = unit(0.12, "inches"), angle = 18)
  gp_arr <- gpar(col = "#2E8B57", fill = "#2E8B57", lwd = 2)
  arrows <- gList(
    linesGrob(
      x = unit(c(ex + bw / 2 * 0.55, mx - bw / 2 * 0.55), "npc"),
      y = unit(c(ey + bh / 2 * 0.7, my - bh / 2 * 0.7), "npc"),
      arrow = arr, gp = gp_arr
    ),
    textGrob("a1", x = 0.30, y = 0.58, gp = gpar(fontsize = 11, fontface = "bold", col = "#2E8B57")),
    linesGrob(
      x = unit(c(mx + bw / 2 * 0.55, ox - bw / 2 * 0.55), "npc"),
      y = unit(c(my - bh / 2 * 0.7, oy + bh / 2 * 0.7), "npc"),
      arrow = arr, gp = gp_arr
    ),
    textGrob("b1", x = 0.70, y = 0.58, gp = gpar(fontsize = 11, fontface = "bold", col = "#2E8B57")),
    linesGrob(
      x = unit(c(ex + bw / 2, ox - bw / 2), "npc"),
      y = unit(c(ey, oy), "npc"),
      arrow = arr, gp = gp_arr
    ),
    textGrob("c1", x = 0.50, y = 0.22, gp = gpar(fontsize = 11, fontface = "bold", col = "#2E8B57"))
  )
  title <- textGrob(
    paste0("A. Mediation path (", db_lab, ")"),
    x = 0.02, y = 0.96, just = c("left", "top"),
    gp = gpar(fontsize = 12, fontface = "bold")
  )
  grobTree(boxes, arrows, title)
}

boot_plots <- list()
est_tab <- list()
for (hid in names(hz)) {
  sp <- hz[[hid]]
  if (!all(c(sp$time, sp$event) %in% names(data))) {
    .message("SKIP %s: missing %s/%s", hid, sp$time, sp$event)
    next
  }
  .message("Fitting %s (%s / %s) ...", hid, sp$time, sp$event)
  fit0 <- .fit_one(data, sp$time, sp$event, exposure, mediator, covars)
  if (is.null(fit0)) {
    .message("SKIP %s: fit failed", hid)
    next
  }
  .message("  n=%d  a=%.4f b=%.4f c'=%.4f  indirect=%.4f  boot B=%d",
           fit0$n, fit0$a, fit0$b, fit0$c_prime, fit0$indirect, B)
  dr <- .boot_draws(fit0, B, seed + match(hid, names(hz)), mediator)
  p_ind <- .hist_panel(
    dr$indirect, fit0$indirect,
    "Bootstrap Distribution: Indirect Effect (a × b)",
    fill = "#6FBF73"
  )
  p_dir <- .hist_panel(
    dr$direct, fit0$c_prime,
    "Bootstrap Distribution: Direct Effect (c')",
    fill = "#F0A060"
  )
  header <- ggplot2::ggplot() +
    ggplot2::annotate(
      "text", x = 0.5, y = 0.75,
      label = sprintf(
        "%s. Bootstrap Distributions of Mediation Effects\nBased on %d bootstrap replications · %s mortality",
        sp$panel, B, sp$label
      ),
      hjust = 0.5, vjust = 0.5, size = 3.1, fontface = "bold"
    ) +
    ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.margin = ggplot2::margin(2, 2, 0, 2))
  footer <- ggplot2::ggplot() +
    ggplot2::annotate(
      "text", x = 0.5, y = 0.5,
      label = "Solid red line: point estimate    Dashed red lines: 95% confidence interval",
      hjust = 0.5, size = 2.4, color = "#444444"
    ) +
    ggplot2::xlim(0, 1) + ggplot2::ylim(0, 1) +
    ggplot2::theme_void()
  boot_plots[[hid]] <- gridExtra::arrangeGrob(
    header, p_ind, p_dir, footer,
    heights = c(0.12, 0.40, 0.40, 0.08), ncol = 1
  )
  est_tab[[hid]] <- data.frame(
    horizon = hid, label = sp$label, n = fit0$n,
    a = fit0$a, b = fit0$b, c_prime = fit0$c_prime,
    indirect = fit0$indirect,
    ind_lo = stats::quantile(dr$indirect, 0.025, names = FALSE),
    ind_hi = stats::quantile(dr$indirect, 0.975, names = FALSE),
    dir_lo = stats::quantile(dr$direct, 0.025, names = FALSE),
    dir_hi = stats::quantile(dr$direct, 0.975, names = FALSE),
    stringsAsFactors = FALSE
  )
}

if (!length(boot_plots)) stop("无可用时点 bootstrap 结果", call. = FALSE)

path_g <- .path_diagram_grob(exposure, mediator, "Mortality risk", db_lab = db_label)
# arrange: A on top spanning; B C D in a row
bottom <- do.call(gridExtra::arrangeGrob, c(boot_plots, list(ncol = length(boot_plots))))
full <- gridExtra::arrangeGrob(
  path_g, bottom,
  heights = c(0.32, 0.68), ncol = 1,
  top = grid::textGrob(
    title_txt, gp = grid::gpar(fontsize = 13, fontface = "bold"),
    just = "left", x = 0.02
  )
)

dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
grDevices::pdf(out_pdf, width = 14, height = 10, useDingbats = FALSE)
grid::grid.draw(full)
grDevices::dev.off()
.message("wrote %s", out_pdf)

csv_out <- sub("\\.pdf$", "_bootstrap_summary.csv", out_pdf, ignore.case = TRUE)
utils::write.csv(do.call(rbind, est_tab), csv_out, row.names = FALSE)
.message("wrote %s", csv_out)
