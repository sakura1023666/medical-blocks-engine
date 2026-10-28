rm(list = ls()); gc()
################################################################################
# C04_ELSA_合并.R  ——  合并 基线 + 抑郁 + 代谢综合征 → ELSA 分析数据集
# 镜像 C04_CHARLS_合并.R 的逻辑; 分析队列 = ELSA MetS 完整病例(N≈3166)
# 输出: D02_ELSA_MetS.RData (对象 ELSA)
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
suppressPackageStartupMessages({ library(dplyr) })

# ========================= 1) 读取三源 =========================
load("D01_baseline_ELSA_2012_0610.RData")               # ELSA 标准化基线(根目录)
base <- baseline %>% mutate(ID = as.character(ID)) %>% select(-any_of(c("wave")))

dep <- read.csv("ELSA/ELSA_wave6_抑郁.csv", stringsAsFactors = FALSE) %>%
  mutate(ID = as.character(idauniq)) %>%
  select(-idauniq) %>%
  rename(Depression_Score = cesd8_total, Dep_Flag = DN)   # 抑郁DN→Dep_Flag

mets <- read.csv("ELSA_2012_代谢综合征.csv", stringsAsFactors = FALSE) %>%
  mutate(ID = as.character(ID)) %>%
  rename(MetS = DN)                                        # MetS的DN→MetS(主分组变量)

cat("基线:", nrow(base), " 抑郁:", nrow(dep), " MetS:", nrow(mets), "\n")

# ========================= 2) 以 MetS 队列为主合并 =========================
ELSA <- mets %>%
  left_join(dep,  by = "ID") %>%
  left_join(base, by = "ID")
cat("合并后维度:", dim(ELSA), "\n")
cat("同时有 MetS+抑郁:", sum(!is.na(ELSA$Depression_Score)), "\n")

# ========================= 3) 列名冲突清理 =========================
# baseline 与 MetS 重叠列删 baseline 侧(MetS 官方组分名不同: waist_cm vs Waist_circumstance 等, 仅 Age 直接撞)
drop_dup <- intersect(c("Glucose","HDL","LDL","TG","TC","Waist_circumstance",
                        "NBPS","NBPD","rgender","sex","Age.x","Gender.x"), colnames(ELSA))
ELSA <- ELSA %>% select(-any_of(drop_dup))
xcols <- grep("\\.x$", colnames(ELSA), value = TRUE)
for (xc in xcols) {
  base_name <- sub("\\.x$", "", xc)
  yc <- paste0(base_name, ".y")
  if (yc %in% colnames(ELSA)) ELSA[[yc]] <- NULL
  colnames(ELSA)[colnames(ELSA) == xc] <- base_name
}
ycols <- grep("\\.y$", colnames(ELSA), value = TRUE)
for (yc in ycols) colnames(ELSA)[colnames(ELSA) == yc] <- sub("\\.y$", "", yc)
cat("清理冲突后维度:", dim(ELSA), "\n\n")

# ========================= 4) 缺失情况体检 =========================
cat("========== 各变量缺失率 ==========\n")
miss <- sapply(ELSA, function(x) mean(is.na(x)))
miss_df <- data.frame(var = names(miss), miss_pct = round(100*miss, 1))
miss_df <- miss_df[order(-miss_df$miss_pct), ]
print(miss_df, row.names = FALSE)
drop_cols <- names(miss)[miss > 0.4]
cat("\n缺失>40% 将在插补前剔除的列:", if(length(drop_cols)) paste(drop_cols, collapse=", ") else "无", "\n")

# ========================= 5) 保存分析数据集 =========================
save(ELSA, file = "D02_ELSA_MetS.RData")
cat("\n已保存分析数据集: D02_ELSA_MetS.RData (维度:", dim(ELSA), ")\n")
cat("分析队列 N =", nrow(ELSA), "(ELSA MetS 完整病例, 年龄≥45)\n")
cat("  MetS(0/1):", sum(ELSA$MetS==0), "vs", sum(ELSA$MetS==1), "\n")
cat("  Dep_Flag(0/1):", sum(ELSA$Dep_Flag==0,na.rm=T), "vs", sum(ELSA$Dep_Flag==1,na.rm=T), "\n")
cat("  CESD-8 条目(网络节点):", paste(grep("^PSced|^psced", colnames(ELSA), value=TRUE), collapse=","), "\n")
