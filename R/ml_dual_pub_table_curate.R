###############################################################################
#  ml_dual_pub_table_curate.R — ML 双库指标汇总表整理
#  主表 Table 1–5 + 附表 S1–S8，其余附表顺延；双库同类表合并为一张
###############################################################################

.ml_ptc_db_slots <- function() c("nhanes", "mimic")

# MIMIC_IV ↔ MIMIC IV：文件名下划线会被改成空格，匹配必须两边都认
.ml_ptc_tag_aliases <- function(tag) {
  tag <- trimws(as.character(tag %||% "")[1L])
  if (!nzchar(tag)) return(character(0))
  unique(c(tag, gsub("_", " ", tag, fixed = TRUE), gsub(" ", "_", tag, fixed = TRUE)))
}

.ml_ptc_tag_flex_re <- function(tag) {
  tag <- trimws(as.character(tag %||% "")[1L])
  if (!nzchar(tag)) return("")
  parts <- strsplit(gsub("[ _]+", " ", tag), " ", fixed = TRUE)[[1L]]
  esc <- if (exists(".regex_escape_pcre", mode = "function")) {
    vapply(parts, .regex_escape_pcre, character(1L), USE.NAMES = FALSE)
  } else {
    gsub("(\\\\|[][{}()+*^$?.|-])", "\\\\\\1", parts, perl = TRUE)
  }
  paste(esc, collapse = "[ _]+")
}

.ml_ptc_slot_tag <- function(cfg, slot) {
  if (exists("dual_db_slot_path_name", mode = "function")) {
    return(dual_db_slot_path_name(cfg, slot))
  }
  dual <- (cfg %||% list())$dual_db %||% list()
  if (identical(slot, "nhanes")) {
    return(as.character((dual$primary %||% list())$name %||% "NHANES")[1L])
  }
  as.character((dual$secondary %||% list())$name %||% "MIMIC")[1L]
}

#' 该 db_tag 是否为次库（dev_internal_ext 下 = 外验库）
.ml_ptc_is_secondary_db <- function(db_tag, cfg = list()) {
  sec <- .ml_ptc_slot_tag(cfg, "mimic")
  if (!nzchar(sec)) return(FALSE)
  tolower(trimws(as.character(db_tag %||% "")[1L])) %in%
    tolower(.ml_ptc_tag_aliases(sec))
}

#' dev_ext：次库（外验）插补 / VIF 表强制归 external，勿被通用 "(validation set)" 误判为 internal
.ml_ptc_dev_ext_force_ext <- function(role, db_tag, cfg) {
  if (!.ml_ptc_is_dev_ext(cfg) || !.ml_ptc_is_secondary_db(db_tag, cfg)) return(role)
  switch(role,
    s_imputation_val = , s_imputation_train = , s_imputation = "s_imputation_ext",
    s_vif_val = , s_vif_train = , s_vif_screen = "s_vif_ext",
    role
  )
}

.ml_ptc_canonical_db_tag <- function(tag, cfg = list()) {
  tag <- trimws(as.character(tag %||% "")[1L])
  if (!nzchar(tag) || identical(tag, "Combined")) return(tag)
  for (slot in .ml_ptc_db_slots()) {
    st <- .ml_ptc_slot_tag(cfg, slot)
    if (tolower(tag) %in% tolower(.ml_ptc_tag_aliases(st))) {
      return(gsub("_", " ", st, fixed = TRUE))
    }
  }
  gsub("_", " ", tag, fixed = TRUE)
}

.ml_ptc_db_tags <- function(cfg = list()) {
  raw <- unique(vapply(.ml_ptc_db_slots(), function(s) .ml_ptc_slot_tag(cfg, s), character(1L)))
  tags <- unique(unlist(lapply(raw[nzchar(raw)], .ml_ptc_tag_aliases), use.names = FALSE))
  tags[nzchar(tags)]
}

.ml_ptc_normalize_bn <- function(bn, cfg = list()) {
  bn <- as.character(bn)[1L]
  tags <- .ml_ptc_db_tags(cfg)
  tags <- tags[order(-nchar(tags), tags)]
  changed <- TRUE
  while (isTRUE(changed)) {
    before <- bn
    for (tag in tags) {
      flex <- .ml_ptc_tag_flex_re(tag)
      if (!nzchar(flex)) next
      bn <- sub(paste0("^", flex, "[ _]"), "", bn, ignore.case = TRUE, perl = TRUE)
      bn <- gsub(paste0("-(?:", flex, ")+(?=\\.)"), "", bn, ignore.case = TRUE, perl = TRUE)
    }
    changed <- !identical(bn, before)
  }
  bn
}

.ml_ptc_strip_db_tag <- function(bn, cfg) {
  .ml_ptc_normalize_bn(bn, cfg)
}

.ml_ptc_extract_db_label <- function(basename, cfg) {
  bn <- as.character(basename)[1L]
  tags <- .ml_ptc_db_tags(cfg)
  tags <- tags[order(-nchar(tags), tags)]
  for (tag in tags) {
    flex <- .ml_ptc_tag_flex_re(tag)
    if (!nzchar(flex)) next
    if (grepl(paste0("^", flex, "[ _]"), bn, ignore.case = TRUE, perl = TRUE) ||
        grepl(paste0("-(?:", flex, ")+\\."), bn, ignore.case = TRUE, perl = TRUE)) {
      return(.ml_ptc_canonical_db_tag(tag, cfg))
    }
  }
  "Combined"
}

