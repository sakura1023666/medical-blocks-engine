###############################################################################
#  shiny_ml_app — ML 风险预测 Shiny App（C01 / ShinyApp + 生成 app.R）
#
#  register_block: "shiny_ml_app"
#  典型流水线: train_validation → ml_models → shiny_ml_app
#              （非 logistic 最优模型；或由 block_shiny 调度）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = train_validation/Data；ml_models/Models/evalresult_<tag>.RData
#  require_results = Model2Factors、ml_best_model_tag（或 shiny_ml_app$ml_model_tag）
#
#  shiny_ml_app = list(
#    enable = TRUE, ml_model_tag = NULL, index_var = NULL,
#    export_app = TRUE, risk_high_pct = 70, risk_low_pct = 30,
#    app_subdir = "ShinyApp", run_interactive = FALSE,
#    # 预后/Cox：默认 surv_prognostic（对齐 https://webcalcula.shinyapps.io/RSF-model_pro/）
#    ui_style = "surv_prognostic"
#  ),
#  未设 shiny_ml_app 时回退 config$shiny 同名键
###############################################################################

.sma_build_glmnet_cox_baseline <- function(final_model, df_train, feats, time_col, event_col) {
  if (!requireNamespace("survival", quietly = TRUE)) return(NULL)
  if (!requireNamespace("glmnet", quietly = TRUE)) return(NULL)
  feats <- as.character(feats)
  feats <- feats[feats %in% names(df_train)]
  if (!length(feats)) return(NULL)
  tm <- suppressWarnings(as.numeric(df_train[[time_col]]))
  ev <- df_train[[event_col]]
  if (is.null(tm) || is.null(ev)) return(NULL)
  if (is.factor(ev) || is.character(ev)) {
    ev_chr <- as.character(ev)
    ev01 <- ifelse(
      ev_chr %in% c("1", "Dead", "Death", "Non-survivor", "Yes", "Event"), 1L,
      ifelse(ev_chr %in% c("0", "Alive", "Survivor", "No", "Censor", "Censored"), 0L, NA_integer_)
    )
  } else {
    ev01 <- as.integer(ev)
  }
  ok <- is.finite(tm) & !is.na(ev01) & ev01 %in% c(0L, 1L)
  d <- df_train[ok, feats, drop = FALSE]
  tm <- tm[ok]
  ev01 <- ev01[ok]
  ## 丢掉特征 NA，保证 mm 行与 Surv 对齐
  keep <- stats::complete.cases(d)
  if (!any(keep)) return(NULL)
  d <- d[keep, , drop = FALSE]
  tm <- tm[keep]
  ev01 <- ev01[keep]
  mm <- tryCatch(
    stats::model.matrix(~ . - 1, data = d),
    error = function(e) NULL
  )
  if (is.null(mm) || !nrow(mm) || nrow(mm) != length(tm)) return(NULL)
  beta <- tryCatch({
    ## glmnet 方法需包已 load；勿用未导出的 coef.cv.glmnet
    suppressPackageStartupMessages(requireNamespace("glmnet", quietly = TRUE))
    b <- coef(final_model, s = "lambda.min")
    if (is.null(b)) {
      j <- which.min(abs(final_model$lambda - final_model$lambda.min))
      as.matrix(final_model$glmnet.fit$beta[, j, drop = FALSE])
    } else {
      as.matrix(b)
    }
  }, error = function(e) {
    tryCatch({
      j <- which.min(abs(final_model$lambda - final_model$lambda.min))
      as.matrix(final_model$glmnet.fit$beta[, j, drop = FALSE])
    }, error = function(e2) NULL)
  })
  if (is.null(beta) || !nrow(beta)) return(NULL)
  cn <- intersect(colnames(mm), rownames(beta))
  if (!length(cn)) return(NULL)
  x <- mm[, cn, drop = FALSE]
  bvec <- as.numeric(beta[cn, 1L])
  names(bvec) <- cn
  lp <- as.numeric(x %*% bvec)
  bl <- tryCatch({
    fit <- survival::coxph(
      survival::Surv(tm, ev01) ~ offset(lp),
      x = FALSE, y = TRUE
    )
    bh <- survival::basehaz(fit, centered = FALSE)
    list(
      time = as.numeric(bh$time),
      surv0 = exp(-as.numeric(bh$hazard)),
      coef = bvec,
      mm_cols = cn,
      lp_mean = mean(lp, na.rm = TRUE)
    )
  }, error = function(e) NULL)
  bl
}
.sma_merged_cfg <- function(cfg) {
  sh <- cfg$shiny %||% list()
  sma <- cfg$shiny_ml_app %||% list()
  if (length(sma)) utils::modifyList(sh, sma) else sh
}

