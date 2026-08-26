###############################################################################
#  environment_lod_screen — 插补前官方 LOD 筛查 + Table S1
#
#  register_block: "environment_lod_screen"
#  典型流水线: column_mapping → environment_lod_screen → imputation
###############################################################################

block_environment_lod_screen <- function(ctx, ...) {
  cfg <- ctx$config
  lod_cfg <- cfg$environment_lod %||% list()
  if (!isTRUE(lod_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("environment_lod_screen: enable=FALSE，跳过。")
    return(ctx)
  }

  root <- cfg$project$root %||% getwd()
  util <- file.path(root, "R", "environment_lod_utils.R")
  if (file.exists(util)) source(util, local = FALSE)
  util_voc <- file.path(root, "R", "environment_voc_preprocess_utils.R")
  if (file.exists(util_voc)) source(util_voc, local = FALSE)

  data <- ctx$data$mapped %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data)) {
    stop("environment_lod_screen: 无 mapped/cleaned 数据。", call. = FALSE)
  }

  voc_cols <- as.character(cfg$environment$voc_columns %||% ctx$results$voc_columns %||% character(0))
  if (!length(voc_cols) && exists("environment_resolve_voc_columns", mode = "function")) {
    voc_cols <- environment_resolve_voc_columns(data, cfg)
  }
  voc_cols <- intersect(voc_cols, names(data))
  if (!length(voc_cols)) {
    stop("environment_lod_screen: 未找到 VOC 列。", call. = FALSE)
  }

  paths <- environment_lod_resolve_paths(cfg, root)
  if (is.na(paths$lookup)) {
    stop("environment_lod_screen: 未找到 LOD lookup CSV。", call. = FALSE)
  }
  lookup_df <- utils::read.csv(paths$lookup, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  per_cycle_df <- if (!is.na(paths$per_cycle)) {
    utils::read.csv(paths$per_cycle, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  } else {
    NULL
  }

  env_code <- NULL
  code_path <- cfg$environment$exposure_code_file %||% NULL
  code_obj <- cfg$environment$exposure_code_obj %||% "Envrioment_code"
  if (nzchar(code_path %||% "")) {
    cp <- if (file.exists(code_path)) code_path else file.path(root, code_path)
    if (file.exists(cp)) {
      ee <- new.env()
      load(cp, envir = ee)
      if (exists(code_obj, envir = ee, inherits = FALSE)) {
        env_code <- get(code_obj, envir = ee)
      }
    }
  }

  cli::cli_h2("environment_lod_screen: 官方 LOD 筛查（插补前，{length(voc_cols)} 个 VOC）")
  stats_df <- environment_lod_compute_stats(data, voc_cols, cfg, lookup_df, per_cycle_df)
  attr(stats_df, "lookup_df") <- lookup_df
  attr(stats_df, "per_cycle_df") <- per_cycle_df

  ctx$results$environment_lod_stats <- stats_df

  masked <- environment_lod_apply_mask(data, voc_cols, stats_df, cfg)
  data <- masked$data
  lod_cfg <- cfg$environment_lod %||% list()
  if (isTRUE(lod_cfg$sample_column_filter_enable %||% FALSE)) {
    voc_after_mask <- intersect(voc_cols, names(data))
    filt <- environment_voc_iterative_sample_column_filter(data, voc_after_mask, cfg)
    data <- filt$data
    masked$keep <- filt$keep
    masked$drop <- unique(c(masked$drop, filt$drop))
    ctx$results$environment_voc_sample_column_audit <- filt$audit
    cli::cli_alert_info(paste0(
      "样本×列迭代筛查: A=", round(filt$A_used, 2),
      " (frac=", round(filt$frac_used, 3), "), 行 ",
      filt$audit$n_rows_in[1], "→", filt$audit$n_rows_out[nrow(filt$audit)],
      ", VOC ", length(voc_after_mask), "→", length(filt$keep)
    ))
    if (length(filt$keep) < as.integer(lod_cfg$min_retained_vocs %||% 10L)) {
      cli::cli_alert_warning(
        "迭代后 VOC 仍 < {lod_cfg$min_retained_vocs %||% 10}（当前 {length(filt$keep)}），已采用最优 frac={round(filt$frac_used, 3)}"
      )
    }
    tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
    dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
    audit_path <- file.path(tbl_dir, "Table_Environment_Sample_Column_Filter_Audit.csv")
    tryCatch(
      utils::write.csv(filt$audit, audit_path, row.names = FALSE, fileEncoding = "UTF-8"),
      error = function(e) cli::cli_alert_warning("筛查审计表导出失败: {e$message}")
    )
    stats_df <- environment_lod_compute_stats(data, filt$keep, cfg, lookup_df, per_cycle_df)
    attr(stats_df, "lookup_df") <- lookup_df
    attr(stats_df, "per_cycle_df") <- per_cycle_df
    ctx$results$environment_lod_stats <- stats_df
  }
  prep_util <- file.path(root, "R", "prepare_environment_dkd_data.R")
  if (file.exists(prep_util)) source(prep_util, local = FALSE)
  if (exists("pipeline_sanitize_numeric_for_mice", mode = "function")) {
    san <- pipeline_sanitize_numeric_for_mice(data, cfg)
    data <- san$data
    if (san$n_nonfinite > 0L || san$n_pp_filled > 0L) {
      cli::cli_alert_info(
        "LOD 后数值清洗: 非有限→NA {san$n_nonfinite}，PP 回填 {san$n_pp_filled}"
      )
    }
  }
  if (exists("prepare_environment_winsorize_voc_columns", mode = "function")) {
    ws <- prepare_environment_winsorize_voc_columns(data, masked$keep, cfg)
    data <- ws$data
  }
  if (exists("pipeline_sanitize_numeric_for_mice", mode = "function")) {
    san2 <- pipeline_sanitize_numeric_for_mice(data, cfg)
    data <- san2$data
  }
  id_col <- cfg$data$id_column %||% "SEQN"
  if (!id_col %in% names(data) && "ID" %in% names(data)) id_col <- "ID"
  pre_mi_cols <- intersect(unique(c(id_col, masked$keep)), names(data))
  ctx$results$env_pre_mi <- data[, pre_mi_cols, drop = FALSE]

  cli::cli_alert_info(
    "LOD 筛查: 保留 {length(masked$keep)}，剔除 {length(masked$drop)}"
  )
  if (length(masked$drop)) {
    cli::cli_alert_warning("  剔除: {paste(head(masked$drop, 12), collapse=', ')}{if (length(masked$drop) > 12) ' ...' else ''}")
  }

  ctx$data$mapped <- data
  ctx$data$cleaned <- data
  if (!is.null(ctx$data$raw)) {
    if (nrow(ctx$data$raw) != nrow(data)) {
      id_col_raw <- cfg$data$id_column %||% "SEQN"
      if (!id_col_raw %in% names(data) && "ID" %in% names(data)) id_col_raw <- "ID"
      if (id_col_raw %in% names(data) && id_col_raw %in% names(ctx$data$raw)) {
        keep_ids <- data[[id_col_raw]]
        ctx$data$raw <- ctx$data$raw[ctx$data$raw[[id_col_raw]] %in% keep_ids, , drop = FALSE]
      } else {
        ctx$data$raw <- ctx$data$raw[seq_len(nrow(data)), , drop = FALSE]
      }
    }
    for (col in voc_cols) {
      if (col %in% names(ctx$data$raw) && col %in% names(data)) {
        ctx$data$raw[[col]] <- data[[col]]
      }
      if (col %in% names(masked$drop)) ctx$data$raw[[col]] <- NULL
    }
  }

  ctx$results$environment_lod_applied <- TRUE
  ctx$results$environment_process_stats <- stats_df
  ctx$results$select_vocs_lod <- masked$keep
  ctx$config$environment$voc_columns <- masked$keep
  if (exists("environment_patch_voc_exclude", mode = "function")) {
    ctx$config <- environment_patch_voc_exclude(ctx$config, data)
  } else {
    ctx$config$incidence$index_exclude_vars <- masked$keep
  }

  tbl_s1 <- environment_lod_build_table_s1(stats_df, env_code, lookup_df, length(masked$keep))
  ctx$results$env_characteristics_table <- tbl_s1
  ctx$results$exposure_count <- sum(tbl_s1$Process == "log(ln)", na.rm = TRUE)

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_title <- as.character(
    (cfg$environment_characteristics %||% list())$table_title %||%
      paste0("Table S1. Characteristics of ", nrow(tbl_s1),
             " Environmental Contaminants or Metabolites")
  )
  tbl_file <- file.path(tbl_dir, "Table S1. Characteristics of Environmental Contaminants or Metabolites.xlsx")
  if (isTRUE(lod_cfg$sample_column_filter_enable %||% FALSE)) {
    t1_note <- paste0(
      "Note. Official LOD: values at/below instrument LOD set to missing (",
      basename(paths$lookup), "). Then sample filter: drop subjects with VOC missing count > ",
      "A (A = n_VOC × ", lod_cfg$sample_miss_frac_initial %||% 0.8,
      ", auto-tighten if retained VOC < ", lod_cfg$min_retained_vocs %||% 10L,
      "). Column filter: drop VOCs with missing > ",
      round(100 * as.numeric(lod_cfg$column_missing_cutoff %||% 0.4)), "%."
    )
  } else {
    t1_note <- paste0(
      "Note. Official Instrument LOD from NHANES laboratory documentation (see ",
      basename(paths$lookup), "). Under LOD(%) = proportion at or below official LOD ",
      "per NHANES cycle. Analytes excluded if raw missingness > ",
      round(100 * as.numeric(lod_cfg$missing_cutoff %||% 0.2)), "% or Under-LOD > ",
      round(100 * as.numeric(lod_cfg$under_lod_cutoff %||% 0.8)),
      "%. Values at/below LOD set to missing and excluded from downstream analysis."
    )
  }
  environment_lod_write_titled_table(tbl_s1, tbl_title, tbl_file, note = t1_note)
  if (exists("queue_table_export", mode = "function")) {
    ctx <- queue_table_export(ctx, tbl_file, tbl_title)
  }
  cli::cli_alert_success("Table S1 已导出: {basename(tbl_file)}")

  ctx
}

register_block(
  "environment_lod_screen",
  block_environment_lod_screen,
  "Pre-imputation official LOD screen + Table S1 (C03 RespiratoryCancer logic)"
)