# 分库 Tables 目录名 / 无后缀主库表 → 回填库标签（禁止只标次库）
.ml_ptc_infer_dir_db_tag <- function(tables_dir, cfg = list()) {
  if (is.null(tables_dir) || !nzchar(as.character(tables_dir)[1L])) {
    return(NA_character_)
  }
  parent <- basename(dirname(as.character(tables_dir)[1L]))
  for (slot in .ml_ptc_db_slots()) {
    st <- .ml_ptc_slot_tag(cfg, slot)
    aliases <- c(.ml_ptc_tag_aliases(st), gsub(" ", "_", st, fixed = TRUE))
    if (tolower(parent) %in% tolower(aliases)) {
      return(.ml_ptc_canonical_db_tag(st, cfg))
    }
  }
  NA_character_
}

.ml_ptc_resolve_db_tag <- function(bn, cfg, tables_dir = NULL) {
  tag <- .ml_ptc_extract_db_label(bn, cfg)
  if (!identical(tag, "Combined") && nzchar(tag)) {
    return(.ml_ptc_canonical_db_tag(tag, cfg))
  }
  dir_tag <- .ml_ptc_infer_dir_db_tag(tables_dir, cfg)
  if (!is.na(dir_tag) && nzchar(dir_tag)) return(dir_tag)
  ## 指标根无后缀表 = 主库（merge=FALSE 时两侧都必须带库名）
  if (!.ml_ptc_should_merge_dual_db_tables(cfg)) {
    pri <- .ml_ptc_slot_tag(cfg, "nhanes")
    if (nzchar(pri)) return(.ml_ptc_canonical_db_tag(pri, cfg))
  }
  "Combined"
}

# 双库不合并时：Table 2-NHANES. / Table 2-MIMIC IV.（主次库都标）
.ml_ptc_table_db_infix <- function(cfg, db_tag) {
  if (.ml_ptc_should_merge_dual_db_tables(cfg) || identical(db_tag, "Combined") ||
      !nzchar(db_tag)) {
    return("")
  }
  paste0("-", .ml_ptc_canonical_db_tag(db_tag, cfg))
}

# 单库已有 Table 1 / Table S4 编号时，只去掉库名标签，不再套一层 Table SX。
# 例：Table S3. Table 1-MIMIC IV. Baseline.xlsx → Table 1. Baseline.xlsx
#     Table 2-MIMIC IV-MIMIC IV. Logistic.xlsx → Table 2. Logistic.xlsx
.ml_ptc_clean_pub_basename <- function(bn) {
  bn <- as.character(bn)[1L]
  if (!nzchar(bn)) return(bn)
  m <- regexec(
    "^(Table|Figure) S?[0-9]+\\. ((Table|Figure) S?[0-9]+[-.].+)$",
    bn
  )
  hit <- regmatches(bn, m)[[1L]]
  if (length(hit) >= 3L) bn <- hit[[2L]]
  sub(
    "^(Table S?[0-9]+|Figure S?[0-9]+)(-[^.]+)?\\.[[:space:]]*",
    "\\1. ",
    bn
  )
}

.ml_ptc_supp_table_no <- function(n) {
  n <- as.integer(n)[1L]
  if (!is.finite(n) || n < 1L) return("S1")
  paste0("S", n)
}

.ml_ptc_rename_keep_original_numbers <- function(tables_dir) {
  files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  n <- 0L
  for (f in files) {
    new_bn <- .ml_ptc_clean_pub_basename(basename(f))
    new_bn <- sub("^Table S([1-9])\\.", "Table S0\\1.", new_bn)
    if (identical(new_bn, basename(f))) next
    dest <- file.path(tables_dir, new_bn)
    if (file.exists(dest) && !identical(normalizePath(f, winslash = "/"), normalizePath(dest, winslash = "/", mustWork = FALSE))) {
      unlink(dest)
    }
    if (isTRUE(file.rename(f, dest))) n <- n + 1L
  }
  invisible(n)
}

.ml_ptc_winning_logistic_scheme <- function(cfg = list(), files = character()) {
  for (k in list(
    cfg$results$logistic_grouping_scheme,
    cfg$logistic$grouping_scheme,
    (cfg$ml_batch %||% list())$logistic_grouping_scheme,
    (cfg$incidence_batch %||% list())$logistic_grouping_scheme,
    (cfg$ml_batch %||% list())$pub_logistic_scheme
  )) {
    s <- tolower(trimws(as.character(k %||% "")[1L]))
    if (nzchar(s) && s %in% c("quartile", "tertile", "binary", "quintile")) return(s)
  }
  bns <- basename(as.character(files))
  logi <- bns[
    grepl("Logistic regression", bns, ignore.case = TRUE) &
      !grepl("RCS", bns, ignore.case = TRUE)
  ]
  t2 <- logi[grepl("^Table 2([.-]|$)", logi)]
  pick <- if (length(t2)) t2[[1L]] else if (length(logi)) logi[[1L]] else ""
  for (sch in c("quintile", "quartile", "tertile", "binary")) {
    if (grepl(sch, pick, ignore.case = TRUE)) return(sch)
  }
  for (sch in c("quartile", "tertile", "binary", "quintile")) {
    if (any(grepl(sch, logi, ignore.case = TRUE))) return(sch)
  }
  ""
}

.ml_ptc_is_dev_ext <- function(cfg = list()) {
  st <- tolower(trimws(as.character((cfg$project %||% list())$study_type %||% "")[1L]))
  if (!identical(st, "incidence")) return(FALSE)
  split <- as.character(
    (cfg$ml_batch %||% list())$split_mode %||%
      (cfg$incidence_batch %||% list())$split_mode %||% ""
  )[1L]
  identical(split, "dev_internal_ext")
}

.ml_ptc_logistic_scheme_of <- function(bn) {
  bn <- tolower(as.character(bn)[1L])
  if (grepl("quintile", bn)) return("quintile")
  if (grepl("quartile", bn)) return("quartile")
  if (grepl("tertile", bn)) return("tertile")
  if (grepl("binary", bn)) return("binary")
  ""
}

