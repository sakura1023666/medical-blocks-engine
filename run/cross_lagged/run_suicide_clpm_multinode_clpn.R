###############################################################################
#  run_suicide_clpm_multinode_clpn.R
#  交叉滞后网络：条目级「拆开」成多节点，一张图很多圈（对齐参考 DN1–DN7 风格）
#  删除 focus 拆图；重写 Figure 4 + Table S8 + S1/S2（1000 boot）
###############################################################################

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
.study <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = file.path(.engine, ".superpowers/sdd/study_mirror")
)
.raw <- Sys.getenv(
  "CROSS_LAGGED_RAW_DIR",
  unset = file.path(.engine, ".superpowers/sdd/prep_raw")
)
.n_boot_edge <- as.integer(Sys.getenv("SUICIDE_CLPM_N_BOOT_EDGE", unset = "1000"))
.n_boot_case <- as.integer(Sys.getenv("SUICIDE_CLPM_N_BOOT_CASE", unset = "1000"))
.seed <- 40595747L

source(file.path(.engine, "R/clpn_node_label_db.R"), local = FALSE)
source(file.path(.engine, "R/clpn_network_plot.R"), local = FALSE)

.fig <- file.path(.study, "summary_result", "figure")
.tab <- file.path(.study, "summary_result", "table")
dir.create(.fig, recursive = TRUE, showWarnings = FALSE)
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)

.message <- function(...) cat(sprintf(...), "\n")

.load_one <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  get(ls(e)[1], envir = e)
}

.yn01 <- function(x) {
  x <- trimws(as.character(x))
  ifelse(x %in% c("Yes ", "Yes", "A", "是", "1"), 1,
         ifelse(x %in% c("No ", "No", "B", "否", "0"), 0, NA_real_))
}

.num <- function(x) suppressWarnings(as.numeric(as.character(x)))

# 出版短码/真名（写入 CSV 缓存用）
.hama_lab <- c(
  "Anxious mood", "Tension", "Fears", "Insomnia", "Intellectual",
  "Depressed mood", "Somatic muscular", "Somatic sensory", "Cardiovascular",
  "Respiratory", "Gastrointestinal", "Genitourinary", "Autonomic symptoms",
  "Behavior at interview"
)
.hamd_lab <- c(
  "Depressed mood", "Guilt", "Suicide", "Insomnia early", "Insomnia middle",
  "Insomnia late", "Work and activities", "Retardation", "Agitation",
  "Anxiety psychic", "Anxiety somatic", "GI somatic", "General somatic",
  "Genital symptoms", "Hypochondriasis", "Weight loss", "Insight"
)
.cssrs_lab <- c(
  "Wish to be dead", "Non-specific active ideation", "Active ideation any methods",
  "Ideation with some intent", "Ideation with plan"
)

# 增补映射库行到运行时 CSV（若缺）
.csvp <- file.path(.engine, "configs/clpn_node_label_db.csv")
.db <- utils::read.csv(.csvp, stringsAsFactors = FALSE)
.add_rows <- list()
for (i in seq_along(.hama_lab)) {
  stem <- paste0("HAMA", i)
  if (!stem %in% .db$stem)
    .add_rows[[length(.add_rows) + 1L]] <- data.frame(
      stem = stem, short_label = paste0("A", i), display_name = .hama_lab[[i]],
      group = "Mood", aliases = paste0("HAMA_index_", i, ";HAMA_1st_", i),
      stringsAsFactors = FALSE
    )
}
for (i in seq_along(.hamd_lab)) {
  stem <- paste0("HAMD", i)
  if (!stem %in% .db$stem)
    .add_rows[[length(.add_rows) + 1L]] <- data.frame(
      stem = stem, short_label = paste0("D", i), display_name = .hamd_lab[[i]],
      group = "Depression", aliases = paste0("HAMD_index_", i, ";HAMD_1st_", i),
      stringsAsFactors = FALSE
    )
}
for (i in seq_along(.cssrs_lab)) {
  stem <- paste0("CSSRS", i)
  if (!stem %in% .db$stem)
    .add_rows[[length(.add_rows) + 1L]] <- data.frame(
      stem = stem, short_label = paste0("S", i), display_name = .cssrs_lab[[i]],
      group = "Outcome", aliases = paste0("C_SSRS_Ideation_index_", i, ";C_SSRS_Ideation_1st_", i),
      stringsAsFactors = FALSE
    )
}
if (length(.add_rows)) {
  .db <- rbind(.db, do.call(rbind, .add_rows))
  utils::write.csv(.db, .csvp, row.names = FALSE)
  .message("Appended %d item stems to clpn_node_label_db.csv", length(.add_rows))
}
# refresh cache
if (exists(".clpn_db_cache", envir = .GlobalEnv)) {
  assign(".clpn_db_cache", NULL, envir = .GlobalEnv)
}

