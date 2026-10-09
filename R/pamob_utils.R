###############################################################################
# pamob_utils.R — PA–Mobility × 认知衰老 公共工具
###############################################################################

`%||%` <- function(a, b) if (!is.null(a)) a else b

pamob_phenotype_labels <- function() {
  c(
    "1" = "Active_preserved",
    "2" = "Inactive_preserved",
    "3" = "Active_limited",
    "4" = "Inactive_limited"
  )
}

#' PA sufficient (1/0) × mobility_limited (1=limited, 0=preserved) → phenotype code 1–4
pamob_phenotype_key <- function(pa_sufficient, mobility_limited) {
  p <- suppressWarnings(as.integer(pa_sufficient))
  m <- suppressWarnings(as.integer(mobility_limited))
  out <- rep(NA_integer_, length(p))
  ok <- !is.na(p) & !is.na(m) & p %in% c(0L, 1L) & m %in% c(0L, 1L)
  out[ok & p == 1L & m == 0L] <- 1L
  out[ok & p == 0L & m == 0L] <- 2L
  out[ok & p == 1L & m == 1L] <- 3L
  out[ok & p == 0L & m == 1L] <- 4L
  out
}

pamob_phenotype_factor <- function(code, ref = "Active_preserved") {
  lab <- pamob_phenotype_labels()
  x <- unname(lab[as.character(code)])
  factor(x, levels = unname(lab))
}

pamob_cfg <- function(ctx) {
  ctx$config$pamob %||% list()
}

pamob_data_root <- function(ctx) {
  bl <- pamob_cfg(ctx)
  as.character(bl$data_root %||% "")[1L]
}

pamob_out_root <- function(ctx) {
  as.character(ctx$config$project$output_dir %||% "Output")[1L]
}

pamob_tables_dir <- function(ctx, sub = NULL) {
  d <- file.path(pamob_out_root(ctx), "Tables")
  if (!is.null(sub) && nzchar(sub)) d <- file.path(d, sub)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

pamob_figures_dir <- function(ctx) {
  d <- file.path(pamob_out_root(ctx), "Figures")
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

pamob_write_csv <- function(df, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
  invisible(path)
}

pamob_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  fileEncoding = "UTF-8-BOM")
}

pamob_find_episodic_ok <- function(charls_dir) {
  hits <- list.files(charls_dir, pattern = "^D01_episodic_memory.*ok.*\\.csv$", full.names = TRUE)
  if (!length(hits)) stop("未找到 D01 episodic ok CSV: ", charls_dir, call. = FALSE)
  hits[[1L]]
}

#' 左补零到 12 位 CHARLS ID_h
pamob_pad_id12 <- function(x) {
  x <- gsub("^\\s+|\\s+$", "", as.character(x))
  x[is.na(x) | !nzchar(x)] <- NA_character_
  ok <- !is.na(x)
  n <- nchar(x[ok])
  x[ok] <- ifelse(n >= 12L, substr(x[ok], 1L, 12L),
                  paste0(strrep("0", 12L - n), x[ok]))
  x
}

#' CHARLS 问卷原始 ID → 12 位 ID_h（对齐 C03/D03）
#' - 10 位（多因 CSV 丢掉前导 0）：在末两位前插 0，再左补到 12
#' - 11 位：C03 规则在末两位前插 0，再左补到 12
#' 请传入 ID_raw / 问卷 ID，不要传入已转换的 ID_h。
pamob_charls_id_h <- function(x) {
  x <- gsub("^\\s+|\\s+$", "", as.character(x))
  x[is.na(x) | !nzchar(x) | x %in% c("NA", "NaN")] <- NA_character_
  ok <- !is.na(x)
  out <- rep(NA_character_, length(x))
  if (!any(ok)) return(out)
  xx <- x[ok]
  n <- nchar(xx)
  body <- ifelse(n == 10L,
                 paste0(substr(xx, 1L, 8L), "0", substr(xx, 9L, 10L)),
                 ifelse(n == 11L,
                        paste0(substr(xx, 1L, 9L), "0", substr(xx, 10L, 11L)),
                        xx))
  out[ok] <- pamob_pad_id12(body)
  out
}

