###############################################################################
#  trajectory_calc_28d_index — 从实验室 CSV 计算 28 天纵向复合指标宽表
#
#  对应用户脚本 calc_28d_index() + save_28d_index()：
#    - 合并 eICU 多分片 / MIMIC 单文件实验室 CSV
#    - 逐日计算 NLR/APRI/LAR/CAR/BUN_Cr/BAR
#    - 保存 12_{Index}.RData（对象 index_df，≥2 天非空）
#
#  trajectory_calc_28d_index = list(
#    index_vars       = c("NLR","APRI","LAR","CAR","BUN_Cr","BAR"),
#    days             = 1:28,
#    min_non_na_days  = 2L,
#    rdata_obj        = "index_df",
#    output_dir       = NULL,          # NULL → config$trajectory_jlcm$output_dir 或 dual_db$output_subdir
#    lab_sources      = NULL,          # NULL → 从 config$dual_db$primary/secondary$lab_sources 读取
#    lab_id_column    = NULL,          # NULL → dual_db$lab_id_column
#    db_type          = NULL,          # NULL → 从 database 名推断 eicu/mimic
#    restrict_to_baseline_ids = TRUE   # 仅保留基线 cohort 中的 subject_id
#  ),
#
#  register_block: "trajectory_calc_28d_index"
#  写: ctx$results$trajectory_28d_index（各指标保存路径与样本量）
###############################################################################

block_trajectory_calc_28d_index <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/trajectory_28d_index_utils.R"), local = FALSE)

  bl <- ctx$config$trajectory_calc_28d_index %||% list()
  cfg <- ctx$config

  id_col <- cfg$data$id_column %||% "subject_id"
  db_name <- tolower(cfg$project$database %||% "")
  db_type <- bl$db_type %||% if (grepl("mimic", db_name)) "mimic" else "eicu"

  # dual_db 覆盖（batch 共享层按库运行时由 trajectory_batch_run_shared_layer 写入）
  db_entry <- NULL
  if (grepl("eicu", db_name)) db_entry <- cfg$dual_db$primary %||% NULL
  if (grepl("mimic", db_name)) db_entry <- cfg$dual_db$secondary %||% NULL

  lab_sources <- bl$lab_sources %||% db_entry$lab_sources %||% NULL
  if (is.null(lab_sources)) {
    stop("trajectory_calc_28d_index: 未配置 lab_sources（config$trajectory_calc_28d_index 或 dual_db）",
         call. = FALSE)
  }

  lab_id_col <- bl$lab_id_column %||% db_entry$lab_id_column %||% id_col

  if (is.null(bl$index_vars) || !length(bl$index_vars)) {
    cfg_ix <- cfg
    if (!is.null(bl$index_group)) {
      if (is.null(cfg_ix$trajectory_batch)) cfg_ix$trajectory_batch <- list()
      cfg_ix$trajectory_batch$index_group <- bl$index_group
    }
    index_vars <- trajectory_batch_resolve_index_vars(cfg_ix)
  } else {
    index_vars <- as.character(bl$index_vars)
  }

  output_dir <- bl$output_dir %||% db_entry$output_subdir %||% NULL
  if (is.null(output_dir) || !nzchar(output_dir)) {
    tpl <- cfg$trajectory_jlcm$output_dir_template %||% NULL
    if (!is.null(tpl)) {
      db_tag <- if (grepl("mimic", db_name)) "mimic" else "eicu"
      output_dir <- gsub("\\{db\\}", db_tag, tpl)
    } else {
      output_dir <- file.path("Data", if (grepl("mimic", db_name)) "mimic" else "eicu")
    }
  }

  baseline <- ctx$data$mapped %||% ctx$data$cleaned %||% ctx$data$imputed
  restrict_ids <- NULL
  if (isTRUE(bl$restrict_to_baseline_ids %||% TRUE) && !is.null(baseline) && id_col %in% names(baseline)) {
    restrict_ids <- unique(as.character(baseline[[id_col]]))
    cli::cli_alert_info("限制至基线 cohort：{length(restrict_ids)} 个 {id_col}")
  }

  days <- as.integer(bl$days %||% 1:28)
  min_non_na <- as.integer(bl$min_non_na_days %||% 2L)
  rdata_obj  <- bl$rdata_obj %||% cfg$trajectory_jlcm$rawdata_obj %||% "index_df"

  results <- trajectory_28d_compute_all(
    lab_sources = lab_sources,
    index_vars = index_vars,
    output_dir = output_dir,
    id_col = id_col,
    lab_id_col = lab_id_col,
    db_type = db_type,
    days = days,
    min_non_na_days = min_non_na,
    rdata_obj = rdata_obj,
    restrict_ids = restrict_ids,
    baseline_df = baseline,
    root = root
  )

  ctx$results$trajectory_28d_index <- lapply(results, function(x) list(path = x$path, n = x$n))
  if (is.null(ctx$config$trajectory_jlcm)) ctx$config$trajectory_jlcm <- list()
  ctx$config$trajectory_jlcm$rawdata_path_template <- file.path(output_dir, "12_{Index}.RData")

  ctx
}

register_block("trajectory_calc_28d_index", block_trajectory_calc_28d_index,
               "28天纵向复合指标宽表计算（12_{Index}.RData）")
