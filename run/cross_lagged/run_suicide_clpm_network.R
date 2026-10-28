#!/usr/bin/env Rscript
# Supplementary CLPN for the outpatient suicide study, same three figures as
# C01_network_out_ELSA: network PDF, edge bootstrap CI, case-dropping stability.
# Nodes are the item content of the three scales: HAMD-17 items, HAMA-14 items,
# and the five C-SSRS ideation items. Covariates are the step04 Model2 set and
# are adjusted, not drawn. This does not replace Table 2.
#
#   CROSS_LAGGED_STUDY_ROOT=... Rscript run/cross_lagged/run_suicide_clpm_network.R

suppressPackageStartupMessages({
  library(glmnet)
  library(qgraph)
  library(ggplot2)
})

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")
if (!nzchar(study_root)) stop("Set CROSS_LAGGED_STUDY_ROOT", call. = FALSE)
study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)

hamd_names <- c(
  "Depressed mood", "Feelings of guilt", "Suicide", "Insomnia, early",
  "Insomnia, middle", "Insomnia, late", "Work and activities", "Retardation",
  "Agitation", "Anxiety, psychic", "Anxiety, somatic", "Somatic, gastrointestinal",
  "Somatic, general", "Genital symptoms", "Hypochondriasis", "Loss of weight", "Insight"
)
hama_names <- c(
  "Anxious mood", "Tension", "Fears", "Insomnia", "Intellectual", "Depressed mood",
  "Somatic, muscular", "Somatic, sensory", "Cardiovascular", "Respiratory",
  "Gastrointestinal", "Genitourinary", "Autonomic", "Behavior at interview"
)
css_names <- c(
  "Wish to be dead", "Suicidal thoughts", "Method", "Intent", "Plan"
)
stems <- c(paste0("H", 1:17), paste0("A", 1:14), paste0("S", 1:5))
item_names <- c(hamd_names, hama_names, css_names)
names(item_names) <- stems
groups <- c(rep("HAMD-17", 17), rep("HAMA-14", 14), rep("C-SSRS", 5))
names(groups) <- stems
n_boot <- 1000L
case_n_boot <- 200L
case_props <- seq(0.95, 0.25, by = -0.05)
seed <- 40595747L
n_cores <- min(8L, parallel::detectCores(logical = TRUE))
# Display only. Full weights stay in the CSV.
show_min <- 0.05

out_dir <- file.path(study_root, "C01_network_out_Outpatient_items")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

e <- new.env(parent = emptyenv())
load(file.path(study_root, "step02_imputation/dabiao.RData"), envir = e)
df <- e$dabiao
m2 <- trimws(readLines(file.path(study_root, "step04_univariate_vif/Model2Factors.txt"), warn = FALSE))
m2 <- m2[nzchar(m2)]

