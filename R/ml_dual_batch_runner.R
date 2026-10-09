###############################################################################
#  ml_dual_batch_runner.R — ML 双库批量多指标编排（复用 incidence batch 基础设施）
#
#  index_mode:
#    single_loop    — 两库共同可用的单指标逐个并行 worker
#    multi_combined — 候选池按单因素 P 值取 top N，合并为一次 ML 运行
#    combo_loop     — 预先锁定的双复合指标组合逐对并行 worker（A+B）
###############################################################################

# 引擎根：优先 MEDICAL_BLOCKS_ROOT（worker cwd 常为课题目录，勿用 getwd()）
.ml_engine_root <- local({
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  normalizePath(er, winslash = "/", mustWork = FALSE)
})
source(file.path(.ml_engine_root, "R", "incidence_dual_batch_runner.R"), local = FALSE)
source(file.path(.ml_engine_root, "R", "ml_dual_pub_table_curate.R"), local = FALSE)
source(file.path(.ml_engine_root, "R", "rscript_ml.R"), local = FALSE)

.ml_batch_bind_config <- function(config) {
  mb <- config$ml_batch %||% list()
  if (length(mb)) {
    config$incidence_batch <- utils::modifyList(
      config$incidence_batch %||% list(),
      mb
    )
  }
  config
}

#' 多指标 job 标签（multi_combined / phase2 历史口径，保持 '_' 连接，勿改）。
ml_batch_index_label <- function(indices) {
  paste(as.character(indices), collapse = "_")
}

#' combo_loop 专用标签：复合指标名本身含 '_'（如 De_Ritis / BUN_Cr），
#' 用 '_' 连接组合会与单指标名歧义，故组合标签用 '+' 连接。
ml_batch_combo_label <- function(indices) {
  paste(as.character(indices), collapse = "+")
}

ml_batch_parse_index_arg <- function(ix_arg) {
  parts <- trimws(strsplit(as.character(ix_arg), ",", fixed = TRUE)[[1L]])
  parts <- parts[nzchar(parts)]
  if (!length(parts)) stop("指标名为空", call. = FALSE)
  parts
}

ml_batch_patch_config_for_indices <- function(config, indices) {
  indices <- unique(as.character(indices)[nzchar(as.character(indices))])
  config <- .ml_batch_bind_config(config)
  if (length(indices) == 1L) {
    config <- incidence_batch_patch_config_for_index(config, indices[[1L]])
  } else {
    config$incidence$index_var <- indices[[1L]]
    config$logistic$index_var <- indices[[1L]]
    config$nhanes$cutoff_index_var <- indices
  }
  # 预后 combo_loop 必须把当前组合写回所有暴露解析入口。否则 study config
  # 中的首个指标会残留为 survival/analysis_exclusion 当前暴露，后者继而把
  # 本 job 的两个指标当作“其他复合指标”硬删。
  config$survival$index_var <- indices[[1L]]
  config$analysis_exclusion <- modifyList(
    config$analysis_exclusion %||% list(),
    list(
      index_var = indices[[1L]],
      current_index_vars = indices,
      protect_vars = unique(c(
        as.character((config$analysis_exclusion %||% list())$protect_vars %||% character(0)),
        indices
      ))
    )
  )
  config$prediction$index_vars <- indices
  config$feature_selection$composite_features <- indices
  config$index <- modifyList(
    config$index %||% list(enable = TRUE),
    list(enable = TRUE, only = indices)
  )
  config$force_continuous_vars <- unique(c(
    config$force_continuous_vars %||% character(0), indices
  ))
  config
}

ml_batch_patch_config_for_index <- function(config, ix) {
  ml_batch_patch_config_for_indices(config, ml_batch_parse_index_arg(ix))
}

#' 在 NHANES 共享 mapped 数据上按单因素 P 值对候选指标排序，取 top N
ml_batch_rank_indices_top_n <- function(config, candidates, top_n = 3L, root = getwd()) {
  candidates <- unique(as.character(candidates)[nzchar(as.character(candidates))])
  top_n <- max(1L, as.integer(top_n)[1L])
  if (length(candidates) <= top_n) return(candidates)

  shared_dir <- incidence_batch_shared_ck_dir(config, "nhanes")
  ck <- file.path(shared_dir, "index.rds")
  if (!file.exists(ck)) return(candidates[seq_len(min(length(candidates), top_n))])

  obj <- tryCatch(readRDS(ck), error = function(e) NULL)
  dat <- incidence_batch_ctx_data(obj$ctx)
  if (is.null(dat) || !is.data.frame(dat)) {
    return(candidates[seq_len(min(length(candidates), top_n))])
  }

  outcome <- config$data$outcome_column %||% "Disease"
  if (!outcome %in% names(dat)) return(candidates[seq_len(min(length(candidates), top_n))])

  y <- dat[[outcome]]
  pvals <- vapply(candidates, function(v) {
    if (!v %in% names(dat)) return(Inf)
    x <- dat[[v]]
    ok <- is.finite(x) & !is.na(y)
    if (sum(ok) < 30L) return(Inf)
    tryCatch({
      fit <- stats::glm(y[ok] ~ x[ok], family = stats::binomial())
      sm <- summary(fit)$coefficients
      if (nrow(sm) < 2L) Inf else sm[2L, 4L]
    }, error = function(e) Inf)
  }, numeric(1))

  ord <- order(pvals, candidates)
  ranked <- candidates[ord]
  ranked <- ranked[is.finite(pvals[ord])]
  if (!length(ranked)) ranked <- candidates
  head(ranked, top_n)
}

