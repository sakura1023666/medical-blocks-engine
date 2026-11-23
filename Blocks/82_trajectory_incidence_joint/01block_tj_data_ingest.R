###############################################################################
# tj_data_ingest — 双指标联合轨迹发病：队列入库、各波暴露重算、结局/随访时间、纳排图数据
#
# 前置：config$data$rawdata_path / rawdata_obj 或 ctx$data$raw；config$joint_trajectory
#
# joint_trajectory = list(
#   id_column         = "id",
#   waves             = c(2, 4, 6),            # 轨迹测量波
#   index_pairs       = list(                  # 体系（联合轨迹对）
#     BMI_TyG   = c("TyG", "BMI"),
#     WHtR_TyG  = c("TyG", "WHtR")
#   ),
#   wave_suffix       = "_w",
#   raw_wave_pattern  = NULL,                  # 若成分列已是 <comp>_w<k> 可留 NULL 跳过重算
#   recompute_indices = TRUE,                  # 用 00_index 公式按波重算指标
#   age_filter        = "age >= 50",           # 可选纳排表达式
#   prevalent_exclude = list(cvd0 = c("angina","mi","hf","arry","stroke")), # 基线现患剔除
#   outcome = list(                            # 新发结局（组件 first-report）
#     primary = list(name = "cvd",
#                    components = c("heart_angina","heart_MI","heart_CHF","heart_arrhythmia","stroke")),
#     secondaries = list(
#       heart  = c("heart_angina","heart_MI","heart_CHF","heart_arrhythmia"),
#       stroke = "stroke"),
#     comp_event_cols = NULL,                  # 已是 df 列：<comp> first-wave（值=波号或NA）
#     visit_time_cols = c("tvisit_w3", ...),   # 各随访波访谈月（相对基线，0=基线）
#     first_obs_wave  = 2,
#     midpoint = TRUE                           # 区间删失取中点
#   }
# )
#
# register_block: "tj_data_ingest"
# 写: ctx$data$cleaned(master 宽表 + 各波指标列 + class 占位), ctx$results$tj_cohort
#     ctx$results$tj_outcome_<name>(event/time 向量), attrition 行
# 落盘: data/clean/tj_master.csv, reports/tj_cohort_build_log.md
###############################################################################

