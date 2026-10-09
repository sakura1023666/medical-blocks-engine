###############################################################################
#  pipeline_capability_layer.R — 通用能力层
#  MI 质量门控 / 分析队列审计 / SHAP 选样说明 / 中介亚组路由 / 敏感性默认场景
###############################################################################

# ── MI 质量门控：Table S1 插补前后 P<阈值 的变量排除 ─────────────────────────

pipeline_mi_quality_protect_vars <- function(cfg) {
  cfg <- cfg %||% list()
  data_cfg <- cfg$data %||% list()
  surv <- cfg$survival %||% list()
  inc <- cfg$incidence %||% list()
  pred <- cfg$prediction %||% list()
  imp <- cfg$imputation %||% list()
  logi <- cfg$logistic %||% list()

  protect <- unique(c(
    as.character(data_cfg$id_column %||% character(0)),
    as.character(data_cfg$strip_id_columns_after_imputation %||% character(0)),
    as.character(data_cfg$outcome_column %||% character(0)),
    as.character(inc$outcome_var %||% character(0)),
    as.character(surv$time_var %||% character(0)),
    as.character(surv$event_var %||% character(0)),
    as.character(surv$index_var %||% character(0)),
    as.character(inc$index_var %||% character(0)),
    as.character(logi$index_var %||% character(0)),
    as.character(pred$index_vars %||% character(0)),
    as.character(imp$mi_quality_protect_vars %||% character(0)),
    as.character(imp$mi_quality_force_keep_vars %||% character(0)),
    # 亚组分层列不得因 MI 质量闸门被整列剔除（森林缺层）；
    # analysis_exclusion$protect_vars（展示保列）与 subgroup$required 同源
    as.character((cfg$analysis_exclusion %||% list())$protect_vars %||% character(0)),
    as.character((cfg$subgroup %||% list())$required_subgroup_vars %||% character(0)),
    "Group", "ID", "Pt_ID", "SEQN", "subject_id",
    "new_weight", "WTINT2YR", "WTMEC2YR", "SDMVSTRA", "SDMVPSU"
  ))
  protect[nzchar(protect)]
}

pipeline_parse_table_s1_pvalue <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x) || identical(x, "NA") || identical(tolower(x), "na")) return(NA_real_)
  if (grepl("^<", x)) {
    num <- suppressWarnings(as.numeric(sub("^<", "", x)))
    if (is.finite(num)) return(num / 10)
    return(0.0005)
  }
  suppressWarnings(as.numeric(x))
}

