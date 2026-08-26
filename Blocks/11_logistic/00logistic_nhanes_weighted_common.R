###############################################################################
#  NHANES / GLM / clogit Logistic 共用：协变量解析、VIF final 拆分、随机搜索、导出。
#  配置: config$logistic_nhanes_weighted（或 config$logistic_covariates）
###############################################################################

.lnw00_lcfg <- function(cfg) {
  cfg$logistic_nhanes_weighted %||% cfg$logistic_covariates %||% list()
}

# glm/clogit 拟完全分离时 profile CI 会抛 "profiling has found a better solution",
# 导致默认 Model1/2 表整体构建失败、整指标挂错。此处退回 Wald(normal) CI 保底。
logistic_safe_confint <- function(m) {
  tryCatch(
    suppressMessages(confint(m)),
    error = function(e) {
      ci <- tryCatch(suppressMessages(confint.default(m)), error = function(e2) NULL)
      if (!is.null(ci)) return(ci)
      co <- tryCatch(coef(m), error = function(e3) NULL)
      s  <- tryCatch(vcov(m), error = function(e4) NULL)
      if (is.null(co) || is.null(s) || nrow(s) == 0L) {
        vec <- rep(NA_real_, length(co))
        if (is.null(names(vec))) names(vec) <- names(co)
        return(as.matrix(vec))
      }
      se <- sqrt(diag(s)); z <- stats::qnorm(0.975)
      ci <- cbind(co - z * se, co + z * se)
      if (is.null(dimnames(ci))) {
        rownames(ci) <- names(co)
        colnames(ci) <- c("2.5 %", "97.5 %")
      }
      ci
    }
  )
}

# survey design 里的暴露若被 Table 1 转成 factor，分位/连续行会空。只改局部 design，不写回 ctx。
.lnw00_design_index_as_numeric <- function(design, index_var) {
  index_var <- as.character(index_var %||% "")[1L]
  if (is.null(design) || !nzchar(index_var)) return(design)
  vars <- design$variables
  if (is.null(vars) || !index_var %in% names(vars)) return(design)
  xv <- vars[[index_var]]
  if (is.numeric(xv) && !is.factor(xv)) return(design)
  xn <- if (exists("pipeline_index_as_numeric", mode = "function")) {
    pipeline_index_as_numeric(xv)
  } else {
    suppressWarnings(as.numeric(as.character(xv)))
  }
  design$variables[[index_var]] <- xn
  design
}

logistic_covariate_lcfg <- .lnw00_lcfg

.lnw00_pretty_var <- function(v) {
  if (exists("pipeline_var_display_name", mode = "function"))
    return(pipeline_var_display_name(v, cfg = NULL))
  gsub("_", " ", as.character(v), fixed = TRUE)
}

.lnw00_var_key <- function(x) {
  x <- tolower(as.character(x))
  gsub("[^a-z0-9]", "", gsub("_", " ", x, fixed = TRUE))
}

.lnw00_var_matches_patterns <- function(v, patterns) {
  vk <- .lnw00_var_key(v)
  if (!nzchar(vk)) return(FALSE)
  any(vapply(as.character(patterns), function(p) {
    pk <- .lnw00_var_key(p)
    nzchar(pk) && identical(vk, pk)
  }, logical(1L)))
}

.lnw00_get_vif_final_pool <- function(ctx) {
  pool <- as.character(
    ctx$results$vif_final_pass %||%
      ctx$results$Model2Factors %||%
      character(0)
  )
  unique(pool[nzchar(pool)])
}

.lnw00_model_exclude_vars <- function(cfg, lcfg, index_var) {
  nhanes_excl <- as.character((cfg$nhanes %||% list())$exclude_cols %||% character(0))
  id_col <- as.character((cfg$data %||% list())$id_column %||% character(0))
  # 默认不踢 BMI/Weight/Height：由 VIF/人体测量共线性协调决定去留
  extra <- as.character(lcfg$exclude_from_models %||% c("ID"))
  idx_excl <- if (exists("pipeline_index_exclude_vars", mode = "function")) {
    pipeline_index_exclude_vars(cfg)
  } else {
    as.character(index_var)
  }
  outcome_cols <- if (exists("pipeline_outcome_leak_columns", mode = "function")) {
    pipeline_outcome_leak_columns(cfg)
  } else {
    c("Disease", "Disease_Group")
  }
  unique(c(idx_excl, extra, id_col, nhanes_excl, outcome_cols))
}

.lnw00_model1_demographic_names <- function(cfg, bl_cfg = list()) {
  lcfg <- .lnw00_lcfg(cfg)
  demo <- as.character(bl_cfg$model1_demographic_names %||% lcfg$model1_demographic_names %||% character(0))
  if (!length(demo)) {
    for (sec in c("multivariate_prognosis", "multivariate_incidence_binary", "multivariate_nhanes")) {
      kw <- as.character((cfg[[sec]] %||% list())$demo_keywords %||% character(0))
      if (length(kw)) {
        demo <- kw
        break
      }
    }
  }
  if (!length(demo)) {
    demo <- as.character(((cfg$dual_db %||% list())$harmonization %||% list())$demo_keywords %||% character(0))
  }
  if (!length(demo)) {
    demo <- c("Age", "Gender", "Sex", "Race", "Smoking", "Smoke",
              "Education", "Marital_Status", "Marital")
  }
  unique(demo[nzchar(demo)])
}

.lnw00_lab_indicator_names <- function(cfg, bl_cfg = list()) {
  lcfg <- .lnw00_lcfg(cfg)
  med_cfg <- cfg$mediation_nhanes_weighted %||% list()
  lab_pool <- bl_cfg$lab_indicator_vars %||% lcfg$lab_indicator_vars %||%
    med_cfg$lab_indicator_vars %||% NULL
  if (is.null(lab_pool) || !length(lab_pool)) {
    if (exists(".default_laboratory_test_vars", mode = "function")) {
      lab_pool <- .default_laboratory_test_vars()
    } else {
      lab_pool <- character(0)
    }
  }
  unique(as.character(lab_pool))
}

.lnw00_is_lab_indicator_var <- function(v, lab_names) {
  .lnw00_var_matches_patterns(v, lab_names)
}

.lnw00_partition_lab_nonlab <- function(pool, lab_names) {
  pool <- unique(as.character(pool)[nzchar(as.character(pool))])
  if (!length(pool) || !length(lab_names)) {
    return(list(lab = character(0), nonlab = pool))
  }
  is_lab <- vapply(pool, .lnw00_is_lab_indicator_var, logical(1L), lab_names = lab_names)
  list(lab = pool[is_lab], nonlab = pool[!is_lab])
}

#' Model1：多因素VIF人口学 → 单因素VIF人口学 → 单因素VIF池全部非实验室（Model2 仅实验室）
.lnw00_resolve_model1_demographics <- function(mvif_pool, uvif_pool, design_vars, excl,
                                               index_var, demo_names, cfg = list(),
                                               bl_cfg = list(), age_significant = NULL) {
  design_candidates <- setdiff(
    as.character(design_vars)[nzchar(as.character(design_vars))],
    c(excl, as.character(index_var))
  )
  pick_demo <- function(pool) {
    pool <- intersect(as.character(pool)[nzchar(as.character(pool))], design_candidates)
    unique(pool[vapply(pool, .lnw00_var_matches_patterns, logical(1L), patterns = demo_names)])
  }

  tier <- "mvif_demo"
  M1 <- pick_demo(mvif_pool)
  if (length(M1)) {
    cli::cli_alert_info(
      "协变量选择: Model1 人口学取自多因素 VIF 池: {paste(M1, collapse = ', ')}"
    )
  }
  if (!length(M1) && length(uvif_pool)) {
    tier <- "uvif_demo"
    M1_uv <- pick_demo(uvif_pool)
    if (length(M1_uv) && exists("pipeline_uv_demo_fallback_model1", mode = "function")) {
      trim <- pipeline_uv_demo_fallback_model1(
        M1_uv, design_candidates, cfg, age_significant = age_significant
      )
      if (isFALSE(age_significant)) {
        cli::cli_alert_info(
          "协变量选择: 强加 Age 不显著，回退单因素人口学: {paste(M1_uv, collapse = ', ')}"
        )
      } else if (length(trim$dropped)) {
        cli::cli_alert_info(
          "协变量选择: 已有 Age，不把单因素人口学强加进 Model1: {paste(trim$dropped, collapse = ', ')}"
        )
      }
      M1 <- trim$M1
    } else {
      M1 <- M1_uv
    }
    if (length(M1)) {
      cli::cli_alert_info(
        "协变量选择: 多因素 VIF 无人口学，Model1 取自单因素 VIF 池: {paste(M1, collapse = ', ')}"
      )
    }
  }
  if (!length(M1)) {
    tier <- "nonlab_uvif_fallback"
    lab_names <- .lnw00_lab_indicator_names(cfg, bl_cfg)
    uvif_cands <- intersect(as.character(uvif_pool), design_candidates)
    non_lab <- .lnw00_partition_lab_nonlab(uvif_cands, lab_names)$nonlab
    if (!length(non_lab)) {
      mvif_cands <- intersect(as.character(mvif_pool), design_candidates)
      non_lab <- .lnw00_partition_lab_nonlab(mvif_cands, lab_names)$nonlab
      if (length(non_lab)) {
        cli::cli_alert_warning(
          "协变量选择: 单因素 VIF 池无非实验室，回退多因素 VIF 池非实验室: {paste(non_lab, collapse = ', ')}"
        )
      }
    }
    M1 <- non_lab
    if (length(M1)) {
      cli::cli_alert_info(
        "协变量选择: 三级回退 — Model1 = 单因素 VIF 池全部非实验室: {paste(M1, collapse = ', ')}"
      )
    } else if (length(uvif_cands)) {
      rs_cfg <- (cfg$logistic_nhanes_weighted %||% cfg$logistic_covariates %||% list())$random_search %||% list()
      seed <- as.integer(rs_cfg$seed %||% (cfg$imputation %||% list())$seed %||% 1234L)
      set.seed(seed)
      non_lab2 <- .lnw00_partition_lab_nonlab(uvif_cands, lab_names)$nonlab
      pick_from <- if (length(non_lab2)) non_lab2 else uvif_cands
      n_pick <- min(length(pick_from), max(1L, length(pick_from)))
      M1 <- sample(pick_from, n_pick, replace = FALSE)
      cli::cli_alert_warning(
        "协变量选择: 三级回退 — 从单因素 VIF 池随机抽取 Model1: {paste(M1, collapse = ', ')}"
      )
    } else {
      cli::cli_alert_warning(
        "协变量选择: 三级回退后 Model1 仍为空（单因素/多因素 VIF 池均无可用候选）"
      )
    }
  }
  if ("Age_Years" %in% M1 && "Age_Group" %in% M1) {
    M1 <- setdiff(M1, "Age_Group")
  }
  list(M1 = unique(M1), tier = tier)
}

