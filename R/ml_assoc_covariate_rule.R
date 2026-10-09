###############################################################################
#  ml_assoc_covariate_rule.R — Cox / Logistic 协变量铁律（全 ML 课题复用）
#
#  默认铁律：
#  Model 1：Age 强制纳入（不论单因素是否显著）；可选 demo_uv_to_model1 将 UV 显著的人口学
#           （Height/Weight/BMI 等）并入 Model1，非强制
#  Model 2（默认）：Model1 +「单因素显著（tb1）且未进入最终 ML 特征」的其余变量（嵌套）
#  Model 2（可选 model2_from_vif_pass）：Model1 + VIF 通过池（可含 ML 特征，仅排除暴露）
#
#  文献对齐 scheme = "literature_m123"（opt-in，不改全局默认）：
#  Model2Factors = Age + Sex/Gender
#  Model3Factors = Model2 ∪ (clinical_covariates ∩ UV-sig ∩ VIF-pass)
#  兼容：Model1Factors ← Model2Factors；Model2Factors 对外也写入 Model3 全调整集
#        （assoc 块仍读 M1=最小调整 / M2=全调整）
#
#  排除：暴露指标本身、（默认）已进 ML 的变量、结局/ID、可选黑名单
#  配置：config$assoc_covariate / config$ml_small_sample$assoc_covariate
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

ml_assoc_covariate_cfg <- function(cfg) {
  ms <- cfg$ml_small_sample %||% list()
  ac <- cfg$assoc_covariate %||% ms$assoc_covariate %||% list()
  list(
    enable = isTRUE(ac$enable %||% TRUE),
    scheme = as.character(ac$scheme %||% "default")[1L],
    force_model1 = as.character(ac$force_model1 %||% "Age"),
    sex_var = as.character(ac$sex_var %||% "Gender")[1L],
    clinical_covariates = unique(as.character(ac$clinical_covariates %||% character(0))),
    uv_source = as.character(ac$uv_source %||% "tb1")[1L],  # tb1 | tb_screen
    max_model2_extra = {
      m <- suppressWarnings(as.integer(ac$max_model2_extra %||% Inf)[1L])
      if (!is.finite(m) || m < 0L) Inf else m
    },
    exclude_extra = as.character(ac$exclude_extra %||% character(0)),
    model2_exclude = as.character(ac$model2_exclude %||% character(0)),
    demo_uv_to_model1 = isTRUE(ac$demo_uv_to_model1 %||% FALSE),
    demo_keywords = as.character(ac$demo_keywords %||% character(0)),
    allow_m2_eq_m1 = isTRUE(ac$allow_m2_eq_m1 %||% TRUE),
    prefer_clinical = as.character(ac$prefer_clinical %||% character(0)),
    allow_ml_features_in_model2 = isTRUE(ac$allow_ml_features_in_model2 %||% FALSE),
    model2_from_vif_pass = isTRUE(ac$model2_from_vif_pass %||% FALSE)
  )
}

ml_assoc_is_literature_m123 <- function(ac_or_cfg) {
  ac <- if (is.list(ac_or_cfg) && !is.null(ac_or_cfg$scheme)) {
    ac_or_cfg
  } else {
    ml_assoc_covariate_cfg(ac_or_cfg %||% list())
  }
  identical(as.character(ac$scheme %||% "default")[1L], "literature_m123")
}

#' Resolve Age + Sex/Gender present in data (literature Model 2).
ml_assoc_resolve_sex_var <- function(sex_var, data_names = NULL) {
  cand <- unique(c(
    as.character(sex_var %||% "Gender")[1L],
    "Gender", "Sex", "gender", "sex"
  ))
  cand <- cand[nzchar(cand)]
  if (is.null(data_names)) return(cand[[1L]])
  hit <- intersect(cand, data_names)
  if (!length(hit)) {
    stop(
      "literature_m123: Sex/Gender column not found in data ",
      "(tried: ", paste(cand, collapse = ", "), ").",
      call. = FALSE
    )
  }
  hit[[1L]]
}

