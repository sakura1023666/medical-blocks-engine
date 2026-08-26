###############################################################################
#  骨质疏松删人副本 — 两阶段编排：
#    BKMR iter=100 筛查 → RCS 不显著 VOC 永久剔除 → BKMR iter=5000 从头重跑
#    LASSO 参数不变（由 config$lasso_environment 控制）
###############################################################################

environment_fuben_project_root <- function(config) {
  bc <- config$environment_batch %||% list()
  normalizePath(
    bc$output_base %||% config$project$output_dir,
    winslash = "/", mustWork = TRUE
  )
}

environment_fuben_orchestrator_state_path <- function(config) {
  file.path(environment_fuben_project_root(config), "orchestrator_state.json")
}

environment_fuben_read_orchestrator_state <- function(config) {
  path <- environment_fuben_orchestrator_state_path(config)
  if (!file.exists(path)) return(list())
  tryCatch(jsonlite::fromJSON(path, simplifyVector = TRUE), error = function(e) list())
}

environment_fuben_write_orchestrator_state <- function(config, state) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) return(invisible(NULL))
  path <- environment_fuben_orchestrator_state_path(config)
  jsonlite::write_json(state, path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}

environment_fuben_clean_outputs <- function(config, keep_logs = TRUE) {
  root <- environment_fuben_project_root(config)
  rel_dirs <- c(
    "checkpoints", "_shared", "by_voc", "_tail",
    "Tables", "Figures", "Results_Summary", "recovery"
  )
  for (d in rel_dirs) {
    p <- file.path(root, d)
    if (dir.exists(p)) {
      unlink(p, recursive = TRUE, force = TRUE)
      cli::cli_alert_info("已删除目录: {.file {d}}")
    }
  }
  cache_slug <- gsub("[^A-Za-z0-9._-]+", "_", basename(root))
  cache_log <- file.path(
    normalizePath(config$environment_batch$project_root %||% getwd(), winslash = "/"),
    ".cache", "environment_voc_batch_logs", cache_slug
  )
  if (dir.exists(cache_log)) {
    unlink(cache_log, recursive = TRUE, force = TRUE)
    cli::cli_alert_info("已删除 worker 日志缓存")
  }
  if (!isTRUE(keep_logs)) {
    log_dir <- file.path(root, "logs")
    if (dir.exists(log_dir)) {
      unlink(list.files(log_dir, full.names = TRUE), force = TRUE)
      cli::cli_alert_info("已清空 logs/")
    }
  }
  invisible(root)
}

environment_fuben_apply_bkmr_iter <- function(config, bkmr_iter) {
  bkmr_iter <- as.integer(bkmr_iter)[1L]
  if (!is.finite(bkmr_iter) || bkmr_iter < 1L) {
    stop("bkmr_iter 须为正整数", call. = FALSE)
  }
  if (is.null(config$bkmr_fit)) config$bkmr_fit <- list()
  config$bkmr_fit$auto_iter <- FALSE
  config$bkmr_fit$iter      <- bkmr_iter
  config
}

environment_fuben_apply_voc_excludes <- function(config, extra_exclude = character(0)) {
  extra_exclude <- unique(as.character(extra_exclude[nzchar(extra_exclude)]))
  if (!length(extra_exclude)) return(config)

  # 同时写入 prepare / environment / lasso / batch，避免仅写 prepare 时
  # nhanes 合并路径或 allowlist 未吃到排除（曾导致 HP2MA 阶段2仍进 LASSO/WQS/BKMR）
  prep <- config$environment_prepare %||% list()
  fixed <- unique(c(
    as.character(prep$voc_exclude_fixed %||% character(0)),
    extra_exclude
  ))
  config$environment_prepare$voc_exclude_fixed <- fixed

  if (is.null(config$environment)) config$environment <- list()
  config$environment$voc_exclude_fixed <- unique(c(
    as.character(config$environment$voc_exclude_fixed %||% character(0)),
    fixed
  ))

  if (is.null(config$lasso_environment)) config$lasso_environment <- list()
  config$lasso_environment$exclude_vars <- unique(c(
    as.character(config$lasso_environment$exclude_vars %||% character(0)),
    extra_exclude
  ))

  bc <- config$environment_batch %||% list()
  bc$rcs_dropped_vocs <- unique(c(
    as.character(bc$rcs_dropped_vocs %||% character(0)),
    extra_exclude
  ))
  config$environment_batch <- bc

  cli::cli_alert_warning(
    "永久剔除 VOC（从头排除）: {paste(extra_exclude, collapse = ', ')}"
  )
  config
}

