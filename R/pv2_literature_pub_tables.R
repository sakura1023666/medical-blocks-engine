###############################################################################
# pv2_literature_pub_tables.R — 预后文献宽表 / S6–S8（引擎级，全项目复用）
#
# 本轮 Hip AKI 沉淀：Jin/TyG 式 M1–M3 宽表、插补前后 S6、暴露–中介 S7、
# 中介路径 S8、敏感性改终点（如 90 天）。课题只传路径/指标/协变量，勿再抄脚本。
#
# 依赖：R/utils.R（sci_xlsx_* / fmt_*）、run/prognosis_v2/pv2_mi_cox.R、
#       R/quantile_scheme_cascade.R（分组展示名）
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0L) b else a

pv2_fmt_p <- function(p) {
  p <- suppressWarnings(as.numeric(p)[1L])
  if (!is.finite(p)) "" else if (p < 0.001) "<0.001" else sprintf("%.3f", p)
}

pv2_hr_cell <- function(hr, lo, hi) {
  if (!all(is.finite(c(hr, lo, hi)))) return("")
  sprintf("%.3f (%.3f\u2013%.3f)", hr, lo, hi)
}

pv2_ci_cell <- function(est, lo, hi, digits = 3L) {
  if (!all(is.finite(c(est, lo, hi)))) return("")
  sprintf(paste0("%.", digits, "f (%.", digits, "f, %.", digits, "f)"), est, lo, hi)
}

#' 定位 summary_results 旁最新 delivery workspace（含 imputed_dbs.rds）
pv2_resolve_delivery_workspace <- function(summary_results_dir) {
  root <- dirname(as.character(summary_results_dir)[1L])
  cands <- list.files(
    file.path(root, "summary_results_delivery_workspace"),
    pattern = "^tables_non_xlsx_", full.names = TRUE
  )
  if (!length(cands)) {
    cands <- list.files(root, pattern = "imputed_dbs\\.rds$", recursive = TRUE, full.names = TRUE)
    if (length(cands)) return(dirname(cands[1L]))
    stop("pv2_resolve_delivery_workspace: no workspace under ", root)
  }
  cands[order(file.info(cands)$mtime, decreasing = TRUE)][1L]
}

#' 将随访截尾到 landmark 天，并重定义事件（敏感性终点）
pv2_censor_at_days <- function(d, days,
                               time_var = "futime_years",
                               event_var = "fustatus") {
  d <- as.data.frame(d)
  days <- as.integer(days)[1L]
  t_cap <- days / 365.25
  t0 <- suppressWarnings(as.numeric(d[[time_var]]))
  e0 <- as.integer(d[[event_var]])
  d[[event_var]] <- as.integer(e0 == 1L & t0 <= t_cap)
  d[[time_var]] <- pmin(t0, t_cap)
  d$time <- d[[time_var]]
  d$event <- d[[event_var]]
  attr(d, "landmark_days") <- days
  d
}

