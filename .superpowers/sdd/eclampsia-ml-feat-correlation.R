## 对 LASSO 入选 4 特征做相关检验热图（连续 Spearman；婚姻状态单独关联）
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
ix <- file.path(study, "by_index/【success】UA_CR")
mi <- file.path(ix, "MIMIC_IV/step06_imputation/D01_AfterMI_Data.RData")
feats_txt <- file.path(study, "checkpoints/by_index/UA_CR/harmonization/feature_selection_final_primary.txt")
out_dir <- file.path(ix, "MIMIC_IV/step36_correlation")
fig_dir <- file.path(out_dir, "Figures")
tab_dir <- file.path(out_dir, "Tables")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
pub_pdf <- file.path(ix, "Figures/pdf")
dir.create(pub_pdf, recursive = TRUE, showWarnings = FALSE)

e <- new.env(parent = emptyenv())
load(mi, envir = e)
objs <- ls(e)
cat("MI objects:", paste(objs, collapse = ", "), "\n")
dat <- NULL
for (nm in c("D01_AfterMI_Data", "dabiao", "data", "df", "imputed")) {
  if (exists(nm, envir = e, inherits = FALSE) && is.data.frame(e[[nm]])) {
    dat <- e[[nm]]
    cat("using object:", nm, " nrow=", nrow(dat), "\n")
    break
  }
}
if (is.null(dat)) {
  ## 取第一个 data.frame
  for (nm in objs) {
    if (is.data.frame(e[[nm]])) { dat <- e[[nm]]; cat("fallback object:", nm, "\n"); break }
  }
}
if (is.null(dat)) stop("unknown object in MI rdata: ", paste(objs, collapse = ", "))

ml_feats <- if (file.exists(feats_txt)) {
  trimws(readLines(feats_txt, warn = FALSE))
} else {
  c("UA_CR", "ALT", "Marital_Status", "Hematocrit")
}
ml_feats <- ml_feats[nzchar(ml_feats)]
cat("ML feats:", paste(ml_feats, collapse = ", "), "\n")

num_feats <- ml_feats[vapply(ml_feats, function(v) v %in% names(dat) && is.numeric(dat[[v]]), logical(1))]
cat_feats <- setdiff(ml_feats, num_feats)
cat("numeric:", paste(num_feats, collapse = ", "), "\n")
cat("categorical:", paste(cat_feats, collapse = ", "), "\n")

if (!requireNamespace("corrplot", quietly = TRUE)) install.packages("corrplot", repos = "https://cloud.r-project.org")
library(corrplot)

thr <- 0.7
X <- as.data.frame(lapply(dat[num_feats], function(z) suppressWarnings(as.numeric(z))))
cor_mat <- cor(X, use = "pairwise.complete.obs", method = "spearman")
p_mat <- matrix(NA_real_, ncol(X), ncol(X), dimnames = list(names(X), names(X)))
for (i in seq_len(ncol(X))) {
  for (j in seq_len(ncol(X))) {
    if (i == j) {
      p_mat[i, j] <- 0
    } else if (i < j) {
      tt <- tryCatch(cor.test(X[[i]], X[[j]], method = "spearman", exact = FALSE), error = function(e) NULL)
      p_mat[i, j] <- p_mat[j, i] <- if (is.null(tt)) NA_real_ else tt$p.value
    }
  }
}

## 高相关对
hi <- which(abs(cor_mat) > thr & upper.tri(cor_mat), arr.ind = TRUE)
hi_df <- if (nrow(hi)) {
  data.frame(
    var1 = rownames(cor_mat)[hi[, 1]],
    var2 = colnames(cor_mat)[hi[, 2]],
    spearman_r = round(cor_mat[hi], 3),
    p_value = round(p_mat[hi], 4),
    stringsAsFactors = FALSE
  )
} else {
  data.frame(var1 = character(), var2 = character(), spearman_r = numeric(), p_value = numeric())
}
write.csv(hi_df, file.path(out_dir, "ml_features_high_correlation_pairs.csv"), row.names = FALSE)
write.csv(
  data.frame(var = rownames(cor_mat), cor_mat, check.names = FALSE),
  file.path(out_dir, "ml_features_spearman_matrix.csv"),
  row.names = FALSE
)
write.csv(
  data.frame(var = rownames(p_mat), p_mat, check.names = FALSE),
  file.path(out_dir, "ml_features_spearman_p.csv"),
  row.names = FALSE
)

