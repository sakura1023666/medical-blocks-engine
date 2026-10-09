## 整理 UA_CR 定稿图/表：只留四分位 logistic；重编号；刷新 Fig3 相关热图说明
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
ix <- file.path(study, "by_index/【success】UA_CR")
stopifnot(dir.exists(ix))

`%||%` <- function(a, b) if (!is.null(a)) a else b

## ── 1) 删除 tertile / binary logistic（主表+库内+RCS 衍生）────────────────
drop_pat <- "(?i)(tertile|binary).*logistic|logistic.*(tertile|binary)"
dirs <- c(
  file.path(ix, "Tables"),
  file.path(ix, "MIMIC_IV/Tables"),
  file.path(ix, "MIMIC_IV")
)
n_drop <- 0L
for (d in dirs) {
  if (!dir.exists(d)) next
  fs <- list.files(d, recursive = TRUE, full.names = TRUE)
  hit <- fs[grepl(drop_pat, basename(fs), perl = TRUE)]
  ## 也删 step 目录里的 tertile/binary glm
  hit2 <- fs[grepl("logistic_(tertile|binary)", fs, ignore.case = TRUE)]
  hit <- unique(c(hit, hit2))
  for (f in hit) {
    if (dir.exists(f)) {
      unlink(f, recursive = TRUE)
    } else if (file.exists(f)) {
      unlink(f)
    }
    n_drop <- n_drop + 1L
    cat("DROP:", f, "\n")
  }
}
cat("dropped", n_drop, "paths\n")

## ── 2) 主表 Tables/ 重编号（单库简洁名）────────────────────────────────────
tab_dir <- file.path(ix, "Tables")
## 目标叙事编号：
## T1 baseline | T2 logistic quartile | T3 ML train | T4 ML val
## S01 imputation | S02 train/val baseline | S03 univariate | S04 VIF
## S05 hyper | S06 logloss | S07 DeLong | S08 NRI-IDI
map_plan <- list(
  list(match = "(?i)Table 1.*Baseline characteristics of", dest = "Table 1. Baseline characteristics.xlsx"),
  list(match = "(?i)Logistic regression of UA.?CR quartile", dest = "Table 2. Logistic regression of UA CR quartile.xlsx"),
  list(match = "(?i)ML performance wide training", dest = "Table 3. ML performance wide training.xlsx"),
  list(match = "(?i)ML performance wide validation", dest = "Table 4. ML performance wide validation.xlsx"),
  list(match = "(?i)before and after imputation", dest = "Table S01. Baseline before and after imputation.xlsx", once = TRUE),
  list(match = "(?i)by training and validation", dest = "Table S02. Baseline by training and validation sets.xlsx"),
  list(match = "(?i)Univariate Regression", dest = "Table S03. Univariate Regression Analysis.xlsx"),
  list(match = "(?i)Multicollinearity.*VIF", dest = "Table S04. Multicollinearity Analysis VIF screen.xlsx"),
  list(match = "(?i)Hyperparameters", dest = "Table S05. ML hyperparameters.xlsx"),
  list(match = "(?i)Log-Loss", dest = "Table S06. Log-Loss.xlsx"),
  list(match = "(?i)NRI and IDI.*validation", dest = "Table S08. NRI and IDI.xlsx", once = TRUE),
  list(match = "(?i)Table S0?12.*NRI and IDI", dest = "Table S08. NRI and IDI.xlsx", once = TRUE),
  list(match = "(?i)DeLong", dest = "Table S07. DeLong tests.xlsx", once = TRUE),
  list(match = "(?i)NRI and IDI", dest = "Table S08. NRI and IDI.xlsx", once = TRUE)
)

xlsx <- list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)
## 先删重复/正态性等
for (f in xlsx) {
  bn <- basename(f)
  if (grepl("(?i)Normality", bn)) {
    unlink(f); cat("DROP normality:", bn, "\n"); next
  }
}
xlsx <- list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)
used <- character(0)
for (pl in map_plan) {
  cands <- xlsx[grepl(pl$match, basename(xlsx), perl = TRUE)]
  cands <- setdiff(cands, used)
  if (!length(cands)) next
  ## once：同名多份只留最新/第一份，其余删
  keep <- cands[[1L]]
  if (isTRUE(pl$once) && length(cands) > 1L) {
    for (extra in cands[-1L]) {
      unlink(extra); cat("DROP dup:", basename(extra), "\n")
    }
  }
  dest <- file.path(tab_dir, pl$dest)
  if (!identical(normalizePath(keep, winslash = "/", mustWork = FALSE),
                 normalizePath(dest, winslash = "/", mustWork = FALSE))) {
    if (file.exists(dest)) unlink(dest)
    ok <- file.rename(keep, dest)
    cat(if (ok) "REN" else "FAIL", basename(keep), "->", basename(dest), "\n")
  } else {
    cat("OK already", basename(dest), "\n")
  }
  used <- c(used, dest)
}
## 清理未映射残留（仍叫 Table 3 tertile 等）
xlsx2 <- list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)
keep_names <- vapply(map_plan, function(z) z$dest, character(1))
for (f in xlsx2) {
  if (!(basename(f) %in% keep_names)) {
    ## 允许已是目标名
    if (!grepl("^(Table [0-9]|Table S[0-9]{2})\\.", basename(f))) {
      cat("LEFT:", basename(f), "\n")
    }
  }
}
cat("\nTables now:\n")
print(sort(basename(list.files(tab_dir, pattern = "\\.xlsx$"))))