#' 文献宽表：Variable | M1 HR | P | M2 HR | P | M3 HR | P
#' @param resolved quantile_scheme_resolve_cascade 结果（含 meta + 已 attach groups）
pv2_cox_wide_m123_body <- function(
    d, indices,
    resolved,
    mids = NULL,
    m2_covs = c("Age", "Gender"),
    m3_covs = c("Age", "Gender", "CHARLSON"),
    time_var = "futime_years",
    event_var = "fustatus",
    rubin = NULL) {
  if (!exists("pv2_cox_extract", mode = "function")) {
    stop("pv2_cox_wide_m123_body: source run/prognosis_v2/pv2_mi_cox.R first")
  }
  if (!exists("quantile_scheme_level_display", mode = "function")) {
    stop("pv2_cox_wide_m123_body: source R/quantile_scheme_cascade.R first")
  }
  d <- as.data.frame(d)
  meta <- resolved$meta
  sch <- resolved$scheme
  if (is.null(rubin)) rubin <- !is.null(mids)
  indices <- as.character(indices)
  keep <- unique(c(
    indices,
    paste0(indices, "_Group"), paste0(indices, "_z"), paste0(indices, "_Q"),
    "qnum", m2_covs, m3_covs
  ))

  rhs_of <- function(expo, model) {
    if (identical(model, "Model1")) return(expo)
    if (identical(model, "Model2")) return(paste(c(expo, m2_covs), collapse = " + "))
    paste(c(expo, m3_covs), collapse = " + ")
  }
  get_cell <- function(expo, term_pat, model) {
    res <- tryCatch(
      pv2_cox_extract(
        d, rhs_of(expo, model), mids = mids,
        time_var = time_var, event_var = event_var,
        exposure_keep = keep, rubin = rubin
      ),
      error = function(e) NULL
    )
    if (is.null(res) || !nrow(res)) return(c(HR = "", P = ""))
    r <- res[grepl(term_pat, res$term), , drop = FALSE]
    if (!nrow(r)) return(c(HR = "", P = ""))
    c(HR = pv2_hr_cell(r$hr[1], r$lo[1], r$hi[1]), P = pv2_fmt_p(r$p[1]))
  }
  get_trend_p <- function(idx, model) {
    qv <- paste0(idx, "_Group")
    dd <- d
    dd$qnum <- as.integer(dd[[qv]])
    fit <- tryCatch(
      survival::coxph(
        stats::as.formula(paste(
          "Surv(", time_var, ", ", event_var, ") ~", rhs_of("qnum", model)
        )),
        data = dd
      ),
      error = function(e) NULL
    )
    if (is.null(fit)) return("")
    sm <- summary(fit)$coefficients
    if (!"qnum" %in% rownames(sm)) return("")
    pv2_fmt_p(sm["qnum", "Pr(>|z|)"])
  }

  rows <- list()
  for (idx in indices) {
    d[[paste0(idx, "_z")]] <- as.numeric(scale(d[[idx]]))
    qv <- paste0(idx, "_Group")
    zv <- paste0(idx, "_z")
    rows[[length(rows) + 1L]] <- c(
      Variable = idx, M1 = "", P1 = "", M2 = "", P2 = "", M3 = "", P3 = ""
    )
    a <- get_cell(zv, "_z", "Model1")
    b <- get_cell(zv, "_z", "Model2")
    c3 <- get_cell(zv, "_z", "Model3")
    rows[[length(rows) + 1L]] <- c(
      Variable = paste0("  ", idx, " (per 1 SD)"),
      M1 = a["HR"], P1 = a["P"], M2 = b["HR"], P2 = b["P"], M3 = c3["HR"], P3 = c3["P"]
    )
    rows[[length(rows) + 1L]] <- c(
      Variable = quantile_scheme_level_display(meta$ref, sch),
      M1 = "Reference", P1 = "", M2 = "Reference", P2 = "", M3 = "Reference", P3 = ""
    )
    for (lv in meta$labels[-1L]) {
      a <- get_cell(qv, lv, "Model1")
      b <- get_cell(qv, lv, "Model2")
      c3 <- get_cell(qv, lv, "Model3")
      rows[[length(rows) + 1L]] <- c(
        Variable = quantile_scheme_level_display(lv, sch),
        M1 = a["HR"], P1 = a["P"], M2 = b["HR"], P2 = b["P"], M3 = c3["HR"], P3 = c3["P"]
      )
    }
    rows[[length(rows) + 1L]] <- c(
      Variable = "  P for trend",
      M1 = "", P1 = get_trend_p(idx, "Model1"),
      M2 = "", P2 = get_trend_p(idx, "Model2"),
      M3 = "", P3 = get_trend_p(idx, "Model3")
    )
  }
  body <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE)
  names(body) <- c(
    "Variable",
    "Model 1 HR (95% CI)", "P1",
    "Model 2 HR (95% CI)", "P2",
    "Model 3 HR (95% CI)", "P3"
  )
  body
}