.as01 <- function(x) {
  if (is.numeric(x)) return(suppressWarnings(as.numeric(x)))
  xc <- trimws(as.character(x))
  ifelse(xc %in% c("1", "Yes", "yes", "YES", "A", "是"), 1,
         ifelse(xc %in% c("0", "No", "no", "NO", "B", "否"), 0, NA_real_))
}
.load_raw <- function(file) {
  ee <- new.env(parent = emptyenv())
  load(file.path(study_root, "data/RDATA/RDATA/01RawData", file), envir = ee)
  as.data.frame(get(ls(ee)[1L], envir = ee))
}
id <- df$ID
hamd_i <- .load_raw("D08_HAMD1.RData")
hamd_f <- .load_raw("D08_HAMD2.RData")
hama_i <- .load_raw("D07_HAMA1.RData")
hama_f <- .load_raw("D07_HAMA2.RData")
css_i <- .load_raw("D10_C_SSRS1.RData")
css_f <- .load_raw("D10_C_SSRS2.RData")
.pull <- function(raw, cols, binary = FALSE) {
  hit <- match(id, raw[["新编号"]])
  if (anyNA(hit)) stop("Unmatched ID while joining ", cols[1L], call. = FALSE)
  out <- raw[hit, cols, drop = FALSE]
  if (isTRUE(binary)) {
    as.data.frame(lapply(out, .as01))
  } else {
    as.data.frame(lapply(out, function(z) suppressWarnings(as.numeric(z))))
  }
}
nodes_i <- cbind(
  .pull(hamd_i, paste0("HAMD_index_", 1:17)),
  .pull(hama_i, paste0("HAMA_index_", 1:14)),
  .pull(css_i, paste0("C_SSRS_Ideation_index_", 1:5), binary = TRUE)
)
nodes_f <- cbind(
  .pull(hamd_f, paste0("HAMD_1st_", 1:17)),
  .pull(hama_f, paste0("HAMA_1st_", 1:14)),
  .pull(css_f, paste0("C_SSRS_Ideation_1st_", 1:5), binary = TRUE)
)
names(nodes_i) <- names(nodes_f) <- stems
# C-SSRS items 3-5 are not asked when item 2 is No. Those blanks are No.
.fill_skip <- function(blk) {
  gate <- blk[["S2"]]
  for (s in c("S3", "S4", "S5")) {
    blk[[s]][is.na(blk[[s]]) & !is.na(gate) & gate == 0] <- 0
  }
  blk
}
nodes_i <- .fill_skip(nodes_i)
nodes_f <- .fill_skip(nodes_f)
miss <- setdiff(m2, names(df))
if (length(miss)) stop("Model2 columns absent: ", paste(miss, collapse = ", "), call. = FALSE)

cov_df <- df[, m2, drop = FALSE]
for (v in names(cov_df)) {
  if (is.character(cov_df[[v]])) cov_df[[v]] <- factor(cov_df[[v]])
}
mm <- stats::model.matrix(~ 0 + ., data = cov_df)
ok <- stats::complete.cases(nodes_i) & stats::complete.cases(nodes_f) & stats::complete.cases(mm)
message("[network] item complete ", sum(ok), " of ", nrow(df))
nodes_i <- nodes_i[ok, , drop = FALSE]
nodes_f <- nodes_f[ok, , drop = FALSE]
mm <- mm[ok, , drop = FALSE]
# z-score each item on the analysis sample
nodes_i[] <- lapply(nodes_i, function(z) as.numeric(scale(z)))
nodes_f[] <- lapply(nodes_f, function(z) as.numeric(scale(z)))
utils::write.csv(
  data.frame(node = stems, scale = groups, item = unname(item_names[stems]), stringsAsFactors = FALSE),
  file.path(out_dir, "item_dictionary.csv"),
  row.names = FALSE
)
mat <- cbind(as.matrix(nodes_i), as.matrix(nodes_f), mm)
storage.mode(mat) <- "double"
k <- length(stems)
n_cov <- ncol(mm)
n <- nrow(mat)
message("[network] N=", n, " nodes=", k, " covariate columns=", n_cov, " cores=", n_cores)

.clpn_adj <- function(mat, k, n_cov) {
  stopifnot(ncol(mat) == (2L * k + n_cov))
  x_idx <- c(seq_len(k), if (n_cov > 0L) (2L * k + seq_len(n_cov)) else integer(0))
  adj <- matrix(0, nrow = k, ncol = k)
  for (i in seq_len(k)) {
    y <- mat[, k + i]
    if (length(unique(y[is.finite(y)])) < 2L) next
    x <- mat[, x_idx, drop = FALSE]
    keep_x <- apply(x, 2L, function(z) length(unique(z[is.finite(z)])) > 1L)
    if (!any(keep_x)) next
    fit <- tryCatch(
      glmnet::cv.glmnet(
        x = x[, keep_x, drop = FALSE], y = y, nfolds = 10L,
        family = "gaussian", alpha = 1, standardize = TRUE
      ),
      error = function(e) NULL
    )
    if (is.null(fit)) next
    cf <- as.numeric(stats::coef(fit, s = "lambda.min"))[-1L]
    full_cf <- rep(0, length(x_idx))
    full_cf[keep_x] <- cf
    adj[, i] <- full_cf[seq_len(k)]
  }
  adj
}

