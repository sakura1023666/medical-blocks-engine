###############################################################################
#  run_suicide_clpm_align_hip_summary.R
#  对齐髋部 summary_result 命名 + CLPN（HAMD/HAMA/CSSRS 拆开）+ 1000 boot
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
.study <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = file.path(.engine, ".superpowers/sdd/study_mirror")
)
.n_boot_edge <- as.integer(Sys.getenv("SUICIDE_CLPM_N_BOOT_EDGE", unset = "1000"))
.n_boot_case <- as.integer(Sys.getenv("SUICIDE_CLPM_N_BOOT_CASE", unset = "1000"))
.seed <- 40595747L
.stems <- c("HAMD", "HAMA", "CSSRS")

source(file.path(.engine, "R/clpn_node_label_db.R"), local = FALSE)
source(file.path(.engine, "R/clpn_network_plot.R"), local = FALSE)

.out_fig <- file.path(.study, "summary_result", "figure")
.out_tab <- file.path(.study, "summary_result", "table")
dir.create(.out_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(.out_tab, recursive = TRUE, showWarnings = FALSE)

.message <- function(...) cat(sprintf(...), "\n")

.load_dabiao <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  e$dabiao
}

.wide_from_dabiao <- function(d) {
  data.frame(
    ID = d$ID,
    T1_HAMD = as.numeric(d$HAMD_Index),
    T2_HAMD = as.numeric(d$HAMD_1st),
    T1_HAMA = as.numeric(d$HAMA_Index),
    T2_HAMA = as.numeric(d$HAMA_1st),
    T1_CSSRS = as.numeric(d$CSSRS_Index),
    T2_CSSRS = as.numeric(d$CSSRS_1st),
    stringsAsFactors = FALSE
  )
}

# 主估计：cv.glmnet；返回 list(adj, lambda)
.estimate_adj_cv <- function(df, stems, nfolds = 10L, alpha = 0.5) {
  k <- length(stems)
  t1 <- paste0("T1_", stems)
  t2 <- paste0("T2_", stems)
  adj <- matrix(0, k, k, dimnames = list(stems, stems))
  lambdas <- rep(NA_real_, k)
  X_all <- as.matrix(df[, t1, drop = FALSE])
  for (i in seq_len(k)) {
    y_var <- as.numeric(df[[t2[[i]]]])
    y_ok <- !is.na(y_var)
    if (sum(y_ok) < 30L) next
    pred_ok <- vapply(seq_len(k), function(j) {
      x <- X_all[y_ok, j]
      mean(is.na(x)) <= 0.5 && length(unique(stats::na.omit(x))) >= 2L
    }, logical(1))
    if (!any(pred_ok)) next
    valid <- y_ok & stats::complete.cases(X_all[, pred_ok, drop = FALSE], y_var)
    if (sum(valid) < 30L) next
    X <- X_all[valid, pred_ok, drop = FALSE]
    y <- as.numeric(y_var[valid])
    ysd <- stats::sd(y)
    if (is.finite(ysd) && ysd > 1e-12) y <- as.numeric(scale(y))
    sd_ok <- apply(X, 2, function(col) {
      s <- stats::sd(col); is.finite(s) && s > 1e-12
    })
    if (!any(sd_ok)) next
    nf <- min(as.integer(nfolds), max(3L, floor(sum(valid) / 20)))
    cvfit <- glmnet::cv.glmnet(
      x = X[, sd_ok, drop = FALSE], y = y, nfolds = nf,
      family = "gaussian", alpha = alpha, standardize = TRUE,
      nlambda = 40L, lambda.min.ratio = 0.001
    )
    lambdas[[i]] <- cvfit$lambda.min
    coef_sub <- as.numeric(stats::coef(cvfit, s = "lambda.min"))[-1]
    coef_vec <- rep(0, k)
    pred_idx <- which(pred_ok)[sd_ok]
    coef_vec[pred_idx] <- coef_sub
    coef_vec[abs(coef_vec) > 5] <- 0
    adj[, i] <- coef_vec
  }
  list(adj = adj, lambda = lambdas)
}

