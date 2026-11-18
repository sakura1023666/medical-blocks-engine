#!/usr/bin/env Rscript
# step05 — nine pre-registered CLPM paths on the step02 imputed outpatient cohort.
# Continuous 1st outcomes: linear model, standardized beta (outcome and focus scaled).
# C-SSRS ideation, 1st: logistic OR per 1 unit of the focus predictor.
# Covariates: step04 Model2 (Age and Age Medication Intake already removed).
# Does not re-run MICE. Does not fit the ward cohort.
#
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_step05_paths.R

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

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)

source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "run/cross_lagged/suicide_clpm_step_sci_tables.R"), local = FALSE)

.cfg_env <- new.env(parent = globalenv())
sys.source(file.path(study_root, "config_suicide_clpm.R"), envir = .cfg_env)
config <- .cfg_env$config
if (exists("pipeline_apply_pub_digits", mode = "function")) pipeline_apply_pub_digits(config)

hamd_i <- "HAMD-17 total, Index"
hamd_f <- "HAMD-17 total, 1st"
hama_i <- "HAMA-14 total, Index"
hama_f <- "HAMA-14 total, 1st"
css_i <- "C-SSRS ideation, Index"
css_f <- "C-SSRS ideation, 1st"
nodes <- c(hamd_i, hamd_f, hama_i, hama_f, css_i, css_f)

# Pre-registered nine paths. Cross-lag models keep the outcome's own Index.
paths <- list(
  list(name = "HAMD-17 autoregression", role = "Autoregression",
       y = hamd_f, x = c(hamd_i), type = "lm", focus = hamd_i),
  list(name = "HAMA-14 autoregression", role = "Autoregression",
       y = hama_f, x = c(hama_i), type = "lm", focus = hama_i),
  list(name = "C-SSRS ideation autoregression", role = "Autoregression",
       y = css_f, x = c(css_i), type = "logit", focus = css_i),
  list(name = "HAMD-17 to C-SSRS ideation", role = "Cross-lag",
       y = css_f, x = c(hamd_i, hama_i, css_i), type = "logit", focus = hamd_i),
  list(name = "HAMA-14 to C-SSRS ideation", role = "Cross-lag",
       y = css_f, x = c(hama_i, hamd_i, css_i), type = "logit", focus = hama_i),
  list(name = "C-SSRS ideation to HAMD-17", role = "Cross-lag",
       y = hamd_f, x = c(css_i, hamd_i, hama_i), type = "lm", focus = css_i),
  list(name = "C-SSRS ideation to HAMA-14", role = "Cross-lag",
       y = hama_f, x = c(css_i, hama_i, hamd_i), type = "lm", focus = css_i),
  list(name = "HAMD-17 to HAMA-14", role = "Cross-lag",
       y = hama_f, x = c(hamd_i, hama_i), type = "lm", focus = hamd_i),
  list(name = "HAMA-14 to HAMD-17", role = "Cross-lag",
       y = hamd_f, x = c(hama_i, hamd_i), type = "lm", focus = hama_i)
)
stopifnot(length(paths) == 9L)

step_dir <- file.path(study_root, "step05_clpm_paths")
tab_dir <- file.path(step_dir, "Tables")
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)

src <- file.path(study_root, "step02_imputation/dabiao.RData")
if (!file.exists(src)) stop("Missing step02 dabiao: ", src, call. = FALSE)
e <- new.env(parent = emptyenv())
load(src, envir = e)
if (!exists("dabiao", envir = e)) stop("Object 'dabiao' not found in ", src, call. = FALSE)
df <- e$dabiao
miss_nodes <- setdiff(nodes, names(df))
if (length(miss_nodes)) stop("Missing node columns: ", paste(miss_nodes, collapse = ", "), call. = FALSE)

m2_path <- file.path(study_root, "step04_univariate_vif/Model2Factors.txt")
if (!file.exists(m2_path)) stop("Missing Model2Factors: ", m2_path, call. = FALSE)
Model2Factors <- trimws(readLines(m2_path, warn = FALSE))
Model2Factors <- Model2Factors[nzchar(Model2Factors)]
leak <- intersect(Model2Factors, nodes)
if (length(leak)) stop("Nodes leaked into Model2: ", paste(leak, collapse = ", "), call. = FALSE)
m2_miss <- setdiff(Model2Factors, names(df))
if (length(m2_miss)) stop("Model2 columns absent: ", paste(m2_miss, collapse = ", "), call. = FALSE)

.as01 <- function(x) {
  if (is.factor(x) || is.character(x)) {
    xc <- trimws(as.character(x))
    as.integer(xc %in% c("1", "Yes", "yes", "YES", "A", "是", "TRUE", "true"))
  } else {
    as.integer(x)
  }
}
df[[css_i]] <- .as01(df[[css_i]])
df[[css_f]] <- .as01(df[[css_f]])
if (!all(df[[css_i]] %in% c(0L, 1L)) || !all(df[[css_f]] %in% c(0L, 1L))) {
  stop("C-SSRS nodes are not 0/1 after recode", call. = FALSE)
}

ok_nodes <- stats::complete.cases(df[, nodes, drop = FALSE])
if (!all(ok_nodes)) {
  stop("Node missingness after step01 listwise: ", sum(!ok_nodes), call. = FALSE)
}

.btick <- function(v) paste0("`", gsub("`", "", v, fixed = TRUE), "`")