# 门诊分析 ID（六节点完整队列）
.dab <- local({
  e <- new.env(parent = emptyenv())
  load(file.path(.study, "data/harmonized/D04_outpatient_clpm_imputed.RData"), envir = e)
  e$dabiao
})
.ids <- as.character(.dab$ID)

.merge_scale <- function(path, id_keep, wave = c("index", "1st")) {
  wave <- match.arg(wave)
  df <- .load_one(path)
  df$新编号 <- trimws(as.character(df$新编号))
  df <- df[df$新编号 %in% id_keep, , drop = FALSE]
  df <- df[!duplicated(df$新编号), , drop = FALSE]
  df
}

.hama1 <- .merge_scale(file.path(.raw, "D07_HAMA1.RData"), .ids, "index")
.hama2 <- .merge_scale(file.path(.raw, "D07_HAMA2.RData"), .ids, "1st")
.hamd1 <- .merge_scale(file.path(.raw, "D08_HAMD1.RData"), .ids, "index")
.hamd2 <- .merge_scale(file.path(.raw, "D08_HAMD2.RData"), .ids, "1st")
.css1 <- .merge_scale(file.path(.raw, "D10_C_SSRS1.RData"), .ids, "index")
.css2 <- .merge_scale(file.path(.raw, "D10_C_SSRS2.RData"), .ids, "1st")

# 宽表：每个 stem 一对 T1_/T2_
.wide <- data.frame(ID = .ids, stringsAsFactors = FALSE)
for (i in 1:14) {
  stem <- paste0("HAMA", i)
  c1 <- paste0("HAMA_index_", i)
  c2 <- paste0("HAMA_1st_", i)
  .wide[[paste0("T1_", stem)]] <- .num(.hama1[[c1]][match(.ids, .hama1$新编号)])
  .wide[[paste0("T2_", stem)]] <- .num(.hama2[[c2]][match(.ids, .hama2$新编号)])
}
for (i in 1:17) {
  stem <- paste0("HAMD", i)
  c1 <- paste0("HAMD_index_", i)
  c2 <- paste0("HAMD_1st_", i)
  .wide[[paste0("T1_", stem)]] <- .num(.hamd1[[c1]][match(.ids, .hamd1$新编号)])
  .wide[[paste0("T2_", stem)]] <- .num(.hamd2[[c2]][match(.ids, .hamd2$新编号)])
}
for (i in 1:5) {
  stem <- paste0("CSSRS", i)
  c1 <- paste0("C_SSRS_Ideation_index_", i)
  c2 <- paste0("C_SSRS_Ideation_1st_", i)
  .wide[[paste0("T1_", stem)]] <- .yn01(.css1[[c1]][match(.ids, .css1$新编号)])
  .wide[[paste0("T2_", stem)]] <- .yn01(.css2[[c2]][match(.ids, .css2$新编号)])
}

.stems0 <- c(paste0("HAMA", 1:14), paste0("HAMD", 1:17), paste0("CSSRS", 1:5))
# 丢掉高缺失/无变异
.ok <- vapply(.stems0, function(s) {
  x1 <- .wide[[paste0("T1_", s)]]
  x2 <- .wide[[paste0("T2_", s)]]
  if (mean(is.na(x1)) > 0.5 || mean(is.na(x2)) > 0.5) return(FALSE)
  if (length(unique(stats::na.omit(x1))) < 2L) return(FALSE)
  if (length(unique(stats::na.omit(x2))) < 2L) return(FALSE)
  TRUE
}, logical(1))
.stems <- .stems0[.ok]
.message("CLPN nodes kept: %d / %d", length(.stems), length(.stems0))
.message("Dropped: %s", paste(.stems0[!.ok], collapse = ", "))

