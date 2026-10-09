# tests/test_ml_dual_dev_ext.R
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/ml_dual_dev_ext.R"), local = FALSE)
source(file.path(root, "R/ml_assoc_data_slots.R"), local = FALSE)
source(file.path(root, "R/ml_dual_pub_table_curate.R"), local = FALSE)

cfg_off <- list(
  project = list(study_type = "incidence"),
  ml_batch = list(split_mode = "per_db_internal")
)
stopifnot(!isTRUE(ml_dual_is_dev_ext_mode(cfg_off)))

cfg_on <- list(
  project = list(study_type = "incidence"),
  ml_batch = list(split_mode = "dev_internal_ext"),
  dual_db = list(
    primary = list(name = "MIMIC_IV"),
    secondary = list(name = "eICU"),
    merge_dual_db_tables = FALSE
  )
)
stopifnot(isTRUE(ml_dual_is_dev_ext_mode(cfg_on)))

cfg_prog <- list(
  project = list(study_type = "prognosis"),
  ml_batch = list(split_mode = "dev_internal_ext")
)
stopifnot(isTRUE(ml_dual_is_dev_ext_mode(cfg_prog)))

cfg2 <- ml_dual_apply_dev_ext_overrides(cfg_on)
stopifnot(identical(cfg2$ml_batch$pub_figure_scheme, "ml_dual_dev_ext"))
stopifnot(identical(cfg2$multicollinearity$data_slots, "train"))
stopifnot(isFALSE(cfg2$performance_ml$combined_panel))

cfg_sec <- ml_dual_apply_dev_ext_db_overrides(cfg2, is_primary = FALSE)
stopifnot(identical(cfg_sec$train_validation$mode, "external_all"))
stopifnot(isFALSE(cfg_sec$performance_ml$enable))
stopifnot(isTRUE(cfg_sec$ml_eval_external$enable))
stopifnot(isFALSE(cfg_sec$ml_models$enable))
stopifnot(isFALSE(cfg_sec$baseline_binary$export_train_val_baseline))
stopifnot(isTRUE(cfg_sec$imputation$export_table_s1))
stopifnot(isFALSE(cfg_sec$imputation$export_table_s1_validation))

cfg_pri <- ml_dual_apply_dev_ext_db_overrides(cfg2, is_primary = TRUE)
stopifnot(isTRUE(cfg_pri$baseline_binary$export_train_val_baseline))
stopifnot(isFALSE(cfg_pri$ml_eval_external$enable))

cfg_sec_off <- ml_dual_apply_dev_ext_db_overrides(cfg_off, is_primary = FALSE)
stopifnot(isFALSE(cfg_sec_off$ml_eval_external$enable))

ll <- ml_dual_dev_ext_logloss(c(1, 0, 1, 0), c(0.9, 0.1, 0.8, 0.2))
stopifnot(is.finite(ll), ll > 0, ll < 1)

stopifnot(identical(ml_dual_dev_ext_scale_for_tag("rf"), "none"))
stopifnot(identical(ml_dual_dev_ext_scale_for_tag("enet"), "center_scale"))
stopifnot(identical(ml_dual_dev_ext_scale_for_tag("mlp"), "range"))

## checkpoint_base 已是 by_index/<ix> 时，候选路径不得再套一层
tmp_ck <- tempfile("ck_ix_")
dir.create(file.path(tmp_ck, "MIMIC_IV"), recursive = TRUE)
saveRDS(list(ctx = list(data = list(train = data.frame(x = 1:3, Group = "a")))),
        file.path(tmp_ck, "MIMIC_IV", "imputation.rds"))
ctx_ck <- list(
  config = list(
    project = list(output_dir = file.path(tempdir(), "by_index", "AF", "eICU")),
    dual_db = list(checkpoint_base = tmp_ck, primary = list(name = "MIMIC_IV"))
  )
)
cands_ck <- ml_dual_dev_ext_primary_train_candidates(ctx_ck, file.path(tempdir(), "missing_pri"))
stopifnot(file.path(tmp_ck, "MIMIC_IV", "imputation.rds") %in% cands_ck)
tr_ck <- ml_dual_dev_ext_load_primary_train(ctx_ck, file.path(tempdir(), "missing_pri"))
stopifnot(is.data.frame(tr_ck), nrow(tr_ck) == 3L)
unlink(tmp_ck, recursive = TRUE)

