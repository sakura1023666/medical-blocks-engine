###############################################################################
#  feature_selection_lasso_cox — 预后专用 LASSO-Cox 特征选择 + A/B/C 拼图
#
#  用途：预后预测套路唯一特征选择方法。候选池须来自「单因素 → VIF」
#        （Model2Factors / vif_screen_pass），不再跑 Boruta/RF 等多模型共识。
#
#  产出图（拼成一张）：
#    A  LASSO 系数路径（Coefficients vs -Log(λ)）
#    B  交叉验证偏似然偏差（Partial Likelihood Deviance）
#    C  入选特征 Pearson 相关热图
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$train（优先）/ imputed；须含 survival$time_var / event_var
#  require_ctx_results = Model2Factors 或 vif_screen_pass（UV→VIF 后）
#  require_packages = glmnet, survival；拼图建议 cowplot；热图建议 corrplot
#
#  feature_selection_lasso_cox = list(
#    enable            = TRUE,
#    seed              = NULL,          # NULL → splitting$seed → 1234
#    cv_folds          = 10L,
#    lambda_choice     = "lambda.min",  # 或 "lambda.1se"
#    lambda_adjust_to_n = TRUE,         # 入选 < min 时沿 λ 路径放宽（勿事后塞 Age/UV）
#    force_include     = NULL,          # 强制保留（如暴露指标），即使 λ 下系数为 0
#    pause_enable      = FALSE,
#    fig_combined_name = "Figure S2.LASSO-Cox.pdf",
#    fig_s1_name       = "Figure S1.LASSO-Cox.pdf"
#  ),
#
#  register_block: "feature_selection_lasso_cox"
#  典型流水线: univariate_prognosis → ml_vif_train_test → 本块
#              →（bundle）→ ml_assoc_covariate_resolve
###############################################################################

.fslcox10_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.fslcox10_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "feature_selection_lasso_cox",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: feature_selection_lasso_cox — ", reason,
    " | See ctx$results$pause_point.",
    call. = FALSE
  )
}

.fslcox10_resolve_candidates <- function(ctx, bl_cfg = list()) {
  src <- tolower(trimws(as.character(bl_cfg$candidate_source %||% "vif")[1L]))
  vif <- unique(as.character(ctx$results$vif_screen_pass %||% character(0)))
  vif <- vif[nzchar(vif)]
  m2 <- unique(as.character(ctx$results$Model2Factors %||% character(0)))
  m2 <- m2[nzchar(m2)]
  uv <- unique(as.character(
    ctx$results$univar_features %||% ctx$results$tb_screen %||% character(0)
  ))
  uv <- uv[nzchar(uv)]
  if (identical(src, "model2")) return(if (length(m2)) m2 else vif)
  if (identical(src, "univariate")) return(uv)
  if (identical(src, "all_predictors")) {
    data <- ctx$data$train %||% ctx$data$imputed %||% ctx$data$cleaned
    if (is.data.frame(data)) {
      cfg <- ctx$config
      never <- unique(c(
        cfg$survival$time_var %||% character(0),
        cfg$survival$event_var %||% character(0),
        cfg$data$outcome_column %||% character(0),
        cfg$data$id_column %||% character(0),
        "Group", "ID", "SEQN", "subject_id", "Pt_ID"
      ))
      return(setdiff(names(data), never[nzchar(never)]))
    }
  }
  ## vif / auto：优先 VIF 通过池（单因素→VIF 铁律）
  if (length(vif)) return(vif)
  if (length(m2)) return(m2)
  uv
}

.fslcox10_terms_from_coef <- function(b_mat, mm_cols, assign_vec, term_labels, feats_all) {
  if (is.null(b_mat) || !is.matrix(b_mat) || !nrow(b_mat)) return(character(0))
  rn <- rownames(b_mat)
  if (is.null(rn) || !length(rn)) return(character(0))
  nz <- rn[abs(b_mat[, 1L]) > 1e-10]
  nz <- setdiff(nz, "(Intercept)")
  if (!length(nz)) return(character(0))
  w <- which(mm_cols %in% nz)
  if (!length(w)) return(character(0))
  intersect(term_labels[unique(assign_vec[w])], feats_all)
}

