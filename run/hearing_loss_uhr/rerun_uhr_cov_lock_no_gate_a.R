#!/usr/bin/env Rscript
# 听力损失 UHR 定制重跑：
#   - 协变量选择前：不做 Gate A 特征/列交集（各库保留全部可用列）
#   - 协变量：三库统一，强制 covariate_lock.json（Model1/Model2）
# 产出目标：by_index/【success】UHR - 副本
suppressPackageStartupMessages(options(stringsAsFactors = FALSE, cli.hyperlink = FALSE, warn = 1))

root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
study <- "/mnt/g/02block_result/15_hearing_loss/incidence_38341157"
dual_cfg <- file.path(study, "config_incidence_dual_batch.R")
lil_cfg  <- file.path(study, "config_incidence_liling.R")
lock_path <- file.path(study, "data/harmonized/covariate_lock.json")
out_copy <- file.path(study, "by_index", "【success】UHR - 副本")
ix <- "UHR"
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
log_dir <- file.path(study, "logs")
dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

setwd(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/incidence_pipeline_brief.R"))
source(file.path(root, "R/incidence_sensitivity_suite.R"))
source(file.path(root, "R/nhanes_survey_weight.R"))

stopifnot(file.exists(dual_cfg), file.exists(lil_cfg), file.exists(lock_path))
lock <- jsonlite::fromJSON(lock_path)
m1 <- as.character(lock$model1)
m2 <- as.character(lock$model2)
cmf <- as.character(lock$common_model_factors %||% setdiff(m2, m1))
cli::cli_h1("Hearing UHR 定制重跑（无 Gate A 特征统一 / 三库协变量锁）")
cli::cli_alert_info("Model1={paste(m1, collapse=', ')}")
cli::cli_alert_info("Model2={paste(m2, collapse=', ')}")

# ── Gate A：各库保留全列，不做特征交集过滤 ──────────────────────────────────
incidence_batch_gate_a_from_clean <<- function(config) {
  bc <- config$incidence_batch %||% list()
  gate_a_thresh <- bc$gate_a_missing_threshold %||% 1.0
  if (!exists("auto_map_column_names", mode = "function")) {
    block_path <- file.path(getwd(), "Blocks/01_column_mappings/01block_column_mapping.R")
    if (file.exists(block_path)) source(block_path, local = FALSE)
  }
  .get_clean_cols <- function(db) {
    db_cfg <- if (db == "nhanes") config$dual_db$primary else config$dual_db$secondary
    env <- new.env(parent = emptyenv())
    raw <- tryCatch({
      path <- db_cfg$rawdata_path
      if (!is_absolute_path(path)) path <- file.path(getwd(), path)
      load(path, envir = env)
      get(db_cfg$rawdata_obj, envir = env)
    }, error = function(e) NULL)
    if (is.null(raw) || !is.data.frame(raw)) return(character(0))
    miss <- vapply(raw, function(x) mean(is.na(x)), numeric(1))
    kept <- raw[, miss <= gate_a_thresh, drop = FALSE]
    suppressMessages(mapped <- auto_map_column_names(kept, db_cfg$column_mapping_type))
    if (exists("pipeline_ensure_outcome_group_column", mode = "function")) {
      mapped <- pipeline_ensure_outcome_group_column(mapped, config)
    }
    sort(names(mapped))
  }
  n_cols <- .get_clean_cols("nhanes")
  m_cols <- .get_clean_cols("mimic")
  if (!length(n_cols) || !length(m_cols)) {
    cli::cli_alert_warning("Gate A keep-all: 无法加载数据，跳过")
    return(config)
  }
  outcome_col <- as.character((config$data %||% list())$outcome_column %||% "Disease_Group")[1L]
  protected <- unique(c(
    outcome_col, "Disease", "Disease_Group",
    "fustatus", "futime", "ID", "SEQN", "subject_id",
    nhanes_survey_weight_source_cols(config)
  ))
  # 仅记录交集供日志；过滤保留各库全列
  common_clin <- sort(intersect(setdiff(n_cols, protected), setdiff(m_cols, protected)))
  harm <- config$dual_db$harmonization %||% list()
  demo_kw <- as.character(harm$demo_keywords %||% character(0))
  if (!exists("dual_db_is_demo_col", mode = "function")) {
    source(file.path(getwd(), "R", "dual_db_harmonize.R"), local = FALSE)
  }
  demo_n <- unique(n_cols[dual_db_is_demo_col(n_cols, demo_kw)])
  demo_m <- unique(m_cols[dual_db_is_demo_col(m_cols, demo_kw)])

  cli::cli_h2("Gate A（定制：各库保留全列，不做特征交集）")
  cli::cli_alert_info("NHANES 列={length(n_cols)} | CHARLS 列={length(m_cols)} | 交集仅供参考={length(common_clin)}")
  cli::cli_alert_success("column_keep = 各库自身全列（协变量统一延后到 Gate B / lock）")

  config$dual_db$harmonization$column_keep_nhanes <- n_cols
  config$dual_db$harmonization$column_keep_mimic  <- m_cols
  config$dual_db$harmonization$common_non_demo_cols <- common_clin
  config$dual_db$harmonization$common_clinical_subgroup_cols <- common_clin
  config$dual_db$harmonization$demo_cols_nhanes <- demo_n
  config$dual_db$harmonization$demo_cols_mimic  <- demo_m
  config$dual_db$current_db <- NULL
  config
}

force_lock_cfg <- function(cfg) {
  cfg$logistic$model1_factors <- m1
  cfg$logistic$model2_factors <- m2
  cfg$logistic$model2_max_covariates <- 20L
  for (nm in c(
    "logistic_nhanes_weighted",
    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "rcs_incidence", "rcs_nhanes"
  )) {
    if (!is.null(cfg[[nm]])) {
      cfg[[nm]]$model1_factors <- m1
      cfg[[nm]]$model2_factors <- m2
      if (!is.null(cfg[[nm]]$random_search)) {
        cfg[[nm]]$random_search$enable <- FALSE
        cfg[[nm]]$random_search$max_attempts <- 1L
        cfg[[nm]]$random_search$max_outer_attempts <- 1L
      }
    }
  }
  if (!is.null(cfg$dual_db$harmonization)) {
    cfg$dual_db$harmonization$lock_covariates_preset <- TRUE
    cfg$dual_db$harmonization$covariate_source <- "vif_screen"
    cfg$dual_db$harmonization$sync_after_vif_final <- FALSE
    cfg$dual_db$harmonization$require_same_clinical_cols <- TRUE
    cfg$dual_db$harmonization$harmonized_model1_nhanes <- m1
    cfg$dual_db$harmonization$harmonized_model2_nhanes <- m2
    cfg$dual_db$harmonization$harmonized_model1_mimic <- m1
    cfg$dual_db$harmonization$harmonized_model2_mimic <- m2
    cfg$dual_db$harmonization$common_model_factors <- cmf
  }
  cfg$incidence$index_var <- ix
  cfg$logistic$index_var <- ix
  if (!is.null(cfg$prediction)) cfg$prediction$index_vars <- ix
  cfg
}

# ── 清盘目标产出与相关 checkpoint ──────────────────────────────────────────
rm_paths <- c(
  out_copy,
  file.path(study, "by_index", "UHR"),
  file.path(study, "by_index", "【success】UHR"),
  file.path(study, "checkpoints", "by_index", ix),
  file.path(study, "checkpoints", "Liling_UHR"),
  file.path(study, "checkpoints", "_shared"),
  file.path(study, "checkpoints", "_global_harmonization", "gate_a_columns.rds"),
  file.path(study, "checkpoints", "_global_harmonization", "gate_b_covariates.rds")
)
for (p in rm_paths) {
  if (file.exists(p) || dir.exists(p)) {
    unlink(p, recursive = TRUE, force = TRUE)
    cli::cli_alert_info("cleared: {p}")
  }
}
dir.create(dirname(out_copy), recursive = TRUE, showWarnings = FALSE)

# ── Dual NHANES + CHARLS ───────────────────────────────────────────────────
Sys.setenv(STUDY_CONFIG_DIR = dirname(dual_cfg))
source(dual_cfg)
config$incidence_batch$output_base <- study
config$incidence_batch$skip_existing <- FALSE
config$incidence_batch$index_vars <- ix
config$project$root <- study
config <- force_lock_cfg(config)

# 预写 Gate A keep-all 缓存，避免 worker 读到旧交集
config <- incidence_batch_gate_a_from_clean(config)
ga <- incidence_batch_extract_gate_a_from_config(config)
dual_db_save_gate_a(study, config, ga)

# Gate B preset = lock
harm_dir <- file.path(study, "checkpoints", "_global_harmonization")
dir.create(harm_dir, recursive = TRUE, showWarnings = FALSE)
gate_b <- list(
  harmonized_model1_nhanes = m1,
  harmonized_model2_nhanes = m2,
  harmonized_model1_mimic = m1,
  harmonized_model2_mimic = m2,
  common_model_factors = cmf,
  covariate_source_used = "lock_preset",
  saved_at = Sys.time()
)
saveRDS(gate_b, file.path(harm_dir, "gate_b_covariates.rds"))

cli::cli_h2("1/3 Dual batch UHR --no-skip")
# 再确认 Gate A 覆盖仍在（run_incidence_dual_batch 内 force 重算会走本覆盖）
stopifnot(exists("incidence_batch_gate_a_from_clean", mode = "function"))
run_incidence_dual_batch(
  root = root,
  config = config,
  pipeline_nhanes_batch = pipeline_nhanes_batch,
  pipeline_regular_batch = pipeline_regular_batch,
  pipeline_shared_nhanes = pipeline_shared_nhanes,
  pipeline_shared_regular = pipeline_shared_regular,
  run_opts = list(
    workers = 1L,
    db_mode = "both",
    only_index = ix,
    skip_existing = FALSE,
    shared_only = FALSE
  ),
  config_path = dual_cfg
)

# 定位 dual 成功目录
dual_dir <- file.path(study, "by_index", "【success】UHR")
if (!dir.exists(dual_dir)) dual_dir <- file.path(study, "by_index", "UHR")
stopifnot(dir.exists(dual_dir))

# ── Liling ────────────────────────────────────────────────────────────────
cli::cli_h2("2/3 Liling UHR")
Sys.setenv(STUDY_CONFIG_DIR = dirname(lil_cfg))
rm(list = intersect(
  c("pipeline_nhanes_batch", "pipeline_regular_batch", "pipeline", "config"),
  ls(envir = .GlobalEnv)
), envir = .GlobalEnv)
source(lil_cfg)
config <- force_lock_cfg(config)
lil_out <- file.path(dual_dir, "Liling")
dir.create(lil_out, recursive = TRUE, showWarnings = FALSE)
config$project$output_dir <- lil_out
pl <- pipeline
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- file.path(study, "checkpoints", "Liling_UHR")
run_pipeline(root, config = config, pipeline = pl, run_opts = list())

# ── 同步到「副本」目录并汇总 ──────────────────────────────────────────────
cli::cli_h2("3/3 同步到 【success】UHR - 副本 + summary")
# 保留 canonical 【success】UHR（collect / 后续脚本依赖），再镜像到用户指定的副本
if (dir.exists(out_copy)) unlink(out_copy, recursive = TRUE, force = TRUE)
system2(
  "cp",
  c("-a", dual_dir, out_copy),
  stdout = TRUE, stderr = TRUE
)
if (!dir.exists(out_copy)) {
  # fallback: R file.copy
  dir.create(dirname(out_copy), recursive = TRUE, showWarnings = FALSE)
  file.copy(dual_dir, dirname(out_copy), recursive = TRUE)
  copied <- file.path(dirname(out_copy), basename(dual_dir))
  if (dir.exists(copied) && !identical(copied, out_copy)) {
    file.rename(copied, out_copy)
  }
}
writeLines(
  c(
    paste0("rerun_at=", Sys.time()),
    "mode=no_gate_a_feature_union; covariate_lock_3db",
    paste0("model1=", paste(m1, collapse = ",")),
    paste0("model2=", paste(m2, collapse = ",")),
    paste0("source_dual=", dual_dir)
  ),
  file.path(out_copy, "_rerun_meta.txt")
)
# 同步一份到 canonical，便于追溯
file.copy(
  file.path(out_copy, "_rerun_meta.txt"),
  file.path(dual_dir, "_rerun_meta.txt"),
  overwrite = TRUE
)

sh <- file.path(root, "run/hearing_loss_uhr/collect_hearing_uhr_summary_result.sh")
if (file.exists(sh)) {
  system2("bash", c(sh, study), stdout = TRUE, stderr = TRUE)
}

cli::cli_alert_success("完成 → {out_copy}")
cli::cli_alert_info("协变量锁 Model2: {paste(m2, collapse=', ')}")
