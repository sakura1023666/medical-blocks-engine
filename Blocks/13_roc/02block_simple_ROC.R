###############################################################################
#  simple_ROC — 基于 pROC 的单变量或多变量预测 ROC（AUC + Youden cutoff + 发表图）
#
#  register_block: "simple_ROC"
#  典型流水线: … → multivariate_*_harmonized → simple_ROC → …
#              （默认多变量 ROC；必须在 VIF final / 锁定协变量之后）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_config = config$roc_simple (optional; falls back to incidence/logistic)
#
#  读 config$roc_simple；暴露/结局见 incidence 与 logistic$index_var。
#
#  outputs:
#    Figures/ Figure S<n>-<DB>. ROC <index_var>.pdf
#    Tables/  Table ROC Simple Summary.xlsx + .tex
#    ctx$results$roc_auc, roc_ci, roc_cutoff, roc_sensitivity, roc_specificity
#    ctx$results$cutoff_value (conditional, if not already set)
#
#  roc_simple$mode:
#    "multivariable" (默认) — index + 协变量 拟合预测概率画 ROC
#    "univariate"           — 仅用 index_var（ML 管线等须显式指定）
#  roc_simple$covariate_source:
#    "vif_final" / "vif_final_pass"（预后模板默认）—
#      用 VIF 终筛完整临床协变量；不跟 Table 2 Gate C 剪枝后的短名单
#    "locked" — Table 2 / locked_multivariable_covariates（可含剪枝后 Age+GCS）
#    "model2" — 同 locked（兼容旧配置）
#    "config" — 仅当明确指定时才用 model_covariates 名单
#  roc_simple$model_engine:
#    "glm" (默认) | "rpart" | "glmnet" | "xgboost"
#    rpart / glmnet / xgboost 为判别专用，不影响 Table 2 logistic/Cox 主分析
#  锁定协变量为空且 mode=multivariable → stop（勿放在 VIF final / Gate B 之前）
#
#  dependencies: pROC, ggplot2
###############################################################################

.sroc_resolve_mode <- function(r_cfg = list()) {
  mode <- tolower(trimws(as.character(r_cfg$mode %||% "multivariable")[1L]))
  if (!mode %in% c("univariate", "multivariable")) {
    stop("simple_ROC: mode 须为 'univariate' 或 'multivariable'。", call. = FALSE)
  }
  mode
}

.sroc_resolve_outcome_var <- function(r_cfg = list(), cfg = list()) {
  explicit <- trimws(as.character(r_cfg$outcome_var %||% "")[1L])
  if (nzchar(explicit)) return(explicit)
  study <- tolower(trimws(as.character((cfg$project %||% list())$study_type %||% "")[1L]))
  ev <- trimws(as.character((cfg$survival %||% list())$event_var %||% "")[1L])
  if (nzchar(ev) && study %in% c("prognosis", "survival")) return(ev)
  # 预后模板偶发未写 study_type，但已配 survival$event_var
  if (nzchar(ev) && !study %in% c("incidence", "prediction", "association")) {
    if (!is.null(cfg$survival) && length(cfg$survival)) return(ev)
  }
  as.character((cfg$data %||% list())$outcome_column %||% "Disease")[1L]
}

.sroc_index_var <- function(r_cfg, cfg = NULL, ctx = NULL) {
  as.character(
    (cfg %||% (ctx$config %||% list()))$incidence$index_var %||%
      (cfg %||% (ctx$config %||% list()))$survival$index_var %||%
      r_cfg$index_var %||%
      ""
  )[1L]
}

