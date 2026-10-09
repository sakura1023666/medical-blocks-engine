#!/usr/bin/env Rscript
# =============================================================================
# Task 6 / Task 8 — 自杀 CLPM 九条路径估计 + 主表
#
# 用法:
#   Rscript run/cross_lagged/run_suicide_clpm_paths.R
#   Rscript run/cross_lagged/run_suicide_clpm_paths.R --cohort ward
#   SUICIDE_CLPM_COHORT=ward CROSS_LAGGED_STUDY_ROOT=/path Rscript ...
#
# 产出:
#   outpatient → Table2_CLPM_paths.csv (+ xlsx)
#   ward       → TableS3_ward_CLPM_paths.csv (+ xlsx); Exploratory；复用门诊 Model2
# =============================================================================

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

# --- path specs (sourced by tests) -------------------------------------------
suicide_clpm_path_specs <- function() {
  list(
    list(name = "HAMD_AR", y = "HAMD_1st", x = c("HAMD_Index"), type = "lm"),
    list(name = "HAMA_AR", y = "HAMA_1st", x = c("HAMA_Index"), type = "lm"),
    list(name = "CSSRS_AR", y = "CSSRS_1st", x = c("CSSRS_Index"), type = "logit"),
    list(
      name = "HAMD_to_CSSRS", y = "CSSRS_1st",
      x = c("HAMD_Index", "HAMA_Index", "CSSRS_Index"), type = "logit", focus = "HAMD_Index"
    ),
    list(
      name = "HAMA_to_CSSRS", y = "CSSRS_1st",
      x = c("HAMA_Index", "HAMD_Index", "CSSRS_Index"), type = "logit", focus = "HAMA_Index"
    ),
    list(
      name = "CSSRS_to_HAMD", y = "HAMD_1st",
      x = c("CSSRS_Index", "HAMD_Index", "HAMA_Index"), type = "lm", focus = "CSSRS_Index"
    ),
    list(
      name = "CSSRS_to_HAMA", y = "HAMA_1st",
      x = c("CSSRS_Index", "HAMA_Index", "HAMD_Index"), type = "lm", focus = "CSSRS_Index"
    ),
    list(
      name = "HAMD_to_HAMA", y = "HAMA_1st",
      x = c("HAMD_Index", "HAMA_Index"), type = "lm", focus = "HAMD_Index"
    ),
    list(
      name = "HAMA_to_HAMD", y = "HAMD_1st",
      x = c("HAMA_Index", "HAMD_Index"), type = "lm", focus = "HAMA_Index"
    )
  )
}

suicide_clpm_nodes <- function() {
  c("HAMD_Index", "HAMD_1st", "HAMA_Index", "HAMA_1st", "CSSRS_Index", "CSSRS_1st")
}

.suicide_clpm_resolve_focus <- function(spec) {
  if (!is.null(spec$focus) && nzchar(spec$focus)) return(as.character(spec$focus)[1L])
  as.character(spec$x)[1L]
}

# Specs-only source for tests: set options(suicide_clpm_paths_specs_only = TRUE)
if (!isTRUE(getOption("suicide_clpm_paths_specs_only", FALSE))) {

.suicide_clpm_resolve_cohort <- function() {
  ca <- commandArgs(trailingOnly = TRUE)
  hit <- grep("^--cohort(=|$)", ca, value = TRUE)
  from_arg <- ""
  if (length(hit)) {
    if (grepl("=", hit[1L], fixed = TRUE)) {
      from_arg <- sub("^--cohort=", "", hit[1L])
    } else {
      ix <- match(hit[1L], ca)
      if (!is.na(ix) && ix < length(ca)) from_arg <- ca[ix + 1L]
    }
  }
  from_env <- Sys.getenv("SUICIDE_CLPM_COHORT", unset = "")
  cohort <- tolower(trimws(if (nzchar(from_arg)) from_arg else from_env))
  if (!nzchar(cohort)) cohort <- "outpatient"
  if (!cohort %in% c("outpatient", "ward")) {
    stop("Invalid cohort '", cohort, "'; use outpatient|ward")
  }
  cohort
}

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) {
  study_root <- file.path(engine_root, ".superpowers/sdd/study_mirror")
}
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

cohort <- .suicide_clpm_resolve_cohort()
is_ward <- identical(cohort, "ward")
tag <- if (is_ward) "[Task8/ward]" else "[Task6]"

nodes <- suicide_clpm_nodes()
paths <- suicide_clpm_path_specs()
stopifnot(length(paths) == 9L)