pamob_find_first <- function(dir, pattern) {
  hits <- list.files(dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  if (!length(hits)) return(NA_character_)
  # prefer non-temp
  hits[[1L]]
}

pamob_load_rdata_df <- function(path, prefer = NULL) {
  if (!nzchar(path) || is.na(path) || !file.exists(path)) {
    stop("pamob_load_rdata_df: 文件不存在: ", path, call. = FALSE)
  }
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  objs <- ls(e)
  if (!length(objs)) stop("RData 无对象: ", path, call. = FALSE)
  if (!is.null(prefer)) {
    hit <- intersect(as.character(prefer), objs)
    if (length(hit)) return(e[[hit[[1L]]]])
  }
  for (o in objs) {
    if (is.data.frame(e[[o]])) return(e[[o]])
  }
  stop("RData 无 data.frame: ", path, " objs=", paste(objs, collapse = ","), call. = FALSE)
}

#' 粗算 eGFR（CKD-EPI 简化；缺性别时按女性公式）
pamob_egfr_ckd_epi <- function(creat_mgdl, age, female) {
  cr <- suppressWarnings(as.numeric(creat_mgdl))
  ag <- suppressWarnings(as.numeric(age))
  fem <- as.logical(female)
  fem[is.na(fem)] <- TRUE
  out <- rep(NA_real_, length(cr))
  ok <- !is.na(cr) & !is.na(ag) & cr > 0 & ag > 0
  if (!any(ok)) return(out)
  kap <- ifelse(fem[ok], 0.7, 0.9)
  alp <- ifelse(fem[ok], -0.329, -0.411)
  sexf <- ifelse(fem[ok], 1.018, 1.0)
  out[ok] <- 141 * (pmin(cr[ok] / kap, 1)^alp) * (pmax(cr[ok] / kap, 1)^(-1.209)) *
    (0.993^ag[ok]) * sexf
  out
}

pamob_ensure_packages <- function(pkgs) {
  miss <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (!length(miss)) return(invisible(TRUE))
  cli::cli_alert_warning("缺少 R 包: {paste(miss, collapse = ', ')} — 尝试安装到当前 R library")
  utils::install.packages(miss, repos = "https://cloud.r-project.org")
  ok <- vapply(miss, requireNamespace, logical(1), quietly = TRUE)
  if (!all(ok)) stop("无法安装: ", paste(miss[!ok], collapse = ", "), call. = FALSE)
  invisible(TRUE)
}

#' Fit nested Model0–3 LMM tables for a continuous cognition outcome
#' LMM Model3 固定效应上的两条预设 pairwise（level + slope）
#' Inactive_preserved vs Active_preserved；Active_limited vs Inactive_limited
pamob_lmm_pairwise_contrasts <- function(fit, outcome = NA_character_) {
  cf <- lme4::fixef(fit)
  V <- as.matrix(stats::vcov(fit))
  nm <- names(cf)
  .wald <- function(L) {
    L <- L[nm]
    if (any(is.na(L))) return(c(est = NA_real_, se = NA_real_, p = NA_real_))
    est <- sum(L * cf)
    se <- sqrt(as.numeric(t(L) %*% V[nm, nm, drop = FALSE] %*% L))
    if (!is.finite(se) || se <= 0) return(c(est = est, se = NA_real_, p = NA_real_))
    c(est = est, se = se, p = 2 * stats::pnorm(-abs(est / se)))
  }
  .L0 <- function() setNames(rep(0, length(cf)), nm)
  specs <- list(
    list(
      contrast = "Inactive_preserved vs Active_preserved",
      level = function() {
        L <- .L0()
        if ("phenotypeInactive_preserved" %in% nm) L[["phenotypeInactive_preserved"]] <- 1
        L
      },
      slope = function() {
        L <- .L0()
        if ("Time_years:phenotypeInactive_preserved" %in% nm) {
          L[["Time_years:phenotypeInactive_preserved"]] <- 1
        }
        L
      }
    ),
    list(
      contrast = "Active_limited vs Inactive_limited",
      level = function() {
        L <- .L0()
        if ("phenotypeActive_limited" %in% nm) L[["phenotypeActive_limited"]] <- 1
        if ("phenotypeInactive_limited" %in% nm) L[["phenotypeInactive_limited"]] <- -1
        L
      },
      slope = function() {
        L <- .L0()
        if ("Time_years:phenotypeActive_limited" %in% nm) {
          L[["Time_years:phenotypeActive_limited"]] <- 1
        }
        if ("Time_years:phenotypeInactive_limited" %in% nm) {
          L[["Time_years:phenotypeInactive_limited"]] <- -1
        }
        L
      }
    )
  )
  # 额外：Active_limited vs Active_preserved slope（ref 编码下即 interaction 项，便于正文引用）
  specs[[length(specs) + 1L]] <- list(
    contrast = "Active_limited vs Active_preserved",
    level = function() {
      L <- .L0()
      if ("phenotypeActive_limited" %in% nm) L[["phenotypeActive_limited"]] <- 1
      L
    },
    slope = function() {
      L <- .L0()
      if ("Time_years:phenotypeActive_limited" %in% nm) {
        L[["Time_years:phenotypeActive_limited"]] <- 1
      }
      L
    }
  )
  rows <- list()
  for (sp in specs) {
    for (tp in c("level", "slope")) {
      w <- .wald(sp[[tp]]())
      rows[[length(rows) + 1L]] <- data.frame(
        outcome = outcome,
        contrast = sp$contrast,
        type = tp,
        estimate = unname(w[["est"]]),
        se = unname(w[["se"]]),
        p_wald = unname(w[["p"]]),
        note = NA_character_,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

#' Survey glm 上两条预设 pairwise（相对 Active_preserved 编码）
pamob_svy_pairwise_contrasts <- function(fit, outcome = "DSST") {
  cf <- stats::coef(fit)
  V <- as.matrix(stats::vcov(fit))
  nm <- names(cf)
  .wald <- function(L) {
    L <- L[nm]
    if (any(is.na(L))) return(c(est = NA_real_, se = NA_real_, p = NA_real_))
    est <- sum(L * cf)
    se <- sqrt(as.numeric(t(L) %*% V[nm, nm, drop = FALSE] %*% L))
    if (!is.finite(se) || se <= 0) return(c(est = est, se = NA_real_, p = NA_real_))
    c(est = est, se = se, p = 2 * stats::pnorm(-abs(est / se)))
  }
  .L0 <- function() setNames(rep(0, length(cf)), nm)
  specs <- list(
    list(
      contrast = "Inactive_preserved vs Active_preserved",
      L = function() {
        L <- .L0()
        if ("phenotypeInactive_preserved" %in% nm) L[["phenotypeInactive_preserved"]] <- 1
        L
      }
    ),
    list(
      contrast = "Active_limited vs Inactive_limited",
      L = function() {
        L <- .L0()
        if ("phenotypeActive_limited" %in% nm) L[["phenotypeActive_limited"]] <- 1
        if ("phenotypeInactive_limited" %in% nm) L[["phenotypeInactive_limited"]] <- -1
        L
      }
    ),
    list(
      contrast = "Active_limited vs Active_preserved",
      L = function() {
        L <- .L0()
        if ("phenotypeActive_limited" %in% nm) L[["phenotypeActive_limited"]] <- 1
        L
      }
    )
  )
  rows <- lapply(specs, function(sp) {
    w <- .wald(sp$L())
    data.frame(
      outcome = outcome, contrast = sp$contrast, type = "mean_diff",
      estimate = unname(w[["est"]]), se = unname(w[["se"]]),
      p_wald = unname(w[["p"]]), note = NA_character_,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

pamob_fit_lmm <- function(long, outcome, bl) {
  pamob_ensure_packages(c("lme4", "lmerTest"))
  long <- long[!is.na(long[[outcome]]) & !is.na(long$phenotype) & !is.na(long$Time_years), , drop = FALSE]
  long$phenotype <- stats::relevel(
    factor(long$phenotype, levels = unname(pamob_phenotype_labels())),
    ref = "Active_preserved"
  )
  cov1 <- intersect(bl$covariates_model1 %||% character(0), names(long))
  cov2 <- intersect(unique(c(cov1, bl$covariates_model2 %||% character(0))), names(long))
  cov3 <- intersect(unique(c(cov2, bl$covariates_model3 %||% character(0))), names(long))

  fit_one <- function(covs, label) {
    rhs <- "Time_years * phenotype"
    if (length(covs)) rhs <- paste(rhs, "+", paste(covs, collapse = " + "))
    fml <- stats::as.formula(paste0(outcome, " ~ ", rhs, " + (1 | ID_h)"))
    fit <- tryCatch(lmerTest::lmer(fml, data = long, REML = TRUE), error = function(e) e)
    if (inherits(fit, "error")) {
      return(data.frame(
        model = label, term = NA_character_, estimate = NA_real_,
        std.error = NA_real_, p.value = NA_real_,
        note = conditionMessage(fit), stringsAsFactors = FALSE
      ))
    }
    sm <- summary(fit)$coefficients
    data.frame(
      model = label,
      term = rownames(sm),
      estimate = sm[, "Estimate"],
      std.error = sm[, "Std. Error"],
      p.value = if ("Pr(>|t|)" %in% colnames(sm)) sm[, "Pr(>|t|)"] else NA_real_,
      note = NA_character_,
      stringsAsFactors = FALSE
    )
  }

  tab <- rbind(
    fit_one(character(0), "Model0_time_pheno"),
    fit_one(cov1, "Model1"),
    fit_one(cov2, "Model2"),
    fit_one(cov3, "Model3")
  )
  list(table = tab, data = long, outcome = outcome)
}

#' 选取实际存在的协变量列
pamob_resolve_covars <- function(df, covars) {
  intersect(as.character(covars %||% character(0)), names(df))
}

#' 构建 phenotype + covars 公式右侧
pamob_fml_rhs <- function(covars, include_phenotype = TRUE) {
  parts <- character(0)
  if (isTRUE(include_phenotype)) parts <- c(parts, "phenotype")
  parts <- c(parts, covars)
  if (!length(parts)) "1" else paste(parts, collapse = " + ")
}

#' PA 区间代表值（Tian & Shi 2022；方案 §5.2）
pamob_pa_duration_map <- function() {
  data.frame(
    questionnaire_interval = c("10–<30 min/day", "30 min–<2 h/day", "2–<4 h/day", "≥4 h/day"),
    representative_minutes = c(20L, 75L, 180L, 240L),
    source = "Tian & Shi 2022 J Clin Med; proposal §5.2",
    stringsAsFactors = FALSE
  )
}

#' PFQ 编码规则说明（方案 §6）
pamob_pfq_coding_rules <- function() {
  c(
    "PFQ061B/C/D/I: 1=no difficulty; 2=some; 3=much; 4=unable; 5=do not do; 7/9=refused/DK.",
    "Main analysis: codes 2–5 (and structural skip from PFQ054=Yes when item missing) → mobility limited.",
    "Answer 5 (do not do): main = limited; sensitivity = exclude respondents with any item=5.",
    "PFQ054 structural skip: if walking difficulty without device, PFQ061B/C may be blank → treat as limited (upstream D04).",
    "ADL/IADL not used in main mobility score."
  )
}

#' 四组基线特征表（连续 mean(SD)；分类 n(%)）
pamob_baseline_by_phenotype <- function(df, pheno_col = "phenotype",
                                        continuous = character(0),
                                        categorical = character(0),
                                        digits_cont = 2L, digits_pct = 1L) {
  df <- as.data.frame(df)
  if (!pheno_col %in% names(df)) stop("缺 phenotype 列", call. = FALSE)
  df[[pheno_col]] <- factor(as.character(df[[pheno_col]]), levels = unname(pamob_phenotype_labels()))
  levs <- levels(df[[pheno_col]])
  continuous <- intersect(continuous, names(df))
  categorical <- intersect(categorical, names(df))
  rows <- list()
  # N row
  ntab <- table(df[[pheno_col]], useNA = "no")
  rows[[length(rows) + 1L]] <- data.frame(
    variable = "N", level = "",
    setNames(as.list(as.integer(ntab[levs])), levs),
    stringsAsFactors = FALSE
  )
  for (v in continuous) {
    vals <- lapply(levs, function(L) {
      x <- suppressWarnings(as.numeric(df[[v]][df[[pheno_col]] == L]))
      x <- x[!is.na(x)]
      if (!length(x)) return("")
      sprintf(paste0("%.", digits_cont, "f (%.", digits_cont, "f)"), mean(x), stats::sd(x))
    })
    rows[[length(rows) + 1L]] <- data.frame(
      variable = v, level = "Mean (SD)",
      setNames(vals, levs), stringsAsFactors = FALSE
    )
  }
  for (v in categorical) {
    x <- as.character(df[[v]])
    x[is.na(x) | !nzchar(x)] <- "(Missing)"
    ul <- sort(unique(x))
    for (lv in ul) {
      vals <- lapply(levs, function(L) {
        idx <- df[[pheno_col]] == L
        n <- sum(idx, na.rm = TRUE)
        k <- sum(idx & x == lv, na.rm = TRUE)
        if (!n) return("")
        sprintf(paste0("%d (%.", digits_pct, "f)"), k, 100 * k / n)
      })
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, level = lv,
        setNames(vals, levs), stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

#' 从 svyglm/glm summary 系数矩阵取 P；df.residual≤0 时 Pr 常为 NaN → 用正态近似兜底
pamob_extract_coef_p <- function(sm, fit = NULL) {
  sm <- as.matrix(sm)
  cn <- colnames(sm)
  p <- if ("Pr(>|t|)" %in% cn) {
    as.numeric(sm[, "Pr(>|t|)"])
  } else if ("Pr(>|z|)" %in% cn) {
    as.numeric(sm[, "Pr(>|z|)"])
  } else if (ncol(sm) >= 4L) {
    as.numeric(sm[, 4L])
  } else {
    rep(NA_real_, nrow(sm))
  }
  need <- !is.finite(p)
  if (!any(need)) return(p)
  est <- as.numeric(sm[, 1L])
  se <- as.numeric(sm[, 2L])
  tstat <- est / se
  ddf <- tryCatch(as.numeric(fit$df.residual), error = function(e) NA_real_)
  if (is.null(ddf) || length(ddf) != 1L || !is.finite(ddf) || ddf <= 0) {
    p[need] <- 2 * stats::pnorm(-abs(tstat[need]))
  } else {
    p[need] <- 2 * stats::pt(-abs(tstat[need]), df = ddf)
  }
  p
}

#' Survey-weighted glm 系数表（单次）；自动丢掉退化协变量
pamob_svyglm_coef_tab <- function(des, outcome, covars, model_label, weight_note, n) {
  d <- des$variables
  covars <- pamob_drop_degenerate_covars(d, covars)
  rhs <- pamob_fml_rhs(covars)
  fml <- stats::as.formula(paste(outcome, "~", rhs))
  fit <- tryCatch(survey::svyglm(fml, design = des), error = function(e) e)
  if (inherits(fit, "error")) {
    return(data.frame(
      model = model_label, outcome = outcome, term = NA_character_,
      estimate = NA_real_, std.error = NA_real_, p.value = NA_real_,
      weight = weight_note, n = n, note = conditionMessage(fit),
      stringsAsFactors = FALSE
    ))
  }
  sm <- summary(fit)$coefficients
  data.frame(
    model = model_label, outcome = outcome, term = rownames(sm),
    estimate = sm[, 1], std.error = sm[, 2],
    p.value = pamob_extract_coef_p(sm, fit),
    weight = weight_note, n = n, note = NA_character_,
    stringsAsFactors = FALSE
  )
}

#' 汇总根目录 Figures：固定 Figure 1–4 + Figure S1（NHANES 纳排）
pamob_collect_main_figures <- function(batch_root) {
  src <- list(
    "Figure 1. PA-mobility phenotype framework.pdf" =
      file.path(batch_root, "by_unit", "【success】CHARLS", "Figures", "pdf",
                "Figure 1. PA-mobility phenotype framework.pdf"),
    "Figure 2. CHARLS flowchart.pdf" =
      file.path(batch_root, "by_unit", "【success】CHARLS", "Figures", "pdf",
                "Figure 2. CHARLS flowchart.pdf"),
    "Figure 3. CHARLS cognitive trajectories.pdf" =
      file.path(batch_root, "by_unit", "【success】CHARLS", "Figures", "pdf",
                "Figure 3. CHARLS cognitive trajectories.pdf"),
    "Figure 4. NHANES DSST and NfL panel.pdf" =
      file.path(batch_root, "by_unit", "【success】NHANES", "Figures", "pdf",
                "Figure 4. NHANES DSST and NfL panel.pdf"),
    "Figure S1. NHANES flowchart.pdf" =
      file.path(batch_root, "by_unit", "【success】NHANES", "Figures", "pdf",
                "Figure S1. NHANES flowchart.pdf")
  )
  # NHANES 可能被编号顺延成 Figure 1 — 兜底搜索
  if (!file.exists(src[[4L]])) {
    alt <- list.files(file.path(batch_root, "by_unit", "【success】NHANES", "Figures", "pdf"),
                      pattern = "NfL|DSST", full.names = TRUE)
    if (length(alt)) src[[4L]] <- alt[[1L]]
  }
  if (!file.exists(src[[5L]])) {
    alt_s <- list.files(file.path(batch_root, "by_unit", "【success】NHANES", "Figures"),
                        pattern = "NHANES flowchart|S1.*flowchart|S2.*flowchart",
                        recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
    alt_s <- alt_s[grepl("\\.pdf$", alt_s, ignore.case = TRUE)]
    if (length(alt_s)) src[[5L]] <- alt_s[[1L]]
  }
  fig_root <- file.path(batch_root, "Figures")
  dir.create(fig_root, recursive = TRUE, showWarnings = FALSE)
  # 清掉旧 S2 命名残留（已统一为 S1）
  old_s2 <- list.files(fig_root, pattern = "Figure S2\\. NHANES flowchart",
                       recursive = TRUE, full.names = TRUE)
  if (length(old_s2)) unlink(old_s2)
  copied <- character(0)
  for (nm in names(src)) {
    if (file.exists(src[[nm]])) {
      file.copy(src[[nm]], file.path(fig_root, nm), overwrite = TRUE)
      copied <- c(copied, nm)
    }
  }
  list(figures_dir = fig_root, copied = copied, sources = src)
}

#' PA 替代时长代表值（敏感性；主分析仍用 20/75/180/240）
pamob_pa_duration_map_alt <- function() {
  data.frame(
    questionnaire_interval = c("10–<30 min/day", "30 min–<2 h/day", "2–<4 h/day", "≥4 h/day"),
    representative_minutes_primary = c(20L, 75L, 180L, 240L),
    representative_minutes_alt = c(15L, 60L, 150L, 210L),
    source = "Sensitivity remap of Tian & Shi bins (proposal §5.2)",
    stringsAsFactors = FALSE
  )
}

#' 从 da053/54/55 映射每日分钟（map = c(lo30, mid, hi2, hi4)）
pamob_minutes_per_day_from_bins <- function(a53, a54, a55, map = c(20, 75, 180, 240)) {
  map <- as.numeric(map)
  ifelse(!is.na(a54) & a54 == 1, map[1],
    ifelse(!is.na(a54) & a54 == 2 & !is.na(a53) & a53 == 1, map[2],
      ifelse(!is.na(a53) & a53 == 2 & !is.na(a55) & a55 == 1, map[3],
        ifelse(!is.na(a55) & a55 == 2, map[4], NA_real_))))
}

#' 从 D03_physical_activity.RData 按替代时长代表值重算 PA sufficient
#' （主分析分钟 20/75/180/240 → 敏感性 15/60/150/210；ID 已与 D05 对齐）
pamob_compute_pa_sufficient_from_raw <- function(charls_dir, wave = 2011L,
                                                 min_map = c(15, 60, 150, 210),
                                                 met_threshold = 600) {
  wave <- as.integer(wave)[1L]
  rds <- file.path(charls_dir, "D03_physical_activity.RData")
  if (!file.exists(rds)) return(NULL)
  e <- new.env(parent = emptyenv())
  load(rds, envir = e)
  pa <- NULL
  for (o in ls(e)) if (is.data.frame(e[[o]])) { pa <- e[[o]]; break }
  if (is.null(pa)) return(NULL)
  pa$wave <- as.integer(pa$wave)
  pa <- pa[pa$wave == wave, , drop = FALSE]
  if (!nrow(pa)) return(NULL)
  if (!"ID_h" %in% names(pa)) return(NULL)
  pa$ID_h <- pamob_pad_id12(pa$ID_h)

  primary <- c(20, 75, 180, 240)
  min_map <- as.numeric(min_map)
  .remap_min <- function(m) {
    m <- suppressWarnings(as.numeric(m))
    out <- rep(NA_real_, length(m))
    for (i in seq_along(primary)) out[!is.na(m) & m == primary[i]] <- min_map[i]
    out
  }
  need <- c("vig_days", "vig_min_day", "mod_days", "mod_min_day", "light_days", "light_min_day")
  if (!all(need %in% names(pa))) return(NULL)
  vig <- ifelse(!is.na(pa$vig_days) & pa$vig_days == 0, 0,
                pa$vig_days * .remap_min(pa$vig_min_day))
  mod <- ifelse(!is.na(pa$mod_days) & pa$mod_days == 0, 0,
                pa$mod_days * .remap_min(pa$mod_min_day))
  light <- ifelse(!is.na(pa$light_days) & pa$light_days == 0, 0,
                  pa$light_days * .remap_min(pa$light_min_day))
  tot <- ifelse(is.na(vig) | is.na(mod) | is.na(light), NA_real_,
                8 * vig + 4 * mod + 3.3 * light)
  out <- data.frame(
    ID_h = pa$ID_h,
    pa_total_alt = tot,
    pa_sufficient_alt = ifelse(is.na(tot), NA_integer_, as.integer(tot >= met_threshold)),
    stringsAsFactors = FALSE
  )
  out[!duplicated(out$ID_h), , drop = FALSE]
}

#' 从 2011 Health dta 构建 ADL/IADL 残障标志（db010–db020 任一项有困难）
pamob_build_adl_iadl_flag <- function(charls_dir, wave = 2011L) {
  pamob_ensure_packages("haven")
  wave <- as.integer(wave)[1L]
  cand <- c(
    file.path(charls_dir, "rawdata", "health_status_and_functioning-2011.dta"),
    file.path(charls_dir, "rawdata", "Health_Status_and_Functioning-2011.dta"),
    file.path(charls_dir, "rawdata", sprintf("Health_Status_and_Functioning-%s.dta", wave)),
    file.path(charls_dir, "rawdata", sprintf("health_status_and_functioning-%s.dta", wave))
  )
  path <- cand[file.exists(cand)][1]
  if (is.na(path) || !nzchar(path)) return(NULL)
  d <- as.data.frame(haven::read_dta(path))
  if (!"ID" %in% names(d)) return(NULL)
  adl <- paste0("db", sprintf("%03d", 10:15))
  iadl <- paste0("db", sprintf("%03d", 16:20))
  items <- intersect(c(adl, iadl), names(d))
  if (!length(items)) return(NULL)
  mat <- sapply(items, function(v) {
    x <- suppressWarnings(as.numeric(d[[v]]))
    # 1=no difficulty; 2/3/4 = difficulty / need help / unable
    ifelse(is.na(x), NA_integer_, as.integer(x >= 2))
  })
  if (is.null(dim(mat))) mat <- cbind(mat)
  any_diff <- as.integer(rowSums(mat == 1L, na.rm = TRUE) > 0L)
  # 若全部条目缺失 → NA
  all_miss <- rowSums(!is.na(mat)) == 0L
  any_diff[all_miss] <- NA_integer_
  data.frame(
    ID_h = pamob_charls_id_h(d$ID),
    adl_iadl_disabled = any_diff,
    n_adl_iadl_items_nonmiss = as.integer(rowSums(!is.na(mat))),
    stringsAsFactors = FALSE
  )[!duplicated(pamob_charls_id_h(d$ID)), , drop = FALSE]
}

#' CHARLS 2011 social participation（da056/da057）→ 基线 contextual 指标
#' 编码依据 Health_Status 2011 变量标签（da056s1–s12 多选）
#' 社区设施/公交：并入 rawdata/community*.dta（JB029 / JB003–JB004），经 communityID
pamob_extract_charls_contextual <- function(charls_dir, wave = 2011L) {
  pamob_ensure_packages("haven")
  wave <- as.integer(wave)[1L]
  cand <- c(
    file.path(charls_dir, "rawdata", "health_status_and_functioning-2011.dta"),
    file.path(charls_dir, "rawdata", "Health_Status_and_Functioning-2011.dta"),
    file.path(charls_dir, "rawdata", sprintf("Health_Status_and_Functioning-%s.dta", wave)),
    file.path(charls_dir, "rawdata", sprintf("health_status_and_functioning-%s.dta", wave))
  )
  path <- cand[file.exists(cand)][1]
  if (is.na(path) || !nzchar(path)) return(NULL)
  d <- as.data.frame(haven::read_dta(path))
  if (!"ID" %in% names(d)) return(NULL)
  .sel <- function(col, code) {
    if (!col %in% names(d)) return(rep(NA_integer_, nrow(d)))
    x <- suppressWarnings(as.numeric(d[[col]]))
    ifelse(is.na(x), NA_integer_, as.integer(x == code))
  }
  # 2011 多选：列值等于选项码表示勾选
  friend <- .sel("da056s1", 1)
  cards_club <- .sel("da056s2", 2) # majong/cards/chess or community club (2011 wording)
  help_apart <- .sel("da056s3", 3)
  went_club <- .sel("da056s4", 4)
  community_org <- .sel("da056s5", 5)
  volunteer <- .sel("da056s6", 6)
  care_sick <- .sel("da056s7", 7)
  none_act <- .sel("da056s12", 12)
  all_miss <- rep(FALSE, nrow(d))
  # 若全部 da056 缺失 → social_any NA
  da_cols <- paste0("da056s", 1:12)
  da_cols <- da_cols[da_cols %in% names(d)]
  if (length(da_cols)) {
    all_miss <- rowSums(!is.na(as.data.frame(lapply(da_cols, function(v) d[[v]])))) == 0L
  }
  # 多选：已作答者未勾选的选项记 0（勿把未勾选当缺失，否则 pct_yes 会假性=100%）
  .zero_if_answered <- function(x) {
    x[!all_miss & is.na(x)] <- 0L
    x[all_miss] <- NA_integer_
    x
  }
  friend <- .zero_if_answered(friend)
  cards_club <- .zero_if_answered(cards_club)
  help_apart <- .zero_if_answered(help_apart)
  went_club <- .zero_if_answered(went_club)
  community_org <- .zero_if_answered(community_org)
  volunteer <- .zero_if_answered(volunteer)
  care_sick <- .zero_if_answered(care_sick)
  none_act <- .zero_if_answered(none_act)

  social_club <- as.integer(
    rowSums(cbind(cards_club, went_club), na.rm = TRUE) > 0L
  )
  social_help <- as.integer(
    rowSums(cbind(help_apart, care_sick), na.rm = TRUE) > 0L
  )
  social_any <- as.integer(
    rowSums(cbind(friend, cards_club, help_apart, went_club, community_org, volunteer, care_sick),
            na.rm = TRUE) > 0L
  )
  social_club[all_miss] <- NA_integer_
  social_help[all_miss] <- NA_integer_
  social_any[all_miss] <- NA_integer_
  n_soc <- as.integer(rowSums(cbind(
    friend, cards_club, went_club, community_org, volunteer, help_apart, care_sick
  ), na.rm = TRUE))
  n_soc[all_miss] <- NA_integer_
  # friend frequency if selected (da057_1_ often maps to first listed; only keep when friend selected)
  friend_freq <- if ("da057_1_" %in% names(d)) suppressWarnings(as.integer(d$da057_1_)) else NA_integer_

  # ---- 社区问卷：recreation (JB029) + public transport (JB003/JB004) ----
  # JB029_1[i]: 1=有 2=没有；重点休闲/康体项：篮球/泳池/露天健身/乒桌/棋牌室/
  # 乒室/舞蹈队/老年活动中心/其他娱乐（见 2011 Community Questionnaire）
  community_recreation_facility <- rep(NA_integer_, nrow(d))
  community_public_transport <- rep(NA_integer_, nrow(d))
  bus_lines_n <- rep(NA_real_, nrow(d))
  bus_stop_km <- rep(NA_real_, nrow(d))
  recreation_n_types <- rep(NA_integer_, nrow(d))
  community_file_used <- NA_character_
  comm_cand <- c(
    file.path(charls_dir, "rawdata", "community-2011.dta"),
    file.path(charls_dir, "rawdata", "community.dta"),
    file.path(charls_dir, "rawdata", sprintf("community-%s.dta", wave)),
    file.path(charls_dir, "community-2011.dta"),
    file.path(charls_dir, "community.dta")
  )
  cpath <- comm_cand[file.exists(comm_cand)][1]
  if (!is.na(cpath) && nzchar(cpath) && "communityID" %in% names(d)) {
    community_file_used <- basename(cpath)
    comm <- as.data.frame(haven::read_dta(cpath))
    if ("communityID" %in% names(comm)) {
      rec_idx <- c(1L, 2L, 3L, 4L, 5L, 6L, 8L, 11L, 14L) # recreation-relevant JB029 items
      rec_cols <- paste0("jb029_1_", rec_idx, "_")
      rec_cols <- rec_cols[rec_cols %in% names(comm)]
      if (length(rec_cols)) {
        rec_mat <- as.data.frame(lapply(rec_cols, function(v) {
          x <- suppressWarnings(as.numeric(comm[[v]]))
          ifelse(is.na(x), NA_integer_, as.integer(x == 1))
        }), stringsAsFactors = FALSE)
        names(rec_mat) <- rec_cols
        comm$recreation_n_types <- as.integer(rowSums(rec_mat, na.rm = TRUE))
        any_ans <- rowSums(!is.na(rec_mat)) > 0L
        comm$community_recreation_facility <- ifelse(any_ans, as.integer(comm$recreation_n_types > 0L), NA_integer_)
      } else {
        comm$recreation_n_types <- NA_integer_
        comm$community_recreation_facility <- NA_integer_
      }
      if ("jb003" %in% names(comm)) {
        bl <- suppressWarnings(as.numeric(comm$jb003))
        bl[bl < 0] <- NA_real_ # -999 等特殊码
        comm$bus_lines_n <- bl
        # 有公交线路 = 线路数 > 0；0 条记为无公交
        comm$community_public_transport <- ifelse(is.na(bl), NA_integer_, as.integer(bl > 0))
      } else {
        comm$bus_lines_n <- NA_real_
        comm$community_public_transport <- NA_integer_
      }
      if ("jb004" %in% names(comm)) {
        km <- suppressWarnings(as.numeric(comm$jb004))
        km[km < 0] <- NA_real_
        comm$bus_stop_km <- km
      } else {
        comm$bus_stop_km <- NA_real_
      }
      keep <- c("communityID", "community_recreation_facility", "community_public_transport",
                "bus_lines_n", "bus_stop_km", "recreation_n_types")
      keep <- keep[keep %in% names(comm)]
      cm <- comm[!duplicated(as.character(comm$communityID)), keep, drop = FALSE]
      cm$communityID <- as.character(cm$communityID)
      d$communityID <- as.character(d$communityID)
      m <- match(d$communityID, cm$communityID)
      community_recreation_facility <- cm$community_recreation_facility[m]
      community_public_transport <- cm$community_public_transport[m]
      bus_lines_n <- cm$bus_lines_n[m]
      bus_stop_km <- cm$bus_stop_km[m]
      recreation_n_types <- cm$recreation_n_types[m]
    }
  }

  out <- data.frame(
    ID_h = pamob_charls_id_h(d$ID),
    ctx_wave = wave,
    social_friend = friend,
    social_club_or_cards = social_club,
    social_community_org = community_org,
    social_volunteer = volunteer,
    social_help_or_care = social_help,
    social_any = social_any,
    social_none = none_act,
    social_n_types = n_soc,
    social_friend_freq = friend_freq, # 1 almost daily; 2 weekly; 3 less often
    community_recreation_facility = community_recreation_facility,
    community_public_transport = community_public_transport,
    recreation_n_types = recreation_n_types,
    bus_lines_n = bus_lines_n,
    bus_stop_km = bus_stop_km,
    stringsAsFactors = FALSE
  )
  attr(out, "community_file") <- community_file_used
  out[!duplicated(out$ID_h), , drop = FALSE]
}

#' NHANES contextual：PA domain + PFQ 社交/外出/辅具 + PIR
pamob_extract_nhanes_contextual <- function(nhanes_dir, cycle = "H", source_file = "2013-2014") {
  pamob_ensure_packages("haven")
  pa <- pamob_read_csv(file.path(nhanes_dir, "D03_physical_activity.csv"))
  pa <- pa[as.character(pa$cycle) == as.character(cycle), , drop = FALSE]
  pa$SEQN <- as.integer(pa$SEQN)
  # Domain METs（已在 D03 算好）
  .pos <- function(v) {
    if (!v %in% names(pa)) return(rep(NA_integer_, nrow(pa)))
    x <- suppressWarnings(as.numeric(pa[[v]]))
    ifelse(is.na(x), NA_integer_, as.integer(x > 0))
  }
  # Yes/No PAQ：1=yes, 2=no
  .yes <- function(v) {
    if (!v %in% names(pa)) return(rep(NA_integer_, nrow(pa)))
    x <- suppressWarnings(as.integer(pa[[v]]))
    ifelse(is.na(x) | x %in% c(7L, 9L), NA_integer_, as.integer(x == 1L))
  }
  work_met <- if (all(c("MET_PAQ605", "MET_PAQ620") %in% names(pa))) {
    rowSums(cbind(
      suppressWarnings(as.numeric(pa$MET_PAQ605)),
      suppressWarnings(as.numeric(pa$MET_PAQ620))
    ), na.rm = TRUE)
  } else rep(NA_real_, nrow(pa))
  trans_met <- if ("MET_PAQ635" %in% names(pa)) suppressWarnings(as.numeric(pa$MET_PAQ635)) else NA_real_
  rec_met <- if (all(c("MET_PAQ650", "MET_PAQ665") %in% names(pa))) {
    rowSums(cbind(
      suppressWarnings(as.numeric(pa$MET_PAQ650)),
      suppressWarnings(as.numeric(pa$MET_PAQ665))
    ), na.rm = TRUE)
  } else rep(NA_real_, nrow(pa))
  out <- data.frame(
    SEQN = pa$SEQN,
    pa_domain_work = as.integer(work_met > 0),
    pa_domain_transport = as.integer(trans_met > 0),
    pa_domain_recreation = as.integer(rec_met > 0),
    pa_work_yes = as.integer(pmax(.yes("PAQ605"), .yes("PAQ620"), na.rm = TRUE) > 0L),
    pa_transport_yes = .yes("PAQ635"),
    pa_recreation_yes = as.integer(pmax(.yes("PAQ650"), .yes("PAQ665"), na.rm = TRUE) > 0L),
    work_met = work_met,
    transport_met = trans_met,
    recreation_met = rec_met,
    stringsAsFactors = FALSE
  )

  # PFQ_H：社交活动困难、辅具
  pfq_path <- file.path(nhanes_dir, "PFQ_H.XPT")
  if (file.exists(pfq_path)) {
    pfq <- as.data.frame(haven::read_xpt(pfq_path))
    pfq$SEQN <- as.integer(pfq$SEQN)
    .diff <- function(v) {
      # PFQ061*: 1 no difficulty … 4 unable; 5 do not do → treat 2–5 as limited
      if (!v %in% names(pfq)) return(rep(NA_integer_, nrow(pfq)))
      x <- suppressWarnings(as.integer(pfq[[v]]))
      ifelse(is.na(x) | x %in% c(7L, 9L), NA_integer_, as.integer(x %in% 2:5))
    }
    .yn <- function(v) {
      if (!v %in% names(pfq)) return(rep(NA_integer_, nrow(pfq)))
      x <- suppressWarnings(as.integer(pfq[[v]]))
      ifelse(is.na(x) | x %in% c(7L, 9L), NA_integer_, as.integer(x == 1L))
    }
    pfq_ctx <- data.frame(
      SEQN = pfq$SEQN,
      social_event_difficulty = .diff("PFQ061R"),
      leisure_home_difficulty = .diff("PFQ061S"),
      work_limitation = .yn("PFQ049"),
      assistive_walk_equipment = .yn("PFQ054"),
      special_healthcare_equipment = .yn("PFQ090"),
      stringsAsFactors = FALSE
    )
    out <- merge(out, pfq_ctx, by = "SEQN", all.x = TRUE)
  } else {
    out$social_event_difficulty <- NA_integer_
    out$leisure_home_difficulty <- NA_integer_
    out$work_limitation <- NA_integer_
    out$assistive_walk_equipment <- NA_integer_
    out$special_healthcare_equipment <- NA_integer_
  }

  # HUQ_H / HIQ_H：就医可及性与保险（老师 contextual 清单）
  huq_path <- file.path(nhanes_dir, sprintf("HUQ_%s.XPT", cycle))
  if (!file.exists(huq_path)) huq_path <- file.path(nhanes_dir, "HUQ_H.XPT")
  if (file.exists(huq_path)) {
    huq <- as.data.frame(haven::read_xpt(huq_path))
    huq$SEQN <- as.integer(huq$SEQN)
    .yn_h <- function(v, yes = 1L) {
      if (!v %in% names(huq)) return(rep(NA_integer_, nrow(huq)))
      x <- suppressWarnings(as.integer(huq[[v]]))
      ifelse(is.na(x) | x %in% c(7L, 9L, 77L, 99L), NA_integer_, as.integer(x == yes))
    }
    # HUQ030: 1=yes routine place, 2=no, 3=more than one → has place if 1 or 3
    has_place <- if ("HUQ030" %in% names(huq)) {
      x <- suppressWarnings(as.integer(huq$HUQ030))
      ifelse(is.na(x) | x %in% c(7L, 9L), NA_integer_, as.integer(x %in% c(1L, 3L)))
    } else rep(NA_integer_, nrow(huq))
    visits <- if ("HUQ051" %in% names(huq)) {
      x <- suppressWarnings(as.numeric(huq$HUQ051))
      x[x %in% c(77, 99)] <- NA_real_
      x
    } else rep(NA_real_, nrow(huq))
    huq_ctx <- data.frame(
      SEQN = huq$SEQN,
      has_routine_healthcare_place = has_place,
      healthcare_visits_past_year = visits,
      overnight_hospital_past_year = .yn_h("HUQ071"),
      seen_mental_health_past_year = .yn_h("HUQ090"),
      stringsAsFactors = FALSE
    )
    out <- merge(out, huq_ctx, by = "SEQN", all.x = TRUE)
  } else {
    out$has_routine_healthcare_place <- NA_integer_
    out$healthcare_visits_past_year <- NA_real_
    out$overnight_hospital_past_year <- NA_integer_
    out$seen_mental_health_past_year <- NA_integer_
  }

  hiq_path <- file.path(nhanes_dir, sprintf("HIQ_%s.XPT", cycle))
  if (!file.exists(hiq_path)) hiq_path <- file.path(nhanes_dir, "HIQ_H.XPT")
  if (file.exists(hiq_path)) {
    hiq <- as.data.frame(haven::read_xpt(hiq_path))
    hiq$SEQN <- as.integer(hiq$SEQN)
    .yn_i <- function(v, yes = 1L) {
      if (!v %in% names(hiq)) return(rep(NA_integer_, nrow(hiq)))
      x <- suppressWarnings(as.integer(hiq[[v]]))
      ifelse(is.na(x) | x %in% c(7L, 9L, 77L, 99L), NA_integer_, as.integer(x == yes))
    }
    # HIQ031*: selected type coded as specific integers when covered
    .sel_code <- function(v, code) {
      if (!v %in% names(hiq)) return(rep(NA_integer_, nrow(hiq)))
      x <- suppressWarnings(as.integer(hiq[[v]]))
      # 未选中多为 NA；选中为 code；拒答 77/99 → NA
      ifelse(!is.na(x) & x %in% c(77L, 99L), NA_integer_,
             ifelse(is.na(x), 0L, as.integer(x == code)))
    }
    covered <- .yn_i("HIQ011")
    # 仅当 HIQ011 作答时，把未勾选保险类型当 0
    priv <- .sel_code("HIQ031A", 14L)
    medi <- .sel_code("HIQ031B", 15L)
    medicaid <- .sel_code("HIQ031D", 17L)
    if (!all(is.na(covered))) {
      answered <- !is.na(covered)
      priv[answered & is.na(priv)] <- 0L
      medi[answered & is.na(medi)] <- 0L
      medicaid[answered & is.na(medicaid)] <- 0L
      priv[!answered] <- NA_integer_
      medi[!answered] <- NA_integer_
      medicaid[!answered] <- NA_integer_
    }
    hiq_ctx <- data.frame(
      SEQN = hiq$SEQN,
      covered_by_health_insurance = covered,
      private_insurance = priv,
      medicare = medi,
      medicaid = medicaid,
      no_insurance_spell_past_year = .yn_i("HIQ210"),
      insurance_covers_prescriptions = .yn_i("HIQ270"),
      stringsAsFactors = FALSE
    )
    out <- merge(out, hiq_ctx, by = "SEQN", all.x = TRUE)
  } else {
    out$covered_by_health_insurance <- NA_integer_
    out$private_insurance <- NA_integer_
    out$medicare <- NA_integer_
    out$medicaid <- NA_integer_
    out$no_insurance_spell_past_year <- NA_integer_
    out$insurance_covers_prescriptions <- NA_integer_
  }

  # PIR from baseline
  demo_path <- pamob_find_first(nhanes_dir, "^D01_baseline_NHANES.*\\.RData$")
  if (!is.na(demo_path) && file.exists(demo_path)) {
    demo <- pamob_load_rdata_df(demo_path, prefer = c("baseline", "Baseline"))
    idn <- if ("SEQN" %in% names(demo)) "SEQN" else if ("ID" %in% names(demo)) "ID" else NA_character_
    if (!is.na(idn)) {
      demo$SEQN <- as.integer(demo[[idn]])
      if ("Source_File" %in% names(demo)) {
        demo <- demo[as.character(demo$Source_File) == source_file, , drop = FALSE]
      }
      demo <- demo[!duplicated(demo$SEQN), , drop = FALSE]
      keep <- intersect(c("SEQN", "PIR"), names(demo))
      out <- merge(out, demo[, keep, drop = FALSE], by = "SEQN", all.x = TRUE)
    }
  }
  if (!"PIR" %in% names(out)) out$PIR <- NA_real_
  out[!duplicated(out$SEQN), , drop = FALSE]
}

#' 发表级表型配色（Okabe–Ito 改编，四组一致贯穿 Fig1–4）
pamob_pheno_colors <- function() {
  c(
    Active_preserved = "#0072B2",
    Inactive_preserved = "#E69F00",
    Active_limited = "#009E73",
    Inactive_limited = "#D55E00"
  )
}

pamob_pheno_labels_pretty <- function() {
  c(
    Active_preserved = "Active\u2013preserved",
    Inactive_preserved = "Inactive\u2013preserved",
    Active_limited = "Active\u2013limited",
    Inactive_limited = "Inactive\u2013limited"
  )
}

pamob_theme_pub <- function(base_size = 11) {
  ggplot2::theme_classic(base_size = base_size) +
    ggplot2::theme(
      plot.title = ggplot2::element_blank(),
      axis.title = ggplot2::element_text(color = "black"),
      axis.text = ggplot2::element_text(color = "black"),
      axis.line = ggplot2::element_line(linewidth = 0.5, color = "black"),
      axis.ticks = ggplot2::element_line(linewidth = 0.4, color = "black"),
      legend.title = ggplot2::element_text(face = "bold", size = base_size),
      legend.text = ggplot2::element_text(size = base_size - 1),
      legend.key = ggplot2::element_blank(),
      legend.background = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "grey95", color = "black", linewidth = 0.4),
      strip.text = ggplot2::element_text(face = "bold", color = "black"),
      panel.grid.major = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      plot.margin = ggplot2::margin(6, 10, 6, 6)
    )
}

pamob_ggsave_pub <- function(path, plot, width = 7, height = 5, dpi = 300) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  use_cairo <- isTRUE(capabilities("cairo"))
  pdf_device <- if (use_cairo) grDevices::cairo_pdf else grDevices::pdf
  ok_pdf <- tryCatch({
    ggplot2::ggsave(path, plot, width = width, height = height, dpi = dpi, device = pdf_device)
    TRUE
  }, error = function(e) FALSE)
  if (!ok_pdf) {
    ggplot2::ggsave(path, plot, width = width, height = height, dpi = dpi)
  }
  png_path <- sub("\\.pdf$", ".png", path, ignore.case = TRUE)
  png_device <- if (use_cairo) grDevices::png else NULL
  if (!is.null(png_device)) {
    ggplot2::ggsave(png_path, plot, width = width, height = height, dpi = dpi,
                    device = png_device, type = "cairo")
  } else {
    ggplot2::ggsave(png_path, plot, width = width, height = height, dpi = dpi)
  }
  invisible(path)
}

#' Figure 1：2×2 概念矩阵（文献级）
pamob_draw_fig1_concept <- function(pdf_path) {
  pamob_ensure_packages("ggplot2")
  cols <- pamob_pheno_colors()
  labs <- pamob_pheno_labels_pretty()
  ge <- "\u2265"
  pa_lev <- c(paste0("Sufficient (", ge, "600)"), "Insufficient (<600)")
  df <- data.frame(
    pa = factor(c(pa_lev[1], pa_lev[1], pa_lev[2], pa_lev[2]), levels = pa_lev),
    mob = factor(c("Preserved", "Limited", "Preserved", "Limited"),
                 levels = c("Limited", "Preserved")),
    code = c("Active_preserved", "Active_limited", "Inactive_preserved", "Inactive_limited"),
    grp = c("1", "3", "2", "4"),
    stringsAsFactors = FALSE
  )
  df$label_main <- unname(labs[df$code])
  df$label_sub <- paste0("Group ", df$grp)

  p <- ggplot2::ggplot(df, ggplot2::aes(pa, mob)) +
    ggplot2::geom_tile(ggplot2::aes(fill = code), color = "white", linewidth = 2.2,
                       width = 0.92, height = 0.92) +
    ggplot2::geom_text(ggplot2::aes(label = label_main), color = "white", fontface = "bold",
                       size = 4.0, nudge_y = 0.08) +
    ggplot2::geom_text(ggplot2::aes(label = label_sub), color = "grey95",
                       size = 3.2, nudge_y = -0.14) +
    ggplot2::scale_fill_manual(values = cols, guide = "none") +
    ggplot2::scale_x_discrete(position = "top", expand = ggplot2::expansion(add = 0.08)) +
    ggplot2::scale_y_discrete(expand = ggplot2::expansion(add = 0.08)) +
    ggplot2::labs(
      x = "Physical activity (MET-min/week)",
      y = "Mobility capacity",
      caption = "CHARLS: longitudinal cognition  |  NHANES: DSST + serum NfL (triangulation)"
    ) +
    pamob_theme_pub(12) +
    ggplot2::theme(
      axis.title = ggplot2::element_text(face = "bold", size = 12),
      axis.text = ggplot2::element_text(size = 11, face = "bold", color = "grey15"),
      axis.ticks = ggplot2::element_blank(),
      axis.line = ggplot2::element_blank(),
      plot.caption = ggplot2::element_text(hjust = 0.5, size = 9, color = "grey40",
                                          margin = ggplot2::margin(t = 10)),
      plot.margin = ggplot2::margin(12, 16, 10, 14),
      panel.background = ggplot2::element_rect(fill = "white", color = NA)
    ) +
    ggplot2::coord_fixed()
  pamob_ggsave_pub(pdf_path, p, width = 7.4, height = 5.4)
}

#' CONSORT 风格纳排（文献级；CHARLS Fig2 / NHANES Fig S1 共用）
pamob_draw_flowchart_pub <- function(steps, pdf_path, lab_map, excl_lab,
                                     width = 7.8, height = NULL) {
  pamob_ensure_packages("ggplot2")
  stopifnot(is.data.frame(steps), all(c("step", "n") %in% names(steps)))
  if (!"excluded_vs_prev" %in% names(steps)) steps$excluded_vs_prev <- NA_integer_
  n <- nrow(steps)
  # 步数增多时拉高画布、收紧间距，避免末框被裁切
  if (is.null(height) || !is.finite(height)) {
    height <- if (n >= 5L) 8.2 else 6.4
  }
  y_top <- 0.92
  y_bot <- 0.10
  y <- if (n <= 1L) y_top else seq(from = y_top, to = y_bot + 0.08, length.out = n)
  box_h <- if (n >= 5L) 0.095 else 0.112
  step_lab <- ifelse(steps$step %in% names(lab_map),
                     unname(lab_map[as.character(steps$step)]),
                     as.character(steps$step))
  boxes <- data.frame(
    x = 0.38, y = y, n = steps$n,
    label = sprintf("%s\nn = %s", step_lab, format(as.integer(steps$n), big.mark = ",")),
    stringsAsFactors = FALSE
  )
  excl <- list()
  for (i in seq_len(n)) {
    if (i == 1L) next
    prev_n <- as.integer(steps$n[i - 1L])
    cur_n <- as.integer(steps$n[i])
    ex <- if (!is.na(steps$excluded_vs_prev[i])) as.integer(steps$excluded_vs_prev[i]) else prev_n - cur_n
    elab <- if (length(excl_lab) >= i && !is.na(excl_lab[i])) excl_lab[i] else "Excluded"
    if (!is.na(ex) && ex > 0) {
      excl[[length(excl) + 1L]] <- data.frame(
        x = 0.78, y = mean(c(y[i - 1L], y[i])),
        label = sprintf("%s\nn = %s", elab, format(ex, big.mark = ",")),
        stringsAsFactors = FALSE
      )
    }
  }
  excl_df <- if (length(excl)) do.call(rbind, excl) else NULL
  seg_main <- data.frame(x = 0.38, xend = 0.38, y = y[-n] - box_h / 2, yend = y[-1] + box_h / 2)

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = seg_main, ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
      arrow = ggplot2::arrow(length = grid::unit(0.16, "cm"), type = "closed"),
      linewidth = 0.65, color = "#334155"
    )
  if (!is.null(excl_df) && nrow(excl_df)) {
    p <- p +
      ggplot2::geom_segment(
        data = data.frame(x = 0.38, xend = 0.64, y = excl_df$y, yend = excl_df$y),
        ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
        linewidth = 0.55, color = "#64748B"
      ) +
      ggplot2::geom_tile(
        data = excl_df, ggplot2::aes(x, y), width = 0.30, height = 0.100,
        fill = "#FFF7ED", color = "#C2410C", linewidth = 0.70
      ) +
      ggplot2::geom_text(
        data = excl_df, ggplot2::aes(x, y, label = label),
        size = 2.85, lineheight = 0.96, color = "#431407"
      )
  }
  p <- p +
    ggplot2::geom_tile(
      data = boxes, ggplot2::aes(x, y), width = 0.48, height = box_h,
      fill = "#EFF6FF", color = "#1D4ED8", linewidth = 0.85
    ) +
    ggplot2::geom_text(
      data = boxes, ggplot2::aes(x, y, label = label),
      size = 3.25, lineheight = 0.98, color = "#0F172A", fontface = "plain"
    ) +
    ggplot2::coord_cartesian(xlim = c(0.06, 0.98), ylim = c(0.10, 1.0), expand = FALSE) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.margin = ggplot2::margin(12, 12, 12, 12),
                   plot.background = ggplot2::element_rect(fill = "white", color = NA))
  pamob_ggsave_pub(pdf_path, p, width = width, height = height)
  invisible(pdf_path)
}

#' Figure 2：CHARLS CONSORT 纳排
#'
#' 主轴：person–waves → baseline IDs → LMM(=Table1)。
#' ≥2-wave 仅作 **LMM 侧支敏感性子集**，禁止画成 5698→6311 的下行箭头。
pamob_draw_fig2_flowchart <- function(steps, pdf_path) {
  pamob_ensure_packages("ggplot2")
  stopifnot(is.data.frame(steps), all(c("step", "n") %in% names(steps)))
  ge <- "\u2265"
  .n_of <- function(pat) {
    i <- grep(pat, as.character(steps$step), ignore.case = TRUE)
    if (!length(i)) return(NA_integer_)
    as.integer(steps$n[i[[1L]]])
  }
  n_pw <- .n_of("person_waves|D05_all")
  n_base <- .n_of("Baseline_phenotype")
  n_lmm <- .n_of("Analytic_IDs_with_cognition")
  n_ge2 <- .n_of("ge2_cognition")
  n_t1 <- .n_of("Table1_baseline|same_as_LMM")
  if (is.na(n_t1) && !is.na(n_lmm)) n_t1 <- n_lmm
  if (anyNA(c(n_pw, n_base, n_lmm, n_t1))) {
    # 回退旧通用绘制（兼容缺列）
    lab_map <- c(
      "1_CHARLS_D05_all_waves_person_waves" =
        "CHARLS person\u2013waves with\nPA\u2013mobility phenotype (all waves)",
      "2_Baseline_phenotype_unique_IDs" =
        "Baseline (2011) unique IDs\nwith phenotype",
      "3_Analytic_IDs_with_cognition" =
        "LMM analytic IDs\n(with cognition)",
      "3_Analytic_IDs_with_cognition_LMM" =
        "LMM analytic unique IDs\n(with cognition)",
      "4_IDs_with_ge2_cognition_waves" =
        paste0("IDs with ", ge, "2 cognition waves\n(sensitivity subset)"),
      "5_Table1_baseline_same_as_LMM_IDs" =
        "Table 1 baseline sample\n(= LMM unique IDs)"
    )
    main <- steps[!grepl("ge2_cognition", as.character(steps$step), ignore.case = TRUE), , drop = FALSE]
    excl_lab <- c(NA, "Collapse to unique\nbaseline IDs",
                  "No eligible cognition\nin follow-up window", NA)
    if (nrow(main) < length(excl_lab)) excl_lab <- excl_lab[seq_len(nrow(main))]
    return(pamob_draw_flowchart_pub(main, pdf_path, lab_map, excl_lab))
  }

  fmt <- function(x) format(as.integer(x), big.mark = ",")
  # 主轴 4 框：末框 Table1 与 LMM 同 N（非从 ≥2-wave 再筛）
  main_lab <- c(
    "CHARLS person\u2013waves with\nPA\u2013mobility phenotype (all waves)",
    "Baseline (2011) unique IDs\nwith phenotype",
    "LMM analytic unique IDs\n(with cognition)",
    "Table 1 baseline sample\n(= LMM unique IDs; not filtered from \u22652-wave)"
  )
  main_n <- c(n_pw, n_base, n_lmm, n_t1)
  y <- c(0.90, 0.68, 0.46, 0.22)
  box_h <- 0.105
  boxes <- data.frame(
    x = 0.36, y = y,
    label = sprintf("%s\nn = %s", main_lab, fmt(main_n)),
    stringsAsFactors = FALSE
  )
  excl_n <- c(n_pw - n_base, n_base - n_lmm)
  excl_lab <- c("Collapse to unique\nbaseline IDs", "No eligible cognition\nin follow-up window")
  excl_df <- data.frame(
    x = 0.78, y = c(mean(y[1:2]), mean(y[2:3])),
    label = sprintf("%s\nn = %s", excl_lab, fmt(excl_n)),
    stringsAsFactors = FALSE
  )
  seg_main <- data.frame(
    x = 0.36, xend = 0.36,
    y = y[-4] - box_h / 2, yend = y[-1] + box_h / 2
  )
  # 侧支：从 LMM 框水平引出 ≥2-wave 敏感性（不进入 Table1 主轴）
  n_one <- if (!is.na(n_ge2)) as.integer(n_lmm - n_ge2) else NA_integer_
  side_y <- y[3]
  side_boxes <- NULL
  seg_side <- NULL
  if (!is.na(n_ge2) && is.finite(n_ge2)) {
    side_boxes <- data.frame(
      x = 0.78, y = side_y - 0.14,
      label = sprintf(
        "IDs with %s2 cognition waves\n(sensitivity subset; not Table 1)\nn = %s",
        ge, fmt(n_ge2)
      ),
      stringsAsFactors = FALSE
    )
    if (!is.na(n_one) && n_one > 0L) {
      excl_df <- rbind(
        excl_df,
        data.frame(
          x = 0.78, y = side_y + 0.02,
          label = sprintf("Only one cognition wave\n(excluded from sensitivity)\nn = %s", fmt(n_one)),
          stringsAsFactors = FALSE
        )
      )
    }
    seg_side <- data.frame(
      x = 0.36 + 0.24, xend = 0.78 - 0.15,
      y = side_y, yend = side_y
    )
  }

  p <- ggplot2::ggplot() +
    ggplot2::geom_segment(
      data = seg_main, ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
      arrow = ggplot2::arrow(length = grid::unit(0.16, "cm"), type = "closed"),
      linewidth = 0.65, color = "#334155"
    )
  if (!is.null(seg_side)) {
    p <- p + ggplot2::geom_segment(
      data = seg_side, ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
      linewidth = 0.55, color = "#64748B",
      arrow = ggplot2::arrow(length = grid::unit(0.12, "cm"), type = "closed")
    )
  }
  p <- p +
    ggplot2::geom_segment(
      data = data.frame(x = 0.36, xend = 0.63, y = excl_df$y[1:2], yend = excl_df$y[1:2]),
      ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
      linewidth = 0.55, color = "#64748B"
    ) +
    ggplot2::geom_tile(
      data = excl_df, ggplot2::aes(x, y), width = 0.30, height = 0.100,
      fill = "#FFF7ED", color = "#C2410C", linewidth = 0.70
    ) +
    ggplot2::geom_text(
      data = excl_df, ggplot2::aes(x, y, label = label),
      size = 2.7, lineheight = 0.95, color = "#431407"
    ) +
    ggplot2::geom_tile(
      data = boxes, ggplot2::aes(x, y), width = 0.48, height = box_h,
      fill = "#EFF6FF", color = "#1D4ED8", linewidth = 0.85
    ) +
    ggplot2::geom_text(
      data = boxes, ggplot2::aes(x, y, label = label),
      size = 3.05, lineheight = 0.96, color = "#0F172A"
    )
  if (!is.null(side_boxes)) {
    p <- p +
      ggplot2::geom_tile(
        data = side_boxes, ggplot2::aes(x, y), width = 0.30, height = 0.115,
        fill = "#F0FDF4", color = "#15803D", linewidth = 0.75
      ) +
      ggplot2::geom_text(
        data = side_boxes, ggplot2::aes(x, y, label = label),
        size = 2.55, lineheight = 0.94, color = "#14532D"
      )
  }
  p <- p +
    ggplot2::coord_cartesian(xlim = c(0.05, 0.98), ylim = c(0.06, 1.0), expand = FALSE) +
    ggplot2::theme_void() +
    ggplot2::theme(plot.margin = ggplot2::margin(12, 12, 12, 12),
                   plot.background = ggplot2::element_rect(fill = "white", color = NA))
  pamob_ggsave_pub(pdf_path, p, width = 8.0, height = 8.4)
  invisible(pdf_path)
}

#' Figure S1：NHANES CONSORT 纳排
pamob_draw_figs1_nhanes_flowchart <- function(steps, pdf_path) {
  lab_map <- c(
    "1_cycle_H_PA_mobility_merged" =
      "NHANES 2013\u20132014 (Cycle H)\nPA\u2013mobility phenotype merged",
    "2_age_60_75" =
      "Age 60\u201375 years",
    "3_DSST_available" =
      "DSST available\n(cognitive performance)",
    "4_NfL_weighted_analytic" =
      "Serum NfL analytic sample\n(WTSSNH2Y survey weights)"
  )
  excl_lab <- c(NA,
                "Age <60 or >75 years",
                "Missing DSST",
                "Missing NfL or\nineligible for weighted NfL")
  pamob_draw_flowchart_pub(steps, pdf_path, lab_map, excl_lab,
                           width = 7.8, height = 6.4)
}

#' Figure 3：校正后认知轨迹（单面板，兼容旧调用）
pamob_draw_fig3_traj <- function(grid, pdf_path) {
  pamob_draw_fig3_traj_dual(grid, pdf_path)
}

#' Figure 3：Global + Episodic 双面板（含 95% CI ribbon）
pamob_draw_fig3_traj_dual <- function(grid, pdf_path) {
  pamob_ensure_packages(c("ggplot2", "patchwork"))
  cols <- pamob_pheno_colors()
  labs <- pamob_pheno_labels_pretty()
  ltys <- c(Active_preserved = "solid", Inactive_preserved = "dashed",
            Active_limited = "dotdash", Inactive_limited = "longdash")
  df <- as.data.frame(grid)
  df$phenotype <- factor(as.character(df$phenotype), levels = names(labs))
  if (!"outcome" %in% names(df)) df$outcome <- "Global_cognition"
  if (!"lo" %in% names(df) && all(c("pred", "se") %in% names(df))) {
    df$lo <- df$pred - 1.96 * df$se
    df$hi <- df$pred + 1.96 * df$se
  }
  has_ci <- all(c("lo", "hi", "pred") %in% names(df)) && any(is.finite(df$lo))

  .panel <- function(d, ylab, tag, show_legend = FALSE) {
    p <- ggplot2::ggplot(
      d, ggplot2::aes(Time_years, pred, color = phenotype, linetype = phenotype, group = phenotype)
    )
    if (has_ci) {
      p <- p + ggplot2::geom_ribbon(
        ggplot2::aes(ymin = lo, ymax = hi, fill = phenotype),
        alpha = 0.14, color = NA, linetype = 0, show.legend = FALSE
      )
    }
    p <- p +
      ggplot2::geom_line(linewidth = 1.05) +
      ggplot2::geom_point(size = 2.1, stroke = 0.2) +
      ggplot2::scale_color_manual(values = cols, labels = labs, name = "Phenotype") +
      ggplot2::scale_fill_manual(values = cols, guide = "none") +
      ggplot2::scale_linetype_manual(values = ltys, labels = labs, name = "Phenotype") +
      ggplot2::scale_x_continuous(breaks = sort(unique(as.numeric(d$Time_years))),
                                  expand = ggplot2::expansion(mult = c(0.02, 0.04))) +
      ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0.04, 0.06))) +
      ggplot2::labs(x = "Years since baseline", y = ylab, tag = tag) +
      pamob_theme_pub(11) +
      ggplot2::theme(
        legend.position = if (isTRUE(show_legend)) "bottom" else "none",
        legend.box = "horizontal",
        legend.box.just = "center",
        legend.key.width = grid::unit(0.95, "cm"),
        legend.key.height = grid::unit(0.32, "cm"),
        legend.text = ggplot2::element_text(size = 9),
        legend.title = ggplot2::element_text(size = 9.5, face = "bold"),
        legend.margin = ggplot2::margin(2, 4, 2, 4),
        plot.margin = ggplot2::margin(6, 10, 6, 8),
        axis.title = ggplot2::element_text(face = "bold", size = 11),
        axis.text = ggplot2::element_text(size = 10),
        plot.tag = ggplot2::element_text(face = "bold", size = 14),
        plot.tag.position = c(0.01, 0.99)
      )
    if (isTRUE(show_legend)) {
      p <- p + ggplot2::guides(
        color = ggplot2::guide_legend(nrow = 2, byrow = TRUE, title = "Phenotype"),
        linetype = ggplot2::guide_legend(nrow = 2, byrow = TRUE, title = "Phenotype")
      )
    } else {
      p <- p + ggplot2::guides(color = "none", linetype = "none")
    }
    p
  }

  d_g <- df[df$outcome %in% c("Global_cognition", "global", "Global"), , drop = FALSE]
  d_e <- df[df$outcome %in% c("Episodic_memory", "episodic", "Episodic"), , drop = FALSE]
  if (!nrow(d_g)) d_g <- df
  p_a <- .panel(d_g, "Predicted global cognition (0\u201321)", "A", show_legend = FALSE)
  if (nrow(d_e)) {
    p_b <- .panel(d_e, "Predicted episodic memory", "B", show_legend = TRUE)
    # 加宽画布 + 双行图例，避免 phenotype 标签超出 PDF 右边界（nature collision P0）
    p <- (p_a / p_b) + patchwork::plot_layout(heights = c(1, 1.12), guides = "keep")
    pamob_ggsave_pub(pdf_path, p, width = 8.4, height = 9.0)
  } else {
    pamob_ggsave_pub(pdf_path, .panel(d_g, "Predicted global cognition (0\u201321)", "A", show_legend = TRUE),
                     width = 8.0, height = 5.4)
  }
}

#' Figure 4：DSST + sNfL 双面板（文献级，含 SE + CLD 组间字母）
pamob_draw_fig4_panel <- function(plot_df, pdf_path) {
  pamob_ensure_packages(c("ggplot2", "patchwork"))
  cols <- pamob_pheno_colors()
  labs <- pamob_pheno_labels_pretty()
  df <- as.data.frame(plot_df)
  df$phenotype <- factor(as.character(df$phenotype), levels = names(labs))
  df$pheno_lab <- factor(unname(labs[as.character(df$phenotype)]), levels = unname(labs))
  has_se <- "se" %in% names(df) && any(is.finite(df$se))
  has_cld <- "cld" %in% names(df) && any(nzchar(as.character(df$cld)), na.rm = TRUE)

  .one <- function(d, ylab, tag) {
    top <- d$mean + if (has_se) d$se else 0
    ymax <- max(top, na.rm = TRUE) * if (has_cld) 1.18 else 1.12
    gg <- ggplot2::ggplot(d, ggplot2::aes(pheno_lab, mean, fill = phenotype)) +
      ggplot2::geom_col(width = 0.68, color = "grey20", linewidth = 0.30) +
      ggplot2::scale_fill_manual(values = cols, guide = "none") +
      ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = c(0, 0.02)),
                                  limits = c(0, ymax)) +
      ggplot2::labs(x = NULL, y = ylab, tag = tag) +
      pamob_theme_pub(11) +
      ggplot2::theme(
        axis.text.x = ggplot2::element_text(angle = 28, hjust = 1, vjust = 1, size = 9.5),
        axis.title.y = ggplot2::element_text(face = "bold", size = 10.5),
        plot.tag = ggplot2::element_text(face = "bold", size = 14),
        plot.tag.position = c(0.01, 0.99),
        plot.margin = ggplot2::margin(8, 8, 4, 6)
      )
    if (has_se) {
      gg <- gg + ggplot2::geom_errorbar(
        ggplot2::aes(ymin = pmax(0, mean - se), ymax = mean + se),
        width = 0.18, linewidth = 0.50, color = "#1F2937"
      )
    }
    if (has_cld) {
      d$lab_y <- top * 1.04
      gg <- gg + ggplot2::geom_text(
        data = d,
        ggplot2::aes(x = pheno_lab, y = lab_y, label = cld),
        inherit.aes = FALSE, size = 4.2, fontface = "bold", color = "#111827",
        vjust = 0
      )
    }
    gg
  }

  d1 <- df[grepl("^DSST$|A\\.\\s*DSST", df$panel), , drop = FALSE]
  if (!nrow(d1)) d1 <- df[df$panel == "DSST", , drop = FALSE]
  d2 <- df[grepl("NfL|nfl", df$panel, ignore.case = TRUE), , drop = FALSE]
  if (!nrow(d1) || !nrow(d2)) {
    p <- ggplot2::ggplot(df, ggplot2::aes(pheno_lab, mean, fill = phenotype)) +
      ggplot2::geom_col(width = 0.68, color = "grey20", linewidth = 0.25) +
      ggplot2::facet_wrap(~panel, scales = "free_y") +
      ggplot2::scale_fill_manual(values = cols, guide = "none") +
      pamob_theme_pub(11) +
      ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 28, hjust = 1))
    pamob_ggsave_pub(pdf_path, p, width = 9.0, height = 4.4)
    return(invisible(pdf_path))
  }
  p <- .one(d1, "Model 3\u2013adjusted mean DSST", "A") |
    .one(d2, "Model 3\u2013adjusted geometric mean sNfL (pg/mL)", "B")
  pamob_ggsave_pub(pdf_path, p, width = 9.2, height = 4.8)
  # CLD note for image_information / Methods (avoid patchwork caption theme quirks)
  note_path <- sub("\\.pdf$", "_CLD_note.txt", pdf_path)
  writeLines(c(
    "Figure 4 letters: compact letter display (CLD).",
    "Wald pairwise contrasts on Model 3-adjusted means; alpha=0.05.",
    "Groups sharing a letter are not significantly different."
  ), note_path)
}

# ── 发表三线表格式化 ──────────────────────────────────────────────

pamob_var_label_map <- function() {
  c(
    Age = "Age, years",
    Age_anal = "Age, years",
    BMI = "BMI, kg/m\u00b2",
    Incometotal = "Household income",
    CESD10 = "CES-D-10",
    Depression = "PHQ-9",
    Global_cognition = "Global cognition (0\u201321)",
    Episodic_memory = "Episodic memory",
    CFDDS = "DSST",
    SSSNFL = "Serum NfL, pg/mL",
    eGFR = "eGFR, mL/min/1.73 m\u00b2",
    CRP = "CRP, mg/dL",
    PIR = "Poverty\u2013income ratio, n (%)",
    Gender = "Sex, n (%)",
    Education = "Education, n (%)",
    Marital_Status = "Marital status, n (%)",
    Residence = "Residence, n (%)",
    Smoke = "Smoking, n (%)",
    Alcohol_drinking = "Alcohol drinking, n (%)",
    Hypertension = "Hypertension, n (%)",
    Diabetes = "Diabetes, n (%)",
    CHD = "Coronary heart disease, n (%)",
    HF = "Heart failure, n (%)",
    Cardiopathy = "Heart disease, n (%)",
    Stroke = "Stroke, n (%)",
    Race = "Race/ethnicity, n (%)"
  )
}

pamob_pretty_term <- function(term) {
  labs <- pamob_pheno_labels_pretty()
  t <- as.character(term)
  t <- gsub("^phenotype", "", t)
  t <- gsub("^Time_years:phenotype", "Time \u00d7 ", t)
  t <- gsub("^Time_years$", "Time (years)", t)
  t <- gsub("^\\(Intercept\\)$", "Intercept", t)
  for (nm in names(labs)) {
    t <- gsub(nm, labs[[nm]], t, fixed = TRUE)
  }
  t <- gsub("_", " ", t)
  t <- gsub("GenderMale", "Sex: Male", t)
  t <- gsub("GenderFemale", "Sex: Female", t)
  t
}

#' long baseline CSV → 经典 Table1 体（Characteristics + 四组；连续合一行；分类缩进）
pamob_format_baseline_pub <- function(raw, drop_vars = character(0),
                                      drop_missing_level = TRUE) {
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)
  pheno_cols <- intersect(unname(pamob_phenotype_labels()), names(raw))
  if (!length(pheno_cols)) {
    pheno_cols <- setdiff(names(raw), c("variable", "level"))
  }
  labs <- pamob_pheno_labels_pretty()
  n_row <- raw[raw$variable == "N", , drop = FALSE]
  ns <- if (nrow(n_row)) {
    setNames(as.integer(unlist(n_row[1L, pheno_cols])), pheno_cols)
  } else {
    setNames(rep(NA_integer_, length(pheno_cols)), pheno_cols)
  }
  hdr <- vapply(pheno_cols, function(p) {
    pretty <- unname(labs[p] %||% p)
    n <- ns[[p]]
    if (is.finite(n)) sprintf("%s\n(n = %s)", pretty, format(n, big.mark = ","))
    else pretty
  }, character(1))

  vmap <- pamob_var_label_map()
  skip <- c("N", drop_vars)
  out_rows <- list()
  vars <- unique(raw$variable)
  vars <- vars[!vars %in% skip]
  for (v in vars) {
    sub <- raw[raw$variable == v, , drop = FALSE]
    if (!nrow(sub)) next
    if (nrow(sub) == 1L && grepl("Mean", sub$level[1L], ignore.case = TRUE)) {
      lab <- unname(vmap[v] %||% v)
      if (grepl("SE", sub$level[1L], ignore.case = TRUE) && !grepl("SE|\\)", lab)) {
        # keep label; footnote explains SE
      }
      row <- c(list(Characteristics = lab),
               as.list(setNames(as.character(unlist(sub[1L, pheno_cols])), hdr)))
      out_rows[[length(out_rows) + 1L]] <- as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
      next
    }
    # categorical: recompute n (%) among non-missing within each phenotype column
    miss <- sub[grepl("^\\(Missing\\)$", sub$level, ignore.case = TRUE), , drop = FALSE]
    lev <- sub[!grepl("^\\(Missing\\)$", sub$level, ignore.case = TRUE), , drop = FALSE]
    lev <- lev[!grepl("Mean", lev$level, ignore.case = TRUE), , drop = FALSE]
    if (!nrow(lev)) next
    if (isTRUE(drop_missing_level) && nrow(miss)) {
      for (pc in pheno_cols) {
        N <- ns[[pc]]
        miss_n <- suppressWarnings(as.integer(sub("^([0-9]+).*", "\\1", as.character(miss[1L, pc]))))
        denom <- if (is.finite(N) && is.finite(miss_n)) max(N - miss_n, 0L) else NA_integer_
        for (i in seq_len(nrow(lev))) {
          k <- suppressWarnings(as.integer(sub("^([0-9]+).*", "\\1", as.character(lev[i, pc]))))
          if (is.finite(k) && is.finite(denom) && denom > 0) {
            lev[i, pc] <- sprintf("%d (%.1f)", k, 100 * k / denom)
          }
        }
      }
    }
    lab <- unname(vmap[v] %||% paste0(v, ", n (%)"))
    blank <- as.list(setNames(rep("", length(hdr)), hdr))
    out_rows[[length(out_rows) + 1L]] <- as.data.frame(
      c(list(Characteristics = lab), blank), stringsAsFactors = FALSE, check.names = FALSE
    )
    for (i in seq_len(nrow(lev))) {
      lv <- as.character(lev$level[i])
      if (!nzchar(lv)) next
      row <- c(list(Characteristics = paste0("  ", lv)),
               as.list(setNames(as.character(unlist(lev[i, pheno_cols])), hdr)))
      out_rows[[length(out_rows) + 1L]] <- as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
    }
  }
  if (!length(out_rows)) return(data.frame(Characteristics = character(0)))
  # unify colnames
  do.call(rbind, lapply(out_rows, function(d) {
    miss <- setdiff(c("Characteristics", hdr), names(d))
    for (m in miss) d[[m]] <- ""
    d[c("Characteristics", hdr)]
  }))
}

#' 回归系数 long → Model | Term | β (SE) | P
pamob_format_coef_pub <- function(raw, keep_models = NULL, keep_term_regex = NULL,
                                  outcome_col = NULL) {
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)
  if (!is.null(keep_models)) raw <- raw[raw$model %in% keep_models, , drop = FALSE]
  if (!is.null(keep_term_regex) && nzchar(keep_term_regex)) {
    raw <- raw[grepl(keep_term_regex, raw$term), , drop = FALSE]
  }
  if (!nrow(raw)) {
    return(data.frame(Model = character(0), Term = character(0),
                      `β (SE)` = character(0), P = character(0),
                      check.names = FALSE, stringsAsFactors = FALSE))
  }
  est <- if (exists("pub_format_est", mode = "function")) {
    pub_format_est(raw$estimate)
  } else {
    sprintf("%.3f", raw$estimate)
  }
  se <- if (exists("pub_format_est", mode = "function")) {
    pub_format_est(raw$std.error)
  } else {
    sprintf("%.3f", raw$std.error)
  }
  p <- if (exists("pub_format_p", mode = "function")) {
    pub_format_p(raw$p.value)
  } else {
    ifelse(raw$p.value < 0.001, "<0.001", sprintf("%.3f", raw$p.value))
  }
  model_lab <- gsub("^Model0_time_pheno$", "Unadjusted", raw$model)
  model_lab <- gsub("^Model0$", "Unadjusted", model_lab)
  model_lab <- gsub("^Model([0-9]+)$", "Model \\1", model_lab)
  out <- data.frame(
    Model = model_lab,
    Term = pamob_pretty_term(raw$term),
    `β (SE)` = sprintf("%s (%s)", est, se),
    P = p,
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  if (!is.null(outcome_col) && outcome_col %in% names(raw)) {
    out <- cbind(Outcome = as.character(raw[[outcome_col]]), out, stringsAsFactors = FALSE)
  }
  if ("analysis" %in% names(raw)) {
    out <- cbind(Analysis = as.character(raw$analysis), out, stringsAsFactors = FALSE)
  }
  out
}

pamob_write_sci_xlsx <- function(df, path, title, footnotes = NULL) {
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    stop("请先 source R/utils.R", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  sci_xlsx_single_header_booktabs(
    filepath = path,
    title = title,
    df_body = df,
    footnotes = footnotes
  )
  invisible(path)
}

# ── 缺口补齐辅助 ──────────────────────────────────────────────

#' 丢掉只有 1 个水平 / 全缺失的协变量（避免 svyglm 因子报错）
pamob_drop_degenerate_covars <- function(df, covars) {
  covars <- intersect(as.character(covars %||% character(0)), names(df))
  keep <- character(0)
  for (v in covars) {
    x <- df[[v]]
    x <- x[!is.na(x)]
    if (!length(x)) next
    if (is.factor(x) || is.character(x)) {
      if (length(unique(as.character(x))) < 2L) next
    } else if (is.numeric(x)) {
      if (stats::sd(as.numeric(x), na.rm = TRUE) == 0 || all(!is.finite(as.numeric(x)))) next
    }
    keep <- c(keep, v)
  }
  keep
}

#' Survey-weighted 基线：连续 mean(SE)；分类 % (SE) —— 输出与 unweighted long 同结构
pamob_baseline_by_phenotype_weighted <- function(df, wt_col = "WTSSNH2Y",
                                                  continuous = character(0),
                                                  categorical = character(0),
                                                  digits_cont = 2L, digits_pct = 1L) {
  pamob_ensure_packages("survey")
  # 分表型子集易 lonely PSU；用全样本 design + svyby，并允许 lonely.psu adjust
  old_lpsu <- getOption("survey.lonely.psu")
  on.exit(options(survey.lonely.psu = old_lpsu), add = TRUE)
  options(survey.lonely.psu = "adjust")

  df <- as.data.frame(df)
  stopifnot(wt_col %in% names(df), "phenotype" %in% names(df))
  df <- df[!is.na(df$phenotype) & !is.na(df[[wt_col]]) & df[[wt_col]] > 0, , drop = FALSE]
  df$phenotype <- factor(as.character(df$phenotype), levels = unname(pamob_phenotype_labels()))
  levs <- levels(df$phenotype)
  continuous <- intersect(continuous, names(df))
  categorical <- intersect(categorical, names(df))
  if (all(c("SDMVPSU", "SDMVSTRA") %in% names(df)) && !any(is.na(df$SDMVPSU))) {
    des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                             weights = stats::as.formula(paste0("~", wt_col)),
                             nest = TRUE, data = df)
  } else {
    des <- survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", wt_col)), data = df)
  }
  rows <- list()
  ntab <- table(df$phenotype, useNA = "no")
  rows[[length(rows) + 1L]] <- data.frame(
    variable = "N", level = "",
    setNames(as.list(as.integer(ntab[levs])), levs),
    stringsAsFactors = FALSE
  )
  .fmt_by <- function(by_tab, value_col) {
    if (is.null(by_tab) || !value_col %in% names(by_tab)) {
      return(setNames(rep("", length(levs)), levs))
    }
    vals <- vapply(levs, function(L) {
      i <- which(as.character(by_tab$phenotype) == L)
      if (!length(i)) return("")
      mu <- as.numeric(by_tab[[value_col]][i[1L]])
      se <- as.numeric(by_tab[["se"]][i[1L]])
      if (length(mu) != 1L || !is.finite(mu)) return("")
      if (length(se) != 1L || !is.finite(se)) se <- 0
      sprintf(paste0("%.", digits_cont, "f (%.", digits_cont, "f)"), mu, se)
    }, character(1))
    setNames(vals, levs)
  }
  for (v in continuous) {
    # skip vars with <2 non-missing overall
    if (sum(!is.na(df[[v]])) < 2L) {
      vals <- setNames(rep("", length(levs)), levs)
    } else {
      by_tab <- tryCatch(
        survey::svyby(stats::as.formula(paste0("~", v)), ~phenotype, des,
                      survey::svymean, na.rm = TRUE),
        error = function(e) NULL
      )
      vals <- .fmt_by(by_tab, v)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      variable = v, level = "Mean (SE)",
      as.list(vals), stringsAsFactors = FALSE, check.names = FALSE
    )
  }
  for (v in categorical) {
    x <- as.character(df[[v]])
    x[is.na(x) | !nzchar(x)] <- "(Missing)"
    ul <- sort(unique(x[x != "(Missing)"]))
    for (lv in ul) {
      df$._bin <- as.integer(x == lv)
      if (all(c("SDMVPSU", "SDMVSTRA") %in% names(df)) && !any(is.na(df$SDMVPSU))) {
        des_b <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                                   weights = stats::as.formula(paste0("~", wt_col)),
                                   nest = TRUE, data = df)
      } else {
        des_b <- survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", wt_col)),
                                   data = df)
      }
      by_tab <- tryCatch(
        survey::svyby(~`._bin`, ~phenotype, des_b, survey::svymean, na.rm = TRUE),
        error = function(e) NULL
      )
      if (is.null(by_tab)) {
        vals <- setNames(rep("", length(levs)), levs)
      } else {
        vals <- vapply(levs, function(L) {
          i <- which(as.character(by_tab$phenotype) == L)
          if (!length(i)) return("")
          pct <- 100 * as.numeric(by_tab[["._bin"]][i[1L]])
          se <- 100 * as.numeric(by_tab[["se"]][i[1L]])
          if (!is.finite(pct)) return("")
          if (!is.finite(se)) se <- 0
          sprintf(paste0("%.", digits_pct, "f (%.", digits_pct, "f)"), pct, se)
        }, character(1))
        vals <- setNames(vals, levs)
      }
      rows[[length(rows) + 1L]] <- data.frame(
        variable = v, level = lv,
        as.list(vals), stringsAsFactors = FALSE, check.names = FALSE
      )
    }
  }
  do.call(rbind, rows)
}

