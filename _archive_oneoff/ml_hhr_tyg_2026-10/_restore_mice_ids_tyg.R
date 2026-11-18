Sys.setenv(MEDICAL_BLOCKS_ROOT = "/mnt/e/01block/01Block-new-Final")
source("R/utils.R")
source("R/mi_rubin_pool.R")
ck <- "/mnt/g/02block_result/15_hearing_loss/ml_tyg_whtr_nhanes_single/checkpoints/by_index/TyG_WHtR/NHANES"
imp <- readRDS(file.path(ck, "imputation.rds"))
good_ids <- as.character(imp$ctx$results$mice_row_ids)
stopifnot(length(good_ids) == 2895L, identical(good_ids[1:3], c("130", "150", "162")))

des_ids <- as.character(
  readRDS(file.path(ck, "obj.rds"))$ctx$results$nhanes_design_quart$variables$ID
)
cat("design keep=", length(des_ids), "\n")

patch_one <- function(path) {
  if (!file.exists(path)) return(invisible(FALSE))
  x <- readRDS(path)
  ctx <- x$ctx
  ctx$results$mice_row_ids <- good_ids
  ctx$results$mice_model <- imp$ctx$results$mice_model
  # keep imputed at design N if already filtered; rebuild Group
  if (!is.null(ctx$data$imputed) && "ID" %in% names(ctx$data$imputed)) {
    if (nrow(ctx$data$imputed) != length(des_ids)) {
      ctx$data$imputed <- ctx$data$imputed[
        as.character(ctx$data$imputed$ID) %in% des_ids, ,
        drop = FALSE
      ]
    }
    idx <- ctx$data$imputed$TyG_WHtR
    qs <- stats::quantile(idx, probs = c(0, 0.25, 0.5, 0.75, 1), na.rm = TRUE)
    ctx$data$imputed$Group <- cut(
      idx,
      breaks = unique(as.numeric(qs)),
      include.lowest = TRUE,
      labels = c("Q1", "Q2", "Q3", "Q4")
    )
  }
  if (!is.null(ctx$results$nhanes_design_quart)) {
    des <- ctx$results$nhanes_design_quart
    m <- match(as.character(des$variables$ID), as.character(ctx$data$imputed$ID))
    des$variables$Group <- as.character(ctx$data$imputed$Group[m])
    ctx$results$nhanes_design_quart <- des
  }
  x$ctx <- ctx
  saveRDS(x, path)
  cat("patched", basename(path), "imputed=", nrow(ctx$data$imputed), "\n")
  # verify align
  dk <- mi_complete_aligned(ctx, ctx$data$imputed, 1L, keep_vars = c("TyG_WHtR", "Group", "Disease_Group"))
  cat("  aligned n=", if (is.null(dk)) NA else nrow(dk), "\n")
  invisible(TRUE)
}

for (f in c(
  "ml_feature_selection_bundle.rds",
  "ml_assoc_covariate_resolve.rds",
  "step18_ml_assoc_covariate_resolve.rds",
  "multicollinearity_nhanes_final.rds"
)) {
  patch_one(file.path(ck, f))
}
cat("DONE\n")
