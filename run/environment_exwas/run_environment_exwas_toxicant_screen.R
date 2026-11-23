#!/usr/bin/env Rscript
# 环境毒物 ExWAS 筛查（对齐 EWAS-new / Dong 2026；仅乳腺癌或前列腺癌）
# 多周期合并；不加权 ExWAS + BH-FDR；mice m=5/maxit=5/seed=123456
# 不做 ERS / RCS / WQS / 中介（等 FDR 命中后再挂）
#
# 用法:
#   Rscript run_environment_exwas_toxicant_screen.R --disease prostate|breast|pancancer --out <dir>
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  disease = NULL, out = NULL, workers = "1", min_age = 20L,
  cycles = NULL, include_smoke = FALSE, require_urine_creat = FALSE,
  creat_adjust = TRUE, require_weight = NULL, weighted = FALSE,
  weight_col = "WTSA2YR",
  # none=粗模型; age=仅Age; demo=Age+Race+Education; full=原文迁移全套(默认无Smoke)
  covars_set = "full"
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--disease" && i < length(args)) { opt$disease <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--min-age" && i < length(args)) { opt$min_age <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--cycles" && i < length(args)) { opt$cycles <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--include-smoke") { opt$include_smoke <- TRUE; i <- i + 1L
  } else if (a == "--no-smoke") { opt$include_smoke <- FALSE; i <- i + 1L
  } else if (a == "--require-urine-creat") { opt$require_urine_creat <- TRUE; i <- i + 1L
  } else if (a == "--no-creat-adjust") { opt$creat_adjust <- FALSE; i <- i + 1L
  } else if (a == "--require-weight" && i < length(args)) {
    opt$require_weight <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--require-weight") {
    opt$require_weight <- "WTSA2YR"; i <- i + 1L
  } else if (a == "--weighted") {
    opt$weighted <- TRUE
    if (is.null(opt$require_weight)) opt$require_weight <- opt$weight_col
    i <- i + 1L
  } else if (a == "--weight-col" && i < length(args)) {
    opt$weight_col <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--covars-set" && i < length(args)) {
    opt$covars_set <- args[[i + 1L]]; i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}
opt$covars_set <- match.arg(opt$covars_set, c("none", "age", "demo", "full"))
if (isTRUE(opt$weighted) && is.null(opt$require_weight)) {
  opt$require_weight <- opt$weight_col
}
if (is.null(opt$disease) || is.null(opt$out)) stop("需要 --disease 与 --out", call. = FALSE)
opt$disease <- match.arg(opt$disease, c("prostate", "breast", "pancancer"))

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(root)
Sys.setenv(EXWAS_WORKERS = opt$workers)
source(file.path(root, "R/environment_exwas_core.R"))
source(file.path(root, "R/environment_exwas_aligned.R"))
source(file.path(root, "R/environment_exwas_toxicant.R"))

to_host_path <- function(p) {
  if (.Platform$OS.type != "windows") return(p)
  p <- chartr("\\", "/", p)
  if (grepl("^/mnt/[A-Za-z]/", p)) paste0(toupper(substr(p, 6, 6)), ":/", substring(p, 8)) else p
}

data_dir <- to_host_path("/mnt/g/02block_result/51_gastric cancer/environment_41380607/data")
out <- to_host_path(opt$out)
exwas_ensure_dir(out)

