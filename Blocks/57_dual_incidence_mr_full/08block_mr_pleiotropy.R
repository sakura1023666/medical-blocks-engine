###############################################################################
#  mr_pleiotropy — 多效性/异质性检验（Cochran Q、I2）
###############################################################################

block_mr_pleiotropy <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  root <- ctx$config$project$root %||% getwd()
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "MR")
  egger_path <- file.path(out, "Table_MR_Egger_PRESSO.csv")
  if (file.exists(egger_path)) {
    tab <- utils::read.csv(egger_path, stringsAsFactors = FALSE)
  } else {
    iv <- utils::read.csv(file.path(out, "Table_MR_SNP_Screened.csv"), stringsAsFactors = FALSE)
    w <- (iv$beta / iv$se)^2
    Q <- sum(w * (iv$beta - weighted.mean(iv$beta, w))^2 / iv$se^2)
    df <- max(1L, nrow(iv) - 1L)
    tab <- data.frame(
      outcome = "SUA", method = "Cochran_Q",
      Q = round(Q, 3), df = df, p_heterogeneity = signif(stats::pchisq(Q, df, lower.tail = FALSE), 3),
      I2 = round(max(0, (Q - df) / Q) * 100, 1), stringsAsFactors = FALSE
    )
  }
  utils::write.csv(tab, file.path(out, "Table_MR_Pleiotropy_Heterogeneity.csv"), row.names = FALSE)
  ctx$results$mr_pleiotropy <- list(table = tab)
  cli::cli_alert_success("多效性/异质性检验完成")
  ctx
}

register_block("mr_pleiotropy", block_mr_pleiotropy, "MR 多效性")
