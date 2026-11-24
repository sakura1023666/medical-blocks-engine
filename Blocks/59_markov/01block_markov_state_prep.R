###############################################################################
#  markov_state_prep — CLHLS 三状态 CH/CI/Death（MMSE<18 或痴呆诊断）
#  文献: Ren 2025 Alzheimers Dement e70090 — N=6488
###############################################################################

block_markov_state_prep <- function(ctx, ...) {
  bl <- ctx$config$markov_cognitive %||% list()
  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) stop("markov_state_prep: 无数据", call. = FALSE)

  mmse_col <- bl$mmse_col %||% "MMSE"
  death_col <- bl$death_col %||% "Death"
  dementia_col <- bl$dementia_col %||% "Dementia_dx"
  ci_cut <- bl$ci_cutoff %||% 18L
  d <- data

  d$MMSE <- suppressWarnings(as.numeric(d[[mmse_col]]))
  d$Death <- as.integer(suppressWarnings(as.numeric(d[[death_col]])) == 1L)
  d$Dementia <- if (dementia_col %in% names(d)) as.integer(suppressWarnings(as.numeric(d[[dementia_col]])) >= 1L) else 0L
  d$CI_flag <- as.integer(d$MMSE < ci_cut | d$Dementia == 1L)

  d$Cognitive_state <- ifelse(d$Death == 1L, "Death",
    ifelse(d$CI_flag == 1L, "CI", "CH"))

  lifestyle_vars <- bl$lifestyle_vars %||% c("Exercise", "Diet", "Social", "Cognitive_activity", "Smoking_reverse")
  lifestyle_vars <- intersect(lifestyle_vars, names(d))
  if (length(lifestyle_vars) >= 3L) {
    sc <- rowSums(sapply(d[lifestyle_vars], function(x) as.integer(suppressWarnings(as.numeric(x)) >= 1)))
    d$Healthy_lifestyle_score <- sc
    d$Healthy_lifestyle <- ifelse(sc >= (bl$lifestyle_cutoff %||% 4L), "High", "Low")
  }

  if ("APOE" %in% names(d)) {
    ap <- as.character(d$APOE)
    d$APOE_carrier <- ifelse(grepl("e4", ap, ignore.case = TRUE), "Carrier", "Non_carrier")
    d$APOE_group3 <- ifelse(grepl("e2/e2|e2/e3", ap), "e2_carrier",
      ifelse(grepl("e4", ap), "e4_carrier", "e3_homozygote"))
  }

  ctx$data$cleaned <- d
  ctx$data$imputed <- d
  ctx$results$markov_state_prep <- list(
    n = length(unique(d$ID)), n_rows = nrow(d),
    state_tab = as.list(table(d$Cognitive_state)),
    ci_cutoff = ci_cut
  )
  cli::cli_alert_success("Markov 三状态 CH/CI/Death 准备完成 (N={length(unique(d$ID))})")
  ctx
}

register_block("markov_state_prep", block_markov_state_prep, "三状态 CH/CI/Death 准备")