pipeline_mi_quality_from_table_s1 <- function(tab_s1, cfg, raw_p_map = NULL) {
  p_thr <- as.numeric((cfg$imputation %||% list())$mi_quality_p_threshold %||% 0.05)[1L]
  if (!is.finite(p_thr) || p_thr <= 0) p_thr <- 0.05
  enable <- isTRUE((cfg$imputation %||% list())$mi_quality_exclude_enable %||% TRUE)
  if (!enable) {
    return(list(exclude = character(0), protected = character(0), details = data.frame()))
  }
  if (is.null(tab_s1) || !is.data.frame(tab_s1) || !nrow(tab_s1)) {
    return(list(exclude = character(0), protected = character(0), details = data.frame()))
  }

  protect <- pipeline_mi_quality_protect_vars(cfg)
  var_col <- if ("Variable" %in% names(tab_s1)) "Variable" else names(tab_s1)[1L]
  p_col <- if ("P value" %in% names(tab_s1)) "P value" else if ("P_value" %in% names(tab_s1)) "P_value" else NULL

  rows <- list()
  for (i in seq_len(nrow(tab_s1))) {
    v_disp <- as.character(tab_s1[[var_col]][i])
    if (!nzchar(v_disp) || grepl("^\\s", v_disp)) next
    # 去掉展示空格，恢复候选原名（先尝试直接，再尝试 underscore 还原）
    v_raw <- gsub(" ", "_", v_disp, fixed = TRUE)
    p_num <- NA_real_
    if (!is.null(raw_p_map) && length(raw_p_map)) {
      if (!is.null(raw_p_map[[v_disp]])) p_num <- as.numeric(raw_p_map[[v_disp]])[1L]
      if (!is.finite(p_num) && !is.null(raw_p_map[[v_raw]])) p_num <- as.numeric(raw_p_map[[v_raw]])[1L]
    }
    if (!is.finite(p_num) && !is.null(p_col)) {
      p_num <- pipeline_parse_table_s1_pvalue(tab_s1[[p_col]][i])
    }
    if (!is.finite(p_num)) next
    rows[[length(rows) + 1L]] <- data.frame(
      variable_display = v_disp,
      variable = v_raw,
      p_value = p_num,
      stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) {
    return(list(exclude = character(0), protected = protect, details = data.frame()))
  }
  det <- do.call(rbind, rows)
  hit <- det$p_value < p_thr
  cand <- unique(as.character(det$variable[hit]))
  # 也把展示名纳入匹配（某些流程永不还原下划线）
  cand <- unique(c(cand, as.character(det$variable_display[hit])))
  cand <- cand[nzchar(cand)]

  protected_hit <- intersect(cand, protect)
  exclude <- setdiff(cand, protect)
  list(
    exclude = unique(exclude),
    protected = unique(protected_hit),
    threshold = p_thr,
    details = det
  )
}

pipeline_apply_mi_quality_to_ctx <- function(ctx, gate) {
  if (is.null(gate)) return(ctx)
  excl <- unique(as.character(gate$exclude %||% character(0)))
  excl <- excl[nzchar(excl)]
  ctx$results$mi_quality_exclude_vars <- excl
  ctx$results$mi_quality_protected_vars <- unique(as.character(gate$protected %||% character(0)))
  ctx$results$mi_quality_p_threshold <- gate$threshold %||% 0.05
  if (!is.null(gate$details) && is.data.frame(gate$details)) {
    ctx$results$mi_quality_details <- gate$details
  }

  if (!length(excl)) {
    cli::cli_alert_info("MI quality gate: 无 P < {ctx$results$mi_quality_p_threshold} 变量需剔除。")
    return(ctx)
  }

  cli::cli_alert_warning(
    "MI quality gate: 插补前后分布变化显著（P < {ctx$results$mi_quality_p_threshold}），后续分析剔除 {length(excl)} 个变量: {paste(excl, collapse = ', ')}"
  )
  if (length(ctx$results$mi_quality_protected_vars)) {
    cli::cli_alert_info(
      "MI quality gate: 以下显著变化变量因保护规则保留: {paste(ctx$results$mi_quality_protected_vars, collapse = ', ')}"
    )
  }

  cfg <- ctx$config %||% list()
  merge_excl <- function(old) unique(c(as.character(old %||% character(0)), excl))

  if (is.null(cfg$baseline_binary)) cfg$baseline_binary <- list()
  cfg$baseline_binary$exclude_vars <- merge_excl(cfg$baseline_binary$exclude_vars)

  if (is.null(cfg$baseline)) cfg$baseline <- list()
  cfg$baseline$exclude_vars <- merge_excl(cfg$baseline$exclude_vars)

  if (is.null(cfg$univariate_incidence_binary)) cfg$univariate_incidence_binary <- list()
  cfg$univariate_incidence_binary$excluded_predictors <- merge_excl(
    cfg$univariate_incidence_binary$excluded_predictors
  )

  if (is.null(cfg$univariate_prognosis)) cfg$univariate_prognosis <- list()
  cfg$univariate_prognosis$excluded_predictors <- merge_excl(
    cfg$univariate_prognosis$excluded_predictors
  )

  if (is.null(cfg$multicollinearity)) cfg$multicollinearity <- list()
  cfg$multicollinearity$exclude_vars <- merge_excl(cfg$multicollinearity$exclude_vars)

  if (is.null(cfg$feature_selection)) cfg$feature_selection <- list()
  cfg$feature_selection$exclude_vars <- merge_excl(cfg$feature_selection$exclude_vars)

  for (bn in c(
    "feature_selection_lasso", "feature_selection_boruta", "feature_selection_bayesian",
    "feature_selection_random_forest", "feature_selection_bagged_trees",
    "feature_selection_lvq", "feature_selection_consensus"
  )) {
    if (is.null(cfg[[bn]])) cfg[[bn]] <- list()
    cfg[[bn]]$exclude_vars <- merge_excl(cfg[[bn]]$exclude_vars)
  }

  ctx$config <- cfg
  ctx
}

pipeline_drop_mi_quality_cols <- function(data, ctx) {
  if (is.null(data) || !is.data.frame(data)) return(data)
  excl <- unique(as.character(ctx$results$mi_quality_exclude_vars %||% character(0)))
  excl <- excl[nzchar(excl)]
  excl <- intersect(excl, names(data))
  protect <- pipeline_mi_quality_protect_vars(ctx$config %||% list())
  excl <- setdiff(excl, protect)
  if (!length(excl)) return(data)
  data[, setdiff(names(data), excl), drop = FALSE]
}

# ── 稀疏分类列剔除（任一层级 n < min_n 则删整列；默认 20）────────────────
# 在生成 Table/Figure 之前调用（imputation finalize + baseline 入口），全局默认开启。
# 双库模式：对两库取并集锁定删除（任一库稀疏 → 两库 Table 1 都不保留该列）。
# 配置: config$analysis_var_policy = list(
#   drop_sparse_categorical = TRUE, min_categorical_n = 20L, discrete_unique_max = 5L,
#   dual_db_lock = TRUE  # 默认 TRUE；FALSE 则仍按单库各自删除
# )

pipeline_sparse_categorical_policy <- function(cfg) {
  cfg <- cfg %||% list()
  pol <- cfg$analysis_var_policy %||% list()
  imp <- cfg$imputation %||% list()
  enable <- pol$drop_sparse_categorical %||% imp$drop_sparse_categorical %||% TRUE
  min_n <- as.integer(pol$min_categorical_n %||% imp$min_categorical_n %||% 20L)[1L]
  if (!is.finite(min_n) || min_n < 1L) min_n <- 20L
  disc_max <- as.integer(pol$discrete_unique_max %||% 5L)[1L]
  if (!is.finite(disc_max) || disc_max < 2L) disc_max <- 5L
  dual_lock <- !isFALSE(pol$dual_db_lock %||% TRUE)
  list(
    enable = isTRUE(enable),
    min_n = min_n,
    discrete_unique_max = disc_max,
    dual_db_lock = dual_lock
  )
}

# 插补前按缺失率删列：只保护结局/暴露/ID/核心人口学，不含 Height/Weight/BMI
pipeline_imputation_missing_protect_vars <- function(cfg) {
  cfg <- cfg %||% list()
  protect <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    protect <- c(protect, pipeline_index_exposure_var(cfg))
  }
  dat <- cfg$data %||% list()
  protect <- c(
    protect,
    as.character(dat$id_column %||% character(0)),
    as.character(dat$outcome_column %||% character(0)),
    as.character((cfg$project %||% list())$id_column %||% character(0))
  )
  protect <- unique(c(
    protect[nzchar(as.character(protect))],
    "Disease", "Disease_Group", "Group", "fustatus", "futime",
    "Gender", "Sex", "Age", "Age_Years",
    "ID", "SEQN", "Pt_ID", "Patient_ID", "subject_id",
    "CRP", "HSCRP", "Residence", "Hukou", "HR", "Pulse"
  ))
  if (pipeline_dual_db_enabled(cfg)) {
    harm <- (cfg$dual_db %||% list())$harmonization %||% list()
    keep_m <- as.character(harm$column_keep_mimic %||% character(0))
    keep_n <- as.character(harm$column_keep_nhanes %||% character(0))
    protect <- c(protect, setdiff(keep_m, keep_n))
  }
  unique(protect[nzchar(as.character(protect))])
}

