#!/usr/bin/env Rscript
# Run paper-logic mediation (spotlight class | All) for all scale-total mediators
# among the 7 network scores. Exposure=PHQ-15, outcome=WHO-DAS
# → mediators = SSS-8, SSD-12, Whiteley-8, PHQ-9, GAD-7 (PHQ-15/WHO-DAS are X/Y)
#
# Outputs:
#   - Table: mediation ACME by LCA class × mediator
#   - Figure 4: SSD-12 (primary SSD construct) spotlight|All
#   - Figure S4a–S4e: each mediator spotlight|All path diagram
#   - Combined multi-page PDF in delivery workspace

`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

proj <- file.path(
  Sys.getenv("BLOCK_RESULT_ROOT", "/mnt/g/02block_result"),
  "63_SSD", "LPA_Network_Mediaton_42214160", "by_index", "main_full_sample"
)
args <- commandArgs(trailingOnly = TRUE)
i <- match("--project", args)
if (!is.na(i) && i < length(args)) {
  proj <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = TRUE)
}
iB <- match("--boots", args)
n_boot <- if (!is.na(iB) && iB < length(args)) as.integer(args[[iB + 1L]]) else 2000L

ck <- readRDS(file.path(proj, "checkpoints/step07_parallel_competing_mediation.rds"))
d0 <- ck$ctx$data$cleaned
cfg <- ck$ctx$config$parallel_competing_mediation
x <- cfg$exposure %||% "PHQ15"
y <- cfg$outcome %||% "WHODAS"
covs <- cfg$covariates %||% c("age", "sex", "education", "marriage", "income", "livingsite")
cls_col <- if ("LCA_class" %in% names(d0)) "LCA_class" else "LPA_class"

nodes7 <- c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7")
ms <- setdiff(nodes7, c(x, y))
ms <- ms[ms %in% names(d0)]
stopifnot(length(ms) >= 1L, cls_col %in% names(d0))

lab_var <- c(
  PHQ15 = "PHQ-15", SSS8 = "SSS-8", SSD12 = "SSD-12", Whiteley8 = "Whiteley-8",
  WHODAS = "WHO-DAS", PHQ9 = "PHQ-9", GAD7 = "GAD-7"
)
.lab <- function(v) {
  z <- unname(lab_var[v]); if (is.na(z) || !nzchar(z)) v else z
}
.star <- function(p) {
  if (!is.finite(p)) "" else if (p < 0.001) "***" else if (p < 0.01) "**" else if (p < 0.05) "*" else ""
}
.fmt <- function(est, p) sprintf("%.3f%s", est, .star(p))

need <- unique(c(x, y, ms, covs, cls_col))
need <- need[need %in% names(d0)]
d <- d0[, need, drop = FALSE]
for (v in setdiff(need, cls_col)) {
  if (is.factor(d[[v]]) || is.character(d[[v]])) {
    fv <- factor(d[[v]])
    tabn <- table(fv)
    rare <- names(tabn)[tabn < 15L]
    if (length(rare)) {
      fv <- as.character(fv)
      fv[fv %in% rare] <- "Other"
      fv <- factor(fv)
    }
    d[[v]] <- droplevels(fv)
  } else {
    d[[v]] <- suppressWarnings(as.numeric(d[[v]]))
  }
}
d <- d[stats::complete.cases(d[, setdiff(need, cls_col), drop = FALSE]), , drop = FALSE]
cov_use <- intersect(covs, names(d))
cov_txt <- if (length(cov_use)) paste0(" + ", paste(cov_use, collapse = " + ")) else ""
message("n=", nrow(d), " mediators=", paste(ms, collapse = ","), " boots=", n_boot)

.boot_one <- function(dd, m, seed) {
  set.seed(seed)
  n <- nrow(dd)
  acme <- numeric(n_boot)
  for (b in seq_len(n_boot)) {
    db <- dd[sample.int(n, n, replace = TRUE), , drop = FALSE]
    for (v in cov_use) {
      if (is.factor(dd[[v]])) db[[v]] <- factor(db[[v]], levels = levels(dd[[v]]))
    }
    keep <- c(x, y, m, cov_use)
    db <- db[stats::complete.cases(db[, keep, drop = FALSE]), , drop = FALSE]
    if (nrow(db) < 30L) { acme[b] <- NA_real_; next }
    mm <- tryCatch(stats::lm(stats::as.formula(paste0(m, " ~ ", x, cov_txt)), db), error = function(e) NULL)
    my <- tryCatch(stats::lm(stats::as.formula(paste0(y, " ~ ", x, " + ", m, cov_txt)), db), error = function(e) NULL)
    if (is.null(mm) || is.null(my)) { acme[b] <- NA_real_; next }
    acme[b] <- unname(stats::coef(mm)[x]) * unname(stats::coef(my)[m])
  }
  ok <- is.finite(acme)
  lo <- as.numeric(stats::quantile(acme[ok], 0.025))
  hi <- as.numeric(stats::quantile(acme[ok], 0.975))
  list(ACME = mean(acme[ok]), lo = lo, hi = hi, sig = (lo * hi) > 0, n_boot = sum(ok))
}

.path_fit <- function(dd, m) {
  mm <- stats::lm(stats::as.formula(paste0(m, " ~ ", x, cov_txt)), data = dd)
  my <- stats::lm(stats::as.formula(paste0(y, " ~ ", x, " + ", m, cov_txt)), data = dd)
  sa <- summary(mm)$coefficients
  sy <- summary(my)$coefficients
  list(
    n = nrow(dd),
    a = unname(sa[x, "Estimate"]), pa = unname(sa[x, "Pr(>|t|)"]),
    b = unname(sy[m, "Estimate"]), pb = unname(sy[m, "Pr(>|t|)"]),
    cprime = unname(sy[x, "Estimate"]), pc = unname(sy[x, "Pr(>|t|)"]),
    a_lab = .fmt(unname(sa[x, "Estimate"]), unname(sa[x, "Pr(>|t|)"])),
    b_lab = .fmt(unname(sy[m, "Estimate"]), unname(sy[m, "Pr(>|t|)"])),
    c_lab = .fmt(unname(sy[x, "Estimate"]), unname(sy[x, "Pr(>|t|)"]))
  )
}

ks <- sort(unique(stats::na.omit(d[[cls_col]])))
groups <- c("All", paste0("C", ks))
tab <- list()
seed0 <- 20261123L
for (gi in seq_along(groups)) {
  g <- groups[[gi]]
  dd <- if (identical(g, "All")) d else {
    k <- as.integer(sub("^C", "", g))
    d[!is.na(d[[cls_col]]) & d[[cls_col]] == k, , drop = FALSE]
  }
  for (mi in seq_along(ms)) {
    m <- ms[[mi]]
    br <- .boot_one(dd, m, seed0 + gi * 31L + mi * 7L)
    pf <- .path_fit(dd, m)
    tab[[length(tab) + 1L]] <- data.frame(
      group = g, mediator = m, mediator_lab = .lab(m), n = pf$n,
      ACME = br$ACME, ACME_lo = br$lo, ACME_hi = br$hi, ACME_sig = br$sig,
      a = pf$a, p_a = pf$pa, b = pf$b, p_b = pf$pb,
      cprime = pf$cprime, p_cprime = pf$pc,
      a_lab = pf$a_lab, b_lab = pf$b_lab, c_lab = pf$c_lab,
      stringsAsFactors = FALSE
    )
    message(sprintf("%s | %s n=%d ACME=%.4f [%s] sig=%s",
                    g, m, pf$n, br$ACME,
                    sprintf("%.4f,%.4f", br$lo, br$hi), br$sig))
  }
}
tab <- do.call(rbind, tab)

.pick_class <- function(mediator) {
  sub <- tab[tab$mediator == mediator & tab$group != "All", , drop = FALSE]
  sig <- sub[sub$ACME_sig %in% TRUE, , drop = FALSE]
  pool <- if (nrow(sig)) sig else sub
  pool[which.max(abs(pool$ACME)), , drop = FALSE]
}

picks <- do.call(rbind, lapply(ms, .pick_class))
message("Spotlight picks:")
print(picks[, c("mediator", "group", "ACME", "ACME_lo", "ACME_hi", "ACME_sig")])

ff <- tryCatch({
  tmp <- tempfile(fileext = ".pdf")
  grDevices::cairo_pdf(tmp, width = 1, height = 1, family = "Times New Roman")
  grDevices::dev.off(); unlink(tmp); "Times New Roman"
}, error = function(e) "Liberation Serif")

.draw_panel <- function(fit, header_top, header_mid, y0) {
  rect(0.04, y0 + 0.72, 0.30, y0 + 0.88, col = "#4C78A8", border = NA)
  text(0.17, y0 + 0.80, header_top, col = "white", cex = 1.1, font = 2, family = ff)
  rect(0.04, y0 + 0.48, 0.30, y0 + 0.72, col = "white", border = "grey30", lwd = 1.3)
  text(0.17, y0 + 0.60, header_mid, cex = 1.05, font = 2, family = ff)
  rect(0.40, y0 + 0.52, 0.62, y0 + 0.78, col = "white", border = "grey30", lwd = 1.3)
  text(0.51, y0 + 0.65, .lab(fit$mediator), cex = 1.05, font = 2, family = ff)
  rect(0.72, y0 + 0.52, 0.96, y0 + 0.78, col = "white", border = "grey30", lwd = 1.3)
  text(0.84, y0 + 0.65, .lab(y), cex = 1.05, font = 2, family = ff)
  arrows(0.30, y0 + 0.62, 0.40, y0 + 0.65, length = 0.09, lwd = 1.5)
  text(0.35, y0 + 0.74, fit$a_lab, cex = 1.0, font = 2, family = ff)
  arrows(0.62, y0 + 0.65, 0.72, y0 + 0.65, length = 0.09, lwd = 1.5)
  text(0.67, y0 + 0.76, fit$b_lab, cex = 1.0, font = 2, family = ff)
  arrows(0.30, y0 + 0.50, 0.72, y0 + 0.50, length = 0.09, lwd = 1.5)
  text(0.51, y0 + 0.40, fit$c_lab, cex = 1.0, font = 2, family = ff)
}

.draw_one <- function(mediator, spotlight_group, out_file, foot) {
  k <- as.integer(sub("^C", "", spotlight_group))
  d_spot <- d[!is.na(d[[cls_col]]) & d[[cls_col]] == k, , drop = FALSE]
  f_spot <- .path_fit(d_spot, mediator); f_spot$mediator <- mediator
  f_all <- .path_fit(d, mediator); f_all$mediator <- mediator
  tmp <- tempfile(fileext = ".pdf")
  grDevices::cairo_pdf(tmp, width = 9.0, height = 5.4, family = ff)
  par(mar = c(2.8, 0.3, 0.6, 0.3), family = ff)
  plot.new(); plot.window(xlim = c(0, 1), ylim = c(0, 1))
  .draw_panel(f_spot, paste("Class", k), .lab(x), 0.48)
  .draw_panel(f_all, "All", .lab(x), 0.00)
  mtext(foot, side = 1, line = 1.4, cex = 0.68, family = ff)
  grDevices::dev.off()
  ok <- file.copy(tmp, out_file, overwrite = TRUE)
  unlink(tmp)
  if (!isTRUE(ok)) stop("copy failed: ", out_file)
  message("wrote ", out_file)
  invisible(list(spot = f_spot, all = f_all, k = k))
}

out_pdf <- file.path(proj, "summary_results/Figures/pdf")
out_md <- file.path(proj, "summary_results/Figures/image_information")
ws <- file.path(proj, "summary_results_delivery_workspace")
tab_dir <- file.path(proj, "step07_parallel_competing_mediation/Tables")
dir.create(out_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(out_md, recursive = TRUE, showWarnings = FALSE)
dir.create(ws, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

utils::write.csv(tab, file.path(ws, "mediation_ACME_all_scale_mediators_by_LCA.csv"), row.names = FALSE)
utils::write.csv(tab, file.path(tab_dir, "Table_mediation_ACME_all_scale_mediators_by_LCA.csv"), row.names = FALSE)
utils::write.csv(picks, file.path(ws, "mediation_spotlight_picks.csv"), row.names = FALSE)

# Figure naming: Fig4 = SSD12; others S4a.. by order of ms
supp_letters <- c("a", "b", "c", "d", "e", "f", "g")
drawn <- list()
for (mi in seq_along(ms)) {
  m <- ms[[mi]]
  pk <- picks[picks$mediator == m, , drop = FALSE]
  foot <- paste0(
    "***P < 0.001; **P < 0.01; *P < 0.05. Adjusted OLS. ",
    "Spotlight ", pk$group[1], " (largest significant ACME among classes) vs All; mediator ", .lab(m), ". ",
    "Bootstrap ACME=", sprintf("%.3f [%.3f, %.3f]", pk$ACME[1], pk$ACME_lo[1], pk$ACME_hi[1]), "."
  )
  if (identical(m, "SSD12")) {
    fp <- file.path(out_pdf, "Figure 4. Mediation path diagram.pdf")
    md_name <- "Figure 4. Mediation path diagram.md"
  } else {
    # map non-SSD to S4a, S4b, ...
    others <- setdiff(ms, "SSD12")
    oi <- match(m, others)
    let <- supp_letters[[oi]]
    fp <- file.path(out_pdf, sprintf("Figure S4%s. Mediation path %s.pdf", let, .lab(m)))
    md_name <- sprintf("Figure S4%s. Mediation path %s.md", let, .lab(m))
  }
  res <- .draw_one(m, pk$group[1], fp, foot)
  drawn[[m]] <- res
  writeLines(c(
    paste0("# ", sub("\\.md$", "", md_name)),
    "", "## 图面说明", "",
    paste0(
      "七量表池中可作为中介的路径（暴露 PHQ-15、结局 WHO-DAS）。",
      "选类逻辑同原文 Fig4：显著 ACME 中 |ACME| 最大类 + All。",
      paste0("本中介 spotlight=", pk$group[1], "。"),
      paste0("路径标注 a=", res$spot$a_lab, "; b=", res$spot$b_lab, "; c′=", res$spot$c_lab,
             "（spotlight）；All: a=", res$all$a_lab, "; b=", res$all$b_lab, "; c′=", res$all$c_lab, "。")
    ),
    "", "## 分析上下文", "",
    paste0("- mediator: ", .lab(m)),
    paste0("- spotlight: ", pk$group[1], " n=", res$spot$n, "; All n=", res$all$n),
    paste0("- ACME: ", sprintf("%.3f [%.3f, %.3f] sig=%s", pk$ACME[1], pk$ACME_lo[1], pk$ACME_hi[1], pk$ACME_sig[1])),
    "- 七量表中 PHQ-15/WHO-DAS 为暴露/结局，不作为中介重跑",
    ""
  ), file.path(out_md, md_name))
}

# remove obsolete single S4 Whiteley name if replaced by S4*
old_s4 <- file.path(out_pdf, "Figure S4. Mediation path Whiteley-8.pdf")
if (file.exists(old_s4) && !any(grepl("Whiteley", list.files(out_pdf), fixed = TRUE) & grepl("^Figure S4[a-z]", list.files(out_pdf)))) {
  # keep if new whiteley S4x exists
}
unlink(file.path(out_pdf, "Figure S4. Mediation path Whiteley-8.pdf"))
unlink(file.path(out_md, "Figure S4. Mediation path Whiteley-8.md"))

# Methods brief
methods <- file.path(proj, "summary_results/Methods_statistical_analysis.md")
if (file.exists(methods)) {
  txt <- paste(readLines(methods, warn = FALSE), collapse = "\n")
  add <- paste0(
    " Beyond the pre-specified parallel mediators (SSD-12 and Whiteley-8), exploratory single-mediator paths ",
    "were also estimated for the remaining scale totals in the seven-score battery (SSS-8, PHQ-9, GAD-7), ",
    "each with LCA-class bootstrap ACME comparison and a Class-spotlight | All path diagram ",
    "(same selection rule as the index paper Figure 4). PHQ-15 and WHO-DAS were the exposure and outcome and were not used as mediators."
  )
  if (!grepl("remaining scale totals in the seven-score battery", txt)) {
    txt <- sub(
      "(Following the index paper's Figure 4 logic[^.]\\.)",
      paste0("\\1", add),
      txt
    )
    if (!grepl("remaining scale totals in the seven-score battery", txt)) {
      txt <- paste0(txt, "\n\n", add, "\n")
    }
    writeLines(txt, methods)
    message("Methods updated")
  }
}

message("DONE all scale mediators")
print(tab[tab$group %in% c("All", as.character(picks$group)),
          c("group", "mediator_lab", "n", "ACME", "ACME_sig", "a_lab", "b_lab", "c_lab")])
message("Figures:\n", paste(list.files(out_pdf, pattern = "Mediation"), collapse = "\n"))