#' Literature Table2 Model2/Model3: Age+Sex; clinical ∩ UV ∩ VIF.
ml_resolve_assoc_covariates_literature_m123 <- function(ctx, data_names = NULL, ac = NULL) {
  cfg <- ctx$config %||% list()
  if (is.null(ac)) ac <- ml_assoc_covariate_cfg(cfg)
  clinical <- unique(as.character(ac$clinical_covariates %||% character(0)))
  clinical <- clinical[nzchar(clinical)]
  if (!length(clinical)) {
    stop(
      "literature_m123: assoc_covariate$clinical_covariates is required ",
      "(clinically meaningful covariates for Model 3).",
      call. = FALSE
    )
  }

  age_var <- as.character(ac$force_model1 %||% "Age")[1L]
  if (!nzchar(age_var)) age_var <- "Age"
  sex_var <- ml_assoc_resolve_sex_var(ac$sex_var, data_names)
  if (!is.null(data_names) && !age_var %in% data_names) {
    stop(
      "literature_m123: Age column '", age_var, "' not found in data.",
      call. = FALSE
    )
  }

  uv <- ml_assoc_uv_sig_vars(ctx, ac$uv_source)
  vif_pool <- ml_assoc_vif_pass_vars(ctx)
  if (!length(vif_pool)) {
    stop(
      "literature_m123: vif_screen_pass is empty; run ml_vif_train_test before resolve.",
      call. = FALSE
    )
  }
  if (!length(uv)) {
    stop(
      "literature_m123: univariate-significant pool is empty (uv_source=",
      ac$uv_source, ").",
      call. = FALSE
    )
  }

  exposure <- ml_assoc_exposure_var(ctx)
  ml_feats <- ml_assoc_ml_feature_set(ctx)
  ban <- unique(c(
    exposure,
    ac$exclude_extra,
    age_var,
    sex_var,
    "ID", "Group", "SEQN", "subject_id",
    as.character((cfg$data %||% list())$outcome_column %||% character(0)),
    as.character((cfg$survival %||% list())$event_var %||% character(0)),
    as.character((cfg$survival %||% list())$time_var %||% character(0)),
    as.character(ac$model2_exclude %||% character(0))
  ))
  ban <- ban[nzchar(ban)]

  extras <- intersect(clinical, intersect(uv, vif_pool))
  extras <- setdiff(extras, ban)
  if (!is.null(data_names)) {
    extras <- intersect(extras, data_names)
  }
  if (!length(extras)) {
    stop(
      "literature_m123: clinical ∩ UV-sig ∩ VIF-pass is empty after exclusions. ",
      "Check clinical_covariates vs tb1/vif_screen_pass. ",
      "clinical_n=", length(clinical),
      "; uv_n=", length(uv),
      "; vif_n=", length(vif_pool),
      ".",
      call. = FALSE
    )
  }
  if (is.finite(ac$max_model2_extra) && length(extras) > ac$max_model2_extra) {
    extras <- extras[seq_len(ac$max_model2_extra)]
  }

  M1 <- unique(c(age_var, sex_var))
  M2 <- unique(c(M1, extras))
  list(
    M1 = M1,
    M2 = M2,
    M3 = M2,
    extras = extras,
    dropped_in_ml = character(0),
    ml_in_model2 = intersect(extras, ml_feats),
    uv_sig = uv,
    vif_pool = vif_pool,
    clinical_covariates = clinical,
    ml_features = ml_feats,
    exposure = exposure,
    allow_m2_eq_m1 = TRUE,
    demo_uv = character(0),
    scheme = "literature_m123",
    sex_var = sex_var,
    note = sprintf(
      "literature_m123: Model2=Age+%s; Model3=Model2 + clinical∩UV∩VIF (%d): %s",
      sex_var,
      length(extras),
      paste(extras, collapse = ", ")
    )
  )
}