pipeline_sparse_categorical_protect_vars <- function(cfg) {
  cfg <- cfg %||% list()
  protect <- character(0)
  if (exists("pipeline_mi_quality_protect_vars", mode = "function")) {
    protect <- c(protect, pipeline_mi_quality_protect_vars(cfg))
  }
  if (exists("pipeline_force_include_covariates", mode = "function")) {
    protect <- c(protect, pipeline_force_include_covariates(cfg))
  }
  if (exists("pipeline_meta_exclude_cols", mode = "function")) {
    protect <- c(protect, pipeline_meta_exclude_cols())
  }
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    protect <- c(protect, pipeline_index_exposure_var(cfg))
  }
  bl_keys <- c("baseline_binary", "baseline_multiclass", "baseline_nhanes", "baseline")
  for (k in bl_keys) {
    bl <- cfg[[k]] %||% list()
    protect <- c(
      protect,
      as.character(bl$strata %||% character(0)),
      as.character(bl$always_include_vars %||% character(0)),
      as.character(bl$include_vars %||% character(0))
    )
  }
  sg <- cfg$subgroup %||% list()
  protect <- unique(c(
    protect,
    as.character(sg$required_subgroup_vars %||% character(0)),
    as.character((cfg$analysis_var_policy %||% list())$protect_categorical_vars %||% character(0)),
    as.character((cfg$analysis_var_policy %||% list())$protect_vars %||% character(0)),
    if (exists("pipeline_model3_required_raw", mode = "function")) {
      pipeline_model3_required_raw(cfg)
    } else {
      character(0)
    },
    # 复杂抽样设计列：绝不可当稀疏分类删掉（KNHANES psu/kstrata；NHANES SDMV*）
    if (exists("nhanes_survey_weight_source_cols", mode = "function")) {
      tryCatch(nhanes_survey_weight_source_cols(cfg), error = function(e) character(0))
    } else {
      character(0)
    },
    if (exists("knhanes_survey_weight_source_cols", mode = "function")) {
      tryCatch(knhanes_survey_weight_source_cols(cfg), error = function(e) character(0))
    } else {
      character(0)
    },
    "W_pooled", "PSU", "STRATA", "new_Weight",
    "wt_itvex", "wt_tot", "psu", "kstrata", "cycle",
    "SDMVPSU", "SDMVSTRA", "Source_File",
    "Disease", "Disease_Group", "Group", "fustatus", "futime",
    "Gender", "Sex", "Age", "Age_Years",
    "BMI", "Weight", "Height",
    # ID / 时间戳：不可当「稀疏分类协变量」删掉（否则 TST 等下游丢主键）
    "ID", "SEQN", "Pt_ID", "Patient_ID", "subject_id", "stay_id", "hadm_id",
    "tst_patient_id", "icustay_id", "patientunitstayid",
    "admit_time", "disch_time", "icu_intime", "icu_outtime",
    "hosp_intime", "hosp_outtime", "charttime", "intime", "outtime"
  ))
  protect[nzchar(as.character(protect))]
}

#' 去掉数据中单水平/常数的协变量（glm 拟合前）
#' @return 仍可用于建模的变量名向量
pipeline_drop_degenerate_covariates <- function(data, vars) {
  vars <- unique(as.character(vars %||% character(0)))
  vars <- vars[nzchar(vars)]
  if (!length(vars) || is.null(data) || !is.data.frame(data)) return(character(0))
  keep <- character(0)
  for (cn in vars) {
    if (!cn %in% names(data)) next
    x <- data[[cn]]
    if (is.factor(x) || is.character(x) || is.logical(x)) {
      if (length(unique(na.omit(as.character(x)))) >= 2L) keep <- c(keep, cn)
    } else {
      xv <- suppressWarnings(as.numeric(x))
      if (length(unique(na.omit(xv))) >= 2L) keep <- c(keep, cn)
    }
  }
  keep
}

pipeline_is_categorical_analysis_col <- function(x, var_name, cfg = list(),
                                                discrete_unique_max = 5L) {
  force_cont <- as.character((cfg$force_continuous_vars %||% character(0)))
  if (var_name %in% force_cont) return(FALSE)
  if (is.factor(x) || is.character(x) || is.logical(x)) return(TRUE)
  if (is.numeric(x)) {
    u <- length(unique(stats::na.omit(x)))
    return(is.finite(u) && u >= 1L && u <= as.integer(discrete_unique_max)[1L])
  }
  FALSE
}

#' 找出任一层级 n < min_n 的分类列名（不删列）
pipeline_find_sparse_categorical_cols <- function(data, cfg = list(), min_n = NULL) {
  if (is.null(data) || !is.data.frame(data) || !ncol(data)) return(character(0))
  pol <- pipeline_sparse_categorical_policy(cfg)
  thr <- as.integer(min_n %||% pol$min_n)[1L]
  if (!is.finite(thr) || thr < 1L) thr <- 20L
  protect <- intersect(pipeline_sparse_categorical_protect_vars(cfg), names(data))
  cand <- setdiff(names(data), protect)
  drop <- character(0)
  for (nm in cand) {
    if (!pipeline_is_categorical_analysis_col(
      data[[nm]], nm, cfg, pol$discrete_unique_max
    )) next
    tab <- table(as.character(data[[nm]]), useNA = "no")
    if (!length(tab) || min(as.integer(tab)) < thr) drop <- c(drop, nm)
  }
  unique(drop)
}

pipeline_dual_db_enabled <- function(cfg) {
  isTRUE((cfg$dual_db %||% list())$enable %||% FALSE)
}

pipeline_dual_db_partner_key <- function(cfg) {
  cur <- (cfg$dual_db %||% list())$current_db %||% NULL
  if (is.null(cur) || !nzchar(as.character(cur)[1L])) return(NULL)
  cur <- as.character(cur)[1L]
  if (identical(cur, "nhanes")) return("mimic")
  if (identical(cur, "mimic")) return("nhanes")
  NULL
}

