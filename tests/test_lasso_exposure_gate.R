#!/usr/bin/env Rscript
## LASSO 暴露门控：未选中暴露 → LASSO_EXPOSURE_NOT_SELECTED
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"))
source(file.path(root, "Blocks/24_ml_dual/02block_ml_feature_selection_bundle.R"))

ctx <- list(
  config = list(
    feature_selection = list(fail_if_exposure_not_in_lasso = TRUE),
    feature_selection_venn = list(require_exposure_in_features = TRUE),
    prediction = list(index_vars = "UA_CR")
  ),
  data = list(train = data.frame(UA_CR = 1, Age = 1)),
  results = list()
)
if (exists("pipeline_index_exposure_var", mode = "function")) {
  ## utils 可能已定义；否则 .mlfsb_exposure_vars 走 prediction$index_vars
}

ok <- tryCatch({
  .mlfsb_assert_exposure_in_lasso(ctx, c("Age", "Gender"), method_lab = "LASSO")
  FALSE
}, error = function(e) {
  grepl("LASSO_EXPOSURE_NOT_SELECTED", conditionMessage(e), fixed = TRUE)
})
stopifnot(isTRUE(ok))

ok2 <- tryCatch({
  .mlfsb_assert_exposure_in_lasso(ctx, c("UA_CR", "Age"), method_lab = "LASSO")
  TRUE
}, error = function(e) FALSE)
stopifnot(isTRUE(ok2))

## 开关关闭则不拦
ctx$config$feature_selection$fail_if_exposure_not_in_lasso <- FALSE
ok3 <- tryCatch({
  .mlfsb_assert_exposure_in_lasso(ctx, c("Age"), method_lab = "LASSO")
  TRUE
}, error = function(e) FALSE)
stopifnot(isTRUE(ok3))

message("test_lasso_exposure_gate: OK")