ml_assoc_vif_pass_vars <- function(ctx) {
  v <- as.character(
    ctx$results$vif_screen_pass %||%
      ctx$results$vif_screen_pass_weighted %||%
      ctx$results$vif_final_pass %||%
      character(0)
  )
  unique(v[nzchar(v)])
}

ml_assoc_uv_sig_vars <- function(ctx, source = "tb1") {
  if (identical(source, "tb_screen")) {
    v <- as.character(ctx$results$tb_screen %||% ctx$results$univar_features %||% character(0))
  } else {
    v <- as.character(ctx$results$tb1 %||% character(0))
  }
  unique(v[nzchar(v)])
}

ml_assoc_ml_feature_set <- function(ctx) {
  unique(c(
    as.character(ctx$results$feature_selection_final %||% character(0)),
    as.character(ctx$results$ml_feature_names %||% character(0)),
    as.character(ctx$results$feature_selection_venn_center %||% character(0))
  ))
}

ml_assoc_exposure_var <- function(ctx) {
  cfg <- ctx$config %||% list()
  exp <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    exp <- as.character(pipeline_index_exposure_var(cfg) %||% character(0))
  }
  unique(c(
    exp,
    as.character((cfg$prediction %||% list())$index_vars %||% character(0)),
    as.character((cfg$ml_batch %||% list())$current_index %||% character(0)),
    as.character((cfg$survival %||% list())$index_var %||% character(0))
  ))
}

