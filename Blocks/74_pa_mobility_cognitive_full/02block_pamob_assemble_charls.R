###############################################################################
# pamob_assemble_charls — D05 表型 + D01/D02 认知 + 2011 基线人口学 + CES-D
###############################################################################

block_pamob_assemble_charls <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  bl <- pamob_cfg(ctx)
  charls_dir <- file.path(pamob_data_root(ctx), "CHARLS")
  baseline_wave <- as.integer(bl$baseline_wave %||% 2011L)[1L]

  ph <- pamob_read_csv(file.path(charls_dir, "D05_four_phenotype-ok.csv"))
  em <- pamob_read_csv(pamob_find_episodic_ok(charls_dir))
  mi <- pamob_read_csv(file.path(charls_dir, "D02_mental_intactness-ok.csv"))

  ph$wave <- as.integer(ph$wave)
  em$wave <- as.integer(em$wave)
  mi$wave <- as.integer(mi$wave)
  # 统一 ID_h：优先 ID_raw（与 C03/D03/ADL 对齐）
  .fix_id <- function(df) {
    if ("ID_raw" %in% names(df)) pamob_charls_id_h(df$ID_raw)
    else if ("ID_h" %in% names(df)) pamob_pad_id12(df$ID_h)
    else if ("ID" %in% names(df)) pamob_charls_id_h(df$ID)
    else stop("缺 ID/ID_h/ID_raw", call. = FALSE)
  }
  ph$ID_h <- .fix_id(ph)
  em$ID_h <- .fix_id(em)
  mi$ID_h <- .fix_id(mi)
  em$em_score <- suppressWarnings(as.numeric(em$em_score))
  mi$mi_score <- suppressWarnings(as.numeric(mi$mi_score))

  cog <- merge(em[, c("wave", "ID_h", "em_score")],
               mi[, c("wave", "ID_h", "mi_score")],
               by = c("wave", "ID_h"), all = TRUE)
  cog$Global_cognition <- cog$em_score + cog$mi_score
  cog$Episodic_memory <- cog$em_score

  # 基线表型（每人一次）
  ph0 <- ph[ph$wave == baseline_wave, , drop = FALSE]
  if (!nrow(ph0)) stop("pamob_assemble_charls: 基线波 ", baseline_wave, " 无表型行", call. = FALSE)
  ph0 <- ph0[!duplicated(ph0$ID_h), , drop = FALSE]
  keep <- c("ID_h", "phenotype_code", "phenotype", "phenotype_2_code", "phenotype_2",
            "pa_sufficient", "mobility_limited", "mobility_limited_2")
  keep <- intersect(keep, names(ph0))
  base <- ph0[, keep, drop = FALSE]
  names(base)[names(base) == "phenotype"] <- "phenotype_bl"
  names(base)[names(base) == "phenotype_code"] <- "phenotype_code_bl"
  names(base)[names(base) == "phenotype_2"] <- "phenotype_2_bl"
  names(base)[names(base) == "phenotype_2_code"] <- "phenotype_2_code_bl"

  # ---- 2011 人口学基线 ----
  # D01$ID 已是 11/12 位个体号：只用 pad12，禁止再跑 pamob_charls_id_h（会把 11 位二次插 0，merge 丢 ~30% 人口学）
  demo_path <- bl$charls_baseline_rdata %||%
    pamob_find_first(charls_dir, "^D01_baseline_CHARLS_2011.*\\.RData$")
  n_demo <- 0L
  if (!is.na(demo_path) && nzchar(demo_path) && file.exists(demo_path)) {
    demo <- pamob_load_rdata_df(demo_path, prefer = c("baseline", "Baseline"))
    id_demo <- if ("ID_raw" %in% names(demo)) "ID_raw" else if ("ID_h" %in% names(demo)) "ID_h" else if ("ID" %in% names(demo)) "ID" else NA_character_
    if (is.na(id_demo)) stop("CHARLS baseline 无 ID/ID_h/ID_raw", call. = FALSE)
    demo$ID_h <- if (identical(id_demo, "ID_raw")) {
      pamob_charls_id_h(demo$ID_raw)
    } else {
      pamob_pad_id12(demo[[id_demo]])
    }
    demo <- demo[!duplicated(demo$ID_h), , drop = FALSE]
    # 避免与表型/认知列名冲突
    drop_demo <- intersect(names(demo), c("Totalcognition", "Executive", "Memory", "wave"))
    if (length(drop_demo)) demo <- demo[, setdiff(names(demo), drop_demo), drop = FALSE]
    if ("ID" %in% names(demo) && id_demo == "ID") demo$ID <- NULL
    base <- merge(base, demo, by = "ID_h", all.x = TRUE)
    n_demo <- sum(!is.na(base$Age))
    cli::cli_alert_info("已合并 CHARLS 基线人口学: {basename(demo_path)} (Age非缺失={n_demo})")
  } else {
    cli::cli_alert_warning("未找到 CHARLS D01_baseline_*.RData，跳过人口学合并")
  }

  # ---- CES-D-10 连续分（取基线波）----
  cesd_path <- bl$charls_depression_rdata %||%
    pamob_find_first(charls_dir, "^D06_depression.*\\.RData$")
  n_cesd <- 0L
  if (!is.na(cesd_path) && nzchar(cesd_path) && file.exists(cesd_path)) {
    cesd <- pamob_load_rdata_df(cesd_path, prefer = c("depression", "Depression"))
    if (!all(c("wave", "ID_h") %in% names(cesd))) {
      stop("CES-D 表需含 wave + ID_h", call. = FALSE)
    }
    score_col <- if ("TOTAL" %in% names(cesd)) "TOTAL" else if ("CESD10" %in% names(cesd)) "CESD10" else NA_character_
    if (is.na(score_col)) stop("CES-D 表无 TOTAL/CESD10 列", call. = FALSE)
    cesd$wave <- as.integer(cesd$wave)
    cesd$ID_h <- if ("ID_raw" %in% names(cesd)) pamob_charls_id_h(cesd$ID_raw) else pamob_charls_id_h(cesd$ID_h)
    cesd$CESD10 <- suppressWarnings(as.numeric(cesd[[score_col]]))
    ces0 <- cesd[cesd$wave == baseline_wave, c("ID_h", "CESD10"), drop = FALSE]
    ces0 <- ces0[!duplicated(ces0$ID_h), , drop = FALSE]
    base <- merge(base, ces0, by = "ID_h", all.x = TRUE)
    n_cesd <- sum(!is.na(base$CESD10))
    cli::cli_alert_info("已合并 CES-D-10 (wave={baseline_wave}): 非缺失={n_cesd}")
  } else {
    cli::cli_alert_warning("未找到 D06_depression*.RData，跳过 CES-D 合并")
  }

  # Sex 别名（部分块可能用 Sex）
  if ("Gender" %in% names(base) && !"Sex" %in% names(base)) base$Sex <- base$Gender

  # ---- ADL/IADL 残障标志（敏感性：排除；主 mobility 仍不含 ADL）----
  adl <- pamob_build_adl_iadl_flag(charls_dir, wave = baseline_wave)
  n_adl <- 0L
  if (!is.null(adl) && nrow(adl)) {
    base <- merge(base, adl, by = "ID_h", all.x = TRUE)
    n_adl <- sum(base$adl_iadl_disabled == 1L, na.rm = TRUE)
    pamob_write_csv(adl, file.path(pamob_tables_dir(ctx, "CHARLS"), "Table_Pamob_ADL_IADL_Baseline.csv"))
    cli::cli_alert_info("已合并 ADL/IADL 残障标志: disabled n={n_adl}")
  } else {
    cli::cli_alert_warning("未构建 ADL/IADL 标志（缺 rawdata Health dta）")
  }

  # 方案：默认纳入 ≥45 岁（config$pamob$charls_age_min）
  age_min <- as.numeric(bl$charls_age_min %||% 45)[1L]
  if ("Age" %in% names(base) && is.finite(age_min)) {
    n_before_age <- nrow(base)
    base <- base[is.na(base$Age) | base$Age >= age_min, , drop = FALSE]
    cli::cli_alert_info("CHARLS Age≥{age_min}: {nrow(base)}/{n_before_age} baseline IDs")
  }

  long <- merge(cog, base, by = "ID_h", all.x = FALSE)
  long$Time_years <- long$wave - baseline_wave
  long$phenotype <- factor(long$phenotype_bl, levels = unname(pamob_phenotype_labels()))
  long <- long[!is.na(long$Global_cognition) | !is.na(long$Episodic_memory), , drop = FALSE]

  ids_ok <- unique(long$ID_h[!is.na(long$phenotype)])
  long <- long[long$ID_h %in% ids_ok, , drop = FALSE]

  ctx$data$pamob_charls_phenotype <- ph
  ctx$data$pamob_charls_long <- long
  ctx$data$pamob_charls_baseline <- base
  ctx$data$cleaned <- long
  ctx$data$imputed <- long

  summ <- data.frame(
    metric = c("n_rows_long", "n_ids", "baseline_wave", "n_with_global",
               "n_with_Age", "n_with_CESD10", "n_waves_mean"),
    value = c(nrow(long), length(unique(long$ID_h)), baseline_wave,
              sum(!is.na(long$Global_cognition)),
              if ("Age" %in% names(long)) sum(!is.na(long$Age)) else 0,
              if ("CESD10" %in% names(long)) sum(!is.na(long$CESD10)) else 0,
              round(mean(table(long$ID_h)), 2)),
    stringsAsFactors = FALSE
  )
  pamob_write_csv(summ, file.path(pamob_tables_dir(ctx, "CHARLS"), "Table_Pamob_CHARLS_Assemble_Summary.csv"))
  # merge QC
  qc <- data.frame(
    step = c("phenotype_baseline", "with_Age", "with_CESD10", "analytic_ids"),
    n = c(nrow(base), n_demo, n_cesd, length(unique(long$ID_h))),
    stringsAsFactors = FALSE
  )
  pamob_write_csv(qc, file.path(pamob_tables_dir(ctx, "CHARLS"), "Table_Pamob_CHARLS_Merge_QC.csv"))

  # 纵向人数诊断（老师审稿 §6）：各波 n、总 obs、每人测量次数分布
  wave_n <- as.data.frame(table(wave = long$wave), stringsAsFactors = FALSE)
  names(wave_n)[2] <- "n_obs"
  wave_ids <- aggregate(ID_h ~ wave, data = long, FUN = function(z) length(unique(z)))
  names(wave_ids)[2] <- "n_ids"
  wave_diag <- merge(wave_n, wave_ids, by = "wave", all = TRUE)
  n_meas <- as.integer(table(long$ID_h[!is.na(long$Global_cognition) | !is.na(long$Episodic_memory)]))
  meas_dist <- as.data.frame(table(n_measurements = n_meas), stringsAsFactors = FALSE)
  names(meas_dist)[2] <- "n_ids"
  long_diag <- data.frame(
    metric = c(
      "n_ids_analytic", "n_obs_total", "n_obs_global", "n_obs_episodic",
      "mean_measurements_per_id", "median_measurements_per_id"
    ),
    value = c(
      length(unique(long$ID_h)), nrow(long),
      sum(!is.na(long$Global_cognition)), sum(!is.na(long$Episodic_memory)),
      round(mean(n_meas), 2), as.numeric(stats::median(n_meas))
    ),
    stringsAsFactors = FALSE
  )
  out_c <- pamob_tables_dir(ctx, "CHARLS")
  pamob_write_csv(wave_diag, file.path(out_c, "Table_Pamob_CHARLS_Wave_N.csv"))
  pamob_write_csv(meas_dist, file.path(out_c, "Table_Pamob_CHARLS_Measurement_Count_Dist.csv"))
  pamob_write_csv(long_diag, file.path(out_c, "Table_Pamob_CHARLS_Longitudinal_Diagnostics.csv"))

  ctx$results$pamob_assemble_charls <- list(
    n_rows = nrow(long), n_ids = length(unique(long$ID_h)),
    baseline_wave = baseline_wave, n_with_Age = n_demo, n_with_CESD10 = n_cesd,
    wave_diag = wave_diag, meas_dist = meas_dist, long_diag = long_diag
  )
  cli::cli_alert_success("pamob_assemble_charls: long n={nrow(long)}, ids={length(unique(long$ID_h))}")
  ctx
}

register_block("pamob_assemble_charls", block_pamob_assemble_charls, "CHARLS 表型+认知+基线+CESD")