#' 读取双库某一侧的分析数据框（优先 per-index mapped，其次 shared mapped）
pipeline_dual_db_load_analysis_df <- function(cfg, db_key) {
  cfg <- cfg %||% list()
  db_key <- as.character(db_key)[1L]
  if (!nzchar(db_key)) return(NULL)
  root <- as.character((cfg$project %||% list())$root %||% getwd())[1L]
  bc <- cfg$survival_batch %||% cfg$incidence_batch %||% list()
  slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
    dual_db_slot_path_name(cfg, db_key)
  } else if (identical(db_key, "mimic")) {
    "MIMIC"
  } else {
    "eICU"
  }

  candidates <- character(0)
  ck_base <- (cfg$dual_db %||% list())$checkpoint_base %||% NULL
  if (!is.null(ck_base) && nzchar(as.character(ck_base)[1L])) {
    candidates <- c(
      candidates,
      file.path(as.character(ck_base)[1L], slot, "index.rds"),
      file.path(as.character(ck_base)[1L], slot, "step04_index.rds"),
      file.path(as.character(ck_base)[1L], slot, "column_mapping.rds")
    )
  }
  ix <- as.character(
    (cfg$survival %||% list())$index_var %||%
      (cfg$incidence %||% list())$index_var %||%
      (cfg$logistic %||% list())$index_var %||%
      character(0)
  )[1L]
  if (nzchar(ix %||% "")) {
    ib <- bc$index_ck_base %||% "checkpoints/by_index"
    if (!grepl("^(?:[A-Za-z]:)?[/\\\\]", ib)) ib <- file.path(root, ib)
    candidates <- c(
      candidates,
      file.path(ib, ix, slot, "index.rds"),
      file.path(ib, ix, slot, "step04_index.rds")
    )
  }
  if (exists("incidence_batch_shared_ck_dir", mode = "function")) {
    sh <- tryCatch(incidence_batch_shared_ck_dir(cfg, db_key), error = function(e) NULL)
    if (!is.null(sh)) {
      candidates <- c(candidates, file.path(sh, "index.rds"), file.path(sh, "step04_index.rds"))
    }
  }
  candidates <- c(
    candidates,
    file.path(root, "checkpoints/_shared", slot, "index.rds"),
    file.path(root, "checkpoints/_shared", slot, "step04_index.rds")
  )
  candidates <- unique(candidates[file.exists(candidates)])
  for (p in candidates) {
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    if (is.null(obj)) next
    ctx <- if (is.list(obj) && !is.null(obj$ctx)) obj$ctx else obj
    if (!is.list(ctx) || is.null(ctx$data)) next
    for (sn in c("mapped", "cleaned", "imputed")) {
      df <- ctx$data[[sn]]
      if (is.data.frame(df) && ncol(df)) return(df)
    }
  }
  NULL
}

pipeline_dual_db_locked_sparse_drop_vars <- function(cfg, data = NULL, min_n = NULL) {
  cfg <- cfg %||% list()
  pol <- pipeline_sparse_categorical_policy(cfg)
  if (!isTRUE(pol$enable)) return(character(0))
  thr <- as.integer(min_n %||% pol$min_n)[1L]
  drop <- character(0)
  if (is.data.frame(data)) {
    drop <- union(drop, pipeline_find_sparse_categorical_cols(data, cfg, thr))
  }
  if (pipeline_dual_db_enabled(cfg) && isTRUE(pol$dual_db_lock)) {
    for (dbk in c("nhanes", "mimic")) {
      df <- pipeline_dual_db_load_analysis_df(cfg, dbk)
      if (is.data.frame(df)) {
        drop <- union(drop, pipeline_find_sparse_categorical_cols(df, cfg, thr))
      }
    }
  }
  unique(as.character(drop))
}

#' 双库：伙伴库中缺失率 > threshold 的列（用于与本库取并集剔除，保证 Table 1 列对齐）
pipeline_dual_db_partner_high_missing_cols <- function(cfg, threshold = 0.4) {
  if (!pipeline_dual_db_enabled(cfg)) return(character(0))
  pol <- pipeline_sparse_categorical_policy(cfg)
  if (!isTRUE(pol$dual_db_lock)) return(character(0))
  partner <- pipeline_dual_db_partner_key(cfg)
  if (is.null(partner)) return(character(0))
  df <- pipeline_dual_db_load_analysis_df(cfg, partner)
  if (!is.data.frame(df) || !ncol(df)) return(character(0))
  thr <- as.numeric(threshold)[1L]
  if (!is.finite(thr)) thr <- 0.4
  miss <- vapply(df, function(x) mean(is.na(x)), numeric(1))
  drop <- names(miss)[is.finite(miss) & miss > thr]
  protect <- pipeline_sparse_categorical_protect_vars(cfg)
  partner_drop <- setdiff(drop, protect)
  # 本库缺失率可接受时，不因伙伴库高缺失并集剔除（保留 CHARLS CRP 等次库可展示列）
  cur <- as.character((cfg$dual_db %||% list())$current_db %||% "")[1L]
  if (nzchar(cur)) {
    df_self <- pipeline_dual_db_load_analysis_df(cfg, cur)
    if (is.data.frame(df_self) && ncol(df_self)) {
      miss_self <- vapply(df_self, function(x) mean(is.na(x)), numeric(1))
      ok_self <- names(miss_self)[is.finite(miss_self) & miss_self <= thr]
      partner_drop <- setdiff(partner_drop, ok_self)
    }
  }
  partner_drop
}

#' 双库：伙伴库全 NA / 零方差列（插补前并集剔除）
pipeline_dual_db_partner_unusable_cols <- function(cfg) {
  if (!pipeline_dual_db_enabled(cfg)) return(character(0))
  pol <- pipeline_sparse_categorical_policy(cfg)
  if (!isTRUE(pol$dual_db_lock)) return(character(0))
  partner <- pipeline_dual_db_partner_key(cfg)
  if (is.null(partner)) return(character(0))
  df <- pipeline_dual_db_load_analysis_df(cfg, partner)
  if (!is.data.frame(df) || !ncol(df)) return(character(0))
  drop <- character(0)
  for (nm in names(df)) {
    x <- df[[nm]]
    if (all(is.na(x))) {
      drop <- c(drop, nm)
      next
    }
    if (is.numeric(x)) {
      v <- x[is.finite(x)]
      if (length(v) < 2L || stats::sd(v) == 0) drop <- c(drop, nm)
    }
  }
  protect <- pipeline_sparse_categorical_protect_vars(cfg)
  setdiff(unique(drop), protect)
}