stopifnot(identical(
  .ml_ptc_target_basename(
    "s_imputation_train",
    "Table S. Baseline characteristics before and after imputation (training set).xlsx",
    cfg_on,
    s_idx = 1L,
    db_tag = "MIMIC IV"
  ),
  "Table S1-MIMIC IV. Baseline characteristics before and after imputation (training set).xlsx"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "s_imputation_ext",
    "Table S. Baseline characteristics before and after imputation (external validation set).xlsx",
    cfg_on,
    s_idx = 1L,
    db_tag = "eICU"
  ),
  "Table S1-eICU. Baseline characteristics before and after imputation (external validation set).xlsx"
))
stopifnot(grepl(
  "external validation set",
  pub_caption_strip_parentheses(
    "Baseline characteristics before and after imputation (external validation set)"
  ),
  fixed = TRUE
))
stopifnot(grepl(
  "internal validation set",
  pub_caption_strip_parentheses(
    "Baseline characteristics before and after imputation (internal validation set)"
  ),
  fixed = TRUE
))

if (requireNamespace("recipes", quietly = TRUE)) {
  tr <- data.frame(
    Group = factor(c("a", "b", "a", "b"), levels = c("a", "b")),
    x = c(1, 2, 3, 4),
    f = factor(c("No", "Yes", "No", "Yes"), levels = c("No", "Yes"))
  )
  nd <- data.frame(
    Group = factor(c("a", "b"), levels = c("a", "b")),
    x = c(1.5, 2.5),
    f = factor(c("Yes", "No"), levels = c("No", "Yes"))
  )
  bk <- ml_dual_dev_ext_bake_newdata(tr, nd, c("x", "f"), "none")
  stopifnot("f_Yes" %in% names(bk), !"f" %in% names(bk))
}

## VIF：只请求 train 时不得回退到 imputed 全集
ctx_vif <- list(
  config = list(multicollinearity = list(data_slots = "train")),
  data = list(
    train = data.frame(x = 1:5),
    test = data.frame(x = 6:8)
  )
)
sl <- ml_vif_resolve_slots(ctx_vif)
stopifnot(identical(sl$slot, "train"))

ctx_both <- list(
  config = list(multicollinearity = list(data_slots = c("train", "test"))),
  data = ctx_vif$data
)
sl2 <- ml_vif_resolve_slots(ctx_both)
stopifnot(identical(sl2$slot, c("train", "test")))

## 表角色：三张插补共用 S1 号，但分类区分 train / 内验 / 外验
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S. Baseline characteristics before and after imputation (training set).xlsx",
    cfg_on
  ),
  "s_imputation_train"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S. Baseline characteristics before and after imputation (internal validation set, n=10).xlsx",
    cfg_on
  ),
  "s_imputation_val"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S. Baseline characteristics before and after imputation (external validation set).xlsx",
    cfg_on
  ),
  "s_imputation_ext"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S. Baseline characteristics by training and internal validation sets (after multiple imputation).xlsx",
    cfg_on
  ),
  "t1_train_val"
))
stopifnot(identical(
  .ml_ptc_classify_table("Table S. DeLong tests (external validation set).xlsx", cfg_on),
  "s_delong_ext"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S. Baseline characteristics before and after imputation (training set).xlsx",
    cfg_off
  ),
  "s_imputation_train"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "s_imputation_train",
    "Table S. Baseline characteristics before and after imputation (training set).xlsx",
    cfg_on,
    s_idx = 1L,
    db_tag = "MIMIC IV"
  ),
  "Table S1-MIMIC IV. Baseline characteristics before and after imputation (training set).xlsx"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "s_imputation_ext",
    "Table S. Baseline characteristics before and after imputation (external validation set).xlsx",
    cfg_on,
    s_idx = 1L,
    db_tag = "eICU"
  ),
  "Table S1-eICU. Baseline characteristics before and after imputation (external validation set).xlsx"
))

## 平行线/宽表：七项指标 + 训练集 Youden（含 Kappa、MCC）
set.seed(12L)
n <- 180L
lp <- rnorm(n)
p <- stats::plogis(lp)
y <- stats::rbinom(n, 1L, p)
w_syn <- data.frame(RF = p, D = y, Outcome = y, check.names = FALSE)
thr_syn <- ml_dual_dev_ext_youden_from_wide(w_syn, "RF")
stopifnot(is.finite(thr_syn), thr_syn > 0, thr_syn < 1)
ev_syn <- ml_dual_dev_ext_eval_metrics(w_syn, "RF", "train", c(RF = thr_syn))
stopifnot(nrow(ev_syn) == 7L)
stopifnot(identical(
  as.character(ev_syn$.metric),
  ml_dual_dev_ext_metric_levels()
))
stopifnot(all(is.finite(ev_syn$.estimate)))
stopifnot(all(ev_syn$.estimate >= 0, ev_syn$.estimate <= 1))

