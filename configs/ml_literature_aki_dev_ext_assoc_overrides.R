###############################################################################
# 文献对齐 AKI 双库预后 ML 套路 — Table2 Model1–3 协变量片段
#
# 用法：在课题 config.R 中 source 本文件，或复制 modifyList 段。
# 对应决策树：Decisiontree/decision_tree_ml_dual_prognosis_aki_dev_ext.md · D5
#
# Model 1: unadjusted
# Model 2: Age + Sex/Gender
# Model 3: clinical_covariates ∩ UV-significant ∩ VIF-pass (VIF < 5)
#
# 不改全局 ml_dual_shared_overrides 默认铁律；仅本套路 opt-in。
###############################################################################

## AKI ICU 临床有意义底稿（映射 PMID 文献 Model3；课题按 _column_review 裁剪）
## 禁止写入 Acute_Renal_Failure / AKI 诊断旗标等结局泄漏列。
.ml_literature_aki_clinical_covariates_default <- function() {
  c(
    "GCS", "APSIII", "OASIS",
    "SpO2", "Lactate", "PH", "pH",
    "Creatinine", "BUN", "PT", "INR",
    "Hemoglobin", "HB", "Hb",
    "Heart_Failure", "Ventilation",
    "MAP", "WBC", "Glucose", "CCI", "Charlson"
  )
}

ml_literature_aki_dev_ext_apply_assoc_overrides <- function(config,
                                                           clinical_covariates = NULL,
                                                           sex_var = "Gender") {
  if (is.null(clinical_covariates)) {
    clinical_covariates <- .ml_literature_aki_clinical_covariates_default()
  }
  clinical_covariates <- unique(as.character(clinical_covariates))
  clinical_covariates <- clinical_covariates[nzchar(clinical_covariates)]
  config$assoc_covariate <- modifyList(
    config$assoc_covariate %||% list(),
    list(
      enable = TRUE,
      scheme = "literature_m123",
      force_model1 = "Age",
      sex_var = as.character(sex_var)[1L],
      clinical_covariates = clinical_covariates,
      demo_uv_to_model1 = FALSE,
      uv_source = "tb1",
      model2_from_vif_pass = TRUE,
      allow_ml_features_in_model2 = TRUE,
      allow_m2_eq_m1 = TRUE,
      model2_exclude = character(0)
    )
  )
  config
}
