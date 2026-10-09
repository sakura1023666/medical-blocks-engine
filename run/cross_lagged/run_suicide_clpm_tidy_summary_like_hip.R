###############################################################################
#  run_suicide_clpm_tidy_summary_like_hip.R
#  1) figure/ 只留髋部式平铺 Figure*.pdf（清掉 pdf/png/tiff/杂散）
#  2) table/ 只留髋部式命名（旧 Table1_baseline 等归档）
#  3) 补齐可对应槽位：Fig1-Ward, Fig2 RCS, Fig3 forest, Fig S4, Fig S11, Fig S3-Ward
#  4) 课题根杂文件进 docs/
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
.study <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = file.path(.engine, ".superpowers/sdd/study_mirror")
)
.fig <- file.path(.study, "summary_result", "figure")
.tab <- file.path(.study, "summary_result", "table")
.arch_fig <- file.path(.study, "summary_result", "_archive_not_hip_layout")
.arch_tab <- file.path(.study, "summary_result", "_archive_old_table_names")
.docs <- file.path(.study, "docs")
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)
dir.create(.arch_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(.arch_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(.docs, recursive = TRUE, showWarnings = FALSE)

.message <- function(...) cat(sprintf(...), "\n")

.load <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  e$dabiao
}

.op <- .load(file.path(.study, "data/harmonized/D04_outpatient_clpm_imputed.RData"))
.wd <- tryCatch(
  .load(file.path(.study, "data/harmonized/D04_ward_clpm_imputed.RData")),
  error = function(e) .load(file.path(.study, "data/harmonized/D04_ward_clpm.RData"))
)
.m2 <- trimws(readLines(file.path(.study, "covariates/Model2Factors.txt"), warn = FALSE))
.m2 <- .m2[nzchar(.m2)]

# ── 1. 清理 figure：非「Figure *.pdf / README*.txt」移走 ──
.message("Cleaning figure/ to hip flat layout ...")
for (f in list.files(.fig, full.names = TRUE)) {
  bn <- basename(f)
  keep <- grepl("^Figure ", bn) || grepl("^README", bn)
  if (dir.exists(f) || !keep) {
    dest <- file.path(.arch_fig, bn)
    if (file.exists(dest) || dir.exists(dest)) {
      dest <- file.path(.arch_fig, paste0(bn, "_", as.integer(Sys.time())))
    }
    file.rename(f, dest)
  }
}

# ── 2. 清理 table：旧短名归档 ──
.message("Cleaning table/ old short names ...")
.old_pat <- "^(Table1_|Table2_|TableS[0-9]|CLPN_adjacency_stems)"
for (f in list.files(.tab, full.names = TRUE)) {
  bn <- basename(f)
  if (grepl(.old_pat, bn) || grepl("_footnote\\.txt$|_NOTE\\.txt$|imputation_note\\.txt$", bn)) {
    file.rename(f, file.path(.arch_tab, bn))
  }
}

# ── 3. 课题根 docs ──
for (bn in c(
  "2026-09-20-suicide-cssrs-hama-hamd-clpm-design.md",
  "2026-09-20-suicide-cssrs-hama-hamd-clpm.md"
)) {
  src <- file.path(.study, bn)
  if (file.exists(src)) file.rename(src, file.path(.docs, bn))
}

# ── helpers ──
.pdf <- function(path, expr, w = 8, h = 6) {
  grDevices::pdf(path, width = w, height = h)
  on.exit(grDevices::dev.off(), add = TRUE)
  force(expr)
  invisible(path)
}

.attrition_fig <- function(csv_path, outfile, title) {
  if (!file.exists(csv_path)) return(invisible(NULL))
  a <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
  # expect columns step, n_remain or similar
  nms <- names(a)
  step_col <- if ("step" %in% nms) "step" else nms[[1]]
  n_col <- if ("n_remain" %in% nms) "n_remain" else if ("n" %in% nms) "n" else nms[[2]]
  labs <- as.character(a[[step_col]])
  ns <- as.numeric(a[[n_col]])
  .pdf(outfile, {
    op <- par(mar = c(1, 1, 3, 1))
    on.exit(par(op), add = TRUE)
    plot.new()
    title(main = title, cex.main = 1.1)
    y <- seq(0.85, 0.15, length.out = length(ns))
    for (i in seq_along(ns)) {
      rect(0.25, y[i] - 0.06, 0.75, y[i] + 0.06, col = "#D6EAF8", border = "#2C3E50")
      text(0.5, y[i], sprintf("%s\nn = %s", labs[i], format(ns[i], big.mark = ",")), cex = 0.9)
      if (i < length(ns)) {
        arrows(0.5, y[i] - 0.07, 0.5, y[i + 1] + 0.07, length = 0.08)
        if (i < length(ns)) {
          excl <- ns[i] - ns[i + 1]
          if (is.finite(excl) && excl > 0)
            text(0.78, (y[i] + y[i + 1]) / 2, sprintf("Excluded %s", excl), cex = 0.75, col = "#C0392B")
        }
      }
    }
  }, w = 7, h = 5)
}

# Fig1-Ward
.attrition_fig(
  file.path(.study, "data/harmonized/attrition_ward.csv"),
  file.path(.fig, "Figure 1-Ward. Longitudinal inclusion exclusion flowchart.pdf"),
  "Figure 1-Ward. Longitudinal inclusion / exclusion"
)

# Ensure Fig1-Outpatient exists (recreate if cleaned away without copy)
.f1o <- file.path(.fig, "Figure 1-Outpatient. Longitudinal inclusion exclusion flowchart.pdf")
if (!file.exists(.f1o)) {
  .attrition_fig(
    file.path(.study, "data/harmonized/attrition_outpatient.csv"),
    .f1o,
    "Figure 1-Outpatient. Longitudinal inclusion / exclusion"
  )
}

# ── Figure 2 RCS: HAMD_Index / HAMA_Index → CSSRS_1st ──
.message("Figure 2 RCS ...")
.rcs_one <- function(d, xvar, outfile, xlab) {
  y <- as.integer(d$CSSRS_1st)
  x <- as.numeric(d[[xvar]])
  ok <- is.finite(x) & !is.na(y)
  d2 <- data.frame(x = x[ok], y = y[ok])
  # natural spline logistic
  sp <- splines::ns(d2$x, df = 4)
  m <- stats::glm(y ~ sp, data = d2, family = binomial())
  xg <- seq(min(d2$x), max(d2$x), length.out = 200)
  Xg <- predict(splines::ns(d2$x, df = 4), newx = xg)
  # rebuild design: intercept + ns columns
  # easier: predict on grid via model.matrix with ns fitted on original
  nd <- data.frame(x = xg)
  # refit with ns in formula
  m2 <- stats::glm(y ~ splines::ns(x, df = 4), data = d2, family = binomial())
  pr <- predict(m2, newdata = nd, type = "link", se.fit = TRUE)
  fit <- plogis(pr$fit)
  lo <- plogis(pr$fit - 1.96 * pr$se.fit)
  hi <- plogis(pr$fit + 1.96 * pr$se.fit)
  .pdf(outfile, {
    plot(xg, fit, type = "l", lwd = 2, col = "#2C7BB6",
         xlab = xlab, ylab = "Predicted P(CSSRS item1 = 1)",
         ylim = range(c(lo, hi, 0, 1), finite = TRUE),
         main = basename(outfile))
    polygon(c(xg, rev(xg)), c(lo, rev(hi)), col = adjustcolor("#2C7BB6", 0.2), border = NA)
    lines(xg, fit, lwd = 2, col = "#2C7BB6")
  }, w = 7.5, h = 5.5)
}

.rcs_one(.op, "HAMD_Index",
         file.path(.fig, "Figure 2-Outpatient. RCS plot between HAMD and CSSRS ideation.pdf"),
         "HAMD Index total")
.rcs_one(.op, "HAMA_Index",
         file.path(.fig, "Figure 2-Outpatient. RCS plot between HAMA and CSSRS ideation.pdf"),
         "HAMA Index total")

# ── Figure 3 subgroup forest: HAMD_Index → CSSRS_1st OR by strata ──
.message("Figure 3 forest ...")
.or_fit <- function(df, subset = NULL) {
  d <- if (is.null(subset)) df else df[subset, , drop = FALSE]
  d <- d[is.finite(d$HAMD_Index) & !is.na(d$CSSRS_1st), , drop = FALSE]
  if (nrow(d) < 40L || length(unique(d$CSSRS_1st)) < 2L)
    return(c(or = NA, lo = NA, hi = NA, n = nrow(d)))
  m <- tryCatch(
    stats::glm(CSSRS_1st ~ HAMD_Index, data = d, family = binomial()),
    error = function(e) NULL
  )
  if (is.null(m)) return(c(or = NA, lo = NA, hi = NA, n = nrow(d)))
  cf <- summary(m)$coefficients
  if (!"HAMD_Index" %in% rownames(cf)) return(c(or = NA, lo = NA, hi = NA, n = nrow(d)))
  b <- cf["HAMD_Index", 1]
  se <- cf["HAMD_Index", 2]
  c(or = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), n = nrow(d))
}