ml_batch_resolve_indices_from_label <- function(label, config) {
  label <- as.character(label)[1L]
  if (grepl(",", label, fixed = TRUE)) return(ml_batch_parse_index_arg(label))

  bc <- config$ml_batch %||% config$incidence_batch %||% list()
  pool <- as.character(bc$index_vars %||% character(0))

  if (length(pool) > 1L) {
    hit <- ml_batch_index_label(pool)
    if (identical(label, hit)) return(pool)
  }

  known <- c(
    get0(".composite_index_vars", inherits = TRUE) %||% character(0),
    get0(".composite_index_vars_dual_safe", inherits = TRUE) %||% character(0),
    pool
  )
  if (length(known) && label %in% known) return(label)

  ## combo_loop 标签：'+' 连接（复合指标名含 '_'，故用 '+' 消歧）。
  if (grepl("+", label, fixed = TRUE)) {
    parts <- trimws(strsplit(label, "+", fixed = TRUE)[[1L]])
    parts <- parts[nzchar(parts)]
    if (length(parts) > 1L && all(parts %in% known)) return(parts)
  }

  mode <- tolower(trimws(as.character(bc$index_mode %||% "")))
  if (identical(mode, "multi_combined") && grepl("_", label, fixed = TRUE)) {
    parts <- strsplit(label, "_", fixed = TRUE)[[1L]]
    if (length(parts) > 1L && all(parts %in% pool)) return(parts)
  }

  if (grepl("_", label, fixed = TRUE)) {
    parts <- strsplit(label, "_", fixed = TRUE)[[1L]]
    if (length(parts) > 1L && all(parts %in% known)) return(parts)
  }

  label
}

ml_batch_apply_filter_for_indices <- function(ck_path, indices, p_trim = 0.01) {
  indices <- unique(as.character(indices))
  stats <- list()
  for (ix in indices) {
    st <- incidence_batch_apply_filter_and_trim(ck_path, ix, p_trim)
    stats[[ix]] <- st
  }
  invisible(stats)
}

#' 解析批量指标计划：single_loop / multi_combined / single_then_multi / combo_loop
ml_batch_resolve_index_plan <- function(config, candidate_vars, root = getwd()) {
  bc <- config$ml_batch %||% config$incidence_batch %||% list()
  mode <- tolower(trimws(as.character(bc$index_mode %||% "single_loop")))
  top_n <- bc$multi_top_n %||% 3L

  if (identical(mode, "single_then_multi")) {
    list(
      mode = "single_then_multi",
      jobs = as.list(candidate_vars),
      labels = candidate_vars
    )
  } else if (identical(mode, "combo_loop")) {
    ## 双复合组合：每 job 一对 (A,B)；仅保留两端点都在共享层已算池中的组合。
    combos <- bc$index_combos %||% list()
    if (!is.list(combos) || !length(combos)) {
      stop("index_mode=combo_loop 需 config$ml_batch$index_combos = list(c('A','B'), ...)",
           call. = FALSE)
    }
    cand <- unique(as.character(candidate_vars))
    jobs <- list(); labels <- character(0); dropped <- character(0)
    for (cp in combos) {
      pair <- unique(as.character(cp)[nzchar(as.character(cp))])
      if (length(pair) != 2L) {
        dropped <- c(dropped, paste0(paste(cp, collapse = "+"), "(非二元组)"))
        next
      }
      if (!all(pair %in% cand)) {
        dropped <- c(dropped, ml_batch_combo_label(pair))
        next
      }
      jobs[[length(jobs) + 1L]] <- pair
      labels <- c(labels, ml_batch_combo_label(pair))
    }
    if (length(dropped)) {
      cli::cli_alert_warning(
        "combo_loop 剔除 {length(dropped)} 个组合（端点未在共享层可算池 / 非二元组）: {paste(dropped, collapse=', ')}"
      )
    }
    if (!length(jobs)) stop("combo_loop：无可运行的双复合组合（全部端点不在共享层可算池）",
                             call. = FALSE)
    dup <- labels[duplicated(labels)]
    if (length(dup)) {
      keep <- !duplicated(labels)
      jobs <- jobs[keep]; labels <- labels[keep]
      cli::cli_alert_warning("combo_loop 去重组合: {paste(unique(dup), collapse=', ')}")
    }
    list(mode = "combo_loop", jobs = jobs, labels = labels)
  } else if (identical(mode, "multi_combined")) {
    pool <- if (!is.null(bc$index_vars) && length(bc$index_vars)) {
      as.character(bc$index_vars)
    } else {
      candidate_vars
    }
    pool <- intersect(pool, candidate_vars)
    if (!length(pool)) pool <- candidate_vars
    selected <- ml_batch_rank_indices_top_n(config, pool, top_n = top_n, root = root)
    list(
      mode = "multi_combined",
      jobs = list(selected),
      labels = ml_batch_index_label(selected)
    )
  } else {
    list(
      mode = "single_loop",
      jobs = as.list(candidate_vars),
      labels = candidate_vars
    )
  }
}

