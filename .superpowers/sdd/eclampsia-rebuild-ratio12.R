## 重建更宽松删行子集：Case:Control ≈ 1:2，尽量少删人
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
load(file.path(study, "Data/mimic/dabiao_clean.RData"))
d <- dabiao
d <- d[!is.na(d$DN) & as.character(d$DN) %in% c("Case", "Control"), ]
if (!"UA_CR" %in% names(d)) {
  d$UA_CR <- as.numeric(d$UricAcid) / as.numeric(d$Creatinine)
}
cat("FULL n=", nrow(d), "\n"); print(table(DN = d$DN))
cat("full ratio Control/Case=", sum(d$DN == "Control") / sum(d$DN == "Case"), "\n")

panel <- intersect(c(
  "UA_CR", "UricAcid", "Creatinine", "Age", "ALT", "AST",
  "Hematocrit", "Hemoglobin", "RBC", "WBC", "PlateletCount", "RDW",
  "UreaNitrogen", "Potassium", "Sodium", "Chloride", "AnionGap", "CalciumTotal"
), names(d))
M <- as.matrix(as.data.frame(lapply(d[panel], function(z) as.numeric(z))))
row_miss <- rowMeans(!is.finite(M))

pick_best <- NULL
for (th in c(0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 1.00)) {
  keep <- row_miss <= th
  dd <- d[keep, , drop = FALSE]
  n1 <- sum(as.character(dd$DN) == "Case")
  n0 <- sum(as.character(dd$DN) == "Control")
  ratio <- n0 / max(n1, 1L)
  cat(sprintf("rm<=%.2f  n=%d  Case=%d  Control=%d  ratio=1:%.2f  kept=%.0f%%\n",
              th, nrow(dd), n1, n0, ratio, 100 * nrow(dd) / nrow(d)))
  ## 目标：比例在 [1.8, 3.2]，且尽量多人
  if (ratio >= 1.8 && ratio <= 3.2 && nrow(dd) >= 400L) {
    if (is.null(pick_best) || nrow(dd) > nrow(pick_best$d)) {
      pick_best <- list(th = th, d = dd, n1 = n1, n0 = n0, ratio = ratio)
    }
  }
}

## 若没有同时满足，选最接近 1:2 且 n 最大的宽松阈值
if (is.null(pick_best)) {
  best_score <- -Inf
  for (th in c(0.70, 0.75, 0.80, 0.85, 0.90, 1.00)) {
    keep <- row_miss <= th
    dd <- d[keep, , drop = FALSE]
    n1 <- sum(as.character(dd$DN) == "Case")
    n0 <- sum(as.character(dd$DN) == "Control")
    ratio <- n0 / max(n1, 1L)
    ## 分数：接近 2.0 的比例 + 样本量
    score <- -abs(ratio - 2.0) * 100 + nrow(dd) / 10
    if (score > best_score) {
      best_score <- score
      pick_best <- list(th = th, d = dd, n1 = n1, n0 = n0, ratio = ratio)
    }
  }
}

cat(sprintf("\nCHOSEN rm<=%.2f n=%d Case=%d Control=%d ratio=1:%.2f\n",
            pick_best$th, nrow(pick_best$d), pick_best$n1, pick_best$n0, pick_best$ratio))

dabiao <- pick_best$d
out1 <- file.path(study, "Data/mimic/dabiao_boost.RData")
out2 <- file.path(study, "_auc_boost_trials/dabiao_rowfiltered_ratio12.RData")
save(dabiao, file = out1)
save(dabiao, file = out2)
writeLines(c(
  paste0("row_miss_max=", pick_best$th),
  paste0("n=", nrow(dabiao)),
  paste0("Case=", pick_best$n1),
  paste0("Control=", pick_best$n0),
  paste0("ratio_control_per_case=", round(pick_best$ratio, 3)),
  paste0("target=1:2_to_1:3"),
  paste0("features_force=UA_CR,ALT,Age")
), file.path(study, "_auc_boost_trials/subset_ratio12_meta.txt"))
cat("Saved", out1, "\nDONE\n")