.lnw00_split_vif_final_models <- function(pool, cfg, design, index_var, bl_cfg = list(),
                                          screen_pool = character(0)) {
  lcfg <- .lnw00_lcfg(cfg)
  demo_names <- .lnw00_model1_demographic_names(cfg, bl_cfg)
  classify_demo_names <- as.character(bl_cfg$demo_factor_names %||% lcfg$demo_factor_names %||% c(
    demo_names, "PIR", "Income"
  ))

  design_vars <- if (is.list(design) && !is.null(design$variables)) {
    names(design$variables)
  } else if (is.data.frame(design)) {
    names(design)
  } else {
    character(0)
  }

  excl <- .lnw00_model_exclude_vars(cfg, lcfg, index_var)
  mvif_pool <- unique(as.character(pool)[nzchar(as.character(pool))])
  uvif_pool <- unique(as.character(screen_pool)[nzchar(as.character(screen_pool))])

  avail <- intersect(mvif_pool, design_vars)
  avail <- avail[nzchar(avail)]
  avail <- setdiff(avail, excl)
  avail <- setdiff(avail, as.character(index_var))
  if (!length(avail) && length(uvif_pool)) {
    cli::cli_alert_warning(
      "协变量选择: 多因素 VIF 池为空，工作池回退至单因素 VIF 池（{length(uvif_pool)} 个候选）"
    )
    avail <- intersect(uvif_pool, design_vars)
    avail <- setdiff(setdiff(avail[nzchar(avail)], excl), as.character(index_var))
  }
  if ("Age_Years" %in% avail && "Age_Group" %in% avail) {
    avail <- setdiff(avail, "Age_Group")
  }

  age_sig <- if (exists("pipeline_forced_age_is_significant", mode = "function") &&
                 is.data.frame(design)) {
    pipeline_forced_age_is_significant(design, cfg, index_var)
  } else {
    NULL
  }
  resolved <- .lnw00_resolve_model1_demographics(
    mvif_pool, uvif_pool, design_vars, excl, index_var, classify_demo_names,
    cfg = cfg, bl_cfg = bl_cfg, age_significant = age_sig
  )
  M1 <- resolved$M1
  model1_tier <- resolved$tier
  lab_names <- .lnw00_lab_indicator_names(cfg, bl_cfg)
  part_avail <- .lnw00_partition_lab_nonlab(avail, lab_names)

  demo_in_avail <- avail[vapply(avail, .lnw00_var_matches_patterns, logical(1L),
                               patterns = classify_demo_names)]
  demo_add <- setdiff(demo_in_avail, M1)
  if (length(demo_add)) {
    M1 <- unique(c(M1, demo_add))
    cli::cli_alert_info(
      "协变量选择: Model1 补入人口学（含社会经济）: {paste(demo_add, collapse = ', ')}"
    )
  }

  uvif_cands <- intersect(uvif_pool, design_vars)
  uvif_cands <- setdiff(setdiff(uvif_cands[nzchar(uvif_cands)], excl), as.character(index_var))
  m1_search <- .lnw00_partition_lab_nonlab(uvif_cands, lab_names)$nonlab

  if (identical(model1_tier, "nonlab_uvif_fallback")) {
    uvif_lab <- .lnw00_partition_lab_nonlab(uvif_cands, lab_names)$lab
    lab_hits <- unique(setdiff(uvif_lab, M1))
    M2 <- unique(c(M1, lab_hits))
    model2_lab_only <- TRUE
    m2_search_pool <- lab_hits
    cli::cli_alert_info(
      "协变量选择: 三级回退 — Model2 = Model1 + 仅实验室指标 ({length(lab_hits)}): {paste(lab_hits, collapse = ', ')}"
    )
  } else {
    m2_add <- setdiff(avail, M1)
    M2 <- unique(c(M1, m2_add))
    model2_lab_only <- FALSE
    m2_search_pool <- m2_add
    cli::cli_alert_info(
      "协变量选择: Model2 = Model1 + 多因素 VIF 池其余变量 ({length(m2_add)}): {paste(m2_add, collapse = ', ')}"
    )
  }

  list(
    M1 = M1, M2 = M2, pool = avail, unclassified = character(0),
    model1_tier = model1_tier, model2_lab_only = model2_lab_only,
    m1_search_pool = m1_search, m2_search_pool = m2_search_pool
  )
}