.ml_ptc_classify_table <- function(basename, cfg = NULL, files = character()) {
  bn <- .ml_ptc_normalize_bn(basename, cfg)
  core <- bn
  core_l <- tolower(core)
  win <- .ml_ptc_winning_logistic_scheme(cfg %||% list(), files)

  if (grepl("Cox quartile|\\(Cox quartile\\)", core, ignore.case = TRUE)) {
    return("t2_cox_quartile")
  }
  if (grepl("Cox tertile|\\(Cox tertile\\)", core, ignore.case = TRUE)) {
    return("t3_cox_tertile")
  }
  if (grepl("Cox binary|\\(Cox binary\\)|Multivariable Cox", core, ignore.case = TRUE)) {
    return("t4_cox_binary")
  }
  if (grepl("Cox regression", core, fixed = TRUE) &&
      grepl("quartile|tertile|binary", core_l, ignore.case = TRUE)) {
    if (grepl("quartile", core_l, ignore.case = TRUE)) return("t2_cox_quartile")
    if (grepl("tertile", core_l, ignore.case = TRUE)) return("t3_cox_tertile")
    return("t4_cox_binary")
  }
  ## 预后 ML：胜出分位 Cox 常导出为 “The Association Between …”（无 Cox quartile 字样）
  ## → 必须进主文 Table 2，不能掉进 S 附表
  assoc <- tolower(trimws(as.character(
    (cfg %||% list())$ml_batch$assoc_model %||%
      (cfg %||% list())$assoc_model %||% ""
  )[1L]))
  # combo_loop 的核心主暴露是双指标中位数高低交叉形成的 Group1–4；
  # 其联合 Cox 表优先占主文 Table 2，单指标分位 Cox 留作补充。
  if (identical(assoc, "cox") &&
      grepl("Joint association of", core, ignore.case = TRUE)) {
    return("t2_cox_quartile")
  }
  if (identical(assoc, "cox") &&
      grepl("The Association Between", core, ignore.case = TRUE) &&
      !grepl("Sensitivity analysis", core, ignore.case = TRUE) &&
      !grepl("RCS", core, ignore.case = TRUE)) {
    ## 仅闸门胜出主表（通常 Table 2）进 T2；tertile/binary 同名产物丢弃，避免冲掉 ML T3/T4
    if (grepl("^Table 3([.-]|$)|^Table 4([.-]|$)", bn, ignore.case = TRUE) ||
        grepl("tertile|三分|binary|二分", core_l)) {
      return("drop")
    }
    return("t2_cox_quartile")
  }
  ## Table 1-库名. Baseline …（normalize 前）或无 Table 前缀的基线特征表
  if (grepl("Baseline characteristics of", core, ignore.case = TRUE) &&
      !grepl("before and after|imputation|training and validation|Q1|Q2|quartile|tertile",
             core_l, ignore.case = TRUE)) {
    return("t1_baseline")
  }
  ## 发病 logistic：仅保留闸门胜出分位为主表；分类暴露无分位字样也算 Table 2
  if (grepl("Logistic regression", core, ignore.case = TRUE) &&
      !grepl("Weighted", core, fixed = TRUE) &&
      !grepl("RCS|screen", core_l, ignore.case = TRUE)) {
    sch <- .ml_ptc_logistic_scheme_of(core)
    if (nzchar(win) && nzchar(sch) && !identical(sch, win)) return("drop")
    if (grepl("quartile|tertile|binary|quintile", core_l) ||
        grepl("Logistic regression of", core, ignore.case = TRUE)) {
      return("t2_logistic")
    }
  }
  if (grepl("ML performance wide", core, ignore.case = TRUE) &&
      grepl("external", core_l)) {
    return("t5_ml_ext")
  }
  if (grepl("ML performance wide training", core, fixed = TRUE)) return("t3_ml_train")
  if (grepl("ML performance wide validation", core, fixed = TRUE)) return("t4_ml_val")
  ## 兼容旧编号角色名
  if (grepl("ML performance wide training", core, ignore.case = TRUE)) return("t3_ml_train")
  if (grepl("ML performance wide validation", core, ignore.case = TRUE)) return("t4_ml_val")
  if (grepl("Hyperparameters", core, ignore.case = TRUE)) return("s_hyper")
  if (grepl("Calibration intercept and slope", core, ignore.case = TRUE)) {
    return("s_calibr")
  }
  ## 亚组数值表与森林图重复，不进发表 Tables（Fig 亚组已覆盖）
  if (grepl("Subgroup Analysis", core, ignore.case = TRUE)) return("drop")
  if (grepl("before and after.*imputation|Comparison of characteristics before and after",
            core_l, ignore.case = TRUE)) {
    if (.ml_ptc_is_dev_ext(cfg %||% list())) {
      if (grepl("training", core_l)) return("s_imputation_train")
      if (grepl("external", core_l)) return("s_imputation_ext")
      if (grepl("internal|validation", core_l)) return("s_imputation_val")
      ## 无 train/val 字样的第二张插补表按内验
      return("s_imputation_val")
    }
    if (grepl("validation", core_l)) return("s_imputation_val")
    if (grepl("training", core_l)) return("s_imputation_train")
    ## 标题已剥掉 train/val：按 S01/S1 vs S02/S2 约定（S1=train, S2=val）
    if (grepl("Table S0?2[.-]", bn, ignore.case = TRUE) ||
        grepl("^Table S2[.-]", bn, ignore.case = TRUE)) {
      return("s_imputation_val")
    }
    return("s_imputation_train")
  }
  if (grepl("Univariate Regression", core, ignore.case = TRUE)) return("s_univariate")
  if (grepl("Multicollinearity", core, ignore.case = TRUE) &&
      grepl("screen|univariate p|VIF screen", core_l, ignore.case = TRUE)) {
    if (.ml_ptc_is_dev_ext(cfg %||% list())) {
      if (grepl("external", core_l)) return("s_vif_ext")
      if (grepl("internal", core_l)) return("s_vif_val")
      if (grepl("training", core_l)) return("s_vif_train")
      if (grepl("validation", core_l)) return("s_vif_val")
      return("s_vif_train")
    }
    return("s_vif_screen")
  }
  ## dev_internal_ext 发表口径（对齐 14_肌少症/sdLDL_C）：多因素筛选表与
  ## final-VIF 属过程表，不进指标汇总 Tables；非 dev_ext 维持原附表角色。
  if (grepl("Multivariable Regression", core, ignore.case = TRUE)) {
    return(if (.ml_ptc_is_dev_ext(cfg %||% list())) "drop" else "s_multivariate")
  }
  if (grepl("Multicollinearity", core, ignore.case = TRUE) &&
      grepl("final|multivariate p", core_l, ignore.case = TRUE)) {
    return(if (.ml_ptc_is_dev_ext(cfg %||% list())) "drop" else "s_vif_final")
  }
  ## dev_ext：final-VIF 过程表常无 “final” 字样（裸 “Multicollinearity Analysis”），
  ## 非 screen 的一律视为过程表剔除，与 14_肌少症 附表清单对齐。
  if (grepl("Multicollinearity", core, ignore.case = TRUE) &&
      !grepl("screen|univariate p", core_l, ignore.case = TRUE) &&
      .ml_ptc_is_dev_ext(cfg %||% list())) {
    return("drop")
  }
  if (grepl("Normality test", core, ignore.case = TRUE)) {
    if (.ml_ptc_is_dev_ext(cfg %||% list())) return("drop")
    return("s_normality")
  }
  if (grepl("by training and validation|training and internal validation", core_l, ignore.case = TRUE)) {
    ## dev_ext 发表口径（对齐 14_肌少症/sdLDL_C）：train-vs-internal 基线进附表 S 队列
    ## （与外验库 Table 1 → 附表同槽同 S 号），不再占主文 Table 1。
    if (.ml_ptc_is_dev_ext(cfg %||% list())) return("s_extra")
    return("s_train_val_baseline")
  }
  if (grepl("Log-Loss", core, ignore.case = TRUE)) return("s_logloss")
  if (grepl("DeLong", core, ignore.case = TRUE)) {
    if (grepl("external", core_l)) return("s_delong_ext")
    if (grepl("internal", core_l)) return("s_delong_internal")
    if (grepl("validation", core_l)) return("s_delong_val")
    if (grepl("training", core_l)) return("s_delong_train")
    ## S09→train, S10→val（补充表导出顺序）
    if (grepl("Table S0?10[.-]|Table S10[.-]", bn, ignore.case = TRUE)) return("s_delong_val")
    return("s_delong_train")
  }
  if (grepl("NRI|IDI", core, ignore.case = TRUE)) {
    if (grepl("external", core_l)) return("s_nri_ext")
    if (grepl("internal", core_l)) return("s_nri_internal")
    if (grepl("validation", core_l)) return("s_nri_val")
    if (grepl("training", core_l)) return("s_nri_train")
    if (grepl("Table S0?12[.-]|Table S12[.-]", bn, ignore.case = TRUE)) return("s_nri_val")
    return("s_nri_train")
  }
  if (grepl("Weighted logistic regression", core, fixed = TRUE) &&
      grepl("dual-DB unified|\\[dual-DB unified\\]", core, ignore.case = TRUE)) {
    return("t2_logistic")
  }
  if (grepl("Weighted Baseline Characteristics", core, fixed = TRUE)) {
    if (grepl("Q1|Q2|Q3|Q4|T1|T2|T3|quartile|tertile|median|index group|exposure group",
              core_l, ignore.case = TRUE)) {
      return("t2_quantile_baseline")
    }
    return("t1_baseline")
  }
  if (grepl("^Table 1\\.", core) && grepl("Baseline", core, fixed = TRUE)) {
    return("t1_baseline")
  }
  if (grepl("^Table_FeatureSelection_|Table[_ ]ML[_ ]ModelPerformance|train_val_split|_reticulate_export",
            bn, ignore.case = TRUE)) return("drop")
  if (grepl("ROC", bn, ignore.case = TRUE)) return("drop")
  if (grepl("logistic regression", core_l, ignore.case = TRUE) &&
      grepl("screen|RCS", core_l, ignore.case = TRUE)) return("drop")
  "s_extra"
}

