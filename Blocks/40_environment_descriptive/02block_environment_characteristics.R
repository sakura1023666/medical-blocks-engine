###############################################################################
#  environment_characteristics — 环境暴露特征描述表（Table S1）
#
#  register_block: "environment_characteristics"
#  典型流水线: process_environment_data → environment_characteristics
#
#  功能：
#    从 process_environment_data block 产出的统计表（environment_process_stats）
#    与暴露标签代码表（label_mapping_df）合并，
#    将 Process 列为 "log(ln)" 但实际已被删除的行修正为 "removed"，
#    生成 SCI 三线格式的环境特征描述表（xlsx）。
#
#  # ── Bug 修复说明（相对原 C01_Environmental_Characteristics.R）────────────
#  Bug 1: load(Uni_RData) 加载后从未使用（注释掉的代码块已废弃）→ 删除
#  Bug 2: colnames(stats)[1] <- 'Abbreviation' 按位置改列名；若列顺序变化则
#         修改了错误的列 → 改为按列名查找后重命名
#  Bug 3: colnames(Envrioment_code)[3] <- 'Abbreviation' 同上 → 同样修复
#  Bug 4: merge(Envrioment_code, stats_update) 依赖列名 'Abbreviation' 匹配，
#         若两者对应列名不一致会静默返回空表 → 显式指定 by 参数
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_ctx_results = environment_process_stats（由 process_environment_data 写入）
#  可选数据            = ctx$data$imputed（用于校验最终保留的 VOC 列名）
#
#  # ── 配置 config$environment_characteristics ─────────────────────────────
#  environment_characteristics = list(
#    # ── 统计表来源（优先级从高到低）──────────────────────────────────────
#    stats_source         = "ctx",      # "ctx" = ctx$results$environment_process_stats
#                                        # "file" = 从文件路径读取
#    stats_file_path      = NULL,        # 仅 stats_source="file" 时使用
#    # ── 列名映射（统计表中各列名）──────────────────────────────────────────
#    stats_id_col         = NULL,        # 统计表中的暴露 ID 列名；
#                                        # NULL = 自动检测（environment_feature 或第1列）
#    # ── 标签代码表（暴露内部列名 → 家族/展示名）────────────────────────────
#    label_df             = NULL,        # data.frame；NULL = ctx$results$env_label_df
#    label_df_id_col      = NULL,        # 标签表中与统计表对接的 ID 列名（自动检测）
#    # ── 最终保留 VOC 检验 ──────────────────────────────────────────────────
#    final_vocs_col       = "Process",   # 用于标记最终使用/删除的列名
#    final_vocs_kept_val  = "log(ln)",   # 该值的行认为是"保留"
#    verify_against_data  = TRUE,        # 是否校验：在 imputed data 中不存在则标 "removed"
#    # ── 输出 ──────────────────────────────────────────────────────────────
#    output_col_names     = NULL,        # 自定义输出列名向量；NULL = 保留合并后列名
#    table_filename       = NULL,        # NULL = "Table_Environment_Characteristics.xlsx"
#    table_title          = NULL
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$results$env_characteristics_table — 最终特征表 data.frame
#      ctx$results$exposure_count           — log(ln) 处理（最终保留）的暴露数
#  文件: Tables/Table_Environment_Characteristics.xlsx
###############################################################################

# ── 辅助：安全地从 data.frame 中按名或位查找列 ──────────────────────────────
.ec02_find_col_name <- function(df, candidates, position = 1L) {
  for (cand in candidates) {
    if (cand %in% names(df)) return(cand)
  }
  # fallback: 返回位置 position 处的列名
  if (position <= ncol(df)) return(names(df)[position])
  NULL
}

# ── 辅助：SCI 三线表 xlsx 导出 ───────────────────────────────────────────────
.ec02_export_xlsx <- function(df, filepath, title) {
  library(openxlsx)
  wb <- createWorkbook()
  addWorksheet(wb, "Sheet1")
  writeData(wb, "Sheet1", df,    startRow = 2L, startCol = 1L)
  writeData(wb, "Sheet1", title, startRow = 1L, startCol = 1L)

  n_col <- ncol(df)
  title_style  <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold", border = "bottom",
                               halign = "center", valign = "center")
  header_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               textDecoration = "bold")
  body_style   <- createStyle(fontName = "Times New Roman", fontSize = 12)
  bottom_style <- createStyle(fontName = "Times New Roman", fontSize = 12,
                               border = "bottom")

  mergeCells(wb, "Sheet1", cols = 1:n_col, rows = 1L)
  addStyle(wb, "Sheet1", title_style,  rows = 1L, cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", header_style, rows = 2L, cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", body_style,
           rows = 3L:(nrow(df) + 2L), cols = 1:n_col, gridExpand = TRUE)
  addStyle(wb, "Sheet1", bottom_style,
           rows = nrow(df) + 3L, cols = 1:(n_col + 1L), gridExpand = FALSE)
  showGridLines(wb, "Sheet1", showGridLines = FALSE)
  setColWidths(wb, "Sheet1", cols = 1:n_col, widths = "auto")
  setColWidths(wb, "Sheet1", cols = 1L, widths = 20)
  saveWorkbook(wb, filepath, overwrite = TRUE)
}

