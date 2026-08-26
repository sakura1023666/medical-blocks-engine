###############################################################################
#  moderated_mediation_process.R — Yan2026 风格中介 / 调节 / 有调节中介共用函数
#  仅供 Blocks/20_mediation/07–12 调用；不改既有 mediation_* 行为。
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

modmed_ensure_pkgs <- function(pkgs = c("mediation", "ggplot2", "corrplot")) {
  if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
    options(repos = c(CRAN = "https://cloud.r-project.org"))
  }
  for (p in pkgs) {
    if (!requireNamespace(p, quietly = TRUE)) {
      install.packages(p, quiet = TRUE)
    }
  }
  invisible(TRUE)
}

#' 校验行序后把 wqs_fit$data$wqs 写入 merged$WQS
modmed_merge_wqs <- function(merged, wqs_fit, wqs_col = "WQS") {
  if (is.null(wqs_fit) || !is.list(wqs_fit) || is.null(wqs_fit$data)) {
    stop("modmed_merge_wqs: wqs_fit$data 缺失", call. = FALSE)
  }
  wd <- wqs_fit$data
  if (!is.data.frame(wd) || !"wqs" %in% names(wd)) {
    stop("modmed_merge_wqs: wqs_fit$data 无 wqs 列", call. = FALSE)
  }
  if (nrow(wd) != nrow(merged)) {
    stop(
      sprintf("modmed_merge_wqs: 行数不一致 merged=%d wqs$data=%d", nrow(merged), nrow(wd)),
      call. = FALSE
    )
  }
  key_m <- paste(
    merged$Age, merged$BMI, as.character(merged$Group),
    merged$White_blood_cells, merged$URXOTD,
    sep = "|"
  )
  key_d <- paste(
    wd$Age, wd$BMI, as.character(wd$Group),
    wd$White_blood_cells, wd$URXOTD,
    sep = "|"
  )
  if (!isTRUE(all(key_m == key_d))) {
    stop("modmed_merge_wqs: 行序键不一致，拒绝盲合并 WQS", call. = FALSE)
  }
  merged[[wqs_col]] <- as.numeric(wd$wqs)
  merged
}

modmed_encode_outcome <- function(x, case_label = "Osteoarthritis", ref_label = "Normal") {
  if (is.numeric(x) && all(stats::na.omit(unique(x)) %in% c(0, 1))) {
    return(as.integer(x))
  }
  xc <- trimws(as.character(x))
  out <- ifelse(xc == case_label, 1L, ifelse(xc == ref_label, 0L, NA_integer_))
  out
}

modmed_encode_gender_num <- function(x, male_label = "Male") {
  if (is.numeric(x) && all(stats::na.omit(unique(x)) %in% c(0, 1))) {
    return(as.numeric(x))
  }
  xc <- trimws(as.character(x))
  ifelse(xc == male_label, 1, 0)
}