.ml_ptc_target_basename <- function(role, src_bn, cfg, s_idx = NULL, db_tag = NULL,
                                    tables_dir = NULL) {
  if (is.null(db_tag) || !nzchar(db_tag)) {
    db_tag <- .ml_ptc_resolve_db_tag(src_bn, cfg, tables_dir = tables_dir)
  }
  db_inf <- .ml_ptc_table_db_infix(cfg, db_tag)
  cap <- .ml_ptc_clean_pub_basename(.ml_ptc_normalize_bn(src_bn, cfg))
  cap <- sub("^Table S?[0-9]+\\.[[:space:]]*", "", cap)
  cap <- sub("\\.xlsx$", "", cap, ignore.case = TRUE)
  if (.ml_ptc_is_dev_ext(cfg) && identical(role, "t1_baseline")) {
    disease <- gsub(
      "_", " ",
      as.character((cfg$project %||% list())$disease %||% "outcome"),
      fixed = TRUE
    )[1L]
    cohort <- if (.ml_ptc_is_secondary_db(db_tag, cfg)) {
      "external validation cohort"
    } else {
      "development cohort"
    }
    cap <- paste0("Baseline characteristics by ", disease, " status (", cohort, ")")
  }
  if (.ml_ptc_is_dev_ext(cfg) && identical(role, "t1_train_val")) {
    cap <- "Baseline characteristics: training vs internal validation"
  }
  lg_cfg <- cfg$logistic %||% list()
  ngrp <- as.integer(lg_cfg$manual_n_groups %||% NA_integer_)[1L]
  grouping_mode <- tolower(trimws(as.character(lg_cfg$grouping_mode %||% "")[1L]))
  # manual_n_groups 仅在 grouping_mode="manual" 时生效。模板常残留
  # manual_n_groups=2 而 grouping_mode="auto"；若仍据此改名，会把真实
  # Q1–Q4 quartile 表错误标成 binary（数据内容没变，只有文件名/A1 错）。
  if (identical(role, "t2_logistic") && identical(grouping_mode, "manual") &&
      isTRUE(ngrp == 2L) &&
      grepl("quartile", cap, ignore.case = TRUE)) {
    cap <- sub("quartile", "binary (Yes vs No)", cap, ignore.case = TRUE)
  }
  ## 强制清晰 train/val 标题（防止历史剥标签残留）
  cap_fixed <- switch(
    role,
    s_imputation_train = "Baseline characteristics before and after imputation (training set)",
    s_imputation_val = if (.ml_ptc_is_dev_ext(cfg)) {
      "Baseline characteristics before and after imputation (internal validation set)"
    } else {
      "Baseline characteristics before and after imputation (validation set)"
    },
    s_imputation_ext = "Baseline characteristics before and after imputation (external validation set)",
    s_vif_train = "Multicollinearity Analysis VIF screen (training set)",
    s_vif_val = if (.ml_ptc_is_dev_ext(cfg)) {
      "Multicollinearity Analysis VIF screen (internal validation set)"
    } else {
      "Multicollinearity Analysis VIF screen (validation set)"
    },
    s_vif_ext = "Multicollinearity Analysis VIF screen (external validation set)",
    s_vif_screen = if (.ml_ptc_is_dev_ext(cfg)) {
      "Multicollinearity Analysis VIF screen (training set)"
    } else {
      "Multicollinearity Analysis VIF screen"
    },
    s_delong_train = "DeLong tests (training set)",
    s_delong_val = "DeLong tests (validation set)",
    s_delong_internal = "DeLong tests (internal validation set)",
    s_delong_ext = "DeLong tests (external validation set)",
    s_nri_train = "NRI and IDI (training set)",
    s_nri_val = "NRI and IDI (validation set)",
    s_nri_internal = "NRI and IDI (internal validation set)",
    s_nri_ext = "NRI and IDI (external validation set)",
    s_logloss = if (.ml_ptc_is_dev_ext(cfg)) {
      "Log-Loss (training, internal validation, and external validation)"
    } else {
      "Log-Loss (training and validation sets)"
    },
    s_hyper = "Hyperparameters for machine learning models",
    s_calibr = "Calibration intercept and slope on validation set",
    t3_ml_train = "ML performance wide training",
    t4_ml_val = "ML performance wide validation",
    t5_ml_ext = "ML performance wide external validation",
    NULL
  )
  if (!is.null(cap_fixed)) cap <- cap_fixed
  ## dev_ext s_extra：train-vs-internal 基线标题统一为参考口径。
  ## 参考（Linux 跑的 14_肌少症）用 “Baseline characteristics: training vs …”，
  ## 但 Windows 文件名禁止冒号 → 语义等价的连字符版。
  if (identical(role, "s_extra") &&
      grepl("training and internal validation|training vs internal", cap, ignore.case = TRUE)) {
    cap <- "Baseline characteristics - training vs internal validation"
  }
  if (!is.null(s_idx)) {
    return(paste0("Table ", .ml_ptc_supp_table_no(s_idx), db_inf, ". ", cap, ".xlsx"))
  }
  switch(role,
    t1_baseline = paste0("Table 1", db_inf, ". ", cap, ".xlsx"),
    t1_train_val = paste0("Table 1", db_inf, ". ", cap, ".xlsx"),
    t2_logistic = paste0("Table 2", db_inf, ". ", cap, ".xlsx"),
    t2_cox_quartile = paste0("Table 2", db_inf, ". ", cap, ".xlsx"),
    t3_ml_train = paste0("Table 3", db_inf, ". ", cap, ".xlsx"),
    t4_ml_val = paste0("Table 4", db_inf, ". ", cap, ".xlsx"),
    t5_ml_ext = paste0("Table 5", db_inf, ". ", cap, ".xlsx"),
    t2_quantile_baseline = paste0("Table 2", db_inf, ". ", cap, ".xlsx"),
    ## 旧角色兼容（双库预后等）
    t3_cox_tertile = paste0("Table 3", db_inf, ". ", cap, ".xlsx"),
    t4_cox_binary = paste0("Table 4", db_inf, ". ", cap, ".xlsx"),
    t5_ml_train = paste0("Table 5", db_inf, ". ML performance wide training.xlsx"),
    t6_ml_val = paste0("Table 6", db_inf, ". ML performance wide validation.xlsx"),
    src_bn
  )
}

