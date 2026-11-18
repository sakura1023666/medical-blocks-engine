###############################################################################
#  shap_glm — Jin Fig3：三时点 SHAP beeswarm (A–C) + 暴露×SOFA 依赖图 (D–F)
#
#  register_block: "shap_glm"
#  典型流水线: logistic_nomogram 之后
#
#  特征集 = 各时点 nomogram backward 入选（与 Fig2 一致），非另选特征算法
#  explain_backend:
#    - "glm"（默认旧行为）：线性主效应 → 依赖图近似直线
#    - "xgboost"：同特征拟合树模型再 TreeSHAP → 文献式非线性曲线（Jin D–F）
#  图题禁止裸写 "best model"
###############################################################################

.shap_glm_cfg <- function(cfg) {
  top <- cfg$shap_glm %||% list()
  if (length(top)) return(top)
  (cfg$jin_index_sofa %||% list())$shap %||% list()
}

.shap_glm_pred_fun <- function(fit, newdata) {
  if (!is.data.frame(newdata)) newdata <- as.data.frame(newdata, stringsAsFactors = FALSE)
  if (inherits(fit, "lrm") || inherits(fit, "rms")) {
    pr <- tryCatch(
      as.numeric(stats::predict(fit, newdata = newdata, type = "fitted")),
      error = function(e) NULL
    )
    if (!is.null(pr) && length(pr) == nrow(newdata) && all(is.finite(pr))) return(pr)
    lp <- tryCatch(
      as.numeric(stats::predict(fit, newdata = newdata, type = "lp")),
      error = function(e) NULL
    )
    if (!is.null(lp) && length(lp) == nrow(newdata) && all(is.finite(lp))) {
      return(as.numeric(stats::plogis(lp)))
    }
  }
  if (inherits(fit, "glm")) {
    return(as.numeric(stats::predict(fit, newdata = newdata, type = "response")))
  }
  as.numeric(stats::predict(fit, newdata = newdata, type = "response"))
}

.shap_glm_y01 <- function(y_raw) {
  y01 <- tryCatch({
    if (exists("pipeline_outcome_as_01", mode = "function")) {
      as.integer(pipeline_outcome_as_01(y_raw))
    } else {
      NA_integer_
    }
  }, error = function(e) NA_integer_)
  if (!length(y01) || all(is.na(y01))) {
    if (is.logical(y_raw)) {
      y01 <- as.integer(y_raw)
    } else if (is.factor(y_raw)) {
      y01 <- as.integer(y_raw) - 1L
    } else {
      y01 <- suppressWarnings(as.integer(as.numeric(y_raw)))
    }
  }
  y01[!is.finite(y01)] <- 0L
  if (any(y01 > 1L, na.rm = TRUE)) y01 <- as.integer(y01 > 0L)
  as.integer(y01)
}

.shap_glm_to_num <- function(X) {
  Xn <- X
  for (cc in names(Xn)) {
    if (is.factor(Xn[[cc]]) || is.character(Xn[[cc]])) {
      Xn[[cc]] <- as.numeric(factor(Xn[[cc]], ordered = FALSE))
    } else {
      Xn[[cc]] <- suppressWarnings(as.numeric(Xn[[cc]]))
    }
  }
  Xn
}

