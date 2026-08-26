###############################################################################
#  unsupervised_clustering_table
#  Unsupervised clustering subtype OR/HR analysis table
#  (Logistic: in-hospital mortality; Cox: 28-day or 7-day mortality)
#
#  config: config$unsupervised_clustering_table  (thresholds / column names / pause only)
#    k_select            = 2              which k subtype to use (integer)
#    vars                = c(...)         clinical variables to analyse (required)
#    preferred_event_var = "survival_28d"
#    preferred_time_var  = "survival_time_28d"
#    fallback_event_var  = "survival_7d"
#    fallback_time_var   = "survival_time_7d"
#    cut_spec            = list(...)      optional custom break / label / ref overrides
#    pause_enable        = TRUE
#
#  读: ctx$data$imputed %||% ctx$data$cleaned
#      ctx$results$df_final        (Subphenotype labels from block_lca)
#      ctx$results$lca_results     (full ConsensusClusterPlus results from block_lca)
#      ctx$results$lca_optimal_k   (optimal k from block_lca)
#
#  写: ctx$results$unsupervised_clustering_table  (final data frame)
#
#  产出（发表序号 / 固定名）:
#    - [main_table] Table n.* OR + HR subtype analysis table
#                   → pub_paths + openxlsx (dual-header SCI three-line table)
#
#  pause: config$unsupervised_clustering_table$pause_enable
###############################################################################

# ── Private helpers (prefix .uct06_ to avoid post-source collisions) ─────────

.uct06_get_consensus_class <- function(results, k_select) {
  k_int <- as.integer(k_select)
  k_chr <- as.character(k_select)

  if (is.list(results) &&
      length(results) >= k_int &&
      !is.null(results[[k_int]]) &&
      !is.null(results[[k_int]]$consensusClass)) {
    return(results[[k_int]]$consensusClass)
  }
  if (is.list(results) &&
      !is.null(results[[k_chr]]) &&
      !is.null(results[[k_chr]]$consensusClass)) {
    return(results[[k_chr]]$consensusClass)
  }
  stop(
    "Cannot find consensusClass for k=", k_select,
    " in lca_results. Check the LCA results object structure.",
    call. = FALSE
  )
}

# Convert event column to 0/1 integer, handling both numeric and character
.uct06_convert_event <- function(x) {
  if (is.numeric(x) || is.integer(x)) return(as.integer(x == 1))
  x_chr <- as.character(x)
  event <- ifelse(
    x_chr %in% c(
      "Non-survivor", "Non-survivor ", "Death", "Dead",
      "1", "Yes", "yes", "TRUE", "True"
    ),
    1L,
    ifelse(
      x_chr %in% c(
        "Survivor", "Survivor ", "Alive",
        "0", "No", "no", "FALSE", "False"
      ),
      0L, NA_integer_
    )
  )
  as.integer(event)
}

# Categorise a continuous variable according to a spec list
# spec = list(breaks = ..., labels = ..., ref = ...)
# Uses right = FALSE (left-closed, right-open intervals)
.uct06_make_cat <- function(x, spec) {
  f <- cut(
    x,
    breaks        = spec$breaks,
    labels        = spec$labels,
    right         = FALSE,
    include.lowest = TRUE   # last bin [a, Inf) closed on right (no practical effect with Inf)
  )
  factor(f, levels = c(spec$ref, setdiff(spec$labels, spec$ref)))
}

# Format p-value to 3 decimal places; returns "<0.001" when p < 0.001
.uct06_fmt_p <- function(p) {
  if (length(p) == 0L || is.na(p) || identical(p, "")) return("")
  if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}

# Logistic regression: returns data.frame with columns Level / OR / CI / P
.uct06_get_or_stats <- function(df, y, x_col, ref_lvl) {
  df   <- df[!is.na(df[[y]]) & !is.na(df[[x_col]]), , drop = FALSE]
  lvls <- levels(df[[x_col]])

  res <- data.frame(
    Level = lvls, OR = "", CI = "", P = "",
    stringsAsFactors = FALSE
  )
  res$OR[res$Level == ref_lvl] <- "Ref"

  # Guard: need outcome variation and ≥ 2 predictor levels
  if (nrow(df) == 0L ||
      length(unique(stats::na.omit(df[[y]]))) < 2L ||
      length(unique(stats::na.omit(df[[x_col]]))) < 2L) {
    return(res)
  }

  fit <- tryCatch(
    stats::glm(
      stats::as.formula(paste(y, "~", x_col)),
      data   = df,
      family = stats::binomial()
    ),
    error = function(e) NULL
  )

  if (!is.null(fit)) {
    summ <- summary(fit)$coefficients
    ci   <- tryCatch(
      stats::confint.default(fit),
      error = function(e) {
        m <- matrix(NA_real_, nrow = nrow(summ), ncol = 2L)
        rownames(m) <- rownames(summ)
        m
      }
    )

    for (lv in lvls) {
      term <- paste0(x_col, lv)
      if (term %in% rownames(summ) && term %in% rownames(ci)) {
        res$OR[res$Level == lv] <- sprintf("%.2f", exp(summ[term, 1L]))
        res$CI[res$Level == lv] <- paste0(
          sprintf("%.2f", exp(ci[term, 1L])),
          "\u2013",
          sprintf("%.2f", exp(ci[term, 2L]))
        )
        res$P[res$Level == lv] <- as.character(summ[term, 4L])
      }
    }
  }
  res
}

