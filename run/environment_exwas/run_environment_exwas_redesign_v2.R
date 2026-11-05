#!/usr/bin/env Rscript
# ExWAS 设计修正版：
#  默认主路径 = 完全病例筛选 FDR（--mice 0）；有 FDR 命中后再加 --mice 做插补敏感性。
#  A) 每暴露独立有效样本（取消全局人级 1/3）
#  B) Day1 / 双日完整 survey ExWAS + DAG 全调整 + Willett + Energy_ln
#  C) 可选 --mice m（仅在用户确认要插补时开；默认关）
#  D) 可选纳入 2017-2018
# 用法:
#   Rscript run_environment_exwas_redesign_v2.R --nutrition <csv> --out <dir> \
#     [--label name] [--workers 4] [--model day1|day2|both] [--include-2017] [--mice 0|20]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  nutrition = NULL, out = NULL, label = "redesign_v2", workers = "4",
  model = "both", include_2017 = FALSE, mice = 0L
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--nutrition" && i < length(args)) { opt$nutrition <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--label" && i < length(args)) { opt$label <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--model" && i < length(args)) { opt$model <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--include-2017") { opt$include_2017 <- TRUE; i <- i + 1L
  } else if (a == "--mice" && i < length(args)) { opt$mice <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}
if (is.null(opt$nutrition) || is.null(opt$out)) stop("需要 --nutrition 与 --out", call. = FALSE)

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(root)
Sys.setenv(EXWAS_WORKERS = opt$workers)
source(file.path(root, "R/environment_exwas_core.R"))
source(file.path(root, "R/environment_exwas_aligned.R"))

to_host_path <- function(p) {
  if (.Platform$OS.type != "windows") return(p)
  p <- chartr("\\", "/", p)
  if (grepl("^/mnt/[A-Za-z]/", p)) paste0(toupper(substr(p, 6, 6)), ":/", substring(p, 8)) else p
}
base <- to_host_path("/mnt/g/02block_result/51_gastric cancer/environment_41380607")
out <- to_host_path(opt$out)
exwas_ensure_dir(out)

nut_csv <- to_host_path(opt$nutrition)
base_r <- file.path(base, "data/D01_baseline_NHANES_0920.RData")

exwas_log("[", opt$label, "] redesign_v2：per-exposure + survey-weighted + DAG全调整")
raw0 <- exwas_aligned_load(nut_csv, base_r)
raw0 <- exwas_aligned_mediators(raw0)

# 能量 Day1（含 2017-2018 时用 2003_2018 提取表）
kcal_csv <- if (isTRUE(opt$include_2017)) {
  file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2018.csv")
} else {
  file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2016.csv")
}
if (!file.exists(kcal_csv)) kcal_csv <- file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2016.csv")
kcal <- exwas_read_csv(kcal_csv)
names(kcal) <- sub("^\ufeff", "", names(kcal))
kcal$SEQN <- as.character(kcal$SEQN)
kcal$cycle <- as.character(kcal$cycle)
raw0$SEQN <- as.character(raw0$SEQN)
raw0$cycle <- as.character(raw0$cycle)
if ("DR1TKCAL" %in% names(raw0)) raw0$DR1TKCAL <- NULL
raw0 <- merge(raw0, kcal[, c("cycle", "SEQN", "DR1TKCAL"), drop = FALSE],
              by = c("cycle", "SEQN"), all.x = TRUE)

# DR2 营养+能量（供 day2 模型 / 日均）
dr2_csv <- if (isTRUE(opt$include_2017)) {
  file.path(base, "data/nutrition_extract/NHANES_DR2TOT_nut53_kcal_2003_2018.csv")
} else {
  file.path(base, "data/nutrition_extract/NHANES_DR2TOT_nut53_kcal_2003_2016.csv")
}
if (!file.exists(dr2_csv)) {
  dr2_csv <- file.path(base, "data/nutrition_extract/NHANES_DR2TOT_nut53_kcal_2003_2016.csv")
}
if (file.exists(dr2_csv)) {
  dr2 <- exwas_read_csv(dr2_csv)
  names(dr2) <- sub("^\ufeff", "", names(dr2))
  dr2$SEQN <- as.character(dr2$SEQN)
  dr2$cycle <- as.character(dr2$cycle)
  add_cols <- setdiff(names(dr2), c("cycle", "SEQN", "WTDR2D"))
  raw0 <- raw0[, setdiff(names(raw0), add_cols), drop = FALSE]
  raw0 <- merge(raw0, dr2[, c("cycle", "SEQN", add_cols), drop = FALSE],
                by = c("cycle", "SEQN"), all.x = TRUE)
}