#' 两库 AfterMI / imputed 列名取交集，写回数据（后续全部表图共用同一列集合）
pipeline_dual_db_common_imputed_colnames <- function(root, cfg, ix, db_seq) {
  root <- as.character(root %||% (cfg$project %||% list())$root %||% getwd())[1L]
  bc <- cfg$survival_batch %||% cfg$incidence_batch %||% list()
  ck_base <- (cfg$dual_db %||% list())$checkpoint_base %||%
    file.path(bc$index_ck_base %||% "checkpoints/by_index", ix)
  if (!grepl("^(?:[A-Za-z]:)?[/\\\\]", as.character(ck_base)[1L])) {
    ck_base <- file.path(root, ck_base)
  }
  protect <- pipeline_sparse_categorical_protect_vars(cfg)
  col_sets <- list()
  for (db in db_seq) {
    slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
      dual_db_slot_path_name(cfg, db)
    } else {
      db
    }
    cols <- character(0)
    # prefer AfterMI rds/RData under output
    out_base <- bc$output_base %||% (cfg$project %||% list())$output_dir %||% root
    d01 <- file.path(out_base, "by_index", ix, slot, "step05_imputation", "D01_AfterMI_Data.RData")
    if (file.exists(d01)) {
      e <- new.env(parent = emptyenv())
      tryCatch(load(d01, envir = e), error = function(err) NULL)
      nm <- ls(e)
      if (length(nm)) {
        d <- e[[nm[[1L]]]]
        if (is.data.frame(d)) cols <- names(d)
      }
    }
    if (!length(cols)) {
      for (fn in c("step05_imputation.rds", "imputation.rds", "step06_baseline_binary.rds",
                   "baseline_binary.rds", "index.rds")) {
        p <- file.path(ck_base, slot, fn)
        if (!file.exists(p)) next
        obj <- tryCatch(readRDS(p), error = function(e) NULL)
        if (is.null(obj)) next
        ctx <- if (!is.null(obj$ctx)) obj$ctx else obj
        df <- ctx$data$imputed %||% ctx$data$mapped
        if (is.data.frame(df)) {
          cols <- names(df)
          break
        }
      }
    }
    col_sets[[as.character(db)]] <- cols
  }
  if (length(col_sets) < 2L || any(!vapply(col_sets, length, 1L))) {
    return(character(0))
  }
  common <- Reduce(intersect, col_sets)
  # 保护列若在任一库存在则尽量保留（仅当两库都有才进交集；保护列已在两侧时自然保留）
  unique(common)
}

pipeline_dual_db_trim_imputed_to_common <- function(root, cfg, ix, db, common_cols,
                                                   verbose = TRUE) {
  if (!length(common_cols)) return(invisible(character(0)))
  bc <- cfg$survival_batch %||% cfg$incidence_batch %||% list()
  root <- as.character(root %||% getwd())[1L]
  ck_base <- (cfg$dual_db %||% list())$checkpoint_base %||%
    file.path(bc$index_ck_base %||% "checkpoints/by_index", ix)
  if (!grepl("^(?:[A-Za-z]:)?[/\\\\]", as.character(ck_base)[1L])) {
    ck_base <- file.path(root, ck_base)
  }
  slot <- if (exists("dual_db_slot_path_name", mode = "function")) {
    dual_db_slot_path_name(cfg, db)
  } else {
    db
  }
  protect <- pipeline_sparse_categorical_protect_vars(cfg)
  dropped_any <- character(0)

  .trim_df <- function(df) {
    if (!is.data.frame(df)) return(df)
    keep <- union(intersect(common_cols, names(df)), intersect(protect, names(df)))
    keep <- intersect(keep, names(df))
    drop <- setdiff(names(df), keep)
    if (length(drop)) dropped_any <<- unique(c(dropped_any, drop))
    df[, keep, drop = FALSE]
  }

  out_base <- bc$output_base %||% (cfg$project %||% list())$output_dir %||% root
  d01 <- file.path(out_base, "by_index", ix, slot, "step05_imputation", "D01_AfterMI_Data.RData")
  if (file.exists(d01)) {
    e <- new.env(parent = emptyenv())
    load(d01, envir = e)
    nm <- ls(e)[1L]
    e[[nm]] <- .trim_df(e[[nm]])
    save(list = nm, envir = e, file = d01)
  }

  ck_dir <- file.path(ck_base, slot)
  if (dir.exists(ck_dir)) {
    for (fn in list.files(ck_dir, pattern = "\\.rds$", full.names = TRUE)) {
      obj <- tryCatch(readRDS(fn), error = function(e) NULL)
      if (is.null(obj) || !is.list(obj)) next
      ctx <- if (!is.null(obj$ctx)) obj$ctx else NULL
      if (is.null(ctx) || is.null(ctx$data)) next
      changed <- FALSE
      for (sn in names(ctx$data)) {
        if (!is.data.frame(ctx$data[[sn]])) next
        new_df <- .trim_df(ctx$data[[sn]])
        if (!identical(names(new_df), names(ctx$data[[sn]]))) {
          ctx$data[[sn]] <- new_df
          changed <- TRUE
        }
      }
      if (!is.null(ctx$results$data_before_mi) && is.data.frame(ctx$results$data_before_mi)) {
        ctx$results$data_before_mi <- .trim_df(ctx$results$data_before_mi)
        changed <- TRUE
      }
      if (changed) {
        if (!is.null(obj$ctx)) obj$ctx <- ctx else obj <- ctx
        saveRDS(obj, fn)
      }
    }
  }
  if (length(dropped_any) && isTRUE(verbose)) {
    cli::cli_alert_warning(
      "dual_db 列交集对齐 [{slot}]: 剔除 {length(dropped_any)} 列: {paste(utils::head(dropped_any, 15), collapse = ', ')}{if (length(dropped_any) > 15) '...' else ''}"
    )
  }
  invisible(dropped_any)
}

#' 删除「分类变量」中任一层级观测数 < min_n 的整列（默认 min_n=20）
#' 双库开启时按两库并集锁定删除，避免后续全部表/图列名不一致。
#' @return data.frame；attr(,"sparse_categorical_dropped") 为被删列名
pipeline_drop_sparse_categorical_cols <- function(data, cfg = list(),
                                                 min_n = NULL, verbose = TRUE) {
  if (is.null(data) || !is.data.frame(data) || !ncol(data)) return(data)
  pol <- pipeline_sparse_categorical_policy(cfg)
  if (!isTRUE(pol$enable)) {
    attr(data, "sparse_categorical_dropped") <- character(0)
    return(data)
  }
  thr <- as.integer(min_n %||% pol$min_n)[1L]
  if (!is.finite(thr) || thr < 1L) thr <- 20L

  if (pipeline_dual_db_enabled(cfg) && isTRUE(pol$dual_db_lock)) {
    drop <- pipeline_dual_db_locked_sparse_drop_vars(cfg, data = data, min_n = thr)
  } else {
    drop <- pipeline_find_sparse_categorical_cols(data, cfg, thr)
  }
  drop <- intersect(unique(drop), names(data))
  protect <- intersect(pipeline_sparse_categorical_protect_vars(cfg), names(data))
  drop <- setdiff(drop, protect)

  if (length(drop)) {
    data <- data[, setdiff(names(data), drop), drop = FALSE]
    if (isTRUE(verbose)) {
      msg <- paste0(
        "sparse_categorical: 删除任一层级 n<", thr, " 的分类列 (",
        length(drop), ")",
        if (pipeline_dual_db_enabled(cfg) && isTRUE(pol$dual_db_lock)) " [双库并集锁定]" else "",
        ": ",
        paste(utils::head(drop, 30L), collapse = ", "),
        if (length(drop) > 30L) ", ..." else ""
      )
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning(msg)
      } else {
        message(msg)
      }
    }
  }
  attr(data, "sparse_categorical_dropped") <- drop
  data
}

