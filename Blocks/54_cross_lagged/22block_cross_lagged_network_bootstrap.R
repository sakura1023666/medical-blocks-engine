###############################################################################
#  cross_lagged_network_bootstrap — CLPN 边权 Bootstrap CI + case-dropping 稳定性
#
#  对齐文献 Supplementary Figs. 25–26（同源 Step07：bootnet nBoots=1000）：
#    Figure S1 — nonparametric bootstrap 边权 + 95% CI（edgeCI）
#    Figure S2 — case-dropping 稳定性（edgeStability）
#
#  硬默认（后续项目一律对齐文献；出版图禁止 smoke 次数）：
#    n_boot_edge = 1000L, n_boot_case = 1000L, nfolds = 10L
#  依赖: glmnet；ggplot2。不强制 bootnet。
#  输入: ctx$data$longitudinal_wide(_clpn)；优先复用 ctx$results$cross_lagged_network$stems
#  配置: ctx$config$cross_lagged_network_bootstrap
#    n_boot_edge / n_boot_case / case_props / max_beta / min_n / seed / nfolds
#  register_block: "cross_lagged_network_bootstrap"
###############################################################################

#' 单次 CLPN 邻接（与 17block 同构：T1_* → T2_*，cv.glmnet）
.clpn_boot_estimate_adj <- function(df, stems, max_beta = 5, min_n = 30L, nfolds = 10L,
                                    alpha = NULL, gaussian_all = NULL) {
  k <- length(stems)
  if (k < 2L) return(matrix(0, 0, 0))
  t1 <- paste0("T1_", stems)
  t2 <- paste0("T2_", stems)
  for (nm in c(t1, t2)) {
    if (!nm %in% names(df)) return(matrix(0, k, k, dimnames = list(stems, stems)))
    df[[nm]] <- suppressWarnings(as.numeric(df[[nm]]))
  }
  adj <- matrix(0, nrow = k, ncol = k, dimnames = list(stems, stems))
  X_all <- as.matrix(df[, t1, drop = FALSE])
  max_na_rate <- 0.50
  for (i in seq_len(k)) {
    y_var <- df[[t2[[i]]]]
    y_ok <- !is.na(y_var)
    if (sum(y_ok) < min_n) next
    pred_ok <- vapply(seq_len(k), function(j) {
      x <- X_all[y_ok, j]
      if (mean(is.na(x)) > max_na_rate) return(FALSE)
      length(unique(stats::na.omit(x))) >= 2L
    }, logical(1))
    if (!any(pred_ok)) next
    valid <- y_ok & stats::complete.cases(X_all[, pred_ok, drop = FALSE], y_var)
    if (sum(valid) < min_n) next
    X <- X_all[valid, pred_ok, drop = FALSE]
    y <- y_var[valid]
    uv <- length(unique(y[!is.na(y)]))
    if (uv < 2L) next
    small_net <- k <= 12L
    alpha_used <- as.numeric(alpha %||% if (isTRUE(small_net)) 0.5 else 1)
    use_g <- isTRUE(gaussian_all %||% small_net)
    family_used <- if (isTRUE(use_g)) "gaussian" else if (uv == 2L) "binomial" else "gaussian"
    y <- as.numeric(y)
    if (identical(family_used, "gaussian")) {
      ysd <- stats::sd(y, na.rm = TRUE)
      if (is.finite(ysd) && ysd > 1e-12) y <- as.numeric(scale(y))
    }
    sd_ok <- apply(X, 2, function(col) {
      s <- stats::sd(col, na.rm = TRUE)
      is.finite(s) && s > 1e-12
    })
    if (!any(sd_ok)) next
    nf <- min(as.integer(nfolds), max(3L, floor(sum(valid) / 20)))
    tryCatch({
      cvfit <- glmnet::cv.glmnet(
        x = X[, sd_ok, drop = FALSE], y = y, nfolds = nf,
        family = family_used, alpha = alpha_used, standardize = TRUE,
        nlambda = 40L, lambda.min.ratio = if (isTRUE(small_net)) 0.001 else 0.05
      )
      coef_sub <- as.numeric(stats::coef(cvfit, s = "lambda.min"))[-1]
      coef_vec <- rep(0, k)
      pred_idx <- which(pred_ok)[sd_ok]
      if (length(coef_sub) == length(pred_idx)) coef_vec[pred_idx] <- coef_sub
      coef_vec[abs(coef_vec) > max_beta] <- 0
      adj[, i] <- coef_vec
    }, error = function(e) invisible(NULL))
  }
  adj
}