.sroc_resolve_covariates <- function(r_cfg, data_cols, ctx = NULL, cfg = NULL) {
  # 预后默认 vif_final：判别用完整 VIF 临床集，不跟 Table 2 剪枝
  src_default <- "locked"
  study <- tolower(trimws(as.character(
    ((cfg %||% (ctx$config %||% list()))$project %||% list())$study_type %||% ""
  )[1L]))
  if (study %in% c("prognosis", "survival")) src_default <- "vif_final"
  src <- tolower(trimws(as.character(r_cfg$covariate_source %||% src_default)[1L]))
  covs <- character(0)
  ix <- .sroc_index_var(r_cfg, cfg = cfg, ctx = ctx)

  if (src %in% c("vif_final", "vif_final_pass")) {
    # 故意不用 locked_multivariable（Gate C 剪枝后可能只剩 Age+GCS）
    pool <- unique(c(
      as.character((ctx$results %||% list())$vif_final_pass %||% character(0)),
      as.character((ctx$results %||% list())$vif_final %||% character(0))
    ))
    pool <- pool[nzchar(pool)]
    # 并入学术必调（Gender/HTN/T2DM 等），仍不吸收剪枝后的短 Model2
    if (!is.null(ctx) && exists("pipeline_resolve_model3_factors", mode = "function")) {
      m3 <- tryCatch(
        pipeline_resolve_model3_factors(
          setdiff(pool, ix[nzchar(ix)]),
          cfg %||% ctx$config,
          data_cols,
          ix
        ),
        error = function(e) character(0)
      )
      if (length(m3)) pool <- unique(c(pool, m3))
    }
    covs <- setdiff(pool, ix[nzchar(ix)])
  } else if (src %in% c("locked", "model2")) {
    if (!is.null(ctx) && exists("locked_multivariable_covariates", mode = "function")) {
      lk <- tryCatch(
        locked_multivariable_covariates(ctx, cfg %||% ctx$config),
        error = function(e) NULL
      )
      if (!is.null(lk)) {
        covs <- as.character(lk$covariates %||% character(0))
      }
    }
    if (!length(covs) && !is.null(ctx)) {
      pool <- unique(c(
        as.character(ctx$results$vif_final_pass %||% character(0)),
        as.character(ctx$results$Model2Factors %||% character(0))
      ))
      pool <- pool[nzchar(pool)]
      covs <- setdiff(pool, ix[nzchar(ix)])
    }
  } else if (identical(src, "config")) {
    covs <- as.character(r_cfg$model_covariates %||% character(0))
  }
  covs <- covs[nzchar(covs)]
  intersect(unique(covs), data_cols)
}

.sroc_prepare_model_frame <- function(data_imp, index_var, outcome_var, analysis_grp, covariates) {
  y_raw <- data_imp[[outcome_var]]
  if (is.character(y_raw) || is.factor(y_raw)) {
    y_num <- ifelse(as.character(y_raw) == as.character(analysis_grp), 1L, 0L)
  } else {
    y_num <- as.numeric(y_raw)
  }
  pred <- suppressWarnings(as.numeric(as.character(data_imp[[index_var]])))
  cols <- unique(c(index_var, covariates))
  df <- data_imp[, cols, drop = FALSE]
  df$.y <- y_num
  df$.pred_index <- pred
  ok <- is.finite(df$.pred_index) & !is.na(df$.y)
  for (cn in covariates) {
    x <- df[[cn]]
    if (is.character(x) || is.factor(x)) next
    ok <- ok & is.finite(suppressWarnings(as.numeric(x)))
  }
  df <- df[ok, , drop = FALSE]
  df
}

.sroc_coerce_predictors <- function(df, vars) {
  for (cn in vars) {
    if (cn %in% names(df) && is.character(df[[cn]])) {
      df[[cn]] <- factor(df[[cn]])
    }
  }
  df
}

