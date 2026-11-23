#!/usr/bin/env Rscript
# Doable 1021 gaps → SUPPLEMENTARY only. Do NOT touch Table 1–16 / Figure 1–7.

suppressPackageStartupMessages({
  library(openxlsx)
  library(ggplot2)
  library(lavaan)
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
.sig_ci <- function(lo, hi) {
  if (!is.finite(lo) || !is.finite(hi)) return("No")
  if (lo * hi > 0) "Yes" else "No"
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
n_boot <- if (!is.na(iB) && iB < length(args)) as.integer(args[[iB + 1L]]) else 1000L

sr <- file.path(proj, "summary_results")
sr_tab <- file.path(sr, "Tables")
sr_pdf <- file.path(sr, "Figures", "pdf")
sr_md <- file.path(sr, "Figures", "image_information")
dir.create(sr_tab, recursive = TRUE, showWarnings = FALSE)
dir.create(sr_pdf, recursive = TRUE, showWarnings = FALSE)
dir.create(sr_md, recursive = TRUE, showWarnings = FALSE)

.protect <- c(
  list.files(sr_tab, pattern = "^Table [0-9]"),
  list.files(sr_pdf, pattern = "^Figure [0-9]")
)
message("protect main: ", length(.protect), " files")

.write_sci <- function(path, title, df, footnotes = NULL) {
  bn <- basename(path)
  if (bn %in% .protect) stop("refusing overwrite main: ", bn)
  if (!grepl("^Table S", bn)) stop("supplementary tables must be Table S*: ", bn)
  sci_xlsx_single_header_booktabs(
    filepath = path, title = title, df_body = df,
    sheet = "Sheet1", footnotes = footnotes, blank_na_cells = TRUE
  )
  py <- Sys.which("python3")
  script <- file.path(root, "python/pub_xlsx_enforce_three_line.py")
  if (nzchar(py) && file.exists(script)) {
    invisible(system2(py, shQuote(c(script, path)), stdout = TRUE, stderr = TRUE))
  }
  message("wrote ", bn)
}

.pipeline_pdf <- function(file, plot, width = 8, height = 5) {
  bn <- basename(file)
  if (bn %in% .protect) stop("refusing overwrite main fig: ", bn)
  if (!grepl("^Figure S", bn)) stop("supplementary figs must be Figure S*: ", bn)
  grDevices::pdf(file, width = width, height = height, useDingbats = FALSE)
  print(plot)
  grDevices::dev.off()
  message("wrote ", bn)
}

ck <- readRDS(file.path(proj, "checkpoints/step05_baseline_multiclass.rds"))
d0 <- ck$ctx$data$cleaned
d0 <- d0[!is.na(d0$LCA_class), , drop = FALSE]
d0$Class <- factor(paste0("C", as.integer(d0$LCA_class)), levels = c("C1", "C2", "C3"))

ssd_items <- paste0("SSD12", c(1:9, 10:12))
w_items <- c("WHITELEY", paste0("WHITELE", 1:7))
stopifnot(all(ssd_items %in% names(d0)), all(w_items %in% names(d0)))

# numeric scales + domains
for (v in c("PHQ15", "SSS8", "SSD12", "Whiteley8", "WHODAS", "PHQ9", "GAD7", "AA6", ssd_items, w_items)) {
  if (v %in% names(d0)) d0[[v]] <- suppressWarnings(as.numeric(d0[[v]]))
}
.domain_mean <- function(dd, items) {
  cols <- intersect(items, names(dd))
  if (!length(cols)) return(rep(NA_real_, nrow(dd)))
  rowMeans(dd[, cols, drop = FALSE], na.rm = TRUE)
}
d0$DAS_Cognition <- .domain_mean(d0, c("DAS1", "DAS2"))
d0$DAS_Mobility <- .domain_mean(d0, c("DAS3", "DAS4"))
d0$DAS_SelfCare <- .domain_mean(d0, c("DAS5", "DAS6"))
d0$DAS_GettingAlong <- .domain_mean(d0, c("DAS7", "DAS8"))
d0$DAS_LifeActivities <- .domain_mean(d0, c("DAS9", "DAS10"))
d0$DAS_Participation <- .domain_mean(d0, c("DAS11", "DAS12"))
dom_vars <- c(
  DAS_Cognition = "Cognition",
  DAS_Mobility = "Mobility",
  DAS_SelfCare = "Self-care",
  DAS_GettingAlong = "Getting along",
  DAS_LifeActivities = "Life activities",
  DAS_Participation = "Participation"
)

# covariates
covs0 <- c("age", "sex", "education", "marriage", "income", "livingsite")
.prep_factor <- function(x, min_n = 15L) {
  if (is.numeric(x)) return(x)
  fv <- factor(x)
  tabn <- table(fv)
  rare <- names(tabn)[tabn < min_n]
  if (length(rare)) {
    xv <- as.character(fv)
    xv[xv %in% rare] <- "Other"
    fv <- factor(xv)
  }
  droplevels(fv)
}
for (v in covs0) if (v %in% names(d0) && v != "age") d0[[v]] <- .prep_factor(d0[[v]])
if ("age" %in% names(d0)) d0$age <- suppressWarnings(as.numeric(d0$age))
cov_use <- intersect(covs0, names(d0))

# objective outcomes
keep_lv <- c("0-2", "3-10", "11-20", "20+")
d0$N12_lab <- as.character(d0$N12AA)
d0$N12_lab[!(d0$N12_lab %in% keep_lv)] <- NA_character_
d0$N12_ord <- as.numeric(factor(d0$N12_lab, levels = keep_lv, ordered = TRUE))
d0$N12_high <- as.integer(d0$N12_lab %in% c("11-20", "20+"))
occ <- tolower(trimws(as.character(d0$occupation)))
d0$not_employed <- as.integer(occ %in% c("unemployed", "housewife", "retire", "student", "others"))
d0$unemployed_only <- as.integer(occ %in% "unemployed")

# binary moderators
.yesno <- function(x) {
  xc <- tolower(trimws(as.character(x)))
  out <- rep(NA_real_, length(xc))
  out[xc %in% c("yes", "1", "true")] <- 1
  out[xc %in% c("no", "0", "false")] <- 0
  out
}
d0$W_sex_female <- as.integer(tolower(as.character(d0$sex)) == "female")
d0$W_pain <- .yesno(d0$pain_predominant)
d0$W_persist <- .yesno(d0$persistent)
d0$W_ssd <- .yesno(d0$SSD)
d0$W_phq9 <- as.integer(d0$PHQ9 >= stats::median(d0$PHQ9, na.rm = TRUE))
d0$W_gad7 <- as.integer(d0$GAD7 >= stats::median(d0$GAD7, na.rm = TRUE))
d0$W_duration <- d0$AA6

cfa_model <- paste0(
  "SSD12 =~ ", paste(ssd_items, collapse = " + "), "\n",
  "Whiteley =~ ", paste(w_items, collapse = " + ")
)

# ═══════════════════════════════════════════════════════════════════════════
# Table S1 — measurement invariance (sex, SSD)
# ═══════════════════════════════════════════════════════════════════════════
message("Table S1 measurement invariance")
.clean_group <- function(x) {
  xc <- tolower(trimws(as.character(x)))
  xc[xc %in% c("", "na", "nan")] <- NA_character_
  factor(xc)
}
.invariance_table <- function(group_var, group_lab, min_n = 120L) {
  dd <- d0[, c(ssd_items, w_items, group_var), drop = FALSE]
  dd[[group_var]] <- .clean_group(dd[[group_var]])
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  g <- droplevels(dd[[group_var]])
  if (nlevels(g) < 2L) return(NULL)
  tabg <- table(g)
  if (any(tabg < min_n)) {
    message("  skip ", group_lab, " small cells: ", paste(names(tabg), tabg, collapse = "; "))
    return(NULL)
  }
  dd$.g <- g
  fit_cfg <- tryCatch(
    lavaan::cfa(cfa_model, data = dd, group = ".g", std.lv = TRUE, estimator = "MLR"),
    error = function(e) NULL
  )
  fit_met <- tryCatch(
    lavaan::cfa(cfa_model, data = dd, group = ".g", std.lv = TRUE, estimator = "MLR",
                group.equal = "loadings"),
    error = function(e) NULL
  )
  fit_sca <- tryCatch(
    lavaan::cfa(cfa_model, data = dd, group = ".g", std.lv = TRUE, estimator = "MLR",
                group.equal = c("loadings", "intercepts")),
    error = function(e) NULL
  )
  if (is.null(fit_cfg) || is.null(fit_met) || is.null(fit_sca)) return(NULL)
  mk <- function(fit, model) {
    fm <- tryCatch(lavaan::fitMeasures(fit, c("chisq", "df", "cfi", "tli", "rmsea", "srmr")),
                   error = function(e) NULL)
    if (is.null(fm)) return(NULL)
    data.frame(
      Grouping = group_lab,
      Model = model,
      n = nrow(dd),
      `Group n` = paste(paste0(names(tabg), "=", as.integer(tabg)), collapse = "; "),
      ChiSq = .fmt_est(unname(fm[["chisq"]]), 2),
      df = as.character(as.integer(unname(fm[["df"]]))),
      CFI = .fmt_est(unname(fm[["cfi"]])),
      TLI = .fmt_est(unname(fm[["tli"]])),
      RMSEA = .fmt_est(unname(fm[["rmsea"]])),
      SRMR = .fmt_est(unname(fm[["srmr"]])),
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  an_cm <- tryCatch(lavaan::anova(fit_cfg, fit_met), error = function(e) NULL)
  an_ms <- tryCatch(lavaan::anova(fit_met, fit_sca), error = function(e) NULL)
  rows <- rbind(mk(fit_cfg, "Configural"), mk(fit_met, "Metric"), mk(fit_sca, "Scalar"))
  dCFI_m <- unname(lavaan::fitMeasures(fit_met, "cfi") - lavaan::fitMeasures(fit_cfg, "cfi"))
  dCFI_s <- unname(lavaan::fitMeasures(fit_sca, "cfi") - lavaan::fitMeasures(fit_met, "cfi"))
  attr(rows, "notes") <- c(
    sprintf("Metric vs configural Delta CFI = %s; anova P = %s.",
            .fmt_est(dCFI_m), if (!is.null(an_cm)) .fmt_p(an_cm$`Pr(>Chisq)`[2]) else .na_cell),
    sprintf("Scalar vs metric Delta CFI = %s; anova P = %s.",
            .fmt_est(dCFI_s), if (!is.null(an_ms)) .fmt_p(an_ms$`Pr(>Chisq)`[2]) else .na_cell),
    "|Delta CFI| < 0.01 often treated as approximate invariance support (rule of thumb)."
  )
  rows
}
inv_sex <- .invariance_table("sex", "Sex (female vs male)", 120L)
inv_ssd <- .invariance_table("SSD", "SSD diagnosis (yes vs no)", 120L)
# pain Yes too small for full CFA; still try with lower min and report if fails
inv_pain <- .invariance_table("pain_predominant", "Pain-predominant (yes vs no)", 40L)
tS1 <- do.call(rbind, Filter(Negate(is.null), list(inv_sex, inv_ssd, inv_pain)))
notes_s1 <- unique(unlist(lapply(list(inv_sex, inv_ssd, inv_pain), function(x) attr(x, "notes"))))
.write_sci(
  file.path(sr_tab, "Table S1. Measurement invariance CFA SSD-12 Whiteley.xlsx"),
  "Table S1. Measurement invariance of the two-factor CFA (SSD-12, Whiteley-8 items).",
  tS1,
  footnotes = c(
    "Supplementary. Main-text Table 9 reports overall discriminant CFA only.",
    "Estimator = MLR; std.lv = TRUE. Persistent course was not tested (one cell n < 40).",
    notes_s1
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table S2 — multi-group path SEM (sex, SSD)
# ═══════════════════════════════════════════════════════════════════════════
message("Table S2 multi-group path SEM")
.path_sem <- function(group_var, group_lab, min_n = 120L) {
  need <- c("PHQ15", "SSD12", "Whiteley8", "WHODAS", group_var, cov_use)
  dd <- d0[, intersect(need, names(d0)), drop = FALSE]
  dd[[group_var]] <- .clean_group(dd[[group_var]])
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  g <- droplevels(dd[[group_var]])
  tabg <- table(g)
  if (nlevels(g) < 2L || any(tabg < min_n)) return(NULL)
  dd$.g <- g
  # demean continuous cov within group not needed for comparison of a*b
  cov_txt <- if (length(intersect(cov_use, names(dd)))) {
    paste(setdiff(intersect(cov_use, names(dd)), group_var), collapse = " + ")
  } else ""
  # drop sex if grouping by sex
  if (identical(group_var, "sex")) {
    cov_txt <- paste(setdiff(strsplit(cov_txt, " \\+ ")[[1]], "sex"), collapse = " + ")
  }
  cov_part <- if (nzchar(cov_txt)) paste0(" + ", cov_txt) else ""
  model <- paste0(
    "SSD12 ~ a1*PHQ15", cov_part, "\n",
    "Whiteley8 ~ a2*PHQ15", cov_part, "\n",
    "WHODAS ~ b1*SSD12 + b2*Whiteley8 + cp*PHQ15", cov_part, "\n",
    "ind_ssd := a1*b1\n",
    "ind_w := a2*b2\n",
    "diff := ind_ssd - ind_w\n"
  )
  fit_free <- tryCatch(
    lavaan::sem(model, data = dd, group = ".g", estimator = "MLR"),
    error = function(e) { message(e$message); NULL }
  )
  fit_eq <- tryCatch(
    lavaan::sem(model, data = dd, group = ".g", estimator = "MLR",
                group.equal = c("regressions")),
    error = function(e) NULL
  )
  if (is.null(fit_free)) return(NULL)
  pe <- lavaan::parameterEstimates(fit_free, ci = TRUE)
  pe <- pe[pe$op == ":=" & pe$lhs %in% c("ind_ssd", "ind_w", "diff"), , drop = FALSE]
  rows <- data.frame(
    Grouping = group_lab,
    Group = pe$group,
    Path = pe$lhs,
    Estimate = vapply(pe$est, .fmt_est, character(1)),
    SE = vapply(pe$se, .fmt_est, character(1)),
    LLCI = vapply(pe$ci.lower, .fmt_est, character(1)),
    ULCI = vapply(pe$ci.upper, .fmt_est, character(1)),
    P = vapply(pe$pvalue, .fmt_p, character(1)),
    stringsAsFactors = FALSE
  )
  # map group index to label
  glab <- levels(dd$.g)
  rows$Group <- ifelse(is.finite(rows$Group), glab[as.integer(rows$Group)], as.character(rows$Group))
  if (!is.null(fit_eq)) {
    an <- tryCatch(lavaan::anova(fit_free, fit_eq), error = function(e) NULL)
    attr(rows, "eq_note") <- if (!is.null(an)) {
      sprintf("Equal-regression vs free multi-group SEM: P = %s.", .fmt_p(an$`Pr(>Chisq)`[2]))
    } else "Equal-regression comparison unavailable."
  }
  rows
}
mg_sex <- .path_sem("sex", "Sex")
mg_ssd <- .path_sem("SSD", "SSD diagnosis")
tS2 <- do.call(rbind, Filter(Negate(is.null), list(mg_sex, mg_ssd)))
eq_notes <- unique(unlist(lapply(list(mg_sex, mg_ssd), function(x) attr(x, "eq_note"))))
.write_sci(
  file.path(sr_tab, "Table S2. Multi-group path SEM indirect effects.xlsx"),
  "Table S2. Multi-group path SEM: PHQ-15 to WHO-DAS via SSD-12 and Whiteley-8.",
  tS2,
  footnotes = c(
    "Supplementary. Path model on scale totals (not latent items) with demographic covariates.",
    "ind_ssd = a1*b1; ind_w = a2*b2; diff = ind_ssd - ind_w.",
    eq_notes,
    "Pain-predominant / persistent multi-group SEM omitted (sparse cells)."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table S3 — formal moderated mediation (index of moderated mediation)
# ═══════════════════════════════════════════════════════════════════════════
message("Table S3 formal moderated mediation")
.boot_imm <- function(dd, x, m, y, w, cov_use, n_boot, seed) {
  # first-stage moderation: M ~ X + W + XW + cov; Y ~ X + M + W + cov (partial)
  set.seed(seed)
  n <- nrow(dd)
  imm <- acme0 <- acme1 <- numeric(n_boot)
  for (b in seq_len(n_boot)) {
    db <- dd[sample.int(n, n, replace = TRUE), , drop = FALSE]
    for (v in cov_use) if (is.factor(dd[[v]])) db[[v]] <- factor(db[[v]], levels = levels(dd[[v]]))
    db$XW <- db[[x]] * db[[w]]
    cov_txt <- if (length(cov_use)) paste0(" + ", paste(cov_use, collapse = " + ")) else ""
    keep <- c(x, m, y, w, "XW", cov_use)
    db <- db[stats::complete.cases(db[, keep, drop = FALSE]), , drop = FALSE]
    if (nrow(db) < 50L) { imm[b] <- acme0[b] <- acme1[b] <- NA_real_; next }
    mm <- tryCatch(stats::lm(stats::as.formula(paste0(m, " ~ ", x, " + ", w, " + XW", cov_txt)), db),
                   error = function(e) NULL)
    my <- tryCatch(stats::lm(stats::as.formula(paste0(y, " ~ ", x, " + ", m, " + ", w, cov_txt)), db),
                   error = function(e) NULL)
    if (is.null(mm) || is.null(my)) { imm[b] <- acme0[b] <- acme1[b] <- NA_real_; next }
    a0 <- unname(stats::coef(mm)[x])
    a_int <- unname(stats::coef(mm)["XW"])
    b1 <- unname(stats::coef(my)[m])
    if (!all(is.finite(c(a0, a_int, b1)))) { imm[b] <- acme0[b] <- acme1[b] <- NA_real_; next }
    imm[b] <- a_int * b1
    acme0[b] <- (a0 + a_int * 0) * b1
    acme1[b] <- (a0 + a_int * 1) * b1
  }
  qci <- function(v) {
    vv <- v[is.finite(v)]
    if (!length(vv)) return(c(est = NA_real_, lo = NA_real_, hi = NA_real_))
    c(est = mean(vv), lo = as.numeric(stats::quantile(vv, 0.025)),
      hi = as.numeric(stats::quantile(vv, 0.975)))
  }
  list(imm = qci(imm), acme_w0 = qci(acme0), acme_w1 = qci(acme1))
}

mod_specs <- list(
  list(name = "Sex (female=1)", w = "W_sex_female", drop = "sex"),
  list(name = "Pain-predominant", w = "W_pain", drop = character(0)),
  list(name = "Persistent course", w = "W_persist", drop = character(0)),
  list(name = "SSD diagnosis", w = "W_ssd", drop = character(0)),
  list(name = "PHQ-9 median-high", w = "W_phq9", drop = character(0)),
  list(name = "GAD-7 median-high", w = "W_gad7", drop = character(0))
)
rows_s3 <- list()
seed_i <- 7000L
for (sp in mod_specs) {
  cu <- setdiff(cov_use, sp$drop)
  need <- unique(c("PHQ15", "SSD12", "WHODAS", sp$w, cu))
  dd <- d0[, need, drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 120L || length(unique(dd[[sp$w]])) < 2L) {
    message("skip IMM ", sp$name, " n=", nrow(dd))
    next
  }
  # require both levels reasonably present
  tb <- table(dd[[sp$w]])
  if (any(tb < 40L)) {
    message("skip IMM sparse ", sp$name, " ", paste(tb, collapse = "/"))
    next
  }
  seed_i <- seed_i + 1L
  message("  IMM ", sp$name, " n=", nrow(dd))
  ef <- .boot_imm(dd, "PHQ15", "SSD12", "WHODAS", sp$w, cu, n_boot, seed_i)
  mk <- function(path, e) {
    data.frame(
      Moderator = sp$name, Path = path,
      Estimate = .fmt_est(e[["est"]]),
      LLCI = .fmt_est(e[["lo"]]), ULCI = .fmt_est(e[["hi"]]),
      Sig = .sig_ci(e[["lo"]], e[["hi"]]),
      n = nrow(dd),
      stringsAsFactors = FALSE
    )
  }
  rows_s3[[length(rows_s3) + 1L]] <- rbind(
    mk("Index of moderated mediation (a_XW * b)", ef$imm),
    mk("ACME at W=0", ef$acme_w0),
    mk("ACME at W=1", ef$acme_w1)
  )
}
tS3 <- do.call(rbind, rows_s3)
.write_sci(
  file.path(sr_tab, "Table S3. Formal moderated mediation index.xlsx"),
  "Table S3. Formal moderated mediation (first-stage) for PHQ-15 → SSD-12 → WHO-DAS.",
  tS3,
  footnotes = c(
    "Supplementary. Index of moderated mediation = a_XW * b from bootstrap product-of-coefficients.",
    "Model: M ~ X + W + X*W + cov; Y ~ X + M + W + cov. Binary W coded 0/1.",
    "Alexithymia / catastrophizing / childhood trauma instruments were unavailable.",
    sprintf("Bootstrap B = %s.", n_boot)
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table S4 — FIML path SEM + MI sensitivity
# ═══════════════════════════════════════════════════════════════════════════
message("Table S4 FIML and MI")
need_fiml <- c("PHQ15", "SSD12", "Whiteley8", "WHODAS", cov_use)
dd_f <- d0[, intersect(need_fiml, names(d0)), drop = FALSE]
# factor to dummy for lavaan FIML simplicity: use numeric age + sex female only + others as numeric if possible
dd_f$sex_f <- as.integer(tolower(as.character(d0$sex[match(rownames(dd_f), rownames(d0))])) == "female")
# rebuild from d0 directly
dd_f <- d0[, c("PHQ15", "SSD12", "Whiteley8", "WHODAS", "age"), drop = FALSE]
dd_f$sex_f <- d0$W_sex_female
model_f <- "
SSD12 ~ a1*PHQ15 + age + sex_f
Whiteley8 ~ a2*PHQ15 + age + sex_f
WHODAS ~ b1*SSD12 + b2*Whiteley8 + cp*PHQ15 + age + sex_f
ind_ssd := a1*b1
ind_w := a2*b2
diff := ind_ssd - ind_w
"
fit_cc <- lavaan::sem(model_f, data = dd_f[stats::complete.cases(dd_f), ], estimator = "MLR")
fit_fiml <- lavaan::sem(model_f, data = dd_f, missing = "fiml", estimator = "MLR")
.pe_row <- function(fit, method) {
  pe <- lavaan::parameterEstimates(fit, ci = TRUE)
  pe <- pe[pe$op == ":=" & pe$lhs %in% c("ind_ssd", "ind_w", "diff"), ]
  data.frame(
    Method = method,
    Path = pe$lhs,
    Estimate = vapply(pe$est, .fmt_est, character(1)),
    SE = vapply(pe$se, .fmt_est, character(1)),
    LLCI = vapply(pe$ci.lower, .fmt_est, character(1)),
    ULCI = vapply(pe$ci.upper, .fmt_est, character(1)),
    P = vapply(pe$pvalue, .fmt_p, character(1)),
    n = as.character(lavaan::nobs(fit)),
    stringsAsFactors = FALSE
  )
}
rows_s4 <- rbind(
  .pe_row(fit_cc, "Complete-case MLR"),
  .pe_row(fit_fiml, "FIML (lavaan missing=fiml)")
)

# mice m=5 on scale totals + age + sex, then pool a*b via Rubin on bootstrap means of each m
if (requireNamespace("mice", quietly = TRUE)) {
  set.seed(42)
  mi_vars <- c("PHQ15", "SSD12", "Whiteley8", "WHODAS", "age", "sex_f")
  dd_mi <- dd_f[, mi_vars, drop = FALSE]
  imp <- mice::mice(dd_mi, m = 5L, maxit = 10L, printFlag = FALSE, seed = 42)
  est_list <- list()
  for (k in 1:5) {
    dk <- mice::complete(imp, k)
    fk <- lavaan::sem(model_f, data = dk, estimator = "MLR")
    pe <- lavaan::parameterEstimates(fk)
    pe <- pe[pe$op == ":=" & pe$lhs %in% c("ind_ssd", "ind_w", "diff"), c("lhs", "est", "se")]
    pe$m <- k
    est_list[[k]] <- pe
  }
  tall <- do.call(rbind, est_list)
  for (path in c("ind_ssd", "ind_w", "diff")) {
    sub <- tall[tall$lhs == path, ]
    # Rubin
    Q <- mean(sub$est)
    U <- mean(sub$se^2)
    B <- stats::var(sub$est)
    Tvar <- U + (1 + 1 / 5) * B
    se <- sqrt(Tvar)
    # t approx df
    df <- if (B < 1e-12) Inf else (5 - 1) * (1 + U / ((1 + 1 / 5) * B))^2
    tcrit <- if (is.finite(df)) stats::qt(0.975, df) else 1.959964
    lo <- Q - tcrit * se; hi <- Q + tcrit * se
    z <- Q / se
    p <- if (is.finite(df)) 2 * stats::pt(-abs(z), df) else 2 * stats::pnorm(-abs(z))
    rows_s4 <- rbind(rows_s4, data.frame(
      Method = "MICE m=5 + Rubin (path SEM)",
      Path = path,
      Estimate = .fmt_est(Q), SE = .fmt_est(se),
      LLCI = .fmt_est(lo), ULCI = .fmt_est(hi),
      P = .fmt_p(p), n = as.character(nrow(dd_f)),
      stringsAsFactors = FALSE
    ))
  }
}
.write_sci(
  file.path(sr_tab, "Table S4. FIML and MI sensitivity for parallel mediation.xlsx"),
  "Table S4. Sensitivity of parallel indirect effects under FIML and multiple imputation.",
  rows_s4,
  footnotes = c(
    "Supplementary. Path SEM covariates simplified to age + sex for FIML/MI comparability.",
    "FIML uses lavaan missing='fiml'. MI: mice m=5, maxit=10, then Rubin pooling of defined effects.",
    "Primary main-text mediation remains complete-case bootstrap product-of-coefficients."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table S5 — objective outcomes as Y in mediation
# ═══════════════════════════════════════════════════════════════════════════
message("Table S5 objective outcome mediation")
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
cov_txt <- if (length(cov_use)) paste0(" + ", paste(cov_use, collapse = " + ")) else ""
obj_specs <- list(
  list(y = "N12_ord", ylab = "Visit burden ordinal (N12AA)", m = "SSD12"),
  list(y = "N12_ord", ylab = "Visit burden ordinal (N12AA)", m = "Whiteley8"),
  list(y = "N12_high", ylab = "High visits (11+)", m = "SSD12"),
  list(y = "N12_high", ylab = "High visits (11+)", m = "Whiteley8"),
  list(y = "not_employed", ylab = "Not employed (vs employed)", m = "SSD12"),
  list(y = "not_employed", ylab = "Not employed (vs employed)", m = "Whiteley8"),
  list(y = "unemployed_only", ylab = "Unemployed only", m = "SSD12")
)
rows_s5 <- list()
for (j in seq_along(obj_specs)) {
  sp <- obj_specs[[j]]
  need <- c("PHQ15", sp$m, sp$y, cov_use)
  dd <- d0[, need, drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 100L) next
  message("  obj ", sp$ylab, " via ", sp$m, " n=", nrow(dd))
  ef <- .boot_med(dd, "PHQ15", sp$m, sp$y, cov_txt, cov_use, n_boot, seed = 8000L + j)
  e <- ef$indirect
  rows_s5[[length(rows_s5) + 1L]] <- data.frame(
    Outcome = sp$ylab,
    Mediator = if (sp$m == "SSD12") "SSD-12" else "Whiteley-8",
    n = nrow(dd),
    ACME = .fmt_est(e[["est"]]),
    LLCI = .fmt_est(e[["lo"]]),
    ULCI = .fmt_est(e[["hi"]]),
    Sig = .sig_ci(e[["lo"]], e[["hi"]]),
    stringsAsFactors = FALSE
  )
}
tS5 <- do.call(rbind, rows_s5)
.write_sci(
  file.path(sr_tab, "Table S5. Mediation with objective function outcomes.xlsx"),
  "Table S5. PHQ-15 → cognitive mediator → objective function burden (dual-outcome extension).",
  tS5,
  footnotes = c(
    "Supplementary. Subjective disability (WHO-DAS) remains the main-text outcome.",
    "N12AA: past-year visits for somatic complaints (ordinal mid-ranks / high=11+).",
    "Occupation: not employed = unemployed + housewife + retire + student + others (vs employed).",
    "Linear probability / OLS bootstrap ACME for binary outcomes (exploratory).",
    sprintf("Bootstrap B = %s.", n_boot)
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Table S6 + Figure S1 — functional subtype qualitative naming (domain k-means)
# ═══════════════════════════════════════════════════════════════════════════
message("Table S6 functional subtypes")
dom_mat <- as.matrix(d0[, names(dom_vars), drop = FALSE])
ok <- stats::complete.cases(dom_mat)
set.seed(42)
km <- stats::kmeans(scale(dom_mat[ok, , drop = FALSE]), centers = 3L, nstart = 50L)
d0$FuncSubtype <- NA_character_
d0$FuncSubtype[ok] <- paste0("FS", km$cluster)

# profile means to assign qualitative names
prof <- aggregate(dom_mat[ok, , drop = FALSE], by = list(FS = d0$FuncSubtype[ok]), mean)
rownames(prof) <- prof$FS
score_work <- prof$DAS_LifeActivities + prof$DAS_Mobility + prof$DAS_SelfCare
score_social <- prof$DAS_GettingAlong + prof$DAS_Participation
score_all <- rowMeans(as.matrix(prof[, names(dom_vars)]))
ord_all <- order(score_all) # indices into prof rows
fs_ord <- prof$FS[ord_all]
names_map <- setNames(character(3), paste0("FS", 1:3))
names_map[fs_ord[1]] <- "Low global disability"
# highest overall -> pervasive if clearly separated; middle by work vs social tilt
if (score_all[ord_all[3]] > score_all[ord_all[2]] + 0.25) {
  names_map[fs_ord[3]] <- "Pervasive high disability"
} else if ((score_work - score_social)[ord_all[3]] >= 0) {
  names_map[fs_ord[3]] <- "Work / mobility-predominant disability"
} else {
  names_map[fs_ord[3]] <- "Social / participation-predominant disability"
}
if ((score_work - score_social)[ord_all[2]] >= 0) {
  names_map[fs_ord[2]] <- "Work / mobility-predominant disability"
} else {
  names_map[fs_ord[2]] <- "Social / participation-predominant disability"
}
# avoid duplicate labels
if (length(unique(names_map)) < 3L) {
  names_map[fs_ord[3]] <- "Pervasive high disability"
  if (identical(names_map[fs_ord[2]], names_map[fs_ord[3]])) {
    names_map[fs_ord[2]] <- if (grepl("Work", names_map[fs_ord[2]])) {
      "Social / participation-predominant disability"
    } else {
      "Work / mobility-predominant disability"
    }
  }
}
d0$FuncSubtype_lab <- unname(names_map[d0$FuncSubtype])

rows_s6 <- list()
for (fs in names(names_map)) {
  idx <- which(d0$FuncSubtype == fs)
  row <- data.frame(
    Subtype = names_map[[fs]],
    Code = fs,
    n = length(idx),
    `%` = .fmt_est(100 * length(idx) / sum(ok), 1),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  for (nm in names(dom_vars)) {
    row[[dom_vars[[nm]]]] <- sprintf("%s (%s)", .fmt_est(mean(d0[[nm]][idx], na.rm = TRUE), 2),
                                     .fmt_est(stats::sd(d0[[nm]][idx], na.rm = TRUE), 2))
  }
  # overlap with severity LCA
  tabc <- table(d0$Class[idx])
  row$`Overlap with severity LCA` <- paste(paste0(names(tabc), "=", as.integer(tabc)), collapse = "; ")
  rows_s6[[length(rows_s6) + 1L]] <- row
}
tS6 <- do.call(rbind, rows_s6)
.write_sci(
  file.path(sr_tab, "Table S6. Qualitative functional subtypes from WHO-DAS domains.xlsx"),
  "Table S6. Qualitative functional subtypes (k-means on WHO-DAS domain scores).",
  tS6,
  footnotes = c(
    "Supplementary. Distinct from main-text severity LCA (C1–C3 on DAS items).",
    "k-means (k=3) on standardized domain means; labels assigned by work/mobility vs social/participation profile and overall level.",
    "DAS8/DAS9 absent in file: Getting along uses DAS7; Life activities uses DAS10."
  )
)

long <- do.call(rbind, lapply(names(dom_vars), function(nm) {
  data.frame(
    Domain = factor(dom_vars[[nm]], levels = unname(dom_vars)),
    Subtype = factor(d0$FuncSubtype_lab, levels = unique(names_map)),
    Score = d0[[nm]],
    stringsAsFactors = FALSE
  )
}))
long <- long[is.finite(long$Score) & !is.na(long$Subtype), ]
agg <- aggregate(Score ~ Domain + Subtype, data = long, FUN = mean)
pS1 <- ggplot(agg, aes(Domain, Score, group = Subtype, colour = Subtype)) +
  geom_line(linewidth = 0.8) + geom_point(size = 2) +
  labs(
    title = "Figure S1. Qualitative functional subtype domain profiles",
    x = NULL, y = "Domain mean (0-4)", colour = NULL
  ) +
  theme_bw(base_family = "serif", base_size = 11) +
  theme(axis.text.x = element_text(angle = 25, hjust = 1), legend.position = "bottom",
        legend.text = element_text(size = 8))
.pipeline_pdf(file.path(sr_pdf, "Figure S1. Functional subtype domain profiles.pdf"), pS1, 9, 5.2)
writeLines(c(
  "# Figure S1. Functional subtype domain profiles",
  "",
  "## 图面说明",
  "基于 WHO-DAS 六维 k-means 的定性功能亚型剖面（工作/行动 vs 社交/参与 vs 低损伤/全面高损伤）。",
  "",
  "## 分析上下文",
  "补充分析；正文 LCA 仍为 C1–C3 严重度分型。详见 Table S6。"
), file.path(sr_md, "Figure S1. Functional subtype domain profiles.md"))

# also map severity LCA qualitative gloss (Table S7)
rows_s7 <- data.frame(
  Severity_LCA = c("C1", "C2", "C3"),
  Qualitative_gloss = c(
    "Low symptom - low disability (near-intact functioning)",
    "Intermediate mixed disability (not a pure work-only or social-only class)",
    "Pervasive high disability across WHO-DAS domains (全面受损取向)"
  ),
  Primary_elevated_domains = c(
    "All domains low",
    "Self-care / participation intermediate",
    "Mobility, self-care, participation, cognition all high"
  ),
  stringsAsFactors = FALSE
)
.write_sci(
  file.path(sr_tab, "Table S7. Qualitative gloss for main-text severity LCA.xlsx"),
  "Table S7. Qualitative naming gloss for main-text WHO-DAS severity LCA (C1-C3).",
  rows_s7,
  footnotes = c(
    "Supplementary naming aid only; does not replace C1-C3 codes in main-text Tables/Figures.",
    "Domain evidence from main-text Table 8 / Figure 5."
  )
)

# ═══════════════════════════════════════════════════════════════════════════
# Methods: CSM title + supplementary inventory (do not alter main table numbers)
# ═══════════════════════════════════════════════════════════════════════════
methods_path <- file.path(sr, "Methods_statistical_analysis.md")
extra <- c(
  "",
  "## Proposed manuscript framing (Common-Sense Model; supplementary analyses)",
  "",
  "### Proposed title",
  "Predictors and mediating mechanisms of disability and social functioning impairment (WHO-DAS 12) among outpatients with somatic symptom disorder in a general hospital: a Common-Sense Model analysis of cognitive-path dominance and heterogeneity.",
  "",
  "中文拟定题目：综合医院门诊躯体症状障碍（SSD）患者残疾与社会功能损害（WHO-DAS 12）的预测因素及介导机制分析——基于症状感知/Common-Sense Model 的认知路径主导性与人群异质性。",
  "",
  "### Innovation claim",
  "The scientific claim is not merely that psychological cognition mediates symptom–disability links, but **which cognitive path dominates** (SSD-12 vs Whiteley-8) and **for whom** (measurement invariance / multi-group SEM, formal moderated mediation, functional subtypes, objective utilization/employment outcomes).",
  "",
  "### Supplementary analyses (Tables S1–S7 / Figure S1)",
  "- Table S1: measurement invariance of SSD-12 / Whiteley CFA across sex and SSD diagnosis.",
  "- Table S2: multi-group path SEM indirect effects.",
  "- Table S3: formal index of moderated mediation (available moderators).",
  "- Table S4: FIML and MICE+Rubin sensitivity for parallel indirect effects.",
  "- Table S5: mediation with objective outcomes (N12AA visits; employment).",
  "- Table S6 / Figure S1: qualitative functional subtypes from WHO-DAS domains (k-means).",
  "- Table S7: qualitative gloss for main-text severity LCA.",
  "",
  "Main-text Tables 1–16 and Figures 1–7 are unchanged by these supplementary additions.",
  ""
)
if (file.exists(methods_path)) {
  old <- readLines(methods_path, warn = FALSE)
  cut <- grep("^## Proposed manuscript framing", old)
  if (length(cut)) old <- old[seq_len(cut[[1]] - 1L)]
  writeLines(c(old, extra), methods_path)
} else {
  writeLines(c("# Statistical analysis", extra), methods_path)
}
message("Methods CSM/supplementary section written")

message("DONE supplementary. New S tables/figs:")
print(list.files(sr_tab, pattern = "^Table S"))
print(list.files(sr_pdf, pattern = "^Figure S"))
