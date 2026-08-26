# threshold_logistic — 发病侧连续 index 的 threshold / piecewise logistic 表+图
###############################################################################
#
#  register_block: "threshold_logistic"
#  典型流水线: … → rcs_incidence → threshold_logistic → subgroup_incidence
#
#  对连续暴露在分位数网格上拟合两段 logistic（优先 segmented 精修 psi），
#  输出阈值点、阈值下/上每单位 OR 与 P、LRT；图为平滑曲线 + 竖线阈值。
#  pub_figure$profile == "mimic_inc_prog_sle_aki" 时走文献版主题（Task 6 可再加深）。
#
#  require_data  = ctx$data$imputed %||% ctx$data$cleaned
#  require_study = project$study_type == "incidence"（非 incidence 则跳过）
#  协变量       = config$threshold_logistic$covariates → Model2Factors → Model1Factors
#
#  # ── 配置 config$threshold_logistic ────────────────────────────────────────
#  threshold_logistic = list(
#    index_var        = NULL,    # NULL → incidence$index_var / logistic$index_var
#    outcome_var      = NULL,    # NULL → incidence$outcome_var / data$outcome_column
#    covariates       = NULL,    # NULL → Model2Factors（空则 Model1）
#    q_lo             = 0.10,    # 网格下分位
#    q_hi             = 0.90,
#    n_grid           = 81L,
#    min_segment_n    = 20L,     # 每段最少人数
#    start_from_rcs   = TRUE,    # 若有 ctx$results$cutoff_value 则作为 segmented 初值
#    table_filename   = NULL,    # NULL → Table_Threshold_logistic_<Index>.csv
#    figure_filename  = NULL     # NULL → Figure_Threshold_<Index>.pdf
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: 连续 index、二元结局、锁定协变量
#  写: ctx$results$threshold_logistic（threshold / or_below / or_above / p_* / method）
#      Tables/Table_Threshold_logistic_*.csv（及 export_sci_table 入队）
#      Figures/Figure_Threshold_*.pdf
###############################################################################

.thl03_need_pkg <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE)) return(TRUE)
  repos <- getOption("repos")
  if (is.null(repos) || identical(unname(repos), "@CRAN@") ||
      identical(repos, c(CRAN = "@CRAN@"))) {
    repos <- c(CRAN = "https://cloud.r-project.org")
  }
  tryCatch({
    utils::install.packages(pkg, repos = repos, quiet = TRUE)
    requireNamespace(pkg, quietly = TRUE)
  }, error = function(e) FALSE)
}

.thl03_parse_factors <- function(x) {
  if (is.null(x) || !length(x)) return(character(0))
  if (length(x) == 1L && is.character(x) && grepl("+", x, fixed = TRUE)) {
    return(trimws(unlist(strsplit(x, "\\s*\\+\\s*"))))
  }
  out <- trimws(as.character(x))
  out[nzchar(out)]
}

.thl03_is_lit_profile <- function(config) {
  if (exists("is_pub_profile", mode = "function")) {
    return(isTRUE(is_pub_profile(config, "mimic_inc_prog_sle_aki")))
  }
  p <- tryCatch(config$pub_figure$profile, error = function(e) NULL)
  identical(as.character(p %||% "")[1L], "mimic_inc_prog_sle_aki")
}

