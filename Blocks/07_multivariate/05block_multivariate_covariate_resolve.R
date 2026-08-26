###############################################################################
#  multivariate_covariate_resolve — tb2 为空时回退 vif_screen_pass
#
#  register_block: "multivariate_covariate_resolve"
#  典型位置: multivariate_* 之后、multicollinearity_*_final 之前
#  触发: ctx$results$tb2 为空且 vif_screen_pass 非空
###############################################################################

.mcr05_demo_keywords <- function(cfg, db_weighted = FALSE) {
  if (db_weighted) {
    kw <- as.character((cfg$multivariate_nhanes %||% list())$demo_keywords %||% character(0))
    if (length(kw)) return(kw)
  }
  kw <- as.character((cfg$multivariate_incidence_binary %||% list())$demo_keywords %||% character(0))
  if (length(kw)) return(kw)
  as.character(((cfg$dual_db %||% list())$harmonization %||% list())$demo_keywords %||% character(0))
}

.mcr05_resolve_fallback_vars <- function(ctx, cfg) {
  r_cfg <- cfg$multivariate_covariate_resolve %||% list()
  chain <- r_cfg$fallback_from
  if (is.null(chain) || !length(chain)) {
    chain <- c("tb_screen", "tb1", "vif_screen_pass", "univar_features")
  }
  chain <- as.character(chain)

  pick_from <- function(key) {
    switch(key,
      tb_screen = as.character(ctx$results$tb_screen %||% character(0)),
      tb1 = as.character(ctx$results$tb1 %||% character(0)),
      vif_screen_pass = as.character(
        ctx$results$vif_screen_pass %||% ctx$results$vif_screen_pass_weighted %||% character(0)
      ),
      univar_features = as.character(ctx$results$univar_features %||% character(0)),
      Model2Factors = as.character(ctx$results$Model2Factors %||% character(0)),
      character(0)
    )
  }

  fallback <- character(0)
  used_key <- NA_character_
  for (key in chain) {
    cand <- unique(pick_from(key))
    cand <- cand[nzchar(cand)]
    if (length(cand)) {
      fallback <- cand
      used_key <- key
      break
    }
  }

  mc_cfg <- cfg$multicollinearity %||% list()
  nhanes_cfg <- cfg$nhanes %||% list()
  index_excl <- if (exists("pipeline_covariate_analysis_exclude_vars", mode = "function")) {
    pipeline_covariate_analysis_exclude_vars(cfg)
  } else {
    character(0)
  }
  drop <- unique(c(
    as.character(mc_cfg$exclude_vars %||% character(0)),
    as.character(mc_cfg$weighted_vif_drop_vars %||% character(0)),
    as.character(cfg$data$id_column %||% character(0)),
    as.character(nhanes_cfg$exclude_cols %||% character(0)),
    index_excl
  ))
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    drop <- setdiff(drop, pipeline_index_exposure_var(cfg))
  }
  fallback <- setdiff(fallback, drop[nzchar(drop)])
  attr(fallback, "source_key") <- used_key
  fallback
}

