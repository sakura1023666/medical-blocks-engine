#!/usr/bin/env Rscript
# 前列腺癌 Age≥65 加权 NuWAS：技术核对 + Top5 深挖（不跑 WQS/ERS/中介）
# 1) 设计：SDMVSTRA/SDMVPSU + WTDRD1/8
# 2) mice m=5 vs m=20 稳定性（Rubin + df.complete=survey::degf）
# 3) 每营养素：有效 n/病例、缺失、IQR、零值比
# 4) Top5：uw vs svy、±能量、Day1 vs Day2 分布与关联
#
args <- commandArgs(trailingOnly = TRUE)
opt <- list(nutrition = NULL, out = NULL, workers = "1", mice_stability = 20L)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--nutrition" && i < length(args)) { opt$nutrition <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--out" && i < length(args)) { opt$out <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--mice-stability" && i < length(args)) { opt$mice_stability <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}
if (is.null(opt$nutrition) || is.null(opt$out)) stop("需要 --nutrition --out", call. = FALSE)

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) {
  normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/")
} else getwd()
setwd(root)
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

cycle_keep <- c("2003-2004", "2005-2006", "2007-2008", "2009-2010",
                "2011-2012", "2013-2014", "2015-2016", "2017-2018")
n_cyc <- length(cycle_keep)
min_age <- 65

# ---- 读入与设计旗标 ----
raw0 <- exwas_aligned_load(to_host_path(opt$nutrition),
                           file.path(base, "data/D01_baseline_NHANES_0920.RData"))
raw0 <- exwas_aligned_mediators(raw0)
raw0$cycle <- as.character(raw0$cycle); raw0$SEQN <- as.character(raw0$SEQN)
raw0 <- raw0[raw0$cycle %in% cycle_keep, , drop = FALSE]
kcal <- exwas_read_csv(file.path(base, "data/nutrition_extract/NHANES_DR1TKCAL_2003_2018.csv"))
names(kcal) <- sub("^\ufeff", "", names(kcal))
kcal$SEQN <- as.character(kcal$SEQN); kcal$cycle <- as.character(kcal$cycle)
if ("DR1TKCAL" %in% names(raw0)) raw0$DR1TKCAL <- NULL
d <- merge(raw0, kcal[, c("cycle", "SEQN", "DR1TKCAL")], by = c("cycle", "SEQN"), all.x = TRUE)

# DR2（须含 WTDR2D，供 Day2 加权）
dr2_csv <- file.path(base, "data/nutrition_extract/NHANES_DR2TOT_nut53_kcal_2003_2018.csv")
if (file.exists(dr2_csv)) {
  dr2 <- exwas_read_csv(dr2_csv)
  names(dr2) <- sub("^\ufeff", "", names(dr2))
  dr2$SEQN <- as.character(dr2$SEQN); dr2$cycle <- as.character(dr2$cycle)
  add <- setdiff(names(dr2), c("cycle", "SEQN"))
  d <- d[, setdiff(names(d), add), drop = FALSE]
  d <- merge(d, dr2[, c("cycle", "SEQN", add), drop = FALSE], by = c("cycle", "SEQN"), all.x = TRUE)
}

d$WTDRD1_8 <- exwas_to_num(d$WTDRD1) / n_cyc
d$WTDR2D_8 <- if ("WTDR2D" %in% names(d)) exwas_to_num(d$WTDR2D) / n_cyc else NA_real_
d$SDMVPSU <- exwas_to_num(d$SDMVPSU)
d$SDMVSTRA <- exwas_to_num(d$SDMVSTRA)
d$Age_num <- if ("Age" %in% names(d)) exwas_to_num(d$Age) else exwas_to_num(d$RIDAGEYR)
d$DN <- exwas_to_num(d$DN); d$MCQ220 <- exwas_to_num(d$MCQ220)
e1 <- exwas_to_num(d$DR1TKCAL)
d$Energy_ln <- ifelse(is.finite(e1) & e1 > 0, log(e1), NA_real_)
d$.analytic <- is.finite(d$Age_num) & d$Age_num >= min_age &
  ((d$DN == 1L) | (d$DN == 0L & d$MCQ220 == 2)) & is.finite(e1) & e1 > 0
