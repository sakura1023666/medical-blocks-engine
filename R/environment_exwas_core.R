if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

# ExWAS 核心（牙周炎文献方法迁到二分类发病）
# ExWAS 不加权；描述 / ERS 关联 / RCS / 亚组 / 中介在权重列齐全时用 survey。
# 不改 Blocks/35–42 里已有 VOC 块的行为。

exwas_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  fileEncoding = "UTF-8")
}

exwas_log <- function(...) {
  message("[exwas] ", paste0(..., collapse = ""))
}

exwas_ensure_dir <- function(path) {
  if (!dir.exists(path)) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  path
}

# 尿/血金属、汞、邻苯、PFAS。营养素与脂肪酸不进毒物池。
exwas_default_exposure_map <- function() {
  list(
    urine_metals = c("URXUCD", "URXUCO", "URXUMN", "URXUMO", "URXUPB", "URXUHG"),
    blood_metals = c("LBXBCD", "LBXBMN", "LBXBPB", "LBXBSE", "LBXTHG", "LBXIHG", "LBXBCO"),
    pfas = c("SSPFNA"),
    phthalate_prefix = c("LBX", "LBD")
  )
}

exwas_is_environmental_col <- function(nm) {
  nm <- as.character(nm)
  keep_exact <- c(
    "URXUCD", "URXUCO", "URXUMN", "URXUMO", "URXUPB", "URXUHG",
    "LBXBCD", "LBXBMN", "LBXBPB", "LBXBSE", "LBXTHG", "LBXIHG", "LBXBCO",
    "LBDBCDSI", "LBDBMNSI", "LBDBPBSI", "LBDBSESI", "LBDTHGSI", "LBDIHGSI", "LBDBCOSI",
    "SSPFNA"
  )
  if (nm %in% keep_exact) return(TRUE)
  # NHANES 邻苯二甲酸代谢物常见编号列（L28）
  grepl("^(LBX|LBD)(028|044|049|052|066|074|087|099|105|118|199)", nm)
}

exwas_join_exposures <- function(outcome, raw_dir) {
  keys <- c("cycle", "SEQN")
  out <- outcome
  files <- list.files(raw_dir, pattern = "\\.tsv$", full.names = TRUE)
  for (fp in files) {
    hdr <- strsplit(readLines(fp, n = 1L, warn = FALSE), "\t", fixed = TRUE)[[1]]
    use <- hdr[hdr %in% keys | vapply(hdr, exwas_is_environmental_col, logical(1))]
    use <- unique(use)
    if (length(setdiff(use, keys)) == 0L) next
    dd <- utils::read.delim(fp, stringsAsFactors = FALSE, check.names = FALSE)
    dd <- dd[, intersect(use, names(dd)), drop = FALSE]
    # 同一分析物多文件时保留先读到的非缺失
    new_cols <- setdiff(names(dd), keys)
    new_cols <- new_cols[!new_cols %in% names(out)]
    if (!length(new_cols)) next
    out <- merge(out, dd[, c(keys, new_cols), drop = FALSE], by = keys, all.x = TRUE)
  }
  out
}

exwas_to_num <- function(x) {
  if (is.numeric(x)) return(x)
  suppressWarnings(as.numeric(as.character(x)))
}