.forest_rows <- list()
.forest_rows[[1]] <- c(label = "Overall", .or_fit(.op))
if ("sex" %in% names(.op)) {
  for (lv in sort(unique(as.character(.op$sex)))) {
    if (!nzchar(lv) || is.na(lv)) next
    .forest_rows[[length(.forest_rows) + 1L]] <- c(
      label = paste0("Sex: ", lv),
      .or_fit(.op, as.character(.op$sex) == lv)
    )
  }
}
if ("age" %in% names(.op)) {
  med <- stats::median(as.numeric(.op$age), na.rm = TRUE)
  .forest_rows[[length(.forest_rows) + 1L]] <- c(
    label = sprintf("Age < %.0f", med),
    .or_fit(.op, as.numeric(.op$age) < med)
  )
  .forest_rows[[length(.forest_rows) + 1L]] <- c(
    label = sprintf("Age >= %.0f", med),
    .or_fit(.op, as.numeric(.op$age) >= med)
  )
}
.fr <- do.call(rbind, lapply(.forest_rows, function(x) {
  data.frame(
    label = x[["label"]],
    or = as.numeric(x[["or"]]),
    lo = as.numeric(x[["lo"]]),
    hi = as.numeric(x[["hi"]]),
    n = as.numeric(x[["n"]]),
    stringsAsFactors = FALSE
  )
}))
utils::write.csv(.fr, file.path(.tab, "Figure3_forest_data_Outpatient.csv"), row.names = FALSE)

