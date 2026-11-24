###############################################################################
#  sem_descriptive — 基线特征表（按肌少症分层）
#  文献: Zhu 2025 J Adv Research
###############################################################################

.sem_ctx_data <- function(ctx) {
  ctx$data$cleaned %||% ctx$data$imputed %||% ctx$data$raw
}

.sem_desc_row <- function(x, label) {
  if (is.numeric(x)) {
    data.frame(
      variable = label,
      overall = sprintf("%.2f (%.2f)", mean(x, na.rm = TRUE), stats::sd(x, na.rm = TRUE)),
      stringsAsFactors = FALSE
    )
  } else {
    tab <- table(x, useNA = "ifany")
    data.frame(
      variable = paste0(label, ": ", names(tab)),
      overall = as.integer(tab),
      stringsAsFactors = FALSE
    )
  }
}

block_sem_descriptive <- function(ctx, ...) {
  bl <- ctx$config$sem_chain %||% list()
  data <- .sem_ctx_data(ctx)
  if (is.null(data)) stop("sem_descriptive: 无数据", call. = FALSE)

  strata_col <- bl$exposure_var %||% "Sarcopenia"
  if (!strata_col %in% names(data)) {
    cli::cli_alert_warning("sem_descriptive: 缺少分层列 {strata_col}，跳过")
    return(ctx)
  }

  desc_vars <- bl$descriptive_vars %||% c(
    "Age", "Gender", "Depression_score", "Depression", "Cognitive_score",
    "Grip_strength", "SMI", "Gait_speed", bl$event_var %||% "Frailty_event"
  )
  desc_vars <- unique(intersect(desc_vars, names(data)))

  strata <- data[[strata_col]]
  if (is.numeric(strata)) {
    strata_lbl <- ifelse(strata == 1L, "Sarcopenia", "Non_sarcopenia")
  } else {
    strata_lbl <- as.character(strata)
  }

  rows <- list()
  for (v in desc_vars) {
    for (i in seq_along(unique(strata_lbl))) {
      lv <- unique(strata_lbl)[i]
      sub <- data[strata_lbl == lv, v, drop = TRUE]
      if (is.numeric(sub)) {
        val <- sprintf("%.2f (%.2f)", mean(sub, na.rm = TRUE), stats::sd(sub, na.rm = TRUE))
      } else {
        val <- paste(names(table(sub)), table(sub), sep = "=", collapse = "; ")
      }
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, stratum = lv, summary = val, n = sum(strata_lbl == lv, na.rm = TRUE),
        stringsAsFactors = FALSE
      )
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no variables")

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_SEM_Baseline_by_Sarcopenia.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(tab, out, row.names = FALSE)

  ctx$results$sem_descriptive <- list(table = tab, n = nrow(data))
  cli::cli_alert_success("基线描述表完成 (按肌少症分层)")
  ctx
}

register_block("sem_descriptive", block_sem_descriptive, "肌少症分层基线表")
