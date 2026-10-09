#!/usr/bin/env Rscript
# 刷新 summary_results/Figures/image_information（图面说明 + 分析上下文，禁标识/技术）
`%||%` <- function(a, b) if (!is.null(a)) a else b
.proj <- "/mnt/g/02block_result/45_Gallstone/Nomogram_41815074"
.fig <- file.path(.proj, "summary_results", "Figures")
.imd <- file.path(.fig, "image_information")
.tab <- file.path(.proj, "summary_results", "Tables")
.arch <- file.path(.tab, "_archive")
dir.create(.imd, recursive = TRUE, showWarnings = FALSE)

.n <- 273L; .n_tr <- 190L; .n_va <- 83L
.note <- file.path(.proj, "Tables", "Methods_split_denominator_note.txt")
if (file.exists(.note)) {
  ln <- readLines(.note, warn = FALSE)
  .get <- function(k) {
    hit <- grep(paste0("^", k, "="), ln, value = TRUE)
    if (!length(hit)) return(NA_integer_)
    as.integer(sub(".*=", "", hit[[1]]))
  }
  .n_tr <- .get("train_n") %||% .n_tr
  .n_va <- .get("val_n") %||% .n_va
  .n <- as.integer(.n_tr + .n_va)
}
.auc <- tryCatch({
  p <- file.path(.arch, "Source_Fig7_AUC_train_val_boot.csv")
  if (!file.exists(p)) p <- file.path(.arch, "Table_AUC_train_val_boot.csv")
  if (!file.exists(p)) p <- file.path(.proj, "Tables", "Table_AUC_train_val_boot.csv")
  utils::read.csv(p, stringsAsFactors = FALSE)
}, error = function(e) NULL)

.write_md <- function(stem, face, ctx_extra = character(0)) {
  lines <- c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    face,
    "",
    "## 分析上下文",
    "- 暴露: 预指定连续预测因子（Age; Diameter, cm; Volume, cm3; Energy, J; Shots；图/亚组另见各图）",
    "- 结局: lithotripsy success（碎石成功，二元）",
    sprintf("- 样本量: 分析集 N = %d；Training = %d；Validation = %d", .n, .n_tr, .n_va),
    "- Grouping: 二元结局 Success；亚组图为连续暴露 × 分层",
    "- 数据库: 单中心胆结石碎石特征表（本课题主库）",
    "- 是否拼图: 见各图说明",
    ctx_extra
  )
  writeLines(lines, file.path(.imd, paste0(stem, ".md")))
}

.write_md(
  "Figure 1. Inclusion exclusion flowchart",
  paste0(
    "CONSORT 风格纳排流程图。\n\n",
    sprintf("图上标注：总纳入 N = %d；Training n = %d；Validation n = %d。", .n, .n_tr, .n_va),
    "\n本步排除缺失建模协变量 n = 0（complete case）。"
  )
)
.write_md(
  "Figure 2. Associations of continuous features",
  paste0(
    "连续预指定特征与碎石成功的关联森林图（Model1/2/3 OR 与 95%CI）。\n\n",
    "图上标注：各特征 OR(95%CI) 与点估计；参考线 OR = 1。"
  ),
  "- 是否拼图: 是（多特征面板）"
)
.write_md(
  "Figure 3. RCS of continuous features",
  paste0(
    "受限立方样条（RCS）展示连续特征与碎石成功的非线性关联。\n\n",
    "图上标注：若图面有 P-overall / P-nonlinear / 竖线切点则以其为准；缺则写未收获。"
  ),
  "- 是否拼图: 是"
)
.write_md(
  "Figure 4. Ridge shrinkage of pre-specified predictors",
  paste0(
    "Ridge（α=0）收缩路径与 10 折交叉验证（λ.1se）。\n\n",
    "图上标注：系数路径与 CV 偏差曲线；竖线为 λ.1se。"
  )
)
.write_md(
  "Figure 5. Multivariate logistic regression",
  paste0(
    "多因素 logistic 森林图（Chen 风格）：Variable | Event(%) | OR(95%CI) | 橙点黑 CI | P。\n\n",
    "连续变量按临床单位缩放（Age/10、Diameter/0.5、Volume/5、Energy/0.05、Shots/50）。\n",
    "图上标注：各行 OR(95%CI)、P 值；参考线 OR = 1；超界 CI 以箭头提示。"
  )
)
.write_md(
  "Figure 6. Nomogram prediction model",
  paste0(
    "碎石成功列线图（ridge λ.1se 系数，Chen 版式）。\n\n",
    "图上标注：各预测因子轴与总分→风险轴对应关系。"
  )
)
.auc_txt <- if (!is.null(.auc) && nrow(.auc)) {
  set_lab <- gsub("_", " ", as.character(.auc$set), fixed = TRUE)
  set_lab <- gsub("(?i)internal\\s*val", "internal validation", set_lab, perl = TRUE)
  paste(sprintf("%s AUC = %s", set_lab, sprintf("%.3f", as.numeric(.auc$AUC))), collapse = "; ")
} else "AUC 见 Tables archive Source Fig7 AUC train/val/boot"
.write_md(
  "Figure 7. ROC and calibration",
  paste0(
    "列线图区分度（ROC）与校准曲线（train / internal validation / bootstrap）。\n\n",
    "图上标注：", .auc_txt, "；校准图截距/斜率以图面为准。"
  ),
  "- 是否拼图: 是（多面板）"
)
.write_md(
  "Figure 8. DCA of nomogram prediction model for lithotripsy success",
  paste0(
    "决策曲线分析（DCA）：列线图净获益 vs Treat all / Treat none。\n\n",
    "图上标注：阈值阈值为 standardized net benefit；上下轴为 High Risk / Cost:Benefit（Chen 风格）。"
  ),
  "- 是否拼图: 是（train / val 等面板）"
)
.write_md(
  "Figure 9. CIC of nomogram prediction model for lithotripsy success",
  paste0(
    "临床影响曲线（CIC）：每 100 人中高危人数与真阳性人数（含 CI）。\n\n",
    "图上标注：红/蓝曲线及置信带；横轴风险阈值。"
  ),
  "- 是否拼图: 是"
)
.write_md(
  "Figure S1. Subgroup analysis of Diameter and lithotripsy success",
  paste0(
    "补充亚组森林：暴露 = Diameter, cm（每 1-SD）；Overall Crude/Adjusted + Age/Sex/Shape/Color/Surface/Stone type。\n\n",
    "图上标注：Event(%)=事件数(事件率)；OR(95%CI)；P for interaction；橙点+黑 CI；蓝菱形为 Overall。\n",
    "源数据：Tables archive 中 Figure S1 对应 csv；脚注见同目录 Methods footnote。"
  )
)
.write_md(
  "Figure S2. Subgroup analysis of Shots and lithotripsy success",
  paste0(
    "补充亚组森林：暴露 = Shots（每 1-SD）；版式同 Figure S1（Chen Supplemental Figure 风格）。\n\n",
    "图上标注：Event(%)、OR(95%CI)、P for interaction；NE = 近分离/稀疏层不可估。"
  )
)
message("image_information refreshed: ", length(list.files(.imd, pattern = "\\.md$")), " md")
