#!/usr/bin/env Rscript
# 单周期 ExWAS（对齐文献「一个 NHANES 两年周期」+ redesign 口径）：
#   - 对照：从未患癌；膳食∩MEC
#   - 每暴露独立有效样本（不做全局人级 1/3）
#   - DAG 全调整；Willett residual + Energy_ln
#   - 默认不加权 logistic（与牙周炎文献 ExWAS 一致）；可选 --survey
#   - BH-FDR 仅在周期内；含 2017-2018
# 用法:
#   Rscript run_environment_exwas_cycle_redesign_v2.R --nutrition <csv> --out <dir> \
#     [--label x] [--workers 4] [--survey] [--mice 0] [--cycle 2013-2014|all]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  nutrition = NULL, out = NULL, label = "cycle_redesign", workers = "4",
  survey = FALSE, mice = 0L, cycle = "all"
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--nutrition" && i < length(args)) { opt$nutrition <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--label" && i < length(args)) { opt$label <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--survey") { opt$survey <- TRUE; i <- i + 1L
  } else if (a == "--mice" && i < length(args)) { opt$mice <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--cycle" && i < length(args)) { opt$cycle <- args[[i + 1L]]; i <- i + 2L
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

cycles_all <- c("2003-2004", "2005-2006", "2007-2008", "2009-2010",
                "2011-2012", "2013-2014", "2015-2016", "2017-2018")
cycles <- if (identical(opt$cycle, "all")) cycles_all else opt$cycle
cycles <- intersect(cycles, cycles_all)
if (!length(cycles)) stop("无有效 --cycle", call. = FALSE)

exwas_log("[", opt$label, "] 单周期 redesign：survey=", opt$survey, " mice=", opt$mice)
raw0 <- exwas_aligned_load(to_host_path(opt$nutrition),
                           file.path(base, "data/D01_baseline_NHANES_0920.RData"))
raw0 <- exwas_aligned_mediators(raw0)
raw0$cycle <- as.character(raw0$cycle)
raw0$SEQN <- as.character(raw0$SEQN)

kcal_csv <- file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2018.csv")
if (!file.exists(kcal_csv)) kcal_csv <- file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2016.csv")
kcal <- exwas_read_csv(kcal_csv)
names(kcal) <- sub("^\ufeff", "", names(kcal))
kcal$SEQN <- as.character(kcal$SEQN)
kcal$cycle <- as.character(kcal$cycle)
if ("DR1TKCAL" %in% names(raw0)) raw0$DR1TKCAL <- NULL
raw0 <- merge(raw0, kcal[, c("cycle", "SEQN", "DR1TKCAL"), drop = FALSE],
              by = c("cycle", "SEQN"), all.x = TRUE)

# 单周期权重：不除以 n_cycles（两年权重原样）
for (w in c("WTINT2YR", "WTMEC2YR", "WTDRD1", "WTDR2D", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2Y")) {
  if (w %in% names(raw0)) raw0[[paste0(w, "_7")]] <- exwas_to_num(raw0[[w]])
}

id_cols <- c("cycle", "SEQN", "RIDAGEYR", "RIAGENDR", "c1", "DN", "k", "pool", "MCQ220",
             "DR1TKCAL", "DR2TKCAL", "Supp_VitE", "Supp_Any", "DSD010", "Age", "Gender")
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
        cycle = cy, n0 = n0, cases0 = dn0, n_never = nrow(d1), n = nrow(d),
        cases = sum(d$DN == 1, na.rm = TRUE), n_exp = 0L, fdr = 0L,
        min_q = NA_real_, min_p = NA_real_, best = NA_character_,
        note = "病例或样本量过少", stringsAsFactors = FALSE
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
  e <- exwas_to_num(d$DR1TKCAL)
  d$Energy_ln <- ifelse(is.finite(e) & e > 0, log(e), NA_real_)

  analyte <- exwas_aligned_analyte_keep(d, exposures, max_missing = 0.40)
  screened <- exwas_aligned_screen_by_family(d, analyte$keep)
  d <- screened$data
  keep <- screened$keep
  if (!length(keep) || sum(d$DN == 1, na.rm = TRUE) < 10L) {
    return(list(
      tab = NULL,
      rank = data.frame(
        cycle = cy, n0 = n0, cases0 = dn0, n_never = nrow(d1), n = nrow(d),
        cases = sum(d$DN == 1, na.rm = TRUE), n_exp = length(keep), fdr = 0L,
        min_q = NA_real_, min_p = NA_real_, best = NA_character_,
        note = "筛选后暴露或病例不足", stringsAsFactors = FALSE
      )
    ))
  }
  fam <- exwas_aligned_family(sub("_(ln|bin)$", "", keep))
  names(fam) <- keep

  dag <- intersect(exwas_aligned_dag_pool(), names(d))
  miss_rate <- vapply(dag, function(v) mean(is.na(d[[v]])), numeric(1))
  dag <- setdiff(dag, names(miss_rate)[miss_rate > 0.25])
  d <- exwas_aligned_as_model_frame(d, dag)
  covars <- dag

  if (isTRUE(opt$survey)) {
    wmap <- stats::setNames(
      vapply(keep, function(x) {
        base_x <- sub("_(ln|bin)$", "", x)
        if (grepl("^DR1|^DR2", base_x)) "WTDRD1_7" else exwas_weight_for_exposure(d, base_x, "WTDRD1_7")
      }, character(1)),
      keep
    )
    wmap[grepl("^DR1", keep)] <- "WTDRD1_7"
    if (is.finite(opt$mice) && opt$mice >= 2L) {
      mice_res <- exwas_run_survey_mice(
        d, "DN", keep, covars, wmap, families = fam, energy_col = "Energy_ln",
        diet_impute_cols = character(0), m = opt$mice, maxit = 8L, seed = 20261105L
      )
      tab <- mice_res$table
      tab$note_model <- "mice_survey"
    } else {
      tab <- exwas_run_survey_per_exposure(
        d, "DN", keep, covars, wmap, families = fam, energy_col = "Energy_ln"
      )
      tab$note_model <- "cc_survey"
    }
  } else {
    # 文献主 ExWAS：不加权；膳食模型仍加 Energy_ln
    # 对膳食暴露：把 Energy_ln 并入 covars
    diet_keep <- keep[grepl("^DR1", keep)]
    lab_keep <- setdiff(keep, diet_keep)
    tabs <- list()
    if (length(diet_keep)) {
      tabs[[1]] <- exwas_run_unweighted(d, "DN", diet_keep, unique(c(covars, "Energy_ln")), fam[diet_keep])
    }
    if (length(lab_keep)) {
      tabs[[2]] <- exwas_run_unweighted(d, "DN", lab_keep, covars, fam[lab_keep])
    }
    tab <- do.call(rbind, tabs)
    # 全表重新 BH（周期内）
    tab$q <- exwas_fdr(tab$p)
    if (!all(is.na(tab$family))) {
      tab$q_family <- ave(tab$p, tab$family, FUN = function(p) stats::p.adjust(p, method = "BH"))
    }
    tab$note_model <- "cc_unweighted"
  }

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
    note = paste0("剔其他癌", nc$n_dropped_other_cancer, ";膳食∩MEC剔", dm$n_dropped,
                  ";per-exp;DAG;model=", unique(tab$note_model)[1]),
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
    list(tab = NULL, rank = data.frame(
      cycle = cy, n0 = NA, cases0 = NA, n_never = NA, n = NA, cases = NA,
      n_exp = 0L, fdr = 0L, min_q = NA_real_, min_p = NA_real_, best = NA_character_,
      note = conditionMessage(e), stringsAsFactors = FALSE
    ))
  })
  all_rank[[cy]] <- one$rank
  if (!is.null(one$tab)) all_tabs[[cy]] <- one$tab
  exwas_log("  n=", one$rank$n, " 病例=", one$rank$cases,
            " 暴露=", one$rank$n_exp, " FDR=", one$rank$fdr,
            " min_q=", one$rank$min_q, " best=", one$rank$best)
}

