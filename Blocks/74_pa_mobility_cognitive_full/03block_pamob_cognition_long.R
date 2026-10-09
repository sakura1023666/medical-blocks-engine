###############################################################################
# pamob_cognition_long — 认知长表质控与导出分析用 CSV
###############################################################################

block_pamob_cognition_long <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  long <- ctx$data$pamob_charls_long
  if (is.null(long) || !nrow(long)) stop("pamob_cognition_long: 请先 pamob_assemble_charls", call. = FALSE)

  tab <- as.data.frame(table(wave = long$wave, phenotype = as.character(long$phenotype)),
                       stringsAsFactors = FALSE)
  names(tab)[3] <- "n"
  desc <- data.frame(
    wave = sort(unique(long$wave)),
    n = as.integer(table(long$wave)[as.character(sort(unique(long$wave)))]),
    mean_global = tapply(long$Global_cognition, long$wave, mean, na.rm = TRUE)[as.character(sort(unique(long$wave)))],
    mean_em = tapply(long$Episodic_memory, long$wave, mean, na.rm = TRUE)[as.character(sort(unique(long$wave)))],
    stringsAsFactors = FALSE
  )
  out <- pamob_tables_dir(ctx, "CHARLS")
  pamob_write_csv(tab, file.path(out, "Table_Pamob_Cognition_by_Wave_Phenotype.csv"))
  pamob_write_csv(desc, file.path(out, "Table_Pamob_Cognition_Wave_Means.csv"))
  pamob_write_csv(long, file.path(out, "Analysis_CHARLS_Long.csv"))

  ctx$results$pamob_cognition_long <- list(n = nrow(long), output_dir = out)
  cli::cli_alert_success("pamob_cognition_long: 已导出分析长表")
  ctx
}

register_block("pamob_cognition_long", block_pamob_cognition_long, "CHARLS 认知长表质控")
