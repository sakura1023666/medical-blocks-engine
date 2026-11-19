#!/usr/bin/env Rscript
# NuWAS 不加权 vs 调查加权对照（同一样本 / 暴露 / 协变量 / mice；只改设计）
# 权重：WTDRD1/8（2003–2018 八个完整两年周期）
# 设计：先对「有限设计变量」建 svydesign，再用 subset(.analytic & .use_x) 进模
# 用法:
#   Rscript run_environment_exwas_nuwas_survey_compare.R --nutrition <csv> --out <dir> \
#     [--unweighted-csv <先前NuWAS表>] [--min-age 65] [--cycles 2003-2018] [--mice 5]
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(
  nutrition = NULL, out = NULL, label = "nuwas_svy", workers = "4",
  cycles = "2003-2018", min_age = 65, mice = 5L, unweighted_csv = NULL
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
  } else if (a == "--unweighted-csv" && i < length(args)) { opt$unweighted_csv <- args[[i + 1L]]; i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}
if (is.null(opt$nutrition) || is.null(opt$out)) stop("需要 --nutrition 与 --out", call. = FALSE)
if (!requireNamespace("survey", quietly = TRUE)) stop("需要 survey", call. = FALSE)
if (!requireNamespace("mice", quietly = TRUE)) stop("需要 mice", call. = FALSE)

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(root)
Sys.setenv(EXWAS_WORKERS = opt$workers)
source(file.path(root, "R/environment_exwas_core.R"))
source(file.path(root, "R/environment_exwas_aligned.R"))
options(survey.lonely.psu = "adjust")

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
n_cyc <- length(cycle_keep)

exwas_log("[", opt$label, "] survey compare：cycles=", opt$cycles,
          " n_cyc=", n_cyc, " min_age=", opt$min_age, " WTDRD1/", n_cyc)

raw0 <- exwas_aligned_load(to_host_path(opt$nutrition),
                           file.path(base, "data/D01_baseline_NHANES_0920.RData"))
raw0 <- exwas_aligned_mediators(raw0)
raw0$cycle <- as.character(raw0$cycle)
raw0$SEQN <- as.character(raw0$SEQN)
raw0 <- raw0[raw0$cycle %in% cycle_keep, , drop = FALSE]

kcal <- exwas_read_csv(file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2018.csv"))
names(kcal) <- sub("^\ufeff", "", names(kcal))
kcal$SEQN <- as.character(kcal$SEQN); kcal$cycle <- as.character(kcal$cycle)
if ("DR1TKCAL" %in% names(raw0)) raw0$DR1TKCAL <- NULL
d <- merge(raw0, kcal[, c("cycle", "SEQN", "DR1TKCAL"), drop = FALSE],
           by = c("cycle", "SEQN"), all.x = TRUE)

# 多年膳食权重
d$WTDRD1_8 <- exwas_to_num(d$WTDRD1) / n_cyc
d$SDMVPSU <- exwas_to_num(d$SDMVPSU)
d$SDMVSTRA <- exwas_to_num(d$SDMVSTRA)
d$Age_num <- if ("Age" %in% names(d)) exwas_to_num(d$Age) else exwas_to_num(d$RIDAGEYR)
d$DN <- exwas_to_num(d$DN)
d$MCQ220 <- exwas_to_num(d$MCQ220)
e0 <- exwas_to_num(d$DR1TKCAL)
d$Energy_ln <- ifelse(is.finite(e0) & e0 > 0, log(e0), NA_real_)

# 与 NuWAS 相同的分析旗标（人级）
d$.analytic <- is.finite(d$Age_num) & d$Age_num >= opt$min_age &
  ((d$DN == 1L) | (d$DN == 0L & d$MCQ220 == 2)) &
  is.finite(e0) & e0 > 0

# 设计域：有限权重/PSU/层（官方：先建完整设计再 subset）
d$.design_ok <- is.finite(d$WTDRD1_8) & d$WTDRD1_8 > 0 &
  is.finite(d$SDMVPSU) & is.finite(d$SDMVSTRA)

exwas_log("全表 n=", nrow(d),
          "；analytic=", sum(d$.analytic, na.rm = TRUE),
          " 病例=", sum(d$.analytic & d$DN == 1, na.rm = TRUE),
          "；design_ok=", sum(d$.design_ok, na.rm = TRUE))

# 营养列（与 NuWAS 相同规则）
nut <- names(d)[grepl("^DR1T", names(d))]
nut <- setdiff(nut, c("DR1TKCAL", "DR1TNUMF", "DR1TSUGR"))
nut <- nut[vapply(nut, function(nm) is.numeric(exwas_to_num(d[[nm]])), logical(1))]
nut <- exwas_aligned_dedup(nut)
ak <- exwas_aligned_analyte_keep(d[d$.analytic, , drop = FALSE], nut, max_missing = 0.40)
nut <- ak$keep
exwas_log("营养暴露 ", length(nut))

covars <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR", "BMI",
    "Smoke", "Alcohol_drinking"),
  names(d)
)
# 在 analytic 上剔高缺失协变量
mr <- vapply(covars, function(v) mean(is.na(d[[v]][d$.analytic])), numeric(1))
covars <- setdiff(covars, names(mr)[mr > 0.25])
d <- exwas_aligned_as_model_frame(d, covars)

