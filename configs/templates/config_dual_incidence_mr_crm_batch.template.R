###############################################################################
#  config_dual_incidence_mr_crm_batch.template.R — 配置模板（复制到研究产出目录后按【必改】修改）
#  原始实例已移至 configs/_archive/config_dual_incidence_mr_crm_batch.R
###############################################################################

source("configs/_archive/config_dual_incidence_mr_crm.R")

.batch_batch_root <- "Output/Dual_Incidence_MR_CRM_Batch"
config$project$output_dir <- .batch_batch_root
config$project$name <- "Dual_Incidence_MR_CRM_Batch"

config$study_batch <- list(
  output_base = .batch_batch_root,
  units = c("CHARLS", "NHANES", "MR"),
  unit_mode = "branch",
  branch_map = list(
    NHANES = list(
      blocks = c("crm_ordinal_logistic", "crm_cox_mortality", "crm_rcs_sua", "crm_nhanes_weighted", "crm_gout_strata"),
      row_filter = "Cohort == 'NHANES'"
    ),
    CHARLS = list(
      blocks = c("crm_ordinal_logistic", "crm_cox_mortality", "crm_rcs_sua", "crm_gout_strata"),
      row_filter = "Cohort == 'CHARLS'"
    ),
    MR = list(
      blocks = c("mr_snp_screen", "mr_twosample", "mr_egger_presso", "mr_pleiotropy", "mr_sensitivity"),
      row_filter = NULL
    )
  ),
  parallel_workers = "auto",
  skip_existing = TRUE,
  worker_script = "run/study/run_study_batch_worker.R",
  shared_ck_alias = "data_clean"
)

pipeline_shared <- list(
  name = "dual_mr_shared",
  blocks = c("data_clean"),
  checkpoint = list(enable = TRUE, dir = file.path(.batch_batch_root, "checkpoints", "_shared", "main"))
)

pipeline_unit <- list(
  name = "dual_mr_unit",
  blocks = c("crm_ordinal_logistic", "crm_cox_mortality", "crm_rcs_sua",
             "crm_nhanes_weighted", "crm_gout_strata",
             "mr_snp_screen", "mr_twosample", "mr_egger_presso",
             "mr_pleiotropy", "mr_sensitivity"),
  checkpoint = list(enable = TRUE)
)

pipeline <- pipeline_shared