#' 安全解析 status 中的 AUC（兼容 {}、null、list、标量）
.ml_batch_coerce_auc <- function(x) {
  if (is.null(x) || length(x) == 0) return(NA_real_)
  if (is.list(x) && !is.numeric(x)) {
    if (!length(x)) return(NA_real_)
    x <- x[[1L]]
  }
  suppressWarnings(as.numeric(x)[1L])
}

#' 从单指标 worker 状态按验证集 AUC 选 top N（NHANES 优先，两库均值次之）
ml_batch_pick_top_indices_from_status <- function(statuses, top_n = 3L,
                                                  max_auc = 0.99) {
  top_n <- max(1L, as.integer(top_n)[1L])
  if (is.null(statuses) || !nrow(statuses)) return(character(0))
  ok <- statuses[tolower(as.character(statuses$status)) == "success", , drop = FALSE]
  if (!nrow(ok)) return(character(0))

  nh_col <- if ("nhanes_auc" %in% names(ok)) ok$nhanes_auc else rep(NA_real_, nrow(ok))
  mi_col <- if ("mimic_auc" %in% names(ok)) ok$mimic_auc else rep(NA_real_, nrow(ok))

  score <- vapply(seq_len(nrow(ok)), function(i) {
    nh <- .ml_batch_coerce_auc(nh_col[[i]])
    mi <- .ml_batch_coerce_auc(mi_col[[i]])
    if (is.finite(max_auc)) {
      if (is.finite(nh) && nh > max_auc) nh <- NA_real_
      if (is.finite(mi) && mi > max_auc) mi <- NA_real_
    }
    if (isTRUE(is.finite(nh) && is.finite(mi))) return(mean(c(nh, mi)))
    if (isTRUE(is.finite(nh))) return(nh)
    if (isTRUE(is.finite(mi))) return(mi)
    NA_real_
  }, numeric(1))

  ok$._score <- score
  ok <- ok[is.finite(ok$._score), , drop = FALSE]
  if (!nrow(ok)) return(character(0))
  ok <- ok[order(-ok$._score, ok$index), , drop = FALSE]
  head(as.character(ok$index), top_n)
}

ml_batch_clean_index_job <- function(output_base, ix_label, ck_base = NULL, index_subdir = "by_index") {
  for (sub in c(
    file.path(output_base, index_subdir, ix_label),
    file.path(output_base, index_subdir, incidence_batch_output_dir_name(ix_label, "success")),
    file.path(output_base, index_subdir, incidence_batch_output_dir_name(ix_label, "failed"))
  )) {
    if (dir.exists(sub)) unlink(sub, recursive = TRUE, force = TRUE)
  }
  if (!is.null(ck_base) && nzchar(ck_base)) {
    ck <- file.path(ck_base, ix_label)
    if (dir.exists(ck)) unlink(ck, recursive = TRUE, force = TRUE)
  }
  invisible(TRUE)
}

#' 复制 shared index.rds 后剔除非本任务复合指标列，供 from=index 续跑
ml_batch_seed_index_checkpoint <- function(alias_dst, indices, other_ix, config_ix) {
  if (!file.exists(alias_dst)) return(invisible(FALSE))
  obj <- tryCatch(readRDS(alias_dst), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) return(invisible(FALSE))
  for (slot in c("mapped", "imputed", "cleaned", "raw")) {
    df <- obj$ctx$data[[slot]]
    if (!is.null(df) && is.data.frame(df)) {
      drop <- intersect(other_ix, names(df))
      if (length(drop)) df <- df[, setdiff(names(df), drop), drop = FALSE]
      obj$ctx$data[[slot]] <- pipeline_ensure_outcome_group_column(df, config_ix)
    }
  }
  obj$ctx$results$computed_index_names <- indices
  if (!is.null(obj$ctx$config)) {
    obj$ctx$config$prediction$index_vars <- indices
    obj$ctx$config$feature_selection$composite_features <- indices
    obj$ctx$config$incidence$index_var <- indices[[1L]]
    obj$ctx$config$index <- modifyList(
      obj$ctx$config$index %||% list(),
      list(only = indices)
    )
  }
  obj$config <- config_ix
  saveRDS(obj, alias_dst)
  invisible(TRUE)
}

