###############################################################################
#  competing_index_exposure — 任意复合指标的基线值 + 四分位 + 28天长表
#
#  泛化版 competing_tyg_compute：由 by_index batch 派发时，
#  ctx$config$competing_risk$index_var 指定当前循环到的指标名（如 "TyG"/"NLR"/...）。
#  数据源：data/mimic/12_{Index}.RData（trajectory_calc_28d_index 共享层产出，
#  对象 index_df，列 subject_id + {Index}_1..{Index}_28）。
#
#  config$competing_risk 新增字段：
#    index_var        — 当前指标名（batch 派发时由 study_batch_patch_config_for_unit 写入）
#    index_data_dir   — 12_{Index}.RData 所在目录
#    index_visit_days — 参与轨迹拟合的天数范围，默认 1:28
#
#  写: {Index}（首个非缺失日基线值）、{Index}_quartile（Q1~Q4）。
#  轨迹分类由 trim 后的 competing_trajectory_cluster 单独完成。
#  设置 ctx$config$competing_risk$exposure_var / trajectory_var / index_var（若未显式配置）
#  ctx$results$competing_index_long — 长表（供 competing_lmm_trajectory 复用）
###############################################################################

block_competing_index_exposure <- function(ctx, ...) {
  bl <- ctx$config$competing_risk %||% list()
  index_var <- as.character(bl$index_var %||% bl$tyg_var %||% "TyG")[1L]
  data <- ctx$data$cleaned %||% ctx$data$raw %||% ctx$data$imputed
  if (is.null(data)) stop("competing_index_exposure: 无数据", call. = FALSE)

  id_col <- ctx$config$data$id_column %||% "ID"
  if (!id_col %in% names(data)) {
    alt <- intersect(c("ID", "subject_id"), names(data))
    if (!length(alt)) stop("competing_index_exposure: 主表缺少 ID 列 ", id_col, call. = FALSE)
    id_col <- alt[1L]
  }

  data_dir <- bl$index_data_dir %||% NULL
  rdata_path <- if (!is.null(data_dir)) file.path(data_dir, paste0("12_", index_var, ".RData")) else NULL

  wide <- NULL
  if (!is.null(rdata_path) && file.exists(rdata_path)) {
    env <- new.env()
    load(rdata_path, envir = env)
    obj_name <- if (exists("index_df", envir = env, inherits = FALSE)) "index_df" else ls(env)[1L]
    wide <- get(obj_name, envir = env)
  }
  if (is.null(wide) || !is.data.frame(wide) || !nrow(wide)) {
    stop(
      "INDEX_NO_DATA_STOP: 指标 ", index_var, " 逐日数据为空或不存在（",
      rdata_path %||% "未配置 index_data_dir", "），终止该指标 pipeline。",
      call. = FALSE
    )
  }

  day_cols <- grep(paste0("^", index_var, "_\\d+$"), names(wide), value = TRUE)
  if (!length(day_cols)) stop("competing_index_exposure: ", rdata_path, " 中找不到 ", index_var, "_<day> 列", call. = FALSE)
  day_num <- as.integer(sub(paste0("^", index_var, "_"), "", day_cols))
  ord <- order(day_num)
  day_cols <- day_cols[ord]; day_num <- day_num[ord]

  visit_days <- bl$index_visit_days %||% seq_len(28L)
  keep <- day_num %in% visit_days
  day_cols <- day_cols[keep]; day_num <- day_num[keep]

  wide[[id_col]] <- as.character(wide[[id_col]] %||% wide$subject_id %||% wide$ID)
  if (!id_col %in% names(wide) || all(is.na(wide[[id_col]]))) {
    if ("subject_id" %in% names(wide)) wide[[id_col]] <- as.character(wide$subject_id)
    else if ("ID" %in% names(wide)) wide[[id_col]] <- as.character(wide$ID)
  }
  mat <- as.matrix(wide[, day_cols, drop = FALSE])
  mat <- suppressWarnings(matrix(as.numeric(mat), nrow = nrow(wide), ncol = ncol(mat)))

  # 轨迹防泄漏：结局发生日及之后的化验置 NA（仅影响长表/轨迹，不影响基线四分位）
  if (isTRUE(bl$trajectory_censor_at_event %||% FALSE)) {
    time_var <- as.character(bl$time_var %||% "competing_time_28d")[1L]
    event_col <- as.character(bl$event_type_col %||% "competing_status_28d")[1L]
    if (time_var %in% names(data) && id_col %in% names(data)) {
      ev <- data.frame(
        id = as.character(data[[id_col]]),
        t = suppressWarnings(as.numeric(data[[time_var]])),
        stringsAsFactors = FALSE
      )
      ev <- ev[!duplicated(ev$id), , drop = FALSE]
      idx <- match(as.character(wide[[id_col]]), ev$id)
      t_ev <- ev$t[idx]
      for (i in seq_len(nrow(mat))) {
        ti <- t_ev[i]
        if (!is.finite(ti)) next
        # 仅保留结局前的观测（day < event day）；当天及之后剔除
        mat[i, day_num >= ti] <- NA_real_
      }
      cli::cli_alert_info(
        "trajectory_censor_at_event: 已按 {time_var} 截断逐日 {index_var}（防信息泄漏）"
      )
    }
  }

  baseline_val <- vapply(seq_len(nrow(mat)), function(i) {
    w <- which(!is.na(mat[i, ]))
    if (length(w)) mat[i, w[1L]] else NA_real_
  }, numeric(1))

  slope <- vapply(seq_len(nrow(mat)), function(i) {
    y <- mat[i, ]; x <- day_num
    ok <- !is.na(y)
    if (sum(ok) < 2L) return(NA_real_)
    unname(coef(lm(y[ok] ~ x[ok]))[2])
  }, numeric(1))

  exp_df <- data.frame(
    id_tmp = wide[[id_col]],
    value = baseline_val,
    slope = slope,
    stringsAsFactors = FALSE
  )
  names(exp_df)[1] <- id_col
  names(exp_df)[2] <- index_var

  min_n_index <- as.integer(bl$min_n_index %||% 20L)[1L]
  n_baseline_ok <- sum(!is.na(exp_df[[index_var]]))
  if (n_baseline_ok < min_n_index) {
    stop(
      "INDEX_MIN_N_STOP: 指标 ", index_var, " 基线非缺失样本量 ", n_baseline_ok,
      " < 阈值 ", min_n_index, "，终止该指标 pipeline。",
      call. = FALSE
    )
  }

  q <- stats::quantile(exp_df[[index_var]], probs = 0:4 / 4, na.rm = TRUE, type = 7)
  if (length(unique(q)) < 5L) {
    exp_df[[paste0(index_var, "_quartile")]] <- NA_character_
  } else {
    exp_df[[paste0(index_var, "_quartile")]] <- as.character(cut(
      exp_df[[index_var]], breaks = q, include.lowest = TRUE, labels = paste0("Q", 1:4)
    ))
  }

  # 长表（供 LMM / Fig6）
  long <- data.frame(
    id_tmp = rep(wide[[id_col]], length(day_cols)),
    day = rep(day_num, each = nrow(wide)),
    value = as.vector(mat),
    stringsAsFactors = FALSE
  )
  names(long)[1] <- id_col
  long <- long[!is.na(long$value), , drop = FALSE]

  # 轨迹列先占位；必须等 analysis_exclusion + trim 后再拟合 LMM/mclust，
  # 避免已裁剪的极端样本影响聚类参数。
  traj_col <- paste0(index_var, "_trajectory")
  exp_df[[traj_col]] <- NA_character_
  exp_df$slope <- NULL

  data[[id_col]] <- as.character(data[[id_col]])
  n_before <- nrow(data)
  chk <- merge(data, exp_df, by = id_col, all.x = TRUE, sort = FALSE)
  if (nrow(chk) != n_before) stop("competing_index_exposure: 合并后行数变化，请检查 ID 重复", call. = FALSE)

  for (slot in c("cleaned", "raw", "imputed")) {
    if (!is.null(ctx$data[[slot]])) {
      d <- ctx$data[[slot]]
      d[[id_col]] <- as.character(d[[id_col]])
      keep_cols <- setdiff(names(exp_df), id_col)
      d[keep_cols] <- NULL
      d <- merge(d, exp_df, by = id_col, all.x = TRUE, sort = FALSE)
      ctx$data[[slot]] <- d
    }
  }

  bl$index_var       <- index_var
  bl$exposure_var    <- paste0(index_var, "_quartile")
  bl$trajectory_var  <- paste0(index_var, "_trajectory")
  bl$tyg_var         <- index_var
  ctx$config$competing_risk <- bl

  ctx$results$competing_index_long <- list(index_var = index_var, id_col = id_col, long = long)
  ctx$results$competing_index_exposure <- list(
    index_var = index_var, n = sum(!is.na(exp_df[[index_var]])),
    n_quartile_ok = sum(!is.na(exp_df[[paste0(index_var, "_quartile")]])),
    n_trajectory_ok = 0L,
    trajectory = NULL
  )
  cli::cli_alert_success(
    "指标暴露计算完成: {index_var}（基线非缺失 {sum(!is.na(exp_df[[index_var]]))} / {nrow(exp_df)}）"
  )
  ctx
}

register_block("competing_index_exposure", block_competing_index_exposure, "任意指标基线/四分位与轨迹长表")
