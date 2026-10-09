###############################################################################
# literature_ckm_cum_egdr.R — Wang 2026 CKM × 累积 eGDR × k-means 助手
# 发表表/图 helpers → R/cum_egdr_kmeans_pub.R
# 唯一发表重导 → run/cum_egdr_kmeans_ckm/rebuild_publication.R
###############################################################################

ckm_stroke_read_wide <- function(path) {
  path <- as.character(path)[1L]
  if (!file.exists(path)) stop("数据文件不存在: ", path, call. = FALSE)
  utils::read.csv(path, stringsAsFactors = FALSE, check.names = FALSE,
                  fileEncoding = "UTF-8-BOM")
}

ckm_stroke_harmonize_columns <- function(df) {
  nm <- names(df)
  ren <- c(
    Age = "age1", Gender = "sex", Waist_circumference = "wc1", BMI = "bmi1",
    SBP = "sbp1", DBP = "dbp1", Glucose = "glucose1", HbA1c = "hba1c1",
    Triglycerides = "tg1", Creatinine = "creatinine1", Total_Cholesterol = "tc1",
    HDL = "hdl1", LDL = "ldl1", UA = "ua1", eGFR = "egfr1",
    Education = "educ4_1", Marital = "marital_married1",
    Smoke = "smoke_ever1", Drink = "drink_ever1",
    Diabetes = "diabe1", Hypertension = "htn1",
    Stroke = "r4stroke", CKM_stage = "ckm_stage",
    eGDR_t1 = "egdr2012", eGDR_t2 = "egdr2015", cum_eGDR = "cum_egdr",
    WC_t2 = "wc3", HbA1c_t2 = "hba1c3", Hypertension_t2 = "htn3"
  )
  for (std in names(ren)) {
    src <- ren[[std]]
    if (src %in% nm && !std %in% nm) df[[std]] <- df[[src]]
  }
  # ELSA 骨质疏松宽表：Hypertension_w4 → Hypertension（uv_vif / Model3 需要）
  if (!"Hypertension" %in% names(df)) {
    for (alt in c("Hypertension_w4", "Hypertension_t1_raw", "htn1")) {
      if (alt %in% names(df)) {
        df$Hypertension <- df[[alt]]
        break
      }
    }
  }
  # Gender 因子
  if ("Gender" %in% names(df)) {
    g <- df$Gender
    if (is.numeric(g) || all(as.character(g) %in% c("1", "2", NA))) {
      df$Gender <- factor(ifelse(as.character(g) == "1", "Male",
                          ifelse(as.character(g) == "2", "Female", NA_character_)),
                          levels = c("Male", "Female"))
    } else if (!is.factor(g)) {
      gc <- trimws(as.character(g))
      df$Gender <- factor(
        ifelse(tolower(gc) %in% c("male", "m"), "Male",
          ifelse(tolower(gc) %in% c("female", "f"), "Female", gc)),
        levels = c("Male", "Female")
      )
    }
  }
  if ("Marital" %in% names(df) && !is.factor(df$Marital)) {
    v <- df$Marital
    vc <- trimws(as.character(v))
    if (any(grepl("married|other|partner|unmarried", vc, ignore.case = TRUE), na.rm = TRUE)) {
      df$Marital <- factor(
        ifelse(grepl("^married$|^partner", vc, ignore.case = TRUE), "Married",
          ifelse(is.na(vc) | vc == "", NA_character_, "Other")),
        levels = c("Married", "Other")
      )
    } else {
      df$Marital <- factor(ifelse(as.numeric(v) == 1, "Married",
                           ifelse(as.numeric(v) == 0, "Other", NA_character_)),
                           levels = c("Married", "Other"))
    }
  }
  if ("Education" %in% names(df) && !is.factor(df$Education)) {
    vnum <- suppressWarnings(as.integer(df$Education))
    if (mean(is.na(vnum)) < 0.5) {
      lab <- c("1" = "Illiterate", "2" = "Primary", "3" = "Middle", "4" = "High+")
      df$Education <- factor(lab[as.character(vnum)], levels = unname(lab))
    } else {
      df$Education <- factor(as.character(df$Education))
    }
  }
  for (bc in c("Smoke", "Drink")) {
    if (bc %in% names(df) && !is.factor(df[[bc]])) {
      v <- df[[bc]]
      vc <- tolower(trimws(as.character(v)))
      if (any(vc %in% c("yes", "no", "y", "n", "never", "current", "former", "ever"), na.rm = TRUE)) {
        df[[bc]] <- factor(
          ifelse(vc %in% c("yes", "y", "1", "current", "former", "ever"), "Yes",
            ifelse(vc %in% c("no", "n", "0", "never"), "No", NA_character_)),
          levels = c("No", "Yes")
        )
      } else {
        df[[bc]] <- factor(ifelse(as.numeric(v) == 1, "Yes",
                           ifelse(as.numeric(v) == 0, "No", NA_character_)),
                           levels = c("No", "Yes"))
      }
    }
  }
  # Hypertension Yes/No for index formulas
  for (hc in c("Hypertension", "Hypertension_t2")) {
    if (hc %in% names(df) && !is.factor(df[[hc]])) {
      v <- df[[hc]]
      vc <- tolower(trimws(as.character(v)))
      if (any(vc %in% c("yes", "no"), na.rm = TRUE)) {
        df[[hc]] <- factor(
          ifelse(vc %in% c("yes", "y", "1"), "Yes",
            ifelse(vc %in% c("no", "n", "0"), "No", NA_character_)),
          levels = c("No", "Yes")
        )
      } else {
        df[[hc]] <- factor(ifelse(as.numeric(v) == 1, "Yes",
                           ifelse(as.numeric(v) == 0, "No", NA_character_)),
                           levels = c("No", "Yes"))
      }
    }
  }
  if ("Diabetes" %in% names(df) && !is.factor(df$Diabetes)) {
    v <- df$Diabetes
    vc <- tolower(trimws(as.character(v)))
    if (any(vc %in% c("yes", "no"), na.rm = TRUE)) {
      df$Diabetes <- factor(
        ifelse(vc %in% c("yes", "y", "1"), "Yes",
          ifelse(vc %in% c("no", "n", "0"), "No", NA_character_)),
        levels = c("No", "Yes")
      )
    } else {
      df$Diabetes <- factor(ifelse(as.numeric(v) == 1, "Yes",
                            ifelse(as.numeric(v) == 0, "No", NA_character_)),
                            levels = c("No", "Yes"))
    }
  }
  # Dyslipidemia 粗构造：TG>=150 或 TC 高或 HDL 低（缺自报时）
  if (!"Dyslipidemia" %in% names(df) && all(c("Triglycerides", "HDL") %in% names(df))) {
    tg <- as.numeric(df$Triglycerides)
    hdl <- as.numeric(df$HDL)
    flag <- as.integer(tg >= 150 | (!is.na(hdl) & hdl < 40))
    df$Dyslipidemia <- factor(ifelse(flag == 1L, "Yes", "No"), levels = c("No", "Yes"))
  }
  if ("Stroke" %in% names(df)) df$Stroke <- as.integer(as.numeric(df$Stroke) == 1)
  if ("Osteoporosis" %in% names(df)) {
    df$Osteoporosis <- as.integer(as.numeric(df$Osteoporosis) == 1)
  }
  if ("CKM_stage" %in% names(df)) df$CKM_stage <- as.integer(df$CKM_stage)
  # ELSA / 通用：Drink 别名
  if (!"Drink" %in% names(df) && "Alcohol_drinking" %in% names(df)) {
    df$Drink <- df$Alcohol_drinking
  }
  if (!"Marital" %in% names(df) && "Marital_Status" %in% names(df)) {
    df$Marital <- df$Marital_Status
  }
  df
}