.lnw00_resolve_models <- function(ctx, cfg, bl_cfg, design, index_var = NULL) {
  lcfg <- .lnw00_lcfg(cfg)
  index_var <- as.character(
    index_var %||% bl_cfg$index_var %||%
      (cfg$logistic %||% list())$index_var %||%
      (cfg$incidence %||% list())$index_var %||% "BMI"
  )[1L]

  m1_manual <- as.character(
    bl_cfg$model1_factors %||%
      ctx$results$assoc_model1_factors %||%
      lcfg$model1_factors %||% character(0)
  )
  m2_manual <- as.character(
    bl_cfg$model2_factors %||%
      ctx$results$assoc_model2_factors %||%
      lcfg$model2_factors %||% character(0)
  )
  use_manual <- length(m1_manual) > 0L && length(m2_manual) > 0L
  if (use_manual) {
    M1 <- m1_manual
    M2 <- m2_manual
    cli::cli_alert_info("logistic NHANES: 使用 config 手动指定 Model1/Model2 协变量")
    M1 <- intersect(M1, names(design$variables))
    M2 <- intersect(M2, names(design$variables))
    M1 <- setdiff(M1, index_var)
    M2 <- setdiff(M2, index_var)
    M2 <- unique(c(M1, M2))
    if (length(M1) && length(M2)) M2 <- c(M1, setdiff(M2, M1))
    if (exists("logistic_constrain_model_factors", mode = "function")) {
      cn <- logistic_constrain_model_factors(M1, M2, cfg, index_var)
      M1 <- cn$M1
      M2 <- cn$M2
    }
    if (exists("pipeline_merge_force_covariates", mode = "function")) {
      merged <- pipeline_merge_force_covariates(M1, M2, names(design$variables), cfg)
      M1 <- merged$M1
      M2 <- merged$M2
    }
    return(list(M1 = M1, M2 = M2, index_var = index_var))
  }

  # 闸门 B 已对齐：Table 2 / RCS / 敏感性 GLM 强制同套 Model1/Model2
  if (isTRUE(ctx$results$dual_db_covariate_harmonized)) {
    M1 <- as.character(ctx$results$Model1Factors %||% character(0))
    M2 <- as.character(ctx$results$Model2Factors %||% character(0))
    M1 <- intersect(M1, names(design$variables))
    M2 <- intersect(M2, names(design$variables))
    M1 <- setdiff(M1, index_var)
    M2 <- setdiff(M2, index_var)
    if (length(M1) && length(M2)) {
      M2 <- c(M1, setdiff(M2, M1))
      if (exists("pipeline_merge_force_covariates", mode = "function")) {
        merged <- pipeline_merge_force_covariates(M1, M2, names(design$variables), cfg)
        M1 <- merged$M1
        M2 <- merged$M2
      }
      cli::cli_alert_info("logistic NHANES: 使用闸门 B 双库统一 Model1/Model2")
      return(list(M1 = M1, M2 = M2, index_var = index_var))
    }
  }

  if (isTRUE(ctx$results$nhanes_logistic_covariate_search_applied) ||
      isTRUE(ctx$results$logistic_covariate_search_applied)) {
    M1 <- as.character(ctx$results$nhanes_logistic_M1 %||% character(0))
    M2 <- as.character(ctx$results$nhanes_logistic_M2 %||% character(0))
    M1 <- intersect(M1, names(design$variables))
    M2 <- intersect(M2, names(design$variables))
    M1 <- setdiff(M1, index_var)
    M2 <- setdiff(M2, index_var)
    if (length(M1) && length(M2)) M2 <- c(M1, setdiff(M2, M1))
    if (exists("pipeline_merge_force_covariates", mode = "function")) {
      merged <- pipeline_merge_force_covariates(M1, M2, names(design$variables), cfg)
      M1 <- merged$M1
      M2 <- merged$M2
    }
    cli::cli_alert_info("logistic NHANES: 使用随机搜索后的 Model1/Model2")
    if (exists("logistic_constrain_model_factors", mode = "function")) {
      cn <- logistic_constrain_model_factors(M1, M2, cfg, index_var)
      M1 <- cn$M1
      M2 <- cn$M2
      if (exists("pipeline_merge_force_covariates", mode = "function")) {
        merged2 <- pipeline_merge_force_covariates(M1, M2, names(design$variables), cfg)
        M1 <- merged2$M1
        M2 <- merged2$M2
      }
    }
    return(list(M1 = M1, M2 = M2, index_var = index_var))
  }

  m1_manual <- as.character(
    bl_cfg$model1_factors %||%
      ctx$results$assoc_model1_factors %||%
      lcfg$model1_factors %||% character(0)
  )
  m2_manual <- as.character(
    bl_cfg$model2_factors %||%
      ctx$results$assoc_model2_factors %||%
      lcfg$model2_factors %||% character(0)
  )
  use_manual <- length(m1_manual) > 0L && length(m2_manual) > 0L

  if (use_manual) {
    M1 <- m1_manual
    M2 <- m2_manual
    cli::cli_alert_info("logistic NHANES: 使用 config 手动指定 Model1/Model2 协变量")
  } else {
    pool <- .lnw00_get_vif_final_pool(ctx)
    if (!length(pool)) {
      pool <- as.character(
        ctx$results$nhanes_logistic_M2 %||% ctx$results$Model2Factors %||% character(0)
      )
      if (length(pool)) {
        cli::cli_alert_warning(
          "logistic NHANES: vif_final_pass 为空，fallback 到 ctx$results$Model2Factors"
        )
      }
    }
    screen_pool <- as.character(
      ctx$results$vif_screen_pass %||% ctx$results$vif_screen_pass_weighted %||% character(0)
    )
    split <- .lnw00_split_vif_final_models(
      pool, cfg, design, index_var, bl_cfg, screen_pool = screen_pool
    )
    M1 <- split$M1
    M2 <- split$M2
    ctx$results$nhanes_logistic_model1_tier <- split$model1_tier %||% "mvif_demo"
    ctx$results$nhanes_logistic_model2_lab_only <- isTRUE(split$model2_lab_only)
    if (!length(M1) || !length(M2)) {
      cli::cli_alert_warning(
        "logistic NHANES: VIF final 拆分后 Model 为空 (M1={length(M1)}, M2={length(M2)})；请先运行 multicollinearity_nhanes_final"
      )
    } else {
      cli::cli_alert_info(
        "logistic NHANES: VIF final → Model1 ({length(M1)}): {paste(M1, collapse = ', ')}"
      )
      cli::cli_alert_info(
        "logistic NHANES: VIF final → Model2 ({length(M2)}): {paste(M2, collapse = ', ')}"
      )
    }
  }

  if ("Age_Years" %in% M1 && "Age_Group" %in% M1) M1 <- setdiff(M1, "Age_Group")
  M1 <- intersect(M1, names(design$variables))
  M2 <- intersect(M2, names(design$variables))
  M1 <- setdiff(M1, index_var)
  M2 <- setdiff(M2, index_var)
  M2 <- unique(c(M1, M2))
  if (length(M1) && length(M2)) {
    M2 <- c(M1, setdiff(M2, M1))
  }

  # 调整模型强制纳入 Age + Sex/Gender（数据有则加）
  force_vars <- character(0)
  if (exists("pipeline_dedupe_force_demo_vars", mode = "function") &&
      exists("pipeline_force_include_covariates", mode = "function")) {
    force_vars <- pipeline_dedupe_force_demo_vars(
      pipeline_force_include_covariates(cfg), names(design$variables)
    )
  }
  if (exists("pipeline_merge_force_covariates", mode = "function") && length(force_vars)) {
    before_m1 <- M1
    before_m2 <- M2
    merged <- pipeline_merge_force_covariates(M1, M2, names(design$variables), cfg)
    M1 <- merged$M1
    M2 <- merged$M2
    add_m1 <- setdiff(M1, before_m1)
    add_m2 <- setdiff(M2, before_m2)
    if (length(add_m1) || length(add_m2)) {
      cli::cli_alert_info(
        "logistic: 强制年龄/性别 Model1+={paste(add_m1, collapse=', ')}; Model2+={paste(add_m2, collapse=', ')}"
      )
    }
  }

  if (exists("logistic_constrain_model_factors", mode = "function")) {
    cn <- logistic_constrain_model_factors(M1, M2, cfg, index_var)
    M1 <- cn$M1
    M2 <- cn$M2
    # 截断后再并一次 force；若超上限则优先踢临床协变量
    if (exists("pipeline_merge_force_covariates", mode = "function") && length(force_vars)) {
      merged2 <- pipeline_merge_force_covariates(M1, M2, names(design$variables), cfg)
      M1 <- merged2$M1
      M2 <- merged2$M2
      max_m2 <- as.integer(
        (cfg$logistic %||% list())$model2_max_covariates %||%
          (cfg$incidence %||% list())$model2_max_covariates %||% 10L
      )[1L]
      if (is.finite(max_m2) && length(M2) > max_m2) {
        force_keep <- intersect(force_vars, M2)
        M1 <- unique(c(intersect(M1, force_keep), force_keep))
        clinical <- setdiff(M2, M1)
        keep_clin <- utils::head(clinical, max(0L, max_m2 - length(M1)))
        M2 <- unique(c(M1, keep_clin))
        cli::cli_alert_info(
          "logistic: Model2 在上限 {max_m2} 下优先保留 Age/Sex，clinical={length(keep_clin)}"
        )
      }
    }
  }

  list(M1 = M1, M2 = M2, index_var = index_var)
}

.lnw00_table_footnotes <- function(M1, M2, M3 = NULL, m3_significant = NULL) {
  if (exists("logistic_glm_table_footnotes", mode = "function")) {
    return(logistic_glm_table_footnotes(M1, M2, M3, m3_significant))
  }
  pipeline_model3_table_footnotes(M1, M2, M3, m3_significant)
}

.lnw00_store_models <- function(ctx, M1, M2, M3 = NULL, m3_sig = NULL, final = NULL) {
  ctx$results$nhanes_logistic_M1 <- M1
  ctx$results$nhanes_logistic_M2 <- M2
  ctx$results$logistic_model1_factors <- M1
  ctx$results$logistic_model2_factors <- M2
  ctx$results$rcs_nhanes_model1_factors <- M1
  final_use <- as.character(final %||% M2)
  ctx$results$rcs_nhanes_model2_factors <- if (length(final_use)) final_use else M2
  if (exists("pipeline_store_model3", mode = "function")) {
    ctx <- pipeline_store_model3(
      ctx,
      M3 %||% as.character(ctx$results$Model3Factors %||% character(0)),
      isTRUE(m3_sig %||% ctx$results$model3_significant),
      final_use,
      announce = FALSE
    )
  }
  ctx
}

.lnw00_attach_model3_table <- function(ctx, cfg, design, M1, M2, raw_levels,
                                       build_table_fn, method = "trend_or_any_group",
                                       threshold = 0.05, index_var = NULL) {
  if (!exists("pipeline_apply_model3_after_m2", mode = "function")) {
    return(list(ctx = ctx, tb = NULL, M3 = character(0), m3_sig = FALSE, final = M2, include_m3 = FALSE))
  }
  pack <- pipeline_apply_model3_after_m2(
    ctx, cfg, M2, names(design$variables), index_var,
    method = method, threshold = threshold
  )
  ctx <- pack$ctx
  if (!isTRUE(pack$include_m3)) return(pack)
  tb <- tryCatch(build_table_fn(M1, M2, pack$M3), error = function(e) {
    cli::cli_alert_warning("Model3 表拟合失败，回退 Model2: {e$message}")
    NULL
  })
  if (is.null(tb)) {
    ctx <- pipeline_store_model3(ctx, pack$M3, FALSE, M2)
    pack$ctx <- ctx
    pack$m3_sig <- FALSE
    pack$final <- M2
    pack$tb <- NULL
    return(pack)
  }
  m3_sig <- pipeline_model3_sig_from_table(tb, raw_levels, method, threshold)
  final <- pipeline_finalize_adjusted_factors(M2, pack$M3, m3_sig)
  ctx <- pipeline_store_model3(ctx, pack$M3, m3_sig, final)
  pack$ctx <- ctx
  pack$tb <- tb
  pack$m3_sig <- m3_sig
  pack$final <- final
  pack
}

