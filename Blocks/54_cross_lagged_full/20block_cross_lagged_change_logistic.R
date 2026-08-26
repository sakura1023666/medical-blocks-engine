###############################################################################
#  cross_lagged_change_logistic — Mean FI / FI change 分位 × 随访结局
#
#  时间窗规则（写进流水线）：
#    - 仅 2 个调查年 → two_wave：T1/T2 pair 构造 Mean/Change，结局挂在 T2
#      （CHARLS 等两波库；暴露与结局窗可重叠，作折中设计）
#    - ≥3 个调查年 → three_plus（对齐原文）：固定前两期算 Mean/Change；
#      要求至第 2 期末仍无病；随访自第 3 期起；Cox 时间 = 结局/删失年 − 第 2 期年
#
#  分位与主文 logistic 闸门一致；Mean FI 与 FI change 同一分位数；Q1=参照
#  出版：单库三线表 + 四库并列 Table S5（可混用 two_wave / three_plus）
#  register_block: "cross_lagged_change_logistic"
###############################################################################

.cross_lagged_change_scheme_n <- function(scheme) {
  scheme <- tolower(as.character(scheme %||% "tertile")[1L])
  switch(
    scheme,
    binary = 2L, dichotomous = 2L, "2" = 2L,
    tertile = 3L, tertiles = 3L, "3" = 3L,
    quartile = 4L, quartiles = 4L, "4" = 4L,
    quintile = 5L, quintiles = 5L, "5" = 5L,
    3L
  )
}

.cross_lagged_change_resolve_scheme <- function(bl, ctx) {
  n_cfg <- bl$n_quantile %||% bl$change_n_quantile
  if (!is.null(n_cfg) && is.finite(as.numeric(n_cfg)[1L])) {
    nq <- as.integer(as.numeric(n_cfg)[1L])
    scheme <- switch(
      as.character(nq),
      "2" = "binary", "3" = "tertile", "4" = "quartile", "5" = "quintile",
      "tertile"
    )
    return(list(scheme = scheme, n = nq))
  }
  scheme <- as.character(
    bl$scheme %||% bl$grouping_scheme %||%
      ctx$results$logistic_grouping_scheme %||%
      ctx$results$logistic_natural_scheme %||%
      ctx$results$nhanes_logistic_selected_scheme %||%
      "tertile"
  )[1L]
  list(scheme = tolower(scheme), n = .cross_lagged_change_scheme_n(scheme))
}

.cross_lagged_change_cut_quantile <- function(x, n, prefix = "Q") {
  x <- as.numeric(x)
  ok <- is.finite(x)
  out <- rep(NA_character_, length(x))
  if (sum(ok) < n || n < 2L) {
    out[ok] <- paste0(prefix, "1")
    return(factor(out, levels = paste0(prefix, seq_len(max(1L, n)))))
  }
  qs <- stats::quantile(x[ok], probs = seq(0, 1, length.out = n + 1L), na.rm = TRUE, type = 7)
  qs <- unique(as.numeric(qs))
  if (length(qs) < 2L) {
    out[ok] <- paste0(prefix, "1")
    return(factor(out, levels = paste0(prefix, "1")))
  }
  labs <- paste0(prefix, seq_len(length(qs) - 1L))
  out[ok] <- as.character(cut(x[ok], breaks = qs, include.lowest = TRUE, labels = labs))
  factor(out, levels = labs)
}

#' 等频分位（对齐 dplyr::ntile / 痴呆 Step05 C01.1）；并列用 ties.method=first
.cross_lagged_change_cut_ntile <- function(x, n, prefix = "Q") {
  x <- as.numeric(x)
  n <- as.integer(n)[1L]
  labs <- paste0(prefix, seq_len(max(1L, n)))
  out <- rep(NA_character_, length(x))
  ok <- is.finite(x)
  if (!any(ok) || n < 2L) {
    out[ok] <- labs[[1L]]
    return(factor(out, levels = labs))
  }
  r <- rank(x[ok], ties.method = "first", na.last = "keep")
  n_ok <- length(r)
  idx <- as.integer(floor((as.numeric(r) - 1) / n_ok * n)) + 1L
  idx[idx < 1L] <- 1L
  idx[idx > n] <- n
  out[ok] <- paste0(prefix, idx)
  factor(out, levels = labs)
}

.cross_lagged_change_fmt_est <- function(est, lo, hi, digits = 2L) {
  sprintf(
    paste0("%.", digits, "f (%.", digits, "f, %.", digits, "f)"),
    as.numeric(est), as.numeric(lo), as.numeric(hi)
  )
}

.cross_lagged_change_fmt_p <- function(p) {
  p <- as.numeric(p)
  if (!is.finite(p)) return("")
  if (p < 0.001) return("<0.001")
  sprintf("%.3f", p)
}