ckm_stroke_recompute_egdr <- function(df, cfg = list()) {
  # 公式逐字：21.158 - 0.09*WC - 3.407*HTN - 0.551*HbA1c
  htn01 <- function(x) {
    if (is.factor(x)) as.integer(x == "Yes") else as.integer(as.numeric(x) == 1)
  }
  if (all(c("Waist_circumference", "Hypertension", "HbA1c") %in% names(df))) {
    df$eGDR_t1 <- 21.158 - 0.09 * as.numeric(df$Waist_circumference) -
      3.407 * htn01(df$Hypertension) - 0.551 * as.numeric(df$HbA1c)
  }
  if (all(c("WC_t2", "Hypertension_t2", "HbA1c_t2") %in% names(df))) {
    df$eGDR_t2 <- 21.158 - 0.09 * as.numeric(df$WC_t2) -
      3.407 * htn01(df$Hypertension_t2) - 0.551 * as.numeric(df$HbA1c_t2)
  }
  mult <- as.numeric(cfg$cum_multiplier %||% 3)
  if (all(c("eGDR_t1", "eGDR_t2") %in% names(df))) {
    df$cum_eGDR <- (as.numeric(df$eGDR_t1) + as.numeric(df$eGDR_t2)) / 2 * mult
  }
  df
}

