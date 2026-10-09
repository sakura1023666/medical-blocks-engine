# 分类暴露：回归变量本身，禁止 continuous / 分位
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/logistic_gate.R"), local = FALSE)
source(file.path(root, "R/ml_dual_pub_table_curate.R"), local = FALSE)

stopifnot(isTRUE(pipeline_index_is_categorical(factor(c("No", "Yes", "No")))))
stopifnot(isTRUE(pipeline_index_is_categorical(c("No", "Yes", "No"))))
stopifnot(isTRUE(pipeline_index_is_categorical(c(0, 1, 0, 1))))
stopifnot(isTRUE(pipeline_index_is_categorical(c(TRUE, FALSE))))
stopifnot(!isTRUE(pipeline_index_is_categorical(c(1.2, 3.4, 5.6, 7.8))))
stopifnot(!isTRUE(pipeline_index_is_categorical(c(1, 2, 3, 4, 5, 6))))

dat <- data.frame(
  AF = factor(c("No", "Yes", "No", "Yes"), levels = c("No", "Yes")),
  NLR = c(1.1, 2.2, 3.3, 4.4)
)
bl <- pipeline_apply_categorical_exposure(list(include_continuous_row = TRUE), dat, "AF")
stopifnot(isTRUE(bl$categorical_exposure))
stopifnot(isFALSE(bl$include_continuous_row))
stopifnot(identical(bl$group_var, "AF"))
bl_n <- pipeline_apply_categorical_exposure(list(include_continuous_row = TRUE), dat, "NLR")
stopifnot(!isTRUE(bl_n$categorical_exposure))
stopifnot(isTRUE(bl_n$include_continuous_row))

ctx <- list(
  config = list(logistic = list(index_var = "AF")),
  data = list(imputed = dat),
  current_block = "logistic_binary_glm",
  results = list()
)
bl2 <- logistic_glm_resolve_bl_cfg(ctx, "logistic_binary_glm")
stopifnot(isTRUE(bl2$categorical_exposure))
stopifnot(isFALSE(bl2$include_continuous_row))
stopifnot(identical(bl2$group_var, "AF"))

stopifnot(isTRUE(pipeline_categorical_exposure_should_skip_block("logistic_quartile_glm", ctx)))
stopifnot(isTRUE(pipeline_categorical_exposure_should_skip_block("logistic_tertile_glm", ctx)))
stopifnot(isTRUE(pipeline_categorical_exposure_should_skip_block("rcs_incidence", ctx)))
stopifnot(!isTRUE(pipeline_categorical_exposure_should_skip_block("logistic_binary_glm", ctx)))
stopifnot(isTRUE(pipeline_logistic_gate_should_skip("logistic_quartile_glm", ctx, list())))

stopifnot(identical(
  logistic_glm_pub_caption("AF", native_levels = TRUE),
  "Logistic regression of AF"
))
stopifnot(identical(
  logistic_glm_pub_caption("AF", scheme = "categorical"),
  "Logistic regression of AF"
))
stopifnot(grepl("binary", logistic_glm_pub_caption("AF", scheme = "binary")))

cfg_on <- list(
  project = list(study_type = "incidence"),
  ml_batch = list(split_mode = "dev_internal_ext")
)
stopifnot(identical(
  .ml_ptc_classify_table("Table 2-eICU. Logistic regression of AF.xlsx", cfg_on),
  "t2_logistic"
))

cat("test_categorical_exposure.R: OK\n")