.cross_lagged_change_extract <- function(fit) {
  sm <- summary(fit)
  if (inherits(fit, "coxph")) {
    cf <- as.data.frame(sm$coefficients)
    ci <- as.data.frame(sm$conf.int)
    rn <- setdiff(rownames(cf), "(Intercept)")
    do.call(rbind, lapply(rn, function(term) {
      data.frame(
        term = term, estimate = ci[term, 1], lo = ci[term, 3], hi = ci[term, 4],
        p = cf[term, ncol(cf)], metric = "HR", stringsAsFactors = FALSE
      )
    }))
  } else {
    cf <- as.data.frame(sm$coefficients)
    rn <- setdiff(rownames(cf), "(Intercept)")
    do.call(rbind, lapply(rn, function(term) {
      b <- cf[term, 1]; se <- cf[term, 2]; p <- cf[term, 4]
      data.frame(
        term = term, estimate = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
        p = p, metric = "OR", stringsAsFactors = FALSE
      )
    }))
  }
}

.cross_lagged_change_pub_rows <- function(fit_tab, group_var, n_levels, section_title) {
  rows <- list()
  rows[[length(rows) + 1L]] <- data.frame(
    Variables = section_title, est = "", p = "", stringsAsFactors = FALSE
  )
  rows[[length(rows) + 1L]] <- data.frame(
    Variables = "Q1 (Ref)", est = "1.00", p = "", stringsAsFactors = FALSE
  )
  for (i in seq_len(max(0L, n_levels - 1L))) {
    lab <- paste0("Q", i + 1L)
    est <- ""; pv <- ""
    if (!is.null(fit_tab) && nrow(fit_tab)) {
      hit <- grepl(group_var, fit_tab$term, fixed = TRUE) &
        grepl(paste0(lab, "$"), fit_tab$term)
      if (any(hit)) {
        r <- fit_tab[which(hit)[1L], , drop = FALSE]
        est <- .cross_lagged_change_fmt_est(r$estimate, r$lo, r$hi)
        pv <- .cross_lagged_change_fmt_p(r$p)
      }
    }
    rows[[length(rows) + 1L]] <- data.frame(
      Variables = lab, est = est, p = pv, stringsAsFactors = FALSE
    )
  }
  do.call(rbind, rows)
}

.cross_lagged_change_survey_years <- function(ctx, db) {
  bl_prep <- ctx$config$cross_lagged_long_prepare %||% list()
  panel <- NULL
  if (!is.null(bl_prep$panel) && !identical(db, "Pooled")) {
    panel <- bl_prep$panel[[db]]
  }
  if (!is.null(panel) && length(panel$years)) {
    ys <- sort(unique(as.integer(vapply(panel$years, function(z) as.integer(z$year), 1L))))
    if (length(ys)) return(ys)
  }
  long <- ctx$data$longitudinal
  if (!is.null(long) && is.data.frame(long) && "year" %in% names(long)) {
    if ("Cohort" %in% names(long) && !identical(db, "Pooled")) {
      long <- long[as.character(long$Cohort) == db, , drop = FALSE]
    }
    ys <- sort(unique(as.integer(stats::na.omit(long$year))))
    if (length(ys)) return(ys)
  }
  integer(0)
}

.cross_lagged_change_resolve_design <- function(n_years, bl = list()) {
  force <- tolower(as.character(bl$design %||% bl$change_design %||% "")[1L])
  if (force %in% c("two_wave", "two-wave", "2", "2wave")) return("two_wave")
  if (force %in% c("three_plus", "three-plus", "3", "3plus", "paper")) return("three_plus")
  if (isTRUE(as.integer(n_years) >= 3L)) "three_plus" else "two_wave"
}

