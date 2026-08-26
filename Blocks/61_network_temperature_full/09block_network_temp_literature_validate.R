###############################################################################
#  network_temp_literature_validate — 性别分层 mixed model 系数与 Grimes 2025 对照
###############################################################################

block_network_temp_literature_validate <- function(ctx, ...) {
  bl <- ctx$config$network_temperature %||% list()
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_validation.R"), local = FALSE)
  out_base <- literature_batch_output_base(ctx)

  targets <- bl$literature_targets %||% list(
    age_main_beta = -0.08,
    age_sex_interaction = -0.04,
    female_intercept_diff = 0.05
  )
  tol <- as.numeric(bl$literature_tol_pct %||% 25)

  coef_paths <- literature_find_table(out_base, "Table_Network_Temperature_MixedModel.csv")
  sex_paths <- literature_find_table(out_base, "Table_Network_Temperature_MixedModel_by_Sex.csv")
  if (!length(coef_paths)) {
    coef_path <- file.path(out_base, "Tables", "Table_Network_Temperature_MixedModel.csv")
    if (file.exists(coef_path)) coef_paths <- coef_path
  }
  if (!length(coef_paths)) {
    cli::cli_alert_warning("缺少 mixed model 系数表，跳过文献对照")
    return(ctx)
  }

  all_rows <- list()
  for (coef_path in coef_paths) {
    cohort <- "All"
    m <- regmatches(coef_path, regexpr("/by_unit/[^/]+/", coef_path))
    if (length(m)) cohort <- gsub(".*/by_unit/([^/]+)/.*", "\\1", coef_path)

    coef_df <- utils::read.csv(coef_path, stringsAsFactors = FALSE)
    sex_path <- sex_paths[grepl(paste0("/by_unit/", cohort, "/"), sex_paths)][1L]
    sex_df <- if (!is.na(sex_path) && file.exists(sex_path)) utils::read.csv(sex_path, stringsAsFactors = FALSE) else data.frame()

    pick <- function(term_kw) {
      hit <- coef_df[grepl(term_kw, coef_df$term, ignore.case = TRUE), , drop = FALSE]
      if (!nrow(hit)) return(NA_real_)
      val <- hit$Estimate[1L]
      if (is.na(val) && "Value" %in% names(hit)) val <- hit$Value[1L]
      suppressWarnings(as.numeric(val))
    }

    rows <- list(
      cbind(literature_compare_metric(pick("Age"), targets$age_main_beta, tol, paste0(cohort, ": Age main (β)")), cohort = cohort),
      cbind(literature_compare_metric(pick("Age.*Sex|Sex.*Age"), targets$age_sex_interaction, tol, paste0(cohort, ": Age×Sex (β)")), cohort = cohort)
    )
    if (nrow(sex_df) && "Sex" %in% names(sex_df)) {
      for (sx in unique(sex_df$Sex)) {
        sub <- sex_df[sex_df$Sex == sx, , drop = FALSE]
        age_b <- suppressWarnings(as.numeric(sub$Estimate[grepl("Age", sub$term)][1L]))
        rows[[length(rows) + 1L]] <- cbind(
          literature_compare_metric(age_b, targets$age_main_beta, tol, paste0(cohort, ": Age slope (", sx, ")")),
          cohort = cohort
        )
      }
    }
    all_rows <- c(all_rows, rows)
  }

  out <- file.path(out_base, "Tables", "Table_Network_Temperature_Literature_Validation.csv")
  tab <- literature_write_validation(all_rows, out, meta = list(
    paper = "Grimes 2025 Nat Mental Health",
    note = "smoke 数据系数不与原文 Figure 一致；需 ABCD/ALSPAC/MCS 真实数据"
  ))
  n_pass <- sum(tab$within_tol %in% TRUE, na.rm = TRUE)
  n_tot <- sum(!is.na(tab$within_tol))
  ctx$results$network_temp_literature_validate <- list(table = tab, pass = n_pass, total = n_tot)
  cli::cli_alert_success("网络温度文献对照: {n_pass}/{n_tot}（smoke 预期 FAIL）")
  ctx
}

register_block("network_temp_literature_validate", block_network_temp_literature_validate, "网络温度性别分层对照")