# 双库初筛：非选中分位不落盘；无主表时 binary 末档必须导出（占位 dual_db$enable=TRUE 的单库也要有 Table 2）
.lnw00_should_skip_table2_export <- function(ctx, cfg, as_main = FALSE, caption = "",
                                            family = NULL) {
  if (isTRUE(as_main)) return(FALSE)
  cap <- as.character(caption %||% "")[1L]
  if (grepl("RCS", cap, ignore.case = TRUE)) return(FALSE)
  if (grepl("dual-DB unified", cap, ignore.case = TRUE)) return(FALSE)
  if (!isTRUE((cfg$dual_db %||% list())$enable)) return(FALSE)
  if (isTRUE((ctx$results %||% list())$nhanes_logistic_exported_main)) return(TRUE)
  fam <- as.character(family %||% "")[1L]
  if (identical(fam, "binary")) return(FALSE)
  TRUE
}

# 主文 Table 2：extend_* 选中档，或闸门未选出时 binary 末档兜底
.lnw00_weighted_export_as_main <- function(ctx, family, is_rcs = FALSE, gate_enable = TRUE,
                                          crude_significant = FALSE) {
  if (isTRUE(is_rcs)) return(FALSE)
  family <- as.character(family %||% "")[1L]
  if (!isTRUE(gate_enable)) {
    return(isTRUE(crude_significant) || identical(family, "binary"))
  }
  branch <- as.character((ctx$results %||% list())$logistic_branch %||% "")[1L]
  if (identical(branch, paste0("extend_", family))) return(TRUE)
  if (identical(family, "binary") && !grepl("^extend_(quartile|tertile|quintile)$", branch)) {
    return(TRUE)
  }
  FALSE
}

.lnw00_export_table2 <- function(ctx, cfg, bl_cfg, rt, caption, as_main = FALSE,
                                 table_footnotes = NULL, family = NULL) {
  # 双库：初筛非选中分位只落 results、不导出发表表（避免 S7/S8 堆满各档）
  # RCS / dual-DB unified / binary 末档兜底仍导出
  if (isTRUE(.lnw00_should_skip_table2_export(ctx, cfg, as_main, caption, family = family))) {
    return(invisible(list(rt = format_logistic_table2_pvalues(rt), filepath = NA_character_)))
  }
  rt2 <- format_logistic_table2_pvalues(rt)
  h1 <- as.character(rt2[1L, ])
  h2 <- as.character(rt2[2L, ])
  body <- rt2[-c(1L, 2L), , drop = FALSE]
  rownames(body) <- NULL
  colnames(body) <- paste0("V", seq_len(ncol(body)))

  fn <- bl_cfg$table_filename
  if (is.null(fn) || !nzchar(fn)) {
    pub <- pub_paths(
      ctx, ctx$output_dir_tables,
      if (isTRUE(as_main)) "main_table" else "supp_table",
      caption, "xlsx"
    )
    fp <- pub$filepath
    title <- pub$title
  } else {
    fp <- file.path(ctx$output_dir_tables, fn)
    title <- pub_title(ctx, if (isTRUE(as_main)) "main_table" else "supp_table", caption)
  }

  tryCatch(
    export_sci_table(
      body, fp, title = title,
      header_row1 = h1, header_row2 = h2,
      latex_include_colnames = FALSE,
      table_footnotes = table_footnotes
    ),
    error = function(e) cli::cli_alert_warning("logistic NHANES export failed: {e$message}")
  )
  invisible(list(rt = rt2, filepath = fp))
}

.lnw00_cascade_selected <- function(ctx) {
  as.character(ctx$results[["nhanes_logistic_selected_scheme"]] %||% "")
}

.lnw00_gate_active <- function(ctx) {
  cfg <- ctx$config %||% list()
  for (k in c(
    "logistic_quartile_nhanes_weighted",
    "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted"
  )) {
    if (isTRUE((cfg[[k]] %||% list())$gate_enable)) return(TRUE)
  }
  FALSE
}

.lnw00_design_from_rcs_groups <- function(ctx, design, bl_cfg) {
  gv <- as.character(bl_cfg$group_var %||% ctx$results$nhanes_rcs_group_col %||% "")[1L]
  if (!nzchar(gv)) {
    stop("logistic NHANES (rcs): group_var / nhanes_rcs_group_col 未设置；请先运行 rcs_nhanes。", call. = FALSE)
  }
  if (is.null(design$variables) || !gv %in% names(design$variables)) {
    stop("logistic NHANES (rcs): 分组列 '", gv, "' 不在 survey design 中。", call. = FALSE)
  }
  xv <- design$variables[[gv]]
  raw_levels <- levels(factor(xv, exclude = NULL))
  if (length(raw_levels) < 2L) {
    # 唯一值过少 / 无 RCS 切点时只有 "All" 一档：由调用方跳过，勿硬崩整指标
    stop("SKIP_RCS_GROUP_LEVELS: RCS 分组水平不足（n_levels=", length(raw_levels), "）。", call. = FALSE)
  }
  grp_chr <- as.character(xv)
  des2 <- stats::update(
    design,
    Group = factor(grp_chr, levels = raw_levels),
    Num = as.numeric(factor(grp_chr, levels = raw_levels))
  )
  cutoffs <- setNames(rep("", length(raw_levels)), raw_levels)
  pc <- suppressWarnings(as.numeric(ctx$results$nhanes_rcs_primary_cutoff %||% NA_real_)[1L])
  if (is.finite(pc) && length(raw_levels) >= 2L) {
    cutoffs[1L] <- paste0("< ", fmt_num(pc))
    cutoffs[length(raw_levels)] <- paste0("\u2265 ", fmt_num(pc))
  }
  list(
    design = des2,
    raw_levels = raw_levels,
    cutoffs = cutoffs
  )
}

.lnw00_should_skip_cascade_block <- function(block_name, ctx) {
  # 双库初筛：三档都要跑完并落表，供闸门 C 统一重导 Table 2
  dual <- ctx$config$dual_db %||% list()
  if (isTRUE(dual$enable) && !isTRUE(ctx$results$dual_db_logistic_unified_locked)) {
    return(FALSE)
  }
  if (.lnw00_gate_active(ctx)) return(FALSE)
  selected <- .lnw00_cascade_selected(ctx)
  if (!nzchar(selected)) return(FALSE)
  if (identical(block_name, "logistic_tertile_nhanes_weighted") && identical(selected, "quartile")) {
    return(TRUE)
  }
  if (identical(block_name, "logistic_binary_nhanes_weighted") &&
      selected %in% c("quartile", "tertile")) {
    return(TRUE)
  }
  sens_glm <- c(
    logistic_quartile_glm = "quartile",
    logistic_tertile_glm  = "tertile",
    logistic_binary_glm   = "binary"
  )
  if (block_name %in% names(sens_glm)) {
    # NHANES 加权主分析后的未加权敏感性：只跑 Table2 选中的那一档
    if (!is.null(ctx$results$logistic_table2_weighted) ||
        !is.null(ctx$results$nhanes_logistic_table2)) {
      want <- as.character(
        ctx$results$nhanes_logistic_selected_scheme %||%
          ctx$results$logistic_grouping_scheme %||% selected
      )[1L]
      if (nzchar(want) && !identical(want, sens_glm[[block_name]])) {
        return(TRUE)
      }
    } else if (!identical(selected, sens_glm[[block_name]])) {
      return(TRUE)
    }
  }
  FALSE
}

.lnw00_parse_pval <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x) || identical(x, "NA")) return(NA_real_)
  if (grepl("^\\s*<", x)) return(0.0001)
  suppressWarnings(as.numeric(x))
}

.lnw00_table_pvals <- function(tb) {
  nr <- nrow(tb)
  if (nr < 2L) {
    return(list(
      trend_crude = NA_real_, trend_m1 = NA_real_, trend_m2 = NA_real_,
      last_crude = NA_real_, last_m1 = NA_real_, last_m2 = NA_real_,
      last_m2_or = NA_real_
    ))
  }
  trend_row <- tb[nr, , drop = TRUE]
  last_grp <- tb[nr - 1L, , drop = TRUE]
  list(
    trend_crude = .lnw00_parse_pval(trend_row[6L]),
    trend_m1    = .lnw00_parse_pval(trend_row[9L]),
    trend_m2    = .lnw00_parse_pval(trend_row[12L]),
    last_crude  = .lnw00_parse_pval(last_grp[6L]),
    last_m1     = .lnw00_parse_pval(last_grp[9L]),
    last_m2     = .lnw00_parse_pval(last_grp[12L]),
    last_m2_or  = suppressWarnings(as.numeric(as.character(last_grp[10L])))
  )
}

.lnw00_crude_trend_significant <- function(pvals, threshold) {
  is.finite(pvals$trend_crude) && pvals$trend_crude < threshold
}

.lnw00_model1_significant <- function(pvals, threshold) {
  is.finite(pvals$trend_m1) && pvals$trend_m1 < threshold
}