.cross_lagged_change_build_three_plus <- function(long, cov_src = NULL, years = NULL) {
  if (is.null(long) || !is.data.frame(long) || !nrow(long))
    stop("three_plus: 需要 longitudinal 长表", call. = FALSE)
  need <- c("ID", "year", "FI")
  if (!all(need %in% names(long)))
    stop("three_plus: longitudinal 缺 ID/year/FI", call. = FALSE)
  long <- as.data.frame(long)
  long$ID <- as.character(long$ID)
  long$year <- as.integer(long$year)
  long$FI <- as.numeric(long$FI)
  if (!"Disease01" %in% names(long)) long$Disease01 <- NA_real_
  long$Disease01 <- as.numeric(long$Disease01)
  if (!"Cohort" %in% names(long)) long$Cohort <- "One"
  if (!"Country" %in% names(long)) long$Country <- NA_character_

  .one_cohort <- function(dsub, years_force = NULL) {
    ys <- years_force
    if (is.null(ys) || !length(ys)) {
      ys <- sort(unique(dsub$year[!is.na(dsub$FI)]))
    }
    ys <- sort(unique(as.integer(ys)))
    if (length(ys) < 3L) return(NULL)
    y1 <- ys[[1L]]; y2 <- ys[[2L]]; fu <- ys[seq(3L, length(ys))]
    fi1 <- dsub[dsub$year == y1 & !is.na(dsub$FI), c("ID", "FI"), drop = FALSE]
    fi2 <- dsub[dsub$year == y2 & !is.na(dsub$FI), c("ID", "FI"), drop = FALSE]
    names(fi1)[2] <- "FI1"; names(fi2)[2] <- "FI2"
    fi1 <- fi1[!duplicated(fi1$ID), , drop = FALSE]
    fi2 <- fi2[!duplicated(fi2$ID), , drop = FALSE]
    base <- merge(fi1, fi2, by = "ID", all = FALSE)
    if (!nrow(base)) return(NULL)

    pre <- dsub[dsub$ID %in% base$ID & dsub$year <= y2 & !is.na(dsub$Disease01), , drop = FALSE]
    sick_pre <- unique(pre$ID[pre$Disease01 == 1])
    base <- base[!base$ID %in% sick_pre, , drop = FALSE]
    if (!nrow(base)) return(NULL)

    fu_d <- dsub[dsub$ID %in% base$ID & dsub$year %in% fu, , drop = FALSE]
    rows <- lapply(base$ID, function(id) {
      sub <- fu_d[fu_d$ID == id, , drop = FALSE]
      if (!nrow(sub)) return(NULL)
      ev_rows <- sub[!is.na(sub$Disease01) & sub$Disease01 == 1, , drop = FALSE]
      if (nrow(ev_rows)) {
        ey <- min(ev_rows$year)
        event <- 1L
      } else {
        ey <- max(sub$year, na.rm = TRUE)
        event <- 0L
      }
      if (!is.finite(ey)) return(NULL)
      data.frame(
        ID = id, event_year = as.integer(ey), T2_outcome = event,
        T2_time = pmax(as.numeric(ey - y2), 0.01),
        stringsAsFactors = FALSE
      )
    })
    rows <- Filter(Negate(is.null), rows)
    if (!length(rows)) return(NULL)
    ev <- do.call(rbind, rows)
    out <- merge(base, ev, by = "ID", all = FALSE)
    out$mean_Index <- (out$FI1 + out$FI2) / 2
    out$Index_change <- out$FI2 - out$FI1
    out$T1_FI <- out$FI1
    out$T2_FI <- out$FI2
    out$change_y1 <- y1
    out$change_y2 <- y2
    out$change_fu_years <- paste(fu, collapse = ",")
    if (!is.null(cov_src) && is.data.frame(cov_src) && "ID" %in% names(cov_src)) {
      cs <- cov_src
      cs$ID <- as.character(cs$ID)
      if ("Cohort" %in% names(cs) && "Cohort" %in% names(dsub)) {
        co0 <- as.character(dsub$Cohort[[1]])
        cs <- cs[as.character(cs$Cohort) == co0 | is.na(cs$Cohort), , drop = FALSE]
      }
      # 勿合并 wide 里已有的暴露/结局列，否则 merge 产生 .x/.y 弄丢 mean_Index
      drop_cov <- c(
        "mean_Index", "Index_change", "FI_mean", "FI_change",
        "T1_FI", "T2_FI", "FI1", "FI2",
        "T2_time", "T2_outcome", "T2_Disease01", "T2_Disease_Group",
        "T2_Disease", "change_design", "change_y1", "change_y2", "change_fu_years",
        "event_year", "time", "wave"
      )
      keep <- setdiff(names(cs), c("ID", drop_cov))
      # 只要协变量样列（T1_* 人口学/行为 + Country/Cohort）
      prefer <- keep[grepl("^T1_", keep) | keep %in% c("Country", "Cohort", "Age", "Alcohol_drinking",
                                                       "Gender", "Education", "Smoking", "BMI")]
      if (length(prefer)) keep <- prefer
      if (length(keep)) {
        out <- merge(out, cs[, c("ID", keep), drop = FALSE], by = "ID", all.x = TRUE)
      }
    } else {
      y1row <- dsub[dsub$year == y1, , drop = FALSE]
      y1row <- y1row[!duplicated(y1row$ID), , drop = FALSE]
      demo <- intersect(
        c("Age", "Gender", "Education", "Alcohol_drinking", "Smoking", "BMI",
          "Marital_Status", "Hypertension", "Country"),
        names(y1row)
      )
      if (length(demo)) {
        add <- y1row[, c("ID", demo), drop = FALSE]
        names(add)[names(add) != "ID"] <- paste0("T1_", names(add)[names(add) != "ID"])
        out <- merge(out, add, by = "ID", all.x = TRUE)
      }
    }
    if ("Country" %in% names(dsub) && !"Country" %in% names(out)) {
      cc <- dsub[!duplicated(dsub$ID), c("ID", "Country"), drop = FALSE]
      out <- merge(out, cc, by = "ID", all.x = TRUE)
    }
    if ("Cohort" %in% names(dsub) && !"Cohort" %in% names(out)) {
      co <- dsub[!duplicated(dsub$ID), c("ID", "Cohort"), drop = FALSE]
      out <- merge(out, co, by = "ID", all.x = TRUE)
    }
    out$change_design <- "three_plus"
    out
  }

  cohorts <- unique(as.character(long$Cohort))
  parts <- list()
  for (co in cohorts) {
    dsub <- long[as.character(long$Cohort) == co, , drop = FALSE]
    ys_use <- if (length(cohorts) == 1L) years else NULL
    one <- .one_cohort(dsub, years_force = ys_use)
    if (!is.null(one) && nrow(one)) parts[[co]] <- one
  }
  if (!length(parts))
    stop("three_plus: 无可用个体（需 ≥3 年且前两期 FI 齐全、第2期末无病、有第3期+观察）", call. = FALSE)
  out <- do.call(rbind, parts)
  rownames(out) <- NULL
  out
}