# ── Block 主函数 ──────────────────────────────────────────────────────────────
block_environment_characteristics <- function(ctx, ...) {
  cfg    <- ctx$config
  bl_cfg <- cfg$environment_characteristics %||% list()

  if (isTRUE(ctx$results$environment_lod_applied %||% FALSE) &&
      !is.null(ctx$results$env_characteristics_table)) {
    cli::cli_alert_info(
      "environment_characteristics: 已由 environment_lod_screen 导出 Table S1，跳过。"
    )
    return(ctx)
  }

  # ── 读取统计表 ────────────────────────────────────────────────────────────
  stats_source <- as.character(bl_cfg$stats_source %||% "ctx")

  if (stats_source == "file") {
    stats_path <- as.character(bl_cfg$stats_file_path %||% "")
    if (!nzchar(stats_path) || !file.exists(stats_path)) {
      stop("environment_characteristics: stats_file_path \u4e0d\u5b58\u5728\u6216\u672a\u8bbe\u7f6e\u3002")
    }
    stats_raw <- utils::read.csv(stats_path, stringsAsFactors = FALSE)
    cli::cli_alert_info("environment_characteristics: \u4ece\u6587\u4ef6\u8bfb\u53d6\u7edf\u8ba1\u8868: {stats_path}")
  } else {
    stats_raw <- ctx$results$environment_process_stats
    if (is.null(stats_raw) || !is.data.frame(stats_raw)) {
      stop(
        "environment_characteristics: ctx$results$environment_process_stats \u4e3a\u7a7a\uff0c",
        "\u8bf7\u5148\u8fd0\u884c process_environment_data block\u3002"
      )
    }
    cli::cli_alert_info("environment_characteristics: \u4ece ctx$results \u8bfb\u53d6\u7edf\u8ba1\u8868")
  }

  # ── 统计表 ID 列（修复 Bug 2：按名查找，不按位置）────────────────────────
  stats_id_candidates <- c(
    as.character(bl_cfg$stats_id_col %||% ""),
    "environment_feature", "Abbreviation", "variable", "feature"
  )
  stats_id_col <- .ec02_find_col_name(stats_raw, stats_id_candidates, 1L)
  if (is.null(stats_id_col)) {
    stop("environment_characteristics: \u65e0\u6cd5\u786e\u5b9a\u7edf\u8ba1\u8868\u7684 ID \u5217\u3002")
  }
  cli::cli_alert_info("environment_characteristics: \u7edf\u8ba1\u8868 ID \u5217 = '{stats_id_col}'")

  # 统一为 Abbreviation（供后续 merge 使用）
  stats_work <- stats_raw
  if (stats_id_col != "Abbreviation") {
    names(stats_work)[names(stats_work) == stats_id_col] <- "Abbreviation"
  }

  # ── 校验：在最终数据中不存在的 log(ln) 行标记为 removed ─────────────────
  process_col <- as.character(bl_cfg$final_vocs_col     %||% "Process")
  kept_vals   <- as.character(bl_cfg$final_vocs_kept_val %||% "log(ln)")
  if (!length(kept_vals)) kept_vals <- "log(ln)"
  verify_data <- isTRUE(bl_cfg$verify_against_data %||% TRUE)

  if (verify_data && process_col %in% names(stats_work)) {
    data_imputed <- ctx$data$imputed %||% ctx$data$cleaned
    if (!is.null(data_imputed) && is.data.frame(data_imputed)) {
      final_cols <- names(data_imputed)
      log_ln_rows <- stats_work[[process_col]] %in% kept_vals
      not_in_data <- !stats_work$Abbreviation %in% final_cols
      to_mark     <- log_ln_rows & not_in_data
      if (any(to_mark, na.rm = TRUE)) {
        stats_work[[process_col]][to_mark] <- "removed"
        cli::cli_alert_info(
          "environment_characteristics: \u6807\u8bb0 {sum(to_mark, na.rm=TRUE)} \u5217\u4e3a 'removed'\uff08\u5df2\u5220\u9664\uff09"
        )
      }
    } else {
      cli::cli_alert_warning(
        "environment_characteristics: verify_against_data=TRUE \u4f46\u65e0 imputed data\uff0c\u8df3\u8fc7\u6821\u9a8c\u3002"
      )
    }
  }

  # ── 读取标签代码表（暴露标签映射）────────────────────────────────────────
  label_df <- bl_cfg$label_df %||% ctx$results$env_label_df

  if (!is.null(label_df) && is.data.frame(label_df)) {
    # 修复 Bug 3：按名查找 label_df 中的 Abbreviation 列，不按位置
    label_id_candidates <- c(
      as.character(bl_cfg$label_df_id_col %||% ""),
      "Abbreviation", "Labels", "label", "id"
    )
    label_id_col <- .ec02_find_col_name(label_df, label_id_candidates, 3L)
    if (!is.null(label_id_col) && label_id_col != "Abbreviation") {
      label_df <- label_df
      names(label_df)[names(label_df) == label_id_col] <- "Abbreviation"
    }

    # 修复 Bug 4：显式指定 by = "Abbreviation"，避免静默空表
    TableS1 <- merge(label_df, stats_work, by = "Abbreviation", all.x = FALSE)
    cli::cli_alert_success(
      "environment_characteristics: \u5408\u5e76\u5b8c\u6210\uff0c{nrow(TableS1)} \u884c"
    )
  } else {
    cli::cli_alert_warning(
      "environment_characteristics: \u672a\u63d0\u4f9b\u6807\u7b7e\u8868\uff0c\u4ec5\u8f93\u51fa\u7edf\u8ba1\u8868\u3002"
    )
    TableS1 <- stats_work
  }

  # ── 重命名列（可选）─────────────────────────────────────────────────────
  out_col_names <- bl_cfg$output_col_names
  if (!is.null(out_col_names) && length(out_col_names) == ncol(TableS1)) {
    colnames(TableS1) <- out_col_names
  }

  # ── 统计保留的暴露数量 ────────────────────────────────────────────────────
  # 找 Process 列（重命名后可能不同）
  proc_col_final <- if (process_col %in% names(TableS1)) {
    process_col
  } else if ("Process" %in% names(TableS1)) {
    "Process"
  } else {
    NULL
  }
  exposure_count <- if (!is.null(proc_col_final)) {
    sum(TableS1[[proc_col_final]] %in% kept_vals, na.rm = TRUE)
  } else {
    nrow(TableS1)
  }
  ctx$results$env_characteristics_table <- TableS1
  ctx$results$exposure_count            <- exposure_count
  cli::cli_alert_success(
    "environment_characteristics: \u6700\u7ec8\u4fdd\u7559 {exposure_count} \u4e2a\u66b4\u9732\uff08{paste(kept_vals, collapse=', ')}\uff09"
  )

  # ── 导出 Excel ────────────────────────────────────────────────────────────
  tbl_dir  <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
  tbl_fn   <- as.character(
    bl_cfg$table_filename %||% "Table_Environment_Characteristics.xlsx"
  )
  tbl_path <- file.path(tbl_dir, tbl_fn)
  disease_name <- as.character(
    cfg$project$disease %||% cfg$project$analysis_group %||% "Disease"
  )
  tbl_title <- as.character(
    bl_cfg$table_title %||%
    paste0("Table S1. Environmental characteristics of ", exposure_count,
           " environmental exposures included in the analysis")
  )
  tryCatch({
    .ec02_export_xlsx(TableS1, tbl_path, tbl_title)
    cli::cli_alert_success("{tbl_fn} \u5df2\u5c55\u5b58")
  }, error = function(e) {
    cli::cli_alert_warning(
      "environment_characteristics: Excel \u5c55\u5b58\u5931\u8d25: {e$message}"
    )
  })

  cli::cli_alert_success("environment_characteristics \u5b8c\u6210\u3002")
  ctx
}

register_block(
  "environment_characteristics",
  block_environment_characteristics,
  "\u73af\u5883\u66b4\u9732\u7279\u5f81\u63cf\u8ff0\u8868 Table S1\uff08\u5408\u5e76\u5904\u7406\u7edf\u8ba1\u4e0e\u6807\u7b7e\u8868\uff09"
)
