###############################################################################
#  config_ml_dual_batch.template.R — ML 双库批量配置模板
#
#  复制到产出目录:
#    //192.168.68.133/02block_result/{疾病编码}_{疾病}/ml_{PMID}/config_ml_dual_batch.R
#
#  发病对照: .../incidence_{PMID}/
#
#  运行:
#    Rscript run/ml/run_ml_dual_batch.R --config "<上述路径>"
###############################################################################

.batch_project_root <- "//192.168.68.133/02block_result/{disease_code}_{disease}/ml_{PMID}"
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.batch_data_root    <- file.path(.batch_project_root, "Data")

config <- list(
  data = list(
    rawdata_path = file.path(.batch_data_root, "nhanes/D04_dabiao.RData"),
    rawdata_obj = "dabiao",
    outcome_column = "Disease",
    id_column = "SEQN",
    strip_id_columns_after_imputation = c("SEQN", "subject_id")
  ),
  project = list(
    name = "{disease}_ML_dual_batch",
    disease_code = "{disease_code}",
    disease = "{disease}",
    literature_pmid = "{PMID}",
    database = "NHANES",
    database_type = "nhanes",
    study_type = "prediction",
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE,
    root = NULL
  ),
  prediction = list(index_vars = NULL),
  index = list(enable = FALSE),
  pub_figures = list(
    formats_dir = TRUE,
    dpi = 300L,
    tiff_compression = "lzw",
    write_image_information = TRUE
  ),
  dual_db = list(
    enable = TRUE,
    workflow = "primary_full_secondary_ml",
    mirror_aggregate = TRUE,
    combine_figures = list(
      enable = TRUE,
      remove_singles = TRUE,
      drop_missing_overview = TRUE,
      panel_order = "primary_first",
      label_format = "A. {db}"
    ),
    checkpoint_base = .batch_ck_root,
    harmonization_dir = file.path(.batch_ck_root, "_global_harmonization"),
    primary = list(
      name = "NHANES", db_type = "nhanes",
      rawdata_path = file.path(.batch_data_root, "nhanes/D04_dabiao.RData"),
      rawdata_obj = "dabiao", id_column = "SEQN", column_mapping_type = "NHANES"
    ),
    secondary = list(
      name = "MIMIC", db_type = "regular",
      rawdata_path = file.path(.batch_data_root, "mimic/D04_dabiao.RData"),
      rawdata_obj = "dabiao", id_column = "SEQN", column_mapping_type = "MIMIC"
    )
  ),
  ml_batch = list(
    index_vars = c("ALBI", "RAR", "SII"),
    db_mode = "both",
    output_base = .batch_project_root,
    shared_ck_base = file.path(.batch_ck_root, "_shared"),
    index_ck_base = file.path(.batch_ck_root, "by_index"),
    skip_existing = TRUE,
    ram_per_worker_gb = 2.5
  ),
  # ML 基线把 simple_ROC 放在 VIF 前：显式单变量，避免引擎默认 multivariable 硬停
  roc_simple = list(
    enable = TRUE,
    mode = "univariate",
    write_cutoff_value = FALSE,
    export_table = FALSE
  ),
  feishu = list(
    enable = TRUE,
    push_on_worker_finish = TRUE,
    push_on_batch_summary = TRUE
  )
)

# pipeline_* 定义与 configs/config_ml_dual_batch.R 相同（复制完整 blocks 列表）
