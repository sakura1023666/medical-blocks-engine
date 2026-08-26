###############################################################################
#  ml_feature_selection_bundle — 多模型特征选择 + 共识 + 韦恩 + 导出主库 RDS
#
#  register_block: "ml_feature_selection_bundle"
#  前置: train_validation + multicollinearity_screen 后 Model2Factors
#  流程: 先 LASSO；若 5–12 个且含暴露 → 仅用 LASSO；否则跑其余算法至目标区间
###############################################################################

.mlfsb_ensure_blocks <- function(ctx) {
  root <- ctx$config$project$root %||% getwd()
  if (!exists("pipeline_source_block", mode = "function")) return(invisible(NULL))
  needed <- c(
    "feature_selection_lasso", "feature_selection_boruta",
    "feature_selection_bayesian", "feature_selection_random_forest",
    "feature_selection_bagged_trees", "feature_selection_lvq",
    "feature_selection_consensus", "feature_selection_venn"
  )
  sourced <- character(0)
  for (b in needed) {
    if (b %in% names(pipeline_block_sources(root))) {
      sourced <- pipeline_source_block(root, b, sourced)
    }
  }
  invisible(sourced)
}

.mlfsb_exposure_vars <- function(ctx) {
  cfg <- ctx$config
  exp <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    exp <- as.character(pipeline_index_exposure_var(cfg))
  }
  exp <- unique(exp[nzchar(exp)])
  if (!length(exp)) {
    exp <- as.character((cfg$prediction %||% list())$index_vars %||% character(0))
    exp <- unique(exp[nzchar(exp)])
  }
  exp
}

## 按单因素 P 升序排列（无 P 的排后）
.mlfsb_order_by_univar_p <- function(vars, ctx) {
  vars <- unique(as.character(vars[nzchar(vars)]))
  if (!length(vars)) return(character(0))
  pmap <- ctx$results$univar_pvalues
  if (is.null(pmap) || !length(pmap)) {
    uc <- ctx$results$univar_coef
    if (is.data.frame(uc) && all(c("Variable", "P") %in% names(uc))) {
      pmap <- stats::setNames(as.numeric(uc$P), as.character(uc$Variable))
    }
  }
  if (is.null(pmap) || !length(pmap)) return(vars)
  pv <- suppressWarnings(as.numeric(pmap[vars]))
  vars[order(pv, na.last = TRUE)]
}

## 最终特征 < min 时放宽：暴露 → Age → 单因素(按P) → VIF/Model2 → 并集补足
.mlfsb_ensure_min_features <- function(ctx, fn_min = 3L) {
  fn_min <- as.integer(fn_min)[1L]
  if (is.na(fn_min) || fn_min < 1L) fn_min <- 3L
  final <- as.character(
    ctx$results$feature_selection_final %||%
      ctx$results$ml_feature_names %||%
      character(0)
  )
  final <- unique(final[nzchar(final)])
  if (length(final) >= fn_min) return(ctx)

  data_cols <- names(
    ctx$data$train %||% ctx$data$imputed %||% ctx$data$cleaned %||% list()
  )
  exposure <- intersect(.mlfsb_exposure_vars(ctx), data_cols)
  age <- intersect(c("Age", "age"), data_cols)
  uv <- .mlfsb_order_by_univar_p(
    as.character(ctx$results$univar_features %||% character(0)), ctx
  )
  uv <- intersect(uv, data_cols)
  vif <- as.character(ctx$results$vif_screen_pass %||% character(0))
  vif <- intersect(vif[nzchar(vif)], data_cols)
  m2 <- as.character(ctx$results$Model2Factors %||% character(0))
  m2 <- intersect(m2[nzchar(m2)], data_cols)
  ## 全模型入选并集（最宽）
  by_m <- ctx$results$feature_selection_by_model %||% list()
  union_m <- unique(unlist(lapply(by_m, function(x) as.character(x)), use.names = FALSE))
  union_m <- intersect(union_m[nzchar(union_m)], data_cols)

  pool_ordered <- unique(c(exposure, age, final, uv, union_m, vif, m2))
  need <- fn_min - length(final)
  add <- setdiff(pool_ordered, final)
  if (length(add) < need) {
    cli::cli_alert_warning(
      "ml_feature_selection_bundle: 放宽后仍仅能补到 {length(final) + length(add)} / {fn_min}（候选池不足）。"
    )
  }
  padded <- unique(c(final, head(add, max(need, 0L))))
  ctx$results$feature_selection_final <- padded
  ctx$results$feature_selection_venn_center <- padded
  ctx$results$ml_feature_names <- padded
  ctx$results$feature_selection_min_padded <- TRUE
  ctx$results$feature_selection_min_padded_from <- length(final)
  cli::cli_alert_warning(
    "ml_feature_selection_bundle: 最终特征 {length(final)} < {fn_min}，已放宽条件补足至 {length(padded)}: {paste(padded, collapse = ', ')}"
  )
  ctx
}