block_multivariate_covariate_resolve <- function(ctx, ...) {
  cfg <- ctx$config
  r_cfg <- cfg$multivariate_covariate_resolve %||% list()
  if (!isTRUE(r_cfg$enable %||% TRUE)) return(ctx)

  tb2 <- unique(as.character(ctx$results$tb2 %||% character(0)))
  tb2 <- tb2[nzchar(tb2)]

  if (length(tb2) > 0L) {
    # 保留多因素显著集；是否改用 VIF screen 由闸门 B 在「两库暴露均多因素显著」时统一决定
    ctx$results$tb2_multivar_sig <- tb2
    ctx$results$multivar_covariate_source <- "multivariate_sig"
    cli::cli_alert_info(
      "multivariate_covariate_resolve: tb2 非空（{length(tb2)} 个），沿用多因素显著协变量供 VIF final；闸门 B 若两库暴露均多因素显著再改用 screen 交集"
    )
    return(ctx)
  }

  fallback <- .mcr05_resolve_fallback_vars(ctx, cfg)
  fallback_src <- attr(fallback, "source_key") %||% NA_character_
  if (length(fallback)) attr(fallback, "source_key") <- NULL

  never_stop <- isTRUE(r_cfg$never_stop %||% TRUE)
  if (!length(fallback)) {
    if (never_stop) {
      cli::cli_alert_warning(
        "multivariate_covariate_resolve: tb2 为空且单因素/VIF 池均无变量，VIF final 将尝试空输入跳过"
      )
      ctx$results$multivar_covariate_source <- "empty"
      return(ctx)
    }
    ctx$results$pause_point <- list(
      block = "multivariate_covariate_resolve",
      reason = "tb2 为空且单因素协变量池无可用变量",
      suggestion = "检查 univariate_prognosis 阈值或数据列名",
      data_snapshot = NULL
    )
    stop(
      "PAUSE_FOR_USER_DECISION: tb2 为空且无法从单因素协变量池回退。",
      call. = FALSE
    )
  }

  db_weighted <- .is_nhanes_db(cfg)
  Model2Factors <- fallback
  if (exists(".mcol_apply_vif_final_covariate_split", mode = "function")) {
    data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped
    split_res <- .mcol_apply_vif_final_covariate_split(ctx, cfg, fallback, data)
    ctx <- split_res$ctx
    Model1Factors <- split_res$Model1Factors
    Model2Factors <- split_res$Model2Factors
  } else {
    demo_keywords <- .mcr05_demo_keywords(cfg, db_weighted)
    demo_pattern <- paste(demo_keywords, collapse = "|")
    Model1Factors <- Model2Factors[grepl(demo_pattern, Model2Factors, ignore.case = TRUE)]
  }

  if (exists("pipeline_strip_index_from_model_factors", mode = "function")) {
    stripped <- pipeline_strip_index_from_model_factors(Model1Factors, Model2Factors, cfg)
    Model1Factors <- stripped$M1
    Model2Factors <- stripped$M2
  }

  ctx$results$tb2 <- fallback
  ctx$results$multivar_features <- fallback
  ctx$results$multivar_covariate_source <- paste0("univariate_fallback:", fallback_src)
  ctx$results$Model1Factors <- Model1Factors
  ctx$results$Model2Factors <- Model2Factors
  ctx$results$univar_features <- fallback

  ctx <- save_result(ctx, "tb2_multivar_features", fallback, "D05_Multivariable_Features.RData")
  ctx <- save_result(ctx, "Model1Factors", Model1Factors, "Model1Factors.RData")
  ctx <- save_result(ctx, "Model2Factors", Model2Factors, "Model2Factors.RData")
  writeLines(Model1Factors, file.path(ctx$output_dir, "Model1Factors.txt"))
  writeLines(Model2Factors, file.path(ctx$output_dir, "Model2Factors.txt"))
  writeLines(fallback, file.path(ctx$output_dir, "tb2_univariate_fallback.txt"))

  src_label <- switch(
    as.character(fallback_src),
    tb_screen = "单因素筛选池 tb_screen (p<screening)",
    tb1 = "单因素显著 tb1",
    vif_screen_pass = "VIF screen 通过池",
    univar_features = "单因素 univar_features",
    Model2Factors = "Model2Factors",
    fallback_src
  )
  cli::cli_alert_warning(
    "multivariate_covariate_resolve: 多因素 tb2 为空，回退 {src_label}（{length(fallback)} 个）"
  )
  cli::cli_alert_info("回退协变量: {paste(fallback, collapse = ', ')}")
  ctx
}

register_block(
  "multivariate_covariate_resolve",
  block_multivariate_covariate_resolve,
  "多因素显著时可用单因素 VIF screen 作下游协变量；否则 tb2 空时回退 screen/tb1"
)