# 文献补充：>90% <LOD 或缺失>40% 剔除；>30% <LOD 二分类（未检出=0）；其余 ln。
# 本数据无 LOD 列时，用缺失率与零值比例近似「低于检出」。
exwas_screen_transform <- function(df, exposure_cols, lod_map = NULL) {
  keep <- character(0)
  notes <- list()
  for (col in exposure_cols) {
    x <- exwas_to_num(df[[col]])
    measured <- x[!is.na(x)]
    n_measured <- length(measured)
    # 全库缺失多半是子样本未抽中，不按全库缺失率剔除。
    nondetect <- if (n_measured == 0L) 1 else mean(measured <= 0)
    if (!is.null(lod_map) && col %in% names(lod_map)) {
      lod <- lod_map[[col]]
      nondetect <- if (n_measured == 0L) 1 else mean(measured < lod)
    }
    decision <- "log"
    if (n_measured < 50L || nondetect > 0.90) {
      decision <- "drop"
    } else if (nondetect > 0.30) {
      decision <- "binary"
      y <- ifelse(is.na(x), NA_real_, ifelse(x > 0, 1, 0))
      df[[paste0(col, "_bin")]] <- y
      keep <- c(keep, paste0(col, "_bin"))
    } else {
      xx <- x
      xx[!is.na(xx) & xx <= 0] <- NA_real_
      df[[paste0(col, "_ln")]] <- log(xx)
      keep <- c(keep, paste0(col, "_ln"))
    }
    notes[[length(notes) + 1L]] <- data.frame(
      exposure = col, n_measured = n_measured, nondetect = nondetect,
      decision = decision, stringsAsFactors = FALSE
    )
  }
  list(data = df, keep = keep, notes = if (length(notes)) do.call(rbind, notes) else NULL)
}

# 营养摄入的 0 是真实未摄入，用 log1p，不用毒物的检出限二分类。
exwas_screen_nutrition <- function(df, exposure_cols) {
  keep <- character(0)
  notes <- list()
  for (col in exposure_cols) {
    x <- exwas_to_num(df[[col]])
    n_measured <- sum(!is.na(x))
    zero_rate <- if (n_measured == 0L) 1 else mean(x == 0, na.rm = TRUE)
    decision <- "log1p"
    if (n_measured < 50L || zero_rate > 0.95) {
      decision <- "drop"
    } else {
      df[[paste0(col, "_ln")]] <- log1p(x)
      keep <- c(keep, paste0(col, "_ln"))
    }
    notes[[length(notes) + 1L]] <- data.frame(
      exposure = col, n_measured = n_measured, zero_rate = zero_rate,
      decision = decision, stringsAsFactors = FALSE
    )
  }
  list(data = df, keep = keep, notes = if (length(notes)) do.call(rbind, notes) else NULL)
}

exwas_dedupe_units <- function(cols) {
  cols <- cols[!grepl("LA$", cols)]
  base <- sub("SI$", "", cols)
  # 同时有常规单位和 SI 时保留常规单位
  drop <- cols[grepl("SI$", cols) & base %in% cols]
  setdiff(cols, drop)
}

exwas_impute_mice <- function(df, cols, m = 5L, maxit = 5L, seed = 123456L) {
  if (!requireNamespace("mice", quietly = TRUE)) {
    stop("需要 R 包 mice。请安装到 R-4.5.1 库。", call. = FALSE)
  }
  use <- df[, cols, drop = FALSE]
  for (nm in names(use)) use[[nm]] <- exwas_to_num(use[[nm]])
  set.seed(seed)
  imp <- mice::mice(use, m = m, maxit = maxit, printFlag = FALSE)
  mice::complete(imp, action = 1L)
}

exwas_fdr <- function(p) stats::p.adjust(p, method = "BH")

