###############################################################################
#  process_environment_data — 环境暴露数据预处理
#                              （LOD 检测限处理 + 对数变换 + 二值化 + MICE 插补）
#
#  register_block: "process_environment_data"
#  典型流水线: column_mapping → process_environment_data → logistic_environment_glm
#
#  算法说明（逐列处理）：
#    1. 以第10百分位数作为检测限（LOD）
#    2. 缺失率 > missing_percentage_cutoff 或 LOD以下占比 > 0.9 → 删除该列
#    3. LOD以下占比 > below_limit_percentage_cutoff            → floor 处理（低于LOD置0，高于LOD保留原值）
#    4. 其余                                                   → 自然对数变换 log(x + 1)
#    5. 对处理后数据做 MICE 多重插补（若有缺失）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$mapped %||% ctx$data$cleaned
#
#  # ── 配置 config$environment_process ──────────────────────────────────────
#  environment_process = list(
#    id_column                     = "SEQN",   # 行 ID 列名；NULL 或 "" 则不处理 ID 列
#    missing_percentage_cutoff     = 0.2,       # 缺失率阈值，超过则删除该列（0~1）
#    below_limit_percentage_cutoff = 0.8,       # LOD 以下占比阈值，超过则 floor 处理（0~1）
#    seed                          = 123L,      # 随机种子
#    mice_m                        = 5L,        # MICE 插补集数
#    mice_method                   = "pmm",     # MICE 单变量插补方法
#    export_stats                  = TRUE       # 是否导出处理统计表 CSV
#  ),
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: ctx$data$imputed              — 处理并插补后的数据
#      ctx$results$environment_process_stats — 逐列处理统计 data.frame
#  文件: Tables/Table_Environment_Process_Stats.csv
###############################################################################

.env01_clean_colnames <- function(data) {
  names(data) <- gsub("\\s+", "_", names(data))
  names(data) <- trimws(names(data))
  names(data) <- make.names(names(data), unique = TRUE)
  data
}

.env01_process_column <- function(data, col, stats_row,
                                   missing_cutoff, below_cutoff,
                                   already_logged = FALSE,
                                   apply_log = TRUE) {
  x          <- data[[col]]
  if (!is.numeric(x)) {
    x <- suppressWarnings(as.numeric(as.character(x)))
    data[[col]] <- x
  }
  valid_mask <- !is.na(x)
  n_valid    <- sum(valid_mask)

  if (n_valid == 0L) {
    stats_row$Process <- "no_valid_samples_removed"
    data[[col]] <- NULL
    cli::cli_alert_warning("  [{col}] 无有效样本，已删除。")
    return(list(data = data, stats_row = stats_row))
  }

  # LOD = 第10百分位数
  lod         <- quantile(x, 0.1, na.rm = TRUE)
  n_below_lod <- sum(x < lod, na.rm = TRUE)
  mean_val    <- mean(x, na.rm = TRUE)
  sd_val      <- sd(x, na.rm = TRUE)
  n_abnormal  <- sum(
    (x > mean_val + 3 * sd_val | x < mean_val - 3 * sd_val),
    na.rm = TRUE
  )

  stats_row$LOD                   <- lod
  stats_row$Under_LOD_pct         <- n_below_lod / n_valid * 100
  stats_row$Missing_pct           <- sum(is.na(x)) / length(x) * 100
  stats_row$Abnormal_value_permil <- n_abnormal / n_valid * 1000
  stats_row$Median_IQR            <- paste0(
    round(median(x, na.rm = TRUE), 2), "(", round(IQR(x, na.rm = TRUE), 2), ")"
  )
  stats_row$Mean_SD <- paste0(round(mean_val, 4), "\u00b1", round(sd_val, 4))

  below_prop   <- stats_row$Under_LOD_pct / 100
  missing_prop <- stats_row$Missing_pct / 100

  if (isTRUE(already_logged)) {
    stats_row$Process <- "already_log(ln)"
    cli::cli_alert_info("  [{col}] 已在 Step01 完成 log/ln，跳过重复变换")
    return(list(data = data, stats_row = stats_row))
  }

  if (below_prop > 0.9 || missing_prop > missing_cutoff) {
    stats_row$Process <- "removed"
    data[[col]] <- NULL
    cli::cli_alert_info(
      "  [{col}] 删除 (LOD\u4ee5\u4e0b={round(below_prop*100,1)}%, \u7f3a\u5931={round(missing_prop*100,1)}%)"
    )
  } else if (below_prop > below_cutoff) {
    # Floor \u5904\u7406\uff1a\u4f4e\u4e8e LOD \u7f6e 0\uff0c\u9ad8\u4e8e LOD \u4fdd\u7559\u539f\u503c
    data[[col]]       <- ifelse(x < lod, 0, x)
    stats_row$Process <- "floor_at_lod"
    cli::cli_alert_info(
      "  [{col}] floor\u5904\u7406 (LOD\u4ee5\u4e0b={round(below_prop*100,1)}%)"
    )
  } else if (isTRUE(apply_log)) {
    data[[col]]       <- log(x + 1)
    stats_row$Process <- "log(ln)"
    cli::cli_alert_success("  [{col}] \u5bf9\u6570\u53d8\u6362")
  } else {
    stats_row$Process <- "raw(no_log)"
    cli::cli_alert_info("  [{col}] \u672a log/ln\uff08\u4fdd\u7559\u539f\u59cb\u5c3a\u5ea6\uff0c\u4ec5\u8bb0\u5f55\u72b6\u6001\uff09")
  }

  list(data = data, stats_row = stats_row)
}

