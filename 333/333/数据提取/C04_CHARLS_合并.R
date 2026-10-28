rm(list = ls()); gc()
################################################################################
# C04_CHARLS_合并.R  ——  合并 基线 + 抑郁 + 代谢综合征 → 分析数据集
# 分析队列 = 有完整 MetS 数据者(N≈8449, 年龄≥45, 有血检)
# 输出: D02_CHARLS_MetS.RData (对象 CHARLS)
################################################################################
# 稳健 setwd: 兼容 RStudio / 命令行(从 --file= 解析脚本目录)
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
load("./CHARLS/D01_baseline_CHARLS_2011_0610.RData")            # baseline: 人口学/临床/血检/认知
base <- baseline %>% mutate(ID = as.character(ID)) %>% select(-any_of(c("wave")))

dep <- read.csv("CHARLS/CHARLS_2011_抑郁.csv", stringsAsFactors = FALSE) %>%
  mutate(ID = as.character(ID)) %>%
  rename(Depression_Score = cesd10_total, Dep_Flag = DN)   # 抑郁DN→Dep_Flag (避免与MetS的DN撞名)

mets <- read.csv("CHARLS_2011_代谢综合征.csv", stringsAsFactors = FALSE) %>%
  mutate(ID = as.character(ID)) %>%
  rename(MetS = DN)                                        # MetS的DN→MetS(主分组变量)

cat("基线:", nrow(base), " 抑郁:", nrow(dep), " MetS:", nrow(mets), "\n")

# ========================= 2) 以 MetS 队列为主合并 =========================
CHARLS <- mets %>%
  left_join(dep,  by = "ID") %>%
  left_join(base, by = "ID")
cat("合并后维度:", dim(CHARLS), "\n")
cat("同时有 MetS+抑郁:", sum(!is.na(CHARLS$Depression_Score)), "\n")

# ========================= 3) 列名冲突清理 =========================
# baseline 与 MetS 重叠的 Glucose/HDL/TG/Waist/BP/性别 → 删 baseline 侧, 保留 MetS 官方组分
drop_dup <- intersect(c("Glucose","HDL","LDL","TG","TC","Waist_circumstance",
                        "NBPS","NBPD","rgender","sex","Smoke.x","Alcohol_drinking.x",
                        "Age.x","Gender.x"), colnames(CHARLS))
CHARLS <- CHARLS %>% select(-any_of(drop_dup))
# 去掉合并产生的 .x/.y 后缀冲突列 (优先保 baseline 的)
xcols <- grep("\\.x$", colnames(CHARLS), value = TRUE)
ycols <- sub("\\.y$", "", xcols)
# .x 列改回原名, .y 列若同名则删
for (xc in xcols) {
  base_name <- sub("\\.x$", "", xc)
  yc <- paste0(base_name, ".y")
  if (yc %in% colnames(CHARLS)) CHARLS[[yc]] <- NULL   # 去掉 .y 重复
  colnames(CHARLS)[colnames(CHARLS) == xc] <- base_name
}
# 残留 .y 列(MetS侧Age等被drop_dup删后, baseline侧的Age.y) 改回干净名
ycols <- grep("\\.y$", colnames(CHARLS), value = TRUE)
for (yc in ycols) colnames(CHARLS)[colnames(CHARLS) == yc] <- sub("\\.y$", "", yc)
cat("清理冲突后维度:", dim(CHARLS), "\n\n")

# ========================= 4) 缺失情况体检 =========================
cat("========== 各变量缺失率 ==========\n")
miss <- sapply(CHARLS, function(x) mean(is.na(x)))
miss_df <- data.frame(var = names(miss), miss_pct = round(100*miss, 1))
miss_df <- miss_df[order(-miss_df$miss_pct), ]
print(miss_df, row.names = FALSE)

drop_cols <- names(miss)[miss > 0.4]
keep_cols <- names(miss)[miss <= 0.4]
cat("\n缺失>40% 将在插补前剔除的列:", if(length(drop_cols)) paste(drop_cols, collapse=", ") else "无", "\n")

# ========================= 5) 保存分析数据集 =========================
# 先保留全列保存一份(含>40%缺失列, 供参考), 再存一份过滤后版本供插补
save(CHARLS, file = "D02_CHARLS_MetS.RData")
cat("\n已保存分析数据集: D02_CHARLS_MetS.RData (维度:", dim(CHARLS), ")\n")
cat("分析队列 N =", nrow(CHARLS), "(MetS 完整病例队列, 年龄≥45)\n")
cat("\n关键变量:\n")
cat("  MetS(0/1):", sum(CHARLS$MetS==0), "vs", sum(CHARLS$MetS==1), "\n")
cat("  Dep_Flag(0/1):", sum(CHARLS$Dep_Flag==0,na.rm=T), "vs", sum(CHARLS$Dep_Flag==1,na.rm=T), "\n")
cat("  CESD 条目(网络节点):", paste(grep("^dc0", colnames(CHARLS), value=TRUE), collapse=","), "\n")
