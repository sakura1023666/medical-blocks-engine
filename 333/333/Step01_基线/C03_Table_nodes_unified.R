rm(list = ls()); gc()
################################################################################
# C03_Table_nodes_unified.R —— 统一节点信息表(两队列同构 13 节点)
#   Label = Depression_1..8 + MetS_1..5(序号)
#   Items = 统一概念名(Felt Depressed / Positive Mindset [POS] / Negative Mindset / ...)
#   抑郁映射: Felt Depressed / Effort / Restless Sleep / Happy[POS]
#             + Positive Mindset [POS](CHARLS Hopeful | ELSA Enjoyed)
#             + Negative Mindset(CHARLS Fearful | ELSA Sad)
#             + Felt Lonely / Could Not Get Going;  CHARLS dc009/010 丢弃.
#   极性: 抑郁统一"高分=更抑郁"; MetS 原始尺度.   R²: mgm 可预测性.
# 输出: Table_nodes_unified_<cohort>.xlsx + .csv
################################################################################
args <- commandArgs(trailingOnly = FALSE)
fa <- grep("^--file=", args, value = TRUE)
if (length(fa) > 0) setwd(normalizePath(dirname(sub("^--file=", "", fa[1])), mustWork = FALSE))
cat("工作目录:", getwd(), "\n"); options(width = 220)
suppressPackageStartupMessages({ library(mgm); library(openxlsx) })

COHORTS <- c("CHARLS", "ELSA")
UNIFIED <- list(
  list(name="Felt Depressed",           CHARLS=c(dc011="Felt Depressed"),             ELSA=c(PScedA="Felt Depressed")),
  list(name="Everything Was an Effort", CHARLS=c(dc012="Everything Was an Effort"),   ELSA=c(PScedB="Everything Was an Effort")),
  list(name="Restless Sleep",           CHARLS=c(dc015="Restless Sleep"),             ELSA=c(PScedC="Restless Sleep")),
  list(name="Happy [POS]",              CHARLS=c(dc016="Happy [POS]"),                ELSA=c(PScedD="Happy [POS]")),
  list(name="Positive Mindset [POS]",   CHARLS=c(dc013="Hopeful About Future [POS]"), ELSA=c(PScedF="Enjoyed Life [POS]")),
  list(name="Negative Mindset",         CHARLS=c(dc014="Felt Fearful"),               ELSA=c(PScedG="Felt Sad")),
  list(name="Felt Lonely",              CHARLS=c(dc017="Felt Lonely"),                ELSA=c(PScedE="Felt Lonely")),
  list(name="Could Not Get Going",      CHARLS=c(dc018="Could Not Get Going"),        ELSA=c(PScedH="Could Not Get Going")))
METS_RAW <- c(waist_cm="Waist Circumference (cm)", hdl_mgdl="HDL-Cholesterol (mg/dL)",
              tg_mgdl="Triglycerides (mg/dL)", meanSBP="Systolic Blood Pressure (mmHg)",
              glu_mgdl="Fasting Glucose (mg/dL)")

pred_r2 <- function(dat) {
  P <- ncol(dat); M <- data.matrix(dat)
  tryCatch({
    fit <- mgm::mgm(M, type = rep("g", P), levels = rep(1, P), k = 2, lambdaSel = "EBIC", ruleReg = "AND", verb = FALSE)
    pr  <- predict(fit, M, errorCon = c("RMSE","R2"))
    setNames(pr$errors$R2, colnames(dat))
  }, error = function(e) { message("  mgm 失败: ", conditionMessage(e)); rep(NA_real_, P) })
}

for (coh in COHORTS) {
  cat("\n==================== ", coh, " ====================\n")
  load(paste0("D01_AfterMI_Data_", coh, ".RData"))   # -> data_imp
  df <- data_imp
  dep_map  <- setNames(lapply(UNIFIED, `[[`, coh), sapply(UNIFIED, `[[`, "name"))  # 概念名 -> c(源列名=源标签)
  dep_cols <- unname(sapply(dep_map, function(x) names(x)))   # 源列名(dc011 ...)
  mets_cols <- names(METS_RAW)
  cols <- c(dep_cols, mets_cols)
  dat <- df[complete.cases(df[, cols]), cols, drop = FALSE]
  cat("N =", nrow(dat), "| 节点 =", ncol(dat), "(8 抑郁 + 5 MetS)\n")

  # 极性统一(8 抑郁): 与其余抑郁条目总和负相关者反向 -> 全部"高分=更抑郁"
  for (i in seq_along(dep_cols)) {
    cn <- dep_cols[i]
    others <- rowSums(dat[, dep_cols[-i], drop = FALSE], na.rm = TRUE)
    r <- cor(dat[[cn]], others, use = "pairwise.complete.obs")
    if (!is.na(r) && r < 0) dat[[cn]] <- max(dat[[cn]], na.rm = TRUE) - dat[[cn]]
  }

  # log 变换 MetS_4(收缩压 meanSBP) + MetS_5(空腹血糖 glu_mgdl)
  log_mets <- intersect(c("tg_mgdl","meanSBP","glu_mgdl"), mets_cols)
  for (cn in log_mets) dat[[cn]] <- if (any(dat[[cn]] <= 0, na.rm = TRUE)) log1p(dat[[cn]]) else log(dat[[cn]])

  Mean <- vapply(dat, mean, na.rm = TRUE, numeric(1))
  SD   <- vapply(dat, sd,   na.rm = TRUE, numeric(1))
  r2   <- pred_r2(dat)

  Label <- c(paste0("Depression_", seq_along(dep_cols)), paste0("MetS_", seq_along(mets_cols)))
  mets_items <- unname(METS_RAW)
  log_pos <- which(names(METS_RAW) %in% c("tg_mgdl","meanSBP","glu_mgdl"))   # MetS_3, MetS_4, MetS_5
  mets_items[log_pos] <- paste0(mets_items[log_pos], " (log)")
  Items <- c(names(dep_map), mets_items)   # 统一概念名
  tab <- data.frame(Label = Label, Items = Items,
                    Mean = round(Mean, 3), SD = round(SD, 3),
                    `Predictability (R²)` = round(r2, 3),
                    check.names = FALSE, stringsAsFactors = FALSE)
  print(tab)

  wb <- createWorkbook(); addWorksheet(wb, "Sheet1")
  hs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", textDecoration="bold", border="bottom")
  bs <- createStyle(fontSize=12, fontName="Times New Roman", halign="center", valign="center")
  writeData(wb, 1, tab, startRow = 1, colNames = TRUE, headerStyle = hs)
  addStyle(wb, 1, bs, rows = 2:(nrow(tab)+1), cols = 1:ncol(tab), gridExpand = TRUE)
  addStyle(wb, 1, createStyle(fontSize=12, fontName="Times New Roman", halign="left"),
           rows = 2:(nrow(tab)+1), cols = 2, gridExpand = TRUE)
  setColWidths(wb, 1, cols = 1:ncol(tab), widths = "auto")
  fn <- paste0("Table_nodes_unified_", coh, ".xlsx")
  saveWorkbook(wb, fn, overwrite = TRUE)
  write.csv(tab, sub("\\.xlsx$", ".csv", fn), row.names = FALSE)
  cat("已保存:", fn, "\n")
}
cat("\n==================== 统一节点信息表完成 ====================\n")
