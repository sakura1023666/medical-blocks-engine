###############################################################################
#  mediation_multi_db_cox — 多库相关 + 未加权 Cox 中介（全项目复用）
#
#  用途：对若干候选中介做 Crude/Model1/Model2 相关，再做 Cox 系数乘积中介；
#        中介本身不进入该路径模型的协变量；路径图可固定某一个中介（不按 P 值挑选）。
#  注意：路径模型默认未加权 coxph（含 NHANES），与 survey 加权主表不是同一模型。
#  入组定义变量（如血脂异常队列里的血脂）应通过 mediators 排除，勿放进 mediators。
#
#  入口：
#    mediation_multi_db_cox_run(...)
#    mediation_multi_db_write_xlsx(...)
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a

.mediation_multi_db_ensure_diagram <- function() {
  eng <- if (dir.exists("E:/01block/01Block-new-Final")) {
    "E:/01block/01Block-new-Final"
  } else if (exists("ENGINE_ROOT", inherits = TRUE)) {
    get("ENGINE_ROOT", inherits = TRUE)
  } else {
    "/mnt/e/01block/01Block-new-Final"
  }
  src <- file.path(eng, "Blocks/20_mediation/01block_mediation_prognosis.R")
  if (!exists(".mp01_draw_mediation_path_diagram", mode = "function")) {
    eval(parse(text = readLines(src, warn = FALSE)[35:346]), envir = .GlobalEnv)
  }
  invisible(TRUE)
}