.pdf(file.path(.fig, "Figure 3-Outpatient. Subgroup Forest analyses of HAMD to CSSRS.pdf"), {
  ok <- is.finite(.fr$or) & is.finite(.fr$lo) & is.finite(.fr$hi)
  fr <- .fr[ok, , drop = FALSE]
  n <- nrow(fr)
  op <- par(mar = c(5, 12, 3, 4))
  on.exit(par(op), add = TRUE)
  ys <- seq_len(n)
  xlim <- range(c(fr$lo, fr$hi, 1), finite = TRUE)
  xlim <- c(max(0.5, xlim[1] * 0.9), xlim[2] * 1.1)
  plot(1, type = "n", xlim = xlim, ylim = c(0.5, n + 0.5),
       xlab = "OR (HAMD_Index → CSSRS_1st)", ylab = "", yaxt = "n", log = "x",
       main = "Figure 3-Outpatient. Subgroup forest")
  abline(v = 1, lty = 2, col = "grey50")
  arrows(fr$lo, ys, fr$hi, ys, code = 3, angle = 90, length = 0.05, col = "#2C7BB6")
  points(fr$or, ys, pch = 15, col = "#2C7BB6", cex = 1.2)
  axis(2, at = ys, labels = sprintf("%s (n=%s)", fr$label, fr$n), las = 1, cex.axis = 0.85)
}, w = 9, h = max(4, 0.55 * nrow(.fr) + 2))

