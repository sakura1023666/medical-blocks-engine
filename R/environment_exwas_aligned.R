# 对齐 Dong 2026 的主顺序：合并权重与协变量 → 去掉重复营养列 →
# mice → 不加权 ExWAS + BH-FDR。
# 描述、ERS、RCS、亚组人数、中介用调查权重（2 年权重 / 7）。
# ExWAS 本身仍不加权。

exwas_aligned_dag_pool <- function() {
  c("Age", "Gender", "Race", "Education", "Marital_Status",
    "PIR", "BMI", "Smoke", "Alcohol_drinking")
}

exwas_aligned_dedup <- function(cols) {
  drop <- character(0)
  # 脂质校正列与原列重复
  la <- cols[grepl("LA$", cols)]
  drop <- c(drop, la[sub("LA$", "", la) %in% cols])
  # SI 与常规单位重复时留常规单位
  si <- cols[grepl("SI$", cols)]
  drop <- c(drop, si[sub("SI$", "", si) %in% cols])
  # 第 2 日与第 1 日同后缀时只留第 1 日（Zhang 2024 主分析用 day 1）
  dr2 <- cols[grepl("^DR2", cols)]
  dr1_as_dr2 <- sub("^DR2", "DR1", dr2)
  drop <- c(drop, dr2[dr1_as_dr2 %in% cols])
  # 食物项求和 DR1I* 与日总量 DR1T* 同后缀时留日总量
  dri <- cols[grepl("^DR1I", cols)]
  drt <- sub("^DR1I", "DR1T", dri)
  drop <- c(drop, dri[drt %in% cols])
  unique(setdiff(cols, drop))
}

exwas_aligned_family <- function(cols) {
  fam <- ifelse(grepl("^DR1", cols), "diet_day1",
         ifelse(grepl("^DR2", cols), "diet_day2",
         ifelse(grepl("^LBX|^LBD", cols), "biomarker", "other")))
  stats::setNames(fam, cols)
}

# Dong：先丢掉队列缺失率 >40%（或测定过少）的分析物，再对人做「缺失超过 1/3」剔除。
exwas_aligned_analyte_keep <- function(df, exposure_cols, max_missing = 0.40, min_n = 50L) {
  notes <- list()
  keep <- character(0)
  for (col in exposure_cols) {
    x <- exwas_to_num(df[[col]])
    n_measured <- sum(is.finite(x))
    miss <- 1 - n_measured / nrow(df)
    zero_rate <- if (n_measured == 0L) 1 else mean(x == 0, na.rm = TRUE)
    decision <- "keep"
    if (n_measured < min_n || miss > max_missing || zero_rate > 0.95) decision <- "drop"
    else keep <- c(keep, col)
    notes[[length(notes) + 1L]] <- data.frame(
      exposure = col, n_measured = n_measured, missing_rate = miss,
      zero_rate = zero_rate, decision = decision, stringsAsFactors = FALSE
    )
  }
  list(keep = keep, notes = if (length(notes)) do.call(rbind, notes) else NULL)
}

exwas_aligned_drop_person_missing <- function(df, exposure_cols, max_frac = 1 / 3) {
  if (!length(exposure_cols)) return(list(data = df, keep_idx = seq_len(nrow(df)), n_excluded = 0L))
  mm <- as.matrix(df[, exposure_cols, drop = FALSE])
  storage.mode(mm) <- "double"
  frac <- rowMeans(!is.finite(mm))
  keep_idx <- which(frac <= max_frac)
  list(
    data = df[keep_idx, , drop = FALSE],
    keep_idx = keep_idx,
    n_excluded = nrow(df) - length(keep_idx),
    missing_frac = frac
  )
}

exwas_aligned_as_model_frame <- function(df, cols) {
  for (nm in cols) {
    if (!nm %in% names(df)) next
    x <- df[[nm]]
    if (is.character(x) || is.factor(x)) {
      df[[nm]] <- factor(x)
    } else {
      df[[nm]] <- exwas_to_num(x)
    }
  }
  df
}

exwas_aligned_univariate <- function(df, y, vars, p_cut = 0.05) {
  rows <- lapply(vars, function(v) {
    dd <- df[stats::complete.cases(df[, c(y, v), drop = FALSE]), c(y, v), drop = FALSE]
    if (nrow(dd) < 40L || length(unique(dd[[y]])) < 2L) {
      return(data.frame(variable = v, n = nrow(dd), p = NA_real_, stringsAsFactors = FALSE))
    }
    fit <- tryCatch(stats::glm(stats::as.formula(paste(y, "~", v)), data = dd, family = stats::binomial()),
                    error = function(e) NULL)
    p <- if (is.null(fit)) NA_real_ else {
      cf <- summary(fit)$coefficients
      if (nrow(cf) < 2L) NA_real_ else suppressWarnings(min(cf[-1, 4], na.rm = TRUE))
    }
    data.frame(variable = v, n = nrow(dd), p = p, stringsAsFactors = FALSE)
  })
  tab <- do.call(rbind, rows)
  keep <- tab$variable[is.finite(tab$p) & tab$p < p_cut]
  if (!"Age" %in% keep && "Age" %in% vars) keep <- c("Age", keep)
  list(table = tab, keep = unique(keep))
}