pipeline_apply_sparse_categorical_drop_to_ctx <- function(ctx, slots = c("imputed")) {
  if (is.null(ctx) || !is.list(ctx)) return(ctx)
  cfg <- ctx$config %||% list()
  if (is.null(ctx$data)) ctx$data <- list()
  if (is.null(ctx$results)) ctx$results <- list()
  dropped_all <- character(0)
  for (sn in unique(as.character(slots))) {
    df <- ctx$data[[sn]]
    if (is.null(df) || !is.data.frame(df)) next
    df2 <- pipeline_drop_sparse_categorical_cols(df, cfg, verbose = TRUE)
    dropped_all <- unique(c(dropped_all, attr(df2, "sparse_categorical_dropped") %||% character(0)))
    attr(df2, "sparse_categorical_dropped") <- NULL
    ctx$data[[sn]] <- df2
  }
  if (!is.null(ctx$results$data_before_mi) && is.data.frame(ctx$results$data_before_mi)) {
    db <- pipeline_drop_sparse_categorical_cols(ctx$results$data_before_mi, cfg, verbose = FALSE)
    dropped_all <- unique(c(dropped_all, attr(db, "sparse_categorical_dropped") %||% character(0)))
    attr(db, "sparse_categorical_dropped") <- NULL
    ctx$results$data_before_mi <- db
  }
  if (length(dropped_all)) {
    prev <- as.character(ctx$results$sparse_categorical_dropped %||% character(0))
    ctx$results$sparse_categorical_dropped <- unique(c(prev, dropped_all))
  }
  ctx
}

# ── 分析队列审计 ────────────────────────────────────────────────────────────

pipeline_population_audit <- function(ctx, stage, data, note = NULL) {
  cfg <- ctx$config %||% list()
  audit <- ctx$results$population_audit %||% list()
  n <- if (is.null(data) || !is.data.frame(data)) NA_integer_ else nrow(data)
  n_cols <- if (is.null(data) || !is.data.frame(data)) NA_integer_ else ncol(data)
  entry <- list(
    stage = as.character(stage)[1L],
    n = n,
    n_cols = n_cols,
    note = as.character(note %||% "")[1L],
    at = as.character(Sys.time())
  )
  audit[[length(audit) + 1L]] <- entry
  ctx$results$population_audit <- audit
  if (is.finite(n)) {
    cli::cli_alert_info(
      "population_audit [{stage}]: n={n}, cols={n_cols}{if (nzchar(entry$note)) paste0(' — ', entry$note) else ''}"
    )
  }
  ctx
}

# ── SHAP waterfall：阳性且高概率优先；否则阳性最高概率并标注 ───────────────

pipeline_pick_shap_waterfall_row_v2 <- function(ctx, pred_prob, outcome01,
                                                prob_threshold = 0.75) {
  n <- length(outcome01)
  empty <- list(
    row_id = 1L,
    incidence = NA_real_,
    pred_prob = NA_real_,
    outcome01 = NA_integer_,
    met_threshold = FALSE,
    rule = "fallback_row1"
  )
  if (!length(pred_prob) || length(pred_prob) != n) return(empty)
  ok <- !is.na(outcome01) & !is.na(pred_prob)
  incidence <- if (any(ok)) mean(outcome01[ok] == 1L) else NA_real_
  thr <- as.numeric(prob_threshold)[1L]
  if (!is.finite(thr)) thr <- 0.75

  hit_hi <- which(ok & outcome01 == 1L & pred_prob > thr)
  if (length(hit_hi)) {
    rid <- as.integer(hit_hi[1L])
    return(list(
      row_id = rid,
      incidence = incidence,
      pred_prob = as.numeric(pred_prob[rid]),
      outcome01 = as.integer(outcome01[rid]),
      met_threshold = TRUE,
      rule = "case_and_prob_gt_threshold"
    ))
  }

  hit_case <- which(ok & outcome01 == 1L)
  if (length(hit_case)) {
    best <- hit_case[which.max(pred_prob[hit_case])]
    rid <- as.integer(best)
    return(list(
      row_id = rid,
      incidence = incidence,
      pred_prob = as.numeric(pred_prob[rid]),
      outcome01 = as.integer(outcome01[rid]),
      met_threshold = isTRUE(pred_prob[rid] > thr),
      rule = "case_highest_prob"
    ))
  }

  rid <- 1L
  list(
    row_id = rid,
    incidence = incidence,
    pred_prob = if (length(pred_prob) >= 1L) as.numeric(pred_prob[1L]) else NA_real_,
    outcome01 = if (length(outcome01) >= 1L) as.integer(outcome01[1L]) else NA_integer_,
    met_threshold = FALSE,
    rule = "fallback_row1"
  )
}

# 兼容旧调用：覆盖 utils 中同名函数的行为（后加载）
pipeline_pick_shap_waterfall_row <- function(ctx, pred_prob, outcome01,
                                             prob_threshold = 0.75) {
  pipeline_pick_shap_waterfall_row_v2(ctx, pred_prob, outcome01, prob_threshold)
}

# ── 中介 / 亚组暴露路由 ─────────────────────────────────────────────────────

