# 泛癌 ExWAS / ERS 共用 Model 2 协变量
# 口径：文献/DAG 候选池 → 单因素(P<0.05) → VIF<4 → 逐步 AIC
# 终末集与 Model2_selection_path.txt 的 stepwise= 行一致
#
# 用法：source 本文件后调用 pancancer_model2_covars(df = ...) 或
#       pancancer_model2_covars_from_path(base)

pancancer_model2_final_default <- c(
  "Gender", "Race", "PIR_cat", "Alcohol_drinking", "eGFR"
)

pancancer_model2_dag_pool_default <- c(
  "Gender", "Race", "Education", "Marital_Status",
  "PIR_cat", "BMI_cat", "Alcohol_drinking", "eGFR"
)

pancancer_model2_covars_from_path <- function(base) {
  p <- file.path(
    base, "Output_pancancer_paperflow_UCR_WTSA_full_pub", "_downstream",
    "Model2_selection_path.txt"
  )
  if (!file.exists(p)) return(pancancer_model2_final_default)
  lines <- readLines(p, warn = FALSE)
  sw <- grep("^stepwise=", lines, value = TRUE)
  if (!length(sw)) return(pancancer_model2_final_default)
  out <- trimws(unlist(strsplit(sub("^stepwise=", "", sw[[1]]), ",\\s*")))
  out <- out[nzchar(out)]
  if (!length(out)) pancancer_model2_final_default else out
}

pancancer_model2_display_labs <- function(covars = pancancer_model2_final_default) {
  map <- c(
    Gender = "sex",
    Race = "race/ethnicity",
    Education = "education",
    Marital_Status = "marital status",
    PIR_cat = "poverty income ratio",
    BMI_cat = "BMI",
    Alcohol_drinking = "alcohol use",
    eGFR = "eGFR",
    Age = "age",
    Smoke = "smoking status"
  )
  vapply(as.character(covars), function(x) {
    if (x %in% names(map)) unname(map[[x]]) else gsub("_", " ", x, fixed = TRUE)
  }, character(1), USE.NAMES = FALSE)
}

pancancer_model2_footnote <- function(covars = pancancer_model2_final_default) {
  paste0(
    "Model 2 covariates were selected from a literature-informed DAG candidate pool ",
    "by univariate screening (P<0.05), VIF<4, and stepwise AIC, yielding ",
    paste(pancancer_model2_display_labs(covars), collapse = ", "),
    " (same set for ExWAS, ERS, mediation, and sensitivity models)."
  )
}