.lnw00_model2_significant <- function(pvals, threshold, rs_cfg = list()) {
  if (isTRUE(rs_cfg$require_highest_group_or_gt1 %||% FALSE)) {
    or_ok <- is.finite(pvals$last_m2_or) && pvals$last_m2_or > 1
    p_ok  <- is.finite(pvals$last_m2) && pvals$last_m2 < threshold
    return(or_ok && p_ok)
  }
  m2_trend <- is.finite(pvals$trend_m2) && pvals$trend_m2 < threshold
  m2_grp   <- is.finite(pvals$last_m2) && pvals$last_m2 < threshold
  m2_trend || m2_grp
}

.lnw00_models_adjusted_significant <- function(pvals, threshold, rs_cfg = list()) {
  m1_ok <- is.finite(pvals$trend_m1) && pvals$trend_m1 < threshold
  m2_ok <- is.finite(pvals$trend_m2) && pvals$trend_m2 < threshold
  if (!m1_ok || !m2_ok) return(FALSE)
  if (isTRUE(rs_cfg$require_highest_group_or_gt1 %||% FALSE)) {
    or_ok <- is.finite(pvals$last_m2_or) && pvals$last_m2_or > 1
    p_ok  <- is.finite(pvals$last_m2) && pvals$last_m2 < threshold
    if (!or_ok || !p_ok) return(FALSE)
  }
  if (isTRUE(rs_cfg$require_all_six_p %||% FALSE)) {
    vals <- c(
      pvals$trend_crude, pvals$trend_m1, pvals$trend_m2,
      pvals$last_crude, pvals$last_m1, pvals$last_m2
    )
    if (!all(is.finite(vals)) || !all(vals < threshold)) return(FALSE)
  }
  TRUE
}

.lnw00_summary_coefs <- function(fit) {
  if (is.null(fit)) return(NULL)
  suppressWarnings(summary(fit)$coefficients)
}

# svyglm 在调查自由度耗尽时 Pr(>|t|) 常为 NaN，但 Estimate/SE 仍可用；
# OR/CI 已用正态近似，P 同步回退 Wald z，避免 Model3 空 P。
.lnw00_pvalue_from_coef <- function(est, se, pv = NA_real_) {
  pv <- suppressWarnings(as.numeric(pv)[1L])
  if (is.finite(pv)) return(pv)
  est <- suppressWarnings(as.numeric(est)[1L])
  se <- suppressWarnings(as.numeric(se)[1L])
  if (is.finite(est) && is.finite(se) && isTRUE(se > 0)) {
    return(2 * stats::pnorm(-abs(est / se)))
  }
  NA_real_
}

.lnw00_coef_row <- function(fit, row_name) {
  if (is.null(fit)) return(rep("", 3L))
  sm <- .lnw00_summary_coefs(fit)
  if (is.null(sm) || !row_name %in% rownames(sm)) return(rep("", 3L))
  est <- sm[row_name, "Estimate", drop = TRUE]
  se <- sm[row_name, "Std. Error", drop = TRUE]
  pr_i <- grep("^Pr\\(", colnames(sm))
  pv <- if (length(pr_i)) suppressWarnings(as.numeric(sm[row_name, pr_i[1L]])) else NA_real_
  pv <- .lnw00_pvalue_from_coef(est, se, pv)
  c(
    fmt_num(exp(est)),
    paste0("(", fmt_num(exp(est - 1.96 * se)), ",", fmt_num(exp(est + 1.96 * se)), ")"),
    fmt_pval(pv)
  )
}

.lnw00_logistic_covariates_locked <- function(ctx, cfg, bl_cfg = list()) {
  if (isTRUE(ctx$results$dual_db_covariate_harmonized)) return(TRUE)
  lcfg <- .lnw00_lcfg(cfg)
  # VIF final 后默认锁定；仅当 random_search$enable=TRUE 时允许搜协变量改写
  rs <- lcfg$random_search %||% list()
  vf <- as.character(ctx$results$vif_final_pass %||% character(0))
  vf <- vf[nzchar(vf)]
  if (length(vf) && !isTRUE(rs$enable %||% FALSE)) return(TRUE)
  m1 <- as.character(bl_cfg$model1_factors %||% lcfg$model1_factors %||% character(0))
  m2 <- as.character(bl_cfg$model2_factors %||% lcfg$model2_factors %||% character(0))
  length(m1) > 0L && length(m2) > 0L
}

.lnw00_need_covariate_search <- function(tb, threshold, crude_sig, rs_cfg = list(),
                                         ctx = NULL, cfg = NULL, bl_cfg = list()) {
  # 默认关闭随机搜协变量，避免 Table2 与 S7/锁定集分叉
  if (!isTRUE(rs_cfg$enable %||% FALSE)) return(FALSE)
  if (!is.null(ctx) && !is.null(cfg) && .lnw00_logistic_covariates_locked(ctx, cfg, bl_cfg)) {
    return(FALSE)
  }
  if (!isTRUE(crude_sig)) return(FALSE)
  pv <- .lnw00_table_pvals(tb)
  !.lnw00_models_adjusted_significant(pv, threshold, rs_cfg)
}

.lnw00_triple_models_significant <- function(pvals, threshold, rs_cfg = list()) {
  .lnw00_crude_trend_significant(pvals, threshold) &&
    .lnw00_model1_significant(pvals, threshold) &&
    .lnw00_model2_significant(pvals, threshold, rs_cfg)
}

.lnw00_power_subsets_nonempty <- function(x) {
  x <- unique(as.character(x[nzchar(x)]))
  if (!length(x)) return(list())
  out <- list()
  for (k in seq_len(length(x))) {
    out <- c(out, combn(x, k, simplify = FALSE))
  }
  out
}

.lnw00_tune_covariates_triple_sig <- function(
    M1, M2, build_table_fn, threshold, rs_cfg = list()) {
  M1 <- unique(as.character(M1[nzchar(M1)]))
  M2 <- unique(as.character(M2[nzchar(M2)]))
  clinical_extra <- setdiff(M2, M1)
  subsets <- .lnw00_power_subsets_nonempty(M1)
  if (!length(subsets)) {
    return(list(M1 = M1, M2 = M2, tb = NULL, succeeded = FALSE, moved_vars = character(0)))
  }
  subsets <- subsets[order(-vapply(subsets, length, integer(1L)))]
  best_p <- Inf
  best <- NULL
  for (M1_try in subsets) {
    removed <- setdiff(M1, M1_try)
    M2_try <- unique(c(M1_try, removed, clinical_extra))
    tb_try <- suppressWarnings(tryCatch(
      build_table_fn(M1_try, M2_try), error = function(e) NULL
    ))
    if (is.null(tb_try)) next
    pv <- .lnw00_table_pvals(tb_try)
    if (!.lnw00_triple_models_significant(pv, threshold, rs_cfg)) next
    p_score <- pv$trend_m2
    if (!is.finite(p_score)) p_score <- pv$last_m2
    if (!is.finite(p_score)) p_score <- pv$trend_m1
    if (!is.finite(p_score)) p_score <- Inf
    if (p_score < best_p) {
      best_p <- p_score
      best <- list(
        M1 = M1_try, M2 = M2_try, tb = tb_try,
        moved_vars = removed
      )
    }
  }
  if (is.null(best)) {
    return(list(M1 = M1, M2 = M2, tb = NULL, succeeded = FALSE, moved_vars = character(0)))
  }
  if (length(best$moved_vars)) {
    cli::cli_alert_success(
      "三模型调协变量: {paste(best$moved_vars, collapse = ', ')} 移出 Model1、保留在 Model2 | Model1={paste(best$M1, collapse = ', ')}"
    )
  } else {
    cli::cli_alert_success(
      "三模型调协变量: Model1={paste(best$M1, collapse = ', ')}, Model2={paste(best$M2, collapse = ', ')}"
    )
  }
  list(
    M1 = best$M1, M2 = best$M2, tb = best$tb,
    succeeded = TRUE, moved_vars = best$moved_vars
  )
}

.lnw00_apply_covariate_tuning <- function(
    M1, M2, tb, build_table_fn, threshold, rs_cfg, ctx, cfg, bl_cfg, crude_sig) {
  if (!isTRUE(crude_sig)) {
    return(list(M1 = M1, M2 = M2, tb = tb, tuned = FALSE, ctx = ctx))
  }
  if (.lnw00_logistic_covariates_locked(ctx, cfg, bl_cfg)) {
    return(list(M1 = M1, M2 = M2, tb = tb, tuned = FALSE, ctx = ctx, run_random = FALSE))
  }
  pv <- .lnw00_table_pvals(tb)
  need_triple <- isTRUE(rs_cfg$require_triple_model_sig %||% TRUE)
  if (!need_triple && .lnw00_models_adjusted_significant(pv, threshold, rs_cfg)) {
    return(list(M1 = M1, M2 = M2, tb = tb, tuned = FALSE, ctx = ctx))
  }
  if (need_triple && .lnw00_triple_models_significant(pv, threshold, rs_cfg)) {
    return(list(M1 = M1, M2 = M2, tb = tb, tuned = FALSE, ctx = ctx))
  }

  tuned <- FALSE
  if (need_triple || !.lnw00_model2_significant(pv, threshold, rs_cfg)) {
    tr <- .lnw00_tune_covariates_triple_sig(M1, M2, build_table_fn, threshold, rs_cfg)
    if (isTRUE(tr$succeeded)) {
      M1 <- tr$M1
      M2 <- tr$M2
      tb <- tr$tb
      tuned <- TRUE
      ctx$results$logistic_triple_tune_applied <- TRUE
      ctx$results$logistic_m1_to_m2_fallback <- tr$moved_vars
      if (length(tr$moved_vars) && exists("dual_db_save_logistic_covariates", mode = "function")) {
        root <- normalizePath(
          (cfg$project %||% list())$root %||% getwd(),
          winslash = "/", mustWork = FALSE
        )
        dual_db_save_logistic_covariates(root, cfg, M1, M2)
      }
    }
  }

  pv2 <- .lnw00_table_pvals(tb)
  locked <- .lnw00_logistic_covariates_locked(ctx, cfg, bl_cfg)
  if (!tuned && !locked && isTRUE(rs_cfg$enable %||% TRUE) &&
      !.lnw00_models_adjusted_significant(pv2, threshold, rs_cfg)) {
    return(list(M1 = M1, M2 = M2, tb = tb, tuned = FALSE, ctx = ctx, run_random = TRUE))
  }
  list(M1 = M1, M2 = M2, tb = tb, tuned = tuned, ctx = ctx, run_random = FALSE)
}

