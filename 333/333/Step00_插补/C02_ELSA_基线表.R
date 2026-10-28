rm(list = ls()); gc()
################################################################################
# C06_ELSA_基线表.R  ——  主 Table 1 (按 MetS 分组)  [镜像 C06_CHARLS]
# 输出: ELSA/Table 1-ELSA. Baseline characteristics.xlsx + csv
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
  library(dplyr); library(gtsummary); library(openxlsx)
})

# ========================= 1) 读取插补后数据 =========================
load("D01_AfterMI_Data_ELSA.RData")   # data_imp
df <- data_imp
cat("维度:", dim(df), "\n")
df <- na.omit(df)

df$MetS <- factor(df$MetS, levels = c(0,1), labels = c("Non-MetS","MetS"))
cat("MetS 分布:\n"); print(table(df$MetS))

# ========================= 2) Table 1 变量选择 =========================
# 排除 CESD-8 条目(网络节点) + MetS 二分类判定/计数(与分组冗余)
exclude_vars <- c(grep("^dc0", colnames(df), value=TRUE),       # CHARLS CESD 条目(若有)
                  grep("^PSced|^psced", colnames(df), value=TRUE), # ELSA CESD-8 条目
                  "c_waist","c_hdl","c_tg","c_bp","c_glu",
                  "mets_count", "ID")
t1_df <- df %>% select(-any_of(exclude_vars))

# ========================= 3) gtsummary Table 1 =========================
tb <- t1_df %>%
  tbl_summary(by = MetS,
              type = list(Depression_Score ~ "continuous"),
              digits = list(all_continuous() ~ 2, all_categorical() ~ 2),
              statistic = list(
                all_continuous() ~ "{median} ({p25},{p75})",
                all_categorical() ~ "{n} ({p}%)"
              )) %>%
  add_p(pvalue_fun = ~ style_pvalue(.x, digits = 3)) %>%
  add_overall() %>%
  modify_header(label ~ "**Variable**") %>%
  modify_spanning_header(c(stat_1, stat_2) ~ "**Baseline**") %>%
  modify_footnote(all_stat_cols() ~ "Median (IQR) or Frequency (%)") %>%
  modify_caption("**Table 1-ELSA. Baseline Characteristics by Metabolic Syndrome Status.**") %>%
  bold_labels()
print(tb)

# ========================= 4) 写 Excel + 样式 =========================
tb_df <- as.data.frame(tb)
rows_with_underscore <- grep("^_.*_$", tb_df[,1])
tb_df[rows_with_underscore,1] <- gsub("^_+|_+$", "", tb_df[rows_with_underscore,1])
colnames(tb_df) <- gsub("\\*\\*", "", colnames(tb_df))
tb_df[,1] <- gsub("_", " ", tb_df[,1])

wb2 <- createWorkbook(); addWorksheet(wb2, "Sheet1")
headerStyle  <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border=c("bottom"))
bodyStyle    <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", valign="center", border=c("top","bottom"), borderStyle="thin")
boldLeft     <- createStyle(fontSize=12, fontName="Times New Roman", halign="left", valign="center", textDecoration="bold", border=c("top","bottom"), borderStyle="thin")
botOdd       <- createStyle(fontSize=12, fontName="Times New Roman", halign="left", valign="center", border=c("top"), borderStyle="thin")
botEven      <- createStyle(fontSize=12, fontName="Times New Roman", halign="left", valign="center", border=c("bottom"), borderStyle="thin")
botCenter    <- createStyle(fontSize=12, fontName="Times New Roman", halign="left", valign="center")
nc <- ncol(tb_df)

writeData(wb2, 1, x = "Table 1-ELSA. Baseline characteristics by Metabolic Syndrome status",
          startRow = 1, startCol = 1, colNames = FALSE, rowNames = FALSE)
mergeCells(wb2, 1, rows = 1, cols = 1:nc); addStyle(wb2, 1, headerStyle, rows = 1, cols = 1:nc, gridExpand = TRUE)
writeData(wb2, 1, x = tb_df, startRow = 2, startCol = 1, colNames = TRUE, rowNames = FALSE)
addStyle(wb2, 1, headerStyle, rows = 2, cols = 1:nc, gridExpand = TRUE)
addStyle(wb2, 1, bodyStyle, rows = 3:(nrow(tb_df)+2), cols = 1:nc, gridExpand = TRUE)
addStyle(wb2, 1, boldLeft, rows = rows_with_underscore + 2, cols = 1, gridExpand = TRUE)
for (rr in (nrow(tb_df)+3):(nrow(tb_df)+5)) mergeCells(wb2, 1, rows = rr, cols = 1:nc)
writeData(wb2, 1, x = "Median (IQR) or Frequency (%)", startRow = nrow(tb_df)+3, startCol = 1, colNames = FALSE, rowNames = FALSE)
writeData(wb2, 1, x = "Wilcoxon rank sum test; Pearson's Chi-squared test", startRow = nrow(tb_df)+4, startCol = 1, colNames = FALSE, rowNames = FALSE)
writeData(wb2, 1, x = "Missing data were handled by multiple imputation (m=5, CART)", startRow = nrow(tb_df)+5, startCol = 1, colNames = FALSE, rowNames = FALSE)
addStyle(wb2, 1, botOdd, rows = nrow(tb_df)+3, cols = 1:nc, gridExpand = TRUE)
addStyle(wb2, 1, botCenter, rows = nrow(tb_df)+4, cols = 1:nc, gridExpand = TRUE)
addStyle(wb2, 1, botEven, rows = nrow(tb_df)+5, cols = 1:nc, gridExpand = TRUE)
setColWidths(wb2, 1, cols = 1:nc, widths = "auto")

file_name <- "Table 1-ELSA. Baseline characteristics.xlsx"
saveWorkbook(wb2, file = file_name, overwrite = TRUE)
write.csv(tb_df, file.path(sub("\\.xlsx$",".csv", basename(file_name))), row.names = FALSE)
cat("已保存:", file_name, "  +  ELSA/csv/", sub("\\.xlsx$",".csv", basename(file_name)), "\n")
cat("\n==================== C06 ELSA 完成 ====================\n")
