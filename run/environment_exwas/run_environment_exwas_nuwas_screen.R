#!/usr/bin/env Rscript
# 营养全关联筛查（对齐 Sci Rep 2025 NuWAS-CVD / NHANES 2007–2018 口径，迁到癌症结局）：
#   - 多周期合并（默认 2007–2018）
#   - 仅膳食日总量 DR1T*（可选用双日均值）
#   - 协变量缺失：mice m=5（不插暴露/结局）
#   - 主筛：不加权 logistic；连续暴露按 IQR；模型含总能量
#   - BH-FDR
#   - 对照：从未患癌；有膳食回忆
# 用法:
#   Rscript run_environment_exwas_nuwas_screen.R --nutrition <csv> --out <dir> \
#     [--label x] [--workers 4] [--cycles 2007-2018|2003-2018] [--min-age 20] \
#     [--mice 5] [--dr12-avg]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  nutrition = NULL, out = NULL, label = "nuwas", workers = "4",
  cycles = "2007-2018", min_age = 20, mice = 5L, dr12_avg = FALSE
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--nutrition" && i < length(args)) { opt$nutrition <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--label" && i < length(args)) { opt$label <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--cycles" && i < length(args)) { opt$cycles <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--min-age" && i < length(args)) { opt$min_age <- as.numeric(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--mice" && i < length(args)) { opt$mice <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--dr12-avg") { opt$dr12_avg <- TRUE; i <- i + 1L
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

cycle_keep <- if (identical(opt$cycles, "2003-2018")) {
  c("2003-2004", "2005-2006", "2007-2008", "2009-2010",
    "2011-2012", "2013-2014", "2015-2016", "2017-2018")
} else {
  c("2007-2008", "2009-2010", "2011-2012", "2013-2014", "2015-2016", "2017-2018")
}

exwas_log("[", opt$label, "] NuWAS 营养筛查：cycles=", opt$cycles,
          " min_age=", opt$min_age, " mice=", opt$mice, " dr12=", opt$dr12_avg)

raw0 <- exwas_aligned_load(to_host_path(opt$nutrition),
                           file.path(base, "data/D01_baseline_NHANES_0920.RData"))
raw0 <- exwas_aligned_mediators(raw0)
raw0$cycle <- as.character(raw0$cycle)
raw0$SEQN <- as.character(raw0$SEQN)
raw0 <- raw0[raw0$cycle %in% cycle_keep, , drop = FALSE]

# 能量
kcal_csv <- file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2018.csv")
if (!file.exists(kcal_csv)) kcal_csv <- file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2016.csv")
kcal <- exwas_read_csv(kcal_csv)
names(kcal) <- sub("^\ufeff", "", names(kcal))
kcal$SEQN <- as.character(kcal$SEQN); kcal$cycle <- as.character(kcal$cycle)
if ("DR1TKCAL" %in% names(raw0)) raw0$DR1TKCAL <- NULL
raw0 <- merge(raw0, kcal[, c("cycle", "SEQN", "DR1TKCAL"), drop = FALSE],
              by = c("cycle", "SEQN"), all.x = TRUE)

# DR2（可选双日均值）
if (isTRUE(opt$dr12_avg)) {
  dr2_csv <- file.path(base, "data/nutrition_extract/NHANES_DR2TOT_nut53_kcal_2003_2018.csv")
  if (!file.exists(dr2_csv)) {
    dr2_csv <- file.path(base, "data/nutrition_extract/NHANES_DR2TOT_nut53_kcal_2003_2016.csv")
  }
  if (file.exists(dr2_csv)) {
    dr2 <- exwas_read_csv(dr2_csv)
    names(dr2) <- sub("^\ufeff", "", names(dr2))
    dr2$SEQN <- as.character(dr2$SEQN); dr2$cycle <- as.character(dr2$cycle)
    add <- setdiff(names(dr2), c("cycle", "SEQN", "WTDR2D"))
    raw0 <- raw0[, setdiff(names(raw0), add), drop = FALSE]
    raw0 <- merge(raw0, dr2[, c("cycle", "SEQN", add), drop = FALSE],
                  by = c("cycle", "SEQN"), all.x = TRUE)
  }
}

# 年龄
age_v <- if ("Age" %in% names(raw0)) exwas_to_num(raw0$Age) else exwas_to_num(raw0$RIDAGEYR)
if (is.finite(opt$min_age)) {
  raw0 <- raw0[is.finite(age_v) & age_v >= opt$min_age, , drop = FALSE]
  exwas_log("Age>=", opt$min_age, " 后 n=", nrow(raw0))
}

# 从未患癌 + 有膳食回忆（能量>0 近似「有营养测量」）
nc <- exwas_aligned_never_cancer_controls(raw0)
d <- nc$data
e0 <- exwas_to_num(d$DR1TKCAL)
d <- d[is.finite(e0) & e0 > 0, , drop = FALSE]
exwas_log("从未患癌后 n=", nrow(nc$data), "；有 Day1 能量 n=", nrow(d),
          " 病例=", sum(d$DN == 1, na.rm = TRUE))

# 仅营养日总量
nut <- names(d)[grepl("^DR1T", names(d))]
nut <- setdiff(nut, c("DR1TKCAL", "DR1TNUMF", "DR1TSUGR")) # 能量不当暴露；糖若存在可留
# 保留所有 DR1T* 数值列（含糖若有）
nut <- nut[vapply(nut, function(nm) is.numeric(exwas_to_num(d[[nm]])), logical(1))]
nut <- exwas_aligned_dedup(nut)
# 缺测过高的营养列剔掉（>40%）
ak <- exwas_aligned_analyte_keep(d, nut, max_missing = 0.40)
nut <- ak$keep
utils::write.csv(ak$notes, file.path(out, "Table_S1_nutrient_keep.csv"), row.names = FALSE)
exwas_log("营养暴露候选 ", length(nut))

if (isTRUE(opt$dr12_avg)) {
  avg <- exwas_aligned_dr12_average(d, nutrient_cols = nut)
  d <- avg$data
  utils::write.csv(avg$notes, file.path(out, "Table_S0_dr12_average.csv"), row.names = FALSE)
  exwas_log("双日均值后 n=", nrow(d))
}

# 能量对数（进模，对齐 NuWAS「adjust total energy」）
ee <- exwas_to_num(d$DR1TKCAL)
d$Energy_ln <- ifelse(is.finite(ee) & ee > 0, log(ee), NA_real_)

# 协变量：NuWAS = age,sex,race,edu,PIR,BMI,smoke,drink,HTN,DM
# 癌症版：去掉疾病共病进模泄漏；用 DAG 人口学/行为 + 能量
covars <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR", "BMI",
    "Smoke", "Alcohol_drinking"),
  names(d)
)
# 高缺失协变量（如某周期婚姻全缺）剔除
mr <- vapply(covars, function(v) mean(is.na(d[[v]])), numeric(1))
drop_c <- names(mr)[mr > 0.25]
if (length(drop_c)) {
  exwas_log("协变量高缺失剔除: ", paste(drop_c, collapse = ","))
  covars <- setdiff(covars, drop_c)
}
d <- exwas_aligned_as_model_frame(d, covars)

