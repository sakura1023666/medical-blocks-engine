#!/usr/bin/env Rscript
## 暴露不当 assoc 协变量，但必须进入 LASSO/Boruta 所用的 Model2Factors 候选池
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/ml_dual_pipeline_helpers.R"), local = FALSE)

cx <- list(
  config = list(
    prediction = list(index_vars = c("Preop_Cr")),
    feature_selection = list(restrict_to_train = FALSE)
  ),
  data = list(
    imputed = data.frame(
      Age = 1:3,
      Gender = c(0, 1, 0),
      Preop_Cr = c(0.8, 1.1, 0.9),
      Preop_Hb = c(12, 13, 11)
    )
  ),
  results = list(
    ## 模拟 VIF screen：通过名单不含暴露（故意）
    Model2Factors = c("Age", "Gender", "Preop_Hb"),
    univar_features = c("Age", "Gender", "Preop_Hb"),
    vif_screen_pass = c("Age", "Gender", "Preop_Hb")
  )
)

cx2 <- inject_feature_selection_compound_indices(cx, "Hosp")

stopifnot("Preop_Cr" %in% cx2$results$univar_features)
## 关键：LASSO 读 Model2Factors（≥3 时不再回退 univar），暴露必须在此
if (!("Preop_Cr" %in% cx2$results$Model2Factors)) {
  stop("inject 未把暴露写入 Model2Factors，LASSO/Boruta 候选池会漏掉暴露", call. = FALSE)
}

## 原有 VIF 通过变量仍保留
stopifnot(all(c("Age", "Gender", "Preop_Hb") %in% cx2$results$Model2Factors))

message("OK: inject_feature_selection_compound_indices puts exposure into Model2Factors")