.ml_ptc_should_merge_dual_db_tables <- function(cfg = list()) {
  dual <- cfg$dual_db %||% list()
  batch <- cfg$ml_batch %||% cfg$incidence_batch %||% list()
  if ("merge_dual_db_tables" %in% names(dual)) {
    return(isTRUE(dual$merge_dual_db_tables))
  }
  if ("merge_dual_db_tables" %in% names(batch)) {
    return(isTRUE(batch$merge_dual_db_tables))
  }
  TRUE
}

#' 汇总 Table 1 是否只留主库（外验基线改附表）
.ml_ptc_table1_primary_only <- function(cfg = list()) {
  dual <- cfg$dual_db %||% list()
  isTRUE(dual$aggregate_table1_primary_only %||% FALSE)
}

.ml_ptc_primary_db_label <- function(cfg = list()) {
  dual <- cfg$dual_db %||% list()
  as.character((dual$primary %||% list())$name %||% "primary")[1L]
}

.ml_ptc_merge_role <- function(role, cfg = list()) {
  if (!.ml_ptc_should_merge_dual_db_tables(cfg)) return(FALSE)
  role %in% c("t3_ml_train", "t4_ml_val", "t5_ml_train", "t6_ml_val", "s_hyper", "s6_hyper")
}

.ml_ptc_read_xlsx_df <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("ml_dual_pub_table_curate: 需要 openxlsx 包。", call. = FALSE)
  }
  as.data.frame(openxlsx::read.xlsx(path), stringsAsFactors = FALSE, check.names = FALSE)
}