.lnw00_random_search_covariates <- function(
    ctx, cfg, M1, search_pool, build_table_fn, crude_sig, rs_cfg = list(), bl_cfg = list(),
    lab_only_m2 = FALSE) {
  rs_cfg <- rs_cfg %||% list()
  lcfg <- .lnw00_lcfg(cfg)
  cascade <- lcfg$cascade %||% list()
  p_thr <- as.numeric(rs_cfg$p_threshold %||% cascade$crude_p_threshold %||% 0.05)[1L]
  max_attempts <- as.integer(rs_cfg$max_attempts %||% 100L)
  max_inner <- as.integer(rs_cfg$max_inner_attempts %||% 20L)
  max_total_fits <- as.integer(rs_cfg$max_total_fits %||% 300L)
  factors_Num <- as.integer(rs_cfg$initial_sample_n %||% 1L)

  M1 <- as.character(M1)
  search_pool <- setdiff(as.character(search_pool), M1)
  search_pool <- search_pool[nzchar(search_pool)]
  if (!length(search_pool)) {
    cli::cli_alert_warning(
      "logistic NHANES: 随机搜索候选池为空（{if (isTRUE(lab_only_m2)) '实验室' else '协变量'}），跳过。"
    )
    return(list(M1 = M1, M2 = M1, tb = NULL, succeeded = FALSE, sample_factors = character(0)))
  }

  n_fits <- 0L
  try_one <- function(sample_factors) {
    n_fits <<- n_fits + 1L
    M2_try <- unique(c(M1, sample_factors))
    tb_try <- suppressWarnings(tryCatch(
      build_table_fn(M1, M2_try), error = function(e) NULL
    ))
    if (is.null(tb_try)) return(NULL)
    pv <- .lnw00_table_pvals(tb_try)
    if (.lnw00_models_adjusted_significant(pv, p_thr, rs_cfg)) {
      list(M2 = M2_try, tb = tb_try, sample_factors = sample_factors)
    } else {
      NULL
    }
  }

  cli::cli_h3("logistic NHANES: crude 显著但 Model1/2 不显著，开始协变量搜索")
  pool_label <- if (isTRUE(lab_only_m2)) "实验室指标" else "协变量"
  cli::cli_alert_info(
    "搜索池（{pool_label}, {length(search_pool)}): {paste(search_pool, collapse = ', ')} | outer≤{max_attempts}, inner≤{max_inner}, total_fits≤{max_total_fits}, p<{p_thr}"
  )

  # 小池先穷举（比 1000×1000 随机快得多）
  exhaustive_max <- as.integer(rs_cfg$exhaustive_max_pool %||% 10L)
  max_combn <- as.integer(rs_cfg$max_exhaustive_combinations %||% 400L)
  if (length(search_pool) <= exhaustive_max) {
    cli::cli_alert_info("候选池≤{exhaustive_max}，先穷举 combn（≤{max_combn} 组/层）")
    for (n_sample in seq_len(length(search_pool))) {
      n_combn <- choose(length(search_pool), n_sample)
      if (n_combn > max_combn) next
      subsets <- combn(search_pool, n_sample, simplify = FALSE)
      for (sample_factors in subsets) {
        if (n_fits >= max_total_fits) break
        hit <- try_one(sample_factors)
        if (!is.null(hit)) {
          cli::cli_alert_success(
            "穷举命中 (n={n_sample}, fits={n_fits}): {paste(hit$sample_factors, collapse = ', ')}"
          )
          return(list(
            M1 = M1, M2 = hit$M2, tb = hit$tb,
            succeeded = TRUE, sample_factors = hit$sample_factors
          ))
        }
      }
      if (n_fits >= max_total_fits) break
    }
  }

  # Cox 式：外层递增 factors_Num，内层随机抽样（上限由 config 控制，非 1000×1000 全跑）
  attempt_count <- 0L
  exit_outer <- FALSE
  tb_best <- NULL
  M2_best <- NULL
  sample_best <- character(0)

  while (attempt_count < max_attempts && !exit_outer && n_fits < max_total_fits) {
    inner_count <- 0L
    condition_met <- FALSE
    n_sample <- min(factors_Num, length(search_pool))

    while (inner_count < max_inner && !condition_met && n_fits < max_total_fits) {
      sample_factors <- if (n_sample > 0L) {
        sample(search_pool, n_sample, replace = FALSE)
      } else {
        character(0)
      }
      inner_count <- inner_count + 1L
      hit <- try_one(sample_factors)
      if (!is.null(hit)) {
        tb_best <- hit$tb
        M2_best <- hit$M2
        sample_best <- hit$sample_factors
        condition_met <- TRUE
        exit_outer <- TRUE
        cli::cli_alert_success(
          "随机搜索命中 (outer={attempt_count + 1L}, inner={inner_count}, n={n_sample}): {paste(sample_factors, collapse = ', ')}"
        )
        break
      }
    }

    if (!condition_met) {
      factors_Num <- factors_Num + 1L
      if (factors_Num > length(search_pool)) {
        cli::cli_alert_warning("logistic NHANES: factors_Num 超出候选池，停止搜索。")
        break
      }
    }
    attempt_count <- attempt_count + 1L
  }

  if (!exit_outer) {
    cli::cli_alert_warning(
      "logistic NHANES: 协变量搜索未命中（outer={attempt_count}, total_fits={n_fits}）"
    )
  }

  list(
    M1 = M1,
    M2 = if (exit_outer) M2_best else unique(c(M1, search_pool)),
    tb = tb_best,
    succeeded = exit_outer,
    sample_factors = sample_best
  )
}

#' 三级回退：从单因素 VIF 池随机搜索非实验室 → Model1，Model2 仅追加实验室指标
.lnw00_random_search_nonlab_m1_lab_m2 <- function(
    ctx, cfg, m1_pool, lab_pool, build_table_fn, rs_cfg = list()) {
  rs_cfg <- rs_cfg %||% list()
  lcfg <- .lnw00_lcfg(cfg)
  cascade <- lcfg$cascade %||% list()
  p_thr <- as.numeric(rs_cfg$p_threshold %||% cascade$crude_p_threshold %||% 0.05)[1L]
  max_attempts <- as.integer(rs_cfg$max_attempts %||% 100L)
  max_inner <- as.integer(rs_cfg$max_inner_attempts %||% 20L)
  max_total_fits <- as.integer(rs_cfg$max_total_fits %||% 300L)
  factors_m1 <- as.integer(rs_cfg$initial_sample_n %||% 1L)
  factors_lab <- as.integer(rs_cfg$initial_lab_sample_n %||% 1L)

  m1_pool <- unique(as.character(m1_pool)[nzchar(as.character(m1_pool))])
  lab_pool <- unique(setdiff(as.character(lab_pool)[nzchar(as.character(lab_pool))], m1_pool))

  if (!length(m1_pool) && !length(lab_pool)) {
    cli::cli_alert_warning("logistic NHANES: 三级回退随机搜索池为空，跳过。")
    return(list(M1 = character(0), M2 = character(0), tb = NULL,
                succeeded = FALSE, sample_factors = character(0)))
  }

  n_fits <- 0L
  try_one <- function(m1_sample, lab_sample) {
    n_fits <<- n_fits + 1L
    M1_try <- unique(as.character(m1_sample))
    M2_try <- unique(c(M1_try, as.character(lab_sample)))
    tb_try <- suppressWarnings(tryCatch(
      build_table_fn(M1_try, M2_try), error = function(e) NULL
    ))
    if (is.null(tb_try)) return(NULL)
    pv <- .lnw00_table_pvals(tb_try)
    if (.lnw00_models_adjusted_significant(pv, p_thr, rs_cfg)) {
      list(M1 = M1_try, M2 = M2_try, tb = tb_try,
           sample_factors = unique(c(M1_try, lab_sample)))
    } else {
      NULL
    }
  }

  cli::cli_h3("logistic NHANES: 三级回退 — 随机搜索非实验室 Model1 + 实验室 Model2")
  cli::cli_alert_info(
    "M1 池 ({length(m1_pool)}): {paste(m1_pool, collapse = ', ')} | 实验室池 ({length(lab_pool)}): {paste(lab_pool, collapse = ', ')}"
  )

  attempt_count <- 0L
  exit_outer <- FALSE
  tb_best <- NULL
  M1_best <- character(0)
  M2_best <- character(0)
  sample_best <- character(0)

  while (attempt_count < max_attempts && !exit_outer && n_fits < max_total_fits) {
    inner_count <- 0L
    n_m1 <- min(factors_m1, length(m1_pool))
    n_lab <- min(factors_lab, length(lab_pool))
    while (inner_count < max_inner && !exit_outer && n_fits < max_total_fits) {
      m1_sample <- if (n_m1 > 0L && length(m1_pool)) {
        sample(m1_pool, n_m1, replace = FALSE)
      } else {
        character(0)
      }
      lab_sample <- if (n_lab > 0L && length(lab_pool)) {
        sample(lab_pool, n_lab, replace = FALSE)
      } else {
        character(0)
      }
      inner_count <- inner_count + 1L
      hit <- try_one(m1_sample, lab_sample)
      if (!is.null(hit)) {
        tb_best <- hit$tb
        M1_best <- hit$M1
        M2_best <- hit$M2
        sample_best <- hit$sample_factors
        exit_outer <- TRUE
        cli::cli_alert_success(
          "三级回退随机搜索命中 (outer={attempt_count + 1L}, inner={inner_count}): M1={paste(M1_best, collapse = ', ')} | 实验室={paste(lab_sample, collapse = ', ')}"
        )
        break
      }
    }
    if (!exit_outer) {
      factors_m1 <- factors_m1 + 1L
      factors_lab <- factors_lab + 1L
      if (factors_m1 > length(m1_pool) && factors_lab > length(lab_pool)) {
        cli::cli_alert_warning("logistic NHANES: 三级回退随机搜索耗尽候选池。")
        break
      }
    }
    attempt_count <- attempt_count + 1L
  }

  if (!exit_outer) {
    cli::cli_alert_warning(
      "logistic NHANES: 三级回退随机搜索未命中（outer={attempt_count}, total_fits={n_fits}）"
    )
  }

  list(
    M1 = if (exit_outer) M1_best else m1_pool,
    M2 = if (exit_outer) M2_best else unique(c(m1_pool, lab_pool)),
    tb = tb_best,
    succeeded = exit_outer,
    sample_factors = sample_best
  )
}