m2_path <- file.path(study_root, "covariates/Model2Factors.txt")
if (!file.exists(m2_path)) stop("Missing Model2Factors: ", m2_path)
Model2Factors <- trimws(readLines(m2_path, warn = FALSE))
Model2Factors <- Model2Factors[nzchar(Model2Factors)]
leak <- intersect(Model2Factors, nodes)
if (length(leak)) {
  warning(tag, " stripping nodes from Model2: ", paste(leak, collapse = ", "))
  Model2Factors <- setdiff(Model2Factors, leak)
}
model2_source_note <- if (is_ward) {
  "reuse_outpatient_Model2Factors (Exploratory comparability)"
} else {
  "outpatient_UV_VIF_Model2"
}

stem <- if (is_ward) "ward" else "outpatient"
imp_path <- file.path(study_root, sprintf("data/harmonized/D04_%s_clpm_imputed.RData", stem))
raw_path <- file.path(study_root, sprintf("data/harmonized/D04_%s_clpm.RData", stem))
data_path <- if (file.exists(imp_path)) imp_path else raw_path
if (!file.exists(data_path)) stop("Missing analysis data under ", dirname(raw_path))
message(tag, " cohort = ", cohort)
message(tag, " study_root = ", study_root)
message(tag, " loading ", data_path)
message(tag, " Model2 source: ", model2_source_note)
load(data_path, envir = .GlobalEnv)
if (!exists("dabiao", inherits = FALSE)) stop("Object 'dabiao' not found")
df0 <- dabiao
stopifnot(is.data.frame(df0), nrow(df0) > 0L)

miss_nodes <- setdiff(nodes, names(df0))
if (length(miss_nodes)) stop("Missing node columns: ", paste(miss_nodes, collapse = ", "))
m2_present <- intersect(Model2Factors, names(df0))
m2_miss <- setdiff(Model2Factors, names(df0))
if (length(m2_miss)) {
  message(tag, " Model2 cols absent (dropped): ", paste(m2_miss, collapse = ", "))
}
Model2Factors <- m2_present
message(tag, " Model2Factors n=", length(Model2Factors), ": ", paste(Model2Factors, collapse = ", "))

# Coerce CSSRS to 0/1 integer
.as01 <- function(x) {
  if (is.factor(x) || is.character(x)) {
    xc <- as.character(x)
    as.integer(xc %in% c("1", "Yes", "yes", "TRUE", "true"))
  } else {
    as.integer(x)
  }
}
df0$CSSRS_Index <- .as01(df0$CSSRS_Index)
df0$CSSRS_1st <- .as01(df0$CSSRS_1st)
# Drop incomplete on six nodes (should already be complete)
ok_nodes <- stats::complete.cases(df0[, nodes, drop = FALSE])
if (!all(ok_nodes)) {
  message(tag, " drop ", sum(!ok_nodes), " rows with incomplete nodes")
  df0 <- df0[ok_nodes, , drop = FALSE]
}

.btick <- function(v) paste0("`", gsub("`", "", v, fixed = TRUE), "`")

# Drop sparse / near-singular covariates (esp. ward n≈102 Exploratory)
.drop_sparse_covars <- function(data, covars, min_level_n = 5L) {
  keep <- character(0)
  dropped <- character(0)
  for (v in covars) {
    if (!v %in% names(data)) {
      dropped <- c(dropped, paste0(v, ":absent"))
      next
    }
    x <- data[[v]]
    if (is.character(x)) x <- factor(x)
    if (is.factor(x)) {
      x <- droplevels(x[!is.na(x)])
      if (nlevels(x) < 2L) {
        dropped <- c(dropped, paste0(v, ":lt2_levels"))
        next
      }
      tabn <- table(x)
      if (any(as.integer(tabn) < min_level_n)) {
        dropped <- c(dropped, paste0(v, ":sparse_level<", min_level_n))
        next
      }
    } else if (is.numeric(x)) {
      xu <- unique(x[!is.na(x)])
      if (length(xu) < 2L) {
        dropped <- c(dropped, paste0(v, ":constant"))
        next
      }
    }
    keep <- c(keep, v)
  }
  list(keep = keep, dropped = dropped)
}

sparse_info <- .drop_sparse_covars(df0, Model2Factors, min_level_n = if (is_ward) 5L else 1L)
if (length(sparse_info$dropped)) {
  message(tag, " sparse covars dropped: ", paste(sparse_info$dropped, collapse = "; "))
}
Model2Factors <- sparse_info$keep
concerns <- character(0)
if (is_ward && length(sparse_info$dropped)) {
  concerns <- c(concerns, paste0("dropped_sparse_Model2=", paste(sparse_info$dropped, collapse = "|")))
}
message(tag, " Model2Factors after sparse filter n=", length(Model2Factors),
        ": ", paste(Model2Factors, collapse = ", "))

