###############################################################################
#  parallel_competing_mediation — 双平行中介 + 间接效应差（bootstrap）
#
#  register_block: "parallel_competing_mediation"
#  方法目录: Blocks/20_mediation/（接着 13 排号）
#
#  默认连续结局（lm + mediation::mediate boot）；二项结局设 outcome_family="binomial"
#
#  config$parallel_competing_mediation = list(
#    exposure = "PHQ15",
#    mediators = c("SSD12", "Whiteley8"),
#    outcome = "WHODAS",
#    covariates = c("age", "sex"),
#    outcome_family = "gaussian",
#    sims = 5000L, seed = 1234L,
#    compare_indirect = TRUE
#  )
###############################################################################

block_parallel_competing_mediation <- function(ctx, ...) {
  if (!requireNamespace("mediation", quietly = TRUE)) {
    stop("需要 mediation 包", call. = FALSE)
  }

  cfg <- ctx$config
  bl <- cfg$parallel_competing_mediation %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("parallel_competing_mediation: 无数据", call. = FALSE)

  x <- as.character(bl$exposure %||% "")[1L]
  ms <- as.character(bl$mediators %||% character(0))
  y <- as.character(bl$outcome %||% "")[1L]
  covs <- as.character(bl$covariates %||% character(0))
  covs <- covs[covs %in% names(data)]
  sims <- as.integer(bl$sims %||% 5000L)
  seed <- as.integer(bl$seed %||% cfg$seed %||% 1234L)
  env_sims <- Sys.getenv("SSD_MED_SIMS", unset = "")
  if (nzchar(env_sims)) sims <- as.integer(env_sims)
  fam <- as.character(bl$outcome_family %||% "gaussian")[1L]

  if (!x %in% names(data) || !y %in% names(data) || length(ms) < 2L) {
    stop("parallel_competing_mediation: exposure/outcome/mediators 配置不完整", call. = FALSE)
  }
  ms <- ms[ms %in% names(data)]
  if (length(ms) < 2L) stop("parallel_competing_mediation: 有效中介 < 2", call. = FALSE)

  need <- unique(c(x, y, ms, covs))
  d <- data[, need, drop = FALSE]
  for (v in c(x, y, ms)) d[[v]] <- suppressWarnings(as.numeric(d[[v]]))
  for (v in covs) {
    if (is.character(data[[v]]) || is.factor(data[[v]])) {
      fv <- factor(data[[v]])
      # 合并稀有水平，避免 bootstrap 出现 new levels
      tabn <- table(fv)
      rare <- names(tabn)[as.integer(tabn) < 15L]
      if (length(rare)) {
        fv <- as.character(fv)
        fv[fv %in% rare] <- "other"
        fv <- factor(fv)
      }
      d[[v]] <- droplevels(fv)
    } else {
      d[[v]] <- suppressWarnings(as.numeric(d[[v]]))
    }
  }
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 50L) stop("parallel_competing_mediation: 完整病例 < 50", call. = FALSE)

  .boot_path <- function(m, seed_i) {
    set.seed(seed_i)
    n <- nrow(d)
    B <- as.integer(sims)
    acme <- ade <- tot <- numeric(B)
    cov_txt <- if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
    for (b in seq_len(B)) {
      db <- d[sample.int(n, n, replace = TRUE), , drop = FALSE]
      # 保证因子水平与全样本一致
      for (v in covs) {
        if (is.factor(d[[v]])) {
          db[[v]] <- factor(db[[v]], levels = levels(d[[v]]))
        }
      }
      db <- db[stats::complete.cases(db), , drop = FALSE]
      if (nrow(db) < 30L) { acme[b] <- ade[b] <- tot[b] <- NA_real_; next }
      mm <- tryCatch(
        stats::lm(stats::as.formula(paste0(m, " ~ ", x, cov_txt)), data = db),
        error = function(e) NULL
      )
      my <- tryCatch(
        stats::lm(stats::as.formula(paste0(y, " ~ ", x, " + ", m, cov_txt)), data = db),
        error = function(e) NULL
      )
      if (is.null(mm) || is.null(my)) { acme[b] <- ade[b] <- tot[b] <- NA_real_; next }
      a <- unname(stats::coef(mm)[x])
      b_coef <- unname(stats::coef(my)[m])
      cprime <- unname(stats::coef(my)[x])
      acme[b] <- a * b_coef
      ade[b] <- cprime
      tot[b] <- acme[b] + ade[b]
    }
    ok <- is.finite(acme) & is.finite(ade)
    list(
      ACME = mean(acme[ok]), ADE = mean(ade[ok]), total = mean(tot[ok]),
      prop = mean(acme[ok] / tot[ok]),
      ACME_lo = as.numeric(stats::quantile(acme[ok], 0.025)),
      ACME_hi = as.numeric(stats::quantile(acme[ok], 0.975)),
      ADE_lo = as.numeric(stats::quantile(ade[ok], 0.025)),
      ADE_hi = as.numeric(stats::quantile(ade[ok], 0.975)),
      n_boot = sum(ok)
    )
  }

  .one_path <- function(m, seed_i) {
    cov_txt <- if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
    fml_m <- stats::as.formula(paste0(m, " ~ ", x, cov_txt))
    fml_y <- stats::as.formula(paste0(y, " ~ ", x, " + ", m, cov_txt))
    model_m <- stats::lm(fml_m, data = d)
    model_y <- if (identical(fam, "binomial")) {
      stats::glm(fml_y, data = d, family = stats::binomial())
    } else {
      stats::lm(fml_y, data = d)
    }
    set.seed(seed_i)
    med <- tryCatch(
      mediation::mediate(
        model.m = model_m, model.y = model_y,
        treat = x, mediator = m,
        boot = TRUE, sims = sims, boot.ci.type = "perc"
      ),
      error = function(e) NULL
    )
    if (!is.null(med) && is.finite(as.numeric(med$d.avg)[1L])) {
      return(data.frame(
        exposure = x, mediator = m, outcome = y,
        ACME = as.numeric(med$d.avg), ADE = as.numeric(med$z.avg),
        total = as.numeric(med$tau.coef),
        prop = as.numeric(med$n.avg),
        ACME_lo = as.numeric(med$d.avg.ci[1]), ACME_hi = as.numeric(med$d.avg.ci[2]),
        ADE_lo = as.numeric(med$z.avg.ci[1]), ADE_hi = as.numeric(med$z.avg.ci[2]),
        method = "mediation::mediate",
        stringsAsFactors = FALSE
      ))
    }
    cli::cli_alert_warning("mediate() 失败，回退 product-of-coefficients bootstrap: {m}")
    bp <- .boot_path(m, seed_i + 17L)
    data.frame(
      exposure = x, mediator = m, outcome = y,
      ACME = bp$ACME, ADE = bp$ADE, total = bp$total, prop = bp$prop,
      ACME_lo = bp$ACME_lo, ACME_hi = bp$ACME_hi,
      ADE_lo = bp$ADE_lo, ADE_hi = bp$ADE_hi,
      method = "bootstrap_ab",
      stringsAsFactors = FALSE
    )
  }

  rows <- list()
  for (i in seq_along(ms)) {
    cli::cli_alert_info("平行中介 [{i}/{length(ms)}]: {x} → {ms[i]} → {y} (sims={sims}, family={fam})")
    rows[[i]] <- .one_path(ms[i], seed + i)
  }
  tab <- do.call(rbind, rows)

  diff_tab <- NULL
  if (isTRUE(bl$compare_indirect %||% TRUE) && length(ms) >= 2L) {
    set.seed(seed + 99L)
    n <- nrow(d)
    B <- min(as.integer(sims), 2000L)
    deltas <- numeric(B)
    for (b in seq_len(B)) {
      idx <- sample.int(n, n, replace = TRUE)
      db <- d[idx, , drop = FALSE]
      get_acme <- function(m) {
        cov_txt <- if (length(covs)) paste0(" + ", paste(covs, collapse = " + ")) else ""
        model_m <- tryCatch(
          stats::lm(stats::as.formula(paste0(m, " ~ ", x, cov_txt)), data = db),
          error = function(e) NULL
        )
        model_y <- tryCatch(
          stats::lm(stats::as.formula(paste0(y, " ~ ", x, " + ", m, cov_txt)), data = db),
          error = function(e) NULL
        )
        if (is.null(model_m) || is.null(model_y)) return(NA_real_)
        a <- stats::coef(model_m)[[x]]
        b1 <- stats::coef(model_y)[[m]]
        as.numeric(a * b1)
      }
      deltas[b] <- get_acme(ms[1]) - get_acme(ms[2])
    }
    deltas <- deltas[is.finite(deltas)]
    diff_tab <- data.frame(
      contrast = paste0("ACME(", ms[1], ") - ACME(", ms[2], ")"),
      estimate = mean(deltas),
      lo = as.numeric(stats::quantile(deltas, 0.025)),
      hi = as.numeric(stats::quantile(deltas, 0.975)),
      n_boot = length(deltas)
    )
  }

  out_dir <- file.path(ctx$output_dir %||% ".", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, file.path(out_dir, "Table_parallel_competing_mediation.csv"), row.names = FALSE)
  if (!is.null(diff_tab)) {
    utils::write.csv(diff_tab, file.path(out_dir, "Table_indirect_effect_contrast.csv"), row.names = FALSE)
  }

  ctx$results$parallel_competing_mediation <- list(
    table = tab, contrast = diff_tab, n = nrow(d), sims = sims, family = fam
  )
  cli::cli_alert_success("parallel_competing_mediation: {length(ms)} 中介完成 (n={nrow(d)})")
  ctx
}

register_block(
  "parallel_competing_mediation",
  block_parallel_competing_mediation,
  "平行竞争中介与间接效应差"
)
