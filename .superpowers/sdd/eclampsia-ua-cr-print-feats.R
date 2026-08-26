root <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
cands <- list.files(file.path(root, "by_index"), pattern = "feature_selection_final.*\\.rds$", recursive = TRUE, full.names = TRUE)
cands <- c(cands, list.files(file.path(root, "checkpoints/by_index/UA_CR"), pattern = "feature_selection_final.*\\.rds$", recursive = TRUE, full.names = TRUE))
cands <- unique(cands[grepl("UA_CR|success.*UA", cands, ignore.case = TRUE) | grepl("checkpoints/by_index/UA_CR", cands)])
print(cands)
for (f in cands) {
  cat("\nFROM ", f, "\n", sep = "")
  x <- tryCatch(readRDS(f), error = function(e) e)
  print(x)
}
# also from checkpoint ctx
ck <- list.files(file.path(root, "checkpoints/by_index/UA_CR"), pattern = "ml_feature_selection|feature_selection", recursive = TRUE, full.names = TRUE)
print(ck)
