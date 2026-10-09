###############################################################################
# pamob_concept_fig1 — Figure 1 四组概念矩阵（发表级）
###############################################################################

block_pamob_concept_fig1 <- function(ctx, ...) {
  source(file.path(ctx$config$project$root %||% getwd(),
                   "Blocks/74_pa_mobility_cognitive_full/00pamob_common.R"), local = FALSE)
  .pamob_source_utils(ctx)
  fig <- pamob_figures_dir(ctx)
  pdf_path <- file.path(fig, "Figure 1. PA-mobility phenotype framework.pdf")
  pamob_draw_fig1_concept(pdf_path)
  ctx$results$pamob_concept_fig1 <- list(path = pdf_path)
  cli::cli_alert_success("Figure 1 (pub style)")
  ctx
}

register_block("pamob_concept_fig1", block_pamob_concept_fig1, "Figure 1 concept")
