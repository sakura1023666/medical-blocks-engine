###############################################################################
#  cits_publication_tables — Table 2 + Supplement A1-A5 风格汇总
###############################################################################

block_cits_publication_tables <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/cdc_wonder_cits_utils.R"), local = FALSE)
  coef <- (ctx$results$cits_model_full %||% list())$coefficients
  did <- (ctx$results$cits_model_full %||% list())$did
  sens <- ctx$results$cits_sensitivity_extended

  if (is.null(coef)) {
    p1 <- file.path(ctx$config$project$output_dir, "Tables", "Table_CITS_Full_Model_Coefficients.csv")
    if (file.exists(p1)) coef <- utils::read.csv(p1, stringsAsFactors = FALSE)
  }
  if (is.null(did)) {
    p2 <- file.path(ctx$config$project$output_dir, "Tables", "Table_CITS_DID_Change_per10k.csv")
    if (file.exists(p2)) did <- utils::read.csv(p2, stringsAsFactors = FALSE)
  }

  table2 <- if (!is.null(did) && nrow(did)) did else data.frame()
  supp <- list(
    Table_A1_coefficients = coef,
    Table_A2_DID = did,
    Table_A3_sensitivity = if (is.data.frame(sens)) sens else data.frame(),
    Table_A4_state_ban_list = data.frame(
      category = c("Ban_default", "Total_ban", "Protected"),
      n_states = c(length(.cits_ban_states_default()$ban), length(.cits_total_ban_states()), length(.cits_protected_states())),
      stringsAsFactors = FALSE
    )
  )

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Publication")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(table2, file.path(out_dir, "Table2_CITS_Main_Outcomes.csv"), row.names = FALSE)
  for (nm in names(supp)) {
    if (is.data.frame(supp[[nm]]) && nrow(supp[[nm]])) {
      utils::write.csv(supp[[nm]], file.path(out_dir, paste0(nm, ".csv")), row.names = FALSE)
    }
  }

  ctx$results$cits_publication_tables <- supp
  cli::cli_alert_success("CITS 发表表（Table2 + Supp A1-A5 风格）完成")
  ctx
}

register_block("cits_publication_tables", block_cits_publication_tables, "CITS 发表表汇总")