#' 解析 Cox/Logistic Model1 / Model2（及 literature_m123 的 Model3）
#' @return list(M1, M2, extras, dropped_in_ml, note, ...)
ml_resolve_assoc_covariates <- function(ctx, data_names = NULL) {
  cfg <- ctx$config %||% list()
  ac <- ml_assoc_covariate_cfg(cfg)
  if (ml_assoc_is_literature_m123(ac)) {
    return(ml_resolve_assoc_covariates_literature_m123(ctx, data_names, ac))
  }
  m1_force <- unique(as.character(ac$force_model1[nzchar(as.character(ac$force_model1))]))
  if (!length(m1_force)) m1_force <- "Age"

  uv <- ml_assoc_uv_sig_vars(ctx, ac$uv_source)
  ml_feats <- ml_assoc_ml_feature_set(ctx)
  exposure <- ml_assoc_exposure_var(ctx)
  vif_pool <- if (isTRUE(ac$model2_from_vif_pass)) ml_assoc_vif_pass_vars(ctx) else character(0)
  candidate_src <- if (isTRUE(ac$model2_from_vif_pass) && length(vif_pool)) vif_pool else uv

  ban <- unique(c(
    exposure,
    ac$exclude_extra,
    "ID", "Group", "SEQN", "subject_id",
    as.character((cfg$data %||% list())$outcome_column %||% character(0)),
    as.character((cfg$survival %||% list())$event_var %||% character(0)),
    as.character((cfg$survival %||% list())$time_var %||% character(0))
  ))
  if (!isTRUE(ac$allow_ml_features_in_model2)) {
    ban <- unique(c(ban, ml_feats))
  }
  ban <- ban[nzchar(ban)]

  m2_never <- unique(as.character(ac$model2_exclude[nzchar(as.character(ac$model2_exclude))]))

  demo_kws <- ac$demo_keywords
  if (!length(demo_kws)) {
    demo_kws <- unique(c(
      as.character((cfg$dual_db$harmonization %||% list())$demo_keywords %||% character(0)),
      as.character((cfg$multivariate_incidence_binary %||% list())$demo_keywords %||% character(0)),
      "Gender", "Sex", "Height", "Weight", "BMI"
    ))
  }
  demo_kws <- setdiff(unique(demo_kws[nzchar(demo_kws)]), m1_force)

  demo_uv <- character(0)
  if (isTRUE(ac$demo_uv_to_model1) && length(candidate_src) && length(demo_kws)) {
    if (exists("pipeline_is_demo_var", mode = "function")) {
      demo_uv <- candidate_src[
        vapply(candidate_src, function(v) pipeline_is_demo_var(v, demo_kws), logical(1))
      ]
    } else {
      demo_uv <- candidate_src[toupper(candidate_src) %in% toupper(demo_kws)]
    }
  }

  m1_all <- unique(c(m1_force, demo_uv))
  extras <- setdiff(candidate_src, unique(c(ban, m1_all, m2_never)))
  # 优先临床名单（若配置），其余按原 UV 顺序
  if (length(ac$prefer_clinical) && length(extras)) {
    pref <- intersect(ac$prefer_clinical, extras)
    extras <- unique(c(pref, setdiff(extras, pref)))
  }
  if (is.finite(ac$max_model2_extra) && length(extras) > ac$max_model2_extra) {
    extras <- extras[seq_len(ac$max_model2_extra)]
  }

  if (!is.null(data_names)) {
    m1_all <- intersect(m1_all, data_names)
    extras <- intersect(extras, data_names)
  }

  ## 2026-09-18 AKI(19) 修复: FIB4/FSI/NFS 等公式含 Age 的指标，Age 被成分防泄漏
  ## 链从分析框剔除后 force_model1="Age" 交集落空；外验库(eICU 称主库/ MIMIC 外验)
  ## 帧里 Race 也不在 → M1 全空直接 stop。仅在 M1 已空时启用 Age_Group→Gender 代理，
  ## 其余指标 M1 非空、行为零改变。
  if (!length(m1_all) && !is.null(data_names)) {
    surrogate <- intersect(c("Age_Group", "Gender", "Race", "Ethnicity"), data_names)[1]
    if (!is.na(surrogate) && nzchar(surrogate)) {
      m1_all <- surrogate
      cli::cli_alert_info(
        "ml_resolve_assoc_covariates: Model1 交集落空，改用代理协变量 '{surrogate}'。")
    }
  }

  M1 <- unique(m1_all)
  M2 <- unique(c(M1, extras))
  if (!length(M1)) {
    stop("ml_resolve_assoc_covariates: Model1 为空（Age 不在数据中？）", call. = FALSE)
  }
  if (!ac$allow_m2_eq_m1 && identical(sort(M1), sort(M2))) {
    # 无额外协变量时允许 M2=M1（小样本常见）
    ac$allow_m2_eq_m1 <- TRUE
  }

  list(
    M1 = M1,
    M2 = M2,
    M3 = M2,
    extras = extras,
    dropped_in_ml = if (isTRUE(ac$allow_ml_features_in_model2)) {
      character(0)
    } else {
      intersect(candidate_src, ml_feats)
    },
    ml_in_model2 = intersect(extras, ml_feats),
    uv_sig = uv,
    vif_pool = vif_pool,
    ml_features = ml_feats,
    exposure = exposure,
    allow_m2_eq_m1 = ac$allow_m2_eq_m1,
    demo_uv = demo_uv,
    scheme = "default",
    note = if (isTRUE(ac$model2_from_vif_pass) && length(vif_pool)) {
      sprintf(
        "Model1=force(%s)%s; Model2=Model1 + VIF-pass (%d)%s: %s",
        paste(m1_force, collapse = "+"),
        if (length(demo_uv)) sprintf(" + demo(%s)", paste(demo_uv, collapse = "+")) else "",
        length(extras),
        if (isTRUE(ac$allow_ml_features_in_model2)) " incl.ML" else " excl.ML",
        if (length(extras)) paste(extras, collapse = ", ") else "(none)"
      )
    } else {
      sprintf(
        "Model1=force(%s)%s; Model2=Model1 + UV-sig not in ML (%d): %s",
        paste(m1_force, collapse = "+"),
        if (length(demo_uv)) {
          sprintf(" + demo-UV(%s)", paste(demo_uv, collapse = "+"))
        } else {
          ""
        },
        length(extras),
        if (length(extras)) paste(extras, collapse = ", ") else "(none)"
      )
    }
  )
}

