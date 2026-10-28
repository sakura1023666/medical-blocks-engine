###############################################################################
#  clhls_weighted — Barrat + Onnela 加权指标写入 Table 2
#  register_block: "clhls_weighted"
#  算法对齐既往 Step04（igraph transitivity barrat / weighted）
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


block_clhls_weighted <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  clhls_net_require_pkgs()
  dirs <- clhls_net_out_dirs(ctx)
  e <- clhls_net_load_core(dirs, "EBIC")
  W <- e$net$graph
  nm <- e$L$Label

  stem <- file.path(dirs$tab, "Table 2. Descriptive statistics of centrality indices")
  xlsx <- paste0(stem, ".xlsx")
  if (!file.exists(xlsx)) stop("缺少 Table 2，请先跑 clhls_centrality", call. = FALSE)
  tab <- openxlsx::read.xlsx(xlsx, startRow = 2)

  g <- igraph::graph_from_adjacency_matrix(abs(W), mode = "undirected", weighted = TRUE, diag = FALSE)
  barrat <- igraph::transitivity(g, type = "barrat", weights = igraph::E(g)$weight)
  onnela <- igraph::transitivity(g, type = "weighted", weights = igraph::E(g)$weight)

  tab$Barrat <- round(barrat[match(tab$Label, nm)], 3)
  tab$Onnela <- round(onnela[match(tab$Label, nm)], 3)
  clhls_net_write_table(tab, stem)

  ctx$results$clhls_weighted <- list(table = tab)
  cli::cli_alert_success("加权指标已写入 Table 2")
  ctx
}

register_block("clhls_weighted", block_clhls_weighted, "CLHLS Barrat/Onnela 加权")
