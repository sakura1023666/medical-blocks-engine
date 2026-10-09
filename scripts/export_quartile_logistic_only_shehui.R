###############################################################################
# 一次性：CHARLS / ELSA / Pooled 各出一份四分位 logistic（不改引擎闸门逻辑）
# Windows 示例：
#   $env:CROSS_LAGGED_STUDY_ROOT="G:/02block_result/23_circadian rhythm/cross_laged_shehui"
#   $env:MEDICAL_BLOCKS_ROOT="E:/01block/01Block-new-Final"
#   & "C:/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" "E:/01block/01Block-new-Final/scripts/export_quartile_logistic_only_shehui.R"
###############################################################################

.is_win <- identical(.Platform$OS.type, "windows")

.default_study <- if (.is_win) {
  "G:/02block_result/23_circadian rhythm/cross_laged_shehui"
} else {
  "/mnt/g/02block_result/23_circadian rhythm/cross_laged_shehui"
}
.default_root <- if (.is_win) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}

study_root <- Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = .default_study)
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = .default_root)
study_root <- normalizePath(study_root, winslash = "/", mustWork = FALSE)
root <- normalizePath(root, winslash = "/", mustWork = FALSE)
if (!dir.exists(root)) stop("引擎根不存在: ", root)
if (!dir.exists(study_root)) stop("课题根不存在: ", study_root)
setwd(root)

# 把 config 里硬编码的 /mnt/g|/mnt/e 改成当前平台路径
.fix_mnt_paths <- function(x) {
  if (is.character(x)) {
    x <- gsub("/mnt/g/", "G:/", x, fixed = TRUE)
    x <- gsub("/mnt/e/", "E:/", x, fixed = TRUE)
    if (!.is_win) {
      x <- gsub("G:/", "/mnt/g/", x, fixed = TRUE)
      x <- gsub("E:/", "/mnt/e/", x, fixed = TRUE)
    }
    return(x)
  }
  if (is.list(x)) return(lapply(x, .fix_mnt_paths))
  x
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "Blocks/11_logistic/01block_logistic_quartile_glm.R"))

`%||%` <- function(a, b) if (is.null(a)) b else a

.M1 <- c("Gender", "Education")
.M2 <- c("Age", "Gender", "Education", "Alcohol_drinking", "Weight", "Height", "SBP", "DBP", "WBC")
.M2p <- c(.M2, "Country")

.load_vif_ck <- function(ck_dir) {
  cands <- list.files(ck_dir, pattern = "multicollinearity_final\\.rds$", full.names = TRUE)
  if (!length(cands)) stop("无 multicollinearity_final: ", ck_dir)
  hit <- cands[grepl("step\\d+_multicollinearity_final", basename(cands))]
  if (!length(hit)) hit <- cands
  hit <- hit[order(file.info(hit)$mtime, decreasing = TRUE)]
  ck <- readRDS(hit[[1L]])
  if (!is.null(ck$ctx)) ck <- ck$ctx
  message("加载 VIF ck: ", basename(hit[[1L]]))
  ck
}

