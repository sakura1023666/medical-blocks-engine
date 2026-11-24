###############################################################################
#  environment_target_enrichment — Step12 Target 靶点交集 + GO/KEGG 富集（VOC 最终/C01_Target.R）
#
#  register_block: "environment_target_enrichment"
#  输入目录默认: VOC 最终/Step12_Target（SEA / SwissTarget / GeneCards 等）
###############################################################################

.etgt_read_csv_safe <- function(path) {
  if (!file.exists(path)) return(NULL)
  tryCatch(read.csv(path, stringsAsFactors = FALSE, check.names = FALSE),
           error = function(e) NULL)
}

.etgt_collect_predicted_genes <- function(data_dir) {
  genes <- character(0)
  sea <- .etgt_read_csv_safe(file.path(data_dir, "sea-results.csv"))
  if (!is.null(sea) && ncol(sea)) {
    for (i in seq_len(nrow(sea))) {
      parts <- strsplit(as.character(sea[i, 1L]), ",", fixed = TRUE)[[1L]]
      if (length(parts) >= 8L && suppressWarnings(as.numeric(parts[4L])) < 0.05) {
        genes <- c(genes, as.character(parts[8L]))
      }
    }
  }
  sw_files <- c(
    "SwissTargetPrediction.csv",
    "SwissTargetPrediction (1).csv",
    "SwissTargetPrediction (2).csv",
    "SwissTargetPrediction (3).csv",
    "SwissTargetPrediction (4).csv",
    "SwissTargetPrediction (5).csv"
  )
  sw_list <- lapply(sw_files, function(fn) .etgt_read_csv_safe(file.path(data_dir, fn)))
  sw_list <- sw_list[!vapply(sw_list, is.null, logical(1L))]
  if (length(sw_list)) {
    sw <- do.call(rbind, sw_list)
    if ("Common.name" %in% names(sw)) genes <- c(genes, sw$Common.name)
  }
  super <- .etgt_read_csv_safe(file.path(data_dir, "bioDBnet_db2db_all.csv"))
  if (!is.null(super) && "Gene.Symbol" %in% names(super)) {
    genes <- c(genes, super$Gene.Symbol)
  }
  unique(genes[nzchar(genes)])
}

.etgt_export_enrich_table <- function(df, filepath, title) {
  if (is.null(df) || !nrow(df)) return(invisible(FALSE))
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    write.csv(df, sub("\\.xlsx$", ".csv", filepath), row.names = FALSE)
    return(invisible(TRUE))
  }
  wb <- openxlsx::createWorkbook()
  openxlsx::addWorksheet(wb, "Sheet1")
  openxlsx::writeData(wb, "Sheet1", df, startRow = 2L)
  openxlsx::writeData(wb, "Sheet1", title, startRow = 1L)
  openxlsx::mergeCells(wb, "Sheet1", cols = 1:ncol(df), rows = 1L)
  title_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12, textDecoration = "bold",
    border = "bottom", halign = "center", valign = "center"
  )
  body_style <- openxlsx::createStyle(
    fontName = "Times New Roman", fontSize = 12,
    halign = "center", valign = "center"
  )
  openxlsx::addStyle(wb, "Sheet1", title_style, rows = 1L, cols = 1:ncol(df), gridExpand = TRUE)
  openxlsx::addStyle(wb, "Sheet1", body_style,
                     rows = 2L:(nrow(df) + 1L), cols = 1:ncol(df), gridExpand = TRUE)
  openxlsx::showGridLines(wb, "Sheet1", showGridLines = FALSE)
  openxlsx::saveWorkbook(wb, filepath, overwrite = TRUE)
  invisible(TRUE)
}

.etgt_resolve_target_data_dir <- function(cfg, bl) {
  rel <- as.character(bl$data_dir %||% "VOC 最终/Step12_Target")
  roots <- unique(c(
    as.character(bl$project_root %||% ""),
    as.character((cfg$environment_batch %||% list())$project_root %||% ""),
    as.character(cfg$project$root %||% ""),
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  ))
  roots <- roots[nzchar(roots)]
  candidates <- character(0)
  if (nzchar(rel) && grepl("^/", rel)) candidates <- c(candidates, rel)
  for (r in roots) {
    candidates <- c(candidates, file.path(r, rel))
  }
  candidates <- unique(normalizePath(candidates, winslash = "/", mustWork = FALSE))
  for (d in candidates) {
    if (dir.exists(d) && file.exists(file.path(d, "GeneCards-SearchResults.csv"))) {
      return(d)
    }
  }
  NA_character_
}