# bootstrap 复用：固定 lambda 的 glmnet（快）
.estimate_adj_fixed <- function(df, stems, lambdas, alpha = 0.5) {
  k <- length(stems)
  t1 <- paste0("T1_", stems)
  t2 <- paste0("T2_", stems)
  adj <- matrix(0, k, k, dimnames = list(stems, stems))
  X_all <- as.matrix(df[, t1, drop = FALSE])
  for (i in seq_len(k)) {
    lam <- lambdas[[i]]
    if (!is.finite(lam)) next
    y_var <- as.numeric(df[[t2[[i]]]])
    y_ok <- !is.na(y_var)
    if (sum(y_ok) < 30L) next
    pred_ok <- vapply(seq_len(k), function(j) {
      x <- X_all[y_ok, j]
      mean(is.na(x)) <= 0.5 && length(unique(stats::na.omit(x))) >= 2L
    }, logical(1))
    if (!any(pred_ok)) next
    valid <- y_ok & stats::complete.cases(X_all[, pred_ok, drop = FALSE], y_var)
    if (sum(valid) < 30L) next
    X <- X_all[valid, pred_ok, drop = FALSE]
    y <- as.numeric(y_var[valid])
    ysd <- stats::sd(y)
    if (is.finite(ysd) && ysd > 1e-12) y <- as.numeric(scale(y))
    sd_ok <- apply(X, 2, function(col) {
      s <- stats::sd(col); is.finite(s) && s > 1e-12
    })
    if (!any(sd_ok)) next
    fit <- glmnet::glmnet(
      x = X[, sd_ok, drop = FALSE], y = y, alpha = alpha,
      lambda = lam, family = "gaussian", standardize = TRUE
    )
    coef_sub <- as.numeric(stats::coef(fit, s = lam))[-1]
    coef_vec <- rep(0, k)
    pred_idx <- which(pred_ok)[sd_ok]
    if (length(coef_sub) == length(pred_idx)) coef_vec[pred_idx] <- coef_sub
    coef_vec[abs(coef_vec) > 5] <- 0
    adj[, i] <- coef_vec
  }
  adj
}

.edge_vec <- function(adj) {
  stems <- rownames(adj)
  k <- length(stems)
  from <- rep(stems, times = k)
  to <- rep(stems, each = k)
  v <- as.numeric(adj)
  names(v) <- paste0(from, "\u2192", to)
  v
}

.plot_one <- function(adj, stems, outfile, title) {
  W <- adj
  dimnames(W) <- list(stems, stems)
  clpn_plot_publication(
    adj = W, stems = stems, outfile = outfile, title = title,
    root = .engine, layout = "circle", drop_self_loops = FALSE,
    fade_weak_edges = FALSE
  )
}

.ego_adj <- function(adj, stems, focus) {
  W <- adj
  dimnames(W) <- list(stems, stems)
  keep <- matrix(FALSE, nrow(W), ncol(W), dimnames = dimnames(W))
  keep[focus, ] <- TRUE
  keep[, focus] <- TRUE
  W[!keep] <- 0
  W
}

.copy_named <- function(src, dest) {
  if (!file.exists(src)) return(invisible(FALSE))
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  file.copy(src, dest, overwrite = TRUE)
}