.run_one <- function(db, out_dir, ck, m1, m2, config) {
  dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_dir, "checkpoints"), recursive = TRUE, showWarnings = FALSE)

  config <- .fix_mnt_paths(config)
  config$project$output_dir <- out_dir
  config$project$database <- db
  config$project$name <- paste0("Circadian_Leisure_", db, "_quartile_only")
  if (is.null(config$logistic_quartile_glm)) config$logistic_quartile_glm <- list()
  config$logistic_quartile_glm$pause_enable <- FALSE
  config$logistic_quartile_glm$pause_on_search_fail <- FALSE
  config$logistic_quartile_glm$gate_enable <- FALSE
  config$logistic_quartile_glm$force_export <- TRUE
  config$logistic_quartile_glm$model1_factors <- m1
  config$logistic_quartile_glm$model2_factors <- m2
  config$logistic_quartile_glm$table_filename <- paste0(
    "Table 2-", db, ". Logistic regression of Leisure score - quartile (GLM).xlsx"
  )
  if (!is.null(config$logistic_quartile_glm$random_search))
    config$logistic_quartile_glm$random_search$enable <- FALSE
  if (is.null(config$logistic_covariates)) config$logistic_covariates <- list()
  config$logistic_covariates$model1_factors <- m1
  config$logistic_covariates$model2_factors <- m2

  ck$config <- config
  ck$results$Model1Factors <- m1
  ck$results$Model2Factors <- m2
  ck$results$vif_final_pass <- m2
  ck$results$logistic_grouping_scheme <- "quartile"
  ck$results$nhanes_logistic_selected_scheme <- "quartile"
  ck$current_block <- "logistic_quartile_glm"
  ck$root_output_dir <- out_dir

  pipe <- list(
    name = paste0("quartile_only_", db),
    blocks = c(
      "data_clean", "column_mapping", "imputation", "baseline_binary",
      "univariate_incidence_binary", "multicollinearity_screen",
      "multivariate_incidence_binary", "multicollinearity_final",
      "logistic_quartile_glm"
    ),
    logistic_gate = list(enable = FALSE),
    checkpoint = list(enable = TRUE, dir = file.path(out_dir, "checkpoints")),
    render_tables_after = "logistic_quartile_glm",
    render_figures_after = character(0),
    dual_db = list(enable = FALSE)
  )

  message("==== 四分位 logistic: ", db, " ====")
  run_pipeline(
    root, config = config, pipeline = pipe,
    run_opts = list(only = "logistic_quartile_glm", initial_ctx = ck)
  )

  src <- file.path(
    out_dir, "Tables",
    paste0("Table 2-", db, ". Logistic regression of Leisure score - quartile (GLM).xlsx")
  )
  dest_dir <- file.path(study_root, "summary_result", "table")
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(src)) {
    dest <- file.path(dest_dir, basename(src))
    file.copy(src, dest, overwrite = TRUE)
    message("OK ", db, ": ", dest)
  } else {
    warning(db, ": 未找到 ", src)
  }
  invisible(TRUE)
}

for (db in c("CHARLS", "ELSA")) {
  e <- new.env(parent = globalenv())
  sys.source(file.path(study_root, paste0("config_phase1_", db, ".R")), envir = e)
  e$config <- .fix_mnt_paths(e$config)
  out_dir <- file.path(study_root, paste0("phase1_", db))
  ck <- .load_vif_ck(file.path(out_dir, "checkpoints"))
  .run_one(db, out_dir, ck, .M1, .M2, e$config)
}

pooled_path <- file.path(study_root, "data/harmonized/D04_Pooled_postvif.RData")
if (!file.exists(pooled_path)) stop("缺少 Pooled: ", pooled_path)
ee <- new.env(parent = emptyenv())
load(pooled_path, envir = ee)
dabiao <- ee$dabiao
dabiao$Country <- factor(dabiao$Country, levels = sort(unique(as.character(dabiao$Country))))
miss <- setdiff(.M2, names(dabiao))
if (length(miss)) stop("Pooled 缺锁定协变量: ", paste(miss, collapse = ", "))
if (!all(c("Country", "Leisure_score") %in% names(dabiao)))
  stop("Pooled 缺 Country 或 Leisure_score")

e <- new.env(parent = globalenv())
sys.source(file.path(study_root, "config_phase1_CHARLS.R"), envir = e)
e$config <- .fix_mnt_paths(e$config)
out_dir <- file.path(study_root, "phase3_post_Pooled")
ck <- list(
  config = e$config,
  data = list(raw = dabiao, cleaned = dabiao, mapped = dabiao, imputed = dabiao),
  results = list(),
  log = list(),
  root_output_dir = out_dir
)
.run_one("Pooled", out_dir, ck, .M1, .M2p, e$config)

message("完成：CHARLS / ELSA / Pooled 四分位 logistic")
message("汇总: ", file.path(study_root, "summary_result/table"))
