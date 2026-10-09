#!/usr/bin/env Rscript
# =============================================================================
# Task 5 / Task 8 — 自杀 CLPM 协变量筛选（UV → VIF → Model2）
#
# 用法:
#   Rscript run/cross_lagged/run_suicide_clpm_covariates.R
#   Rscript run/cross_lagged/run_suicide_clpm_covariates.R --cohort ward
#   SUICIDE_CLPM_COHORT=ward CROSS_LAGGED_STUDY_ROOT=/path Rscript ...
#
# 产出（研究区）:
#   outpatient:
#     covariates/uv_table.csv, vif_screen.csv, Model2Factors.txt
#     data/harmonized/D04_outpatient_clpm_imputed.RData
#   ward (Exploratory; prefer reuse outpatient Model2 — does NOT overwrite Model2):
#     covariates/ward_Model2_reuse_note.txt
#     data/harmonized/D04_ward_clpm_imputed.RData  （可选；仅协变量 MICE）
#
# 插补策略: mice(m=5, method=cart, complete_action=1) 仅对 covariate_candidate_vars；
#           六节点 + exclude_from_mice_cols 排除；缺失率 ≥0.5 的候选列先剔除不进 MICE。
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
tag <- if (is_ward) "[Task8/ward-cov]" else "[Task5]"

cfg_path <- file.path(study_root, "config_suicide_clpm.R")
if (!file.exists(cfg_path)) stop("Missing config: ", cfg_path)

# Source config into local env (sets config + covariate_candidate_vars)
.cfg_env <- new.env(parent = globalenv())
Sys.setenv(CROSS_LAGGED_STUDY_ROOT = study_root, MEDICAL_BLOCKS_ROOT = engine_root)
sys.source(cfg_path, envir = .cfg_env)
config <- .cfg_env$config
cands <- .cfg_env$covariate_candidate_vars
if (is.null(cands) || !length(cands)) {
  cands <- config$suicide_cssrs$covariate_candidate_vars
}
cands <- as.character(cands)
nodes <- as.character(config$suicide_cssrs$nodes)
mice_excl <- as.character(config$imputation$exclude_from_mice_cols %||% nodes)
screen_y <- "CSSRS_1st"
uv_p_cut <- 0.10
vif_thr <- 4
miss_drop_thr <- 0.5
seed <- as.integer(config$imputation$seed %||% 40595747L)
m_imp <- as.integer(config$imputation$m %||% 5L)
maxit <- as.integer(config$imputation$max_iter %||% 5L)

