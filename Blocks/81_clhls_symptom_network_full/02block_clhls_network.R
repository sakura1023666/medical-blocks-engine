###############################################################################
#  clhls_network — pcor + EBICglasso(γ=0.5) 双网络 + 节点 R² + Fig 1
#  register_block: "clhls_network"
#  算法对齐既往 Step02：Pearson → nearPD → pcor / EBICglasso；mgm R²
#  写出: rdata/core_EBIC_CLHLS.RData, Figures/Figure 1..., Tables/edgeweight_*.csv
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


block_clhls_network <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  clhls_net_require_pkgs()
  cfg <- clhls_net_cfg(ctx)
  dirs <- clhls_net_out_dirs(ctx)
  df <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(df)) stop("clhls_network: 无数据，请先跑 clhls_symptom_ingest", call. = FALSE)

  dat <- clhls_net_cov_mat(df, cfg$nodes, cfg$covariates)
  if (length(cfg$covariates)) {
    cli::cli_alert_info("协变量残差化: {paste(cfg$covariates, collapse=', ')} (n={nrow(dat)})")
  }
  items <- unname(cfg$items)
  labels <- cfg$nodes
  groups <- cfg$groups
  short <- cfg$short
  r2 <- clhls_net_pred_r2(dat)

  comm <- rep(NA_character_, length(labels))
  for (g in names(groups)) comm[groups[[g]]] <- g
  L <- list(Label = labels, Items = items, N = nrow(dat), Community = comm)

  cli::cli_alert_info(
    "相关矩阵: {cfg$cor_method} (use={cfg$cor_use})"
  )
  net_pcor <- clhls_net_fit_pcor(dat, method = cfg$cor_method, use = cfg$cor_use)
  net_ebic <- clhls_net_fit_ebic(
    dat, cfg$ebic_gamma, method = cfg$cor_method, use = cfg$cor_use
  )

  for (m in c("pcor", "EBIC")) {
    net <- if (m == "pcor") net_pcor else net_ebic
    save(L, net, r2, dat, file = file.path(dirs$rdata, sprintf("core_%s_CLHLS.RData", m)))
    ew <- as.data.frame(round(net$graph, 3), check.names = FALSE)
    rownames(ew) <- colnames(ew) <- labels
    ew <- cbind(Node = rownames(ew), ew, stringsAsFactors = FALSE)
    clhls_net_write_table(ew, file.path(dirs$tab, sprintf("edgeweight_%s_CLHLS", m)))
  }

  # Fig 1：主文用 EBIC。全偏相关矩阵只进表，不出 Figure S0
  clhls_net_save_pdf(file.path(dirs$fig, paste0(cfg$figure1_stem, ".pdf")), function() {
    qgraph::qgraph(
      net_ebic$graph, layout = "spring", groups = groups, palette = "colorblind",
      posCol = "#003D7A", negCol = "#9B1B1B", negDashed = TRUE, fade = FALSE,
      esize = 16, pie = r2, vsize = 7,
      labels = short, nodeNames = items, legend = TRUE, legend.cex = 0.45,
      label.cex = 0.9, mar = c(2, 2, 2, 2)
    )
  })

  pred_tab <- data.frame(
    Label = labels, Items = items,
    R2 = round(as.numeric(r2[labels]), 3),
    stringsAsFactors = FALSE
  )
  clhls_net_write_table(pred_tab, file.path(dirs$tab, "Table_node_predictability_R2"))

  ctx$results$clhls_network <- list(
    n = L$N, n_edges_ebic = sum(net_ebic$graph != 0) / 2,
    mean_r2 = mean(r2, na.rm = TRUE), output_dir = dirs$root
  )
  cli::cli_alert_success("网络构建完成: N={L$N}, EBIC 非零边={ctx$results$clhls_network$n_edges_ebic}")
  ctx
}

register_block("clhls_network", block_clhls_network, "CLHLS 症状网络 pcor+EBIC")
