###############################################################################
# kmeans_trajectory_panels — unit 级 Fig2 草稿面板
# 发表定稿 Fig2 = A elbow | B scatter+hull | C mean±SE，由
#   ckm_stroke_fig2_abc() / run/.../rebuild_publication.R 写出合并图。
# 本 block 仍写分面板草稿供 QC；finalize 后以 summary 合并图为准。
###############################################################################

block_kmeans_trajectory_panels <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_ckm_cum_egdr.R"), local = FALSE)
  pub_helper <- file.path(root, "R/cum_egdr_kmeans_pub.R")
  if (file.exists(pub_helper)) source(pub_helper, local = FALSE)
  bl <- ctx$config$cum_egdr_kmeans %||% list()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !ckm_stroke_is_full_depth(idx, bl)) {
    ctx$results$kmeans_trajectory_panels <- list(skipped = TRUE)
    return(ctx)
  }
  if (!all(c("eGDR_Class", "eGDR_t1", "eGDR_t2") %in% names(data))) {
    cli::cli_alert_warning("缺 Class/eGDR 两波列，跳过轨迹面板")
    return(ctx)
  }
  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "by_index", idx, "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  if (exists("ckm_stroke_fig2_abc", mode = "function") &&
      exists("ckm_stroke_class_map_paper", mode = "function")) {
    cmap <- ckm_stroke_class_map_paper()
    d2 <- ckm_stroke_attach_class_paper(data, "eGDR_Class", cmap)
    elbow_csv <- file.path(
      ctx$config$project$output_dir %||% "Output", "by_index", idx, "Tables",
      "Kmeans_elbow_WCSS.csv"
    )
    tryCatch({
      ckm_stroke_fig2_abc(
        d2, elbow_csv = if (file.exists(elbow_csv)) elbow_csv else NULL,
        outfile = file.path(out_dir, "Figure 2. eGDR change patterns.pdf"),
        cmap = cmap
      )
      cli::cli_alert_success("Fig.2 combined (A|B|C) via ckm_stroke_fig2_abc")
    }, error = function(e) cli::cli_alert_warning("Fig2 combined: {e$message}"))
  }

  agg <- stats::aggregate(
    cbind(eGDR_t1, eGDR_t2) ~ eGDR_Class,
    data = data.frame(
      eGDR_Class = data$eGDR_Class,
      eGDR_t1 = as.numeric(data$eGDR_t1),
      eGDR_t2 = as.numeric(data$eGDR_t2)
    ),
    FUN = mean, na.rm = TRUE
  )

  pdf(file.path(out_dir, "Figure 2B. Mean eGDR trajectories by class.pdf"), width = 6, height = 4.5)
  plot(NA, xlim = c(1, 2), ylim = range(c(agg$eGDR_t1, agg$eGDR_t2), na.rm = TRUE),
       xlab = "Wave", ylab = "Mean eGDR", xaxt = "n", main = "eGDR trajectories (draft)")
  axis(1, at = c(1, 2), labels = c("2012", "2015"))
  cols <- c("#2CA02C", "#D62728", "#1F77B4", "#9467BD")
  for (i in seq_len(nrow(agg))) {
    lines(c(1, 2), c(agg$eGDR_t1[i], agg$eGDR_t2[i]), col = cols[((i - 1L) %% 4) + 1L], lwd = 2)
    points(c(1, 2), c(agg$eGDR_t1[i], agg$eGDR_t2[i]), col = cols[((i - 1L) %% 4) + 1L], pch = 16)
  }
  legend("topright", legend = as.character(agg$eGDR_Class), col = cols[seq_len(nrow(agg))], lwd = 2, cex = 0.8)
  dev.off()

  pdf(file.path(out_dir, "Figure 2C. eGDR distribution by class.pdf"), width = 7, height = 4.5)
  op <- par(mfrow = c(1, 2))
  boxplot(as.numeric(data$eGDR_t1) ~ data$eGDR_Class, main = "2012", xlab = "", ylab = "eGDR", las = 2, cex.axis = 0.7)
  boxplot(as.numeric(data$eGDR_t2) ~ data$eGDR_Class, main = "2015", xlab = "", ylab = "eGDR", las = 2, cex.axis = 0.7)
  par(op)
  dev.off()

  ctx$results$kmeans_trajectory_panels <- list(means = agg)
  cli::cli_alert_success("Fig.2 draft panels written; publication Fig2 via rebuild_publication.R")
  ctx
}

register_block("kmeans_trajectory_panels", block_kmeans_trajectory_panels, "kmeans轨迹与分布面板")
