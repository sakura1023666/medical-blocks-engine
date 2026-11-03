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
stopifnot(identical(pub_format_prob_metric(0), "<0.001"))
stopifnot(identical(pub_format_prob_metric(0.7901), "0.790"))
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
stopifnot(identical(out$DT[2], "<0.001"))
stopifnot(identical(out$RF[1], "<0.001"))
stopifnot(identical(out$DT[1], "-"))

## NRI 列
nri <- data.frame(
  Model = c("ENet", "MLP"),
  NRI = c("0", "0.003"),
  IDI = c("0.000", "0.066"),
  stringsAsFactors = FALSE
)
n2 <- pub_normalize_pub_df(nri, filepath = "Table S11. NRI and IDI.xlsx", title = "NRI and IDI")
stopifnot(identical(n2$NRI[1], "<0.001"))
stopifnot(identical(n2$IDI[1], "<0.001"))
stopifnot(identical(n2$NRI[2], "0.003"))

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
