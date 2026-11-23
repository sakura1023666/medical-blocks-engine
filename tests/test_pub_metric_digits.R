#!/usr/bin/env Rscript
## 发表数字规范：P / AUC / NRI / DeLong 矩阵；引擎强制入口
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R/utils.R"), local = FALSE)
pipeline_apply_pub_digits(list(pub_digits = list(
  est = 3L, p = 3L, desc = 3L, cutoff = 3L,
  int_big_mark = TRUE, desc_trim = TRUE, p_style = "fixed"
)))

stopifnot(identical(pub_format_p_cell(0), "<0.001"))
stopifnot(identical(pub_format_p_cell(0.0004), "<0.001"))
stopifnot(identical(pub_format_p_cell(0.97), "0.970"))
stopifnot(identical(pub_format_p_cell("0.000"), "<0.001"))
## 精确 0 保留 0.000（Sens=0 的退化 DT 不得写成 <0.001）；微小正值仍 <0.001
stopifnot(identical(pub_format_prob_metric(0), "0.000"))
stopifnot(identical(pub_format_prob_metric(0.0004), "<0.001"))
stopifnot(identical(pub_format_prob_metric(0.7901), "0.790"))
stopifnot(identical(pub_format_prob_metric(NaN), "NE"))
stopifnot(identical(pub_format_est(1.01), "1.010"))

## DeLong 矩阵规范化
df <- data.frame(
  Model = c("DT", "RF"),
  DT = c("-", "0"),
  RF = c("0.000", "-"),
  stringsAsFactors = FALSE
)
out <- pub_normalize_pub_df(
  df,
  filepath = "Table S8. DeLong tests (training set).xlsx",
  title = "DeLong tests (training set)"
)
## DeLong 矩阵格按 P 矩阵规范：裸 0 → <0.001
stopifnot(identical(out$DT[2], "<0.001"))
stopifnot(identical(out$RF[1], "<0.001"))
stopifnot(identical(out$DT[1], "-"))

## NRI 列（裸数字 + PredictABEL 长串不得打成 NE）
nri <- data.frame(
  Model = c("ENet", "MLP"),
  NRI = c("0", "0.003"),
  IDI = c("0.000", "0.066"),
  stringsAsFactors = FALSE
)
n2 <- pub_normalize_pub_df(nri, filepath = "Table S11. NRI and IDI.xlsx", title = "NRI and IDI")
stopifnot(identical(n2$NRI[1], "0.000"))
stopifnot(identical(n2$IDI[1], "0.000"))
stopifnot(identical(n2$NRI[2], "0.003"))
nri_long <- data.frame(
  `New model-Baseline model` = "RF - XGBoost",
  NRI = "NRI(Continuous) [95% CI]: 0.8211 [ 0.7534 - 0.8888 ]",
  `P value (NRI)` = "<0.001",
  IDI = "IDI [95% CI]: 0.1116 [ 0.1032 - 0.12 ]",
  `P value (IDI)` = "<0.001",
  check.names = FALSE,
  stringsAsFactors = FALSE
)
n3 <- pub_normalize_pub_df(
  nri_long,
  filepath = "Table S12. NRI and IDI (training set).xlsx",
  title = "NRI and IDI (training set)"
)
stopifnot(identical(n3$NRI[1], "0.821 (0.753, 0.889)"))
stopifnot(identical(n3$IDI[1], "0.112 (0.103, 0.120)"))
## DeLong 宽表 New model / Baseline model = AUC
dl <- data.frame(
  `New model-Baseline model` = "RF - XGBoost",
  `New model` = 0.896097302504817,
  `Baseline model` = 0.724041040462428,
  `Difference of AUC` = 0.172,
  `95% CI` = "0.159 ~ 0.185",
  `Z statistic` = 25.868,
  `P value` = "<0.001",
  check.names = FALSE,
  stringsAsFactors = FALSE
)
dl2 <- pub_normalize_pub_df(
  dl,
  filepath = "Table S10. DeLong tests (training set).xlsx",
  title = "DeLong tests (training set)"
)
stopifnot(identical(dl2[["New model"]][1], "0.896"))
stopifnot(identical(dl2[["Baseline model"]][1], "0.724"))

## 超参表不得改写 0.000237
hp <- data.frame(
  Model = "DT",
  Hyperparameter = "cost complexity=0.000237129, tree depth=4",
  stringsAsFactors = FALSE
)
hp2 <- pub_normalize_pub_df(hp, filepath = "Table S6. Hyperparameters.xlsx", title = "Hyperparameters")
stopifnot(grepl("0.000237", hp2$Hyperparameter[1], fixed = TRUE))

## P 列
reg <- data.frame(
  Variable = "Age",
  OR = 1.355,
  `P-value` = 0.0004,
  check.names = FALSE,
  stringsAsFactors = FALSE
)
r2 <- pub_normalize_pub_df(reg, filepath = "Table 2.xlsx", title = "Logistic")
stopifnot(identical(r2[["P-value"]], "<0.001"))
stopifnot(identical(r2$OR, "1.355"))

message("OK test_pub_metric_digits")
