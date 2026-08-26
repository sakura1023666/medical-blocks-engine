###############################################################################
#  complex_network_covariate_residual — 协变量调整后的症状网络（残差化 + bootnet）
###############################################################################

block_complex_network_covariate_residual <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_packages.R"), local = FALSE)
  literature_ensure_packages("network")

  bl <- ctx$config$complex_network %||% list()
  data <- ctx$data$imputed %||% ctx$data$cleaned
  covars <- bl$covariate_cols %||% c("Age", "Gender", "Living_alone")
  covars <- intersect(covars, names(data))

  sym <- grep("^(CESD|GAD)[0-9]+$", names(data), value = TRUE)
  if (!length(sym)) stop("complex_network_covariate_residual: 无症状列", call. = FALSE)

  resid_mat <- as.data.frame(matrix(NA_real_, nrow(data), length(sym), dimnames = list(NULL, sym)))
  rhs <- if (length(covars)) paste(covars, collapse = " + ") else "1"
  for (s in sym) {
    y <- as.numeric(data[[s]])
    if (rhs == "1") {
      resid_mat[[s]] <- y - mean(y, na.rm = TRUE)
    } else {
      fit <- stats::lm(stats::as.formula(paste(s, "~", rhs)), data = data)
      resid_mat[[s]] <- stats::residuals(fit)
    }
  }
  resid_mat <- resid_mat[stats::complete.cases(resid_mat), , drop = FALSE]

  out_tab <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Network")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)

  net_adj <- bootnet::estimateNetwork(resid_mat, default = "EBICglasso", corMethod = "cor_auto")
  adj <- tryCatch(bootnet::getWmat(net_adj), error = function(e) NULL)
  if (!is.null(adj) && any(adj != 0) && requireNamespace("qgraph", quietly = TRUE)) {
    cent <- tryCatch(qgraph::centrality(adj), error = function(e) NULL)
    if (!is.null(cent)) {
      cent_df <- as.data.frame(cent)
      cent_df$node <- rownames(cent_df)
      utils::write.csv(cent_df, file.path(out_tab, "Table_Network_Centrality_covariate_adj.csv"), row.names = FALSE)
    }
  } else {
    utils::write.csv(
      data.frame(note = "empty network after covariate residualization"),
      file.path(out_tab, "Table_Network_Centrality_covariate_adj.csv"), row.names = FALSE
    )
  }

  ctx$results$complex_network_covariate_residual <- list(n = nrow(resid_mat), covariates = covars)
  cli::cli_alert_success("协变量调整网络完成（协变量: {paste(covars, collapse=', ')}）")
  ctx
}

register_block("complex_network_covariate_residual", block_complex_network_covariate_residual,
               "协变量残差化 bootnet 网络")