d$.design_ok <- is.finite(d$WTDRD1_8) & d$WTDRD1_8 > 0 &
  is.finite(d$SDMVPSU) & is.finite(d$SDMVSTRA)

# 设计核对
des0 <- survey::svydesign(
  ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~WTDRD1_8,
  data = d[d$.design_ok, , drop = FALSE], nest = TRUE
)
df_complete <- tryCatch(as.numeric(survey::degf(des0)), error = function(e) NA_real_)
utils::write.csv(
  data.frame(
    n_cycles = n_cyc, weight = paste0("WTDRD1/", n_cyc),
    psu = "SDMVPSU", strata = "SDMVSTRA",
    n_design_ok = sum(d$.design_ok), n_analytic = sum(d$.analytic),
    n_cases = sum(d$.analytic & d$DN == 1, na.rm = TRUE),
    degf_design_ok = df_complete,
    lonely_psu = "adjust",
    stringsAsFactors = FALSE
  ),
  file.path(out, "Table_S0_survey_design_check.csv"), row.names = FALSE
)
exwas_log("设计 degf=", df_complete, " analytic=", sum(d$.analytic),
          " 病例=", sum(d$.analytic & d$DN == 1, na.rm = TRUE))

covars <- intersect(
  c("Age", "Gender", "Race", "Education", "Marital_Status", "PIR", "BMI",
    "Smoke", "Alcohol_drinking"),
  names(d)
)
mr <- vapply(covars, function(v) mean(is.na(d[[v]][d$.analytic])), numeric(1))
covars <- setdiff(covars, names(mr)[mr > 0.25])
d <- exwas_aligned_as_model_frame(d, covars)

nut <- names(d)[grepl("^DR1T", names(d))]
nut <- setdiff(nut, c("DR1TKCAL", "DR1TNUMF", "DR1TSUGR"))
nut <- nut[vapply(nut, function(nm) is.numeric(exwas_to_num(d[[nm]])), logical(1))]
nut <- exwas_aligned_dedup(nut)
ak <- exwas_aligned_analyte_keep(d[d$.analytic, , drop = FALSE], nut, max_missing = 0.40)
nut <- ak$keep

# ---- 每营养素样本诊断（analytic 内）----
diag_rows <- lapply(nut, function(x) {
  xx <- exwas_to_num(d[[x]][d$.analytic])
  dn <- d$DN[d$.analytic]
  ok <- is.finite(xx) & is.finite(dn)
  data.frame(
    exposure = x,
    n_analytic = sum(d$.analytic),
    n_nonmiss = sum(ok),
    miss_rate = 1 - mean(ok),
    n_cases_nonmiss = sum(ok & dn == 1),
    zero_rate = if (sum(ok)) mean(xx[ok] == 0) else NA_real_,
    iqr = if (sum(ok) > 2) stats::IQR(xx[ok]) else NA_real_,
    median = if (sum(ok)) stats::median(xx[ok]) else NA_real_,
    p01 = if (sum(ok)) as.numeric(stats::quantile(xx[ok], 0.01)) else NA_real_,
    p99 = if (sum(ok)) as.numeric(stats::quantile(xx[ok], 0.99)) else NA_real_,
    stringsAsFactors = FALSE
  )
})
diag_df <- do.call(rbind, diag_rows)
utils::write.csv(diag_df, file.path(out, "Table_S1_nutrient_sample_diagnostics.csv"), row.names = FALSE)

