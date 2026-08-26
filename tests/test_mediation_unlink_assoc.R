#!/usr/bin/env Rscript
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
source(file.path(root, "Blocks/20_mediation/00mediation_common.R"), local = FALSE)

td <- tempfile("med_unlink_")
dir.create(file.path(td, "Tables"), recursive = TRUE)
dir.create(file.path(td, "Figures"), recursive = TRUE)

keep <- file.path(td, "Tables", "Table S7-MIMIC. Final multivariable model harmonized.xlsx")
assoc <- file.path(td, "Tables", "Table S8-MIMIC. Associations of APRI with laboratory indicators.xlsx")
assoc_old <- file.path(td, "Tables", "Table S9-eICU. The associations between APRI and laboratory indicators.xlsx")
med <- file.path(td, "Tables", "Table S9-MIMIC. Mediation analysis of APRI.xlsx")
pathfig <- file.path(td, "Figures", "Figure S3-MIMIC. Path diagram of mediation.pdf")
writeLines("x", keep)
writeLines("x", assoc)
writeLines("x", assoc_old)
writeLines("x", med)
writeLines("x", pathfig)

# 模拟 LM 提前入队后门控失败：队列项也应被清掉
.table_queue_env <<- new.env(parent = emptyenv())
.table_queue_env$items <- list(
  list(filepath = file.path(td, "Tables", "queued_Associations of APRI with laboratory indicators.xlsx")),
  list(filepath = keep)
)

ctx <- list(
  output_dir_tables = file.path(td, "Tables"),
  output_dir_figures = file.path(td, "Figures"),
  root_output_dir = td
)
n <- .mi02_unlink_mediation_exports(ctx)
stopifnot(n >= 4L)
stopifnot(file.exists(keep))
stopifnot(!file.exists(assoc))
stopifnot(!file.exists(assoc_old))
stopifnot(!file.exists(med))
stopifnot(!file.exists(pathfig))
stopifnot(length(.table_queue_env$items) == 1L)
stopifnot(identical(.table_queue_env$items[[1L]]$filepath, keep))
unlink(td, recursive = TRUE)
message("test_mediation_unlink_assoc: OK")