exwas_fit_one <- function(df, y, x, covars) {
  cols <- unique(c(y, x, covars))
  cols <- cols[nzchar(cols) & cols %in% names(df)]
  dd <- df[, cols, drop = FALSE]
  # 字符协变量转因子，避免 complete.cases 后仍无法建模
  for (nm in setdiff(names(dd), c(y, x))) {
    if (is.character(dd[[nm]])) dd[[nm]] <- factor(dd[[nm]])
  }
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 40L || length(unique(dd[[y]])) < 2L) {
    return(data.frame(exposure = x, n = nrow(dd), OR = NA_real_, lo = NA_real_,
                      hi = NA_real_, p = NA_real_, stringsAsFactors = FALSE))
  }
  # 丢掉分析子集中无变异协变量（如前列腺仅男性 Gender）
  cov_ok <- character(0)
  for (cv in setdiff(names(dd), c(y, x))) {
    v <- dd[[cv]]
    nlev <- if (is.factor(v) || is.character(v)) {
      length(unique(as.character(v)))
    } else {
      length(unique(v[is.finite(exwas_to_num(v))]))
    }
    if (is.finite(nlev) && nlev >= 2L) cov_ok <- c(cov_ok, cv)
  }
  for (cv in cov_ok) {
    if (is.factor(dd[[cv]])) dd[[cv]] <- droplevels(dd[[cv]])
  }
  # 每 IQR（连续）；二分类则为检出 vs 未检出
  xv <- exwas_to_num(dd[[x]])
  dd[[x]] <- xv
  if (length(unique(xv[is.finite(xv)])) > 2L) {
    iqr <- stats::IQR(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- 1
    dd[[x]] <- dd[[x]] / iqr
  }
  rhs <- c(x, cov_ok)
  fml <- stats::as.formula(paste(y, "~", paste(rhs, collapse = " + ")))
  fit <- tryCatch(stats::glm(fml, data = dd, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) {
    return(data.frame(exposure = x, n = nrow(dd), OR = NA_real_, lo = NA_real_,
                      hi = NA_real_, p = NA_real_, stringsAsFactors = FALSE))
  }
  cf <- summary(fit)$coefficients
  rn <- rownames(cf)
  hit <- rn[rn == x | startsWith(rn, paste0(x))]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) {
    return(data.frame(exposure = x, n = nrow(dd), OR = NA_real_, lo = NA_real_,
                      hi = NA_real_, p = NA_real_, stringsAsFactors = FALSE))
  }
  b <- cf[hit[1], 1]
  se <- cf[hit[1], 2]
  data.frame(
    exposure = x, n = nrow(dd),
    OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
    p = cf[hit[1], 4], stringsAsFactors = FALSE
  )
}

exwas_run_unweighted <- function(df, y, exposures, covars, families = NULL) {
  nworkers <- suppressWarnings(as.integer(Sys.getenv("EXWAS_WORKERS", "1")))
  if (is.na(nworkers) || nworkers < 1L) nworkers <- 1L
  if (nworkers > 1L && length(exposures) > 1L) {
    cl <- parallel::makeCluster(nworkers)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterExport(
      cl,
      c("exwas_fit_one", "exwas_to_num", "df", "y", "covars"),
      envir = environment()
    )
    rows <- parallel::parLapply(cl, exposures, function(x) {
      exwas_fit_one(df, y, x, covars)
    })
  } else {
    rows <- lapply(exposures, function(x) exwas_fit_one(df, y, x, covars))
  }
  tab <- do.call(rbind, rows)
  tab$q <- exwas_fdr(tab$p)
  tab$family <- if (!is.null(families)) unname(families[tab$exposure]) else NA_character_
  if (!all(is.na(tab$family))) {
    tab$q_family <- ave(tab$p, tab$family, FUN = function(p) stats::p.adjust(p, method = "BH"))
  } else {
    tab$q_family <- NA_real_
  }
  tab
}

