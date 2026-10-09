###############################################################################
# tidy recolor Fig4 + dedupe figures
###############################################################################
`%||%` <- function(a, b) if (is.null(a)) b else a
.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final")
.study <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  file.path(.engine, ".superpowers/sdd/study_mirror")
)
.fig <- file.path(.study, "summary_result", "figure")
.tab <- file.path(.study, "summary_result", "table")
.arch <- file.path(.study, "summary_result", "_archive_ward_exploratory")
dir.create(.arch, recursive = TRUE, showWarnings = FALSE)

source(file.path(.engine, "R/clpn_node_label_db.R"), local = FALSE)
source(file.path(.engine, "R/clpn_network_plot.R"), local = FALSE)

x <- readRDS(file.path(.tab, "CLPN_bootstrap_Outpatient.rds"))
stems <- x$stems
adj <- x$adj
grp <- clpn_node_group(stems, root = .engine)
message("Group counts:")
print(table(grp))

out4 <- file.path(.fig, "Figure 4-Outpatient. CLPN network of HAMD HAMA CSSRS items.pdf")
clpn_plot_publication(
  adj = adj, stems = stems, outfile = out4, title = "Outpatient",
  root = .engine, layout = "spring", drop_self_loops = TRUE, fade_weak_edges = TRUE
)
message("Rewrote Fig4")

op <- local({
  e <- new.env(parent = emptyenv())
  load(file.path(.study, "data/harmonized/D04_outpatient_clpm_imputed.RData"), envir = e)
  e$dabiao
})
f2 <- file.path(.fig, "Figure 2-Outpatient. RCS plot between mood scores and CSSRS ideation.pdf")
grDevices::pdf(f2, width = 10, height = 5)
par(mfrow = c(1, 2), mar = c(4.5, 4.2, 3, 1))
for (xv in c("HAMD_Index", "HAMA_Index")) {
  y <- as.integer(op$CSSRS_1st)
  xnum <- as.numeric(op[[xv]])
  ok <- is.finite(xnum) & !is.na(y)
  d2 <- data.frame(x = xnum[ok], y = y[ok])
  m2 <- stats::glm(y ~ splines::ns(x, df = 4), data = d2, family = binomial())
  xg <- seq(min(d2$x), max(d2$x), length.out = 200)
  pr <- predict(m2, newdata = data.frame(x = xg), type = "link", se.fit = TRUE)
  fit <- plogis(pr$fit)
  lo <- plogis(pr$fit - 1.96 * pr$se.fit)
  hi <- plogis(pr$fit + 1.96 * pr$se.fit)
  plot(xg, fit, type = "l", lwd = 2, col = "#2C7BB6",
       xlab = xv, ylab = "P(CSSRS item1=1)", ylim = c(0, 1), main = xv)
  polygon(c(xg, rev(xg)), c(lo, rev(hi)), col = adjustcolor("#2C7BB6", 0.2), border = NA)
  lines(xg, fit, lwd = 2, col = "#2C7BB6")
}
grDevices::dev.off()
invisible(file.remove(file.path(
  .fig,
  c(
    "Figure 2-Outpatient. RCS plot between HAMD and CSSRS ideation.pdf",
    "Figure 2-Outpatient. RCS plot between HAMA and CSSRS ideation.pdf"
  )
)))
message("Merged Figure 2")

ward_files <- list.files(.fig, pattern = "-Ward\\.", full.names = TRUE)
for (f in ward_files) {
  dest <- file.path(.arch, basename(f))
  if (file.exists(dest)) file.remove(dest)
  file.rename(f, dest)
}
message("Archived Ward figs: ", length(ward_files))

writeLines(c(
  "figure/ = Outpatient main set only (flat).",
  "Fig4 colors: Outcome/CSSRS pink #F6B7C6; Depression/HAMD blue #A8C5E2; Mood/HAMA green #82B181.",
  "Ward exploratory -> summary_result/_archive_ward_exploratory/",
  "Figure 2 = one 2-panel RCS."
), file.path(.fig, "README_FigS1_S2_CLPN_bootstrap.txt"))

message("Remaining:")
print(sort(list.files(.fig)))
