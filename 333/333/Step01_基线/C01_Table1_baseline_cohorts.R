rm(list = ls()); gc()
################################################################################
# C01_Table1_baseline_cohorts.R —— Table 1. Baseline characteristics by cohort
# 输出: Table1_baseline_cohorts.xlsx + .csv
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(dplyr); library(openxlsx) })

COHORTS <- c("CHARLS", "ELSA")
DATA_DIR <- getwd()

var_info <- list(
  Age = list(label = "Age (years)", type = "continuous"),
  Gender = list(label = "Gender", type = "categorical"),
  Education = list(label = "Education", type = "categorical"),
  Marital_Status = list(label = "Marital status", type = "categorical"),
  # BMI = list(label = "BMI (kg/m²)", type = "continuous"),
  Smoke = list(label = "Smoking", type = "categorical"),
  Alcohol_drinking = list(label = "Alcohol drinking", type = "categorical"),
  # Hypertension = list(label = "Hypertension", type = "categorical"),
  # T2DM = list(label = "Type 2 diabetes", type = "categorical"),
  Malignant_Tumor = list(label = "Malignant tumor", type = "categorical"),
  MetS = list(label = "Metabolic syndrome", type = "categorical"),
  Dep_Flag = list(label = "Depression", type = "categorical"),
  Depression_Score = list(label = "Depression score", type = "continuous")
  # waist_cm = list(label = "Waist circumference (cm)", type = "continuous"),
  # meanSBP = list(label = "Systolic BP (mmHg)", type = "continuous"),
  # meanDBP = list(label = "Diastolic BP (mmHg)", type = "continuous"),
  # hdl_mgdl = list(label = "HDL-C (mg/dL)", type = "continuous"),
  # tg_mgdl = list(label = "Triglycerides (mg/dL)", type = "continuous"),
  # glu_mgdl = list(label = "Fasting glucose (mg/dL)", type = "continuous"),
  # HbA1c = list(label = "HbA1c (%)", type = "continuous"),
  # CRP = list(label = "CRP (mg/L)", type = "continuous"),
  # TyG = list(label = "TyG index", type = "continuous"),
  # Weight = list(label = "Weight (kg)", type = "continuous"),
  # Height = list(label = "Height (cm)", type = "continuous"),
  # HR = list(label = "Heart rate (bpm)", type = "continuous"),
  # PP = list(label = "Pulse pressure (mmHg)", type = "continuous")
)

results <- list()
sample_sizes <- c(CHARLS = 8412, ELSA = 3166)

for (coh in COHORTS) {
  cat("\n==================== ", coh, " ====================\n")
  load(file.path(DATA_DIR, paste0("D01_AfterMI_Data_", coh, ".RData")))
  df <- data_imp
  df$Depression_Score <- scale(df$Depression_Score)
  
  n_total <- nrow(df)
  cat("数据N =", n_total, "; 表中显示N =", sample_sizes[coh], "\n")
  
  coh_results <- data.frame(Variable = character(),
                            Category = character(),
                            Value = character(),
                            stringsAsFactors = FALSE)
  
  for (var_name in names(var_info)) {
    if (!var_name %in% colnames(df)) {
      cat("  跳过缺失变量:", var_name, "\n")
      next
    }
    
    var_label <- var_info[[var_name]]$label
    var_type <- var_info[[var_name]]$type
    var_data <- df[[var_name]]
    
    if (var_type == "continuous") {
      median_val <- median(var_data, na.rm = TRUE)
      p25 <- quantile(var_data, 0.25, na.rm = TRUE)
      p75 <- quantile(var_data, 0.75, na.rm = TRUE)
      coh_results <- rbind(coh_results, data.frame(
        Variable = var_label,
        Category = "",
        Value = sprintf("%.1f (%.1f, %.1f)", median_val, p25, p75),
        stringsAsFactors = FALSE))
    } else {
      if (!is.factor(var_data)) {
        var_data <- factor(var_data)
      }
      tbl <- table(var_data, useNA = "no")
      total <- sum(tbl)
      for (lev in names(tbl)) {
        n <- as.integer(tbl[lev])
        pct <- round(n / total * 100, 1)
        coh_results <- rbind(coh_results, data.frame(
          Variable = if (lev == names(tbl)[1]) var_label else "",
          Category = lev,
          Value = sprintf("%d (%.1f%%)", n, pct),
          stringsAsFactors = FALSE))
      }
    }
  }
  
  results[[coh]] <- coh_results
}

combined <- results[[COHORTS[1]]]
combined[[paste0("CHARLS (n = ", sample_sizes[COHORTS[1]], ")")]] <- combined$Value
combined$Value <- NULL

for (i in 2:length(COHORTS)) {
  coh <- COHORTS[i]
  combined[[paste0(coh, " (n = ", sample_sizes[coh], ")")]] <- results[[coh]]$Value
}

write.csv(combined, "Table1_baseline_cohorts.csv", row.names = FALSE)

wb <- createWorkbook()
addWorksheet(wb, "Sheet1")

hs <- createStyle(fontSize = 12, fontName = "Times New Roman", 
                  halign = "center", textDecoration = "bold")
bs <- createStyle(fontSize = 11, fontName = "Times New Roman", 
                  halign = "left", valign = "center")
bc <- createStyle(fontSize = 11, fontName = "Times New Roman", 
                  halign = "center", valign = "center")

writeData(wb, 1, "Table 1. Baseline characteristics of the study populations in CHARLS and ELSA.", 
          startRow = 1, colNames = FALSE)
mergeCells(wb, 1, rows = 1, cols = 1:ncol(combined))
addStyle(wb, 1, hs, rows = 1, cols = 1:ncol(combined), gridExpand = TRUE)

col_headers <- colnames(combined)
writeData(wb, 1, col_headers, startRow = 2, colNames = FALSE)
addStyle(wb, 1, hs, rows = 2, cols = 1:ncol(combined), gridExpand = TRUE)

for (row_idx in 1:nrow(combined)) {
  writeData(wb, 1, combined[row_idx, ], startRow = row_idx + 2, colNames = FALSE)
}

addStyle(wb, 1, bs, rows = 3:(nrow(combined) + 2), cols = 1:2, gridExpand = TRUE)
addStyle(wb, 1, bc, rows = 3:(nrow(combined) + 2), cols = 3:ncol(combined), gridExpand = TRUE)

for (rr in (nrow(combined) + 3):(nrow(combined) + 5)) {
  mergeCells(wb, 1, rows = rr, cols = 1:ncol(combined))
}
writeData(wb, 1, "Data presented as median (IQR) for continuous variables and n (%) for categorical variables.", 
          startRow = nrow(combined) + 3, colNames = FALSE)
writeData(wb, 1, "CHARLS = China Health and Retirement Longitudinal Study; ELSA = English Longitudinal Study of Ageing.", 
          startRow = nrow(combined) + 4, colNames = FALSE)

setColWidths(wb, 1, cols = 1:ncol(combined), widths = "auto")

saveWorkbook(wb, "Table1_baseline_cohorts.xlsx", overwrite = TRUE)
cat("\n已保存: Table1_baseline_cohorts.xlsx + .csv\n")
cat("\n==================== Table1 完成 ====================\n")