pipeline_resolve_exposure_targets <- function(ctx) {
  cfg <- ctx$config %||% list()
  ms <- cfg$mediation_subgroup %||% cfg$capability %||% list()
  mode <- tolower(trimws(as.character(
    ms$exposure_mode %||% cfg$capability$exposure_mode %||% "auto"
  )[1L]))

  primary <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    primary <- as.character(pipeline_index_exposure_var(cfg) %||% character(0))
  }
  primary <- unique(c(
    primary,
    as.character((cfg$prediction %||% list())$index_vars %||% character(0)),
    as.character((cfg$incidence %||% list())$index_var %||% character(0)),
    as.character((cfg$survival %||% list())$index_var %||% character(0)),
    as.character((cfg$logistic %||% list())$index_var %||% character(0))
  ))
  primary <- unique(primary[nzchar(primary) & !is.na(primary)])

  ml_feats <- unique(as.character(
    ctx$results$ml_feature_names %||%
      ctx$results$feature_selection_final %||%
      character(0)
  ))
  ml_feats <- ml_feats[nzchar(ml_feats)]

  if (identical(mode, "all_ml_features") ||
      (identical(mode, "auto") && isTRUE(ms$all_ml_features %||% FALSE))) {
    targets <- if (length(ml_feats)) ml_feats else primary
    return(list(mode = "all_ml_features", exposures = targets, primary = primary))
  }

  if (identical(mode, "primary_only") || identical(mode, "auto")) {
    return(list(mode = "primary_only", exposures = primary, primary = primary))
  }

  list(mode = mode, exposures = primary, primary = primary)
}

# ── 敏感性默认场景 ──────────────────────────────────────────────────────────

pipeline_default_sensitivity_scenarios <- function(cfg = list()) {
  alias <- (cfg$capability %||% list())$variable_aliases %||% list()
  age_v <- as.character(alias$age %||% "Age")[1L]
  cut <- as.integer(
    (cfg$sensitivity_suite %||% list())$age_cutoff %||%
      (cfg$nhanes %||% list())$age_cutoff %||%
      (cfg$subgroup %||% list())$age_cutoff %||%
      (cfg$incidence_batch %||% list())$sensitivity_suite$age_cutoff %||%
      (cfg$survival_batch %||% list())$sensitivity_suite$age_cutoff %||% 65
  )[1L]
  list(
    list(name = "age_lt", label = sprintf("SA_age_lt_%s", cut),
         expr = sprintf("as.numeric(%s) < %s", age_v, cut),
         required_vars = age_v),
    list(name = "age_ge", label = sprintf("SA_age_ge_%s", cut),
         expr = sprintf("as.numeric(%s) >= %s", age_v, cut),
         required_vars = age_v)
  )
}

pipeline_sensitivity_scenarios_for_data <- function(cfg, data = NULL) {
  sens <- (cfg$capability %||% list())$sensitivity_suite %||%
    (cfg$sensitivity_suite %||% list()) %||%
    (cfg$incidence_batch %||% list())$sensitivity_suite %||%
    (cfg$survival_batch %||% list())$sensitivity_suite %||% list()
  scenarios <- sens$scenarios %||% NULL
  if (is.null(scenarios) || !length(scenarios)) {
    scenarios <- pipeline_default_sensitivity_scenarios(cfg)
  }
  out <- list()
  for (s in scenarios) {
    req <- unique(as.character(s$required_vars %||% character(0)))
    if (!length(req) && nzchar(s$expr %||% "")) {
      req <- tryCatch(all.vars(parse(text = s$expr)), error = function(e) character(0))
    }
    if (!is.null(data) && is.data.frame(data) && length(req) &&
        !all(req %in% names(data))) {
      next
    }
    out[[length(out) + 1L]] <- list(
      name = as.character(s$name %||% s$label %||% paste0("sc", length(out) + 1L))[1L],
      label = as.character(s$label %||% s$name %||% paste0("sc", length(out) + 1L))[1L],
      expr = as.character(s$expr %||% "")[1L],
      required_vars = req
    )
  }
  out
}

pipeline_apply_row_filter_expr <- function(data, expr) {
  if (is.null(data) || !is.data.frame(data) || !nzchar(expr %||% "")) return(data)
  need <- tryCatch(all.vars(parse(text = expr)), error = function(e) character(0))
  if (length(need) && !all(need %in% names(data))) return(data)
  keep <- tryCatch(
    as.logical(eval(parse(text = expr), envir = data)),
    error = function(e) rep(TRUE, nrow(data))
  )
  if (length(keep) != nrow(data)) keep <- rep(TRUE, nrow(data))
  keep[is.na(keep)] <- FALSE
  data[keep, , drop = FALSE]
}

# ── 连续变量 KM：与 Cox/logistic 共用分位切点 ─────────────────────────────────

pipeline_quantile_breaks <- function(x, method = c("quartile", "tertile", "median")) {
  method <- match.arg(method)
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (length(x) < 3L) return(NULL)
  probs <- switch(method,
    quartile = c(0, 0.25, 0.5, 0.75, 1),
    tertile = c(0, 1 / 3, 2 / 3, 1),
    median = c(0, 0.5, 1)
  )
  br <- as.numeric(stats::quantile(x, probs = probs, na.rm = TRUE, type = 7))
  # 保留完整边界（含 min/max）；允许边界重复，由分组因子回退
  if (length(unique(br)) < 2L) return(NULL)
  br
}