environment_batch_rcs_nonsignificant_vocs <- function(config,
                                                       p_threshold = NULL,
                                                       model = "model2") {
  bc <- config$environment_batch %||% list()
  rn <- config$rcs_nhanes %||% list()
  p_threshold <- as.numeric(p_threshold %||% rn$p_threshold %||% 0.05)[1L]
  model <- tolower(as.character(model)[1L])
  root <- environment_fuben_project_root(config)
  by_voc <- file.path(root, "by_voc")
  if (!dir.exists(by_voc)) return(character(0))

  bad <- character(0)
  rows <- list()
  for (voc in list.dirs(by_voc, recursive = FALSE, full.names = FALSE)) {
    ck <- file.path(by_voc, voc, "checkpoints", "rcs_nhanes.rds")
    if (!file.exists(ck)) {
      bad <- c(bad, voc)
      rows[[length(rows) + 1L]] <- data.frame(
        VOC = voc, P_overall = NA_real_, Significant = FALSE,
        Note = "missing_rcs_checkpoint", stringsAsFactors = FALSE
      )
      next
    }
    obj <- tryCatch(readRDS(ck), error = function(e) NULL)
    r <- obj$ctx$results$nhanes_rcs %||% list()
    res <- switch(model,
      model2 = r$model2,
      model1 = r$model1,
      crude  = r$crude,
      r$model2
    )
    po <- if (!is.null(res)) as.numeric(res$p_overall)[1L] else NA_real_
    sig <- is.finite(po) && po < p_threshold
    if (!sig) bad <- c(bad, voc)
    rows[[length(rows) + 1L]] <- data.frame(
      VOC = voc,
      P_overall = po,
      Significant = sig,
      Note = if (sig) "pass" else "rcs_nonsignificant",
      stringsAsFactors = FALSE
    )
  }
  log_dir <- file.path(root, "logs")
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)
  if (length(rows)) {
    log_df <- do.call(rbind, rows)
    utils::write.csv(
      log_df,
      file.path(log_dir, "rcs_significance_screen.csv"),
      row.names = FALSE
    )
  }
  unique(bad[nzchar(bad)])
}

