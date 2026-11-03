###############################################################################
#  cox_multi_horizon — 院内 / 30d / 365d 多时点 Cox（Table 2 风格）
#
#  register_block: "cox_multi_horizon"
#  典型流水线: derived_grouping 之后；UV/VIF/Cox 之后
#
#  config$cox_multi_horizon = list(
#    enable = TRUE,
#    exposure_var = "Index_SOFA_Q",   # 或 Index_HL
#    ref_level = "Q1",
#    horizons = c("hosp", "d30", "d365"),
#    # 列名覆盖（缺则用默认 / 已有 futime/fustatus）
#    hosp = list(time = "futime", event = "fustatus"),
#    d30  = list(time = "time_d30", event = "event_d30"),
#    d365 = list(time = "time_d365", event = "event_d365"),
#    model1_factors = NULL,           # NULL → ctx Model1Factors
#    model2_factors = NULL,
#    exclude_adjust = character(0)    # 额外踢出调整集（SOFA 默认踢）
#  )
#  兼容: 缺 config$cox_multi_horizon 时回读 config$jin_index_sofa$multi_horizon
#
#  推断: 有 mids 且 rubin_pool → mi_coxph；否则 complete#1 + 脚注说明
#  写: ctx$results$cox_multi_horizon；step 目录 CSV；export_sci_table（若可用）
#  禁止: write.xlsx 覆盖已导出 SCI 三线表
###############################################################################

.cox_mh_cfg <- function(cfg) {
  top <- cfg$cox_multi_horizon %||% list()
  if (length(top)) return(top)
  (cfg$jin_index_sofa %||% list())$multi_horizon %||% list()
}