exwas_log("==== ", opt$disease, " 毒物 ExWAS 筛查（文献对齐）====")
built <- exwas_tox_build_cancer_table(opt$disease, data_dir, min_age = opt$min_age)
d0 <- built$data
# 可选单周期（原文 2013-2014）
if (!is.null(opt$cycles) && nzchar(opt$cycles)) {
  keep_cyc <- trimws(strsplit(opt$cycles, ",", fixed = TRUE)[[1]])
  d0 <- d0[as.character(d0$cycle) %in% keep_cyc, , drop = FALSE]
  exwas_log("限制周期: ", paste(keep_cyc, collapse = ", "),
            " → n=", nrow(d0), " 病例=", sum(d0$DN == 1, na.rm = TRUE))
}
# 必须有尿肌酐（尿毒物校正分母；血毒物样本也强制同口径）
n_before_ucr <- nrow(d0)
if (isTRUE(opt$require_urine_creat)) {
  ucr0 <- if ("URXUCR" %in% names(d0)) exwas_to_num(d0$URXUCR) else rep(NA_real_, nrow(d0))
  ok_ucr <- is.finite(ucr0) & ucr0 > 0
  d0 <- d0[ok_ucr, , drop = FALSE]
  exwas_log("要求 URXUCR>0: ", n_before_ucr, "→", nrow(d0),
            " 病例=", sum(d0$DN == 1, na.rm = TRUE),
            "（剔除无尿肌酐 ", n_before_ucr - nrow(d0), "）")
}
# 原文描述/亚组/中介用 wtsa2yr；无正权重则剔出分析集（ExWAS 本体仍可不加权）
if (!is.null(opt$require_weight) && nzchar(opt$require_weight)) {
  wcol <- opt$require_weight
  # 别名：WTSVOC2Y 等偶见截断名
  if (!wcol %in% names(d0) && wcol == "WTSA2YR" && "WTSA2YR" %in% names(d0)) {
    # no-op
  }
  if (!wcol %in% names(d0)) {
    stop("缺少权重列 ", wcol, "；现有: ",
         paste(grep("^WT", names(d0), value = TRUE), collapse = ","), call. = FALSE)
  }
  n_before_w <- nrow(d0)
  ww <- exwas_to_num(d0[[wcol]])
  ok_w <- is.finite(ww) & ww > 0
  d0 <- d0[ok_w, , drop = FALSE]
  exwas_log("要求 ", wcol, ">0: ", n_before_w, "→", nrow(d0),
            " 病例=", sum(d0$DN == 1, na.rm = TRUE),
            "（剔除无权重 ", n_before_w - nrow(d0), "）")
}
tox <- built$tox_cols
tox <- tox[tox %in% names(d0)]
exwas_log("合并后 n=", nrow(d0), " 病例=", sum(d0$DN == 1, na.rm = TRUE),
          " 对照=", sum(d0$DN == 0, na.rm = TRUE),
          " 周期数=", length(unique(d0$cycle)), " 毒物列=", length(tox))
if (nrow(d0) < 80L || sum(d0$DN == 1, na.rm = TRUE) < 10L) {
  stop("样本量过小，无法 ExWAS: n=", nrow(d0), " cases=", sum(d0$DN == 1, na.rm = TRUE), call. = FALSE)
}

# 尿肌酐校正（尿液毒物）；--no-creat-adjust 时保留原始 µg/L / ng/mL（贴原文图注单位）
if (isTRUE(opt$creat_adjust)) {
  cr <- exwas_tox_creatinine_adjust(d0, tox, creat_col = "URXUCR")
  d1 <- cr$data
  utils::write.csv(
    data.frame(note = cr$note, n_adjusted = length(cr$adjusted),
               adjusted = paste(cr$adjusted, collapse = ";")),
    file.path(out, "Table_S0_creatinine_adjust.csv"), row.names = FALSE
  )
} else {
  d1 <- d0
  utils::write.csv(
    data.frame(note = "skipped_raw_urine_ugL_or_ngmL", n_adjusted = 0L, adjusted = ""),
    file.path(out, "Table_S0_creatinine_adjust.csv"), row.names = FALSE
  )
  exwas_log("跳过尿肌酐除法校正：尿毒物保留原始浓度单位")
}

# 分析物三档筛查
scr <- exwas_tox_screen_transform(d1, tox)
utils::write.csv(scr$notes, file.path(out, "Table_S1_analyte_LOD_screen.csv"), row.names = FALSE)
exwas_log("分析物保留 ", length(scr$keep), " / ", length(tox),
          "（drop=", sum(scr$notes$decision == "drop"),
          " binary=", sum(scr$notes$decision == "binary"),
          " log=", sum(scr$notes$decision == "log"), ")")