# 每暴露独立完全病例 + NHANES 复杂抽样加权 Logistic（quasibinomial）。
# weight_map: named character, names=exposure, values=weight column.
# extra_covars_by_x: optional named list of additional covariates per exposure (e.g. energy).
exwas_fit_one_survey <- function(df, y, x, covars, weight_col,
                                  psu = "SDMVPSU", strata = "SDMVSTRA",
                                  extra_covars = NULL, min_n = 80L, min_events = 15L) {
  if (requireNamespace("survey", quietly = TRUE)) {
    # 单 PSU 层：用调整而非直接失败（双日/正值子集常见）
    options(survey.lonely.psu = "adjust")
  }
  cov_use <- unique(c(covars, extra_covars))
  need <- unique(c(y, x, cov_use, weight_col, psu, strata))
  if (!all(c(y, x, weight_col, psu, strata) %in% names(df))) {
    return(data.frame(
      exposure = x, n = 0L, n_events = 0L, weight = weight_col,
      OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
      note = "missing_columns", stringsAsFactors = FALSE
    ))
  }
  dd <- df[, intersect(need, names(df)), drop = FALSE]
  for (nm in c(y, x, weight_col, psu, strata)) dd[[nm]] <- exwas_to_num(dd[[nm]])
  ok <- is.finite(dd[[y]]) & is.finite(dd[[x]]) &
    is.finite(dd[[weight_col]]) & dd[[weight_col]] > 0 &
    is.finite(dd[[psu]]) & is.finite(dd[[strata]])
  for (cv in cov_use) {
    if (!cv %in% names(dd)) next
    if (is.factor(dd[[cv]]) || is.character(dd[[cv]])) {
      ok <- ok & !is.na(dd[[cv]])
    } else {
      dd[[cv]] <- exwas_to_num(dd[[cv]])
      ok <- ok & is.finite(dd[[cv]])
    }
  }
  dd <- dd[which(ok), , drop = FALSE]
  n_ev <- sum(dd[[y]] == 1, na.rm = TRUE)
  if (nrow(dd) < min_n || n_ev < min_events || length(unique(dd[[y]])) < 2L) {
    return(data.frame(
      exposure = x, n = nrow(dd), n_events = n_ev, weight = weight_col,
      OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
      note = "sparse", stringsAsFactors = FALSE
    ))
  }
  # 丢掉分析子集中无变异的协变量（如前列腺仅男性时 Gender）
  cov_ok <- character(0)
  for (cv in cov_use) {
    if (!cv %in% names(dd)) next
    v <- dd[[cv]]
    nlev <- if (is.factor(v) || is.character(v)) length(unique(as.character(v))) else length(unique(v[is.finite(exwas_to_num(v))]))
    if (is.finite(nlev) && nlev >= 2L) cov_ok <- c(cov_ok, cv)
  }
  cov_use <- cov_ok
  for (cv in cov_use) {
    if (is.factor(dd[[cv]])) dd[[cv]] <- droplevels(dd[[cv]])
  }
  xv <- dd[[x]]
  if (length(unique(xv)) > 2L) {
    iqr <- stats::IQR(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- 1
    dd[[x]] <- dd[[x]] / iqr
  }
  dd$.w <- dd[[weight_col]]
  des <- tryCatch(
    survey::svydesign(
      ids = stats::as.formula(paste0("~", psu)),
      strata = stats::as.formula(paste0("~", strata)),
      weights = ~.w, data = dd, nest = TRUE
    ),
    error = function(e) NULL
  )
  if (is.null(des)) {
    return(data.frame(
      exposure = x, n = nrow(dd), n_events = n_ev, weight = weight_col,
      OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
      note = "design_fail", stringsAsFactors = FALSE
    ))
  }
  rhs <- c(x, cov_use)
  fml <- stats::as.formula(paste(y, "~", paste(rhs, collapse = " + ")))
  err_msg <- NULL
  fit <- tryCatch(
    survey::svyglm(fml, design = des, family = stats::quasibinomial()),
    error = function(e) { err_msg <<- conditionMessage(e); NULL }
  )
  if (is.null(fit)) {
    return(data.frame(
      exposure = x, n = nrow(dd), n_events = n_ev, weight = weight_col,
      OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
      note = paste0("fit_fail:", substr(as.character(err_msg), 1, 80)),
      stringsAsFactors = FALSE
    ))
  }
  cf <- summary(fit)$coefficients
  # factor exposures may get "xYes" rownames
  rn <- rownames(cf)
  hit <- rn[rn == x | startsWith(rn, paste0(x))]
  hit <- hit[hit != "(Intercept)"]
  if (!length(hit)) {
    return(data.frame(
      exposure = x, n = nrow(dd), n_events = n_ev, weight = weight_col,
      OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_,
      note = "coef_missing", stringsAsFactors = FALSE
    ))
  }
  b <- cf[hit[1], 1]; se <- cf[hit[1], 2]; pv <- cf[hit[1], 4]
  data.frame(
    exposure = x, n = nrow(dd), n_events = n_ev, weight = weight_col,
    OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = pv,
    note = "ok", stringsAsFactors = FALSE
  )
}

exwas_run_survey_per_exposure <- function(df, y, exposures, covars, weight_map,
                                          families = NULL, energy_col = NULL,
                                          psu = "SDMVPSU", strata = "SDMVSTRA") {
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("需要 R 包 survey", call. = FALSE)
  }
  nworkers <- suppressWarnings(as.integer(Sys.getenv("EXWAS_WORKERS", "1")))
  if (is.na(nworkers) || nworkers < 1L) nworkers <- 1L
  wmap <- as.list(weight_map)
  if (nworkers > 1L && length(exposures) > 1L) {
    cl <- parallel::makeCluster(nworkers)
    on.exit(parallel::stopCluster(cl), add = TRUE)
    parallel::clusterExport(
      cl,
      c("exwas_fit_one_survey", "exwas_to_num", "df", "y", "covars",
        "wmap", "energy_col", "psu", "strata"),
      envir = environment()
    )
    parallel::clusterEvalQ(cl, {
      suppressPackageStartupMessages(requireNamespace("survey", quietly = TRUE))
      NULL
    })
    rows <- parallel::parLapply(cl, exposures, function(x) {
      wcol <- if (!is.null(wmap[[x]])) wmap[[x]] else "WTDRD1_7"
      if (is.null(wcol) || !nzchar(wcol)) wcol <- "WTDRD1_7"
      extra <- if (!is.null(energy_col) && grepl("^DR1", x)) energy_col else NULL
      exwas_fit_one_survey(df, y, x, covars, wcol, psu = psu, strata = strata, extra_covars = extra)
    })
  } else {
    rows <- lapply(exposures, function(x) {
      wcol <- if (!is.null(wmap[[x]])) wmap[[x]] else "WTDRD1_7"
      if (is.null(wcol) || !nzchar(wcol)) wcol <- "WTDRD1_7"
      extra <- if (!is.null(energy_col) && grepl("^DR1", x)) energy_col else NULL
      exwas_fit_one_survey(df, y, x, covars, wcol, psu = psu, strata = strata, extra_covars = extra)
    })
  }
  tab <- do.call(rbind, rows)
  tab$q <- exwas_fdr(tab$p)
  tab$family <- if (!is.null(families)) unname(families[tab$exposure]) else NA_character_
  if (!all(is.na(tab$family))) {
    tab$q_family <- ave(tab$p, tab$family, FUN = function(p) stats::p.adjust(p, method = "BH"))
  } else {
    tab$q_family <- NA_real_
  }
  tab
}

