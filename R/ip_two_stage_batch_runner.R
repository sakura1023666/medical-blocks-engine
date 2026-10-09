###############################################################################
#  ip_two_stage_batch_runner.R
#  SLE → AKI 发病 + 28 天预后：单库 MIMIC、共享层 + 按指标并行 worker
#
#  参考: R/incidence_dual_batch_runner.R（shared + dispatch + finalize 模式）
#  差异: dual_db$enable=FALSE；同一 worker 内 Stage1 → 桥接 → Stage2
#  产出只写 config$project$output_dir（结果根），禁止镜像到引擎仓库根
###############################################################################

ip_two_stage_batch_cfg <- function(config) {
  ib <- config$incidence_batch %||% list()
  ip <- config$ip_two_stage_batch %||% list()
  utils::modifyList(ib, ip)
}

ip_two_stage_sync_batch_cfg <- function(config) {
  merged <- ip_two_stage_batch_cfg(config)
  config$incidence_batch <- merged
  config$ip_two_stage_batch <- merged
  # code bundle / slot 目录用 mimic，与 template checkpoint 一致
  if (is.null(config$dual_db) || !is.list(config$dual_db)) config$dual_db <- list()
  config$dual_db$enable <- FALSE
  if (is.null(config$dual_db$secondary) || !is.list(config$dual_db$secondary)) {
    config$dual_db$secondary <- list()
  }
  if (is.null(config$dual_db$secondary$name) || !nzchar(as.character(config$dual_db$secondary$name)[1L])) {
    config$dual_db$secondary$name <- "mimic"
  }
  # Stage1 Table1：暴露组间不显著早停（缺省 TRUE；课题可显式 FALSE）
  if (!is.null(config$baseline_binary) && is.list(config$baseline_binary)) {
    if (is.null(config$baseline_binary$early_stop_if_index_ns)) {
      config$baseline_binary$early_stop_if_index_ns <- TRUE
    }
  }
  config
}

ip_two_stage_assert_result_root <- function(config, root) {
  out <- as.character(
    (ip_two_stage_batch_cfg(config)$output_base %||% config$project$output_dir %||% "")[1L]
  )
  if (!nzchar(out)) {
    stop("ip_two_stage: 缺少 project$output_dir / ip_two_stage_batch$output_base", call. = FALSE)
  }
  out_n <- tryCatch(normalizePath(out, winslash = "/", mustWork = FALSE), error = function(e) out)
  root_n <- tryCatch(normalizePath(root, winslash = "/", mustWork = FALSE), error = function(e) root)
  # 禁止把发表产出写到引擎仓库根
  if (nzchar(root_n) && identical(tolower(out_n), tolower(root_n))) {
    stop(
      "ip_two_stage: output_dir 不能等于引擎根 ", root_n,
      "。请把结果写到课题结果根（如 G:/02block_result/29_SLE/...）。",
      call. = FALSE
    )
  }
  out_n
}

ip_two_stage_shared_ck_dir <- function(config) {
  bc <- ip_two_stage_batch_cfg(config)
  parent <- bc$shared_ck_base %||% file.path(
    bc$output_base %||% config$project$output_dir, "checkpoints", "_shared"
  )
  cands <- unique(c(
    file.path(parent, "mimic"),
    file.path(parent, "MIMIC"),
    parent
  ))
  for (d in cands) {
    if (file.exists(file.path(d, "index.rds")) ||
        file.exists(file.path(d, "imputation.rds"))) {
      return(d)
    }
  }
  file.path(parent, "mimic")
}

ip_two_stage_index_ck_dir <- function(config, ix) {
  bc <- ip_two_stage_batch_cfg(config)
  file.path(bc$index_ck_base %||% file.path(
    bc$output_base %||% config$project$output_dir, "checkpoints", "by_index"
  ), ix, "mimic")
}

ip_two_stage_index_output_dir <- function(config, ix, resume = FALSE) {
  bc <- ip_two_stage_batch_cfg(config)
  output_base <- bc$output_base %||% config$project$output_dir
  if (isTRUE(resume) && exists("incidence_batch_find_index_output_dir", mode = "function")) {
    return(incidence_batch_find_index_output_dir(output_base, ix, "by_index"))
  }
  file.path(output_base, "by_index", ix)
}

ip_two_stage_shared_complete <- function(ck_dir) {
  file.exists(file.path(ck_dir, "imputation.rds"))
}

ip_two_stage_latest_shared_ck <- function(ck_dir) {
  for (bn in c("imputation.rds", "index.rds")) {
    p <- file.path(ck_dir, bn)
    if (file.exists(p)) return(p)
  }
  NA_character_
}

ip_two_stage_ensure_index_alias <- function(ck_dir) {
  idx <- file.path(ck_dir, "index.rds")
  if (file.exists(idx)) return(idx)
  src <- ip_two_stage_latest_shared_ck(ck_dir)
  if (!is.na(src) && file.exists(src)) {
    file.copy(src, idx, overwrite = TRUE)
  }
  idx
}

ip_two_stage_resolve_index_vars <- function(config) {
  bc <- ip_two_stage_batch_cfg(config)
  ivs <- bc$index_vars
  if (!is.null(ivs) && length(ivs)) {
    return(incidence_batch_filter_disease_derived_indices(config, as.character(ivs)))
  }
  only <- as.character((config$index %||% list())$only %||% character(0))
  only <- only[nzchar(only)]
  if (length(only)) {
    return(incidence_batch_filter_disease_derived_indices(config, only))
  }
  incidence_batch_resolve_index_vars(config)
}

