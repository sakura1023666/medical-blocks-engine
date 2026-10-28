rm(list = ls()); gc()
################################################################################
# Table1_baseline.R  ——  基线特征表(按 MetS 分组)· CHARLS + ELSA
#   ★ 仅保留两队列共有变量(交集); 单队列独有变量删除.
#   ★ 变量名与单位统一(英文标签 + 单位); Education 水平统一; 因子尾空格 trim.
# 数据 : D01_AfterMI_Data_<cohort>.RData   输出 : Table1_<cohort>_baseline.xlsx + .csv
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(dplyr); library(gtsummary); library(openxlsx) })

COHORTS <- c("CHARLS", "ELSA")
# ---- 两队列共有变量(交集; 排除 CESD 条目/MetS 判定/ID/单队列独有) ----
common_vars <- c(
  "Age","Gender","Education","Marital_Status","Smoke","Alcohol_drinking",
  "BMI","Weight","Height","waist_cm","meanSBP","meanDBP","HR","PP",
  "hdl_mgdl","tg_mgdl","glu_mgdl","HbA1c",
  "WBC","Hemoglobin","CRP","TyG","TyGBMI",
  "Hypertension","T2DM","Malignant_Tumor",
  "Depression_Score","Dep_Flag")
# ---- 统一英文标签 + 单位 ----
var_label <- c(
  Age="Age (years)", Gender="Gender", Education="Education", Marital_Status="Marital status",
  Smoke="Smoking", Alcohol_drinking="Alcohol drinking",
  BMI="BMI (kg/m²)", Weight="Weight (kg)", Height="Height (cm)",
  waist_cm="Waist circumference (cm)", meanSBP="Systolic BP (mmHg)", meanDBP="Diastolic BP (mmHg)",
  HR="Heart rate (bpm)", PP="Pulse pressure (mmHg)",
  hdl_mgdl="HDL-C (mg/dL)", tg_mgdl="Triglycerides (mg/dL)", glu_mgdl="Fasting glucose (mg/dL)",
  HbA1c="HbA1c (%)", WBC="WBC (×10⁹/L)", Hemoglobin="Hemoglobin (g/dL)", CRP="CRP (mg/L)",
  TyG="TyG index", TyGBMI="TyGBMI index",
  Hypertension="Hypertension", T2DM="Type 2 diabetes", Malignant_Tumor="Malignant tumor",
  Depression_Score="Depression score", Dep_Flag="Depression (Dep_Flag)")