# 估计（主：cv；boot：固定 lambda）
.estimate_adj_cv <- function(df, stems, nfolds = 10L, alpha = 1) {
  k <- length(stems)
  t1 <- paste0("T1_", stems)
  t2 <- paste0("T2_", stems)
  adj <- matrix(0, k, k, dimnames = list(stems, stems))
  lambdas <- rep(NA_real_, k)
  X_all <- as.matrix(df[, t1, drop = FALSE])
  for (i in seq_len(k)) {
    y_var <- as.numeric(df[[t2[[i]]]])
    y_ok <- !is.na(y_var)
    if (sum(y_ok) < 40L) next
    pred_ok <- vapply(seq_len(k), function(j) {
      x <- X_all[y_ok, j]
      mean(is.na(x)) <= 0.5 && length(unique(stats::na.omit(x))) >= 2L
    }, logical(1))
    if (!any(pred_ok)) next
    valid <- y_ok & stats::complete.cases(X_all[, pred_ok, drop = FALSE], y_var)
    if (sum(valid) < 40L) next
    X <- X_all[valid, pred_ok, drop = FALSE]
    y <- as.numeric(y_var[valid])
    uv <- length(unique(y))
    fam <- if (uv == 2L) "binomial" else "gaussian"
    if (identical(fam, "gaussian")) {
      ysd <- stats::sd(y)
      if (is.finite(ysd) && ysd > 1e-12) y <- as.numeric(scale(y))
    }
    sd_ok <- apply(X, 2, function(col) {
      s <- stats::sd(col); is.finite(s) && s > 1e-12
    })
    if (!any(sd_ok)) next
    nf <- min(as.integer(nfolds), max(3L, floor(sum(valid) / 20)))
    cvfit <- tryCatch(
      glmnet::cv.glmnet(
        x = X[, sd_ok, drop = FALSE], y = y, nfolds = nf,
        family = fam, alpha = alpha, standardize = TRUE,
        nlambda = 40L, lambda.min.ratio = 0.05
      ),
      error = function(e) NULL
    )
    if (is.null(cvfit)) next
    lambdas[[i]] <- cvfit$lambda.min
    coef_sub <- as.numeric(stats::coef(cvfit, s = "lambda.min"))[-1]
    coef_vec <- rep(0, k)
    pred_idx <- which(pred_ok)[sd_ok]
    if (length(coef_sub) == length(pred_idx)) coef_vec[pred_idx] <- coef_sub
    coef_vec[abs(coef_vec) > 5] <- 0
    adj[, i] <- coef_vec
  }
  list(adj = adj, lambda = lambdas)
}

.estimate_adj_fixed <- function(df, stems, lambdas, alpha = 1) {
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
    if (sum(y_ok) < 40L) next
    pred_ok <- vapply(seq_len(k), function(j) {
      x <- X_all[y_ok, j]
      mean(is.na(x)) <= 0.5 && length(unique(stats::na.omit(x))) >= 2L
    }, logical(1))
    if (!any(pred_ok)) next
    valid <- y_ok & stats::complete.cases(X_all[, pred_ok, drop = FALSE], y_var)
    if (sum(valid) < 40L) next
    X <- X_all[valid, pred_ok, drop = FALSE]
    y <- as.numeric(y_var[valid])
    uv <- length(unique(y))
    fam <- if (uv == 2L) "binomial" else "gaussian"
    if (identical(fam, "gaussian")) {
      ysd <- stats::sd(y)
      if (is.finite(ysd) && ysd > 1e-12) y <- as.numeric(scale(y))
    }
    sd_ok <- apply(X, 2, function(col) {
      s <- stats::sd(col); is.finite(s) && s > 1e-12
    })
    if (!any(sd_ok)) next
    fit <- tryCatch(
      glmnet::glmnet(
        x = X[, sd_ok, drop = FALSE], y = y, alpha = alpha,
        lambda = lam, family = fam, standardize = TRUE
      ),
      error = function(e) NULL
    )
    if (is.null(fit)) next
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
  names(v) <- paste0(from, "->", to)
  v
}