ip_two_stage_resolve_from_shared_ck <- function(config, candidate_vars) {
  ck_dir <- ip_two_stage_shared_ck_dir(config)
  alias <- ip_two_stage_latest_shared_ck(ck_dir)
  if (is.na(alias) || !file.exists(alias)) {
    stop("共享层检查点缺失: ", ck_dir, call. = FALSE)
  }
  obj <- tryCatch(readRDS(alias), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) {
    stop("共享层检查点无效: ", alias, call. = FALSE)
  }
  df <- if (exists("incidence_batch_ctx_data", mode = "function")) {
    incidence_batch_ctx_data(obj$ctx)
  } else {
    obj$ctx$data$imputed %||% obj$ctx$data$mapped %||% obj$ctx$data$cleaned
  }
  names_in <- names(df %||% list())
  computed <- as.character(obj$ctx$results$computed_index_names %||% character(0))
  min_valid <- as.integer(ip_two_stage_batch_cfg(config)$min_valid_per_db %||% 50L)
  if (length(computed)) {
    available <- intersect(computed, names_in)
  } else {
    available <- intersect(candidate_vars, names_in)
  }
  available <- available[vapply(available, function(ix) {
    if (!ix %in% names(df)) return(FALSE)
    sum(!is.na(df[[ix]])) >= min_valid
  }, logical(1L))]
  raw_extra <- intersect(candidate_vars, names_in)
  raw_extra <- raw_extra[vapply(raw_extra, function(ix) {
    sum(!is.na(df[[ix]])) >= min_valid
  }, logical(1L))]
  available <- unique(c(available, raw_extra))
  final <- candidate_vars[candidate_vars %in% available]
  cli::cli_alert_success(
    "共享层可用指标 (n_valid>={min_valid}): {length(final)} 个: {paste(final, collapse = ', ')}"
  )
  if (!length(final)) {
    stop("共享层没有任何指标可用，请检查 index / min_valid_per_db。", call. = FALSE)
  }
  final
}

#' 解析 --from/--to 到两阶段相位（shared 由父进程处理）
ip_two_stage_plan_worker_phases <- function(stage1_blocks, stage2_blocks,
                                            from_token = NULL, to_token = NULL) {
  s1 <- as.character(stage1_blocks %||% character(0))
  s2 <- as.character(stage2_blocks %||% character(0))
  bridge <- "ip_stage2_cohort_28d"
  s0 <- c(
    "ip_cohort_sle_aki", "attrition_flowchart", "data_clean",
    "column_mapping", "index", "analysis_exclusion", "imputation"
  )
  aliases <- list(
    shared = "imputation", stage0 = "imputation", imputation = "imputation",
    stage1 = tail(s1, 1L),
    logistic = "logistic_quintile_glm",
    rcs = "rcs_incidence",
    threshold = "threshold_logistic",
    subgroup = "subgroup_incidence",
    mediation = "mediation_incidence",
    bridge = bridge, stage2_cohort = bridge,
    stage2 = tail(s2, 1L),
    cox = "cox_binary",
    km = "km_binary"
  )

  .norm <- function(tok) {
    if (is.null(tok) || !nzchar(as.character(tok)[1L])) return(NULL)
    raw <- trimws(as.character(tok)[1L])
    key <- tolower(raw)
    if (key %in% names(aliases)) return(unname(aliases[[key]]))
    raw
  }
  from_b <- .norm(from_token)
  to_b <- .norm(to_token)

  .phase_of <- function(b, prefer = "stage1") {
    if (is.null(b)) return(NA_character_)
    if (identical(b, bridge) || identical(tolower(b), "bridge")) return("bridge")
    if (b %in% s0) return("shared")
    in1 <- b %in% s1
    in2 <- b %in% s2
    if (in1 && in2) return(prefer)
    if (in1) return("stage1")
    if (in2) return("stage2")
    NA_character_
  }

  from_ph <- .phase_of(from_b, prefer = "stage1")
  to_ph <- .phase_of(to_b, prefer = if (identical(from_ph, "stage2")) "stage2" else "stage1")
  if (is.na(from_ph) && !is.null(from_b)) {
    stop("未知 --from 块: ", from_b, call. = FALSE)
  }
  if (is.na(to_ph) && !is.null(to_b)) {
    stop("未知 --to 块: ", to_b, call. = FALSE)
  }

  order_ph <- c("shared", "stage1", "bridge", "stage2")
  start_i <- if (is.na(from_ph)) 2L else match(from_ph, order_ph)
  end_i <- if (is.na(to_ph)) 4L else match(to_ph, order_ph)
  if (is.na(start_i)) start_i <- 2L
  if (is.na(end_i)) end_i <- 4L
  if (end_i < start_i) {
    stop("--from/--to 相位顺序无效: ", from_ph, " → ", to_ph, call. = FALSE)
  }
  active <- order_ph[seq.int(start_i, end_i)]

  .from_for <- function(ph) {
    if (!identical(from_ph, ph)) return(NULL)
    from_b
  }
  .to_for <- function(ph) {
    if (!identical(to_ph, ph)) return(NULL)
    to_b
  }

  list(
    run_stage1 = "stage1" %in% active,
    run_bridge = "bridge" %in% active,
    run_stage2 = "stage2" %in% active,
    stage1_from = .from_for("stage1"),
    stage1_to = .to_for("stage1"),
    stage2_from = .from_for("stage2"),
    stage2_to = .to_for("stage2"),
    from_phase = from_ph,
    to_phase = to_ph
  )
}