.fit_one_path <- function(spec, data, covars) {
  focus <- spec$focus
  y <- spec$y
  rhs_vars <- unique(c(spec$x, covars))
  d <- data[, unique(c(y, rhs_vars)), drop = FALSE]
  for (v in setdiff(rhs_vars, nodes)) {
    if (is.character(d[[v]])) d[[v]] <- factor(d[[v]])
  }
  d <- d[stats::complete.cases(d), , drop = FALSE]
  n <- nrow(d)
  fml <- stats::as.formula(paste(.btick(y), "~", paste(.btick(rhs_vars), collapse = " + ")))
  also <- setdiff(spec$x, focus)
  base <- data.frame(
    path = spec$name,
    role = spec$role,
    outcome = y,
    predictor = focus,
    also_adjusted_index = if (length(also)) paste(also, collapse = "; ") else "None",
    n = n,
    stringsAsFactors = FALSE
  )
  if (identical(spec$type, "logit")) {
    d[[y]] <- .as01(d[[y]])
    m <- stats::glm(fml, data = d, family = stats::binomial())
    sm <- summary(m)$coefficients
    rn <- gsub("`", "", rownames(sm), fixed = TRUE)
    sj <- which(rn == focus)[1L]
    if (is.na(sj)) stop("Focus coefficient missing: ", focus, call. = FALSE)
    ci <- stats::confint.default(m)
    rownames(ci) <- gsub("`", "", rownames(ci), fixed = TRUE)
    cbind(base, data.frame(
      effect = "OR",
      estimate = as.numeric(exp(sm[sj, 1L])),
      ci_low = as.numeric(exp(ci[focus, 1L])),
      ci_high = as.numeric(exp(ci[focus, 2L])),
      p = as.numeric(sm[sj, 4L]),
      stringsAsFactors = FALSE
    ))
  } else {
    m_raw <- stats::lm(fml, data = d)
    sm <- summary(m_raw)$coefficients
    rn <- gsub("`", "", rownames(sm), fixed = TRUE)
    sj <- which(rn == focus)[1L]
    if (is.na(sj)) stop("Focus coefficient missing: ", focus, call. = FALSE)
    d_std <- d
    d_std[[y]] <- as.numeric(scale(as.numeric(d[[y]])))
    d_std[[focus]] <- as.numeric(scale(as.numeric(d[[focus]])))
    m_std <- stats::lm(fml, data = d_std)
    ci <- stats::confint(m_std)
    rownames(ci) <- gsub("`", "", rownames(ci), fixed = TRUE)
    cf <- stats::coef(m_std)
    names(cf) <- gsub("`", "", names(cf), fixed = TRUE)
    cbind(base, data.frame(
      effect = "Standardized beta",
      estimate = as.numeric(cf[[focus]]),
      ci_low = as.numeric(ci[focus, 1L]),
      ci_high = as.numeric(ci[focus, 2L]),
      p = as.numeric(sm[sj, 4L]),
      stringsAsFactors = FALSE
    ))
  }
}

message("[step05] N = ", nrow(df), "; Model2 (", length(Model2Factors), "): ",
        paste(Model2Factors, collapse = ", "))
rows <- lapply(paths, function(sp) {
  message("[step05] ", sp$name)
  .fit_one_path(sp, df, Model2Factors)
})
tab <- do.call(rbind, rows)
rownames(tab) <- NULL
if (any(!is.finite(tab$estimate) | !is.finite(tab$p))) {
  stop("Non-finite path estimate", call. = FALSE)
}
utils::write.csv(tab, file.path(step_dir, "paths_results.csv"), row.names = FALSE, fileEncoding = "UTF-8")

.est_ci <- function(est, lo, hi) {
  paste0(pub_format_est(est), " (", pub_format_est(lo), ", ", pub_format_est(hi), ")")
}
show <- data.frame(
  Path = tab$path,
  Role = tab$role,
  Outcome = tab$outcome,
  Predictor = tab$predictor,
  `Also adjusted Index` = tab$also_adjusted_index,
  Effect = tab$effect,
  `Estimate (95% CI)` = .est_ci(tab$estimate, tab$ci_low, tab$ci_high),
  P = vapply(tab$p, pub_format_p_cell, character(1)),
  stringsAsFactors = FALSE,
  check.names = FALSE
)

options(pipeline.database_name = "Outpatient")
.table_queue_env$items <- list()
export_sci_table(
  show,
  file.path(tab_dir, "Table 2. Cross-lagged paths from Index to 1st.xlsx"),
  title = "Table 2. Cross-lagged paths from Index to 1st",
  table_footnotes = c(
    paste0("Outpatient N = ", nrow(df), ". Six nodes were complete before imputation and were not imputed. Baseline covariates were multiply imputed."),
    paste0("Each path is adjusted for: ", paste(Model2Factors, collapse = ", "), "."),
    "Age and Age Medication Intake were removed before these models because of collinearity.",
    "Autoregression is Index to the same scale at 1st. Cross-lag paths also include the Index nodes listed under Also adjusted Index, including the outcome's own Index.",
    "HAMD-17 to HAMA-14 and HAMA-14 to HAMD-17 do not include C-SSRS ideation, Index. The two paths into C-SSRS ideation, 1st include all three Index nodes in one logistic model; the table reports each focus coefficient.",
    "Continuous outcomes use a linear model. Standardized beta scales the 1st outcome and the focus predictor; other predictors stay on their original scale. P is the Wald P from the unstandardized linear model.",
    "C-SSRS ideation, 1st uses logistic regression. OR is per 1-point increase for HAMD-17 or HAMA-14, and for Yes versus No when the predictor is C-SSRS ideation, Index."
  )
)
suicide_clpm_flush_sci_tables()

meta <- data.frame(
  step = "step05_clpm_paths",
  n = nrow(df),
  n_paths = nrow(tab),
  n_model2 = length(Model2Factors),
  written_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  stringsAsFactors = FALSE
)
utils::write.csv(meta, file.path(step_dir, "step_meta.csv"), row.names = FALSE, fileEncoding = "UTF-8")
message("[step05] DONE ", step_dir)
print(show, row.names = FALSE)