# 人缺失 >1/3：按该周期可测分析物集合（多周期对齐文献意图）
person <- exwas_tox_drop_person_missing(
  scr$data, scr$keep, max_frac = 1 / 3, cycle_col = "cycle",
  raw_from_model = sub("_(ln|bin)$", "", scr$keep)
)
df <- person$data
exwas_log("人级缺失>1/3（周期内面板）剔除 ", person$n_excluded,
          " → n=", nrow(df), " 病例=", sum(df$DN == 1, na.rm = TRUE))

attrition <- data.frame(
  step = c(
    paste0("merged_outcome_x_toxicant_agege", opt$min_age, "_nevercancer_ctrl",
           if (isTRUE(opt$require_urine_creat)) "_require_URXUCR" else ""),
    "after_analyte_LOD_screen_pool",
    "after_person_missing_le_1_3"
  ),
  n = c(nrow(d0), nrow(d0), nrow(df)),
  cases = c(sum(d0$DN == 1, na.rm = TRUE), sum(d0$DN == 1, na.rm = TRUE), sum(df$DN == 1, na.rm = TRUE)),
  stringsAsFactors = FALSE
)
utils::write.csv(attrition, file.path(out, "Table_S0_attrition.csv"), row.names = FALSE)

# 协变量方案（默认无 Smoke；泛癌双性别含 Gender，对齐原文）
sex_strat <- opt$disease != "pancancer"
want <- switch(
  opt$covars_set,
  none = character(0),
  age = c("Age"),
  demo = if (isTRUE(sex_strat)) {
    c("Age", "Race", "Education")
  } else {
    c("Age", "Gender", "Race", "Education")
  },
  full = exwas_tox_cancer_covars(
    sex_stratified = sex_strat, include_smoke = isTRUE(opt$include_smoke)
  )
)
covars <- character(0)
for (v in want) {
  if (v == "PIR" && "PIR_cat" %in% names(df)) covars <- c(covars, "PIR_cat")
  else if (v == "BMI" && "BMI_cat" %in% names(df)) covars <- c(covars, "BMI_cat")
  else if (v %in% names(df)) covars <- c(covars, v)
}
covars <- unique(covars)
if (length(covars)) {
  mr <- vapply(covars, function(v) mean(is.na(df[[v]])), numeric(1))
  drop_hi <- names(mr)[mr > 0.40]
  if (length(drop_hi)) {
    exwas_log("协变量缺失>40% 剔除: ", paste(drop_hi, collapse = ", "))
    covars <- setdiff(covars, drop_hi)
    mr <- mr[covars]
  }
} else {
  mr <- numeric(0)
}
df <- exwas_aligned_as_model_frame(df, covars)
exwas_log("协变量方案=", opt$covars_set, ": ",
          if (length(covars)) paste(covars, collapse = ", ") else "(none/crude)")
