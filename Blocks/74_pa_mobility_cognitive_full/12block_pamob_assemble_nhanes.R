###############################################################################
# pamob_assemble_nhanes — PA×Mobility×DSST×NfL + 基线人口学 + PHQ + Stroke
###############################################################################

block_pamob_assemble_nhanes <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  bl <- pamob_cfg(ctx)
  nh <- file.path(pamob_data_root(ctx), "NHANES")
  cycle_keep <- as.character(bl$nhanes_cycle %||% "H")[1L]
  age_min <- as.numeric(bl$nhanes_age_min %||% 60)[1L]
  age_max <- as.numeric(bl$nhanes_age_max %||% 75)[1L]
  source_file <- as.character(bl$nhanes_source_file %||% "2013-2014")[1L]

  pa <- pamob_read_csv(file.path(nh, "D03_physical_activity.csv"))
  mo <- pamob_read_csv(file.path(nh, "D04_mobility_capacity.csv"))
  ds <- pamob_read_csv(file.path(nh, "D02_cognitive_performance.csv"))
  nf <- pamob_read_csv(file.path(nh, "D05_serum_nfl.csv"))

  if (names(mo)[1] %in% c("X", "")) mo <- mo[, -1, drop = FALSE]
  if (names(ds)[1] %in% c("X", "")) ds <- ds[, -1, drop = FALSE]

  pa$SEQN <- as.integer(pa$SEQN)
  mo$SEQN <- as.integer(mo$SEQN)
  ds$SEQN <- as.integer(ds$SEQN)
  nf$SEQN <- as.integer(nf$SEQN)

  pa <- pa[as.character(pa$cycle) == cycle_keep, , drop = FALSE]
  mo <- mo[as.character(mo$cycle) == cycle_keep, , drop = FALSE]

  pa$pa_sufficient <- suppressWarnings(as.integer(pa$pa_level))
  mo$mobility_limited <- suppressWarnings(as.integer(mo$mobility_limited))
  pfq_cols <- intersect(c("PFQ061B", "PFQ061C", "PFQ061D", "PFQ061I"), names(mo))
  mo_keep <- unique(c("SEQN", "mobility_limited", "mobility_status", pfq_cols))
  d <- merge(pa[, c("SEQN", "cycle", "total_met", "pa_sufficient", "pa_group")],
             mo[, mo_keep, drop = FALSE],
             by = "SEQN", all = FALSE)
  # PFQ answer 5 flag（敏感性：排除）
  if (length(pfq_cols)) {
    any5 <- Reduce(`|`, lapply(pfq_cols, function(v) {
      x <- suppressWarnings(as.integer(d[[v]]))
      !is.na(x) & x == 5L
    }))
    d$pfq_any_do_not_do <- as.integer(any5)
  } else {
    d$pfq_any_do_not_do <- NA_integer_
  }
  d$phenotype_code <- pamob_phenotype_key(d$pa_sufficient, d$mobility_limited)
  d$phenotype <- pamob_phenotype_factor(d$phenotype_code)
  d <- d[!is.na(d$phenotype), , drop = FALSE]

  d <- merge(d, ds[, c("SEQN", "CFDDS", "CFDDPP", "CFDDRNC")], by = "SEQN", all.x = TRUE)
  d <- merge(d, nf[, c("SEQN", "SSSNFL", "ln_SSSNFL", "WTSSNH2Y", "SDMVSTRA", "SDMVPSU", "RIDAGEYR")],
             by = "SEQN", all.x = TRUE)

  # ---- 人口学基线（筛 2013-2014）----
  demo_path <- bl$nhanes_baseline_rdata %||%
    pamob_find_first(nh, "^D01_baseline_NHANES.*\\.RData$")
  n_demo <- 0L
  if (!is.na(demo_path) && file.exists(demo_path)) {
    demo <- pamob_load_rdata_df(demo_path, prefer = c("baseline", "Baseline"))
    idn <- if ("SEQN" %in% names(demo)) "SEQN" else if ("ID" %in% names(demo)) "ID" else NA_character_
    if (is.na(idn)) stop("NHANES baseline 无 SEQN/ID", call. = FALSE)
    demo$SEQN <- as.integer(demo[[idn]])
    if ("Source_File" %in% names(demo)) {
      demo <- demo[as.character(demo$Source_File) == source_file, , drop = FALSE]
    }
    demo <- demo[!duplicated(demo$SEQN), , drop = FALSE]
    # demo 可带 WTMEC2YR；SDMV* 先留 NfL 侧，缺则用 demo 回填
    demo_sdmv <- demo[, intersect(c("SEQN", "SDMVSTRA", "SDMVPSU"), names(demo)), drop = FALSE]
    keep_demo <- setdiff(names(demo), c("SDMVSTRA", "SDMVPSU", "WTSSNH2Y", "ID"))
    demo <- demo[, unique(c("SEQN", setdiff(keep_demo, "SEQN"))), drop = FALSE]
    d <- merge(d, demo, by = "SEQN", all.x = TRUE)
    if (nrow(demo_sdmv)) {
      d <- merge(d, demo_sdmv, by = "SEQN", all.x = TRUE, suffixes = c("", "_demo"))
      if ("SDMVSTRA_demo" %in% names(d)) {
        d$SDMVSTRA <- ifelse(is.na(d$SDMVSTRA), d$SDMVSTRA_demo, d$SDMVSTRA)
        d$SDMVSTRA_demo <- NULL
      }
      if ("SDMVPSU_demo" %in% names(d)) {
        d$SDMVPSU <- ifelse(is.na(d$SDMVPSU), d$SDMVPSU_demo, d$SDMVPSU)
        d$SDMVPSU_demo <- NULL
      }
    }
    n_demo <- sum(!is.na(d$Age))
    cli::cli_alert_info("已合并 NHANES 基线 ({source_file}): Age非缺失={n_demo}")
  } else {
    cli::cli_alert_warning("未找到 D01_baseline_NHANES*.RData")
  }

  # ---- PHQ-9 连续分 ----
  phq_path <- bl$nhanes_depression_rdata %||%
    pamob_find_first(nh, "^D06_depression.*\\.RData$")
  n_phq <- 0L
  if (!is.na(phq_path) && file.exists(phq_path)) {
    phq <- pamob_load_rdata_df(phq_path, prefer = c("depression", "Depression"))
    idn <- if ("SEQN" %in% names(phq)) "SEQN" else if ("ID" %in% names(phq)) "ID" else NA_character_
    sc <- if ("Depression" %in% names(phq)) "Depression" else if ("PHQ9" %in% names(phq)) "PHQ9" else NA_character_
    if (is.na(idn) || is.na(sc)) stop("NHANES depression 需 ID/SEQN + Depression/PHQ9", call. = FALSE)
    phq$SEQN <- as.integer(phq[[idn]])
    phq$PHQ9 <- suppressWarnings(as.numeric(phq[[sc]]))
    phq <- phq[!duplicated(phq$SEQN), c("SEQN", "PHQ9"), drop = FALSE]
    d <- merge(d, phq, by = "SEQN", all.x = TRUE)
    # 分析列名与方案一致：Depression 连续分
    d$Depression <- d$PHQ9
    n_phq <- sum(!is.na(d$Depression))
    cli::cli_alert_info("已合并 PHQ-9/Depression: 非缺失={n_phq}")
  }

  # ---- Stroke ----
  st_path <- bl$nhanes_stroke_rdata %||%
    pamob_find_first(nh, "^D07_stroke.*\\.RData$")
  n_st <- 0L
  if (!is.na(st_path) && file.exists(st_path)) {
    st <- pamob_load_rdata_df(st_path, prefer = c("stroke_data", "stroke", "Stroke"))
    idn <- if ("SEQN" %in% names(st)) "SEQN" else if ("ID" %in% names(st)) "ID" else NA_character_
    if (is.na(idn) || !"Stroke" %in% names(st)) stop("NHANES stroke 需 ID/SEQN + Stroke", call. = FALSE)
    st$SEQN <- as.integer(st[[idn]])
    st$Stroke <- suppressWarnings(as.integer(st$Stroke))
    st <- st[!duplicated(st$SEQN), c("SEQN", "Stroke"), drop = FALSE]
    if ("Stroke" %in% names(d)) d$Stroke <- NULL
    d <- merge(d, st, by = "SEQN", all.x = TRUE)
    n_st <- sum(!is.na(d$Stroke))
    cli::cli_alert_info("已合并 Stroke: 非缺失={n_st}")
  }

  d$CFDDS <- suppressWarnings(as.numeric(d$CFDDS))
  d$SSSNFL <- suppressWarnings(as.numeric(d$SSSNFL))
  d$ln_SSSNFL <- suppressWarnings(as.numeric(d$ln_SSSNFL))
  d$WTSSNH2Y <- suppressWarnings(as.numeric(d$WTSSNH2Y))
  if ("WTMEC2YR" %in% names(d)) d$WTMEC2YR <- suppressWarnings(as.numeric(d$WTMEC2YR))
  d$RIDAGEYR <- suppressWarnings(as.numeric(d$RIDAGEYR))
  if ("Age" %in% names(d)) d$Age <- suppressWarnings(as.numeric(d$Age))
  # 年龄优先用基线 Age，否则 RIDAGEYR
  d$Age_anal <- ifelse(!is.na(d$Age), d$Age, d$RIDAGEYR)
  d$SDMVSTRA <- suppressWarnings(as.integer(d$SDMVSTRA))
  d$SDMVPSU <- suppressWarnings(as.integer(d$SDMVPSU))
  if ("Gender" %in% names(d) && !"Sex" %in% names(d)) d$Sex <- d$Gender

  # eGFR（NfL 扩展）
  if ("Creatinine" %in% names(d) && "Age_anal" %in% names(d)) {
    fem <- if ("Gender" %in% names(d)) {
      g <- tolower(as.character(d$Gender))
      g %in% c("2", "f", "female", "女", "women", "woman")
    } else if ("Sex" %in% names(d)) {
      g <- tolower(as.character(d$Sex))
      g %in% c("2", "f", "female", "女")
    } else rep(NA, nrow(d))
    d$eGFR <- pamob_egfr_ckd_epi(d$Creatinine, d$Age_anal, fem)
  }

  # NfL exploratory：仍锁定 60–75 + WTSSNH2Y
  d_age_nfl <- d[!is.na(d$Age_anal) & d$Age_anal >= age_min & d$Age_anal <= age_max, , drop = FALSE]
  d_nfl <- d_age_nfl[!is.na(d_age_nfl$WTSSNH2Y) & d_age_nfl$WTSSNH2Y > 0 & !is.na(d_age_nfl$ln_SSSNFL), , drop = FALSE]

  # 正文 DSST 主样本：age≥60，不设上限，不要求 NfL；权重 WTMEC2YR
  dsst_age_min <- as.numeric(bl$nhanes_dsst_age_min %||% age_min)[1L]
  d_dsst <- d[!is.na(d$Age_anal) & d$Age_anal >= dsst_age_min & !is.na(d$CFDDS), , drop = FALSE]
  if ("WTMEC2YR" %in% names(d_dsst)) {
    d_dsst <- d_dsst[!is.na(d_dsst$WTMEC2YR) & d_dsst$WTMEC2YR > 0, , drop = FALSE]
  }

  # 兼容旧槽位：pamob_nhanes = NfL 年龄窗（敏感性等仍可用）
  d_age <- d_age_nfl

  # NHANES 纳排 flowchart：主路径 DSST；NfL 分叉 exploratory
  steps_nh <- data.frame(
    step = c(
      "1_cycle_H_PA_mobility_merged",
      "2_age_ge60_DSST_main",
      "3_DSST_plus_WTMEC2YR",
      "4_NfL_exploratory_age60_75"
    ),
    n = c(
      nrow(d),
      sum(!is.na(d$Age_anal) & d$Age_anal >= dsst_age_min, na.rm = TRUE),
      nrow(d_dsst),
      nrow(d_nfl)
    ),
    stringsAsFactors = FALSE
  )
  steps_nh$excluded_vs_prev <- c(
    NA_integer_,
    nrow(d) - steps_nh$n[2],
    steps_nh$n[2] - steps_nh$n[3],
    NA_integer_
  )
  pamob_write_csv(steps_nh, file.path(pamob_tables_dir(ctx), "Flowchart_attrition_NHANES.csv"))
  fig <- pamob_figures_dir(ctx)
  pdf_nh <- file.path(fig, "Figure S1. NHANES flowchart.pdf")
  pamob_draw_figs1_nhanes_flowchart(steps_nh, pdf_nh)
  old_s2 <- list.files(fig, pattern = "Figure S2\\. NHANES flowchart",
                       recursive = TRUE, full.names = TRUE)
  if (length(old_s2)) unlink(old_s2)

  ctx$data$pamob_nhanes <- d_age
  ctx$data$pamob_nhanes_nfl <- d_nfl
  ctx$data$pamob_nhanes_dsst <- d_dsst
  ctx$data$cleaned <- d_dsst
  ctx$data$imputed <- d_dsst

  summ <- data.frame(
    set = c("merged_pheno", "dsst_main_age60plus_wtmec", "nfl_exploratory_60_75",
            "with_Age_demo", "with_Depression", "with_Stroke",
            "with_CRP", "pfq_any_do_not_do"),
    n = c(nrow(d), nrow(d_dsst), nrow(d_nfl),
          sum(!is.na(d$Age)), sum(!is.na(d$Depression)), sum(!is.na(d$Stroke)),
          if ("CRP" %in% names(d)) sum(!is.na(d$CRP)) else 0L,
          sum(d$pfq_any_do_not_do == 1L, na.rm = TRUE)),
    stringsAsFactors = FALSE
  )
  pamob_write_csv(summ, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_NHANES_Assemble_Summary.csv"))
  phn <- as.data.frame(table(phenotype = as.character(d_dsst$phenotype)), stringsAsFactors = FALSE)
  names(phn)[2] <- "n"
  pamob_write_csv(phn, file.path(pamob_tables_dir(ctx, "NHANES"), "Table_Pamob_NHANES_Phenotype_N.csv"))

  ctx$results$pamob_assemble_nhanes <- list(
    n = nrow(d_dsst), n_nfl = nrow(d_nfl), n_dsst = nrow(d_dsst),
    n_demo = n_demo, n_phq = n_phq, n_stroke = n_st
  )
  cli::cli_alert_success(
    "pamob_assemble_nhanes: DSST-main n={nrow(d_dsst)}, NfL-exploratory={nrow(d_nfl)}"
  )
  ctx
}

register_block("pamob_assemble_nhanes", block_pamob_assemble_nhanes, "NHANES 完整组装")