#' 单次 X→M→Y 中介（logit Y, lm M）；boot + BCa CI
modmed_run_mediate <- function(data, exposure, mediator, outcome,
                               sims = 1000L, seed = 1234L,
                               covariates = character(0)) {
  need <- unique(c(exposure, mediator, outcome, covariates))
  if (!all(need %in% names(data))) return(NULL)
  d <- data[, need, drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 30L) return(NULL)
  if (length(unique(d[[outcome]])) < 2L) return(NULL)
  if (length(unique(d[[mediator]])) < 2L) return(NULL)
  if (length(unique(d[[exposure]])) < 2L) return(NULL)

  cov_use <- setdiff(covariates, c(exposure, mediator, outcome))
  rhs_cov <- if (length(cov_use)) paste0(" + ", paste(cov_use, collapse = " + ")) else ""
  fml_m <- stats::as.formula(paste0(mediator, " ~ ", exposure, rhs_cov))
  fml_y <- stats::as.formula(paste0(outcome, " ~ ", exposure, " + ", mediator, rhs_cov))

  model_m <- tryCatch(stats::lm(fml_m, data = d), error = function(e) NULL)
  model_y <- tryCatch(
    stats::glm(fml_y, data = d, family = stats::binomial()),
    error = function(e) NULL
  )
  if (is.null(model_m) || is.null(model_y)) return(NULL)

  set.seed(as.integer(seed))
  med_fit <- tryCatch(
    mediation::mediate(
      model.m = model_m, model.y = model_y,
      treat = exposure, mediator = mediator,
      sims = as.integer(sims), boot = TRUE, boot.ci.type = "bca"
    ),
    error = function(e) {
      tryCatch(
        mediation::mediate(
          model.m = model_m, model.y = model_y,
          treat = exposure, mediator = mediator,
          sims = as.integer(sims), boot = TRUE, boot.ci.type = "perc"
        ),
        error = function(e2) {
          tryCatch(
            mediation::mediate(
              model.m = model_m, model.y = model_y,
              treat = exposure, mediator = mediator,
              sims = as.integer(sims), boot = FALSE
            ),
            error = function(e3) NULL
          )
        }
      )
    }
  )
  if (is.null(med_fit)) return(NULL)

  sm <- summary(med_fit)
  .coef <- function(base) {
    nm <- paste0(base, ".coef")
    if (!is.null(sm[[nm]]) && length(sm[[nm]])) return(as.numeric(sm[[nm]][1L]))
    as.numeric(sm[[base]][1L])
  }
  .ci <- function(base) {
    nm <- paste0(base, ".ci")
    v <- sm[[nm]]
    if (is.null(v) || length(v) < 2L) return(c(NA_real_, NA_real_))
    as.numeric(v[1:2])
  }
  .p <- function(base) {
    nm <- paste0(base, ".p")
    if (!is.null(sm[[nm]]) && length(sm[[nm]])) return(as.numeric(sm[[nm]][1L]))
    NA_real_
  }

  acme <- .coef("d.avg"); if (!is.finite(acme)) acme <- .coef("d0")
  acme_ci <- .ci("d.avg"); if (anyNA(acme_ci)) acme_ci <- .ci("d0")
  acme_p <- .p("d.avg"); if (!is.finite(acme_p)) acme_p <- .p("d0")

  ade <- .coef("z.avg"); if (!is.finite(ade)) ade <- .coef("z0")
  ade_ci <- .ci("z.avg"); if (anyNA(ade_ci)) ade_ci <- .ci("z0")
  ade_p <- .p("z.avg"); if (!is.finite(ade_p)) ade_p <- .p("z0")

  tot <- .coef("tau.coef"); if (!is.finite(tot)) tot <- .coef("tau")
  tot_ci <- .ci("tau")
  tot_p <- .p("tau")

  prop <- .coef("n.avg"); if (!is.finite(prop)) prop <- .coef("n0")
  prop_ci <- .ci("n.avg"); if (anyNA(prop_ci)) prop_ci <- .ci("n0")

  data.frame(
    exposure = exposure,
    mediator = mediator,
    outcome = outcome,
    n = nrow(d),
    ACME = acme, ACME_lo = acme_ci[1], ACME_hi = acme_ci[2], ACME_p = acme_p,
    ADE = ade, ADE_lo = ade_ci[1], ADE_hi = ade_ci[2], ADE_p = ade_p,
    total = tot, total_lo = tot_ci[1], total_hi = tot_ci[2], total_p = tot_p,
    prop_mediated = prop, prop_lo = prop_ci[1], prop_hi = prop_ci[2],
    significant = is.finite(acme_ci[1]) && is.finite(acme_ci[2]) &&
      (acme_ci[1] > 0 || acme_ci[2] < 0),
    stringsAsFactors = FALSE
  )
}

