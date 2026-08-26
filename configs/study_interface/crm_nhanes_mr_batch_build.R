###############################################################################
#  configs/study_interface/crm_nhanes_mr_batch_build.R
#
#  程序员薄 config → 完整 CRM×MR batch config。
#  前置: .study；MEDICAL_BLOCKS_ROOT（由 run_study 注入）。
#
#  .study 必填:
#    disease_code, disease
#  .study 常用可选:
#    literature_pmid / pmid
#    nhanes_rdata_file / nhanes_rdata_obj
#    mortality_file / mortality_obj
#    gwas_exposure_path, iv_cache_path, outcome_cache_dir, mendelian_lib_root
#    plink_bin, ld_bfile
#    feishu_enable (默认 FALSE)
#
#  数据约定（研究目录）:
#    Data/nhanes/<nhanes_rdata_file>
#    Data/nhanes/<mortality_file>
#  GWAS/PLINK 默认仍指向引擎 Data/（可大文件共用）；也可用 .study 覆盖。
###############################################################################

if (!exists(".study", inherits = TRUE))
  stop(".study 未定义：请在 config.R 顶部设置", call. = FALSE)

`%||%` <- function(a, b) if (!is.null(a)) a else b

.engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(.engine) || !dir.exists(.engine))
  stop("MEDICAL_BLOCKS_ROOT 未设置或无效：请使用 run_study.bat / run_study.sh", call. = FALSE)

.study <- .study %||% list()
.req <- function(x, key) {
  v <- x[[key]]
  if (is.null(v) || (is.character(v) && !nzchar(v[[1L]])))
    stop("config.R 中 .study$", key, " 必填", call. = FALSE)
  v
}

if (!exists(".batch_project_root", inherits = TRUE) || !nzchar(.batch_project_root %||% "")) {
  .study_config_file <- {
    ca <- commandArgs(trailingOnly = TRUE)
    i  <- match("--config", ca)
    if (!is.na(i) && i < length(ca))
      normalizePath(ca[[i + 1L]], winslash = "/", mustWork = TRUE)
    else
      NA_character_
  }
  .batch_project_root <- if (!is.na(.study_config_file)) {
    dirname(.study_config_file)
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = TRUE)
  }
}

.batch_ck_root   <- file.path(.batch_project_root, "checkpoints")
.batch_data_root <- file.path(.batch_project_root, "Data")
.crm_data_root   <- file.path(.batch_data_root, "nhanes")

disease_code   <- as.character(.req(.study, "disease_code"))
disease        <- as.character(.req(.study, "disease"))
pmid           <- as.character(.study$literature_pmid %||% .study$pmid %||% "40145269")
feishu_on      <- isTRUE(.study$feishu_enable %||% FALSE)

nhanes_file <- as.character(.study$nhanes_rdata_file %||% "NHANES_\u6587\u732e_0722.RData")
nhanes_obj  <- as.character(.study$nhanes_rdata_obj %||% "df")
mort_file   <- as.character(.study$mortality_file %||% "nhanes-\u6b7b\u4ea1.Rdata")
mort_obj    <- as.character(.study$mortality_obj %||% "combined_data")
id_col      <- as.character(.study$id_column %||% "SEQN")

gwas_path <- as.character(
  .study$gwas_exposure_path %||%
    file.path(.engine, "Data/GCST90018977.h.tsv.gz")
)
iv_cache <- as.character(
  .study$iv_cache_path %||%
    file.path(.engine, "Data/crm_han2025_iv/SUA_IVs_GCST90018977_p5e-8_kb10000_r0.001.rds")
)
outcome_cache <- as.character(
  .study$outcome_cache_dir %||%
    file.path(.engine, "Data/crm_han2025_r9")
)
mendel_lib <- as.character(.study$mendelian_lib_root %||% "E:/\u5b5f\u5fb7\u5c14")
plink_bin  <- as.character(
  .study$plink_bin %||% "D:/easyMR/MRmyy_refer_file/plink/plink.exe"
)
ld_bfile   <- as.character(
  .study$ld_bfile %||%
    "D:/easyMR/MRmyy_refer_file/1000G_EUR_Phase3_plink/1000G.EUR.QC"
)