block_process_environment_data <- function(ctx, ...) {
  suppressPackageStartupMessages(library(mice))

  cfg     <- ctx$config
  env_cfg <- cfg$environment_process %||% list()

  data <- ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop(
      "process_environment_data: \u672a\u627e\u5230\u6570\u636e\uff0c",
      "\u8bf7\u5148\u8fd0\u884c imputation / column_mapping \u6216\u5176\u4ed6\u6570\u636e\u51c6\u5907 block\u3002"
    )
  }

  id_col        <- as.character(env_cfg$id_column %||% "SEQN")
  missing_cutoff <- as.numeric(env_cfg$missing_percentage_cutoff     %||% 0.2)
  below_cutoff   <- as.numeric(env_cfg$below_limit_percentage_cutoff %||% 0.8)
  seed          <- as.integer(env_cfg$seed        %||% 123L)
  mice_m        <- as.integer(env_cfg$mice_m      %||% 5L)
  mice_method   <- as.character(env_cfg$mice_method %||% "pmm")
  export_stats  <- isTRUE(env_cfg$export_stats    %||% TRUE)
  apply_log     <- isTRUE(env_cfg$apply_log_transform %||% FALSE)
  only_voc      <- isTRUE(env_cfg$only_voc_cols %||% TRUE)

  root <- cfg$project$root %||% getwd()
  helper <- file.path(root, "R", "environment_voc_preprocess_utils.R")
  if (file.exists(helper)) source(helper, local = FALSE)

  prelog_vocs <- character(0)
  if (exists("environment_prelog_voc_columns", mode = "function")) {
    prelog_vocs <- environment_prelog_voc_columns(cfg, root)
    early_log <- ctx$results$environment_early_log_vocs %||% character(0)
    prelog_vocs <- unique(c(prelog_vocs, early_log))
    if (length(prelog_vocs)) {
      cli::cli_alert_info(
        "process_environment_data: Step01 已 log/ln 的 {length(prelog_vocs)} 个 VOC 将跳过重复变换"
      )
    }
  }

  set.seed(seed)

  data <- data.frame(data, stringsAsFactors = FALSE, check.names = FALSE)
  data <- .env01_clean_colnames(data)

  if (exists("environment_patch_voc_exclude", mode = "function")) {
    cfg <- environment_patch_voc_exclude(cfg, data)
    ctx$config <- cfg
  }

  voc_cols <- as.character(env_cfg$target_cols %||% character(0))
  voc_cols <- voc_cols[nzchar(voc_cols)]
  if (!length(voc_cols) && only_voc &&
      exists("environment_resolve_voc_columns", mode = "function")) {
    voc_cols <- environment_resolve_voc_columns(data, cfg)
  }
  if (!length(voc_cols) && only_voc) {
    pat <- (cfg$environment %||% list())$voc_col_pattern
    if (!is.null(pat) && nzchar(pat)) {
      voc_cols <- names(data)[grepl(pat, names(data), ignore.case = TRUE)]
    }
    fixed_excl <- if (exists("environment_voc_exclude_fixed", mode = "function")) {
      environment_voc_exclude_fixed(cfg)
    } else {
      character(0)
    }
    voc_cols <- setdiff(voc_cols, fixed_excl)
  }
  if (!length(voc_cols)) {
    voc_cols <- names(data)
    only_voc <- FALSE
    cli::cli_alert_warning(
      "process_environment_data: 未识别 VOC 列，将处理全部 {length(voc_cols)} 列（建议设置 environment$voc_col_pattern）。"
    )
  } else {
    cli::cli_alert_info(
      "process_environment_data: 仅处理 {length(voc_cols)} 个 VOC 列，保留其余临床列。"
    )
  }

  if (!only_voc && nzchar(id_col) && id_col %in% names(data)) {
    rownames(data) <- as.character(data[[id_col]])
    data[[id_col]] <- NULL
    cli::cli_alert_info(
      "process_environment_data: \u4ee5 {id_col} \u8bbe\u7f6e\u884c\u540d\u5e76\u79fb\u9664\u3002"
    )
  }

  stats <- data.frame(
    environment_feature           = voc_cols,
    LOD                           = numeric(length(voc_cols)),
    Under_LOD_pct                 = numeric(length(voc_cols)),
    Missing_pct                   = numeric(length(voc_cols)),
    Abnormal_value_permil         = numeric(length(voc_cols)),
    Median_IQR                    = character(length(voc_cols)),
    Mean_SD                       = character(length(voc_cols)),
    Process                       = character(length(voc_cols)),
    stringsAsFactors              = FALSE
  )

  cli::cli_h2("process_environment_data: \u5904\u7406 {length(voc_cols)} \u5217\u73af\u5883\u66b4\u9732\u53d8\u91cf")

  for (i in seq_along(voc_cols)) {
    col <- voc_cols[i]
    if (!col %in% names(data)) next
    if (!is.numeric(data[[col]]) && !is.logical(data[[col]])) {
      suppressWarnings(data[[col]] <- as.numeric(as.character(data[[col]])))
    }
    if (!is.numeric(data[[col]])) {
      cli::cli_alert_warning("  [{col}] 非数值列，跳过环境暴露处理。")
      stats[i, "Process"] <- "skipped_non_numeric"
      next
    }
    result <- .env01_process_column(
      data, col, stats[i, ], missing_cutoff, below_cutoff,
      already_logged = col %in% prelog_vocs,
      apply_log = apply_log
    )
    data <- result$data
    stats[i, ] <- result$stats_row
    if (!col %in% names(data)) next
  }

  voc_present <- intersect(voc_cols, names(data))
  n_missing <- if (length(voc_present)) sum(is.na(data[, voc_present, drop = FALSE])) else 0L
  if (n_missing > 0L) {
    cli::cli_h2(
      "process_environment_data: VOC MICE \u63d2\u8865 (m={mice_m}, method='{mice_method}', seed={seed})"
    )
    imp_data <- data[, voc_present, drop = FALSE]
    imp          <- mice::mice(
      imp_data, m = mice_m, method = mice_method,
      seed = seed, printFlag = FALSE
    )
    imp_complete <- mice::complete(imp, 1L)
    data[, voc_present] <- imp_complete
  } else {
    cli::cli_alert_info("process_environment_data: VOC 无缺失值，跳过 MICE。")
  }

  ctx$data$imputed <- data
  ctx$results$environment_process_stats <- stats
  ctx$results$environment_voc_cols <- voc_present
  ctx$results$environment_prelog_vocs <- prelog_vocs
  if (exists("environment_build_env_label_df", mode = "function")) {
    ctx$results$env_label_df <- environment_build_env_label_df(voc_present, cfg, root)
    n_unmap <- sum(ctx$results$env_label_df$Family == "Unmapped", na.rm = TRUE)
    if (n_unmap > 0L) {
      cli::cli_alert_warning(
        "process_environment_data: {n_unmap} 个 VOC 未匹配暴露代码表（Family=Unmapped）"
      )
    }
  }

  if (isTRUE(export_stats)) {
    tbl_dir <- ctx$output_dir_tables %||%
      file.path(ctx$output_dir %||% ".", "Tables")
    if (!dir.exists(tbl_dir)) dir.create(tbl_dir, recursive = TRUE)
    tbl_path <- file.path(tbl_dir, "Table_Environment_Process_Stats.csv")
    tryCatch(
      utils::write.csv(stats, tbl_path, row.names = FALSE),
      error = function(e) {
        cli::cli_alert_warning("\u7edf\u8ba1\u8868\u5bfc\u51fa\u5931\u8d25: {e$message}")
      }
    )
    cli::cli_alert_success("\u5904\u7406\u7edf\u8ba1\u8868\u5df2\u4fdd\u5b58: {basename(tbl_path)}")
    if (exists("environment_export_log_transform_summary", mode = "function")) {
      environment_export_log_transform_summary(stats, prelog_vocs, tbl_dir)
    }
  }

  n_removed <- sum(
    stats$Process %in% c("removed", "no_valid_samples_removed"),
    na.rm = TRUE
  )
  n_floor  <- sum(stats$Process == "floor_at_lod", na.rm = TRUE)
  n_already <- sum(stats$Process == "already_log(ln)", na.rm = TRUE)
  n_log    <- sum(stats$Process == "log(ln)", na.rm = TRUE)

  cli::cli_alert_success(
    "process_environment_data \u5b8c\u6210: \u5220\u9664 {n_removed} \u5217, floor {n_floor} \u5217, \u5df2log {n_already} \u5217, \u65b0log {n_log} \u5217"
  )

  ctx
}

register_block(
  "process_environment_data",
  block_process_environment_data,
  "\u73af\u5883\u66b4\u9732\u9884\u5904\u7406\uff1aLOD \u68c0\u6d4b\u9650\u5220\u5217/floor/\u5bf9\u6570\u53d8\u6362 + MICE \u63d2\u8865"
)
