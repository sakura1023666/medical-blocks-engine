###############################################################################
#  multimorbidity_empirical_transition — Stability/Progression/Regression + GEE
###############################################################################

block_multimorbidity_empirical_transition <- function(ctx, ...) {
  mm <- ctx$config$multimorbidity %||% list()
  bl <- ctx$config$multimorbidity_gee %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("multimorbidity_empirical_transition: 无数据", call. = FALSE)

  cat_col <- as.character(mm$category_col %||% "Multimorbidity_cat")[1L]
  id_col <- as.character(mm$id_col %||% ctx$config$data$id_column %||% "ID")[1L]
  wave_col <- as.character(mm$wave_col %||% "Followup_wave")[1L]
  w0 <- mm$baseline_wave %||% min(as.integer(data[[wave_col]]), na.rm = TRUE)
  w1 <- mm$outcome_wave %||% max(as.integer(data[[wave_col]]), na.rm = TRUE)
  trans_col <- as.character(mm$empirical_transition_col %||% "Empirical_transition")[1L]

  rank_map <- c(Neither = 0, Depression_alone = 1, Obesity_alone = 1, Comorbidity = 2)
  a <- data[as.integer(data[[wave_col]]) == as.integer(w0), c(id_col, cat_col)]
  b <- data[as.integer(data[[wave_col]]) == as.integer(w1), c(id_col, cat_col)]
  names(a) <- c(id_col, "from"); names(b) <- c(id_col, "to")
  ab <- merge(a, b, by = id_col)
  ab$r0 <- unname(rank_map[as.character(ab$from)])
  ab$r1 <- unname(rank_map[as.character(ab$to)])
  ab[[trans_col]] <- factor(
    ifelse(is.na(ab$r0) | is.na(ab$r1), NA_character_,
           ifelse(ab$r1 == ab$r0, "Stability",
                  ifelse(ab$r1 > ab$r0, "Progression", "Regression"))),
    levels = c("Stability", "Progression", "Regression")
  )
  data <- merge(data, ab[, c(id_col, trans_col)], by = id_col, all.x = TRUE)

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    as.data.frame(table(ab[[trans_col]])),
    file.path(out_dir, "Table_S_Empirical_Transition_Counts.csv"),
    row.names = FALSE
  )

  # GEE on transition (person-level: use baseline row + outcome)
  if (requireNamespace("geepack", quietly = TRUE)) {
    suppressPackageStartupMessages(library(geepack))
    out_col <- as.character(bl$outcome_col %||% bl$cognition_col %||% "Cognition_z")[1L]
    time_col <- as.character(bl$time_col %||% wave_col)[1L]
    d2 <- data[!is.na(data[[trans_col]]) & !is.na(data[[out_col]]), , drop = FALSE]
    if (nrow(d2) >= 30L && out_col %in% names(d2)) {
      d2[[trans_col]] <- stats::relevel(factor(as.character(d2[[trans_col]])), ref = "Stability")
      form <- stats::as.formula(paste(out_col, "~", trans_col, "+", time_col))
      fit <- tryCatch(
        geepack::geeglm(form, data = d2, id = d2[[id_col]], family = gaussian(), corstr = "exchangeable"),
        error = function(e) NULL
      )
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        utils::write.csv(
          data.frame(term = rownames(sm), beta = sm[, "Estimate"], p = sm[, "Pr(>|W|)"]),
          file.path(out_dir, "Table_S_GEE_Empirical_Transition.csv"),
          row.names = FALSE
        )
      }
    }
  }

  ctx$data$imputed <- data
  ctx$data$cleaned <- data
  ctx$results$multimorbidity_empirical <- list(col = trans_col)
  cli::cli_alert_success("经验转移分组完成")
  ctx
}

register_block(
  "multimorbidity_empirical_transition",
  block_multimorbidity_empirical_transition,
  "经验 Stability/Progression/Regression"
)
