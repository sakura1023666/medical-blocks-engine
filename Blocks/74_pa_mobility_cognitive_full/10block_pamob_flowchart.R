###############################################################################
# pamob_flowchart — Figure 2 CHARLS 纳排（CONSORT 风格）
# 明确：LMM unique N / person-wave / >=2 waves / Table1（与 LMM 对齐）
###############################################################################

block_pamob_flowchart <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  bl <- pamob_cfg(ctx)
  baseline_wave <- as.integer(bl$baseline_wave %||% 2011L)[1L]
  ph <- ctx$data$pamob_charls_phenotype
  long <- ctx$data$pamob_charls_long
  if (is.null(ph) || is.null(long)) stop("pamob_flowchart: 缺组装结果", call. = FALSE)

  n_ph_bl <- length(unique(ph$ID_h[ph$wave == baseline_wave]))
  n_anal <- length(unique(long$ID_h))
  n_obs <- nrow(long)
  n_ge2 <- sum(table(long$ID_h) >= 2L)
  # Table1 与 LMM unique ID 对齐（见 baseline_charls）
  n_table1 <- ctx$results$pamob_baseline_charls$n %||% n_anal
  n_wave_bl_in_long <- sum(long$wave == baseline_wave & !duplicated(long$ID_h))

  steps <- data.frame(
    step = c(
      "1_CHARLS_D05_all_waves_person_waves",
      "2_Baseline_phenotype_unique_IDs",
      "3_Analytic_IDs_with_cognition_LMM",
      "4_IDs_with_ge2_cognition_waves",
      "5_Table1_baseline_same_as_LMM_IDs"
    ),
    n = c(nrow(ph), n_ph_bl, n_anal, n_ge2, n_table1),
    stringsAsFactors = FALSE
  )
  steps$excluded_vs_prev <- c(
    NA_integer_,
    as.integer(steps$n[1] - steps$n[2]),
    as.integer(n_ph_bl - n_anal),
    as.integer(n_anal - n_ge2),
    NA_integer_ # Table1 不是从 ge2 再筛，与 step3 同口径
  )
  pamob_write_csv(steps, file.path(pamob_tables_dir(ctx), "Flowchart_attrition_CHARLS.csv"))

  # 旁注：旧误解 5698→2098
  note <- data.frame(
    item = c(
      "LMM_unique_N", "LMM_person_wave_obs", "ge2_wave_IDs",
      "Table1_N", "cognition_row_at_baseline_wave_in_long"
    ),
    n = c(n_anal, n_obs, n_ge2, n_table1, n_wave_bl_in_long),
    stringsAsFactors = FALSE
  )
  pamob_write_csv(note, file.path(pamob_tables_dir(ctx), "Flowchart_CHARLS_N_roles.csv"))

  fig <- pamob_figures_dir(ctx)
  pdf_path <- file.path(fig, "Figure 2. CHARLS flowchart.pdf")
  pamob_draw_fig2_flowchart(steps, pdf_path)
  ctx$results$pamob_flowchart <- list(steps = steps, path = pdf_path, n_roles = note)
  cli::cli_alert_success(
    "Figure 2 flowchart: LMM n={n_anal}, obs={n_obs}, ge2={n_ge2}, Table1={n_table1}"
  )
  ctx
}

register_block("pamob_flowchart", block_pamob_flowchart, "Figure 2 flowchart")