ip_two_stage_snapshot_stage1_covariates <- function(ctx) {
  m1 <- unique(as.character(
    ctx$results$Model1Factors %||% ctx$results$model1_incidence %||% character(0)
  ))
  m2 <- unique(as.character(
    ctx$results$Model2Factors %||% ctx$results$model2_incidence %||% character(0)
  ))
  # 少数流程会把 Model1 写成与 Model2 同长名单；回退人口学作 Model1，保留长名单作 Model2
  if (length(m1) && length(m2) && setequal(m1, m2) && length(m1) > 3L) {
    demo <- intersect(c("Age", "Gender", "Sex", "Race"), m2)
    if (!length(demo)) demo <- intersect(c("Age", "Gender"), names(ctx$data$imputed %||% list()))
    if (length(demo)) {
      cli::cli_alert_warning(
        "Stage1 Model1 与 Model2 相同，Model1 回退为: {paste(demo, collapse = ', ')}"
      )
      m1 <- demo
    }
  }
  if (!length(m2)) m2 <- m1
  ctx$results$model1_incidence <- m1
  ctx$results$model2_incidence <- unique(c(m1, m2))
  ctx$results$model2_incidence_full <- ctx$results$model2_incidence
  ctx$results$Model1Factors <- m1
  ctx$results$Model2Factors <- ctx$results$model2_incidence
  d0 <- NULL
  for (nm in c("imputed", "locked", "cleaned", "analysis")) {
    if (is.data.frame(ctx$data[[nm]])) { d0 <- ctx$data[[nm]]; break }
  }
  if (is.data.frame(d0)) ctx$results$ip_stage1_n <- nrow(d0)
  ctx
}

#' Stage1 亚组变量锁定 → Stage2 prognosis 森林图同名单
ip_two_stage_snapshot_stage1_subgroup <- function(ctx, config = NULL) {
  sg <- unique(as.character(ctx$results$subgroup_vars_used %||% character(0)))
  sg <- sg[nzchar(sg)]
  if (!length(sg)) return(ctx)
  ctx$results$locked_subgroup_vars <- sg
  if (!is.null(config) && is.list(config)) {
    if (is.null(config$subgroup) || !is.list(config$subgroup)) config$subgroup <- list()
    config$subgroup$locked_subgroup_vars <- sg
    if (is.null(config$subgroup_prognosis) || !is.list(config$subgroup_prognosis)) {
      config$subgroup_prognosis <- list()
    }
    config$subgroup_prognosis$locked_subgroup_vars <- sg
    ctx$config <- config
  }
  cli::cli_alert_info(
    "Stage1 亚组锁定 → Stage2: {paste(sg, collapse = ', ')}"
  )
  ctx
}

#' 发病/预后共用同一套 Model1/Model2（Stage1 锁定）；禁止 Stage2 再并集膨胀
ip_two_stage_apply_covariate_union <- function(ctx, config, when = c("before_stage2", "after_stage2")) {
  when <- match.arg(when)
  m1_inc <- unique(as.character(ctx$results$model1_incidence %||% character(0)))
  m2_inc <- unique(as.character(ctx$results$model2_incidence %||% character(0)))
  df <- NULL
  for (nm in c("imputed", "stage2", "locked", "cleaned")) {
    if (is.data.frame(ctx$data[[nm]])) { df <- ctx$data[[nm]]; break }
  }
  m2_full <- m2_inc
  if (is.data.frame(df)) {
    m1_inc <- intersect(m1_inc, names(df))
    m2_inc <- intersect(m2_inc, names(df))
  }
  if (length(m1_inc) && length(m2_inc) && setequal(m1_inc, m2_inc) && length(m1_inc) > 3L) {
    demo <- intersect(c("Age", "Gender", "Sex", "Race"), m2_inc)
    if (length(demo)) m1_inc <- demo
  }
  if (!length(m1_inc) && is.data.frame(df) && "Age" %in% names(df)) {
    m1_inc <- "Age"
  }
  if (!length(m2_inc)) m2_inc <- m1_inc
  m2_fit <- unique(c(m1_inc, m2_inc))

  ctx$results$Model1Factors <- m1_inc
  ctx$results$Model2Factors <- m2_fit
  ctx$results$model1_incidence <- m1_inc
  ctx$results$model2_incidence <- m2_full
  ctx$results$model2_incidence_full <- m2_full
  ctx$results$model1_union <- m1_inc
  ctx$results$model2_union <- m2_fit

  if (identical(when, "before_stage2")) {
    for (nm in c("univariate_prognosis", "multivariate_prognosis")) {
      if (is.null(ctx$config[[nm]]) || !is.list(ctx$config[[nm]])) next
      ctx$config[[nm]]$required_predictors <- unique(c(
        as.character(ctx$config[[nm]]$required_predictors %||% character(0)),
        m1_inc
      ))
    }
    cli::cli_alert_info(
      "Stage2 协变量与发病对齐: Model1={paste(m1_inc, collapse = ', ')} | Model2={paste(m2_inc, collapse = ', ')}"
    )
  } else {
    cli::cli_alert_success(
      "Stage2 协变量已强制回写为发病锁定集: Model1={paste(m1_inc, collapse = ', ')} | Model2={paste(m2_inc, collapse = ', ')}"
    )
  }
  ctx
}

