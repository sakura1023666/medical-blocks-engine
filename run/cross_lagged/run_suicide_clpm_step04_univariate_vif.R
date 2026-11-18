#!/usr/bin/env Rscript
# step04 — univariate logistic screen then VIF, on the step02 imputed outpatient cohort.
# Outcome: C-SSRS ideation, 1st (item2). Nodes are not screened as covariates.
# Does not re-run MICE.
#
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_step04_univariate_vif.R

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run") {
  engine_root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  engine_root <- normalizePath(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd()), winslash = "/")
}
setwd(engine_root)

`%||%` <- function(a, b) if (is.null(a)) b else a

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_indicator_names.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)

.cfg_env <- new.env(parent = globalenv())
sys.source(file.path(study_root, "config_suicide_clpm.R"), envir = .cfg_env)
config <- .cfg_env$config
if (exists("pipeline_apply_pub_digits", mode = "function")) pipeline_apply_pub_digits(config)

screen_y <- "C-SSRS ideation, 1st"
uv_p_cut <- 0.10
vif_thr <- 4
miss_drop_thr <- 0.4

step_dir <- file.path(study_root, "step04_univariate_vif")
tab_dir <- file.path(step_dir, "Tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

src <- file.path(study_root, "step02_imputation/dabiao.RData")
if (!file.exists(src)) stop("Missing step02 dabiao: ", src, call. = FALSE)
e <- new.env(parent = emptyenv())
load(src, envir = e)
df <- e$dabiao
stopifnot(is.data.frame(df), screen_y %in% names(df))

y_raw <- df[[screen_y]]
y01 <- if (is.factor(y_raw) || is.character(y_raw)) {
  as.integer(tolower(trimws(as.character(y_raw))) %in% c("1", "yes"))
} else {
  as.integer(y_raw)
}
if (!all(y01 %in% c(0L, 1L))) stop("Screen outcome is not 0/1", call. = FALSE)
df$.screen_y <- y01

cands <- as.character(config$suicide_cssrs$covariate_candidate_vars %||% character(0))
nodes <- as.character(config$suicide_cssrs$nodes)
cands <- intersect(cands, names(df))
cands <- setdiff(cands, nodes)
miss_rate <- vapply(cands, function(v) mean(is.na(df[[v]])), numeric(1))
drop_hi <- names(miss_rate)[is.finite(miss_rate) & miss_rate >= miss_drop_thr]
cands <- setdiff(cands, drop_hi)
cands <- suicide_order_table_vars(cands)

.or_cell <- function(est, lo, hi) {
  if (!is.finite(est) || !is.finite(lo) || !is.finite(hi)) return("NE")
  paste0(pub_format_est(est), " ", pub_format_ci(lo, hi))
}

.n_pct <- function(k, n_tot) {
  if (!is.finite(n_tot) || n_tot <= 0) return("")
  paste0(pub_format_int(k), " (", fmt_num(100 * k / n_tot), "%)")
}

.empty_uv_row <- function(characteristic, statistic = "", all_cell = "", or_cell = "") {
  data.frame(
    Characteristic = characteristic,
    Statistic = statistic,
    all = all_cell,
    `OR (univariable)` = or_cell,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

.cont_stat <- function(x) {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  paste0(
    fmt_num(stats::median(x)), " (",
    fmt_num(stats::quantile(x, 0.25)), ", ",
    fmt_num(stats::quantile(x, 0.75)), ")"
  )
}

.fit_one <- function(x) {
  d <- df[, c(".screen_y", x), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  n <- nrow(d)
  xv <- d[[x]]
  if (is.character(xv)) xv <- factor(xv)
  if (is.factor(xv)) {
    xv <- droplevels(xv)
    d[[x]] <- xv
    if (nlevels(xv) < 2L) {
      return(list(overall_p = NA_real_, n = n, rows = .empty_uv_row(x)))
    }
  } else if (length(unique(xv)) < 2L) {
    return(list(overall_p = NA_real_, n = n, rows = .empty_uv_row(x)))
  }
  fml <- stats::as.formula(paste(".screen_y ~", paste0("`", x, "`")))
  m <- tryCatch(stats::glm(fml, data = d, family = binomial()), error = function(e) e)
  if (inherits(m, "error")) {
    return(list(overall_p = NA_real_, n = n, rows = .empty_uv_row(x, or_cell = "NE")))
  }
  overall_p <- tryCatch({
    a <- stats::anova(m, test = "LRT")
    pv <- a$`Pr(>Chi)`
    pv <- pv[!is.na(pv)]
    if (!length(pv)) NA_real_ else as.numeric(pv[length(pv)])
  }, error = function(e) NA_real_)
  ci <- tryCatch(suppressMessages(stats::confint.default(m)), error = function(e) NULL)
  sm <- summary(m)$coefficients
  if (is.numeric(df[[x]]) || is.integer(df[[x]])) {
    est <- sm[2L, 1L]
    lo <- if (!is.null(ci)) ci[2L, 1L] else NA_real_
    hi <- if (!is.null(ci)) ci[2L, 2L] else NA_real_
    p <- sm[2L, 4L]
    rows <- .empty_uv_row(
      x, "Median (Q1, Q3)", .cont_stat(df[[x]]),
      pub_fmt_est_ci_p(exp(est), exp(lo), exp(hi), p)
    )
  } else {
    levs <- levels(d[[x]])
    rows <- vector("list", length(levs))
    for (i in seq_along(levs)) {
      k <- sum(d[[x]] == levs[i], na.rm = TRUE)
      if (i == 1L) {
        rows[[i]] <- .empty_uv_row(x, levs[i], .n_pct(k, n), "")
      } else {
        rn <- paste0("`", x, "`", levs[i])
        hit <- which(rownames(sm) == rn)
        if (!length(hit)) hit <- which(grepl(levs[i], rownames(sm), fixed = TRUE))
        cell <- if (!length(hit)) {
          "NE"
        } else {
          j <- hit[1L]
          pub_fmt_est_ci_p(exp(sm[j, 1L]), exp(ci[j, 1L]), exp(ci[j, 2L]), sm[j, 4L])
        }
        rows[[i]] <- .empty_uv_row("", levs[i], .n_pct(k, n), cell)
      }
    }
    rows <- do.call(rbind, rows)
  }
  list(overall_p = if (is.numeric(df[[x]]) || is.integer(df[[x]])) sm[2L, 4L] else overall_p,
       n = n, rows = rows)
}

fits <- lapply(cands, .fit_one)
names(fits) <- cands
uv_rows <- do.call(rbind, lapply(fits, `[[`, "rows"))
rownames(uv_rows) <- NULL
uv_p <- vapply(fits, function(z) z$overall_p, numeric(1))
uv_pass <- cands[is.finite(uv_p) & uv_p < uv_p_cut]
# Age is eligible for VIF removal: in this cohort it is collinear with Age at onset
# (Pearson r = 0.76, VIF about 4.9) and loses its independent association once both are entered.
force_keep <- intersect("Sex", cands)
vif_cand <- unique(c(force_keep, uv_pass))
vif_cand <- suicide_order_table_vars(vif_cand)

.calc_vif <- function(vars, data) {
  vars <- vars[vars %in% names(data)]
  if (length(vars) <= 1L) {
    return(stats::setNames(rep(NA_real_, length(vars)), vars))
  }
  sub <- data[stats::complete.cases(data[, vars, drop = FALSE]), vars, drop = FALSE]
  safe <- paste0("V", seq_along(vars), "_")
  names(sub) <- safe
  for (v in safe) {
    if (is.factor(sub[[v]]) || is.character(sub[[v]])) sub[[v]] <- as.numeric(as.factor(sub[[v]]))
  }
  mm <- tryCatch(stats::model.matrix(~ ., data = sub)[, -1L, drop = FALSE], error = function(e) NULL)
  if (is.null(mm) || ncol(mm) < 2L) return(stats::setNames(rep(NA_real_, length(vars)), vars))
  out <- stats::setNames(rep(NA_real_, length(vars)), vars)
  r2 <- vapply(seq_len(ncol(mm)), function(j) {
    summary(stats::lm(mm[, j] ~ mm[, -j, drop = FALSE]))$r.squared
  }, numeric(1))
  vif_col <- 1 / (1 - r2)
  vif_col[!is.finite(vif_col)] <- Inf
  for (i in seq_along(vars)) {
    hit <- colnames(mm) == safe[i] | startsWith(colnames(mm), safe[i])
    if (any(hit)) out[[vars[i]]] <- max(vif_col[hit])
  }
  out
}

working <- vif_cand
removed <- character(0)
removed_vif <- numeric(0)
final_vif <- NULL
repeat {
  if (length(working) <= 1L) {
    final_vif <- .calc_vif(working, df)
    break
  }
  vx <- .calc_vif(working, df)
  dropable <- setdiff(working, force_keep)
  if (!length(dropable)) {
    final_vif <- vx
    break
  }
  worst <- dropable[which.max(vx[dropable])]
  worst_vif <- unname(vx[worst])
  if (!is.finite(worst_vif) || worst_vif < vif_thr) {
    final_vif <- vx
    break
  }
  message(sprintf("[step04] VIF drop: %s (VIF=%.3f)", worst, worst_vif))
  removed <- c(removed, worst)
  removed_vif <- c(removed_vif, worst_vif)
  working <- setdiff(working, worst)
}

Model2Factors <- suicide_order_table_vars(unique(c(force_keep, working)))
Model2Factors <- setdiff(Model2Factors, nodes)

uv_summary <- data.frame(
  variable = cands,
  n = vapply(fits, function(z) z$n, integer(1)),
  p_value = uv_p,
  pass_uv = cands %in% uv_pass,
  stringsAsFactors = FALSE
)
vif_summary <- data.frame(
  variable = c(names(final_vif), removed),
  VIF = c(as.numeric(final_vif), removed_vif),
  status = c(rep("Retained", length(final_vif)), rep("Removed", length(removed))),
  stringsAsFactors = FALSE
)
vif_summary <- vif_summary[match(suicide_order_table_vars(vif_summary$variable), vif_summary$variable), , drop = FALSE]

utils::write.csv(uv_summary, file.path(step_dir, "uv_table.csv"), row.names = FALSE, fileEncoding = "UTF-8")
utils::write.csv(vif_summary, file.path(step_dir, "vif_screen.csv"), row.names = FALSE, fileEncoding = "UTF-8")
writeLines(Model2Factors, file.path(step_dir, "Model2Factors.txt"))
cov_dir <- file.path(study_root, "covariates")
dir.create(cov_dir, recursive = TRUE, showWarnings = FALSE)
utils::write.csv(uv_summary, file.path(cov_dir, "uv_table.csv"), row.names = FALSE, fileEncoding = "UTF-8")
utils::write.csv(vif_summary, file.path(cov_dir, "vif_screen.csv"), row.names = FALSE, fileEncoding = "UTF-8")
writeLines(Model2Factors, file.path(cov_dir, "Model2Factors.txt"))

vif_show <- data.frame(
  Variable = vif_summary$variable,
  VIF = ifelse(is.finite(vif_summary$VIF), pub_format_est(vif_summary$VIF), "NE"),
  Decision = vif_summary$status,
  stringsAsFactors = FALSE
)
vif_final <- data.frame(
  Variable = names(final_vif),
  VIF = ifelse(is.finite(final_vif), pub_format_est(as.numeric(final_vif)), "NE"),
  stringsAsFactors = FALSE
)
vif_final <- vif_final[match(suicide_order_table_vars(vif_final$Variable), vif_final$Variable), , drop = FALSE]
utils::write.csv(vif_final, file.path(step_dir, "vif_final.csv"), row.names = FALSE, fileEncoding = "UTF-8")
utils::write.csv(vif_final, file.path(cov_dir, "vif_final.csv"), row.names = FALSE, fileEncoding = "UTF-8")
m2_show <- data.frame(
  Variable = Model2Factors,
  Role = ifelse(Model2Factors %in% force_keep, "Forced (Sex)", "UV pass and VIF < 4"),
  stringsAsFactors = FALSE
)

.table_queue_env$items <- list()
export_sci_table(
  uv_rows,
  file.path(tab_dir, "Table. Univariate logistic regression for C-SSRS ideation at 1st.xlsx"),
  title = "Table. Univariate logistic regression for C-SSRS ideation at 1st",
  table_footnotes = c(
    paste0("Outpatient N = ", nrow(df), " after multiple imputation of baseline covariates."),
    "Outcome: C-SSRS ideation, 1st (item 2, active suicidal thoughts; Yes = 1, No = 0).",
    "Layout follows the univariate regression table: continuous variables show median (Q1, Q3); categorical variables show n (%), with the first level as the reference (OR cell blank).",
    "OR (univariable) is from a separate logistic model for each variable. Continuous OR is per 1-unit increase. P is the Wald P for that contrast.",
    "Screen: overall P < 0.10. Sex is retained for the VIF step even if P >= 0.10.",
    "HAMD-17, HAMA-14 and C-SSRS nodes were not screened as covariates.",
    paste0("Not screened because missingness >= 40%: ", if (length(drop_hi)) paste(drop_hi, collapse = ", ") else "none.")
  )
)
export_sci_table(
  vif_show,
  file.path(tab_dir, "Table. Variance inflation factors among univariate candidates.xlsx"),
  title = "Table. Variance inflation factors among univariate candidates",
  table_footnotes = c(
    "Candidates are covariates with univariate P < 0.10, plus Sex.",
    "VIF threshold = 4. The covariate with the largest VIF at or above 4 was removed and VIF was recalculated. Sex was not removed.",
    "Age was removed because it was collinear with Age at onset. Age at onset was retained.",
    "Binary factors were entered as numeric codes for the VIF calculation."
  )
)
# Published final VIF table is the joint model: retained covariates plus both
# Index totals. vif_final.csv stays the covariate-only screen used to lock Model 2.
hamd_i_pub <- "HAMD-17 total, Index"
hama_i_pub <- "HAMA-14 total, Index"
joint_vif <- .calc_vif(c(vif_final$Variable, hamd_i_pub, hama_i_pub), df)
vif_pub <- data.frame(
  Variable = c(vif_final$Variable, "HAMD-index", "HAMA-index"),
  VIF = pub_format_est(as.numeric(joint_vif[c(vif_final$Variable, hamd_i_pub, hama_i_pub)])),
  stringsAsFactors = FALSE
)
export_sci_table(
  vif_pub,
  file.path(tab_dir, "Table. Final variance inflation factors after removing collinear covariates.xlsx"),
  title = "Table. Final variance inflation factors after removing collinear covariates",
  table_footnotes = c(
    paste0(
      "Outpatient N = ", nrow(df),
      ". One model: the ", nrow(vif_final),
      " retained covariates plus HAMD-index and HAMA-index. Every VIF in this table is from that model."
    ),
    "Removed before the covariates were locked: Age Medication Intake (VIF = 7.511) and Age (VIF = 4.921). Those two were not put back.",
    "Age was removed for collinearity with Age at onset. Age at onset was retained.",
    paste0(
      "The threshold of 4 was used only to drop covariates. HAMD-index (VIF = ",
      pub_format_est(joint_vif[[hamd_i_pub]]),
      ") and HAMA-index (VIF = ",
      pub_format_est(joint_vif[[hama_i_pub]]),
      ") were added after that screen. Both are below 5. CSSRS-index is not in this model. Binary factors were entered as numeric codes."
    ),
    "HAMD-index is the HAMD-17 total at Index. HAMA-index is the HAMA-14 total at Index."
  )
)
export_sci_table(
  m2_show,
  file.path(tab_dir, "Table. Covariates retained after univariate and VIF screening.xlsx"),
  title = "Table. Covariates retained after univariate and VIF screening",
  table_footnotes = c(
    "These covariates are the adjustment set for the subsequent Index to 1st paths.",
    "Age was removed for collinearity with Age at onset. Age at onset was retained.",
    "They do not include HAMD-17 total, HAMA-14 total, or C-SSRS ideation."
  )
)
suicide_clpm_flush_sci_tables()

# Extra report, not part of covariate screening. The screen excludes the scale
# totals. After Model 2 is locked, both Index totals are entered together with
# those covariates so their mutual VIF can be reported. CSSRS-index is not included.
hamd_i <- "HAMD-17 total, Index"
hama_i <- "HAMA-14 total, Index"
scale_vif <- .calc_vif(c(Model2Factors, hamd_i, hama_i), df)
scale_show <- data.frame(
  Predictor = c("HAMD-index", "HAMA-index"),
  VIF = pub_format_est(as.numeric(scale_vif[c(hamd_i, hama_i)])),
  stringsAsFactors = FALSE
)
utils::write.csv(scale_show, file.path(step_dir, "vif_hamd_hama_with_model2.csv"),
                 row.names = FALSE, fileEncoding = "UTF-8")
.table_queue_env$items <- list()
export_sci_table(
  scale_show,
  file.path(tab_dir, "Table. VIF of HAMD-index and HAMA-index with retained covariates.xlsx"),
  title = "Table. VIF of HAMD-index and HAMA-index with retained covariates",
  table_footnotes = c(
    paste0("Outpatient N = ", nrow(df), ". Calculated after the covariate VIF screen, with the same numeric-code method."),
    "The covariate screen did not include the scale totals. This table enters HAMD-index and HAMA-index together with the 12 retained covariates and reports the VIF of each total.",
    "HAMD-index and HAMA-index are the scale totals at Index (about 3 days before discharge). CSSRS-index is not in this model. The 12 covariates are the retained Model 2 set."
  )
)
suicide_clpm_flush_sci_tables()

meta <- data.frame(
  step = "step04_univariate_vif",
  n = nrow(df),
  screen_outcome = screen_y,
  n_screened = length(cands),
  n_uv_pass = length(uv_pass),
  n_model2 = length(Model2Factors),
  uv_p_cutoff = uv_p_cut,
  vif_threshold = vif_thr,
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)
utils::write.csv(meta, file.path(step_dir, "step_meta.csv"), row.names = FALSE, fileEncoding = "UTF-8")
message("[step04] UV pass: ", paste(uv_pass, collapse = ", "))
message("[step04] VIF removed: ", if (length(removed)) paste(removed, collapse = ", ") else "(none)")
message("[step04] Model2 (", length(Model2Factors), "): ", paste(Model2Factors, collapse = ", "))
message("[step04] DONE ", step_dir)