## 热图
pdf_path <- file.path(fig_dir, "Figure Correlation Heatmap ML features.pdf")
pdf(pdf_path, width = 5.5, height = 5.5)
corrplot(
  cor_mat,
  method = "circle",
  type = "upper",
  order = "original",
  col = colorRampPalette(c("#BB4444", "#EE9988", "#FFFFFF", "#77AADD", "#4477AA"))(200),
  addCoef.col = "black",
  number.cex = 1.0,
  tl.col = "black",
  tl.srt = 45,
  diag = TRUE,
  title = "Spearman | ML features (continuous)",
  mar = c(0, 0, 2, 0)
)
dev.off()
file.copy(pdf_path, file.path(pub_pdf, "Figure 3. Correlation Heatmap.pdf"), overwrite = TRUE)
file.copy(pdf_path, file.path(ix, "MIMIC_IV/Figures/Figure 3. Correlation Heatmap.pdf"), overwrite = TRUE)
file.copy(pdf_path, file.path(ix, "Figures/Figure Correlation Heatmap Filtered-MIMIC IV.pdf"), overwrite = TRUE)

## Marital_Status 与连续特征关联（Kruskal / eta-like）
assoc_rows <- list()
if ("Marital_Status" %in% names(dat) && length(num_feats)) {
  ms <- factor(as.character(dat$Marital_Status))
  for (v in num_feats) {
    x <- suppressWarnings(as.numeric(dat[[v]]))
    ok <- is.finite(x) & !is.na(ms)
    kt <- tryCatch(stats::kruskal.test(x[ok] ~ ms[ok]), error = function(e) NULL)
    ## 点二列：按水平均值方差解释比例（eta^2 近似）
    eta2 <- NA_real_
    if (nlevels(droplevels(ms[ok])) >= 2L) {
      fit <- tryCatch(stats::aov(x[ok] ~ ms[ok]), error = function(e) NULL)
      if (!is.null(fit)) {
        ss <- summary(fit)[[1]]
        eta2 <- as.numeric(ss["ms[ok]", "Sum Sq"] / sum(ss[, "Sum Sq"]))
      }
    }
    assoc_rows[[v]] <- data.frame(
      feature = v,
      with = "Marital_Status",
      test = "Kruskal-Wallis",
      p_value = if (is.null(kt)) NA_real_ else round(kt$p.value, 4),
      eta2 = round(eta2, 4),
      note = "categorical ML feature vs continuous",
      stringsAsFactors = FALSE
    )
  }
}
assoc_df <- if (length(assoc_rows)) do.call(rbind, assoc_rows) else data.frame()
write.csv(assoc_df, file.path(out_dir, "ml_features_marital_assoc.csv"), row.names = FALSE)

## 摘要
sink(file.path(out_dir, "ml_features_correlation_summary.txt"))
cat("ML features:", paste(ml_feats, collapse = ", "), "\n")
cat("Spearman among continuous:", paste(num_feats, collapse = ", "), "\n")
cat("threshold |r| >", thr, "\n\n")
cat("Spearman matrix:\n"); print(round(cor_mat, 3))
cat("\nHigh-correlation pairs:\n")
if (nrow(hi_df)) print(hi_df) else cat("(none)\n")
cat("\nMarital_Status associations:\n")
if (nrow(assoc_df)) print(assoc_df) else cat("(none)\n")
sink()

cat("\n=== SUMMARY ===\n")
print(round(cor_mat, 3))
cat("\nHigh |r|>", thr, " pairs: ", nrow(hi_df), "\n", sep = "")
if (nrow(hi_df)) print(hi_df)
if (nrow(assoc_df)) {
  cat("\nMarital_Status:\n"); print(assoc_df)
}
cat("\nSaved:", pdf_path, "\nDONE\n")