# Top5 from prior survey compare
cmp_path <- file.path(base, "Output_prostate_nuwas_survey_compare_age65/Table_compare_unweighted_vs_survey.csv")
top5 <- if (file.exists(cmp_path)) {
  cm <- utils::read.csv(cmp_path, stringsAsFactors = FALSE)
  cm <- cm[order(cm$q_svy, cm$p_svy), ]
  head(cm$exposure, 5)
} else {
  nut[1:5]
}
exwas_log("Top5: ", paste(top5, collapse = ", "))

# ---- 拟合工具 ----
fit_uw <- function(dd, y, x, covars, use_energy = TRUE) {
  cov_use <- if (use_energy) unique(c(covars, "Energy_ln")) else covars
  cols <- unique(c(y, x, cov_use)); cols <- cols[cols %in% names(dd)]
  z <- dd[, cols, drop = FALSE]
  for (nm in setdiff(names(z), c(y, x))) if (is.character(z[[nm]])) z[[nm]] <- factor(z[[nm]])
  z[[y]] <- exwas_to_num(z[[y]]); z[[x]] <- exwas_to_num(z[[x]])
  z <- z[stats::complete.cases(z), , drop = FALSE]
  n_ev <- sum(z[[y]] == 1, na.rm = TRUE)
  if (nrow(z) < 80L || n_ev < 10L) return(list(beta = NA_real_, se = NA_real_, n = nrow(z), n_events = n_ev, note = "sparse"))
  cov_ok <- character(0)
  for (cv in setdiff(names(z), c(y, x))) {
    v <- z[[cv]]
    nlev <- if (is.factor(v)) length(unique(as.character(v))) else length(unique(v[is.finite(exwas_to_num(v))]))
    if (is.finite(nlev) && nlev >= 2L) cov_ok <- c(cov_ok, cv)
  }
  xv <- z[[x]]
  if (length(unique(xv)) > 2L) {
    iqr <- stats::IQR(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- 1
    z[[x]] <- z[[x]] / iqr
  }
  fml <- stats::as.formula(paste(y, "~", paste(c(x, cov_ok), collapse = "+")))
  fit <- tryCatch(stats::glm(fml, data = z, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) return(list(beta = NA_real_, se = NA_real_, n = nrow(z), n_events = n_ev, note = "fail"))
  cf <- summary(fit)$coefficients
  hit <- rownames(cf)[rownames(cf) == x | startsWith(rownames(cf), x)]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) return(list(beta = NA_real_, se = NA_real_, n = nrow(z), n_events = n_ev, note = "coef"))
  list(beta = cf[hit[1], 1], se = cf[hit[1], 2], n = nrow(z), n_events = n_ev, note = "ok")
}

fit_svy <- function(d_full, y, x, covars, use_energy = TRUE, weight_col = "WTDRD1_8") {
  cov_use <- if (use_energy) unique(c(covars, "Energy_ln")) else covars
  w0 <- exwas_to_num(d_full[[weight_col]])
  ok <- as.logical(d_full$.analytic) & as.logical(d_full$.design_ok) &
    is.finite(exwas_to_num(d_full[[y]])) & is.finite(exwas_to_num(d_full[[x]])) &
    is.finite(w0) & w0 > 0
  ok[is.na(ok)] <- FALSE
  for (cv in cov_use) {
    if (!cv %in% names(d_full)) next
    v <- d_full[[cv]]
    if (is.factor(v) || is.character(v)) ok <- ok & !is.na(v) else ok <- ok & is.finite(exwas_to_num(v))
  }
  ok[is.na(ok)] <- FALSE
  d_full$.use <- ok
  n_use <- sum(ok); n_ev <- sum(ok & exwas_to_num(d_full[[y]]) == 1)
  if (n_use < 80L || n_ev < 10L) return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev, note = "sparse", degf = NA_real_))
  # 设计样本：有限权重 + PSU/strata（Day2 切勿把 NA 权重带进 svydesign）
  des_ok <- as.logical(d_full$.design_ok) & is.finite(w0) & w0 > 0 &
    is.finite(exwas_to_num(d_full$SDMVPSU)) & is.finite(exwas_to_num(d_full$SDMVSTRA))
  des_ok[is.na(des_ok)] <- FALSE
  dd <- d_full[des_ok, , drop = FALSE]
  dd$.w <- exwas_to_num(dd[[weight_col]])
  xv <- exwas_to_num(dd[[x]][dd$.use])
  iqr <- stats::IQR(xv, na.rm = TRUE)
  if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv, na.rm = TRUE)
  if (!is.finite(iqr) || iqr == 0) iqr <- 1
  dd[[x]] <- exwas_to_num(dd[[x]]) / iqr
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
  des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA, weights = ~.w, data = dd, nest = TRUE)
  degf_u <- tryCatch(as.numeric(survey::degf(des)), error = function(e) NA_real_)
  des_u <- des[which(as.logical(des$variables$.use)), ]
  fml <- stats::as.formula(paste(y, "~", paste(c(x, cov_ok), collapse = "+")))
  fit <- tryCatch(survey::svyglm(fml, design = des_u, family = stats::quasibinomial()), error = function(e) NULL)
  if (is.null(fit)) return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev, note = "fail", degf = degf_u))
  cf <- summary(fit)$coefficients
  hit <- rownames(cf)[rownames(cf) == x | startsWith(rownames(cf), x)]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) return(list(beta = NA_real_, se = NA_real_, n = n_use, n_events = n_ev, note = "coef", degf = degf_u))
  list(beta = cf[hit[1], 1], se = cf[hit[1], 2], n = n_use, n_events = n_ev, note = "ok", degf = degf_u)
}

