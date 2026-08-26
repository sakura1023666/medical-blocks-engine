# tests/test_cross_lagged_network_node_stems.R
# Smoke: force node_stems = condition1–7 → 7x7 adjacency

root <- "/mnt/e/01block/01Block-new-Final"
source(file.path(root, "R/utils.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/17block_cross_lagged_network.R"))

set.seed(1)
n <- 80L
stems <- paste0("condition", 1:7)
wide <- data.frame(ID = seq_len(n))
for (s in stems) {
  wide[[paste0("T1_", s)]] <- rbinom(n, 1, 0.4)
  wide[[paste0("T2_", s)]] <- rbinom(n, 1, 0.4)
}
# decoy FI items that must be ignored when node_stems is set
wide$T1_dressa <- rbinom(n, 1, 0.2)
wide$T2_dressa <- rbinom(n, 1, 0.2)

ctx <- list(
  data = list(longitudinal_wide = wide),
  results = list(),
  config = list(
    project = list(output_dir = tempfile("clpn_")),
    cross_lagged_network = list(
      node_stems = stems,
      fi_items_only = FALSE,
      include_outcome = FALSE,
      include_lipids = FALSE,
      max_nodes = 7L,
      min_n = 20L
    )
  )
)
dir.create(file.path(ctx$config$project$output_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ctx$config$project$output_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)

ctx2 <- block_cross_lagged_network(ctx)
adj <- ctx2$results$cross_lagged_network$adjacency
if (is.null(adj)) {
  # fallback: find matrix in results
  adj <- ctx2$results$clpn_adj %||% ctx2$results$network_adj
}
# If block writes only files, load first csv in Tables
if (is.null(adj)) {
  fs <- list.files(file.path(ctx$config$project$output_dir, "Tables"), pattern = "csv$", full.names = TRUE)
  stopifnot(length(fs) >= 1L)
  adj <- as.matrix(read.csv(fs[[1]], row.names = 1, check.names = FALSE))
}
stopifnot(nrow(adj) == 7L, ncol(adj) == 7L)
rn <- gsub("^T[12]_", "", rownames(adj))
stopifnot(!any(grepl("dressa", rn, ignore.case = TRUE)))
cat("OK 7x7 node_stems network\n")

# keep_forced: 无变异 condition 仍占节点
wide$T1_condition2 <- 1
wide$T2_condition2 <- 1
ctx$config$cross_lagged_network$keep_forced_nodes <- TRUE
ctx$config$project$output_dir <- tempfile("clpn2_")
dir.create(file.path(ctx$config$project$output_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ctx$config$project$output_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
ctx3 <- block_cross_lagged_network(ctx)
adj3 <- ctx3$results$cross_lagged_network$adjacency
stopifnot(nrow(adj3) == 7L)
cat("OK keep_forced_nodes 7x7 with constant condition2\n")