# 研究区路径覆盖骨架（source 模板后再深合并）
config <- list(
  project = list(
    name = paste0(disease, "_NHANES_MR_Batch"),
    disease = disease,
    disease_code = disease_code,
    literature_pmid = pmid,
    study_type = "prognosis",
    analysis_group = as.character(.study$analysis_group %||% "1"),
    reference_group = as.character(.study$reference_group %||% "0"),
    database = "NHANES",
    database_type = "NHANES",
    root = .engine,
    output_dir = .batch_project_root,
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),
  data = list(
    rawdata_path = file.path(.crm_data_root, nhanes_file),
    rawdata_obj = nhanes_obj,
    id_column = id_col,
    outcome_column = "fustatus",
    strip_id_columns_after_imputation = c("ID", "SEQN", "subject_id")
  ),
  crm_nhanes_pub = list(
    mortality_path = file.path(.crm_data_root, mort_file),
    mortality_obj = mort_obj
  ),
  dual_incidence_mr = list(
    gwas_exposure = gwas_path,
    gwas_exposure_path = gwas_path,
    mendelian_lib_root = mendel_lib,
    plink_bin = plink_bin,
    ld_bfile = ld_bfile,
    iv_cache_path = iv_cache,
    outcome_cache_dir = outcome_cache
  ),
  study_batch = list(
    output_base = .batch_project_root,
    project_root = .engine
  ),
  feishu = list(
    enable = feishu_on,
    disease_label = paste0(disease_code, "_", disease),
    protocol_label = "crm_nhanes_mr",
    project_id = paste0(disease_code, "_crm_nhanes_mr_", pmid),
    push_on_worker_finish = feishu_on,
    push_on_batch_summary = feishu_on
  )
)

.template_path <- file.path(.engine, "configs/templates/config_crm_nhanes_mr_batch.template.R")
if (!file.exists(.template_path))
  stop("引擎模板缺失: ", .template_path, call. = FALSE)

.study_config <- config
._saved_root <- .batch_project_root
._saved_ck   <- .batch_ck_root
._saved_data <- .batch_data_root
._saved_crm  <- .crm_data_root
source(.template_path, local = TRUE)
.batch_project_root <- ._saved_root
.batch_ck_root      <- ._saved_ck
.batch_data_root    <- ._saved_data
.crm_data_root      <- ._saved_crm

.deep_merge <- function(base, patch) {
  if (!is.list(base) || !is.list(patch)) return(patch)
  nm <- union(names(base), names(patch))
  out <- base
  for (k in nm) {
    if (k %in% names(patch)) {
      out[[k]] <- if (is.list(patch[[k]]) && !is.null(base[[k]]) && is.list(base[[k]]))
        .deep_merge(base[[k]], patch[[k]]) else patch[[k]]
    }
  }
  out
}
config <- .deep_merge(config, .study_config)

# 强制写回研究区路径（模板默认指向 02block_result 固定盘）
config$project$root <- .engine
config$project$output_dir <- .batch_project_root
config$project$disease <- disease
config$project$disease_code <- disease_code
config$project$literature_pmid <- pmid
config$data$rawdata_path <- file.path(.crm_data_root, nhanes_file)
config$data$rawdata_obj <- nhanes_obj
config$data$id_column <- id_col
config$crm_nhanes_pub$mortality_path <- file.path(.crm_data_root, mort_file)
config$crm_nhanes_pub$mortality_obj <- mort_obj
config$dual_incidence_mr$gwas_exposure <- gwas_path
config$dual_incidence_mr$gwas_exposure_path <- gwas_path
config$dual_incidence_mr$iv_cache_path <- iv_cache
config$dual_incidence_mr$outcome_cache_dir <- outcome_cache
config$dual_incidence_mr$mendelian_lib_root <- mendel_lib
config$dual_incidence_mr$plink_bin <- plink_bin
config$dual_incidence_mr$ld_bfile <- ld_bfile
config$study_batch$output_base <- .batch_project_root
config$study_batch$project_root <- .engine
config$feishu$enable <- feishu_on
config$feishu$push_on_worker_finish <- feishu_on
config$feishu$push_on_batch_summary <- feishu_on

if (exists("pipeline_shared", inherits = FALSE) && is.list(pipeline_shared)) {
  pipeline_shared$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "main")
}
if (exists("pipeline", inherits = FALSE) && is.list(pipeline) &&
    !is.null(pipeline$checkpoint)) {
  pipeline$checkpoint$dir <- file.path(.batch_ck_root, "_shared", "main")
}

rm(.study_config, .template_path, .study, .engine, .req, .deep_merge,
   "._saved_root", "._saved_ck", "._saved_data", "._saved_crm",
   list = intersect(
     c("disease_code", "disease", "pmid", "feishu_on",
       "nhanes_file", "nhanes_obj", "mort_file", "mort_obj", "id_col",
       "gwas_path", "iv_cache", "outcome_cache", "mendel_lib", "plink_bin", "ld_bfile"),
     ls()
   ))

invisible(NULL)