.mlfsb_lasso_sufficient <- function(ctx, fs) {
  lasso_feats <- as.character(ctx$results$feature_selection_by_model$lasso %||% character(0))
  lasso_feats <- unique(lasso_feats[nzchar(lasso_feats)])
  n <- length(lasso_feats)
  fn_min <- as.integer(fs$target_n_features_min %||% 5L)[1L]
  fn_max <- as.integer(fs$target_n_features_max %||% 12L)[1L]
  if (!is.finite(fn_min) || !is.finite(fn_max) || fn_min > fn_max) {
    fn_min <- 5L; fn_max <- 12L
  }
  if (n < fn_min || n > fn_max) return(FALSE)
  require_exp <- isTRUE((ctx$config$feature_selection_venn %||% list())$require_exposure_in_features %||% FALSE)
  if (!require_exp) return(TRUE)
  exposure <- .mlfsb_exposure_vars(ctx)
  if (!length(exposure)) return(TRUE)
  any(exposure %in% lasso_feats)
}

.mlfsb_run_methods <- function(ctx) {
  .mlfsb_ensure_blocks(ctx)
  fs <- ctx$config$feature_selection %||% list()
  if (isFALSE(fs$enable %||% TRUE)) {
    m2 <- ctx$results$Model2Factors %||% ctx$results$univar_features %||% character(0)
    ctx$results$feature_selection_final <- as.character(m2)
    return(ctx)
  }

  lasso_first <- isTRUE(fs$lasso_first %||% TRUE)
  methods <- fs$methods
  if (isTRUE(fs$auto_methods %||% TRUE) && (is.null(methods) || !length(methods))) {
    methods <- c("lasso", "boruta", "random_forest", "bayesian", "bagged_trees", "lvq")
  }
  methods <- tolower(as.character(methods))
  method_map <- list(
    lasso = "feature_selection_lasso",
    boruta = "feature_selection_boruta",
    bayesian = "feature_selection_bayesian",
    random_forest = "feature_selection_random_forest",
    bagged_trees = "feature_selection_bagged_trees",
    lvq = "feature_selection_lvq"
  )

  run_one <- function(m) {
    blk <- method_map[[m]]
    if (is.null(blk)) return(ctx)
    root <- ctx$config$project$root %||% getwd()
    if (exists("pipeline_source_block", mode = "function") &&
        blk %in% names(pipeline_block_sources(root))) {
      pipeline_source_block(root, blk)
    }
    if (exists(blk, envir = .block_registry)) {
      ctx <<- run_block(ctx, blk)
    }
    ctx
  }

  only_lasso <- length(setdiff(methods, "lasso")) == 0L && "lasso" %in% methods
  if ("lasso" %in% methods) {
    ctx <- run_one("lasso")
    lasso_feats <- as.character(ctx$results$feature_selection_by_model$lasso %||% character(0))
    lasso_feats <- unique(lasso_feats[nzchar(lasso_feats)])
    use_lasso_only <- length(lasso_feats) > 0L && (
      only_lasso || (lasso_first && .mlfsb_lasso_sufficient(ctx, fs))
    )
    if (use_lasso_only) {
      ctx$results$feature_selection_final <- lasso_feats
      ctx$results$feature_selection_venn_center <- lasso_feats
      ctx$results$ml_feature_names <- lasso_feats
      ctx$results$feature_selection_lasso_only <- TRUE
      fn_min <- as.integer(fs$target_n_features_min %||% 5L)[1L]
      fn_max <- as.integer(fs$target_n_features_max %||% 12L)[1L]
      if (only_lasso) {
        cli::cli_alert_success(
          "ml_feature_selection_bundle: 仅 LASSO，采用 {length(lasso_feats)} 个特征（目标参考 {fn_min}-{fn_max}）。"
        )
      } else {
        cli::cli_alert_success(
          "ml_feature_selection_bundle: LASSO 已选出 {length(lasso_feats)} 个特征（目标 {fn_min}-{fn_max} 且含暴露），跳过后续算法。"
        )
      }
      return(ctx)
    }
    if (lasso_first) {
      cli::cli_alert_info(
        "ml_feature_selection_bundle: LASSO 未达目标区间或未含暴露，继续运行其余特征选择算法。"
      )
    }
    methods <- setdiff(methods, "lasso")
  }

  for (m in methods) ctx <- run_one(m)

  ctx <- tryCatch(
    run_block(ctx, "feature_selection_consensus"),
    error = function(e) {
      lasso_fb <- as.character(ctx$results$feature_selection_by_model$lasso %||% character(0))
      lasso_fb <- unique(lasso_fb[nzchar(lasso_fb)])
      fn_min <- as.integer(fs$target_n_features_min %||% 3L)[1L]
      fn_max <- as.integer(fs$target_n_features_max %||% 12L)[1L]
      ## 即使不足 min 也先落地，交给后续 .mlfsb_ensure_min_features 放宽补足
      if (length(lasso_fb)) {
        cli::cli_alert_warning(
          "feature_selection_consensus 失败，暂用 LASSO 特征 ({length(lasso_fb)} 个，目标 {fn_min}-{fn_max})，稍后放宽补足: {conditionMessage(e)}"
        )
        ctx$results$feature_selection_final <- lasso_fb
        ctx$results$feature_selection_venn_center <- lasso_fb
        ctx$results$ml_feature_names <- lasso_fb
        ctx
      } else {
        ## 无 LASSO 结果：用并集/Model2 占位，仍交 ensure_min 补足
        by_m <- ctx$results$feature_selection_by_model %||% list()
        union_fb <- unique(unlist(lapply(by_m, function(x) as.character(x)), use.names = FALSE))
        union_fb <- unique(c(
          union_fb[nzchar(union_fb)],
          as.character(ctx$results$Model2Factors %||% character(0))
        ))
        union_fb <- union_fb[nzchar(union_fb)]
        if (length(union_fb)) {
          cli::cli_alert_warning(
            "feature_selection_consensus 失败且无 LASSO，暂用模型并集/Model2 ({length(union_fb)} 个): {conditionMessage(e)}"
          )
          ctx$results$feature_selection_final <- union_fb
          ctx$results$feature_selection_venn_center <- union_fb
          ctx$results$ml_feature_names <- union_fb
          ctx
        } else {
          stop(conditionMessage(e), call. = FALSE)
        }
      }
    }
  )
  if (isTRUE(fs$draw_venn %||% TRUE)) {
    ctx <- tryCatch(
      run_block(ctx, "feature_selection_venn"),
      error = function(e) {
        cli::cli_alert_warning("feature_selection_venn 跳过: {conditionMessage(e)}")
        ctx
      }
    )
  }
  ctx
}

