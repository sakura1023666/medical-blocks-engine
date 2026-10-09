#!/usr/bin/env Rscript

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
register_block <- function(...) invisible(NULL)
source(file.path(root, "Blocks", "24_ml_dual", "05block_ml_assoc_bundle.R"))

preds <- .ml_assoc_literature_roc_predictors(
  a = 1:100,
  b = 101:200,
  joint_num = rep(1:4, 25),
  score_values = 201:300,
  indices = c("SOSM", "WPR"),
  score = "APSIII"
)

stopifnot(
  identical(names(preds), c("SOSM", "WPR", "Joint Group1-4", "APSIII")),
  all(vapply(preds, length, integer(1L)) == 100L)
)
cat("ML_ASSOC_ROC_PREDICTORS_OK predictors=4\n")
