###############################################################################
#  prognosis_outcome_landmark — 插补后对 futime/fustatus 做行政截尾（默认 28 天）
#
#  register_block: "prognosis_outcome_landmark"
#  典型位置: imputation 之后、baseline_binary 之前
#
#  config$prognosis_outcome = list(
#    enable = TRUE,
#    landmark_days = 28L
#  )
#  config$survival$outcome_label = "28-day all-cause mortality"
###############################################################################

block_prognosis_outcome_landmark <- function(ctx, ...) {
  po <- ctx$config$prognosis_outcome %||% list()
  if (isFALSE(po$enable)) return(ctx)

  study_type <- tolower(trimws(as.character((ctx$config$project %||% list())$study_type %||% "")[1L]))
  if (!identical(study_type, "prognosis")) return(ctx)

  if (!exists("prognosis_apply_outcome_landmark", mode = "function")) {
    root <- ctx$project_root %||% Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    src <- file.path(root, "R/prognosis_outcome_landmark.R")
    if (!file.exists(src)) stop("缺少 R/prognosis_outcome_landmark.R", call. = FALSE)
    source(src, local = FALSE)
  }

  rt <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(rt) || !is.data.frame(rt) || !nrow(rt)) {
    stop("prognosis_outcome_landmark: 无 imputed/cleaned 数据", call. = FALSE)
  }

  landmark_days <- as.integer(po$landmark_days %||% 28L)[1L]
  event_var <- (ctx$config$survival %||% list())$event_var %||% "fustatus"
  # 计数必须走标签感知的 0/1 转换，禁止对 Survivor/Non-survivor 因子 as.integer
  if (exists("prognosis_event_to_01", mode = "function")) {
    n_ev_before <- sum(prognosis_event_to_01(rt[[event_var]], ctx$config) == 1L, na.rm = TRUE)
  } else {
    n_ev_before <- sum(as.character(rt[[event_var]]) %in% c(
      ctx$config$project$analysis_group %||% "Non-survivor", "Non-survivor", "1"
    ), na.rm = TRUE)
  }
  rt2 <- prognosis_apply_outcome_landmark(rt, ctx$config)
  n_ev_after <- sum(as.integer(rt2[[event_var]]) == 1L, na.rm = TRUE)

  ctx$data$imputed <- rt2
  if (!is.null(ctx$data$cleaned)) ctx$data$cleaned <- rt2
  ctx$results$prognosis_outcome_landmark <- list(
    landmark_days = landmark_days,
    n = nrow(rt2),
    n_event_before = n_ev_before,
    n_event_after = n_ev_after
  )

  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success(
      "prognosis_outcome_landmark: {landmark_days}-day 截尾完成 (events {n_ev_before} -> {n_ev_after}, n={nrow(rt2)})"
    )
  }
  ctx
}

register_block(
  "prognosis_outcome_landmark",
  block_prognosis_outcome_landmark,
  "28-day admin censor on futime/fustatus after imputation"
)
