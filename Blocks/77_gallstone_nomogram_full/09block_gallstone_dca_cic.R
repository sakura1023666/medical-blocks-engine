###############################################################################
# gallstone_dca_cic — Fig8 DCA + Fig9 CIC（train / val / bootstrap）
###############################################################################

block_gallstone_dca_cic <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  rr <- ctx$results$gallstone_roc_cal_boot
  if (is.null(rr)) stop("dca_cic: 需先跑 gallstone_roc_cal_boot", call. = FALSE)

  .nb <- function(y, p, thr) {
    # net benefit
    tp <- mean(p > thr & y == 1)
    fp <- mean(p > thr & y == 0)
    prev <- mean(y == 1)
    nb_model <- tp - fp * (thr / (1 - thr))
    nb_all <- prev - (1 - prev) * (thr / (1 - thr))
    c(model = nb_model, all = nb_all, none = 0)
  }
  .dca_df <- function(y, p, thrs = seq(0.05, 0.8, by = 0.01)) {
    do.call(rbind, lapply(thrs, function(t) {
      v <- .nb(y, p, t)
      data.frame(thr = t, nb_model = v["model"], nb_all = v["all"], nb_none = 0)
    }))
  }
  .cic_df <- function(y, p, thrs = seq(0.05, 0.8, by = 0.01), N = 1000) {
    do.call(rbind, lapply(thrs, function(t) {
      high <- p > t
      data.frame(
        thr = t,
        n_high = sum(high) / length(p) * N,
        n_true = sum(high & y == 1) / length(p) * N
      )
    }))
  }

  panels <- list(
    train = list(y = rr$y_train, p = rr$p_train),
    val = list(y = rr$y_val, p = rr$p_val),
    boot = list(y = rr$y_full, p = rr$p_boot)
  )
  dirs <- gallstone_nomogram_out_dirs(ctx, "ALL")
  gallstone_nomogram_ensure_dirs(list(dirs$shared_figures, file.path(dirs$project, "Figures")))

  pdf(file.path(dirs$shared_figures, "Figure 8. DCA.pdf"), width = 12, height = 4)
  par(mfrow = c(1, 3))
  labs <- c(train = "A. DCA train", val = "B. DCA internal val", boot = "C. DCA bootstrap")
  for (nm in names(panels)) {
    dd <- .dca_df(panels[[nm]]$y, panels[[nm]]$p)
    plot(dd$thr, dd$nb_model, type = "l", col = "steelblue", lwd = 2,
         ylim = range(c(dd$nb_model, dd$nb_all, 0), finite = TRUE),
         xlab = "Threshold", ylab = "Net benefit", main = labs[[nm]])
    lines(dd$thr, dd$nb_all, col = "grey40", lty = 2)
    abline(h = 0, col = "black")
    legend("topright", c("Model", "Treat all", "Treat none"),
           col = c("steelblue", "grey40", "black"), lty = c(1, 2, 1), bty = "n", cex = 0.8)
  }
  dev.off()
  file.copy(file.path(dirs$shared_figures, "Figure 8. DCA.pdf"),
            file.path(dirs$project, "Figures", "Figure 8. DCA.pdf"), overwrite = TRUE)

  pdf(file.path(dirs$shared_figures, "Figure 9. CIC.pdf"), width = 12, height = 4)
  par(mfrow = c(1, 3))
  labs2 <- c(train = "A. CIC train", val = "B. CIC internal val", boot = "C. CIC bootstrap")
  for (nm in names(panels)) {
    cc <- .cic_df(panels[[nm]]$y, panels[[nm]]$p)
    plot(cc$thr, cc$n_high, type = "l", col = "darkorange", lwd = 2,
         ylim = c(0, max(cc$n_high, na.rm = TRUE)),
         xlab = "Threshold", ylab = "Number per 1000", main = labs2[[nm]])
    lines(cc$thr, cc$n_true, col = "steelblue", lwd = 2)
    legend("topright", c("High risk", "True positive"),
           col = c("darkorange", "steelblue"), lty = 1, bty = "n", cex = 0.8)
  }
  dev.off()
  file.copy(file.path(dirs$shared_figures, "Figure 9. CIC.pdf"),
            file.path(dirs$project, "Figures", "Figure 9. CIC.pdf"), overwrite = TRUE)

  ctx$results$gallstone_dca_cic <- list(ok = TRUE)
  cli::cli_alert_success("Fig8-9 DCA + CIC")
  ctx
}

register_block("gallstone_dca_cic", block_gallstone_dca_cic, "胆结石Fig8 DCA + Fig9 CIC")