.cross_lagged_change_build_two_wave <- function(wide, bl, event_lab) {
  if (is.null(wide) || !is.data.frame(wide))
    stop("two_wave: 需要 longitudinal_wide", call. = FALSE)
  t1 <- bl$fi_t1 %||% "T1_FI"
  t2 <- bl$fi_t2 %||% "T2_FI"
  y_col <- bl$outcome_t2 %||% "T2_Disease_Group"
  y01 <- bl$outcome01_t2 %||% "T2_Disease01"
  time_col <- bl$time_col %||% "T2_time"
  if (!all(c(t1, t2) %in% names(wide)))
    stop("two_wave: 缺 ", t1, "/", t2, call. = FALSE)
  d <- as.data.frame(wide)
  d$mean_Index <- if ("mean_Index" %in% names(d)) as.numeric(d$mean_Index) else
    rowMeans(cbind(as.numeric(d[[t1]]), as.numeric(d[[t2]])), na.rm = TRUE)
  d$Index_change <- if ("Index_change" %in% names(d)) as.numeric(d$Index_change) else
    as.numeric(d[[t2]]) - as.numeric(d[[t1]])
  if (y01 %in% names(d)) {
    d$T2_outcome <- as.integer(d[[y01]] == 1L)
  } else if (y_col %in% names(d)) {
    if (is.numeric(d[[y_col]]) || is.integer(d[[y_col]])) d$T2_outcome <- as.integer(d[[y_col]] == 1L)
    else d$T2_outcome <- as.integer(as.character(d[[y_col]]) == as.character(event_lab))
  } else stop("two_wave: 缺结局列", call. = FALSE)
  if (time_col %in% names(d) && any(is.finite(as.numeric(d[[time_col]])))) {
    d$T2_time <- pmax(as.numeric(d[[time_col]]), 0.01)
  }
  d$change_design <- "two_wave"
  d
}

