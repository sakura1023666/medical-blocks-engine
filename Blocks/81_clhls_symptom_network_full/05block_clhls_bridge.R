###############################################################################
#  clhls_bridge — Bridge Strength / EI / Closeness（Depression ↔ Anxiety）
#  register_block: "clhls_bridge"
#  算法对齐既往 Step05：networktools::bridge
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


block_clhls_bridge <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  clhls_net_require_pkgs()
  cfg <- clhls_net_cfg(ctx)
  dirs <- clhls_net_out_dirs(ctx)
  e <- clhls_net_load_core(dirs, "EBIC")
  W <- e$net$graph
  nm <- e$L$Label
  items <- e$L$Items
  comm <- e$L$Community
  if (is.null(comm)) {
    comm <- rep(NA_character_, length(nm))
    for (g in names(cfg$groups)) comm[cfg$groups[[g]]] <- g
  }

  G <- qgraph::qgraph(W, layout = "spring", DoNotPlot = TRUE)
  br <- networktools::bridge(G, communities = comm, useCommunities = "all")

  bstr <- as.numeric(br$`Bridge Strength`)
  be1 <- as.numeric(br$`Bridge Expected Influence (1-step)`)
  bcl <- as.numeric(br$`Bridge Closeness`)
  btw <- as.numeric(br$`Bridge Betweenness`)

  # 图与表用原始桥接值（文献 plot(bridge, zscore=FALSE)），不再做 z 标准化
  bridge_tab <- data.frame(
    Label = nm, Items = items, Community = comm,
    Bridge_Strength = round(bstr, 3),
    Bridge_ExpectedInfluence = round(be1, 3),
    Bridge_Closeness = round(bcl, 3),
    Bridge_Betweenness = round(btw, 3),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  clhls_net_write_table(bridge_tab, file.path(dirs$tab, "Table_Bridge_centrality"))

  # 自绘桥图（三面板），彻底避开 networktools 默认 x 轴把三个指标名串在一行导致的标题重叠
  br_df <- data.frame(
    Node = nm,
    Community = comm,
    Strength = bstr,
    ExpectedInfluence = be1,
    Betweenness = btw,
    stringsAsFactors = FALSE
  )
  br_df$Node <- factor(br_df$Node, levels = nm)
  long <- reshape(
    br_df[, c("Node", "Community", "Strength", "ExpectedInfluence", "Betweenness")],
    direction = "long", varying = c("Strength", "ExpectedInfluence", "Betweenness"),
    v.names = "Value", timevar = "Metric", times = c("Bridge Strength", "Bridge Expected Influence", "Bridge Betweenness"),
    idvar = "Node"
  )
  long$Metric <- factor(long$Metric,
                        levels = c("Bridge Strength", "Bridge Expected Influence", "Bridge Betweenness"))
  p <- ggplot2::ggplot(long, ggplot2::aes(x = Node, y = Value, fill = Community)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::facet_wrap(~ Metric, scales = "free_x", ncol = 3) +
    ggplot2::scale_fill_manual(values = c("#0B6ECC", "#E69F00")) +
    ggplot2::geom_hline(yintercept = 0, color = "grey40") +
    ggplot2::labs(x = NULL, y = "Value (raw)", fill = "Community") +
    ggplot2::theme_minimal(base_size = 12) +
    ggplot2::theme(
      axis.text.x = ggplot2::element_text(angle = 45, hjust = 1),
      strip.text = ggplot2::element_text(face = "bold")
    )
  clhls_net_save_pdf(file.path(dirs$fig, "Figure 3. Bridge symptom analysis.pdf"), function() {
    print(p)
  }, width = 14, height = 5.5)

  ctx$results$clhls_bridge <- list(table = bridge_tab)
  cli::cli_alert_success("桥症状分析完成")
  ctx
}

register_block("clhls_bridge", block_clhls_bridge, "CLHLS 桥症状分析")