.lnw00_maybe_search_covariates <- function(
    ctx, cfg, design, index_var, M1, M2, tb, crude_sig, build_table_fn, bl_cfg = list()) {
  lcfg <- .lnw00_lcfg(cfg)
  rs_cfg <- lcfg$random_search %||% list()
  cascade <- lcfg$cascade %||% list()
  threshold <- as.numeric(rs_cfg$p_threshold %||% cascade$crude_p_threshold %||% 0.05)[1L]

  if (!isTRUE(crude_sig)) {
    return(list(M1 = M1, M2 = M2, tb = tb, searched = FALSE, fallback = FALSE,
                sample_factors = character(0), ctx = ctx))
  }

  tune0 <- .lnw00_apply_covariate_tuning(
    M1, M2, tb, build_table_fn, threshold, rs_cfg, ctx, cfg, bl_cfg, crude_sig
  )
  M1 <- tune0$M1
  M2 <- tune0$M2
  tb <- tune0$tb
  ctx <- tune0$ctx
  if (isTRUE(tune0$tuned)) {
    return(list(
      M1 = M1, M2 = M2, tb = tb, searched = FALSE, fallback = TRUE,
      sample_factors = character(0), ctx = ctx
    ))
  }

  pv0 <- .lnw00_table_pvals(tb)
  if (isTRUE(rs_cfg$require_triple_model_sig %||% TRUE) &&
      .lnw00_triple_models_significant(pv0, threshold, rs_cfg)) {
    return(list(M1 = M1, M2 = M2, tb = tb, searched = FALSE, fallback = FALSE,
                sample_factors = character(0), ctx = ctx))
  }
  if (!isTRUE(rs_cfg$require_triple_model_sig %||% TRUE) &&
      .lnw00_models_adjusted_significant(pv0, threshold, rs_cfg)) {
    return(list(M1 = M1, M2 = M2, tb = tb, searched = FALSE, fallback = FALSE,
                sample_factors = character(0), ctx = ctx))
  }

  searched <- FALSE
  sample_factors <- character(0)

  if (isTRUE(tune0$run_random) &&
      .lnw00_need_covariate_search(tb, threshold, crude_sig, rs_cfg, ctx, cfg, bl_cfg)) {
    pool <- .lnw00_get_vif_final_pool(ctx)
    screen_pool <- as.character(
      ctx$results$vif_screen_pass %||% ctx$results$vif_screen_pass_weighted %||% character(0)
    )
    split <- .lnw00_split_vif_final_models(
      pool, cfg, design, index_var, bl_cfg, screen_pool = screen_pool
    )
    if (isTRUE(split$model2_lab_only) && identical(split$model1_tier, "nonlab_uvif_fallback")) {
      sr <- .lnw00_random_search_nonlab_m1_lab_m2(
        ctx, cfg, split$m1_search_pool, split$m2_search_pool,
        build_table_fn, rs_cfg
      )
    } else {
      search_pool <- setdiff(split$m2_search_pool %||% character(0), M1)
      sr <- .lnw00_random_search_covariates(
        ctx, cfg, M1, search_pool, build_table_fn, crude_sig, rs_cfg, bl_cfg,
        lab_only_m2 = isTRUE(split$model2_lab_only)
      )
    }
    if (isTRUE(sr$succeeded)) {
      ctx$results$nhanes_logistic_covariate_search_applied <- TRUE
      ctx$results$logistic_covariate_search_applied <- TRUE
      ctx$results$nhanes_logistic_search_succeeded <- TRUE
      ctx$results$logistic_search_succeeded <- TRUE
      ctx$results$nhanes_logistic_search_sample_factors <- sr$sample_factors
      ctx$results$logistic_search_sample_factors <- sr$sample_factors
      return(list(
        M1 = sr$M1, M2 = sr$M2, tb = sr$tb,
        searched = TRUE, fallback = FALSE, sample_factors = sr$sample_factors, ctx = ctx
      ))
    }
    ctx$results$nhanes_logistic_search_succeeded <- FALSE
    ctx$results$logistic_search_succeeded <- FALSE
    if (!is.null(sr$tb)) {
      tb <- sr$tb
      M2 <- sr$M2
    }
    if (isTRUE(rs_cfg$pause_on_search_fail %||% FALSE)) {
      ctx$results$pause_point <- list(
        block = "logistic_nhanes_weighted",
        reason = "crude 显著但随机搜索未找到 Model1/2 均显著的协变量组合",
        suggestion = "增大 random_search$max_attempts 或启用 m1_to_m2_fallback",
        data_snapshot = if (is.matrix(tb)) utils::head(as.data.frame(tb), 8L) else NULL
      )
      stop(
        "PAUSE_FOR_USER_DECISION: logistic NHANES 协变量随机搜索失败。",
        call. = FALSE
      )
    }
  } else if (.lnw00_logistic_covariates_locked(ctx, cfg, bl_cfg)) {
    cli::cli_alert_info("logistic NHANES: 双库闸门 B 已锁定协变量池，跳过随机搜索")
  }

  tune1 <- .lnw00_apply_covariate_tuning(
    M1, M2, tb, build_table_fn, threshold, rs_cfg, ctx, cfg, bl_cfg, crude_sig
  )
  ctx <- tune1$ctx
  list(
    M1 = tune1$M1, M2 = tune1$M2, tb = tune1$tb,
    searched = searched, fallback = isTRUE(tune1$tuned),
    sample_factors = sample_factors, ctx = ctx
  )
}

# ── 全 logistic 块共用公开 API ───────────────────────────────────────────────

logistic_resolve_pos_factors <- function(ctx, data_cols, excl_cols, block_name = "logistic") {
  pool <- .lnw00_get_vif_final_pool(ctx)
  pool <- intersect(as.character(pool), as.character(data_cols))
  pool <- setdiff(pool, as.character(excl_cols))
  pool <- unique(pool[nzchar(pool)])
  if (!length(pool)) {
    cli::cli_alert_warning(
      "{block_name}: vif_final_pass 为空，fallback final_features / Model2Factors"
    )
    pool <- as.character(ctx$results$final_features %||% ctx$results$Model2Factors %||% character(0))
    pool <- setdiff(intersect(pool, as.character(data_cols)), as.character(excl_cols))
    pool <- unique(pool[nzchar(pool)])
  }
  pool
}

logistic_resolve_models <- function(ctx, cfg, data, index_var, bl_cfg = list()) {
  design_like <- if (is.data.frame(data)) {
    list(variables = data)
  } else if (is.list(data) && !is.null(data$variables)) {
    data
  } else {
    list(variables = data)
  }
  out <- .lnw00_resolve_models(ctx, cfg, bl_cfg, design_like, index_var)
  cols <- if (is.data.frame(data)) {
    names(data)
  } else {
    names(design_like$variables %||% list())
  }
  if (exists("pipeline_ensure_age_in_model1", mode = "function")) {
    ens <- pipeline_ensure_age_in_model1(out$M1, out$M2, cols, cfg)
    out$M1 <- ens$M1
    out$M2 <- ens$M2
  }
  out
}