# mice on analytic
run_mice_pool <- function(m, exposures, use_energy = TRUE, day2 = FALSE) {
  da <- d[d$.analytic, , drop = FALSE]
  imp_cols <- unique(c(covars, "Energy_ln"))
  use <- da[, imp_cols, drop = FALSE]
  for (nm in names(use)) {
    if (is.character(use[[nm]])) use[[nm]] <- factor(use[[nm]])
    else if (!is.factor(use[[nm]])) use[[nm]] <- exwas_to_num(use[[nm]])
  }
  set.seed(20261119L)
  imp <- mice::mice(use, m = as.integer(m), maxit = 10L, printFlag = FALSE, seed = 20261119L)
  store_u <- store_s <- lapply(exposures, function(x) {
    list(beta = rep(NA_real_, m), se = rep(NA_real_, m), n = rep(NA_integer_, m),
         n_events = rep(NA_integer_, m), degf = rep(NA_real_, m))
  })
  names(store_u) <- names(store_s) <- exposures
  for (j in seq_len(m)) {
    comp <- mice::complete(imp, j)
    d_j <- d
    idx <- which(d_j$.analytic)
    for (nm in names(comp)) {
      if (is.factor(comp[[nm]])) {
        d_j[[nm]] <- as.character(d_j[[nm]])
        d_j[[nm]][idx] <- as.character(comp[[nm]])
        d_j[[nm]] <- factor(d_j[[nm]])
      } else d_j[[nm]][idx] <- comp[[nm]]
    }
    # Day2：把 DR2* 拷到模型用的暴露名（仅 top 敏感性）
    if (isTRUE(day2)) {
      for (x in exposures) {
        x2 <- sub("^DR1", "DR2", x)
        if (x2 %in% names(d_j)) d_j[[x]] <- exwas_to_num(d_j[[x2]])
      }
      # Day2 能量
      if ("DR2TKCAL" %in% names(d_j)) {
        e2 <- exwas_to_num(d_j$DR2TKCAL)
        d_j$Energy_ln <- ifelse(is.finite(e2) & e2 > 0, log(e2), NA_real_)
      }
      ok2 <- is.finite(exwas_to_num(d_j$WTDR2D_8)) & d_j$WTDR2D_8 > 0 &
        is.finite(exwas_to_num(d_j$Energy_ln))
      ok2[is.na(ok2)] <- FALSE
      d_j$.analytic <- as.logical(d_j$.analytic) & ok2
      # 调查设计权重改为 Day2；design_ok 必须与有限权重对齐，否则 svydesign 报 missing weights
      d_j$WTDRD1_8 <- d_j$WTDR2D_8
      d_j$.design_ok <- ok2 & is.finite(d_j$SDMVPSU) & is.finite(d_j$SDMVSTRA)
    }
    da_j <- d_j[d_j$.analytic, , drop = FALSE]
    for (x in exposures) {
      bu <- fit_uw(da_j, "DN", x, covars, use_energy = use_energy)
      bs <- fit_svy(d_j, "DN", x, covars, use_energy = use_energy)
      store_u[[x]]$beta[j] <- bu$beta; store_u[[x]]$se[j] <- bu$se
      store_u[[x]]$n[j] <- bu$n; store_u[[x]]$n_events[j] <- bu$n_events
      store_s[[x]]$beta[j] <- bs$beta; store_s[[x]]$se[j] <- bs$se
      store_s[[x]]$n[j] <- bs$n; store_s[[x]]$n_events[j] <- bs$n_events
      store_s[[x]]$degf[j] <- bs$degf
    }
    if (j == 1L || j %% 5L == 0L) exwas_log("m=", m, " energy=", use_energy, " day2=", day2, " complete ", j, "/", m)
  }
  df_svy <- stats::median(unlist(lapply(store_s, function(z) z$degf)), na.rm = TRUE)
  if (!is.finite(df_svy)) df_svy <- df_complete
  # 不加权：大样本自由度；加权：survey::degf（复杂抽样，禁止一律正态）
  pool_one <- function(store, tag, df_c) {
    do.call(rbind, lapply(names(store), function(x) {
      st <- store[[x]]
      pl <- exwas_rubin_pool(st$beta, st$se, df_complete = df_c)
      data.frame(
        exposure = x, method = tag, m = as.integer(m),
        use_energy = use_energy, day2 = day2,
        n = as.integer(round(mean(st$n, na.rm = TRUE))),
        n_events = as.integer(round(mean(st$n_events, na.rm = TRUE))),
        beta = pl$beta, se = pl$se,
        OR = pl$OR, lo = pl$lo, hi = pl$hi, p = pl$p,
        df = pl$df, df_complete = pl$df_complete,
        lambda = pl$lambda, m_ok = pl$m_ok,
        stringsAsFactors = FALSE
      )
    }))
  }
  list(
    uw = pool_one(store_u, "unweighted", Inf),
    svy = pool_one(store_s, "survey", df_svy),
    df_complete_used = df_svy
  )
}