#' 把发病锁定 Model1/Model2 写入 Cox / RCS config，并关闭协变量搜索
ip_two_stage_lock_cox_rcs_covariates <- function(config, ctx) {
  m1 <- unique(as.character(
    ctx$results$model1_incidence %||% ctx$results$Model1Factors %||% character(0)
  ))
  m2 <- unique(as.character(
    ctx$results$model2_incidence %||% ctx$results$Model2Factors %||% character(0)
  ))
  if (length(m1) && length(m2) && setequal(m1, m2) && length(m1) > 3L) {
    demo <- intersect(c("Age", "Gender", "Sex", "Race"), m2)
    if (length(demo)) m1 <- demo
  }
  if (!length(m2)) m2 <- m1
  m2 <- unique(c(m1, m2))
  m2_ref <- unique(as.character(
    ctx$results$model2_incidence_full %||% ctx$results$model2_incidence %||% m2
  ))
  ctx$results$Model1Factors <- m1
  ctx$results$Model2Factors <- m2
  df <- NULL
  for (dn in c("imputed", "stage2", "locked", "cleaned")) {
    if (is.data.frame(ctx$data[[dn]])) { df <- ctx$data[[dn]]; break }
  }
  m1_fit <- m1
  m2_fit <- m2
  if (is.data.frame(df)) {
    m1_fit <- intersect(m1, names(df))
    m2_fit <- intersect(m2_ref, names(df))
    m2_fit <- unique(c(m1_fit, m2_fit))
  }
  ctx$results$Model1Factors <- m1_fit
  ctx$results$Model2Factors <- m2_fit
  for (nm in c("cox_quartile", "cox_tertile", "cox_binary",
               "rcs_incidence", "rcs_prognosis", "segmented_cox_quartile",
               "segmented_cox_tertile", "segmented_cox_binary")) {
    if (is.null(config[[nm]]) || !is.list(config[[nm]])) next
    config[[nm]]$model1_factors <- m1_fit
    config[[nm]]$model2_factors <- m2_fit
    config[[nm]]$allow_m2_eq_m1 <- TRUE
    if (!is.null(config[[nm]]$covariate_search) && is.list(config[[nm]]$covariate_search)) {
      config[[nm]]$covariate_search$enable <- FALSE
    }
  }
  config
}

#' 按指标注入 km_strata 分层列（与 survival_dual_batch_runner 对齐；含 Cox 降级分支）
ip_two_stage_patch_km_strata_for_index <- function(config, ix) {
  q_col <- paste0(ix, "_quartile")
  t_col <- paste0(ix, "_tertile")
  if (is.null(config$km_strata) || !is.list(config$km_strata)) {
    config$km_strata <- list()
  }
  surv <- config$survival %||% list()
  if (is.null(config$km_strata$time_var) ||
      !nzchar(as.character(config$km_strata$time_var)[1L] %||% "")) {
    config$km_strata$time_var <- surv$time_var %||% "futime"
  }
  if (is.null(config$km_strata$event_var) ||
      !nzchar(as.character(config$km_strata$event_var)[1L] %||% "")) {
    config$km_strata$event_var <- surv$event_var %||% "fustatus"
  }
  if (is.null(config$km_strata$event_value)) {
    config$km_strata$event_value <- surv$event_value %||% 1
  }
  if (is.null(config$km_strata$time_divisor)) {
    config$km_strata$time_divisor <- surv$time_divisor %||% 1
  }
  config$km_strata$strata_vars <- c(q_col)
  config$km_strata$strata_vars_by_branch <- list(
    extend_quartile  = c(q_col),
    extend_tertile   = c(t_col),
    extend_binary    = c(q_col),
    degrade_tertile  = c(t_col),
    degrade_binary   = c(q_col),
    degrade_done     = c(q_col)
  )
  config$km_strata$strata_defs <- list()
  config$km_strata$strata_defs[[q_col]] <- list(
    source = ix,
    type   = "quartile_factor",
    labels = c("Q1", "Q2", "Q3", "Q4"),
    levels = c("Q1", "Q2", "Q3", "Q4")
  )
  config$km_strata$strata_defs[[t_col]] <- list(
    source = ix,
    type   = "tertile_factor",
    labels = c("T1", "T2", "T3"),
    levels = c("T1", "T2", "T3")
  )
  config
}

#' 按指标写入 Stage1/Stage2 各 block 的 index_var（续跑 checkpoint 时避免 idx 为空）
ip_two_stage_patch_stage2_blocks_for_index <- function(config, ix) {
  config$incidence$index_var <- ix
  config$logistic$index_var <- ix
  config$survival$index_var <- ix
  for (blk in c(
    "cox_quartile", "cox_tertile", "cox_binary",
    "rcs_prognosis", "plot_cutoff",
    "km_binary", "km_strata",
    "segmented_cox_quartile", "segmented_cox_tertile", "segmented_cox_binary",
    "subgroup_prognosis", "simple_ROC",
    "univariate_prognosis", "multivariate_prognosis"
  )) {
    if (is.null(config[[blk]]) || !is.list(config[[blk]])) next
    config[[blk]]$index_var <- ix
  }
  config
}

#' Stage2 中属于「预后协变量再筛选」的 block（reuse_stage1_covariates=TRUE 时整段跳过）
ip_two_stage_stage2_covariate_selection_blocks <- function() {
  c(
    "univariate_prognosis",
    "multicollinearity_screen",
    "multivariate_prognosis",
    "multicollinearity_final",
    "multivariate_prognosis_harmonized",
    "simple_ROC"
  )
}

#' 是否 Stage2 直接沿用 Stage1 锁定 Model1/Model2（默认 TRUE）
ip_two_stage_reuse_stage1_covariates <- function(config) {
  flag <- (config$ip_two_stage %||% list())$reuse_stage1_covariates
  if (!is.null(flag)) return(isTRUE(flag))
  flag <- (ip_two_stage_batch_cfg(config)$reuse_stage1_covariates %||% TRUE)
  isTRUE(flag)
}