# 暴露用权重：膳食→膳食日权重；实验室→MEC（有子样本权重列且该列>0人数够则用子样本）。
exwas_weight_for_exposure <- function(df, exposure, diet_weight = "WTDRD1_7",
                                      mec_weight = "WTMEC2YR_7") {
  if (grepl("^DR1|^DR2", exposure)) return(diet_weight)
  # 常见子样本权重：有值则优先（VOC/金属等）
  for (w in c("WTSVOC2Y_7", "WTSA2YR_7", "WTSB2YR_7", "WTSC2YR_7")) {
    if (w %in% names(df)) {
      ww <- exwas_to_num(df[[w]])
      if (sum(is.finite(ww) & ww > 0, na.rm = TRUE) >= 200L) return(w)
    }
  }
  mec_weight
}

# 从 svyglm 取暴露系数（供 Rubin 合并）
exwas_fit_one_survey_beta <- function(df, y, x, covars, weight_col,
                                      psu = "SDMVPSU", strata = "SDMVSTRA",
                                      extra_covars = NULL, min_n = 80L, min_events = 15L) {
  one <- exwas_fit_one_survey(df, y, x, covars, weight_col, psu = psu, strata = strata,
                              extra_covars = extra_covars, min_n = min_n, min_events = min_events)
  if (is.null(one)) {
    return(data.frame(exposure = x, beta = NA_real_, se = NA_real_, n = 0L,
                      n_events = 0L, note = "null", stringsAsFactors = FALSE))
  }
  if (!identical(one$note, "ok") || !is.finite(one$OR) || !(one$OR > 0)) {
    return(data.frame(exposure = x, beta = NA_real_, se = NA_real_,
                      n = as.integer(one$n %||% 0L),
                      n_events = as.integer(one$n_events %||% 0L),
                      note = one$note %||% "fail",
                      stringsAsFactors = FALSE))
  }
  beta <- log(one$OR)
  # 从 Wald CI 反推 se（与 svyglm 一致）
  se <- if (is.finite(one$lo) && one$lo > 0) (log(one$hi) - log(one$lo)) / (2 * 1.96) else NA_real_
  data.frame(exposure = x, beta = beta, se = se, n = one$n, n_events = one$n_events,
             note = "ok", stringsAsFactors = FALSE)
}

