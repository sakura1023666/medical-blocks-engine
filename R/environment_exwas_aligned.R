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