#' 连续值 → 分位因子（quartile=Q1–Q4 / tertile=T1–T3）；切点重复时秩等频回退
pipeline_quantile_group_factor <- function(x, method = c("quartile", "tertile"), breaks = NULL) {
  method <- match.arg(method)
  x <- as.numeric(x)
  labs <- if (identical(method, "quartile")) c("Q1", "Q2", "Q3", "Q4") else c("T1", "T2", "T3")
  n_g <- length(labs)
  need_inner <- n_g - 1L
  if (is.null(breaks)) breaks <- pipeline_quantile_breaks(x, method)
  br <- as.numeric(breaks)
  br <- br[is.finite(br)]
  if (!is.null(br) && length(br) >= need_inner) {
    # 3 个内部切点（cox_index_breaks）或 5 个全边界（min/Q1/Q2/Q3/max）都要识别
    br_inner <- if (length(br) == need_inner) {
      unique(br)
    } else if (length(br) >= need_inner + 2L) {
      unique(br[-c(1L, length(br))])
    } else {
      unique(br)
    }
    br_inner <- br_inner[is.finite(br_inner)]
    if (length(br_inner) >= need_inner) {
      g <- cut(
        x,
        breaks = unique(c(-Inf, br_inner[seq_len(need_inner)], Inf)),
        labels = labs,
        include.lowest = TRUE,
        right = FALSE
      )
      if (nlevels(droplevels(g[!is.na(g)])) >= n_g) {
        return(factor(as.character(g), levels = labs))
      }
      # 切点不足时允许较少水平标签
      if (length(br_inner) >= 1L) {
        n_lab <- length(br_inner) + 1L
        g2 <- cut(
          x,
          breaks = unique(c(-Inf, br_inner, Inf)),
          labels = labs[seq_len(n_lab)],
          include.lowest = TRUE,
          right = FALSE
        )
        if (nlevels(droplevels(g2[!is.na(g2)])) >= 2L) {
          return(factor(as.character(g2), levels = labs[seq_len(n_lab)]))
        }
      }
    }
  }
  # 秩等频回退
  r <- rank(x, ties.method = "average", na.last = "keep")
  n <- sum(is.finite(r))
  if (n < n_g) {
    stop(sprintf("无法为连续变量形成 %s 组（有效 n < %d）", method, n_g), call. = FALSE)
  }
  probs <- seq(0, 1, length.out = n_g + 1L)
  q <- findInterval(
    r,
    stats::quantile(r, probs = probs, na.rm = TRUE, type = 7),
    rightmost.closed = TRUE,
    all.inside = TRUE
  )
  q[!is.finite(r)] <- NA_integer_
  q[is.finite(q) & q < 1L] <- 1L
  q[is.finite(q) & q > n_g] <- n_g
  if (length(unique(stats::na.omit(q))) < n_g) {
    ord <- order(x, na.last = NA)
    q2 <- rep(NA_integer_, length(x))
    n_ok <- length(ord)
    cuts <- c(0L, vapply(seq_len(n_g - 1L), function(k) as.integer(floor(k * n_ok / n_g)), integer(1L)), n_ok)
    for (k in seq_len(n_g)) {
      if (cuts[k] < cuts[k + 1L]) q2[ord[(cuts[k] + 1L):cuts[k + 1L]]] <- k
    }
    q <- q2
  }
  if (length(unique(stats::na.omit(q))) < 2L) {
    stop(sprintf("无法为连续变量形成至少 2 个 %s 组", method), call. = FALSE)
  }
  factor(labs[q], levels = labs)
}

pipeline_tertile_factor <- function(x, breaks = NULL) {
  pipeline_quantile_group_factor(x, method = "tertile", breaks = breaks)
}

pipeline_quartile_factor <- function(x, breaks = NULL) {
  pipeline_quantile_group_factor(x, method = "quartile", breaks = breaks)
}

#' KM 图例用总 N / 总事件（禁止用 summary(fit, times=28)$n.event）
pipeline_km_stratum_counts <- function(fit) {
  tab <- tryCatch(summary(fit)$table, error = function(e) NULL)
  if (is.null(tab)) {
    return(data.frame(n = integer(0), n_event = integer(0)))
  }
  if (!is.matrix(tab)) {
    tab <- matrix(tab, nrow = 1L, dimnames = list(NULL, names(tab)))
  }
  n <- if ("records" %in% colnames(tab)) {
    as.integer(tab[, "records"])
  } else {
    as.integer(fit$n)
  }
  n_event <- if ("events" %in% colnames(tab)) {
    as.integer(tab[, "events"])
  } else {
    as.integer(fit$n.event)
  }
  data.frame(n = n, n_event = n_event, stringsAsFactors = FALSE)
}

pipeline_store_continuous_km_cutpoints <- function(ctx, var, breaks, method = "quartile") {
  store <- ctx$results$continuous_km_cutpoints %||% list()
  br <- as.numeric(breaks)
  store[[as.character(var)[1L]]] <- list(
    breaks = br,
    method = as.character(method)[1L]
  )
  ctx$results$continuous_km_cutpoints <- store
  # cox_index_breaks 约定为内部切点（quartile=3 / tertile=2），供 segmented_cox 使用
  need_inner <- switch(as.character(method)[1L], quartile = 3L, tertile = 2L, 1L)
  br_ok <- br[is.finite(br)]
  ctx$results$cox_index_breaks <- if (length(br_ok) == need_inner) {
    br_ok
  } else if (length(br_ok) >= need_inner + 2L) {
    br_ok[-c(1L, length(br_ok))]
  } else {
    br_ok
  }
  ctx$results$cox_grouping <- list(
    method = method,
    group_levels = switch(
      method,
      quartile = c("Q1", "Q2", "Q3", "Q4"),
      tertile = c("T1", "T2", "T3"),
      median = c("Low", "High"),
      NULL
    )
  )
  ctx
}

pipeline_build_km_strata_defs_from_cutpoints <- function(ctx, vars = NULL, method = "quartile") {
  store <- ctx$results$continuous_km_cutpoints %||% list()
  vars <- if (is.null(vars) || !length(vars)) names(store) else as.character(vars)
  vars <- unique(vars[nzchar(vars)])
  defs <- list()
  strata_vars <- character(0)
  for (v in vars) {
    method_v <- as.character(store[[v]]$method %||% method)[1L]
    br_full <- as.numeric(store[[v]]$breaks %||% numeric(0))
    br_full <- br_full[is.finite(br_full)]
    if (!length(br_full)) next
    out_col <- paste0(v, "_", method_v)
    # 分位分组：统一走 pipeline_*_factor，切点重复时自动秩回退
    if (identical(method_v, "tertile")) {
      labs <- c("T1", "T2", "T3")
      defs[[out_col]] <- list(
        source = v,
        type = "tertile_factor",
        breaks_full = br_full,
        labels = labs,
        levels = labs
      )
      strata_vars <- c(strata_vars, out_col)
      next
    }
    if (identical(method_v, "quartile")) {
      labs <- c("Q1", "Q2", "Q3", "Q4")
      defs[[out_col]] <- list(
        source = v,
        type = "quartile_factor",
        breaks_full = br_full,
        labels = labs,
        levels = labs
      )
      strata_vars <- c(strata_vars, out_col)
      next
    }
    if (length(br_full) < 3L) next
    # cut_manual 约定：breaks 为内部切点，labels 长度 = length(breaks)+1
    br_inner <- unique(br_full[-c(1L, length(br_full))])
    if (!length(br_inner)) next
    labs <- switch(
      method_v,
      median = c("Low", "High"),
      paste0("G", seq_len(length(br_inner) + 1L))
    )
    n_lab <- length(br_inner) + 1L
    if (length(labs) != n_lab) labs <- paste0("G", seq_len(n_lab))
    defs[[out_col]] <- list(
      source = v,
      type = "cut_manual",
      breaks = br_inner,
      labels = labs,
      levels = labs
    )
    strata_vars <- c(strata_vars, out_col)
  }
  list(strata_vars = unique(strata_vars), strata_defs = defs)
}
