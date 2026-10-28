###############################################################################
#  clhls_sex_nct — 男女网络比较 NCT（边 + strength）
#  register_block: "clhls_sex_nct"
#  算法对齐既往 Step06 backup：NetworkComparisonTest::NCT
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


.clhls_net_extract_nct_sig <- function(nct, node_names, fdr = "BH", alpha = 0.05) {
  do_fdr <- !identical(fdr, "none")
  P <- length(node_names)
  p_edge <- if (!is.null(nct$einv.pvals)) as.numeric(nct$einv.pvals[["p-value"]])
            else if (!is.null(nct$einf.pvals)) as.numeric(nct$einf.pvals) else NULL
  all_edges <- data.frame(); sig_edges <- data.frame()
  if (!is.null(p_edge) && length(p_edge) > 0) {
    q_edge <- if (do_fdr) stats::p.adjust(p_edge, method = fdr) else p_edge
    pairs <- tryCatch(as.matrix(utils::combn(node_names, 2)), error = function(e) NULL)
    npair <- if (!is.null(pairs)) ncol(pairs) else NA_integer_
    if (!is.null(pairs) && !is.na(npair) && npair == length(p_edge)) {
      all_edges <- data.frame(
        nodeA = pairs[1, ], nodeB = pairs[2, ],
        p_raw = round(p_edge, 4), q_BH = round(q_edge, 4),
        significant = q_edge < alpha, stringsAsFactors = FALSE, check.names = FALSE
      )
    } else {
      all_edges <- data.frame(
        edge_idx = seq_along(p_edge), p_raw = round(p_edge, 4), q_BH = round(q_edge, 4),
        significant = q_edge < alpha, stringsAsFactors = FALSE, check.names = FALSE
      )
    }
    sig_edges <- all_edges[!is.na(all_edges$significant) & all_edges$significant, , drop = FALSE]
  }

  p_cent_m <- if (!is.null(nct$diffcen.pval)) as.matrix(nct$diffcen.pval)
              else if (!is.null(nct$cinall)) as.matrix(nct$cinall) else NULL
  all_centrality <- data.frame(); sig_centrality <- data.frame()
  if (!is.null(p_cent_m)) {
    cols <- seq_len(ncol(p_cent_m))
    nodename_ok <- !is.null(rownames(p_cent_m)) && all(rownames(p_cent_m) %in% node_names)
    long <- do.call(rbind, lapply(cols, function(j) {
      p <- as.numeric(p_cent_m[, j])
      q <- if (do_fdr) stats::p.adjust(p, method = fdr) else p
      nm <- if (nodename_ok) rownames(p_cent_m)
            else if (nrow(p_cent_m) == P) node_names
            else seq_len(nrow(p_cent_m))
      idx <- if (ncol(p_cent_m) > 1) colnames(p_cent_m)[j] else "strength"
      data.frame(node = nm, index = idx, p_raw = round(p, 4), q_BH = round(q, 4),
                 significant = q < alpha, stringsAsFactors = FALSE, check.names = FALSE)
    }))
    all_centrality <- long
    sig_centrality <- long[!is.na(long$significant) & long$significant, , drop = FALSE]
  }
  list(all_edges = all_edges, sig_edges = sig_edges,
       all_centrality = all_centrality, sig_centrality = sig_centrality)
}

block_clhls_sex_nct <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  clhls_net_require_pkgs()
  cfg <- clhls_net_cfg(ctx)
  dirs <- clhls_net_out_dirs(ctx)
  df <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(df)) stop("clhls_sex_nct: 无数据", call. = FALSE)

  parts <- clhls_net_sex_split(df, cfg)
  dat_m <- clhls_net_cov_mat(parts$Male, cfg$nodes, cfg$covariates)
  dat_f <- clhls_net_cov_mat(parts$Female, cfg$nodes, cfg$covariates)
  nm <- cfg$nodes
  items <- unname(cfg$items)

  cli::cli_alert_info("NCT 置换 it={cfg$nct_it} ...")
  nct <- tryCatch(
    NetworkComparisonTest::NCT(
      dat_m, dat_f, it = cfg$nct_it, binary.data = FALSE, paired = FALSE,
      test.edges = TRUE, edges = "all", test.centrality = TRUE,
      centrality = "strength", progressbar = FALSE
    ),
    error = function(e) {
      cli::cli_alert_warning("NCT 失败: {conditionMessage(e)}")
      NULL
    }
  )

  if (!is.null(nct)) {
    save(nct, file = file.path(dirs$rdata, "nct_sex.RData"))
    sig <- .clhls_net_extract_nct_sig(nct, nm)
    if (nrow(sig$all_edges)) {
      clhls_net_write_table(sig$all_edges, file.path(dirs$tab, "NCT_edges_all"))
    }
    if (nrow(sig$sig_edges)) {
      out <- sig$sig_edges
      if (all(c("nodeA", "nodeB") %in% names(out))) {
        out$nodeA_label <- items[match(out$nodeA, nm)]
        out$nodeB_label <- items[match(out$nodeB, nm)]
      }
      clhls_net_write_table(out, file.path(dirs$tab, "NCT_edges_significant"))
    }
    if (nrow(sig$all_centrality)) {
      clhls_net_write_table(sig$all_centrality, file.path(dirs$tab, "NCT_centrality_all"))
    }
    if (nrow(sig$sig_centrality)) {
      outc <- sig$sig_centrality
      outc$Items <- items[match(outc$node, nm)]
      clhls_net_write_table(outc, file.path(dirs$tab, "NCT_centrality_significant"))
    }
  }

  ctx$results$clhls_sex_nct <- list(nct_it = cfg$nct_it, ok = !is.null(nct))
  cli::cli_alert_success("NCT 完成 ok={ctx$results$clhls_sex_nct$ok}")
  ctx
}

register_block("clhls_sex_nct", block_clhls_sex_nct, "CLHLS 性别 NCT")