#' Compact letter display from pairwise p-matrix (rows/cols = group names)
pamob_compact_letters <- function(pmat, alpha = 0.05) {
  pmat <- as.matrix(pmat)
  levs <- rownames(pmat)
  if (is.null(levs)) levs <- colnames(pmat)
  stopifnot(length(levs) >= 1L)
  if (length(levs) == 1L) return(setNames("a", levs))
  comps <- numeric(0)
  nms <- character(0)
  for (i in seq_len(length(levs) - 1L)) {
    for (j in seq.int(i + 1L, length(levs))) {
      nms <- c(nms, paste(levs[i], levs[j], sep = "-"))
      comps <- c(comps, as.numeric(pmat[levs[i], levs[j]]))
    }
  }
  names(comps) <- nms
  comps[!is.finite(comps)] <- 1
  pamob_ensure_packages("multcompView")
  lett <- multcompView::multcompLetters(comps, threshold = alpha)$Letters
  # ensure all levels present; lowercase for figure style
  out <- setNames(tolower(unname(lett[levs])), levs)
  out[is.na(out) | !nzchar(out)] <- "?"
  out
}

#' Model3 校正后的 phenotype 边际预测均值（survey）；附两两比较 CLD 字母
pamob_svy_adjusted_means <- function(d, y, wt, covars, ref_levels = NULL,
                                     alpha = 0.05, add_cld = TRUE) {
  pamob_ensure_packages("survey")
  old_lpsu <- getOption("survey.lonely.psu")
  on.exit(options(survey.lonely.psu = old_lpsu), add = TRUE)
  options(survey.lonely.psu = "adjust")
  d <- as.data.frame(d)
  d <- d[!is.na(d[[y]]) & !is.na(d$phenotype) & !is.na(d[[wt]]) & d[[wt]] > 0, , drop = FALSE]
  d$phenotype <- stats::relevel(
    factor(d$phenotype, levels = unname(pamob_phenotype_labels())),
    ref = "Active_preserved"
  )
  covars <- pamob_drop_degenerate_covars(d, covars)
  for (v in covars) {
    if (is.character(d[[v]])) d[[v]] <- factor(d[[v]])
  }
  if (all(c("SDMVPSU", "SDMVSTRA") %in% names(d)) && !any(is.na(d$SDMVPSU))) {
    des <- survey::svydesign(ids = ~SDMVPSU, strata = ~SDMVSTRA,
                             weights = stats::as.formula(paste0("~", wt)),
                             nest = TRUE, data = d)
  } else {
    des <- survey::svydesign(ids = ~1, weights = stats::as.formula(paste0("~", wt)), data = d)
  }
  rhs <- pamob_fml_rhs(covars)
  fml <- stats::as.formula(paste(y, "~", rhs))
  fit <- survey::svyglm(fml, design = des)
  ref <- d[1L, , drop = FALSE]
  for (v in covars) {
    if (is.numeric(d[[v]])) {
      m <- survey::svymean(stats::as.formula(paste0("~", v)), des, na.rm = TRUE)
      ref[[v]] <- as.numeric(m[1L])
    } else {
      tab <- table(d[[v]])
      ref[[v]] <- names(tab)[which.max(tab)]
      if (is.factor(d[[v]])) ref[[v]] <- factor(ref[[v]], levels = levels(d[[v]]))
    }
  }
  levs <- unname(pamob_phenotype_labels())
  cf <- stats::coef(fit)
  V <- as.matrix(stats::vcov(fit))
  Xlist <- list()
  out <- lapply(levs, function(L) {
    nd <- ref
    nd$phenotype <- factor(L, levels = levels(d$phenotype))
    X <- stats::model.matrix(stats::delete.response(stats::terms(fit)), data = nd)
    miss <- setdiff(names(cf), colnames(X))
    if (length(miss)) {
      for (m in miss) X <- cbind(X, setNames(0, m))
    }
    X <- X[, names(cf), drop = FALSE]
    Xlist[[L]] <<- X
    est <- as.numeric(X %*% cf)
    se <- sqrt(as.numeric(X %*% V %*% t(X)))
    data.frame(phenotype = L, mean = est, se = se, stringsAsFactors = FALSE)
  })
  means <- do.call(rbind, out)
  if (isTRUE(add_cld) && length(levs) >= 2L) {
    pmat <- matrix(1, length(levs), length(levs), dimnames = list(levs, levs))
    for (i in seq_len(length(levs) - 1L)) {
      for (j in seq.int(i + 1L, length(levs))) {
        xd <- Xlist[[levs[i]]] - Xlist[[levs[j]]]
        diff <- as.numeric(xd %*% cf)
        se_d <- sqrt(as.numeric(xd %*% V %*% t(xd)))
        p <- if (is.finite(se_d) && se_d > 0) 2 * stats::pnorm(-abs(diff / se_d)) else 1
        pmat[levs[i], levs[j]] <- pmat[levs[j], levs[i]] <- p
      }
    }
    lett <- pamob_compact_letters(pmat, alpha = alpha)
    means$cld <- unname(lett[as.character(means$phenotype)])
    means$pmat_note <- sprintf("CLD letters: groups sharing a letter not different at alpha=%.2f (Wald)", alpha)
  } else {
    means$cld <- NA_character_
  }
  means
}