.run_cohort <- function(key, rdata, rdata_fb, do_boot = TRUE) {
  .message("==== %s ====", key)
  rp <- if (file.exists(rdata)) rdata else rdata_fb
  if (!file.exists(rp)) {
    .message("skip %s: missing data", key)
    return(invisible(NULL))
  }
  d <- .load_dabiao(rp)
  wide <- .wide_from_dabiao(d)
  fit0 <- .estimate_adj_cv(wide, .stems)
  adj <- fit0$adj
  lambdas <- fit0$lambda
  lab <- clpn_node_display(.stems, root = .engine, fallback = TRUE)
  adj_lab <- adj
  dimnames(adj_lab) <- list(lab, lab)

  utils::write.csv(adj_lab, file.path(.out_tab, sprintf("Table S8-%s. CLPN adjacency.csv", key)),
                   row.names = TRUE)
  utils::write.csv(adj, file.path(.out_tab, sprintf("CLPN_adjacency_stems_%s.csv", key)),
                   row.names = TRUE)

  fig4 <- file.path(.out_fig, sprintf("Figure 4-%s. CLPN network of HAMD HAMA CSSRS.pdf", key))
  .plot_one(adj, .stems, fig4, title = key)

  focus_map <- c(
    HAMD = "HAMD depression",
    HAMA = "HAMA anxiety",
    CSSRS = "C-SSRS ideation"
  )
  for (foc in names(focus_map)) {
    fout <- file.path(.out_fig, sprintf("Figure 4-%s. CLPN network focus %s.pdf", key, foc))
    .plot_one(.ego_adj(adj, .stems, foc), .stems, fout,
              title = paste0(key, " · ", focus_map[[foc]]))
  }

  if (!isTRUE(do_boot)) return(invisible(adj))

  sample_vec <- .edge_vec(adj)
  set.seed(.seed)
  n <- nrow(wide)
  .message("edge bootstrap n=%d ...", .n_boot_edge)
  boot_edge <- matrix(NA_real_, .n_boot_edge, length(sample_vec))
  colnames(boot_edge) <- names(sample_vec)
  t0 <- proc.time()[[3]]
  for (b in seq_len(.n_boot_edge)) {
    idx <- sample.int(n, n, replace = TRUE)
    ab <- .estimate_adj_fixed(wide[idx, , drop = FALSE], .stems, lambdas)
    boot_edge[b, ] <- .edge_vec(ab)
    if (b %% 100L == 0L) {
      .message("  edge %d/%d (%.1fs)", b, .n_boot_edge, proc.time()[[3]] - t0)
    }
  }
  edge_df <- data.frame(
    edge = names(sample_vec),
    sample = as.numeric(sample_vec),
    boot_mean = colMeans(boot_edge, na.rm = TRUE),
    ci_lo = apply(boot_edge, 2, stats::quantile, 0.025, na.rm = TRUE, names = FALSE),
    ci_hi = apply(boot_edge, 2, stats::quantile, 0.975, na.rm = TRUE, names = FALSE),
    stringsAsFactors = FALSE
  )
  utils::write.csv(edge_df, file.path(.out_tab, sprintf("CLPN_edge_bootstrap_%s.csv", key)),
                   row.names = FALSE)

  if (requireNamespace("ggplot2", quietly = TRUE)) {
    ed <- edge_df
    ed$edge <- factor(ed$edge, levels = ed$edge[order(ed$sample)])
    p1 <- ggplot2::ggplot(ed, ggplot2::aes(y = .data$edge)) +
      ggplot2::geom_vline(xintercept = 0, linetype = 2, colour = "grey70") +
      ggplot2::geom_errorbarh(
        ggplot2::aes(xmin = .data$ci_lo, xmax = .data$ci_hi),
        height = 0.2, colour = "grey55"
      ) +
      ggplot2::geom_point(ggplot2::aes(x = .data$sample), colour = "#2C7BB6", size = 2) +
      ggplot2::geom_point(ggplot2::aes(x = .data$boot_mean), colour = "#D7191C",
                          shape = 17, size = 2) +
      ggplot2::labs(
        title = sprintf("Figure S1-%s. CLPN edge weight bootstrap", key),
        subtitle = sprintf("nBoots=%d; blue=sample, red=boot mean, grey=95%% CI", .n_boot_edge),
        x = "Edge weight", y = NULL
      ) +
      ggplot2::theme_bw(base_size = 11)
    ggplot2::ggsave(
      file.path(.out_fig, sprintf("Figure S1-%s. CLPN edge weight bootstrap.pdf", key)),
      p1, width = 9, height = max(4.5, 0.32 * nrow(ed) + 2)
    )
  }

  .message("case-dropping bootstrap n=%d ...", .n_boot_case)
  props <- seq(0.95, 0.25, by = -0.05)
  rows <- list()
  for (p in props) {
    n_keep <- max(30L, as.integer(floor(n * p)))
    cors <- numeric(.n_boot_case)
    for (b in seq_len(.n_boot_case)) {
      idx <- sample.int(n, n_keep, replace = FALSE)
      ab <- .estimate_adj_fixed(wide[idx, , drop = FALSE], .stems, lambdas)
      cors[[b]] <- suppressWarnings(stats::cor(sample_vec, .edge_vec(ab),
                                               use = "pairwise.complete.obs"))
    }
    cors <- cors[is.finite(cors)]
    rows[[length(rows) + 1L]] <- data.frame(
      sampled = p,
      mean_cor = mean(cors),
      lo = stats::quantile(cors, 0.025, names = FALSE),
      hi = stats::quantile(cors, 0.975, names = FALSE),
      stringsAsFactors = FALSE
    )
    .message("  case-drop %.0f%% mean_cor=%.3f", 100 * p, mean(cors))
  }
  stab <- do.call(rbind, rows)
  utils::write.csv(stab, file.path(.out_tab, sprintf("CLPN_case_dropping_%s.csv", key)),
                   row.names = FALSE)
  if (requireNamespace("ggplot2", quietly = TRUE)) {
    p2 <- ggplot2::ggplot(stab, ggplot2::aes(x = .data$sampled * 100, y = .data$mean_cor)) +
      ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lo, ymax = .data$hi),
                           fill = "grey85", colour = NA) +
      ggplot2::geom_line(colour = "#2C7BB6", linewidth = 1) +
      ggplot2::geom_point(colour = "#2C7BB6", size = 2) +
      ggplot2::ylim(0, 1) +
      ggplot2::labs(
        title = sprintf("Figure S2-%s. CLPN case-dropping stability", key),
        subtitle = sprintf("nBoots=%d per proportion", .n_boot_case),
        x = "Sampled cases (%)", y = "Average correlation with original edges"
      ) +
      ggplot2::theme_bw(base_size = 11)
    ggplot2::ggsave(
      file.path(.out_fig, sprintf("Figure S2-%s. CLPN case-dropping stability.pdf", key)),
      p2, width = 8, height = 5
    )
  }

  saveRDS(
    list(adj = adj, lambdas = lambdas, sample_edges = sample_vec,
         boot_edge = boot_edge, case_stability = stab,
         n_boot_edge = .n_boot_edge, n_boot_case = .n_boot_case, seed = .seed),
    file.path(.out_tab, sprintf("CLPN_bootstrap_%s.rds", key))
  )
  invisible(adj)
}