.ml_ptc_merge_xlsx_files <- function(files, db_labels, out_path, title = NULL) {
  parts <- list()
  for (i in seq_along(files)) {
    df <- .ml_ptc_read_xlsx_df(files[[i]])
    if (nrow(df)) {
      df$Database <- db_labels[[i]]
      parts[[length(parts) + 1L]] <- df
    }
  }
  if (!length(parts)) return(invisible(FALSE))
  if (requireNamespace("dplyr", quietly = TRUE)) {
    merged <- dplyr::bind_rows(parts)
  } else {
    merged <- do.call(rbind, parts)
  }
  cols <- c("Database", setdiff(names(merged), "Database"))
  merged <- merged[, cols, drop = FALSE]
  if (!exists("export_sci_table", mode = "function")) {
    openxlsx::write.xlsx(merged, out_path, overwrite = TRUE)
  } else {
    export_sci_table(merged, out_path, title = title %||% sub("\\.xlsx$", "", basename(out_path)))
  }
  invisible(TRUE)
}

## 三集表（Log-Loss / DeLong / NRI）不按库名分副本：无编号 Table S. 与 S6–S12 同角色
.ml_ptc_role_ignore_db <- function(role) {
  role %in% c(
    "s_logloss",
    "s_delong_train", "s_delong_internal", "s_delong_ext", "s_delong_val",
    "s_nri_train", "s_nri_internal", "s_nri_ext", "s_nri_val"
  )
}

.ml_ptc_dedupe_files_by_role_db <- function(files, cfg = list()) {
  if (length(files) <= 1L) return(files)
  roles <- vapply(
    basename(files),
    function(bn) .ml_ptc_classify_table(bn, cfg = cfg, files = files),
    character(1L)
  )
  dbs <- vapply(
    basename(files),
    function(bn) .ml_ptc_resolve_db_tag(bn, cfg),
    character(1L)
  )
  dbs[.ml_ptc_role_ignore_db(roles)] <- ""
  mt <- suppressWarnings(file.info(files)$mtime)
  mt_num <- if (inherits(mt, "POSIXt")) as.numeric(mt) else as.numeric(mt)
  mt_num[is.na(mt_num)] <- 0
  ord <- order(roles, dbs, -mt_num, files)
  files <- files[ord]
  roles <- roles[ord]
  dbs <- dbs[ord]
  keep <- !duplicated(paste(roles, dbs, sep = "\x01"))
  files[keep]
}

