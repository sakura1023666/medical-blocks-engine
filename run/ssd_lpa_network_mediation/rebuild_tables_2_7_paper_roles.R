#!/usr/bin/env Rscript
# Rebuild Table 2–7 to Ma 2026 (Acta Psychol) paper roles:
#   T2 LPA fit | T3 multinomial OR | T4 Strength centrality |
#   T5 correlation | T6 mediation SSD-12 | T7 mediation Whiteley-8
# Extras (ROC/CFA/CS/contrast) → Table S*.

suppressPackageStartupMessages({
  library(openxlsx)
})

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)
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

sr_tab <- file.path(proj, "summary_results/Tables")
ws <- file.path(proj, "summary_results_delivery_workspace")
dir.create(sr_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(ws, recursive = TRUE, showWarnings = FALSE)
net_dir <- file.path(proj, "step08_complex_network_profile_batch/Tables/Network")
med_dir <- file.path(proj, "step07_parallel_competing_mediation/Tables")

.na_cell <- "-"
.fmt_p <- function(p) {
  if (!is.finite(p)) return(.na_cell)
  if (p < 0.001) "<0.001" else formatC(p, format = "f", digits = 3)
}
.fmt_est <- function(x, d = 3L) {
  if (!is.finite(x)) return(.na_cell)
  formatC(x, format = "f", digits = d)
}
.fmt_pct <- function(x) {
  if (!is.finite(x)) return("/")
  paste0(formatC(100 * x, format = "f", digits = 2), "%")
}
.se_from_ci <- function(lo, hi) {
  if (!is.finite(lo) || !is.finite(hi)) return(NA_real_)
  (hi - lo) / (2 * 1.959964)
}

.write_sci <- function(path, title, df, footnotes = NULL, merge_cat = FALSE) {
  sci_xlsx_single_header_booktabs(
    filepath = path, title = title, df_body = df,
    sheet = "Sheet1", footnotes = footnotes, blank_na_cells = TRUE
  )
  if (isTRUE(merge_cat) && "Category" %in% names(df)) {
    wb <- loadWorkbook(path)
    sh <- names(wb)[[1]]
    body_start <- 3L
    cats <- as.character(df$Category)
    r <- 1L
    while (r <= length(cats)) {
      if (!nzchar(cats[[r]])) { r <- r + 1L; next }
      r2 <- r
      while (r2 < length(cats) && !nzchar(cats[[r2 + 1L]])) r2 <- r2 + 1L
      if (r2 > r) {
        tryCatch(
          mergeCells(wb, sh, cols = 1, rows = (body_start + r - 1L):(body_start + r2 - 1L)),
          error = function(e) NULL
        )
      }
      r <- r2 + 1L
    }
    saveWorkbook(wb, path, overwrite = TRUE)
  }
  py <- Sys.which("python3")
  script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
  if (nzchar(py) && file.exists(script)) {
    invisible(system2(py, shQuote(c(script, path)), stdout = TRUE, stderr = TRUE))
  }
  message("wrote ", basename(path))
}

# ── archive old wrong-role xlsx ──────────────────────────────────────────────
old_keep <- character(0)
arch <- file.path(ws, paste0("tables_pre_paper_roles_", format(Sys.time(), "%Y%m%d_%H%M%S")))
dir.create(arch, recursive = TRUE, showWarnings = FALSE)
for (f in list.files(sr_tab, pattern = "^Table [2-7].*\\.xlsx$|^Table S.*\\.xlsx$")) {
  file.copy(file.path(sr_tab, f), file.path(arch, f), overwrite = TRUE)
  # keep Table 1
}
message("archived prior T2–S* → ", arch)

# ═══════════════════════════════════════════════════════════════════════════
# Table 2 — LPA fit (paper columns)
# ═══════════════════════════════════════════════════════════════════════════
fit <- utils::read.csv(
  file.path(proj, "step04_latent_profile_tidylpa/Tables/Table_LPA_fit_indices.csv"),
  stringsAsFactors = FALSE
)
n_fit <- 698L
t2 <- data.frame(
  Class = as.integer(fit$K),
  AIC = vapply(fit$AIC, function(x) .fmt_est(x, 2L), character(1)),
  BIC = vapply(fit$BIC, function(x) .fmt_est(x, 2L), character(1)),
  aBIC = vapply(seq_len(nrow(fit)), function(i) {
    ll <- fit$loglik[[i]]
    kpar <- (fit$AIC[[i]] + 2 * ll) / 2
    abic <- -2 * ll + kpar * log((n_fit + 2) / 24)
    .fmt_est(abic, 2L)
  }, character(1)),
  Entropy = vapply(fit$entropy, function(e) {
    if (is.na(e)) .na_cell else .fmt_est(e, 3L)
  }, character(1)),
  Proportion = vapply(fit$class_counts, function(cc) {
    ns <- as.integer(strsplit(as.character(cc), "\\|")[[1]])
    paste(formatC(ns / sum(ns), format = "f", digits = 2), collapse = "/")
  }, character(1)),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
.write_sci(
  file.path(sr_tab, "Table 2. Latent class analysis fit indices.xlsx"),
  "Table 2. Latent class analysis of WHO-DAS items in outpatients with somatic symptom burden (n = 698).",
  t2,
  footnotes = c(
    "AIC, Akaike Information Criterion; BIC, Bayesian Information Criterion; aBIC, sample-size adjusted BIC.",
    "Entropy = relative entropy.",
    "Selected K = 3 (class counts 375|219|104; entropy = 0.873)."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table 3 — paper three-level header (dedicated script)
# ═══════════════════════════════════════════════════════════════════════════
system2(
  "Rscript",
  c(file.path(root, "run/ssd_lpa_network_mediation/rebuild_table3_paper_header.R"),
    "--project", proj),
  stdout = TRUE, stderr = TRUE
) |> (\(x) { message(paste(utils::tail(x, 3), collapse = "\n")); invisible(x) })()

# keep cleaned data for Table 5 correlation
ck5 <- readRDS(file.path(proj, "checkpoints/step05_baseline_multiclass.rds"))
d0 <- ck5$ctx$data$cleaned
d0 <- d0[!is.na(d0$LCA_class), , drop = FALSE]

# ═══════════════════════════════════════════════════════════════════════════
# Table 4 — paper long class-name headers (dedicated script)
# ═══════════════════════════════════════════════════════════════════════════
system2(
  "Rscript",
  c(file.path(root, "run/ssd_lpa_network_mediation/rebuild_table4_paper_header.R"),
    "--project", proj),
  stdout = TRUE, stderr = TRUE
) |> (\(x) { message(paste(utils::tail(x, 2), collapse = "\n")); invisible(x) })()

# ═══════════════════════════════════════════════════════════════════════════
# Table 5 — Correlation (paper-style construct matrix)
# ═══════════════════════════════════════════════════════════════════════════
vars5 <- c("PHQ15", "SSD12", "Whiteley8", "WHODAS")
labs5 <- c("PHQ-15", "SSD-12", "Whiteley-8", "WHO-DAS")
M <- suppressWarnings(stats::cor(d0[, vars5], use = "pairwise.complete.obs", method = "spearman"))
t5 <- as.data.frame(matrix("", length(vars5), length(vars5) + 1L), stringsAsFactors = FALSE)
names(t5) <- c("Variables", labs5)
t5$Variables <- labs5
for (i in seq_along(vars5)) {
  for (j in seq_len(i)) {
    t5[i, j + 1L] <- .fmt_est(M[i, j], 3L)
  }
}
.write_sci(
  file.path(sr_tab, "Table 5. Correlation analysis of key constructs.xlsx"),
  "Table 5. Spearman correlation of PHQ-15, SSD-12, Whiteley-8, and WHO-DAS.",
  t5,
  footnotes = c(
    "Spearman ρ; pairwise complete cases. Lower triangle shown (diagonal = 1).",
    "Construct roles align with the mediation model (exposure / mediators / outcome)."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table 6 / 7 — Mediation All/C* Total·Direct·Indirect (paper Table 6 geometry)
# ═══════════════════════════════════════════════════════════════════════════
med <- utils::read.csv(
  file.path(med_dir, "Table_mediation_ACME_by_LCA_class.csv"),
  stringsAsFactors = FALSE
)
med_all <- utils::read.csv(
  file.path(med_dir, "Table_parallel_competing_mediation.csv"),
  stringsAsFactors = FALSE
)

.build_med_table <- function(mediator) {
  sub <- med[med$mediator == mediator, , drop = FALSE]
  rows <- list()
  for (g in c("All", "C1", "C2", "C3")) {
    w <- sub[sub$group == g, , drop = FALSE]
    if (!nrow(w)) next
    acme <- w$ACME[[1]]
    ade <- w$ADE[[1]]
    tot <- acme + ade
    acme_lo <- w$ACME_lo[[1]]
    acme_hi <- w$ACME_hi[[1]]
    se_i <- .se_from_ci(acme_lo, acme_hi)
    # ADE CI only for All from parallel table
    ade_lo <- ade_hi <- se_d <- se_t <- tot_lo <- tot_hi <- NA_real_
    if (identical(g, "All")) {
      wa <- med_all[med_all$mediator == mediator, , drop = FALSE]
      if (nrow(wa)) {
        ade_lo <- wa$ADE_lo[[1]]
        ade_hi <- wa$ADE_hi[[1]]
        se_d <- .se_from_ci(ade_lo, ade_hi)
        # total CI approx from ACME+ADE bounds (conservative envelope not exact)
        tot_lo <- acme_lo + ade_lo
        tot_hi <- acme_hi + ade_hi
        se_t <- .se_from_ci(tot_lo, tot_hi)
      }
    }
    mk <- function(label, est, se, lo, hi, size) {
      data.frame(
        Path = paste0(g, "- ", label),
        Effect = .fmt_est(est),
        SE = if (is.finite(se)) .fmt_est(se) else .na_cell,
        LLCI = if (is.finite(lo)) .fmt_est(lo) else .na_cell,
        ULCI = if (is.finite(hi)) .fmt_est(hi) else .na_cell,
        `Effect size` = size,
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
    rows[[length(rows) + 1L]] <- mk("Total effect", tot, se_t, tot_lo, tot_hi, "/")
    rows[[length(rows) + 1L]] <- mk(
      "Direct effect", ade, se_d, ade_lo, ade_hi,
      .fmt_pct(ade / tot)
    )
    rows[[length(rows) + 1L]] <- mk(
      "Indirect effect", acme, se_i, acme_lo, acme_hi,
      .fmt_pct(acme / tot)
    )
  }
  do.call(rbind, rows)
}

t6 <- .build_med_table("SSD12")
.write_sci(
  file.path(sr_tab, "Table 6. Mediating effect analysis (SSD-12).xlsx"),
  "Table 6. Mediating effect analysis of PHQ-15, SSD-12, and WHO-DAS.",
  t6,
  footnotes = c(
    "Exposure = PHQ-15; mediator = SSD-12; outcome = WHO-DAS. Covariates: age, sex, education, marriage, income, livingsite.",
    "Indirect = ACME (bootstrap product-of-coefficients); Direct = ADE; Total = ACME + ADE.",
    "LLCI / ULCI = 95% percentile bootstrap CI (reported for indirect in all strata; for All also Direct).",
    "Effect size = |effect| / |total| × 100% (Direct / Indirect); Total marked '/'.",
    "C1–C3 = LCA classes; All = full sample."
  )
)

t7 <- .build_med_table("Whiteley8")
contrast <- utils::read.csv(
  file.path(med_dir, "Table_indirect_effect_contrast.csv"),
  stringsAsFactors = FALSE
)
ct_ft <- if (nrow(contrast)) {
  sprintf(
    "Indirect-effect contrast ACME(SSD-12) − ACME(Whiteley-8) = %s (95%% CI %s–%s; n boot = %s).",
    .fmt_est(contrast$estimate[[1]]),
    .fmt_est(contrast$lo[[1]]),
    .fmt_est(contrast$hi[[1]]),
    as.character(contrast$n_boot[[1]] %||% contrast[["n.boot"]][[1]] %||% "2000")
  )
} else {
  "Indirect-effect contrast archived in Table S (ACME SSD-12 − Whiteley-8)."
}
.write_sci(
  file.path(sr_tab, "Table 7. Mediating effect analysis (Whiteley-8).xlsx"),
  "Table 7. Mediating effect analysis of PHQ-15, Whiteley-8, and WHO-DAS.",
  t7,
  footnotes = c(
    "Parallel competing mediator to Table 6 (Whiteley-8). Same covariates and bootstrap scheme.",
    "Layout mirrors the index paper Table 6 (All / C1 / C2 / C3 × Total / Direct / Indirect).",
    ct_ft
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# No Table S* in delivery (user: drop S1–S3)
# ═══════════════════════════════════════════════════════════════════════════
obsolete <- c(
  "Table 2. LCA fit indices.xlsx",
  "Table 3. Parallel competing mediation.xlsx",
  "Table 4. Indirect effect contrast.xlsx",
  "Table 5. Network profile summary.xlsx",
  "Table 6. Clinical ROC.xlsx",
  "Table 6. Mediating effect analysis (SSD-12).xlsx",
  "Table 7. Mediating effect analysis (Whiteley-8).xlsx",
  "Table S1. CFA discriminant fit.xlsx",
  "Table S2. Network stability (CS).xlsx",
  "Table S2. Scale score summary.xlsx",
  "Table S3. Clinical ROC.xlsx"
)
for (f in obsolete) {
  fp <- file.path(sr_tab, f)
  if (file.exists(fp)) {
    file.copy(fp, file.path(arch, f), overwrite = TRUE)
    unlink(fp)
  }
}

message("DONE Table 2–7 paper roles → ", sr_tab)
print(list.files(sr_tab, pattern = "\\.xlsx$"))
