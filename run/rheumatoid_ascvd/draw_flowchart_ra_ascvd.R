#!/usr/bin/env Rscript
# DEPRECATED (2026-08): Prefer config$attrition + block attrition_flowchart
# (pipeline末尾). Kept only as a legacy redraw from an existing CSV.
# See Blocks/00_attrition/01block_attrition_flowchart.R and R/attrition_log.R.
#
# Draw Figure 1 inclusion/exclusion flowchart for RA+GC → ASCVD MIMIC study
study <- "/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157"
csv <- file.path(study, "Tables", "Flowchart_attrition_MIMIC.csv")
pdf_path <- file.path(study, "Figures", "Figure 1. Inclusion exclusion flowchart.pdf")
dir.create(dirname(pdf_path), recursive = TRUE, showWarnings = FALSE)

rows <- utils::read.csv(csv, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
stopifnot(all(c("step", "n") %in% names(rows)))

# Append case/control breakdown on last box label
last <- nrow(rows)
if ("n_ASCVD" %in% names(rows) && is.finite(rows$n_ASCVD[last])) {
  rows$step[last] <- sprintf(
    "%s\n(ASCVD %s / Non-ASCVD %s)",
    rows$step[last],
    format(as.integer(rows$n_ASCVD[last]), big.mark = ","),
    format(as.integer(rows$n_Non_ASCVD[last]), big.mark = ",")
  )
}

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
surv <- file.path(root, "R/survival_dual_batch_runner.R")
utils_r <- file.path(root, "R/utils.R")
if (file.exists(utils_r)) source(utils_r, local = FALSE)
if (file.exists(surv)) {
  # source only the draw function environment safely
  source(surv, local = FALSE)
}

title <- "Figure 1. Inclusion/exclusion flowchart (MIMIC: RA + glucocorticoid -> ASCVD)"
if (exists("survival_batch_draw_flowchart_pdf", mode = "function")) {
  ok <- survival_batch_draw_flowchart_pdf(
    rows[, c("step", "n"), drop = FALSE],
    title = title,
    pdf_path = pdf_path,
    font_family = "Times New Roman"
  )
} else {
  # Fallback minimal drawer
  grDevices::pdf(pdf_path, width = 8.5, height = 7, family = "Times")
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(0.4, 0.4, 2.2, 0.4))
  graphics::plot.new()
  graphics::plot.window(xlim = c(0, 1), ylim = c(0, 1))
  graphics::title(main = title, cex.main = 1.0)
  n_box <- nrow(rows)
  y_top <- 0.94
  box_h <- min(0.11, 0.82 / (n_box * 1.35))
  gap <- box_h * 0.32
  for (i in seq_len(n_box)) {
    y1 <- y_top - (i - 1) * (box_h + gap)
    y0 <- y1 - box_h
    graphics::rect(0.16, y0, 0.84, y1, border = "black", col = "#F7F7F7", lwd = 1.4)
    graphics::text(0.5, (y0 + y1) / 2,
                   sprintf("%s\nN = %s", rows$step[i], format(as.integer(rows$n[i]), big.mark = ",")),
                   cex = 0.8)
    if (i < n_box) {
      graphics::arrows(0.5, y0 - 0.004, 0.5, y0 - gap + 0.008, length = 0.07, lwd = 1.1)
      drop_n <- as.integer(rows$n[i]) - as.integer(rows$n[i + 1L])
      if (is.finite(drop_n) && drop_n > 0L) {
        graphics::text(0.87, y0 - gap / 2, sprintf("-%s", format(drop_n, big.mark = ",")),
                       cex = 0.72, col = "#555555", adj = 0)
      }
    }
  }
  ok <- TRUE
}

message("Flowchart PDF: ", pdf_path, " ok=", isTRUE(ok))