# mice：仅 analytic 行的协变量+能量（与 NuWAS 同 seed）
m <- as.integer(opt$mice)
da <- d[d$.analytic, , drop = FALSE]
imp_cols <- unique(c(covars, "Energy_ln"))
use <- da[, imp_cols, drop = FALSE]
for (nm in names(use)) {
  if (is.character(use[[nm]])) use[[nm]] <- factor(use[[nm]])
  else if (!is.factor(use[[nm]])) use[[nm]] <- exwas_to_num(use[[nm]])
}
use <- use[, names(use)[vapply(use, function(z) !all(is.na(z)), logical(1))], drop = FALSE]
set.seed(20261119L)
exwas_log("MICE m=", m, " 列=", paste(names(use), collapse = ","))
imp <- mice::mice(use, m = m, maxit = 10L, printFlag = FALSE, seed = 20261119L)

# ---- 单暴露：不加权 / 调查加权（返回 beta, se）----
fit_unweighted <- function(dd, y, x, covars) {
  cov_use <- unique(c(covars, "Energy_ln"))
  cols <- unique(c(y, x, cov_use))
  cols <- cols[cols %in% names(dd)]
  z <- dd[, cols, drop = FALSE]
  for (nm in setdiff(names(z), c(y, x))) if (is.character(z[[nm]])) z[[nm]] <- factor(z[[nm]])
  z[[y]] <- exwas_to_num(z[[y]]); z[[x]] <- exwas_to_num(z[[x]])
  z <- z[stats::complete.cases(z), , drop = FALSE]
  n_ev <- sum(z[[y]] == 1, na.rm = TRUE)
  if (nrow(z) < 80L || n_ev < 10L || length(unique(z[[y]])) < 2L) {
    return(list(beta = NA_real_, se = NA_real_, n = nrow(z), n_events = n_ev, note = "sparse"))
  }
  cov_ok <- character(0)
  for (cv in setdiff(names(z), c(y, x))) {
    v <- z[[cv]]
    nlev <- if (is.factor(v)) length(unique(as.character(v))) else length(unique(v[is.finite(exwas_to_num(v))]))
    if (is.finite(nlev) && nlev >= 2L) cov_ok <- c(cov_ok, cv)
  }
  for (cv in cov_ok) if (is.factor(z[[cv]])) z[[cv]] <- droplevels(z[[cv]])
  xv <- z[[x]]
  if (length(unique(xv)) > 2L) {
    iqr <- stats::IQR(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- 1
    z[[x]] <- z[[x]] / iqr
  }
  fml <- stats::as.formula(paste(y, "~", paste(c(x, cov_ok), collapse = " + ")))
  fit <- tryCatch(stats::glm(fml, data = z, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) return(list(beta = NA_real_, se = NA_real_, n = nrow(z), n_events = n_ev, note = "fit_fail"))
  cf <- summary(fit)$coefficients
  rn <- rownames(cf)
  hit <- rn[rn == x | startsWith(rn, paste0(x))]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) return(list(beta = NA_real_, se = NA_real_, n = nrow(z), n_events = n_ev, note = "coef_missing"))
  list(beta = cf[hit[1], 1], se = cf[hit[1], 2], n = nrow(z), n_events = n_ev, note = "ok")
}

# 全表 + analytic 旗标；对单暴露标记 .use 后：design → subset(.use)
fit_survey_design_subset <- function(d_full, y, x, covars) {
  cov_use <- unique(c(covars, "Energy_ln"))
  # 与不加权相同的完全病例规则，标在全表上（勿用 isTRUE：对向量只取首元素）
  ok <- as.logical(d_full$.analytic) & as.logical(d_full$.design_ok) &
    is.finite(exwas_to_num(d_full[[y]])) & is.finite(exwas_to_num(d_full[[x]]))
  ok[is.na(ok)] <- FALSE
  for (cv in cov_use) {
    if (!cv %in% names(d_full)) next
    v <- d_full[[cv]]
    if (is.factor(v) || is.character(v)) ok <- ok & !is.na(v)
    else ok <- ok & is.finite(exwas_to_num(v))
  }
  ok[is.na(ok)] <- FALSE
  d_full$.use <- ok
  n_use <- sum(d_full$.use, na.rm = TRUE)
  n_ev <- sum(d_full$.use & exwas_to_num(d_full[[y]]) == 1, na.rm = TRUE)
  if (n_use < 80L || n_ev < 10L) {
    return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev, note = "sparse"))
  }
  # 设计域：design_ok 行（可大于 analytic）
  dd <- d_full[d_full$.design_ok, , drop = FALSE]
  dd$.w <- dd$WTDRD1_8
  # IQR 缩放仅在 .use 行上估，再写回（避免用全设计域污染尺度）
  xv_use <- exwas_to_num(dd[[x]][dd$.use])
  scale <- 1
  if (length(unique(xv_use[is.finite(xv_use)])) > 2L) {
    iqr <- stats::IQR(xv_use, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv_use, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- 1
    scale <- iqr
  }
  dd[[x]] <- exwas_to_num(dd[[x]]) / scale
  # 丢无变异协变量（按 .use 子集）
  cov_ok <- character(0)
  for (cv in cov_use) {
    if (!cv %in% names(dd)) next
    v <- dd[[cv]][dd$.use]
    nlev <- if (is.factor(v) || is.character(v)) length(unique(as.character(v))) else length(unique(v[is.finite(exwas_to_num(v))]))
    if (is.finite(nlev) && nlev >= 2L) cov_ok <- c(cov_ok, cv)
  }
  for (cv in cov_ok) {
    if (is.character(dd[[cv]])) dd[[cv]] <- factor(dd[[cv]])
    if (is.factor(dd[[cv]])) dd[[cv]] <- droplevels(dd[[cv]])
  }
  des <- tryCatch(
    survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~.w, data = dd, nest = TRUE),
    error = function(e) NULL
  )
  if (is.null(des)) {
    return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev, note = "design_fail"))
  }
  # 官方推荐 subset；用 variables$.use 索引，避免 NSE 在循环里丢列
  keep_u <- which(as.logical(des$variables$.use))
  if (!length(keep_u) || length(keep_u) < 80L) {
    return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev, note = "subset_fail"))
  }
  des_u <- des[keep_u, ]
  fml <- stats::as.formula(paste(y, "~", paste(c(x, cov_ok), collapse = " + ")))
  err <- NULL
  fit <- tryCatch(
    survey::svyglm(fml, design = des_u, family = stats::quasibinomial()),
    error = function(e) { err <<- conditionMessage(e); NULL }
  )
  if (is.null(fit)) {
    return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev,
                note = paste0("fit_fail:", substr(as.character(err), 1, 80))))
  }
  cf <- summary(fit)$coefficients
  rn <- rownames(cf)
  hit <- rn[rn == x | startsWith(rn, paste0(x))]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) {
    return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev, note = "coef_missing"))
  }
  list(beta = cf[hit[1], 1], se = cf[hit[1], 2], n = n_use, n_events = n_ev, note = "ok")
}

