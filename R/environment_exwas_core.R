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
  cols <- c(y, x, covars)
  cols <- cols[nzchar(cols)]
  dd <- df[, cols, drop = FALSE]
  dd <- dd[stats::complete.cases(dd), , drop = FALSE]
  if (nrow(dd) < 40L || length(unique(dd[[y]])) < 2L) {
    return(data.frame(exposure = x, n = nrow(dd), OR = NA, lo = NA, hi = NA, p = NA))
  }
  # 每 IQR（连续）；二分类则为检出 vs 未检出
  xv <- dd[[x]]
  if (length(unique(xv)) > 2L) {
    iqr <- stats::IQR(xv, na.rm = TRUE)
    if (!is.finite(iqr) || iqr == 0) iqr <- stats::sd(xv)
    dd[[x]] <- dd[[x]] / iqr
  }
  fml <- stats::as.formula(paste(y, "~", paste(c(x, covars), collapse = " + ")))
  fit <- tryCatch(stats::glm(fml, data = dd, family = stats::binomial()), error = function(e) NULL)
  if (is.null(fit)) {
    return(data.frame(exposure = x, n = nrow(dd), OR = NA, lo = NA, hi = NA, p = NA))
  }
  cf <- summary(fit)$coefficients
  if (!x %in% rownames(cf)) {
    return(data.frame(exposure = x, n = nrow(dd), OR = NA, lo = NA, hi = NA, p = NA))
  }
  b <- cf[x, 1]
  se <- cf[x, 2]
  data.frame(
    exposure = x, n = nrow(dd),
    OR = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
    p = cf[x, 4], stringsAsFactors = FALSE
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