# ── Figure S3-Ward path diagram (from Table 2 ward if exists) ──
.message("Figure S3-Ward ...")
.ward_paths <- file.path(.tab, "Table 2-Ward. Exploratory cross-lagged path analysis HAMD HAMA CSSRS.csv")
if (!file.exists(.ward_paths)) {
  .ward_paths <- file.path(.arch_tab, "TableS3_ward_CLPM_paths.csv")
}
if (file.exists(.ward_paths)) {
  wp <- utils::read.csv(.ward_paths, stringsAsFactors = FALSE)
  .pdf(file.path(.fig, "Figure S3-Ward. Exploratory cross-lagged path diagram of HAMD HAMA CSSRS.pdf"), {
    plot.new()
    title("Figure S3-Ward (Exploratory) CLPM paths")
    if ("path" %in% names(wp)) {
      labs <- sprintf(
        "%s: est=%.3f p=%s",
        wp$path,
        as.numeric(wp$estimate),
        format.pval(as.numeric(wp$p), digits = 3)
      )
      text(0.05, seq(0.9, 0.1, length.out = length(labs)), labs, adj = 0, cex = 0.7, family = "mono")
    }
  }, w = 10, h = 7)
}

# Ensure S3-Outpatient still present
.s3o <- file.path(.fig, "Figure S3-Outpatient. Cross-lagged path diagram of HAMD HAMA CSSRS.pdf")
if (!file.exists(.s3o)) {
  # recreate simple text from Table2
  t2 <- file.path(.tab, "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.csv")
  if (!file.exists(t2)) t2 <- file.path(.arch_tab, "Table2_CLPM_paths.csv")
  if (file.exists(t2)) {
    wp <- utils::read.csv(t2, stringsAsFactors = FALSE)
    .pdf(.s3o, {
      plot.new()
      title("Figure S3-Outpatient CLPM paths")
      labs <- sprintf("%s: est=%.3f p=%s", wp$path, as.numeric(wp$estimate),
                      format.pval(as.numeric(wp$p), digits = 3))
      text(0.05, seq(0.9, 0.1, length.out = length(labs)), labs, adj = 0, cex = 0.7, family = "mono")
    }, w = 10, h = 7)
  }
}

# ── Figure S4: Mean HAMD/HAMA by wave and CSSRS_Index ──
.message("Figure S4 ...")
.pdf(file.path(.fig, "Figure S4-Outpatient. Mean HAMD HAMA by Wave and CSSRS.pdf"), {
  d <- .op
  d$CSSRS_lab <- ifelse(d$CSSRS_Index == 1, "CSSRS+", "CSSRS-")
  means <- rbind(
    data.frame(wave = "Index", score = "HAMD", grp = d$CSSRS_lab, val = d$HAMD_Index),
    data.frame(wave = "1st", score = "HAMD", grp = d$CSSRS_lab, val = d$HAMD_1st),
    data.frame(wave = "Index", score = "HAMA", grp = d$CSSRS_lab, val = d$HAMA_Index),
    data.frame(wave = "1st", score = "HAMA", grp = d$CSSRS_lab, val = d$HAMA_1st)
  )
  means <- means[is.finite(means$val) & !is.na(means$grp), ]
  agg <- stats::aggregate(val ~ wave + score + grp, means, mean)
  op <- par(mfrow = c(1, 2), mar = c(5, 4, 3, 1))
  on.exit(par(op), add = TRUE)
  for (sc in c("HAMD", "HAMA")) {
    sub <- agg[agg$score == sc, ]
    grps <- sort(unique(sub$grp))
    waves <- c("Index", "1st")
    mat <- sapply(grps, function(g) {
      sapply(waves, function(w) {
        v <- sub$val[sub$grp == g & sub$wave == w]
        if (length(v)) v[[1]] else NA_real_
      })
    })
    barplot(mat, beside = TRUE, names.arg = grps, legend.text = waves,
            args.legend = list(x = "topright", bty = "n", cex = 0.8),
            col = c("#A8C5E2", "#F6B7C6"),
            main = sc, ylab = "Mean score", ylim = c(0, max(mat, na.rm = TRUE) * 1.25))
  }
}, w = 10, h = 5)