#' 双库预设锁 / 闸门 B 已对齐时，取程序员指定的 Model1/Model2（禁止 UV 铁律覆盖）
ml_assoc_locked_preset_models <- function(ctx) {
  cfg <- ctx$config %||% list()
  harm <- cfg$dual_db$harmonization %||% list()
  am <- cfg$analysis_models %||% list()

  # 0) 外验 / 次库已继承主库训练集 M1/M2（禁止再用空 UV 解析成只剩 Age）
  if (identical(ctx$results$assoc_covariates_inherited_from, "primary")) {
    m1 <- unique(as.character(ctx$results$assoc_model1_factors %||% character(0)))
    m2 <- unique(as.character(ctx$results$assoc_model2_factors %||% character(0)))
    m3 <- unique(as.character(
      ctx$results$assoc_model3_factors %||%
        ctx$results$Model3Factors %||%
        m2
    ))
    m1 <- m1[nzchar(m1)]
    m2 <- m2[nzchar(m2)]
    m3 <- m3[nzchar(m3)]
    if (!length(m3)) m3 <- unique(c(m1, m2))
    if (length(m1) && length(m2)) {
      return(list(
        M1 = m1, M2 = unique(c(m1, m2)), M3 = unique(c(m1, m3)),
        extras = setdiff(unique(c(m2, m3)), m1),
        dropped_in_ml = character(0), allow_m2_eq_m1 = TRUE,
        scheme = ctx$results$assoc_covariate_scheme %||% "default",
        note = ctx$results$assoc_covariate_note %||% sprintf(
          "继承主库训练集 Model1=%s; Model2=%s",
          paste(m1, collapse = "+"), paste(unique(c(m1, m2)), collapse = "+")
        ),
        source = "primary_inherit"
      ))
    }
  }

  # 1) 闸门 B 已写入 ctx 的统一池（Gate C 重导时优先）
  if (isTRUE(ctx$results$dual_db_covariate_harmonized)) {
    m1 <- as.character(ctx$results$Model1Factors %||% character(0))
    m2 <- as.character(ctx$results$Model2Factors %||% character(0))
    if (length(m1) && length(m2)) {
      return(list(
        M1 = m1, M2 = unique(c(m1, m2)), extras = setdiff(m2, m1),
        dropped_in_ml = character(0), allow_m2_eq_m1 = TRUE,
        note = sprintf(
          "Gate B 锁定 Model1=%s; Model2=%s",
          paste(m1, collapse = "+"), paste(unique(c(m1, m2)), collapse = "+")
        ),
        source = "gate_b"
      ))
    }
  }

  # 2) lock_covariates_preset：harmonized_* / analysis_models
  if (!isTRUE(harm$lock_covariates_preset)) return(NULL)

  slot <- as.character(
    ctx$config$project$current_db %||%
      ctx$results$current_db %||%
      ctx$results$dual_db_slot %||%
      "nhanes"
  )[1L]
  use_mimic <- identical(tolower(slot), "mimic") ||
    identical(tolower(slot), "charls") ||
    (exists("dual_db_slot_is_primary", mode = "function") &&
       !dual_db_slot_is_primary(slot))
  m1_key <- if (use_mimic) "harmonized_model1_mimic" else "harmonized_model1_nhanes"
  m2_key <- if (use_mimic) "harmonized_model2_mimic" else "harmonized_model2_nhanes"
  m1 <- as.character(harm[[m1_key]] %||% am$model1_factors %||% character(0))
  m2 <- as.character(harm[[m2_key]] %||% am$model2_factors %||% character(0))
  if (!length(m1) || !length(m2)) return(NULL)

  list(
    M1 = m1, M2 = unique(c(m1, m2)), extras = setdiff(m2, m1),
    dropped_in_ml = character(0), allow_m2_eq_m1 = TRUE,
    note = sprintf(
      "lock_covariates_preset Model1=%s; Model2=%s",
      paste(m1, collapse = "+"), paste(unique(c(m1, m2)), collapse = "+")
    ),
    source = "lock_preset"
  )
}

