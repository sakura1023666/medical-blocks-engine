#!/usr/bin/env Rscript
# 仅重跑 contextual 抽取 + 四组分布（依赖已有 CHARLS/NHANES success checkpoints）
# Usage: Rscript run/pa_mobility_cognitive/run_contextual_profiling_extract.R

root <- normalizePath(getwd(), winslash = "/")
if (basename(root) == "pa_mobility_cognitive") {
  root <- normalizePath(file.path(root, "..", ".."), winslash = "/")
}
setwd(root)
suppressPackageStartupMessages({
  source("R/utils.R")
  source("R/pamob_utils.R")
})
source("Blocks/74_pa_mobility_cognitive_full/19block_pamob_contextual_inventory.R", local = FALSE)

batch <- "/mnt/g/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
data_root <- "/mnt/g/02block_result/02_Cognitive_impairment/trajectory_Personalized_yuhan/data"

# Load analytic sets from latest revision checkpoints if present, else assemble checkpoints
charls_ck <- file.path(batch, "by_unit", "【success】CHARLS", "checkpoints", "pamob_teacher_revision_charls.rds")
nhanes_ck <- file.path(batch, "by_unit", "【success】NHANES", "checkpoints", "pamob_teacher_revision_nhanes.rds")
if (!file.exists(charls_ck)) {
  charls_ck <- file.path(batch, "by_unit", "【success】CHARLS", "checkpoints", "pamob_assemble_charls.rds")
}
if (!file.exists(nhanes_ck)) {
  nhanes_ck <- file.path(batch, "by_unit", "【success】NHANES", "checkpoints", "pamob_assemble_nhanes.rds")
}

ctx_c <- readRDS(charls_ck)$ctx
ctx_n <- readRDS(nhanes_ck)$ctx

config <- ctx_c$config
config$project$root <- root
config$project$output_dir <- batch  # write inventory to project root Manuscript/Tables
config$pamob$data_root <- data_root

# merge data slots
ctx <- list(
  config = config,
  data = list(
    pamob_charls_long = ctx_c$data$pamob_charls_long,
    pamob_charls_baseline = ctx_c$data$pamob_charls_baseline,
    pamob_nhanes_dsst = ctx_n$data$pamob_nhanes_dsst %||% ctx_n$results$pamob_svy_dsst$data
  ),
  results = list()
)

ctx <- block_pamob_contextual_inventory(ctx)

# also mirror into unit folders for convenience
for (u in c(
  file.path(batch, "by_unit", "【success】CHARLS"),
  file.path(batch, "by_unit", "【success】NHANES")
)) {
  dir.create(file.path(u, "Tables"), recursive = TRUE, showWarnings = FALSE)
  for (f in c(
    "Table_S_Contextual_variable_inventory.csv",
    "Table_S_Contextual_by_phenotype.csv",
    "Table_S_Contextual_discordant_contrast.csv"
  )) {
    src <- file.path(batch, "Tables", f)
    if (file.exists(src)) file.copy(src, file.path(u, "Tables", f), overwrite = TRUE)
  }
}
file.copy(
  file.path(batch, "Manuscript", "Contextual_variable_inventory.md"),
  file.path(batch, "by_unit", "【success】CHARLS", "Manuscript", "Contextual_variable_inventory.md"),
  overwrite = TRUE
)

message("DONE contextual extract")
message("dist rows=", nrow(ctx$results$pamob_contextual_inventory$distribution))
message("discordant rows=", nrow(ctx$results$pamob_contextual_inventory$discordant))
