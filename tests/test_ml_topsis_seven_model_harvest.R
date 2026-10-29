#!/usr/bin/env Rscript
## 真融合：七模型概率收割 + 多模型 TOPSIS 不得退化为 0/1（除非真全胜）
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = normalizePath(".", winslash = "/"))
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
if (!exists("cli", mode = "any")) {
  ## topsis 块成功路径会用 cli；本单测只测 helper
}
source(file.path(root, "Blocks/22_ml_models/00block_ml_eval_common.R"), local = FALSE)
source(file.path(root, "Blocks/22_ml_models/24block_ml_topsis_fusion.R"), local = FALSE)

stopifnot(identical(.ml_tcf_canonical_name("xgboost"), "XGB"))
stopifnot(identical(.ml_tcf_canonical_name("rsvm"), "SVM"))

## fake final_predictions
n <- 40L
set.seed(1)
preds <- data.frame(
  dataset = rep(c("Validation set", "Training set"), each = n / 2L),
  XGBoost_predicted_value = runif(n),
  stringsAsFactors = FALSE
)
p_te <- .ml_extract_test_ana_prob(preds)
stopifnot(length(p_te) == n / 2L)

ctx <- list(
  results = list(
    ml_model_probs = list(NB = runif(20), GBDT = runif(20)),
    ml_predictions_all = list(
      dt = data.frame(
        dataset = rep("Validation set", 20L),
        DT_predicted_value = runif(20),
        stringsAsFactors = FALSE
      ),
      rf = data.frame(
        dataset = rep("Validation set", 20L),
        RF_predicted_value = runif(20),
        stringsAsFactors = FALSE
      ),
      xgboost = data.frame(
        dataset = rep("Validation set", 20L),
        XGBoost_predicted_value = runif(20),
        stringsAsFactors = FALSE
      ),
      lightgbm = data.frame(
        dataset = rep("Validation set", 20L),
        LightGBM_predicted_value = runif(20),
        stringsAsFactors = FALSE
      ),
      rsvm = data.frame(
        dataset = rep("Validation set", 20L),
        RSVM_predicted_value = runif(20),
        stringsAsFactors = FALSE
      )
    )
  ),
  output_dir = tempdir(),
  config = list(
    data = list(outcome_column = "y"),
    project = list(analysis_group = "1"),
    ml_topsis_fusion = list(enable = TRUE)
  ),
  data = list(
    test = data.frame(y = factor(sample(c("0", "1"), 20L, replace = TRUE)))
  )
)

want <- c("DT", "RF", "XGB", "LGBM", "SVM", "NB", "GBDT")
h <- .mltcf24_collect_mapped_probs(ctx, want, 20L)
stopifnot(length(h$mapped) == 7L)
stopifnot(setequal(names(h$mapped), want))

## 交错优劣 → 权重不应塌成单模型 0/1
mat <- rbind(
  c(0.70, 0.55, 0.60, 0.50, 0.55, 0.65),
  c(0.72, 0.58, 0.62, 0.52, 0.60, 0.64),
  c(0.68, 0.60, 0.61, 0.55, 0.62, 0.60)
)
colnames(mat) <- c("AUC", "F1", "ACC", "PRE", "SEN", "SPE")
rownames(mat) <- c("A", "B", "C")
a <- .mltcf24_topsis_alpha(mat)
stopifnot(all(a > 0), all(a < 1), abs(sum(a) - 1) < 1e-8)

## 两模型全胜 → 才允许 0/1
mat2 <- rbind(
  c(0.60, 0.50, 0.55, 0.45, 0.50, 0.60),
  c(0.75, 0.65, 0.70, 0.60, 0.70, 0.72)
)
colnames(mat2) <- colnames(mat)
rownames(mat2) <- c("NB", "GBDT")
a2 <- .mltcf24_topsis_alpha(mat2)
stopifnot(abs(a2[["NB"]]) < 1e-9, abs(a2[["GBDT"]] - 1) < 1e-9)

message("OK test_ml_topsis_seven_model_harvest")