run_environment_fuben_orchestrated <- function(root, config,
                                                pipeline_shared,
                                                pipeline_voc_batch,
                                                pipeline_tail,
                                                config_path = NULL,
                                                phase = "auto",
                                                workers = "auto") {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("需要 jsonlite 包", call. = FALSE)
  }
  bc <- config$environment_batch %||% list()
  orch <- bc$orchestrator %||% list()
  bkmr_screen <- as.integer(orch$bkmr_iter_screen %||% 100L)[1L]
  bkmr_final  <- as.integer(orch$bkmr_iter_final %||% 5000L)[1L]
  rcs_model   <- as.character(orch$rcs_significance_model %||% "model2")[1L]
  rcs_p       <- as.numeric(orch$rcs_p_threshold %||% config$rcs_nhanes$p_threshold %||% 0.05)[1L]
  lasso_cv    <- as.integer(config$lasso_environment$cv_times %||% 1000L)[1L]

  phase <- tolower(as.character(phase)[1L])
  state <- environment_fuben_read_orchestrator_state(config)

  run_one <- function(label, bkmr_iter, extra_exclude = character(0)) {
    cli::cli_h1("{label} — BKMR iter={bkmr_iter}（LASSO cv_times={lasso_cv} 不变）")
    cfg <- environment_fuben_apply_bkmr_iter(config, bkmr_iter)
    if (length(extra_exclude)) {
      cfg <- environment_fuben_apply_voc_excludes(cfg, extra_exclude)
    }
    environment_fuben_clean_outputs(cfg, keep_logs = TRUE)
    run_environment_voc_batch(
      root               = root,
      config             = cfg,
      pipeline_shared    = pipeline_shared,
      pipeline_voc_batch = pipeline_voc_batch,
      pipeline_tail      = pipeline_tail,
      run_opts = list(
        skip_existing = FALSE,
        workers       = workers
      ),
      config_path = config_path
    )
    bad <- environment_batch_rcs_nonsignificant_vocs(cfg, p_threshold = rcs_p, model = rcs_model)
    list(config = cfg, rcs_nonsignificant = bad)
  }

  if (phase %in% c("clean", "clean-only")) {
    environment_fuben_clean_outputs(config, keep_logs = FALSE)
    environment_fuben_write_orchestrator_state(config, list(status = "cleaned"))
    return(invisible(list(status = "cleaned")))
  }

  if (phase %in% c("1", "screen", "phase1")) {
    res <- run_one("阶段 1（BKMR 筛查）", bkmr_screen)
    environment_fuben_write_orchestrator_state(config, list(
      status = "phase1_done",
      bkmr_iter = bkmr_screen,
      rcs_nonsignificant = res$rcs_nonsignificant,
      rcs_dropped = res$rcs_nonsignificant
    ))
    return(invisible(res))
  }

  if (phase %in% c("2", "final", "phase2")) {
    dropped <- as.character(
      state$rcs_nonsignificant %||%
        state$rcs_dropped %||%
        bc$rcs_dropped_vocs %||%
        character(0)
    )
    # jsonlite 可能把单元素向量解成标量字符串
    dropped <- unique(as.character(unlist(dropped, use.names = FALSE)))
    dropped <- dropped[nzchar(dropped)]
    if (!length(dropped)) {
      cli::cli_alert_warning("阶段 2 无 RCS 剔除 VOC；仍按 BKMR iter={bkmr_final} 全量重跑")
    } else {
      cli::cli_alert_info(
        "阶段 2 将永久剔除: {paste(dropped, collapse = ', ')}"
      )
    }
    res <- run_one("阶段 2（BKMR 终跑）", bkmr_final, extra_exclude = dropped)
    environment_fuben_write_orchestrator_state(config, list(
      status = "completed",
      bkmr_iter = bkmr_final,
      rcs_dropped = dropped,
      rcs_nonsignificant = dropped,
      phase2_rcs_nonsignificant = res$rcs_nonsignificant
    ))
    return(invisible(res))
  }

  cli::cli_h1(
    "自动两阶段编排（BKMR {bkmr_screen} → RCS {rcs_model} 筛查 → BKMR {bkmr_final} 从头终跑）"
  )
  res1 <- run_one("阶段 1（BKMR 筛查）", bkmr_screen)
  dropped <- res1$rcs_nonsignificant
  if (length(dropped)) {
    cli::cli_alert_warning(
      "RCS {rcs_model} 不显著 {length(dropped)} 个: {paste(dropped, collapse = ', ')}；阶段 2 将永久剔除后 BKMR iter={bkmr_final} 重跑"
    )
  } else {
    cli::cli_alert_success(
      "RCS {rcs_model} 全部显著（P<{rcs_p}）；阶段 2 仍按 BKMR iter={bkmr_final} 从头终跑"
    )
  }
  res2 <- run_one("阶段 2（BKMR 终跑）", bkmr_final, extra_exclude = dropped)
  environment_fuben_write_orchestrator_state(config, list(
    status = "completed",
    phase1_bkmr_iter = bkmr_screen,
    phase2_bkmr_iter = bkmr_final,
    rcs_dropped = dropped,
    rcs_nonsignificant = dropped,
    phase2_rcs_nonsignificant = res2$rcs_nonsignificant
  ))
  invisible(res2)
}
