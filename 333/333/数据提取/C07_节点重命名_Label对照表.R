rm(list = ls()); gc()
################################################################################
# C07_节点重命名_Label对照表.R
# 把抑郁条目 → Depression_1..N, MetS 组分 → MetS_1..5, 并生成论文风格的 Label/Items 对照表
# 数据源: 合并后观测值 D02_*_MetS.RData (节点用完整病例, 不用插补值)
# 输出: 各队列 network 节点矩阵(RData+csv) + 节点Label对照表(xlsx+csv)
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
suppressPackageStartupMessages({ library(dplyr); library(openxlsx) })

# ===================== 标签映射 (CHARLS CESD-10 来自 .dta 权威标签) =====================
# CESD-10: 标★为积极条目(原始高分=状态好), 网络解读时注意极性相反
CHARLS_DEP <- c(
  dc009 = "Bothered by Things",
  dc010 = "Trouble Keeping Mind on Things",
  dc011 = "Felt Depressed",
  dc012 = "Everything Was an Effort",
  dc013 = "Hopeful About Future ★(positive)",   # 积极条目
  dc014 = "Felt Fearful",
  dc015 = "Restless Sleep",
  dc016 = "Happy ★(positive)",                   # 积极条目
  dc017 = "Felt Lonely",
  dc018 = "Could Not Get Going"
)
# ELSA CESD-8: 标准 HRS/ELSA 映射 (待与 ELSA codebook 核对)
ELSA_DEP <- c(
  PScedA = "Felt Depressed",
  PScedB = "Everything Was an Effort",
  PScedC = "Restless Sleep",
  PScedD = "Happy ★(positive)",
  PScedE = "Felt Lonely",
  PScedF = "Enjoyed Life ★(positive)",
  PScedG = "Felt Sad",
  PScedH = "Could Not Get Going"
)
# MetS 5 组分 (两队列通用)
METS_MAP <- c(
  waist_cm = "Waist Circumference (cm)",
  hdl_mgdl = "HDL-Cholesterol (mg/dL)",
  tg_mgdl  = "Triglycerides (mg/dL)",
  meanSBP  = "Systolic Blood Pressure (mmHg)",
  glu_mgdl = "Fasting Glucose (mg/dL)"
)

# ===================== 处理函数 =====================
process_cohort <- function(cohort, rdata, dep_map){
  cat("\n================== ", cohort, " ==================\n")
  e <- new.env(); load(rdata, envir=e)
  df <- get(ls(e)[1], envir=e)

  # 节点完整病例 (网络入组标准: 节点观测值齐全, 不依赖插补)
  node_cols <- c(names(dep_map), names(METS_MAP))
  node_cols <- intersect(node_cols, colnames(df))
  before <- nrow(df)
  df_n <- df[complete.cases(df[, node_cols]), , drop=FALSE]
  cat("节点完整病例:", before, "->", nrow(df_n), "\n")

  # 重命名: 抑郁 -> Depression_1..N, MetS -> MetS_1..5
  dep_present <- intersect(names(dep_map), colnames(df_n))
  new_names <- c(setNames(paste0("Depression_", seq_along(dep_present)), dep_present),
                 setNames(paste0("MetS_", seq_along(METS_MAP)), names(METS_MAP)))
  net <- df_n[, names(new_names), drop=FALSE]
  colnames(net) <- as.character(new_names)

  # 保存网络节点矩阵
  saveRDS(net, paste0(cohort, "_network_nodes.rds"))
  write.csv(net, paste0(cohort, "_network_nodes.csv"), row.names=FALSE)
  cat("已保存:", cohort, "_network_nodes.csv/rds (", ncol(net), "节点, N=", nrow(net), ")\n", sep="")

  # 构造该队列的 Label/Items 表
  lab_df <- data.frame(
    Cohort = cohort,
    Label  = c(paste0("Depression_", seq_along(dep_present)),
               paste0("MetS_", seq_along(METS_MAP))),
    Items  = c(dep_map[dep_present], unname(METS_MAP)),
    stringsAsFactors = FALSE
  )
  lab_df
}

# ===================== 两队列分别处理 =====================
lab_charls <- process_cohort("CHARLS", "D02_CHARLS_MetS.RData", CHARLS_DEP)
lab_elsa   <- process_cohort("ELSA",   "D02_ELSA_MetS.RData",   ELSA_DEP)
lab_all <- rbind(lab_charls, lab_elsa)

# ===================== 输出 Label/Items 对照表 (论文风格) =====================
write.csv(lab_all, "节点Label_Items对照表.csv", row.names=FALSE)

wb <- createWorkbook(); addWorksheet(wb, "Label-Items")
hs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center",
                  textDecoration="bold", border="bottom")
bs <- createStyle(fontSize=12, fontName="Times New Roman", halign="left", valign="center")
writeData(wb, 1, x = lab_all, startRow=1, startCol=1, colNames=TRUE, rowNames=FALSE)
addStyle(wb, 1, hs, rows=1, cols=1:3, gridExpand=TRUE)
addStyle(wb, 1, bs, rows=2:(nrow(lab_all)+1), cols=1:3, gridExpand=TRUE)
setColWidths(wb, 1, cols=1:3, widths=c(12,16,42))
saveWorkbook(wb, "节点Label_Items对照表.xlsx", overwrite=TRUE)

cat("\n========== 节点 Label/Items 对照表 ==========\n")
print(lab_all, row.names=FALSE)
cat("\n已保存: 节点Label_Items对照表.xlsx / .csv\n")
cat("注: ★积极条目(高分=状态好), 网络中与其他抑郁条目极性相反; 如需统一极性可反向计分\n")
cat("注: ELSA CESD-8 标签为标准 HRS/ELSA 映射, 建议与 ELSA codebook 核对\n")
cat("\n==================== C07 完成 ====================\n")
