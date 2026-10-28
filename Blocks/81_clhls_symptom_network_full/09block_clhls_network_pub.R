###############################################################################
#  clhls_network_pub — Table 1 + 发表图四目录
#  register_block: "clhls_network_pub"
#  Table 1: 年龄/性别 + 条目均值/SD + 节点 R²（对齐文献 Table 1）
###############################################################################



if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || length(x) == 0) y else x
}


block_clhls_network_pub <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "Blocks/81_clhls_symptom_network_full/00clhls_net_common.R"), local = FALSE)
  cfg <- clhls_net_cfg(ctx)
  dirs <- clhls_net_out_dirs(ctx)
  df <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(df)) stop("clhls_network_pub: 无数据", call. = FALSE)

  nodes <- cfg$nodes
  items <- cfg$items
  mat <- clhls_net_node_matrix(df, nodes)

  r2_path <- file.path(dirs$tab, "Table_node_predictability_R2.xlsx")
  r2_map <- setNames(rep(NA_real_, length(nodes)), nodes)
  if (file.exists(r2_path)) {
    r2_df <- openxlsx::read.xlsx(r2_path, startRow = 2)
    r2_map[r2_df$Label] <- r2_df$R2
  }

  item_rows <- lapply(nodes, function(v) {
    x <- mat[[v]]
    data.frame(
      Label = v, Items = unname(items[[v]]),
      Mean = round(mean(x, na.rm = TRUE), 2),
      SD = round(stats::sd(x, na.rm = TRUE), 2),
      Predictability_R2 = round(as.numeric(r2_map[[v]]), 3),
      stringsAsFactors = FALSE
    )
  })
  item_tab <- do.call(rbind, item_rows)

  sx <- clhls_net_sex_code(df[[cfg$sex_col]])
  n_male <- sum(sx == clhls_net_sex_code(cfg$male_code), na.rm = TRUE)
  n_female <- sum(sx == clhls_net_sex_code(cfg$female_code), na.rm = TRUE)

  clhls_net_write_table(item_tab, file.path(dirs$tab, cfg$table1_stem))

  # 四目录发表图
  root <- ctx$config$project$root %||% getwd()
  if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
    source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
    if (exists("pub_figure_ensure_formats", mode = "function")) {
      tryCatch(
        pub_figure_ensure_formats(dirs$fig, config = ctx$config %||% list()),
        error = function(e) cli::cli_alert_warning("四目录导出: {conditionMessage(e)}")
      )
    }
  }

  ctx$results$clhls_network_pub <- list(
    n = nrow(mat), n_male = n_male, n_female = n_female,
    tables = dirs$tab, figures = dirs$fig
  )
  cli::cli_alert_success("Table 1 与发表图收口完成")
  ctx
}

register_block("clhls_network_pub", block_clhls_network_pub, "CLHLS 网络 Table1 与发表图")