.shap_glm_compute_sv <- function(fit, X_num, X_fac, feats, n_explain, bg_n, seed,
                                 has_fs, has_ks, has_sv,
                                 backend = "glm", y01 = NULL) {
  set.seed(as.integer(seed))
  n <- nrow(X_num)
  n_explain <- as.integer(min(n_explain, n))
  bg_n <- as.integer(min(bg_n, n))
  ix <- if (n > n_explain) sample.int(n, n_explain) else seq_len(n)
  bg_ix <- if (n > bg_n) sample.int(n, bg_n) else seq_len(n)
  X_ex_n <- X_num[ix, , drop = FALSE]
  X_bg_n <- X_num[bg_ix, , drop = FALSE]
  sv <- NULL
  method_used <- NA_character_
  err_msg <- NULL
  backend <- tolower(as.character(backend %||% "glm")[1L])

  ## 同 nomogram 特征集的 xgboost → TreeSHAP：依赖图可呈文献式非线性曲线
  if (identical(backend, "xgboost") && has_sv &&
        requireNamespace("xgboost", quietly = TRUE) &&
        !is.null(y01) && length(y01) == n) {
    xgb_try <- tryCatch({
      y_num <- as.numeric(y01)
      if (any(!is.finite(y_num)) || length(unique(y_num[!is.na(y_num)])) < 2L) {
        stop("y01 非二分类或全缺失")
      }
      X_mat <- as.matrix(X_num)
      storage.mode(X_mat) <- "double"
      dm <- xgboost::xgb.DMatrix(data = X_mat, label = y_num)
      bst <- xgboost::xgb.train(
        params = list(
          objective = "binary:logistic",
          max_depth = 4L,
          eta = 0.08,
          subsample = 0.85,
          colsample_bytree = 0.85,
          min_child_weight = 5,
          eval_metric = "logloss"
        ),
        data = dm,
        nrounds = 120L,
        verbose = 0L
      )
      ## shapviz.xgb.Booster 要求 X_pred 为 matrix / xgb.DMatrix（勿传 data.frame）
      Xp <- as.matrix(X_ex_n)
      storage.mode(Xp) <- "double"
      shapviz::shapviz(bst, X_pred = Xp, X = as.data.frame(X_ex_n))
    }, error = function(e) e)
    if (!inherits(xgb_try, "error")) {
      sv <- xgb_try
      method_used <- "xgboost+shapviz"
    } else {
      err_msg <- paste0("xgboost: ", conditionMessage(xgb_try))
      cli::cli_alert_warning("shap_glm: xgboost TreeSHAP 失败，回退 glm SHAP — {err_msg}")
    }
  }

  pred_fun <- function(object, newdata) {
    if (!is.data.frame(newdata)) newdata <- as.data.frame(newdata, stringsAsFactors = FALSE)
    nd <- newdata
    for (cc in intersect(names(nd), feats)) {
      if (is.factor(X_fac[[cc]]) && !is.factor(nd[[cc]])) {
        lev <- levels(X_fac[[cc]])
        ii <- as.integer(round(as.numeric(nd[[cc]])))
        ii[!is.finite(ii)] <- 1L
        ii <- pmax(1L, pmin(length(lev), ii))
        nd[[cc]] <- factor(lev[ii], levels = lev)
      } else if (!is.factor(X_fac[[cc]])) {
        nd[[cc]] <- suppressWarnings(as.numeric(nd[[cc]]))
      }
    }
    .shap_glm_pred_fun(object, nd)
  }
  if (is.null(sv) && has_fs && has_sv) {
    fs <- tryCatch({
      fastshap::explain(
        fit, X = X_ex_n,
        pred_wrapper = function(object, newdata) pred_fun(object, newdata),
        nsim = 50L, adjust = TRUE
      )
    }, error = function(e) e)
    if (!inherits(fs, "error")) {
      sv <- tryCatch(shapviz::shapviz(fs, X = X_ex_n), error = function(e) e)
      if (!inherits(sv, "error")) method_used <- "fastshap+shapviz" else {
        err_msg <- conditionMessage(sv); sv <- NULL
      }
    } else err_msg <- paste(err_msg %||% "", conditionMessage(fs), sep = "; ")
  }
  if (is.null(sv) && has_ks && has_sv) {
    ks <- tryCatch(
      kernelshap::kernelshap(fit, X_ex_n, bg_X = X_bg_n, pred_fun = pred_fun),
      error = function(e) e
    )
    if (!inherits(ks, "error")) {
      sv <- tryCatch(shapviz::shapviz(ks), error = function(e) e)
      if (!inherits(sv, "error")) method_used <- "kernelshap+shapviz" else {
        err_msg <- conditionMessage(sv); sv <- NULL
      }
    } else err_msg <- paste(err_msg %||% "", conditionMessage(ks), sep = "; ")
  }
  list(sv = sv, method = method_used, error = err_msg, n_explain = length(ix), ix = ix)
}