#' 路径 a/b/c' 上 X×W 或 M×W 交互
modmed_moderation_tests <- function(data, exposure, mediator, outcome, moderator,
                                    continuous_moderators = c("Age", "BMI")) {
  need <- c(exposure, mediator, outcome, moderator)
  if (!all(need %in% names(data))) return(NULL)
  d <- data[, need, drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 30L) return(NULL)

  w_is_cont <- moderator %in% continuous_moderators || is.numeric(d[[moderator]])
  if (w_is_cont) {
    d[[paste0(moderator, "_c")]] <- as.numeric(scale(d[[moderator]], scale = FALSE))
    w_term <- paste0(moderator, "_c")
  } else {
    d[[moderator]] <- factor(d[[moderator]])
    w_term <- moderator
  }

  .extract_int <- function(fit, pattern_hint) {
    if (is.null(fit)) return(list(beta = NA_real_, se = NA_real_, p = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_))
    sm <- summary(fit)$coefficients
    rn <- rownames(sm)
    hit <- rn[grepl(":", rn, fixed = TRUE)]
    if (!length(hit)) {
      return(list(beta = NA_real_, se = NA_real_, p = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_))
    }
    # 取第一个交互项（二元交互模型仅一项或 Gender 哑变量一项）
    use <- hit[1L]
    beta <- as.numeric(sm[use, 1])
    se <- as.numeric(sm[use, 2])
    p <- as.numeric(sm[use, ncol(sm)])
    ci <- tryCatch({
      cf <- stats::confint(fit)
      if (use %in% rownames(cf)) as.numeric(cf[use, 1:2]) else c(beta - 1.96 * se, beta + 1.96 * se)
    }, error = function(e) c(beta - 1.96 * se, beta + 1.96 * se))
    list(beta = beta, se = se, p = p, ci_lo = ci[1], ci_hi = ci[2], term = use)
  }

  # a: M ~ X * W
  f_a <- stats::as.formula(paste0(mediator, " ~ ", exposure, " * ", w_term))
  fit_a <- tryCatch(stats::lm(f_a, data = d), error = function(e) NULL)
  ra <- .extract_int(fit_a)

  # b: Y ~ X + M * W
  f_b <- stats::as.formula(paste0(outcome, " ~ ", exposure, " + ", mediator, " * ", w_term))
  fit_b <- tryCatch(stats::glm(f_b, data = d, family = stats::binomial()), error = function(e) NULL)
  rb <- .extract_int(fit_b)

  # c': Y ~ M + X * W
  f_c <- stats::as.formula(paste0(outcome, " ~ ", mediator, " + ", exposure, " * ", w_term))
  fit_c <- tryCatch(stats::glm(f_c, data = d, family = stats::binomial()), error = function(e) NULL)
  rc <- .extract_int(fit_c)

  rbind(
    data.frame(
      exposure = exposure, mediator = mediator, outcome = outcome, moderator = moderator,
      path = "a", beta = ra$beta, se = ra$se, p = ra$p, ci_lo = ra$ci_lo, ci_hi = ra$ci_hi,
      significant = is.finite(ra$p) && ra$p < 0.05, n = nrow(d),
      stringsAsFactors = FALSE
    ),
    data.frame(
      exposure = exposure, mediator = mediator, outcome = outcome, moderator = moderator,
      path = "b", beta = rb$beta, se = rb$se, p = rb$p, ci_lo = rb$ci_lo, ci_hi = rb$ci_hi,
      significant = is.finite(rb$p) && rb$p < 0.05, n = nrow(d),
      stringsAsFactors = FALSE
    ),
    data.frame(
      exposure = exposure, mediator = mediator, outcome = outcome, moderator = moderator,
      path = "c_prime", beta = rc$beta, se = rc$se, p = rc$p, ci_lo = rc$ci_lo, ci_hi = rc$ci_hi,
      significant = is.finite(rc$p) && rc$p < 0.05, n = nrow(d),
      stringsAsFactors = FALSE
    )
  )
}