block_cross_lagged_change_logistic <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$cross_lagged_change_logistic %||% list()
  event <- bl$outcome_event_level %||% cfg$project$analysis_group %||% "Hip_Fracture"
  db <- as.character(cfg$project$database %||% "DB")[1L]

  years <- .cross_lagged_change_survey_years(ctx, db)
  # 显式 design 优先（Table S5.1 强制 two_wave）
  force_design <- tolower(as.character(bl$design %||% bl$change_design %||% "")[1L])
  if (force_design %in% c("two_wave", "two-wave", "2", "2wave",
                          "three_plus", "three-plus", "3", "3plus", "paper")) {
    design <- .cross_lagged_change_resolve_design(length(years), bl)
  } else if (identical(db, "Pooled") && !is.null(ctx$data$longitudinal)) {
    long0 <- ctx$data$longitudinal
    if ("Cohort" %in% names(long0) && "year" %in% names(long0)) {
      n_by <- tapply(long0$year, long0$Cohort, function(z) length(unique(stats::na.omit(z))))
      design <- if (any(as.integer(n_by) >= 3L)) "three_plus" else "two_wave"
    } else {
      design <- .cross_lagged_change_resolve_design(length(years), bl)
    }
  } else {
    design <- .cross_lagged_change_resolve_design(length(years), bl)
  }

  if (identical(design, "three_plus")) {
    long <- ctx$data$longitudinal
    if (is.null(long) || !is.data.frame(long)) {
      cli::cli_alert_warning("{db}: three_plus 缺 longitudinal，回退 two_wave")
      design <- "two_wave"
      d <- .cross_lagged_change_build_two_wave(ctx$data$longitudinal_wide, bl, event)
    } else {
      d3 <- tryCatch(
        .cross_lagged_change_build_three_plus(long, cov_src = ctx$data$longitudinal_wide, years = years),
        error = function(e) {
          cli::cli_alert_warning(paste0(db, ": three_plus 失败 (", conditionMessage(e), ")，回退 two_wave"))
          NULL
        }
      )
      if (is.null(d3) || !nrow(d3)) {
        design <- "two_wave"
        d <- .cross_lagged_change_build_two_wave(ctx$data$longitudinal_wide, bl, event)
      } else if (identical(db, "Pooled") && "Cohort" %in% names(long)) {
        have <- unique(as.character(d3$Cohort))
        allc <- unique(as.character(long$Cohort))
        miss <- setdiff(allc, have)
        d <- d3
        if (length(miss) && !is.null(ctx$data$longitudinal_wide)) {
          w <- ctx$data$longitudinal_wide
          if ("Cohort" %in% names(w)) {
            for (mc in miss) {
              wsub <- w[as.character(w$Cohort) == mc, , drop = FALSE]
              if (!nrow(wsub)) next
              d2 <- tryCatch(.cross_lagged_change_build_two_wave(wsub, bl, event), error = function(e) NULL)
              if (!is.null(d2) && nrow(d2)) {
                d2$Cohort <- mc
                for (nm in setdiff(names(d), names(d2))) d2[[nm]] <- NA
                for (nm in setdiff(names(d2), names(d))) d[[nm]] <- NA
                d <- rbind(d[, names(d2), drop = FALSE], d2[, names(d2), drop = FALSE])
                cli::cli_alert_info("Pooled: {mc} 仅两波 → two_wave 并入")
              }
            }
          }
        }
        design <- "mixed"
      } else {
        d <- d3
      }
    }
  } else {
    d <- .cross_lagged_change_build_two_wave(ctx$data$longitudinal_wide, bl, event)
  }

  has_time <- "T2_time" %in% names(d) && any(is.finite(as.numeric(d$T2_time)))
  if (has_time) d$T2_time <- pmax(as.numeric(d$T2_time), 0.01)

  sch <- .cross_lagged_change_resolve_scheme(bl, ctx)
  nq <- sch$n
  scheme <- sch$scheme
  gmeth <- tolower(as.character(bl$grouping_method %||% bl$cut_method %||% "quantile")[1L])
  cut_fun <- if (gmeth %in% c("ntile", "dplyr_ntile", "equal_n")) {
    .cross_lagged_change_cut_ntile
  } else {
    .cross_lagged_change_cut_quantile
  }
  # 优先用 Step05 预计算三分位（C01.1 ntile），与主分析 Table S5 切点一致
  use_pre_q <- isTRUE(bl$use_precomputed_q3) || identical(gmeth, "precomputed_q3")
  if (use_pre_q && "mean_Index_q3" %in% names(d) &&
      any(!is.na(d$mean_Index_q3))) {
    d$Index_mean_q <- factor(as.character(d$mean_Index_q3), levels = c("Q1", "Q2", "Q3"))
  } else {
    d$Index_mean_q <- cut_fun(d$mean_Index, nq)
  }
  if (use_pre_q && "Index_change_q3" %in% names(d) &&
      any(!is.na(d$Index_change_q3))) {
    d$Index_change_q <- factor(as.character(d$Index_change_q3), levels = c("Q1", "Q2", "Q3"))
  } else {
    d$Index_change_q <- cut_fun(d$Index_change, nq)
  }

  .resolve_cov_names <- function(covars) {
    covars <- as.character(covars %||% character(0))
    covars <- covars[nzchar(covars)]
    prefer_t2 <- identical(tolower(as.character(bl$covariate_wave %||% "T1")[1L]), "t2")
    out <- character(0)
    for (cv in covars) {
      if (cv %in% names(d)) {
        out <- c(out, cv)
      } else if (prefer_t2 && paste0("T2_", cv) %in% names(d)) {
        out <- c(out, paste0("T2_", cv))
      } else if (paste0("T1_", cv) %in% names(d)) {
        out <- c(out, paste0("T1_", cv))
      } else if (paste0("T2_", cv) %in% names(d)) {
        out <- c(out, paste0("T2_", cv))
      }
    }
    unique(out)
  }

  # Mean / Change 可分开调协变量（痴呆主分析 C02.3：Mean=Age+Alcohol；Change=不调整）
  covars_mean <- bl$mean_covariates %||% bl$covariates %||%
    ctx$results$Model2Factors %||% character(0)
  covars_chg <- if (!is.null(bl$change_covariates)) {
    bl$change_covariates
  } else {
    covars_mean
  }
  cov_use_m <- .resolve_cov_names(covars_mean)
  cov_use_c <- .resolve_cov_names(covars_chg)
  if (identical(db, "Pooled") || ("Country" %in% names(d) &&
      length(unique(stats::na.omit(as.character(d$Country)))) > 1L)) {
    if ("Country" %in% names(d)) {
      if (length(covars_mean) && !"Country" %in% cov_use_m)
        cov_use_m <- unique(c(cov_use_m, "Country"))
      if (length(as.character(covars_chg %||% character(0))) && !"Country" %in% cov_use_c &&
          !is.null(bl$change_covariates) && length(bl$change_covariates))
        cov_use_c <- unique(c(cov_use_c, "Country"))
      # Change 明确不调整时不加 Country；Pooled 主分析 change 仍带 Country
      if (identical(db, "Pooled") && is.null(bl$change_covariates) &&
          !"Country" %in% cov_use_c && length(cov_use_m))
        cov_use_c <- unique(c(cov_use_c, "Country"))
      if (identical(db, "Pooled") && !is.null(bl$change_covariates) &&
          length(bl$change_covariates) == 0L) {
        # explicit empty: keep empty (non-pooled); for Pooled main used Country only on change
        cov_use_c <- if ("Country" %in% names(d)) "Country" else character(0)
      }
    }
  }
  # 简化：显式 change_covariates=character(0) 表示完全不调整（含 Pooled 也不强行加）
  if (!is.null(bl$change_covariates) && length(bl$change_covariates) == 0L) {
    cov_use_c <- character(0)
  }
  cov_use <- unique(c(cov_use_m, cov_use_c)) # meta 汇总用

  .fit_one <- function(rhs_terms) {
    rhs_terms <- rhs_terms[nzchar(as.character(rhs_terms))]
    rhs <- paste(rhs_terms, collapse = " + ")
    if (!nzchar(rhs)) return(NULL)
    if (has_time && requireNamespace("survival", quietly = TRUE)) {
      tryCatch(
        survival::coxph(stats::as.formula(paste0("survival::Surv(T2_time, T2_outcome) ~ ", rhs)), data = d),
        error = function(e) NULL
      )
    } else {
      tryCatch(
        stats::glm(stats::as.formula(paste0("T2_outcome ~ ", rhs)), data = d, family = binomial()),
        error = function(e) NULL
      )
    }
  }

  rows <- list()
  fit_m <- .fit_one(c("Index_mean_q", cov_use_m))
  tab_m <- if (!is.null(fit_m)) .cross_lagged_change_extract(fit_m) else NULL
  if (!is.null(tab_m) && nrow(tab_m)) {
    tab_m <- tab_m[grepl("Index_mean_q", tab_m$term), , drop = FALSE]
    if (nrow(tab_m)) rows[[length(rows) + 1L]] <- cbind(analysis = "Mean_FI", tab_m)
  }

  fit_c <- .fit_one(c("Index_change_q", cov_use_c))
  tab_c <- if (!is.null(fit_c)) .cross_lagged_change_extract(fit_c) else NULL
  if (!is.null(tab_c) && nrow(tab_c)) {
    tab_c <- tab_c[grepl("Index_change_q", tab_c$term), , drop = FALSE]
    if (nrow(tab_c)) rows[[length(rows) + 1L]] <- cbind(analysis = "FI_change", tab_c)
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame()
  metric <- if (has_time) "HR" else "OR"
  metric_lab <- metric

  pub <- rbind(
    .cross_lagged_change_pub_rows(tab_m, "Index_mean_q", nq, "Mean FI"),
    .cross_lagged_change_pub_rows(tab_c, "Index_change_q", nq, "FI change")
  )
  names(pub) <- c("Variables", paste0(metric_lab, " (95% CI)"), "P-value")

  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  # output_suffix：""=主结果(Table S5)；"_twowave"=全库两年敏感性(Table S5.1)
  suf <- as.character(bl$output_suffix %||% "")[1L]
  if (is.na(suf)) suf <- ""
  stem <- paste0("Table_Change_FI_mean_and_change", suf)
  csv_path <- file.path(out_dir, paste0(stem, ".csv"))
  utils::write.csv(tab, csv_path, row.names = FALSE)
  xlsx_path <- file.path(out_dir, paste0(stem, ".xlsx"))
  pub_path <- file.path(out_dir, paste0(stem, "_pub.xlsx"))
  rds_path <- file.path(out_dir, paste0(stem, "_pub.rds"))
  meta_path <- file.path(out_dir, paste0("Table_Change_FI_meta", suf, ".csv"))

  if (requireNamespace("openxlsx", quietly = TRUE) && nrow(tab))
    openxlsx::write.xlsx(tab, xlsx_path)

  design_lab <- switch(
    design,
    three_plus = "three_plus (exposure=wave1+2, FU from wave3+)",
    two_wave = "two_wave (pair T1/T2; overlapping windows)",
    mixed = "mixed (per-cohort two_wave/three_plus)",
    design
  )
  yr_txt <- if (length(years)) paste(years, collapse = "/") else "panel"
  adj_note <- {
    mlab <- if (length(cov_use_m)) {
      paste(gsub("^T[12]_", "", cov_use_m), collapse = " and ")
    } else "none"
    clab <- if (length(cov_use_c)) {
      paste(gsub("^T[12]_", "", cov_use_c), collapse = " and ")
    } else "none"
    if (identical(mlab, clab)) mlab else paste0("Mean: ", mlab, "; Change: ", clab)
  }
  note <- sprintf(
    "Note: Q1 is the reference group. Design=%s; survey years=%s. Grouping=%s (%d levels%s). Adjusted for %s.",
    design_lab, yr_txt, scheme, nq,
    if (use_pre_q) "; precomputed q3" else if (gmeth %in% c("ntile", "dplyr_ntile", "equal_n")) "; ntile" else "",
    adj_note
  )
  if (exists(".sci_xlsx_write_three_line_workbook", mode = "function") && nrow(pub)) {
    body2 <- pub
    for (j in seq_len(ncol(body2))) body2[[j]] <- as.character(body2[[j]])
    hdr <- setNames(
      as.data.frame(as.list(names(pub)), stringsAsFactors = FALSE),
      names(pub)
    )
    tbl_df_new <- rbind(hdr, body2)
    q_labs <- c("Q1 (Ref)", paste0("Q", seq_len(nq)[-1L]))
    level_idx <- which(tbl_df_new[[1L]] %in% q_labs)
    .sci_xlsx_write_three_line_workbook(
      pub_path,
      title = sprintf("Table. Change analysis Mean FI and FI change (%s)", db),
      tbl_df_new = tbl_df_new,
      sheet = "Table",
      footnotes = note,
      insert_map = c("Mean FI" = 1L, "FI change" = 1L),
      level_row_idx = level_idx
    )
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(pub, pub_path)
  }

  meta <- data.frame(
    database = db,
    change_design = design,
    survey_years = yr_txt,
    scheme = scheme,
    n_quantile = nq,
    n = nrow(d),
    n_event = sum(d$T2_outcome == 1, na.rm = TRUE),
    model = if (has_time) "cox" else "logistic",
    metric = metric,
    covariates = paste(cov_use, collapse = ", "),
    mean_covariates = paste(cov_use_m, collapse = ", "),
    change_covariates = if (length(cov_use_c)) paste(cov_use_c, collapse = ", ") else "(none)",
    stringsAsFactors = FALSE
  )
  utils::write.csv(meta, meta_path, row.names = FALSE)
  saveRDS(
    list(
      db = db, scheme = scheme, n_quantile = nq, metric = metric,
      change_design = design, survey_years = years,
      pub = pub, tab = tab, meta = meta,
      note_covars = cov_use, note_covars_mean = cov_use_m, note_covars_change = cov_use_c,
      output_suffix = suf
    ),
    rds_path
  )

  ctx$results$cross_lagged_change_logistic <- list(
    table = tab, pub = pub, path = csv_path, pub_path = pub_path, rds_path = rds_path,
    meta = meta, covariates = cov_use, scheme = scheme, n_quantile = nq,
    change_design = design, output_suffix = suf
  )
  ctx$results$logistic_grouping_scheme <- scheme
  cli::cli_alert_success(
    "Change 分析完成 [{db}]: design={design}{if (nzchar(suf)) paste0(' suffix=', suf) else ''}; {if (has_time) 'Cox' else 'logistic'} {metric}; scheme={scheme} (n={nq}); N={nrow(d)}; events={sum(d$T2_outcome==1, na.rm=TRUE)}"
  )
  ctx
}


