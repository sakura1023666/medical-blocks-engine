###############################################################################
#  环境毒物文献扩展 — 网络毒理学 / ML 基因 / scRNA / GSEA / MR+对接
###############################################################################

.env_omics_out_tables <- function(ctx) {
  file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Omics")
}

.env_omics_run_py <- function(ctx, mode, extra_args = character()) {
  root <- ctx$config$project$root %||% getwd()
  if (!exists("run_literature_python", mode = "function")) {
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  }
  out <- .env_omics_out_tables(ctx)
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  args <- c("--out-dir", out, extra_args)
  run_literature_python(root, mode, args)
  out
}

block_env_network_toxicology <- function(ctx, ...) {
  bl <- ctx$config$environment_omics %||% list()
  genes <- as.character(bl$network_genes %||% c("FOXO3", "CCND1", "MAP1LC3B", "HMOX1", "MT1G"))
  out <- .env_omics_run_py(ctx, "network_toxicology", c("--genes", paste(genes, collapse = ",")))
  ctx$results$env_network_toxicology <- list(output_dir = out, genes = genes)
  cli::cli_alert_success("网络毒理学完成（{length(genes)} 基因）")
  ctx
}

block_env_ml_gene_screen <- function(ctx, ...) {
  bl <- ctx$config$environment_omics %||% list()
  root <- ctx$config$project$root %||% getwd()
  expr <- bl$gene_expr_path %||% "Data/smoke/D02_env_cd_gene_expr.csv"
  if (!is_absolute_path(expr)) expr <- file.path(root, expr)
  out <- .env_omics_run_py(ctx, "ml_gene_screen", c("--expr-path", expr))
  ctx$results$env_ml_gene_screen <- list(output_dir = out, expr_path = expr)
  cli::cli_alert_success("ML 基因筛选完成")
  ctx
}

block_env_scrna_summary <- function(ctx, ...) {
  bl <- ctx$config$environment_omics %||% list()
  root <- ctx$config$project$root %||% getwd()
  scrna <- bl$scrna_path %||% "Data/smoke/D02_env_cd_scrna.csv"
  if (!is_absolute_path(scrna)) scrna <- file.path(root, scrna)
  out <- .env_omics_run_py(ctx, "scrna_summary", c("--scrna-path", scrna))
  ctx$results$env_scrna_summary <- list(output_dir = out)
  cli::cli_alert_success("scRNA 汇总完成")
  ctx
}

block_env_gsea <- function(ctx, ...) {
  bl <- ctx$config$environment_omics %||% list()
  root <- ctx$config$project$root %||% getwd()
  rank <- bl$gsea_rank_path %||% "Data/smoke/D02_env_cd_gsea_rank.csv"
  if (!is_absolute_path(rank)) rank <- file.path(root, rank)
  out <- .env_omics_run_py(ctx, "gsea", c("--rank-path", rank))
  ctx$results$env_gsea <- list(output_dir = out)
  cli::cli_alert_success("GSEA 完成")
  ctx
}

block_env_mr_docking <- function(ctx, ...) {
  out <- .env_omics_run_py(ctx, "mr_docking", character())
  ctx$results$env_mr_docking <- list(output_dir = out)
  cli::cli_alert_success("MR + geniposide 对接/动力学完成")
  ctx
}

register_block("env_network_toxicology", block_env_network_toxicology, "网络毒理学 PPI")
register_block("env_ml_gene_screen", block_env_ml_gene_screen, "ML 基因重要性筛选")
register_block("env_scrna_summary", block_env_scrna_summary, "scRNA 细胞类型表达")
register_block("env_gsea", block_env_gsea, "GSEA 通路富集")
register_block("env_mr_docking", block_env_mr_docking, "MR IVW + 分子对接/MD")
