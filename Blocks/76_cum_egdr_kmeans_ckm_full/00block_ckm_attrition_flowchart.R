###############################################################################
# ckm_attrition_flowchart — Fig.1 纳排（本口径 17708→4983）
###############################################################################

block_ckm_attrition_flowchart <- function(ctx, ...) {
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  # shared 层可能尚未有 by_index；优先写到 project 根与 by_index/eGDR
  roots <- unique(c(
    file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx),
    ctx$config$project$output_dir %||% "Output"
  ))

  # 优先读全队列 17708 逐步标志；否则用固定本口径人数
  path17708 <- bl$attrition_csv %||% sub("4d_.*", "4_数据集_17708.csv",
                                         bl$data_csv %||% ctx$config$data$rawdata_path %||% "")
  steps <- NULL
  if (nzchar(path17708) && file.exists(path17708)) {
    raw <- tryCatch(
      utils::read.csv(path17708, stringsAsFactors = FALSE, check.names = FALSE,
                      fileEncoding = "UTF-8-BOM"),
      error = function(e) NULL
    )
    if (!is.null(raw) && all(c("ex_E1", "ex_E2", "ex_E3", "ex_E4", "cohort_final") %in% names(raw))) {
      n0 <- nrow(raw)
      keep <- rep(TRUE, n0)
      e1 <- as.integer(raw$ex_E1) == 1L
      n_e1 <- sum(keep & e1); keep[e1] <- FALSE; n1 <- sum(keep)
      e2 <- as.integer(raw$ex_E2) == 1L
      n_e2 <- sum(keep & e2); keep[e2] <- FALSE; n2 <- sum(keep)
      e3 <- as.integer(raw$ex_E3) == 1L
      n_e3 <- sum(keep & e3); keep[e3] <- FALSE; n3 <- sum(keep)
      e4 <- as.integer(raw$ex_E4) == 1L
      n_e4 <- sum(keep & e4); keep[e4] <- FALSE; n4 <- sum(keep)
      lab <- bl$attrition_labels %||% list()
      steps <- data.frame(
        step = c("N0", "After_E1", "After_E2", "After_E3", "After_E4"),
        label = c(
          lab$n0 %||% "CHARLS wave1 adults",
          lab$e1 %||% "CKM staging complete",
          lab$e2 %||% "No prior stroke / known stroke status",
          lab$e3 %||% "2018 stroke outcome available",
          lab$e4 %||% "Complete two-wave eGDR components"
        ),
        n_remain = c(n0, n1, n2, n3, n4),
        n_exclude = c(NA_integer_, n_e1, n_e2, n_e3, n_e4),
        exclude_label = c(
          NA_character_,
          lab$ex1 %||% "Incomplete CKM staging inputs",
          lab$ex2 %||% "Prior stroke or missing stroke history",
          lab$ex3 %||% "Missing 2018 stroke outcome",
          lab$ex4 %||% "Incomplete eGDR components (wave1/3)"
        ),
        stringsAsFactors = FALSE
      )
    }
  }
  if (is.null(steps)) {
    # 交付文档本口径固定人数
    steps <- data.frame(
      step = c("N0", "After_E1", "After_E2", "After_E3", "After_E4"),
      label = c(
        "CHARLS wave1 adults",
        "CKM staging complete",
        "No prior stroke / known stroke status",
        "2018 stroke outcome available",
        "Complete two-wave eGDR components"
      ),
      n_remain = c(17708L, 9350L, 7546L, 6837L, 4983L),
      n_exclude = c(NA_integer_, 8358L, 1804L, 709L, 1854L),
      exclude_label = c(
        NA_character_,
        "Incomplete CKM staging inputs",
        "Prior stroke or missing stroke history",
        "Missing 2018 stroke outcome",
        "Incomplete eGDR components (wave1/3)"
      ),
      stringsAsFactors = FALSE
    )
  }

  for (out_root in roots) {
    tab_dir <- file.path(out_root, "Tables")
    fig_dir <- file.path(out_root, "Figures")
    dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(steps, file.path(tab_dir, "Flowchart_attrition.csv"),
                     row.names = FALSE)

    db_lab <- ctx$config$project$database %||% "cohort"
    pdf(file.path(fig_dir, "Figure 1. Inclusion exclusion flowchart.pdf"),
        width = 8.5, height = 10)
    op <- par(mar = c(1, 1, 2, 1))
    plot.new()
    title(sprintf("Figure 1. Study flowchart (%s)", db_lab), cex.main = 1)
    y <- 0.92
    for (i in seq_len(nrow(steps))) {
      rect(0.25, y - 0.06, 0.75, y, border = "black", col = "white")
      text(0.5, y - 0.03, sprintf("%s\n(n = %s)", steps$label[i],
                                  format(steps$n_remain[i], big.mark = ",")),
           cex = 0.85)
      if (i < nrow(steps)) {
        arrows(0.5, y - 0.06, 0.5, y - 0.10, length = 0.08)
        if (!is.na(steps$n_exclude[i + 1L])) {
          text(0.82, y - 0.08,
               sprintf("Exclude: %s\n(n = %s)",
                       steps$exclude_label[i + 1L],
                       format(steps$n_exclude[i + 1L], big.mark = ",")),
               cex = 0.65, adj = 0)
        }
        y <- y - 0.16
      }
    }
    mtext("Footnote: denominator follows project construction (N=4,983), not exact paper replication.",
          side = 1, cex = 0.65, line = -1)
    par(op)
    dev.off()
  }

  ctx$results$ckm_attrition_flowchart <- list(steps = steps)
  cli::cli_alert_success("Fig.1 纳排已写出 (final n={steps$n_remain[nrow(steps)]})")
  ctx
}

register_block("ckm_attrition_flowchart", block_ckm_attrition_flowchart, "CKM卒中纳排流程图")
