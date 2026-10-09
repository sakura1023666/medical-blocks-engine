###############################################################################
# gallstone_table1 — Table 1 按 Success 分组基线
###############################################################################

block_gallstone_table1 <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  d <- ctx$data$imputed %||% ctx$data$cleaned
  outcome <- ctx$config$data$outcome_column %||% "Success"
  if (is.null(d) || !outcome %in% names(d)) stop("table1: 无数据/结局", call. = FALSE)
  vars <- unique(c(
    gallstone_nomogram_cat_features(ctx$config),
    gallstone_nomogram_cont_features(ctx$config)
  ))
  vars <- vars[vars %in% names(d)]
  y <- d[[outcome]]
  if (!is.factor(y)) y <- factor(ifelse(as.integer(y) == 1L, "Yes", "No"))
  rows <- list()
  for (v in vars) {
    x <- d[[v]]
    if (is.numeric(x) && !is.factor(x)) {
      for (lv in levels(y)) {
        xi <- x[y == lv]
        rows[[length(rows) + 1L]] <- data.frame(
          variable = v, level = as.character(lv),
          summary = sprintf("%.2f \u00b1 %.2f", mean(xi, na.rm = TRUE), stats::sd(xi, na.rm = TRUE)),
          n = sum(is.finite(xi)), stringsAsFactors = FALSE
        )
      }
      p <- tryCatch(stats::wilcox.test(x ~ y)$p.value, error = function(e) NA_real_)
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, level = "P", summary = sprintf("%.3f", p), n = NA_integer_,
        stringsAsFactors = FALSE
      )
    } else {
      x <- factor(x)
      tab <- table(x, y)
      for (lv in levels(x)) {
        for (yy in levels(y)) {
          n <- as.integer(tab[lv, yy] %||% 0L)
          den <- sum(y == yy)
          rows[[length(rows) + 1L]] <- data.frame(
            variable = v, level = paste(lv, yy, sep = "|"),
            summary = sprintf("%d (%.1f%%)", n, 100 * n / max(den, 1)),
            n = n, stringsAsFactors = FALSE
          )
        }
      }
      p <- tryCatch(stats::chisq.test(tab)$p.value, error = function(e) NA_real_)
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, level = "P", summary = sprintf("%.3f", p), n = NA_integer_,
        stringsAsFactors = FALSE
      )
    }
  }
  tab <- do.call(rbind, rows)
  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(dirs$shared_tables, file.path(dirs$project, "Tables")))
  for (td in unique(c(dirs$shared_tables, file.path(dirs$project, "Tables")))) {
    utils::write.csv(tab, file.path(td, "Table 1. Baseline by Success.csv"), row.names = FALSE)
  }
  ctx$results$gallstone_table1 <- tab
  cli::cli_alert_success("Table 1 baseline: {length(vars)} vars")
  ctx
}

register_block("gallstone_table1", block_gallstone_table1, "胆结石Table1按Success基线")