.sma_resolve_tv_data_dir <- function(ctx) {
  .remap <- function(p) {
    p <- as.character(p %||% "")[1L]
    if (!nzchar(p)) return("")
    if (dir.exists(p)) return(p)
    p2 <- sub("/by_index/([^/【]+)/", "/by_index/\u3010success\u3011\\1/", p, perl = TRUE)
    if (dir.exists(p2)) return(p2)
    p
  }
  tv <- ctx$log$block_output_dirs[["train_validation"]] %||% ""
  tv <- .remap(as.character(tv)[1L])
  if (nzchar(tv)) {
    d <- file.path(tv, "Data")
    if (dir.exists(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
  }
  out <- .remap(as.character(ctx$output_dir %||% "")[1L])
  d2 <- file.path(out, "Data")
  if (dir.exists(d2)) return(normalizePath(d2, winslash = "/", mustWork = FALSE))
  ## step*_train_validation/Data under output
  if (nzchar(out) && dir.exists(out)) {
    hits <- list.files(out, pattern = "^step[0-9]+_train_validation$", full.names = TRUE)
    for (h in hits) {
      d <- file.path(h, "Data")
      if (dir.exists(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
    }
  }
  ""
}

.sma_resolve_ml_models_dir <- function(ctx, tag = NULL) {
  if (!is.null(tag) && nzchar(as.character(tag)[1L])) {
    d <- resolve_ml_models_dir_for_tag(ctx, tag)
    if (dir.exists(d)) {
      return(normalizePath(d, winslash = "/", mustWork = FALSE))
    }
  }
  ml_block <- as.character(ctx$log$block_output_dirs[["ml_models_bundle"]] %||% "")[1L]
  if (nzchar(ml_block)) {
    ml_block2 <- sub("/by_index/([^/【]+)/", "/by_index/\u3010success\u3011\\1/", ml_block, perl = TRUE)
    for (mb in unique(c(ml_block, ml_block2))) {
      d <- file.path(mb, "Models")
      if (dir.exists(d)) return(normalizePath(d, winslash = "/", mustWork = FALSE))
    }
  }
  stored <- as.character(ctx$results[["ml_models_models_dir"]] %||% "")[1L]
  if (nzchar(stored)) {
    stored2 <- sub("/by_index/([^/【]+)/", "/by_index/\u3010success\u3011\\1/", stored, perl = TRUE)
    for (s in unique(c(stored, stored2))) {
      if (dir.exists(s)) return(normalizePath(s, winslash = "/", mustWork = FALSE))
    }
  }
  ""
}

.sma_resolve_index_vars <- function(cfg, sma_cfg) {
  # 单指标课题优先 prediction / ml_batch，避免 preset 残留 ALBI/RAR/SII 等
  candidates <- list(
    sma_cfg$index_var,
    (cfg$ml_batch %||% list())$index_vars,
    (cfg$prediction %||% list())$index_vars,
    (cfg$incidence %||% list())$index_var,
    (cfg$index %||% list())$only
  )
  idx <- character(0)
  for (cand in candidates) {
    v <- unique(as.character(cand %||% character(0)))
    v <- v[nzchar(trimws(v))]
    if (length(v)) {
      idx <- v
      break
    }
  }
  if (!length(idx)) {
    cli::cli_alert_info(
      "block_shiny_ml_app: 未配置主暴露 index，按纯预测特征生成 Shiny（侧栏不标注 index）。"
    )
    return(character(0))
  }
  # 单指标 loop：只保留当前分析指标（与 prediction$index_vars / ml_batch 对齐）
  active <- unique(as.character(
    (cfg$prediction %||% list())$index_vars %||%
      (cfg$ml_batch %||% list())$index_vars %||%
      character(0)
  ))
  active <- active[nzchar(trimws(active))]
  if (length(active)) {
    hit <- intersect(idx, active)
    if (length(hit)) idx <- hit
  }
  if (length(idx) > 1L && identical(as.character((cfg$ml_batch %||% list())$index_mode %||% ""), "single_loop")) {
    idx <- idx[[1L]]
  }
  if (length(idx) > 1L) {
    cli::cli_alert_info(
      "block_shiny_ml_app: 纳入 {length(idx)} 个 index 指标: {paste(idx, collapse = ', ')}"
    )
  }
  idx
}

.sma_resolve_ml_tag <- function(ctx, sma_cfg) {
  tag <- as.character(sma_cfg$ml_model_tag %||% ctx$results$ml_best_model_tag %||% "")[1L]
  if (!nzchar(tag)) {
    tag <- as.character(sma_cfg$ml_model_tag_fallback %||% "logistic")[1L]
  }
  tolower(trimws(tag))
}

.sma_recipe_type_for_ml_tag <- function(tag) {
  tg <- tolower(trimws(tag))
  if (tg %in% c("enet", "rsvm")) return("center_scale")
  if (tg %in% c("mlp", "realmlp")) return("range")
  "none"
}

.sma_build_recipe <- function(train_dat, scale_type = "none") {
  r <- recipes::recipe(Group ~ ., data = train_dat)
  r <- recipes::step_impute_median(r, recipes::all_numeric_predictors())
  r <- recipes::step_impute_mode(r, recipes::all_nominal_predictors())
  r <- recipes::step_dummy(r, recipes::all_nominal_predictors())
  if (identical(scale_type, "center_scale")) {
    r <- recipes::step_center(r, recipes::all_predictors())
    r <- recipes::step_scale(r, recipes::all_predictors())
  } else if (identical(scale_type, "range")) {
    r <- recipes::step_range(r, recipes::all_predictors())
  }
  recipes::prep(r)
}

.sma_copy_if_exists <- function(src, dst) {
  if (!nzchar(src) || !file.exists(src)) return(FALSE)
  dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
  isTRUE(tryCatch(file.copy(src, dst, overwrite = TRUE), error = function(e) FALSE))
}

.sma_ensure_group_column <- function(df, cfg) {
  if ("Group" %in% names(df)) return(df)
  oc <- cfg$data$outcome_column %||% "Disease"
  ana <- cfg$project$analysis_group %||% cfg$project$disease %||% "Case"
  ref <- cfg$project$reference_group %||% "Control"
  if (oc %in% names(df)) {
    y_chr <- trimws(as.character(df[[oc]]))
    df$Group <- factor(
      ifelse(y_chr == trimws(ana), ana, ifelse(y_chr == trimws(ref), ref, NA_character_)),
      levels = c(ref, ana)
    )
    return(df)
  }
  if ("fustatus" %in% names(df)) {
    colnames(df)[colnames(df) == "fustatus"] <- "Group"
    return(df)
  }
  if ("Disease" %in% names(df)) {
    colnames(df)[colnames(df) == "Disease"] <- "Group"
    return(df)
  }
  df
}

.sma_resolve_model2_factors <- function(ctx) {
  Model2Factors <- as.character(ctx$results$Model2Factors %||% character(0))
  Model2Factors <- unique(Model2Factors[nzchar(Model2Factors)])
  if (length(Model2Factors)) return(Model2Factors)
  fs_dir <- as.character(ctx$log$block_output_dirs[["feature_selection"]] %||% "")[1L]
  m2_path <- if (nzchar(fs_dir)) file.path(fs_dir, "Model2Factors.RData") else ""
  if (nzchar(m2_path) && file.exists(m2_path)) {
    e_m2 <- new.env(parent = emptyenv())
    load(m2_path, envir = e_m2)
    if (exists("Model2Factors", envir = e_m2)) {
      Model2Factors <- as.character(e_m2$Model2Factors)
    }
  }
  unique(Model2Factors[nzchar(Model2Factors)])
}

.sma_pick_max_predicted_individual <- function(rdata_path, cov_names) {
  if (!nzchar(rdata_path) || !file.exists(rdata_path)) {
    return(list(ok = FALSE, msg = paste0("未找到 ", rdata_path)))
  }
  e <- new.env(parent = emptyenv())
  load(rdata_path, envir = e)
  nms <- ls(envir = e, pattern = "^final_prediction", all.names = TRUE)
  if (!length(nms)) {
    if (exists("final_predictions", envir = e, inherits = FALSE)) {
      nms <- "final_predictions"
    } else {
      return(list(ok = FALSE, msg = "evalresult 中无 final_predictions 或 final_prediction* 对象。"))
    }
  }
  dfs <- list()
  for (nm in nms) {
    obj <- get(nm, envir = e)
    if (is.data.frame(obj) && nrow(obj) > 0L) dfs[[nm]] <- obj
  }
  if (!length(dfs)) {
    return(list(ok = FALSE, msg = "final_predictions 为空。"))
  }
  big <- if (length(dfs) == 1L) dfs[[1L]] else dplyr::bind_rows(dfs)
  pred_cols <- grep("_predicted_value$", names(big), value = TRUE)
  if (!length(pred_cols)) {
    return(list(ok = FALSE, msg = "final_predictions 中无 *_predicted_value 列。"))
  }
  pm <- as.matrix(big[, pred_cols, drop = FALSE])
  if (!is.numeric(pm)) mode(pm) <- "numeric"
  row_max <- apply(pm, 1L, function(z) suppressWarnings(max(as.numeric(z), na.rm = TRUE)))
  row_max[!is.finite(row_max)] <- NA_real_
  if (all(is.na(row_max))) {
    return(list(ok = FALSE, msg = "_predicted_value 列无法转为有效数值。"))
  }
  imax <- which.max(row_max)
  ref <- big[imax, , drop = FALSE]
  cov_keep <- intersect(cov_names, names(ref))
  ref_cov <- if (length(cov_keep)) ref[, cov_keep, drop = FALSE] else ref[, character(0), drop = FALSE]
  top_col <- pred_cols[which.max(as.numeric(ref[1, pred_cols, drop = TRUE]))]
  top_val <- suppressWarnings(max(as.numeric(ref[1, pred_cols, drop = TRUE]), na.rm = TRUE))
  summ <- paste0(
    "参考个体：final_predictions 第 ", imax, " 行（*_predicted_value 行内最大约 ",
    format(top_val, digits = 6), "，列 ", top_col, "）。"
  )
  list(ok = TRUE, row = ref_cov, summary = summ)
}

.sma_default_for_covariate <- function(v, ref_row, x_train) {
  ref_one <- NULL
  if (!is.null(ref_row) && is.data.frame(ref_row) && nrow(ref_row) >= 1L && v %in% names(ref_row)) {
    ref_one <- ref_row[[v]][1L]
  }
  x <- x_train[[v]]
  if (is.numeric(x) || is.integer(x)) {
    def <- if (!is.null(ref_one) && is.finite(suppressWarnings(as.numeric(ref_one)))) {
      as.numeric(ref_one)
    } else {
      suppressWarnings(stats::median(x, na.rm = TRUE))
    }
    if (!is.finite(def)) def <- 0
    return(list(kind = "numeric", value = def))
  }
  if (is.logical(x)) {
    def <- if (!is.null(ref_one)) as.logical(ref_one) else as.logical(stats::median(as.integer(x), na.rm = TRUE))
    if (is.na(def)) def <- FALSE
    return(list(kind = "logical", value = def))
  }
  levs <- if (is.factor(x)) levels(x) else unique(as.character(x[!is.na(x)]))
  if (!length(levs)) levs <- ""
  def <- if (!is.null(ref_one)) {
    rc <- as.character(ref_one)
    if (rc %in% levs) rc else NA_character_
  } else {
    NA_character_
  }
  if (is.na(def) || !length(def)) {
    def <- levs[which.max(tabulate(match(as.character(x), levs)))]
  }
  if (!length(def) || is.na(def)) def <- levs[1]
  list(kind = "factor", value = def, levels = levs)
}

.sma_r_string <- function(x) {
  paste0("\"", gsub("\\\\", "\\\\\\\\", gsub("\"", "\\\\\"", as.character(x))), "\"")
}

.sma_r_literal <- function(x) {
  x <- as.character(x)
  if (length(x) <= 1L) return(.sma_r_string(x[1L]))
  paste0("c(", paste(vapply(x, .sma_r_string, character(1L)), collapse = ", "), ")")
}

.sma_generate_sidebar_ui_lines <- function(cov_names, defaults, index_vars) {
  index_vars <- as.character(index_vars)
  lines <- character(0)
  for (v in cov_names) {
    id <- v
    lab <- gsub("_", " ", v, fixed = TRUE)
    if (v %in% index_vars) lab <- paste0(lab, " (index)")
    d <- defaults[[v]]
    if (d$kind == "numeric") {
      lines <- c(lines, sprintf(
        "      numericInput(%s, %s, value = %s),",
        .sma_r_string(id), .sma_r_string(paste0("Please enter your ", lab)),
        as.character(d$value)
      ))
    } else if (d$kind == "logical") {
      sel <- if (isTRUE(d$value)) "TRUE" else "FALSE"
      lines <- c(lines, sprintf(
        "      selectInput(%s, %s, choices = c(\"FALSE\", \"TRUE\"), selected = %s),",
        .sma_r_string(id), .sma_r_string(paste0("Please enter your ", lab)),
        .sma_r_string(sel)
      ))
    } else {
      ch <- paste(vapply(d$levels, .sma_r_string, character(1L)), collapse = ", ")
      lines <- c(lines, sprintf(
        "      selectInput(%s, %s, choices = c(%s), selected = %s),",
        .sma_r_string(id), .sma_r_string(paste0("Please enter your ", lab)),
        ch, .sma_r_string(d$value)
      ))
    }
  }
  lines
}

.sma_generate_server_assign_lines <- function(cov_names) {
  vapply(cov_names, function(v) sprintf("    %s <- input$%s", v, v), character(1L))
}

.sma_generate_df_assign_lines <- function(cov_names) {
  vapply(cov_names, function(v) sprintf("      %s = %s,", v, v), character(1L))
}

.sma_generate_predict_lines <- function(ml_tag, pred_col, disease, risk_hi, risk_lo) {
  tg <- tolower(trimws(as.character(ml_tag)[1L]))
  ## 生存模型（rfsrc / xgb / gbm / glmnet / CoxBoost）不是 tidymodels workflow，
  ## 不能用 predict(..., new_data=, type=\"prob\")，否则取不到概率 → if(length0) 闪退。
  if (identical(tg, "rsf")) {
    return(c(
      "    ## RSF：原始因子帧 + newdata；事件概率 = 1 - S(t) @ surv_horizon",
      "    feats <- shiny_staging$Final_Features",
      "    if (!is.null(shiny_staging$model_features) && length(shiny_staging$model_features))",
      "      feats <- shiny_staging$model_features",
      "    miss <- setdiff(feats, names(df))",
      "    if (length(miss)) stop(\"缺少特征: \", paste(miss, collapse = \", \"))",
      "    df_use <- df[, feats, drop = FALSE]",
      "    for (cn in names(df_use)) {",
      "      if (is.character(df_use[[cn]]) || is.logical(df_use[[cn]]))",
      "        df_use[[cn]] <- factor(as.character(df_use[[cn]]))",
      "    }",
      "    ## 对齐训练集因子水平（避免新水平导致 rfsrc 失败）",
      "    if (exists(\"df_train\") && is.data.frame(df_train)) {",
      "      for (cn in names(df_use)) {",
      "        if (!is.factor(df_use[[cn]]) || !cn %in% names(df_train)) next",
      "        lv <- levels(factor(df_train[[cn]]))",
      "        if (length(lv)) df_use[[cn]] <- factor(as.character(df_use[[cn]]), levels = lv)",
      "      }",
      "    }",
      "    pr <- predict(final_model, newdata = df_use)",
      "    hor <- as.numeric(shiny_staging$surv_horizon %||% 48)[1]",
      "    if (!is.finite(hor)) hor <- 48",
      "    j <- which.min(abs(pr$time.interest - hor))",
      "    p1 <- as.numeric(1 - pr$survival[1, j])",
      "    if (!is.finite(p1)) p1 <- as.numeric(pr$predicted[1])",
      "    if (!is.finite(p1)) stop(\"RSF 预测失败：无有效风险/生存概率\")",
      "    ## predicted 若为死亡率尺度，回退用经验秩次压到 0-1",
      "    if (p1 < 0 || p1 > 1) {",
      "      p1 <- stats::plogis(as.numeric(pr$predicted[1]) - mean(as.numeric(pr$predicted), na.rm = TRUE))",
      "    }",
      "    predicted_probability <- round(p1 * 100, 2)"
    ))
  }
  if (tg %in% c("xgbsurv", "gbmsurv", "coxboost", "ridge_cox", "enet_cox")) {
    return(c(
      "    stop(paste0(",
      paste0("      \"Shiny 生存模型标签 ", tg, " 的网页预测路径尚未启用；当前课题最优为 RSF。\""),
      "    ))"
    ))
  }
  ## 默认：分类 tidymodels workflow
  c(
    "    df_processed <- bake(datarecipe, new_data = df)",
    "    pred_prob <- predict(final_model, new_data = df_processed, type = \"prob\")",
    paste0("    pred_col <- ", .sma_r_string(pred_col)),
    "    if (!pred_col %in% names(pred_prob)) {",
    "      pcols <- grep(\"^\\\\.pred_\", names(pred_prob), value = TRUE)",
    "      if (!length(pcols)) stop(\"预测结果无 .pred_* 概率列\")",
    "      pred_col <- pcols[length(pcols)]",
    "    }",
    "    predicted_probability <- round(as.numeric(pred_prob[[pred_col]]) * 100, 2)",
    "    if (!length(predicted_probability) || !is.finite(predicted_probability[1]))",
    "      stop(\"未能得到有效预测概率\")",
    "    predicted_probability <- predicted_probability[1]"
  )
}

.sma_write_app_r <- function(app_dir, meta) {
  ml_tag <- tolower(trimws(as.character(meta$ml_tag %||% "")[1L]))
  ui_style <- tolower(trimws(as.character(meta$ui_style %||% "")[1L]))
  study_type <- tolower(trimws(as.character(meta$study_type %||% "")[1L]))
  assoc <- tolower(trimws(as.character(meta$assoc_model %||% "")[1L]))
  ## 预后 / Cox 关联：默认文献站风格（navbar + 多时点 + 生存曲线）
  ## https://webcalcula.shinyapps.io/RSF-model_pro/
  surv_tags <- c("rsf", "ridge_cox", "enet_cox", "xgbsurv", "gbmsurv", "coxboost")
  use_surv_prog <- identical(ui_style, "rsf_prognostic") ||
    identical(ui_style, "surv_prognostic") ||
    (identical(ui_style, "") &&
       (identical(study_type, "prognosis") || identical(assoc, "cox")) &&
       ml_tag %in% surv_tags)
  if (isTRUE(use_surv_prog) && !identical(ui_style, "classic")) {
    root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    ## 通用生存模板优先；旧 RSF 专用模板作回退
    tmpl_cands <- c(
      file.path(root, "Blocks/25_shiny/templates/app_surv_prognostic.R"),
      file.path(root, "Blocks/25_shiny/templates/app_rsf_prognostic.R"),
      "Blocks/25_shiny/templates/app_surv_prognostic.R",
      file.path(getwd(), "Blocks/25_shiny/templates/app_surv_prognostic.R"),
      "Blocks/25_shiny/templates/app_rsf_prognostic.R",
      file.path(getwd(), "Blocks/25_shiny/templates/app_rsf_prognostic.R")
    )
    ## RSF 且显式 rsf_prognostic 时仍可用旧模板；其余走通用
    if (identical(ml_tag, "rsf") && identical(ui_style, "rsf_prognostic")) {
      tmpl_cands <- c(
        file.path(root, "Blocks/25_shiny/templates/app_rsf_prognostic.R"),
        tmpl_cands
      )
    }
    tmpl <- tmpl_cands[file.exists(tmpl_cands)][1]
    if (nzchar(tmpl %||% "") && file.exists(tmpl)) {
      ok <- file.copy(tmpl, file.path(app_dir, "app.R"), overwrite = TRUE)
      if (isTRUE(ok)) {
        cli::cli_alert_success(
          "shiny_ml_app: 已写入 Survival Prognostic Tool 风格 app.R（model={ml_tag}）"
        )
        return(invisible(TRUE))
      }
    }
    cli::cli_alert_warning("shiny_ml_app: 未找到 surv/rsf prognostic 模板，回退 classic UI。")
  }

  sidebar_ui <- .sma_generate_sidebar_ui_lines(
    meta$cov_names, meta$defaults, meta$Index_vars
  )
  server_assign <- .sma_generate_server_assign_lines(meta$cov_names)
  df_assign <- .sma_generate_df_assign_lines(meta$cov_names)
  note_b <- meta$note_covariates_text
  disease <- meta$disease_lbl
  pred_col <- meta$pred_col
  risk_hi <- meta$risk_high
  risk_lo <- meta$risk_low
  ml_tag <- meta$ml_tag
  eval_bn <- meta$evalresult_basename
  predict_lines <- .sma_generate_predict_lines(ml_tag, pred_col, disease, risk_hi, risk_lo)

  lines <- c(
    "# Auto-generated by block_shiny_ml_app — deploy this folder to shinyapps.io",
    "# Files required in the same directory: shiny_staging.RData, df_train_RData.RData,",
    paste0("# model2factors.RData, ", eval_bn),
    "",
    paste0("Index <- ", .sma_r_literal(meta$Index_vars)),
    "",
    "library(tidymodels)",
    "library(tidyverse)",
    "library(tidyr)",
    "library(dplyr)",
    "",
    "library(xgboost)",
    "library(randomForest)",
    if (identical(ml_tag, "rsf")) "library(randomForestSRC)",
    if (identical(ml_tag, "coxboost")) "library(CoxBoost)",
    if (identical(ml_tag, "gbmsurv")) "library(gbm)",
    if (ml_tag %in% c("ridge_cox", "enet_cox")) "library(glmnet)",
    "library(sfd)",
    "library(dials)",
    "library(shiny)",
    "library(httr)",
    "library(jsonlite)",
    "library(lightgbm)",
    "library(bonsai)",
    "",
    "`%||%` <- function(x, y) if (is.null(x) || length(x) == 0L || (is.atomic(x) && length(x) == 1L && is.na(x))) y else x",
    "",
    "load(\"shiny_staging.RData\")",
    "load(\"df_train_RData.RData\")",
    paste0("load(", .sma_r_string(eval_bn), ")"),
    "",
    "## 兼容旧产物：曾误存为 staged",
    "if (!exists(\"shiny_staging\") && exists(\"staged\")) shiny_staging <- staged",
    "if (!exists(\"shiny_staging\")) stop(\"shiny_staging.RData 须包含 shiny_staging（或 staged）\")",
    "datarecipe <- shiny_staging$datarecipe",
    paste0("final_model <- final_", ml_tag),
    "if (!exists(\"df_train\")) stop(\"df_train_RData.RData 须包含 df_train\")",
    "if (!\"Group\" %in% names(df_train)) {",
    "  if (\"fustatus\" %in% names(df_train)) colnames(df_train)[colnames(df_train) == \"fustatus\"] <- \"Group\"",
    "}",
    "",
    "ui <- fluidPage(",
    "  tags$head(",
    "    tags$style(HTML(\"",
    "      .blue-text {",
    "        font-size: 1.5em;",
    "        color: #6699FF;",
    "        font-weight: bold;",
    "        margin: 10px 0;",
    "        white-space: pre-line;",
    "      }",
    "      .note p{",
    "        font-size: 0.9em;",
    "        margin-bottom: 5px;",
    "        line-height: 1.2;",
    "      }",
    "      .shiny-output-error { visibility: visible; color: #b00020; }",
    "    \"))",
    "  ),",
    paste0("  titlePanel(", .sma_r_string(paste0("Predicting ", disease)), "),"),
    "  sidebarLayout(",
    "    sidebarPanel(",
    sidebar_ui,
    "      actionButton(\"submitBtn\", \"Submit\", icon = icon(\"play\"), class = \"btn-primary\")",
    "    ),",
    "    mainPanel(",
    paste0("      h3(", .sma_r_string(paste0("Predicting ", disease, " outcomes:")), "),"),
    "      div(class = \"blue-text\", textOutput(\"result\")),",
    "      div(class = \"note\",",
    "        p(\"Note:\"),",
    paste0("        p(", .sma_r_string(paste0(
      "a. This website aims to develop and validate a model using machine learning algorithms to predict the risk of ",
      disease
    )), "),"),
    paste0("        p(", .sma_r_string(paste0(
      "b. By simply inputting the information: ", note_b,
      ", it is possible to predict the risk of ", disease
    )), "),"),
    "      )",
    "    )",
    "  )",
    ")",
    "",
    "options(shiny.maxRequestSize = 100*1024^2, shiny.timeout = 600)",
    "server <- function(input, output, session) {",
    "  observeEvent(input$submitBtn, {",
    "    tryCatch({",
    server_assign,
    "    df <- data.frame(",
    df_assign,
    "      stringsAsFactors = FALSE",
    "    )",
    predict_lines,
    paste0("    if (predicted_probability >= ", risk_hi, ") {"),
    "      risk_level <- \"high risk\"",
    paste0("    } else if (predicted_probability < ", risk_lo, ") {"),
    "      risk_level <- \"low risk\"",
    "    } else {",
    "      risk_level <- \"medium risk\"",
    "    }",
    "    output$result <- renderText({",
    paste0("      paste0(\"This patient is at \", risk_level, \" of ", disease, "! \\n\","),
    paste0("             \"The probability of ", disease, " is: \", predicted_probability, \"%\")"),
    "    })",
    "    }, error = function(e) {",
    "      output$result <- renderText({ paste0(\"Prediction error: \", conditionMessage(e)) })",
    "      showNotification(conditionMessage(e), type = \"error\", duration = 8)",
    "    })",
    "  })",
    "}",
    "",
    "shinyApp(ui = ui, server = server)",
    ""
  )
  writeLines(lines, file.path(app_dir, "app.R"), useBytes = TRUE)
}

block_shiny_ml_app <- function(ctx, ...) {
  cfg <- ctx$config
  sma_cfg <- .sma_merged_cfg(cfg)
  pred_cfg <- cfg$prediction %||% list()

  sh_legacy <- cfg$shiny %||% list()
  if (!isTRUE(sma_cfg$enable %||% sh_legacy$enable %||% pred_cfg$shiny_app_enable %||% FALSE)) {
    cli::cli_alert_info(
      "block_shiny_ml_app: 未启用（shiny_ml_app$enable / shiny$enable / prediction$shiny_app_enable），跳过。"
    )
    return(ctx)
  }

  if (!requireNamespace("recipes", quietly = TRUE)) {
    stop("block_shiny_ml_app: 需要 recipes 包。", call. = FALSE)
  }
  if (!requireNamespace("shiny", quietly = TRUE)) {
    stop("block_shiny_ml_app: 需要 shiny 包。", call. = FALSE)
  }

  Index_vars <- .sma_resolve_index_vars(cfg, sma_cfg)
  ml_tag <- .sma_resolve_ml_tag(ctx, sma_cfg)

  disease_lbl <- cfg$project$disease %||% cfg$project$analysis_group %||% "Outcome"
  disease_lbl <- as.character(disease_lbl)[1L]
  pred_col <- paste0(".pred_", make.names(disease_lbl))
  risk_high <- as.numeric(sma_cfg$risk_high_pct %||% 70)[1L]
  risk_low  <- as.numeric(sma_cfg$risk_low_pct %||% 30)[1L]
  app_subdir <- as.character(
    sma_cfg$app_subdir_ml %||% sma_cfg$app_subdir %||% "ShinyApp"
  )[1L]

  tv_dir <- .sma_resolve_tv_data_dir(ctx)
  ml_dir <- .sma_resolve_ml_models_dir(ctx, ml_tag)
  if (!nzchar(tv_dir)) {
    stop("block_shiny_ml_app: 未找到 train_validation/Data。", call. = FALSE)
  }
  if (!nzchar(ml_dir)) {
    stop("block_shiny_ml_app: 未找到 ml_models/Models。", call. = FALSE)
  }

  src_train <- file.path(tv_dir, "df_train_RData.RData")
  src_val   <- file.path(tv_dir, "df_validation_RData.RData")
  if (!file.exists(src_val)) {
    alt <- file.path(tv_dir, "df_val_RData.RData")
    if (file.exists(alt)) src_val <- alt
  }
  eval_src <- file.path(ml_dir, paste0("evalresult_", ml_tag, ".RData"))
  if (!file.exists(eval_src)) {
    stop("block_shiny_ml_app: 未找到 ", eval_src, call. = FALSE)
  }

  Model2Factors <- .sma_resolve_model2_factors(ctx)
  ## 优先用 ML 最终入选特征（与 RSF/xgb 训练列一致）；勿把 Model2/无关列塞进 Shiny
  ml_feats <- as.character(
    ctx$results$feature_selection_final %||%
      ctx$results$shap_ml_feature_names %||%
      character(0)
  )
  ml_feats <- unique(ml_feats[nzchar(ml_feats)])
  if (length(ml_feats)) {
    Final_Features <- ml_feats
  } else if (length(Model2Factors)) {
    Final_Features <- unique(c(Model2Factors, Index_vars))
  } else {
    stop("block_shiny_ml_app: 无 Model2Factors / feature_selection_final。", call. = FALSE)
  }
  Final_Features <- Final_Features[nzchar(Final_Features)]
  ## 若最优模型对象带 xvar.names（RSF），再收紧到训练列
  model_features <- Final_Features
  eval_probe <- file.path(
    .sma_resolve_ml_models_dir(ctx, ml_tag),
    paste0("evalresult_", ml_tag, ".RData")
  )
  if (nzchar(eval_probe) && file.exists(eval_probe)) {
    e_m <- new.env(parent = emptyenv())
    tryCatch(load(eval_probe, envir = e_m), error = function(e) NULL)
    fit_nm <- paste0("final_", ml_tag)
    if (exists(fit_nm, envir = e_m)) {
      fit0 <- get(fit_nm, envir = e_m)
      xv <- tryCatch(as.character(fit0$xvar.names), error = function(e) character(0))
      xv <- xv[nzchar(xv)]
      if (length(xv)) {
        model_features <- xv
        Final_Features <- xv
      }
    }
  }

  e_tr <- new.env(parent = emptyenv())
  load(src_train, envir = e_tr)
  if (!exists("df_train", envir = e_tr)) {
    stop("block_shiny_ml_app: ", src_train, " 中无 df_train。", call. = FALSE)
  }
  df_train <- e_tr$df_train
  df_train <- .sma_ensure_group_column(df_train, cfg)

  miss <- setdiff(Final_Features, names(df_train))
  if (length(miss)) {
    stop(
      "block_shiny_ml_app: 训练集缺少协变量: ", paste(miss, collapse = ", "),
      call. = FALSE
    )
  }

  pick <- .sma_pick_max_predicted_individual(eval_src, Final_Features)
  ref_row <- if (isTRUE(pick$ok)) pick$row else NULL
  if (!isTRUE(pick$ok)) {
    cli::cli_alert_warning("block_shiny_ml_app: {pick$msg}；侧栏默认值改用训练集中位数/众数。")
  }

  defaults <- stats::setNames(
    lapply(Final_Features, function(v) {
      .sma_default_for_covariate(v, ref_row, df_train)
    }),
    Final_Features
  )

  traindata <- df_train[, c("Group", Final_Features), drop = FALSE]
  scale_type <- .sma_recipe_type_for_ml_tag(ml_tag)
  datarecipe <- .sma_build_recipe(traindata, scale_type = scale_type)
  cli::cli_alert_success(
    "block_shiny_ml_app: recipe 已预计算（scale={scale_type}）。"
  )

  app_dir <- file.path(ctx$output_dir, app_subdir)
  data_dir <- file.path(ctx$output_dir, "Data")
  dir.create(app_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(data_dir, recursive = TRUE, showWarnings = FALSE)

  eval_bn <- paste0("evalresult_", ml_tag, ".RData")
  surv_horizon <- as.numeric(
    (cfg$performance_ml %||% list())$surv_horizon %||%
      (cfg$survival %||% list())$surv_horizon %||% 28
  )[1L]
  if (!is.finite(surv_horizon)) surv_horizon <- 28
  horizons <- unique(as.numeric(
    sma_cfg$horizons %||% c(
      max(1, round(surv_horizon / 4)),
      max(1, round(surv_horizon / 2)),
      max(1, round(3 * surv_horizon / 4)),
      surv_horizon
    )
  ))
  horizons <- sort(horizons[is.finite(horizons) & horizons > 0])

  cox_baseline <- NULL
  if (ml_tag %in% c("ridge_cox", "enet_cox")) {
    e_fit <- new.env(parent = emptyenv())
    tryCatch(load(eval_src, envir = e_fit), error = function(e) NULL)
    fit_obj <- if (exists(paste0("final_", ml_tag), envir = e_fit)) {
      get(paste0("final_", ml_tag), envir = e_fit)
    } else {
      NULL
    }
    time_col <- as.character(
      (cfg$survival %||% list())$time_var %||%
        (cfg$km_binary %||% list())$time_var %||% "survival_time_28d"
    )[1L]
    event_col <- as.character(
      (cfg$survival %||% list())$event_var %||%
        (cfg$km_binary %||% list())$event_var %||% "DN"
    )[1L]
    if (is.null(df_train[[event_col]]) && "survival_28d" %in% names(df_train)) {
      event_col <- "survival_28d"
    }
    if (is.null(df_train[[time_col]]) && "futime" %in% names(df_train)) {
      time_col <- "futime"
    }
    cox_baseline <- .sma_build_glmnet_cox_baseline(
      fit_obj, df_train, Final_Features, time_col, event_col
    )
    if (is.null(cox_baseline)) {
      cli::cli_alert_warning(
        "shiny_ml_app: 未能构建 glmnet Cox 基线生存；网页预测可能不可用。"
      )
    } else {
      cli::cli_alert_success("shiny_ml_app: 已写入 glmnet Cox 基线 S0(t)（Breslow）。")
    }
  }

  shiny_staging <- list(
    datarecipe = datarecipe,
    Index = Index_vars,
    Index_vars = Index_vars,
    disease_lbl = disease_lbl,
    Final_Features = Final_Features,
    model_features = model_features,
    cov_names = Final_Features,
    ml_tag = ml_tag,
    evalresult_basename = eval_bn,
    pred_col = pred_col,
    risk_high = risk_high,
    risk_low = risk_low,
    surv_horizon = surv_horizon,
    horizons = horizons,
    cox_baseline = cox_baseline,
    ref_summary = pick$summary %||% "",
    note_covariates_text = paste(Final_Features, collapse = ",")
  )
  ## 对象名必须与 app.R 中 load 后引用的 shiny_staging 一致（勿再存 staged）
  save(shiny_staging, file = file.path(app_dir, "shiny_staging.RData"))

  copies <- list(
    list(src = src_train, dst = file.path(app_dir, "df_train_RData.RData")),
    list(src = src_val,   dst = file.path(app_dir, "df_validation_RData.RData")),
    list(src = eval_src,  dst = file.path(app_dir, eval_bn))
  )
  if (nzchar(src_val) && file.exists(src_val)) {
    copies[[2]]$dst <- file.path(app_dir, "df_validation_RData.RData")
  } else {
    copies <- copies[c(1L, 3L)]
  }

  copied <- character(0)
  for (cp in copies) {
    if (.sma_copy_if_exists(cp$src, cp$dst)) {
      copied <- c(copied, basename(cp$dst))
      .sma_copy_if_exists(cp$src, file.path(data_dir, basename(cp$dst)))
    }
  }

  save(Model2Factors, file = file.path(app_dir, "model2factors.RData"))
  save(Model2Factors, file = file.path(data_dir, "model2factors.RData"))

  note_cov <- paste(Final_Features, collapse = ",")
  meta <- list(
    Index_vars = Index_vars,
    disease_lbl = disease_lbl,
    cov_names = Final_Features,
    defaults = defaults,
    pred_col = pred_col,
    risk_high = risk_high,
    risk_low = risk_low,
    ml_tag = ml_tag,
    evalresult_basename = eval_bn,
    note_covariates_text = note_cov,
    study_type = tolower(trimws(as.character(cfg$project$study_type %||% "")[1L])),
    assoc_model = tolower(trimws(as.character(
      (cfg$ml_batch %||% list())$assoc_model %||% ""
    )[1L])),
    ui_style = as.character(
      sma_cfg$ui_style %||%
        if (tolower(trimws(as.character((cfg$ml_batch %||% list())$assoc_model %||% "")[1L])) == "cox" ||
            tolower(trimws(as.character(cfg$project$study_type %||% "")[1L])) == "prognosis") {
          "surv_prognostic"
        } else {
          ""
        }
    )[1L]
  )

  if (isTRUE(sma_cfg$export_app %||% TRUE)) {
    .sma_write_app_r(app_dir, meta)
    writeLines(
      c(
        "ML Risk Prediction App (block_shiny_ml_app)",
        "",
        "Deploy to shinyapps.io:",
        "1. Upload entire ShinyApp/ folder (app.R + all .RData files).",
        "2. Or: setwd to this folder; source('app.R') or shiny::runApp()",
        "",
        paste0("Model tag: ", ml_tag),
        paste0("Index: ", paste(Index_vars, collapse = ", ")),
        paste0("Features: ", note_cov),
        "",
        if (nzchar(pick$summary %||% "")) pick$summary else ""
      ),
      file.path(app_dir, "README.txt"),
      useBytes = TRUE
    )
    cli::cli_alert_success("block_shiny_ml_app: 已写出 {.file {app_dir}/app.R}")
  }

  if (isTRUE(sma_cfg$run_interactive %||% FALSE)) {
    old_wd <- getwd()
    on.exit(setwd(old_wd), add = TRUE)
    setwd(app_dir)
    cli::cli_alert_info("block_shiny_ml_app: 启动 Shiny（关闭后流水线继续）...")
    shiny::runApp(app_dir)
  }

  ctx$results$shiny_app_dir <- app_dir
  ctx$results$shiny_app_mode <- "ml_predict_c01"
  ctx$results$shiny_ml_model_tag <- ml_tag
  ctx$results$shiny_index_var <- Index_vars
  ctx$results$shiny_staged_files <- copied
  ctx$results$shiny_final_features <- Final_Features

  cli::cli_alert_success(
    "block_shiny_ml_app: 完成（模型={ml_tag}；已复制: {paste(copied, collapse=', ')})"
  )
  ctx
}

register_block(
  "shiny_ml_app",
  block_shiny_ml_app,
  "Shiny ML 预测 App（C01 / ShinyApp）"
)