#' 把解析结果写进 ctx 与 cox/logistic block config（供随后 assoc 使用）
ml_apply_assoc_covariate_rule_to_ctx <- function(ctx) {
  ac <- ml_assoc_covariate_cfg(ctx$config %||% list())
  if (!isTRUE(ac$enable)) return(ctx)

  locked <- ml_assoc_locked_preset_models(ctx)
  if (!is.null(locked)) {
    res <- locked
  } else {
    dat <- ctx$data$imputed %||% ctx$data$train %||% ctx$data$cleaned
    nm <- if (is.data.frame(dat)) names(dat) else NULL
    res <- ml_resolve_assoc_covariates(ctx, data_names = nm)
  }

  ctx$results$assoc_model1_factors <- res$M1
  ctx$results$assoc_model2_factors <- res$M2
  ctx$results$assoc_model3_factors <- res$M3 %||% res$M2
  ctx$results$assoc_model2_extras <- res$extras %||% setdiff(res$M2, res$M1)
  ctx$results$assoc_covariate_note <- res$note
  ctx$results$assoc_covariate_scheme <- res$scheme %||% "default"
  # 兼容旧键：不覆盖 VIF 用的 Model2Factors（ML 候选池），只写 assoc 专用
  ctx$results$cox_model1_covariates <- res$M1
  ctx$results$cox_model2_covariates <- res$extras %||% setdiff(res$M2, res$M1)
  ctx$results$logistic_model1_factors <- res$M1
  ctx$results$logistic_model2_factors <- res$M2
  ## 外验继承：assoc bundle 读 Model1/2，必须写成训练集名单（勿留 Age-only）
  ## literature_m123：另写 Model3Factors；勿覆盖 VIF 用的 Model2Factors 候选池
  if (identical(res$source, "primary_inherit")) {
    ctx$results$Model1Factors <- res$M1
    ctx$results$Model2Factors <- res$M2
    ctx$results$Model3Factors <- res$M3 %||% res$M2
  } else if (identical(res$scheme, "literature_m123")) {
    ctx$results$Model3Factors <- res$M3 %||% res$M2
  }

  .set_blk <- function(cfg, blk, m1, m2, allow_eq) {
    cfg[[blk]] <- modifyList(
      cfg[[blk]] %||% list(),
      list(
        model1_factors = m1,
        model2_factors = m2,
        allow_m2_eq_m1 = allow_eq,
        covariate_search = list(enable = FALSE)
      )
    )
    cfg
  }
  cfg <- ctx$config
  for (blk in c("cox_quartile", "cox_tertile", "cox_binary",
                "cox_quintile", "cox_sextile")) {
    cfg <- .set_blk(cfg, blk, res$M1, res$M2, isTRUE(res$allow_m2_eq_m1 %||% TRUE))
  }
  for (blk in c(
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted"
  )) {
    cfg <- .set_blk(cfg, blk, res$M1, res$M2, isTRUE(res$allow_m2_eq_m1 %||% TRUE))
  }
  # RCS / KM 用 Model1
  for (blk in c("rcs_prognosis", "rcs_incidence", "km_binary", "rcs_nhanes")) {
    cfg[[blk]] <- modifyList(
      cfg[[blk]] %||% list(),
      list(model1_factors = res$M1)
    )
  }
  ctx$config <- cfg

  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("assoc 协变量铁律: {res$note}")
    if (length(res$dropped_in_ml %||% character(0))) {
      cli::cli_alert_info(
        "单因素显著但已进 ML、故不进 Model2: {paste(res$dropped_in_ml, collapse = ', ')}"
      )
    }
    if (length(res$ml_in_model2 %||% character(0))) {
      cli::cli_alert_info(
        "VIF 池内已进 ML、仍纳入 Model2: {paste(res$ml_in_model2, collapse = ', ')}"
      )
    }
  }
  ctx
}