## 高事件率 DCA 不得再封顶 0.5
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
source(file.path(root, "Blocks/23_ml_performance/01block_performance_ml.R"), local = FALSE)
pw_lo <- data.frame(
  Outcome = c(rep(1L, 15L), rep(0L, 85L)),
  M = runif(100L, 0, 0.35)
)
thr_lo <- .pm_dca_auto_thresholds(pw_lo)
stopifnot(max(thr_lo) <= 0.5 + 1e-8)
pw_hi <- data.frame(
  Outcome = c(rep(1L, 88L), rep(0L, 12L)),
  M = runif(100L, 0.55, 0.98)
)
thr_hi <- .pm_dca_auto_thresholds(pw_hi)
stopifnot(max(thr_hi) > 0.5)

source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
md5 <- paste(
  .pub_figure_detailed_body(
    "Figure 5. ML metrics training internal and external",
    list(exposure = "AF", outcome = "AKI")
  ),
  collapse = " "
)
stopifnot(grepl("平行线", md5))
stopifnot(!grepl("Q2相对Q1", md5))
md6 <- paste(
  .pub_figure_detailed_body(
    "Figure 6. ML DCA training internal and external",
    list(exposure = "AF", outcome = "AKI")
  ),
  collapse = " "
)
stopifnot(grepl("决策曲线", md6))
stopifnot(!grepl("Q2相对Q1", md6))

stopifnot(identical(
  .ml_ptc_classify_table("Table S. DeLong tests training set.xlsx", cfg = cfg_on),
  "s_delong_train"
))
stopifnot(identical(
  .ml_ptc_classify_table("Table S7-MIMIC IV. DeLong tests (training set).xlsx", cfg = cfg_on),
  "s_delong_train"
))
stopifnot(identical(
  .ml_ptc_classify_table("Table S. Log-Loss.xlsx", cfg = cfg_on),
  "s_logloss"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table 5-eICU. ML performance wide external validation.xlsx",
    cfg = cfg_on
  ),
  "t5_ml_ext"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table 4-MIMIC IV. ML performance wide validation.xlsx",
    cfg = cfg_on
  ),
  "t4_ml_val"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S3-MIMIC IV. Multicollinearity Analysis VIF screen.xlsx",
    cfg = cfg_on
  ),
  "s_vif_train"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S. Multicollinearity Analysis VIF screen (internal validation set).xlsx",
    cfg = cfg_on
  ),
  "s_vif_val"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S. Multicollinearity Analysis VIF screen (external validation set).xlsx",
    cfg = cfg_on
  ),
  "s_vif_ext"
))
stopifnot(identical(
  .ml_ptc_classify_table(
    "Table S4-MIMIC IV. Normality test results for continuous variables.xlsx",
    cfg = cfg_on
  ),
  "drop"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "s_vif_train",
    "Table S3-MIMIC IV. Multicollinearity Analysis VIF screen.xlsx",
    cfg_on,
    s_idx = 3L,
    db_tag = "MIMIC IV"
  ),
  "Table S3-MIMIC IV. Multicollinearity Analysis VIF screen (training set).xlsx"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "s_hyper",
    "Table S5-MIMIC IV. Hyperparameters for machine learning models.xlsx",
    cfg_on,
    s_idx = 4L,
    db_tag = "MIMIC IV"
  ),
  "Table S4-MIMIC IV. Hyperparameters for machine learning models.xlsx"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "s_nri_ext",
    "Table S12-MIMIC IV. NRI and IDI (external validation set).xlsx",
    cfg_on,
    s_idx = 11L,
    db_tag = "MIMIC IV"
  ),
  "Table S11-MIMIC IV. NRI and IDI (external validation set).xlsx"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "t5_ml_ext",
    "Table 5-eICU. ML performance wide external validation.xlsx",
    cfg_on,
    db_tag = "eICU"
  ),
  "Table 5-eICU. ML performance wide external validation.xlsx"
))
w5 <- data.frame(
  model = c("RF", "RF"),
  dataset = "test",
  .metric = c("roc_auc", "accuracy"),
  .estimate = c(0.71, 0.66),
  stringsAsFactors = FALSE
)
w5 <- rbind(
  w5,
  data.frame(
    model = "RF", dataset = "test",
    .metric = c("sens", "spec", "f_meas", "kap", "mcc"),
    .estimate = c(0.5, 0.8, 0.6, 0.3, 0.35),
    stringsAsFactors = FALSE
  )
)
wt5 <- ml_dual_dev_ext_eval_wide_table(w5, digits = 3L, events = 1598L, total = 2190L)
stopifnot(identical(wt5$Model[[1L]], "Events (Case/Total)"))
stopifnot(identical(wt5$AUC[[1L]], "1598/2190"))
stopifnot(any(wt5$Model == "RF"))
stopifnot(identical(wt5$Kappa[wt5$Model == "RF"], "0.300"))
stopifnot(identical(wt5$MCC[wt5$Model == "RF"], "0.350"))