.message("Estimating multi-node CLPN (n=%d, k=%d) ...", nrow(.wide), length(.stems))
.fit <- .estimate_adj_cv(.wide, .stems, alpha = 1)
.adj <- .fit$adj
.lambdas <- .fit$lambda
.message("Non-zero edges: %d", sum(.adj != 0))

.lab <- clpn_node_display(.stems, root = .engine, fallback = TRUE)
.adj_lab <- .adj
dimnames(.adj_lab) <- list(.lab, .lab)
utils::write.csv(.adj_lab, file.path(.tab, "Table S8-Outpatient. CLPN adjacency.csv"), row.names = TRUE)
utils::write.csv(.adj, file.path(.tab, "CLPN_adjacency_stems_Outpatient_items.csv"), row.names = TRUE)
saveRDS(.wide, file.path(.study, "data/harmonized/longitudinal_wide_clpn_items.RData"))

# 删掉旧的 3 节点 Fig4 / focus 拆图
.old4 <- list.files(.fig, pattern = "^Figure 4-.*CLPN", full.names = TRUE)
file.remove(.old4)
.message("Removed old Figure 4 files: %d", length(.old4))

# 新 Figure 4：多节点 spring（像参考图很多圈）
.out4 <- file.path(.fig, "Figure 4-Outpatient. CLPN network of HAMD HAMA CSSRS items.pdf")
clpn_plot_publication(
  adj = .adj, stems = .stems, outfile = .out4, title = "Outpatient",
  root = .engine, layout = "spring", drop_self_loops = TRUE, fade_weak_edges = TRUE
)
.message("Wrote %s", .out4)

# Ward：若有 ID 可做；否则跳过多节点（Exploratory 保留旧 S1/S2 可删 focus）
.old4w <- list.files(.fig, pattern = "^Figure 4-Ward.*focus", full.names = TRUE)
file.remove(.old4w)

# Bootstrap 1000（固定 lambda）
.message("Edge bootstrap %d ...", .n_boot_edge)
set.seed(.seed)
.sample_vec <- .edge_vec(.adj)
.n <- nrow(.wide)
.boot_edge <- matrix(NA_real_, .n_boot_edge, length(.sample_vec))
colnames(.boot_edge) <- names(.sample_vec)
.t0 <- proc.time()[[3]]
for (b in seq_len(.n_boot_edge)) {
  idx <- sample.int(.n, .n, replace = TRUE)
  ab <- .estimate_adj_fixed(.wide[idx, , drop = FALSE], .stems, .lambdas, alpha = 1)
  .boot_edge[b, ] <- .edge_vec(ab)
  if (b %% 100L == 0L)
    .message("  edge %d/%d (%.1fs)", b, .n_boot_edge, proc.time()[[3]] - .t0)
}
.edge_df <- data.frame(
  edge = names(.sample_vec),
  sample = as.numeric(.sample_vec),
  boot_mean = colMeans(.boot_edge, na.rm = TRUE),
  ci_lo = apply(.boot_edge, 2, stats::quantile, 0.025, na.rm = TRUE, names = FALSE),
  ci_hi = apply(.boot_edge, 2, stats::quantile, 0.975, na.rm = TRUE, names = FALSE),
  stringsAsFactors = FALSE
)
# 只画非零样本边，避免 S1 图爆炸
.edge_nz <- .edge_df[abs(.edge_df$sample) > 1e-8, , drop = FALSE]
utils::write.csv(.edge_df, file.path(.tab, "CLPN_edge_bootstrap_Outpatient.csv"), row.names = FALSE)

if (requireNamespace("ggplot2", quietly = TRUE) && nrow(.edge_nz)) {
  ed <- .edge_nz
  # 最多显示 |sample| top 40，否则图不可读
  if (nrow(ed) > 40L) {
    ed <- ed[order(-abs(ed$sample)), , drop = FALSE][seq_len(40L), , drop = FALSE]
  }
  ed$edge <- factor(ed$edge, levels = ed$edge[order(ed$sample)])
  p1 <- ggplot2::ggplot(ed, ggplot2::aes(y = .data$edge)) +
    ggplot2::geom_vline(xintercept = 0, linetype = 2, colour = "grey70") +
    ggplot2::geom_errorbarh(ggplot2::aes(xmin = .data$ci_lo, xmax = .data$ci_hi),
                            height = 0.2, colour = "grey55") +
    ggplot2::geom_point(ggplot2::aes(x = .data$sample), colour = "#2C7BB6", size = 1.8) +
    ggplot2::geom_point(ggplot2::aes(x = .data$boot_mean), colour = "#D7191C",
                        shape = 17, size = 1.8) +
    ggplot2::labs(
      title = "Figure S1-Outpatient. CLPN edge weight bootstrap",
      subtitle = sprintf("nBoots=%d; showing top |w| edges (k=%d nodes)", .n_boot_edge, length(.stems)),
      x = "Edge weight", y = NULL
    ) +
    ggplot2::theme_bw(base_size = 10)
  ggplot2::ggsave(
    file.path(.fig, "Figure S1-Outpatient. CLPN edge weight bootstrap.pdf"),
    p1, width = 10, height = max(5, 0.28 * nrow(ed) + 2)
  )
}