exwas_aligned_vif_screen <- function(df, y, vars, thr = 4) {
  vars <- unique(vars)
  log_drop <- data.frame(variable = character(0), vif = numeric(0), stringsAsFactors = FALSE)
  if (length(vars) < 2L) return(list(keep = vars, dropped = log_drop))
  repeat {
    dd <- df[stats::complete.cases(df[, c(y, vars), drop = FALSE]), c(y, vars), drop = FALSE]
    mm <- tryCatch(stats::model.matrix(stats::as.formula(paste("~", paste(vars, collapse = "+"))), data = dd),
                   error = function(e) NULL)
    if (is.null(mm) || ncol(mm) < 3L) break
    vif_num <- numeric(length(vars))
    names(vif_num) <- vars
    for (v in vars) {
      cols_v <- grep(paste0("^", v), colnames(mm))
      others <- setdiff(seq_len(ncol(mm)), c(1L, cols_v))
      if (!length(cols_v) || !length(others)) next
      r2 <- tryCatch(summary(stats::lm(mm[, cols_v[1]] ~ mm[, others]))$r.squared, error = function(e) NA_real_)
      vif_num[v] <- if (is.finite(r2) && r2 < 1) 1 / (1 - r2) else Inf
    }
    if (!length(vif_num) || max(vif_num, na.rm = TRUE) < thr) break
    worst <- names(which.max(vif_num))
    if (identical(worst, "Age") && length(vars) > 1L) {
      alt <- setdiff(names(vif_num), "Age")
      worst <- alt[which.max(vif_num[alt])]
    }
    log_drop <- rbind(log_drop, data.frame(variable = worst, vif = unname(vif_num[worst])))
    vars <- setdiff(vars, worst)
    if (length(vars) < 2L) break
  }
  list(keep = vars, dropped = log_drop)
}

exwas_aligned_evalue_or <- function(or, lo) {
  ev <- function(x) {
    if (!is.finite(x) || x <= 0) return(NA_real_)
    if (x < 1) x <- 1 / x
    x + sqrt(x * (x - 1))
  }
  c(evalue = ev(or), evalue_ci = ev(lo))
}

exwas_aligned_load <- function(nutrition_csv, baseline_rdata) {
  nut <- exwas_read_csv(nutrition_csv)
  names(nut) <- sub("^\ufeff", "", names(nut))
  e <- new.env()
  load(baseline_rdata, envir = e)
  b <- e$baseline
  b$cycle <- as.character(b$Source_File)
  b$SEQN <- as.character(b$ID)
  nut$SEQN <- as.character(nut$SEQN)
  nut$cycle <- as.character(nut$cycle)
  keep_b <- c(
    "cycle", "SEQN", "Age", "Gender", "Race", "Education", "Marital_Status",
    "PIR", "BMI", "Smoke", "Alcohol_drinking",
    "WBC", "NeutrophilCount", "Lymphocytes", "Mononuclear_cell_count", "PlateletCount",
    "SDMVPSU", "SDMVSTRA",
    "WTINT2YR", "WTMEC2YR", "WTDRD1", "WTDR2D",
    "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2Y"
  )
  keep_b <- intersect(keep_b, names(b))
  m <- merge(nut, b[, keep_b, drop = FALSE], by = c("cycle", "SEQN"), all.x = TRUE)
  for (w in c("WTINT2YR", "WTMEC2YR", "WTDRD1", "WTDR2D", "WTSA2YR", "WTSB2YR", "WTSC2YR", "WTSVOC2Y")) {
    if (w %in% names(m)) m[[paste0(w, "_7")]] <- exwas_to_num(m[[w]]) / 7
  }
  m$DN <- exwas_to_num(m$DN)
  m
}

exwas_aligned_mediators <- function(df) {
  eps <- 1e-6
  neu <- exwas_to_num(df$NeutrophilCount)
  lym <- pmax(exwas_to_num(df$Lymphocytes), eps)
  mono <- exwas_to_num(df$Mononuclear_cell_count)
  plt <- exwas_to_num(df$PlateletCount)
  df$WBC <- exwas_to_num(df$WBC)
  df$NEUT <- neu
  df$MONO <- mono
  df$NLR <- neu / lym
  df$SII <- plt * neu / lym
  df$SIRI <- neu * mono / lym
  df
}