logistic_nested_random_search <- function(
    search_pool, M1, raw_levels, p_threshold, rs_cfg,
    build_table_fn,
    combine_model2_fn = NULL) {
  rs_cfg <- rs_cfg %||% list()
  combine_model2_fn <- combine_model2_fn %||% function(m1, sampled) unique(c(m1, sampled))
  M1 <- as.character(M1)
  search_pool <- setdiff(as.character(search_pool), M1)
  search_pool <- search_pool[nzchar(search_pool)]

  max_outer <- as.integer(rs_cfg$max_outer_attempts %||% rs_cfg$max_attempts %||% 1000L)
  max_inner <- as.integer(rs_cfg$max_inner_attempts %||% 1000L)
  factors_Num <- as.integer(
    rs_cfg$initial_factors_n %||% rs_cfg$initial_sample_n %||% rs_cfg$sample_n %||% 1L
  )
  if (!is.null(rs_cfg$seed)) set.seed(as.integer(rs_cfg$seed))

  attempt_count <- 0L
  exit_outer <- FALSE
  tb_best <- NULL
  M2_best <- NULL
  sample_best <- character(0)
  tb_last <- NULL
  M2_last <- combine_model2_fn(M1, character(0))

  if (!length(search_pool)) {
    return(list(
      tb01 = NULL, Model2Factors = M2_last, sample_factors = character(0),
      search_succeeded = FALSE, attempt_count = 0L
    ))
  }

  while (attempt_count < max_outer && !exit_outer) {
    inner_count <- 0L
    n_sample <- min(factors_Num, length(search_pool))
    while (inner_count < max_inner && !exit_outer) {
      sampled <- if (n_sample > 0L) sample(search_pool, n_sample, replace = FALSE) else character(0)
      M2_try <- combine_model2_fn(M1, sampled)
      tb_try <- suppressWarnings(tryCatch(
        build_table_fn(M2_try), error = function(e) NULL
      ))
      inner_count <- inner_count + 1L
      if (!is.null(tb_try)) {
        tb_last <- tb_try
        M2_last <- M2_try
      }
      if (is.null(tb_try)) next
      pv <- .lnw00_table_pvals(tb_try)
      if (.lnw00_models_adjusted_significant(pv, p_threshold, rs_cfg)) {
        tb_best <- tb_try
        M2_best <- M2_try
        sample_best <- sampled
        exit_outer <- TRUE
        break
      }
    }
    if (!exit_outer) {
      factors_Num <- factors_Num + 1L
      if (factors_Num > length(search_pool)) break
    }
    attempt_count <- attempt_count + 1L
  }

  list(
    tb01 = if (exit_outer) tb_best else tb_last,
    Model2Factors = if (exit_outer) M2_best else M2_last,
    sample_factors = sample_best,
    search_succeeded = exit_outer,
    attempt_count = attempt_count
  )
}

logistic_prepare_covariates <- function(
    ctx, cfg, bl_cfg, data, index_var, excl_cols, block_name,
    build_table_fn,
    combine_model2_fn = NULL,
    filter_m1 = NULL) {
  lcfg <- .lnw00_lcfg(cfg)
  rs_cfg <- lcfg$random_search %||% bl_cfg$random_search %||% list()
  cascade <- lcfg$cascade %||% list()
  p_thr <- as.numeric(rs_cfg$p_threshold %||% cascade$crude_p_threshold %||% 0.05)[1L]

  models <- logistic_resolve_models(ctx, cfg, data, index_var, bl_cfg)
  M1 <- models$M1
  M2 <- models$M2
  if (is.function(filter_m1)) {
    M1 <- filter_m1(M1)
    M2 <- unique(c(M1, intersect(M2, if (is.data.frame(data)) colnames(data) else names(data))))
  }
  M2 <- setdiff(M2, as.character(excl_cols))

  tb <- tryCatch(build_table_fn(M1, M2), error = function(e) {
    attr(e, ".keep") <- TRUE
    e
  })
  if (inherits(tb, "error") || is.null(tb)) {
    msg <- if (inherits(tb, "error")) conditionMessage(tb) else "unknown"
    stop(block_name, ": 默认 Model1/2 表构建失败: ", msg, call. = FALSE)
  }

  if (.lnw00_logistic_covariates_locked(ctx, cfg, bl_cfg)) {
    if (exists("logistic_constrain_model_factors", mode = "function")) {
      cn <- logistic_constrain_model_factors(M1, M2, cfg, index_var)
      M1 <- cn$M1
      M2 <- cn$M2
      tb_new <- tryCatch(build_table_fn(M1, M2), error = function(e) NULL)
      if (!is.null(tb_new)) tb <- tb_new
    }
    cli::cli_alert_info("{block_name}: 协变量已锁定（config 预设），跳过调参与随机搜索")
    return(list(
      M1 = M1, M2 = M2, tb = tb, ctx = ctx,
      search_succeeded = FALSE, sample_factors = character(0), attempt_count = 0L
    ))
  }

  pv <- .lnw00_table_pvals(tb)
  crude_sig <- is.finite(pv$trend_crude) && pv$trend_crude < p_thr
  search_succeeded <- FALSE
  sample_factors <- character(0)
  attempt_count <- 0L

  tune0 <- .lnw00_apply_covariate_tuning(
    M1, M2, tb,
    build_table_fn = function(m1, m2) build_table_fn(m1, m2),
    p_thr, rs_cfg, ctx, cfg, bl_cfg, crude_sig
  )
  M1 <- tune0$M1
  M2 <- tune0$M2
  tb <- tune0$tb
  ctx <- tune0$ctx

  if (crude_sig && isTRUE(tune0$run_random) &&
      isTRUE(rs_cfg$enable %||% TRUE) &&
      !.lnw00_logistic_covariates_locked(ctx, cfg, bl_cfg)) {
    cli::cli_h3("{block_name}: crude 显著但 Model1/2 不显著，开始随机搜索协变量")
    pool <- setdiff(logistic_resolve_pos_factors(ctx, colnames(data), excl_cols, block_name), M1)
    if (!is.null(rs_cfg$seed)) set.seed(as.integer(rs_cfg$seed))
    sr <- logistic_nested_random_search(
      pool, M1, NULL, p_thr, rs_cfg,
      build_table_fn = function(m2) build_table_fn(M1, m2),
      combine_model2_fn = combine_model2_fn
    )
    attempt_count <- sr$attempt_count %||% 0L
    if (!is.null(sr$tb01)) tb <- sr$tb01
    if (isTRUE(sr$search_succeeded)) {
      M2 <- sr$Model2Factors
      sample_factors <- sr$sample_factors
      search_succeeded <- TRUE
      ctx$results$logistic_covariate_search_applied <- TRUE
      ctx$results$nhanes_logistic_covariate_search_applied <- TRUE
      ctx$results$logistic_search_succeeded <- TRUE
      ctx$results$logistic_search_sample_factors <- sample_factors
      cli::cli_alert_success(
        "{block_name}: 随机搜索命中（attempt #{attempt_count}, k={length(sample_factors)}）"
      )
    } else {
      cli::cli_alert_warning("{block_name}: 随机搜索未命中，尝试 M1→M2 回退")
      ctx$results$logistic_search_succeeded <- FALSE
      if (isTRUE(rs_cfg$pause_on_search_fail %||% FALSE)) {
        ctx$results$pause_point <- list(
          block = block_name,
          reason = "crude 显著但随机搜索未找到 Model1/2 均显著的协变量组合",
          suggestion = "增大 random_search$max_attempts 或启用 m1_to_m2_fallback",
          data_snapshot = utils::head(as.data.frame(tb), 8L)
        )
        stop("PAUSE_FOR_USER_DECISION: ", block_name, " 协变量随机搜索失败。", call. = FALSE)
      }
    }
  } else if (crude_sig && .lnw00_logistic_covariates_locked(ctx, cfg, bl_cfg)) {
    cli::cli_alert_info("{block_name}: 双库闸门 B 已锁定协变量池，跳过随机搜索")
  } else if (crude_sig) {
    cli::cli_alert_info("{block_name}: 默认 Model1/2 已显著，跳过随机搜索")
  }

  tune1 <- .lnw00_apply_covariate_tuning(
    M1, M2, tb,
    build_table_fn = function(m1, m2) build_table_fn(m1, m2),
    p_thr, rs_cfg, ctx, cfg, bl_cfg, crude_sig
  )
  M1 <- tune1$M1
  M2 <- tune1$M2
  tb <- tune1$tb
  ctx <- tune1$ctx

  if (exists("logistic_constrain_model_factors", mode = "function")) {
    cn <- logistic_constrain_model_factors(M1, M2, cfg, index_var)
    M1 <- cn$M1
    M2 <- cn$M2
    tb_new <- tryCatch(build_table_fn(M1, M2), error = function(e) NULL)
    if (!is.null(tb_new)) tb <- tb_new
  }

  list(
    M1 = M1, M2 = M2, tb = tb, ctx = ctx,
    search_succeeded = search_succeeded,
    sample_factors = sample_factors,
    attempt_count = attempt_count
  )
}
