###############################################################################
#  trajectory_chisq — 轨迹组 × 结局变量 卡方检验（GBMT/JLCM 通用）
#
#  路径: Blocks/26_trajectory/05block_trajectory_chisq.R
#  register_block: "trajectory_chisq"
#  读 config$trajectory（index_vars, class_for_test, outcome_vars 等）
#
#  Block: trajectory_chisq — 轨迹组 × 结局变量 卡方检验
#
#  功能：
#    - 读取各 Index × D 的轨迹类别分配（ctx$data$trajectory_long 优先，磁盘兜底）
#    - 加载插补后结局数据（ctx$data$imputed 优先，outcome_data_path 磁盘兜底）
#    - 对 class_for_test × outcome_vars 所有组合执行卡方检验
#      （期望频数 < 5 时自动切换为 Fisher's exact test）
#    - 汇总为一张总表，输出 SCI 三线表（xlsx + tex）
#    - 若所有组合均 p >= p_threshold，触发交互式暂停
#
#  依赖 block：
#    - trajectory_gbmt / trajectory_jlcm（或已有落盘的 D01_long_*.RData）
#    - block_imputation       （提供 ctx$data$imputed；或配置 outcome_data_path）
#
#  输入：
#    ctx$data$trajectory_long[["Index_DD"]]  — 轨迹类别分配（fit block 产出）
#    ctx$data$imputed                        — 插补后数据（含结局变量，优先）
#    config$trajectory$index_vars
#    config$trajectory$class_for_test        — 检验哪些类别数（最终选定分类）
#    config$trajectory$outcome_vars          — 结局变量列表
#    config$trajectory$outcome_data_path     — 兜底路径（ctx$data$imputed 为空时）
#    config$trajectory$outcome_data_obj      — RData 中对象名（默认 "imputed_data"）
#    config$trajectory$p_threshold           — 显著性阈值（默认 0.05）
#    config$trajectory$long_data_dir         — 轨迹数据磁盘兜底目录（可选）
#    config$trajectory$long_data_filename_template
#    config$trajectory$long_data_obj
#
#  输出：
#    ctx$results$trajectory_chisq_results        — 汇总 data.frame
#    Tables/Table_Trajectory_Chisq.xlsx / .tex   — SCI 三线表
###############################################################################

