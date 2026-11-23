#!/usr/bin/env Rscript
# Extend delivery for 1021 feedback gaps WITHOUT touching Table1–6 / Fig1–4.
# New: Table7+ and Figure5+.

suppressPackageStartupMessages({
  library(openxlsx)
  library(ggplot2)
})

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)
`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b
.na_cell <- "-"
.fmt_est <- function(x, d = 3L) {
  if (length(x) != 1L || !is.finite(x)) return(.na_cell)
  formatC(x, format = "f", digits = d)
}
.fmt_p <- function(p) {
  if (!is.finite(p)) return(.na_cell)
  if (p < 0.001) "<0.001" else formatC(p, format = "f", digits = 3)
}
.fmt_pct <- function(x) {
  if (!is.finite(x)) return("/")
  paste0(formatC(100 * x, format = "f", digits = 2), "%")
}
.se_ci <- function(lo, hi) {
  if (!is.finite(lo) || !is.finite(hi)) return(NA_real_)
  (hi - lo) / (2 * 1.959964)
}

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
n_boot <- if (!is.na(iB) && iB < length(args)) as.integer(args[[iB + 1L]]) else 1500L

sr <- file.path(proj, "summary_results")
sr_tab <- file.path(sr, "Tables")
sr_pdf <- file.path(sr, "Figures", "pdf")
sr_md <- file.path(sr, "Figures", "image_information")
ws <- file.path(proj, "summary_results_delivery_workspace")
dir.create(sr_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(sr_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(sr_md, recursive = TRUE, showWarnings = FALSE)
dir.create(ws, recursive = TRUE, showWarnings = FALSE)

# Protect existing delivery names
.protect <- c(
  list.files(sr_tab, pattern = "^Table [1-6]\\b"),
  list.files(sr_pdf, pattern = "^Figure [1-4]\\b")
)
message("protect: ", paste(.protect, collapse = "; "))

.write_sci <- function(path, title, df, footnotes = NULL) {
  if (basename(path) %in% .protect) stop("refusing overwrite: ", basename(path))
  sci_xlsx_single_header_booktabs(
    filepath = path, title = title, df_body = df,
    sheet = "Sheet1", footnotes = footnotes, blank_na_cells = TRUE
  )
  py <- Sys.which("python3")
  script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
  if (nzchar(py) && file.exists(script)) {
    invisible(system2(py, shQuote(c(script, path)), stdout = TRUE, stderr = TRUE))
  }
  message("wrote ", basename(path))
}

.pipeline_pdf <- function(file, plot, width = 8, height = 5) {
  if (basename(file) %in% .protect) stop("refusing overwrite fig: ", basename(file))
  grDevices::pdf(file, width = width, height = height, useDingbats = FALSE)
  print(plot)
  grDevices::dev.off()
  message("wrote ", basename(file))
}

# ── data ────────────────────────────────────────────────────────────────────
ck <- readRDS(file.path(proj, "checkpoints/step05_baseline_multiclass.rds"))
d0 <- ck$ctx$data$cleaned
d0 <- d0[!is.na(d0$LCA_class), , drop = FALSE]
d0$Class <- factor(paste0("C", as.integer(d0$LCA_class)), levels = c("C1", "C2", "C3"))
class_lab <- c(
  C1 = "Low symptom–Low disability",
  C2 = "Moderate symptom–Moderate disability",
  C3 = "High symptom–High disability"
)

# covariates for mediation
covs0 <- c("age", "sex", "education", "marriage", "income", "livingsite")
.prep_med <- function(dd, extra = character(0)) {
  need <- unique(c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7",
                   covs0, extra, "Class", paste0("DAS", 1:12), "N12AA",
                   "pain_predominant", "persistent", "SSD", "sex"))
  need <- need[need %in% names(dd)]
  d <- dd[, need, drop = FALSE]
  for (v in setdiff(need, c("Class", "N12AA", "pain_predominant", "persistent", "SSD", "sex"))) {
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
    } else d[[v]] <- suppressWarnings(as.numeric(d[[v]]))
  }
  d
}
d <- .prep_med(d0)
cov_use <- intersect(covs0, names(d))
cov_txt <- if (length(cov_use)) paste0(" + ", paste(cov_use, collapse = " + ")) else ""

# WHO-DAS domains (WHO-DAS 2.0 12-item pairing; file lacks DAS8/DAS9)
.domain_mean <- function(dd, items) {
  cols <- intersect(items, names(dd))
  if (!length(cols)) return(rep(NA_real_, nrow(dd)))
  rowMeans(dd[, cols, drop = FALSE], na.rm = TRUE)
}
d$DAS_Cognition <- .domain_mean(d, c("DAS1", "DAS2"))
d$DAS_Mobility <- .domain_mean(d, c("DAS3", "DAS4"))
d$DAS_SelfCare <- .domain_mean(d, c("DAS5", "DAS6"))
d$DAS_GettingAlong <- .domain_mean(d, c("DAS7", "DAS8"))
d$DAS_LifeActivities <- .domain_mean(d, c("DAS9", "DAS10"))
d$DAS_Participation <- .domain_mean(d, c("DAS11", "DAS12"))
dom_vars <- c(
  DAS_Cognition = "Cognition",
  DAS_Mobility = "Mobility",
  DAS_SelfCare = "Self-care",
  DAS_GettingAlong = "Getting along",
  DAS_LifeActivities = "Life activities",
  DAS_Participation = "Participation"
)
dom_item_note <- "Available items: DAS1–7, DAS10–12 (DAS8/DAS9 absent in file). Getting along uses DAS7; Life activities uses DAS10."

# ═══════════════════════════════════════════════════════════════════════════
# Table 7 — H3 indirect contrast SSD-12 vs Whiteley-8
# ═══════════════════════════════════════════════════════════════════════════
ct <- utils::read.csv(
  file.path(proj, "step07_parallel_competing_mediation/Tables/Table_indirect_effect_contrast.csv"),
  stringsAsFactors = FALSE
)
t7 <- data.frame(
  Contrast = "ACME(SSD-12) - ACME(Whiteley-8)",
  Estimate = .fmt_est(ct$estimate[[1]]),
  LLCI = .fmt_est(ct$lo[[1]]),
  ULCI = .fmt_est(ct$hi[[1]]),
  `n boot` = as.character(ct$n_boot[[1]]),
  Significant = if (ct$lo[[1]] * ct$hi[[1]] > 0) "Yes" else "No",
  check.names = FALSE, stringsAsFactors = FALSE
)
# also All ACME side-by-side from parallel table
par <- utils::read.csv(
  file.path(proj, "step07_parallel_competing_mediation/Tables/Table_parallel_competing_mediation.csv"),
  stringsAsFactors = FALSE
)
t7b <- data.frame(
  Mediator = c("SSD-12", "Whiteley-8", "Difference (SSD-12 - Whiteley-8)"),
  ACME = c(.fmt_est(par$ACME[par$mediator == "SSD12"]),
           .fmt_est(par$ACME[par$mediator == "Whiteley8"]),
           .fmt_est(ct$estimate[[1]])),
  LLCI = c(.fmt_est(par$ACME_lo[par$mediator == "SSD12"]),
           .fmt_est(par$ACME_lo[par$mediator == "Whiteley8"]),
           .fmt_est(ct$lo[[1]])),
  ULCI = c(.fmt_est(par$ACME_hi[par$mediator == "SSD12"]),
           .fmt_est(par$ACME_hi[par$mediator == "Whiteley8"]),
           .fmt_est(ct$hi[[1]])),
  Prop_mediated = c(.fmt_pct(par$prop[par$mediator == "SSD12"]),
                    .fmt_pct(par$prop[par$mediator == "Whiteley8"]), "/"),
  check.names = FALSE, stringsAsFactors = FALSE
)
.write_sci(
  file.path(sr_tab, "Table 7. Indirect effect contrast SSD-12 vs Whiteley-8.xlsx"),
  "Table 7. Parallel competing mediation: indirect-effect contrast (H3).",
  t7b,
  footnotes = c(
    "Exposure = PHQ-15; outcome = WHO-DAS; parallel mediators = SSD-12 and Whiteley-8.",
    "Difference = ACME(SSD-12) - ACME(Whiteley-8) from the same bootstrap scheme (percentile 95% CI).",
    "H3: the two psychological paths may differ in mediated effect size.",
    sprintf("n boot for contrast = %s.", as.character(ct$n_boot[[1]]))
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table 8 + Figure 5 — WHO-DAS domains by class
# ═══════════════════════════════════════════════════════════════════════════
rows8 <- list()
for (nm in names(dom_vars)) {
  x <- d[[nm]]
  g <- d$Class
  ok <- is.finite(x) & !is.na(g)
  x <- x[ok]; g <- droplevels(g[ok])
  kw <- tryCatch(stats::kruskal.test(x ~ g), error = function(e) NULL)
  row <- data.frame(
    Domain = dom_vars[[nm]],
    Overall = sprintf("%s (%s)", .fmt_est(mean(x), 2), .fmt_est(stats::sd(x), 2)),
    stringsAsFactors = FALSE
  )
  for (cl in levels(d$Class)) {
    xi <- x[g == cl]
    row[[paste0(cl, " mean (SD)")]] <- sprintf("%s (%s)", .fmt_est(mean(xi), 2), .fmt_est(stats::sd(xi), 2))
  }
  row$`H (Kruskal)` <- if (!is.null(kw)) .fmt_est(unname(kw$statistic), 3) else .na_cell
  row$P <- if (!is.null(kw)) .fmt_p(kw$p.value) else .na_cell
  rows8[[length(rows8) + 1L]] <- row
}
t8 <- do.call(rbind, rows8)
.write_sci(
  file.path(sr_tab, "Table 8. WHO-DAS domain scores by LCA class.xlsx"),
  "Table 8. WHO-DAS 12 domain scores by latent class.",
  t8,
  footnotes = c(
    "Domains follow WHO-DAS 2.0 12-item pairing: Cognition (DAS1–2), Mobility (DAS3–4), Self-care (DAS5–6), Getting along (DAS7–8), Life activities (DAS9–10), Participation (DAS11–12).",
    dom_item_note,
    "Cells = mean (SD) of item-mean domain scores (0–4). P from Kruskal–Wallis across C1–C3."
  )
)

# Fig5 domain profile
long <- do.call(rbind, lapply(names(dom_vars), function(nm) {
  data.frame(
    Domain = factor(dom_vars[[nm]], levels = unname(dom_vars)),
    Class = d$Class,
    Score = d[[nm]],
    stringsAsFactors = FALSE
  )
}))
long <- long[is.finite(long$Score), ]
agg <- aggregate(Score ~ Domain + Class, data = long, FUN = mean)
p5 <- ggplot(agg, aes(Domain, Score, group = Class, colour = Class)) +
  geom_line(linewidth = 0.8) +
  geom_point(size = 2) +
  scale_colour_manual(values = c(C1 = "#2c7bb6", C2 = "#fdae61", C3 = "#d7191c"),
                      labels = paste0(names(class_lab), ": ", class_lab)) +
  labs(
    title = "Figure 5. WHO-DAS domain profiles by LCA class",
    x = NULL, y = "Domain mean score (0–4)", colour = NULL
  ) +
  theme_bw(base_family = "serif", base_size = 11) +
  theme(axis.text.x = element_text(angle = 25, hjust = 1), legend.position = "bottom")
.pipeline_pdf(file.path(sr_pdf, "Figure 5. WHO-DAS domain profiles by LCA class.pdf"), p5, 8.5, 5)
writeLines(c(
  "# Figure 5. WHO-DAS domain profiles by LCA class",
  "",
  "## 图面说明",
  "六条 WHO-DAS 维度均分按 LCA 三类折线：C1 最低、C3 最高，与总分梯度一致。",
  "",
  "## 分析上下文",
  "Domain means from paired DAS items; Kruskal–Wallis in Table 8."
), file.path(sr_md, "Figure 5. WHO-DAS domain profiles by LCA class.md"))

# ═══════════════════════════════════════════════════════════════════════════
# Table 9 — CFA discriminant (restore as main Table 9)
# ═══════════════════════════════════════════════════════════════════════════
cfa <- utils::read.csv(
  file.path(proj, "step06_sem_cfa_discriminant/Tables/Table_CFA_discriminant_fit.csv"),
  stringsAsFactors = FALSE
)
t9 <- data.frame(
  CFI = .fmt_est(cfa$CFI[[1]]),
  TLI = .fmt_est(cfa$TLI[[1]]),
  RMSEA = .fmt_est(cfa$RMSEA[[1]]),
  SRMR = .fmt_est(cfa$SRMR[[1]]),
  `phi (SSD-12, Whiteley)` = .fmt_est(cfa$phi_std[[1]]),
  `AVE SSD-12` = .fmt_est(cfa$AVE_A[[1]]),
  `AVE Whiteley` = .fmt_est(cfa$AVE_B[[1]]),
  `Fornell-Larcker pass` = as.character(cfa$fornell_larcker_pass[[1]]),
  n = as.character(cfa$n[[1]]),
  Estimator = as.character(cfa$estimator[[1]]),
  check.names = FALSE, stringsAsFactors = FALSE
)
.write_sci(
  file.path(sr_tab, "Table 9. CFA discriminant validity SSD-12 vs Whiteley.xlsx"),
  "Table 9. CFA discriminant validity of SSD-12 versus Whiteley-8.",
  t9,
  footnotes = c(
    "Two-factor CFA (lavaan). High standardized factor correlation indicates substantial conceptual overlap.",
    "Fornell–Larcker compares AVE with squared factor correlation.",
    "Measurement invariance / multi-group SEM were not fully identified in this outpatient sample beyond this discriminant CFA; see Methods."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Bootstrap helpers for mediation extensions
# ═══════════════════════════════════════════════════════════════════════════
.boot_med <- function(dd, x, m, y, cov_txt, cov_use, n_boot, seed) {
  set.seed(seed)
  n <- nrow(dd)
  acme <- ade <- tot <- numeric(n_boot)
  for (b in seq_len(n_boot)) {
    db <- dd[sample.int(n, n, replace = TRUE), , drop = FALSE]
    for (v in cov_use) if (is.factor(dd[[v]])) db[[v]] <- factor(db[[v]], levels = levels(dd[[v]]))
    keep <- c(x, y, m, cov_use)
    db <- db[stats::complete.cases(db[, keep, drop = FALSE]), , drop = FALSE]
    if (nrow(db) < 40L) { acme[b] <- ade[b] <- tot[b] <- NA_real_; next }
    mm <- tryCatch(stats::lm(stats::as.formula(paste0(m, " ~ ", x, cov_txt)), db), error = function(e) NULL)
    my <- tryCatch(stats::lm(stats::as.formula(paste0(y, " ~ ", x, " + ", m, cov_txt)), db), error = function(e) NULL)
    if (is.null(mm) || is.null(my)) { acme[b] <- ade[b] <- tot[b] <- NA_real_; next }
    a <- unname(stats::coef(mm)[x]); bc <- unname(stats::coef(my)[m]); cp <- unname(stats::coef(my)[x])
    acme[b] <- a * bc; ade[b] <- cp; tot[b] <- a * bc + cp
  }
  qci <- function(v) {
    vv <- v[is.finite(v)]
    c(est = mean(vv), lo = as.numeric(stats::quantile(vv, 0.025)),
      hi = as.numeric(stats::quantile(vv, 0.975)))
  }
  list(indirect = qci(acme), direct = qci(ade), total = qci(tot))
}
.row_effects <- function(label, ef) {
  mk <- function(kind, lab) {
    e <- ef[[kind]]
    data.frame(
      Model = label, Path = lab,
      Effect = .fmt_est(e[["est"]]),
      SE = .fmt_est(.se_ci(e[["lo"]], e[["hi"]])),
      LLCI = .fmt_est(e[["lo"]]), ULCI = .fmt_est(e[["hi"]]),
      `Effect size` = if (identical(kind, "total")) "/" else .fmt_pct(e[["est"]] / ef$total[["est"]]),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  rbind(mk("total", "Total"), mk("direct", "Direct"), mk("indirect", "Indirect"))
}

dd_all <- d[stats::complete.cases(d[, c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", cov_use), drop = FALSE]), ]

# ═══════════════════════════════════════════════════════════════════════════
# Table 10 — SSS-8 as exposure (parallel mediators SSD12 / Whiteley)
# ═══════════════════════════════════════════════════════════════════════════
message("Table 10 SSS-8 exposure boots=", n_boot)
rows10 <- list()
for (m in c("SSD12", "Whiteley8")) {
  ef <- .boot_med(dd_all, "SSS8", m, "WHODAS", cov_txt, cov_use, n_boot, seed = 2000L + match(m, c("SSD12", "Whiteley8")))
  tmp <- .row_effects(paste0("SSS-8 → ", if (m == "SSD12") "SSD-12" else "Whiteley-8", " → WHO-DAS"), ef)
  rows10[[length(rows10) + 1L]] <- tmp
}
t10 <- do.call(rbind, rows10)
.write_sci(
  file.path(sr_tab, "Table 10. Mediation with SSS-8 as exposure.xlsx"),
  "Table 10. Mediation pathways with SSS-8 as exposure (sensitivity to PHQ-15 primary).",
  t10,
  footnotes = c(
    "Same outcome (WHO-DAS) and mediators (SSD-12, Whiteley-8) as primary analysis; exposure replaced by SSS-8.",
    sprintf("Bootstrap B = %s; covariates identical to primary mediation.", n_boot)
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table 11 — sensitivity: + PHQ-9 / + GAD-7 covariates
# ═══════════════════════════════════════════════════════════════════════════
message("Table 11 sensitivity")
rows11 <- list()
for (spec in list(
  list(name = "Primary (demo only)", extra = character(0)),
  list(name = "Primary + PHQ-9", extra = "PHQ9"),
  list(name = "Primary + GAD-7", extra = "GAD7"),
  list(name = "Primary + PHQ-9 + GAD-7", extra = c("PHQ9", "GAD7"))
)) {
  cu <- c(cov_use, intersect(spec$extra, names(dd_all)))
  ct2 <- if (length(cu)) paste0(" + ", paste(cu, collapse = " + ")) else ""
  ef <- .boot_med(dd_all, "PHQ15", "SSD12", "WHODAS", ct2, cu, n_boot, seed = 3100L + nchar(spec$name))
  tmp <- .row_effects(spec$name, ef)
  # keep indirect row mainly but report all three
  rows11[[length(rows11) + 1L]] <- tmp
}
t11 <- do.call(rbind, rows11)
.write_sci(
  file.path(sr_tab, "Table 11. Sensitivity mediation adjusting depression anxiety.xlsx"),
  "Table 11. Sensitivity: PHQ-15 → SSD-12 → WHO-DAS with/without depression–anxiety covariates.",
  t11,
  footnotes = c(
    "Primary covariates = age, sex, education, marriage, income, livingsite.",
    "Additional adjustment for PHQ-9 and/or GAD-7 evaluates whether the cognitive mediation path persists after emotional covariates.",
    sprintf("Bootstrap B = %s.", n_boot)
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table 12 — moderated / stratified mediation (available moderators)
# ═══════════════════════════════════════════════════════════════════════════
message("Table 12 moderated/stratified")
.mod_bin <- function(v, lab_true, lab_false) {
  x <- d[[v]]
  if (is.null(x)) return(NULL)
  if (is.numeric(x)) {
    med <- stats::median(x, na.rm = TRUE)
    factor(ifelse(x >= med, lab_true, lab_false))
  } else {
    xc <- tolower(trimws(as.character(x)))
    out <- rep(NA_character_, length(xc))
    out[xc %in% c("yes", "1", "true")] <- lab_true
    out[xc %in% c("no", "0", "false")] <- lab_false
    factor(out, levels = c(lab_false, lab_true))
  }
}
mods <- list(
  Sex = factor(ifelse(tolower(as.character(d$sex)) == "female", "Female", "Male")),
  Pain_predominant = .mod_bin("pain_predominant", "Pain-predominant Yes", "No"),
  Persistent = .mod_bin("persistent", "Persistent Yes", "No"),
  SSD_diagnosis = .mod_bin("SSD", "SSD Yes", "SSD No"),
  PHQ9_high = {
    med <- stats::median(d$PHQ9, na.rm = TRUE)
    factor(ifelse(d$PHQ9 >= med, "PHQ-9 high", "PHQ-9 low"))
  },
  GAD7_high = {
    med <- stats::median(d$GAD7, na.rm = TRUE)
    factor(ifelse(d$GAD7 >= med, "GAD-7 high", "GAD-7 low"))
  }
)
.sig_ci <- function(lo, hi) {
  if (!is.finite(lo) || !is.finite(hi)) return("No")
  if (lo * hi > 0) "Yes" else "No"
}
rows12 <- list()
seed_i <- 4000L
for (mn in names(mods)) {
  fac <- mods[[mn]]
  if (is.null(fac) || all(is.na(fac))) next
  d$.mod <- fac
  drop_cov <- if (identical(mn, "Sex")) "sex" else character(0)
  cu12 <- setdiff(cov_use, drop_cov)
  ct12 <- if (length(cu12)) paste0(" + ", paste(cu12, collapse = " + ")) else ""
  for (lv in levels(droplevels(factor(fac)))) {
    sub <- d[!is.na(d$.mod) & as.character(d$.mod) == lv, , drop = FALSE]
    keep_cc <- c("PHQ15", "SSD12", "WHODAS", cu12)
    sub <- sub[stats::complete.cases(sub[, keep_cc, drop = FALSE]), ]
    if (nrow(sub) < 60L) {
      message("skip ", mn, " / ", lv, " n=", nrow(sub))
      next
    }
    seed_i <- seed_i + 1L
    message("  ", mn, " | ", lv, " n=", nrow(sub))
    ef <- .boot_med(sub, "PHQ15", "SSD12", "WHODAS", ct12, cu12, n_boot, seed = seed_i)
    e <- ef$indirect
    rows12[[length(rows12) + 1L]] <- data.frame(
      Moderator = mn,
      Level = lv,
      n = nrow(sub),
      ACME = .fmt_est(e[["est"]]),
      LLCI = .fmt_est(e[["lo"]]),
      ULCI = .fmt_est(e[["hi"]]),
      Sig = .sig_ci(e[["lo"]], e[["hi"]]),
      stringsAsFactors = FALSE
    )
  }
}
t12 <- do.call(rbind, rows12)
.write_sci(
  file.path(sr_tab, "Table 12. Stratified mediation by available moderators.xlsx"),
  "Table 12. Stratified PHQ-15 → SSD-12 → WHO-DAS indirect effects by available moderators.",
  t12,
  footnotes = c(
    "Data did not contain dedicated alexithymia / catastrophizing / childhood-trauma scales named in the 1021 plan; available clinical moderators were used instead (sex, pain-predominant, persistent course, SSD diagnosis, PHQ-9/GAD-7 median splits).",
    "Each row = bootstrap ACME within stratum (same covariates as primary).",
    "This is stratified mediation (effect heterogeneity), not a full product-term moderated-mediation SEM."
  )
)

# Figure 7 forest of stratified ACME
if (nrow(t12)) {
  t12p <- t12
  t12p$est <- as.numeric(t12$ACME)
  t12p$lo <- as.numeric(t12$LLCI)
  t12p$hi <- as.numeric(t12$ULCI)
  t12p$lab <- paste0(t12p$Moderator, ": ", t12p$Level, " (n=", t12p$n, ")")
  t12p$lab <- factor(t12p$lab, levels = rev(t12p$lab))
  p7 <- ggplot(t12p, aes(est, lab)) +
    geom_vline(xintercept = 0, linetype = 2, colour = "grey50") +
    geom_errorbarh(aes(xmin = lo, xmax = hi), height = 0.2) +
    geom_point(size = 2) +
    labs(title = "Figure 7. Stratified indirect effects (ACME)",
         x = "ACME (PHQ-15 → SSD-12 → WHO-DAS)", y = NULL) +
    theme_bw(base_family = "serif", base_size = 11)
  .pipeline_pdf(file.path(sr_pdf, "Figure 7. Stratified mediation ACME forest.pdf"), p7, 8, max(4, 0.35 * nrow(t12p) + 1.5))
  writeLines(c(
    "# Figure 7. Stratified mediation ACME forest",
    "",
    "## 图面说明",
    "各可用调节分层内 PHQ-15→SSD-12→WHO-DAS 间接效应及 95% bootstrap CI。",
    "",
    "## 分析上下文",
    "数值同源 Table 12。"
  ), file.path(sr_md, "Figure 7. Stratified mediation ACME forest.md"))
}

# ═══════════════════════════════════════════════════════════════════════════
# Table 13 — ROC (restore as main)
# ═══════════════════════════════════════════════════════════════════════════
roc <- utils::read.csv(
  file.path(proj, "step09_clinical_threshold_dca/Tables/Table_clinical_ROC.csv"),
  stringsAsFactors = FALSE
)
t13 <- data.frame(
  Predictor = roc$predictor,
  AUC = vapply(roc$AUC, .fmt_est, character(1)),
  `AUC lo` = vapply(roc$AUC_lo, .fmt_est, character(1)),
  `AUC hi` = vapply(roc$AUC_hi, .fmt_est, character(1)),
  `Youden cut` = vapply(roc$youden_cut, .fmt_est, character(1)),
  Sens = vapply(roc$sens, .fmt_est, character(1)),
  Spec = vapply(roc$spec, .fmt_est, character(1)),
  n = as.character(roc$n),
  check.names = FALSE, stringsAsFactors = FALSE
)
.write_sci(
  file.path(sr_tab, "Table 13. Clinical ROC for WHO-DAS median split.xlsx"),
  "Table 13. ROC of cognitive/symptom scores for WHO-DAS median-split classification.",
  t13,
  footnotes = c(
    "Binary label = WHO-DAS median split. AUC CI from pROC.",
    "Supports clinical thresholding for stratified intervention hypotheses (high cognitive bias vs high somatic load)."
  )
)

# Figure 6 DCA if CSV exists
dca <- tryCatch(
  utils::read.csv(file.path(proj, "step09_clinical_threshold_dca/Tables/Table_clinical_DCA.csv"),
                  stringsAsFactors = FALSE),
  error = function(e) NULL
)
if (!is.null(dca) && nrow(dca) > 2L) {
  # expect columns threshold, model, net_benefit-like
  cn <- names(dca)
  thr <- cn[grepl("thresh|pt", cn, ignore.case = TRUE)][1]
  nb <- cn[grepl("net|nb|benefit", cn, ignore.case = TRUE)][1]
  mod <- cn[grepl("model|pred|strategy|label", cn, ignore.case = TRUE)][1]
  if (!is.na(thr) && !is.na(nb)) {
    if (is.na(mod)) dca$.model <- "model" else dca$.model <- as.character(dca[[mod]])
    p6 <- ggplot(dca, aes(.data[[thr]], .data[[nb]], colour = .model, group = .model)) +
      geom_line() +
      labs(title = "Figure 6. Decision-curve analysis",
           x = "Threshold probability", y = "Net benefit", colour = NULL) +
      theme_bw(base_family = "serif", base_size = 11) +
      theme(legend.position = "bottom")
    .pipeline_pdf(file.path(sr_pdf, "Figure 6. Decision curve analysis.pdf"), p6, 8, 5)
    writeLines(c(
      "# Figure 6. Decision curve analysis",
      "",
      "## 图面说明",
      "WHO-DAS 中位二分标签下，各预测分数的决策曲线净获益。",
      "",
      "## 分析上下文",
      "同源 clinical_threshold_dca 块；与 Table 13 ROC 配套。"
    ), file.path(sr_md, "Figure 6. Decision curve analysis.md"))
  }
}

# ═══════════════════════════════════════════════════════════════════════════
# Table 14 — N12AA objective visit burden
# ═══════════════════════════════════════════════════════════════════════════
keep_lv <- c("0-2", "3-10", "11-20", "20+")
d0$N12_lab <- as.character(d0$N12AA)
d0$N12_lab[!(d0$N12_lab %in% keep_lv)] <- NA_character_
tab_n12 <- table(Class = paste0("C", d0$LCA_class), Visits = d0$N12_lab, useNA = "no")
tab_n12 <- tab_n12[, intersect(colnames(tab_n12), keep_lv), drop = FALSE]
chi <- tryCatch(stats::chisq.test(tab_n12), error = function(e) NULL)
rows14 <- list()
for (cl in rownames(tab_n12)) {
  ncl <- sum(tab_n12[cl, ])
  for (lv in colnames(tab_n12)) {
    n <- tab_n12[cl, lv]
    rows14[[length(rows14) + 1L]] <- data.frame(
      Class = cl,
      `Visits in past 12 months` = lv,
      n = as.character(n),
      `% within class` = .fmt_est(100 * n / max(ncl, 1), 2),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
}
t14 <- do.call(rbind, rows14)
# association WHODAS / PHQ15 with ordinal visits
ord <- factor(d0$N12_lab, levels = keep_lv, ordered = TRUE)
kw_w <- tryCatch(stats::kruskal.test(as.numeric(d0$WHODAS) ~ ord), error = function(e) NULL)
kw_p <- tryCatch(stats::kruskal.test(as.numeric(d0$PHQ15) ~ ord), error = function(e) NULL)
.write_sci(
  file.path(sr_tab, "Table 14. Objective visit burden N12AA by LCA class.xlsx"),
  "Table 14. Self-reported outpatient visit burden (N12AA) by LCA class.",
  t14,
  footnotes = c(
    "N12AA: number of medical visits in the past 12 months due to somatic complaints (categorical).",
    if (!is.null(chi)) sprintf("Chi-square test of Class x Visits: P = %s.", .fmt_p(chi$p.value)) else "Chi-square not available.",
    if (!is.null(kw_w)) sprintf("Kruskal–Wallis WHO-DAS across visit categories: P = %s.", .fmt_p(kw_w$p.value)) else "",
    if (!is.null(kw_p)) sprintf("Kruskal–Wallis PHQ-15 across visit categories: P = %s.", .fmt_p(kw_p$p.value)) else "",
    "Supports dual-outcome framing: subjective disability (WHO-DAS) + objective care utilization (visits)."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table 15 — reverse / competing models
# ═══════════════════════════════════════════════════════════════════════════
message("Table 15 reverse/competing")
rows15 <- list()
specs15 <- list(
  list(name = "Primary: PHQ-15 → SSD-12 → WHO-DAS", x = "PHQ15", m = "SSD12", y = "WHODAS"),
  list(name = "Competing: PHQ-15 → WHO-DAS → SSD-12", x = "PHQ15", m = "WHODAS", y = "SSD12"),
  list(name = "Reverse: WHO-DAS → SSD-12 → PHQ-15", x = "WHODAS", m = "SSD12", y = "PHQ15"),
  list(name = "Primary Whiteley: PHQ-15 → Whiteley-8 → WHO-DAS", x = "PHQ15", m = "Whiteley8", y = "WHODAS")
)
for (j in seq_along(specs15)) {
  sp <- specs15[[j]]
  ef <- .boot_med(dd_all, sp$x, sp$m, sp$y, cov_txt, cov_use, n_boot, seed = 5000L + j)
  e <- ef$indirect
  rows15[[length(rows15) + 1L]] <- data.frame(
    Model = sp$name,
    ACME = .fmt_est(e[["est"]]),
    LLCI = .fmt_est(e[["lo"]]),
    ULCI = .fmt_est(e[["hi"]]),
    Sig = .sig_ci(e[["lo"]], e[["hi"]]),
    stringsAsFactors = FALSE
  )
}
t15 <- do.call(rbind, rows15)
.write_sci(
  file.path(sr_tab, "Table 15. Competing and reverse mediation models.xlsx"),
  "Table 15. Competing and reverse mediation models (bootstrap ACME).",
  t15,
  footnotes = c(
    "Primary cognitive-path model versus outcome-as-mediator and reverse-direction models.",
    "Cross-sectional data cannot establish temporal order; competing models are reported for robustness, not causal adjudication.",
    sprintf("Bootstrap B = %s; same demographic covariates.", n_boot)
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table 16 — correlation FDR (multiplicity note)
# ═══════════════════════════════════════════════════════════════════════════
vars_fdr <- c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7")
labs_fdr <- c("PHQ-15", "SSS-8", "SSD-12", "Whiteley-8", "WHO-DAS", "PHQ-9", "GAD-7")
M <- stats::cor(dd_all[, vars_fdr], use = "pairwise.complete.obs", method = "spearman")
P <- matrix(NA_real_, length(vars_fdr), length(vars_fdr), dimnames = list(labs_fdr, labs_fdr))
for (a in seq_along(vars_fdr)) for (b in seq_along(vars_fdr)) {
  if (a >= b) next
  ct2 <- suppressWarnings(stats::cor.test(dd_all[[vars_fdr[a]]], dd_all[[vars_fdr[b]]], method = "spearman", exact = FALSE))
  P[a, b] <- P[b, a] <- ct2$p.value
}
pvec <- P[upper.tri(P)]
padj <- stats::p.adjust(pvec, method = "BH")
Padj <- P
Padj[upper.tri(Padj)] <- padj
Padj[lower.tri(Padj)] <- t(Padj)[lower.tri(Padj)]
rows16 <- list()
for (a in seq_along(vars_fdr)) for (b in seq_along(vars_fdr)) if (a < b) {
  rows16[[length(rows16) + 1L]] <- data.frame(
    Var1 = labs_fdr[a], Var2 = labs_fdr[b],
    rho = .fmt_est(M[a, b]),
    P = .fmt_p(P[a, b]),
    `P FDR (BH)` = .fmt_p(Padj[a, b]),
    check.names = FALSE, stringsAsFactors = FALSE
  )
}
t16 <- do.call(rbind, rows16)
.write_sci(
  file.path(sr_tab, "Table 16. Spearman correlations with FDR adjustment.xlsx"),
  "Table 16. Pairwise Spearman correlations among key scores with Benjamini–Hochberg FDR.",
  t16,
  footnotes = c(
    "Complements Table 5; FDR applied to all unique pairs among the seven scale totals.",
    "Primary analyses remain complete-case (no FIML/MICE in the mediation bootstrap models)."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Methods append (do not rewrite numbers of existing tables/figs)
# ═══════════════════════════════════════════════════════════════════════════
methods_path <- file.path(sr, "Methods_statistical_analysis.md")
extra <- c(
  "",
  "## Extensions aligned with the 1021 analysis plan (Tables 7–16 / Figures 5–7)",
  "",
  "### Theoretical framing (Common-Sense Model)",
  "Analyses are interpreted under a Common-Sense / symptom-perception framework: somatic symptom burden (PHQ-15/SSS-8) may impair functioning directly and/or via illness-related cognitive–affective representations (SSD-12, Whiteley-8). The scientific claim emphasizes **which cognitive path dominates** and **for whom** (class and moderator heterogeneity), not merely that mediation exists.",
  "",
  "### Parallel competing mediation (H3)",
  "Table 7 reports the bootstrap contrast ACME(SSD-12) − ACME(Whiteley-8) under identical covariates, addressing whether disease anxiety / over-attention differs from hypochondriacal concern in mediating disability.",
  "",
  "### Functional heterogeneity",
  "Beyond WHO-DAS total scores, Table 8 / Figure 5 summarize the six WHO-DAS 12 domains by LCA class. Table 14 adds an objective utilization marker (N12AA past-year visits).",
  "",
  "### Measurement and robustness",
  "Table 9 restores the SSD-12 vs Whiteley CFA discriminant check. Table 15 reports competing/reverse path models. Table 11 evaluates sensitivity to depression/anxiety covariates. Table 16 applies BH-FDR to pairwise scale correlations. Primary mediation remains complete-case; FIML/MICE was not used for the bootstrap product-of-coefficients models.",
  "",
  "### Moderated / stratified mediation",
  "Named instruments for alexithymia, catastrophizing, and childhood trauma were unavailable in the analytic file. Stratified ACME (Table 12 / Figure 7) used available modifiers: sex, pain-predominant, persistent course, SSD diagnosis, and PHQ-9/GAD-7 median splits.",
  "",
  "### Clinical translation",
  "Table 13 (ROC) and Figure 6 (DCA, if available) support threshold-oriented reporting. Stratified intervention hypotheses: (i) high somatic load with relatively lower cognitive bias → prioritize symptom management; (ii) high SSD-12/Whiteley cognitive bias → prioritize CBT / attentional / illness-anxiety interventions; (iii) LCA high-disability class (C3) warrants intensified multimodal care.",
  "",
  "### SSS-8 exposure sensitivity",
  "Table 10 repeats mediation with SSS-8 as exposure to address the plan’s dual somatic severity markers alongside PHQ-15.",
  ""
)
if (file.exists(methods_path)) {
  old <- readLines(methods_path, warn = FALSE)
  # drop previous extension block if re-run
  cut <- grep("^## Extensions aligned with the 1021", old)
  if (length(cut)) old <- old[seq_len(cut[[1]] - 1L)]
  writeLines(c(old, extra), methods_path)
} else {
  writeLines(c("# Statistical analysis", extra), methods_path)
}
message("Methods appended")

message("DONE extension. New tables/figs:")
print(setdiff(list.files(sr_tab, pattern = "\\.xlsx$"), .protect))
print(setdiff(list.files(sr_pdf, pattern = "\\.pdf$"), .protect))
