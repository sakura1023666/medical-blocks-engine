# patch_gpr_new_mice_ids.R — 为已跑 GPR[new] 回填 mice_row_ids 并删掉模型后检查点
base <- "/mnt/g/02block_result/11_ischemic stroke/Competing_risk_model_40119388/by_unit/GPR[new]/checkpoints"
imp <- readRDS(file.path(base, "imputation.rds"))
pre0 <- imp$ctx$results$data_before_mi
mm <- imp$ctx$results$mice_model
id_col <- "ID"
stopifnot(id_col %in% names(pre0), nrow(pre0) == nrow(mm$data))
ids <- as.character(pre0[[id_col]])
message("lock mice_row_ids n=", length(ids))

cks <- list.files(base, pattern = "\\.rds$", full.names = TRUE)
n_upd <- 0L
for (f in cks) {
  x <- readRDS(f)
  if (!is.list(x) || is.null(x$ctx) || !is.list(x$ctx$results)) next
  if (is.null(x$ctx$results$mice_model)) next
  x$ctx$results$mice_row_ids <- ids
  saveRDS(x, f)
  n_upd <- n_upd + 1L
}
message("updated checkpoints: ", n_upd)

del <- cks[grepl(
  "competing_models_123|competing_stratified|competing_rcs|competing_cif|competing_cox_sensitivity|competing_ph_calibration|competing_supp|competing_pub",
  basename(cks)
)]
del2 <- cks[grepl("^step(1[5-9]|2[0-9])_", basename(cks))]
unlink(unique(c(del, del2)))
message("deleted model+ later ck: ", length(unique(c(del, del2))))