.shap_glm_horizon_specs <- function(cfg, nom) {
  ng <- cfg$logistic_nomogram %||% (cfg$jin_index_sofa %||% list())$nomogram %||% list()
  defaults <- list(
    hosp = list(event = "fustatus", label = "in-hospital Mortality", panel = "A"),
    d30  = list(event = "event_d30", label = "30-day Mortality", panel = "B"),
    d365 = list(event = "event_d365", label = "365-day Mortality", panel = "C")
  )
  hz_ids <- as.character(ng$horizons %||% names(nom$features_by_horizon) %||% c("hosp", "d30", "d365"))
  out <- list()
  for (hid in hz_ids) {
    sp <- ng[[hid]] %||% defaults[[hid]] %||% list()
    lab <- as.character(sp$label %||% defaults[[hid]]$label %||% hid)[1L]
    ## 精简文献式短标题
    lab <- sub("^Probability of\\s+", "", lab, ignore.case = TRUE)
    out[[hid]] <- list(
      event = as.character(sp$event %||% defaults[[hid]]$event %||% "fustatus")[1L],
      label = lab,
      panel = as.character(sp$panel %||% defaults[[hid]]$panel %||% toupper(substr(hid, 1, 1)))[1L]
    )
  }
  out
}

.shap_glm_compose_jin_fig3 <- function(bee_paths, dep_paths, labels, out_path,
                                       exposure_lab = "WPR", color_lab = "SOFA",
                                       db_label = "") {
  ## 2×3：上 A–C beeswarm，下 D–F dependence
  py <- NULL
  for (r in unique(c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    getwd()
  ))) {
    if (!nzchar(r)) next
    cand <- file.path(r, "R", "compose_jin_shap_fig3.py")
    if (file.exists(cand)) { py <- cand; break }
  }
  if (is.null(py)) return(invisible(FALSE))
  labs <- as.character(labels)
  if (length(labs) < 3L) labs <- c(labs, rep("", 3L - length(labs)))
  st <- tryCatch({
    system2(
      "python3",
      c(
        py,
        "--bee-a", bee_paths[[1L]], "--bee-b", bee_paths[[2L]], "--bee-c", bee_paths[[3L]],
        "--dep-a", dep_paths[[1L]], "--dep-b", dep_paths[[2L]], "--dep-c", dep_paths[[3L]],
        "--label-a", labs[[1L]], "--label-b", labs[[2L]], "--label-c", labs[[3L]],
        "--exposure", exposure_lab, "--color", color_lab,
        "--db-label", as.character(db_label %||% "")[1L],
        "--max-edge-in", "16",
        "--out", out_path
      ),
      stdout = TRUE, stderr = TRUE
    )
  }, error = function(e) e)
  invisible(is.character(st) && file.exists(out_path) &&
            isTRUE((file.info(out_path)$size %||% 0) > 2000))
}

