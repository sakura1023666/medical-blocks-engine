#!/usr/bin/env Rscript
# 严格纳排 + Willett 能量残差 的「按周期」ExWAS：
#   对照 MCQ220=2；膳食∩MEC；DR1*~DR1TKCAL residual；实验室 LOD / 膳食 log1p；
#   分析物缺失>40% → 人缺失>1/3；每周期内 BH-FDR。
# 用法:
#   Rscript run_environment_exwas_cycle_scan_strict_energy.R --nutrition <csv> --out <dir> [--label name]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(nutrition = NULL, out = NULL, label = "cycle", workers = "4", min_age = NA_real_)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--nutrition" && i < length(args)) { opt$nutrition <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--label" && i < length(args)) { opt$label <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--min-age" && i < length(args)) { opt$min_age <- as.numeric(args[[i + 1L]]); i <- i + 2L
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

cycles <- c("2003-2004", "2005-2006", "2007-2008", "2009-2010",
            "2011-2012", "2013-2014", "2015-2016")

exwas_log("[", opt$label, "] 读取宽表 + baseline + DR1TKCAL")
raw0 <- exwas_aligned_load(to_host_path(opt$nutrition),
                           file.path(base, "data/D01_baseline_NHANES_0920.RData"))
raw0 <- exwas_aligned_mediators(raw0)
raw0$cycle <- as.character(raw0$cycle)
raw0$SEQN <- as.character(raw0$SEQN)
kcal <- exwas_read_csv(file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2016.csv"))
names(kcal) <- sub("^\ufeff", "", names(kcal))
kcal$SEQN <- as.character(kcal$SEQN)
kcal$cycle <- as.character(kcal$cycle)
if ("DR1TKCAL" %in% names(raw0)) raw0$DR1TKCAL <- NULL
raw0 <- merge(raw0, kcal[, c("cycle", "SEQN", "DR1TKCAL"), drop = FALSE],
              by = c("cycle", "SEQN"), all.x = TRUE)
if (is.finite(opt$min_age)) {
  age_v <- if ("Age" %in% names(raw0)) exwas_to_num(raw0$Age) else exwas_to_num(raw0$RIDAGEYR)
  raw0 <- raw0[is.finite(age_v) & age_v >= opt$min_age, , drop = FALSE]
  exwas_log("限龄 Age>=", opt$min_age, "后 n=", nrow(raw0),
            " 病例=", sum(raw0$DN == 1, na.rm = TRUE))
}

id_cols <- c("cycle", "SEQN", "RIDAGEYR", "RIAGENDR", "c1", "DN", "k", "pool", "MCQ220", "DR1TKCAL")
weight_cols <- c(
  "SDMVPSU", "SDMVSTRA",
  "WTINT2YR", "WTMEC2YR", "WTDRD1", "WTDR2D", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2Y",
  "WTINT2YR_7", "WTMEC2YR_7", "WTDRD1_7", "WTDR2D_7", "WTSA2YR_7", "WTSB2YR_7", "WTSC2YR_7", "WTSVOC2Y_7"
)
exclude_exp <- c(id_cols, exwas_aligned_dag_pool(),
                 "WBC", "NeutrophilCount", "Lymphocytes", "Mononuclear_cell_count", "PlateletCount",
                 "NEUT", "MONO", "NLR", "SII", "SIRI", weight_cols)

run_one_cycle <- function(cy) {
  d0 <- raw0[raw0$cycle == cy, , drop = FALSE]
  n0 <- nrow(d0)
  dn0 <- sum(d0$DN == 1, na.rm = TRUE)
  nc <- exwas_aligned_never_cancer_controls(d0)
  d1 <- nc$data
  dm <- exwas_aligned_require_diet_mec(d1)
  d <- dm$data
  if (nrow(d) < 80L || sum(d$DN == 1, na.rm = TRUE) < 10L) {
    return(list(
      tab = NULL,
      rank = data.frame(
        cycle = cy, n0 = n0, cases0 = dn0,
        n_never = nrow(d1), n = nrow(d), cases = sum(d$DN == 1, na.rm = TRUE),
        n_exp = 0L, fdr = 0L, min_q = NA_real_, min_p = NA_real_, best = NA_character_,
        note = "病例或样本量过少，跳过",
        stringsAsFactors = FALSE
      )
    ))
  }

  exposures_raw <- setdiff(names(d), exclude_exp)
  exposures_raw <- exposures_raw[vapply(exposures_raw, function(nm) {
    is.numeric(exwas_to_num(d[[nm]]))
  }, logical(1))]
  exposures <- exwas_aligned_dedup(exposures_raw)

  diet_cols <- exposures[grepl("^DR1", exposures)]
  ea <- exwas_aligned_energy_residual(d, diet_cols, energy_col = "DR1TKCAL")
  d <- ea$data

  analyte <- exwas_aligned_analyte_keep(d, exposures, max_missing = 0.40)
  person <- exwas_aligned_drop_person_missing(d, analyte$keep, max_frac = 1 / 3)
  d <- person$data
  screened <- exwas_aligned_screen_by_family(d, analyte$keep)
  d <- screened$data
  keep <- screened$keep
  if (!length(keep) || sum(d$DN == 1, na.rm = TRUE) < 10L) {
    return(list(
      tab = NULL,
      rank = data.frame(
        cycle = cy, n0 = n0, cases0 = dn0,
        n_never = nrow(d1), n = nrow(d), cases = sum(d$DN == 1, na.rm = TRUE),
        n_exp = length(keep), fdr = 0L, min_q = NA_real_, min_p = NA_real_, best = NA_character_,
        note = "筛选后暴露或病例不足",
        stringsAsFactors = FALSE
      )
    ))
  }

  fam <- exwas_aligned_family(sub("_(ln|bin)$", "", keep))
  names(fam) <- keep

  dag <- intersect(exwas_aligned_dag_pool(), names(d))
  d <- exwas_aligned_as_model_frame(d, dag)
  # 单周期病例少：协变量放宽，Age 强制；其余仍走单因素 p<0.05，但允许最终只剩 Age
  uni <- exwas_aligned_univariate(d, "DN", dag, 0.05)
  vif <- exwas_aligned_vif_screen(d, "DN", uni$keep, 4)
  covars <- vif$keep
  if (!length(covars)) covars <- intersect("Age", names(d))

  tab <- exwas_run_unweighted(d, "DN", keep, covars, fam)
  tab$cycle <- cy
  tab$cohort_n <- nrow(d)
  tab$cases <- sum(d$DN == 1, na.rm = TRUE)
  tab$n_covars <- length(covars)
  tab$covars <- paste(covars, collapse = "+")

  ok <- is.finite(tab$q)
  fdr_n <- sum(ok & tab$q < 0.05)
  best_i <- if (any(ok)) which.min(tab$q) else NA_integer_
  rank <- data.frame(
    cycle = cy, n0 = n0, cases0 = dn0,
    n_never = nrow(d1), n = nrow(d), cases = sum(d$DN == 1, na.rm = TRUE),
    n_exp = nrow(tab), fdr = fdr_n,
    min_q = if (any(ok)) min(tab$q, na.rm = TRUE) else NA_real_,
    min_p = if (any(is.finite(tab$p))) min(tab$p, na.rm = TRUE) else NA_real_,
    best = if (is.finite(best_i)) as.character(tab$exposure[best_i]) else NA_character_,
    note = paste0("剔除其他癌", nc$n_dropped_other_cancer, ";膳食∩MEC剔", dm$n_dropped,
                  ";人缺>1/3剔", person$n_excluded, ";cov=", paste(covars, collapse = "+")),
    stringsAsFactors = FALSE
  )
  list(tab = tab, rank = rank)
}

all_tabs <- list()
all_rank <- list()
for (cy in cycles) {
  exwas_log("[", opt$label, "] 周期 ", cy)
  one <- tryCatch(run_one_cycle(cy), error = function(e) {
    exwas_log("周期失败 ", cy, ": ", conditionMessage(e))
    list(
      tab = NULL,
      rank = data.frame(
        cycle = cy, n0 = NA, cases0 = NA, n_never = NA, n = NA, cases = NA,
        n_exp = 0L, fdr = 0L, min_q = NA_real_, min_p = NA_real_, best = NA_character_,
        note = conditionMessage(e), stringsAsFactors = FALSE
      )
    )
  })
  all_rank[[cy]] <- one$rank
  if (!is.null(one$tab)) all_tabs[[cy]] <- one$tab
  exwas_log("  n=", one$rank$n, " 病例=", one$rank$cases,
            " 暴露=", one$rank$n_exp, " FDR=", one$rank$fdr,
            " min_q=", one$rank$min_q)
}

rank_df <- do.call(rbind, all_rank)
utils::write.csv(rank_df, file.path(out, "Table_cycle_rank.csv"), row.names = FALSE)
if (length(all_tabs)) {
  tab_df <- do.call(rbind, all_tabs)
  utils::write.csv(tab_df, file.path(out, "Table_ExWAS_by_cycle.csv"), row.names = FALSE)
} else {
  utils::write.csv(data.frame(), file.path(out, "Table_ExWAS_by_cycle.csv"), row.names = FALSE)
}

writeLines(c(
  "按周期 ExWAS（严格纳排 + Willett 能量残差）：对照仅 MCQ220=2；WTDRD1>0∩WTMEC2YR>0；",
  "膳食 DR1* 对 DR1TKCAL 做 residual（Willett AJCN 1997）；实验室不调能量；",
  "暴露=原142并集DR1TOT53；周期内缺失>40%/人缺>1/3；膳食 log1p / 实验室 LOD；",
  "ExWAS 不加权；BH 仅在周期内。单周期命中属探索性。",
  paste0("总 FDR 命中周期数=", sum(rank_df$fdr > 0, na.rm = TRUE),
         "；命中条数合计=", sum(rank_df$fdr, na.rm = TRUE))
), file.path(out, "README_cycle_scan.txt"))

exwas_log("[", opt$label, "] 周期扫描写完 ", out)
print(rank_df[, c("cycle", "n", "cases", "n_exp", "fdr", "min_q", "best")])