# m=5 主对照（Top5，±能量）
r5_e <- run_mice_pool(5L, top5, use_energy = TRUE, day2 = FALSE)
r5_ne <- run_mice_pool(5L, top5, use_energy = FALSE, day2 = FALSE)
# Day2 敏感性（有 WTDR2D 时）
r5_d2 <- tryCatch(
  run_mice_pool(5L, top5, use_energy = TRUE, day2 = TRUE),
  error = function(e) {
    exwas_log("Day2 失败: ", conditionMessage(e))
    NULL
  }
)
# m=20 稳定性（仅加权 + 能量）
r20 <- run_mice_pool(as.integer(opt$mice_stability), top5, use_energy = TRUE, day2 = FALSE)

tab_top <- rbind(r5_e$uw, r5_e$svy, r5_ne$uw, r5_ne$svy)
if (!is.null(r5_d2)) tab_top <- rbind(tab_top, r5_d2$uw, r5_d2$svy)
tab_top <- rbind(tab_top, r20$uw, r20$svy)
# 各自场景内 BH（仅 5 个暴露，探索性）
tab_top$q_within_top5 <- ave(tab_top$p, tab_top$method, tab_top$m, tab_top$use_energy, tab_top$day2,
                             FUN = function(p) stats::p.adjust(p, method = "BH"))