ckm_stroke_is_full_depth <- function(index_name, cfg) {
  full <- as.character(cfg$full_depth_indices %||% "eGDR")
  toupper(as.character(index_name)[1L]) %in% toupper(full)
}

ckm_stroke_kmeans_elbow <- function(mat, k_max = 8L, seed = 2026L, nstart = 25L) {
  set.seed(as.integer(seed))
  mat <- as.matrix(mat)
  ok <- stats::complete.cases(mat)
  mat <- mat[ok, , drop = FALSE]
  k_max <- max(2L, min(as.integer(k_max), nrow(mat) - 1L))
  wcss <- vapply(seq_len(k_max), function(k) {
    km <- stats::kmeans(mat, centers = k, nstart = nstart, iter.max = 100L)
    km$tot.withinss
  }, numeric(1))
  # 简单肘点：相邻差分减量最大处之后的 k（与文献目视 K=4 对齐时可 force_k）
  d1 <- diff(wcss)
  d2 <- diff(d1)
  elbow_k <- if (length(d2)) which.max(-d2) + 1L else 4L
  elbow_k <- max(2L, min(elbow_k, k_max))
  list(wcss = wcss, elbow_k = as.integer(elbow_k), n_complete = nrow(mat))
}

ckm_stroke_kmeans_fit <- function(mat, k = 4L, seed = 2026L, nstart = 25L) {
  set.seed(as.integer(seed))
  mat <- as.matrix(mat)
  ok <- stats::complete.cases(mat)
  cl <- rep(NA_integer_, nrow(mat))
  if (sum(ok) < k) return(list(cluster = cl, centers = NULL, ok = ok))
  km <- stats::kmeans(mat[ok, , drop = FALSE], centers = as.integer(k),
                      nstart = as.integer(nstart), iter.max = 100L)
  cl[ok] <- km$cluster
  list(cluster = cl, centers = km$centers, ok = ok, tot.withinss = km$tot.withinss)
}

