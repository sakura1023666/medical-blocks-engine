###############################################################################
#  mr_twosample — 两样本孟德尔随机化（TwoSampleMR 或 smoke IVW）
###############################################################################

block_mr_twosample <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  root <- ctx$config$project$root %||% getwd()
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "MR")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  outcomes <- bl$mr_outcomes %||% c("CVD", "CKD", "Diabetes")
  rows <- list()
  for (oc in outcomes) {
    exp_path <- file.path(root, bl$gwas_exposure %||% "Data/smoke/GWAS_SUA.csv")
    out_path <- file.path(root, sprintf("Data/smoke/GWAS_%s.csv", oc))
  if (!file.exists(exp_path) || !file.exists(out_path)) next
    exp <- utils::read.csv(exp_path, stringsAsFactors = FALSE)
    outg <- utils::read.csv(out_path, stringsAsFactors = FALSE)
    merged <- merge(exp, outg, by = "SNP", suffixes = c("_exp", "_out"))
    if (!nrow(merged)) next
    b <- merged$beta_exp; bout <- merged$beta_out; sout <- merged$se_out
    if (!all(c("beta_exp", "beta_out", "se_out") %in% names(merged))) next
    ivw <- sum(b * bout / sout^2) / sum(b^2 / sout^2)
    se_ivw <- sqrt(1 / sum(b^2 / sout^2))
    rows[[length(rows) + 1L]] <- data.frame(
      exposure = "SUA", outcome = oc, method = "IVW",
      beta = round(ivw, 4), se = round(se_ivw, 4),
      p = signif(2 * stats::pnorm(-abs(ivw / se_ivw)), 3),
      n_snps = nrow(merged), stringsAsFactors = FALSE
    )
  }
  tab <- if (length(rows)) do.call(rbind, rows) else data.frame(note = "no MR data")
  utils::write.csv(tab, file.path(out, "Table_MR_IVW_Results.csv"), row.names = FALSE)
  ctx$results$mr_twosample <- list(table = tab, output_dir = out)
  cli::cli_alert_success("两样本 MR IVW 完成")
  ctx
}

register_block("mr_twosample", block_mr_twosample, "两样本 MR")