mediation_multi_db_cox_run <- function(
    dbs,
    exposure = "Sleep_hours",
    mediators,
    mediator_labels = NULL,
    diagram_mediator = NULL,
    path_covariates,
    cor_adj1 = "Age",
    cor_adj2 = c("Age", "Gender"),
    bootstrap_iter = 100L,
    seed = 1L,
    exposure_label = NULL,
    outcome_label = "All-cause mortality",
    time_var = "time",
    event_var = "event",
    fig_path = NULL,
    tab_dir = NULL,
    diagram_palette = "matcha") {
  suppressPackageStartupMessages({
    library(survival)
    library(ggplot2)
  })
  .mediation_multi_db_ensure_diagram()
  if (is.null(exposure_label)) exposure_label <- gsub("_", " ", exposure)
  if (is.null(diagram_mediator) || !nzchar(diagram_mediator)) diagram_mediator <- mediators[1L]
  if (is.null(mediator_labels)) {
    mediator_labels <- setNames(gsub("_", " ", mediators), mediators)
  }
  med_cov_of <- function(med) setdiff(path_covariates, med)

  one_lm <- function(d, med, rhs) {
    f <- stats::lm(stats::as.formula(paste(exposure, "~", paste(c(med, rhs), collapse = "+"))), data = d)
    cf <- summary(f)$coefficients
    rn <- rownames(cf)
    hit <- rn[rn == med | startsWith(rn, med)][1]
    ci <- tryCatch(stats::confint(f)[hit, ], error = function(e) c(NA, NA))
    c(beta = unname(cf[hit, 1]), lo = unname(ci[1]), hi = unname(ci[2]), p = unname(cf[hit, 4]))
  }

  one_med <- function(d, med, B) {
    med_cov <- med_cov_of(med)
    need <- c(time_var, event_var, exposure, med, med_cov)
    dd <- d[stats::complete.cases(d[, need]), need]
    names(dd)[names(dd) == time_var] <- "time"
    names(dd)[names(dd) == event_var] <- "event"
    names(dd)[names(dd) == exposure] <- "Sleep_hours"
    for (v in intersect(c("Gender", "Education", "Hypertension", "Alcohol", "Smoke"), names(dd))) {
      dd[[v]] <- factor(dd[[v]])
    }
    dd$.M <- as.numeric(scale(dd[[med]]))
    if (!length(med_cov)) {
      fa <- stats::as.formula(".M ~ Sleep_hours")
      ff <- stats::as.formula("Surv(time, event) ~ Sleep_hours + .M")
      ft <- stats::as.formula("Surv(time, event) ~ Sleep_hours")
    } else {
      rhs <- paste(med_cov, collapse = " + ")
      fa <- stats::as.formula(paste(".M ~ Sleep_hours +", rhs))
      ff <- stats::as.formula(paste("Surv(time, event) ~ Sleep_hours + .M +", rhs))
      ft <- stats::as.formula(paste("Surv(time, event) ~ Sleep_hours +", rhs))
    }
    ma <- stats::lm(fa, data = dd)
    mf <- survival::coxph(ff, data = dd, ties = "efron")
    mt <- survival::coxph(ft, data = dd, ties = "efron")
    ca <- stats::coef(ma)[["Sleep_hours"]]
    sea <- summary(ma)$coefficients["Sleep_hours", "Std. Error"]
    pa <- summary(ma)$coefficients["Sleep_hours", "Pr(>|t|)"]
    cb <- stats::coef(mf)[[".M"]]
    seb <- summary(mf)$coefficients[".M", "se(coef)"]
    pb <- summary(mf)$coefficients[".M", "Pr(>|z|)"]
    cprime <- stats::coef(mf)[["Sleep_hours"]]
    secprime <- summary(mf)$coefficients["Sleep_hours", "se(coef)"]
    pcprime <- summary(mf)$coefficients["Sleep_hours", "Pr(>|z|)"]
    cc <- stats::coef(mt)[["Sleep_hours"]]
    sec <- summary(mt)$coefficients["Sleep_hours", "se(coef)"]
    pc <- summary(mt)$coefficients["Sleep_hours", "Pr(>|z|)"]
    set.seed(seed)
    pm_boot <- replicate(B, {
      idx <- sample.int(nrow(dd), replace = TRUE)
      db <- dd[idx, ]
      db$.M <- as.numeric(scale(db[[med]]))
      a <- tryCatch(stats::coef(stats::lm(fa, data = db))[["Sleep_hours"]], error = function(e) NA_real_)
      b <- tryCatch(stats::coef(survival::coxph(ff, data = db, ties = "efron"))[[".M"]], error = function(e) NA_real_)
      ctot <- tryCatch(stats::coef(survival::coxph(ft, data = db, ties = "efron"))[["Sleep_hours"]], error = function(e) NA_real_)
      if (any(!is.finite(c(a, b, ctot))) || abs(ctot) < 1e-10) return(NA_real_)
      (a * b) / ctot
    })
    pm_ci <- stats::quantile(pm_boot, c(0.025, 0.975), na.rm = TRUE)
    se_ab <- sqrt(ca^2 * seb^2 + cb^2 * sea^2)
    p_ab <- 2 * (1 - stats::pnorm(abs((ca * cb) / se_ab)))
    prop <- if (is.finite(cc) && abs(cc) > 1e-10) (ca * cb) / cc else NA_real_
    list(
      coef_a = ca, se_a = sea, p_a = pa,
      coef_b = cb, se_b = seb, p_b = pb,
      coef_c = cc, se_c = sec, p_c = pc,
      coef_cp = cprime, se_cp = secprime, p_cp = pcprime,
      se_ab = se_ab, p_ab = p_ab, prop = prop,
      prop_lo = unname(pm_ci[1]), prop_hi = unname(pm_ci[2])
    )
  }

  fmt <- function(x) formatC(round(as.numeric(x), 3), format = "f", digits = 3)
  cor_rows <- list()
  med_rows <- list()
  plots <- list()
  diag_fits <- list()

  for (nm in names(dbs)) {
    d <- as.data.frame(dbs[[nm]])
    if (!time_var %in% names(d) && "futime_years" %in% names(d)) d[[time_var]] <- d$futime_years
    if (!event_var %in% names(d) && "fustatus" %in% names(d)) d[[event_var]] <- d$fustatus
    if ("Gender" %in% names(d)) d$Gender <- factor(d$Gender)
    keep_cols <- unique(c(time_var, event_var, exposure, mediators, path_covariates, cor_adj1, cor_adj2))
    keep_cols <- intersect(keep_cols, names(d))
    d <- d[stats::complete.cases(d[, keep_cols]) & d[[time_var]] > 0, ]
    message(nm, " 相关 + 中介 n=", nrow(d))
    diag_fit <- NULL
    for (med in mediators) {
      dz <- d
      dz[[med]] <- as.numeric(scale(dz[[med]]))
      crude <- one_lm(dz, med, character(0))
      m1 <- one_lm(dz, med, intersect(cor_adj1, names(dz)))
      m2 <- one_lm(dz, med, intersect(cor_adj2, names(dz)))
      cor_rows[[length(cor_rows) + 1L]] <- rbind(
        data.frame(database = nm, mediator = med, model = "Crude",
                   beta = crude["beta"], lo = crude["lo"], hi = crude["hi"], p = crude["p"],
                   stringsAsFactors = FALSE),
        data.frame(database = nm, mediator = med, model = "Model1",
                   beta = m1["beta"], lo = m1["lo"], hi = m1["hi"], p = m1["p"],
                   stringsAsFactors = FALSE),
        data.frame(database = nm, mediator = med, model = "Model2",
                   beta = m2["beta"], lo = m2["lo"], hi = m2["hi"], p = m2["p"],
                   stringsAsFactors = FALSE)
      )
      message(sprintf("  %s Model2 beta=%.3f p=%.3g", med, m2["beta"], m2["p"]))
      r <- one_med(d, med, bootstrap_iter)
      if (identical(med, diagram_mediator)) diag_fit <- r
      message(sprintf("  %s direct HR=%.3f prop=%.1f%%", med, exp(r$coef_cp), 100 * r$prop))
      med_rows[[length(med_rows) + 1L]] <- data.frame(
        database = nm, mediator = med,
        path_a = paste0(fmt(r$coef_a), " (", fmt(r$coef_a - 1.96 * r$se_a), ", ", fmt(r$coef_a + 1.96 * r$se_a), ")"),
        path_a_p = r$p_a,
        path_b = paste0(fmt(r$coef_b), " (", fmt(r$coef_b - 1.96 * r$se_b), ", ", fmt(r$coef_b + 1.96 * r$se_b), ")"),
        path_b_p = r$p_b,
        total_HR = paste0(fmt(exp(r$coef_c)), " (", fmt(exp(r$coef_c - 1.96 * r$se_c)), ", ", fmt(exp(r$coef_c + 1.96 * r$se_c)), ")"),
        direct_HR = paste0(fmt(exp(r$coef_cp)), " (", fmt(exp(r$coef_cp - 1.96 * r$se_cp)), ", ", fmt(exp(r$coef_cp + 1.96 * r$se_cp)), ")"),
        indirect = paste0(fmt(exp(r$coef_a * r$coef_b)), " (", fmt(exp(r$coef_a * r$coef_b - 1.96 * r$se_ab)), ", ", fmt(exp(r$coef_a * r$coef_b + 1.96 * r$se_ab)), ")"),
        prop_pct = round(100 * r$prop, 3),
        prop_lo_pct = round(100 * r$prop_lo, 3),
        prop_hi_pct = round(100 * r$prop_hi, 3),
        stringsAsFactors = FALSE
      )
    }
    diag_fits[[nm]] <- diag_fit
    br <- diag_fit
    if (!is.null(br)) {
      pal <- .mp01_palettes[[diagram_palette]] %||% .mp01_palettes$matcha
      plots[[nm]] <- .mp01_draw_mediation_path_diagram(
        exposure_label = exposure_label,
        mediator_label = unname(mediator_labels[[diagram_mediator]] %||% diagram_mediator),
        outcome_label = outcome_label,
        coef_a = br$coef_a, p_a = br$p_a,
        coef_b = br$coef_b, p_b = br$p_b,
        effect_total = exp(br$coef_cp), p_total = br$p_cp,
        prop_pct = 100 * br$prop,
        prop_lo_pct = 100 * br$prop_lo,
        prop_hi_pct = 100 * br$prop_hi,
        colors = pal,
        ci_a_lo = br$coef_a - 1.96 * br$se_a,
        ci_a_hi = br$coef_a + 1.96 * br$se_a,
        ci_b_lo = br$coef_b - 1.96 * br$se_b,
        ci_b_hi = br$coef_b + 1.96 * br$se_b,
        ci_tot_lo = exp(br$coef_cp - 1.96 * br$se_cp),
        ci_tot_hi = exp(br$coef_cp + 1.96 * br$se_cp),
        font_family = "Times"
      ) + ggplot2::ggtitle(nm)
    }
  }

  cor_tab <- do.call(rbind, cor_rows)
  med_tab <- do.call(rbind, med_rows)
  if (!is.null(tab_dir) && dir.exists(tab_dir)) {
    data.table::fwrite(cor_tab, file.path(tab_dir, "Table mediation correlation.csv"))
    data.table::fwrite(med_tab, file.path(tab_dir, "Table mediation cox.csv"))
  }
  if (!is.null(fig_path) && length(plots)) {
    stem <- sub("\\.[^.]+$", "", basename(fig_path))
    old <- list.files(
      dirname(fig_path),
      pattern = paste0("^", gsub("([.\\(\\)])", "\\\\\\1", stem)),
      full.names = TRUE
    )
    if (length(old)) unlink(old)
    n <- length(plots)
    grDevices::cairo_pdf(fig_path, width = 7.2, height = max(4.2 * n, 4.2), family = "Times")
    grid::grid.newpage()
    for (i in seq_len(n)) {
      print(plots[[i]], vp = grid::viewport(y = (n - i + 0.5) / n, height = 1 / n))
    }
    grDevices::dev.off()
    message("中介图: ", fig_path)
  }
  invisible(list(
    correlation = cor_tab,
    mediation = med_tab,
    mediator_labels = mediator_labels,
    diagram_mediator = diagram_mediator,
    path_covariates = path_covariates,
    plots = plots
  ))
}

