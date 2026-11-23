# 环境毒物 ExWAS（对齐 Dong 2026 EWAS-new / paper_004）
# 筛查铁律：年龄≥20；分析物缺失>40% 或 >90%<LOD 剔除；人缺失>1/3 剔除；
# >30%<LOD 二分类(0/1)；其余 ln；尿液毒物先按尿肌酐校正；
# mice m=5 maxit=5 seed=123456；ExWAS 不加权 logistic，连续暴露 OR/IQR；BH-FDR。

exwas_tox_is_urine <- function(nm) {
  grepl("^(URX|URD)", nm)
}

exwas_tox_is_blood <- function(nm) {
  grepl("^(LBX|LBD)", nm)
}

# 尿浓度(µg/L 等) / 尿肌酐(mg/dL) × 100 → µg/g creatinine（NHANES 常用）
exwas_tox_creatinine_adjust <- function(df, exposure_cols, creat_col = "URXUCR") {
  if (!creat_col %in% names(df)) {
    return(list(data = df, adjusted = character(0), note = "no_creatinine_col"))
  }
  cr <- exwas_to_num(df[[creat_col]])
  adj <- character(0)
  for (nm in exposure_cols) {
    if (!exwas_tox_is_urine(nm)) next
    if (!nm %in% names(df)) next
    x <- exwas_to_num(df[[nm]])
    y <- ifelse(is.finite(x) & is.finite(cr) & cr > 0, x / cr * 100, NA_real_)
    df[[nm]] <- y
    adj <- c(adj, nm)
  }
  list(data = df, adjusted = adj, note = paste0("urine_over_creat_x100:", length(adj)))
}

# 文献三档 LOD（无 LOD 列时用 ≤0 近似低于检出）。
# 多周期：缺失率分母 = 该分析物至少有一例非缺失的周期内人数（避免未测周期虚高缺失）。
exwas_tox_screen_transform <- function(df, exposure_cols,
                                       max_missing = 0.40, max_lod_drop = 0.90,
                                       lod_binary = 0.30, min_n = 50L,
                                       cycle_col = "cycle") {
  keep <- character(0)
  notes <- list()
  has_cycle <- cycle_col %in% names(df)
  for (col in exposure_cols) {
    if (!col %in% names(df)) next
    x <- exwas_to_num(df[[col]])
    n_measured <- sum(is.finite(x))
    if (has_cycle && n_measured > 0L) {
      cyc_ok <- unique(as.character(df[[cycle_col]][is.finite(x)]))
      in_cyc <- as.character(df[[cycle_col]]) %in% cyc_ok
      n_denom <- sum(in_cyc)
      miss <- 1 - sum(is.finite(x) & in_cyc) / max(n_denom, 1L)
      n_cycles_meas <- length(cyc_ok)
    } else {
      n_denom <- nrow(df)
      miss <- 1 - n_measured / max(n_denom, 1L)
      n_cycles_meas <- NA_integer_
    }
    # 测定值中 ≤0 视为 <LOD
    nondetect <- if (n_measured == 0L) 1 else mean(x[is.finite(x)] <= 0)
    decision <- "log"
    out_col <- paste0(col, "_ln")
    if (n_measured < min_n || miss > max_missing || nondetect > max_lod_drop) {
      decision <- "drop"
      out_col <- NA_character_
    } else if (nondetect > lod_binary) {
      decision <- "binary"
      out_col <- paste0(col, "_bin")
      df[[out_col]] <- ifelse(!is.finite(x), NA_real_, ifelse(x > 0, 1, 0))
      keep <- c(keep, out_col)
    } else {
      decision <- "log"
      xx <- x
      xx[!is.finite(xx) | xx <= 0] <- NA_real_
      df[[out_col]] <- log(xx)
      keep <- c(keep, out_col)
    }
    notes[[length(notes) + 1L]] <- data.frame(
      exposure = col, n_measured = n_measured, n_denom_cycles = n_denom,
      n_cycles_measured = n_cycles_meas,
      missing_rate = miss, under_lod_rate = nondetect, decision = decision,
      model_col = if (is.na(out_col)) NA_character_ else out_col,
      stringsAsFactors = FALSE
    )
  }
  list(
    data = df,
    keep = unique(keep),
    notes = if (length(notes)) do.call(rbind, notes) else NULL
  )
}