for (coh in COHORTS) {
  cat("\n==================== ", coh, " ====================\n")
  # coh <- COHORTS[1]
  load(paste0("D01_AfterMI_Data_", coh, ".RData"))   # -> data_imp
  df <- data_imp
  df$Depression_Score <- scale(df$Depression_Score)
  vars <- intersect(common_vars, colnames(df))        # 只取两队列都有且本队列存在的
  dropped <- setdiff(common_vars, colnames(df))
  if (length(dropped)) cat("  本队列缺失(跳过):", paste(dropped, collapse=", "), "\n")
  df <- df[, c(vars, "MetS")]
  df <- na.omit(df)
  # 分类列: trim 尾空格 + 统一 Education 水平
  for (v in vars) {
    if (!is.numeric(df[[v]])) {
      df[[v]] <- factor(trimws(as.character(df[[v]])))
      if (v == "Education")
        levels(df[[v]])[levels(df[[v]]) == "High school and above"] <- "Above High school"
    }
  }
  if ("Dep_Flag" %in% vars && is.numeric(df$Dep_Flag))
    df$Dep_Flag <- factor(df$Dep_Flag, levels = c(0,1), labels = c("No","Yes"))
  df$MetS <- factor(df$MetS, levels = c(0,1), labels = c("Non-MetS","MetS"))
  cat("N =", nrow(df), "; MetS:\n"); print(table(df$MetS))

  tb <- df %>%
    tbl_summary(by = MetS, include = all_of(vars),
      label = as.list(var_label[vars]),
      type  = list(Depression_Score ~ "continuous", all_dichotomous() ~ "categorical"),
      digits= list(all_continuous() ~ 2),
      statistic = list(all_continuous() ~ "{median} ({p25},{p75})",
                       all_categorical() ~ "{n} ({p}%)")) %>%
    add_p(pvalue_fun = ~ style_pvalue(.x, digits = 3)) %>%
    add_overall(last = FALSE) %>%
    modify_header(label ~ "**Variable**") %>%
    modify_spanning_header(c(stat_1, stat_2) ~ "**Baseline**") %>%
    modify_footnote(all_stat_cols() ~ "Median (IQR) or Frequency (%)") %>%
    modify_caption(paste0("**Table 1-", coh, ". Baseline Characteristics by MetS Status (common variables).**")) %>%
    bold_labels()

  tb_df <- as.data.frame(tb)
  rwu <- grep("^_.*_$", tb_df[,1])
  if (length(rwu)) tb_df[rwu,1] <- gsub("^_+|_+$", "", tb_df[rwu,1])
  colnames(tb_df) <- gsub("\\*\\*", "", colnames(tb_df))
  tb_df[,1] <- gsub("_", " ", tb_df[,1])

  wb <- createWorkbook(); addWorksheet(wb, "Sheet1")
  hs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border="bottom")
  bs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", valign="center", border=c("top","bottom"), borderStyle="thin")
  bl <- createStyle(fontSize=12, fontName="Times New Roman", halign="left",  valign="center", textDecoration="bold", border=c("top","bottom"), borderStyle="thin")
  nc <- ncol(tb_df)
  writeData(wb, 1, x = paste0("Table 1-", coh, ". Baseline characteristics by Metabolic Syndrome status (common variables only)"),
            startRow = 1, colNames = FALSE)
  mergeCells(wb, 1, rows = 1, cols = 1:nc); addStyle(wb, 1, hs, rows = 1, cols = 1:nc, gridExpand = TRUE)
  writeData(wb, 1, x = tb_df, startRow = 2, colNames = TRUE)
  addStyle(wb, 1, hs, rows = 2, cols = 1:nc, gridExpand = TRUE)
  addStyle(wb, 1, bs, rows = 3:(nrow(tb_df)+2), cols = 1:nc, gridExpand = TRUE)
  if (length(rwu)) addStyle(wb, 1, bl, rows = rwu + 2, cols = 1, gridExpand = TRUE)
  for (rr in (nrow(tb_df)+3):(nrow(tb_df)+6)) mergeCells(wb, 1, rows = rr, cols = 1:nc)
  writeData(wb, 1, x = "Median (IQR) or Frequency (%)",                                                              startRow = nrow(tb_df)+3, colNames = FALSE)
  writeData(wb, 1, x = "Wilcoxon rank sum test; Pearson's Chi-squared test",                                         startRow = nrow(tb_df)+4, colNames = FALSE)
  writeData(wb, 1, x = "Missing data handled by multiple imputation (m=5, CART)",                                    startRow = nrow(tb_df)+5, colNames = FALSE)
  writeData(wb, 1, x = "Restricted to variables common to both cohorts; names & units unified. Depression score: CHARLS CESD-10 (0-30), ELSA CESD-8 (0-8) — not directly comparable across cohorts.",
            startRow = nrow(tb_df)+6, colNames = FALSE)
  setColWidths(wb, 1, cols = 1:nc, widths = "auto")

  fn <- paste0("Table1_", coh, "_baseline.xlsx")
  saveWorkbook(wb, fn, overwrite = TRUE)
  write.csv(tb_df, sub("\\.xlsx$", ".csv", fn), row.names = FALSE)
  cat("已保存:", fn, "\n")
}
cat("\n==================== 基线表完成 ====================\n")