# Ward Exploratory: reuse outpatient Model2; optional covar-only MICE; never overwrite Model2Factors.txt
if (is_ward) {
  message(tag, " study_root = ", study_root)
  message(tag, " Exploratory ward: reuse outpatient Model2 (no UV/VIF re-screen)")
  m2_path <- file.path(study_root, "covariates/Model2Factors.txt")
  if (!file.exists(m2_path)) stop("Missing outpatient Model2Factors for reuse: ", m2_path)
  Model2Factors <- trimws(readLines(m2_path, warn = FALSE))
  Model2Factors <- Model2Factors[nzchar(Model2Factors)]
  Model2Factors <- setdiff(Model2Factors, nodes)

  ward_raw <- file.path(study_root, "data/harmonized/D04_ward_clpm.RData")
  if (!file.exists(ward_raw)) stop("Missing ward dabiao: ", ward_raw)
  load(ward_raw, envir = .GlobalEnv)
  if (!exists("dabiao", inherits = FALSE)) stop("Object 'dabiao' not found")
  df0 <- dabiao
  stopifnot(is.data.frame(df0), nrow(df0) > 0L)

  mice_vars <- intersect(unique(c(Model2Factors, cands)), names(df0))
  mice_vars <- setdiff(mice_vars, unique(c(nodes, mice_excl)))
  miss_rate <- vapply(mice_vars, function(v) mean(is.na(df0[[v]])), numeric(1))
  drop_hi_miss <- names(miss_rate)[miss_rate >= miss_drop_thr]
  mice_vars <- setdiff(mice_vars, drop_hi_miss)

  impute_note <- c(
    "COHORT=ward Exploratory",
    "MODEL2=reuse_outpatient_Model2Factors (comparability; UV/VIF not re-run on ward)",
    paste0("MODEL2_FACTORS=", paste(Model2Factors, collapse = ",")),
    paste0("N_SIX_NODE=", nrow(df0))
  )
  df_imp <- df0
  need_mice <- length(mice_vars) > 0L &&
    any(vapply(mice_vars, function(v) any(is.na(df0[[v]])), logical(1)))
  imp_path <- file.path(study_root, "data/harmonized/D04_ward_clpm_imputed.RData")

  if (need_mice) {
    if (!requireNamespace("mice", quietly = TRUE)) {
      message(tag, " mice unavailable — save raw as imputed copy")
      dabiao <- df_imp
      dir.create(dirname(imp_path), recursive = TRUE, showWarnings = FALSE)
      save(dabiao, file = imp_path)
      impute_note <- c(impute_note, "IMPUTATION=skipped_mice_unavailable; copied_raw")
    } else {
      set.seed(seed)
      mice_df <- df0[, mice_vars, drop = FALSE]
      for (v in names(mice_df)) {
        if (is.character(mice_df[[v]])) mice_df[[v]] <- factor(mice_df[[v]])
      }
      message(tag, " mice start: m=", m_imp, " maxit=", maxit, " method=cart")
      imp <- tryCatch(
        mice::mice(mice_df, m = m_imp, maxit = maxit, method = "cart",
                   seed = seed, printFlag = FALSE),
        error = function(e) e
      )
      if (inherits(imp, "error")) {
        message(tag, " mice failed: ", conditionMessage(imp))
        impute_note <- c(impute_note, paste0("MICE_FAILED: ", conditionMessage(imp)))
        dabiao <- df_imp
        dir.create(dirname(imp_path), recursive = TRUE, showWarnings = FALSE)
        save(dabiao, file = imp_path)
      } else {
        completed <- mice::complete(imp, action = 1L)
        for (v in names(completed)) df_imp[[v]] <- completed[[v]]
        for (v in intersect(nodes, names(df0))) df_imp[[v]] <- df0[[v]]
        dabiao <- df_imp
        dir.create(dirname(imp_path), recursive = TRUE, showWarnings = FALSE)
        save(dabiao, file = imp_path)
        impute_note <- c(
          impute_note,
          sprintf("IMPUTATION=mice_covars_only m=%d complete_action=1 method=cart seed=%d",
                  m_imp, seed),
          paste0("MICE_VARS=", paste(mice_vars, collapse = ",")),
          paste0("DROPPED_HI_MISS=", paste(drop_hi_miss, collapse = ","))
        )
        message(tag, " imputed dabiao saved: ", imp_path)
      }
    }
  } else {
    dabiao <- df_imp
    dir.create(dirname(imp_path), recursive = TRUE, showWarnings = FALSE)
    save(dabiao, file = imp_path)
    impute_note <- c(impute_note, "IMPUTATION=none_needed_or_no_mice_vars")
  }

  out_dir <- file.path(study_root, "covariates")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  note_path <- file.path(out_dir, "ward_Model2_reuse_note.txt")
  writeLines(impute_note, note_path)
  message(tag, " wrote ", note_path, " (Model2Factors.txt NOT overwritten)")

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
    unc_cov <- file.path(unc_root, "covariates")
    dir.create(unc_cov, recursive = TRUE, showWarnings = FALSE)
    file.copy(note_path, file.path(unc_cov, basename(note_path)), overwrite = TRUE)
    unc_imp <- file.path(unc_root, "data/harmonized")
    dir.create(unc_imp, recursive = TRUE, showWarnings = FALSE)
    if (file.exists(imp_path)) {
      file.copy(imp_path, file.path(unc_imp, basename(imp_path)), overwrite = TRUE)
    }
    message(tag, " synced ward cov note → ", unc_cov)
  } else {
    message(tag, " UNC study root not found; skip sync")
  }

  invisible(list(
    cohort = "ward",
    Model2Factors = Model2Factors,
    reuse = TRUE,
    impute_note = impute_note
  ))
} else {

message(tag, " study_root = ", study_root)
message(tag, " loading ", config$data$rawdata_path)
load(config$data$rawdata_path, envir = .GlobalEnv)
if (!exists("dabiao", inherits = FALSE)) stop("Object 'dabiao' not found in RData")
df0 <- dabiao
stopifnot(is.data.frame(df0), nrow(df0) > 0L)
if (!screen_y %in% names(df0)) stop("Screen outcome missing: ", screen_y)

# --- candidates present & not nodes / design ---
design_excl <- as.character(config$suicide_cssrs$design_exclude_vars %||% character(0))
disease_vars <- as.character(config$analysis_exclusion$disease_vars %||% character(0))
# Nodes may be in disease_vars but protected; never screen them as covariates
forbid <- unique(c(nodes, mice_excl, design_excl, setdiff(disease_vars, nodes)))
cands_present <- intersect(cands, names(df0))
cands_present <- setdiff(cands_present, forbid)
miss_rate <- vapply(cands_present, function(v) mean(is.na(df0[[v]])), numeric(1))
drop_hi_miss <- names(miss_rate)[miss_rate >= miss_drop_thr]
if (length(drop_hi_miss)) {
  message("[Task5] drop high-missing (>=", miss_drop_thr, "): ", paste(drop_hi_miss, collapse = ", "))
}
mice_vars <- setdiff(cands_present, drop_hi_miss)
message("[Task5] MICE covariate vars n=", length(mice_vars))

# --- minimal MICE on covariate candidates only ---
impute_note <- character(0)
df_imp <- df0
need_mice <- any(vapply(mice_vars, function(v) any(is.na(df0[[v]])), logical(1)))
imp_path <- file.path(study_root, "data/harmonized/D04_outpatient_clpm_imputed.RData")

if (need_mice) {
  if (!requireNamespace("mice", quietly = TRUE)) {
    stop("Package 'mice' required for covariate imputation")
  }
  set.seed(seed)
  mice_df <- df0[, mice_vars, drop = FALSE]
  # Ensure factors stay factors; characters → factor
  for (v in names(mice_df)) {
    if (is.character(mice_df[[v]])) mice_df[[v]] <- factor(mice_df[[v]])
  }
  message("[Task5] mice start: m=", m_imp, " maxit=", maxit, " method=cart seed=", seed)
  t0 <- proc.time()[["elapsed"]]
  imp <- tryCatch(
    mice::mice(
      mice_df,
      m = m_imp,
      maxit = maxit,
      method = "cart",
      seed = seed,
      printFlag = FALSE
    ),
    error = function(e) e
  )
  elapsed <- proc.time()[["elapsed"]] - t0
  if (inherits(imp, "error")) {
    message("[Task5] mice failed: ", conditionMessage(imp), " — fallback listwise for screening")
    impute_note <- c(
      impute_note,
      paste0("MICE_FAILED: ", conditionMessage(imp)),
      "SCREENING_MODE=listwise_complete_on_Model2_candidates"
    )
  } else {
    completed <- mice::complete(imp, action = 1L)
    for (v in names(completed)) {
      df_imp[[v]] <- completed[[v]]
    }
    # Nodes untouched
    for (v in intersect(nodes, names(df0))) {
      df_imp[[v]] <- df0[[v]]
    }
    dabiao <- df_imp
    dir.create(dirname(imp_path), recursive = TRUE, showWarnings = FALSE)
    save(dabiao, file = imp_path)
    impute_note <- c(
      impute_note,
      sprintf(
        "IMPUTATION=mice_covars_only m=%d complete_action=1 method=cart seed=%d elapsed_s=%.1f",
        m_imp, seed, elapsed
      ),
      paste0("MICE_VARS=", paste(mice_vars, collapse = ",")),
      paste0("DROPPED_HI_MISS=", paste(drop_hi_miss, collapse = ",")),
      paste0("NODES_EXCLUDED_FROM_MICE=", paste(intersect(nodes, names(df0)), collapse = ","))
    )
    message("[Task5] imputed dabiao saved: ", imp_path, " (", round(elapsed, 1), "s)")
  }
} else {
  impute_note <- c(impute_note, "IMPUTATION=none_needed (no NA in mice_vars)")
  dabiao <- df_imp
  dir.create(dirname(imp_path), recursive = TRUE, showWarnings = FALSE)
  save(dabiao, file = imp_path)
}

# --- prepare Y ---
y_raw <- df_imp[[screen_y]]
if (is.factor(y_raw) || is.character(y_raw)) {
  y01 <- as.integer(as.character(y_raw) == "1" | as.character(y_raw) == "Yes")
} else {
  y01 <- as.integer(y_raw)
}
if (!all(y01 %in% c(0L, 1L, NA_integer_))) {
  stop("CSSRS_1st not binary 0/1 after coercion")
}
df_imp$.screen_y <- y01

# --- UV logistic ---
.uv_p <- function(dat, x) {
  if (!x %in% names(dat)) return(list(p = NA_real_, n = 0L, note = "missing_col"))
  d <- dat[, c(".screen_y", x), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  n <- nrow(d)
  if (n < 20L) return(list(p = NA_real_, n = n, note = "n_lt_20"))
  xv <- d[[x]]
  if (is.character(xv)) xv <- factor(xv)
  # drop unused / singleton levels for factors
  if (is.factor(xv)) {
    xv <- droplevels(xv)
    if (nlevels(xv) < 2L) return(list(p = NA_real_, n = n, note = "lt2_levels"))
    d[[x]] <- xv
  } else if (is.numeric(xv) && length(unique(xv)) < 2L) {
    return(list(p = NA_real_, n = n, note = "constant"))
  }
  fml <- stats::as.formula(paste(".screen_y ~", paste0("`", x, "`")))
  m <- tryCatch(stats::glm(fml, data = d, family = binomial()), error = function(e) e)
  if (inherits(m, "error")) return(list(p = NA_real_, n = n, note = paste0("glm_fail:", conditionMessage(m))))
  # LRT vs null for overall (handles multi-level factors)
  p <- tryCatch({
    a <- stats::anova(m, test = "LRT")
    pv <- a$`Pr(>Chi)`
    pv <- pv[!is.na(pv)]
    if (!length(pv)) NA_real_ else as.numeric(pv[length(pv)])
  }, error = function(e) {
    sm <- summary(m)$coefficients
    if (nrow(sm) < 2L) return(NA_real_)
    as.numeric(sm[2L, 4L])
  })
  list(p = p, n = n, note = "ok")
}

uv_rows <- lapply(mice_vars, function(x) {
  r <- .uv_p(df_imp, x)
  data.frame(
    variable = x,
    n = r$n,
    p_value = r$p,
    pass_uv = is.finite(r$p) && r$p < uv_p_cut,
    note = r$note,
    stringsAsFactors = FALSE
  )
})
uv_table <- do.call(rbind, uv_rows)
rownames(uv_table) <- NULL
uv_pass <- uv_table$variable[which(isTRUE(uv_table$pass_uv) | uv_table$pass_uv %in% TRUE)]

force_keep <- intersect(
  c("age", "sex", "Age", "Sex", "gender", "Gender"),
  names(df_imp)
)
force_keep <- intersect(force_keep, cands_present)
message("[Task5] UV pass n=", length(uv_pass), ": ", paste(uv_pass, collapse = ", "))
message("[Task5] force_keep: ", paste(force_keep, collapse = ", "))

vif_cand <- unique(c(force_keep, uv_pass))
vif_cand <- setdiff(vif_cand, nodes)

# --- VIF screen (numericized; iterative drop max VIF >= thr) ---
.calc_vif <- function(vars, data) {
  vars <- unique(as.character(vars))
  vars <- vars[vars %in% names(data)]
  if (length(vars) <= 1L) {
    return(list(vif_df = data.frame(Variable = vars, VIF = NA_real_, stringsAsFactors = FALSE),
                vif_values = setNames(rep(NA_real_, length(vars)), vars)))
  }
  df_subset <- data[, vars, drop = FALSE]
  ok <- stats::complete.cases(df_subset)
  df_subset <- df_subset[ok, , drop = FALSE]
  for (v in vars) {
    if (is.factor(df_subset[[v]]) || is.character(df_subset[[v]])) {
      df_subset[[v]] <- as.numeric(as.factor(df_subset[[v]]))
    }
  }
  X <- tryCatch({
    mm <- stats::model.matrix(~ ., data = df_subset)
    mm[, -1L, drop = FALSE]
  }, error = function(e) NULL)
  if (is.null(X) || ncol(X) == 0L) {
    return(list(vif_df = NULL, vif_values = NULL))
  }
  vif_values <- tryCatch({
    r2s <- vapply(seq_len(ncol(X)), function(j) {
      if (ncol(X) == 1L) return(0)
      summary(stats::lm(X[, j] ~ X[, -j, drop = FALSE]))$r.squared
    }, numeric(1))
    stats::setNames(1 / (1 - r2s), colnames(X))
  }, error = function(e) NULL)
  if (is.null(vif_values)) return(list(vif_df = NULL, vif_values = NULL))
  list(
    vif_df = data.frame(
      Variable = names(vif_values),
      VIF = round(as.numeric(vif_values), 3),
      stringsAsFactors = FALSE
    ),
    vif_values = vif_values
  )
}

.max_vif_orig <- function(vif_values, orig_name) {
  if (is.null(vif_values) || !length(vif_values)) return(NA_real_)
  hit <- names(vif_values)[
    names(vif_values) == orig_name |
      grepl(paste0("^", orig_name, "(?:[0-9]|[^A-Za-z0-9_])"), names(vif_values), perl = TRUE)
  ]
  if (!length(hit)) return(NA_real_)
  max(as.numeric(vif_values[hit]), na.rm = TRUE)
}

working <- vif_cand
removed <- character(0)
vif_log <- list()
iter <- 0L
repeat {
  iter <- iter + 1L
  if (length(working) <= 1L) break
  res <- .calc_vif(working, df_imp)
  if (is.null(res$vif_values)) break
  mx <- vapply(working, function(v) .max_vif_orig(res$vif_values, v), numeric(1))
  names(mx) <- working
  vif_log[[iter]] <- data.frame(
    iter = iter,
    variable = working,
    VIF = as.numeric(mx),
    stringsAsFactors = FALSE
  )
  # never drop force_keep for VIF (keep demographics)
  dropable <- setdiff(working, force_keep)
  if (!length(dropable)) break
  mx_drop <- mx[dropable]
  worst <- names(mx_drop)[which.max(mx_drop)]
  worst_vif <- unname(mx_drop[worst])
  if (!is.finite(worst_vif) || worst_vif < vif_thr) break
  message(sprintf("[Task5] VIF drop iter=%d: %s (VIF=%.3f)", iter, worst, worst_vif))
  removed <- c(removed, worst)
  working <- setdiff(working, worst)
}

vif_final <- if (length(vif_log)) {
  last <- vif_log[[length(vif_log)]]
  last$status <- ifelse(last$variable %in% working, "pass", "fail")
  last$threshold <- vif_thr
  last$removed_in_path <- last$variable %in% removed
  last
} else {
  data.frame(
    iter = 1L, variable = working, VIF = NA_real_,
    status = "pass", threshold = vif_thr, removed_in_path = FALSE,
    stringsAsFactors = FALSE
  )
}

Model2Factors <- unique(c(force_keep, intersect(working, vif_cand)))
Model2Factors <- setdiff(Model2Factors, nodes)
# Safety: no node / raw scale in Model2
leak <- intersect(Model2Factors, unique(c(nodes, mice_excl, disease_vars)))
if (length(leak)) {
  warning("[Task5] stripping leak vars from Model2: ", paste(leak, collapse = ", "))
  Model2Factors <- setdiff(Model2Factors, leak)
}

# --- write outputs ---
out_dir <- file.path(study_root, "covariates")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

utils::write.csv(uv_table, file.path(out_dir, "uv_table.csv"), row.names = FALSE)
utils::write.csv(vif_final, file.path(out_dir, "vif_screen.csv"), row.names = FALSE)
writeLines(Model2Factors, file.path(out_dir, "Model2Factors.txt"))
writeLines(impute_note, file.path(out_dir, "imputation_note.txt"))

message("[Task5] Model2Factors (", length(Model2Factors), "): ", paste(Model2Factors, collapse = ", "))
message("[Task5] wrote ", out_dir)

# --- sync UNC study if mounted ---
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
  unc_cov <- file.path(unc_root, "covariates")
  dir.create(unc_cov, recursive = TRUE, showWarnings = FALSE)
  for (fn in c("uv_table.csv", "vif_screen.csv", "Model2Factors.txt", "imputation_note.txt")) {
    src <- file.path(out_dir, fn)
    if (file.exists(src)) file.copy(src, file.path(unc_cov, fn), overwrite = TRUE)
  }
  unc_imp <- file.path(unc_root, "data/harmonized")
  if (dir.exists(dirname(unc_imp)) || dir.exists(file.path(unc_root, "data"))) {
    dir.create(unc_imp, recursive = TRUE, showWarnings = FALSE)
    if (file.exists(imp_path)) {
      file.copy(imp_path, file.path(unc_imp, basename(imp_path)), overwrite = TRUE)
    }
  }
  message("[Task5] synced Model2Factors → ", unc_cov)
} else {
  message("[Task5] UNC study root not found; skip sync")
}

invisible(list(
  Model2Factors = Model2Factors,
  uv_table = uv_table,
  vif_screen = vif_final,
  impute_note = impute_note
))

} # end outpatient branch (else of is_ward)