block_environment_target_enrichment <- function(ctx, ...) {
  cfg <- ctx$config
  bl  <- cfg$environment_target %||% list()
  if (!isTRUE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("environment_target_enrichment: enable=FALSE，跳过。")
    return(ctx)
  }

  data_dir <- .etgt_resolve_target_data_dir(cfg, bl)
  if (is.na(data_dir) || !dir.exists(data_dir)) {
    cli::cli_alert_warning(
      "environment_target_enrichment: 未找到 Step12_Target（需含 GeneCards-SearchResults.csv）"
    )
    return(ctx)
  }
  cli::cli_alert_info("environment_target_enrichment: 数据目录 {data_dir}")

  gc_path <- file.path(data_dir, "GeneCards-SearchResults.csv")
  gc <- .etgt_read_csv_safe(gc_path)
  if (is.null(gc) || !"Gene.Symbol" %in% names(gc)) {
    cli::cli_alert_warning("environment_target_enrichment: 缺少 GeneCards-SearchResults.csv")
    return(ctx)
  }
  if (requireNamespace("dplyr", quietly = TRUE)) {
    gc <- gc %>% dplyr::distinct(Gene.Symbol, .keep_all = TRUE)
  } else {
    gc <- gc[!duplicated(gc$Gene.Symbol), , drop = FALSE]
  }

  predicted <- .etgt_collect_predicted_genes(data_dir)
  final_genes <- intersect(gc$Gene.Symbol, predicted)
  if (!length(final_genes)) {
    cli::cli_alert_warning("environment_target_enrichment: 靶点交集为空。")
    return(ctx)
  }
  cli::cli_alert_success("environment_target_enrichment: 交集靶点 {length(final_genes)} 个")

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  fig_dir <- file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  # Venn 图（可选）
  venn_path <- file.path(fig_dir, as.character(bl$fig_venn_filename %||% "Figure 9A. Venn Plot.pdf"))
  if (requireNamespace("Vennerable", quietly = TRUE)) {
    tryCatch({
      glist <- list(GeneCards = gc$Gene.Symbol, PredictedGenes = predicted)
      vst <- Vennerable::Venn(glist)
      vst2 <- vst[, c("GeneCards", "PredictedGenes")]
      grDevices::pdf(venn_path, width = 6, height = 4)
      plot(vst2, doWeights = FALSE)
      grDevices::dev.off()
      cli::cli_alert_success("Venn 图已保存")
    }, error = function(e) {
      try(grDevices::dev.off(), silent = TRUE)
      cli::cli_alert_warning("Venn 图失败: {e$message}")
    })
  }

  if (!requireNamespace("clusterProfiler", quietly = TRUE) ||
      !requireNamespace("org.Hs.eg.db", quietly = TRUE)) {
    cli::cli_alert_warning("environment_target_enrichment: 缺少 clusterProfiler/org.Hs.eg.db，仅完成交集统计。")
    ctx$results$environment_target_genes <- final_genes
    return(ctx)
  }

  q_cut <- as.numeric(bl$qvalue_cutoff %||% 0.01)
  eg <- clusterProfiler::bitr(
    final_genes, fromType = "SYMBOL",
    toType = c("ENTREZID", "ENSEMBL", "SYMBOL"),
    OrgDb = org.Hs.eg.db::org.Hs.eg.db
  )
  if (!nrow(eg)) {
    cli::cli_alert_warning("environment_target_enrichment: bitr 转换失败。")
    return(ctx)
  }

  .run_go <- function(ont, fn, title) {
    ego <- clusterProfiler::enrichGO(
      gene = eg$ENTREZID, OrgDb = org.Hs.eg.db::org.Hs.eg.db,
      ont = ont, pAdjustMethod = "BH", qvalueCutoff = q_cut
    )
    res <- ego@result
    out <- file.path(tbl_dir, fn)
    .etgt_export_enrich_table(res, out, title)
    write.csv(res, sub("\\.xlsx$", ".csv", out), row.names = FALSE)
    res
  }

  fn_kegg <- as.character(bl$table_kegg_filename %||% "Table S12. Results of KEGG Enrichment Analysis.xlsx")
  fn_bp   <- as.character(bl$table_gobp_filename %||% "Table S13. Results of GO-BP Enrichment Analysis.xlsx")
  fn_cc   <- as.character(bl$table_gocc_filename %||% "Table S14. Results of GO-CC Enrichment Analysis.xlsx")
  fn_mf   <- as.character(bl$table_gomf_filename %||% "Table S15. Results of GO-MF Enrichment Analysis.xlsx")

  tryCatch({
    ekegg <- clusterProfiler::enrichKEGG(
      gene = eg$ENTREZID, organism = "hsa",
      pAdjustMethod = "BH", qvalueCutoff = q_cut
    )
    .etgt_export_enrich_table(
      ekegg@result,
      file.path(tbl_dir, fn_kegg),
      "Table S12. Results of KEGG Enrichment Analysis"
    )
  }, error = function(e) cli::cli_alert_warning("KEGG 富集失败: {e$message}"))

  tryCatch(.run_go("BP", fn_bp, "Table S13. Results of GO-BP Enrichment Analysis"),
           error = function(e) cli::cli_alert_warning("GO-BP 失败: {e$message}"))
  tryCatch(.run_go("CC", fn_cc, "Table S14. Results of GO-CC Enrichment Analysis"),
           error = function(e) cli::cli_alert_warning("GO-CC 失败: {e$message}"))
  tryCatch(.run_go("MF", fn_mf, "Table S15. Results of GO-MF Enrichment Analysis"),
           error = function(e) cli::cli_alert_warning("GO-MF 失败: {e$message}"))

  ctx$results$environment_target_genes <- final_genes
  cli::cli_alert_success("environment_target_enrichment 完成。")
  ctx
}

register_block(
  "environment_target_enrichment",
  block_environment_target_enrichment,
  "Step12 Target：GeneCards∩预测靶点 + GO/KEGG 富集表与 Venn 图"
)