message("[network] fitting full-sample LASSO")
adj <- .clpn_adj(mat, k, n_cov)
colnames(adj) <- rownames(adj) <- stems
utils::write.csv(adj, file.path(out_dir, "edgeWeight_Outpatient.csv"), row.names = TRUE)

.plot_network <- function(adj, outfile) {
  show <- adj
  diag(show) <- 0
  show[abs(show) < show_min] <- 0
  edge_colors <- ifelse(show > 0, "#6095ce", "#e87d72")
  edge_colors[show == 0] <- NA
  grp <- list(
    "HAMD-17" = which(unname(groups[rownames(show)]) == "HAMD-17"),
    "HAMA-14" = which(unname(groups[rownames(show)]) == "HAMA-14"),
    "C-SSRS" = which(unname(groups[rownames(show)]) == "C-SSRS")
  )
  grDevices::pdf(outfile, width = 14, height = 10)
  on.exit(grDevices::dev.off(), add = TRUE)
  qgraph::qgraph(
    show,
    groups = grp,
    layout = "spring",
    labels = rownames(show),
    nodeNames = unname(item_names[rownames(show)]),
    color = c("HAMD-17" = "#5B8FA8", "HAMA-14" = "#E07A5F", "C-SSRS" = "#3D5A40"),
    edge.color = edge_colors,
    legend = TRUE,
    legend.cex = 0.38,
    title = "Outpatient",
    title.cex = 1.2,
    directed = TRUE,
    vsize = 6,
    label.cex = 0.65,
    layout.par = list(repulse.rad = 5),
    mar = c(3, 3, 3, 3)
  )
}

pdf_net <- file.path(out_dir, "network_Outpatient.pdf")
.plot_network(adj, pdf_net)
message("[network] wrote ", pdf_net)

sample_vec <- as.numeric(adj)
elabs <- paste0(rep(stems, times = k), "->", rep(stems, each = k))
names(sample_vec) <- elabs

.one_boot <- function(seed_i, n_keep = NULL) {
  set.seed(seed_i)
  idx <- if (is.null(n_keep)) {
    sample.int(n, n, replace = TRUE)
  } else {
    sample.int(n, n_keep, replace = FALSE)
  }
  as.numeric(.clpn_adj(mat[idx, , drop = FALSE], k, n_cov))
}

message("[network] edge bootstrap ", n_boot)
set.seed(seed)
boot_edge <- parallel::mclapply(
  seq_len(n_boot),
  function(b) .one_boot(seed + b),
  mc.cores = n_cores, mc.set.seed = FALSE
)
boot_edge <- do.call(rbind, boot_edge)
colnames(boot_edge) <- elabs
edge_ci <- data.frame(
  edge = elabs,
  sample = sample_vec,
  boot_mean = colMeans(boot_edge, na.rm = TRUE),
  ci_lo = apply(boot_edge, 2L, stats::quantile, 0.025, na.rm = TRUE, names = FALSE),
  ci_hi = apply(boot_edge, 2L, stats::quantile, 0.975, na.rm = TRUE, names = FALSE),
  stringsAsFactors = FALSE
)
utils::write.csv(edge_ci, file.path(out_dir, "edgeCI_Outpatient.csv"), row.names = FALSE)

ord <- order(sample_vec)
d <- data.frame(
  id = factor(elabs[ord], levels = elabs[ord]),
  sample = sample_vec[ord],
  boot = edge_ci$boot_mean[ord],
  lo = edge_ci$ci_lo[ord],
  hi = edge_ci$ci_hi[ord],
  stringsAsFactors = FALSE
)
p_ci <- ggplot2::ggplot(d, ggplot2::aes(y = .data$id)) +
  ggplot2::geom_ribbon(
    ggplot2::aes(xmin = .data$lo, xmax = .data$hi, group = 1L),
    fill = "grey85", colour = NA
  ) +
  ggplot2::geom_path(ggplot2::aes(x = .data$boot, group = 1L), colour = "grey35", linewidth = 0.35) +
  ggplot2::geom_point(ggplot2::aes(x = .data$boot), colour = "grey35", size = 1.4) +
  ggplot2::geom_path(ggplot2::aes(x = .data$sample, group = 1L), colour = "#E45756", linewidth = 0.7) +
  ggplot2::geom_point(ggplot2::aes(x = .data$sample), colour = "#E45756", size = 1.8) +
  ggplot2::geom_vline(xintercept = 0, linewidth = 0.3) +
  ggplot2::labs(x = NULL, y = NULL, title = "edge") +
  ggplot2::theme_bw(base_size = 12) +
  ggplot2::theme(
    axis.text.y = ggplot2::element_blank(),
    axis.ticks.y = ggplot2::element_blank(),
    panel.grid.minor = ggplot2::element_blank()
  )