## ── 3) 刷新 Fig3：ML 三连续特征 Spearman 热图（发表版）───────────────────
if (!requireNamespace("corrplot", quietly = TRUE)) {
  install.packages("corrplot", repos = "https://cloud.r-project.org")
}
library(corrplot)
mi <- file.path(ix, "MIMIC_IV/step06_imputation/D01_AfterMI_Data.RData")
e <- new.env(parent = emptyenv()); load(mi, envir = e)
dat <- e$object
if (!is.data.frame(dat)) {
  for (nm in ls(e)) if (is.data.frame(e[[nm]])) { dat <- e[[nm]]; break }
}
num_feats <- c("UA_CR", "ALT", "Hematocrit")
X <- as.data.frame(lapply(dat[num_feats], function(z) suppressWarnings(as.numeric(z))))
cor_mat <- cor(X, use = "pairwise.complete.obs", method = "spearman")
fig3 <- file.path(ix, "Figures/pdf/Figure 3. Correlation Heatmap.pdf")
dir.create(dirname(fig3), recursive = TRUE, showWarnings = FALSE)
grDevices::pdf(fig3, width = 5.2, height = 5.2, family = "Times")
corrplot(
  cor_mat, method = "circle", type = "upper", order = "original",
  col = colorRampPalette(c("#BB4444", "#EE9988", "#FFFFFF", "#77AADD", "#4477AA"))(200),
  addCoef.col = "black", number.cex = 1.15, tl.col = "black", tl.srt = 45,
  diag = TRUE, cl.cex = 0.9,
  title = "Spearman correlation of ML features",
  mar = c(0, 0, 2.2, 0)
)
grDevices::dev.off()
## 镜像
file.copy(fig3, file.path(ix, "MIMIC_IV/Figures/Figure 3. Correlation Heatmap.pdf"), overwrite = TRUE)
cor_dir <- file.path(ix, "MIMIC_IV/step36_correlation/Figures")
dir.create(cor_dir, recursive = TRUE, showWarnings = FALSE)
file.copy(fig3, file.path(cor_dir, "Figure Correlation Heatmap ML features.pdf"), overwrite = TRUE)
write.csv(round(cor_mat, 3),
          file.path(ix, "MIMIC_IV/step36_correlation/ml_features_spearman_matrix.csv"))

md3 <- file.path(ix, "Figures/image_information/Figure 3. Correlation Heatmap.md")
writeLines(c(
  "# Figure 3. Correlation Heatmap",
  "",
  "## 图面说明",
  "本图为 LASSO 入选 ML 特征中连续变量的 Spearman 相关热图（上三角 + 相关系数标注）。",
  "变量为 UA_CR、ALT、Hematocrit（Marital_Status 为分类变量，不进 Spearman 矩阵）。",
  "对角线为 1；色圈大小/颜色表示相关强弱。本课题阈值 |r|>0.7 视为高相关：三变量两两 |r| 均 <0.15，无强共线。",
  "",
  "## 分析上下文",
  "- 暴露: UA_CR",
  "- 结局: DN（Case/Control）",
  "- 样本量: n=509（插补后分析集）",
  "- Grouping: 与主文 logistic 四分位闸门一致（Table 2）",
  "- 数据库: MIMIC IV（本课题单库）",
  "- 是否拼图: 否",
  "- 特征来源: LASSO 最终 ML 特征（连续子集）"
), md3)

## 图序核对清单
writeLines(c(
  "Figure 1. Flowchart",
  "Figure 2. RCS plot between UA CR and Case",
  "Figure 3. Correlation Heatmap (ML continuous features)",
  "Figure 4. ML performance combined 2x4",
  "Figure 5. SHAP (C waterfall on top)",
  "Figure 6. Subgroup Forest analyses of UA CR",
  "",
  "Table 1. Baseline",
  "Table 2. Logistic quartile only",
  "Table 3. ML performance training",
  "Table 4. ML performance validation",
  "Table S01–S08: imputation / train-val baseline / UV / VIF / hyper / logloss / DeLong / NRI-IDI"
), file.path(ix, "Figures/PUB_ORDER_CHECKLIST.txt"))

cat("\nDONE curate tables + fig3\n")