.thl03_wald_or <- function(fit, term) {
  sm <- tryCatch(summary(fit)$coefficients, error = function(e) NULL)
  empty <- list(or = NA_real_, ci_lo = NA_real_, ci_hi = NA_real_, p = NA_real_)
  if (is.null(sm) || !nrow(sm)) return(empty)
  rn <- rownames(sm)
  hit <- which(rn == term | rn == paste0("`", term, "`"))[1L]
  if (!length(hit) || is.na(hit)) {
    hit <- grep(paste0("^", gsub("\\.", "\\\\.", term)), rn)[1L]
  }
  if (!length(hit) || is.na(hit)) return(empty)
  est <- as.numeric(sm[hit, "Estimate"])
  se <- as.numeric(sm[hit, "Std. Error"])
  pr_col <- grep("^Pr\\(", colnames(sm))[1L]
  pv <- if (length(pr_col) && !is.na(pr_col)) as.numeric(sm[hit, pr_col]) else NA_real_
  if (!is.finite(est) || !is.finite(se) || se < 0) return(empty)
  list(
    or = exp(est),
    ci_lo = exp(est - 1.96 * se),
    ci_hi = exp(est + 1.96 * se),
    p = pv
  )
}

.thl03_fit_piecewise <- function(data, ycol, xcol, tau, covs) {
  xv <- as.numeric(data[[xcol]])
  n_lo <- sum(is.finite(xv) & xv < tau)
  n_hi <- sum(is.finite(xv) & xv >= tau)
  d <- data
  d$.x_lo <- pmin(xv, tau)
  d$.x_hi <- pmax(xv - tau, 0)
  rhs <- c(".x_lo", ".x_hi", covs)
  fml <- stats::as.formula(paste(ycol, "~", paste(rhs, collapse = " + ")))
  fit <- tryCatch(
    stats::glm(fml, data = d, family = stats::binomial()),
    error = function(e) NULL
  )
  if (is.null(fit)) return(NULL)
  conv <- isTRUE(fit$converged)
  ll <- tryCatch(as.numeric(stats::logLik(fit)), error = function(e) NA_real_)
  if (!isTRUE(conv) || !is.finite(ll)) return(NULL)
  list(fit = fit, data = d, tau = tau, ll = ll, n_lo = n_lo, n_hi = n_hi)
}

.thl03_fit_linear <- function(data, ycol, xcol, covs) {
  rhs <- c(xcol, covs)
  fml <- stats::as.formula(paste(ycol, "~", paste(rhs, collapse = " + ")))
  tryCatch(
    stats::glm(fml, data = data, family = stats::binomial()),
    error = function(e) NULL
  )
}

.thl03_grid_search <- function(data, ycol, xcol, covs, q_lo, q_hi, n_grid, min_n) {
  xv <- as.numeric(data[[xcol]])
  xv <- xv[is.finite(xv)]
  qs <- stats::quantile(xv, probs = seq(q_lo, q_hi, length.out = n_grid), na.rm = TRUE, names = FALSE)
  cands <- sort(unique(as.numeric(qs)))
  best <- NULL
  for (tau in cands) {
    n_lo <- sum(is.finite(as.numeric(data[[xcol]])) & as.numeric(data[[xcol]]) < tau)
    n_hi <- sum(is.finite(as.numeric(data[[xcol]])) & as.numeric(data[[xcol]]) >= tau)
    if (n_lo < min_n || n_hi < min_n) next
    fit <- .thl03_fit_piecewise(data, ycol, xcol, tau, covs)
    if (is.null(fit)) next
    if (is.null(best) || fit$ll > best$ll) best <- fit
  }
  best
}

.thl03_try_segmented <- function(data, ycol, xcol, covs, psi0) {
  if (!.thl03_need_pkg("segmented")) return(NULL)
  fit0 <- .thl03_fit_linear(data, ycol, xcol, covs)
  if (is.null(fit0)) return(NULL)
  psi <- list()
  psi[[xcol]] <- as.numeric(psi0)[1L]
  seg <- tryCatch(
    segmented::segmented(fit0, seg.Z = stats::as.formula(paste("~", xcol)), psi = psi),
    error = function(e) NULL
  )
  if (is.null(seg) || is.null(seg$psi)) return(NULL)
  tau <- suppressWarnings(as.numeric(seg$psi[1L, "Est."]))
  if (!is.finite(tau)) return(NULL)
  list(tau = tau, seg = seg)
}