incidence_batch_curate_ml_pub_tables <- function(tables_dir, cfg = list()) {
  if (!dir.exists(tables_dir)) return(invisible(0L))
  all_files <- list.files(tables_dir, pattern = "\\.xlsx$", full.names = TRUE, ignore.case = TRUE)
  if (!length(all_files)) return(invisible(0L))
  files <- .ml_ptc_dedupe_files_by_role_db(all_files, cfg)
  drop_dup <- setdiff(all_files, files)
  if (length(drop_dup)) {
    unlink(drop_dup)
    cli::cli_alert_info(
      "ML 汇总表去重删除 {length(drop_dup)} 张同角色旧副本: {.file {basename(tables_dir)}}"
    )
  }

  ## 单库/双库统一：按角色 drop 非胜出分位 → 主表 1–4 顺延 → 附表 S 连续
  roles <- vapply(
    basename(files),
    function(bn) .ml_ptc_classify_table(bn, cfg = cfg, files = files),
    character(1L)
  )
  drop_idx <- roles == "drop"
  if (any(drop_idx)) {
    unlink(files[drop_idx])
    cli::cli_alert_info(
      "ML 汇总表删除非发表项 {sum(drop_idx)} 张（含非胜出分位）: {.file {basename(tables_dir)}}"
    )
    files <- files[!drop_idx]
    roles <- roles[!drop_idx]
  }
  if (!length(files)) return(invisible(sum(drop_idx)))

  keyed <- split(files, roles)
  renames <- list()
  merged_out <- list()

  main_order <- c(
    "t1_baseline", "t1_train_val", "t2_logistic", "t2_cox_quartile", "t2_quantile_baseline",
    "t3_ml_train", "t4_ml_val", "t5_ml_ext",
    "t3_cox_tertile", "t4_cox_binary", "t5_ml_train", "t6_ml_val"
  )
  supp_order <- if (.ml_ptc_is_dev_ext(cfg)) {
    c(
      "s_imputation_train", "s_imputation_val", "s_imputation_ext", "s_imputation",
      "s_univariate",
      "s_vif_train", "s_vif_val", "s_vif_ext", "s_vif_screen",
      "s_multivariate", "s_vif_final",
      "s_hyper", "s_calibr", "s_logloss",
      "s_delong_train", "s_delong_internal", "s_delong_ext", "s_delong_val",
      "s_nri_train", "s_nri_internal", "s_nri_ext", "s_nri_val",
      "s_extra"
    )
  } else {
    c(
      "s_imputation_train", "s_imputation_val", "s_normality", "s_train_val_baseline",
      "s_univariate", "s_vif_screen", "s_multivariate", "s_vif_final",
      "s_hyper", "s_calibr", "s_logloss",
      "s_delong_train", "s_delong_val", "s_nri_train", "s_nri_val",
      "s_extra"
    )
  }

  for (role in main_order) {
    grp <- keyed[[role]]
    if (is.null(grp) || !length(grp)) next
    src_bn <- basename(grp[[1L]])
    ## Table 1：主库/外验设计下汇总只留主库一张；外验基线改入附表
    if (identical(role, "t1_baseline") && .ml_ptc_table1_primary_only(cfg) && length(grp) >= 1L) {
      pri <- .ml_ptc_canonical_db_tag(.ml_ptc_primary_db_label(cfg), cfg)
      dbs <- vapply(
        basename(grp),
        function(bn) .ml_ptc_resolve_db_tag(bn, cfg, tables_dir = tables_dir),
        character(1L)
      )
      pri_hit <- grp[tolower(dbs) == tolower(pri)]
      sec_hit <- setdiff(grp, pri_hit)
      if (!length(pri_hit)) pri_hit <- grp[[1L]]
      # 无库名标签：Table 1. Baseline ...
      tgt_bn <- paste0(
        "Table 1. ",
        sub("^Table 1[^.]*\\.[[:space:]]*", "",
            .ml_ptc_clean_pub_basename(.ml_ptc_normalize_bn(basename(pri_hit[[1L]]), cfg)))
      )
      tgt_bn <- sub("\\.xlsx$", "", tgt_bn, ignore.case = TRUE)
      if (!grepl("\\.xlsx$", tgt_bn, ignore.case = TRUE)) tgt_bn <- paste0(tgt_bn, ".xlsx")
      renames[[pri_hit[[1L]]]] <- file.path(tables_dir, tgt_bn)
      if (length(pri_hit) > 1L) unlink(setdiff(pri_hit, pri_hit[[1L]]))
      if (length(sec_hit)) {
        # 外验 Table 1 → 附表（稍后按 s_extra 连续编号）；暂挂 keyed$s_extra
        keyed$s_extra <- c(keyed$s_extra %||% character(0), sec_hit)
      }
      next
    }
    if (.ml_ptc_merge_role(role, cfg) && length(grp) >= 2L) {
      tgt_bn <- .ml_ptc_target_basename(role, src_bn, cfg)
      tgt <- file.path(tables_dir, tgt_bn)
      db_labels <- vapply(
        basename(grp),
        function(bn) .ml_ptc_resolve_db_tag(bn, cfg, tables_dir = tables_dir),
        character(1L)
      )
      ok <- .ml_ptc_merge_xlsx_files(grp, db_labels, tgt, title = sub("\\.xlsx$", "", tgt_bn))
      if (isTRUE(ok)) {
        merged_out[[tgt]] <- grp
        unlink(grp)
      } else {
        renames[[grp[[1L]]]] <- tgt
      }
    } else {
      used <- character(0)
      for (f in grp) {
        db_tag <- .ml_ptc_resolve_db_tag(basename(f), cfg, tables_dir = tables_dir)
        tgt <- file.path(
          tables_dir,
          .ml_ptc_target_basename(
            role, basename(f), cfg, db_tag = db_tag, tables_dir = tables_dir
          )
        )
        if (tgt %in% used) next
        renames[[f]] <- tgt
        used <- c(used, tgt)
      }
      drop_extra <- setdiff(grp, names(renames))
      if (length(drop_extra)) unlink(drop_extra)
    }
  }

  s_i <- 0L
  ## 开发/内验/外验三张插补表共用 S1
  if (.ml_ptc_is_dev_ext(cfg)) {
    imp_roles <- c("s_imputation_train", "s_imputation_val", "s_imputation_ext", "s_imputation")
    imp_files <- unique(unlist(keyed[imp_roles], use.names = FALSE))
    imp_files <- as.character(imp_files %||% character(0))
    imp_files <- imp_files[nzchar(imp_files) & file.exists(imp_files)]
    if (length(imp_files)) {
      s_i <- 1L
      used_tgt <- character(0)
      for (f in imp_files) {
        role_f <- .ml_ptc_classify_table(basename(f), cfg = cfg, files = files)
        db_tag <- .ml_ptc_resolve_db_tag(basename(f), cfg, tables_dir = tables_dir)
        role_f <- .ml_ptc_dev_ext_force_ext(role_f, db_tag, cfg)
        tgt <- file.path(
          tables_dir,
          .ml_ptc_target_basename(
            role_f, basename(f), cfg, s_idx = s_i, db_tag = db_tag, tables_dir = tables_dir
          )
        )
        if (tgt %in% used_tgt) next
        renames[[f]] <- tgt
        used_tgt <- c(used_tgt, tgt)
      }
      drop_extra <- setdiff(imp_files, names(renames))
      if (length(drop_extra)) unlink(drop_extra)
    }
    supp_order <- setdiff(
      supp_order,
      c("s_imputation_train", "s_imputation_val", "s_imputation_ext", "s_imputation")
    )
  }
  vif_group <- c("s_vif_train", "s_vif_val", "s_vif_ext", "s_vif_screen")
  vif_shared_done <- FALSE
  for (role in supp_order) {
    if (.ml_ptc_is_dev_ext(cfg) && role %in% vif_group) {
      if (isTRUE(vif_shared_done)) next
      vif_shared_done <- TRUE
      vif_files <- unique(unlist(keyed[vif_group], use.names = FALSE))
      vif_files <- as.character(vif_files %||% character(0))
      vif_files <- vif_files[nzchar(vif_files) & file.exists(vif_files)]
      if (!length(vif_files)) next
      s_i <- s_i + 1L
      used_tgt <- character(0)
      for (f in vif_files) {
        role_f <- .ml_ptc_classify_table(basename(f), cfg = cfg, files = files)
        db_tag <- .ml_ptc_resolve_db_tag(basename(f), cfg, tables_dir = tables_dir)
        role_f <- .ml_ptc_dev_ext_force_ext(role_f, db_tag, cfg)
        tgt <- file.path(
          tables_dir,
          .ml_ptc_target_basename(
            role_f, basename(f), cfg, s_idx = s_i, db_tag = db_tag, tables_dir = tables_dir
          )
        )
        if (tgt %in% used_tgt) next
        renames[[f]] <- tgt
        used_tgt <- c(used_tgt, tgt)
      }
      drop_extra <- setdiff(vif_files, names(renames))
      if (length(drop_extra)) unlink(drop_extra)
      next
    }
    grp <- keyed[[role]]
    if (is.null(grp) || !length(grp)) next
    if (identical(role, "s_extra")) {
      grp <- grp[order(basename(grp))]
    }
    ## 双库同角色共用一个 S 号：Table S1-NHANES / Table S1-CHARLS
    s_i <- s_i + 1L
    used_tgt <- character(0)
    for (f in grp) {
      db_tag <- .ml_ptc_resolve_db_tag(basename(f), cfg, tables_dir = tables_dir)
      tgt <- file.path(
        tables_dir,
        .ml_ptc_target_basename(
          role, basename(f), cfg, s_idx = s_i, db_tag = db_tag, tables_dir = tables_dir
        )
      )
      if (tgt %in% used_tgt) next
      renames[[f]] <- tgt
      used_tgt <- c(used_tgt, tgt)
    }
    drop_extra <- setdiff(grp, names(renames))
    if (length(drop_extra)) unlink(drop_extra)
  }

  if (!length(renames)) {
    cli::cli_alert_info("ML 汇总表已整理（无需重命名）: {.file {basename(tables_dir)}}")
    return(invisible(length(merged_out)))
  }

  tmp_map <- list()
  i <- 0L
  for (old in names(renames)) {
    i <- i + 1L
    tmp <- file.path(tables_dir, sprintf(".ml_tbl_curate_%03d.xlsx", i))
    if (file.exists(tmp)) unlink(tmp)
    if (!file.exists(old)) next
    file.rename(old, tmp)
    tmp_map[[renames[[old]]]] <- tmp
  }
  for (new in names(tmp_map)) {
    if (file.exists(new)) unlink(new)
    file.rename(tmp_map[[new]], new)
    ## 同步表内标题为文件名 stem
    if (exists("incidence_batch_write_xlsx_title", mode = "function")) {
      incidence_batch_write_xlsx_title(new, sub("\\.xlsx$", "", basename(new)))
    }
  }

  n_merged <- length(merged_out)
  cli::cli_alert_success(
    paste0(
      "ML 汇总表已顺延（T1 基线 → T2 胜出 logistic → T3/T4 ML；附表 S 连续且含 train/val）: ",
      basename(tables_dir), "（合并 ", n_merged, "）"
    )
  )
  invisible(n_merged + length(renames))
}

