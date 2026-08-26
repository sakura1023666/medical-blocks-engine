###############################################################################
#  ml_assoc_covariate_rule.R — Cox / Logistic 协变量铁律（全 ML 课题复用）
#
#  Model 1：Age 强制纳入（不论单因素是否显著）
#  Model 2：Age +「单因素显著（tb1）且未进入最终 ML 特征」的变量（嵌套）
#
#  排除：暴露指标本身、已进 ML 的变量、结局/ID、可选黑名单
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
    force_model1 = as.character(ac$force_model1 %||% "Age"),
    uv_source = as.character(ac$uv_source %||% "tb1")[1L],  # tb1 | tb_screen
    max_model2_extra = {
      m <- suppressWarnings(as.integer(ac$max_model2_extra %||% Inf)[1L])
      if (!is.finite(m) || m < 0L) Inf else m
    },
    exclude_extra = as.character(ac$exclude_extra %||% character(0)),
    allow_m2_eq_m1 = isTRUE(ac$allow_m2_eq_m1 %||% TRUE),
    prefer_clinical = as.character(ac$prefer_clinical %||% character(0))
  )
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

#' 解析 Cox/Logistic Model1 / Model2
#' @return list(M1, M2, extras, dropped_in_ml, note)
ml_resolve_assoc_covariates <- function(ctx, data_names = NULL) {
  cfg <- ctx$config %||% list()
  ac <- ml_assoc_covariate_cfg(cfg)
  m1_force <- unique(as.character(ac$force_model1[nzchar(as.character(ac$force_model1))]))
  if (!length(m1_force)) m1_force <- "Age"

  uv <- ml_assoc_uv_sig_vars(ctx, ac$uv_source)
  ml_feats <- ml_assoc_ml_feature_set(ctx)
  exposure <- ml_assoc_exposure_var(ctx)

  ban <- unique(c(
    ml_feats,
    exposure,
    ac$exclude_extra,
    "ID", "Group", "SEQN", "subject_id",
    as.character((cfg$data %||% list())$outcome_column %||% character(0)),
    as.character((cfg$survival %||% list())$event_var %||% character(0)),
    as.character((cfg$survival %||% list())$time_var %||% character(0))
  ))
  ban <- ban[nzchar(ban)]

  extras <- setdiff(uv, unique(c(ban, m1_force)))
  # 优先临床名单（若配置），其余按原 UV 顺序
  if (length(ac$prefer_clinical) && length(extras)) {
    pref <- intersect(ac$prefer_clinical, extras)
    extras <- unique(c(pref, setdiff(extras, pref)))
  }
  if (is.finite(ac$max_model2_extra) && length(extras) > ac$max_model2_extra) {
    extras <- extras[seq_len(ac$max_model2_extra)]
  }

  if (!is.null(data_names)) {
    m1_force <- intersect(m1_force, data_names)
    extras <- intersect(extras, data_names)
  }

  M1 <- unique(m1_force)
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
    extras = extras,
    dropped_in_ml = intersect(uv, ml_feats),
    uv_sig = uv,
    ml_features = ml_feats,
    exposure = exposure,
    allow_m2_eq_m1 = ac$allow_m2_eq_m1,
    note = sprintf(
      "Model1=force(%s); Model2=Model1 + UV-sig not in ML (%d): %s",
      paste(M1, collapse = "+"),
      length(extras),
      if (length(extras)) paste(extras, collapse = ", ") else "(none)"
    )
  )
}

#' 把解析结果写进 ctx 与 cox/logistic block config（供随后 assoc 使用）
ml_apply_assoc_covariate_rule_to_ctx <- function(ctx) {
  ac <- ml_assoc_covariate_cfg(ctx$config %||% list())
  if (!isTRUE(ac$enable)) return(ctx)

  dat <- ctx$data$imputed %||% ctx$data$train %||% ctx$data$cleaned
  nm <- if (is.data.frame(dat)) names(dat) else NULL
  res <- ml_resolve_assoc_covariates(ctx, data_names = nm)

  ctx$results$assoc_model1_factors <- res$M1
  ctx$results$assoc_model2_factors <- res$M2
  ctx$results$assoc_model2_extras <- res$extras
  ctx$results$assoc_covariate_note <- res$note
  # 兼容旧键：不覆盖 VIF 用的 Model2Factors（ML 候选池），只写 assoc 专用
  ctx$results$cox_model1_covariates <- res$M1
  ctx$results$cox_model2_covariates <- res$extras
  ctx$results$logistic_model1_factors <- res$M1
  ctx$results$logistic_model2_factors <- res$M2

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
    cfg <- .set_blk(cfg, blk, res$M1, res$M2, res$allow_m2_eq_m1)
  }
  for (blk in c(
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs"
  )) {
    cfg <- .set_blk(cfg, blk, res$M1, res$M2, res$allow_m2_eq_m1)
  }
  # RCS / KM 用 Model1
  for (blk in c("rcs_prognosis", "rcs_incidence", "km_binary")) {
    cfg[[blk]] <- modifyList(
      cfg[[blk]] %||% list(),
      list(model1_factors = res$M1)
    )
  }
  ctx$config <- cfg

  if (requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_success("assoc 协变量铁律: {res$note}")
    if (length(res$dropped_in_ml)) {
      cli::cli_alert_info(
        "单因素显著但已进 ML、故不进 Model2: {paste(res$dropped_in_ml, collapse = ', ')}"
      )
    }
  }
  ctx
}