# Cox regression: returns data.frame with columns Level / HR / CI / P
.uct06_get_hr_stats <- function(df, time, event, x_col, ref_lvl) {
  df <- df[
    !is.na(df[[time]]) & !is.na(df[[event]]) & !is.na(df[[x_col]]),
    , drop = FALSE
  ]
  lvls <- levels(df[[x_col]])

  res <- data.frame(
    Level = lvls, HR = "", CI = "", P = "",
    stringsAsFactors = FALSE
  )
  res$HR[res$Level == ref_lvl] <- "Ref"

  if (nrow(df) == 0L ||
      sum(df[[event]] == 1L, na.rm = TRUE) < 5L ||
      length(unique(stats::na.omit(df[[x_col]]))) < 2L) {
    return(res)
  }

  # Replace non-positive survival times (Cox requires time > 0)
  df[[time]] <- ifelse(df[[time]] <= 0, 0.001, df[[time]])

  fit <- tryCatch(
    survival::coxph(
      stats::as.formula(
        paste0("survival::Surv(", time, ", ", event, ") ~ ", x_col)
      ),
      data = df
    ),
    error = function(e) NULL
  )

  if (!is.null(fit)) {
    summ <- summary(fit)
    for (lv in lvls) {
      term <- paste0(x_col, lv)
      if (term %in% rownames(summ$coefficients)) {
        res$HR[res$Level == lv] <- sprintf("%.2f", summ$conf.int[term, 1L])
        res$CI[res$Level == lv] <- paste0(
          sprintf("%.2f", summ$conf.int[term, 3L]),
          "\u2013",
          sprintf("%.2f", summ$conf.int[term, 4L])
        )
        res$P[res$Level == lv] <- as.character(summ$coefficients[term, 5L])
      }
    }
  }
  res
}

# Build one table section (overall cohort OR a single subtype)
# Returns a character matrix with 7 columns:
#   Characteristic | OR | 95% CI (OR) | P (OR) | HR | 95% CI (HR) | P (HR)
.uct06_build_table <- function(sub_df, title_text, vars, cut_spec, out_or, out_hr_t) {
  rows_out <- list()
  rows_out[[1L]] <- c(title_text, rep(NA_character_, 6L))

  for (v in vars) {
    spec     <- cut_spec[[v]]
    col_name <- paste0("cat_", v)

    sub_df[[col_name]] <- .uct06_make_cat(sub_df[[v]], spec)

    or_res <- .uct06_get_or_stats(
      df      = sub_df,
      y       = out_or,
      x_col   = col_name,
      ref_lvl = spec$ref
    )
    hr_res <- .uct06_get_hr_stats(
      df      = sub_df,
      time    = out_hr_t,
      event   = "out_hr_event_num",
      x_col   = col_name,
      ref_lvl = spec$ref
    )

    # Variable header row (no statistics)
    rows_out[[length(rows_out) + 1L]] <- c(v, rep(NA_character_, 6L))

    for (lv in levels(sub_df[[col_name]])) {
      or_row <- or_res[or_res$Level == lv, ]
      hr_row <- hr_res[hr_res$Level == lv, ]

      rows_out[[length(rows_out) + 1L]] <- c(
        paste0("    ", lv),
        or_row$OR,
        or_row$CI,
        .uct06_fmt_p(suppressWarnings(as.numeric(or_row$P))),
        hr_row$HR,
        hr_row$CI,
        .uct06_fmt_p(suppressWarnings(as.numeric(hr_row$P)))
      )
    }
  }

  do.call(rbind, rows_out)
}


# ── Main block function ───────────────────────────────────────────────────────