# 主队列 + 病房
.run_cohort(
  "Outpatient",
  file.path(.study, "data/harmonized/D04_outpatient_clpm_imputed.RData"),
  file.path(.study, "data/harmonized/D04_outpatient_clpm.RData"),
  do_boot = TRUE
)
.run_cohort(
  "Ward",
  file.path(.study, "data/harmonized/D04_ward_clpm_imputed.RData"),
  file.path(.study, "data/harmonized/D04_ward_clpm.RData"),
  do_boot = TRUE
)

# 髋部风格重命名既有产物
.message("==== rename legacy outputs ====")
.copy_named(
  file.path(.out_fig, "pdf/Figure 1. Outpatient attrition flowchart.pdf"),
  file.path(.out_fig, "Figure 1-Outpatient. Longitudinal inclusion exclusion flowchart.pdf")
)
.copy_named(
  file.path(.out_fig, "pdf/Figure 2. CLPM path diagram.pdf"),
  file.path(.out_fig, "Figure S3-Outpatient. Cross-lagged path diagram of HAMD HAMA CSSRS.pdf")
)
.tab_map <- list(
  "Table1_baseline.xlsx" =
    "Table 1-Outpatient. Baseline characteristics of suicide ideation CLPM.xlsx",
  "Table1_baseline.csv" =
    "Table 1-Outpatient. Baseline characteristics of suicide ideation CLPM.csv",
  "Table2_CLPM_paths.xlsx" =
    "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.xlsx",
  "Table2_CLPM_paths.csv" =
    "Table 2-Outpatient. Cross-lagged path analysis HAMD HAMA CSSRS.csv",
  "TableS1_imputation_note.xlsx" =
    "Table S1-Outpatient. Baseline characteristics before and after multiple imputation.xlsx",
  "TableS1_imputation_note.csv" =
    "Table S1-Outpatient. Baseline characteristics before and after multiple imputation.csv",
  "TableS2_node_correlation.xlsx" =
    "Table S6. Correlation regression HAMD HAMA CSSRS.xlsx",
  "TableS2_node_correlation.csv" =
    "Table S6. Correlation regression HAMD HAMA CSSRS.csv",
  "TableS3_ward_CLPM_paths.xlsx" =
    "Table 2-Ward. Exploratory cross-lagged path analysis HAMD HAMA CSSRS.xlsx",
  "TableS3_ward_CLPM_paths.csv" =
    "Table 2-Ward. Exploratory cross-lagged path analysis HAMD HAMA CSSRS.csv"
)
for (nm in names(.tab_map)) {
  .copy_named(file.path(.out_tab, nm), file.path(.out_tab, .tab_map[[nm]]))
}
.copy_named(
  file.path(.study, "covariates/uv_table.csv"),
  file.path(.out_tab, "Table S3-Outpatient. Univariate Regression Analysis.csv")
)
.copy_named(
  file.path(.study, "covariates/vif_screen.csv"),
  file.path(.out_tab, "Table S4-Outpatient. Multicollinearity Analysis (VIF, univariate p 0.1 screen).csv")
)

writeLines(c(
  "Suicide CLPM summary_result — aligned to hip fracture cross-lagged naming.",
  "Figure 4: CLPN with HAMD/HAMA/CSSRS as separate nodes (+ focus splits).",
  sprintf("Figure S1/S2: n_boot_edge=%d n_boot_case=%d seed=%d", .n_boot_edge, .n_boot_case, .seed),
  "N/A (frailty multi-DB only): Fig2 RCS, Fig3 forest, FigS4/S5, FigS11, TableS5/S7, S9-S17.1.",
  "Main = Outpatient; Ward = Exploratory."
), file.path(.out_fig, "README_FigS1_S2_CLPN_bootstrap.txt"))

writeLines(
  "See figure/README_FigS1_S2_CLPN_bootstrap.txt",
  file.path(.out_tab, "README_summary_slots.txt")
)

.message("DONE -> %s", file.path(.study, "summary_result"))