utils::write.csv(
  data.frame(
    covariate = if (length(covars)) covars else "(none)",
    missing_rate = if (length(covars)) as.numeric(mr[covars]) else NA_real_,
    note = paste0("covars_set=", opt$covars_set,
                  if (isTRUE(opt$include_smoke)) "+Smoke" else "+noSmoke"),
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_S0_covariates.csv"), row.names = FALSE
)

fam_map <- stats::setNames(built$code$Family, built$code$Labels)
# model_col → raw
raw_of <- sub("_(ln|bin)$", "", scr$keep)
families <- stats::setNames(unname(fam_map[raw_of]), scr$keep)

if (isTRUE(opt$weighted)) {
  if (!length(covars)) stop("加权 ExWAS 暂不支持 covars_set=none", call. = FALSE)
  wcol <- if (!is.null(opt$require_weight) && nzchar(opt$require_weight)) {
    opt$require_weight
  } else {
    opt$weight_col
  }
  for (need_svy in c(wcol, "SDMVPSU", "SDMVSTRA")) {
    if (!need_svy %in% names(df)) {
      stop("加权 ExWAS 缺少列 ", need_svy, call. = FALSE)
    }
  }
  # 多周期：层号可能跨周期撞车 → 用 cycle×strata 嵌套
  df$SDMVSTRA_cyc <- as.integer(
    interaction(as.character(df$cycle), exwas_to_num(df$SDMVSTRA), drop = TRUE, lex.order = TRUE)
  )
  wmap <- stats::setNames(as.list(rep(wcol, length(scr$keep))), scr$keep)
  exwas_log("加权 ExWAS：svyglm + mice/Rubin；weight=", wcol,
            "；strata=SDMVSTRA_cyc；PSU=SDMVPSU")
  svy <- exwas_run_survey_mice(
    df, "DN", scr$keep, covars,
    weight_map = wmap,
    families = families,
    energy_col = NULL,
    m = 5L, maxit = 5L, seed = 123456L,
    psu = "SDMVPSU", strata = "SDMVSTRA_cyc"
  )
  tab <- svy$table
  tab$exposure_raw <- sub("_(ln|bin)$", "", tab$exposure)
  tab$transform <- ifelse(endsWith(tab$exposure, "_bin"), "binary",
                          ifelse(endsWith(tab$exposure, "_ln"), "log", "other"))
} else if (length(covars) < 2L) {
  # 粗模型或仅 1 个协变量：mice 至少要 2 列，改走完整病例 glm
  exwas_log(
    if (!length(covars)) "粗模型 ExWAS（无协变量）"
    else paste0("完整病例 ExWAS（协变量少，跳过 mice）: ", paste(covars, collapse = "+"))
  )
  rows <- lapply(scr$keep, function(x) {
    one <- exwas_fit_one(df, "DN", x, covars)
    raw <- sub("_(ln|bin)$", "", x)
    n_ev <- NA_integer_
    if (x %in% names(df) && "DN" %in% names(df)) {
      ok <- is.finite(exwas_to_num(df[[x]])) & is.finite(exwas_to_num(df$DN))
      for (cv in covars) {
        if (!cv %in% names(df)) next
        v <- df[[cv]]
        ok <- ok & if (is.factor(v) || is.character(v)) !is.na(v) else is.finite(exwas_to_num(v))
      }
      n_ev <- as.integer(sum(exwas_to_num(df$DN[ok]) == 1, na.rm = TRUE))
    }
    data.frame(
      exposure = x, exposure_raw = raw,
      transform = if (endsWith(x, "_bin")) "binary" else if (endsWith(x, "_ln")) "log" else "other",
      n = one$n, n_events = n_ev,
      beta = if (is.finite(one$OR) && one$OR > 0) log(one$OR) else NA_real_,
      se = NA_real_,
      OR = one$OR, lo = one$lo, hi = one$hi, p = one$p,
      m_ok = 1L, m = 1L,
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)
  tab$q <- exwas_fdr(tab$p)
  tab$family <- unname(families[tab$exposure])
} else {
  tab <- exwas_run_unweighted_mice(
    df, "DN", scr$keep, covars,
    m = 5L, maxit = 5L, seed = 123456L,
    families = families
  )
}
tab <- tab[order(tab$q, tab$p), ]
# 挂显示名
lab <- stats::setNames(built$code$Exposure, built$code$Labels)
tab$exposure_name <- unname(lab[tab$exposure_raw])

utils::write.csv(tab, file.path(out, "Table_2_ExWAS_toxicant_screen.csv"), row.names = FALSE)
hit <- tab[is.finite(tab$q) & tab$q < 0.05, , drop = FALSE]
utils::write.csv(hit, file.path(out, "Table_2b_ExWAS_FDR_hits.csv"), row.names = FALSE)

summ <- data.frame(
  disease = opt$disease,
  n = nrow(df),
  n_cases = sum(df$DN == 1, na.rm = TRUE),
  n_exposures_tested = nrow(tab),
  n_fdr_lt05 = nrow(hit),
  min_q = if (nrow(tab)) min(tab$q, na.rm = TRUE) else NA_real_,
  min_p = if (nrow(tab)) min(tab$p, na.rm = TRUE) else NA_real_,
  covars = paste(covars, collapse = "+"),
  mice = "m=5;maxit=5;seed=123456",
  design = if (isTRUE(opt$weighted)) {
    paste0("survey_svyglm_mice_Rubin_BH_FDR_weight=",
           if (is.null(opt$require_weight)) opt$weight_col else opt$require_weight)
  } else {
    "unweighted_ExWAS_BH_FDR"
  },
  cycles = if (is.null(opt$cycles)) "multi" else opt$cycles,
  include_smoke = isTRUE(opt$include_smoke),
  min_age = opt$min_age,
  require_urine_creat = isTRUE(opt$require_urine_creat),
  creat_adjust = isTRUE(opt$creat_adjust),
  require_weight = if (is.null(opt$require_weight)) NA_character_ else opt$require_weight,
  weighted = isTRUE(opt$weighted),
  covars_set = opt$covars_set,
  stringsAsFactors = FALSE
)
utils::write.csv(summ, file.path(out, "Table_compare_summary.csv"), row.names = FALSE)

writeLines(c(
  paste0("# ExWAS toxicant screen — ", opt$disease),
  "Literature alignment (Dong 2026 EWAS-new):",
  paste0("- Age >= ", opt$min_age, "; cases DN=1; controls never-cancer (MCQ220=2)"),
  paste0("- Require urine creatinine (URXUCR>0): ", isTRUE(opt$require_urine_creat)),
  paste0("- Require weight >0: ",
         if (is.null(opt$require_weight)) "FALSE" else opt$require_weight,
         " (paper wtsa2yr)"),
  paste0("- ExWAS design: ",
         if (isTRUE(opt$weighted)) {
           "WEIGHTED svyglm (WTSA2YR + PSU/strata) + mice/Rubin (paper ExWAS was unweighted; this is sensitivity)"
         } else {
           "UNWEIGHTED glm (paper ExWAS default)"
         }),
  paste0("- Creatinine division adjust: ", isTRUE(opt$creat_adjust),
         if (isTRUE(opt$creat_adjust)) " (urine / URXUCR * 100)" else " (raw urine ug/L or ng/mL)"),
  paste0("- Cycles: ", summ$cycles),
  if (isTRUE(opt$creat_adjust)) {
    "- Urine toxicants: concentration / URXUCR * 100"
  } else {
    "- Urine toxicants: raw concentration (no creatinine division; paper Fig units)"
  },
  "- Analyte: drop if missing>40% (within measured cycles) or underLOD>90%; binary if underLOD>30%; else ln",
  "- Person: drop if missing >1/3 of analytes measurable in that participant's cycle",
  "- mice m=5 maxit=5 seed=123456 on covariates; Rubin pool",
  "- Unweighted logistic ExWAS; continuous OR per IQR; BH-FDR",
  paste0("- Covariates: ", paste(covars, collapse = "+")),
  paste0("- Smoke in model: ", isTRUE(opt$include_smoke),
         " (paper main ExWAS excludes Smoke; sensitivity only)"),
  "- Paper logic: DAG+confounders; dental N/A dropped; eGFR CKD-EPI2021",
  "- ERS/RCS/WQS/mediation NOT run in this screen"
), file.path(out, "README_toxicant_exwas_screen.txt"))

exwas_log("FDR hits=", nrow(hit), " min_q=", signif(summ$min_q, 4))
exwas_log("写完 ", out)
print(summ)
print(utils::head(tab[, c("exposure", "exposure_name", "transform", "n", "n_events", "OR", "p", "q")], 10))
