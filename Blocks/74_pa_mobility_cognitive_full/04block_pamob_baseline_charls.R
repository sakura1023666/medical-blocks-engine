###############################################################################
# pamob_baseline_charls — Table 1 完整四组基线特征
# 样本口径：与 LMM 分析集 unique ID 对齐（用 baseline 协变量行），不再只用
# long 中 wave==2011 有认知观测的子集（旧口径 ~2098，与轨迹 N 脱节）。
###############################################################################

block_pamob_baseline_charls <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  long <- ctx$data$pamob_charls_long
  if (is.null(long)) stop("pamob_baseline_charls: 无长表", call. = FALSE)
  bl <- pamob_cfg(ctx)
  baseline_wave <- as.integer(bl$baseline_wave %||% 2011L)[1L]
  age_min <- as.numeric(bl$charls_age_min %||% 45)[1L]

  anal_ids <- unique(as.character(long$ID_h))
  base0 <- ctx$data$pamob_charls_baseline
  n_wave2011_in_long <- sum(long$wave == baseline_wave & !duplicated(long$ID_h))

  if (!is.null(base0) && nrow(base0)) {
    base_rows <- base0
    base_rows$ID_h <- as.character(base_rows$ID_h)
    base_rows <- base_rows[base_rows$ID_h %in% anal_ids, , drop = FALSE]
    if ("phenotype_bl" %in% names(base_rows) && !"phenotype" %in% names(base_rows)) {
      base_rows$phenotype <- factor(base_rows$phenotype_bl, levels = unname(pamob_phenotype_labels()))
    } else {
      base_rows$phenotype <- factor(as.character(base_rows$phenotype %||% base_rows$phenotype_bl),
                                    levels = unname(pamob_phenotype_labels()))
    }
    base_rows <- base_rows[!duplicated(base_rows$ID_h), , drop = FALSE]
  } else {
    # 回退：仍用 long 基线波行
    base_rows <- long[long$wave == baseline_wave & !duplicated(long$ID_h), , drop = FALSE]
    base_rows$phenotype <- factor(as.character(base_rows$phenotype),
                                  levels = unname(pamob_phenotype_labels()))
  }
  if ("Age" %in% names(base_rows) && is.finite(age_min)) {
    base_rows <- base_rows[is.na(base_rows$Age) | base_rows$Age >= age_min, , drop = FALSE]
  }

  cont <- c("Age", "BMI", "Incometotal", "CESD10", "Global_cognition", "Episodic_memory")
  # 认知得分：若 baseline 行无，从 long 基线波补
  for (cv in c("Global_cognition", "Episodic_memory")) {
    if ((!cv %in% names(base_rows) || all(is.na(base_rows[[cv]]))) && cv %in% names(long)) {
      lw <- long[long$wave == baseline_wave, c("ID_h", cv), drop = FALSE]
      lw <- lw[!duplicated(lw$ID_h), , drop = FALSE]
      base_rows[[cv]] <- lw[[cv]][match(as.character(base_rows$ID_h), as.character(lw$ID_h))]
    }
  }
  catg <- c("Gender", "Education", "Marital_Status", "Residence",
            "Smoke", "Alcohol_drinking",
            "Hypertension", "Diabetes", "Cardiopathy", "Stroke")
  tab <- pamob_baseline_by_phenotype(base_rows, continuous = cont, categorical = catg)
  simp <- as.data.frame(table(phenotype = as.character(base_rows$phenotype)), stringsAsFactors = FALSE)
  names(simp)[2] <- "n"
  simp$pct <- round(100 * simp$n / sum(simp$n), 1)

  demo_vars <- intersect(c("Gender", "Education", "Marital_Status", "Residence", "Age"), names(base_rows))
  miss_qc <- data.frame(
    variable = demo_vars,
    n_nonmiss = vapply(demo_vars, function(v) sum(!is.na(base_rows[[v]])), integer(1)),
    n_total = nrow(base_rows),
    stringsAsFactors = FALSE
  )
  miss_qc$pct_miss <- round(100 * (1 - miss_qc$n_nonmiss / miss_qc$n_total), 1)
  cc <- base_rows
  for (v in intersect(c("Gender", "Education", "Marital_Status"), names(cc))) {
    cc <- cc[!is.na(cc[[v]]), , drop = FALSE]
  }
  n_lmm <- length(anal_ids)
  n_obs <- nrow(long)
  n_ge2 <- sum(table(long$ID_h) >= 2L)
  miss_qc_note <- sprintf(
    paste0(
      "Table1 N=%d = LMM analytic unique IDs with baseline phenotype covariates (age>=%g). ",
      "LMM person-wave observations=%d; IDs with >=2 cognition waves=%d. ",
      "Legacy note: only %d analytic IDs have a cognition row at wave %d in the long file ",
      "(not a sequential filter from the >=2-wave set). ",
      "Gender/Education/Marital complete-case N=%d (%.1f%%)."
    ),
    nrow(base_rows), age_min, n_obs, n_ge2, n_wave2011_in_long, baseline_wave,
    nrow(cc), 100 * nrow(cc) / max(1L, nrow(base_rows))
  )

  # 样本量对齐一览（给 Methods / 流程图脚注）
  n_bridge <- data.frame(
    role = c(
      "LMM_unique_IDs",
      "LMM_person_wave_obs",
      "IDs_with_ge2_cognition_waves",
      "Table1_baseline_covariate_sample",
      "IDs_with_cognition_row_at_baseline_wave_in_long"
    ),
    n = c(n_lmm, n_obs, n_ge2, nrow(base_rows), n_wave2011_in_long),
    note = c(
      "Primary longitudinal analysis denominator (unique participants)",
      "Total repeated observations in analytic long file",
      "Subset with >=2 cognition waves (sensitivity / trajectory robustness)",
      "Table 1 denominator: same IDs as LMM, baseline covariates from D01/phenotype merge",
      "NOT Table1 denominator; many LMM IDs enter cognition long at later waves only"
    ),
    stringsAsFactors = FALSE
  )

  out_dir <- pamob_tables_dir(ctx)
  pamob_write_csv(tab, file.path(out_dir, "Table 1. CHARLS baseline by phenotype.csv"))
  pamob_write_csv(simp, file.path(out_dir, "Table 1b. CHARLS phenotype N.csv"))
  pamob_write_csv(miss_qc, file.path(out_dir, "Table_Pamob_CHARLS_Table1_Missing_QC.csv"))
  pamob_write_csv(n_bridge, file.path(out_dir, "Table_Pamob_CHARLS_Sample_N_bridge.csv"))
  writeLines(miss_qc_note, file.path(out_dir, "Table_Pamob_CHARLS_Table1_Missing_Note.txt"))
  writeLines(c(
    "# CHARLS sample size bridge (Table1 vs flowchart vs LMM)",
    "",
    miss_qc_note,
    "",
    "Key point: 5698 (IDs with >=2 cognition waves) is **not** filtered down to Table1.",
    "Table1 uses the LMM unique-ID baseline covariate sample.",
    "IDs with a cognition observation at baseline wave in the long file are a different cross-section."
  ), file.path(out_dir, "Sample_N_bridge_CHARLS.md"))

  ctx$results$pamob_baseline_charls <- list(
    table = tab, n = nrow(base_rows), simple = simp,
    n_complete_demo = nrow(cc), missing_note = miss_qc_note,
    n_bridge = n_bridge, n_lmm = n_lmm, n_obs = n_obs, n_ge2 = n_ge2
  )
  cli::cli_alert_success(
    "Table 1 CHARLS n={nrow(base_rows)} (=LMM IDs); LMM obs={n_obs}; ge2={n_ge2}; wave{baseline_wave}-in-long={n_wave2011_in_long}"
  )
  ctx
}

register_block("pamob_baseline_charls", block_pamob_baseline_charls, "CHARLS Table1")