block_unsupervised_clustering_table <- function(ctx, ...) {

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  suppressPackageStartupMessages({
    library(dplyr)
    library(survival)
    library(openxlsx)
    library(cli)
  })

  cfg    <- ctx$config
  bl_cfg <- cfg$unsupervised_clustering_table %||% list()

  # ── Step 1: Read configuration ────────────────────────────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 1: Configuration")

  k_select <- as.integer(bl_cfg$k_select %||% 2L)

  vars <- bl_cfg$vars
  if (is.null(vars) || length(vars) == 0L) {
    stop(
      "config$unsupervised_clustering_table$vars is required but not set. ",
      "Provide a character vector of clinical variable names.",
      call. = FALSE
    )
  }

  preferred_event_var <- bl_cfg$preferred_event_var %||% "survival_28d"
  preferred_time_var  <- bl_cfg$preferred_time_var  %||% "survival_time_28d"
  fallback_event_var  <- bl_cfg$fallback_event_var  %||% "survival_7d"
  fallback_time_var   <- bl_cfg$fallback_time_var   %||% "survival_time_7d"
  pause_enable        <- !isFALSE(bl_cfg$pause_enable)

  cli::cli_alert_info("k_select = {k_select}")
  cli::cli_alert_info("Clinical variables: {paste(vars, collapse = ', ')}")

  # ── Step 2: Load data ─────────────────────────────────────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 2: Loading data")

  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp) || !is.data.frame(data_imp)) {
    ctx$results$pause_point <- list(
      block      = "block_unsupervised_clustering_table",
      reason     = "No imputed / cleaned data found (ctx$data$imputed and ctx$data$cleaned are both NULL).",
      suggestion = "Run 'imputation' or 'data_clean' block before this block."
    )
    stop("PAUSE_FOR_USER_DECISION: No analysis data. See ctx$results$pause_point.", call. = FALSE)
  }
  data_imp <- as.data.frame(data_imp)
  cli::cli_alert_success("Imputed data loaded: {nrow(data_imp)} rows, {ncol(data_imp)} columns")

  df_final <- ctx$results$df_final
  if (is.null(df_final) || !is.data.frame(df_final)) {
    ctx$results$pause_point <- list(
      block      = "block_unsupervised_clustering_table",
      reason     = "ctx$results$df_final is NULL – block_lca has not been run.",
      suggestion = "Run 'lca' block before this block."
    )
    stop("PAUSE_FOR_USER_DECISION: LCA results not found. See ctx$results$pause_point.", call. = FALSE)
  }

  lca_results  <- ctx$results$lca_results
  lca_optimal_k <- ctx$results$lca_optimal_k %||% NULL

  cli::cli_alert_info(
    "df_final rows: {nrow(df_final)}, lca_optimal_k: {lca_optimal_k %||% 'unknown'}"
  )

  # ── Step 3: Match subjects and attach subphenotype labels ─────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 3: Building analysis dataset")

  df_rn  <- rownames(df_final)
  imp_rn <- rownames(data_imp)
  idx    <- match(df_rn, imp_rn)
  valid  <- !is.na(idx)

  if (sum(valid) == 0L) {
    ctx$results$pause_point <- list(
      block      = "block_unsupervised_clustering_table",
      reason     = "No rownames in df_final match rownames in data_imp.",
      suggestion = "Ensure df_final (from block_lca) and the imputed data share identical row identifiers (rownames)."
    )
    stop("PAUSE_FOR_USER_DECISION: Subject matching failed. See ctx$results$pause_point.", call. = FALSE)
  }

  n_lost <- sum(!valid)
  if (n_lost > 0L) {
    cli::cli_alert_warning(
      "{n_lost} subject(s) in df_final could not be matched in imputed data and will be excluded."
    )
  }

  analysis_df <- data_imp[idx[valid], , drop = FALSE]

  # Determine subphenotype labels for the requested k
  if (!is.null(lca_optimal_k) &&
      k_select == as.integer(lca_optimal_k) &&
      "Subphenotype" %in% colnames(df_final)) {
    # Optimal k: use labels already stored in df_final
    raw_cls <- as.integer(df_final$Subphenotype[valid])
    cli::cli_alert_info("Using Subphenotype from ctx$results$df_final (optimal k = {k_select})")
  } else if (!is.null(lca_results)) {
    # Non-optimal k: extract consensusClass from full results object
    all_cls <- .uct06_get_consensus_class(lca_results, k_select)
    raw_cls  <- as.integer(all_cls[valid])
    cli::cli_alert_info("Using consensusClass from ctx$results$lca_results (k = {k_select})")
  } else {
    ctx$results$pause_point <- list(
      block      = "block_unsupervised_clustering_table",
      reason     = paste0(
        "k_select (", k_select, ") differs from lca_optimal_k (", lca_optimal_k %||% "NULL",
        ") and ctx$results$lca_results is NULL."
      ),
      suggestion = "Either set k_select equal to lca_optimal_k, or ensure block_lca stores lca_results in ctx."
    )
    stop("PAUSE_FOR_USER_DECISION: Cannot retrieve subphenotype labels. See ctx$results$pause_point.", call. = FALSE)
  }

  analysis_df$Subphenotype <- factor(
    raw_cls,
    levels = seq_len(k_select),
    labels = paste0("Class ", seq_len(k_select))
  )

  cli::cli_alert_success(
    "Subphenotype distribution: {paste(paste0(names(table(analysis_df$Subphenotype)), '=', as.integer(table(analysis_df$Subphenotype))), collapse = ', ')}"
  )

  # ── Step 4: Validate clinical variables ───────────────────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 4: Variable validation")

  missing_vars <- setdiff(vars, colnames(analysis_df))
  if (length(missing_vars) > 0L) {
    ctx$results$pause_point <- list(
      block         = "block_unsupervised_clustering_table",
      reason        = paste("Variables not found in analysis_df:", paste(missing_vars, collapse = ", ")),
      suggestion    = "Check config$unsupervised_clustering_table$vars against available columns in the imputed data.",
      data_snapshot = utils::head(analysis_df, 5L)
    )
    stop("PAUSE_FOR_USER_DECISION: Missing clinical variables. See ctx$results$pause_point.", call. = FALSE)
  }
  cli::cli_alert_success("All {length(vars)} clinical variables found.")

  # ── Step 5: Determine outcome variables ───────────────────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 5: Outcome variable selection")

  if (preferred_event_var %in% colnames(analysis_df) &&
      preferred_time_var  %in% colnames(analysis_df)) {
    out_hr_e  <- preferred_event_var
    out_hr_t  <- preferred_time_var
    cox_title <- "28-day mortality"
  } else if (fallback_event_var %in% colnames(analysis_df) &&
             fallback_time_var  %in% colnames(analysis_df)) {
    out_hr_e  <- fallback_event_var
    out_hr_t  <- fallback_time_var
    cox_title <- "7-day mortality"
  } else {
    ctx$results$pause_point <- list(
      block      = "block_unsupervised_clustering_table",
      reason     = paste0(
        "Neither preferred (", preferred_event_var, " / ", preferred_time_var,
        ") nor fallback (", fallback_event_var, " / ", fallback_time_var,
        ") survival variables were found in the data."
      ),
      suggestion = "Update config$unsupervised_clustering_table preferred/fallback event and time variable names.",
      data_snapshot = utils::head(analysis_df, 5L)
    )
    stop("PAUSE_FOR_USER_DECISION: Survival variables not found. See ctx$results$pause_point.", call. = FALSE)
  }
  cli::cli_alert_success("Cox outcome: {out_hr_e} / {out_hr_t} ({cox_title})")

  # ── Step 6: Convert outcome variables ─────────────────────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 6: Outcome variable conversion")

  analysis_df[[out_hr_e]] <- as.character(analysis_df[[out_hr_e]])
  analysis_df$out_hr_event_num <- .uct06_convert_event(analysis_df[[out_hr_e]])
  analysis_df[[out_hr_t]] <- suppressWarnings(as.numeric(as.character(analysis_df[[out_hr_t]])))

  # Logistic outcome: prefer is_dead, then hospital_expire_flag, fallback to Cox event
  if ("is_dead" %in% names(analysis_df)) {
    analysis_df$is_dead_num <- .uct06_convert_event(analysis_df$is_dead)
    cli::cli_alert_info("Logistic outcome source: 'is_dead'")
  } else if ("hospital_expire_flag" %in% names(analysis_df)) {
    analysis_df$is_dead_num <- .uct06_convert_event(analysis_df$hospital_expire_flag)
    cli::cli_alert_info("Logistic outcome source: 'hospital_expire_flag'")
  } else {
    analysis_df$is_dead_num <- analysis_df$out_hr_event_num
    cli::cli_alert_warning(
      "Neither 'is_dead' nor 'hospital_expire_flag' found; using Cox event variable as logistic outcome."
    )
  }
  out_or <- "is_dead_num"

  # Convert clinical variables to numeric
  analysis_df[vars] <- lapply(
    analysis_df[vars],
    function(x) suppressWarnings(as.numeric(as.character(x)))
  )

  # ── Step 7: Categorisation cut-point specifications ───────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 7: Defining categorisation cut points")

  # Default clinical cut specifications
  # Intervals use right = FALSE (left-closed, right-open): [a, b)
  # Reference level is listed first in 'ref'; other levels follow in the factor
  # Default clinical cut specifications
  # Evidence-based reference ranges where available; right = FALSE → [a, b) intervals
  # Variables are grouped by clinical category for readability
  default_cut_spec <- list(

    # ── Respiratory ───────────────────────────────────────────────────────────
    pO2 = list(
      breaks = c(-Inf, 80, 100, Inf),
      labels = c("<80", "80-99", ">=100"),
      ref    = ">=100"
    ),
    SpO2 = list(
      breaks = c(-Inf, 90, 95, Inf),
      labels = c("<90", "90-94", ">=95"),
      ref    = ">=95"
    ),
    RR = list(
      breaks = c(-Inf, 12, 20, Inf),
      labels = c("<12", "12-20", ">20"),
      ref    = "12-20"
    ),
    # PaO2/FiO2 ratio (Berlin ARDS classification: severe <100, moderate 100-199, mild 200-299)
    PF_ratio = list(
      breaks = c(-Inf, 100, 200, 300, Inf),
      labels = c("<100", "100-199", "200-299", ">=300"),
      ref    = ">=300"
    ),
    FiO2 = list(
      breaks = c(-Inf, 0.4, 0.6, Inf),
      labels = c("<0.40", "0.40-0.59", ">=0.60"),
      ref    = "<0.40"
    ),
    PEEP = list(
      breaks = c(-Inf, 5, 10, Inf),
      labels = c("<5", "5-9", ">=10"),
      ref    = "<5"
    ),
    TidalVolume = list(
      breaks = c(-Inf, 400, 600, Inf),
      labels = c("<400", "400-600", ">600"),
      ref    = "400-600"
    ),

    # ── Haemodynamics ─────────────────────────────────────────────────────────
    HR = list(
      breaks = c(-Inf, 60, 100, Inf),
      labels = c("<60", "60-100", ">100"),
      ref    = "60-100"
    ),
    SBP = list(
      breaks = c(-Inf, 90, 120, Inf),
      labels = c("<90", "90-119", ">=120"),
      ref    = ">=120"
    ),
    DBP = list(
      breaks = c(-Inf, 60, 90, Inf),
      labels = c("<60", "60-89", ">=90"),
      ref    = "60-89"
    ),
    MAP = list(
      breaks = c(-Inf, 65, 90, Inf),
      labels = c("<65", "65-89", ">=90"),
      ref    = "65-89"
    ),

    # ── Temperature ───────────────────────────────────────────────────────────
    Temperature = list(
      breaks = c(-Inf, 36.0, 37.5, 38.5, Inf),
      labels = c("<36.0", "36.0-37.4", "37.5-38.4", ">=38.5"),
      ref    = "36.0-37.4"
    ),

    # ── Haematology ───────────────────────────────────────────────────────────
    WBC = list(
      breaks = c(-Inf, 4, 12, Inf),
      labels = c("<4", "4-12", ">12"),
      ref    = "4-12"
    ),
    Hemoglobin = list(
      breaks = c(-Inf, 8, 12, Inf),
      labels = c("<8", "8-11.9", ">=12"),
      ref    = ">=12"
    ),
    Hematocrit = list(
      breaks = c(-Inf, 30, 45, Inf),
      labels = c("<30", "30-44", ">=45"),
      ref    = "30-44"
    ),
    PlateletCount = list(
      breaks = c(-Inf, 100, 150, Inf),
      labels = c("<100", "100-149", ">=150"),
      ref    = ">=150"
    ),
    INR = list(
      breaks = c(-Inf, 1.0, 1.5, Inf),
      labels = c("<1.0", "1.0-1.49", ">=1.5"),
      ref    = "<1.0"
    ),
    PT = list(
      breaks = c(-Inf, 11, 14, Inf),
      labels = c("<11", "11-14", ">14"),
      ref    = "11-14"
    ),
    PTT = list(
      breaks = c(-Inf, 25, 35, Inf),
      labels = c("<25", "25-35", ">35"),
      ref    = "25-35"
    ),
    APTT = list(
      breaks = c(-Inf, 25, 35, Inf),
      labels = c("<25", "25-35", ">35"),
      ref    = "25-35"
    ),

    # ── Metabolic / Acid-base ─────────────────────────────────────────────────
    pH = list(
      breaks = c(-Inf, 7.35, 7.45, Inf),
      labels = c("<7.35", "7.35-7.44", ">=7.45"),
      ref    = "7.35-7.44"
    ),
    Bicarbonate = list(
      breaks = c(-Inf, 18, 23, Inf),
      labels = c("<18", "18-22", ">=23"),
      ref    = ">=23"
    ),
    HCO3 = list(
      breaks = c(-Inf, 18, 23, Inf),
      labels = c("<18", "18-22", ">=23"),
      ref    = ">=23"
    ),
    Lactate = list(
      # [2, 4) labelled "2-<4" to accurately reflect the right-open boundary
      breaks = c(-Inf, 2, 4, Inf),
      labels = c("<2", "2-<4", ">=4"),
      ref    = "<2"
    ),
    Glucose = list(
      breaks = c(-Inf, 70, 180, Inf),
      labels = c("<70", "70-179", ">=180"),
      ref    = "70-179"
    ),

    # ── Electrolytes ──────────────────────────────────────────────────────────
    Sodium = list(
      breaks = c(-Inf, 135, 145, Inf),
      labels = c("<135", "135-144", ">=145"),
      ref    = "135-144"
    ),
    Potassium = list(
      breaks = c(-Inf, 3.5, 5.0, Inf),
      labels = c("<3.5", "3.5-4.9", ">=5.0"),
      ref    = "3.5-4.9"
    ),
    Chloride = list(
      breaks = c(-Inf, 98, 107, Inf),
      labels = c("<98", "98-106", ">=107"),
      ref    = "98-106"
    ),
    Calcium = list(
      breaks = c(-Inf, 8.5, 10.5, Inf),
      labels = c("<8.5", "8.5-10.4", ">=10.5"),
      ref    = "8.5-10.4"
    ),
    Magnesium = list(
      breaks = c(-Inf, 1.5, 2.5, Inf),
      labels = c("<1.5", "1.5-2.4", ">=2.5"),
      ref    = "1.5-2.4"
    ),
    Phosphate = list(
      breaks = c(-Inf, 2.5, 4.5, Inf),
      labels = c("<2.5", "2.5-4.4", ">=4.5"),
      ref    = "2.5-4.4"
    ),

    # ── Renal ─────────────────────────────────────────────────────────────────
    Creatinine = list(
      breaks = c(-Inf, 1.2, 2.0, Inf),
      labels = c("<1.2", "1.2-1.9", ">=2.0"),
      ref    = "<1.2"
    ),
    BUN = list(
      breaks = c(-Inf, 7, 20, Inf),
      labels = c("<7", "7-20", ">20"),
      ref    = "7-20"
    ),
    Urea = list(
      breaks = c(-Inf, 7, 20, Inf),
      labels = c("<7", "7-20", ">20"),
      ref    = "7-20"
    ),

    # ── Hepatic ───────────────────────────────────────────────────────────────
    Albumin = list(
      breaks = c(-Inf, 2.5, 3.5, Inf),
      labels = c("<2.5", "2.5-3.4", ">=3.5"),
      ref    = ">=3.5"
    ),
    Bilirubin = list(
      breaks = c(-Inf, 1.0, 2.0, Inf),
      labels = c("<1.0", "1.0-1.9", ">=2.0"),
      ref    = "<1.0"
    ),
    TotalBilirubin = list(
      breaks = c(-Inf, 1.0, 2.0, Inf),
      labels = c("<1.0", "1.0-1.9", ">=2.0"),
      ref    = "<1.0"
    ),
    ALT = list(
      breaks = c(-Inf, 40, 120, Inf),
      labels = c("<40", "40-119", ">=120"),
      ref    = "<40"
    ),
    AST = list(
      breaks = c(-Inf, 40, 120, Inf),
      labels = c("<40", "40-119", ">=120"),
      ref    = "<40"
    ),

    # ── Inflammatory / Biomarkers ─────────────────────────────────────────────
    CRP = list(
      breaks = c(-Inf, 10, 50, Inf),
      labels = c("<10", "10-49", ">=50"),
      ref    = "<10"
    ),
    Procalcitonin = list(
      breaks = c(-Inf, 0.5, 2.0, Inf),
      labels = c("<0.5", "0.5-1.9", ">=2.0"),
      ref    = "<0.5"
    ),
    PCT = list(
      breaks = c(-Inf, 0.5, 2.0, Inf),
      labels = c("<0.5", "0.5-1.9", ">=2.0"),
      ref    = "<0.5"
    ),
    Troponin = list(
      breaks = c(-Inf, 0.04, Inf),
      labels = c("<0.04", ">=0.04"),
      ref    = "<0.04"
    ),
    TroponinI = list(
      breaks = c(-Inf, 0.04, Inf),
      labels = c("<0.04", ">=0.04"),
      ref    = "<0.04"
    ),
    TroponinT = list(
      breaks = c(-Inf, 0.014, Inf),
      labels = c("<0.014", ">=0.014"),
      ref    = "<0.014"
    ),
    BNP = list(
      breaks = c(-Inf, 100, 400, Inf),
      labels = c("<100", "100-399", ">=400"),
      ref    = "<100"
    ),
    NT_proBNP = list(
      breaks = c(-Inf, 300, 900, Inf),
      labels = c("<300", "300-899", ">=900"),
      ref    = "<300"
    ),

    # ── Severity scores ───────────────────────────────────────────────────────
    GCS = list(
      # GCS is always an integer; "<=8" is the conventional clinical label for [-Inf, 9)
      breaks = c(-Inf, 9, 13, Inf),
      labels = c("<=8", "9-12", ">=13"),
      ref    = ">=13"
    ),
    SOFA = list(
      breaks = c(-Inf, 6, 10, Inf),
      labels = c("<6", "6-9", ">=10"),
      ref    = "<6"
    ),
    APACHE_II = list(
      breaks = c(-Inf, 10, 20, Inf),
      labels = c("<10", "10-19", ">=20"),
      ref    = "<10"
    ),
    APACHE2 = list(
      breaks = c(-Inf, 10, 20, Inf),
      labels = c("<10", "10-19", ">=20"),
      ref    = "<10"
    ),
    SAPS_II = list(
      breaks = c(-Inf, 30, 50, Inf),
      labels = c("<30", "30-49", ">=50"),
      ref    = "<30"
    ),

    # ── Demographics / Anthropometrics ────────────────────────────────────────
    Age = list(
      breaks = c(-Inf, 45, 65, 75, Inf),
      labels = c("<45", "45-64", "65-74", ">=75"),
      ref    = "45-64"
    ),
    BMI = list(
      breaks = c(-Inf, 18.5, 25, 30, Inf),
      labels = c("<18.5", "18.5-24.9", "25.0-29.9", ">=30"),
      ref    = "18.5-24.9"
    )
  )

  # Merge user-defined overrides (config$unsupervised_clustering_table$cut_spec)
  user_cut_spec <- bl_cfg$cut_spec %||% list()
  cut_spec      <- utils::modifyList(default_cut_spec, user_cut_spec)

  # Auto-generate median-based binary cut spec for variables without a predefined spec.
  # If a variable is not found in the built-in or user-defined specs, compute the
  # sample median from analysis_df and split into "< median" vs ">= median".
  missing_spec <- setdiff(vars, names(cut_spec))
  if (length(missing_spec) > 0L) {
    cli::cli_alert_warning(
      "No predefined cut_spec for {length(missing_spec)} variable(s): {paste(missing_spec, collapse = ', ')}. ",
      "Falling back to median-based binary split."
    )
    for (mv in missing_spec) {
      x_vals <- suppressWarnings(as.numeric(as.character(analysis_df[[mv]])))
      med    <- stats::median(x_vals, na.rm = TRUE)
      if (is.na(med) || !is.finite(med)) {
        ctx$results$pause_point <- list(
          block      = "block_unsupervised_clustering_table",
          reason     = paste0(
            "Variable '", mv, "' has no predefined cut_spec and its median is NA/non-finite ",
            "(all values missing or non-numeric). Cannot create a cut point."
          ),
          suggestion = paste0(
            "Either supply a manual cut_spec for '", mv,
            "' via config$unsupervised_clustering_table$cut_spec, or remove it from vars."
          )
        )
        stop("PAUSE_FOR_USER_DECISION: Cannot auto-cut variable. See ctx$results$pause_point.", call. = FALSE)
      }
      med_label <- formatC(med, format = "fg", digits = 4)
      lo_label  <- paste0("< ", med_label)
      hi_label  <- paste0(">= ", med_label)
      cut_spec[[mv]] <- list(
        breaks = c(-Inf, med, Inf),
        labels = c(lo_label, hi_label),
        ref    = lo_label
      )
      cli::cli_alert_info(
        "Auto cut_spec for '{mv}': median = {round(med, 4)}, groups: '{lo_label}' / '{hi_label}' (ref = '{lo_label}')"
      )
    }
  }

  # ── Step 8: Filter to complete cases on outcome variables ─────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 8: Complete-case filter on outcomes")

  analysis_df <- analysis_df %>%
    dplyr::filter(
      !is.na(Subphenotype),
      !is.na(.data[[out_or]]),
      !is.na(out_hr_event_num),
      !is.na(.data[[out_hr_t]])
    )

  n_total <- nrow(analysis_df)
  cli::cli_alert_success("Final analytic sample: n = {n_total}")
  cli::cli_alert_info(
    "Subphenotype: {paste(paste0(names(table(analysis_df$Subphenotype)), '=', as.integer(table(analysis_df$Subphenotype))), collapse = ', ')}"
  )
  cli::cli_alert_info(
    "Logistic outcome (0/1): {paste(paste0(names(table(analysis_df[[out_or]])), '=', as.integer(table(analysis_df[[out_or]]))), collapse = ', ')}"
  )
  cli::cli_alert_info(
    "Cox event (0/1): {paste(paste0(names(table(analysis_df$out_hr_event_num)), '=', as.integer(table(analysis_df$out_hr_event_num))), collapse = ', ')}"
  )

  if (pause_enable && n_total < 30L) {
    ctx$results$pause_point <- list(
      block         = "block_unsupervised_clustering_table",
      reason        = paste0("Final analytic sample too small: n = ", n_total),
      suggestion    = "Check outcome variable completeness, or relax inclusion criteria.",
      data_snapshot = utils::head(analysis_df, 5L)
    )
    stop("PAUSE_FOR_USER_DECISION: Insufficient sample size. See ctx$results$pause_point.", call. = FALSE)
  }

  # ── Step 9: Build OR / HR table ───────────────────────────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 9: Building OR/HR table")

  sp_levels   <- paste0("Class ", seq_len(k_select))
  tbl_overall <- .uct06_build_table(
    sub_df     = analysis_df,
    title_text = "The whole cohort",
    vars       = vars,
    cut_spec   = cut_spec,
    out_or     = out_or,
    out_hr_t   = out_hr_t
  )

  tbl_sps <- lapply(sp_levels, function(k) {
    .uct06_build_table(
      sub_df     = analysis_df %>% dplyr::filter(Subphenotype == k),
      title_text = paste0("Subphenotype ", k),
      vars       = vars,
      cut_spec   = cut_spec,
      out_or     = out_or,
      out_hr_t   = out_hr_t
    )
  })

  final_matrix <- rbind(tbl_overall, do.call(rbind, tbl_sps))
  final_df     <- as.data.frame(final_matrix, stringsAsFactors = FALSE)
  colnames(final_df) <- c(
    "Characteristic",
    "OR", "95% CI (OR)", "P (OR)",
    "HR", "95% CI (HR)", "P (HR)"
  )

  # ── Step 10: Export SCI three-line table (dual header) ────────────────────
  cli::cli_h1("[block_unsupervised_clustering_table] Step 10: Exporting SCI table")

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% "Output", "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)

  # Obtain auto-numbered publication title and filepath
  tbl_pub <- pub_paths(
    ctx, tbl_dir, "main_table",
    paste0(
      "OR and HR Analysis by Unsupervised Clustering Subphenotype (k=", k_select, ")"
    ),
    "xlsx"
  )

  wb <- createWorkbook()
  addWorksheet(wb, "Table")

  # Row 1: publication title (full-width)
  writeData(wb, sheet = 1, x = tbl_pub$title, startCol = 1, startRow = 1)
  mergeCells(wb, sheet = 1, cols = 1:7, rows = 1)

  # Row 2: dual group header
  writeData(wb, sheet = 1, x = "In-hospital mortality", startCol = 2, startRow = 2)
  writeData(wb, sheet = 1, x = cox_title,               startCol = 5, startRow = 2)
  mergeCells(wb, sheet = 1, cols = 2:4, rows = 2)
  mergeCells(wb, sheet = 1, cols = 5:7, rows = 2)

  # Row 3+: column names and data
  writeData(wb, sheet = 1, x = final_df, startRow = 3)

  # ── Styles ─────────────────────────────────────────────────────────────
  title_style <- createStyle(
    fontName        = "Times New Roman",
    fontSize        = 12,
    textDecoration  = "bold",
    halign          = "center",
    valign          = "center",
    border          = "TopBottom"
  )
  header_center_style <- createStyle(
    fontName        = "Times New Roman",
    fontSize        = 12,
    textDecoration  = "bold",
    halign          = "center",
    valign          = "center",
    border          = "bottom"
  )
  body_center_style <- createStyle(
    fontName = "Times New Roman",
    fontSize = 11,
    halign   = "center",
    valign   = "center"
  )
  body_left_style <- createStyle(
    fontName = "Times New Roman",
    fontSize = 11,
    halign   = "left",
    valign   = "center"
  )
  bold_left_style <- createStyle(
    fontName       = "Times New Roman",
    fontSize       = 11,
    textDecoration = "bold",
    halign         = "left",
    valign         = "center"
  )

  n_data_rows  <- nrow(final_df)
  data_row_end <- 3L + n_data_rows  # row 3 = colnames; row 4.. = data

  addStyle(wb, 1, title_style,         rows = 1L,       cols = 1:7, gridExpand = TRUE)
  addStyle(wb, 1, header_center_style, rows = 2:3,      cols = 1:7, gridExpand = TRUE)
  addStyle(wb, 1, body_center_style,   rows = 4:data_row_end, cols = 2:7, gridExpand = TRUE)
  addStyle(wb, 1, body_left_style,     rows = 4:data_row_end, cols = 1,   gridExpand = TRUE)

  # Bold rows: section headers (whole cohort / subphenotype titles) and variable names
  bold_patterns <- c(
    "The whole cohort",
    paste0("Subphenotype Class ", seq_len(k_select)),
    vars
  )
  bold_rows <- which(final_df$Characteristic %in% bold_patterns)
  if (length(bold_rows) > 0L) {
    # +3 to shift from final_df row index to Excel row (rows 1–3 are title/header/colnames)
    addStyle(wb, 1, bold_left_style, rows = bold_rows + 3L, cols = 1, gridExpand = TRUE)
  }

  # Bottom border on last data row (SCI three-line table bottom rule)
  bottom_rule_style <- createStyle(
    fontName = "Times New Roman",
    fontSize = 11,
    halign   = "center",
    valign   = "center",
    border   = "bottom"
  )
  addStyle(wb, 1, bottom_rule_style, rows = data_row_end, cols = 1:7, gridExpand = TRUE)

  setColWidths(wb, 1, cols = 1L,   widths = 28)
  setColWidths(wb, 1, cols = 2:7,  widths = 15)

  saveWorkbook(wb, file = tbl_pub$filepath, overwrite = TRUE)
  cli::cli_alert_success("Table saved: {.file {basename(tbl_pub$filepath)}}")

  # ── Step 11: Write results back to ctx ────────────────────────────────────
  ctx$results$unsupervised_clustering_table        <- final_df
  ctx$results$unsupervised_clustering_table_cox    <- cox_title
  ctx$results$unsupervised_clustering_table_k      <- k_select
  ctx$results$unsupervised_clustering_table_vars   <- vars

  cli::cli_alert_success(
    "[block_unsupervised_clustering_table] Done (k={k_select}, {cox_title})."
  )
  ctx
}


register_block(
  "unsupervised_clustering_table",
  block_unsupervised_clustering_table,
  "Unsupervised clustering OR/HR table: Logistic (in-hospital mortality) + Cox (28/7-day mortality) stratified by subphenotype"
)