# 原文协变量逻辑（Dong 2026）：DAG + 与结局/混杂相关的人口学·社会经济·行为·临床。
# 原文主分析：Age, Gender, Race, Education, Marital, PIR, BMI, Alcohol,
#   上次看牙时间, mouthwash, flossing, eGFR（连续）。
#   Smoking 不进主 ExWAS（烟相关毒物碰撞偏倚），仅敏感性。
# 癌症迁移：去掉口腔三项；性别分层故默认不含 Gender；
#   补 eGFR；Smoke 因癌症病因学进主模（与原文牙周主模不同，见 README）。
exwas_tox_cancer_covars <- function(sex_stratified = TRUE, include_smoke = TRUE) {
  base <- c("Age", "Race", "Education", "Marital_Status", "PIR", "BMI",
            "Alcohol_drinking", "eGFR")
  if (isTRUE(include_smoke)) base <- c(base, "Smoke")
  if (!isTRUE(sex_stratified)) base <- c("Age", "Gender", setdiff(base, "Age"))
  base
}

# CKD-EPI 2021 无种族式（血清肌酐 mg/dL）
exwas_tox_egfr_ckdepi2021 <- function(creat_mgdl, age, female) {
  scr <- exwas_to_num(creat_mgdl)
  age <- exwas_to_num(age)
  female <- as.logical(female)
  out <- rep(NA_real_, length(scr))
  ok <- is.finite(scr) & scr > 0 & is.finite(age) & !is.na(female)
  if (!any(ok)) return(out)
  s <- scr[ok]; a <- age[ok]; f <- female[ok]
  eg <- ifelse(
    f,
    ifelse(s <= 0.7,
           142 * (s / 0.7)^(-0.241) * (0.9938^a) * 1.012,
           142 * (s / 0.7)^(-1.200) * (0.9938^a) * 1.012),
    ifelse(s <= 0.9,
           142 * (s / 0.9)^(-0.302) * (0.9938^a),
           142 * (s / 0.9)^(-1.200) * (0.9938^a))
  )
  out[ok] <- eg
  out
}

# 将协变量尽量编成原文分类（ExWAS 调整集）
exwas_tox_recode_covars_like_paper <- function(df) {
  if ("Education" %in% names(df)) {
    ed <- as.character(df$Education)
    # 尽量映射到 below HS vs HS+
    df$Education <- factor(ed)
  }
  if ("PIR" %in% names(df)) {
    # 数值则按原文切点；已是因子/字符则直接作分类协变量
    if (is.numeric(df$PIR) || is.integer(df$PIR)) {
      pir <- exwas_to_num(df$PIR)
      df$PIR_cat <- factor(
        ifelse(!is.finite(pir), NA_character_,
               ifelse(pir < 1.3, "<1.3",
                      ifelse(pir <= 3.5, "1.3-3.5", ">3.5"))),
        levels = c("<1.3", "1.3-3.5", ">3.5")
      )
    } else {
      df$PIR_cat <- factor(as.character(df$PIR))
    }
  }
  if ("BMI" %in% names(df)) {
    bmi <- exwas_to_num(df$BMI)
    # 原文：normal (<25) vs overweight/obese (>=25)
    df$BMI_cat <- factor(
      ifelse(!is.finite(bmi), NA_character_,
             ifelse(bmi < 25, "Normal", "Overweight_or_Obese")),
      levels = c("Normal", "Overweight_or_Obese")
    )
  }
  if ("Alcohol_drinking" %in% names(df)) {
    al <- as.character(df$Alcohol_drinking)
    df$Alcohol_drinking <- factor(al)
  }
  if ("Smoke" %in% names(df)) {
    df$Smoke <- factor(as.character(df$Smoke))
  }
  if ("Race" %in% names(df)) df$Race <- factor(as.character(df$Race))
  if ("Marital_Status" %in% names(df)) {
    df$Marital_Status <- factor(as.character(df$Marital_Status))
  }
  df
}