## 在给定 λ 下解析原变量入选集（含 force_include）
.fslcox10_selected_at_s <- function(cvfit, s, mm, assign_vec, term_labels, cand, force_inc) {
  b <- tryCatch(as.matrix(coef(cvfit, s = s)), error = function(e) NULL)
  if (is.null(b)) return(character(0))
  sel <- .fslcox10_terms_from_coef(b, colnames(mm), assign_vec, term_labels, cand)
  unique(c(intersect(force_inc, cand), sel))
}

## 入选 < fn_min：沿 CV 路径向更小 λ（惩罚更松）走。
## 在 [fn_min, fn_max] 内优先「更少特征、更大 λ」（小样本更稳、更可解释）。
.fslcox10_adjust_lambda_for_n <- function(cvfit, s0, mm, assign_vec, term_labels,
                                         cand, force_inc, fn_min, fn_max) {
  lam_path <- as.numeric(cvfit$lambda)
  if (!length(lam_path)) {
    return(list(selected = character(0), lambda = s0, adjusted = FALSE))
  }
  i0 <- which.min(abs(lam_path - as.numeric(s0)[1L]))
  if (!length(i0) || !is.finite(i0)) i0 <- 1L

  base_sel <- .fslcox10_selected_at_s(
    cvfit, s0, mm, assign_vec, term_labels, cand, force_inc
  )
  best <- list(selected = base_sel, lambda = as.numeric(s0)[1L], adjusted = FALSE)
  if (length(best$selected) >= fn_min &&
      (!is.finite(fn_max) || length(best$selected) <= fn_max)) {
    return(best)
  }

  cands <- list()
  for (i in seq.int(i0, length(lam_path))) {
    s_i <- lam_path[[i]]
    sel_i <- .fslcox10_selected_at_s(
      cvfit, s_i, mm, assign_vec, term_labels, cand, force_inc
    )
    n_i <- length(sel_i)
    if (n_i < fn_min) next
    if (is.finite(fn_max) && n_i > fn_max) {
      ## 超过上限：仍记下，后续按 |coef| 截断
      cands[[length(cands) + 1L]] <- list(
        selected = sel_i, lambda = s_i, n = n_i, over_max = TRUE
      )
      next
    }
    cands[[length(cands) + 1L]] <- list(
      selected = sel_i, lambda = s_i, n = n_i, over_max = FALSE
    )
  }
  if (!length(cands)) {
    s_lo <- lam_path[[length(lam_path)]]
    sel_lo <- .fslcox10_selected_at_s(
      cvfit, s_lo, mm, assign_vec, term_labels, cand, force_inc
    )
    return(list(
      selected = sel_lo, lambda = s_lo, adjusted = TRUE,
      still_short = length(sel_lo) < fn_min
    ))
  }
  ## 优先：未超 max → 更少 n → 更大 λ（更靠近 CV 最优）
  ok <- vapply(cands, function(z) !isTRUE(z$over_max), logical(1L))
  pool <- if (any(ok)) cands[ok] else cands
  ns <- vapply(pool, function(z) as.integer(z$n), integer(1L))
  lams <- vapply(pool, function(z) as.numeric(z$lambda), numeric(1L))
  ord <- order(ns, -lams)
  hit <- pool[[ord[[1L]]]]
  list(
    selected = hit$selected,
    lambda = hit$lambda,
    adjusted = TRUE,
    over_max = isTRUE(hit$over_max)
  )
}

