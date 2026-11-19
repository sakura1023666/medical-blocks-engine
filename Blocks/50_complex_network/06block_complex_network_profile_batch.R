###############################################################################
#  complex_network_profile_batch — 按 LPA 剖面分层估计心理网络（薄封装）
#
#  register_block: "complex_network_profile_batch"
#  方法目录: Blocks/50_complex_network/
#  复用: bootnet/qgraph；算法对齐 81/50 既有网络块
#
#  config$complex_network_profile_batch = list(
#    class_col = "LPA_class",
#    nodes = c(...),
#    communities = list(...),   # 可选
#    min_n = 80L,
#    gamma = 0.5,
#    n_boots = 1000L,
#    include_overall = TRUE
#  )
###############################################################################

block_complex_network_profile_batch <- function(ctx, ...) {
  cfg <- ctx$config
  bl <- cfg$complex_network_profile_batch %||% cfg$complex_network %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("complex_network_profile_batch: 无数据", call. = FALSE)

  class_col <- as.character(bl$class_col %||% "LPA_class")[1L]
  nodes <- as.character(bl$nodes %||% character(0))
  nodes <- nodes[nodes %in% names(data)]
  if (length(nodes) < 3L) stop("complex_network_profile_batch: nodes < 3", call. = FALSE)
  min_n <- as.integer(bl$min_n %||% 80L)
  gamma <- as.numeric(bl$gamma %||% 0.5)
  n_boots <- as.integer(bl$n_boots %||% 200L)
  env_b <- Sys.getenv("SSD_NET_BOOTS", unset = "")
  if (nzchar(env_b)) n_boots <- as.integer(env_b)

  need <- c("bootnet", "qgraph")
  miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]
  if (length(miss)) stop("需要包: ", paste(miss, collapse = ", "), call. = FALSE)

  out_tab <- file.path(ctx$output_dir %||% ".", "Tables", "Network")
  out_fig <- file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  dir.create(out_fig, recursive = TRUE, showWarnings = FALSE)

  .fit_one <- function(df, tag) {
    mat <- as.data.frame(lapply(df[nodes], function(z) suppressWarnings(as.numeric(z))))
    mat <- mat[stats::complete.cases(mat), , drop = FALSE]
    if (nrow(mat) < min_n) {
      cli::cli_alert_warning("{tag}: n={nrow(mat)} < min_n={min_n}，降级跳过正式网络")
      return(list(tag = tag, n = nrow(mat), skipped = TRUE))
    }
    net <- bootnet::estimateNetwork(
      mat, default = "EBICglasso", corMethod = "cor_auto", tuning = gamma
    )
    adj <- tryCatch({
      if (!is.null(net$graph) && is.matrix(net$graph)) net$graph
      else if (exists("getWmat", where = asNamespace("bootnet"), mode = "function")) {
        bootnet::getWmat(net)
      } else NULL
    }, error = function(e) NULL)
    if (is.null(adj) || !is.matrix(adj)) {
      # 回退：用 glasso 直接估精度矩阵
      if (requireNamespace("qgraph", quietly = TRUE)) {
        adj <- tryCatch(
          qgraph::EBICglasso(stats::cor(mat, use = "pairwise.complete.obs"),
                             n = nrow(mat), gamma = gamma),
          error = function(e) NULL
        )
      }
    }
    fig_path <- file.path(out_fig, paste0("Figure_Network_", tag, ".pdf"))
    grDevices::pdf(fig_path, width = 8, height = 8)
    ok_plot <- FALSE
    if (!is.null(adj) && is.matrix(adj) && nrow(adj) >= 2L) {
      colnames(adj) <- rownames(adj) <- nodes[seq_len(nrow(adj))]
      tryCatch({
        qgraph::qgraph(
          adj, labels = colnames(adj), layout = "spring",
          theme = "colorblind", title = paste0("Network: ", tag, " (n=", nrow(mat), ")")
        )
        ok_plot <- TRUE
      }, error = function(e) {
        cli::cli_alert_warning("{tag}: qgraph 失败: {e$message}")
      })
    }
    if (!ok_plot) {
      plot.new()
      text(0.5, 0.5, paste0("Network plot unavailable: ", tag))
    }
    grDevices::dev.off()
    cent <- NULL
    if (!is.null(adj) && is.matrix(adj) && requireNamespace("qgraph", quietly = TRUE)) {
      cent <- tryCatch(qgraph::centrality_auto(adj)$node.centrality, error = function(e) {
        tryCatch(as.data.frame(qgraph::centrality(adj)), error = function(e2) NULL)
      })
    }
    cs <- NA_real_
    if (n_boots >= 20L) {
      boot_case <- tryCatch(
        bootnet::bootnet(net, nBoots = n_boots, type = "case", nCores = 1L),
        error = function(e) NULL
      )
      if (!is.null(boot_case)) {
        cs <- tryCatch(as.numeric(bootnet::corStability(boot_case)), error = function(e) NA_real_)
      }
    }
    list(tag = tag, n = nrow(mat), skipped = FALSE, centrality = cent, cs = cs, adj = adj)
  }

  jobs <- list()
  if (isTRUE(bl$include_overall %||% TRUE)) {
    jobs[["Overall"]] <- data
  }
  if (class_col %in% names(data)) {
    lv <- sort(unique(stats::na.omit(data[[class_col]])))
    for (k in lv) {
      jobs[[paste0("C", k)]] <- data[!is.na(data[[class_col]]) & data[[class_col]] == k, , drop = FALSE]
    }
  }

  summaries <- list()
  results <- list()
  for (nm in names(jobs)) {
    cli::cli_alert_info("网络分层: {nm}")
    one <- .fit_one(jobs[[nm]], nm)
    results[[nm]] <- one
    summaries[[length(summaries) + 1L]] <- data.frame(
      stratum = nm, n = one$n, skipped = isTRUE(one$skipped),
      CS_strength = if (!is.null(one$cs)) as.numeric(one$cs)[1] else NA_real_
    )
    if (!isTRUE(one$skipped) && !is.null(one$centrality)) {
      ctab <- as.data.frame(one$centrality)
      ctab$node <- rownames(ctab)
      utils::write.csv(ctab, file.path(out_tab, paste0("Centrality_", nm, ".csv")), row.names = FALSE)
    }
  }
  sum_df <- do.call(rbind, summaries)
  utils::write.csv(sum_df, file.path(out_tab, "Network_profile_summary.csv"), row.names = FALSE)

  ctx$results$complex_network_profile_batch <- list(
    summary = sum_df, results = results, nodes = nodes
  )
  cli::cli_alert_success("complex_network_profile_batch: {nrow(sum_df)} 层完成")
  ctx
}

register_block(
  "complex_network_profile_batch",
  block_complex_network_profile_batch,
  "按 LPA 剖面分层心理网络"
)