# 周期范围
if (!isTRUE(opt$include_2017)) {
  raw0 <- raw0[!raw0$cycle %in% c("2017-2018", "2017-2020", "2021-2023"), , drop = FALSE]
} else {
  raw0 <- raw0[!raw0$cycle %in% c("2017-2020", "2021-2023"), , drop = FALSE]
  exwas_log("保留 2017-2018；周期分布：")
  print(table(raw0$cycle, useNA = "ifany"))
}

# 多周期合并权重：除以实际两年周期数（7 或 8），覆盖 load 时写死的 /7
n_cyc <- length(unique(raw0$cycle))
for (w in c("WTINT2YR", "WTMEC2YR", "WTDRD1", "WTDR2D", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2Y")) {
  if (w %in% names(raw0)) {
    raw0[[paste0(w, "_7")]] <- exwas_to_num(raw0[[w]]) / n_cyc
  }
}
exwas_log("权重按 ", n_cyc, " 个两年周期缩放（列名仍 *_7）")

# 从未患癌对照 + 膳食∩MEC（入队门槛；真正加权在模型里）
nc <- exwas_aligned_never_cancer_controls(raw0)
raw1 <- nc$data
dm <- exwas_aligned_require_diet_mec(raw1)
raw <- dm$data
exwas_log("入队：从未患癌对照剔其他癌 ", nc$n_dropped_other_cancer,
          "；膳食∩MEC 后 n=", nrow(raw), " 病例=", sum(raw$DN == 1, na.rm = TRUE))

# 暴露候选（不在这里做全局人级 1/3 剔除）
id_cols <- c("cycle", "SEQN", "RIDAGEYR", "RIAGENDR", "c1", "DN", "k", "pool", "MCQ220",
             "DR1TKCAL", "DR2TKCAL", "Supp_VitE", "Supp_Any", "DSD010", "Age", "Gender")
exposures_raw <- setdiff(names(raw), c(
  id_cols, exwas_aligned_dag_pool(),
  "WBC", "NeutrophilCount", "Lymphocytes", "Mononuclear_cell_count", "PlateletCount",
  "NEUT", "MONO", "NLR", "SII", "SIRI",
  "SDMVPSU", "SDMVSTRA",
  "WTINT2YR", "WTMEC2YR", "WTDRD1", "WTDR2D", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2Y",
  "WTINT2YR_7", "WTMEC2YR_7", "WTDRD1_7", "WTDR2D_7", "WTSA2YR_7", "WTSB2YR_7", "WTSC2YR_7", "WTSVOC2Y_7"
))
exposures_raw <- exposures_raw[vapply(exposures_raw, function(nm) {
  is.numeric(exwas_to_num(raw[[nm]]))
}, logical(1))]
exposures <- exwas_aligned_dedup(exposures_raw)
exwas_log("暴露候选 ", length(exposures), "（已去重 DR2/SI/LA；尚未按暴露删人）")

# 仅剔「整列几乎不可用」的暴露；不因其他列缺失删人
analyte <- exwas_aligned_analyte_keep(raw, exposures, max_missing = 0.40)
exposures <- analyte$keep
utils::write.csv(analyte$notes, file.path(out, "Table_S1a_analyte_keep.csv"), row.names = FALSE)
exwas_log("列级保留 ", length(exposures), "（缺失>40% 剔列；不做全局人级 1/3）")

# DAG 全调整（取消 UV P 筛选）；VIF 仅诊断记录，不自动踢因果必要变量
# 但若某 DAG 变量在入队样本缺失率过高（如 2017–2018 婚姻 100% 缺失），则剔除该变量，否则整周期被 CC 清空
dag <- intersect(exwas_aligned_dag_pool(), names(raw))
miss_rate <- vapply(dag, function(v) mean(is.na(raw[[v]])), numeric(1))
# 总体缺失>25%，或任一周期缺失≥90%（如 2017–2018 婚姻全缺）→ 不进模
dag_drop <- names(miss_rate)[miss_rate > 0.25]
cyc_drop <- character(0)
for (v in dag) {
  byc <- tapply(is.na(raw[[v]]), as.character(raw$cycle), mean)
  if (any(byc >= 0.90, na.rm = TRUE)) cyc_drop <- c(cyc_drop, v)
}
dag_drop <- unique(c(dag_drop, cyc_drop))
if (length(dag_drop)) {
  exwas_log("DAG 变量因高缺失/整周期缺失暂不进模：",
            paste(sprintf("%s(总体%.0f%%)", dag_drop, 100 * miss_rate[dag_drop]), collapse = ", "))
  utils::write.csv(
    data.frame(variable = dag_drop, missing_rate = unname(miss_rate[dag_drop])),
    file.path(out, "covariate_dropped_high_missing.csv"), row.names = FALSE
  )
}
dag <- setdiff(dag, dag_drop)
raw <- exwas_aligned_as_model_frame(raw, dag)
vif_diag <- if (length(dag) >= 2L) exwas_aligned_vif_screen(raw, "DN", dag, 4) else list(dropped = data.frame())
covars <- dag
utils::write.csv(vif_diag$dropped, file.path(out, "covariate_vif_diagnostic_only.csv"), row.names = FALSE)
writeLines(c(
  paste("covars=", paste(covars, collapse = ",")),
  paste("dropped_high_missing=", paste(dag_drop, collapse = ",")),
  "DAG 全调整；已取消单因素 P 筛选。",
  "缺失>25% 的 DAG 变量不进模（避免整周期被完全病例清空，如 2017-2018 Marital_Status）。",
  "VIF 仅诊断（见 covariate_vif_diagnostic_only.csv），不自动删其余 DAG 变量。",
  "本版：每暴露独立 CC + survey 加权；不做全局人级 1/3 剔除。",
  "Willett residual 后结局模型仍含 Energy_ln。"
), file.path(out, "covariate_final.txt"))
exwas_log("协变量（DAG可用） ", paste(covars, collapse = ","))

# ---------- Model A: Day1 ----------
run_one_model <- function(raw_in, model_tag, diet_weight, do_dr12_avg, require_dr2) {
  df <- raw_in
  note_avg <- NULL
  if (isTRUE(require_dr2)) {
    dr2c <- exwas_aligned_require_dr2_complete(df, require_kcal2 = TRUE)
    df <- dr2c$data
    exwas_log(model_tag, " 双日完整后 n=", nrow(df), " 病例=", sum(df$DN == 1, na.rm = TRUE))
  }
  if (isTRUE(do_dr12_avg)) {
    diet_for_avg <- names(df)[grepl("^DR1[TI]", names(df))]
    avg <- exwas_aligned_dr12_average(df, nutrient_cols = diet_for_avg)
    df <- avg$data
    note_avg <- avg$notes
    utils::write.csv(note_avg, file.path(out, paste0("Table_S0_dr12_average_", model_tag, ".csv")),
                     row.names = FALSE)
  }
  # Willett residual on diet cols; keep energy for outcome model
  diet_cols <- exposures[grepl("^DR1", exposures)]
  diet_cols <- diet_cols[diet_cols %in% names(df)]
  ea <- exwas_aligned_energy_residual(df, diet_cols, energy_col = "DR1TKCAL")
  df <- ea$data
  utils::write.csv(ea$notes, file.path(out, paste0("Table_S0_energy_residual_", model_tag, ".csv")),
                   row.names = FALSE)
  # Energy_ln for outcome model (Willett 残差后仍调整能量)
  e <- exwas_to_num(df$DR1TKCAL)
  df$Energy_ln <- ifelse(is.finite(e) & e > 0, log(e), NA_real_)

  # 每暴露 transform（不全局删人）
  screened <- exwas_aligned_screen_by_family(df, exposures)
  df <- screened$data
  keep <- screened$keep
  fam <- exwas_aligned_family(sub("_(ln|bin)$", "", keep))
  names(fam) <- keep
  utils::write.csv(screened$notes, file.path(out, paste0("Table_S1_screen_", model_tag, ".csv")),
                   row.names = FALSE)

  # 权重映射
  wmap <- stats::setNames(
    vapply(keep, function(x) {
      base_x <- sub("_(ln|bin)$", "", x)
      if (grepl("^DR1|^DR2", base_x)) diet_weight else exwas_weight_for_exposure(df, base_x, diet_weight)
    }, character(1)),
    keep
  )
  # 把 transform 后名映射：diet always diet_weight
  wmap[grepl("^DR1", keep)] <- diet_weight

  exwas_log(model_tag, " survey ExWAS：暴露 ", length(keep),
            "；膳食权重 ", diet_weight, "；n_pool=", nrow(df))
  tab <- exwas_run_survey_per_exposure(
    df, "DN", keep, covars, wmap, families = fam, energy_col = "Energy_ln"
  )
  tab$model <- model_tag
  utils::write.csv(tab, file.path(out, paste0("Table_2_ExWAS_survey_", model_tag, ".csv")),
                   row.names = FALSE)
  n_fdr <- sum(is.finite(tab$q) & tab$q < 0.05, na.rm = TRUE)
  min_q <- suppressWarnings(min(tab$q, na.rm = TRUE))
  exwas_log(model_tag, " FDR<0.05 ", n_fdr, " / ", sum(is.finite(tab$p)),
            " 最小q ", min_q)

  # ATOA 专项诊断
  atoa_raw <- if ("DR1TATOA" %in% names(raw_in)) exwas_to_num(raw_in$DR1TATOA) else NULL
  atoa_row <- tab[tab$exposure %in% c("DR1TATOA_ln", "DR1TATOA_bin", "DR1TATOA"), , drop = FALSE]
  atoc_row <- tab[tab$exposure %in% c("DR1TATOC_ln", "DR1TATOC_bin", "DR1TATOC"), , drop = FALSE]
  diag <- data.frame(
    model = model_tag,
    n_pool = nrow(df),
    cases_pool = sum(df$DN == 1, na.rm = TRUE),
    atoa_zero_rate_raw = if (!is.null(atoa_raw)) mean(atoa_raw == 0, na.rm = TRUE) else NA_real_,
    atoa_na_rate_raw = if (!is.null(atoa_raw)) mean(!is.finite(atoa_raw)) else NA_real_,
    atoa_exposure = if (nrow(atoa_row)) atoa_row$exposure[1] else NA_character_,
    atoa_n = if (nrow(atoa_row)) atoa_row$n[1] else NA_integer_,
    atoa_OR = if (nrow(atoa_row)) atoa_row$OR[1] else NA_real_,
    atoa_p = if (nrow(atoa_row)) atoa_row$p[1] else NA_real_,
    atoa_q = if (nrow(atoa_row)) atoa_row$q[1] else NA_real_,
    atoc_OR = if (nrow(atoc_row)) atoc_row$OR[1] else NA_real_,
    atoc_q = if (nrow(atoc_row)) atoc_row$q[1] else NA_real_,
    stringsAsFactors = FALSE
  )
  # 相关：日均前原始 ATOA vs ATOC
  if (all(c("DR1TATOA", "DR1TATOC") %in% names(raw_in))) {
    a1 <- exwas_to_num(raw_in$DR1TATOA); a2 <- exwas_to_num(raw_in$DR1TATOC)
    okc <- is.finite(a1) & is.finite(a2)
    diag$cor_atoa_atoc <- if (sum(okc) > 50) stats::cor(a1[okc], a2[okc]) else NA_real_
  } else diag$cor_atoa_atoc <- NA_real_
  list(
    tab = tab, diag = diag, n = nrow(df), cases = sum(df$DN == 1, na.rm = TRUE),
    df = df, keep = keep, fam = fam, wmap = wmap, diet_weight = diet_weight
  )
}

models_run <- list()
diags <- list()
rA <- NULL
if (opt$model %in% c("day1", "both")) {
  # Day1：不做 DR12 平均；膳食权重 WTDRD1_7
  rA <- run_one_model(raw, "day1", diet_weight = "WTDRD1_7",
                      do_dr12_avg = FALSE, require_dr2 = FALSE)
  models_run[["day1"]] <- rA$tab
  diags[["day1"]] <- rA$diag
}
if (opt$model %in% c("day2", "both")) {
  # 双日完整：均值 + WTDR2D_7
  rB <- run_one_model(raw, "day2_complete", diet_weight = "WTDR2D_7",
                      do_dr12_avg = TRUE, require_dr2 = TRUE)
  models_run[["day2_complete"]] <- rB$tab
  diags[["day2_complete"]] <- rB$diag
}

# ---------- 可选：有 FDR 筛查结果后，再 --mice 做插补敏感性（默认关）----------
if (is.finite(opt$mice) && opt$mice >= 2L && !is.null(rA)) {
  exwas_log("【可选插补】MICE m=", opt$mice, "（只插协变量+Energy；须已有 CC FDR 筛查）")
  diet_imp <- character(0)
  mice_res <- exwas_run_survey_mice(
    rA$df, "DN", rA$keep, covars, rA$wmap,
    families = rA$fam, energy_col = "Energy_ln",
    diet_impute_cols = diet_imp,
    m = opt$mice, maxit = 10L, seed = 20261105L
  )
  tab_m <- mice_res$table
  tab_m$model <- "day1_mice_sensitivity"
  utils::write.csv(tab_m, file.path(out, "Table_2_ExWAS_survey_day1_mice.csv"), row.names = FALSE)
  models_run[["day1_mice_sensitivity"]] <- tab_m
  n_fdr_m <- sum(is.finite(tab_m$q) & tab_m$q < 0.05, na.rm = TRUE)
  exwas_log("day1_mice FDR<0.05 ", n_fdr_m, " / ", sum(is.finite(tab_m$p)),
            " 最小q ", suppressWarnings(min(tab_m$q, na.rm = TRUE)))
  writeLines(c(
    "role=OPTIONAL_SENSITIVITY (run only after CC FDR screen)",
    paste0("mice_m=", opt$mice),
    paste0("imputed_covars=", paste(covars, collapse = ",")),
    "imputed_energy=Energy_ln",
    "labs_not_imputed=TRUE",
    "pooling=Rubin on survey logOR"
  ), file.path(out, "Table_S0_mice_design.txt"))
} else {
  exwas_log("本轮仅完全病例筛 FDR（--mice 0）；出命中后再开 --mice")
}

# 各 model 列可能不同（mice 多 m/m_ok）——按并集对齐再 rbind
.all_nms <- unique(unlist(lapply(models_run, names)))
models_run <- lapply(models_run, function(tb) {
  miss <- setdiff(.all_nms, names(tb))
  for (nm in miss) tb[[nm]] <- NA
  tb[, .all_nms, drop = FALSE]
})
tab_all <- do.call(rbind, models_run)
utils::write.csv(tab_all, file.path(out, "Table_2_ExWAS_survey_all_models.csv"), row.names = FALSE)
diag_all <- do.call(rbind, diags)
utils::write.csv(diag_all, file.path(out, "Table_ATOA_diagnostics.csv"), row.names = FALSE)

# ---------- ATOA 两部分模型（Day1 主分析队列）----------
# Part1: any added α-tocopherol (DR1TATOA>0) vs 0
# Part2: among >0, log(ATOA) continuous, survey-weighted
exwas_log("ATOA 两部分模型（Day1 队列）")
dfA <- raw
a <- exwas_to_num(dfA$DR1TATOA)
dfA$ATOA_any <- ifelse(is.finite(a) & a > 0, 1, ifelse(is.finite(a), 0, NA_real_))
dfA$ATOA_pos_ln <- ifelse(is.finite(a) & a > 0, log(a), NA_real_)
e <- exwas_to_num(dfA$DR1TKCAL)
dfA$Energy_ln <- ifelse(is.finite(e) & e > 0, log(e), NA_real_)
dfA <- exwas_aligned_as_model_frame(dfA, dag)
# Part1 不用 Willett（零膨胀）；仍调能量
p1 <- exwas_fit_one_survey(dfA, "DN", "ATOA_any", dag, "WTDRD1_7", extra_covars = "Energy_ln")
p1$part <- "any_vs_zero"
# Part2：仅 ATOA>0；连续 log；可加 Willett 于正值子集
dfP <- dfA[is.finite(dfA$ATOA_pos_ln), , drop = FALSE]
# 对正值做 residual（可选）：用原始 ATOA 对能量残差再 ln
if (nrow(dfP) > 100L) {
  ea_p <- exwas_aligned_energy_residual(dfP, "DR1TATOA", "DR1TKCAL")
  dfP <- ea_p$data
  ap <- exwas_to_num(dfP$DR1TATOA)
  dfP$ATOA_pos_ln <- ifelse(is.finite(ap) & ap > 0, log(ap),
                            ifelse(is.finite(ap), log1p(pmax(ap, 0)), NA_real_))
}
p2 <- exwas_fit_one_survey(dfP, "DN", "ATOA_pos_ln", dag, "WTDRD1_7", extra_covars = "Energy_ln")
p2$part <- "positive_only_ln"
atoa_2p <- rbind(p1, p2)
atoa_2p$n_zero <- sum(is.finite(a) & a == 0, na.rm = TRUE)
atoa_2p$n_pos <- sum(is.finite(a) & a > 0, na.rm = TRUE)
atoa_2p$zero_rate <- mean(is.finite(a) & a == 0, na.rm = TRUE)
utils::write.csv(atoa_2p, file.path(out, "Table_ATOA_two_part_day1.csv"), row.names = FALSE)
exwas_log("ATOA 两部分：any p=", p1$p, "；positive-ln p=", p2$p,
          "；zero_rate=", round(mean(is.finite(a) & a == 0, na.rm = TRUE), 3))

utils::write.csv(
  data.frame(
    step = c(
      "cohort_after_never_cancer_diet_MEC",
      "design_note",
      "day1_n",
      "day2_complete_n"
    ),
    n = c(
      nrow(raw),
      NA_integer_,
      if (!is.null(models_run$day1)) models_run$day1$n[1] else NA_integer_,
      if (!is.null(models_run$day2_complete)) models_run$day2_complete$n[1] else NA_integer_
    ),
    cases = c(
      sum(raw$DN == 1, na.rm = TRUE),
      NA_integer_,
      if (!is.null(diags$day1)) diags$day1$cases_pool else NA_integer_,
      if (!is.null(diags$day2_complete)) diags$day2_complete$cases_pool else NA_integer_
    ),
    note = c(
      paste0("旧流程删人规则=A（全局大表1/3）；本版改为每暴露独立有效样本"),
      "主路径=完全病例筛FDR；MICE仅可选敏感性（默认关）；加权svyglm；DAG全调整；Willett+Energy_ln",
      "Day1 CC + WTDRD1_7",
      "双日完整均值 + WTDR2D_7"
    ),
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_attrition_redesign_v2.csv"),
  row.names = FALSE
)

# 简要 README
writeLines(c(
  "# ExWAS redesign v2",
  "",
  "## 本课题约定顺序（用户）",
  "1) 完全病例 / 单周期先筛 FDR",
  "2) 有 FDR 命中后再开 --mice 做插补敏感性",
  "默认 --mice 0。",
  "",
  "## 旧流程缺失规则",
  "A：宽表全局人级 1/3 剔人 → 已废。本版每暴露独立有效样本。",
  "",
  "## 本版要点",
  "1. 主筛：CC Day1 / 双日 survey ExWAS",
  "2. survey::svyglm + 暴露特异权重；DAG 全调整；Willett + Energy_ln",
  "3. 可选 --mice m（协变量+Energy；暴露/实验室不插）",
  "",
  paste0("label=", opt$label),
  paste0("include_2017=", opt$include_2017),
  paste0("mice_m=", opt$mice)
), file.path(out, "README_redesign_v2.txt"))

exwas_log("redesign_v2 写完 ", out)