mediation_multi_db_write_xlsx <- function(
    res,
    tab_dir,
    databases = NULL,
    corr_title = "Table S7. Correlation between exposure and mediators",
    med_title = "Table S8. Mediation analysis",
    corr_filename = function(db) sprintf("Table S7-%s. Correlation between exposure and mediators.xlsx", db),
    med_filename = function(db) sprintf("Table S8-%s. Mediation analysis.xlsx", db),
    corr_footnotes = NULL,
    med_footnotes = NULL) {
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    stop("mediation_multi_db_write_xlsx: source R/utils.R first")
  }
  fmt_p <- function(p) {
    p <- suppressWarnings(as.numeric(p))
    ifelse(!is.finite(p), "", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p)))
  }
  lab <- res$mediator_labels
  cor <- res$correlation
  med <- res$mediation
  if (is.null(databases)) databases <- unique(as.character(cor$database))
  if (is.null(corr_footnotes)) {
    corr_footnotes <- c(
      "The Crude Model was non-adjusted.",
      "The Model 1 was adjusted by: Age.",
      "The Model 2 was adjusted by: Age, Gender.",
      "The outcome of each linear model is the exposure. Mediators are standardized to 1 SD."
    )
  }
  if (is.null(med_footnotes)) {
    med_footnotes <- c(
      "Path models are unweighted Cox models, including in NHANES when that database is present.",
      "The mediator is omitted from its own adjustment set.",
      "A negative proportion mediated indicates suppression, not a mediated fraction."
    )
  }
  for (nm in databases) {
    sub <- cor[cor$database == nm, ]
    cor_df <- data.frame(
      Mediator = unname(lab[sub$mediator]),
      Model = sub$model,
      `Beta (95% CI)` = sprintf("%.3f (%.3f, %.3f)", sub$beta, sub$lo, sub$hi),
      P = fmt_p(sub$p),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    p7 <- file.path(tab_dir, corr_filename(nm))
    sci_xlsx_single_header_booktabs(p7, title = corr_title, df_body = cor_df, footnotes = corr_footnotes)
    sm <- med[med$database == nm, ]
    med_df <- data.frame(
      Mediator = unname(lab[sm$mediator]),
      `Path a (95% CI)` = sm$path_a,
      `Path a P` = fmt_p(sm$path_a_p),
      `Path b (95% CI)` = sm$path_b,
      `Path b P` = fmt_p(sm$path_b_p),
      `Direct effect HR (95% CI)` = sm$direct_HR,
      `Proportion mediated, %` = sm$prop_pct,
      `Proportion 95% CI, %` = sprintf("%.3f, %.3f", sm$prop_lo_pct, sm$prop_hi_pct),
      check.names = FALSE, stringsAsFactors = FALSE
    )
    p8 <- file.path(tab_dir, med_filename(nm))
    sci_xlsx_single_header_booktabs(p8, title = med_title, df_body = med_df, footnotes = med_footnotes)
    message(basename(p7), " / ", basename(p8))
  }
  invisible(TRUE)
}
