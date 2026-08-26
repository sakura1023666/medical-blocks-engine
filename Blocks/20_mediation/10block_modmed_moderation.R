###############################################################################
#  modmed_moderation — Yan2026 步5–6：Age/BMI/Gender 调节检验
#
#  register_block: "modmed_moderation"
###############################################################################

block_modmed_moderation <- function(ctx, ...) {
  root <- ctx$root %||% getwd()
  source(file.path(root, "R/moderated_mediation_process.R"), local = FALSE)

  cfg <- ctx$config
  bl <- cfg$modmed_moderation %||% cfg$modmed %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("modmed_moderation: 无数据", call. = FALSE)

  outcome <- bl$outcome %||% cfg$modmed$outcome %||% "Group_bin"
  moderators <- bl$moderators %||% cfg$modmed$moderators %||% c("Age", "BMI", "Gender")
  # Gender 用数值版更稳
  moderators <- vapply(moderators, function(w) {
    if (identical(w, "Gender") && "Gender_num" %in% names(data)) "Gender_num" else w
  }, character(1))

  pairs <- ctx$results$modmed_significant_pairs
  if (is.null(pairs) || !nrow(pairs)) {
    # 允许 config 强制指定（冒烟）
    pairs <- bl$force_pairs %||% NULL
    if (is.null(pairs)) {
      cli::cli_alert_warning("无显著中介对，跳过调节")
      ctx$results$modmed_moderation_table <- data.frame()
      return(ctx)
    }
  }

  rows <- list()
  for (i in seq_len(nrow(pairs))) {
    x <- as.character(pairs$exposure[i])
    m <- as.character(pairs$mediator[i])
    for (w in moderators) {
      if (!all(c(x, m, outcome, w) %in% names(data))) next
      one <- tryCatch(
        modmed_moderation_tests(data, x, m, outcome, w),
        error = function(e) {
          cli::cli_alert_warning("{x}/{m}/{w}: {e$message}")
          NULL
        }
      )
      if (!is.null(one)) rows[[length(rows) + 1L]] <- one
    }
  }

  tab <- if (length(rows)) do.call(rbind, rows) else data.frame()
  sig <- if (nrow(tab)) tab[tab$significant %in% TRUE, , drop = FALSE] else tab

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  modmed_write_csv(tab, file.path(tbl_dir, "Table_Moderation.csv"))
  modmed_write_csv(sig, file.path(tbl_dir, "Table_Moderation_Significant.csv"))

  ctx$results$modmed_moderation_table <- tab
  ctx$results$modmed_moderation_significant <- sig
  cli::cli_alert_success("调节检验: {nrow(tab)} 行，显著交互 {nrow(sig)}")
  ctx
}

register_block("modmed_moderation", block_modmed_moderation, "OA Yan2026: 调节效应")