#' 仅跑 Phase 2：从 Phase 1 成功指标按 AUC 取 top N，合并跑一次完整 ML
run_ml_dual_batch_phase2_only <- function(root,
                                          config,
                                          run_opts = list(),
                                          config_path = NULL) {
  root   <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- .ml_batch_bind_config(config)
  bc     <- config$ml_batch %||% config$incidence_batch %||% list()
  top_n  <- as.integer(bc$multi_top_n %||% 3L)[1L]
  output_base <- bc$output_base %||% config$project$output_dir
  ck_base <- bc$index_ck_base %||% file.path(output_base, "checkpoints", "by_index")

  phase1_labels <- bc$phase1_labels %||% NULL
  if (is.null(phase1_labels) || !length(phase1_labels)) {
    candidate_vars <- incidence_batch_resolve_index_vars(config)
    phase1_labels <- tryCatch(
      incidence_batch_resolve_from_shared_ck(config, candidate_vars, bc$db_mode %||% "both"),
      error = function(e) candidate_vars
    )
  }

  statuses1 <- incidence_batch_read_all_status(output_base, phase1_labels)
  incidence_batch_print_summary(statuses1)
  top_ix <- ml_batch_pick_top_indices_from_status(statuses1, top_n = top_n)
  if (!length(top_ix)) stop("Phase 1 无可用 success 指标（含 AUC）可排名", call. = FALSE)

  combined_label <- ml_batch_index_label(top_ix)
  cli::cli_h1("Phase 2 — multi_combined：{combined_label}")
  cli::cli_alert_info("Top {length(top_ix)}: {paste(top_ix, collapse=', ')}")

  ml_batch_clean_index_job(output_base, combined_label, ck_base = ck_base)
  log_f <- file.path(output_base, "logs", paste0(combined_label, ".log"))
  if (file.exists(log_f)) unlink(log_f, force = TRUE)

  bc2 <- utils::modifyList(bc, list(
    index_mode = "multi_combined",
    index_vars = top_ix
  ))
  config$ml_batch <- bc2
  config$incidence_batch <- bc2

  run_opts$skip_existing <- FALSE
  ml_batch_dispatch_index_workers(
    root, config, combined_label, run_opts, config_path
  )

  st <- incidence_batch_read_all_status(output_base, combined_label)
  incidence_batch_print_summary(st)
  invisible(list(top_indices = top_ix, label = combined_label, status = st))
}

ml_batch_dispatch_index_workers <- function(root, config, dispatch_labels, run_opts, config_path) {
  bc <- config$ml_batch %||% config$incidence_batch %||% list()
  workers_raw <- run_opts$workers %||% bc$parallel_workers
  auto_workers <- is.null(workers_raw) ||
    identical(tolower(trimws(as.character(workers_raw))), "auto")
  workers <- if (!auto_workers) max(1L, as.integer(workers_raw)) else NA_integer_
  db_mode <- run_opts$db_mode %||% bc$db_mode %||% "both"
  skip_exist <- isTRUE(run_opts$skip_existing %||% bc$skip_existing %||% TRUE)
  p_trim <- as.numeric(run_opts$p_trim %||% bc$trim_quantile %||% 0.01)
  only_index <- run_opts$only_index %||% NULL

  if (!is.null(only_index) && length(only_index)) {
    dispatch_labels <- dispatch_labels[dispatch_labels %in% only_index]
  }
  if (!length(dispatch_labels)) stop("无可用指标可跑", call. = FALSE)

  if (auto_workers) {
    workers <- incidence_batch_auto_workers(
      length(dispatch_labels),
      ram_per_worker  = bc$ram_per_worker_gb %||% 2.5,
      cpu_headroom    = bc$cpu_headroom %||% 2L,
      ram_headroom_gb = bc$ram_headroom_gb %||% 4.0,
      max_workers     = bc$max_workers %||% NULL
    )
  }

  win_rscript <- if (identical(Sys.getenv("MEDICAL_BLOCKS_SKIP_WIN_R", unset = ""), "1")) {
    NULL
  } else {
    tryCatch(ml_rscript_bin(), error = function(e) {
      cli::cli_alert_warning("Windows Rscript 未找到，回退当前 R: {conditionMessage(e)}")
      NULL
    })
  }

  incidence_batch_dispatch_workers(
    root = root,
    config = config,
    index_vars = dispatch_labels,
    workers = workers,
    db_mode = db_mode,
    only = only_index,
    skip_existing = skip_exist,
    p_trim = p_trim,
    config_path = config_path,
    worker_script = "run/ml/run_ml_dual_batch_worker.R",
    rscript_bin = win_rscript
  )
  invisible(dispatch_labels)
}

ml_batch_feishu_push_result <- function(config, fields) {
  if (!isTRUE((config$feishu %||% list())$enable %||% FALSE)) return(invisible(NULL))
  if (!exists("incidence_batch_feishu_push_result", mode = "function")) return(invisible(NULL))
  tryCatch(incidence_batch_feishu_push_result(config, fields), error = function(e) NULL)
  invisible(NULL)
}