utils::write.csv(tab_top, file.path(out, "Table_Top5_models_uw_svy_energy_day_m.csv"), row.names = FALSE)

# m5 vs m20 稳定性（survey + energy + day1）
st <- merge(
  r5_e$svy[, c("exposure", "beta", "se", "OR", "p", "df")],
  r20$svy[, c("exposure", "beta", "se", "OR", "p", "df")],
  by = "exposure", suffixes = c("_m5", "_m20")
)
st$delta_beta <- st$beta_m20 - st$beta_m5
st$ratio_se <- st$se_m20 / st$se_m5
st$sign_same <- sign(st$beta_m5) == sign(st$beta_m20)
utils::write.csv(st, file.path(out, "Table_Top5_stability_m5_vs_m20_survey.csv"), row.names = FALSE)

# Top5 摄入分布 + Day1/Day2 相关
dist_rows <- lapply(top5, function(x) {
  a <- d[d$.analytic, , drop = FALSE]
  x1 <- exwas_to_num(a[[x]])
  x2n <- sub("^DR1", "DR2", x)
  x2 <- if (x2n %in% names(a)) exwas_to_num(a[[x2n]]) else rep(NA_real_, nrow(a))
  ok1 <- is.finite(x1); ok2 <- is.finite(x2); both <- ok1 & ok2
  data.frame(
    exposure = x,
    n_day1 = sum(ok1), zero_rate_day1 = mean(x1[ok1] == 0),
    median_day1 = stats::median(x1[ok1]), iqr_day1 = stats::IQR(x1[ok1]),
    n_day2 = sum(ok2), zero_rate_day2 = if (sum(ok2)) mean(x2[ok2] == 0) else NA_real_,
    median_day2 = if (sum(ok2)) stats::median(x2[ok2]) else NA_real_,
    n_both = sum(both),
    cor_day12 = if (sum(both) > 50) stats::cor(x1[both], x2[both]) else NA_real_,
    stringsAsFactors = FALSE
  )
})
utils::write.csv(do.call(rbind, dist_rows), file.path(out, "Table_Top5_intake_day1_day2.csv"), row.names = FALSE)

# 宽表：加权主模型一行一张卡
wide <- r5_e$svy
wide <- merge(wide, r5_e$uw[, c("exposure", "beta", "se", "OR", "lo", "hi", "p")],
              by = "exposure", suffixes = c("_svy", "_uw"))
wide <- merge(wide, diag_df[, c("exposure", "miss_rate", "zero_rate", "iqr", "n_cases_nonmiss")], by = "exposure")
wide <- merge(wide, do.call(rbind, dist_rows)[, c("exposure", "cor_day12", "zero_rate_day1", "zero_rate_day2")], by = "exposure")
utils::write.csv(wide, file.path(out, "Table_Top5_card_survey_primary.csv"), row.names = FALSE)

writeLines(c(
  "# Prostate Age>=65 technical QC + Top5 (no WQS/ERS/mediation)",
  paste0("design: SDMVSTRA + SDMVPSU + WTDRD1/", n_cyc),
  paste0("degf(design_ok)=", df_complete),
  "Rubin: Barnard-Rubin df with df_complete=survey degf; t-based CI/P (not pure normal)",
  paste0("Top5 (by prior survey q): ", paste(top5, collapse = ", ")),
  paste0("stability mice m=5 vs m=", opt$mice_stability),
  "Day2 = exploratory same-name DR2 columns + WTDR2D/8; not NCI usual intake",
  "Within-Top5 BH q is exploratory only (not genome-wide 53-test FDR)"
), file.path(out, "README_prostate_top5_qc.txt"))

exwas_log("写完 ", out)
print(st)
keep_cols <- intersect(
  c("exposure", "OR_svy", "lo_svy", "hi_svy", "p_svy", "OR_uw", "p_uw", "zero_rate", "cor_day12"),
  names(wide)
)
print(wide[, keep_cols, drop = FALSE])