#' 从 pipeline_stage2 去掉预后 UV/MV/ROC（保留 baseline + Cox/RCS/KM/亚组）
ip_two_stage_trim_stage2_pipeline <- function(config, pipeline) {
  if (!ip_two_stage_reuse_stage1_covariates(config)) return(pipeline)
  drop <- ip_two_stage_stage2_covariate_selection_blocks()
  pipeline$blocks <- setdiff(as.character(pipeline$blocks %||% character(0)), drop)
  pipeline$render_tables_after <- setdiff(
    as.character(pipeline$render_tables_after %||% character(0)), drop
  )
  pipeline$render_figures_after <- setdiff(
    as.character(pipeline$render_figures_after %||% character(0)), drop
  )
  pipeline
}

#' Stage2 入口：快照发病 Model1/2 并写入 Cox/RCS/KM config（不再跑预后协变量筛选）
ip_two_stage_prepare_stage2_locked_covariates <- function(config, ctx) {
  if (is.null(ctx)) {
    stop("ip_two_stage: Stage2 缺少 ctx，无法沿用发病协变量。", call. = FALSE)
  }
  ctx <- ip_two_stage_snapshot_stage1_covariates(ctx)
  ctx <- ip_two_stage_apply_covariate_union(ctx, config, "before_stage2")
  config <- ip_two_stage_lock_cox_rcs_covariates(config, ctx)
  ctx$config <- config
  ctx$results$ip_stage2_covariates_reused <- TRUE
  m1 <- unique(as.character(ctx$results$Model1Factors %||% character(0)))
  m2 <- unique(as.character(ctx$results$Model2Factors %||% character(0)))
  cli::cli_alert_info(
    "Stage2 沿用发病锁定协变量（已跳过预后 UV/MV）: Model1={paste(m1, collapse = ', ')} | Model2={paste(m2, collapse = ', ')}"
  )
  list(config = config, ctx = ctx)
}

ip_two_stage_switch_to_prognosis <- function(config, ctx = NULL) {
  config$project$study_type <- "prognosis"
  config$data$outcome_column <- "fustatus"
  config$survival$time_var <- config$survival$time_var %||% "futime"
  config$survival$event_var <- config$survival$event_var %||% "fustatus"
  # Stage2 Table1：按 28 天死亡分层；暴露组间不显著同样早停记失败（与 Stage1 一致）
  if (is.null(config$baseline_binary) || !is.list(config$baseline_binary)) {
    config$baseline_binary <- list()
  }
  if (is.null(config$baseline_binary$early_stop_if_index_ns)) {
    config$baseline_binary$early_stop_if_index_ns <- TRUE
  }
  if (is.null(config$baseline_binary$table_title) ||
      !nzchar(as.character(config$baseline_binary$table_title)[1L])) {
    config$baseline_binary$table_title <- paste(
      "Baseline characteristics among AKI by 28-day mortality"
    )
  }
  if (!is.null(ctx)) {
    ctx$config <- config
    if (!is.null(ctx$config$project)) ctx$config$project$study_type <- "prognosis"
    if (!is.null(ctx$config$data)) ctx$config$data$outcome_column <- "fustatus"
  }
  list(config = config, ctx = ctx)
}

ip_two_stage_copy_dir_files <- function(src, dest, pattern = NULL) {
  if (is.null(src) || !dir.exists(src)) return(0L)
  if (!dir.exists(dest)) dir.create(dest, recursive = TRUE)
  files <- list.files(src, full.names = TRUE, recursive = FALSE)
  if (!is.null(pattern) && length(files)) {
    files <- files[grepl(pattern, basename(files), ignore.case = TRUE)]
  }
  n <- 0L
  for (f in files) {
    if (dir.exists(f)) next
    if (grepl("\\.(svg|tex)$", basename(f), ignore.case = TRUE)) next
    ok <- tryCatch(file.copy(f, file.path(dest, basename(f)), overwrite = TRUE),
                   error = function(e) FALSE)
    if (isTRUE(ok)) n <- n + 1L
  }
  n
}

#' 从 _shared 拷贝 Figure 1 纳排到指标 / 结果根 Figures（含 pdf/ 与 image_information）
ip_two_stage_ensure_figure1_flowchart <- function(index_root, result_root, shared_out) {
  candidates <- c(
    file.path(shared_out, "Figures", "pdf", "Figure 1. Flowchart.pdf"),
    file.path(shared_out, "Figures", "Figure 1. Flowchart.pdf"),
    file.path(shared_out, "step02_attrition_flowchart", "Figures", "Figure 1. Flowchart.pdf")
  )
  src <- candidates[file.exists(candidates)][1L]
  if (is.na(src) || !nzchar(src %||% "")) {
    cli::cli_alert_warning("未找到 shared Figure 1. Flowchart.pdf，跳过拷贝")
    return(invisible(FALSE))
  }
  md_cands <- c(
    file.path(shared_out, "Figures", "image_information", "Figure 1. Flowchart.md"),
    file.path(dirname(dirname(src)), "image_information", "Figure 1. Flowchart.md")
  )
  md_src <- md_cands[file.exists(md_cands)][1L]
  for (root in unique(c(index_root, result_root))) {
    if (!nzchar(root %||% "")) next
    fig_root <- file.path(root, "Figures")
    dir.create(file.path(fig_root, "pdf"), recursive = TRUE, showWarnings = FALSE)
    dir.create(file.path(fig_root, "image_information"), recursive = TRUE, showWarnings = FALSE)
    file.copy(src, file.path(fig_root, "Figure 1. Flowchart.pdf"), overwrite = TRUE)
    file.copy(src, file.path(fig_root, "pdf", "Figure 1. Flowchart.pdf"), overwrite = TRUE)
    if (!is.na(md_src) && nzchar(md_src %||% "")) {
      file.copy(md_src, file.path(fig_root, "image_information", "Figure 1. Flowchart.md"),
                overwrite = TRUE)
    }
  }
  cli::cli_alert_success("已确保 Figure 1. Flowchart → 指标与结果根")
  invisible(TRUE)
}

