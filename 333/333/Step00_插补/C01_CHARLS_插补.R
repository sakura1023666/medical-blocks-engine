rm(list = ls()); gc()
################################################################################
# C05_CHARLS_插补.R  ——  mice 插补 + Table S1 (Before/After MI)
# 参考 111/Step01_RawData/C01_MI.R
# 输出: D01_AfterMI_Data_CHARLS.RData (对象 data_imp)
#       Table S1-CHARLS (插补前后对比, xlsx + csv)
################################################################################
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
if (length(file_arg) > 0) {
  script_path <- dirname(normalizePath(sub("^--file=", "", file_arg), mustWork = FALSE))
} else if (requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  script_path <- normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path))
} else {
  script_path <- getwd()
}
setwd(script_path)
cat("工作目录:", getwd(), "\n")
options(width=220)

suppressPackageStartupMessages({
  library(dplyr); library(mice); library(table1); library(openxlsx)
})

dir.create("CHARLS/csv", showWarnings = FALSE, recursive = TRUE)

# ========================= 1) 读取合并数据 =========================
load("D02_CHARLS_MetS.RData")   # 对象 CHARLS
data_table01 <- CHARLS
cat("合并数据维度:", dim(data_table01), "\n")

# ========================= 2) 去缺失>40%的列 =========================
missing.percent <- colSums(is.na(data_table01)) / nrow(data_table01)
drop_cols <- names(missing.percent[missing.percent > 0.4])
cat("缺失>40%剔除:", paste(drop_cols, collapse=", "), "\n")
data_table01 <- data_table01[, missing.percent <= 0.4, drop = FALSE]
cat("过滤后列数:", ncol(data_table01), "\n")

# ========================= 3) 分离结局变量(不参与插补) =========================
# 二分类结局/诊断标签不插补, 插补后拼回; 与参考一致(DN/Frailty_Score 思路)
outcome_cols <- c("MetS", "mets_count", "Dep_Flag", "ID")
outcomes <- data_table01[, outcome_cols[outcome_cols %in% colnames(data_table01)], drop = FALSE]
data_mi <- data_table01[, !(colnames(data_table01) %in% outcome_cols), drop = FALSE]

# 去掉不参与插补的列(衍生/共线, 参考剔除 BMI/Weight/Height/PP)
remove_cols <- c("Weight", "Height", "PP")
remove_cols <- remove_cols[remove_cols %in% colnames(data_mi)]
cat("去掉不插补的衍生列:", paste(remove_cols, collapse=", "), "\n")
removed <- data_mi[, remove_cols, drop = FALSE]   # 保留, 插补后拼回
data_mi <- data_mi[, !(colnames(data_mi) %in% remove_cols), drop = FALSE]

# char→factor (mice cart 需要)
char_cols <- sapply(data_mi, is.character)
if (any(char_cols)) {
  data_mi[char_cols] <- lapply(data_mi[char_cols], as.factor)
  cat("转factor的列:", paste(names(char_cols[char_cols]), collapse=", "), "\n")
}

# ========================= 4) mice 插补 (有缓存则跳过) =========================
if (file.exists("D01_AfterMI_Data_CHARLS.RData")) {
  load("D01_AfterMI_Data_CHARLS.RData")
  cat("检测到已存在插补结果, 跳过 mice (如需重跑请先删除该文件)\n")
} else {
  cat("\n开始 mice 插补 (m=5, seed=1234, cart)... 这会花几分钟\n")
  t0 <- Sys.time()
  imp <- mice(data = data_mi, m = 5, seed = 1234, method = "cart", printFlag = TRUE)
  data_imp <- mice::complete(imp)
  cat("插补耗时:", round(as.numeric(difftime(Sys.time(), t0, units="secs")), 0), "秒\n")
  cat("插补后剩余NA:", sum(is.na(data_imp)), "\n")
  # 拼回结局 + 衍生列
  data_imp <- cbind(data_imp, removed, outcomes)
  save(data_imp, file = "D01_AfterMI_Data_CHARLS.RData")
  cat("已保存: D01_AfterMI_Data_CHARLS.RData\n")
}
cat("最终维度:", dim(data_imp), "\n")