# 人缺失>1/3：多周期下只对「该周期内至少有一个非缺失的保留分析物」集合计算
# （单周期原文 = 全分析物集合；多周期避免用未测周期的列虚增缺失）
exwas_tox_drop_person_missing <- function(df, model_cols, max_frac = 1 / 3,
                                          cycle_col = "cycle", raw_from_model = NULL) {
  if (!length(model_cols)) {
    return(list(data = df, keep_idx = seq_len(nrow(df)), n_excluded = 0L))
  }
  if (is.null(raw_from_model)) raw_from_model <- sub("_(ln|bin)$", "", model_cols)
  # 每个周期：哪些 raw 暴露在该周期有测定
  cycles <- unique(as.character(df[[cycle_col]]))
  raw_cols <- unique(raw_from_model)
  # 用原始列（transform 前）判断「本周期是否设计测定」；若只剩 model 列则用 model 列
  probe <- if (all(raw_cols %in% names(df))) raw_cols else model_cols
  cycle_panels <- lapply(cycles, function(cy) {
    hit <- df[[cycle_col]] == cy
    probe[vapply(probe, function(nm) any(is.finite(exwas_to_num(df[[nm]][hit]))), logical(1))]
  })
  names(cycle_panels) <- cycles
  # model_cols 与 probe 对齐
  keep_idx <- integer(0)
  frac <- rep(NA_real_, nrow(df))
  for (i in seq_len(nrow(df))) {
    cy <- as.character(df[[cycle_col]][i])
    panel_raw <- cycle_panels[[cy]]
    if (!length(panel_raw)) { frac[i] <- 1; next }
    # 对应 model 列
    if (identical(probe, model_cols)) {
      panel_m <- panel_raw
    } else {
      panel_m <- model_cols[raw_from_model %in% panel_raw]
    }
    if (!length(panel_m)) { frac[i] <- 1; next }
    xi <- exwas_to_num(unlist(df[i, panel_m, drop = FALSE]))
    frac[i] <- mean(!is.finite(xi))
    if (is.finite(frac[i]) && frac[i] <= max_frac) keep_idx <- c(keep_idx, i)
  }
  list(
    data = df[keep_idx, , drop = FALSE],
    keep_idx = keep_idx,
    n_excluded = nrow(df) - length(keep_idx),
    missing_frac = frac
  )
}

