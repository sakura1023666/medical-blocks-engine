###############################################################################
#  sem_chain_mediation — 链式中介 Bootstrap（a*b, a*b*c 间接效应）
#  文献: Zhu 2025 J Adv Research — Sarcopenia → Depression → Cognitive → Frailty
###############################################################################

.sem_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
}

.sem_active_covs <- function(d, covs) {
  covs <- intersect(covs, names(d))
  covs[vapply(covs, function(c) {
    x <- d[[c]]
    length(unique(x[!is.na(x)])) > 1L
  }, logical(1L))]
}

.sem_chain_effects <- function(d, x, m1, m2, y, covs) {
  adj <- .sem_active_covs(d, covs)
  adj_rhs <- if (length(adj)) paste("+", paste(adj, collapse = " + ")) else ""
  a <- coef(stats::lm(stats::as.formula(paste(m1, "~", x, adj_rhs)), d))[x]
  fit_b <- stats::lm(stats::as.formula(paste(m2, "~", x, "+", m1, adj_rhs)), d)
  b <- coef(fit_b)[m1]
  c_prime <- coef(fit_b)[x]
  fit_y <- if (is.numeric(d[[y]])) {
    stats::lm(stats::as.formula(paste(y, "~", x, "+", m1, "+", m2, adj_rhs)), d)
  } else {
    stats::glm(stats::as.formula(paste(y, "~", x, "+", m1, "+", m2, adj_rhs)), d, family = stats::binomial())
  }
  c <- coef(fit_y)[m2]
  d_dir <- coef(fit_y)[x]
  list(
    a = a, b = b, c = c,
    indirect_m1_m2 = a * b,
    indirect_full = a * b * c,
    direct = d_dir,
    total = d_dir + a * b * c
  )
}

block_sem_chain_mediation <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_chain_mediation: 无数据", call. = FALSE)

  x <- bl$exposure_var %||% "Sarcopenia"
  m1 <- bl$m1_var %||% "Depression"
  m2 <- bl$m2_var %||% "Cognitive_score"
  y <- bl$event_var %||% "Frailty_event"
  covs <- bl$covariate_vars %||% bl$covariates %||% c("Age", "Gender", "Sex")
  n_boot <- as.integer(bl$mediation_boot_R %||% 500L)
  if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) n_boot <- min(n_boot, 50L)

  need <- c(x, m1, m2, y)
  if (!all(need %in% names(data))) {
    cli::cli_alert_warning("链式中介: 变量缺失，跳过")
    return(ctx)
  }

  d <- data[complete.cases(data[need]), , drop = FALSE]
  if (nrow(d) < 30L) {
    cli::cli_alert_warning("链式中介: 样本不足")
    return(ctx)
  }

  point <- .sem_chain_effects(d, x, m1, m2, y, covs)
  stat_fn <- function(dat, idx) {
    dd <- dat[idx, , drop = FALSE]
    tryCatch(.sem_chain_effects(dd, x, m1, m2, y, covs), error = function(e) NULL)
  }

  set.seed(bl$mediation_boot_seed %||% 42L)
  boots <- replicate(n_boot, stat_fn(d, sample.int(nrow(d), replace = TRUE)), simplify = FALSE)
  boots <- boots[!vapply(boots, is.null, logical(1L))]

  .boot_ci <- function(field) {
    vals <- vapply(boots, function(b) b[[field]], numeric(1L))
    vals <- vals[is.finite(vals)]
    c(
      estimate = mean(vals),
      ci_lower = stats::quantile(vals, 0.025),
      ci_upper = stats::quantile(vals, 0.975),
      n_boot = length(vals)
    )
  }

  paths <- c("a", "b", "c", "indirect_m1_m2", "indirect_full", "direct", "total")
  tab <- do.call(rbind, lapply(paths, function(p) {
    ci <- .boot_ci(p)
    data.frame(
      path = p,
      point = unname(point[[p]]),
      estimate = ci["estimate"],
      ci_lower = ci["ci_lower"],
      ci_upper = ci["ci_upper"],
      n_boot = ci["n_boot"],
      stringsAsFactors = FALSE
    )
  }))

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Chain_Mediation_Bootstrap.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)

  ctx$results$sem_chain_mediation <- list(table = tab, n_boot = n_boot, point = point)
  cli::cli_alert_success("链式中介 Bootstrap 完成 (R={n_boot})")
  ctx
}

register_block("sem_chain_mediation", block_sem_chain_mediation, "链式中介 Bootstrap 500")
