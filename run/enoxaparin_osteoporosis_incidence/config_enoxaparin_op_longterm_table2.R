###############################################################################
# 仅用于产出文献 Table 2：按长期≥30天分层的基线表
# 跑完后由 03_liu_clinical_pub_align.R 拷入主 output 并命名为 Table 2
###############################################################################
source("/mnt/e/01block/01Block/run/enoxaparin_osteoporosis_incidence/config_enoxaparin_op_incidence.R")

config$project$output_dir <-
  "/mnt/g/02block_result/66_linchuangshengxin/Clinical_Bio_41947218/Output/enoxaparin_op_longterm_table2"
config$project$analysis_group <- "LongTerm"
config$project$reference_group <- "Non_LongTerm"
config$baseline_binary$strata <- "long_term_label"
config$baseline_binary$include_vars <- c(
  "Age", "Gender", "Race", "BMI",
  "DVT", "CKD", "Malignancy", "Glucocorticoid",
  "exposure_days", "n_admin", "cum_dose_mg",
  "avg_admin_per_day", "daily_avg_dose", "Disease"
)
config$pipeline$checkpoint$dir <- file.path(config$project$output_dir, "checkpoints")

pipeline$blocks <- c(
  "data_clean",
  "column_mapping",
  "analysis_exclusion",
  "imputation",
  "baseline_binary"
)
pipeline$name <- "enoxaparin_op_longterm_table2"
pipeline$render_tables_after <- c("imputation", "baseline_binary")