block_ml_feature_selection_bundle <- function(ctx, ...) {
  bl <- ctx$config$ml_feature_selection_bundle %||% list()
  if (isFALSE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("ml_feature_selection_bundle$enable=FALSE，跳过。")
    return(ctx)
  }
  root <- ctx$config$project$root %||% getwd()
  if (!exists("inject_feature_selection_compound_indices", mode = "function")) {
    source(file.path(root, "R/ml_dual_pipeline_helpers.R"), local = FALSE)
  }
  fs_cfg <- ctx$config$feature_selection %||% list()
  fn_min <- as.integer(fs_cfg$target_n_features_min %||% 3L)[1L]
  if (is.na(fn_min) || fn_min < 1L) fn_min <- 3L

  ## 课题可显式锁定最终特征（小样本少特征），跳过 LASSO/共识
  force_final <- unique(as.character(
    fs_cfg$force_final %||% bl$force_final %||% character(0)
  ))
  force_final <- force_final[nzchar(force_final)]
  if (length(force_final)) {
    data_cols <- names(ctx$data$imputed %||% ctx$data$train %||% ctx$data$cleaned %||% list())
    ## 别名：UricAcid ↔ Uric_Acid
    alias <- c(UricAcid = "Uric_Acid", Uric_Acid = "Uric_Acid", UA_Cr = "UA_CR")
    mapped <- vapply(force_final, function(v) {
      if (v %in% data_cols) return(v)
      if (!is.null(alias[[v]]) && alias[[v]] %in% data_cols) return(alias[[v]])
      if (identical(v, "Uric_Acid") && "UricAcid" %in% data_cols) return("UricAcid")
      v
    }, character(1L))
    keep <- unique(mapped[mapped %in% data_cols])
    if (!length(keep)) {
      stop("feature_selection$force_final 均不在数据中: ", paste(force_final, collapse = ", "), call. = FALSE)
    }
    ctx$results$feature_selection_final <- keep
    ctx$results$feature_selection_venn_center <- keep
    ctx$results$ml_feature_names <- keep
    ctx$results$feature_selection_by_model <- list(forced = keep)
    ctx$results$feature_selection_forced <- TRUE
    cli::cli_alert_success(
      "ml_feature_selection_bundle: 使用 force_final 锁定 {length(keep)} 个特征: {paste(keep, collapse = ', ')}"
    )
    if (isTRUE(bl$export_for_secondary %||% TRUE)) {
      if (!exists("pipeline_export_primary_ml_features", mode = "function")) {
        source(file.path(root, "R/ml_dual_pipeline_helpers.R"), local = FALSE)
      }
      if (identical(ctx$config$dual_db$current_db %||% "nhanes", "nhanes") ||
          identical(ctx$config$multi_db$role %||% "primary", "primary")) {
        pipeline_export_primary_ml_features(ctx, root, ctx$config)
      }
    }
    return(ctx)
  }

  ## Cox 表可能把 Model2Factors 缩成 Age+GCS；ML 候选池必须从 VIF 恢复
  vif_pass <- as.character(ctx$results$vif_screen_pass %||% character(0))
  vif_pass <- vif_pass[nzchar(vif_pass)]
  if (length(vif_pass) >= 3L) {
    m2_now <- as.character(ctx$results$Model2Factors %||% character(0))
    if (length(m2_now) < 3L || !all(vif_pass %in% m2_now)) {
      age <- intersect(c("Age", "age"), names(ctx$data$imputed %||% ctx$data$train %||% list()))
      exp_var <- character(0)
      if (exists("pipeline_index_exposure_var", mode = "function")) {
        exp_var <- as.character(pipeline_index_exposure_var(ctx$config) %||% character(0))
      }
      restored <- unique(c(age, vif_pass, exp_var, m2_now))
      restored <- restored[nzchar(restored)]
      ctx$results$Model2Factors <- restored
      ctx$results$ml_model2_restored_from_vif <- TRUE
      cli::cli_alert_info(
        "ml_feature_selection_bundle: 从 VIF 恢复 ML 候选池 ({length(restored)}): {paste(restored, collapse = ', ')}"
      )
    }
  }
  ## 候选池仍 < min：用单因素按 P 补足，避免 LASSO「候选不足」硬停
  m2_now <- as.character(ctx$results$Model2Factors %||% character(0))
  m2_now <- m2_now[nzchar(m2_now)]
  if (length(m2_now) < fn_min) {
    data_cols <- names(ctx$data$imputed %||% ctx$data$train %||% list())
    uv_ord <- .mlfsb_order_by_univar_p(
      as.character(ctx$results$univar_features %||% character(0)), ctx
    )
    uv_ord <- intersect(uv_ord, data_cols)
    age <- intersect(c("Age", "age"), data_cols)
    exp_var <- intersect(.mlfsb_exposure_vars(ctx), data_cols)
    expanded <- unique(c(exp_var, age, m2_now, uv_ord, vif_pass))
    expanded <- intersect(expanded[nzchar(expanded)], data_cols)
    if (length(expanded) > length(m2_now)) {
      ctx$results$Model2Factors <- expanded
      cli::cli_alert_warning(
        "ml_feature_selection_bundle: 候选池 {length(m2_now)} < {fn_min}，已放宽并入单因素/暴露至 {length(expanded)} 个。"
      )
    }
  }
  db_tag <- ctx$config$project$database %||% "NHANES"
  ctx <- inject_feature_selection_compound_indices(ctx, db_tag)
  ctx <- .mlfsb_run_methods(ctx)
  ## ICU 严重度评分成分重叠：APSIII/SAPSII/OASIS/SOFA/GCS 最多保留 1 个
  root <- ctx$config$project$root %||% getwd()
  overlap_helper <- file.path(root, "R/ml_severity_score_overlap.R")
  if (file.exists(overlap_helper)) source(overlap_helper, local = FALSE)
  if (exists("ml_apply_severity_score_dedupe_to_ctx", mode = "function")) {
    ctx <- ml_apply_severity_score_dedupe_to_ctx(ctx)
  }
  ## 最终特征必须 ≥ min：不足则按暴露/Age/单因素P/并集放宽补足
  ctx <- .mlfsb_ensure_min_features(ctx, fn_min = fn_min)
  if (isTRUE(bl$export_for_secondary %||% TRUE)) {
    root <- ctx$config$project$root %||% getwd()
    if (!exists("pipeline_export_primary_ml_features", mode = "function")) {
      source(file.path(root, "R/ml_dual_pipeline_helpers.R"), local = FALSE)
    }
    if (identical(ctx$config$dual_db$current_db %||% "nhanes", "nhanes") ||
        identical(ctx$config$multi_db$role %||% "primary", "primary")) {
      pipeline_export_primary_ml_features(ctx, root, ctx$config)
    }
  }
  ctx
}

register_block(
  "ml_feature_selection_bundle",
  block_ml_feature_selection_bundle,
  "LASSO优先 → 其余算法/共识/韦恩 + 导出主库特征 RDS"
)