.message("Case-dropping bootstrap %d ...", .n_boot_case)
.props <- seq(0.95, 0.25, by = -0.05)
.rows <- list()
for (p in .props) {
  n_keep <- max(40L, as.integer(floor(.n * p)))
  cors <- numeric(.n_boot_case)
  for (b in seq_len(.n_boot_case)) {
    idx <- sample.int(.n, n_keep, replace = FALSE)
    ab <- .estimate_adj_fixed(.wide[idx, , drop = FALSE], .stems, .lambdas, alpha = 1)
    cors[[b]] <- suppressWarnings(stats::cor(
      .sample_vec, .edge_vec(ab), use = "pairwise.complete.obs"
    ))
  }
  cors <- cors[is.finite(cors)]
  .rows[[length(.rows) + 1L]] <- data.frame(
    sampled = p, mean_cor = mean(cors),
    lo = stats::quantile(cors, 0.025, names = FALSE),
    hi = stats::quantile(cors, 0.975, names = FALSE)
  )
  .message("  case-drop %.0f%% mean_cor=%.3f", 100 * p, mean(cors))
}
.stab <- do.call(rbind, .rows)
utils::write.csv(.stab, file.path(.tab, "CLPN_case_dropping_Outpatient.csv"), row.names = FALSE)
if (requireNamespace("ggplot2", quietly = TRUE)) {
  p2 <- ggplot2::ggplot(.stab, ggplot2::aes(x = .data$sampled * 100, y = .data$mean_cor)) +
    ggplot2::geom_ribbon(ggplot2::aes(ymin = .data$lo, ymax = .data$hi),
                         fill = "grey85", colour = NA) +
    ggplot2::geom_line(colour = "#2C7BB6", linewidth = 1) +
    ggplot2::geom_point(colour = "#2C7BB6", size = 2) +
    ggplot2::ylim(0, 1) +
    ggplot2::labs(
      title = "Figure S2-Outpatient. CLPN case-dropping stability",
      subtitle = sprintf("nBoots=%d; item-level network k=%d", .n_boot_case, length(.stems)),
      x = "Sampled cases (%)", y = "Average correlation with original edges"
    ) +
    ggplot2::theme_bw(base_size = 11)
  ggplot2::ggsave(
    file.path(.fig, "Figure S2-Outpatient. CLPN case-dropping stability.pdf"),
    p2, width = 8, height = 5
  )
}

saveRDS(
  list(
    stems = .stems, adj = .adj, lambdas = .lambdas,
    sample_edges = .sample_vec, boot_edge = .boot_edge, case_stability = .stab,
    n_boot_edge = .n_boot_edge, n_boot_case = .n_boot_case, seed = .seed,
    n = .n, note = "Item-level CLPN: HAMA1-14 + HAMD1-17 + CSSRS1-5"
  ),
  file.path(.tab, "CLPN_bootstrap_Outpatient.rds")
)

writeLines(c(
  "Figure 4 = ONE multi-node CLPN (items split as separate circles), NOT separate focus plots.",
  sprintf("Nodes: %d (HAMA items + HAMD items + CSSRS ideation items).", length(.stems)),
  sprintf("Bootstrap: n_boot_edge=%d n_boot_case=%d.", .n_boot_edge, .n_boot_case),
  "Legacy 3-node / focus-* Figure 4 files removed."
), file.path(.fig, "README_FigS1_S2_CLPN_bootstrap.txt"))

.message("DONE multinode CLPN")
