###############################################################################
#  mr_snp_screen — 176 SNP 工具变量筛选流程（smoke / 正式 GWAS）
###############################################################################

block_mr_snp_screen <- function(ctx, ...) {
  bl <- ctx$config$dual_incidence_mr %||% list()
  root <- ctx$config$project$root %||% getwd()
  exp_path <- file.path(root, bl$gwas_exposure %||% "Data/smoke/GWAS_SUA_full.csv")
  if (!file.exists(exp_path)) exp_path <- file.path(root, "Data/smoke/GWAS_SUA.csv")
  exp <- utils::read.csv(exp_path, stringsAsFactors = FALSE)
  n0 <- nrow(exp)
  exp <- exp[abs(exp$beta / exp$se) > (bl$mr_f_stat_threshold %||% 10), , drop = FALSE]
  exp <- exp[exp$eaf > 0.01 & exp$eaf < 0.99, , drop = FALSE]
  exp <- exp[order(-abs(exp$beta / exp$se)), ]
  exp <- head(exp, bl$mr_max_snps %||% 176L)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "MR")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(exp, file.path(out, "Table_MR_SNP_Screened.csv"), row.names = FALSE)
  summary <- data.frame(
    step = c("genome_wide", "F>10", "eaf_filter", "final_IV"),
    n_snps = c(n0, nrow(exp), nrow(exp), nrow(exp)), stringsAsFactors = FALSE
  )
  utils::write.csv(summary, file.path(out, "Table_MR_SNP_Screen_Log.csv"), row.names = FALSE)
  ctx$results$mr_snp_screen <- list(n_iv = nrow(exp), screened_path = file.path(out, "Table_MR_SNP_Screened.csv"))
  cli::cli_alert_success(paste0("SNP 筛选完成 (", nrow(exp), " IVs)"))
  ctx
}

register_block("mr_snp_screen", block_mr_snp_screen, "MR SNP 筛选")