exwas_rubin_pool <- function(betas, ses) {
  ok <- is.finite(betas) & is.finite(ses) & ses > 0
  betas <- betas[ok]; ses <- ses[ok]
  m <- length(betas)
  if (m < 1L) {
    return(list(OR = NA_real_, lo = NA_real_, hi = NA_real_, p = NA_real_, m_ok = 0L))
  }
  qbar <- mean(betas)
  ubar <- mean(ses^2)
  b <- if (m > 1L) stats::var(betas) else 0
  t <- ubar + (1 + 1 / m) * b
  se <- sqrt(t)
  # Barnard-Rubin df
  lambda <- if (t > 0) (1 + 1 / m) * b / t else 0
  df_old <- if (m > 1L && b > 0) (m - 1) / lambda^2 else Inf
  # 简化：用正态近似当 df 很大
  z <- if (se > 0) qbar / se else NA_real_
  p <- if (is.finite(z)) 2 * stats::pnorm(-abs(z)) else NA_real_
  list(
    OR = exp(qbar), lo = exp(qbar - 1.96 * se), hi = exp(qbar + 1.96 * se),
    p = p, m_ok = m, beta = qbar, se = se
  )
}

# MICE 主分析（对齐文献顺序）：先插补协变量±能量/低缺失膳食，再每套做 ExWAS，Rubin 合并。
# 实验室/周期结构性未测不进插补矩阵（暴露仍按观测；每人暴露独立有效样本）。
exwas_run_survey_mice <- function(df, y, exposures, covars, weight_map,
                                  families = NULL, energy_col = "Energy_ln",
                                  diet_impute_cols = NULL,
                                  m = 20L, maxit = 10L, seed = 20261105L,
                                  psu = "SDMVPSU", strata = "SDMVSTRA") {
  if (!requireNamespace("mice", quietly = TRUE)) stop("需要 mice", call. = FALSE)
  if (!requireNamespace("survey", quietly = TRUE)) stop("需要 survey", call. = FALSE)
  options(survey.lonely.psu = "adjust")

  imp_cols <- unique(c(covars, energy_col, diet_impute_cols))
  imp_cols <- imp_cols[imp_cols %in% names(df)]
  use <- df[, imp_cols, drop = FALSE]
  for (nm in names(use)) {
    if (is.character(use[[nm]])) use[[nm]] <- factor(use[[nm]])
    else if (!is.factor(use[[nm]])) use[[nm]] <- exwas_to_num(use[[nm]])
  }
  keep_c <- names(use)[vapply(use, function(z) !all(is.na(z)), logical(1))]
  use <- use[, keep_c, drop = FALSE]
  set.seed(seed)
  exwas_log("MICE 拟合 m=", m, " maxit=", maxit, " 列=", paste(names(use), collapse = ","))
  imp <- mice::mice(use, m = as.integer(m), maxit = as.integer(maxit),
                    printFlag = FALSE, seed = as.integer(seed))

  wmap <- as.list(weight_map)
  nworkers <- suppressWarnings(as.integer(Sys.getenv("EXWAS_WORKERS", "1")))
  if (is.na(nworkers) || nworkers < 1L) nworkers <- 1L

  store <- lapply(exposures, function(x) {
    list(beta = rep(NA_real_, m), se = rep(NA_real_, m), n = rep(NA_integer_, m),
         n_events = rep(NA_integer_, m), note = rep(NA_character_, m))
  })
  names(store) <- exposures

  for (j in seq_len(m)) {
    comp <- mice::complete(imp, action = j)
    dfi <- df
    for (nm in names(comp)) dfi[[nm]] <- comp[[nm]]
    dfi <- exwas_aligned_as_model_frame(dfi, intersect(covars, names(dfi)))
    if (nworkers > 1L && length(exposures) > 1L) {
      cl <- parallel::makeCluster(nworkers)
      on.exit(try(parallel::stopCluster(cl), silent = TRUE), add = TRUE)
      parallel::clusterExport(
        cl,
        c("exwas_fit_one_survey", "exwas_fit_one_survey_beta", "exwas_to_num",
          "dfi", "y", "covars", "wmap", "energy_col", "psu", "strata"),
        envir = environment()
      )
      parallel::clusterEvalQ(cl, {
        options(survey.lonely.psu = "adjust")
        NULL
      })
      bts <- parallel::parLapply(cl, exposures, function(x) {
        wcol <- if (!is.null(wmap[[x]])) wmap[[x]] else "WTDRD1_7"
        extra <- if (!is.null(energy_col) && grepl("^DR1", x)) energy_col else NULL
        exwas_fit_one_survey_beta(dfi, y, x, covars, wcol,
                                  psu = psu, strata = strata, extra_covars = extra)
      })
      parallel::stopCluster(cl)
      on.exit(NULL)
    } else {
      bts <- lapply(exposures, function(x) {
        wcol <- if (!is.null(wmap[[x]])) wmap[[x]] else "WTDRD1_7"
        extra <- if (!is.null(energy_col) && grepl("^DR1", x)) energy_col else NULL
        exwas_fit_one_survey_beta(dfi, y, x, covars, wcol,
                                  psu = psu, strata = strata, extra_covars = extra)
      })
    }
    for (i in seq_along(exposures)) {
      x <- exposures[[i]]
      bt <- bts[[i]]
      store[[x]]$beta[j] <- bt$beta
      store[[x]]$se[j] <- bt$se
      store[[x]]$n[j] <- bt$n
      store[[x]]$n_events[j] <- bt$n_events
      store[[x]]$note[j] <- bt$note
    }
    if (j == 1L || j %% 5L == 0L || j == m) {
      exwas_log("MICE complete ", j, "/", m, " ExWAS 完成")
    }
  }

  rows <- lapply(exposures, function(x) {
    st <- store[[x]]
    pl <- exwas_rubin_pool(st$beta, st$se)
    data.frame(
      exposure = x,
      n = suppressWarnings(as.integer(round(mean(st$n, na.rm = TRUE)))),
      n_events = suppressWarnings(as.integer(round(mean(st$n_events, na.rm = TRUE)))),
      weight = if (!is.null(wmap[[x]])) wmap[[x]] else "WTDRD1_7",
      OR = pl$OR, lo = pl$lo, hi = pl$hi, p = pl$p,
      m_ok = pl$m_ok, m = as.integer(m),
      note = if (pl$m_ok >= 1L) "rubin_ok" else paste0("rubin_fail:", paste(unique(st$note), collapse = "|")),
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)
  tab$q <- exwas_fdr(tab$p)
  tab$family <- if (!is.null(families)) unname(families[tab$exposure]) else NA_character_
  if (!all(is.na(tab$family))) {
    tab$q_family <- ave(tab$p, tab$family, FUN = function(p) stats::p.adjust(p, method = "BH"))
  } else {
    tab$q_family <- NA_real_
  }
  list(table = tab, mice = imp)
}

exwas_has_survey <- function(df, cfg) {
  w <- cfg$survey_weight %||% "survey_weight"
  psu <- cfg$survey_psu %||% "SDMVPSU"
  st <- cfg$survey_strata %||% "SDMVSTRA"
  all(c(w, psu, st) %in% names(df)) && any(is.finite(exwas_to_num(df[[w]])))
}

exwas_design <- function(df, cfg) {
  if (!requireNamespace("survey", quietly = TRUE)) stop("需要 R 包 survey", call. = FALSE)
  w <- cfg$survey_weight
  df$.w <- exwas_to_num(df[[w]])
  df <- df[is.finite(df$.w) & df$.w > 0, , drop = FALSE]
  survey::svydesign(
    ids = stats::as.formula(paste0("~", cfg$survey_psu)),
    strata = stats::as.formula(paste0("~", cfg$survey_strata)),
    weights = ~.w, data = df, nest = TRUE
  )
}

exwas_weighted_logit <- function(df, y, x, covars, cfg) {
  if (!exwas_has_survey(df, cfg)) return(NULL)
  des <- exwas_design(df, cfg)
  fml <- stats::as.formula(paste(y, "~", paste(c(x, covars), collapse = " + ")))
  fit <- survey::svyglm(fml, design = des, family = stats::quasibinomial())
  cf <- summary(fit)$coefficients
  b <- cf[x, 1]; se <- cf[x, 2]
  data.frame(OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se), p = cf[x, 4])
}

exwas_write_descriptives <- function(df, y, out) {
  exwas_ensure_dir(out)
  age <- exwas_to_num(df$RIDAGEYR)
  sex <- df$RIAGENDR
  tab <- data.frame(
    group = c("all", "DN0", "DN1"),
    n = c(nrow(df), sum(df[[y]] == 0, na.rm = TRUE), sum(df[[y]] == 1, na.rm = TRUE)),
    age_median = c(
      stats::median(age, na.rm = TRUE),
      stats::median(age[df[[y]] == 0], na.rm = TRUE),
      stats::median(age[df[[y]] == 1], na.rm = TRUE)
    ),
    stringsAsFactors = FALSE
  )
  utils::write.csv(tab, file.path(out, "Table_1_age_sex_available.csv"), row.names = FALSE)
  df$age60 <- ifelse(age < 60, "<60", ">=60")
  utils::write.csv(
    as.data.frame(table(Age = df$age60, Sex = sex, Outcome = df[[y]]), stringsAsFactors = FALSE),
    file.path(out, "Table_S3_S4_strata_counts.csv"),
    row.names = FALSE
  )
  writeLines(
    "当前提取没有白细胞、中性粒、单核细胞，不能做原文 Figure 5 的炎症中介，未编造路径图。",
    file.path(out, "Figure_5_mediation_unavailable.txt")
  )
  survey_cfg <- list(
    survey_weight = "WTMEC2YR",
    survey_psu = "SDMVPSU",
    survey_strata = "SDMVSTRA"
  )
  if (!exwas_has_survey(df, survey_cfg)) {
    writeLines(
      "未找到 WTMEC2YR、SDMVPSU、SDMVSTRA。Table 1 按未加权计数。补上这三列后重跑即可加权。",
      file.path(out, "weight_unavailable_descriptive.txt")
    )
  }
  invisible(tab)
}
