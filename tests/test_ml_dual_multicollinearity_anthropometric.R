# tests/test_ml_dual_multicollinearity_anthropometric.R
# ML dual：人体测量不得被 psoriasis preset exclude_vars 静默剔除出 VIF
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "configs/psoriasis/config11.R"), local = FALSE)
source(file.path(root, "configs/ml_dual_shared_overrides.R"), local = FALSE)

stopifnot("Weight" %in% (config$multicollinearity$exclude_vars %||% character(0)))

cfg2 <- ml_dual_apply_feature_selection_overrides(config)
excl <- cfg2$multicollinearity$exclude_vars %||% character(0)
stopifnot(!"Weight" %in% excl)
stopifnot(!"Height" %in% excl)
stopifnot(!"BMI" %in% excl)

ar <- cfg2$multicollinearity$anthropometric_vif_resolution %||% list()
stopifnot(isTRUE(ar$enable))
stopifnot(all(c("BMI", "Weight", "Height") %in% (ar$vars %||% character(0))))

cat("test_ml_dual_multicollinearity_anthropometric.R: OK\n")