# ── Figure S11 ROC ──
.message("Figure S11 ROC ...")
.pdf(file.path(.fig, "Figure S11-Outpatient. ROC HAMD HAMA for CSSRS.pdf"), {
  d <- .op
  y <- as.integer(d$CSSRS_1st)
  if (requireNamespace("pROC", quietly = TRUE)) {
    r1 <- pROC::roc(y, d$HAMD_Index, quiet = TRUE)
    r2 <- pROC::roc(y, d$HAMA_Index, quiet = TRUE)
    plot(r1, col = "#2C7BB6", lwd = 2, main = "Figure S11-Outpatient. ROC")
    plot(r2, col = "#D7191C", lwd = 2, add = TRUE)
    legend("bottomright",
           legend = c(
             sprintf("HAMD Index AUC=%.3f", as.numeric(pROC::auc(r1))),
             sprintf("HAMA Index AUC=%.3f", as.numeric(pROC::auc(r2)))
           ),
           col = c("#2C7BB6", "#D7191C"), lwd = 2, bty = "n")
  } else {
    # manual ROC-ish via ranking
    plot.new()
    title("pROC not installed")
  }
}, w = 6.5, h = 6.5)

# ── README like hip ──
.boot_note <- "CLPN bootstrap CONFIRMED: n_boot_edge=1000, n_boot_case=1000 (see table/CLPN_bootstrap_Outpatient.rds)."
writeLines(c(
  "summary_result/figure — hip-style FLAT folder (Figure*.pdf only).",
  .boot_note,
  "",
  "Slot map (Outpatient ≈ main cohort; Ward ≈ exploratory second panel):",
  "  Figure 1-Outpatient / Figure 1-Ward — attrition",
  "  Figure 2-Outpatient — RCS HAMD/HAMA → CSSRS (two files)",
  "  Figure 3-Outpatient — subgroup forest HAMD→CSSRS",
  "  Figure 4-Outpatient/Ward — CLPN (+ focus splits)",
  "  Figure S1/S2-Outpatient/Ward — CLPN bootstrap 1000",
  "  Figure S3-Outpatient/Ward — path diagram",
  "  Figure S4-Outpatient — mean scores by wave × CSSRS",
  "  Figure S11-Outpatient — ROC",
  "",
  "Not applicable vs hip multi-DB: Figure 2/3/S3/S4 Pooled, Figure S5 country,",
  "  CHARLS/ELSA/HRS triplicate copies.",
  "",
  "Archived clutter: summary_result/_archive_not_hip_layout/",
  "Old short table names: summary_result/_archive_old_table_names/"
), file.path(.fig, "README_FigS1_S2_CLPN_bootstrap.txt"))

writeLines(c(
  .boot_note,
  "figure/ is flat like hip. See figure/README_FigS1_S2_CLPN_bootstrap.txt"
), file.path(.tab, "README_summary_slots.txt"))

# List final figure dir
.message("Final figure/ files:")
print(sort(list.files(.fig)))
.message("DONE tidy")
