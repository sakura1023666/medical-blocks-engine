###############################################################################
# pamob_feasibility — 方案 §9.1 七项可行性闸门 + 变量字典
###############################################################################

block_pamob_feasibility <- function(ctx, ...) {
  if (file.exists(file.path(ctx$config$project$root %||% getwd(),
                            "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"))) {
    source(file.path(ctx$config$project$root %||% getwd(),
                     "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  }
  .pamob_source_utils(ctx)
  bl <- pamob_cfg(ctx)
  data_root <- pamob_data_root(ctx)
  if (!nzchar(data_root) || !dir.exists(data_root)) {
    stop("pamob_feasibility: config$pamob$data_root 不存在: ", data_root, call. = FALSE)
  }
  charls_dir <- file.path(data_root, "CHARLS")
  nhanes_dir <- file.path(data_root, "NHANES")
  req <- c(
    file.path(charls_dir, "D05_four_phenotype-ok.csv"),
    file.path(charls_dir, "D02_mental_intactness-ok.csv"),
    file.path(nhanes_dir, "D03_physical_activity.csv"),
    file.path(nhanes_dir, "D04_mobility_capacity.csv"),
    file.path(nhanes_dir, "D02_cognitive_performance.csv"),
    file.path(nhanes_dir, "D05_serum_nfl.csv")
  )
  miss <- req[!file.exists(req)]
  if (length(miss)) stop("pamob_feasibility: 缺文件:\n", paste(miss, collapse = "\n"), call. = FALSE)
  em_path <- pamob_find_episodic_ok(charls_dir)
  demo_c <- pamob_find_first(charls_dir, "^D01_baseline_CHARLS_2011.*\\.RData$")
  cesd_c <- pamob_find_first(charls_dir, "^D06_depression.*\\.RData$")
  demo_n <- pamob_find_first(nhanes_dir, "^D01_baseline_NHANES.*\\.RData$")
  phq_n <- pamob_find_first(nhanes_dir, "^D06_depression.*\\.RData$")
  st_n <- pamob_find_first(nhanes_dir, "^D07_stroke.*\\.RData$")
  opt <- data.frame(
    item = c("CHARLS_baseline", "CHARLS_CESD", "NHANES_baseline", "NHANES_PHQ", "NHANES_Stroke"),
    path = c(demo_c, cesd_c, demo_n, phq_n, st_n),
    exists = c(
      !is.na(demo_c) && file.exists(demo_c),
      !is.na(cesd_c) && file.exists(cesd_c),
      !is.na(demo_n) && file.exists(demo_n),
      !is.na(phq_n) && file.exists(phq_n),
      !is.na(st_n) && file.exists(st_n)
    ),
    stringsAsFactors = FALSE
  )

  ph <- pamob_read_csv(req[[1L]])
  ph$wave <- as.integer(ph$wave)
  ph$ID_h <- pamob_pad_id12(ph$ID_h)
  em <- pamob_read_csv(em_path)
  mi <- pamob_read_csv(req[[2L]])
  em$wave <- as.integer(em$wave); mi$wave <- as.integer(mi$wave)
  em$ID_h <- pamob_pad_id12(em$ID_h); mi$ID_h <- pamob_pad_id12(mi$ID_h)

  # ---- §9.1-1 波次 × 可用性矩阵 ----
  waves <- sort(unique(ph$wave))
  avail <- do.call(rbind, lapply(waves, function(w) {
    ids_ph <- unique(ph$ID_h[ph$wave == w])
    ids_em <- unique(em$ID_h[em$wave == w])
    ids_mi <- unique(mi$ID_h[mi$wave == w])
    data.frame(
      wave = w,
      n_phenotype = length(ids_ph),
      n_episodic = length(ids_em),
      n_mental_intactness = length(ids_mi),
      n_global_both = length(intersect(ids_em, ids_mi)),
      n_pheno_and_global = length(intersect(ids_ph, intersect(ids_em, ids_mi))),
      stringsAsFactors = FALSE
    )
  }))

  # ---- §9.1-2 方案 A(2011) vs B(2015) 逐步 n ----
  .scheme_attrition <- function(bl_wave, follow_waves) {
    ph0 <- ph[ph$wave == bl_wave & !duplicated(ph$ID_h), , drop = FALSE]
    n1 <- nrow(ph0)
    win <- c(bl_wave, follow_waves)
    cog_w <- unique(rbind(
      data.frame(ID_h = em$ID_h[em$wave %in% win], wave = em$wave[em$wave %in% win],
                 stringsAsFactors = FALSE),
      data.frame(ID_h = mi$ID_h[mi$wave %in% win], wave = mi$wave[mi$wave %in% win],
                 stringsAsFactors = FALSE)
    ))
    ids <- intersect(ph0$ID_h, unique(cog_w$ID_h))
    n2 <- length(ids)
    n_obs <- table(cog_w$ID_h[cog_w$ID_h %in% ids])
    n3 <- sum(n_obs >= 2L)
    data.frame(
      scheme = if (bl_wave == 2011L) "A_2011_baseline" else "B_2015_baseline",
      baseline_wave = bl_wave,
      follow_waves = paste(follow_waves, collapse = ","),
      step = c("baseline_phenotype_IDs", "with_any_cognition_in_window", "IDs_with_ge2_cognition_waves"),
      n = c(n1, n2, n3),
      stringsAsFactors = FALSE
    )
  }
  attr_a <- .scheme_attrition(2011L, c(2013L, 2015L, 2018L))
  attr_b <- .scheme_attrition(2015L, c(2018L))
  attrition <- rbind(attr_a, attr_b)

  # ---- §9.1-3 四组 N ----
  by_wave <- as.data.frame(table(wave = ph$wave, phenotype = ph$phenotype), stringsAsFactors = FALSE)
  names(by_wave)[3] <- "n"
  overall <- as.data.frame(table(phenotype = ph$phenotype), stringsAsFactors = FALSE)
  names(overall)[2] <- "n"
  overall$pct <- round(100 * overall$n / sum(overall$n), 1)

  # NHANES phenotype N (cycle H, age 60–75 if Age available later; here raw merge)
  pa <- pamob_read_csv(req[[3L]])
  mo <- pamob_read_csv(req[[4L]])
  if (names(mo)[1] %in% c("X", "")) mo <- mo[, -1, drop = FALSE]
  pa <- pa[as.character(pa$cycle) == as.character(bl$nhanes_cycle %||% "H"), ]
  mo <- mo[as.character(mo$cycle) == as.character(bl$nhanes_cycle %||% "H"), ]
  pa$pa_sufficient <- suppressWarnings(as.integer(pa$pa_level))
  mo$mobility_limited <- suppressWarnings(as.integer(mo$mobility_limited))
  nh <- merge(pa[, c("SEQN", "pa_sufficient")], mo[, c("SEQN", "mobility_limited",
                                                      intersect(c("PFQ061B", "PFQ061C", "PFQ061D", "PFQ061I"), names(mo)))],
              by = "SEQN")
  nh$phenotype_code <- pamob_phenotype_key(nh$pa_sufficient, nh$mobility_limited)
  nh$phenotype <- pamob_phenotype_factor(nh$phenotype_code)
  nh <- nh[!is.na(nh$phenotype), ]
  nh_pheno <- as.data.frame(table(phenotype = as.character(nh$phenotype)), stringsAsFactors = FALSE)
  names(nh_pheno)[2] <- "n"
  nh_pheno$pct <- round(100 * nh_pheno$n / sum(nh_pheno$n), 1)

  nf <- pamob_read_csv(req[[6L]])
  nf$SEQN <- as.integer(nf$SEQN)
  nf_m <- merge(nh, nf[, intersect(c("SEQN", "SSSNFL", "ln_SSSNFL", "WTSSNH2Y", "RIDAGEYR"), names(nf))],
                by = "SEQN", all.x = TRUE)
  age_min <- as.numeric(bl$nhanes_age_min %||% 60)
  age_max <- as.numeric(bl$nhanes_age_max %||% 75)
  if ("RIDAGEYR" %in% names(nf_m)) {
    nf_m <- nf_m[!is.na(nf_m$RIDAGEYR) & nf_m$RIDAGEYR >= age_min & nf_m$RIDAGEYR <= age_max, ]
  }
  nfl_anal <- nf_m[!is.na(nf_m$WTSSNH2Y) & nf_m$WTSSNH2Y > 0 & !is.na(nf_m$ln_SSSNFL), ]
  nfl_by <- as.data.frame(table(phenotype = as.character(nfl_anal$phenotype)), stringsAsFactors = FALSE)
  names(nfl_by)[2] <- "n"
  if (nrow(nfl_by) && "WTSSNH2Y" %in% names(nfl_anal)) {
    w <- tapply(nfl_anal$WTSSNH2Y, as.character(nfl_anal$phenotype), sum, na.rm = TRUE)
    nfl_by$pct_weighted <- round(100 * as.numeric(w[nfl_by$phenotype]) / sum(w, na.rm = TRUE), 1)
  }
  nfl_by$flag <- ifelse(nfl_by$n < 30, "below_n30_exploratory",
                        ifelse(nfl_by$n < 50, "caution_30_49", "ok_ge50"))

  # ---- §9.1-4 PA 区间代表值 ----
  pa_map <- pamob_pa_duration_map()

  # ---- §9.1-5 PFQ 规则 ----
  pfq_rules <- data.frame(rule = pamob_pfq_coding_rules(), stringsAsFactors = FALSE)

  # ---- §9.1-7 变量字典 ----
  dict <- data.frame(
    database = c(
      rep("CHARLS", 12), rep("NHANES", 14)
    ),
    analysis_concept = c(
      "Vigorous/Moderate/Walking PA", "PA MET-min/week", "PA sufficient (≥600)",
      "Walking ~1km", "Climb stairs", "Chair rise", "Stoop/kneel",
      "Mobility limited (any)", "Four phenotypes", "Global cognition 0–21",
      "Episodic memory", "CES-D-10 continuous",
      "GPAQ domains PA", "PA sufficient (≥600)",
      "PFQ061B quarter-mile", "PFQ061C ten steps", "PFQ061D stoop", "PFQ061I chair",
      "PFQ answer 5", "PFQ054 structural skip",
      "Four phenotypes", "DSST", "Serum NfL", "NfL weight",
      "PHQ-9 continuous", "Stroke"
    ),
    source_file = c(
      "upstream C03 / D03_physical_activity-ok.csv", "D03 / D05", "D05 pa_sufficient",
      "D04/D05 mobility items", "D04/D05", "D04/D05", "D04/D05",
      "D05 mobility_limited", "D05_four_phenotype-ok.csv",
      "D01 episodic + D02 mental intactness", "D01 episodic em_score",
      "D06_depression_ok.RData TOTAL",
      "D03_physical_activity.csv (PAQ_H)", "D03 pa_level",
      "D04 PFQ061B", "D04 PFQ061C", "D04 PFQ061D", "D04 PFQ061I",
      "D04 code=5", "upstream PFQ054→D04 limited",
      "PA×mobility merge", "D02 CFDDS (CFQ_H)", "D05 SSSNFL", "D05 WTSSNH2Y",
      "D06_depression Depression", "D07_stroke Stroke"
    ),
    original_vars = c(
      "vigorous/moderate/walking days×duration bins", "MET=8/4/3.3", "pa_sufficient 0/1",
      "walk 1km difficulty", "stairs difficulty", "chair rise difficulty", "stoop difficulty",
      "mobility_limited 0/1", "phenotype_code 1–4", "em_score+mi_score",
      "em_score", "TOTAL→CESD10",
      "PAQ605–670 / PAD*", "pa_level 0/1",
      "PFQ061B", "PFQ061C", "PFQ061D", "PFQ061I",
      "5=do not do", "PFQ054 Yes → B/C skip",
      "phenotype", "CFDDS", "SSSNFL / ln_SSSNFL", "WTSSNH2Y+SDMVSTRA+SDMVPSU",
      "Depression/PHQ9", "Stroke 0/1"
    ),
    recode_rule = c(
      "Duration bins→20/75/180/240 min (Tian&Shi 2022)", "Sum MET-min/week", "≥600 vs <600",
      "any difficulty→limited", "same", "same", "same",
      "≥1 item difficulty", "PA×mobility 2×2; ref=Active_preserved",
      "0–21 sum; not clinical AD", "secondary outcome",
      "baseline-wave continuous covariate (not cognition outcome)",
      "GPAQ MET; cycle H", "≥600",
      "1=no diff; 2–4 limited; 5→limited (main)", "same", "same", "same",
      "main=limited; sens=exclude", "missing B/C after PFQ054=Yes → limited",
      "ref Active_preserved", "continuous DSST", "log(sNfL) outcome", "survey design required",
      "continuous covariate", "exclude in sensitivity"
    ),
    notes = c(
      "Raw PA bins not re-exported in D03-ok; primary uses locked D05", "Locked before results", "Locked 600",
      "Not ADL/IADL", "Not running/arm", "Not grip", "NHANES-harmonized four",
      "Alt: mobility_limited_2 (≥2)", "phenotype_2 for sens", "Primary CHARLS outcome",
      "Secondary", "Model3 covariate",
      "2013–2014 / cycle H", "Locked 600",
      "Quarter mile", "Ten steps", "Stoop/kneel/crouch", "Armless chair",
      "n with any5 in cycle H ≈61 (feasibility)", "Documented in D04 pipeline",
      "Cross-db triangulation only", "Not decline", "Not AD-specific", "Not WTMEC for NfL main",
      "Not cognition outcome", "Cerebrovascular confounder"
    ),
    stringsAsFactors = FALSE
  )

  path_tab <- data.frame(
    item = c("data_root", "CHARLS_D05", "CHARLS_D01_ok", "CHARLS_D02_ok",
             "NHANES_PA", "NHANES_MOB", "NHANES_DSST", "NHANES_NfL",
             opt$item),
    path = c(data_root, req[1], em_path, req[2], req[3], req[4], req[5], req[6],
             opt$path),
    exists = c(rep(TRUE, 8), opt$exists),
    stringsAsFactors = FALSE
  )

  out <- pamob_tables_dir(ctx, "Feasibility")
  pamob_write_csv(path_tab, file.path(out, "Table_Pamob_Paths.csv"))
  pamob_write_csv(avail, file.path(out, "Table_Pamob_Wave_Availability_Matrix.csv"))
  pamob_write_csv(attrition, file.path(out, "Table_Pamob_Baseline_Scheme_AB_Attrition.csv"))
  pamob_write_csv(by_wave, file.path(out, "Table_Pamob_CHARLS_Phenotype_by_Wave.csv"))
  pamob_write_csv(overall, file.path(out, "Table_Pamob_CHARLS_Phenotype_Overall.csv"))
  pamob_write_csv(nh_pheno, file.path(out, "Table_Pamob_NHANES_Phenotype_N_raw.csv"))
  pamob_write_csv(nfl_by, file.path(out, "Table_Pamob_NHANES_NfL_Phenotype_N_Gate.csv"))
  pamob_write_csv(pa_map, file.path(out, "Table_Pamob_PA_Duration_Representatives.csv"))
  pamob_write_csv(pfq_rules, file.path(out, "Table_Pamob_PFQ_Coding_Rules.csv"))
  pamob_write_csv(dict, file.path(out, "Table_Pamob_Variable_Dictionary.csv"))

  locked <- as.integer(bl$baseline_wave %||% 2011L)[1L]
  min_nfl <- if (nrow(nfl_by)) min(nfl_by$n) else NA_integer_
  report <- c(
    "# Feasibility Report — PA–Mobility × Cognitive Aging (proposal §9.1)",
    "",
    "## 1. CHARLS wave × variable availability",
    "See Table_Pamob_Wave_Availability_Matrix.csv",
    "",
    "## 2. Baseline scheme A vs B attrition",
    "See Table_Pamob_Baseline_Scheme_AB_Attrition.csv",
    paste0("**Locked baseline for main analysis: ", locked,
           "** (Scheme A preferred: more cognition waves 2011→2013/2015/2018)."),
    "",
    "## 3. Phenotype N",
    "CHARLS: Table_Pamob_CHARLS_Phenotype_Overall.csv / by_wave",
    "NHANES cycle H: Table_Pamob_NHANES_Phenotype_N_raw.csv",
    "",
    "## 4. PA duration representatives",
    "20 / 75 / 180 / 240 min (Tian & Shi 2022). Table_Pamob_PA_Duration_Representatives.csv",
    "Primary phenotypes use delivered D05 (threshold 600 MET-min/week locked).",
    "",
    "## 5. PFQ054 / answer-5 rules",
    paste(pamob_pfq_coding_rules(), collapse = " "),
    "",
    "## 6. NHANES sNfL min phenotype cell",
    paste0("Age window ", age_min, "–", age_max, "; analytic NfL n=", nrow(nfl_anal),
           "; min phenotype n=", min_nfl, "."),
    if (!is.na(min_nfl) && min_nfl < 30) {
      "GATE: min n<30 → NfL four-group main should be exploratory."
    } else if (!is.na(min_nfl) && min_nfl < 50) {
      "GATE: min n 30–49 → interpret cautiously."
    } else {
      "GATE: min n≥50 → four-group NfL main retained."
    },
    "",
    "## 7. Variable dictionary",
    "Table_Pamob_Variable_Dictionary.csv (proposal Appendix A filled from delivered D0x).",
    "",
    "## Decision lock (Appendix C)",
    paste0("- CHARLS baseline wave: ", locked),
    "- PA threshold: 600 MET-min/week",
    "- Mobility limited: any of 4 items",
    "- NHANES cycle H / 2013–2014; age 60–75 for integrated sample",
    "- NfL weight: WTSSNH2Y + SDMVSTRA/PSU",
    "- Sensitivities preset: stroke exclude; mobility≥2; PFQ5 exclude; NfL +eGFR/+CRP; NHANES stroke exclude"
  )
  writeLines(report, file.path(out, "Feasibility_Report.md"))
  writeLines(report, file.path(out, "Feasibility_README.txt"))

  ctx$results$pamob_feasibility <- list(
    n_charls_rows = nrow(ph), n_ids = length(unique(ph$ID_h)),
    phenotype_overall = overall, nfl_gate = nfl_by, output_dir = out,
    locked_baseline = locked
  )
  cli::cli_alert_success("pamob_feasibility: §9.1 七项已落盘 → {out}")
  ctx
}

register_block("pamob_feasibility", block_pamob_feasibility, "PA-mobility 可行性闸门")