block_trajectory_chisq <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(dplyr)
    library(cli)
  })
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)

  cfg      <- ctx$config
  traj_cfg <- cfg$trajectory %||% cfg$trajectory_chisq %||% list()

  # ── 1. 读取配置 ────────────────────────────────────────────────────────────
  index_vars     <- traj_cfg$index_vars %||%
    stop("trajectory$index_vars 未配置。")
  outcome_vars   <- traj_cfg$outcome_vars %||%
    stop("trajectory$outcome_vars 未配置。")
  outcome_path   <- traj_cfg$outcome_data_path %||% NULL
  outcome_obj    <- traj_cfg$outcome_data_obj  %||% "imputed_data"
  p_threshold    <- traj_cfg$p_threshold       %||% 0.05
  id_col         <- traj_cfg$id_column %||% cfg$data$id_column %||% "subject_id"

  long_data_dir     <- traj_cfg$long_data_dir               %||% NULL
  long_filename_tpl <- traj_cfg$long_data_filename_template %||%
    "D01_long_{Index}_D_{D}.RData"
  long_data_obj_nm  <- traj_cfg$long_data_obj               %||% "long"

  # ── 2. 加载结局数据 ────────────────────────────────────────────────────────
  # 优先：ctx$data$imputed（由 block_imputation 写入）
  outcome_data <- ctx$data$imputed

  if (is.null(outcome_data) && !is.null(outcome_path)) {
    op_full <- if (grepl("^(/|[A-Za-z]:[/\\\\])", outcome_path)) {
      outcome_path
    } else {
      file.path(getwd(), outcome_path)
    }

    if (!file.exists(op_full)) {
      stop(paste0(
        "结局数据文件不存在: ", op_full,
        "\n  → 请先运行 block_imputation，或检查 trajectory$outcome_data_path 路径"
      ))
    }

    e_out <- new.env(parent = emptyenv())
    load(op_full, envir = e_out)

    if (!exists(outcome_obj, envir = e_out)) {
      stop(paste0(
        "RData 中找不到对象 '", outcome_obj,
        "'，请检查 trajectory$outcome_data_obj 配置\n",
        "  文件路径: ", op_full
      ))
    }
    outcome_data <- get(outcome_obj, envir = e_out)
    cli::cli_alert_info("从磁盘加载结局数据: {.file {op_full}}")
  }

  if (is.null(outcome_data)) {
    stop(paste0(
      "结局数据不可用：\n",
      "  ① ctx$data$imputed 为空（请先运行 block_imputation）\n",
      "  ② trajectory$outcome_data_path 未配置或文件不存在\n",
      "  请二选一处理后重新运行。"
    ))
  }

  # 检查结局变量是否存在，过滤不存在的
  missing_vars <- setdiff(outcome_vars, names(outcome_data))
  if (length(missing_vars) > 0) {
    cli::cli_alert_warning(
      "以下结局变量在数据中不存在，将跳过: {paste(missing_vars, collapse=', ')}"
    )
    outcome_vars <- intersect(outcome_vars, names(outcome_data))
  }
  if (length(outcome_vars) == 0) {
    stop(paste0(
      "所有配置的 outcome_vars 均不在结局数据中，请检查列名。\n",
      "  可用列（前20个）: ",
      paste(head(names(outcome_data), 20), collapse = ", ")
    ))
  }

  # 仅保留 id + outcome 列（减少内存）
  outcome_slim <- outcome_data[, unique(c(id_col, outcome_vars)), drop = FALSE]

  # ── 3. 辅助函数 ────────────────────────────────────────────────────────────
  .fmt_pval <- function(p) {
    if (is.na(p)) return("NA")
    if (p < 0.001) return("<0.001")
    formatC(p, digits = 3, format = "f")
  }

  # ── 4. 主循环：Index × D × outcome ───────────────────────────────────────
  result_rows <- list()
  n_total <- 0L
  n_done  <- 0L

  for (Index in index_vars) {
    class_for_test <- trajectory_resolve_class_ng_spec(
      ctx, Index, cfg, traj_cfg, field = "class_for_test", fallback = 2L
    )
    cli::cli_alert_info("trajectory_chisq [{Index}]: 使用 ng={paste(class_for_test, collapse=', ')}")
    n_total <- n_total + length(class_for_test) * length(outcome_vars)

    for (D in class_for_test) {
      key <- paste0(Index, "_D", D)

      # 加载轨迹数据（ctx 优先，磁盘兜底）
      long_data <- ctx$data$trajectory_long[[key]]

      if (is.null(long_data) && !is.null(long_data_dir)) {
        fname <- gsub("\\{Index\\}", Index,
                 gsub("\\{D\\}",     as.character(D), long_filename_tpl))
        fpath <- if (grepl("^(/|[A-Za-z]:[/\\\\])", long_data_dir)) {
          file.path(long_data_dir, fname)
        } else {
          file.path(getwd(), long_data_dir, fname)
        }
        if (file.exists(fpath)) {
          e <- new.env(parent = emptyenv())
          load(fpath, envir = e)
          long_data <- tryCatch(
            get(long_data_obj_nm, envir = e),
            error = function(e2) NULL
          )
          if (!is.null(long_data)) {
            cli::cli_alert_info("{key}: 从磁盘加载轨迹数据 {.file {fpath}}")
          }
        }
      }

      if (is.null(long_data)) {
        cli::cli_alert_warning("{key}: 轨迹数据不可用，跳过全部结局检验")
        next
      }

      if (!"Class" %in% names(long_data)) {
        cli::cli_alert_warning("{key}: 数据缺少 Class 列，跳过")
        next
      }

      # 每位受试者取第一个非 NA 的 Class（统一 ID 为 character 避免类型冲突）
      class_data <- long_data |>
        dplyr::mutate(!!id_col := as.character(.data[[id_col]])) |>
        dplyr::group_by(.data[[id_col]]) |>
        dplyr::summarize(
          Class = dplyr::first(Class[!is.na(Class)]),
          .groups = "drop"
        )

      outcome_slim[[id_col]] <- as.character(outcome_slim[[id_col]])

      data_merged <- dplyr::inner_join(
        class_data, outcome_slim, by = id_col
      )

      n_merged <- nrow(data_merged)
      if (n_merged == 0) {
        cli::cli_alert_warning(
          "{key}: 轨迹数据与结局数据合并后无共同 ID，跳过（请检查 id_column 配置）"
        )
        next
      }
      cli::cli_alert_info("{key}: 合并后样本 n = {n_merged}")

      # 对每个结局变量执行检验
      for (outcome in outcome_vars) {
        n_done <- n_done + 1L

        if (!outcome %in% names(data_merged)) {
          cli::cli_alert_warning("{key} × {outcome}: 结局列在合并数据中缺失，跳过")
          next
        }

        # 构建列联表
        tbl <- table(data_merged[["Class"]], data_merged[[outcome]])

        # 自动选择检验方式（期望频数 < 5 用 Fisher）
        use_fisher <- any(tbl < 5)
        test_res   <- tryCatch({
          if (use_fisher) {
            fisher.test(tbl, simulate.p.value = TRUE, B = 2000)
          } else {
            chisq.test(tbl)
          }
        }, error = function(e) {
          cli::cli_alert_warning(
            "{key} × {outcome} 检验失败: {e$message}"
          )
          NULL
        })

        if (is.null(test_res)) next

        p_val    <- test_res$p.value
        stat_val <- if (use_fisher) NA_real_ else as.numeric(test_res$statistic)
        df_val   <- if (use_fisher) NA_integer_ else as.integer(test_res$parameter)

        result_rows[[length(result_rows) + 1L]] <- data.frame(
          Index       = Index,
          D           = D,
          n_subjects  = n_merged,
          Outcome     = outcome,
          Test        = if (use_fisher) "Fisher" else "Chi-square",
          Statistic   = if (is.na(stat_val)) NA_real_ else round(stat_val, 3),
          DF          = df_val,
          P_value     = p_val,
          P_value_fmt = .fmt_pval(p_val),
          Significant = ifelse(p_val < p_threshold, "Yes", "No"),
          stringsAsFactors = FALSE
        )

        cli::cli_alert_success(
          "{key} x {outcome}: {if(use_fisher) 'Fisher' else 'chi-sq'} p = {(.fmt_pval(p_val))} [{if(p_val < p_threshold) 'sig' else 'ns'}]"
        )
      }
    }
  }

  # ── 5. 汇总并输出总表 ─────────────────────────────────────────────────────
  if (length(result_rows) == 0) {
    if (isFALSE(traj_cfg$pause_on_no_results %||% TRUE)) {
      cli::cli_alert_warning("卡方检验无有效结果（pause_on_no_results=FALSE，继续）")
      ctx$results$trajectory_chisq_results <- data.frame(note = "no valid tests")
      return(ctx)
    }
    ctx$results$pause_point <- list(
      block      = "block_trajectory_chisq",
      reason     = "所有 Index × D × Outcome 均未产生有效检验结果（数据不足或加载失败）",
      suggestion = paste0(
        "请检查：① trajectory$index_vars / class_for_test / outcome_vars 配置；",
        "② 轨迹数据与结局数据 ID 是否能对上（id_column 配置）；",
        "③ 上方日志中的警告信息"
      )
    )
    stop(
      "PAUSE_FOR_USER_DECISION: 卡方检验无有效结果，",
      "请查看 ctx$results$pause_point 并指示下一步操作。"
    )
  }

  chisq_table <- dplyr::bind_rows(result_rows)
  chisq_table <- chisq_table[order(chisq_table$Index, chisq_table$D, chisq_table$Outcome), ]
  ctx$results$trajectory_chisq_results <- chisq_table

  # 输出展示版（不含原始数值型 P_value 列）
  display_table <- chisq_table[, c(
    "Index", "D", "n_subjects", "Outcome",
    "Test", "Statistic", "DF", "P_value_fmt", "Significant"
  ), drop = FALSE]
  names(display_table)[names(display_table) == "P_value_fmt"] <- "P value"

  fp_chisq <- file.path(
    ctx$output_dir_tables, "Table_Trajectory_Chisq.xlsx"
  )
  export_sci_table(
    display_table,
    filepath = fp_chisq,
    title    = paste0(
      "Table. Chi-square / Fisher's exact test: ",
      "Trajectory class vs clinical outcomes"
    ),
    sheet    = "Chisq",
    table_footnotes = paste0(
      "Abbreviations: D = number of trajectory classes; ",
      "n_subjects = sample size after merging trajectory and outcome data. ",
      "Fisher's exact test (simulate.p.value=TRUE, B=2000) was applied ",
      "when any expected cell count < 5. ",
      "P\u00a0value significance threshold: ", p_threshold, "."
    )
  )
  cli::cli_alert_success(
    "Table_Trajectory_Chisq 已入队（{nrow(display_table)} 行）: ",
    "{.file {basename(fp_chisq)}}"
  )

  # ── 6. 阴性结果暂停 ────────────────────────────────────────────────────────
  all_ns <- all(chisq_table$P_value >= p_threshold, na.rm = TRUE)
  if (all_ns) {
    ctx$results$pause_point <- list(
      block      = "block_trajectory_chisq",
      reason     = paste0(
        "所有 ", nrow(chisq_table), " 个检验均无显著性",
        "（p >= ", p_threshold, "），无阳性结果"
      ),
      suggestion = paste0(
        "建议：① 检查轨迹分类是否合理（尝试不同 class_for_test）；",
        "② 调整 trajectory$p_threshold；",
        "③ 确认结局变量编码（是否为 0/1 或因子）"
      ),
      data_snapshot = head(display_table, 5)
    )
    stop(
      "PAUSE_FOR_USER_DECISION: ",
      "轨迹-结局卡方检验全为阴性，请查看 ctx$results$pause_point 并指示下一步。"
    )
  }

  n_sig <- sum(chisq_table$P_value < p_threshold, na.rm = TRUE)
  cli::cli_alert_success(
    "block_trajectory_chisq 完成：{n_done} 个检验，{n_sig} 个显著 (p < {p_threshold})。"
  )
  return(ctx)
}

register_block(
  "trajectory_chisq", block_trajectory_chisq,
  "轨迹组 × 结局卡方检验（自动切换 Fisher），汇总总表 xlsx+tex，阴性自动暂停"
)
