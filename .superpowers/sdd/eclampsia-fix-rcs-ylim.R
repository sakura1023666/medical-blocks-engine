Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
root <- "E:/01block/01Block-new-Final"
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
ix <- file.path(study, "by_index/【success】UA_CR")
ck <- file.path(study, "checkpoints/by_index/UA_CR/MIMIC_IV")
setwd(root)
source("R/utils.R")
source("R/pipeline_runner.R")
source("Blocks/15_rcs/02block_rcs_incidence.R")
pack <- readRDS(file.path(ck, "performance_ml.rds"))
ctx <- pack$ctx
`%||%` <- function(a, b) if (!is.null(a)) a else b
ctx$config$rcs_incidence <- modifyList(ctx$config$rcs_incidence %||% list(), list(
  y_min = 0, y_max = 25, ylim = NULL
))
## 清掉可能写死的 ylim=c(0,5)
ctx$config$rcs_incidence$ylim <- NULL
ctx$config$rcs_incidence$y_max <- 25
cat("rcs_incidence cfg:\n"); print(ctx$config$rcs_incidence[c("y_min","y_max","ylim")])
ctx$output_dir <- file.path(study, "by_index/UA_CR/MIMIC_IV/step30_rcs_incidence")
dir.create(ctx$output_dir, recursive = TRUE, showWarnings = FALSE)
if (!exists("run_block", mode = "function")) {
  run_block <- function(ctx, n, ...) block_rcs_incidence(ctx, ...)
}
ctx <- run_block(ctx, "rcs_incidence")
pdfs <- list.files(ctx$output_dir, pattern = "RCS.*\\.pdf$", recursive = TRUE, full.names = TRUE)
print(pdfs)
stopifnot(length(pdfs) >= 1L)
file.copy(pdfs[1], file.path(ix, "Figures/pdf/Figure 2. RCS plot between UA CR and Case.pdf"), overwrite = TRUE)
file.copy(pdfs[1], file.path(ix, "MIMIC_IV/Figures/Figure 2. RCS plot between UA CR and Case.pdf"), overwrite = TRUE)
cat("DONE RCS fix copy\n")