store_u <- lapply(nut, function(x) list(beta = rep(NA_real_, m), se = rep(NA_real_, m),
                                        n = rep(NA_integer_, m), n_events = rep(NA_integer_, m),
                                        note = rep(NA_character_, m)))
store_s <- lapply(nut, function(x) list(beta = rep(NA_real_, m), se = rep(NA_real_, m),
                                        n = rep(NA_integer_, m), n_events = rep(NA_integer_, m),
                                        note = rep(NA_character_, m)))
names(store_u) <- names(store_s) <- nut

for (j in seq_len(m)) {
  comp <- mice::complete(imp, action = j)
  # 把插补写回全表 analytic 行（按原行序）；因子按 complete 水平重建
  d_j <- d
  idx <- which(d_j$.analytic)
  for (nm in names(comp)) {
    if (is.factor(comp[[nm]])) {
      d_j[[nm]] <- as.character(d_j[[nm]])
      d_j[[nm]][idx] <- as.character(comp[[nm]])
      d_j[[nm]] <- factor(d_j[[nm]])
    } else {
      d_j[[nm]][idx] <- comp[[nm]]
    }
  }
  da_j <- d_j[d_j$.analytic, , drop = FALSE]

  for (x in nut) {
    bu <- fit_unweighted(da_j, "DN", x, covars)
    bs <- fit_survey_design_subset(d_j, "DN", x, covars)
    store_u[[x]]$beta[j] <- bu$beta; store_u[[x]]$se[j] <- bu$se
    store_u[[x]]$n[j] <- bu$n; store_u[[x]]$n_events[j] <- bu$n_events
    store_u[[x]]$note[j] <- bu$note
    store_s[[x]]$beta[j] <- bs$beta; store_s[[x]]$se[j] <- bs$se
    store_s[[x]]$n[j] <- bs$n; store_s[[x]]$n_events[j] <- bs$n_events
    store_s[[x]]$note[j] <- bs$note
  }
  # 诊断：首套插补打印前 3 个营养 survey note
  if (j == 1L) {
    exwas_log("survey note sample: ",
              paste(sprintf("%s=%s", nut[1:3], vapply(nut[1:3], function(z) store_s[[z]]$note[1], "")),
                    collapse = "; "))
  }
  exwas_log("complete ", j, "/", m, " 完成")
}