block_shap_glm <- function(ctx, ...) {
  .cands <- unique(c(
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""),
    as.character(ctx$config$project$root %||% "")[1L],
    getwd()
  ))
  for (.r in .cands[nzchar(as.character(.cands))]) {
    .p <- file.path(.r, "R", "literature_jin_index_sofa.R")
    if (file.exists(.p)) {
      tryCatch(source(.p, local = FALSE), error = function(e) NULL)
      break
    }
  }

  sh <- .shap_glm_cfg(ctx$config)
  if (!is.null(sh$enable) && !isTRUE(sh$enable)) {
    cli::cli_alert_info("shap_glm: enable=FALSE，跳过")
    return(ctx)
  }

  nom <- ctx$results$logistic_nomogram %||% ctx$results$jin_nomogram_cal
  if (is.null(nom) || !length(nom$features)) {
    cli::cli_alert_warning("shap_glm: 需先跑 logistic_nomogram；跳过")
    return(ctx)
  }

  has_sv <- requireNamespace("shapviz", quietly = TRUE)
  has_ks <- requireNamespace("kernelshap", quietly = TRUE)
  has_fs <- requireNamespace("fastshap", quietly = TRUE)
  if (!has_sv || (!has_ks && !has_fs)) {
    cli::cli_alert_warning("shap_glm: 缺 shapviz/fastshap/kernelshap，跳过")
    ctx$results$shap_glm <- list(ok = FALSE, reason = "missing_packages")
    return(ctx)
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    cli::cli_alert_warning("shap_glm: 需要 ggplot2，跳过")
    ctx$results$shap_glm <- list(ok = FALSE, reason = "missing_ggplot2")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  exposure <- as.character(nom$exposure %||% ctx$config$project$index_var %||% "WPR")[1L]
  sofa_var <- as.character(nom$sofa_var %||% "SOFA")[1L]
  hz_specs <- .shap_glm_horizon_specs(ctx$config, nom)
  feats_by <- nom$features_by_horizon %||% list()

  n_explain <- suppressWarnings(as.integer(sh$n_explain %||% 200L)[1L])
  bg_n <- suppressWarnings(as.integer(sh$bg_n %||% 50L)[1L])
  seed <- suppressWarnings(as.integer(sh$seed %||% 42L)[1L])
  top_n <- suppressWarnings(as.integer(sh$top_n %||% 12L)[1L])
  ## jin_fig3 默认 xgboost：同 Fig2 特征但非线性，D–F 才出曲线（glm 主效应≈直线）
  explain_backend <- as.character(
    sh$explain_backend %||% if (isTRUE(sh$jin_fig3)) "xgboost" else "glm"
  )[1L]
  if (!is.finite(n_explain) || n_explain < 10L) n_explain <- 200L
  if (!is.finite(bg_n) || bg_n < 5L) bg_n <- 50L
  if (!is.finite(seed)) seed <- 42L
  if (!is.finite(top_n) || top_n < 3L) top_n <- 12L
  cli::cli_alert_info("shap_glm: explain_backend={explain_backend}")

  fig_dirs <- unique(c(
    as.character(ctx$output_dir_figures %||% "")[1L],
    file.path(as.character(ctx$output_dir %||% getwd())[1L], "Figures"),
    {
      lib_root <- tryCatch(dirname(as.character(ctx$output_dir %||% "")[1L]), error = function(e) "")
      if (nzchar(lib_root) && basename(lib_root) %in% c("MIMIC", "eICU", "NHANES")) {
        file.path(lib_root, "Figures")
      } else NA_character_
    }
  ))
  fig_dirs <- fig_dirs[nzchar(fig_dirs) & !is.na(fig_dirs)]
  for (fd in fig_dirs) dir.create(fd, recursive = TRUE, showWarnings = FALSE)
  fig_dir <- fig_dirs[[1L]]
  step_dir <- file.path(as.character(ctx$output_dir %||% fig_dir)[1L], "step_shap_glm")
  dir.create(step_dir, recursive = TRUE, showWarnings = FALSE)

  bee_paths <- character(0)
  dep_paths <- character(0)
  panel_labels <- character(0)
  methods <- character(0)
  by_hz <- list()

  for (hid in names(hz_specs)) {
    sp <- hz_specs[[hid]]
    outcome <- sp$event
    feats <- as.character(feats_by[[hid]] %||% nom$features)
    feats <- feats[feats %in% names(data)]
    if (!outcome %in% names(data) || length(feats) < 2L) {
      cli::cli_alert_warning("shap_glm: {hid} 缺结局/特征，跳过该时点")
      next
    }
    if (!exposure %in% feats) feats <- c(exposure, feats)
    if (!sofa_var %in% feats && sofa_var %in% names(data)) feats <- c(feats, sofa_var)
    feats <- unique(feats[feats %in% names(data)])

    need <- unique(c(feats, outcome))
    d <- data[, need, drop = FALSE]
    for (cc in feats) if (is.character(d[[cc]])) d[[cc]] <- factor(d[[cc]])
    d <- stats::na.omit(d)
    if (nrow(d) < 30L) {
      cli::cli_alert_warning("shap_glm: {hid} 完整病例过少，跳过")
      next
    }
    d[[outcome]] <- .shap_glm_y01(d[[outcome]])
    X <- d[, feats, drop = FALSE]
    X_num <- .shap_glm_to_num(X)
    ok_row <- stats::complete.cases(X_num)
    d <- d[ok_row, , drop = FALSE]
    X <- X[ok_row, , drop = FALSE]
    X_num <- X_num[ok_row, , drop = FALSE]

    fml <- stats::as.formula(paste(outcome, "~", paste(feats, collapse = " + ")))
    fit <- tryCatch(stats::glm(fml, data = d, family = stats::binomial()), error = function(e) NULL)
    if (is.null(fit)) {
      cli::cli_alert_warning("shap_glm: {hid} glm 失败，跳过")
      next
    }

    comp <- .shap_glm_compute_sv(
      fit, X_num, X, feats, n_explain, bg_n, seed + match(hid, names(hz_specs), nomatch = 1L),
      has_fs, has_ks, has_sv,
      backend = explain_backend, y01 = d[[outcome]]
    )
    if (is.null(comp$sv)) {
      cli::cli_alert_warning("shap_glm: {hid} SHAP 失败 — {comp$error %||% '?'}")
      next
    }
    methods <- c(methods, comp$method)
    panel_labels <- c(panel_labels, sp$label)

    bee_bn <- sprintf("shap_panel_%s_%s_beeswarm.pdf", sp$panel, hid)
    dep_bn <- sprintf("shap_panel_%s_%s_dependence.pdf", sp$panel, hid)
    bee_path <- file.path(step_dir, bee_bn)
    dep_path <- file.path(step_dir, dep_bn)

    title_bee <- sprintf("%s. %s", sp$panel, sp$label)
    grDevices::pdf(bee_path, width = 5.2, height = 4.6, useDingbats = FALSE)
    p_bee <- tryCatch({
      shapviz::sv_importance(comp$sv, kind = "beeswarm", max_display = top_n) +
        ggplot2::ggtitle(title_bee) +
        ggplot2::theme_bw(base_size = 9) +
        ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 10))
    }, error = function(e) {
      shapviz::sv_importance(comp$sv, kind = "bar", max_display = top_n) +
        ggplot2::ggtitle(title_bee)
    })
    print(p_bee)
    grDevices::dev.off()

    ## 依赖图：暴露 SHAP vs 暴露值，颜色 = SOFA（对齐文献 D–F）
    dep_letter <- c(A = "D", B = "E", C = "F")[[sp$panel]] %||% "D"
    title_dep <- sprintf(
      "%s. %s impact on %s", dep_letter, exposure, sp$label
    )
    grDevices::pdf(dep_path, width = 5.2, height = 4.6, useDingbats = FALSE)
    ## 手绘依赖图：点按 SOFA 上色 + 预计算黑色 LOESS（文献 D–F；勿用默认 lm）
    p_dep <- tryCatch({
      sv_obj <- comp$sv
      xv <- as.numeric(sv_obj$X[[exposure]])
      sv <- as.numeric(sv_obj$S[, exposure])
      cv <- if (sofa_var %in% names(sv_obj$X)) as.numeric(sv_obj$X[[sofa_var]]) else NA_real_
      df_dep <- data.frame(x = xv, shap = sv, color = cv)
      df_dep <- df_dep[is.finite(df_dep$x) & is.finite(df_dep$shap), , drop = FALSE]
      ## 预计算 LOESS → geom_path，避免 geom_smooth 在部分设备上不画/被盖住
      o <- order(df_dep$x)
      xs <- df_dep$x[o]
      ys <- df_dep$shap[o]
      span_use <- if (nrow(df_dep) >= 80L) 0.55 else 0.75
      lo <- tryCatch(
        stats::loess(ys ~ xs, span = span_use, degree = 2L),
        error = function(e) NULL
      )
      df_lo <- if (!is.null(lo)) {
        xg <- seq(min(xs), max(xs), length.out = 200L)
        data.frame(x = xg, shap = as.numeric(stats::predict(lo, newdata = data.frame(xs = xg))))
      } else {
        data.frame(x = xs, shap = ys)
      }
      df_lo <- df_lo[is.finite(df_lo$x) & is.finite(df_lo$shap), , drop = FALSE]
      ggplot2::ggplot(df_dep, ggplot2::aes(x = .data$x, y = .data$shap, color = .data$color)) +
        ggplot2::geom_point(alpha = 0.65, size = 1.6) +
        ggplot2::geom_path(
          data = df_lo,
          mapping = ggplot2::aes(x = .data$x, y = .data$shap),
          inherit.aes = FALSE,
          color = "white", linewidth = 2.6, lineend = "round"
        ) +
        ggplot2::geom_path(
          data = df_lo,
          mapping = ggplot2::aes(x = .data$x, y = .data$shap),
          inherit.aes = FALSE,
          color = "black", linewidth = 1.55, lineend = "round"
        ) +
        ggplot2::scale_color_viridis_c(option = "plasma", name = sofa_var, na.value = "grey60") +
        ggplot2::ggtitle(title_dep) +
        ggplot2::labs(
          x = exposure,
          y = paste0("SHAP value for ", exposure, " (Impact on Mortality Prediction)")
        ) +
        ggplot2::theme_bw(base_size = 9) +
        ggplot2::theme(
          plot.title = ggplot2::element_text(face = "bold", size = 10),
          legend.position = "right"
        )
    }, error = function(e) {
      ggplot2::ggplot() + ggplot2::ggtitle(paste("dependence failed:", conditionMessage(e)))
    })
    print(p_dep)
    grDevices::dev.off()

    bee_paths <- c(bee_paths, bee_path)
    dep_paths <- c(dep_paths, dep_path)
    by_hz[[hid]] <- list(
      features = feats, outcome = outcome, method = comp$method,
      n_explain = comp$n_explain, beeswarm = bee_path, dependence = dep_path
    )
    cli::cli_alert_info(
      "shap_glm: {sp$panel}/{hid} method={comp$method} n={comp$n_explain} feats={length(feats)}"
    )
  }

  if (length(bee_paths) < 3L || length(dep_paths) < 3L) {
    cli::cli_alert_warning(
      "shap_glm: 时点面板不足 ({length(bee_paths)} bee / {length(dep_paths)} dep)，无法拼 Jin Fig3"
    )
    ctx$results$shap_glm <- list(ok = FALSE, reason = "incomplete_horizons", by_horizon = by_hz)
    return(ctx)
  }

  combined_bn <- "Figure. SHAP summary and dependence in-hospital 30-day 365-day mortality.pdf"
  combined_path <- file.path(fig_dir, combined_bn)
  ok_comp <- .shap_glm_compose_jin_fig3(
    bee_paths[1:3], dep_paths[1:3], panel_labels[1:3],
    combined_path, exposure_lab = exposure, color_lab = sofa_var
  )
  if (!isTRUE(ok_comp)) {
    ## 退回：竖排三 beeswarm
    if (requireNamespace("pdftools", quietly = TRUE)) {
      tryCatch(pdftools::pdf_combine(bee_paths[1:3], output = combined_path), error = function(e) NULL)
    } else {
      file.copy(bee_paths[[1L]], combined_path, overwrite = TRUE)
    }
  }

  ## 兼容旧单图文件名（院内 beeswarm）
  legacy_bee <- file.path(fig_dir, "Figure. SHAP beeswarm logistic nomogram in-hospital mortality.pdf")
  file.copy(bee_paths[[1L]], legacy_bee, overwrite = TRUE)

  for (fd in fig_dirs[-1L]) {
    if (!nzchar(fd)) next
    file.copy(combined_path, file.path(fd, combined_bn), overwrite = TRUE)
    file.copy(legacy_bee, file.path(fd, basename(legacy_bee)), overwrite = TRUE)
  }

  res <- list(
    ok = TRUE,
    method = unique(methods),
    fit_backend = explain_backend,
    exposure = exposure,
    sofa_var = sofa_var,
    features = nom$features,
    features_by_horizon = lapply(by_hz, `[[`, "features"),
    by_horizon = by_hz,
    n_explain = n_explain,
    jin_fig3_pdf = combined_path,
    beeswarm_pdf = legacy_bee,
    panel_beeswarm = bee_paths,
    panel_dependence = dep_paths,
    title_rule = "Jin Fig3: A-C beeswarm + D-F exposure dependence colored by SOFA; same features as Fig2 nomogram; never bare best model."
  )
  ctx$results$shap_glm <- res
  ctx$results$jin_shap_explain <- res
  cli::cli_alert_success(
    "shap_glm: Jin Fig3 2x3 → {basename(combined_path)} (method={paste(unique(methods), collapse=',')})"
  )
  ctx
}

register_block(
  "shap_glm",
  block_shap_glm,
  "Jin Fig3：三时点SHAP beeswarm+暴露依赖图（同列线图特征）"
)
