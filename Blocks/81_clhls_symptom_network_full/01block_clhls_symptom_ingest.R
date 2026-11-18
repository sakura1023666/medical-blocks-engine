###############################################################################
#  clhls_symptom_ingest — 读入 Chang 2025 复现队列（2028 人，17 节点已定向）
#  register_block: "clhls_symptom_ingest"
#  典型位置: data_clean → column_mapping → imputation 之后。
#  若上游已有 cleaned/imputed 则沿用；否则读 clhls_network$cohort_csv。
#  config$clhls_network = list(cohort_csv = ".../CLHLS-复杂网络-复现队列_2028.csv")
#  写出: ctx$data$cleaned / ctx$data$imputed
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}

block_clhls_symptom_ingest <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  cfg <- clhls_net_cfg(ctx)
  df <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(df)) {
    if (!nzchar(cfg$cohort_csv)) {
      stop("clhls_symptom_ingest: 无上游清洗结果，且未设置 clhls_network$cohort_csv", call. = FALSE)
    }
    df <- clhls_net_read_cohort(cfg$cohort_csv, cfg$nodes)
  }
  # 先把数据列（dev1/circ1…）改名为展示短标签（I1/C1…），全链统一
  df <- clhls_net_rename_nodes(df, cfg)
  miss <- setdiff(cfg$nodes, names(df))
  if (length(miss)) {
    stop("clhls_symptom_ingest: 数据缺少节点列: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  ctx$data$cleaned <- df
  ctx$data$imputed <- df
  cli::cli_alert_success("CLHLS 症状网络队列 n={nrow(df)}")
  ctx$results$clhls_symptom_ingest <- list(n = nrow(df), path = cfg$cohort_csv)
  ctx
}

register_block("clhls_symptom_ingest", block_clhls_symptom_ingest, "CLHLS 2028 症状网络队列读入")