rank_df <- do.call(rbind, all_rank)
utils::write.csv(rank_df, file.path(out, "Table_cycle_rank.csv"), row.names = FALSE)
if (length(all_tabs)) {
  # 列对齐
  nms <- unique(unlist(lapply(all_tabs, names)))
  all_tabs <- lapply(all_tabs, function(tb) {
    for (nm in setdiff(nms, names(tb))) tb[[nm]] <- NA
    tb[, nms, drop = FALSE]
  })
  utils::write.csv(do.call(rbind, all_tabs), file.path(out, "Table_ExWAS_by_cycle.csv"), row.names = FALSE)
} else {
  utils::write.csv(data.frame(), file.path(out, "Table_ExWAS_by_cycle.csv"), row.names = FALSE)
}

writeLines(c(
  "# 单周期 ExWAS redesign v2",
  "对齐文献：每个两年周期单独分析，周期内 BH-FDR。",
  paste0("加权=", opt$survey, "（默认 FALSE=不加权，同牙周炎文献 ExWAS）"),
  paste0("mice_m=", opt$mice, "（0=完全病例；>1 仅 --survey 时走 Rubin）"),
  "不做全局人级 1/3；DAG 全调整；Willett + Energy_ln。",
  paste0("总 FDR 命中周期数=", sum(rank_df$fdr > 0, na.rm = TRUE),
         "；命中条数合计=", sum(rank_df$fdr, na.rm = TRUE))
), file.path(out, "README_cycle_redesign_v2.txt"))

exwas_log("[", opt$label, "] 写完 ", out)
print(rank_df[, c("cycle", "n", "cases", "n_exp", "fdr", "min_q", "best")])
