# tests/test_ml_assoc_covariate_rule.R
source("R/ml_assoc_covariate_rule.R")
source("R/ml_dual_pipeline_helpers.R")

ctx <- list(
  config = list(
    assoc_covariate = list(
      enable = TRUE,
      force_model1 = "Age",
      demo_uv_to_model1 = TRUE,
      demo_keywords = c("Height", "Weight", "BMI"),
      model2_exclude = character(0),
      uv_source = "tb1"
    ),
    data = list(outcome_column = "hypothermia"),
    ml_batch = list(current_index = "Preop_Cr")
  ),
  results = list(
    tb1 = c("Weight", "Preop_Htn", "Asa"),
    feature_selection_final = c("Asa")
  )
)
res <- ml_resolve_assoc_covariates(ctx)
stopifnot(identical(sort(res$M1), sort(c("Age", "Weight"))))
stopifnot("Weight" %in% res$M1)
stopifnot(!"Height" %in% res$M1)
stopifnot(identical(res$extras, "Preop_Htn"))
stopifnot(!"Weight" %in% res$extras)

ctx2 <- list(
  config = list(
    assoc_covariate = list(
      enable = TRUE,
      force_model1 = "Age",
      demo_uv_to_model1 = TRUE,
      demo_keywords = c("Gender", "Sex", "Height", "Weight", "BMI"),
      model2_exclude = character(0),
      uv_source = "tb1"
    ),
    data = list(outcome_column = "hypothermia"),
    ml_batch = list(current_index = "Preop_Cr")
  ),
  results = list(
    tb1 = c("Weight", "Gender", "Preop_Htn", "Asa"),
    feature_selection_final = c("Gender", "Asa")
  )
)
res2 <- ml_resolve_assoc_covariates(ctx2)
stopifnot(all(c("Age", "Weight", "Gender") %in% res2$M1))
stopifnot(!"Gender" %in% res2$extras)

cfg_def <- ml_assoc_covariate_cfg(list())
stopifnot(identical(cfg_def$force_model1, "Age"))
stopifnot(length(cfg_def$model2_exclude) == 0L)

ctx3 <- list(
  config = list(
    assoc_covariate = list(
      enable = TRUE,
      force_model1 = "Age",
      model2_from_vif_pass = TRUE,
      allow_ml_features_in_model2 = TRUE,
      demo_uv_to_model1 = FALSE
    ),
    data = list(outcome_column = "Disease_Group"),
    ml_batch = list(current_index = "sdLDL_C")
  ),
  results = list(
    vif_screen_pass = c("Age", "SBP", "WBC", "Glucose", "Diabetes", "sdLDL_C"),
    feature_selection_final = c("SBP", "Glucose", "sdLDL_C")
  )
)
res3 <- ml_resolve_assoc_covariates(ctx3)
stopifnot(identical(sort(res3$M1), "Age"))
stopifnot(all(c("SBP", "Glucose", "Diabetes") %in% res3$M2))
stopifnot(!"sdLDL_C" %in% res3$M2)
stopifnot(all(c("SBP", "Glucose") %in% res3$ml_in_model2))

## 外验继承主库训练集 M1/M2，禁止再解析成只剩 Age
ctx_inh <- list(
  config = list(
    assoc_covariate = list(enable = TRUE, force_model1 = "Age"),
    data = list(outcome_column = "AKI")
  ),
  results = list(
    assoc_covariates_inherited_from = "primary",
    assoc_model1_factors = c("Age", "Gender", "Race"),
    assoc_model2_factors = c("Age", "Gender", "Race", "SBP", "WBC"),
    assoc_covariate_note = "继承主库训练集",
    tb1 = "Age",
    feature_selection_final = c("SBP")
  ),
  data = list(imputed = data.frame(
    Age = 1:4, Gender = 1:4, Race = 1:4, SBP = 1:4, WBC = 1:4, AKI = 0:3
  ))
)
locked <- ml_assoc_locked_preset_models(ctx_inh)
stopifnot(identical(locked$source, "primary_inherit"))
stopifnot(all(c("Age", "Gender", "Race") %in% locked$M1))
stopifnot(all(c("SBP", "WBC") %in% locked$M2))
ctx_inh2 <- ml_apply_assoc_covariate_rule_to_ctx(ctx_inh)
stopifnot(all(c("Age", "Gender", "Race") %in% ctx_inh2$results$assoc_model1_factors))
stopifnot(all(c("SBP", "WBC") %in% ctx_inh2$results$assoc_model2_factors))
stopifnot(all(c("Age", "Gender", "Race") %in% ctx_inh2$results$Model1Factors))

source("R/ml_dual_pipeline_helpers.R")
got <- pipeline_assoc_restrict_to_imputed_common(
  c("Age", "Gender", "TotalCo2", "PT", "WBC"),
  c("Age", "Gender", "WBC", "SBP"),
  "Model2"
)
stopifnot(identical(got, c("Age", "Gender", "WBC")))
stopifnot(!any(c("TotalCo2", "PT") %in% got))

cat("test_ml_assoc_covariate_rule.R: OK\n")