# 不加权 mice → 每套 ExWAS → Rubin → BH-FDR（对齐文献筛查）
exwas_run_unweighted_mice <- function(df, y, exposures, covars,
                                      m = 5L, maxit = 5L, seed = 123456L,
                                      families = NULL) {
  if (!requireNamespace("mice", quietly = TRUE)) stop("需要 mice", call. = FALSE)
  imp_cols <- unique(c(covars))
  imp_cols <- imp_cols[imp_cols %in% names(df)]
  use <- df[, imp_cols, drop = FALSE]
  for (nm in names(use)) {
    if (is.character(use[[nm]])) use[[nm]] <- factor(use[[nm]])
    else if (!is.factor(use[[nm]])) use[[nm]] <- exwas_to_num(use[[nm]])
  }
  keep_c <- names(use)[vapply(use, function(z) !all(is.na(z)), logical(1))]
  use <- use[, keep_c, drop = FALSE]
  set.seed(as.integer(seed))
  exwas_log("毒物 ExWAS mice m=", m, " maxit=", maxit, " seed=", seed,
            " 列=", paste(names(use), collapse = ","))
  imp <- mice::mice(use, m = as.integer(m), maxit = as.integer(maxit),
                    printFlag = FALSE, seed = as.integer(seed))

  store <- lapply(exposures, function(x) {
    list(beta = rep(NA_real_, m), se = rep(NA_real_, m),
         n = rep(NA_integer_, m), n_events = rep(NA_integer_, m))
  })
  names(store) <- exposures

  for (j in seq_len(m)) {
    comp <- mice::complete(imp, action = j)
    dfi <- df
    for (nm in names(comp)) {
      if (is.factor(comp[[nm]])) {
        dfi[[nm]] <- as.character(dfi[[nm]])
        dfi[[nm]] <- factor(as.character(comp[[nm]]))
      } else {
        dfi[[nm]] <- comp[[nm]]
      }
    }
    dfi <- exwas_aligned_as_model_frame(dfi, intersect(covars, names(dfi)))
    for (x in exposures) {
      one <- exwas_fit_one(dfi, y, x, covars)
      # 从 OR/CI 反推 beta/se（fit_one 未直接返回）；重算更稳
      cols <- unique(c(y, x, covars))
      cols <- cols[cols %in% names(dfi)]
      dd <- dfi[, cols, drop = FALSE]
      for (nm in setdiff(names(dd), c(y, x))) if (is.character(dd[[nm]])) dd[[nm]] <- factor(dd[[nm]])
      dd <- dd[stats::complete.cases(dd), , drop = FALSE]
      n_ev <- sum(exwas_to_num(dd[[y]]) == 1, na.rm = TRUE)
      store[[x]]$n[j] <- nrow(dd)
      store[[x]]$n_events[j] <- n_ev
      if (nrow(dd) < 40L || length(unique(dd[[y]])) < 2L) next
      cov_ok <- character(0)
      for (cv in setdiff(names(dd), c(y, x))) {
        v <- dd[[cv]]
        nlev <- if (is.factor(v) || is.character(v)) length(unique(as.character(v))) else length(unique(v[is.finite(exwas_to_num(v))]))
        if (is.finite(nlev) && nlev >= 2L) cov_ok <- c(cov_ok, cv)
      }
      xv <- exwas_to_num(dd[[x]])
      dd[[x]] <- xv
      if (length(unique(xv[is.finite(xv)])) > 2L) {
        iqr <- stats::IQR(xv, na.rm = TRUE)
        if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv, na.rm = TRUE)
        if (!is.finite(iqr) || iqr == 0) iqr <- 1
        dd[[x]] <- dd[[x]] / iqr
      }
      fml <- stats::as.formula(paste(y, "~", paste(c(x, cov_ok), collapse = "+")))
      fit <- tryCatch(stats::glm(fml, data = dd, family = stats::binomial()), error = function(e) NULL)
      if (is.null(fit)) next
      cf <- summary(fit)$coefficients
      hit <- rownames(cf)[rownames(cf) == x | startsWith(rownames(cf), x)]
      hit <- hit[hit != "(Intercept)"]
      if (!length(hit)) next
      store[[x]]$beta[j] <- cf[hit[1], 1]
      store[[x]]$se[j] <- cf[hit[1], 2]
    }
    if (j == 1L || j == m) exwas_log("mice complete ", j, "/", m)
  }

  rows <- lapply(exposures, function(x) {
    st <- store[[x]]
    # 不加权大样本：df_complete = Inf → 正态/大 df
    pl <- exwas_rubin_pool(st$beta, st$se, df_complete = Inf)
    raw <- sub("_(ln|bin)$", "", x)
    data.frame(
      exposure = x, exposure_raw = raw,
      transform = if (endsWith(x, "_bin")) "binary" else if (endsWith(x, "_ln")) "log" else "other",
      n = suppressWarnings(as.integer(round(mean(st$n, na.rm = TRUE)))),
      n_events = suppressWarnings(as.integer(round(mean(st$n_events, na.rm = TRUE)))),
      beta = pl$beta, se = pl$se,
      OR = pl$OR, lo = pl$lo, hi = pl$hi, p = pl$p,
      m_ok = pl$m_ok, m = as.integer(m),
      stringsAsFactors = FALSE
    )
  })
  tab <- do.call(rbind, rows)
  tab$q <- exwas_fdr(tab$p)
  if (!is.null(families)) {
    tab$family <- unname(families[tab$exposure_raw])
    if (all(is.na(tab$family))) tab$family <- unname(families[tab$exposure])
  } else {
    tab$family <- NA_character_
  }
  tab
}