df_complete_svy <- tryCatch({
  dd0 <- d[d$.design_ok, , drop = FALSE]
  des0 <- survey::svydesign(
    ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTDRD1_8,
    data = dd0, nest = TRUE
  )
  as.numeric(survey::degf(des0))
}, error = function(e) Inf)
exwas_log("Rubin df_complete(survey degf)=", df_complete_svy)

pool_tab <- function(store, tag, df_c = Inf) {
  rows <- lapply(names(store), function(x) {
    st <- store[[x]]
    pl <- exwas_rubin_pool(st$beta, st$se, df_complete = df_c)
    data.frame(
      exposure = x, method = tag,
      n = suppressWarnings(as.integer(round(mean(st$n, na.rm = TRUE)))),
      n_events = suppressWarnings(as.integer(round(mean(st$n_events, na.rm = TRUE)))),
      beta = if (!is.null(pl$beta)) pl$beta else NA_real_,
      se = if (!is.null(pl$se)) pl$se else NA_real_,
      OR = pl$OR %||% NA_real_, lo = pl$lo %||% NA_real_, hi = pl$hi %||% NA_real_,
      p = pl$p %||% NA_real_,
      df = pl$df %||% NA_real_, df_complete = pl$df_complete %||% NA_real_,
      m_ok = pl$m_ok %||% 0L, stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)
  tab$q <- exwas_fdr(tab$p)
  tab
}

tab_u <- pool_tab(store_u, "unweighted", Inf)
tab_s <- pool_tab(store_s, "survey_WTDRD1_over_8", df_complete_svy)
# 诊断 note（首套）
utils::write.csv(
  data.frame(
    exposure = nut,
    note_uw_m1 = vapply(nut, function(z) store_u[[z]]$note[1], ""),
    note_svy_m1 = vapply(nut, function(z) store_s[[z]]$note[1], ""),
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_fit_notes_m1.csv"), row.names = FALSE
)
utils::write.csv(tab_u, file.path(out, "Table_NuWAS_unweighted_rerun.csv"), row.names = FALSE)
utils::write.csv(tab_s, file.path(out, "Table_NuWAS_survey_WTDRD1_8.csv"), row.names = FALSE)

cmp <- merge(
  tab_u[, c("exposure", "n", "n_events", "beta", "se", "OR", "p", "q")],
  tab_s[, c("exposure", "beta", "se", "OR", "p", "q")],
  by = "exposure", suffixes = c("_uw", "_svy")
)
cmp$delta_beta <- cmp$beta_svy - cmp$beta_uw
cmp$ratio_se <- cmp$se_svy / cmp$se_uw
cmp$sign_same <- sign(cmp$beta_uw) == sign(cmp$beta_svy)
cmp$p_uw_lt05 <- cmp$p_uw < 0.05
cmp$p_svy_lt05 <- cmp$p_svy < 0.05
cmp$q_uw_lt05 <- cmp$q_uw < 0.05
cmp$q_svy_lt05 <- cmp$q_svy < 0.05
cmp <- cmp[order(cmp$q_svy, cmp$p_svy), ]
utils::write.csv(cmp, file.path(out, "Table_compare_unweighted_vs_survey.csv"), row.names = FALSE)

# 若提供先前不加权表，再对一下（容许重跑种子一致）
if (!is.null(opt$unweighted_csv) && file.exists(to_host_path(opt$unweighted_csv))) {
  old <- utils::read.csv(to_host_path(opt$unweighted_csv), stringsAsFactors = FALSE)
  if (all(c("exposure", "OR", "p", "q") %in% names(old))) {
    ck <- merge(old[, c("exposure", "OR", "p", "q")],
                tab_u[, c("exposure", "OR", "p", "q")],
                by = "exposure", suffixes = c("_prior", "_rerun"))
    utils::write.csv(ck, file.path(out, "Table_check_unweighted_rerun_vs_prior.csv"), row.names = FALSE)
  }
}

summ <- data.frame(
  n_analytic = sum(d$.analytic),
  n_cases = sum(d$.analytic & d$DN == 1, na.rm = TRUE),
  n_nutrients = length(nut),
  weight = paste0("WTDRD1/", n_cyc),
  fdr_uw = sum(tab_u$q < 0.05, na.rm = TRUE),
  fdr_svy = sum(tab_s$q < 0.05, na.rm = TRUE),
  min_q_uw = suppressWarnings(min(tab_u$q, na.rm = TRUE)),
  min_q_svy = suppressWarnings(min(tab_s$q, na.rm = TRUE)),
  median_ratio_se = stats::median(cmp$ratio_se, na.rm = TRUE),
  prop_sign_same = mean(cmp$sign_same, na.rm = TRUE),
  n_p05_uw = sum(tab_u$p < 0.05, na.rm = TRUE),
  n_p05_svy = sum(tab_s$p < 0.05, na.rm = TRUE),
  stringsAsFactors = FALSE
)
utils::write.csv(summ, file.path(out, "Table_compare_summary.csv"), row.names = FALSE)
writeLines(c(
  "method=unweighted vs survey compare",
  "design=svydesign(full design_ok) -> subset(.use=analytic & CC for nutrient)",
  paste0("weight=WTDRD1/", n_cyc),
  paste0("min_age=", opt$min_age),
  paste0("mice_m=", m, " seed=20261119 Rubin then BH"),
  paste0("fdr_uw=", summ$fdr_uw, " fdr_svy=", summ$fdr_svy),
  paste0("median_SE_svy/SE_uw=", round(summ$median_ratio_se, 3)),
  paste0("sign_concordance=", round(summ$prop_sign_same, 3))
), file.path(out, "README_survey_compare.txt"))

exwas_log("FDR uw=", summ$fdr_uw, " svy=", summ$fdr_svy,
          "；median SE_svy/SE_uw=", round(summ$median_ratio_se, 3),
          "；方向一致=", round(summ$prop_sign_same, 3))
print(utils::head(cmp[, c("exposure", "beta_uw", "beta_svy", "se_uw", "se_svy",
                          "ratio_se", "p_uw", "p_svy", "q_uw", "q_svy", "sign_same")], 12))
exwas_log("写完 ", out)