ggplot2::ggsave(file.path(out_dir, "edgeCI_Outpatient.pdf"), p_ci, width = 8, height = 9, device = "pdf")
message("[network] wrote edgeCI")

message("[network] case-dropping")
rows <- list()
for (p in case_props) {
  n_keep <- max(30L, as.integer(floor(n * p)))
  cors <- parallel::mclapply(seq_len(case_n_boot), function(b) {
    vec <- .one_boot(seed + 100000L + as.integer(round(p * 1000)) * n_boot + b, n_keep = n_keep)
    suppressWarnings(stats::cor(sample_vec, vec, use = "pairwise.complete.obs"))
  }, mc.cores = n_cores, mc.set.seed = FALSE)
  cors <- as.numeric(unlist(cors))
  cors <- cors[is.finite(cors)]
  rows[[length(rows) + 1L]] <- data.frame(
    sampled = p,
    mean_cor = mean(cors),
    lo = stats::quantile(cors, 0.025, names = FALSE),
    hi = stats::quantile(cors, 0.975, names = FALSE),
    type = "edge",
    stringsAsFactors = FALSE
  )
  message(sprintf("  sampled %d%%  mean cor %.3f", as.integer(round(100 * p)), mean(cors)))
}
stab <- do.call(rbind, rows)
utils::write.csv(stab, file.path(out_dir, "edgeStability_Outpatient.csv"), row.names = FALSE)
p_st <- ggplot2::ggplot(stab, ggplot2::aes(x = .data$sampled, y = .data$mean_cor)) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = .data$lo, ymax = .data$hi),
    fill = "#F8766D", alpha = 0.35, colour = NA
  ) +
  ggplot2::geom_hline(yintercept = 0, colour = "black", linewidth = 0.4) +
  ggplot2::geom_line(colour = "#F8766D", linewidth = 0.9) +
  ggplot2::geom_point(colour = "#F8766D", size = 2.2) +
  ggplot2::scale_x_continuous(
    breaks = sort(unique(stab$sampled), decreasing = TRUE),
    labels = function(x) paste0(round(100 * x), "%"),
    trans = "reverse"
  ) +
  ggplot2::coord_cartesian(ylim = c(-1, 1)) +
  ggplot2::labs(
    x = "Sampled cases",
    y = "Average correlation with original sample",
    title = "type: edge"
  ) +
  ggplot2::theme_bw(base_size = 12) +
  ggplot2::theme(panel.grid.minor = ggplot2::element_blank())
ggplot2::ggsave(file.path(out_dir, "edgeStability_Outpatient.pdf"), p_st, width = 8, height = 8, device = "pdf")

utils::write.csv(data.frame(
  db = "Outpatient", n = n, k = k,   n_boot = n_boot, case_n_boot = case_n_boot, seed = seed,
  covs = paste(m2, collapse = ";"),
  note = "Item-level LASSO CLPN. H1-H17 HAMD-17, A1-A14 HAMA-14, S1-S5 C-SSRS ideation. Nodes z-scored. Network figure omits the diagonal and edges with absolute weight below 0.05. Covariates adjusted, not drawn.",
  stringsAsFactors = FALSE
), file.path(out_dir, "run_meta.csv"), row.names = FALSE)
message("[network] DONE ", out_dir)
print(round(adj, 3))
