###############################################################################
#  environment_subgroup_search — 全队列 GLM 后 VOC 不足时，尝试亚组并重跑至 GLM
#
#  register_block: "environment_subgroup_search"
#  位置: glm_environment_quartile 之后；全队列 GLM 不足时先尝试亚组，再尝试极端值剔除
###############################################################################

block_environment_subgroup_search <- function(ctx, ...) {
  cfg <- ctx$config
  bl  <- cfg$environment_subgroup_search %||% list()
  if (!isTRUE(bl$enable %||% TRUE)) {
    cli::cli_alert_info("environment_subgroup_search: enable=FALSE，跳过。")
    return(ctx)
  }

  root <- cfg$project$root %||% getwd()
  helper <- file.path(root, "R", "environment_voc_recovery_utils.R")
  if (file.exists(helper)) source(helper, local = FALSE)

  min_target <- environment_recovery_min_glm_vocs(cfg)
  min_n <- as.integer(bl$min_subgroup_n %||% 80L)[1L]
  force_id <- as.character(bl$force_filter_id %||% "")[1L]
  if (!length(force_id) || !nzchar(force_id)) force_id <- ""

  cnt0 <- environment_count_glm_final_vocs(ctx)

  raw_base <- ctx$data$raw
  if (is.null(raw_base) || !nrow(raw_base)) {
    stop("environment_subgroup_search: ctx$data$raw 为空。", call. = FALSE)
  }
  ctx <- environment_ensure_raw_snapshot(ctx)
  raw_base <- ctx$results$environment_raw_snapshot %||% raw_base

  if (nzchar(force_id)) {
    filters_all <- environment_default_subgroup_filters(cfg)
    force_filter <- Filter(function(f) identical(f$id, force_id), filters_all)
    if (!length(force_filter)) {
      stop("environment_subgroup_search: force_filter_id 无效: ", force_id, call. = FALSE)
    }
    force_filter <- force_filter[[1L]]
    sub_raw <- environment_apply_subgroup_filter(raw_base, force_filter)
    if (nrow(sub_raw) < min_n) {
      stop(
        "environment_subgroup_search: 强制亚组 ", force_filter$label,
        " 样本量 ", nrow(sub_raw), " < min_subgroup_n=", min_n,
        call. = FALSE
      )
    }
    recovery_root <- file.path(environment_recovery_base(ctx), "subgroup_search")
    selected_dir <- file.path(recovery_root, paste0("_selected_", force_id))
    cli::cli_h2(
      "environment_subgroup_search: 强制亚组 {force_filter$label}（n={nrow(sub_raw)}）→ 重跑至 GLM"
    )
    trial <- environment_trial_glm_voc_count(
      sub_raw, ctx, root,
      trial_output_dir = selected_dir,
      trial_meta = list(
        kind = "subgroup_search_forced",
        subgroup_id = force_id,
        subgroup_label = force_filter$label
      )
    )
    ctx <- trial$ctx
    cnt1 <- environment_count_glm_final_vocs(ctx)
    ctx$results$environment_active_subgroup <- force_id
    ctx$results$environment_active_subgroup_label <- force_filter$label
    ctx$results$environment_subgroup_search_best <- list(
      id = force_id,
      label = force_filter$label,
      n = cnt1$n,
      n_sample = nrow(sub_raw),
      vocs = cnt1$vocs
    )
    ctx$config$environment_subgroup_search$active_filter <- force_id
    return(ctx)
  }

  if (cnt0$n >= min_target) {
    cli::cli_alert_success(
      "environment_subgroup_search: 全队列 GLM 已有 {cnt0$n} 个 VOC（≥{min_target}），跳过亚组 recovery。"
    )
    return(ctx)
  }

  filters <- environment_default_subgroup_filters(cfg)
  filters <- filters[vapply(filters, function(f) {
    d <- environment_apply_subgroup_filter(raw_base, f)
    nrow(d) >= min_n
  }, logical(1L))]

  if (!length(filters)) {
    cli::cli_alert_warning("environment_subgroup_search: 无满足 min_subgroup_n 的亚组定义。")
    return(ctx)
  }

  cli::cli_h2(
    "environment_subgroup_search: 全队列 GLM 仅 {cnt0$n} 个 VOC（目标 ≥{min_target}），尝试 {length(filters)} 个亚组"
  )

  parallel_ok <- isTRUE(bl$use_parallel %||% FALSE) &&
    .Platform$OS.type != "windows" &&
    length(filters) > 1L
  n_workers <- min(
    length(filters),
    as.integer(bl$max_workers %||% max(1L, parallel::detectCores(logical = TRUE) - 1L))
  )

  recovery_root <- file.path(environment_recovery_base(ctx), "subgroup_search")
  dir.create(recovery_root, recursive = TRUE, showWarnings = FALSE)

  .run_one <- function(f) {
    sub_raw <- environment_apply_subgroup_filter(raw_base, f)
    if (nrow(sub_raw) < min_n) {
      return(list(
        id = f$id, label = f$label, n = 0L, n_sample = nrow(sub_raw),
        vocs = character(0), trial_dir = NA_character_, status = "too_small"
      ))
    }
    trial_dir <- file.path(recovery_root, f$id)
    tr <- environment_trial_glm_voc_count(
      sub_raw, ctx, root,
      trial_output_dir = trial_dir,
      trial_meta = list(kind = "subgroup_search", subgroup_id = f$id, subgroup_label = f$label)
    )
    list(
      id = f$id, label = f$label, n = tr$n, n_sample = nrow(sub_raw),
      vocs = tr$vocs, trial_dir = trial_dir, status = tr$status %||% "ok",
      trial_ctx = tr$ctx
    )
  }

  results <- if (parallel_ok && n_workers > 1L) {
    cli::cli_alert_info("亚组并行: {n_workers} workers × {length(filters)} 组")
    res <- tryCatch(
      parallel::mclapply(filters, .run_one, mc.cores = n_workers),
      error = function(e) NULL
    )
    ok <- is.list(res) && length(res) == length(filters) &&
      all(vapply(res, function(r) is.list(r) && "label" %in% names(r), logical(1L)))
    if (!ok) {
      cli::cli_alert_warning("亚组并行失败，回退顺序执行。")
      lapply(filters, .run_one)
    } else {
      res
    }
  } else {
    lapply(filters, .run_one)
  }

  tab <- do.call(rbind, lapply(results, function(r) {
    data.frame(
      Subgroup = r$label, ID = r$id, N = r$n_sample,
      GLM_Final_VOCs = r$n, Passed_VOCs = paste(r$vocs, collapse = "; "),
      Status = r$status %||% NA_character_,
      Trial_Dir = r$trial_dir %||% NA_character_,
      stringsAsFactors = FALSE
    )
  }))
  tab <- tab[order(-tab$GLM_Final_VOCs, -tab$N), , drop = FALSE]

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir %||% ".", "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  out_csv <- file.path(tbl_dir, as.character(bl$table_filename %||% "Table_Environment_Subgroup_Search.csv"))
  tryCatch(utils::write.csv(tab, out_csv, row.names = FALSE, fileEncoding = "UTF-8"), error = function(e) NULL)

  best_idx <- which.max(vapply(results, function(r) r$n, numeric(1)))
  best <- results[[best_idx]]
  if (best$n <= cnt0$n) {
    cli::cli_alert_warning(
      "environment_subgroup_search: 最佳亚组 {best$label} GLM 仅 {best$n} 个 VOC，不优于全队列 {cnt0$n}，保留全队列结果。"
    )
    ctx$results$environment_subgroup_search_best <- best
    return(ctx)
  }

  cli::cli_alert_success(
    "environment_subgroup_search: 选用 {best$label}（n={best$n_sample}, GLM VOC={best$n}）"
  )
  ctx <- best$trial_ctx
  ctx$results$environment_active_subgroup <- best$id
  ctx$results$environment_active_subgroup_label <- best$label
  ctx$results$environment_subgroup_search_best <- best[c("id", "label", "n", "n_sample", "vocs")]
  ctx$config$environment_subgroup_search$active_filter <- best$id
  ctx
}

register_block(
  "environment_subgroup_search",
  block_environment_subgroup_search,
  "全队列 GLM 不足时搜索亚组并重跑至 GLM"
)
