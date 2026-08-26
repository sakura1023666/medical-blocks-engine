###############################################################################
#  markov_msm_utils.R — CLHLS 三状态 MSM + Bootstrap + 生命表
###############################################################################

.markov_prep_long_msm <- function(data, bl) {
  id_col <- bl$id_col %||% "ID"
  time_col <- bl$time_col %||% "Followup_years"
  state_col <- bl$state_col %||% "Cognitive_state"
  d <- data[order(data[[id_col]], data[[time_col]]), , drop = FALSE]
  st <- as.character(d[[state_col]])
  d$state_num <- ifelse(st %in% c("Death", "3"), 3L,
    ifelse(st %in% c("CI", "2"), 2L, 1L))
  if (id_col != "ID") d$ID <- d[[id_col]]
  d[[time_col]] <- suppressWarnings(as.numeric(d[[time_col]]))
  d
}

.markov_fit_msm <- function(long, bl) {
  id_col <- bl$id_col %||% "ID"
  time_col <- bl$time_col %||% "Followup_years"
  if (!requireNamespace("msm", quietly = TRUE)) {
    stop("请安装 msm 包: install.packages('msm')", call. = FALSE)
  }
  Q <- rbind(
    c(0, 0.02, 0.005),
    c(0.01, 0, 0.03),
    c(0, 0, 0)
  )
  covs <- intersect(bl$msm_covars %||% c("APOE_carrier", "Healthy_lifestyle", "Sex"), names(long))
  fit <- msm::msm(
    stats::as.formula(paste("state_num ~", time_col)),
    subject = ID,
    data = long,
    qmatrix = Q,
    death = 3L,
    covariates = if (length(covs)) stats::as.formula(paste("~", paste(covs, collapse = "+"))) else NULL,
    method = "BFGS",
    control = list(trace = 0)
  )
  fit
}

.markov_bootstrap_q <- function(long, bl, R = 100L) {
  id_col <- bl$id_col %||% "ID"
  ids <- unique(long[[id_col]])
  if (R > length(ids)) R <- max(50L, min(R, length(ids)))
  q_rows <- list()
  for (b in seq_len(R)) {
    samp <- sample(ids, length(ids), replace = TRUE)
    boot <- do.call(rbind, lapply(samp, function(i) long[long[[id_col]] == i, , drop = FALSE]))
    fit <- tryCatch(.markov_fit_msm(boot, bl), error = function(e) NULL)
    if (is.null(fit)) next
    qm <- as.vector(fit$Qmatrices$baseline)
    q_rows[[length(q_rows) + 1L]] <- qm
  }
  if (!length(q_rows)) return(NULL)
  mat <- do.call(rbind, q_rows)
  data.frame(
    q12_mean = mean(mat[, 2], na.rm = TRUE), q12_lo = stats::quantile(mat[, 2], 0.025, na.rm = TRUE),
    q12_hi = stats::quantile(mat[, 2], 0.975, na.rm = TRUE),
    q13_mean = mean(mat[, 3], na.rm = TRUE),
    q23_mean = mean(mat[, 5], na.rm = TRUE)
  )
}

.markov_life_expectancy_table <- function(long, bl, ages = c(65, 75, 85)) {
  id_col <- bl$id_col %||% "ID"
  time_col <- bl$time_col %||% "Followup_years"
  state_col <- bl$state_col %||% "Cognitive_state"
  rows <- list()
  for (age_entry in ages) {
    for (st in c("CH", "CI")) {
      sub <- long[long[[state_col]] == st & long[[time_col]] >= 0, , drop = FALSE]
      if (!nrow(sub)) next
      fut <- stats::aggregate(
        as.numeric(long[[time_col]][match(sub[[id_col]], long[[id_col]])]) ~ sub[[id_col]],
        data = sub, FUN = max
      )
      le <- mean(fut[, 2L], na.rm = TRUE)
      rows[[length(rows) + 1L]] <- data.frame(
        entry_age = age_entry, state = st, life_expectancy_years = le,
        n = length(unique(sub[[id_col]])),
        stringsAsFactors = FALSE
      )
    }
  }
  if (!length(rows)) return(data.frame())
  do.call(rbind, rows)
}

.markov_apoe_le_diff <- function(le_df, apoe_col = "APOE_carrier") {
  if (!nrow(le_df)) return(data.frame())
  ch <- le_df[le_df$state %in% c("CH", "Healthy"), , drop = FALSE]
  if (!nrow(ch)) return(data.frame())
  data.frame(
    metric = "CH_life_expectancy_diff",
    carrier_minus_noncarrier = NA_real_,
    note = "按 APOE 分层生命表在 block_markov_apoe_le_difference 中计算",
    stringsAsFactors = FALSE
  )
}
