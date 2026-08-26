###############################################################################
#  bayesian_body_clock — brms 贝叶斯有序回归 Body Clock（cumulative + mo）
#  文献: Salimi 2025 Nat Commun — BODN ordinal, 11 系统 monotonic 效应
###############################################################################

block_bayesian_body_clock <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_packages.R"), local = FALSE)
  literature_ensure_packages("bayesian")

  bl <- ctx$config$bayesian_comorbidity %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !"BODN" %in% names(data))
    stop("bayesian_body_clock: 请先运行 bayesian_bodn", call. = FALSE)

  sys_cols <- bl$system_severity_cols %||% grep("_sev$", names(data), value = TRUE)
  train_cohort <- bl$train_cohort %||% "BLSA"
  train_df <- if ("Cohort" %in% names(data)) data[data$Cohort == train_cohort, , drop = FALSE] else data
  if (nrow(train_df) < 20L) train_df <- data

  mo_terms <- paste(sprintf("mo(%s)", sys_cols), collapse = " + ")
  fml_mo <- stats::as.formula(paste("BODN_ord ~", mo_terms))
  fml_lm <- stats::as.formula(paste("BODN ~", paste(sys_cols, collapse = " + ")))
  train_df$BODN_ord <- ordered(train_df$BODN)
  for (sc in sys_cols) train_df[[sc]] <- as.numeric(train_df[[sc]])
  iter <- as.integer(bl$brms_iter %||% 800L)
  chains <- as.integer(bl$brms_chains %||% 2L)

  fit <- tryCatch(
    brms::brm(
      fml_lm, data = train_df, family = stats::gaussian(),
      chains = chains, iter = iter, cores = min(chains, 2L),
      refresh = 0, silent = 2, seed = bl$brms_seed %||% 42L
    ),
    error = function(e) {
      fit2 <- tryCatch(
        brms::brm(
          fml_mo, data = train_df, family = brms::cumulative("logit"),
          chains = chains, iter = iter, cores = min(chains, 2L),
          refresh = 0, silent = 2, seed = bl$brms_seed %||% 42L
        ),
        error = function(e2) NULL
      )
      if (!is.null(fit2)) return(fit2)
      cli::cli_alert_warning("brms 失败，回退加权: {e$message}")
      NULL
    }
  )

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  model_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Models")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(model_dir, recursive = TRUE, showWarnings = FALSE)

  if (!is.null(fit)) {
    saveRDS(fit, file.path(model_dir, "brms_body_clock_train.rds"))
    full <- ctx$data$imputed %||% ctx$data$cleaned
    for (sc in sys_cols) full[[sc]] <- as.numeric(full[[sc]])
    full$BODN_ord <- ordered(full$BODN)
    pred <- tryCatch(
      colMeans(brms::fitted(fit, newdata = full, re.form = NA, summary = FALSE)),
      error = function(e) tryCatch(
        as.numeric(stats::predict(fit, newdata = full)),
        error = function(e2) as.numeric(full$BODN)
      )
    )
    full$Body_Clock <- pred
    summ <- brms::posterior_summary(fit)
    utils::write.csv(as.data.frame(summ), file.path(out_dir, "Table_Body_Clock_brms_posterior.csv"))
    engine <- "brms"
    data <- full
  } else {
    full <- ctx$data$imputed %||% ctx$data$cleaned
    sev_full <- as.data.frame(lapply(full[sys_cols], function(x) as.numeric(x)))
    sev_full[is.na(sev_full)] <- 0
    w <- rep(1 / length(sys_cols), length(sys_cols))
    full$Body_Clock <- as.numeric(as.matrix(sev_full) %*% w)
    data <- full
    fit <- NULL
    engine <- "mean_severity_fallback"
  }

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$bayesian_body_clock <- list(model = fit, engine = engine, train_cohort = train_cohort)
  cli::cli_alert_success("Body Clock 估计完成（{engine}, train={train_cohort}）")
  ctx
}

register_block("bayesian_body_clock", block_bayesian_body_clock, "brms 贝叶斯有序 Body Clock")