.fslcox10_draw_combined <- function(cvfit, selected, data_train, out_path,
                                    label_a = "A", label_b = "B", label_c = "C") {
  if (!length(selected)) {
    grDevices::pdf(out_path, width = 12, height = 4.2)
    graphics::plot.new()
    graphics::title("LASSO-Cox: no selected features")
    grDevices::dev.off()
    return(invisible(FALSE))
  }
  sel <- intersect(selected, names(data_train))
  if (!length(sel)) sel <- selected

  ## 临时单页 PDF → 再拼；base 图用 tempfile
  tmp_a <- tempfile(fileext = ".pdf")
  tmp_b <- tempfile(fileext = ".pdf")
  tmp_c <- tempfile(fileext = ".pdf")
  on.exit({
    unlink(c(tmp_a, tmp_b, tmp_c), force = TRUE)
  }, add = TRUE)

  ## 优先直接画横排 A|B|C（避免 magick/pdf_combine 变成多页方图、轴标题重叠）
  .fslcox10_draw_panel_c <- function() {
    ok_c <- FALSE
    ## ≥2 入选：相关热图；仅 1 个入选：改画 |coef| 条形（避免 C 面板空白）
    if (length(sel) >= 2L) {
      num_df <- tryCatch({
        as.data.frame(lapply(data_train[, sel, drop = FALSE], function(x) {
          if (is.numeric(x)) return(as.numeric(x))
          if (is.factor(x)) return(as.numeric(x))
          suppressWarnings(as.numeric(as.character(x)))
        }), stringsAsFactors = FALSE)
      }, error = function(e) NULL)
      if (!is.null(num_df) && ncol(num_df) >= 2L) {
        keep <- vapply(num_df, function(x) sum(is.finite(x)) >= 3L, logical(1L))
        num_df <- num_df[, keep, drop = FALSE]
        if (ncol(num_df) >= 2L) {
          cn <- names(num_df)
          short <- cn
          short <- gsub("Aggravation_Duration", "AggravDur", short, fixed = TRUE)
          short <- gsub("Has_Adenomyosis", "Adenomyosis", short, fixed = TRUE)
          short <- gsub("Adh_rAFS", "Adh×rAFS", short, fixed = TRUE)
          short <- gsub("Age_AMH", "Age×AMH", short, fixed = TRUE)
          names(num_df) <- short
          cm <- tryCatch(
            stats::cor(num_df, use = "pairwise.complete.obs", method = "pearson"),
            error = function(e) NULL
          )
          if (!is.null(cm) && is.matrix(cm) && requireNamespace("corrplot", quietly = TRUE)) {
            ok_c <- isTRUE(tryCatch({
              corrplot::corrplot(
                cm, method = "color", type = "lower",
                addCoef.col = "black", number.cex = 0.55,
                tl.col = "black", tl.srt = 45, tl.cex = 0.65,
                cl.cex = 0.65, diag = TRUE, is.corr = TRUE,
                mar = c(0, 0, 1, 0)
              )
              TRUE
            }, error = function(e) FALSE))
          }
        }
      }
    }
    if (!ok_c) {
      ## 兜底：λ 处 |coef| 最大的若干设计列（含入选与接近入选者）
      b_abs <- tryCatch({
        bm <- as.matrix(stats::coef(cvfit, s = s_use))
        if (is.null(bm) || !nrow(bm)) {
          bm <- as.matrix(cvfit$glmnet.fit$beta[, which.min(abs(cvfit$lambda - cvfit$lambda.min)), drop = FALSE])
        }
        v <- abs(as.numeric(bm[, 1L]))
        names(v) <- rownames(bm)
        sort(v[is.finite(v) & v > 0], decreasing = TRUE)
      }, error = function(e) numeric(0))
      if (!length(b_abs)) {
        ## 再兜底：入选变量在训练集的 |z| 条形
        b_abs <- tryCatch({
          one <- sel[[1L]]
          x <- data_train[[one]]
          if (is.null(x)) return(numeric(0))
          if (!is.numeric(x)) x <- suppressWarnings(as.numeric(as.factor(x)))
          stats::setNames(abs(stats::cor(x, seq_along(x), use = "complete.obs")), one)
        }, error = function(e) numeric(0))
      }
      if (length(b_abs)) {
        topn <- head(b_abs, n = min(12L, length(b_abs)))
        ok_c <- isTRUE(tryCatch({
          graphics::par(mar = c(5.5, 8.5, 2.8, 1.2))
          graphics::barplot(
            rev(topn),
            horiz = TRUE,
            las = 1,
            col = "#4C78A8",
            border = NA,
            xlab = "|coefficient| at selected λ",
            main = ""
          )
          TRUE
        }, error = function(e) FALSE))
      }
    }
    if (!ok_c) {
      graphics::plot.new()
      graphics::title("C: coefficient panel unavailable")
    }
    invisible(ok_c)
  }

  stacked <- isTRUE(tryCatch({
    grDevices::pdf(out_path, width = 13.5, height = 4.5)
    graphics::layout(matrix(1:3, nrow = 1L, ncol = 3L))
    graphics::par(mar = c(4.5, 4.2, 2.8, 1.0), mgp = c(2.2, 0.7, 0))
    ## A：系数路径；xvar=lambda 自带 xlab，勿再 mtext 造成重叠
    tryCatch({
      plot(cvfit$glmnet.fit, xvar = "lambda", label = FALSE)
    }, error = function(e) graphics::plot.new())
    graphics::mtext(label_a, side = 3, line = 0.6, adj = 0, font = 2, cex = 1.15)
    ## B：CV 曲线
    graphics::par(mar = c(4.5, 4.2, 2.8, 1.0), mgp = c(2.2, 0.7, 0))
    tryCatch({
      plot(cvfit)
    }, error = function(e) graphics::plot.new())
    graphics::mtext(label_b, side = 3, line = 0.6, adj = 0, font = 2, cex = 1.15)
    ## C：相关热图
    graphics::par(mar = c(5.5, 5.0, 2.8, 2.5))
    .fslcox10_draw_panel_c()
    graphics::mtext(label_c, side = 3, line = 0.6, adj = 0, font = 2, cex = 1.15)
    grDevices::dev.off()
    file.exists(out_path) && isTRUE(file.info(out_path)$size > 1000L)
  }, error = function(e) FALSE))

  if (!stacked) {
    grDevices::pdf(tmp_a, width = 4.5, height = 4.5)
    graphics::par(mar = c(4.5, 4.2, 2.2, 1.2))
    tryCatch(plot(cvfit$glmnet.fit, xvar = "lambda", label = FALSE),
             error = function(e) graphics::plot.new())
    grDevices::dev.off()
    grDevices::pdf(tmp_b, width = 4.5, height = 4.5)
    graphics::par(mar = c(4.5, 4.2, 2.2, 1.2))
    tryCatch(plot(cvfit), error = function(e) graphics::plot.new())
    grDevices::dev.off()
    grDevices::pdf(tmp_c, width = 4.5, height = 4.5)
    graphics::par(mar = c(5.5, 5.0, 2.2, 2.5))
    .fslcox10_draw_panel_c()
    grDevices::dev.off()
    if (requireNamespace("magick", quietly = TRUE) && requireNamespace("pdftools", quietly = TRUE)) {
      stacked <- isTRUE(tryCatch({
        imgs <- lapply(c(tmp_a, tmp_b, tmp_c), function(p) magick::image_read_pdf(p, density = 200))
        row <- magick::image_append(do.call(c, imgs), stack = FALSE)
        w <- magick::image_info(row)$width
        panel_w <- w / 3
        labeled <- magick::image_annotate(row, label_a, size = 28, weight = 700,
                                          gravity = "northwest", location = "+10+5", color = "black")
        labeled <- magick::image_annotate(labeled, label_b, size = 28, weight = 700,
                                          gravity = "northwest",
                                          location = paste0("+", as.integer(panel_w) + 10, "+5"), color = "black")
        labeled <- magick::image_annotate(labeled, label_c, size = 28, weight = 700,
                                          gravity = "northwest",
                                          location = paste0("+", as.integer(2 * panel_w) + 10, "+5"), color = "black")
        magick::image_write(labeled, path = out_path, format = "pdf")
        file.exists(out_path) && file.info(out_path)$size > 1000L
      }, error = function(e) FALSE))
    }
  }
  invisible(TRUE)
}