.cox_mh_hr_row <- function(fit, term_pattern = NULL) {
  cf <- tryCatch(stats::coef(fit), error = function(e) NULL)
  if (is.null(cf) || !length(cf)) {
    return(data.frame(
      term = NA_character_, HR = NA_real_, lo = NA_real_, hi = NA_real_,
      p = NA_real_, HR_CI = NA_character_, stringsAsFactors = FALSE
    ))
  }
  nm <- names(cf)
  if (!is.null(term_pattern) && nzchar(term_pattern)) {
    hit <- grep(term_pattern, nm, value = TRUE)
    if (!length(hit)) hit <- nm
  } else {
    hit <- nm
  }
  sm <- tryCatch(summary(fit), error = function(e) NULL)
  ci <- tryCatch(stats::confint(fit), error = function(e) NULL)
  rows <- lapply(hit, function(tn) {
    est <- unname(cf[[tn]])
    hr <- exp(est)
    if (!is.null(ci) && tn %in% rownames(ci)) {
      lo <- exp(ci[tn, 1L]); hi <- exp(ci[tn, 2L])
    } else {
      se <- tryCatch(sqrt(diag(stats::vcov(fit)))[[tn]], error = function(e) NA_real_)
      lo <- exp(est - 1.96 * se); hi <- exp(est + 1.96 * se)
    }
    p <- NA_real_
    if (!is.null(sm) && !is.null(sm$coefficients) && tn %in% rownames(sm$coefficients)) {
      pc <- intersect(c("Pr(>|z|)", "Pr(>|Z|)"), colnames(sm$coefficients))
      if (length(pc)) p <- sm$coefficients[tn, pc[[1L]]]
    }
    hr_s <- if (exists("pub_format_est", mode = "function")) pub_format_est(hr) else sprintf("%.3f", hr)
    lo_s <- if (exists("pub_format_est", mode = "function")) pub_format_est(lo) else sprintf("%.3f", lo)
    hi_s <- if (exists("pub_format_est", mode = "function")) pub_format_est(hi) else sprintf("%.3f", hi)
    p_s <- if (exists("pub_format_p", mode = "function")) pub_format_p(p) else
      if (exists("fmt_pval", mode = "function")) fmt_pval(p) else sprintf("%.3f", p)
    data.frame(
      term = tn, HR = as.numeric(hr), lo = as.numeric(lo), hi = as.numeric(hi),
      p = as.numeric(p),
      HR_CI = sprintf("%s (%s, %s)", hr_s, lo_s, hi_s),
      P = p_s,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

.cox_mh_fit_one <- function(ctx, data, time_var, event_var, rhs, use_rubin) {
  if (!all(c(time_var, event_var) %in% names(data))) return(NULL)
  d <- data
  d$.t <- suppressWarnings(as.numeric(d[[time_var]]))
  d$.e <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) == 1L)
  ok <- is.finite(d$.t) & d$.t > 0 & !is.na(d$.e)
  d <- d[ok, , drop = FALSE]
  if (!nrow(d) || length(unique(d$.e)) < 2L) return(NULL)

  rhs <- rhs[rhs %in% names(d)]
  if (!length(rhs)) return(NULL)
  fml <- stats::as.formula(
    paste("survival::Surv(.t, .e) ~", paste(rhs, collapse = " + "))
  )
  if (isTRUE(use_rubin) && exists("mi_coxph", mode = "function")) {
    d2 <- d
    d2[[time_var]] <- d2$.t
    d2[[event_var]] <- d2$.e
    fml2 <- stats::as.formula(
      paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ",
             paste(rhs, collapse = " + "))
    )
    fit <- tryCatch(
      mi_coxph(ctx, fml2, d2, keep_vars = c(time_var, event_var, rhs)),
      error = function(e) NULL
    )
    if (!is.null(fit)) return(list(fit = fit, n = nrow(d), pool = "rubin"))
  }
  fit <- tryCatch(survival::coxph(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  list(fit = fit, n = nrow(d), pool = "complete1")
}

block_cox_multi_horizon <- function(ctx, ...) {
  ## 助手在引擎 R/，勿只从课题 project$root 找
  .cands <- unique(c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    as.character(ctx$config$project$root %||% "")[1L],
    getwd()
  ))
  .lit <- NULL
  for (.r in .cands[nzchar(as.character(.cands))]) {
    .p <- file.path(.r, "R", "literature_jin_index_sofa.R")
    if (file.exists(.p)) { .lit <- .p; break }
  }
  if (!is.null(.lit)) source(.lit, local = FALSE)

  cfg <- ctx$config
  mh <- .cox_mh_cfg(cfg)
  if (!is.null(mh$enable) && !isTRUE(mh$enable)) {
    cli::cli_alert_info("cox_multi_horizon: enable=FALSE，跳过")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    stop("cox_multi_horizon: 无数据", call. = FALSE)
  }

  strata <- ctx$results$derived_grouping %||%
    ctx$results$jin_index_sofa_strata %||% list()
  expo <- as.character(
    mh$exposure_var %||% strata$q4_var %||% "Index_SOFA_Q"
  )[1L]
  if (!expo %in% names(data)) {
    stop("cox_multi_horizon: 暴露列不存在: ", expo, call. = FALSE)
  }
  ref <- as.character(mh$ref_level %||% "Q1")[1L]
  if (is.factor(data[[expo]]) || is.character(data[[expo]])) {
    data[[expo]] <- factor(as.character(data[[expo]]))
    if (ref %in% levels(data[[expo]])) {
      data[[expo]] <- stats::relevel(data[[expo]], ref = ref)
    }
  }

  m1 <- mh$model1_factors %||% ctx$results$Model1Factors %||% c("Age", "Gender")
  m2 <- mh$model2_factors %||% ctx$results$Model2Factors %||% m1
  m1 <- as.character(m1); m2 <- as.character(m2)
  excl <- unique(c(
    as.character(mh$exclude_adjust %||% character(0)),
    strata$sofa_var %||% "SOFA",
    strata$sofa_bin_var %||% "SOFA_bin",
    expo,
    "Index_SOFA_Q", "Index_HL", "SOFA_bin",
    as.character((cfg$analysis_exclusion %||% list())$disease_vars %||% character(0))
  ))
  m1 <- setdiff(m1, excl)
  m2 <- setdiff(unique(c(m1, m2)), excl)
  m1 <- m1[m1 %in% names(data)]
  m2 <- m2[m2 %in% names(data)]

  use_rubin <- exists("mi_rubin_enabled", mode = "function") && isTRUE(mi_rubin_enabled(ctx))
  pool_note <- if (use_rubin) {
    "Estimates pooled across m=5 imputed datasets by Rubin's rules (mi_coxph)."
  } else {
    "Fits used the operational complete dataset (complete#1 / single complete); not Rubin-pooled."
  }

  horiz_specs <- list(
    hosp = list(
      label = "In-hospital",
      time = (mh$hosp %||% list())$time %||% "futime",
      event = (mh$hosp %||% list())$event %||% "fustatus"
    ),
    d30 = list(
      label = "30-day",
      time = (mh$d30 %||% list())$time %||% "time_d30",
      event = (mh$d30 %||% list())$event %||% "event_d30"
    ),
    d365 = list(
      label = "365-day",
      time = (mh$d365 %||% list())$time %||% "time_d365",
      event = (mh$d365 %||% list())$event %||% "event_d365"
    )
  )
  want <- as.character(mh$horizons %||% c("hosp", "d30", "d365"))
  want <- intersect(want, names(horiz_specs))

  if (!horiz_specs$hosp$time %in% names(data)) {
    tv <- cfg$survival$time_var %||% NULL
    ev <- cfg$survival$event_var %||% NULL
    if (!is.null(tv) && tv %in% names(data)) horiz_specs$hosp$time <- tv
    if (!is.null(ev) && ev %in% names(data)) horiz_specs$hosp$event <- ev
  }

  rows <- list()
  meta <- list()
  for (h in want) {
    sp <- horiz_specs[[h]]
    if (!all(c(sp$time, sp$event) %in% names(data))) {
      cli::cli_alert_warning(
        "cox_multi_horizon: 跳过 {h}（缺列 {sp$time}/{sp$event}）"
      )
      next
    }
    specs_rhs <- list(
      Crude = expo,
      Model1 = c(expo, m1),
      Model2 = c(expo, m2)
    )
    for (mn in names(specs_rhs)) {
      fit_info <- .cox_mh_fit_one(ctx, data, sp$time, sp$event, specs_rhs[[mn]], use_rubin)
      if (is.null(fit_info)) next
      tab <- .cox_mh_hr_row(fit_info$fit)
      if (!nrow(tab)) next
      tab$horizon <- sp$label
      tab$horizon_id <- h
      tab$model <- mn
      tab$n <- fit_info$n
      tab$pool <- fit_info$pool
      rows[[length(rows) + 1L]] <- tab
      meta[[paste(h, mn, sep = "/")]] <- list(
        n = fit_info$n, pool = fit_info$pool,
        time = sp$time, event = sp$event
      )
    }
  }

  if (!length(rows)) {
    cli::cli_alert_warning("cox_multi_horizon: 无成功拟合，跳过导出")
    res <- list(ok = FALSE, note = pool_note)
    ctx$results$cox_multi_horizon <- res
    ctx$results$jin_multi_horizon_cox <- res
    return(ctx)
  }

  out_df <- do.call(rbind, rows)
  rownames(out_df) <- NULL

  out_dir <- cfg$project$output_dir %||% NULL
  if (is.null(out_dir) || !nzchar(out_dir)) {
    out_dir <- file.path(root, "Output")
  }
  step_dir <- file.path(out_dir, "step_cox_multi_horizon")
  dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)
  csv_path <- file.path(step_dir, "Table_multi_horizon_cox.csv")
  utils::write.csv(out_df, csv_path, row.names = FALSE)
  writeLines(pool_note, file.path(step_dir, "footnote_pool.txt"))

  pub_df <- out_df[, intersect(
    c("horizon", "model", "term", "HR_CI", "P", "n", "pool"),
    names(out_df)
  ), drop = FALSE]
  title <- paste0(
    "Table. Multivariable Cox across mortality horizons (",
    expo, "; ref=", ref, ")"
  )
  tbl_dir <- file.path(out_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  xlsx_path <- file.path(tbl_dir, "Table. Multi-horizon Cox Index_SOFA_Q.xlsx")
  exported <- FALSE
  if (exists("export_sci_table", mode = "function")) {
    tryCatch({
      export_sci_table(
        pub_df,
        filepath = xlsx_path,
        title = title,
        table_footnotes = c(
          pool_note,
          paste0("Exposure=", expo, "; SOFA used only in stratum coding, not as adjuster."),
          "Middle tertile of exposure excluded from Q1-Q4 (NA)."
        )
      )
      exported <- TRUE
    }, error = function(e) {
      cli::cli_alert_warning("export_sci_table 失败: {e$message}；保留 CSV")
    })
  }

  res <- list(
    ok = TRUE,
    exposure = expo,
    ref = ref,
    model1 = m1,
    model2 = m2,
    table = out_df,
    csv = csv_path,
    xlsx = if (exported) xlsx_path else NA_character_,
    pool_note = pool_note,
    use_rubin = use_rubin,
    meta = meta
  )
  ctx$results$cox_multi_horizon <- res
  ctx$results$jin_multi_horizon_cox <- res
  cli::cli_alert_success(
    "cox_multi_horizon: {nrow(out_df)} 行（Rubin={use_rubin}）→ {basename(csv_path)}"
  )
  ctx
}

register_block(
  "cox_multi_horizon",
  block_cox_multi_horizon,
  "多时点Cox（院内/30d/365d，优先Rubin）"
)
