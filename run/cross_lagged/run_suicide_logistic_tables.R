###############################################################################
# Suicide outpatient: proper logistic tables (SCI three-line)
#   Table 2  — HAMD/HAMA Index → CSSRS item1 1st  (Crude / Model1 / Model2)
#   Table 3  — CLPM paths (former Table 2; β / OR)
#   Table S3 — Univariate logistic OR (95%CI) + P
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "/mnt/e/01block/01Block-new-Final")
.study <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  file.path(.engine, ".superpowers/sdd/study_mirror")
)
.tab <- file.path(.study, "summary_result", "table")
.support <- file.path(.study, "summary_result", "_support_clpn")
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)
dir.create(.support, recursive = TRUE, showWarnings = FALSE)

setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
.table_queue_env$items <- list()

.fmt_p <- function(p) {
  p <- as.numeric(p)
  ifelse(is.na(p), "",
         ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
}
.fmt_est <- function(x, d = 3L) {
  x <- as.numeric(x)
  ifelse(!is.finite(x), "", sprintf(paste0("%.", d, "f"), x))
}
.fmt_or_ci <- function(or, lo, hi) {
  if (!is.finite(or) || !is.finite(lo) || !is.finite(hi)) return("")
  sprintf("%s (%s, %s)", .fmt_est(or), .fmt_est(lo), .fmt_est(hi))
}

load(file.path(.study, "data/harmonized/D04_outpatient_clpm_imputed.RData"))
stopifnot(exists("dabiao"), nrow(dabiao) == 649L)

m2 <- trimws(readLines(file.path(.study, "covariates/Model2Factors.txt"), warn = FALSE))
m2 <- m2[nzchar(m2)]
m1 <- intersect(c("age", "sex"), names(dabiao))
if (!length(m1)) m1 <- "age"

df <- dabiao
df$y <- as.integer(df$CSSRS_1st)
stopifnot(all(df$y %in% c(0L, 1L)))

# ---- helper: fit focus coef OR from glm ----
.fit_or <- function(data, focus, covars = character(0)) {
  covars <- unique(setdiff(covars[nzchar(covars)], focus))
  covars <- intersect(covars, names(data))
  rhs <- c(focus, covars)
  # backtick names with dots
  rhs_q <- vapply(rhs, function(v) paste0("`", v, "`"), character(1))
  fml <- stats::as.formula(paste("y ~", paste(rhs_q, collapse = " + ")))
  d <- data[, c("y", rhs), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 30L || length(unique(d$y)) < 2L) {
    return(list(or = NA, lo = NA, hi = NA, p = NA, n = nrow(d), n_case = NA))
  }
  m <- tryCatch(stats::glm(fml, data = d, family = stats::binomial()), error = function(e) e)
  if (inherits(m, "error")) {
    return(list(or = NA, lo = NA, hi = NA, p = NA, n = nrow(d), n_case = sum(d$y == 1),
                note = conditionMessage(m)))
  }
  sm <- summary(m)$coefficients
  rn <- rownames(sm)
  # continuous: name is focus; factor: first non-intercept matching focus
  hit <- which(rn == focus | startsWith(rn, paste0(focus)))
  hit <- hit[hit > 1L]
  if (!length(hit)) {
    return(list(or = NA, lo = NA, hi = NA, p = NA, n = nrow(d), n_case = sum(d$y == 1)))
  }
  # for continuous single coef
  if (length(hit) == 1L) {
    b <- sm[hit, 1]; se <- sm[hit, 2]; p <- sm[hit, 4]
    or <- exp(b); lo <- exp(b - 1.96 * se); hi <- exp(b + 1.96 * se)
    return(list(or = or, lo = lo, hi = hi, p = p, n = nrow(d), n_case = sum(d$y == 1)))
  }
  # multi-level: LRT overall p; report not a single OR — caller handles levels
  p <- tryCatch({
    a <- stats::anova(m, test = "LRT")
    pv <- a$`Pr(>Chi)`; pv <- pv[!is.na(pv)]; as.numeric(pv[length(pv)])
  }, error = function(e) NA_real_)
  list(or = NA, lo = NA, hi = NA, p = p, n = nrow(d), n_case = sum(d$y == 1), multilevel = TRUE)
}

.fit_factor_levels <- function(data, focus, covars = character(0),
                               ref = NULL) {
  covars <- unique(setdiff(covars[nzchar(covars)], focus))
  covars <- intersect(covars, names(data))
  x <- data[[focus]]
  if (is.character(x)) x <- factor(x)
  if (!is.factor(x)) x <- factor(x)
  x <- droplevels(x)
  # default ref = most frequent level (avoids sparse-first-level separation)
  if (is.null(ref) || !ref %in% levels(x)) {
    tabn <- sort(table(x), decreasing = TRUE)
    ref <- names(tabn)[1L]
  }
  x <- stats::relevel(x, ref = ref)
  data[[focus]] <- x
  levs <- levels(x)
  if (length(levs) < 2L) return(list())
  rhs <- c(focus, covars)
  rhs_q <- vapply(rhs, function(v) paste0("`", v, "`"), character(1))
  fml <- stats::as.formula(paste("y ~", paste(rhs_q, collapse = " + ")))
  d <- data[, c("y", rhs), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  m <- tryCatch(stats::glm(fml, data = d, family = stats::binomial()), error = function(e) e)
  if (inherits(m, "error")) return(list())
  sm <- summary(m)$coefficients
  out <- list()
  out[[ref]] <- list(or = 1, lo = 1, hi = 1, p = NA, label = paste0(ref, " (Ref)"),
                     n = nrow(d), n_case = sum(d$y == 1))
  for (lv in levs[-1L]) {
    rn <- paste0(focus, lv)
    if (!rn %in% rownames(sm)) next
    b <- sm[rn, 1]; se <- sm[rn, 2]; p <- sm[rn, 4]
    # drop insane separation ORs from display
    or <- exp(b); lo <- exp(b - 1.96 * se); hi <- exp(b + 1.96 * se)
    if (!is.finite(or) || or < 1e-6 || or > 1e6) {
      or <- lo <- hi <- NA_real_
    }
    out[[lv]] <- list(
      or = or, lo = lo, hi = hi, p = p,
      label = lv, n = nrow(d), n_case = sum(d$y == 1)
    )
  }
  out
}

# =============================================================================
# Table 2 — Crude / Model1 / Model2 logistic
# Grouping gate: quartile → tertile → binary (highest Model2 P < 0.05)
# Primary exposure for gate = HAMD_Index; same scheme applied to HAMA
# =============================================================================
.message <- function(...) message("[logit] ", ...)

.make_groups <- function(x, scheme, lab) {
  x <- as.numeric(x)
  if (identical(scheme, "quartile")) {
    qs <- stats::quantile(x, c(0.25, 0.5, 0.75), na.rm = TRUE)
    cut(x, breaks = c(-Inf, qs[1], qs[2], qs[3], Inf),
        labels = paste0(lab, " Q", 1:4), include.lowest = TRUE)
  } else if (identical(scheme, "tertile")) {
    qs <- stats::quantile(x, c(1 / 3, 2 / 3), na.rm = TRUE)
    cut(x, breaks = c(-Inf, qs[1], qs[2], Inf),
        labels = paste0(lab, " T", 1:3), include.lowest = TRUE)
  } else if (identical(scheme, "binary")) {
    md <- stats::median(x, na.rm = TRUE)
    cut(x, breaks = c(-Inf, md, Inf),
        labels = paste0(lab, c(" Low", " High")), include.lowest = TRUE)
  } else {
    stop("Unknown scheme: ", scheme)
  }
}

.scheme_highest_model2_p <- function(focus_col) {
  labs <- levels(df[[focus_col]])
  ref <- labs[[1L]]
  high <- labs[[length(labs)]]
  lv <- .fit_factor_levels(df, focus_col, m2, ref = ref)
  if (!length(lv) || is.null(lv[[high]])) return(NA_real_)
  as.numeric(lv[[high]]$p)
}

.scheme_pass <- function(focus_col, p_cut = 0.05) {
  p <- .scheme_highest_model2_p(focus_col)
  is.finite(p) && p < p_cut
}

# Cascade gate on HAMD
.gate_order <- c("quartile", "tertile", "binary")
.selected_scheme <- NA_character_
.gate_log <- character(0)
for (sch in .gate_order) {
  col <- paste0("HAMD_", sch)
  df[[col]] <- .make_groups(df$HAMD_Index, sch, "HAMD")
  ok <- .scheme_pass(col)
  ph <- .scheme_highest_model2_p(col)
  .gate_log <- c(
    .gate_log,
    sprintf("%s: Model2 highest-group P=%s → %s",
            sch,
            if (is.finite(ph)) sprintf("%.4f", ph) else "NA",
            if (ok) "PASS" else "fail")
  )
  .message(.gate_log[length(.gate_log)])
  if (ok) {
    .selected_scheme <- sch
    break
  }
}
if (!nzchar(.selected_scheme %||% "")) {
  .selected_scheme <- "binary"
  .message("No scheme passed Model2 highest-group; fallback binary")
}
.message("Selected grouping = ", .selected_scheme)

# Apply selected scheme to HAMA
df[[paste0("HAMA_", .selected_scheme)]] <- .make_groups(
  df$HAMA_Index, .selected_scheme, "HAMA"
)
# Persist gate for Methods / downstream
.write_gate <- file.path(.study, "covariates/logistic_grouping_gate.txt")
writeLines(c(
  paste0("selected_scheme=", .selected_scheme),
  paste0("primary_exposure=HAMD_Index"),
  paste0("outcome=CSSRS_1st"),
  paste0("rule=quartile→tertile→binary; pass if Model2 highest exposure group P<0.05"),
  .gate_log
), .write_gate)

.scheme_label <- c(
  quartile = "Quartile",
  tertile = "Tertile",
  binary = "Binary (median)"
)[[.selected_scheme]]

.row_block_cont <- function(focus, pretty) {
  cr <- .fit_or(df, focus, character(0))
  m1r <- .fit_or(df, focus, m1)
  m2r <- .fit_or(df, focus, m2)
  n_case <- sum(df$y == 1, na.rm = TRUE)
  n_all <- nrow(df)
  data.frame(
    Characteristic = pretty,
    `Exposure` = "Continuous (per 1-point)",
    `Case n (%)` = sprintf("%s (%.1f%%)", format(n_case, big.mark = ","), 100 * n_case / n_all),
    `Crude OR (95% CI)` = .fmt_or_ci(cr$or, cr$lo, cr$hi),
    `Crude P` = .fmt_p(cr$p),
    `Model1 OR (95% CI)` = .fmt_or_ci(m1r$or, m1r$lo, m1r$hi),
    `Model1 P` = .fmt_p(m1r$p),
    `Model2 OR (95% CI)` = .fmt_or_ci(m2r$or, m2r$lo, m2r$hi),
    `Model2 P` = .fmt_p(m2r$p),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

.row_block_group <- function(focus, pretty) {
  labs <- levels(df[[focus]])
  ref_level <- labs[[1L]]
  cr_lv <- .fit_factor_levels(df, focus, character(0), ref = ref_level)
  m1_lv <- .fit_factor_levels(df, focus, m1, ref = ref_level)
  m2_lv <- .fit_factor_levels(df, focus, m2, ref = ref_level)
  levs <- names(cr_lv)
  rows <- list()
  rows[[1]] <- data.frame(
    Characteristic = pretty,
    `Exposure` = .scheme_label,
    `Case n (%)` = "",
    `Crude OR (95% CI)` = "",
    `Crude P` = "",
    `Model1 OR (95% CI)` = "",
    `Model1 P` = "",
    `Model2 OR (95% CI)` = "",
    `Model2 P` = "",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  for (lv in levs) {
    a <- cr_lv[[lv]]; b <- m1_lv[[lv]]; c <- m2_lv[[lv]]
    is_ref <- grepl("\\(Ref\\)", a$label %||% "")
    idx <- as.character(df[[focus]]) == sub(" \\(Ref\\)$", "", a$label)
    n_lv <- sum(idx, na.rm = TRUE)
    n_case_lv <- sum(df$y[idx] == 1, na.rm = TRUE)
    rows[[length(rows) + 1L]] <- data.frame(
      Characteristic = paste0("  ", sub(" \\(Ref\\)$", "", a$label)),
      `Exposure` = if (is_ref) "Ref" else "",
      `Case n (%)` = sprintf("%s/%s (%.1f%%)", n_case_lv, n_lv, 100 * n_case_lv / max(n_lv, 1)),
      `Crude OR (95% CI)` = if (is_ref) "Ref" else .fmt_or_ci(a$or, a$lo, a$hi),
      `Crude P` = if (is_ref) "" else .fmt_p(a$p),
      `Model1 OR (95% CI)` = if (is_ref) "Ref" else .fmt_or_ci(b$or, b$lo, b$hi),
      `Model1 P` = if (is_ref) "" else .fmt_p(b$p),
      `Model2 OR (95% CI)` = if (is_ref) "Ref" else .fmt_or_ci(c$or, c$lo, c$hi),
      `Model2 P` = if (is_ref) "" else .fmt_p(c$p),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

.hamd_g <- paste0("HAMD_", .selected_scheme)
.hama_g <- paste0("HAMA_", .selected_scheme)
t2 <- rbind(
  .row_block_cont("HAMD_Index", "HAMD Index total"),
  .row_block_group(.hamd_g, paste0("HAMD Index ", tolower(.scheme_label))),
  .row_block_cont("HAMA_Index", "HAMA Index total"),
  .row_block_group(.hama_g, paste0("HAMA Index ", tolower(.scheme_label)))
)
rownames(t2) <- NULL

t2_path <- file.path(
  .tab,
  paste0(
    "Table 2-Outpatient. Logistic regression analysis of HAMD HAMA and CSSRS ideation - ",
    .selected_scheme, " (GLM).xlsx"
  )
)
export_sci_table(
  t2, t2_path,
  title = paste0(
    "Table 2-Outpatient. Logistic regression analysis of HAMD HAMA and CSSRS ideation - ",
    .selected_scheme, " (GLM)"
  ),
  table_footnotes = c(
    "Outcome: 1st-wave C-SSRS ideation item1 (Yes=1 / No=0). N=649 outpatient six-node complete cases.",
    paste0("Grouping gate (HAMD primary): quartile → tertile → binary; selected = ",
           .selected_scheme, " (Model2 highest exposure group P<0.05)."),
    paste0("Model 1 adjusted for: ", paste(m1, collapse = ", "), "."),
    paste0("Model 2 adjusted for: ", paste(m2, collapse = ", "), "."),
    paste0("Continuous: OR per 1-point. ", .scheme_label, ": lowest group as reference."),
    "Cross-lagged path estimates are reported in Table 3.",
    paste("Gate log:", paste(.gate_log, collapse = " | "))
  )
)
.message("queued Table 2 logistic (", .selected_scheme, ")")

# =============================================================================
# Table 3 — CLPM paths (move former Table 2)
# =============================================================================
raw_path <- file.path(
  .support,
  "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.csv"
)
if (!file.exists(raw_path)) {
  raw_path <- file.path(
    .study, "summary_result/_archive_old_table_names/Table2_CLPM_paths.csv"
  )
}
raw2 <- utils::read.csv(raw_path, stringsAsFactors = FALSE)
.path_lab <- c(
  HAMD_AR = "HAMD Index → HAMD 1st (autoregressive)",
  HAMA_AR = "HAMA Index → HAMA 1st (autoregressive)",
  CSSRS_AR = "CSSRS item1 Index → CSSRS item1 1st (autoregressive)",
  HAMD_to_CSSRS = "HAMD Index → CSSRS item1 1st",
  HAMA_to_CSSRS = "HAMA Index → CSSRS item1 1st",
  CSSRS_to_HAMD = "CSSRS item1 Index → HAMD 1st",
  CSSRS_to_HAMA = "CSSRS item1 Index → HAMA 1st",
  HAMD_to_HAMA = "HAMD Index → HAMA 1st",
  HAMA_to_HAMD = "HAMA Index → HAMD 1st"
)
.eff_lab <- c(std_beta = "Standardized β", OR = "OR")
table3 <- data.frame(
  Path = ifelse(raw2$path %in% names(.path_lab), unname(.path_lab[raw2$path]), raw2$path),
  Effect = ifelse(raw2$effect_type %in% names(.eff_lab),
                  unname(.eff_lab[raw2$effect_type]), raw2$effect_type),
  `Estimate (95% CI)` = sprintf(
    "%s (%s, %s)",
    .fmt_est(raw2$estimate), .fmt_est(raw2$ci_low), .fmt_est(raw2$ci_high)
  ),
  `P-value` = .fmt_p(raw2$p),
  N = as.integer(raw2$n),
  check.names = FALSE,
  stringsAsFactors = FALSE
)
t3_path <- file.path(
  .tab,
  "Table 3-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.xlsx"
)
export_sci_table(
  table3, t3_path,
  title = "Table 3-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS",
  table_footnotes = c(
    "Nine pre-registered Index→1st paths; outpatient n=649.",
    "Continuous outcomes: standardized β; CSSRS item1 outcome: odds ratio (OR) from logistic regression.",
    paste0("Adjusted for Model 2 covariates: ", paste(m2, collapse = ", "), ".")
  )
)
.message("queued Table 3 CLPM")

# =============================================================================
# Table S3 — Univariate logistic OR for covariates (outcome CSSRS_1st)
# =============================================================================
cands <- setdiff(m2, c("HAMD_Index", "HAMA_Index", "CSSRS_Index", "CSSRS_1st"))
# also include full UV list from covariates/uv_table.csv
uv0 <- utils::read.csv(file.path(.study, "covariates/uv_table.csv"), stringsAsFactors = FALSE)
uv_vars <- unique(c(uv0$variable, cands))
uv_vars <- intersect(uv_vars, names(df))
uv_vars <- setdiff(uv_vars, c("CSSRS_1st", "CSSRS_Index", "HAMD_1st", "HAMA_1st"))

s3_rows <- list()
for (v in uv_vars) {
  xv <- df[[v]]
  if (is.numeric(xv) && length(unique(stats::na.omit(xv))) > 8L) {
    r <- .fit_or(df, v, character(0))
    s3_rows[[length(s3_rows) + 1L]] <- data.frame(
      Characteristic = v,
      Level = "Continuous",
      N = r$n,
      `OR (95% CI)` = .fmt_or_ci(r$or, r$lo, r$hi),
      `P-value` = .fmt_p(r$p),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  } else {
    if (!is.factor(xv)) xv <- factor(as.character(xv))
    df[[v]] <- droplevels(xv)
    lv <- .fit_factor_levels(df, v, character(0))
    if (!length(lv)) next
    # overall LRT p on parent
    ov <- .fit_or(df, v, character(0))
    s3_rows[[length(s3_rows) + 1L]] <- data.frame(
      Characteristic = v,
      Level = "",
      N = ov$n,
      `OR (95% CI)` = "",
      `P-value` = .fmt_p(ov$p),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    for (nm in names(lv)) {
      a <- lv[[nm]]
      is_ref <- grepl("\\(Ref\\)", a$label)
      s3_rows[[length(s3_rows) + 1L]] <- data.frame(
        Characteristic = "",
        Level = sub(" \\(Ref\\)$", "", a$label),
        N = a$n,
        `OR (95% CI)` = if (is_ref) "Ref" else .fmt_or_ci(a$or, a$lo, a$hi),
        `P-value` = if (is_ref) "" else .fmt_p(a$p),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    }
  }
}
s3 <- do.call(rbind, s3_rows)
rownames(s3) <- NULL
s3_path <- file.path(.tab, "Table S3-Outpatient. Univariate Logistic Regression Analysis.xlsx")
export_sci_table(
  s3, s3_path,
  title = "Table S3-Outpatient. Univariate Logistic Regression Analysis",
  table_footnotes = c(
    "Outcome: 1st-wave C-SSRS ideation item1 (Yes=1).",
    "Univariable logistic OR (95% CI). Categorical: first level as reference; overall P from LRT.",
    "Used for Model 2 covariate screening (p<0.10) prior to VIF."
  )
)
.message("queued Table S3 UV logistic")

# Render
render_queued_tables(list())

# Drop .tex (not publication deliverable in table/)
for (f in list.files(.tab, pattern = "\\.tex$", full.names = TRUE)) {
  dest <- file.path(.support, basename(f))
  if (file.exists(dest)) file.remove(dest)
  file.rename(f, dest)
}
# Archive ungated / CLPM-misnamed Table 2; keep "... - quartile|tertile|binary.xlsx"
for (f in list.files(.tab, pattern = "^Table 2-Outpatient\\.", full.names = TRUE)) {
  bn <- basename(f)
  if (grepl(" - (quartile|tertile|binary)\\.xlsx$", bn)) next
  dest <- file.path(.support, bn)
  if (file.exists(dest)) file.remove(dest)
  file.rename(f, dest)
  message("[logit] archived non-gated Table2: ", bn)
}
old_s3 <- file.path(.tab, "Table S3-Outpatient. Univariate Regression Analysis.xlsx")
if (file.exists(old_s3)) {
  file.rename(old_s3, file.path(.support, basename(old_s3)))
}

# Renumber S8 CLPN adjacency → S5 (no hip S5–S7 slots in this study)
.s8 <- file.path(.tab, "Table S8-Outpatient. CLPN adjacency.csv")
.s5 <- file.path(.tab, "Table S5-Outpatient. CLPN adjacency.csv")
if (file.exists(.s8)) {
  if (file.exists(.s5)) file.remove(.s5)
  file.rename(.s8, .s5)
  message("[logit] renumbered S8 → S5 CLPN adjacency")
} else if (!file.exists(.s5)) {
  alt <- file.path(.support, "Table S8-Outpatient. CLPN adjacency.csv")
  if (file.exists(alt)) {
    file.copy(alt, .s5, overwrite = TRUE)
    message("[logit] restored S5 CLPN adjacency from support")
  }
}

# Restore gated Table 2 if missing
.t2_pat <- "Table 2-Outpatient\\. Logistic regression analysis of HAMD HAMA and CSSRS ideation - (quartile|tertile|binary)\\.xlsx$"
.t2_hit <- list.files(.tab, pattern = .t2_pat, full.names = TRUE)
if (!length(.t2_hit)) {
  .t2_sup <- list.files(.support, pattern = .t2_pat, full.names = TRUE)
  if (length(.t2_sup)) {
    file.copy(.t2_sup[[1L]], file.path(.tab, basename(.t2_sup[[1L]])), overwrite = TRUE)
    message("[logit] restored gated Table 2: ", basename(.t2_sup[[1L]]))
  }
}

# Hygiene: Table1–3, S1–S5 + README
keep_re <- paste(
  "^Table [13]-Outpatient\\..*\\.xlsx$",
  "^Table 2-Outpatient\\..* - (quartile|tertile|binary)\\.xlsx$",
  "^Table S[1-4]-Outpatient\\..*\\.xlsx$",
  "^Table S5-Outpatient\\. CLPN adjacency\\.csv$",
  "^README_summary_slots\\.txt$",
  sep = "|"
)
for (f in list.files(.tab, full.names = TRUE)) {
  bn <- basename(f)
  if (grepl(keep_re, bn)) next
  if (!file.exists(f) || dir.exists(f)) next
  dest <- file.path(.support, bn)
  if (file.exists(dest)) file.remove(dest)
  file.rename(f, dest)
  message("[logit] moved to support: ", bn)
}

writeLines(c(
  "table/ = Outpatient SCI three-line xlsx (export_sci_table).",
  "",
  "Table 1 — Baseline characteristics",
  "Table 2 — Logistic HAMD/HAMA → CSSRS item1 1st (Crude/Model1/Model2); grouping gate quartile→tertile→binary",
  "Table 3 — Cross-lagged path analysis (β / OR)",
  "Table S1 — Imputation note",
  "Table S2 — Node Spearman correlation",
  "Table S3 — Univariate logistic OR",
  "Table S4 — VIF",
  "Table S5 — CLPN adjacency.csv",
  "",
  "Gate log: covariates/logistic_grouping_gate.txt",
  "Support dumps → _support_clpn/; Ward → _archive_ward_exploratory/"
), file.path(.tab, "README_summary_slots.txt"))

message("[logit] remaining:")
print(sort(list.files(.tab)))
message("[logit] DONE")
