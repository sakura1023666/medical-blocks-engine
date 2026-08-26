###############################################################################
#  config_osteo_yan2026_modmed.R
#  骨关节炎 × 环境毒物：Yan2026 中介/调节复现（独立课题，不改旧 osteo 流水线）
#
#  用法:
#    "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#      run/environment/run_osteo_yan2026_modmed.R
#    MODMED_SIMS=50 同上   # 冒烟
###############################################################################

.cfg_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.cfg_root)) .cfg_root <- getwd()

.resolve_batch_path <- function(p) {
  p <- as.character(p)[1L]
  if (grepl("^\\\\", p)) {
    p <- sub("^\\\\\\\\[^\\\\]+\\\\", "G:/", gsub("\\\\", "/", p))
  }
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", p)) {
    wsl <- paste0("/mnt/", tolower(substr(p, 1L, 1L)), substr(p, 3L, nchar(p)))
    if (dir.exists(wsl) || dir.exists(dirname(wsl))) return(wsl)
  }
  p
}

.project_root <- .resolve_batch_path("G:/02block_result/04_Osteoarthritis/medition")
.data_dir <- file.path(.project_root, "data")
.out_dir <- file.path(.project_root, "yan2026_modmed_reproduce")

.exposures <- c(
  "URXOTD", "URXNPIP", "URXMB2", "URXDHB", "URXCEM", "URX4BP", "URXP01", "URX1NP", "WQS"
)
.mediators <- c(
  "Creatinine_mol", "Red_blood_cells", "Mean_cell_hemoglobin", "TBIL_mol",
  "Total_Protein_gdL", "BUN_mol", "Potassium", "Sodium",
  "White_blood_cells", "Neutrophil_count", "Mononuclear_cell_count", "lymphocyte_count"
)

# 冒烟：MODMED_SMOKE=1 时只跑 1 个暴露 × 2 个中介；MODMED_SIMS 覆盖 bootstrap 次数
if (identical(Sys.getenv("MODMED_SMOKE", unset = ""), "1")) {
  .exposures <- .exposures[1L]
  .mediators <- .mediators[c(1L, length(.mediators))]
}

config <- list(
  project = list(
    name = "osteo_yan2026_modmed",
    disease = "Osteoarthritis",
    disease_cn = "骨关节炎",
    analysis_group = "Osteoarthritis",
    reference_group = "Normal",
    output_dir = .out_dir
  ),
  data = list(
    rawdata_path = file.path(.data_dir, "结局_8环境毒物_基线全指标.RData"),
    rawdata_obj = "merged",
    outcome_column = "Group",
    id_column = "SEQN"
  ),
  analysis_exclusion = list(
    disease_vars = c(
      "Diabetes", "Group", "Group_bin",
      "Hypertension", "Cardiovasculardiseases"
    ),
    exclude_exposure_if_uses_disease_var = TRUE
  ),
  modmed = list(
    exposures = .exposures,
    mediators = .mediators,
    outcome = "Group_bin",
    moderators = c("Age", "BMI", "Gender"),
    sims = 5000L,
    seed = 1234L,
    covariates = character(0)
  ),
  modmed_data_prep = list(
    merged_rdata = file.path(.data_dir, "结局_8环境毒物_基线全指标.RData"),
    merged_obj = "merged",
    wqs_rdata = file.path(.data_dir, "D01_WQS_Result.RData"),
    wqs_obj = "wqs_fit",
    wqs_col = "WQS",
    case_label = "Osteoarthritis",
    ref_label = "Normal",
    male_label = "Male"
  ),
  modmed_spearman = list(),
  modmed_mediation_batch = list(
    resume = TRUE
  ),
  modmed_moderation = list(),
  modmed_moderated_mediation = list(),
  modmed_simple_slopes = list(),
  feishu = list(enable = FALSE)
)

pipeline <- list(
  name = "osteo_yan2026_modmed",
  blocks = c(
    "modmed_data_prep",
    "modmed_spearman",
    "modmed_mediation_batch",
    "modmed_moderation",
    "modmed_moderated_mediation",
    "modmed_simple_slopes"
  ),
  checkpoint = list(
    enable = TRUE,
    dir = file.path(.out_dir, "checkpoints")
  )
)
