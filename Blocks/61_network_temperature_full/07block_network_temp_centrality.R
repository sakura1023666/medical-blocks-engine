###############################################################################
#  network_temp_centrality — GGM centrality / EI 汇总（与原文分析链衔接）
###############################################################################

block_network_temp_centrality <- function(ctx, ...) {
  ggm_dir <- (ctx$results$network_temp_ggm_fit %||% list())$output_dir
  if (is.null(ggm_dir) || !dir.exists(ggm_dir))
    stop("network_temp_centrality: 请先运行 network_temp_ggm_fit", call. = FALSE)

  ei_path <- file.path(ggm_dir, "Table_Network_EI.csv")
  edge_path <- file.path(ggm_dir, "Table_Network_Edges.csv")
  if (!file.exists(ei_path)) stop("network_temp_centrality: 缺少 EI 表", call. = FALSE)

  ei_df <- utils::read.csv(ei_path, stringsAsFactors = FALSE)
  edge_df <- if (file.exists(edge_path)) utils::read.csv(edge_path, stringsAsFactors = FALSE) else data.frame()

  if (nrow(edge_df)) {
    edge_df$abs_weight <- abs(edge_df$weight)
    nodes <- unique(c(edge_df$source, edge_df$target))
    strength <- vapply(nodes, function(n) {
      sum(edge_df$abs_weight[edge_df$source == n | edge_df$target == n], na.rm = TRUE)
    }, numeric(1))
    strength_df <- data.frame(node = nodes, strength = strength, stringsAsFactors = FALSE)
    ei_df <- merge(ei_df, strength_df, by = "node", all.x = TRUE)
  }

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(ei_df, file.path(out_tab, "Table_Network_Centrality_EI_Strength.csv"), row.names = FALSE)

  ctx$results$network_temp_centrality <- list(n_nodes = nrow(ei_df), table = ei_df)
  cli::cli_alert_success("网络 centrality / EI 汇总完成")
  ctx
}

register_block("network_temp_centrality", block_network_temp_centrality, "GGM centrality 汇总")