# 从结局周期 csv × 毒物 sav × baseline × 尿肌酐 拼分析表
# disease=pancancer：双性别；MCQ220 任意癌（DN=1）vs 从未患癌（DN=0）
exwas_tox_build_cancer_table <- function(disease = c("prostate", "breast", "pancancer"),
                                         data_dir,
                                         min_age = 20L) {
  disease <- match.arg(disease)
  data_dir <- as.character(data_dir)
  if (disease == "pancancer") {
    sex_keep <- NULL
    pattern <- "泛癌-.*样本_.*\\.csv$"
    dx_dir <- file.path(data_dir, "pancancer_nhanes")
  } else if (disease == "prostate") {
    sex_keep <- 1L
    pattern <- "前列腺癌-.*样本_.*\\.csv$"
    dx_dir <- file.path(data_dir, "prostate_nhanes")
  } else {
    sex_keep <- 2L
    pattern <- "乳腺癌-.*样本_.*\\.csv$"
    dx_dir <- file.path(data_dir, "breast_nhanes")
  }

  fs <- list.files(dx_dir, pattern = pattern, full.names = TRUE)
  if (!length(fs)) stop("未找到结局 csv: ", dx_dir, call. = FALSE)
  outc <- do.call(rbind, lapply(fs, function(f) {
    d <- utils::read.csv(f, stringsAsFactors = FALSE, check.names = FALSE, fileEncoding = "UTF-8")
    names(d) <- sub("^\ufeff", "", names(d))
    d$SEQN <- as.character(d$SEQN)
    d$cycle <- as.character(d$cycle)
    d
  }))
  if (!is.null(sex_keep)) {
    outc <- outc[exwas_to_num(outc$RIAGENDR) == sex_keep, , drop = FALSE]
  }
  outc$Age <- exwas_to_num(outc$RIDAGEYR)
  outc$DN <- exwas_to_num(outc$DN)
  outc$MCQ220 <- exwas_to_num(outc$MCQ220)
  # 病例 或 从未患癌对照（泛癌：DN 已=MCQ220 门；仍剔除 7/9/缺失）
  outc$.keep_out <- (outc$DN == 1L) | (outc$DN == 0L & outc$MCQ220 == 2)
  outc <- outc[outc$.keep_out & is.finite(outc$Age) & outc$Age >= min_age, , drop = FALSE]

  sav_path <- file.path(data_dir, "enviroment-factors.sav")
  if (!requireNamespace("haven", quietly = TRUE)) stop("需要 haven 读 sav", call. = FALSE)
  sav <- as.data.frame(haven::read_sav(sav_path))
  sav$SEQN <- as.character(sav$SEQN)
  sav$cycle <- as.character(sav$cycle)
  sav$cycle[grepl("^2017", sav$cycle) & !grepl("2017-2018", sav$cycle)] <- "2017-2020"
  tox_cols <- setdiff(names(sav), c("SEQN", "cycle"))
  for (nm in tox_cols) sav[[nm]] <- exwas_to_num(sav[[nm]])

  d <- merge(outc, sav, by = c("SEQN", "cycle"), all.x = FALSE)

  # 尿肌酐
  ucr_path <- file.path(data_dir, "尿肌酐_nhanes.csv")
  if (file.exists(ucr_path)) {
    ucr <- utils::read.csv(ucr_path, stringsAsFactors = FALSE, check.names = FALSE)
    names(ucr) <- sub("^\ufeff", "", names(ucr))
    ucr$SEQN <- as.character(ucr$SEQN)
    ucr$URXUCR <- exwas_to_num(ucr$URXUCR)
    # 仅 SEQN：多周期同一人可能多行肌酐，取非缺失
    ucr <- ucr[is.finite(ucr$URXUCR), , drop = FALSE]
    ucr <- ucr[!duplicated(ucr$SEQN), c("SEQN", "URXUCR"), drop = FALSE]
    d <- merge(d, ucr, by = "SEQN", all.x = TRUE)
  }

  # baseline 协变量
  base_r <- file.path(data_dir, "D01_baseline_NHANES_0920.RData")
  e <- new.env()
  load(base_r, envir = e)
  b <- e$baseline
  b$cycle <- as.character(b$Source_File)
  b$SEQN <- as.character(b$ID)
  keep_b <- c(
    "cycle", "SEQN", "Age", "Gender", "Race", "Education", "Marital_Status",
    "PIR", "BMI", "Smoke", "Alcohol_drinking", "UrineCreatinine", "Creatinine",
    "SDMVPSU", "SDMVSTRA", "WTMEC2YR", "WTSA2YR"
  )
  keep_b <- intersect(keep_b, names(b))
  d <- merge(d, b[, keep_b, drop = FALSE], by = c("cycle", "SEQN"), all.x = TRUE,
             suffixes = c("", "_b"))
  if (!"Age" %in% names(d) || all(!is.finite(exwas_to_num(d$Age)))) {
    d$Age <- exwas_to_num(d$RIDAGEYR)
  } else {
    # 优先 baseline Age，否则 RIDAGEYR
    a1 <- exwas_to_num(d$Age)
    a2 <- exwas_to_num(d$RIDAGEYR)
    d$Age <- ifelse(is.finite(a1), a1, a2)
  }
  if (!"URXUCR" %in% names(d) || all(!is.finite(exwas_to_num(d$URXUCR)))) {
    if ("UrineCreatinine" %in% names(d)) d$URXUCR <- exwas_to_num(d$UrineCreatinine)
  }

  # eGFR（CKD-EPI 2021）；女性=Gender/RIAGENDR
  creat <- if ("Creatinine" %in% names(d)) exwas_to_num(d$Creatinine) else rep(NA_real_, nrow(d))
  sex_f <- if ("Gender" %in% names(d)) {
    grepl("^[Ff]|Female|女", as.character(d$Gender))
  } else if ("RIAGENDR" %in% names(d)) {
    exwas_to_num(d$RIAGENDR) == 2
  } else {
    rep(disease == "breast", nrow(d))
  }
  d$eGFR <- exwas_tox_egfr_ckdepi2021(creat, d$Age, sex_f)
  # 泛癌双性别：补 Gender 因子（原文含 gender）
  if (disease == "pancancer" && !"Gender" %in% names(d) && "RIAGENDR" %in% names(d)) {
    g <- exwas_to_num(d$RIAGENDR)
    d$Gender <- factor(ifelse(g == 1, "Male", ifelse(g == 2, "Female", NA_character_)),
                       levels = c("Male", "Female"))
  } else if (disease == "pancancer" && "Gender" %in% names(d)) {
    d$Gender <- factor(as.character(d$Gender))
  }
  d <- exwas_tox_recode_covars_like_paper(d)

  # 至少 1 个毒物非缺失
  has_tox <- rowSums(sapply(tox_cols, function(v) is.finite(exwas_to_num(d[[v]])))) > 0
  d <- d[has_tox, , drop = FALSE]

  code_path <- file.path(data_dir, "Envrioment_code_realname.csv")
  code <- if (file.exists(code_path)) {
    utils::read.csv(code_path, stringsAsFactors = FALSE)
  } else {
    data.frame(Labels = tox_cols, Exposure = tox_cols, Family = "Environmental Toxicants",
               stringsAsFactors = FALSE)
  }
  list(
    data = d,
    tox_cols = intersect(code$Labels, names(d)),
    code = code,
    disease = disease,
    sex_keep = sex_keep,
    n_cycles = length(unique(d$cycle))
  )
}