#' 清理两阶段主文图同号撞车残留（只留叙事线定稿文件名模式）
ip_two_stage_prune_main_figure_collisions <- function(index_root) {
  fig_dirs <- c(
    file.path(index_root, "Figures"),
    file.path(index_root, "Figures", "pdf")
  )
  fig_dirs <- fig_dirs[dir.exists(fig_dirs)]
  keep_re <- c(
    "(?i)^Figure 1\\. Flowchart",
    "(?i)^Figure 2.*RCS plot between .+ and AKI",
    "(?i)^Figure 3.*Subgroup Forest",
    "(?i)^Figure 4.*RCS Analysis .+ Mortality",
    "(?i)^Figure 5.*Kaplan-Meier",
    "(?i)^Figure 6.*Subgroup Forest"
  )
  # 主文 Figure N 但不符合 keep 的 → 删（避免同号多张）；Figure S* 保留
  n_del <- 0L
  for (d in fig_dirs) {
    pdfs <- list.files(d, pattern = "(?i)^Figure [0-9].*\\.pdf$", full.names = TRUE)
    for (fp in pdfs) {
      bn <- basename(fp)
      if (grepl("(?i)^Figure S", bn)) next
      ok <- any(vapply(keep_re, function(re) grepl(re, bn, perl = TRUE), logical(1)))
      if (!ok) {
        # 删非定稿主文 Figure 1–9（含错号 RCS 占 Figure 1）
        if (grepl("(?i)^Figure [1-9]([.-]|$)", bn)) {
          unlink(fp)
          n_del <- n_del + 1L
          md2 <- file.path(index_root, "Figures", "image_information",
                           sub("\\.pdf$", ".md", bn, ignore.case = TRUE))
          if (file.exists(md2)) unlink(md2)
        }
      }
    }
  }
  if (n_del > 0L) {
    cli::cli_alert_info("已清理 {n_del} 个非定稿主文图撞号文件")
  }
  invisible(n_del)
}

ip_two_stage_mirror_pub_outputs <- function(index_root, result_root, shared_out = NULL) {
  n <- 0L
  for (kind in c("Tables", "Figures")) {
    n <- n + ip_two_stage_copy_dir_files(
      file.path(index_root, kind), file.path(index_root, kind)
    )
    n <- n + ip_two_stage_copy_dir_files(
      file.path(index_root, kind), file.path(result_root, kind)
    )
    if (!is.null(shared_out) && dir.exists(file.path(shared_out, kind))) {
      n <- n + ip_two_stage_copy_dir_files(
        file.path(shared_out, kind), file.path(index_root, kind)
      )
      n <- n + ip_two_stage_copy_dir_files(
        file.path(shared_out, kind), file.path(result_root, kind)
      )
    }
  }
  n
}

ip_two_stage_finalize_index_outputs <- function(root, config, ix, ctx = NULL) {
  bc <- ip_two_stage_batch_cfg(config)
  light <- isTRUE(bc$.sensitivity_light)
  result_root <- bc$output_base %||% config$project$output_dir
  index_root <- ip_two_stage_index_output_dir(config, ix, resume = TRUE)
  if (!dir.exists(index_root)) {
    index_root <- file.path(result_root, "by_index", ix)
    dir.create(index_root, recursive = TRUE, showWarnings = FALSE)
  }
  shared_out <- file.path(result_root, "_shared")

  if (exists("sync_all_block_pub_outputs_to_root", mode = "function") && !is.null(ctx)) {
    ctx$root_output_dir <- index_root
    ctx$config$project$output_dir <- index_root
    tryCatch(
      sync_all_block_pub_outputs_to_root(ctx),
      error = function(e) cli::cli_alert_warning("同步 step 发表物失败: {e$message}")
    )
  }

  ip_two_stage_mirror_pub_outputs(index_root, result_root, shared_out)
  if (!light) {
    ip_two_stage_ensure_figure1_flowchart(index_root, result_root, shared_out)
    tryCatch(
      ip_two_stage_prune_main_figure_collisions(index_root),
      error = function(e) cli::cli_alert_warning("主文图撞号清理失败: {e$message}")
    )
  }
  cli::cli_alert_info("已镜像 Tables/Figures → {.file {index_root}} 与结果根")

  if (light) return(invisible(index_root))

  n_total <- NULL
  n_by_db <- NULL
  if (!is.null(ctx)) {
    n_s1 <- suppressWarnings(as.integer(ctx$results$ip_stage1_n %||% NA_integer_)[1L])
    if (!is.finite(n_s1)) {
      n_s1 <- tryCatch({
        d0 <- NULL
        for (nm in c("imputed", "locked", "cleaned")) {
          if (is.data.frame(ctx$data[[nm]])) { d0 <- ctx$data[[nm]]; break }
        }
        if (is.data.frame(d0)) nrow(d0) else NA_integer_
      }, error = function(e) NA_integer_)
    }
    n_s2 <- suppressWarnings(as.integer(ctx$results$ip_stage2$n_stage2 %||% NA_integer_)[1L])
    if (is.finite(n_s1)) n_total <- n_s1
    n_by_db <- list()
    if (is.finite(n_s1)) n_by_db$MIMIC_stage1 <- n_s1
    if (is.finite(n_s2)) n_by_db$MIMIC_stage2_AKI <- n_s2
    if (!length(n_by_db)) n_by_db <- NULL
  }
  st_path <- file.path(index_root, "_batch_status.json")
  if (file.exists(st_path) && requireNamespace("jsonlite", quietly = TRUE)) {
    st <- tryCatch(jsonlite::fromJSON(st_path), error = function(e) NULL)
    if (!is.null(st)) {
      if (is.null(n_total)) n_total <- st$n_before %||% st$n_after %||% st$n %||% NULL
      if (is.null(n_by_db)) {
        n_by_db <- list(MIMIC = n_total)
        if (!is.null(st$n_stage2)) n_by_db$MIMIC_stage2_AKI <- st$n_stage2
      }
    }
  }

  if (exists("export_pub_figures", mode = "function") ||
      file.exists(file.path(root, "R/pub_figure_export.R"))) {
    if (!exists("export_pub_figures", mode = "function")) {
      tryCatch(source(file.path(root, "R/pub_figure_export.R"), local = FALSE),
               error = function(e) NULL)
    }
    figs <- file.path(index_root, "Figures")
    if (exists("export_pub_figures", mode = "function") && dir.exists(figs)) {
      tryCatch(
        export_pub_figures(figs, meta = list(
          exposure = ix,
          outcome = "AKI / 28-day mortality",
          n_total = n_total,
          n_by_db = n_by_db,
          databases = "MIMIC",
          combined = FALSE,
          infer_outcome_from_stem = TRUE
        ), config = config),
        error = function(e) cli::cli_alert_warning("发表图导出跳过: {e$message}")
      )
    }
  }

  if (!exists("index_code_bundle_finalize", mode = "function")) {
    cb <- file.path(root, "R/index_code_bundle.R")
    if (file.exists(cb)) {
      tryCatch(source(cb, local = FALSE), error = function(e) NULL)
    }
  }
  if (exists("index_code_bundle_finalize", mode = "function")) {
    tryCatch(
      index_code_bundle_finalize(root, config, ix, "mimic", index_root),
      error = function(e) cli::cli_alert_warning("指标 code 包生成失败: {e$message}")
    )
  }
  invisible(index_root)
}