block_tj_data_ingest <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_trajectory_joint.R"), local = FALSE)
  .al <- file.path(root, "R/attrition_log.R")
  if (file.exists(.al)) source(.al, local = FALSE)   # attrition_record / *_component_missing_label
  bl <- ctx$config$joint_trajectory %||%
    stop("tj_data_ingest: 缺 config$joint_trajectory", call. = FALSE)
  id_col <- bl$id_column %||% ctx$config$data$id_column %||% "id"

  df <- ctx$data$raw %||% ctx$data$cleaned
  if (is.null(df)) {
    rp <- ctx$config$data$rawdata_path
    rob <- ctx$config$data$rawdata_obj
    if (!is.null(rp) && file.exists(rp) && !is.null(rob)) {
      e <- new.env(parent = emptyenv()); load(rp, envir = e)
      df <- as.data.frame(e[[rob]])
    } else stop("tj_data_ingest: 无原始数据", call. = FALSE)
  }
  df <- as.data.frame(df)
  if (!id_col %in% names(df)) stop("tj_data_ingest: 缺 ID 列 ", id_col, call. = FALSE)
  df[[id_col]] <- as.character(df[[id_col]])

  log_lines <- c(sprintf("# 联合轨迹发病 队列构建日志 %s", format(Sys.time())), "")
  say <- function(...) { l <- paste0(...); cat(l, "\n", sep = ""); log_lines[[length(log_lines) + 1L]] <<- l }

  n0 <- nrow(df)
  say(sprintf("Step0 入库池: %d", n0))

  # ── 年龄门控 ──
  if (!is.null(bl$age_filter) && nzchar(as.character(bl$age_filter)[1L])) {
    keep <- with(df, eval(parse(text = as.character(bl$age_filter)[1L])))
    keep[is.na(keep)] <- FALSE
    n_age_ex <- sum(!keep)
    df <- df[keep, , drop = FALSE]
    say(sprintf("Step1 年龄筛 '%s' 排除: -%d => %d", bl$age_filter, n_age_ex, nrow(df)))
    ctx <- attrition_record(ctx, "tj_age", paste0("Age filter (", bl$age_filter, ")"),
                     nrow(df), kind = "exclude",
                     meta = list(excluded = n_age_ex))
  }

  # ── 各波暴露：可选按 00_index 公式重算 ──
  waves <- as.integer(bl$waves)
  sfx <- bl$wave_suffix %||% "_w"
  all_idx <- unique(unlist(bl$index_pairs))
  if (isTRUE(bl$recompute_indices) && length(all_idx)) {
    for (ix in all_idx) {
      dfn <- tj_calc_index_waves(df, ix, waves, wave_suffix = sfx, root = root)
      if (!is.null(dfn)) df <- dfn
    }
  }

  # 指标成分缺失分项（Attrition §8 诚实出框）
  idx_cols <- lapply(bl$index_pairs, function(pr) {
    vapply(pr, function(ix) paste0(ix, sfx, waves[1]), character(1))
  })
  first_idx_cols <- unique(unlist(idx_cols))
  miss_log <- c()
  for (cn in first_idx_cols) {
    if (cn %in% names(df)) {
      miss_log[[cn]] <- sum(is.na(as.numeric(df[[cn]])))
      say(sprintf("  成分 %s 基线缺失 n=%d", cn, miss_log[[cn]]))
    }
  }
  # 任一轨迹指标基线不可算 → 剔除（指标成分缺失）
  core_cols <- unique(unlist(lapply(bl$index_pairs, function(pr)
    paste0(pr, sfx, waves[1]))))
  keep2 <- stats::complete.cases(as.data.frame(lapply(core_cols, function(cn)
    as.numeric(df[[cn]]))))
  n_core_ex <- sum(!keep2)
  df <- df[keep2, , drop = FALSE]
  say(sprintf("Step2 指标成分缺失排除: -%d => %d", n_core_ex, nrow(df)))
  comp_label <- attrition_index_component_missing_label(df, paste(core_cols, collapse = "/"),
                                                        counts = as.integer(miss_log))
  ctx <- attrition_record(ctx, "tj_index_missing", comp_label, nrow(df), kind = "exclude",
                   meta = list(excluded = n_core_ex))

  # ── 基线现患剔除 ──
  if (!is.null(bl$prevalent_exclude) && length(bl$prevalent_exclude) >= 1L &&
      !is.null(names(bl$prevalent_exclude)[1L])) {
    pe <- bl$prevalent_exclude
    pv <- names(pe)[1]; codes <- pe[[1]]
    keep3 <- rep(TRUE, nrow(df))
    for (col in codes) {
      if (col %in% names(df)) {
        v <- as.numeric(df[[col]]); v[is.na(v)] <- 0
        keep3 <- keep3 & !(v %in% c(1, 2))   # ELSA 码 1/2=ever 诊断
      }
    }
    n_prev <- sum(!keep3)
    df <- df[keep3, , drop = FALSE]
    say(sprintf("Step3 基线现患(%s)排除: -%d => %d [FINAL]", paste(codes, collapse = "+"),
                n_prev, nrow(df)))
    ctx <- attrition_record(ctx, "tj_prevalent", paste0("Prevalent ", pv, " at baseline"),
                     nrow(df), kind = "exclude", meta = list(excluded = n_prev))
  }

  ctx <- attrition_record(ctx, "tj_included", "Included analytic cohort", nrow(df), kind = "include")

  # ── 结局 event/time ──
  oc <- bl$outcome %||% list()
  # 与 bespoke 一致：事件与随访时间由独立结局步（new-report 波次 + 中点随访月）
  # 预先写入 master 列 <name>_event / <name>_time_m；本块只负责挂到 ctx。
  for (o in c(list(oc$primary), oc$secondaries %||% list())) {
    nm <- o$name
    ec <- o$event_col %||% paste0(nm, "_event"); tc <- o$time_col %||% paste0(nm, "_time_m")
    if (ec %in% names(df) && tc %in% names(df)) {
      ctx$results[[paste0("tj_outcome_", nm)]] <- list(
        event = as.integer(df[[ec]]), time = as.numeric(df[[tc]]))
      say(sprintf("结局 %s: events=%d (%.1f%%), time %s", nm, sum(df[[ec]], na.rm = TRUE),
                  100 * mean(df[[ec]], na.rm = TRUE),
                  paste(round(range(as.numeric(df[[tc]]), na.rm = TRUE), 1), collapse = " .. ")))
    } else {
      say(sprintf("结局 %s: 缺列 %s / %s（跳过；请先在结局步生成）", nm, ec, tc))
    }
  }

  df$.tj_row_id <- seq_len(nrow(df))
  ctx$data$cleaned <- df
  ctx$data$raw <- df
  ctx$results$tj_cohort <- list(
    n = nrow(df), id_column = id_col, waves = waves,
    index_pairs = bl$index_pairs, outcomes = names(ctx$results)[grepl("^tj_outcome_", names(ctx$results))])

  dir.create(file.path(ctx$config$project$output_dir %||% "Output", "data", "clean"),
             showWarnings = FALSE, recursive = TRUE)
  utils::write.csv(df, file.path(ctx$config$project$output_dir %||% "Output", "data", "clean", "tj_master.csv"),
                   row.names = FALSE, na = "")
  dir.create(file.path(ctx$config$project$output_dir %||% "Output", "reports"),
             showWarnings = FALSE, recursive = TRUE)
  writeLines(log_lines, file.path(ctx$config$project$output_dir %||% "Output", "reports", "tj_cohort_build_log.md"))

  cli::cli_alert_success("tj_data_ingest: n={nrow(df)}, 结局={paste(ctx$results$tj_cohort$outcomes, collapse=', ')}")
  ctx
}

register_block("tj_data_ingest", block_tj_data_ingest, "联合轨迹发病 队列/暴露/结局入库+纳排")