run_ml_dual_batch <- function(root,
                              config,
                              pipeline_nhanes_batch,
                              pipeline_mimic_ml_batch,
                              pipeline_shared_nhanes,
                              pipeline_shared_regular,
                              run_opts = list(),
                              config_path = NULL) {
  root   <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- .ml_batch_bind_config(config)
  bc     <- config$ml_batch %||% config$incidence_batch %||% list()

  shared_only    <- isTRUE(run_opts$shared_only)
  only_index     <- run_opts$only_index %||% NULL
  workers_raw    <- run_opts$workers %||% bc$parallel_workers
  auto_workers   <- is.null(workers_raw) ||
    identical(tolower(trimws(as.character(workers_raw))), "auto")
  workers        <- if (!auto_workers) max(1L, as.integer(workers_raw)) else NA_integer_
  db_mode        <- run_opts$db_mode %||% bc$db_mode %||% "both"
  skip_exist     <- isTRUE(run_opts$skip_existing %||% bc$skip_existing %||% TRUE)
  p_trim         <- as.numeric(run_opts$p_trim %||% bc$trim_quantile %||% 0.01)

  candidate_vars <- incidence_batch_resolve_index_vars(config)
  cli::cli_h1("ML Dual Batch — 候选 {length(candidate_vars)} 个指标")
  cli::cli_alert_info("db_mode={db_mode}, workers={workers_raw %||% 'auto'}")

  db_seq <- switch(db_mode, nhanes = "nhanes", mimic = "mimic", c("nhanes", "mimic"))

  if (isTRUE(config$dual_db$enable)) {
    config <- tryCatch(
      incidence_batch_ensure_gate_a(config, root, force = !skip_exist)$config,
      error = function(e) {
        cli::cli_alert_warning("Gate A 失败: {e$message}")
        config
      }
    )
  }

  for (db in db_seq) {
    shared_read  <- incidence_batch_shared_ck_dir(config, db)
    shared_write <- incidence_batch_shared_ck_canonical_dir(config, db)
    pl_shared    <- if (dual_db_is_weighted(config, db)) pipeline_shared_nhanes else pipeline_shared_regular
    alias_path   <- file.path(shared_read, "index.rds")
    if (file.exists(alias_path) && isTRUE(skip_exist)) {
      cli::cli_alert_info("共享层 [{dual_db_slot_path_name(config, db)}] 已存在，跳过")
    } else {
      cli::cli_h2("运行共享层 [{dual_db_slot_path_name(config, db)}]")
      incidence_batch_run_shared_layer(root, config, db, pl_shared, shared_write)
    }
  }

  # 选指标 OR/HR 对比表（信息用，不自动改 index_vars）
  tryCatch(
    ml_batch_write_index_screening_or_hr(root, config, candidate_vars),
    error = function(e) cli::cli_alert_warning("选指标表失败: {conditionMessage(e)}")
  )

  if (shared_only) {
    avail <- tryCatch(
      incidence_batch_resolve_from_shared_ck(config, candidate_vars, db_mode),
      error = function(e) { cli::cli_alert_warning(e$message); candidate_vars }
    )
    cli::cli_alert_success("--shared-only 完成，可用指标: {length(avail)} 个")
    return(invisible(avail))
  }

  index_vars <- tryCatch(
    incidence_batch_resolve_from_shared_ck(config, candidate_vars, db_mode),
    error = function(e) candidate_vars
  )
  .batch_mode0 <- tolower(trimws(as.character(bc$index_mode %||% "single_loop")))
  ## combo_loop：候选池须保持「单指标名」供组合端点校验；--only-index 留到计划后再筛标签
  if (!is.null(only_index) && length(only_index) && !identical(.batch_mode0, "combo_loop")) {
    only_index <- as.character(only_index)
    hit <- intersect(only_index, index_vars)
    index_vars <- if (length(hit)) hit else only_index
  }

  plan <- ml_batch_resolve_index_plan(config, index_vars, root)
  mode <- plan$mode

  if (identical(mode, "single_then_multi")) {
    top_n <- as.integer(bc$multi_top_n %||% 3L)[1L]
    cli::cli_h2("Phase 1/2 — single_loop：{length(index_vars)} 个两库共有单指标并行")
    bc1 <- utils::modifyList(bc, list(index_mode = "single_loop"))
    config$ml_batch <- bc1
    config$incidence_batch <- bc1
    plan1 <- ml_batch_resolve_index_plan(config, index_vars, root)
    ml_batch_dispatch_index_workers(
      root, config, plan1$labels, run_opts, config_path
    )
    statuses1 <- incidence_batch_read_all_status(
      bc$output_base %||% config$project$output_dir,
      plan1$labels,
      index_subdir = incidence_batch_index_output_subdir(bc)
    )
    incidence_batch_print_summary(statuses1)
    top_ix <- ml_batch_pick_top_indices_from_status(statuses1, top_n = top_n)
    if (!length(top_ix)) {
      cli::cli_alert_warning("Phase 1 无成功指标，回退单因素 P 值 top {top_n}")
      top_ix <- ml_batch_rank_indices_top_n(config, index_vars, top_n = top_n, root = root)
    }
    combined_label <- ml_batch_index_label(top_ix)
    cli::cli_h2(
      "Phase 2/2 — multi_combined：{combined_label}（top {length(top_ix)}: {paste(top_ix, collapse=', ')})"
    )
    bc2 <- utils::modifyList(bc, list(
      index_mode = "multi_combined",
      index_vars = top_ix
    ))
    config$ml_batch <- bc2
    config$incidence_batch <- bc2
    ml_batch_dispatch_index_workers(
      root, config, combined_label, run_opts, config_path
    )
    dispatch_labels <- c(plan1$labels, combined_label)
  } else {
    cli::cli_alert_info(
      "指标模式: {plan$mode} | 任务数: {length(plan$jobs)} | 标签: {paste(plan$labels, collapse=', ')}"
    )
    dispatch_labels <- plan$labels
    if (!is.null(only_index) && length(only_index)) {
      if (plan$mode %in% c("multi_combined", "combo_loop")) {
        want <- if (plan$mode == "combo_loop") {
          ## 允许 'NLR+RAR' 或 'NLR,RAR' 两种写法定位到单个组合
          vapply(as.character(only_index), function(z) {
            if (grepl(",", z, fixed = TRUE)) ml_batch_combo_label(ml_batch_parse_index_arg(z))
            else z
          }, character(1))
        } else {
          ml_batch_index_label(only_index)
        }
        if (!any(want %in% dispatch_labels)) {
          stop("--only-index 与 {plan$mode} 计划不匹配", call. = FALSE)
        }
        dispatch_labels <- dispatch_labels[dispatch_labels %in% want]
      } else {
        dispatch_labels <- dispatch_labels[dispatch_labels %in% only_index]
      }
    }
    if (!length(dispatch_labels)) stop("无可用指标可跑", call. = FALSE)
    ml_batch_dispatch_index_workers(
      root, config, dispatch_labels, run_opts, config_path
    )
  }

  statuses <- incidence_batch_read_all_status(
    bc$output_base %||% config$project$output_dir,
    dispatch_labels,
    index_subdir = incidence_batch_index_output_subdir(bc)
  )
  incidence_batch_print_summary(statuses)

  if (identical(mode, "single_then_multi") && length(top_ix %||% NULL)) {
    cli::cli_alert_success(
      "两阶段完成：Phase1 {length(plan1$labels)} 单指标 → Phase2 合并 {paste(top_ix, collapse=', ')}"
    )
  }

  if (isTRUE((config$feishu %||% list())$push_on_batch_summary %||% FALSE)) {
    tryCatch(
      ml_batch_feishu_push_result(config, list(
        index = "BATCH_SUMMARY",
        status = "summary",
        db_mode = db_mode,
        error_message = paste0(
          "success=", sum(statuses$status == "success", na.rm = TRUE),
          " failed=", sum(statuses$status %in% c("error", "failed"), na.rm = TRUE)
        )
      )),
      error = function(e) NULL
    )
  }

  invisible(statuses)
}