ip_two_stage_run_shared_layer <- function(root, config, pipeline_shared) {
  bc <- ip_two_stage_batch_cfg(config)
  result_root <- ip_two_stage_assert_result_root(config, root)
  ck_dir <- as.character((pipeline_shared$checkpoint %||% list())$dir %||%
    ip_two_stage_shared_ck_dir(config))[1L]
  if (!dir.exists(ck_dir)) dir.create(ck_dir, recursive = TRUE)

  cfg <- config
  cfg$project$root <- root
  cfg$project$output_dir <- file.path(result_root, "_shared")
  cfg$dual_db$enable <- FALSE
  # 共享层不按缺失删列（与 incidence dual-batch 一致），否则 NLR/Albumin 等成分
  # 在小队列上被 30% 阈值提前踢掉，index 全 skip。列缺失交给 imputation(0.4)。
  cfg$data_clean$missing_threshold <- 1.0
  # 共享层尚无单一 index_var；只排除 disease_vars，不删已算指标列
  cfg$analysis_exclusion$allow_no_index <- TRUE
  cfg$analysis_exclusion$exclude_other_composite_indices <- FALSE
  # 已算指标列（如 NLR 缺 66%）不得被 imputation 按 0.4 阈值删掉
  cfg$imputation$force_keep_columns <- unique(c(
    as.character(cfg$imputation$force_keep_columns %||% character(0)),
    as.character((cfg$index %||% list())$only %||% character(0)),
    tryCatch(ip_two_stage_resolve_index_vars(cfg), error = function(e) character(0))
  ))
  # 共享层含插补：保留 Table S1 / 缺失图（写到 _shared，finalize 再镜像）
  pl <- pipeline_shared
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir <- ck_dir
  pl$dual_db <- list(enable = FALSE)

  cli::cli_h2("共享层 Stage0 — {paste(pl$blocks, collapse = ' → ')}")
  cli::cli_alert_info("checkpoint: {.file {ck_dir}}")
  cli::cli_alert_info("output: {.file {cfg$project$output_dir}}")
  run_pipeline(root, config = cfg, pipeline = pl)
  ip_two_stage_ensure_index_alias(ck_dir)
  alias <- file.path(ck_dir, "index.rds")
  if (file.exists(alias) && exists("pipeline_patch_checkpoint_outcome_group", mode = "function")) {
    tryCatch(
      pipeline_patch_checkpoint_outcome_group(alias, cfg),
      error = function(e) NULL
    )
  }
  invisible(ck_dir)
}