#' 有调节中介：在给定 W 水平上估计间接效应 a*b（bootstrap）
modmed_conditional_indirect <- function(data, exposure, mediator, outcome, moderator,
                                        path = "a", sims = 1000L, seed = 1234L,
                                        w_levels = NULL,
                                        continuous_moderators = c("Age", "BMI")) {
  need <- c(exposure, mediator, outcome, moderator)
  if (!all(need %in% names(data))) return(NULL)
  d0 <- data[, need, drop = FALSE]
  d0 <- d0[stats::complete.cases(d0), , drop = FALSE]
  if (nrow(d0) < 30L) return(NULL)

  w_is_cont <- moderator %in% continuous_moderators || is.numeric(d0[[moderator]])
  if (is.null(w_levels)) {
    if (w_is_cont) {
      mu <- mean(d0[[moderator]], na.rm = TRUE)
      sdv <- stats::sd(d0[[moderator]], na.rm = TRUE)
      w_levels <- c(mu - sdv, mu, mu + sdv)
      names(w_levels) <- c("Mean-1SD", "Mean", "Mean+1SD")
    } else {
      lv <- sort(unique(as.character(d0[[moderator]])))
      w_levels <- lv
      names(w_levels) <- lv
    }
  }

  .one_ab <- function(dd, w_val) {
    dd <- dd
    if (w_is_cont) {
      dd$W_c <- as.numeric(dd[[moderator]]) - as.numeric(w_val)
      # 在该水平：等价于用中心化后 W_c=0 处的简单效应
      # 用全体样本、以 (W - w_val) 中心化后取主效应
      if (identical(path, "a") || identical(path, "a_and_b")) {
        fit_m <- stats::lm(
          stats::as.formula(paste0(mediator, " ~ ", exposure, " * W_c")),
          data = dd
        )
        cf <- stats::coef(fit_m)
        a <- unname(cf[[exposure]])
      } else {
        fit_m <- stats::lm(stats::as.formula(paste0(mediator, " ~ ", exposure)), data = dd)
        a <- unname(stats::coef(fit_m)[[exposure]])
      }
      if (identical(path, "b") || identical(path, "a_and_b")) {
        fit_y <- stats::glm(
          stats::as.formula(paste0(outcome, " ~ ", exposure, " + ", mediator, " * W_c")),
          data = dd, family = stats::binomial()
        )
        cfy <- stats::coef(fit_y)
        b <- unname(cfy[[mediator]])
      } else {
        fit_y <- stats::glm(
          stats::as.formula(paste0(outcome, " ~ ", exposure, " + ", mediator)),
          data = dd, family = stats::binomial()
        )
        b <- unname(stats::coef(fit_y)[[mediator]])
      }
    } else {
      dd_s <- dd[as.character(dd[[moderator]]) == as.character(w_val), , drop = FALSE]
      if (nrow(dd_s) < 20L) return(c(a = NA_real_, b = NA_real_, ab = NA_real_))
      fit_m <- stats::lm(stats::as.formula(paste0(mediator, " ~ ", exposure)), data = dd_s)
      fit_y <- stats::glm(
        stats::as.formula(paste0(outcome, " ~ ", exposure, " + ", mediator)),
        data = dd_s, family = stats::binomial()
      )
      a <- unname(stats::coef(fit_m)[[exposure]])
      b <- unname(stats::coef(fit_y)[[mediator]])
    }
    c(a = a, b = b, ab = a * b)
  }

  set.seed(as.integer(seed))
  n <- nrow(d0)
  out_rows <- list()
  for (i in seq_along(w_levels)) {
    w_val <- w_levels[[i]]
    w_lab <- names(w_levels)[i] %||% as.character(w_val)
    point <- tryCatch(.one_ab(d0, w_val), error = function(e) c(a = NA, b = NA, ab = NA))
    boots <- replicate(as.integer(sims), {
      idx <- sample.int(n, n, replace = TRUE)
      tryCatch(.one_ab(d0[idx, , drop = FALSE], w_val), error = function(e) c(a = NA, b = NA, ab = NA))
    })
    ab_boot <- if (is.matrix(boots)) boots["ab", ] else rep(NA_real_, sims)
    ab_boot <- ab_boot[is.finite(ab_boot)]
    ci <- if (length(ab_boot) >= 50L) {
      stats::quantile(ab_boot, c(0.025, 0.975), names = FALSE, na.rm = TRUE)
    } else {
      c(NA_real_, NA_real_)
    }
    out_rows[[length(out_rows) + 1L]] <- data.frame(
      exposure = exposure, mediator = mediator, outcome = outcome,
      moderator = moderator, path = path, w_level = w_lab, w_value = as.numeric(w_val) %||% NA_real_,
      a = unname(point[["a"]]), b = unname(point[["b"]]),
      indirect = unname(point[["ab"]]),
      indirect_lo = ci[1], indirect_hi = ci[2],
      significant = is.finite(ci[1]) && is.finite(ci[2]) && (ci[1] > 0 || ci[2] < 0),
      n = n, sims = as.integer(sims),
      stringsAsFactors = FALSE
    )
  }
  do.call(rbind, out_rows)
}