.sroc_fit_predict <- function(mdf, index_var, model_covariates, r_cfg) {
  engine <- tolower(trimws(as.character(r_cfg$model_engine %||% "glm")[1L]))
  if (!engine %in% c("glm", "rpart", "glmnet", "xgboost")) {
    stop("simple_ROC: model_engine 须为 'glm'、'rpart'、'glmnet' 或 'xgboost'。", call. = FALSE)
  }
  fml <- stats::as.formula(
    paste(".y ~", paste(c(index_var, model_covariates), collapse = " + "))
  )
  if (identical(engine, "rpart")) {
    if (!requireNamespace("rpart", quietly = TRUE)) {
      stop("simple_ROC (rpart): 需要 rpart 包。", call. = FALSE)
    }
    suppressPackageStartupMessages(library(rpart))
    dfx <- .sroc_coerce_predictors(mdf, c(index_var, model_covariates))
    cp <- as.numeric(r_cfg$rpart_cp %||% 0.001)
    minsplit <- as.integer(r_cfg$rpart_minsplit %||% 20L)[1L]
    ctrl <- rpart::rpart.control(minsplit = minsplit)
    maxdepth <- suppressWarnings(as.integer(r_cfg$rpart_maxdepth %||% NA_integer_)[1L])
    if (is.finite(maxdepth) && maxdepth >= 1L) {
      ctrl$maxdepth <- maxdepth
    }
    fit <- tryCatch(
      rpart::rpart(fml, data = dfx, method = "class", cp = cp, control = ctrl),
      error = function(e) {
        stop("simple_ROC (rpart): 拟合失败 — ", conditionMessage(e), call. = FALSE)
      }
    )
    pred <- as.numeric(stats::predict(fit, type = "prob")[, 2L])
    return(list(predictor = pred, engine = "rpart", fit = fit))
  }
  if (identical(engine, "glmnet")) {
    if (!requireNamespace("glmnet", quietly = TRUE)) {
      stop("simple_ROC (glmnet): 需要 glmnet 包。", call. = FALSE)
    }
    suppressPackageStartupMessages(library(glmnet))
    dfx <- .sroc_coerce_predictors(mdf, c(index_var, model_covariates))
    mm <- stats::model.matrix(fml, data = dfx)
    alpha <- as.numeric(r_cfg$glmnet_alpha %||% 0.5)
    nfolds <- as.integer(r_cfg$glmnet_nfolds %||% 10L)[1L]
    set.seed(as.integer(r_cfg$seed %||% r_cfg$model_seed %||% 42L))
    cv <- glmnet::cv.glmnet(
      mm, dfx$.y, family = "binomial", alpha = alpha, nfolds = nfolds
    )
    lam <- as.character(r_cfg$glmnet_lambda %||% "lambda.min")
    pred <- as.numeric(stats::predict(cv, newx = mm, s = lam, type = "response"))
    return(list(predictor = pred, engine = "glmnet", fit = cv))
  }
  if (identical(engine, "xgboost")) {
    if (!requireNamespace("xgboost", quietly = TRUE)) {
      stop("simple_ROC (xgboost): 需要 xgboost 包。", call. = FALSE)
    }
    suppressPackageStartupMessages(library(xgboost))
    dfx <- .sroc_coerce_predictors(mdf, c(index_var, model_covariates))
    mm <- as.matrix(stats::model.matrix(fml, data = dfx)[, -1L, drop = FALSE])
    set.seed(as.integer(r_cfg$xgb_seed %||% r_cfg$seed %||% r_cfg$model_seed %||% 42L))
    params <- list(
      objective = "binary:logistic",
      max_depth = as.integer(r_cfg$xgb_max_depth %||% 3L)[1L],
      eta = as.numeric(r_cfg$xgb_eta %||% 0.05),
      min_child_weight = as.numeric(r_cfg$xgb_min_child_weight %||% 30),
      subsample = as.numeric(r_cfg$xgb_subsample %||% 0.8),
      colsample_bytree = as.numeric(r_cfg$xgb_colsample_bytree %||% 0.8),
      lambda = as.numeric(r_cfg$xgb_lambda %||% 10)
    )
    nrounds <- as.integer(r_cfg$xgb_nrounds %||% 80L)[1L]
    dtrain <- xgboost::xgb.DMatrix(data = mm, label = dfx$.y)
    fit <- tryCatch(
      xgboost::xgb.train(params, dtrain, nrounds = nrounds, verbose = 0L),
      error = function(e) {
        stop("simple_ROC (xgboost): 拟合失败 — ", conditionMessage(e), call. = FALSE)
      }
    )
    pred <- as.numeric(stats::predict(fit, dtrain))
    return(list(predictor = pred, engine = "xgboost", fit = fit))
  }
  fit <- tryCatch(
    stats::glm(fml, data = mdf, family = stats::binomial),
    error = function(e) {
      stop("simple_ROC (glm): 拟合失败 — ", conditionMessage(e), call. = FALSE)
    }
  )
  list(
    predictor = as.numeric(stats::predict(fit, type = "response")),
    engine = "glm",
    fit = fit
  )
}