#' 四库并列 Table S5：Mean FI / FI change（与参考表格式一致）
#' @param rds_paths 命名或无名路径向量 → phase3_long_*/Tables/..._pub.rds
#' @param outfile 输出 xlsx
#' @param cohorts 列顺序（默认含 Pooled；缺 rds 的库自动跳过）
#' @param include_n_events 是否在表体首两行写 N / Events
cross_lagged_change_build_table_s5 <- function(
    rds_paths,
    outfile,
    cohorts = c("CHARLS", "ELSA", "HRS", "Pooled"),
    title = "Table S5. Change analysis Mean FI and FI change",
    sheet = NULL,
    include_n_events = TRUE
) {
  if (is.null(sheet) || !nzchar(as.character(sheet)[1L])) {
    sheet <- if (grepl("S5\\.1", title, fixed = FALSE)) "Table S5.1" else "Table S5"
  }
  sheet <- as.character(sheet)[1L]
  objs <- list()
  for (p in rds_paths) {
    if (!file.exists(p)) next
    o <- readRDS(p)
    db <- as.character(o$db %||% NA_character_)[1L]
    if (!nzchar(db) || is.na(db)) next
    objs[[db]] <- o
  }
  cohorts <- cohorts[cohorts %in% names(objs)]
  if (!length(cohorts)) stop("cross_lagged_change_build_table_s5: 无可用库结果", call. = FALSE)

  # 以第一库行结构为骨架（不可用 match(Variables)：Q1/Q2/Q3 标签重复）
  skeleton <- objs[[cohorts[[1]]]]$pub
  vars_body <- as.character(skeleton$Variables)
  n_body <- length(vars_body)
  metric <- as.character(objs[[cohorts[[1]]]]$metric %||% "HR")[1L]
  scheme <- as.character(objs[[cohorts[[1]]]]$scheme %||% "tertile")[1L]
  nq <- as.integer(objs[[cohorts[[1]]]]$n_quantile %||% 3L)[1L]
  model0 <- as.character(objs[[cohorts[[1]]]]$meta$model %||% if (identical(metric, "HR")) "cox" else "logistic")[1L]

  est_col <- paste0(metric, " (95% CI)")
  pick_est <- function(pub) {
    nm <- names(pub)
    hit <- nm[grepl("95% CI", nm)]
    if (length(hit)) as.character(pub[[hit[1L]]]) else as.character(pub[[2L]])
  }
  pick_p <- function(pub) {
    nm <- names(pub)
    hit <- nm[grepl("^P", nm, ignore.case = TRUE)]
    if (length(hit)) as.character(pub[[hit[1L]]]) else as.character(pub[[3L]])
  }
  .meta_n <- function(o) {
    n <- suppressWarnings(as.integer(o$meta$n %||% NA_integer_)[1L])
    if (!is.finite(n)) n <- NA_integer_
    n
  }
  .meta_ev <- function(o) {
    e <- suppressWarnings(as.integer(o$meta$n_event %||% NA_integer_)[1L])
    if (!is.finite(e)) e <- NA_integer_
    e
  }

  n_pre <- if (isTRUE(include_n_events)) 2L else 0L
  vars <- if (n_pre) c("N", "Events", vars_body) else vars_body
  n_row <- length(vars)

  body <- data.frame(Variables = vars, stringsAsFactors = FALSE)
  h1 <- c("Variables")
  h2 <- c("")
  for (db in cohorts) {
    pub <- objs[[db]]$pub
    if (nrow(pub) != n_body || !identical(as.character(pub$Variables), vars_body)) {
      if (exists("cli_alert_warning", mode = "function") ||
          requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning(
          "Table S5: {db} 行结构与骨架不一致（期望 {n_body} 行），按行序截断/填充"
        )
      }
    }
    est <- pick_est(pub)
    pv <- pick_p(pub)
    if (length(est) < n_body) est <- c(est, rep("", n_body - length(est)))
    if (length(pv) < n_body) pv <- c(pv, rep("", n_body - length(pv)))
    est <- est[seq_len(n_body)]
    pv <- pv[seq_len(n_body)]
    is_sec <- vars_body %in% c(
      "Mean FI", "FI change", "Mean Leisure Activities", "Leisure Activities Change"
    )
    est[is_sec] <- ""
    pv[is_sec] <- ""
    n_txt <- {
      nn <- .meta_n(objs[[db]])
      if (is.finite(nn)) format(nn, big.mark = ",", scientific = FALSE) else ""
    }
    e_txt <- {
      ee <- .meta_ev(objs[[db]])
      if (is.finite(ee)) format(ee, big.mark = ",", scientific = FALSE) else ""
    }
    if (n_pre) {
      est <- c(n_txt, e_txt, est)
      pv <- c("", "", pv)
    }
    body[[paste0(db, "_est")]] <- est
    body[[paste0(db, "_p")]] <- pv
    h1 <- c(h1, db, "")
    h2 <- c(h2, est_col, "P-value")
  }
  colnames(body) <- paste0("c", seq_len(ncol(body)))

  cov_note <- unique(unlist(lapply(objs[cohorts], function(o) o$note_covars %||% character(0))))
  cov_note <- gsub("^T1_", "", cov_note)
  cov_note <- setdiff(cov_note, "Country")
  designs <- vapply(cohorts, function(db) {
    as.character(objs[[db]]$change_design %||% objs[[db]]$meta$change_design %||% "?")[1L]
  }, character(1))
  design_txt <- paste(sprintf("%s=%s", cohorts, designs), collapse = "; ")
  n_ev_txt <- paste(vapply(cohorts, function(db) {
    sprintf(
      "%s N=%s, Events=%s",
      db,
      {
        nn <- .meta_n(objs[[db]])
        if (is.finite(nn)) format(nn, big.mark = ",", scientific = FALSE) else "—"
      },
      {
        ee <- .meta_ev(objs[[db]])
        if (is.finite(ee)) format(ee, big.mark = ",", scientific = FALSE) else "—"
      }
    )
  }, character(1)), collapse = "; ")
  yr_txt <- paste(vapply(cohorts, function(db) {
    ys <- objs[[db]]$survey_years %||% objs[[db]]$meta$survey_years %||% NA
    if (is.numeric(ys) || is.integer(ys)) ys <- paste(ys, collapse = "/")
    sprintf("%s: %s", db, as.character(ys)[1L])
  }, character(1)), collapse = "; ")

  notes <- c(
    sprintf(
      paste0(
        "Note: Q1 is the reference group. Estimates are %s from %s models. ",
        "Design by cohort: %s. ",
        "Rule: 2 survey years → two_wave (T1/T2 pair); ≥3 years → three_plus ",
        "(Mean/Change from wave1–2, follow-up from wave3+)."
      ),
      metric,
      if (identical(model0, "cox")) "Cox" else "logistic",
      design_txt
    ),
    sprintf(
      "Sample for change analysis: %s.",
      n_ev_txt
    ),
    sprintf(
      "Survey years (panel): %s. Grouping=%s (%d levels), aligned with main logistic gate. Adjusted for %s%s.",
      yr_txt, scheme, nq,
      if (length(cov_note)) paste(cov_note, collapse = " and ") else "locked covariates",
      if ("Pooled" %in% cohorts) " (Pooled additionally adjusted for Country)" else ""
    )
  )

  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  if (exists(".sci_xlsx_double_header_booktabs", mode = "function")) {
    .sci_xlsx_double_header_booktabs(
      filepath = outfile,
      title = title,
      df_body = body,
      h1 = h1,
      h2 = h2,
      sheet = sheet,
      footnotes = notes
    )
    # 加粗 N / Events / Mean FI / FI change
    if (requireNamespace("openxlsx", quietly = TRUE)) {
      wb <- openxlsx::loadWorkbook(outfile)
      sh <- openxlsx::getSheetNames(outfile)[1L]
      has_title <- nzchar(title %||% "")
      r0 <- if (has_title) 4L else 3L  # title + h1 + h2 → body starts
      bold <- openxlsx::createStyle(
        fontSize = 12, fontName = "Times New Roman", halign = "left",
        textDecoration = "bold"
      )
      for (i in seq_along(vars)) {
        if (vars[[i]] %in% c("N", "Events", "Mean FI", "FI change")) {
          openxlsx::addStyle(
            wb, sheet = sh, style = bold,
            rows = r0 + i - 1L, cols = 1L, gridExpand = FALSE, stack = TRUE
          )
        }
      }
      openxlsx::saveWorkbook(wb, outfile, overwrite = TRUE)
    }
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    # fallback: 表体 + 表注写到同表下方
    flat <- body
    names(flat) <- ifelse(nzchar(h2), paste(h1, h2), h1)
    openxlsx::write.xlsx(flat, outfile)
    if (requireNamespace("openxlsx", quietly = TRUE) && length(notes)) {
      wb <- openxlsx::loadWorkbook(outfile)
      sh <- openxlsx::getSheetNames(outfile)[1L]
      r0 <- nrow(flat) + 3L
      for (i in seq_along(notes)) {
        openxlsx::writeData(wb, sh, notes[[i]], startRow = r0 + i - 1L, startCol = 1L)
      }
      openxlsx::saveWorkbook(wb, outfile, overwrite = TRUE)
    }
  } else {
    utils::write.csv(body, sub("\\.xlsx$", ".csv", outfile), row.names = FALSE)
  }
  invisible(list(
    path = outfile, cohorts = cohorts, scheme = scheme,
    n_quantile = nq, metric = metric, n_events = n_ev_txt
  ))
}

register_block("cross_lagged_change_logistic", block_cross_lagged_change_logistic,
               "Mean FI / FI change 分位（跟闸门；Cox优先）")
