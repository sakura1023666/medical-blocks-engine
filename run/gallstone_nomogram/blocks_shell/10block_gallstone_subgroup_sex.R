###############################################################################
# gallstone_subgroup_sex — 亚组敏感性（至少 Sex；连续暴露=当前 unit）
###############################################################################

block_gallstone_subgroup_sex <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  expose <- as.character(ctx$config$incidence$index_var %||% "")[1L]
  data <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Success"
  if (!nzchar(expose) || is.null(data) || !expose %in% names(data)) return(ctx)
  if (!"Sex" %in% names(data)) {
    cli::cli_alert_warning("subgroup: 无 Sex 列")
    return(ctx)
  }
  rows <- list()
  for (lv in levels(factor(data$Sex))) {
    d <- data[as.character(data$Sex) == lv, , drop = FALSE]
    rr <- gallstone_nomogram_fit_or_row(d, expose, outcome, character(0))
    if (!is.null(rr)) {
      rr$subgroup <- "Sex"; rr$level <- lv; rr$n <- nrow(d)
      rows[[length(rows) + 1L]] <- rr
    }
  }
  # Age binary 65
  if ("Age" %in% names(data)) {
    ag <- ifelse(as.numeric(data$Age) >= 65, ">=65", "<65")
    for (lv in unique(ag)) {
      d <- data[ag == lv, , drop = FALSE]
      rr <- gallstone_nomogram_fit_or_row(d, expose, outcome, character(0))
      if (!is.null(rr)) {
        rr$subgroup <- "Age_Group"; rr$level <- lv; rr$n <- nrow(d)
        rows[[length(rows) + 1L]] <- rr
      }
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame()
  dirs <- gallstone_nomogram_out_dirs(ctx, expose)
  gallstone_nomogram_ensure_dirs(dirs)
  utils::write.csv(tab, file.path(dirs$tables, "Table_subgroup_OR.csv"), row.names = FALSE)
  if (nrow(tab)) {
    pdf(file.path(dirs$figures, sprintf("Figure S. Subgroup %s.pdf", expose)), width = 7, height = 5)
    op <- par(mar = c(5, 10, 3, 2))
    ys <- seq_len(nrow(tab))
    labs <- paste(tab$subgroup, tab$level, sep = ": ")
    plot(tab$OR, ys, pch = 16, xlim = range(c(tab$CI_low, tab$CI_high, 1), finite = TRUE),
         yaxt = "n", xlab = "OR", ylab = "", main = sprintf("Subgroup OR: %s", expose))
    axis(2, at = ys, labels = labs, las = 1, cex.axis = 0.7)
    arrows(tab$CI_low, ys, tab$CI_high, ys, angle = 90, code = 3, length = 0.04)
    abline(v = 1, lty = 2, col = "grey40")
    par(op); dev.off()
  }
  ctx$results$gallstone_subgroup_sex <- tab
  cli::cli_alert_success("Subgroup: {expose} rows={nrow(tab)}")
  ctx
}

register_block("gallstone_subgroup_sex", block_gallstone_subgroup_sex, "胆结石Sex/Age亚组")