# 对照只留从未患癌（MCQ220=2）；病例 DN=1 保留。去掉「其他癌症」对照。
exwas_aligned_never_cancer_controls <- function(df) {
  if (!"MCQ220" %in% names(df)) {
    stop("需要 MCQ220 列才能限制对照为从未患癌。", call. = FALSE)
  }
  mcq <- exwas_to_num(df$MCQ220)
  dn <- exwas_to_num(df$DN)
  keep <- (dn == 1L) | (dn == 0L & mcq == 2)
  list(
    data = df[which(keep), , drop = FALSE],
    n_dropped_other_cancer = sum(dn == 0L & mcq == 1, na.rm = TRUE),
    n_dropped_other = sum(!keep, na.rm = TRUE) - sum(dn == 0L & mcq == 1, na.rm = TRUE)
  )
}

# 必须同时有第 1 日膳食应答与 MEC 体检权重。
exwas_aligned_require_diet_mec <- function(df) {
  w_d <- if ("WTDRD1_7" %in% names(df)) exwas_to_num(df$WTDRD1_7) else exwas_to_num(df$WTDRD1)
  w_m <- if ("WTMEC2YR_7" %in% names(df)) exwas_to_num(df$WTMEC2YR_7) else exwas_to_num(df$WTMEC2YR)
  ok <- is.finite(w_d) & w_d > 0 & is.finite(w_m) & w_m > 0
  list(
    data = df[which(ok), , drop = FALSE],
    n_before = nrow(df),
    n_after = sum(ok, na.rm = TRUE),
    n_dropped = nrow(df) - sum(ok, na.rm = TRUE)
  )
}

# 双日膳食完整：WTDR2D>0，且（若有）DR2TKCAL>0。
exwas_aligned_require_dr2_complete <- function(df, require_kcal2 = TRUE) {
  w2 <- if ("WTDR2D_7" %in% names(df)) exwas_to_num(df$WTDR2D_7) else exwas_to_num(df$WTDR2D)
  ok <- is.finite(w2) & w2 > 0
  if (isTRUE(require_kcal2) && "DR2TKCAL" %in% names(df)) {
    e2 <- exwas_to_num(df$DR2TKCAL)
    ok <- ok & is.finite(e2) & e2 > 0
  }
  list(
    data = df[which(ok), , drop = FALSE],
    n_before = nrow(df),
    n_after = sum(ok, na.rm = TRUE),
    n_dropped = nrow(df) - sum(ok, na.rm = TRUE)
  )
}

# DR1 + DR2 日均：两边都有取均值；仅一日有则用该日；都无则 NA。
# 覆盖 DR1* 列；同步把能量写成 DR1TKCAL = mean(DR1TKCAL, DR2TKCAL)（同规则）。
# 返回后暴露池应去掉 DR2*，避免与日均重复进 ExWAS。
exwas_aligned_dr12_average <- function(df, nutrient_cols = NULL, energy1 = "DR1TKCAL", energy2 = "DR2TKCAL") {
  if (is.null(nutrient_cols)) {
    nutrient_cols <- names(df)[grepl("^DR1[TI]", names(df))]
  }
  nutrient_cols <- nutrient_cols[grepl("^DR1", nutrient_cols)]
  notes <- list()
  n_both_total <- 0L
  for (col1 in nutrient_cols) {
    col2 <- sub("^DR1", "DR2", col1)
    if (!col1 %in% names(df)) next
    x1 <- exwas_to_num(df[[col1]])
    if (col2 %in% names(df)) {
      x2 <- exwas_to_num(df[[col2]])
    } else {
      x2 <- rep(NA_real_, length(x1))
    }
    both <- is.finite(x1) & is.finite(x2)
    only1 <- is.finite(x1) & !is.finite(x2)
    only2 <- !is.finite(x1) & is.finite(x2)
    avg <- rep(NA_real_, length(x1))
    avg[both] <- (x1[both] + x2[both]) / 2
    avg[only1] <- x1[only1]
    avg[only2] <- x2[only2]
    df[[col1]] <- avg
    n_both_total <- n_both_total + sum(both)
    notes[[length(notes) + 1L]] <- data.frame(
      exposure = col1, paired_dr2 = col2 %in% names(df),
      n_both = sum(both), n_day1_only = sum(only1), n_day2_only = sum(only2),
      n_missing = sum(!is.finite(avg)), stringsAsFactors = FALSE
    )
  }
  # 能量日均 → 写回 energy1，供 Willett residual
  if (energy1 %in% names(df)) {
    e1 <- exwas_to_num(df[[energy1]])
    e2 <- if (energy2 %in% names(df)) exwas_to_num(df[[energy2]]) else rep(NA_real_, length(e1))
    both <- is.finite(e1) & is.finite(e2) & e1 > 0 & e2 > 0
    only1 <- is.finite(e1) & e1 > 0 & !(is.finite(e2) & e2 > 0)
    only2 <- is.finite(e2) & e2 > 0 & !(is.finite(e1) & e1 > 0)
    eavg <- rep(NA_real_, length(e1))
    eavg[both] <- (e1[both] + e2[both]) / 2
    eavg[only1] <- e1[only1]
    eavg[only2] <- e2[only2]
    df[[energy1]] <- eavg
    notes[[length(notes) + 1L]] <- data.frame(
      exposure = energy1, paired_dr2 = energy2 %in% names(df),
      n_both = sum(both), n_day1_only = sum(only1), n_day2_only = sum(only2),
      n_missing = sum(!is.finite(eavg)), stringsAsFactors = FALSE
    )
  }
  list(
    data = df,
    notes = if (length(notes)) do.call(rbind, notes) else NULL,
    n_pair_rows = n_both_total
  )
}