#' 主入口：共享层 + 按指标派发 worker
ip_two_stage_batch_run <- function(root, config,
                                   pipeline_shared,
                                   pipeline_stage1,
                                   pipeline_stage2,
                                   pipeline_regular_batch = NULL,
                                   run_opts = list(),
                                   config_path = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  config <- ip_two_stage_sync_batch_cfg(config)
  bc <- ip_two_stage_batch_cfg(config)
  result_root <- ip_two_stage_assert_result_root(config, root)

  shared_only <- isTRUE(run_opts$shared_only)
  only_index <- run_opts$only_index %||% NULL
  workers_raw <- run_opts$workers %||% bc$parallel_workers
  auto_workers <- is.null(workers_raw) ||
    identical(tolower(trimws(as.character(workers_raw))), "auto")
  workers <- if (!auto_workers) max(1L, as.integer(workers_raw)) else NA_integer_
  skip_exist <- isTRUE(run_opts$skip_existing %||% bc$skip_existing %||% TRUE)
  from_token <- run_opts$from %||% NULL
  to_token <- run_opts$to %||% NULL
  if ((!is.null(from_token) && nzchar(as.character(from_token)[1L])) ||
      (!is.null(to_token) && nzchar(as.character(to_token)[1L]))) {
    skip_exist <- FALSE
    cli::cli_alert_info(
      "续跑范围: from={from_token %||% '(start)'} → to={to_token %||% '(end)'}"
    )
  }

  candidate_vars <- ip_two_stage_resolve_index_vars(config)
  cli::cli_h1("SLE→AKI two-stage batch — 候选 {length(candidate_vars)} 个指标")
  cli::cli_alert_info(
    "single-db MIMIC | workers={if (auto_workers) 'auto' else workers} | skip_existing={skip_exist}"
  )
  cli::cli_alert_info("结果根: {.file {result_root}}")

  shared_ck <- ip_two_stage_shared_ck_dir(config)
  have_shared <- ip_two_stage_shared_complete(shared_ck)
  from_is_shared <- FALSE
  if (!is.null(from_token) && nzchar(as.character(from_token)[1L])) {
    plan0 <- ip_two_stage_plan_worker_phases(
      pipeline_stage1$blocks, pipeline_stage2$blocks, from_token, to_token
    )
    from_is_shared <- identical(plan0$from_phase, "shared")
  }

  run_shared <- (!have_shared || !skip_exist || from_is_shared) &&
    (is.null(from_token) || from_is_shared || !have_shared)
  if (have_shared && isTRUE(skip_exist) && !from_is_shared) {
    cli::cli_alert_info("共享层已存在，跳过: {.file {shared_ck}}")
  } else if (isTRUE(run_shared) || !have_shared) {
    ip_two_stage_run_shared_layer(root, config, pipeline_shared)
  }

  if (shared_only) {
    avail <- tryCatch(
      ip_two_stage_resolve_from_shared_ck(config, candidate_vars),
      error = function(e) {
        cli::cli_alert_warning(e$message)
        candidate_vars
      }
    )
    cli::cli_alert_success("--shared-only 完成，实际可用指标: {length(avail)} 个")
    return(invisible(avail))
  }

  if (!ip_two_stage_shared_complete(ip_two_stage_shared_ck_dir(config))) {
    stop("共享层检查点不完整（缺 imputation.rds），请先 --shared-only 或 --no-skip",
         call. = FALSE)
  }

  cli::cli_h2("从共享层筛查实际可用指标")
  index_vars <- tryCatch(
    ip_two_stage_resolve_from_shared_ck(config, candidate_vars),
    error = function(e) {
      cli::cli_alert_warning("读取 checkpoint 失败: {e$message}，使用候选全量")
      candidate_vars
    }
  )
  index_vars <- incidence_batch_filter_disease_derived_indices(config, index_vars)
  cli::cli_alert_success("最终批量指标: {length(index_vars)} 个")

  effective_n <- if (!is.null(only_index)) length(intersect(index_vars, only_index))
  else length(index_vars)
  if (auto_workers) {
    workers <- incidence_batch_auto_workers(
      n_indices       = effective_n,
      ram_per_worker  = bc$ram_per_worker_gb %||% 2.0,
      cpu_headroom    = bc$cpu_headroom %||% 2L,
      ram_headroom_gb = bc$ram_headroom_gb %||% 4.0,
      max_workers     = bc$max_workers %||% NULL
    )
  } else {
    cli::cli_alert_info("Worker 数: {workers}（手动指定）| 指标数: {effective_n}")
  }

  if (is.null(bc$worker_wait_sec)) {
    config$incidence_batch$worker_wait_sec <- 21600
    config$ip_two_stage_batch$worker_wait_sec <- 21600
  }

  incidence_batch_dispatch_workers(
    root          = root,
    config        = config,
    index_vars    = index_vars,
    workers       = workers,
    log_dir       = file.path(result_root, "logs"),
    db_mode       = "mimic",
    only          = only_index,
    skip_existing = skip_exist,
    p_trim        = 0,
    config_path   = config_path,
    worker_script = "run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch_worker.R",
    from_token    = from_token,
    to_token      = to_token
  )

  statuses <- incidence_batch_read_all_status(result_root, index_vars)
  incidence_batch_print_summary(statuses)
  out_dir <- file.path(result_root, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Batch_summary_all_indices.csv")
  tryCatch(
    utils::write.csv(statuses, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("汇总 CSV 写入失败: {e$message}")
  )
  cli::cli_alert_success("汇总表: {.file {csv_path}}")

  # ── 敏感性分析（success 后自动；config$incidence_batch$sensitivity_suite$enable）──
  if (!shared_only) {
    sens <- (config$incidence_batch %||% list())$sensitivity_suite %||% list()
    if (isTRUE(sens$enable) && exists("incidence_sensitivity_pass", mode = "function")) {
      success_ix <- as.character(statuses$index[statuses$status == "success"])
      success_ix <- success_ix[nzchar(success_ix)]
      if (!is.null(only_index) && length(only_index)) {
        success_ix <- intersect(success_ix, only_index)
      }
      if (length(success_ix)) {
        tryCatch(
          incidence_sensitivity_pass(
            root, config, success_ix, config_path,
            only_index = only_index,
            worker_script = "run/sle_aki_inc_prog/run_sle_aki_inc_prog_batch_worker.R",
            force = !skip_exist
          ),
          error = function(e) cli::cli_alert_warning("敏感性分析阶段出错: {e$message}")
        )
      }
    }
  }

  invisible(statuses)
}