.clpn_boot_edge_vec <- function(adj) {
  if (is.null(adj) || !is.matrix(adj) || !length(adj)) return(numeric(0))
  as.numeric(adj)
}

.clpn_boot_edge_labels <- function(stems) {
  k <- length(stems)
  from <- rep(stems, times = k)
  to <- rep(stems, each = k)
  paste0(from, "→", to)
}

#' 边权准确性图（文献 / bootnet 风格）
.clpn_plot_edge_accuracy <- function(sample_vec, boot_mat, outfile,
                                     title = "edge") {
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("cross_lagged_network_bootstrap: 需要 ggplot2", call. = FALSE)
  ok <- is.finite(sample_vec)
  if (!any(ok)) return(invisible(NULL))
  sample_vec <- sample_vec[ok]
  boot_mat <- boot_mat[, ok, drop = FALSE]
  labs <- names(sample_vec)
  if (is.null(labs) || !length(labs)) labs <- as.character(seq_along(sample_vec))
  mean_b <- colMeans(boot_mat, na.rm = TRUE)
  lo <- apply(boot_mat, 2L, stats::quantile, probs = 0.025, na.rm = TRUE, names = FALSE)
  hi <- apply(boot_mat, 2L, stats::quantile, probs = 0.975, na.rm = TRUE, names = FALSE)
  ord <- order(sample_vec)
  d <- data.frame(
    id = factor(labs[ord], levels = labs[ord]),
    sample = sample_vec[ord],
    boot = mean_b[ord],
    lo = lo[ord],
    hi = hi[ord],
    stringsAsFactors = FALSE
  )
  p <- ggplot2::ggplot(d, ggplot2::aes(y = .data$id)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(xmin = .data$lo, xmax = .data$hi, group = 1L),
      fill = "grey85", colour = NA
    ) +
    ggplot2::geom_path(
      ggplot2::aes(x = .data$boot, group = 1L),
      colour = "grey35", linewidth = 0.35
    ) +
    ggplot2::geom_point(
      ggplot2::aes(x = .data$boot),
      colour = "grey35", size = 0.55
    ) +
    ggplot2::geom_path(
      ggplot2::aes(x = .data$sample, group = 1L),
      colour = "#E45756", linewidth = 0.85
    ) +
    ggplot2::geom_point(
      ggplot2::aes(x = .data$sample),
      colour = "#E45756", size = 0.85
    ) +
    ggplot2::facet_wrap(~ factor(title, levels = title)) +
    ggplot2::labs(x = NULL, y = NULL) +
    ggplot2::theme_bw(base_size = 11) +
    ggplot2::theme(
      axis.text.y = ggplot2::element_blank(),
      axis.ticks.y = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      strip.background = ggplot2::element_rect(fill = "grey80", colour = NA)
    )
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    outfile, p, width = 7.2, height = max(5.5, min(14, 0.035 * nrow(d) + 3)),
    device = if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else "pdf",
    limitsize = FALSE
  )
  invisible(outfile)
}

#' case-dropping 稳定性图（文献 / bootnet 风格）
.clpn_plot_case_stability <- function(stab_df, outfile) {
  if (!requireNamespace("ggplot2", quietly = TRUE))
    stop("cross_lagged_network_bootstrap: 需要 ggplot2", call. = FALSE)
  p <- ggplot2::ggplot(stab_df, ggplot2::aes(x = .data$sampled, y = .data$mean_cor)) +
    ggplot2::geom_ribbon(
      ggplot2::aes(ymin = .data$lo, ymax = .data$hi),
      fill = "#F8766D", alpha = 0.35, colour = NA
    ) +
    ggplot2::geom_hline(yintercept = 0, colour = "black", linewidth = 0.4) +
    ggplot2::geom_line(colour = "#F8766D", linewidth = 0.9) +
    ggplot2::geom_point(colour = "#F8766D", size = 2.2) +
    ggplot2::scale_x_continuous(
      breaks = sort(unique(stab_df$sampled), decreasing = TRUE),
      labels = function(x) paste0(round(100 * x), "%"),
      trans = "reverse"
    ) +
    ggplot2::coord_cartesian(ylim = c(-1, 1)) +
    ggplot2::labs(
      x = "Sampled cases",
      y = "Average correlation with original sample"
    ) +
    ggplot2::theme_bw(base_size = 12) +
    ggplot2::theme(
      legend.position = "none",
      panel.grid.minor = ggplot2::element_blank(),
      plot.title = ggplot2::element_text(size = 11)
    ) +
    ggplot2::ggtitle("type: edge")
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(
    outfile, p, width = 7.5, height = 5.2,
    device = if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else "pdf"
  )
  invisible(outfile)
}

