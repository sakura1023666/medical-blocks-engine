###############################################################################
#  environment_voc_log_transform — 环境 VOC log/ln 审计（默认不变换数据）
#
#  插补后、Table 1 前：导出 Environment_VOC_Log_Status.txt，说明 Step01 哪些已 log。
#  仅当 config$environment_voc_log_transform$apply_log = TRUE 时才执行 log(x+1)。
###############################################################################

block_environment_voc_log_transform <- function(ctx, ...) {
  cfg  <- ctx$config
  root <- (cfg$project %||% list())$root %||% getwd()
  helper <- file.path(root, "R", "environment_voc_preprocess_utils.R")
  if (file.exists(helper)) source(helper, local = FALSE)

  ep <- cfg$environment_voc_log_transform %||% list()
  if (isFALSE(ep$enable %||% TRUE)) {
    cli::cli_alert_info("environment_voc_log_transform: 已关闭，跳过。")
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("environment_voc_log_transform: 无可用数据，请先运行 imputation。", call. = FALSE)
  }

  tbl_dir <- ctx$output_dir_tables %||%
    file.path(ctx$output_dir %||% ".", "Tables")
  if (exists("environment_export_voc_log_status_txt", mode = "function")) {
    txt_path <- environment_export_voc_log_status_txt(data, cfg, root, tbl_dir)
    ctx$results$environment_voc_log_status_txt <- txt_path
    status_df <- environment_build_voc_log_status_df(data, cfg, root)
    ctx$results$environment_voc_log_status <- status_df
  }

  if (exists("environment_patch_baseline_table1_labels", mode = "function")) {
    ctx$config <- environment_patch_baseline_table1_labels(ctx$config, data, root)
  }

  if (isTRUE(ep$apply_log %||% FALSE)) {
    prelog_extra <- ctx$results$environment_early_log_vocs %||% character(0)
    res <- environment_apply_voc_log_transform(data, cfg, root, prelog_extra = prelog_extra)
    ctx$data$imputed <- res$data
    ctx$data$cleaned <- res$data
    ctx$results$environment_prelog_vocs <- unique(c(
      res$prelog_vocs,
      ctx$results$environment_prelog_vocs %||% character(0)
    ))
    ctx$results$environment_early_log_vocs <- unique(c(
      ctx$results$environment_early_log_vocs %||% character(0),
      res$newly_logged
    ))
    cli::cli_alert_success(
      "environment_voc_log_transform: 已 log {length(res$newly_logged)} 列，跳过 {length(res$prelog_vocs)} 列"
    )
  } else {
    prelog <- environment_prelog_voc_columns(cfg, root)
    ctx$results$environment_prelog_vocs <- prelog
    cli::cli_alert_info(
      "environment_voc_log_transform: 未对数据做 log/ln（apply_log=FALSE），仅导出状态 TXT。"
    )
  }

  ctx
}

register_block(
  "environment_voc_log_transform",
  block_environment_voc_log_transform,
  "环境 VOC log/ln 审计（默认不变换；导出 Environment_VOC_Log_Status.txt）"
)