#' 写出 M1–M3 宽表并修正表头第二列为 P
pv2_write_cox_wide_xlsx <- function(path, title, body, footnotes = character(0)) {
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    stop("pv2_write_cox_wide_xlsx: source R/utils.R first")
  }
  sci_xlsx_single_header_booktabs(
    path, title = title, df_body = body, footnotes = footnotes,
    level_row_idx = which(startsWith(body$Variable, "  ")) + 1L
  )
  wb <- openxlsx::loadWorkbook(path)
  openxlsx::writeData(wb, 1, x = "Model 1 HR (95% CI)", startCol = 2L, startRow = 2L)
  openxlsx::writeData(wb, 1, x = "P", startCol = 3L, startRow = 2L)
  openxlsx::writeData(wb, 1, x = "Model 2 HR (95% CI)", startCol = 4L, startRow = 2L)
  openxlsx::writeData(wb, 1, x = "P", startCol = 5L, startRow = 2L)
  openxlsx::writeData(wb, 1, x = "Model 3 HR (95% CI)", startCol = 6L, startRow = 2L)
  openxlsx::writeData(wb, 1, x = "P", startCol = 7L, startRow = 2L)
  openxlsx::saveWorkbook(wb, path, overwrite = TRUE)
  invisible(path)
}

#' Table S6：插补前后（Variable | Statistic | Before | After | P）
pv2_s6_before_after_body <- function(
    before_df, after_df,
    sections,
    cont_spec,
    cat_spec,
    cat_lab = character(0)) {
  b <- as.data.frame(before_df)
  a <- as.data.frame(after_df)
  if ("ID" %in% names(b) && "ID" %in% names(a)) {
    b$ID <- as.character(b$ID)
    a$ID <- as.character(a$ID)
    a <- a[match(b$ID, a$ID), ]
  }
  is_normal_vec <- function(x) {
    x <- x[!is.na(x)]
    n <- length(x)
    if (n < 3L) return(FALSE)
    p <- tryCatch({
      if (n > 5000L) stats::ks.test(scale(x), "pnorm")$p.value else stats::shapiro.test(x)$p.value
    }, error = function(e) 0)
    is.finite(p) && p >= 0.05
  }
  same_num <- function(x, y) {
    isTRUE(all.equal(as.numeric(x), as.numeric(y), tolerance = 1e-8, check.attributes = FALSE))
  }
  rows <- list()
  level_rows <- integer(0)
  add <- function(v, stat, before_cell, after_cell, p) {
    rows[[length(rows) + 1L]] <<- data.frame(
      Variable = v, Statistic = stat,
      `Before imputation` = before_cell,
      `After imputation` = after_cell,
      `P value` = p,
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  for (sec in names(sections)) {
    add(sec, "", "", "", "")
    for (v in sections[[sec]]) {
      if (!v %in% names(b) || !v %in% names(a)) next
      xb <- b[[v]]
      xa <- a[[v]]
      if (v %in% names(cont_spec)) {
        normal <- is_normal_vec(xa)
        p <- if (same_num(xb, xa)) 1 else tryCatch(
          if (normal) stats::t.test(xa, xb)$p.value else stats::wilcox.test(xa, xb)$p.value,
          error = function(e) NA_real_
        )
        add(
          cont_spec[[v]],
          if (normal) "Mean \u00b1 SD" else "Median (Q1, Q3)",
          fmt_continuous(xb, normal), fmt_continuous(xa, normal), pv2_fmt_p(p)
        )
      } else {
        p <- if (identical(as.character(xb), as.character(xa))) 1 else tryCatch({
          tbl <- table(
            c(as.character(xb), as.character(xa)),
            c(rep("Before", length(xb)), rep("After", length(xa)))
          )
          if (any(tbl < 5)) stats::fisher.test(tbl, simulate.p.value = TRUE, B = 2000)$p.value
          else suppressWarnings(stats::chisq.test(tbl)$p.value)
        }, error = function(e) NA_real_)
        lab <- if (!is.null(cat_lab[[v]]) && nzchar(cat_lab[[v]])) cat_lab[[v]] else v
        add(lab, "n (%)", "", "", pv2_fmt_p(p))
        for (lv in cat_spec[[v]]) {
          level_rows <- c(level_rows, length(rows) + 1L)
          nb <- sum(as.character(xb) == lv, na.rm = TRUE)
          na_ <- sum(as.character(xa) == lv, na.rm = TRUE)
          add(
            paste0("  ", lv), "",
            sprintf("%s (%s%%)", pub_format_int(nb), fmt_num(100 * nb / nrow(b))),
            sprintf("%s (%s%%)", pub_format_int(na_), fmt_num(100 * na_ / nrow(a))),
            ""
          )
        }
      }
      level_rows <- c(level_rows, length(rows) + 1L)
      add(
        "  Missing (%)", "",
        paste0(fmt_num(100 * mean(is.na(xb))), "%"),
        paste0(fmt_num(100 * mean(is.na(xa))), "%"),
        ""
      )
    }
  }
  list(body = do.call(rbind, rows), level_rows = level_rows)
}

#' Table S7：暴露(per 1 SD) ~ 中介(1 SD)，Model1–3 与 Table 3 同构
#' Table S7：暴露→标准化中介的线性关联（与 Table S8 path a 同向）
#' Model3 beta 应对齐 S8 Path a（同一 complete#1 / 同一协变量）。
pv2_s7_exposure_mediator_body <- function(
    d, exposures, mediators,
    mediator_labels = NULL,
    m1_covs = character(0),
    m2_covs = c("Age", "Gender"),
    m3_covs = c("Age", "Gender", "CHARLSON")) {
  d <- as.data.frame(d)
  if (is.null(mediator_labels)) {
    mediator_labels <- stats::setNames(mediators, mediators)
  }
  for (m in mediators) d[[paste0(m, "_z")]] <- as.numeric(scale(d[[m]]))
  for (e in exposures) d[[paste0(e, "_z")]] <- as.numeric(scale(d[[e]]))
  if ("Gender" %in% names(d)) d$Gender <- factor(d$Gender)

  # 与中介 path a 同向：mediator_z ~ exposure_z + covs（禁止反写 index ~ OASIS）
  fit_lm_beta <- function(y, x, covs) {
    rhs <- if (!length(covs)) x else paste(c(x, covs), collapse = " + ")
    fit <- tryCatch(stats::lm(stats::as.formula(paste(y, "~", rhs)), data = d), error = function(e) NULL)
    if (is.null(fit)) return(NULL)
    sm <- summary(fit)$coefficients
    if (!x %in% rownames(sm)) return(NULL)
    b <- sm[x, 1]; se <- sm[x, 2]; p <- sm[x, 4]
    list(beta = b, lo = b - 1.96 * se, hi = b + 1.96 * se, p = p)
  }
  specs <- list(Model1 = m1_covs, Model2 = m2_covs, Model3 = m3_covs)
  rows <- list()
  for (e in exposures) {
    xz <- paste0(e, "_z")
    for (m in mediators) {
      y <- paste0(m, "_z")
      for (mod in names(specs)) {
        r <- fit_lm_beta(y, xz, specs[[mod]])
        if (is.null(r)) next
        rows[[length(rows) + 1L]] <- data.frame(
          Exposure = e,
          Mediator = unname(mediator_labels[[m]] %||% m),
          Model = mod,
          `Beta (95% CI)` = pv2_ci_cell(r$beta, r$lo, r$hi),
          P = pv2_fmt_p(r$p),
          check.names = FALSE, stringsAsFactors = FALSE
        )
      }
    }
  }
  do.call(rbind, rows)
}

#' Table S8：中介路径（调整集默认 = Table 3 Model 3）
pv2_s8_mediation_body <- function(
    d, exposures, mediators,
    mediator_labels = NULL,
    covs = c("Age", "Gender", "CHARLSON"),
    time_var = "futime_years",
    event_var = "fustatus",
    bootstrap_B = 400L,
    seed = 41904528L) {
  d <- as.data.frame(d)
  if (is.null(mediator_labels)) {
    mediator_labels <- stats::setNames(mediators, mediators)
  }
  for (m in mediators) d[[paste0(m, "_z")]] <- as.numeric(scale(d[[m]]))
  for (e in exposures) d[[paste0(e, "_z")]] <- as.numeric(scale(d[[e]]))
  if ("Gender" %in% names(d)) d$Gender <- factor(d$Gender)
  d$time <- suppressWarnings(as.numeric(d[[time_var]]))
  d$event <- as.integer(d[[event_var]])

  .med_once <- function(data, expo_z, med_z) {
    need <- c(expo_z, med_z, "time", "event", covs)
    d2 <- data[stats::complete.cases(data[, need]), , drop = FALSE]
    if (nrow(d2) < 40L || sum(d2$event) < 5L) return(NULL)
    ma <- stats::lm(stats::as.formula(paste(med_z, "~", paste(c(expo_z, covs), collapse = "+"))), d2)
    mf <- survival::coxph(
      stats::as.formula(paste("Surv(time, event) ~", paste(c(expo_z, med_z, covs), collapse = "+"))),
      data = d2
    )
    mt <- survival::coxph(
      stats::as.formula(paste("Surv(time, event) ~", paste(c(expo_z, covs), collapse = "+"))),
      data = d2
    )
    sa <- summary(ma)$coefficients
    sf <- summary(mf)$coefficients
    st <- summary(mt)$coefficients
    if (!all(c(expo_z, med_z) %in% rownames(sf)) || !expo_z %in% rownames(sa)) return(NULL)
    ca <- sa[expo_z, 1]; sea <- sa[expo_z, 2]; pa <- sa[expo_z, 4]
    cb <- sf[med_z, 1]; seb <- sf[med_z, 3]; pb <- sf[med_z, 5]
    cp <- sf[expo_z, 1]; sep <- sf[expo_z, 3]
    cc <- st[expo_z, 1]
    ab <- ca * cb
    prop <- if (is.finite(cc) && abs(cc) > 1e-12) 100 * ab / cc else NA_real_
    list(
      n = nrow(d2),
      a = ca, a_lo = ca - 1.96 * sea, a_hi = ca + 1.96 * sea, pa = pa,
      b = cb, b_lo = cb - 1.96 * seb, b_hi = cb + 1.96 * seb, pb = pb,
      de_hr = exp(cp), de_lo = exp(cp - 1.96 * sep), de_hi = exp(cp + 1.96 * sep),
      prop = prop
    )
  }
  boot_prop <- function(data, expo_z, med_z) {
    set.seed(seed)
    props <- rep(NA_real_, bootstrap_B)
    n <- nrow(data)
    for (i in seq_len(bootstrap_B)) {
      idx <- sample.int(n, n, replace = TRUE)
      r <- tryCatch(.med_once(data[idx, , drop = FALSE], expo_z, med_z), error = function(e) NULL)
      if (!is.null(r)) props[i] <- r$prop
    }
    qs <- stats::quantile(props, c(0.025, 0.975), na.rm = TRUE, names = FALSE)
    c(lo = qs[1], hi = qs[2])
  }

  rows <- list()
  for (e in exposures) {
    ez <- paste0(e, "_z")
    for (m in mediators) {
      mz <- paste0(m, "_z")
      r <- .med_once(d, ez, mz)
      if (is.null(r)) next
      bp <- boot_prop(d, ez, mz)
      rows[[length(rows) + 1L]] <- data.frame(
        Exposure = e,
        Mediator = unname(mediator_labels[[m]] %||% m),
        `Path a (95% CI)` = pv2_ci_cell(r$a, r$a_lo, r$a_hi),
        `Path a P` = pv2_fmt_p(r$pa),
        `Path b (95% CI)` = pv2_ci_cell(r$b, r$b_lo, r$b_hi),
        `Path b P` = pv2_fmt_p(r$pb),
        `Direct effect HR (95% CI)` = pv2_hr_cell(r$de_hr, r$de_lo, r$de_hi),
        `Proportion mediated, %` = if (is.finite(r$prop)) round(r$prop, 3) else NA_real_,
        `Proportion 95% CI, %` = if (all(is.finite(bp))) {
          sprintf("%.3f, %.3f", bp["lo"], bp["hi"])
        } else "",
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

#' 标准脚注：S7/S8 协变量与 Table 3 一致
pv2_table3_covariate_footnotes <- function(
    m2_covs = c("Age", "Gender"),
    m3_covs = c("Age", "Gender", "CHARLSON")) {
  c(
    "Covariate sets are identical to Table 3.",
    "The Model 1 was non-adjusted.",
    paste0("The Model 2 was adjusted by: ", paste(m2_covs, collapse = ", "), "."),
    paste0("The Model 3 was adjusted by: ", paste(m3_covs, collapse = ", "), ".")
  )
}
