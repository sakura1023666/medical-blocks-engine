###############################################################################
#  dual_db_column_harmonize — 闸门 A：插补前对齐两库列名（人口学可异，其余取交集）
###############################################################################

block_dual_db_column_harmonize <- function(ctx) {
  cfg <- ctx$config
  dual <- cfg$dual_db %||% list()
  if (!isTRUE(dual$enable)) {
    cli::cli_alert_info("dual_db 未启用，跳过列对齐。")
    return(ctx)
  }

  harm <- dual$harmonization %||% list()
  db_name <- as.character(dual$current_db %||% "")[1L]
  keep <- dual_db_column_keep_for_db(cfg, db_name, harm)
  data_src_early <- ctx$data$mapped
  if (!exists("pipeline_ventilation_keep_alias", mode = "function")) {
    utils_src <- file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "."), "R", "utils.R")
    if (file.exists(utils_src)) source(utils_src, local = FALSE)
  }
  if (exists("pipeline_ventilation_keep_alias", mode = "function") &&
      !is.null(data_src_early)) {
    keep <- pipeline_ventilation_keep_alias(keep, names(data_src_early))
  }
  if (!length(keep)) {
    cli::cli_alert_warning(
      "闸门 A：无 column_keep_{db_name}；将跳过列过滤（请先跑 Gate A / --db both）。"
    )
    return(ctx)
  }

  data_src <- ctx$data$mapped
  if (is.null(data_src)) {
    stop("dual_db_column_harmonize: ctx$data$mapped 为空。", call. = FALSE)
  }

  n_before <- ncol(data_src)
  if (length(keep) < 10L && n_before >= 20L) {
    cli::cli_alert_warning(
      "闸门 A keep 仅 {length(keep)} 列而数据有 {n_before} 列，跳过过滤以免只剩结局。"
    )
    return(ctx)
  }
  data_filt <- dual_db_filter_data_columns(data_src, keep, "闸门 A")
  if (exists("pipeline_ensure_outcome_group_column", mode = "function")) {
    data_filt <- pipeline_ensure_outcome_group_column(data_filt, cfg)
  }
  # 早期衍生 BMI（表1/单多因素/亚组共用；不依赖 index 指标列）
  derive_cfg <- harm$derive_bmi %||% list(enable = TRUE)
  if (exists("dual_db_derive_bmi", mode = "function")) {
    data_filt <- dual_db_derive_bmi(data_filt, derive_cfg)
  }
  ctx$data$mapped <- data_filt
  ctx$results$dual_db_column_harmonized <- TRUE
  ctx$results$dual_db_column_keep <- keep

  cli::cli_alert_success(
    "闸门 A [{toupper(db_name)}]: {n_before} → {ncol(data_filt)} 列（共享非人口学 {length(harm$common_non_demo_cols %||% character(0))}）"
  )
  ctx
}

register_block(
  "dual_db_column_harmonize",
  block_dual_db_column_harmonize,
  "Dual-DB gate A: harmonize column names before imputation"
)