# ========================= 5) Table S1: Before/After MI =========================
cat("\n生成 Table S1 (插补前后对比)...\n")
pvalue <- function(x, ...) {
  y <- unlist(x); g <- factor(rep(1:length(x), times = sapply(x, length)))
  if (is.numeric(y)) {
    p <- if (length(unique(g)) == 2) t.test(y ~ g)$p.value else kruskal.test(y ~ g)$p.value
  } else {
    p <- chisq.test(table(y, g))$p.value
  }
  c("", sub("<", "&lt;", ifelse(p < 0.001, "<0.001", sprintf("%.3f", p))))
}
my.render.cont <- function(x) {
  with(stats.apply.rounding(stats.default(x), digits = 2),
       c("", "Median (IQR)" = sprintf("%s (%s,%s)", MEDIAN, Q1, Q3)))
}
my.render.cat <- function(x) {
  c("", sapply(stats.default(x), function(y) with(y, sprintf("%d (%0.0f %%)", FREQ, PCT))))
}

data_tbl_imp <- data_imp[, !(colnames(data_imp) %in% outcome_cols), drop = FALSE]
data_tbl_raw <- data_mi
# 统一列(衍生列Weight/Height/PP只在插补后拼回, Before侧没有 → 取交集)
common_table_cols <- intersect(colnames(data_tbl_imp), colnames(data_tbl_raw))
data_tbl_imp <- data_tbl_imp[, common_table_cols, drop = FALSE]
data_tbl_raw <- data_tbl_raw[, common_table_cols, drop = FALSE]
data_tbl_imp$Group <- "AfterMI"; data_tbl_raw$Group <- "BeforeMI"
rt <- rbind(data_tbl_imp, data_tbl_raw)
rt$Group <- factor(rt$Group, levels = c("BeforeMI","AfterMI"), ordered = TRUE)

Tab1 <- table1(~ . | Group, data = rt,
               extra.col = list("p-value" = pvalue),
               render.continuous = my.render.cont,
               render.categorical = my.render.cat)

tab_df <- as.data.frame(Tab1)
tab_df[] <- lapply(tab_df, function(x) gsub("&plusmn;", "±", x))
colnames(tab_df) <- gsub("\\*\\*", "", colnames(tab_df))
tab_df[, 1] <- gsub("_", " ", tab_df[, 1])

# ---- openxlsx 样式 (套用参考) ----
wb1 <- createWorkbook(); addWorksheet(wb1, "Sheet1")
s1headerStyle <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border=c("top"))
s1line2Style  <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border=c("bottom"))
s1bodyStyle   <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", valign="center")
s1boldLeft    <- createStyle(fontSize=12, fontName="Times New Roman", halign="left", valign="center", textDecoration="bold")
s1endline     <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", valign="center", border=c("bottom"), borderStyle="thin")
rows_without_space <- grep("^\\S*$", tab_df[, 1])

writeData(wb1, 1, x = tab_df, startRow = 2, startCol = 1, colNames = TRUE, rowNames = FALSE)
writeData(wb1, 1, x = "Table S1-CHARLS. Baseline characteristics before and after multiple imputation",
          startRow = 1, startCol = 1, colNames = FALSE, rowNames = FALSE)
mergeCells(wb1, 1, rows = 1, cols = 1:ncol(tab_df))
addStyle(wb1, 1, s1line2Style, rows = 1, cols = 1:ncol(tab_df), gridExpand = TRUE)
addStyle(wb1, 1, s1headerStyle, rows = 2, cols = 1:ncol(tab_df), gridExpand = TRUE)
addStyle(wb1, 1, s1line2Style, rows = 3, cols = 1:ncol(tab_df), gridExpand = TRUE)
addStyle(wb1, 1, s1bodyStyle, rows = 4:(nrow(tab_df)+1), cols = 1:ncol(tab_df), gridExpand = TRUE)
addStyle(wb1, 1, s1boldLeft, rows = rows_without_space + 2, cols = 1, gridExpand = TRUE)
addStyle(wb1, 1, s1endline, rows = nrow(tab_df)+2, cols = 1:ncol(tab_df), gridExpand = TRUE)
setColWidths(wb1, 1, cols = 1:ncol(tab_df), widths = "auto")

file_name <- "CHARLS/Table S1-CHARLS. Baseline characteristics before and after multiple imputation.xlsx"
saveWorkbook(wb1, file = file_name, overwrite = TRUE)
write.csv(tab_df, file.path("CHARLS/csv", sub("\\.xlsx$",".csv", basename(file_name))), row.names = FALSE)
cat("已保存:", file_name, "  +  csv/", sub("\\.xlsx$",".csv", basename(file_name)), "\n")
cat("\n==================== C05 完成 ====================\n")