.fit_one_path <- function(spec, data, covars) {
  focus <- .suicide_clpm_resolve_focus(spec)
  rhs_vars <- unique(c(as.character(spec$x), covars))
  rhs_vars <- rhs_vars[rhs_vars %in% names(data)]
  y <- as.character(spec$y)[1L]
  use_cols <- unique(c(y, rhs_vars))
  d <- data[, use_cols, drop = FALSE]
  # factorize characters among covariates
  for (v in setdiff(rhs_vars, c(nodes, focus))) {
    if (is.character(d[[v]])) d[[v]] <- factor(d[[v]])
  }
  d <- d[stats::complete.cases(d), , drop = FALSE]
  n <- nrow(d)
  fml <- stats::as.formula(paste(
    .btick(y), "~", paste(.btick(rhs_vars), collapse = " + ")
  ))
  type <- as.character(spec$type)[1L]

  if (identical(type, "logit")) {
    d[[y]] <- .as01(d[[y]])
    m <- stats::glm(fml, data = d, family = stats::binomial())
    cf <- stats::coef(m)
    cn2 <- gsub("`", "", names(cf), fixed = TRUE)
    hit <- which(cn2 == focus)
    if (!length(hit)) {
      return(data.frame(
        path = spec$name, model = paste(deparse(fml), collapse = " "),
        estimate = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
        p = NA_real_, n = n, effect_type = "OR", focus = focus,
        note = paste0("focus_coef_missing:", focus),
        stringsAsFactors = FALSE
      ))
    }
    j <- hit[1L]
    sm <- summary(m)$coefficients
    rn2 <- gsub("`", "", rownames(sm), fixed = TRUE)
    sj <- which(rn2 == focus)[1L]
    pval <- if (!is.na(sj)) as.numeric(sm[sj, 4L]) else NA_real_
    ci_mat <- stats::confint.default(m)
    rownames(ci_mat) <- gsub("`", "", rownames(ci_mat), fixed = TRUE)
    ci <- ci_mat[focus, ]
    na_coef <- any(!is.finite(cf))
    note_ok <- if (na_coef) "ok_with_NA_coef_singularity" else "ok"
    data.frame(
      path = spec$name,
      model = paste(deparse(fml), collapse = " "),
      estimate = as.numeric(exp(cf[j])),
      ci_low = as.numeric(exp(ci[1L])),
      ci_high = as.numeric(exp(ci[2L])),
      p = pval,
      n = n,
      effect_type = "OR",
      focus = focus,
      note = note_ok,
      stringsAsFactors = FALSE
    )
  } else if (identical(type, "lm")) {
    # Raw-scale model for P
    m_raw <- stats::lm(fml, data = d)
    sm <- summary(m_raw)$coefficients
    rn2 <- gsub("`", "", rownames(sm), fixed = TRUE)
    sj <- which(rn2 == focus)[1L]
    if (is.na(sj)) {
      return(data.frame(
        path = spec$name, model = paste(deparse(fml), collapse = " "),
        estimate = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
        p = NA_real_, n = n, effect_type = "std_beta", focus = focus,
        note = paste0("focus_coef_missing:", focus),
        stringsAsFactors = FALSE
      ))
    }
    pval <- as.numeric(sm[sj, 4L])

    # Standardized beta: scale y and focus x; other predictors unscaled
    d_std <- d
    d_std[[y]] <- as.numeric(scale(as.numeric(d[[y]])))
    d_std[[focus]] <- as.numeric(scale(as.numeric(d[[focus]])))
    m_std <- stats::lm(fml, data = d_std)
    cf_std <- stats::coef(m_std)
    cn2 <- gsub("`", "", names(cf_std), fixed = TRUE)
    j <- which(cn2 == focus)[1L]
    ci_std <- tryCatch({
      ci_m <- stats::confint(m_std)
      rownames(ci_m) <- gsub("`", "", rownames(ci_m), fixed = TRUE)
      ci_m[focus, ]
    }, error = function(e) c(NA_real_, NA_real_))
    data.frame(
      path = spec$name,
      model = paste(deparse(fml), collapse = " "),
      estimate = as.numeric(cf_std[j]),
      ci_low = as.numeric(ci_std[1L]),
      ci_high = as.numeric(ci_std[2L]),
      p = pval,
      n = n,
      effect_type = "std_beta",
      focus = focus,
      note = "ok; p_from_raw_lm; beta_y_and_focus_scaled",
      stringsAsFactors = FALSE
    )
  } else {
    stop("Unknown path type: ", type)
  }
}

