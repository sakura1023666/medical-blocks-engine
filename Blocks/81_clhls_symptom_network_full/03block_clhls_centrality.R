###############################################################################
#  clhls_centrality — Strength / Closeness / Betweenness / Expected Influence
#  register_block: "clhls_centrality"
#  算法对齐既往 Step03；写出 Fig 2 + Table 2 前四列
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


block_clhls_centrality <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  clhls_net_require_pkgs()
  dirs <- clhls_net_out_dirs(ctx)
  e <- clhls_net_load_core(dirs, "EBIC")
  W <- e$net$graph
  nm <- e$L$Label
  items <- e$L$Items

  G <- qgraph::qgraph(W, layout = "spring", DoNotPlot = TRUE)
  c <- qgraph::centrality(G)
  Strength <- rowSums(abs(W))
  Closeness <- c$Closeness
  Betweenness <- c$Betweenness
  EI <- if (!is.null(c$ExpectedInfluence)) c$ExpectedInfluence else rowSums(W)

  tab <- data.frame(
    Label = nm, Items = items,
    Strength = round(as.numeric(Strength), 3),
    Closeness = round(as.numeric(Closeness), 3),
    Betweenness = round(as.numeric(Betweenness), 3),
    ExpectedInfluence = round(as.numeric(EI), 3),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  clhls_net_write_table(tab, file.path(dirs$tab, "Table 2. Descriptive statistics of centrality indices"))

  clhls_net_save_pdf(file.path(dirs$fig, "Figure 2. Centrality measures.pdf"), function() {
    # print=FALSE：centralityPlot 默认会自己往当前设备画一页，再 print 就会变成两页
    p <- qgraph::centralityPlot(
      G, scale = "raw", standardized = FALSE, print = FALSE,
      include = c("Strength", "Closeness", "Betweenness", "ExpectedInfluence"),
      labels = nm
    )
    print(p + ggplot2::xlab("Centrality Value (Raw)"))
  }, width = 12, height = 7)

  ctx$results$clhls_centrality <- list(table = tab)
  cli::cli_alert_success("中心性完成; Strength 最高: {nm[which.max(Strength)]}")
  ctx
}

register_block("clhls_centrality", block_clhls_centrality, "CLHLS 症状网络中心性")
