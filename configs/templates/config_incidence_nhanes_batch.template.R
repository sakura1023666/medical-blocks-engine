###############################################################################
#  config_incidence_nhanes_batch.template.R — NHANES 单库发病批量模板
#
#  使用步骤:
#    1. 复制到 <项目根>/Data/config_incidence_<disease>_nhanes_batch.R
#    2. 修改 .batch_project_root、data、project、incidence_batch 等【必改】项
#    3. 配置 .disease_exclusion_vars（疾病相关变量，不得进协变量/亚组）
#    4. 运行:
#       Rscript run/incidence/run_incidence_nhanes_batch.R \
#         --config "<项目根>/Data/config_incidence_<disease>_nhanes_batch.R" \
#         --workers 28
#
#  source 后产物: config, pipeline_shared_nhanes, pipeline_nhanes_batch, ...
#
#  硬排除规则（全项目复用）:
#    index → analysis_exclusion → imputation → …
#    协变量不得含：疾病相关变量、当前指标组成变量、其它复合指标
###############################################################################

.batch_project_root <- "G:/02block_result/XX_Disease/ml_XXXXXXXX"  # 【必改】
.batch_ck_root      <- file.path(.batch_project_root, "checkpoints")
.batch_data_root    <- file.path(.batch_project_root, "Data")

# 【必改·按疾病】结局/诊断泄漏与疾病标志物；糖尿病视网膜病变示例见下
# .disease_exclusion_vars <- c("T1DM","T2DM","Diabetes","HbA1c","Glucose","Insulin","Antidiabetic_agents","Albumin_Urine","UACR")
.disease_exclusion_vars <- character(0)

config <- list(
  data = list(
    rawdata_path     = file.path(.batch_data_root, "nhanes/D04_dabiao_XXX.RData"),  # 【必改】
    rawdata_obj      = "dabiao",                                                     # 【必改】
    outcome_column   = "Disease_Group",
    id_column        = "ID",
    strip_id_columns_after_imputation = c("ID", "SEQN")
  ),
  project = list(
    disease_code = "XX", disease = "YOUR_DISEASE", literature_pmid = "00000000",  # 【必改】
    database = "NHANES", study_type = "incidence", classification_mode = "binary",
    analysis_group = "1", reference_group = "0",
    output_dir = .batch_project_root,
    mirror_pub_outputs_to_root = TRUE
  ),
  attrition = list(
    enable = TRUE,
    title = NULL,
    db_label = NULL,
    steps = list(),
    # CONSORT Figure 1：主列纳入、右侧 Exclude、底部分叉（发病=病例/对照）
    outcome_breakdown = TRUE,
    auto_append = TRUE,
    draw_pdf = TRUE,
    csv_name = "Flowchart_attrition.csv",
    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
    specialty_figure_mode = "skip_if_generic"
  ),
  incidence = list(outcome_var = "Disease_Group", index_var = NULL),
  index = list(enable = TRUE),
  analysis_exclusion = list(
    disease_vars = .disease_exclusion_vars,
    component_scope = "current_transitive",
    exclude_other_composite_indices = TRUE,
    exclude_exposure_if_uses_disease_var = TRUE
  ),
  nhanes = list(
    survey_weight = "new_Weight", survey_cluster = "SDMVPSU", survey_strata = "SDMVSTRA",
    auto_new_weight = TRUE,
    # 年龄亚组默认二分类；切点按病种文献选定（见 .cursor/rules/age_subgroup_binary.mdc）
    # 禁止无依据配置 age_group_cutoffs 多档
    age_cutoff = 65L
  ),
  incidence_batch = list(
    index_group = "all", db_mode = "nhanes", parallel_workers = NULL,
    output_base = .batch_project_root
  ),
  subgroup = list(
    # 年龄切点依据：写 config 前查本疾病常用界值；无依据时默认 65
    age_cutoff = 65L,
    level_order = list(
      Age_Group = c("< 65", "\u2265 65"),
      PIR = c("< 1.3", "1.3-3.5", "> 3.5"),
      Hypertension = c("No", "Yes"),
      Smoking = c("Never", "Former", "Current")
    )
  ),
  feishu = list(enable = FALSE)
)

# 完整 block 参数请复制已落地的研究 config（如 Data/config_incidence_dr_nhanes_batch.R）
# 并参照 configs/config_incidence_nhanes.R 补齐 pipeline_* 段；blocks 须含 analysis_exclusion。