rows <- lapply(paths, function(sp) {
  message(tag, " fitting ", sp$name, " (", sp$type, ", focus=", .suicide_clpm_resolve_focus(sp), ")")
  tryCatch(
    .fit_one_path(sp, df0, Model2Factors),
    error = function(e) {
      data.frame(
        path = sp$name, model = NA_character_,
        estimate = NA_real_, ci_low = NA_real_, ci_high = NA_real_,
        p = NA_real_, n = NA_integer_, effect_type = if (identical(sp$type, "logit")) "OR" else "std_beta",
        focus = .suicide_clpm_resolve_focus(sp),
        note = paste0("ERROR: ", conditionMessage(e)),
        stringsAsFactors = FALSE
      )
    }
  )
})
tab <- do.call(rbind, rows)
rownames(tab) <- NULL
tab$cohort <- cohort
tab$analysis_label <- if (is_ward) "Exploratory" else "Main"
tab$model2_source <- model2_source_note
if (any(grepl("ERROR|singularity|NA_coef|focus_coef_missing", tab$note, ignore.case = TRUE))) {
  concerns <- c(concerns, "path_fit_issues_see_note_column")
}

out_dir <- file.path(study_root, "summary_result/table")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
out_base <- if (is_ward) "TableS3_ward_CLPM_paths" else "Table2_CLPM_paths"
csv_path <- file.path(out_dir, paste0(out_base, ".csv"))
utils::write.csv(tab, csv_path, row.names = FALSE)
message(tag, " wrote ", csv_path)

xlsx_path <- file.path(out_dir, paste0(out_base, ".xlsx"))
if (requireNamespace("openxlsx", quietly = TRUE)) {
  openxlsx::write.xlsx(tab, xlsx_path, overwrite = TRUE)
  message(tag, " wrote ", xlsx_path)
} else {
  message(tag, " openxlsx not available; skip xlsx")
}

if (is_ward) {
  note_path <- file.path(out_dir, "TableS3_ward_CLPM_paths_Exploratory_NOTE.txt")
  writeLines(c(
    "Table S3 — Ward Exploratory CLPM paths (NOT merged into main Table 2)",
    paste0("cohort=ward; n_six_node=", nrow(df0)),
    paste0("Model2=", model2_source_note),
    paste0("Model2_used=", paste(Model2Factors, collapse = ",")),
    paste0("concerns=", if (length(concerns)) paste(concerns, collapse = "; ") else "none"),
    paste0("status=", if (length(concerns)) "DONE_WITH_CONCERNS" else "DONE")
  ), note_path)
  message(tag, " wrote ", note_path)
}

# Print brief significance summary
sig <- tab[!is.na(tab$p) & tab$p < 0.05, c("path", "estimate", "ci_low", "ci_high", "p", "effect_type"), drop = FALSE]
message(tag, " significant (p<0.05) n=", nrow(sig))
if (nrow(sig)) print(sig, row.names = FALSE)
if (length(concerns)) message(tag, " DONE_WITH_CONCERNS: ", paste(concerns, collapse = "; "))

# --- sync UNC if mounted ---
unc_candidates <- c(
  Sys.getenv("CROSS_LAGGED_SYNC_ROOT", unset = ""),
  "/mnt/g/02block_result/43_Suicide/cross-laged_40595747",
  "/mnt/e/02block_result/43_Suicide/cross-laged_40595747"
)
unc_root <- ""
for (p in unc_candidates) {
  if (nzchar(p) && dir.exists(p)) {
    unc_root <- p
    break
  }
}
if (nzchar(unc_root)) {
  unc_tab <- file.path(unc_root, "summary_result/table")
  dir.create(unc_tab, recursive = TRUE, showWarnings = FALSE)
  file.copy(csv_path, file.path(unc_tab, basename(csv_path)), overwrite = TRUE)
  if (file.exists(xlsx_path)) {
    file.copy(xlsx_path, file.path(unc_tab, basename(xlsx_path)), overwrite = TRUE)
  }
  if (is_ward) {
    note_path <- file.path(out_dir, "TableS3_ward_CLPM_paths_Exploratory_NOTE.txt")
    if (file.exists(note_path)) {
      file.copy(note_path, file.path(unc_tab, basename(note_path)), overwrite = TRUE)
    }
  }
  message(tag, " synced ", out_base, " → ", unc_tab)
} else {
  message(tag, " UNC study root not found; skip sync")
}

invisible(tab)

} # end !specs_only