#' 简单斜率：连续调节时 X→M（或指定路径）在 Mean±1SD
modmed_simple_slopes_table <- function(data, exposure, mediator, moderator,
                                       continuous_moderators = c("Age", "BMI")) {
  need <- c(exposure, mediator, moderator)
  if (!all(need %in% names(data))) return(NULL)
  d <- data[, need, drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 30L) return(NULL)

  if (moderator %in% continuous_moderators || is.numeric(d[[moderator]])) {
    mu <- mean(d[[moderator]], na.rm = TRUE)
    sdv <- stats::sd(d[[moderator]], na.rm = TRUE)
    levels <- c(mu - sdv, mu, mu + sdv)
    labs <- c("Mean-1SD", "Mean", "Mean+1SD")
    rows <- lapply(seq_along(levels), function(i) {
      d$W_c <- d[[moderator]] - levels[i]
      fit <- stats::lm(stats::as.formula(paste0(mediator, " ~ ", exposure, " * W_c")), data = d)
      sm <- summary(fit)$coefficients
      beta <- as.numeric(sm[exposure, 1])
      se <- as.numeric(sm[exposure, 2])
      p <- as.numeric(sm[exposure, 4])
      data.frame(
        exposure = exposure, mediator = mediator, moderator = moderator,
        w_level = labs[i], w_value = levels[i],
        slope = beta, se = se, p = p,
        ci_lo = beta - 1.96 * se, ci_hi = beta + 1.96 * se,
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, rows)
  } else {
    lv <- sort(unique(as.character(d[[moderator]])))
    rows <- lapply(lv, function(lab) {
      ds <- d[as.character(d[[moderator]]) == lab, , drop = FALSE]
      if (nrow(ds) < 20L) return(NULL)
      fit <- stats::lm(stats::as.formula(paste0(mediator, " ~ ", exposure)), data = ds)
      sm <- summary(fit)$coefficients
      if (!exposure %in% rownames(sm)) return(NULL)
      beta <- as.numeric(sm[exposure, 1])
      se <- as.numeric(sm[exposure, 2])
      p <- as.numeric(sm[exposure, 4])
      data.frame(
        exposure = exposure, mediator = mediator, moderator = moderator,
        w_level = lab, w_value = NA_real_,
        slope = beta, se = se, p = p,
        ci_lo = beta - 1.96 * se, ci_hi = beta + 1.96 * se,
        stringsAsFactors = FALSE
      )
    })
    do.call(rbind, Filter(Negate(is.null), rows))
  }
}

modmed_plot_simple_slopes <- function(slope_df, title = NULL, outfile = NULL) {
  modmed_ensure_pkgs("ggplot2")
  if (is.null(slope_df) || !nrow(slope_df)) return(NULL)
  slope_df$w_level <- factor(slope_df$w_level, levels = unique(slope_df$w_level))
  p <- ggplot2::ggplot(slope_df, ggplot2::aes(x = w_level, y = slope, group = 1)) +
    ggplot2::geom_hline(yintercept = 0, linetype = 2, color = "grey50") +
    ggplot2::geom_point(size = 2.5) +
    ggplot2::geom_errorbar(ggplot2::aes(ymin = ci_lo, ymax = ci_hi), width = 0.15) +
    ggplot2::geom_line() +
    ggplot2::labs(
      title = title %||% paste0(
        "Simple slopes: ", slope_df$exposure[1], " -> ", slope_df$mediator[1]
      ),
      x = slope_df$moderator[1], y = "Simple slope (X -> M)"
    ) +
    ggplot2::theme_bw(base_size = 12)
  if (!is.null(outfile)) {
    dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
    ggplot2::ggsave(outfile, p, width = 6, height = 4)
  }
  p
}

modmed_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}
