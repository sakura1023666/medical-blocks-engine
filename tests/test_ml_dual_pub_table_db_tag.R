# tests/test_ml_dual_pub_table_db_tag.R
# 双库表：MIMIC_IV / MIMIC IV 都能识别，主次库标题都带库名
root <- normalizePath(".")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/dual_db_harmonize.R"), local = FALSE)
source(file.path(root, "R/ml_dual_pub_table_curate.R"), local = FALSE)

cfg <- list(
  dual_db = list(
    merge_dual_db_tables = FALSE,
    primary = list(name = "MIMIC_IV"),
    secondary = list(name = "eICU")
  )
)

stopifnot(identical(
  .ml_ptc_extract_db_label("Table 1-eICU. Baseline.xlsx", cfg),
  "eICU"
))
stopifnot(identical(
  .ml_ptc_extract_db_label("Table 1-MIMIC IV. Baseline.xlsx", cfg),
  "MIMIC IV"
))
stopifnot(identical(
  .ml_ptc_extract_db_label("Table 2-MIMIC IV-MIMIC IV. Logistic.xlsx", cfg),
  "MIMIC IV"
))
stopifnot(identical(
  .ml_ptc_extract_db_label("Table 3-MIMIC_IV. ML.xlsx", cfg),
  "MIMIC IV"
))

stopifnot(identical(
  .ml_ptc_target_basename(
    "t1_baseline", "Table 1. Baseline characteristics of AKI.xlsx", cfg,
    db_tag = .ml_ptc_resolve_db_tag(
      "Table 1. Baseline characteristics of AKI.xlsx",
      cfg,
      tables_dir = "/tmp/AF/MIMIC_IV/Tables"
    )
  ),
  "Table 1-MIMIC IV. Baseline characteristics of AKI.xlsx"
))
stopifnot(identical(
  .ml_ptc_target_basename(
    "t1_baseline", "Table 1. Baseline characteristics of AKI.xlsx", cfg,
    db_tag = .ml_ptc_resolve_db_tag(
      "Table 1. Baseline characteristics of AKI.xlsx",
      cfg,
      tables_dir = "/tmp/【success】AF/Tables"
    )
  ),
  "Table 1-MIMIC IV. Baseline characteristics of AKI.xlsx"
))

options(pipeline.database_name = "MIMIC_IV")
lab <- .inject_db_into_pub_label("Table 1-MIMIC IV. Baseline characteristics of AKI")
stopifnot(identical(lab, "Table 1-MIMIC IV. Baseline characteristics of AKI"))
lab2 <- .inject_db_into_pub_label("Table 1-MIMIC IV-MIMIC IV. Baseline characteristics of AKI")
stopifnot(identical(lab2, "Table 1-MIMIC IV. Baseline characteristics of AKI"))

# auto 闸门已选 quartile 时，模板残留 manual_n_groups=2 不得误改名
cfg_auto <- utils::modifyList(
  cfg,
  list(logistic = list(grouping_mode = "auto", manual_n_groups = 2L))
)
stopifnot(grepl(
  "quartile",
  .ml_ptc_target_basename(
    "t2_logistic", "Table 2. Logistic regression of AF quartile.xlsx",
    cfg_auto, db_tag = "MIMIC_IV"
  ),
  ignore.case = TRUE
))

# 只有显式 manual 二分类才允许 quartile 历史文件名归一为 binary
cfg_manual <- utils::modifyList(
  cfg,
  list(logistic = list(grouping_mode = "manual", manual_n_groups = 2L))
)
stopifnot(grepl(
  "binary",
  .ml_ptc_target_basename(
    "t2_logistic", "Table 2. Logistic regression of AF quartile.xlsx",
    cfg_manual, db_tag = "MIMIC_IV"
  ),
  ignore.case = TRUE
))

cat("test_ml_dual_pub_table_db_tag.R: OK\n")