.thl03_fmt_or <- function(or, lo, hi) {
  if (!is.finite(or)) return("")
  paste0(
    formatC(or, digits = 3, format = "f"),
    " (", formatC(lo, digits = 3, format = "f"), ", ",
    formatC(hi, digits = 3, format = "f"), ")"
  )
}

.thl03_fmt_p <- function(p) {
  if (!is.finite(p)) return("")
  if (p < 0.001) return("P < 0.001")
  formatC(p, digits = 4, format = "f")
}

.thl03_make_plot <- function(data, ycol, xcol, tau, pw, covs, lit, index_lab) {
  if (!.thl03_need_pkg("ggplot2")) {
    stop("threshold_logistic: 需要 ggplot2 包。", call. = FALSE)
  }
  xv <- as.numeric(data[[xcol]])
  ok <- is.finite(xv) & is.finite(as.numeric(data[[ycol]]))
  x_grid <- seq(min(xv[ok]), max(xv[ok]), length.out = 200L)
  nd <- data.frame(.x_lo = pmin(x_grid, tau), .x_hi = pmax(x_grid - tau, 0))
  for (cv in covs) {
    v <- data[[cv]]
    if (is.numeric(v) || is.integer(v)) {
      nd[[cv]] <- stats::median(as.numeric(v), na.rm = TRUE)
    } else {
      tb <- table(v)
      nd[[cv]] <- names(tb)[which.max(tb)][1L]
      if (is.factor(v)) nd[[cv]] <- factor(nd[[cv]], levels = levels(v))
    }
  }
  pr <- as.numeric(stats::predict(pw$fit, newdata = nd, type = "response"))
  # 以阈值处预测概率为参照，画相对 OR 平滑曲线
  pr_tau <- stats::approx(x_grid, pr, xout = tau, rule = 2)$y
  odds <- function(p) p / (1 - pmax(pmin(p, 1 - 1e-8), 1e-8))
  rel_or <- odds(pr) / odds(pr_tau)
  plot_df <- data.frame(x = x_grid, or = rel_or, stringsAsFactors = FALSE)

  pal <- if (isTRUE(lit)) c(line = "#1B4F72", vline = "#C0392B") else c(line = "#2C3E50", vline = "#E74C3C")
  p <- ggplot2::ggplot(plot_df, ggplot2::aes(x = x, y = or)) +
    ggplot2::geom_line(color = pal[["line"]], linewidth = 0.9) +
    ggplot2::geom_hline(yintercept = 1, linetype = "dashed", colour = "grey50", linewidth = 0.3) +
    ggplot2::geom_vline(xintercept = tau, linetype = "dashed", colour = pal[["vline"]], linewidth = 0.6) +
    ggplot2::labs(
      x = index_lab,
      y = "Odds ratio (ref = threshold)",
      title = paste0("Threshold logistic of ", index_lab)
    )
  if (isTRUE(lit)) {
    lab <- paste0("Threshold = ", formatC(tau, digits = 3, format = "f"))
    p <- p +
      ggplot2::annotate(
        "text", x = tau, y = max(plot_df$or, na.rm = TRUE),
        label = lab, hjust = -0.05, vjust = 1.2, size = 3.2
      ) +
      ggplot2::theme_classic(base_size = 11, base_family = "Times New Roman") +
      ggplot2::theme(
        plot.title = ggplot2::element_text(face = "bold", hjust = 0.5),
        axis.title = ggplot2::element_text(face = "plain")
      )
  } else {
    p <- p + ggplot2::theme_bw(base_size = 11)
  }
  p
}

