Sys.setenv(MEDICAL_BLOCKS_ROOT = "/mnt/e/01block/01Block-new-Final")
source("R/utils.R")
source("R/mi_rubin_pool.R")
ck <- "/mnt/g/02block_result/15_hearing_loss/ml_tyg_whtr_nhanes_single/checkpoints/by_index/TyG_WHtR/NHANES"
x <- readRDS(file.path(ck, "ml_assoc_covariate_resolve.rds"))
ctx <- x$ctx
id_col <- "ID"
mm <- ctx$results$mice_model
if (inherits(mm, "mids") && id_col %in% names(mm$data)) {
  ctx$results$mice_row_ids <- as.character(mm$data[[id_col]])
  cat("restored mice_row_ids n=", length(ctx$results$mice_row_ids), "\n")
}
des <- ctx$results$nhanes_design_quart
keep_ids <- as.character(des$variables[[id_col]])
cat("keep_ids=", length(keep_ids), " imputed=", nrow(ctx$data$imputed), "\n")
idx <- ctx$data$imputed$TyG_WHtR
qs <- stats::quantile(idx, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)
g <- cut(idx, breaks = unique(as.numeric(qs)), include.lowest = TRUE, labels = c("Q1", "Q2", "Q3", "Q4"))
ctx$data$imputed$Group <- g
cat("imputed Group:\n")
print(table(ctx$data$imputed$Group, useNA = "ifany"))
iv <- des$variables
m <- match(as.character(iv[[id_col]]), as.character(ctx$data$imputed[[id_col]]))
iv$Group <- as.character(ctx$data$imputed$Group[m])
des$variables <- iv
ctx$results$nhanes_design_quart <- des
cat("design Group:\n")
print(table(des$variables$Group, useNA = "ifany"))
d0 <- ctx$data$imputed
dk <- mi_complete_aligned(ctx, d0, 1L, keep_vars = c("TyG_WHtR", "Group", "Disease_Group", "Age", "Gender"))
cat("aligned k1 n=", if (is.null(dk)) NA else nrow(dk), "\n")
x$ctx <- ctx
saveRDS(x, file.path(ck, "ml_assoc_covariate_resolve.rds"))
if (file.exists(file.path(ck, "step18_ml_assoc_covariate_resolve.rds"))) {
  saveRDS(x, file.path(ck, "step18_ml_assoc_covariate_resolve.rds"))
}
fs <- readRDS(file.path(ck, "ml_feature_selection_bundle.rds"))
fs$ctx$results$mice_row_ids <- ctx$results$mice_row_ids
fs$ctx$data$imputed <- ctx$data$imputed
fs$ctx$results$nhanes_design_quart <- ctx$results$nhanes_design_quart
saveRDS(fs, file.path(ck, "ml_feature_selection_bundle.rds"))
cat("patched OK\n")