incidence_batch_collect_index_shiny_outputs <- function(index_root, cfg, db_seq = character(0)) {
  if (is.null(index_root) || !nzchar(index_root) || !dir.exists(index_root)) {
    return(invisible(0L))
  }
  db_seq <- unique(as.character(db_seq[nzchar(as.character(db_seq))]))
  if (!length(db_seq)) return(invisible(0L))

  shiny_root <- file.path(index_root, "Shiny")
  dir.create(shiny_root, recursive = TRUE, showWarnings = FALSE)
  n <- 0L

  for (db in db_seq) {
    db_dir <- if (exists("dual_db_slot_path_name", mode = "function")) {
      dual_db_slot_path_name(cfg, db)
    } else {
      db
    }
    db_out <- file.path(index_root, db_dir)
    if (!dir.exists(db_out)) next
    all_dirs <- list.dirs(db_out, recursive = TRUE, full.names = TRUE)
    hits <- all_dirs[grepl("ShinyApp$", basename(all_dirs), ignore.case = TRUE)]
    if (!length(hits)) next
    src <- hits[[1L]]
    dest <- file.path(shiny_root, db_dir)
    dir.create(dest, recursive = TRUE, showWarnings = FALSE)
    if (dir.exists(file.path(dest, "ShinyApp"))) {
      unlink(file.path(dest, "ShinyApp"), recursive = TRUE, force = TRUE)
    }
    ok <- file.copy(src, dest, recursive = TRUE, overwrite = TRUE)
    if (isTRUE(ok)) {
      n <- n + 1L
      cli::cli_alert_info("Shiny 已汇总: {.file {file.path(dest, 'ShinyApp')}}")
    } else {
      cli::cli_alert_warning("Shiny 汇总失败 [{db_dir}]: {.file {src}}")
    }
  }
  if (n > 0L) {
    cli::cli_alert_success("Shiny 产出已写入 {.file {shiny_root}}（{n} 个库）")
  }
  invisible(n)
}