# Willett residual 能量调整（AJCN 1997）：营养素 ~ 总能量，残差 + 均值能量处预测值。
# 只作用于膳食绝对摄入列；实验室/尿浓度不要调用。
exwas_aligned_energy_residual <- function(df, nutrient_cols, energy_col = "DR1TKCAL", min_n = 50L) {
  if (!energy_col %in% names(df)) {
    stop("缺少能量列 ", energy_col, "，无法做能量调整。", call. = FALSE)
  }
  e <- exwas_to_num(df[[energy_col]])
  ok_e <- is.finite(e) & e > 0
  notes <- list()
  for (col in nutrient_cols) {
    if (!col %in% names(df)) next
    y <- exwas_to_num(df[[col]])
    ok <- ok_e & is.finite(y)
    n_ok <- sum(ok)
    res <- rep(NA_real_, length(y))
    decision <- "skip"
    if (n_ok >= min_n) {
      fit <- stats::lm(y[ok] ~ e[ok])
      mu_e <- mean(e[ok])
      pred_mean <- as.numeric(stats::coef(fit)[1] + stats::coef(fit)[2] * mu_e)
      res[ok] <- stats::residuals(fit) + pred_mean
      # 残差后可能出现负值；下游膳食仍走 log1p，故平移到非负
      min_res <- suppressWarnings(min(res[ok], na.rm = TRUE))
      if (is.finite(min_res) && min_res < 0) res[ok] <- res[ok] - min_res
      df[[col]] <- res
      decision <- "residual"
    }
    notes[[length(notes) + 1L]] <- data.frame(
      exposure = col, n_ok = n_ok, decision = decision,
      stringsAsFactors = FALSE
    )
  }
  list(
    data = df,
    notes = if (length(notes)) do.call(rbind, notes) else NULL,
    n_energy_ok = sum(ok_e)
  )
}

# 膳食用 log1p；实验室按原文 LOD 规则（>90% 剔 / >30% 二分类 / 其余 ln；无 LOD 列时用 ≤0 近似未检出）。
exwas_aligned_screen_by_family <- function(df, exposure_cols, lod_map = NULL) {
  fam <- exwas_aligned_family(exposure_cols)
  diet <- names(fam)[fam %in% c("diet_day1", "diet_day2")]
  lab <- names(fam)[fam == "biomarker"]
  other <- setdiff(exposure_cols, c(diet, lab))
  keep <- character(0)
  notes <- list()
  if (length(diet)) {
    sc <- exwas_screen_nutrition(df, diet)
    df <- sc$data
    keep <- c(keep, sc$keep)
    if (!is.null(sc$notes)) {
      sc$notes$family <- "diet"
      notes[[length(notes) + 1L]] <- sc$notes
    }
  }
  if (length(lab)) {
    sc <- exwas_screen_transform(df, lab, lod_map = lod_map)
    df <- sc$data
    keep <- c(keep, sc$keep)
    if (!is.null(sc$notes)) {
      sc$notes$family <- "biomarker"
      # 统一列名便于 rbind
      if (!"zero_rate" %in% names(sc$notes) && "nondetect" %in% names(sc$notes)) {
        sc$notes$zero_rate <- sc$notes$nondetect
      }
      notes[[length(notes) + 1L]] <- sc$notes
    }
  }
  if (length(other)) {
    sc <- exwas_screen_nutrition(df, other)
    df <- sc$data
    keep <- c(keep, sc$keep)
    if (!is.null(sc$notes)) {
      sc$notes$family <- "other"
      notes[[length(notes) + 1L]] <- sc$notes
    }
  }
  note_df <- if (length(notes)) {
    # 对齐列
    cols_u <- unique(unlist(lapply(notes, names)))
    notes <- lapply(notes, function(x) {
      for (nm in cols_u) if (!nm %in% names(x)) x[[nm]] <- NA
      x[, cols_u, drop = FALSE]
    })
    do.call(rbind, notes)
  } else NULL
  list(data = df, keep = keep, notes = note_df)
}