#' Shared-layer index screening table (OR/HR); does NOT filter index_vars.
ml_batch_write_index_screening_or_hr <- function(root, config, candidate_vars = NULL,
                                                min_valid = 50L) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  pipeline_ensure_index_formula_helpers(root)
  defs <- tryCatch(pipeline_index_definition_map(), error = function(e) list())
  cands <- candidate_vars
  if (is.null(cands) || !length(cands)) {
    cands <- tryCatch(.composite_index_vars_dual_safe, error = function(e) names(defs))
  }
  cands <- unique(as.character(cands)[nzchar(as.character(cands))])

  # Prefer larger shared DB as analysis frame
  db_seq <- c("nhanes", "mimic")
  best_db <- NULL
  best_n <- -1L
  best_df <- NULL
  for (db in db_seq) {
    ck <- file.path(incidence_batch_shared_ck_dir(config, db), "index.rds")
    if (!file.exists(ck)) next
    obj <- tryCatch(readRDS(ck), error = function(e) NULL)
    df <- incidence_batch_ctx_data(obj$ctx)
    if (is.null(df) || !is.data.frame(df)) next
    if (nrow(df) > best_n) {
      best_n <- nrow(df)
      best_db <- db
      best_df <- df
    }
  }
  if (is.null(best_df)) {
    cli::cli_alert_warning("选指标表: 无共享层数据，跳过")
    return(invisible(NULL))
  }

  outcome <- as.character(config$data$outcome_column %||% "Disease_Group")[1L]
  ana <- as.character(config$project$analysis_group %||% character())[1L]
  time_var <- as.character(config$survival$time_var %||% character())[1L]
  has_time <- nzchar(time_var) && time_var %in% names(best_df)

  rows <- list()
  for (ix in cands) {
    if (!ix %in% names(best_df)) next
    x <- best_df[[ix]]
    ok <- !is.na(x)
    if (!outcome %in% names(best_df)) next
    y_raw <- best_df[[outcome]]
    ok <- ok & !is.na(y_raw)
    n <- sum(ok)
    if (n < as.integer(min_valid)[1L]) next
    y <- as.character(y_raw[ok])
    if (nzchar(ana)) {
      y_bin <- as.integer(y == ana)
    } else {
      y_bin <- as.integer(y %in% c("1", "TRUE", "True", "true"))
    }
    n_event <- sum(y_bin == 1L, na.rm = TRUE)
    x_ok <- as.numeric(x[ok])
    or_est <- NA_real_
    p_or <- NA_real_
    hr_est <- NA_real_
    p_hr <- NA_real_
    if (length(unique(y_bin[!is.na(y_bin)])) >= 2L && sum(is.finite(x_ok)) >= 10L) {
      fit <- tryCatch(
        stats::glm(y_bin ~ x_ok, family = stats::binomial()),
        error = function(e) NULL
      )
      if (!is.null(fit)) {
        sm <- summary(fit)$coefficients
        if (nrow(sm) >= 2L) {
          or_est <- unname(exp(sm[2L, 1L]))
          p_or <- unname(sm[2L, 4L])
        }
      }
      if (has_time) {
        tt <- as.numeric(best_df[[time_var]][ok])
        keep <- is.finite(tt) & tt > 0 & is.finite(x_ok)
        if (sum(keep) >= 10L && requireNamespace("survival", quietly = TRUE)) {
          cf <- tryCatch(
            survival::coxph(survival::Surv(tt[keep], y_bin[keep]) ~ x_ok[keep]),
            error = function(e) NULL
          )
          if (!is.null(cf)) {
            cs <- summary(cf)$coefficients
            if (!is.null(cs) && nrow(cs) >= 1L) {
              hr_est <- unname(exp(cs[1L, 1L]))
              p_hr <- unname(cs[1L, 5L])
            }
          }
        }
      }
    }

    comps <- tryCatch(
      index_get_formula_components(ix),
      error = function(e) character()
    )
    formula_str <- if (ix %in% names(defs)) {
      as.character(defs[[ix]])[1L]
    } else {
      ""
    }

    rows[[length(rows) + 1L]] <- data.frame(
      复合指标名 = ix,
      变量名 = paste(comps, collapse = ", "),
      计算公式 = formula_str,
      总样本量 = n,
      `DN=1的人数` = n_event,
      OR = or_est,
      P_OR = p_or,
      HR = hr_est,
      P_HR = p_hr,
      分析库 = .db_display_name_for_screening(config, best_db),
      stringsAsFactors = FALSE,
      check.names = FALSE
    )
  }

  if (!length(rows)) {
    cli::cli_alert_warning("选指标表: 无可用指标行")
    return(invisible(NULL))
  }
  tab <- do.call(rbind, rows)
  out_base <- (config$ml_batch %||% config$incidence_batch %||% list())$output_base %||%
    config$project$output_dir %||% root
  out_dir <- file.path(out_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  out_csv <- file.path(out_dir, "Index_screening_OR_HR.csv")
  utils::write.csv(tab, out_csv, row.names = FALSE, fileEncoding = "UTF-8")
  cli::cli_alert_success("选指标表已写: {.file {out_csv}}（{nrow(tab)} 行，不改循环名单）")
  invisible(tab)
}