block_cross_lagged_network_bootstrap <- function(ctx, ...) {
  if (!requireNamespace("glmnet", quietly = TRUE))
    stop("cross_lagged_network_bootstrap: 需要 glmnet", call. = FALSE)

  cfg <- ctx$config
  bl <- cfg$cross_lagged_network_bootstrap %||% list()
  net_bl <- cfg$cross_lagged_network %||% list()
  df <- ctx$data$longitudinal_wide_clpn %||% ctx$data$longitudinal_wide
  if (is.null(df) || !is.data.frame(df))
    stop("cross_lagged_network_bootstrap: 需要 longitudinal_wide", call. = FALSE)
  df <- as.data.frame(df)

  net_res <- ctx$results$cross_lagged_network
  stems <- net_res$stems
  if (is.null(stems) || !length(stems)) {
    # 回退：若未先跑 network，则要求显式 stems
    stems <- as.character(bl$stems %||% character(0))
  }
  if (!length(stems))
    stop("cross_lagged_network_bootstrap: 无 stems；请先跑 cross_lagged_network", call. = FALSE)

  max_beta <- as.numeric(bl$max_beta %||% net_bl$max_beta %||% 5)
  min_n <- as.integer(bl$min_n %||% net_bl$min_n %||% 30L)
  # 与文献 CLPN / 同源 Step07 一致：cv.glmnet nfolds=10；bootstrap nBoots=1000
  nfolds <- as.integer(bl$nfolds %||% 10L)
  n_boot_edge <- as.integer(bl$n_boot_edge %||% Sys.getenv("CROSS_LAGGED_BOOT_EDGE", "1000"))
  n_boot_case <- as.integer(bl$n_boot_case %||% Sys.getenv("CROSS_LAGGED_BOOT_CASE", "1000"))
  if (!is.finite(n_boot_edge) || n_boot_edge < 1L) n_boot_edge <- 1000L
  if (!is.finite(n_boot_case) || n_boot_case < 1L) n_boot_case <- 1000L
  case_props <- bl$case_props %||% seq(0.95, 0.25, by = -0.05)
  case_props <- as.numeric(case_props)
  seed <- as.integer(bl$seed %||% 40595747L)
  skip_case <- isTRUE(bl$skip_case)
  skip_edge <- isTRUE(bl$skip_edge)
  if (n_boot_edge < 1000L || n_boot_case < 1000L) {
    cli::cli_alert_warning(
      "CLPN bootstrap nBoots edge={n_boot_edge} case={n_boot_case} < 文献默认 1000；出版图请保持 1000"
    )
  }

  db <- as.character(cfg$project$database %||% "Cohort")[1L]
  out_dir <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  fig_dir <- file.path(cfg$project$output_dir %||% "Output", "Figures")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  n <- nrow(df)
  set.seed(seed)
  cli::cli_alert_info(
    "CLPN bootstrap [{db}]: n={n}, k={length(stems)}, edge_boots={n_boot_edge}, case_boots={n_boot_case}"
  )

  adj0 <- .clpn_boot_estimate_adj(df, stems, max_beta = max_beta, min_n = min_n, nfolds = nfolds)
  sample_vec <- .clpn_boot_edge_vec(adj0)
  elabs <- .clpn_boot_edge_labels(stems)
  names(sample_vec) <- elabs

  s1_path <- file.path(
    fig_dir,
    paste0("Figure S1-", db, ". CLPN edge weight bootstrap.pdf")
  )
  s2_path <- file.path(
    fig_dir,
    paste0("Figure S2-", db, ". CLPN case-dropping stability.pdf")
  )

  boot_edge <- NULL
  if (!isTRUE(skip_edge) && n_boot_edge > 0L && length(sample_vec)) {
    boot_edge <- matrix(NA_real_, nrow = n_boot_edge, ncol = length(sample_vec))
    colnames(boot_edge) <- elabs
    for (b in seq_len(n_boot_edge)) {
      idx <- sample.int(n, n, replace = TRUE)
      adj_b <- .clpn_boot_estimate_adj(
        df[idx, , drop = FALSE], stems,
        max_beta = max_beta, min_n = min_n, nfolds = nfolds
      )
      boot_edge[b, ] <- .clpn_boot_edge_vec(adj_b)
      if (b %% 50L == 0L || b == n_boot_edge)
        cli::cli_alert_info("  edge bootstrap {b}/{n_boot_edge}")
    }
    .clpn_plot_edge_accuracy(sample_vec, boot_edge, s1_path, title = "edge")
    utils::write.csv(
      data.frame(
        edge = elabs,
        sample = sample_vec,
        boot_mean = colMeans(boot_edge, na.rm = TRUE),
        ci_lo = apply(boot_edge, 2L, stats::quantile, 0.025, na.rm = TRUE, names = FALSE),
        ci_hi = apply(boot_edge, 2L, stats::quantile, 0.975, na.rm = TRUE, names = FALSE),
        stringsAsFactors = FALSE
      ),
      file.path(out_dir, paste0("CLPN_edge_bootstrap_", db, ".csv")),
      row.names = FALSE
    )
    cli::cli_alert_success("Figure S1 已写: {s1_path}")
  } else {
    s1_path <- NULL
  }

  stab_df <- NULL
  if (!isTRUE(skip_case) && n_boot_case > 0L && length(sample_vec) && any(sample_vec != 0)) {
    rows <- list()
    for (p in case_props) {
      n_keep <- max(min_n, as.integer(floor(n * p)))
      cors <- numeric(n_boot_case)
      for (b in seq_len(n_boot_case)) {
        idx <- sample.int(n, n_keep, replace = FALSE)
        adj_b <- .clpn_boot_estimate_adj(
          df[idx, , drop = FALSE], stems,
          max_beta = max_beta, min_n = min_n, nfolds = nfolds
        )
        v <- .clpn_boot_edge_vec(adj_b)
        cors[[b]] <- suppressWarnings(stats::cor(sample_vec, v, use = "pairwise.complete.obs"))
      }
      cors <- cors[is.finite(cors)]
      rows[[length(rows) + 1L]] <- data.frame(
        sampled = p,
        mean_cor = if (length(cors)) mean(cors) else NA_real_,
        lo = if (length(cors)) stats::quantile(cors, 0.025, names = FALSE) else NA_real_,
        hi = if (length(cors)) stats::quantile(cors, 0.975, names = FALSE) else NA_real_,
        type = "edge",
        stringsAsFactors = FALSE
      )
      cli::cli_alert_info("  case-drop sampled={round(100*p)}%  mean_cor={round(mean(cors), 3)}")
    }
    stab_df <- do.call(rbind, rows)
    .clpn_plot_case_stability(stab_df, s2_path)
    utils::write.csv(
      stab_df,
      file.path(out_dir, paste0("CLPN_case_dropping_", db, ".csv")),
      row.names = FALSE
    )
    cli::cli_alert_success("Figure S2 已写: {s2_path}")
  } else {
    s2_path <- NULL
  }

  rds_path <- file.path(out_dir, paste0("CLPN_bootstrap_", db, ".rds"))
  saveRDS(
    list(
      stems = stems, sample_edges = sample_vec, boot_edge = boot_edge,
      case_stability = stab_df, n_boot_edge = n_boot_edge, n_boot_case = n_boot_case,
      seed = seed
    ),
    rds_path
  )

  ctx$results$cross_lagged_network_bootstrap <- list(
    figure_s1 = s1_path, figure_s2 = s2_path, rds = rds_path,
    stems = stems, n_boot_edge = n_boot_edge, n_boot_case = n_boot_case
  )
  ctx
}

register_block(
  "cross_lagged_network_bootstrap",
  block_cross_lagged_network_bootstrap,
  "CLPN 边权 Bootstrap CI + case-dropping（Figure S1/S2）"
)
