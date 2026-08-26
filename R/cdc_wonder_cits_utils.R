###############################################################################
#  cdc_wonder_cits_utils.R — CDC WONDER CITS 完整规格（tau + 组内 post 斜率）
###############################################################################

.cits_ban_states_default <- function() {
  list(
    ban = c("AL", "AR", "ID", "IN", "KY", "LA", "MS", "MO", "ND", "OK", "SD", "TN", "TX", "WV", "WI"),
    no_ban = c("CA", "NY", "IL", "PA", "OH", "MI", "GA", "NC", "VA", "WA", "MA", "AZ", "CO", "OR", "NJ")
  )
}

.cits_total_ban_states <- function() {
  c("AL", "AR", "ID", "IN", "KY", "LA", "MS", "MO", "OK", "SD", "TN", "TX", "WV")
}

.cits_protected_states <- function() {
  c("CA", "NY", "IL", "WA", "OR", "CO", "MA", "NJ", "CT", "VT", "MD")
}

.cits_fetch_natality_monthly <- function(start_month = "2021-01", end_month = "2024-02",
                                         cache_path = "Data/smoke/D01_cdc_wonder_monthly_rates.csv") {
  cache_path <- normalizePath(cache_path, winslash = "/", mustWork = FALSE)
  if (file.exists(cache_path)) {
    return(utils::read.csv(cache_path, stringsAsFactors = FALSE))
  }
  url <- paste0(
    "https://wonder.cdc.gov/natality.html"
  )
  message("WONDER API: 使用本地缓存 ", cache_path, "（无缓存时请运行 smoke 或放置 WONDER 导出 CSV）")
  if (!file.exists(cache_path)) stop("CDC WONDER 数据不可用: ", cache_path, call. = FALSE)
  utils::read.csv(cache_path, stringsAsFactors = FALSE)
}

.cits_prepare_monthly_rates <- function(records, bl) {
  date_col <- bl$date_col %||% "Birth_month"
  group_col <- bl$group_col %||% "Ban_state"
  state_col <- bl$state_col %||% "State"
  outcome_cols <- bl$outcome_cols %||% c("Nonliving_birth", "Congenital_anomaly", "Maternal_morbidity")
  intervention <- as.Date(bl$intervention_date %||% "2022-11-01")
  scale <- bl$rate_per_n %||% 10000L

  d <- records
  if (state_col %in% names(d) && !group_col %in% names(d)) {
    bans <- .cits_ban_states_default()$ban
    d[[group_col]] <- ifelse(d[[state_col]] %in% bans, "Ban", "No_ban")
  }
  d$month <- as.Date(paste0(d[[date_col]], "-01"))
  d$ban <- as.integer(as.character(d[[group_col]]) %in% c("Ban", "1", "Yes"))
  d$tau <- as.numeric(d$month - min(d$month, na.rm = TRUE)) / 30.44
  d$post <- as.integer(d$month >= intervention)

  rows <- list()
  for (oc in intersect(outcome_cols, names(d))) {
    d$count <- suppressWarnings(as.numeric(d[[oc]]))
    d$n_births <- suppressWarnings(as.numeric(d$n_births %||% d$Births %||% 1L))
    if (!"n_births" %in% names(d)) d$n_births <- 1L
    agg <- stats::aggregate(
      cbind(count = count, n_births = n_births) ~ month + ban + post + tau,
      data = d, FUN = sum, na.rm = TRUE
    )
    agg$rate_per10k <- agg$count / pmax(agg$n_births, 1L) * scale
    agg$outcome <- oc
    rows[[length(rows) + 1L]] <- agg
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

.cits_fit_full <- function(monthly, outcome = NULL) {
  if (!is.null(outcome)) monthly <- monthly[monthly$outcome == outcome, , drop = FALSE]
  if (!nrow(monthly)) stop("CITS: 无月度数据", call. = FALSE)
  monthly$ban_post <- monthly$ban * monthly$post
  monthly$ban_tau <- monthly$ban * monthly$tau
  monthly$post_tau <- monthly$post * monthly$tau
  monthly$ban_post_tau <- monthly$ban * monthly$post * monthly$tau
  fml <- stats::as.formula(
    "rate_per10k ~ ban + post + tau + ban:post + ban:tau + post:tau + ban:post:tau"
  )
  fit <- stats::lm(fml, data = monthly)
  vcov_mat <- if (requireNamespace("sandwich", quietly = TRUE)) {
    tryCatch(sandwich::NeweyWest(fit, lag = 3L), error = function(e) stats::vcov(fit))
  } else stats::vcov(fit)
  if (requireNamespace("lmtest", quietly = TRUE)) {
    cf <- lmtest::coeftest(fit, vcov = vcov_mat)
  } else {
    cf <- summary(fit)$coefficients
  }
  coef_df <- data.frame(
    term = rownames(cf),
    estimate = cf[, 1L],
    se = cf[, 2L],
    statistic = cf[, 3L],
    p_value = cf[, 4L],
    stringsAsFactors = FALSE
  )
  list(fit = fit, coefficients = coef_df, outcome = unique(monthly$outcome))
}

.cits_did_change <- function(monthly, outcome) {
  sub <- monthly[monthly$outcome == outcome, , drop = FALSE]
  pre <- stats::aggregate(rate_per10k ~ ban, data = sub[sub$post == 0L, , drop = FALSE], FUN = mean, na.rm = TRUE)
  post <- stats::aggregate(rate_per10k ~ ban, data = sub[sub$post == 1L, , drop = FALSE], FUN = mean, na.rm = TRUE)
  names(pre) <- c("ban", "pre_rate")
  names(post) <- c("ban", "post_rate")
  m <- merge(pre, post, by = "ban")
  if (nrow(m) < 2L) return(data.frame(outcome = outcome, did_diff = NA_real_))
  ch_ban <- m$post_rate[m$ban == 1L] - m$pre_rate[m$ban == 1L]
  ch_nob <- m$post_rate[m$ban == 0L] - m$pre_rate[m$ban == 0L]
  data.frame(
    outcome = outcome,
    change_ban = ch_ban, change_no_ban = ch_nob,
    did_diff = ch_ban - ch_nob,
    stringsAsFactors = FALSE
  )
}