.db_display_name_for_screening <- function(config, db) {
  if (identical(db, "nhanes")) {
    as.character(config$dual_db$primary$name %||% "primary")[1L]
  } else {
    as.character(config$dual_db$secondary$name %||% "secondary")[1L]
  }
}
#'
#' Requires seeded per-DB \code{index.rds} under checkpoints/by_index/<ix>/<DB>/
#' (worker seed loop). Larger-n DB → train; remaining → test. Skips secondary
#' \code{pipeline_mimic_ml_batch}.
#'
#' @return Final pipeline \code{ctx} (invisible).
ml_batch_run_cross_db_index <- function(root, config_ix, ix, indices, actual_db_seq, bc,
                                        primary_pipeline) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  indices <- as.character(indices)
  ck_base <- bc$index_ck_base %||% file.path(.batch_ck_root, "by_index")
  out_base <- bc$output_base %||% config_ix$project$output_dir
  ix_subdir <- incidence_batch_index_output_subdir(bc)
  out_root <- file.path(out_base, ix_subdir, ix)
  dir.create(file.path(out_root, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(out_root, "Figures"), recursive = TRUE, showWarnings = FALSE)

  .db_display_name <- function(db) {
    if (identical(db, "nhanes")) {
      as.character(config_ix$dual_db$primary$name %||% "primary")[1L]
    } else {
      as.character(config_ix$dual_db$secondary$name %||% "secondary")[1L]
    }
  }

  frames <- list()
  db_n <- integer()
  event_counts <- integer()
  outcome_col <- as.character(config_ix$data$outcome_column %||% "Disease_Group")[1L]
  ana <- as.character(config_ix$project$analysis_group %||% character())[1L]

  for (db in actual_db_seq) {
    nm <- .db_display_name(db)
    ck_path <- file.path(ck_base, ix, dual_db_slot_path_name(config_ix, db), "index.rds")
    if (!file.exists(ck_path)) {
      stop("cross_db: 缺少 index 检查点: ", ck_path, call. = FALSE)
    }
    obj <- readRDS(ck_path)
    df <- incidence_batch_ctx_data(obj$ctx)
    if (is.null(df) || !is.data.frame(df) || !nrow(df)) {
      stop("cross_db: ", nm, " 无可用数据", call. = FALSE)
    }
    if (length(indices) == 1L && indices[[1L]] %in% names(df)) {
      df <- df[!is.na(df[[indices[[1L]]]]), , drop = FALSE]
    }
    frames[[nm]] <- df
    db_n[[nm]] <- nrow(df)
    if (nzchar(outcome_col) && outcome_col %in% names(df)) {
      y <- df[[outcome_col]]
      if (nzchar(ana)) {
        event_counts[[nm]] <- sum(as.character(y) == ana, na.rm = TRUE)
      } else {
        event_counts[[nm]] <- sum(!is.na(y) & y %in% c(1, "1", TRUE), na.rm = TRUE)
      }
    } else {
      event_counts[[nm]] <- NA_integer_
    }
  }

  # 双库列对齐到交集，避免 train 有/test 无导致 ML undefined columns
  common_cols <- Reduce(intersect, lapply(frames, names))
  if (!length(common_cols)) stop("cross_db: 两库无共同列", call. = FALSE)
  frames <- lapply(frames, function(d) d[, common_cols, drop = FALSE])
  cli::cli_alert_info("cross_db 列对齐: 共有 {length(common_cols)} 列")

  primary_name <- as.character(config_ix$dual_db$primary$name %||% names(db_n)[[1L]])[1L]
  roles <- ml_cross_db_assign_roles(db_n, primary_name = primary_name, event_counts = event_counts)
  bound <- ml_cross_db_bind_role(frames, roles$assignment)
  if (is.null(bound$test) && length(bound) > 1L) {
    stop("cross_db: 未绑定 test 帧", call. = FALSE)
  }

  assign_path <- file.path(out_root, "Tables", "Train_test_assignment.csv")
  utils::write.csv(roles$assignment, assign_path, row.names = FALSE, fileEncoding = "UTF-8")
  cli::cli_alert_success(
    "cross_db 划分: train={roles$train_db} (n={db_n[[roles$train_db]]}) | test={paste(roles$test_dbs, collapse=', ')}"
  )
  cli::cli_alert_info("已写 {.file {assign_path}}")

  train_db_key <- actual_db_seq[
    vapply(actual_db_seq, function(db) identical(.db_display_name(db), roles$train_db), logical(1))
  ][[1L]]
  train_ck <- file.path(
    ck_base, ix, dual_db_slot_path_name(config_ix, train_db_key), "index.rds"
  )
  obj <- readRDS(train_ck)
  ctx <- obj$ctx
  ctx$data$train <- bound$train
  ctx$data$test <- bound$test %||% bound[[names(bound)[names(bound) != "train"][[1L]]]]
  ctx$data$mapped <- bound$train
  ctx$data$cleaned <- bound$train
  ctx$data$imputed <- NULL
  ctx$results$cross_db_assignment <- roles$assignment
  ctx$results$cross_db_train_db <- roles$train_db
  ctx$results$cross_db_test_dbs <- roles$test_dbs

  cfg <- config_ix
  cfg$project$output_dir <- out_root
  cfg$project$database <- ""
  cfg$dual_db$mirror_aggregate <- FALSE
  cfg$dual_db$mirror_aggregate_prefix_db <- FALSE
  cfg$dual_db$current_db <- train_db_key
  cfg$ml_batch$split_mode <- "cross_db"
  cfg$incidence_batch$split_mode <- "cross_db"
  cfg <- ml_dual_apply_cross_db_split_overrides(cfg)
  if (!is.null(ctx$config)) {
    ctx$config <- cfg
  }
  obj$ctx <- ctx
  obj$config <- cfg

  per_ck <- file.path(ck_base, ix, "cross_db")
  if (!dir.exists(per_ck)) dir.create(per_ck, recursive = TRUE)
  saveRDS(obj, file.path(per_ck, "index.rds"))

  pipe <- primary_pipeline
  if (is.null(pipe)) {
    pipe <- if (dual_db_is_weighted(cfg, "nhanes")) {
      pipeline_nhanes_batch
    } else {
      pipeline_regular_primary_ml_batch
    }
  }
  pipe <- incidence_batch_set_pipeline_ck(pipe, per_ck)
  pipe$database_name <- ""

  cli::cli_h2("[{ix}] cross_db — 单流水线 Train({roles$train_db}) / Test({paste(roles$test_dbs, collapse='+')})")
  ctx_out <- run_pipeline(root, config = cfg, pipeline = pipe, run_opts = list(from = "index", to = NULL))
  invisible(ctx_out)
}