block_simple_ROC <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(pROC)
    library(ggplot2)
  })

  cfg   <- ctx$config
  r_cfg <- cfg$roc_simple %||% list()
  if (isFALSE(r_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$roc_simple$enable = FALSE，跳过 simple_ROC。")
    return(ctx)
  }

  data_imp <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data_imp)) stop("No data found. Run 'imputation' or 'data_clean' first.")
  data_imp <- as.data.frame(data_imp)

  inc_cfg <- cfg$incidence %||% list()
  log_cfg <- cfg$logistic %||% list()
  dat_cfg <- cfg$data %||% list()

  index_var   <- r_cfg$index_var %||% inc_cfg$index_var %||% log_cfg$index_var %||%
    (cfg$survival %||% list())$index_var
  outcome_var <- .sroc_resolve_outcome_var(r_cfg, cfg)
  ff <- plot_font_from_config(list(
    plot = list(font_family = r_cfg$font_family %||% cfg$plot$font_family %||% "Times New Roman")
  ))

  if (is.null(index_var) || !nzchar(index_var)) {
    stop("simple_ROC: index_var 未指定（config$roc_simple$index_var / config$incidence$index_var）。")
  }
  if (!index_var %in% names(data_imp)) {
    stop("simple_ROC: index_var '", index_var, "' 不在数据列中。")
  }
  if (!outcome_var %in% names(data_imp)) {
    stop("simple_ROC: outcome_var '", outcome_var, "' 不在数据列中。")
  }

  analysis_grp <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref_grp      <- cfg$project$reference_group %||% "Control"
  db_name      <- cfg$project$database %||% "UnknownDB"

  roc_mode <- .sroc_resolve_mode(r_cfg)

  cli::cli_alert_info(
    "simple_ROC: mode = {.field {roc_mode}}, index = {.field {index_var}}, outcome = {.field {outcome_var}}"
  )

  model_covariates <- character(0)
  roc_model_type   <- "Univariate"
  roc_model_engine <- "glm"
  if (identical(roc_mode, "multivariable")) {
    model_covariates <- .sroc_resolve_covariates(
      r_cfg, names(data_imp), ctx = ctx, cfg = cfg
    )
    if (!length(model_covariates)) {
      stop(
        "simple_ROC: mode=multivariable 但锁定协变量为空。",
        "请把 simple_ROC 放在 VIF final / Gate B / multivariate_*_harmonized 之后，",
        "或设 roc_simple$mode='univariate' / covariate_source='config'。",
        call. = FALSE
      )
    }
    roc_model_engine <- tolower(trimws(as.character(r_cfg$model_engine %||% "glm")[1L]))
    roc_model_type <- switch(
      roc_model_engine,
      rpart = "Multivariable (rpart)",
      glmnet = "Multivariable (glmnet)",
      xgboost = "Multivariable (xgboost)",
      "Multivariable (glm)"
    )
    cli::cli_alert_info(
      "Multivariable ROC ({roc_model_engine}, {length(model_covariates)} covariates): {paste(model_covariates, collapse = ', ')}"
    )
  }

  # ── 准备响应变量与预测得分 ───────────────────────────────────────────────────
  if (identical(roc_mode, "multivariable")) {
    mdf <- .sroc_prepare_model_frame(
      data_imp, index_var, outcome_var, analysis_grp, model_covariates
    )
    y_num <- mdf$.y
    fit_res <- .sroc_fit_predict(mdf, index_var, model_covariates, r_cfg)
    predictor <- fit_res$predictor
    roc_model_engine <- fit_res$engine
    roc_model_type <- switch(
      roc_model_engine,
      rpart = "Multivariable (rpart)",
      glmnet = "Multivariable (glmnet)",
      xgboost = "Multivariable (xgboost)",
      "Multivariable (glm)"
    )
    if (is.character(data_imp[[outcome_var]]) || is.factor(data_imp[[outcome_var]])) {
      cli::cli_alert_info("Outcome '{analysis_grp}' → 1, others → 0")
    } else {
      cli::cli_alert_info("Outcome column '{outcome_var}' (numeric event)")
    }
  } else {
    predictor <- suppressWarnings(as.numeric(as.character(data_imp[[index_var]])))
    y_raw     <- data_imp[[outcome_var]]
    if (is.character(y_raw) || is.factor(y_raw)) {
      y_num <- ifelse(as.character(y_raw) == as.character(analysis_grp), 1L, 0L)
      cli::cli_alert_info("Outcome '{analysis_grp}' → 1, others → 0")
    } else {
      y_num <- as.numeric(y_raw)
    }
    ok <- is.finite(predictor) & !is.na(y_num)
    predictor <- predictor[ok]
    y_num     <- y_num[ok]
  }

  n_valid <- length(y_num)
  if (n_valid < 20L) {
    cli::cli_alert_warning("simple_ROC: 有效观测仅 {n_valid}，跳过 ROC。")
    return(ctx)
  }
  if (length(unique(y_num)) < 2L) {
    cli::cli_alert_warning("simple_ROC: 结局只有单一类别，跳过 ROC。")
    return(ctx)
  }

  cli::cli_alert_info("Valid observations: {n_valid} (case = {sum(y_num == 1)}, control = {sum(y_num == 0)})")

  # ── 计算 ROC ────────────────────────────────────────────────────────────────
  roc_obj <- pROC::roc(response = y_num, predictor = predictor, quiet = TRUE)
  auc_v   <- as.numeric(pROC::auc(roc_obj))
  auc_ci  <- pROC::ci.auc(roc_obj, quiet = TRUE)
  coords  <- pROC::coords(roc_obj, "all",
                            ret = c("sensitivity", "specificity", "threshold"))
  j_idx   <- coords$sensitivity + coords$specificity - 1
  i_best  <- which.max(j_idx)
  best_spec <- coords$specificity[i_best]
  best_sens <- coords$sensitivity[i_best]
  cutoff    <- coords$threshold[i_best]

  cli::cli_alert_info("AUC = {format(round(auc_v, 3), nsmall = 3)} [{format(round(auc_ci[1], 3), nsmall = 3)} - {format(round(auc_ci[3], 3), nsmall = 3)}]")
  cli::cli_alert_info("Youden cutoff = {format(round(cutoff, 4), scientific = FALSE)} (sensitivity = {format(round(best_sens, 3), nsmall = 3)}, specificity = {format(round(best_spec, 3), nsmall = 3)})")

  # ── 构图 ────────────────────────────────────────────────────────────────────
  df_line <- data.frame(
    x = 1 - coords$specificity,
    y = coords$sensitivity
  )

  lbl <- paste0(
    "AUC = ", format(round(auc_v, 3), nsmall = 3),
    "\n95% CI: [", format(round(auc_ci[1], 3), nsmall = 3), ", ",
    format(round(auc_ci[3], 3), nsmall = 3), "]"
  )

  # 发表图不标注样本量（双库一致；n 仍写入 ROC 汇总表）
  ix_disp <- pipeline_index_display_name(cfg, index_var)
  title_str <- if (identical(roc_mode, "multivariable")) {
    if (identical(roc_model_engine, "rpart")) {
      "ROC Curve for multivariable classification tree"
    } else if (identical(roc_model_engine, "glmnet")) {
      "ROC Curve for multivariable penalized logistic model"
    } else if (identical(roc_model_engine, "xgboost")) {
      "ROC Curve for multivariable gradient boosting model"
    } else {
      "ROC Curve for multivariable prediction model"
    }
  } else {
    paste0("ROC Curve for ", ix_disp)
  }

  g <- ggplot(df_line, aes(x = .data$x, y = .data$y)) +
    geom_path(linewidth = 1, color = "#C6524A") +
    geom_abline(slope = 1, intercept = 0, linetype = "longdash", color = "gray50", linewidth = 0.8) +
    scale_x_continuous("1 - Specificity", breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
    scale_y_continuous("Sensitivity", breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
    annotate(
      "text", x = 1, y = 0.2, label = lbl, hjust = 1,
      size = 4.2, color = "#C6524A", fontface = "bold", family = ff
    ) +
    labs(title = title_str) +
    theme_bw(base_family = ff) +
    theme(
      plot.title       = element_text(hjust = 0.5, size = 14, face = "bold", family = ff),
      axis.title       = element_text(size = 11, family = ff),
      axis.text        = element_text(family = ff),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank(),
      panel.background = element_rect(fill = "white", color = NA),
      plot.background  = element_rect(fill = "white", color = NA),
      panel.border     = element_rect(color = "black", fill = NA, linewidth = 0.5)
    )

  if (exists("is_pub_profile", mode = "function") &&
      is_pub_profile(cfg, "mimic_inc_prog_sle_aki")) {
    g <- g +
      ggplot2::annotate(
        "point", x = 1 - best_spec, y = best_sens,
        color = "#2874C5", size = 3.2, shape = 19
      ) +
      ggplot2::annotate(
        "text",
        x = min(1 - best_spec + 0.05, 0.98),
        y = max(best_sens - 0.05, 0.05),
        label = paste0("Youden cutoff: ", format(round(cutoff, 4), scientific = FALSE)),
        hjust = 0, vjust = 1, size = 3.6, color = "#2874C5", family = ff
      )
    if (exists("pub_figure_profile_apply_ggplot", mode = "function")) {
      g <- pub_figure_profile_apply_ggplot(g, cfg)
    }
  }

  # ── 保存图 ──────────────────────────────────────────────────────────────────
  fig_w <- r_cfg$figure_width %||% 8
  fig_h <- r_cfg$figure_height %||% 7
  if (exists("is_pub_profile", mode = "function") &&
      is_pub_profile(cfg, "mimic_inc_prog_sle_aki")) {
    fig_w <- min(as.numeric(fig_w)[1L], 6.5)
    fig_h <- fig_w
  }
  fig_caption <- as.character(
    r_cfg$figure_caption %||%
      if (identical(roc_mode, "multivariable")) {
        paste0("ROC Multivariable ", ix_disp)
      } else {
        paste0("ROC ", ix_disp)
      }
  )[1L]
  fig_dir  <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
  # 发表规范：默认 Figure S*；可用 figure_number 固定编号（预后双库 S4）
  fig_kind <- as.character(r_cfg$figure_kind %||% "supp_figure")[1L]
  if (!nzchar(fig_kind)) fig_kind <- "supp_figure"
  fig_no <- suppressWarnings(as.integer(r_cfg$figure_number %||% NA_integer_)[1L])
  # boxplot 通常占 Figure S1；ROC 固定 S1 会在全项目重复出两张 ROC（编号重排后残留 S3）
  if (is.finite(fig_no) && fig_no == 1L) {
    existing_s1 <- list.files(
      fig_dir,
      pattern = "^Figure S1.*Boxplot.*\\.pdf$",
      ignore.case = TRUE
    )
    if (length(existing_s1)) {
      fig_no <- 2L
      cli::cli_alert_info("simple_ROC: Boxplot 已占 Figure S1，ROC 改用 Figure S2")
    }
  }
  fig_path <- if (is.finite(fig_no) && fig_no >= 1L &&
                  exists("pub_figure_filepath_at", mode = "function")) {
    pub_figure_filepath_at(
      fig_dir, fig_no, fig_caption, ext = "pdf",
      bump_counter = isTRUE(r_cfg$bump_counter %||% FALSE),
      kind = fig_kind
    )
  } else {
    file.path(fig_dir, pub_figure_file(ctx, fig_kind, fig_caption))
  }
  fig_name <- basename(fig_path)

  ff_resolved <- plot_font_from_config(cfg)
  tryCatch(
    {
      grDevices::cairo_pdf(fig_path, width = fig_w, height = fig_h, family = ff_resolved)
      print(g)
      grDevices::dev.off()
      cli::cli_alert_success("ROC figure saved: {.file {fig_path}}")
    },
    error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("cairo_pdf failed ({e$message}); retrying with pdf()…")
      tryCatch({
        grDevices::pdf(fig_path, width = fig_w, height = fig_h)
        print(g)
        grDevices::dev.off()
        cli::cli_alert_success("ROC figure saved: {.file {fig_path}}")
      }, error = function(e2) {
        try(grDevices::dev.off(), silent = TRUE)
        cli::cli_alert_danger("ROC figure not saved: {e2$message}")
      })
    }
  )
  mirror_pub_output_to_root(ctx, fig_path)

  # ── 汇总表 ──────────────────────────────────────────────────────────────────
  summary_df <- data.frame(
    Model_Type    = roc_model_type,
    Model_Engine  = roc_model_engine,
    Variable      = index_var,
    Covariates    = if (length(model_covariates)) {
      paste(model_covariates, collapse = ", ")
    } else {
      ""
    },
    Outcome       = outcome_var,
    N             = n_valid,
    N_Case        = sum(y_num == 1),
    N_Control     = sum(y_num == 0),
    AUC           = fmt_num(auc_v, 3),
    AUC_CI_Lower  = fmt_num(auc_ci[1], 3),
    AUC_CI_Upper  = fmt_num(auc_ci[3], 3),
    Youden_Cutoff = fmt_num(cutoff, 4),
    Sensitivity   = fmt_num(best_sens, 3),
    Specificity   = fmt_num(best_spec, 3),
    stringsAsFactors = FALSE
  )

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)

  if (isTRUE(r_cfg$export_table %||% FALSE)) {
    tbl_suffix <- as.character(r_cfg$table_title_suffix %||% "")[1L]
    tbl_title <- paste0(
      "ROC Analysis of ", ix_disp, " (", db_name, ")",
      if (nzchar(tbl_suffix)) paste0(" — ", tbl_suffix) else ""
    )
    tbl_pub <- pub_pair(
      ctx, tbl_dir, "supp_table",
      title_caption = tbl_title,
      file_caption  = fig_caption,
      ext = "xlsx"
    )
    tryCatch(
      export_sci_table(summary_df, tbl_pub$filepath, title = tbl_pub$title),
      error = function(e) cli::cli_alert_warning("ROC table export failed: {e$message}")
    )
    cli::cli_alert_success("ROC table saved: {.file {basename(tbl_pub$filepath)}}")
  } else {
    cli::cli_alert_info("simple_ROC: export_table=FALSE，跳过 ROC 附表（仅保留图与 cutoff）")
  }

  # ── 写入 ctx$results ────────────────────────────────────────────────────────
  ctx$results$roc_auc         <- auc_v
  ctx$results$roc_ci          <- c(lo = as.numeric(auc_ci[1]), hi = as.numeric(auc_ci[3]))
  ctx$results$roc_cutoff      <- cutoff
  ctx$results$roc_sensitivity <- best_sens
  ctx$results$roc_specificity <- best_spec
  ctx$results$roc_simple_summary <- summary_df
  ctx$results$roc_mode <- roc_mode
  ctx$results$roc_model_engine <- roc_model_engine
  if (length(model_covariates)) {
    ctx$results$roc_model_covariates <- model_covariates
  }

  write_cutoff <- isTRUE(r_cfg$write_cutoff_value %||% TRUE) &&
    !identical(roc_mode, "multivariable")
  if (write_cutoff && is.null(ctx$results$cutoff_value)) {
    ctx$results$cutoff_value <- cutoff
    cli::cli_alert_info("cutoff_value written to ctx$results ({format(round(cutoff, 4), scientific = FALSE)})")
  }

  cli::cli_alert_success("simple_ROC completed (AUC = {format(round(auc_v, 3), nsmall = 3)})")
  ctx
}

register_block("simple_ROC", block_simple_ROC,
               "Simple / multivariable ROC (pROC): AUC, Youden cutoff, publication figure")