ckm_stroke_anchor_classes <- function(cluster, t1, t2, ref_policy = "lowest_mean_t1") {
  # 文献 Class2 = persistent low eGDR = 高风险参照
  u <- sort(unique(stats::na.omit(cluster)))
  means <- vapply(u, function(k) {
    mean(as.numeric(t1)[cluster == k], na.rm = TRUE)
  }, numeric(1))
  ord <- order(means) # 低 eGDR 在前
  map <- setNames(seq_along(ord), as.character(u[ord]))
  # 重编码：1=最低均值…；再把「最低」标为 Class2 语义参照较别扭
  # 采用：按均值升序映射到文献语义标签后再固定因子水平，参照=Persistent_low
  labels <- c("Rapid_or_other", "Persistent_low", "Moderate_high_stable", "Stable_high")
  # 更稳：按 t1 均值四分：最低→Persistent_low(ref)，次低→Rapid_decrease 近似，…
  # 简化对齐文献：最低均值 → Class2 Persistent_low；最高 → Class3 Stable_high；
  # 中间两个按 Δ(t2-t1) 区分下降 vs 稳定
  out <- rep(NA_character_, length(cluster))
  if (!length(u)) return(factor(out))
  ranked <- u[order(means)]
  low <- ranked[1L]
  high <- ranked[length(ranked)]
  mid <- setdiff(ranked, c(low, high))
  out[cluster == low] <- "Persistent_low"
  out[cluster == high] <- "Stable_high"
  if (length(mid) == 1L) {
    out[cluster == mid] <- "Moderate_high_stable"
  } else if (length(mid) >= 2L) {
    dlt <- vapply(mid, function(k) {
      mean(as.numeric(t2)[cluster == k] - as.numeric(t1)[cluster == k], na.rm = TRUE)
    }, numeric(1))
    # 下降更多 → Rapid_decrease；另一 → Moderate_high_stable
    dec <- mid[which.min(dlt)]
    stab <- setdiff(mid, dec)
    out[cluster == dec] <- "Rapid_decrease"
    out[cluster %in% stab] <- "Moderate_high_stable"
  }
  factor(out, levels = c("Persistent_low", "Moderate_high_stable", "Stable_high", "Rapid_decrease"))
}

