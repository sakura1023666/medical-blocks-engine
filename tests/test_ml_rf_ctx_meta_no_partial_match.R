###############################################################################
# ml_rf write_ctx_meta：禁止 $ml_models 部分匹配到 ml_models_models_dir
###############################################################################

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath("..", winslash = "/"))
if (!file.exists(file.path(root, "Blocks/22_ml_models/02block_ml_rf.R"))) {
  root <- normalizePath(".", winslash = "/")
}
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "Blocks/22_ml_models/02block_ml_rf.R"), local = FALSE)

ctx <- list(results = list())
prep <- list(
  df_train = data.frame(x = 1),
  df_validation = data.frame(x = 1),
  pred_ref_col = ".pred_0",
  pred_ana_col = ".pred_1",
  feats = "x",
  models_dir = "/tmp/fake_models_dir"
)

ctx2 <- .mlrf02_write_ctx_meta(ctx, prep)
stopifnot(is.list(ctx2$results[["ml_models"]]))
stopifnot(identical(ctx2$results[["ml_models_models_dir"]], "/tmp/fake_models_dir"))

## 模拟「先有 dir、再 ensure」旧顺序的对照：新实现不得把 ml_models 写成字符
fake_wf <- list(class = "workflow_stub")
ctx2$results[["ml_models"]][["rf"]] <- fake_wf
stopifnot(identical(ctx2$results[["ml_models"]][["rf"]], fake_wf))

## 若误用 $ 部分匹配，下面会把字符路径当成 ml_models
bad <- list(results = list(ml_models_models_dir = "/tmp/x"))
got <- bad$results$ml_models
stopifnot(is.character(got)) # 证明旧坑仍存在于 R 语义
safe <- bad$results[["ml_models"]]
stopifnot(is.null(safe))

cat("OK test_ml_rf_ctx_meta_no_partial_match\n")