writeLines(c(
  "method=NuWAS-style nutrient screen (Sci Rep 2025 CVD adapted to cancer)",
  paste0("cycles=", paste(cycle_keep, collapse = ",")),
  paste0("min_age=", opt$min_age),
  paste0("n=", nrow(d), " cases=", sum(d$DN == 1, na.rm = TRUE)),
  paste0("nutrients=", length(nut)),
  paste0("covars=", paste(covars, collapse = ",")),
  "energy_in_model=Energy_ln",
  paste0("mice_m=", opt$mice, " (covariates+energy only)"),
  "exwas=unweighted logistic, OR per IQR, BH-FDR",
  "labs_not_included=TRUE"
), file.path(out, "README_nuwas_screen.txt"))

# ---------- 筛查：mice → 每套不加权 ExWAS → Rubin ----------
run_unweighted_iqr_one <- function(df, y, x, covars, energy_col = "Energy_ln") {
  cov_use <- unique(c(covars, energy_col))
  cov_use <- cov_use[cov_use %in% names(df)]
  cols <- unique(c(y, x, cov_use))
  dd <- df[, cols, drop = FALSE]
  for (nm in setdiff(names(dd), c(y, x))) {
    if (is.character(dd[[nm]])) dd[[nm]] <- factor(dd[[nm]])
  }
  dd[[y]] <- exwas_to_num(dd[[y]])
  dd[[x]] <- exwas_to_num(dd[[x]])
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  n_ev <- sum(dd[[y]] == 1, na.rm = TRUE)
  if (nrow(dd) < 80L || n_ev < 10L || length(unique(dd[[y]])) < 2L) {
    return(list(beta = NA_real_, se = NA_real_, n = nrow(dd), n_events = n_ev, note = "sparse"))
  }
  cov_ok <- character(0)
  for (cv in setdiff(names(dd), c(y, x))) {
    v <- dd[[cv]]
    nlev <- if (is.factor(v)) length(unique(as.character(v))) else length(unique(v[is.finite(exwas_to_num(v))]))
    if (is.finite(nlev) && nlev >= 2L) cov_ok <- c(cov_ok, cv)
  }
  for (cv in cov_ok) if (is.factor(dd[[cv]])) dd[[cv]] <- droplevels(dd[[cv]])
  xv <- dd[[x]]
  if (length(unique(xv)) > 2L) {
    iqr <- stats::IQR(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- 1
    dd[[x]] <- dd[[x]] / iqr
  }
  fml <- stats::as.formula(paste(y, "~", paste(c(x, cov_ok), collapse = " + ")))
  fit <- tryCatch(stats::glm(fml, data = dd, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) return(list(beta = NA_real_, se = NA_real_, n = nrow(dd), n_events = n_ev, note = "fit_fail"))
  cf <- summary(fit)$coefficients
  rn <- rownames(cf)
  hit <- rn[rn == x | startsWith(rn, paste0(x))]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) return(list(beta = NA_real_, se = NA_real_, n = nrow(dd), n_events = n_ev, note = "coef_missing"))
  list(beta = cf[hit[1], 1], se = cf[hit[1], 2], n = nrow(dd), n_events = n_ev, note = "ok")
}

m <- as.integer(opt$mice)
if (!is.finite(m) || m < 1L) m <- 1L

if (m >= 2L) {
  if (!requireNamespace("mice", quietly = TRUE)) stop("需要 mice", call. = FALSE)
  imp_cols <- unique(c(covars, "Energy_ln"))
  use <- d[, imp_cols, drop = FALSE]
  for (nm in names(use)) {
    if (is.character(use[[nm]])) use[[nm]] <- factor(use[[nm]])
    else if (!is.factor(use[[nm]])) use[[nm]] <- exwas_to_num(use[[nm]])
  }
  use <- use[, names(use)[vapply(use, function(z) !all(is.na(z)), logical(1))], drop = FALSE]
  set.seed(20261119L)
  exwas_log("MICE m=", m, " 列=", paste(names(use), collapse = ","))
  imp <- mice::mice(use, m = m, maxit = 10L, printFlag = FALSE, seed = 20261119L)
} else {
  imp <- NULL
}

store <- lapply(nut, function(x) {
  list(beta = rep(NA_real_, m), se = rep(NA_real_, m), n = rep(NA_integer_, m),
       n_events = rep(NA_integer_, m), note = rep(NA_character_, m))
})
names(store) <- nut

nworkers <- suppressWarnings(as.integer(Sys.getenv("EXWAS_WORKERS", "1")))
if (is.na(nworkers) || nworkers < 1L) nworkers <- 1L

for (j in seq_len(m)) {
  dfi <- d
  if (!is.null(imp)) {
    comp <- mice::complete(imp, action = j)
    for (nm in names(comp)) dfi[[nm]] <- comp[[nm]]
  }
  dfi <- exwas_aligned_as_model_frame(dfi, intersect(covars, names(dfi)))
  if (nworkers > 1L && length(nut) > 1L) {
    cl <- parallel::makeCluster(nworkers)
    on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
    parallel::clusterExport(
      cl, c("run_unweighted_iqr_one", "exwas_to_num", "dfi", "covars"),
      envir = environment()
    )
    bts <- parallel::parLapply(cl, nut, function(x) {
      run_unweighted_iqr_one(dfi, "DN", x, covars, "Energy_ln")
    })
    parallel::stopCluster(cl)
    on.exit(NULL)
  } else {
    bts <- lapply(nut, function(x) run_unweighted_iqr_one(dfi, "DN", x, covars, "Energy_ln"))
  }
  for (ii in seq_along(nut)) {
    x <- nut[[ii]]; bt <- bts[[ii]]
    store[[x]]$beta[j] <- bt$beta
    store[[x]]$se[j] <- bt$se
    store[[x]]$n[j] <- bt$n
    store[[x]]$n_events[j] <- bt$n_events
    store[[x]]$note[j] <- bt$note
  }
  exwas_log("complete ", j, "/", m, " 完成")
}

rows <- lapply(nut, function(x) {
  st <- store[[x]]
  if (m >= 2L) {
    pl <- exwas_rubin_pool(st$beta, st$se)
    data.frame(
      exposure = x,
      n = suppressWarnings(as.integer(round(mean(st$n, na.rm = TRUE)))),
      n_events = suppressWarnings(as.integer(round(mean(st$n_events, na.rm = TRUE)))),
      OR = pl$OR, lo = pl$lo, hi = pl$hi, p = pl$p, m_ok = pl$m_ok, m = m,
      note = if (pl$m_ok >= 1L) "rubin_ok" else paste(unique(st$note), collapse = "|"),
      stringsAsFactors = FALSE
    )
  } else {
    ok <- is.finite(st$beta[1]) & is.finite(st$se[1])
    data.frame(
      exposure = x, n = st$n[1], n_events = st$n_events[1],
      OR = if (ok) exp(st$beta[1]) else NA_real_,
      lo = if (ok) exp(st$beta[1] - 1.96 * st$se[1]) else NA_real_,
      hi = if (ok) exp(st$beta[1] + 1.96 * st$se[1]) else NA_real_,
      p = if (ok) 2 * stats::pnorm(-abs(st$beta[1] / st$se[1])) else NA_real_,
      m_ok = as.integer(ok), m = 1L, note = st$note[1],
      stringsAsFactors = FALSE
    )
  }
})
tab <- do.call(rbind, rows)
tab$q <- exwas_fdr(tab$p)
tab <- tab[order(tab$q, tab$p), , drop = FALSE]
utils::write.csv(tab, file.path(out, "Table_2_NuWAS_nutrient_screen.csv"), row.names = FALSE)

hit <- tab[is.finite(tab$q) & tab$q < 0.05, , drop = FALSE]
utils::write.csv(hit, file.path(out, "Table_2_NuWAS_FDR_hits.csv"), row.names = FALSE)
exwas_log("FDR<0.05 营养数=", nrow(hit), " / ", sum(is.finite(tab$p)),
          "；最小q=", suppressWarnings(min(tab$q, na.rm = TRUE)),
          "；最佳=", if (nrow(tab)) tab$exposure[1] else NA)

if (nrow(hit)) print(hit[, c("exposure", "OR", "lo", "hi", "p", "q", "n", "n_events")])
else print(utils::head(tab[, c("exposure", "OR", "p", "q", "n", "n_events")], 10))

exwas_log("写完 ", out)
