###############################################################################
#  sem_cox_chain_mediation — Cox 生存链式中介（Zhu 2025 主分析框架）
#  X→M1 (logistic) → M2 (linear) → Y (Cox)；Bootstrap 间接效应
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

.sem_cox_chain_point <- function(d, x, m1, m2, time_var, event_var, covs) {
  adj <- .sem_active_covs(d, covs)
  adj_rhs <- if (length(adj)) paste("+", paste(adj, collapse = " + ")) else ""

  fit_a <- stats::glm(
    stats::as.formula(paste(m1, "~", x, adj_rhs)), data = d, family = stats::binomial()
  )
  a <- unname(coef(fit_a)[x])

  fit_b <- stats::lm(stats::as.formula(paste(m2, "~", x, "+", m1, adj_rhs)), data = d)
  b <- unname(coef(fit_b)[m1])

  surv_fml <- stats::as.formula(paste0(
    "survival::Surv(", time_var, ", ", event_var, ") ~ ", x, " + ", m1, " + ", m2, adj_rhs
  ))
  fit_c <- survival::coxph(surv_fml, data = d)
  cf <- coef(fit_c)
  c_loghr <- unname(cf[m2])
  d_loghr <- unname(cf[x])

  fit_c_m1 <- survival::coxph(
    stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", x, " + ", m1, adj_rhs)),
    data = d
  )
  fit_c_x <- survival::coxph(
    stats::as.formula(paste0("survival::Surv(", time_var, ", ", event_var, ") ~ ", x, adj_rhs)),
    data = d
  )
  a_cox <- unname(coef(fit_c_x)[x])
  b_cox <- unname(coef(fit_c_m1)[m1])

  list(
    a_log_or = a, b_lm = b, c_log_hr = c_loghr, d_log_hr = d_loghr,
    a_cox_log_hr = a_cox, b_cox_log_hr = b_cox,
    indirect_depression = a_cox * b_cox,
    indirect_chain_log = a * b * c_loghr,
    indirect_chain_hr = exp(a * b * c_loghr),
    total_log_hr_x = a_cox,
    n = nrow(d), events = sum(d[[event_var]] == 1L, na.rm = TRUE)
  )
}

block_sem_cox_chain_mediation <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  if (!requireNamespace("survival", quietly = TRUE)) stop("请安装 survival", call. = FALSE)
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_cox_chain_mediation: 无数据", call. = FALSE)

  x <- bl$exposure_var %||% "Sarcopenia"
  m1 <- bl$m1_var %||% "Depression"
  m2 <- bl$m2_var %||% "Cognitive_score"
  time_var <- bl$time_var %||% "Frailty_time"
  event_var <- bl$event_var %||% "Frailty_event"
  covs <- bl$covariate_vars %||% bl$covariates %||% c("Age", "Sex", "Education", "BMI")
  n_boot <- as.integer(bl$mediation_boot_R %||% 500L)
  if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) n_boot <- min(n_boot, 100L)

  need <- c(x, m1, m2, time_var, event_var)
  if (!all(need %in% names(data))) {
    cli::cli_alert_warning("Cox 链式中介: 变量缺失，跳过")
    return(ctx)
  }

  d <- data[stats::complete.cases(data[need]), , drop = FALSE]
  d[[time_var]] <- suppressWarnings(as.numeric(d[[time_var]]))
  d[[event_var]] <- as.integer(suppressWarnings(as.numeric(d[[event_var]])) >= 1L)
  if (nrow(d) < 40L || sum(d[[event_var]] == 1L) < 10L) {
    cli::cli_alert_warning("Cox 链式中介: 样本/事件不足")
    return(ctx)
  }

  point <- .sem_cox_chain_point(d, x, m1, m2, time_var, event_var, covs)
  set.seed(bl$mediation_boot_seed %||% 42L)
  boots <- replicate(n_boot, {
    idx <- sample.int(nrow(d), replace = TRUE)
    tryCatch(.sem_cox_chain_point(d[idx, , drop = FALSE], x, m1, m2, time_var, event_var, covs),
             error = function(e) NULL)
  }, simplify = FALSE)
  boots <- boots[!vapply(boots, is.null, logical(1L))]

  .boot_row <- function(field, transform = identity) {
    vals <- vapply(boots, function(b) transform(b[[field]]), numeric(1L))
    vals <- vals[is.finite(vals)]
    data.frame(
      effect = field,
      point = transform(point[[field]]),
      boot_mean = mean(vals),
      ci_lower = stats::quantile(vals, 0.025),
      ci_upper = stats::quantile(vals, 0.975),
      n_boot = length(vals),
      stringsAsFactors = FALSE
    )
  }

  tab <- rbind(
    .boot_row("a_log_or"),
    .boot_row("b_lm"),
    .boot_row("c_log_hr"),
    .boot_row("d_log_hr"),
    .boot_row("indirect_chain_log"),
    .boot_row("indirect_chain_hr"),
    .boot_row("indirect_depression"),
    .boot_row("a_cox_log_hr", exp),
    .boot_row("b_cox_log_hr", exp)
  )
  tab$HR_or_scale <- ifelse(tab$effect %in% c("a_log_or", "b_lm", "c_log_hr", "d_log_hr", "indirect_chain_log"), "log", "exp")

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_Cox_Chain_Mediation_Bootstrap.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)

  ctx$results$sem_cox_chain_mediation <- list(table = tab, point = point, n_boot = n_boot)
  cli::cli_alert_success("Cox 链式中介 Bootstrap 完成 (R={n_boot}, chain HR={round(point$indirect_chain_hr,3)})")
  ctx
}

register_block("sem_cox_chain_mediation", block_sem_cox_chain_mediation, "Cox 生存链式中介 Bootstrap")
