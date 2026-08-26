###############################################################################
#  complex_network_bootnet — bootnet + EBICglasso + 稳定性 bootstrap（文献主分析）
###############################################################################

block_complex_network_bootnet <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_packages.R"), local = FALSE)
  literature_ensure_packages("network")

  bl <- ctx$config$complex_network %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("complex_network_bootnet: 无数据", call. = FALSE)

  sym <- grep("^(CESD|GAD)[0-9]+$", names(data), value = TRUE)
  if (length(sym) < 3L) sym <- grep("^(CESD|GAD)", names(data), value = TRUE)
  mat <- as.data.frame(lapply(data[sym], function(x) as.numeric(x)))
  mat <- mat[stats::complete.cases(mat), , drop = FALSE]
  if (nrow(mat) < 30L) stop("complex_network_bootnet: 有效样本 < 30", call. = FALSE)

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Network")
  out_fig <- file.path(ctx$config$project$output_dir %||% "Output", "Figures")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)

  n_boot <- as.integer(bl$bootnet_n_boot %||% 50L)
  lambda_min <- as.numeric(bl$ebicglasso_lambda_min_ratio %||% 0.1)

  net <- bootnet::estimateNetwork(
    mat, default = "EBICglasso", corMethod = "cor_auto",
    lambda.min.ratio = lambda_min,
    nlambda = as.integer(bl$ebicglasso_nlambda %||% 50L)
  )

  adj <- tryCatch(bootnet::getWmat(net), error = function(e) NULL)
  if (!is.null(adj) && any(adj != 0) && requireNamespace("qgraph", quietly = TRUE)) {
    cent <- tryCatch(qgraph::centrality(adj), error = function(e) NULL)
    if (!is.null(cent)) {
      cent_df <- as.data.frame(cent)
      cent_df$node <- rownames(cent_df)
      utils::write.csv(cent_df, file.path(out_tab, "Table_Network_Centrality_bootnet.csv"), row.names = FALSE)
    }
    if (requireNamespace("networktools", quietly = TRUE)) {
      comm <- ifelse(grepl("^CESD", rownames(adj)), "Depression", "Anxiety")
      bridge <- tryCatch(networktools::bridge(adj, communities = comm), error = function(e) NULL)
      if (!is.null(bridge) && !is.null(bridge$bridgeStrength)) {
        br_df <- data.frame(node = names(bridge$bridgeStrength), bridge_ei = as.numeric(bridge$bridgeStrength))
        utils::write.csv(br_df, file.path(out_tab, "Table_Network_Bridge_EI_bootnet.csv"), row.names = FALSE)
      }
    }
    boot_stab <- tryCatch(
      bootnet::bootnet(net, nBoots = n_boot, type = "nonparametric",
                       statistics = c("strength", "betweenness", "closeness")),
      error = function(e) NULL
    )
    if (!is.null(boot_stab)) saveRDS(boot_stab, file.path(out_tab, "bootnet_stability.rds"))
    grDevices::pdf(file.path(out_fig, "Figure_Network_bootnet.pdf"), width = 10, height = 8)
    qgraph::qgraph(adj, labels = sym, layout = "spring", theme = "colorblind")
    grDevices::dev.off()
    if (!is.null(boot_stab)) {
      grDevices::pdf(file.path(out_fig, "Figure_Centrality_bootnet.pdf"), width = 10, height = 6)
      plot(boot_stab, statistics = "strength")
      grDevices::dev.off()
    }
  } else {
    cli::cli_alert_warning("bootnet 空网络或无边权，已跳过 bootstrap 图")
  }

  ctx$results$complex_network_bootnet <- list(net = net, n_boot = n_boot, n_nodes = length(sym))
  cli::cli_alert_success("bootnet EBICglasso 完成（n={nrow(mat)}）")
  ctx
}

register_block("complex_network_bootnet", block_complex_network_bootnet, "bootnet EBICglasso 网络")