ckm_stroke_fit_or_row <- function(df, exposure, outcome, covars = NULL) {
  d <- df[, unique(c(outcome, exposure, covars)), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 20L) return(NULL)
  if (is.factor(d[[exposure]]) || is.character(d[[exposure]])) {
    d[[exposure]] <- factor(d[[exposure]])
    if (nlevels(d[[exposure]]) < 2L) return(NULL)
  }
  fml <- stats::as.formula(paste(outcome, "~", paste(c(exposure, covars), collapse = "+")))
  fit <- tryCatch(stats::glm(fml, data = d, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  sm <- summary(fit)$coefficients
  rn <- rownames(sm)
  # 暴露相关行
  hit <- grepl(paste0("^", exposure), rn)
  if (!any(hit) && exposure %in% rn) hit <- rn == exposure
  rows <- list()
  for (i in which(hit)) {
    est <- sm[i, 1]; se <- sm[i, 2]; p <- sm[i, 4]
    or <- exp(est); lo <- exp(est - 1.96 * se); hi <- exp(est + 1.96 * se)
    rows[[length(rows) + 1L]] <- data.frame(
      term = rn[i], OR = or, CI_low = lo, CI_high = hi, P = p,
      OR_CI = sprintf("%.2f (%.2f, %.2f)", or, lo, hi),
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(NULL)
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

ckm_stroke_add_futime <- function(df) {
  if (all(c("iwy1", "iwy4") %in% names(df))) {
    t0 <- as.numeric(df$iwy1) + as.numeric(if ("iwm1" %in% names(df)) df$iwm1 else 1) / 12
    t1 <- as.numeric(df$iwy4) + as.numeric(if ("iwm4" %in% names(df)) df$iwm4 else 1) / 12
    df$futime <- pmax(t1 - t0, 0.01)
  }
  if ("Stroke" %in% names(df)) {
    df$status <- as.integer(as.numeric(df$Stroke) == 1L)
  } else if ("Osteoporosis" %in% names(df) && !"status" %in% names(df)) {
    df$status <- as.integer(as.numeric(df$Osteoporosis) == 1L)
  }
  df
}

ckm_stroke_fit_hr_row <- function(df, exposure, covars = NULL) {
  if (!requireNamespace("survival", quietly = TRUE)) return(NULL)
  if (!all(c("futime", "status") %in% names(df))) return(NULL)
  d <- df[, unique(c("futime", "status", exposure, covars)), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 20L || sum(d$status) < 5L) return(NULL)
  if (is.factor(d[[exposure]]) || is.character(d[[exposure]])) {
    d[[exposure]] <- factor(d[[exposure]])
    if (nlevels(d[[exposure]]) < 2L) return(NULL)
  }
  fml <- stats::as.formula(
    paste("survival::Surv(futime, status) ~", paste(c(exposure, covars), collapse = "+"))
  )
  fit <- tryCatch(survival::coxph(fml, data = d), error = function(e) NULL)
  if (is.null(fit)) return(NULL)
  sm <- summary(fit)$coefficients
  rn <- rownames(sm)
  hit <- grepl(paste0("^", exposure), rn)
  if (!any(hit) && exposure %in% rn) hit <- rn == exposure
  rows <- list()
  for (i in which(hit)) {
    est <- sm[i, 1]; se <- sm[i, 3]; p <- sm[i, 5]
    hr <- exp(est); lo <- exp(est - 1.96 * se); hi <- exp(est + 1.96 * se)
    rows[[length(rows) + 1L]] <- data.frame(
      term = rn[i], HR = hr, CI_low = lo, CI_high = hi, P = p,
      HR_CI = sprintf("%.2f (%.2f, %.2f)", hr, lo, hi),
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(NULL)
  out <- do.call(rbind, rows)
  rownames(out) <- NULL
  out
}

# 暴露成分不得进 Model（BMI 指数时踢 BMI；eGDR 不踢 BMI）
ckm_stroke_model_drop_exposure_components <- function(vars, index_name = NULL, bl = list()) {
  vars <- unique(as.character(vars %||% character(0)))
  idx <- as.character(index_name %||% bl$current_index %||% "")[1L]
  drop <- character(0)
  if (identical(toupper(idx), "BMI")) drop <- c(drop, "BMI")
  if (grepl("WHtR|WWI|ABSI|CMI|VAI|AIP_BMI|TyG_BMI|METSIR|MCMI", idx, ignore.case = TRUE)) {
    if (grepl("BMI|WHtR|WWI|ABSI|CMI|VAI|METSIR|MCMI|AIP_BMI|TyG_BMI", idx, ignore.case = TRUE) &&
        !grepl("^TyG$", idx) && !grepl("^AIP$", idx) && !grepl("^eGDR$", idx, ignore.case = TRUE)) {
      drop <- c(drop, "BMI")
    }
  }
  setdiff(vars, drop)
}

# 单因素 logistic P（连续=系数 P；因子=LRT 整体 P）
ckm_stroke_uv_p <- function(data, outcome, var) {
  if (!all(c(outcome, var) %in% names(data))) return(NA_real_)
  d <- data[, c(outcome, var), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  if (nrow(d) < 30L || length(unique(d[[outcome]])) < 2L) return(NA_real_)
  y <- d[[outcome]]
  if (is.factor(y) || is.character(y)) {
    y <- as.integer(as.numeric(y) == 1L | grepl("yes|osteopor|stroke|case|1", as.character(y), ignore.case = TRUE))
  } else {
    y <- as.integer(as.numeric(y) == 1L)
  }
  d$y <- y
  x <- d[[var]]
  if (is.character(x)) x <- factor(x)
  d$x <- x
  if (is.factor(d$x) && nlevels(droplevels(d$x)) < 2L) return(NA_real_)
  fit0 <- tryCatch(stats::glm(y ~ 1, data = d, family = stats::binomial()), error = function(e) NULL)
  fit1 <- tryCatch(stats::glm(y ~ x, data = d, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit0) || is.null(fit1)) return(NA_real_)
  if (is.factor(d$x) || is.character(d$x)) {
    a <- tryCatch(stats::anova(fit0, fit1, test = "LRT"), error = function(e) NULL)
    if (is.null(a) || nrow(a) < 2L) return(NA_real_)
    return(as.numeric(a$`Pr(>Chi)`[2L]))
  }
  co <- tryCatch(summary(fit1)$coefficients, error = function(e) NULL)
  if (is.null(co) || !"x" %in% rownames(co)) return(NA_real_)
  as.numeric(co["x", "Pr(>|z|)"])
}

# 在候选集上迭代剔除最高 VIF（默认阈值 4，对齐发病 multicollinearity_screen）
ckm_stroke_vif_pass <- function(data, vars, threshold = 4) {
  vars <- intersect(unique(as.character(vars %||% character(0))), names(data))
  if (length(vars) <= 1L) return(vars)
  dd <- data[, vars, drop = FALSE]
  for (v in vars) {
    if (is.character(dd[[v]])) dd[[v]] <- factor(dd[[v]])
  }
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 30L) return(vars)
  thr <- as.numeric(threshold)[1L]
  if (!is.finite(thr) || thr <= 0) thr <- 4
  cur <- vars
  .score_one <- function(cur_vars) {
    d2 <- dd[, cur_vars, drop = FALSE]
    d2$.vif_y <- stats::rnorm(nrow(d2))
    fit <- tryCatch(
      stats::lm(stats::as.formula(paste(".vif_y ~", paste(cur_vars, collapse = "+"))), data = d2),
      error = function(e) NULL
    )
    if (is.null(fit)) return(NULL)
    if (!requireNamespace("car", quietly = TRUE)) return(NULL)
    vv <- tryCatch(car::vif(fit), error = function(e) NULL)
    if (is.null(vv)) return(NULL)
    score <- setNames(rep(NA_real_, length(cur_vars)), cur_vars)
    if (is.matrix(vv)) {
      gvif <- as.numeric(vv[, ncol(vv)]) # 常用 GVIF^(1/(2*Df)) 或末列
      if (all(!is.finite(gvif))) gvif <- as.numeric(vv[, 1L])
      nm <- rownames(vv)
      for (v in cur_vars) {
        hit <- nm == v | startsWith(nm, paste0(v))
        if (any(hit)) score[[v]] <- max(gvif[hit], na.rm = TRUE)
      }
    } else {
      nm <- names(vv)
      val <- as.numeric(vv)
      for (v in cur_vars) {
        hit <- nm == v | startsWith(nm, paste0(v))
        if (any(hit)) score[[v]] <- max(val[hit], na.rm = TRUE)
      }
    }
    score[is.finite(score)]
  }
  while (length(cur) >= 2L) {
    score <- .score_one(cur)
    if (is.null(score) || !length(score)) break
    if (max(score, na.rm = TRUE) < thr) break
    drop_v <- names(score)[which.max(score)]
    cur <- setdiff(cur, drop_v)
  }
  cur
}

# 发病口径：单因素显著 → VIF；Model2=人口学，Model3=Model2+其他
ckm_stroke_resolve_models_uv_vif <- function(
    data, outcome, bl = list(), index_name = NULL,
    demo_pool = NULL, clinical_pool = NULL) {
  # ELSA 等宽表常见别名
  if (!"Hypertension" %in% names(data) && "Hypertension_w4" %in% names(data)) {
    data$Hypertension <- data$Hypertension_w4
  }
  alpha <- as.numeric(bl$uv_alpha %||% 0.05)[1L]
  vif_thr <- as.numeric(bl$vif_threshold %||% 4)[1L]
  force_demo <- as.character(bl$force_demo %||% "Age")
  demo_pool <- as.character(demo_pool %||% bl$demo_pool %||%
    bl$model2 %||% c("Age", "Gender", "Marital", "Education"))
  clinical_pool <- as.character(clinical_pool %||% bl$clinical_pool %||%
    setdiff(bl$model3 %||% character(0), demo_pool))
  if (!length(clinical_pool)) {
    clinical_pool <- c("BMI", "Smoke", "Drink", "Dyslipidemia", "Diabetes", "Hypertension", "eGFR")
  }
  demo_pool <- intersect(unique(demo_pool), names(data))
  clinical_pool <- intersect(unique(setdiff(clinical_pool, demo_pool)), names(data))
  # 暴露成分先从候选踢掉
  demo_pool <- ckm_stroke_model_drop_exposure_components(demo_pool, index_name, bl)
  clinical_pool <- ckm_stroke_model_drop_exposure_components(clinical_pool, index_name, bl)

  cand <- unique(c(demo_pool, clinical_pool))
  uv_rows <- lapply(cand, function(v) {
    p <- ckm_stroke_uv_p(data, outcome, v)
    data.frame(
      variable = v,
      pool = if (v %in% demo_pool) "demo" else "clinical",
      uv_p = p,
      uv_sig = is.finite(p) && p < alpha,
      stringsAsFactors = FALSE
    )
  })
  uv_df <- if (length(uv_rows)) do.call(rbind, uv_rows) else {
    data.frame(variable = character(), pool = character(), uv_p = numeric(),
               uv_sig = logical(), stringsAsFactors = FALSE)
  }
  # 强制人口学（默认 Age）即使 UV 不显著也进 VIF 候选
  force_demo <- intersect(force_demo, demo_pool)
  uv_keep <- unique(c(uv_df$variable[which(uv_df$uv_sig)], force_demo))
  uv_keep <- uv_keep[uv_keep %in% cand]
  vif_keep <- ckm_stroke_vif_pass(data, uv_keep, threshold = vif_thr)

  m2 <- intersect(demo_pool, vif_keep)
  # 保证 force_demo 在 VIF 后仍尽量保留（若被 VIF 剔掉则不加回，避免共线）
  m3_extra <- intersect(clinical_pool, vif_keep)
  m3 <- unique(c(m2, m3_extra))
  m2 <- ckm_stroke_model_drop_exposure_components(m2, index_name, bl)
  m3 <- ckm_stroke_model_drop_exposure_components(m3, index_name, bl)

  uv_df$force_demo <- uv_df$variable %in% force_demo
  uv_df$vif_pass <- uv_df$variable %in% vif_keep
  uv_df$in_model2 <- uv_df$variable %in% m2
  uv_df$in_model3 <- uv_df$variable %in% m3

  list(
    Model1 = character(0),
    Model2 = m2,
    Model3 = m3,
    uv_table = uv_df,
    uv_alpha = alpha,
    vif_threshold = vif_thr,
    mode = "uv_vif"
  )
}

ckm_stroke_model_sets <- function(bl, data, index_name = NULL, outcome = NULL) {
  mode <- tolower(as.character(bl$covariate_mode %||% "fixed")[1L])
  if (identical(mode, "uv_vif")) {
    oc <- as.character(outcome %||% bl$outcome_column %||% "Osteoporosis")[1L]
    if (!oc %in% names(data)) {
      # 常见别名回退
      for (alt in c("Stroke", "status", "Osteoporosis")) {
        if (alt %in% names(data)) { oc <- alt; break }
      }
    }
    res <- ckm_stroke_resolve_models_uv_vif(data, oc, bl = bl, index_name = index_name)
    return(list(
      Model1 = res$Model1, Model2 = res$Model2, Model3 = res$Model3,
      uv_vif = res
    ))
  }

  m1 <- character(0)
  m2 <- intersect(as.character(bl$model2 %||% c("Age", "Gender", "Marital")), names(data))
  m3 <- intersect(as.character(bl$model3 %||% c(
    "Age", "Gender", "Marital", "BMI", "Education", "Smoke", "Drink",
    "eGFR", "Dyslipidemia", "Diabetes"
  )), names(data))
  m2 <- ckm_stroke_model_drop_exposure_components(m2, index_name, bl)
  m3 <- ckm_stroke_model_drop_exposure_components(m3, index_name, bl)
  list(Model1 = m1, Model2 = m2, Model3 = m3)
}

ckm_stroke_prepare_age_group <- function(df, cutoff = 60L) {
  if (!"Age" %in% names(df)) return(df)
  cut <- as.numeric(cutoff)[1L]
  df$Age_Group <- factor(
    ifelse(as.numeric(df$Age) < cut, paste0("< ", cut), paste0("\u2265 ", cut)),
    levels = c(paste0("< ", cut), paste0("\u2265 ", cut))
  )
  df
}