block_feature_selection_lasso_cox <- function(ctx, ...) {
  cfg <- ctx$config %||% list()
  bl_cfg <- modifyList(
    cfg$feature_selection %||% list(),
    cfg$feature_selection_lasso_cox %||% list()
  )
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("feature_selection_lasso_cox$enable=FALSE，跳过。")
    return(ctx)
  }

  study_type <- tolower(trimws(as.character(cfg$project$study_type %||% "")[1L]))
  assoc_cox <- identical(
    tolower(trimws(as.character(
      (cfg$ml_batch %||% list())$assoc_model %||%
        (cfg$incidence_batch %||% list())$assoc_model %||% ""
    )[1L])),
    "cox"
  )
  has_surv <- nzchar(as.character(cfg$survival$time_var %||% "")[1L]) &&
    nzchar(as.character(cfg$survival$event_var %||% "")[1L])
  ## 允许：正式 prognosis，或 incidence 流水线 + Cox 关联（单指标预后 ML）
  if (!identical(study_type, "prognosis") && !(isTRUE(assoc_cox) && isTRUE(has_surv))) {
    cli::cli_alert_warning(
      "feature_selection_lasso_cox: study_type={study_type}，本块仅服务预后；跳过。"
    )
    return(ctx)
  }

  if (!requireNamespace("glmnet", quietly = TRUE) || !requireNamespace("survival", quietly = TRUE)) {
    stop("feature_selection_lasso_cox: 需要 glmnet 与 survival。", call. = FALSE)
  }

  tv <- as.character(cfg$survival$time_var %||% "")[1L]
  ev <- as.character(cfg$survival$event_var %||% "")[1L]
  if (!nzchar(tv) || !nzchar(ev)) {
    stop("feature_selection_lasso_cox: 缺少 survival$time_var / event_var。", call. = FALSE)
  }

  data <- ctx$data$train %||% ctx$data$imputed %||% ctx$data$cleaned
  if (!is.data.frame(data) || !nrow(data)) {
    stop("feature_selection_lasso_cox: 无训练数据。", call. = FALSE)
  }
  if (!all(c(tv, ev) %in% names(data))) {
    stop(
      "feature_selection_lasso_cox: 数据缺少 ", tv, " / ", ev, "。",
      call. = FALSE
    )
  }

  seed <- as.integer(bl_cfg$seed %||% cfg$splitting$seed %||% cfg$imputation$seed %||% 1234L)[1L]
  set.seed(seed)
  nfolds <- as.integer(bl_cfg$cv_folds %||% 10L)[1L]
  if (is.na(nfolds) || nfolds < 3L) nfolds <- 10L
  lam_choice <- tolower(trimws(as.character(bl_cfg$lambda_choice %||% "lambda.min")[1L]))
  if (!lam_choice %in% c("lambda.min", "lambda.1se")) lam_choice <- "lambda.min"

  never_pred <- if (exists("pipeline_never_predictor_names", mode = "function")) {
    pipeline_never_predictor_names(cfg)
  } else {
    character(0)
  }
  never_pred <- unique(c(
    never_pred,
    tv, ev,
    as.character(cfg$data$outcome_column %||% character(0)),
    as.character(cfg$data$id_column %||% character(0)),
    "Group", "ID", "SEQN", "subject_id"
  ))
  never_pred <- never_pred[nzchar(never_pred)]

  cand <- .fslcox10_resolve_candidates(ctx, bl_cfg)
  cand <- setdiff(intersect(cand, names(data)), never_pred)
  ## 暴露强制进候选
  exposure <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    exposure <- as.character(pipeline_index_exposure_var(cfg) %||% character(0))
  }
  force_inc <- unique(c(
    exposure,
    as.character(bl_cfg$force_include %||% character(0))
  ))
  force_inc <- intersect(force_inc[nzchar(force_inc)], names(data))
  cand <- unique(c(force_inc, cand))
  cand <- setdiff(intersect(cand, names(data)), never_pred)

  fn_min <- as.integer(
    bl_cfg$target_n_features_min %||%
      (cfg$feature_selection %||% list())$target_n_features_min %||% 3L
  )[1L]
  if (is.na(fn_min) || fn_min < 1L) fn_min <- 3L
  fn_max <- as.integer(
    bl_cfg$target_n_features_max %||%
      (cfg$feature_selection %||% list())$target_n_features_max %||% Inf
  )[1L]
  if (is.na(fn_max) || fn_max < 1L) fn_max <- Inf

  if (length(cand) < fn_min) {
    reason <- paste0("UV→VIF 候选仅 ", length(cand), " 个，低于下限 ", fn_min)
    if (.fslcox10_should_pause(bl_cfg, "pause_on_insufficient_candidates", TRUE)) {
      .fslcox10_pause(ctx, reason, "检查 univariate_prognosis / VIF 或放宽筛选阈值", data[, head(cand, 5L), drop = FALSE])
    }
    stop("feature_selection_lasso_cox: ", reason, call. = FALSE)
  }

  ok <- stats::complete.cases(data[, c(tv, ev, cand), drop = FALSE])
  d <- data[ok, , drop = FALSE]
  if (nrow(d) < 30L) {
    stop("feature_selection_lasso_cox: 完整病例 < 30。", call. = FALSE)
  }

  ## 因子/字符 → 模型矩阵；数值保持
  fml <- stats::as.formula(paste("~", paste(sprintf("`%s`", cand), collapse = " + "), "- 1"))
  mm <- stats::model.matrix(fml, data = d)
  assign_vec <- attr(mm, "assign")
  term_labels <- cand
  y_surv <- survival::Surv(as.numeric(d[[tv]]), as.integer(d[[ev]] != 0))
  if (anyNA(y_surv)) {
    stop("feature_selection_lasso_cox: Surv 含 NA。", call. = FALSE)
  }

  nfolds_use <- min(nfolds, max(3L, nrow(mm) %/% 5L))
  cli::cli_h2(
    "LASSO-Cox: 候选 {length(cand)} → cv.glmnet(family=cox, folds={nfolds_use}, λ={lam_choice})"
  )
  cvfit <- glmnet::cv.glmnet(
    mm, y_surv,
    family = "cox",
    alpha = 1,
    nfolds = nfolds_use,
    type.measure = "deviance"
  )
  s_use <- if (identical(lam_choice, "lambda.1se")) cvfit$lambda.1se else cvfit$lambda.min
  s_cv <- as.numeric(s_use)[1L]
  b <- as.matrix(coef(cvfit, s = s_use))
  use_all <- isTRUE(bl_cfg$use_all_candidates %||% FALSE)
  lambda_adjusted <- FALSE
  selected <- if (use_all) {
    cli::cli_alert_info(
      "LASSO-Cox: use_all_candidates=TRUE，ML 采用 UV/VIF 全候选 {length(cand)} 个（仍出 LASSO 路径图）。"
    )
    cand
  } else {
    .fslcox10_terms_from_coef(b, colnames(mm), assign_vec, term_labels, cand)
  }
  ## 强制纳入
  selected <- unique(c(intersect(force_inc, cand), selected))

  if (!length(selected)) {
    ## 兜底：取 |coef| 最大的 fn_min 个原变量
    b_abs <- abs(as.numeric(b[, 1L]))
    names(b_abs) <- rownames(b)
    b_abs <- b_abs[setdiff(names(b_abs), "(Intercept)")]
    b_abs <- sort(b_abs, decreasing = TRUE)
    top_cols <- names(b_abs)[seq_len(min(length(b_abs), max(fn_min * 3L, fn_min)))]
    w <- which(colnames(mm) %in% top_cols)
    selected <- unique(c(force_inc, intersect(term_labels[unique(assign_vec[w])], cand)))
    cli::cli_alert_warning(
      "LASSO-Cox: λ={lam_choice} 无非零系数，已按 |coef| 兜底入选 {length(selected)} 个。"
    )
  }

  ## 入选 < min：沿 λ 路径放宽（与发病 LASSO 一致），禁止靠事后塞 Age/UV 凑数
  do_lam_adj <- !isFALSE(bl_cfg$lambda_adjust_to_n %||% TRUE) && !use_all
  if (do_lam_adj && length(selected) < fn_min) {
    n_before <- length(selected)
    adj <- .fslcox10_adjust_lambda_for_n(
      cvfit, s_use, mm, assign_vec, term_labels, cand, force_inc, fn_min, fn_max
    )
    if (length(adj$selected) > length(selected) || isTRUE(adj$adjusted)) {
      selected <- adj$selected
      s_use <- adj$lambda
      b <- as.matrix(coef(cvfit, s = s_use))
      lambda_adjusted <- isTRUE(adj$adjusted)
      if (isTRUE(adj$still_short)) {
        cli::cli_alert_warning(
          "LASSO-Cox: 已放宽至路径最松 λ={round(as.numeric(s_use), 5)}，仍仅 {length(selected)} < {fn_min}。"
        )
      } else {
        cli::cli_alert_warning(
          "LASSO-Cox: {lam_choice} 仅 {n_before} 个；已沿路径放宽 λ→{round(as.numeric(s_use), 5)}，入选 {length(selected)} 个（目标 ≥{fn_min}）。"
        )
      }
    }
  }

  ## 小样本硬上限：超过 target_n_features_max 时按 |coef| 截断（强制纳入优先保留）
  if (is.finite(fn_max) && length(selected) > fn_max) {
    b_abs <- abs(as.numeric(b[, 1L]))
    names(b_abs) <- rownames(b)
    b_abs <- b_abs[setdiff(names(b_abs), "(Intercept)")]
    ## 原变量级 |coef|：取该变量对应设计列绝对值之和
    var_score <- setNames(numeric(length(cand)), cand)
    for (j in seq_along(cand)) {
      cols_j <- colnames(mm)[assign_vec == j]
      var_score[cand[j]] <- sum(b_abs[intersect(names(b_abs), cols_j)], na.rm = TRUE)
    }
    keep_force <- intersect(force_inc, selected)
    rest <- setdiff(selected, keep_force)
    rest <- rest[order(var_score[rest], decreasing = TRUE)]
    n_rest <- max(0L, as.integer(fn_max) - length(keep_force))
    selected <- unique(c(keep_force, head(rest, n_rest)))
    cli::cli_alert_warning(
      "LASSO-Cox: 入选超过上限 {fn_max}，已按 |coef| 截断至 {length(selected)} 个。"
    )
  }

  cli::cli_alert_success(
    "LASSO-Cox 入选 {length(selected)} 个: {paste(selected, collapse = ', ')}"
  )

  if (is.null(ctx$results$feature_selection_by_model)) {
    ctx$results$feature_selection_by_model <- list()
  }
  ctx$results$feature_selection_by_model$lasso_cox <- selected
  ctx$results$feature_selection_by_model$lasso <- selected
  ctx$results$feature_selection_final <- selected
  ctx$results$feature_selection_venn_center <- selected
  ctx$results$ml_feature_names <- selected
  ctx$results$feature_selection_lasso_only <- TRUE
  ctx$results$feature_selection_methods_selected <- "lasso_cox"
  ctx$results$feature_selection_lasso_cox_meta <- list(
    lambda_choice = lam_choice,
    lambda = as.numeric(s_use)[1L],
    lambda_cv = s_cv,
    lambda_adjusted = lambda_adjusted,
    lambda_min = as.numeric(cvfit$lambda.min)[1L],
    lambda_1se = as.numeric(cvfit$lambda.1se)[1L],
    n_candidates = length(cand),
    n_selected = length(selected),
    n_complete = nrow(d),
    cv_folds = nfolds_use,
    selected = selected,
    candidates = cand
  )
  ctx <- save_result(
    ctx, "feature_selection_lasso_cox", selected,
    "feature_selection_lasso_cox.RData"
  )

  fig_name <- as.character(
    bl_cfg$fig_combined_name %||% "Figure S2.LASSO-Cox.pdf"
  )[1L]
  s1_name <- as.character(
    bl_cfg$fig_s1_name %||% "Figure S1.LASSO-Cox.pdf"
  )[1L]

  ctx <- save_figure(ctx, fig_name, function() {
    ## save_figure 会开 PDF 设备；这里改写为直接画到当前设备的三栏
    graphics::layout(matrix(1:3, nrow = 1L))
    graphics::par(mar = c(4.5, 4.2, 2.8, 1.2))
    tryCatch({
      plot(cvfit$glmnet.fit, xvar = "lambda", label = FALSE)
    }, error = function(e) graphics::plot.new())
    graphics::mtext("A", side = 3, line = 0.6, adj = 0, font = 2, cex = 1.2)
    tryCatch({
      plot(cvfit)
    }, error = function(e) graphics::plot.new())
    graphics::mtext("B", side = 3, line = 0.6, adj = 0, font = 2, cex = 1.2)

    ## C 热图
    graphics::par(mar = c(6, 6, 2.8, 3.5))
    sel_plot <- intersect(selected, names(d))
    drew <- FALSE
    if (length(sel_plot) >= 2L) {
      num_df <- as.data.frame(lapply(d[, sel_plot, drop = FALSE], function(x) {
        if (is.numeric(x)) as.numeric(x) else if (is.factor(x)) as.numeric(x) else suppressWarnings(as.numeric(as.character(x)))
      }), stringsAsFactors = FALSE)
      keep <- vapply(num_df, function(x) sum(is.finite(x)) >= 3L, logical(1L))
      num_df <- num_df[, keep, drop = FALSE]
      if (ncol(num_df) >= 2L) {
        cm <- tryCatch(
          stats::cor(num_df, use = "pairwise.complete.obs"),
          error = function(e) NULL
        )
        if (!is.null(cm)) {
          if (requireNamespace("corrplot", quietly = TRUE)) {
            tryCatch({
              corrplot::corrplot(
                cm, method = "color", type = "lower",
                addCoef.col = "black", number.cex = 0.65,
                tl.col = "black", tl.srt = 45, tl.cex = 0.75,
                cl.cex = 0.65, diag = TRUE
              )
              drew <- TRUE
            }, error = function(e) NULL)
          }
          if (!drew) {
            n <- nrow(cm)
            graphics::plot.new()
            graphics::plot.window(xlim = c(0.5, n + 0.5), ylim = c(0.5, n + 0.5), asp = 1)
            cols <- grDevices::colorRampPalette(c("#B2182B", "white", "#2166AC"))(101)
            for (i in seq_len(n)) for (j in seq_len(i)) {
              v <- cm[i, j]
              if (!is.finite(v)) next
              ci <- max(1L, min(101L, as.integer(round((v + 1) / 2 * 100)) + 1L))
              graphics::rect(j - 0.5, n - i + 0.5, j + 0.5, n - i + 1.5, col = cols[ci], border = "grey80")
              graphics::text(j, n - i + 1, sprintf("%.2f", v), cex = 0.6)
            }
            graphics::axis(1, at = seq_len(n), labels = colnames(cm), las = 2, cex.axis = 0.65)
            graphics::axis(2, at = seq_len(n), labels = rev(colnames(cm)), las = 1, cex.axis = 0.65)
            drew <- TRUE
          }
        }
      }
    }
    if (!drew) graphics::plot.new()
    graphics::mtext("C", side = 3, line = 0.6, adj = 0, font = 2, cex = 1.2)
  }, width = 12, height = 4.2)

  ## 同步一份 S1（单方法特征选择主图）
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  src_fig <- file.path(fig_dir, fig_name)
  if (file.exists(src_fig)) {
    dest_s1 <- file.path(fig_dir, s1_name)
    tryCatch(file.copy(src_fig, dest_s1, overwrite = TRUE), error = function(e) NULL)
  }

  ## 也写一份高清拼图（magick），覆盖同名更清晰
  if (dir.exists(fig_dir)) {
    hi <- file.path(fig_dir, fig_name)
    tryCatch(
      .fslcox10_draw_combined(cvfit, selected, d, hi),
      error = function(e) {
        cli::cli_alert_warning("LASSO-Cox 高清拼图失败: {conditionMessage(e)}")
      }
    )
    if (file.exists(hi)) {
      tryCatch(
        file.copy(hi, file.path(fig_dir, s1_name), overwrite = TRUE),
        error = function(e) NULL
      )
    }
  }

  ctx$results$feature_selection_venn_input <- list(
    by_model = list(lasso_cox = selected),
    by_model_all = list(lasso_cox = selected),
    final = selected,
    selected_methods = "lasso_cox",
    U = selected,
    method_names = "lasso_cox",
    overlap_methods = "lasso_cox",
    list_in = list(lasso_cox = selected),
    list_in_full = list(lasso_cox = selected)
  )

  cli::cli_alert_success("feature_selection_lasso_cox 完成（图 {fig_name} / {s1_name}）。")
  ctx
}

register_block(
  "feature_selection_lasso_cox",
  block_feature_selection_lasso_cox,
  "预后 LASSO-Cox 特征选择 + A/B/C 拼图（路径/CV/相关）"
)