block_threshold_logistic <- function(ctx, ...) {
  cfg <- ctx$config %||% list()
  study_type <- tolower(trimws(as.character(cfg$project$study_type %||% "")[1L]))
  if (!identical(study_type, "incidence")) {
    cli::cli_alert_info("threshold_logistic: study_type 非 incidence，跳过。")
    return(ctx)
  }

  bl_cfg <- cfg$threshold_logistic %||% list()
  inc_cfg <- cfg$incidence %||% list()
  data_imp <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data_imp) || !is.data.frame(data_imp) || !nrow(data_imp)) {
    stop("threshold_logistic: 无分析数据，请先运行 imputation / data_clean。", call. = FALSE)
  }

  Index <- as.character(
    bl_cfg$index_var %||% inc_cfg$index_var %||% (cfg$logistic %||% list())$index_var %||% ""
  )[1L]
  if (!nzchar(Index) || !Index %in% names(data_imp)) {
    stop("threshold_logistic: 未设置或找不到 index_var。", call. = FALSE)
  }
  ycol <- as.character(
    bl_cfg$outcome_var %||% inc_cfg$outcome_var %||%
      cfg$data$outcome_column %||% "Disease"
  )[1L]
  if (!ycol %in% names(data_imp)) {
    stop("threshold_logistic: 结局列 '", ycol, "' 不在数据中。", call. = FALSE)
  }

  d <- data_imp
  d[[ycol]] <- if (exists("pipeline_outcome_as_01", mode = "function")) {
    pipeline_outcome_as_01(d[[ycol]], cfg)
  } else {
    as.numeric(d[[ycol]])
  }
  d[[Index]] <- as.numeric(d[[Index]])
  keep <- is.finite(d[[Index]]) & is.finite(d[[ycol]])
  d <- d[keep, , drop = FALSE]
  if (nrow(d) < 40L || length(unique(d[[ycol]])) < 2L) {
    stop("threshold_logistic: 有效样本过少或结局无变异。", call. = FALSE)
  }

  covs <- .thl03_parse_factors(
    bl_cfg$covariates %||% ctx$results$Model2Factors %||% ctx$results$Model1Factors
  )
  covs <- setdiff(covs, c(Index, ycol))
  covs <- intersect(covs, names(d))
  # 丢掉与暴露完全共线的协变量（例如冒烟时 Age 既当 index 又当协变量）
  if (length(covs)) {
    xv <- d[[Index]]
    drop_colin <- vapply(covs, function(cv) {
      v <- suppressWarnings(as.numeric(d[[cv]]))
      if (!is.numeric(d[[cv]]) && !is.integer(d[[cv]])) return(FALSE)
      ok <- is.finite(v) & is.finite(xv)
      if (sum(ok) < 8L) return(FALSE)
      stats::sd(v[ok]) < 1e-12 || abs(stats::cor(v[ok], xv[ok])) > 0.999
    }, logical(1))
    if (any(drop_colin)) {
      cli::cli_alert_info(
        "threshold_logistic: 去掉与暴露共线协变量: {paste(covs[drop_colin], collapse = ', ')}"
      )
      covs <- covs[!drop_colin]
    }
  }

  q_lo <- as.numeric(bl_cfg$q_lo %||% 0.10)[1L]
  q_hi <- as.numeric(bl_cfg$q_hi %||% 0.90)[1L]
  n_grid <- as.integer(bl_cfg$n_grid %||% 81L)[1L]
  min_n <- as.integer(bl_cfg$min_segment_n %||% 20L)[1L]
  if (!is.finite(n_grid) || n_grid < 5L) n_grid <- 41L
  if (!is.finite(min_n) || min_n < 5L) min_n <- 10L

  grid <- .thl03_grid_search(d, ycol, Index, covs, q_lo, q_hi, n_grid, min_n)
  if (is.null(grid)) {
    stop("threshold_logistic: 网格搜索未得到有效两段模型。", call. = FALSE)
  }
  method <- "quantile_grid"
  tau <- grid$tau
  psi0 <- tau
  if (isTRUE(bl_cfg$start_from_rcs %||% TRUE)) {
    rcs_cut <- suppressWarnings(as.numeric(ctx$results$cutoff_value)[1L])
    if (is.finite(rcs_cut)) psi0 <- rcs_cut
  }
  seg <- .thl03_try_segmented(d, ycol, Index, covs, psi0)
  if (!is.null(seg) && is.finite(seg$tau)) {
    xv <- as.numeric(d[[Index]])
    n_lo <- sum(is.finite(xv) & xv < seg$tau)
    n_hi <- sum(is.finite(xv) & xv >= seg$tau)
    if (n_lo >= min_n && n_hi >= min_n) {
      pw_seg <- .thl03_fit_piecewise(d, ycol, Index, seg$tau, covs)
      if (!is.null(pw_seg)) {
        tau <- seg$tau
        grid <- pw_seg
        method <- "segmented"
      }
    }
  }

  pw <- grid
  or_lo <- .thl03_wald_or(pw$fit, ".x_lo")
  or_hi <- .thl03_wald_or(pw$fit, ".x_hi")
  fit_lin <- .thl03_fit_linear(d, ycol, Index, covs)
  p_lrt <- NA_real_
  if (!is.null(fit_lin)) {
    ll_lin <- tryCatch(as.numeric(stats::logLik(fit_lin)), error = function(e) NA_real_)
    if (is.finite(ll_lin) && is.finite(pw$ll) && pw$ll >= ll_lin) {
      p_lrt <- stats::pchisq(2 * (pw$ll - ll_lin), df = 1, lower.tail = FALSE)
    }
  }

  n_total <- nrow(d)
  n_evt <- as.integer(sum(d[[ycol]] == 1, na.rm = TRUE))
  tab <- data.frame(
    index = Index,
    threshold = tau,
    method = method,
    n = n_total,
    events = n_evt,
    n_below = pw$n_lo,
    n_above = pw$n_hi,
    or_below = or_lo$or,
    ci_below_lo = or_lo$ci_lo,
    ci_below_hi = or_lo$ci_hi,
    p_below = or_lo$p,
    or_above = or_hi$or,
    ci_above_lo = or_hi$ci_lo,
    ci_above_hi = or_hi$ci_hi,
    p_above = or_hi$p,
    p_lrt = p_lrt,
    covariates = paste(covs, collapse = " + "),
    stringsAsFactors = FALSE
  )

  tbl_dir <- ctx$output_dir_tables %||%
    file.path(ctx$output_dir %||% cfg$project$output_dir %||% "Output", "Tables")
  fig_dir <- ctx$output_dir_figures %||%
    file.path(ctx$output_dir %||% cfg$project$output_dir %||% "Output", "Figures")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)

  csv_name <- as.character(bl_cfg$table_filename %||% paste0("Table_Threshold_logistic_", Index, ".csv"))[1L]
  if (!grepl("\\.csv$", csv_name, ignore.case = TRUE)) csv_name <- paste0(csv_name, ".csv")
  csv_path <- file.path(tbl_dir, csv_name)
  utils::write.csv(tab, csv_path, row.names = FALSE)
  cli::cli_alert_success("Saved: {basename(csv_path)}")

  # 发表三线表入队（与 logistic_* 同口径）；失败不影响 CSV
  sci <- data.frame(
    Segment = c(
      paste0("< ", formatC(tau, digits = 3, format = "f")),
      paste0("\u2265 ", formatC(tau, digits = 3, format = "f"))
    ),
    N = c(pw$n_lo, pw$n_hi),
    Events = c(NA_integer_, NA_integer_),
    OR = c(
      .thl03_fmt_or(or_lo$or, or_lo$ci_lo, or_lo$ci_hi),
      .thl03_fmt_or(or_hi$or, or_hi$ci_lo, or_hi$ci_hi)
    ),
    `P-value` = c(.thl03_fmt_p(or_lo$p), .thl03_fmt_p(or_hi$p)),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  if (exists("export_sci_table", mode = "function")) {
    ix_disp <- if (exists("pipeline_index_display_name", mode = "function")) {
      pipeline_index_display_name(cfg, Index)
    } else {
      Index
    }
    caption <- paste0("Threshold logistic of ", ix_disp)
    xlsx_path <- file.path(tbl_dir, sub("\\.csv$", ".xlsx", csv_name, ignore.case = TRUE))
    if (exists("pub_paths", mode = "function") && !is.null(ctx$output_dir_tables)) {
      pub <- tryCatch(
        pub_paths(ctx, tbl_dir, "supp_table", caption, "xlsx"),
        error = function(e) NULL
      )
      if (!is.null(pub)) {
        xlsx_path <- pub$filepath
        caption <- pub$title
      }
    }
    tryCatch(
      export_sci_table(
        sci, xlsx_path, title = caption,
        table_footnotes = paste0(
          "Piecewise logistic per-unit OR below/above threshold. ",
          "Threshold=", formatC(tau, digits = 4, format = "f"),
          "; method=", method,
          "; LRT P=", .thl03_fmt_p(p_lrt),
          if (length(covs)) paste0("; adjusted for ", paste(covs, collapse = ", ")) else "; unadjusted",
          "."
        )
      ),
      error = function(e) cli::cli_alert_warning("threshold_logistic: export_sci_table 失败: {e$message}")
    )
  }

  lit <- .thl03_is_lit_profile(cfg)
  ix_lab <- if (exists("pipeline_index_display_name", mode = "function")) {
    pipeline_index_display_name(cfg, Index)
  } else {
    Index
  }
  fig_path <- NULL
  if (!isFALSE(bl_cfg$export_figure %||% TRUE)) {
    gg <- .thl03_make_plot(d, ycol, Index, tau, pw, covs, lit, ix_lab)
    fig_name <- as.character(bl_cfg$figure_filename %||% paste0("Figure_Threshold_", Index, ".pdf"))[1L]
    if (!grepl("\\.pdf$", fig_name, ignore.case = TRUE)) fig_name <- paste0(fig_name, ".pdf")
    if (exists(".pub_figure_filename", mode = "function")) {
      fig_name <- .pub_figure_filename(.inject_db_into_pub_label(fig_name, sanitize_for_file = TRUE))
    }
    fig_path <- file.path(fig_dir, fig_name)
    if (exists("pipeline_ggsave_pdf", mode = "function")) {
      pipeline_ggsave_pdf(fig_path, gg, width = if (lit) 6.5 else 7, height = 5, cfg = cfg)
    } else {
      ggplot2::ggsave(fig_path, plot = gg, width = 7, height = 5)
    }
    cli::cli_alert_success("Saved: {basename(fig_path)}")
    if (exists("mirror_pub_output_to_root", mode = "function")) {
      tryCatch(mirror_pub_output_to_root(ctx, fig_path), error = function(e) invisible(FALSE))
    }
  } else {
    cli::cli_alert_info("threshold_logistic: export_figure=FALSE，跳过阈值图（表仍导出）")
  }
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    tryCatch(mirror_pub_output_to_root(ctx, csv_path), error = function(e) invisible(FALSE))
  }

  ctx$results$threshold_logistic <- list(
    threshold = tau,
    method = method,
    or_below = or_lo$or,
    or_above = or_hi$or,
    p_below = or_lo$p,
    p_above = or_hi$p,
    p_lrt = p_lrt,
    n = n_total,
    events = n_evt,
    n_below = pw$n_lo,
    n_above = pw$n_hi,
    covariates = covs,
    table = tab,
    table_path = csv_path,
    figure = fig_path,
    lit_profile = lit
  )
  ctx$results$threshold_value <- tau
  cli::cli_alert_success(
    "threshold_logistic: {Index} threshold={signif(tau, 4)} method={method}"
  )
  ctx
}

register_block("threshold_logistic", block_threshold_logistic,
               "发病侧 threshold/piecewise logistic 表图")