if (requireNamespace("openxlsx", quietly = TRUE)) {
  td <- tempfile("ml_ptc_")
  dir.create(td)
  openxlsx::write.xlsx(data.frame(a = 1), file.path(td, "Table S. Log-Loss.xlsx"))
  openxlsx::write.xlsx(data.frame(a = 2), file.path(td, "Table S6-MIMIC IV. Log-Loss (training, internal validation, and external validation).xlsx"))
  Sys.sleep(0.05)
  openxlsx::write.xlsx(data.frame(a = 3), file.path(td, "Table S. DeLong tests training set.xlsx"))
  openxlsx::write.xlsx(data.frame(a = 4), file.path(td, "Table S7-MIMIC IV. DeLong tests (training set).xlsx"))
  incidence_batch_curate_ml_pub_tables(td, cfg_on)
  left <- list.files(td, pattern = "\\.xlsx$")
  stopifnot(!any(grepl("^Table S\\. ", left)))
  stopifnot(any(grepl("Log-Loss", left, ignore.case = TRUE)))
  stopifnot(any(grepl("DeLong tests \\(training set\\)", left, ignore.case = TRUE)))
  unlink(td, recursive = TRUE)

  td2 <- tempfile("ml_ptc_s_")
  dir.create(td2)
  write_dummy <- function(bn) {
    openxlsx::write.xlsx(data.frame(x = 1), file.path(td2, bn))
  }
  write_dummy("Table S1-MIMIC IV. Baseline characteristics before and after imputation (training set).xlsx")
  write_dummy("Table S1-MIMIC IV. Baseline characteristics before and after imputation (internal validation set).xlsx")
  write_dummy("Table S1-eICU. Baseline characteristics before and after imputation (external validation set).xlsx")
  write_dummy("Table S2-MIMIC IV. Univariate Regression Analysis.xlsx")
  write_dummy("Table S3-MIMIC IV. Multicollinearity Analysis VIF screen.xlsx")
  write_dummy("Table S. Multicollinearity Analysis VIF screen (internal validation set).xlsx")
  write_dummy("Table S. Multicollinearity Analysis VIF screen (external validation set).xlsx")
  write_dummy("Table S4-MIMIC IV. Normality test results for continuous variables.xlsx")
  write_dummy("Table S5-MIMIC IV. Hyperparameters for machine learning models.xlsx")
  write_dummy("Table S6-MIMIC IV. Log-Loss (training, internal validation, and external validation).xlsx")
  write_dummy("Table S7-MIMIC IV. DeLong tests (training set).xlsx")
  write_dummy("Table S8-MIMIC IV. DeLong tests (internal validation set).xlsx")
  write_dummy("Table S9-MIMIC IV. DeLong tests (external validation set).xlsx")
  write_dummy("Table S10-MIMIC IV. NRI and IDI (training set).xlsx")
  write_dummy("Table S11-MIMIC IV. NRI and IDI (internal validation set).xlsx")
  write_dummy("Table S12-MIMIC IV. NRI and IDI (external validation set).xlsx")
  incidence_batch_curate_ml_pub_tables(td2, cfg_on)
  left2 <- list.files(td2, pattern = "\\.xlsx$")
  stopifnot(!any(grepl("Normality", left2, ignore.case = TRUE)))
  stopifnot(any(grepl("^Table S3-.+VIF screen \\(training set\\)", left2)))
  stopifnot(any(grepl("^Table S3-.+VIF screen \\(internal validation set\\)", left2)))
  stopifnot(any(grepl("^Table S3-.+VIF screen \\(external validation set\\)", left2)))
  stopifnot(any(grepl("^Table S4-.+Hyperparameters", left2)))
  stopifnot(any(grepl("^Table S5-.+Log-Loss", left2)))
  stopifnot(any(grepl("^Table S6-.+DeLong tests \\(training set\\)", left2)))
  stopifnot(any(grepl("^Table S11-.+NRI and IDI \\(external validation set\\)", left2)))
  unlink(td2, recursive = TRUE)
}

cat("test_ml_dual_dev_ext.R: OK\n")
