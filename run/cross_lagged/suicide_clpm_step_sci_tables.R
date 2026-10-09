# Shared helpers: SCI three-line tables for suicide CLPM step folders.
# Source from step runners after products exist.
# Requires: engine R/utils.R loaded; .table_queue_env available.

suicide_clpm_flush_sci_tables <- function() {
  if (!exists("render_queued_tables", mode = "function")) {
    stop("render_queued_tables not found; source R/utils.R first", call. = FALSE)
  }
  if (!exists(".table_queue_env")) {
    stop(".table_queue_env missing", call. = FALSE)
  }
  render_queued_tables(list())
  invisible(TRUE)
}

suicide_clpm_step_tables_dir <- function(step_dir) {
  d <- file.path(step_dir, "Tables")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

#' Export step01 attrition as SCI three-line table(s).
suicide_clpm_export_step01_tables <- function(step_dir, n_final = NULL) {
  tab_dir <- suicide_clpm_step_tables_dir(step_dir)
  attr_path <- file.path(step_dir, "attrition.csv")
  if (!file.exists(attr_path)) stop("Missing attrition.csv in ", step_dir, call. = FALSE)
  attr <- utils::read.csv(attr_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  if (is.null(n_final)) {
    hit <- attr$n_remain[attr$step == "six_nodes_complete"]
    n_final <- if (length(hit)) as.integer(hit[[1L]]) else NA_integer_
  }

  # Main attrition (gate steps + final)
  keep_steps <- c(
    "has_ID",
    grep("^group_", attr$step, value = TRUE),
    "six_nodes_complete"
  )
  main <- attr[attr$step %in% keep_steps, , drop = FALSE]
  # Prefer ordered
  ord <- match(keep_steps, main$step)
  main <- main[ord[!is.na(ord)], , drop = FALSE]
  main_out <- data.frame(
    Step = main$step,
    `N remaining` = as.integer(main$n_remain),
    `N excluded` = as.integer(main$n_excluded),
    Rule = main$rule,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  export_sci_table(
    main_out,
    file.path(tab_dir, "Table. Outpatient attrition flowchart (six-node complete).xlsx"),
    title = "Table. Outpatient attrition flowchart (six-node complete)",
    table_footnotes = c(
      paste0("Final analysis N = ", n_final, " (outpatient; six CLPM nodes listwise complete)."),
      "CSSRS nodes = C-SSRS ideation item2 (active suicidal thoughts; Yes=1 / No=0).",
      "HAMD/HAMA are continuous totals at Index and 1st waves."
    )
  )

  # Detailed require_* breakdown if present
  req <- attr[grepl("^require_", attr$step), , drop = FALSE]
  if (nrow(req) > 0L) {
    req_out <- data.frame(
      Step = req$step,
      `N remaining` = as.integer(req$n_remain),
      `N excluded` = as.integer(req$n_excluded),
      Rule = req$rule,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    export_sci_table(
      req_out,
      file.path(tab_dir, "Table. Outpatient node-wise completeness (cumulative).xlsx"),
      title = "Table. Outpatient node-wise completeness (cumulative)",
      table_footnotes = c(
        "Rows are cumulative after outpatient filter; each step requires one additional non-missing node.",
        "Final six-node complete N matches the attrition flowchart table."
      )
    )
  }

  # QC snapshot if present
  qc_path <- file.path(step_dir, "prep_qc.csv")
  if (file.exists(qc_path)) {
    qc <- utils::read.csv(qc_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
    qc_out <- data.frame(
      Cohort = qc$cohort,
      `N has ID` = qc$n_has_id,
      `N group` = qc$n_group,
      `N six-node complete` = qc$n_nodes_complete,
      `Mean HAMD Index` = sprintf("%.2f", as.numeric(qc$mean_HAMD_Index)),
      `Mean HAMD 1st` = sprintf("%.2f", as.numeric(qc$mean_HAMD_1st)),
      `Mean HAMA Index` = sprintf("%.2f", as.numeric(qc$mean_HAMA_Index)),
      `Mean HAMA 1st` = sprintf("%.2f", as.numeric(qc$mean_HAMA_1st)),
      `CSSRS Index Yes` = as.integer(qc$cssrs_index_yes),
      `CSSRS 1st Yes` = as.integer(qc$cssrs_1st_yes),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    export_sci_table(
      qc_out,
      file.path(tab_dir, "Table. Outpatient prep QC summary.xlsx"),
      title = "Table. Outpatient prep QC summary",
      table_footnotes = c(
        "CSSRS Yes counts refer to ideation item2.",
        "HAMD Index vs 1st means should differ (waves not identical)."
      )
    )
  }

  invisible(tab_dir)
}

#' Export step02 imputation products as SCI three-line tables.
suicide_clpm_export_step02_tables <- function(step_dir, n = NULL,
                                              before_rdata = NULL) {
  tab_dir <- suicide_clpm_step_tables_dir(step_dir)
  if (is.null(n)) {
    meta_path <- file.path(step_dir, "step_meta.csv")
    if (file.exists(meta_path)) {
      meta <- utils::read.csv(meta_path, stringsAsFactors = FALSE)
      n <- as.integer(meta$n[[1L]])
    } else {
      n <- NA_integer_
    }
  }

  # Resolve Before/After dabiao
  after_path <- file.path(step_dir, "dabiao.RData")
  if (!file.exists(after_path)) stop("Missing after-MI dabiao: ", after_path, call. = FALSE)
  e_after <- new.env(parent = emptyenv())
  load(after_path, envir = e_after)
  df_after <- e_after$dabiao

  if (is.null(before_rdata)) {
    before_rdata <- file.path(dirname(step_dir), "step01_data_clean", "dabiao.RData")
  }
  if (!file.exists(before_rdata)) {
    stop("Missing before-MI dabiao (step01): ", before_rdata, call. = FALSE)
  }
  e_before <- new.env(parent = emptyenv())
  load(before_rdata, envir = e_before)
  df_before <- e_before$dabiao

  mv_path <- file.path(step_dir, "mice_vars.csv")
  mice_vars <- if (file.exists(mv_path)) {
    utils::read.csv(mv_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")$variable
  } else {
    character(0)
  }
  mice_vars <- intersect(as.character(mice_vars), intersect(names(df_before), names(df_after)))

  .fmt2 <- function(x) sprintf("%.2f", as.numeric(x))
  .desc_one <- function(x) {
    if (is.numeric(x) || is.integer(x)) {
      x <- as.numeric(x)
      x <- x[is.finite(x)]
      if (!length(x)) return(list(kind = "cont", text = ""))
      return(list(
        kind = "cont",
        text = sprintf("%s (%s)", .fmt2(mean(x)), .fmt2(stats::sd(x)))
      ))
    }
    # categorical / factor / character
    xc <- as.character(x)
    xc[is.na(xc) | !nzchar(xc)] <- "(Missing)"
    tab <- sort(table(xc), decreasing = TRUE)
    list(kind = "cat", levels = names(tab), counts = as.integer(tab), n = length(xc))
  }

  # ---- Main: Before MI vs After MI characteristics ----
  rows <- list()
  for (v in mice_vars) {
    b <- .desc_one(df_before[[v]])
    a <- .desc_one(df_after[[v]])
    n_miss_b <- sum(is.na(df_before[[v]]))
    if (identical(b$kind, "cont") || identical(a$kind, "cont")) {
      # treat as continuous if either side numeric
      if (!identical(b$kind, "cont")) {
        xb <- suppressWarnings(as.numeric(as.character(df_before[[v]])))
        b <- .desc_one(xb)
      }
      if (!identical(a$kind, "cont")) {
        xa <- suppressWarnings(as.numeric(as.character(df_after[[v]])))
        a <- .desc_one(xa)
      }
      rows[[length(rows) + 1L]] <- data.frame(
        Characteristic = v,
        `Before MI` = b$text,
        `After MI` = a$text,
        `N missing before` = as.integer(n_miss_b),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
    } else {
      # categorical: variable header + level rows
      rows[[length(rows) + 1L]] <- data.frame(
        Characteristic = v,
        `Before MI` = "",
        `After MI` = "",
        `N missing before` = as.integer(n_miss_b),
        check.names = FALSE,
        stringsAsFactors = FALSE
      )
      levs <- unique(c(b$levels, a$levels))
      # put (Missing) last
      levs <- c(setdiff(levs, "(Missing)"), intersect(levs, "(Missing)"))
      for (lv in levs) {
        nb <- if (lv %in% b$levels) b$counts[match(lv, b$levels)] else 0L
        na <- if (lv %in% a$levels) a$counts[match(lv, a$levels)] else 0L
        pb <- if (b$n > 0L) 100 * nb / b$n else NA_real_
        pa <- if (a$n > 0L) 100 * na / a$n else NA_real_
        rows[[length(rows) + 1L]] <- data.frame(
          Characteristic = paste0("  ", lv),
          `Before MI` = sprintf("%d (%.1f%%)", nb, pb),
          `After MI` = sprintf("%d (%.1f%%)", na, pa),
          `N missing before` = NA_integer_,
          check.names = FALSE,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  cmp <- do.call(rbind, rows)
  rownames(cmp) <- NULL
  export_sci_table(
    cmp,
    file.path(tab_dir, "Table. Baseline characteristics before and after multiple imputation.xlsx"),
    title = "Table. Baseline characteristics before and after multiple imputation",
    table_footnotes = c(
      paste0("Outpatient N = ", n, " (same analytic sample; imputation fills covariate missing values only)."),
      "Before MI = step01 six-node complete data; After MI = step02 after MICE (complete_action=1).",
      "Continuous variables: mean (SD). Categorical variables: n (%).",
      "Only covariates that entered MICE are shown; HAMD/HAMA/CSSRS (item2) were never imputed.",
      "MICE: method=cart, m=5, seed=40595747; covariate missing-rate entry threshold <40%."
    )
  )

  mba_path <- file.path(step_dir, "missing_before_after.csv")
  if (!file.exists(mba_path)) stop("Missing missing_before_after.csv", call. = FALSE)
  mba <- utils::read.csv(mba_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  mba_out <- data.frame(
    Variable = mba$variable,
    `N missing Before MI` = as.integer(mba$n_missing_before),
    `% missing Before MI` = sprintf("%.2f", as.numeric(mba$pct_missing_before)),
    `N missing After MI` = as.integer(mba$n_missing_after),
    `% missing After MI` = sprintf("%.2f", as.numeric(mba$pct_missing_after)),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  export_sci_table(
    mba_out,
    file.path(tab_dir, "Table. Covariate missingness Before MI vs After MI.xlsx"),
    title = "Table. Covariate missingness Before MI vs After MI",
    table_footnotes = c(
      paste0("Outpatient analysis N = ", n, " (unchanged by imputation)."),
      "Companion to the Before/After characteristics table; counts of missing cells only.",
      "MICE: method=cart, m=5, complete_action=1, seed=40595747.",
      "Only baseline covariates with missing rate <40% entered MICE.",
      "HAMD / HAMA / CSSRS (item2) related columns were never imputed."
    )
  )

  if (file.exists(mv_path)) {
    mv <- utils::read.csv(mv_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
    mv_out <- data.frame(
      Variable = mv$variable,
      `Entered MICE` = ifelse(isTRUE(mv$in_mice) | mv$in_mice %in% TRUE, "Yes", "No"),
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    export_sci_table(
      mv_out,
      file.path(tab_dir, "Table. Variables entered into MICE.xlsx"),
      title = "Table. Variables entered into MICE",
      table_footnotes = c(
        "Covariate whitelist from config; high-missing (>=40%) covariates excluded.",
        "Scale/node columns are listed in the excluded-from-MICE table."
      )
    )
  }

  ex_path <- file.path(step_dir, "excluded_from_mice.csv")
  if (file.exists(ex_path)) {
    ex <- utils::read.csv(ex_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
    ex_out <- data.frame(
      Variable = ex$variable,
      `Excluded from MICE` = "Yes",
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    export_sci_table(
      ex_out,
      file.path(tab_dir, "Table. Variables excluded from MICE.xlsx"),
      title = "Table. Variables excluded from MICE",
      table_footnotes = c(
        "Includes HAMD/HAMA/CSSRS nodes, raw scale copies, and design ID columns.",
        "CSSRS = ideation item2."
      )
    )
  }

  drop_path <- file.path(step_dir, "dropped_high_missing.csv")
  if (file.exists(drop_path)) {
    dr <- utils::read.csv(drop_path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
    dr_out <- data.frame(
      Variable = dr$variable,
      `% missing` = sprintf("%.2f", as.numeric(dr$pct_missing)),
      Reason = dr$reason,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
    export_sci_table(
      dr_out,
      file.path(tab_dir, "Table. Covariates dropped for high missingness.xlsx"),
      title = "Table. Covariates dropped for high missingness",
      table_footnotes = c(
        "Threshold: missing rate >=40%; these covariates were not imputed and not used in MICE."
      )
    )
  }

  # Compact method note (S1-style)
  note_path <- file.path(step_dir, "imputation_note.txt")
  note_lines <- if (file.exists(note_path)) readLines(note_path, warn = FALSE) else character(0)
  parse_kv <- function(key) {
    hit <- grep(paste0("^", key, "="), note_lines, value = TRUE)
    if (!length(hit)) return("")
    sub(paste0("^", key, "="), "", hit[[1L]])
  }
  s1 <- data.frame(
    Item = c(
      "Imputation method",
      "m / complete_action / seed",
      "Missingness threshold for covariate entry",
      "Variables entered into MICE (n)",
      "Scale/node columns excluded from MICE",
      "Dropped high-missing covariates",
      "Analysis N"
    ),
    Detail = c(
      parse_kv("IMPUTATION"),
      "m=5; complete_action=1; seed=40595747",
      "<40% missing required to enter MICE",
      as.character(length(mice_vars)),
      parse_kv("SCALE_COLS_FROZEN"),
      parse_kv("DROPPED_HI_MISS"),
      as.character(n)
    ),
    stringsAsFactors = FALSE
  )
  export_sci_table(
    s1,
    file.path(tab_dir, "Table. Multiple imputation note (covariates only).xlsx"),
    title = "Table. Multiple imputation note (covariates only)",
    table_footnotes = c(
      "Six CLPM nodes were listwise-complete before imputation and were never imputed.",
      "Only baseline covariates were eligible for MICE.",
      "See also: Baseline characteristics before and after multiple imputation."
    )
  )

  invisible(tab_dir)
}
