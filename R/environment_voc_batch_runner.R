###############################################################################
#  environment_voc_batch_runner.R — DKD × 环境 VOC 批量编排（NHANES 单库）
#
#  流程:
#    1. 共享层（Step01–06 + Step11 描述性）跑 1 次 → _shared/main checkpoint
#    2. 从 select_vocs_final 解析 VOC 列表，并行派发 worker → 每 VOC 跑 rcs_nhanes（Step07）
#    3. 尾段（Step08–10）在主进程续跑：qgcomp → mediation → subgroup×N
#    4. 飞书同步（复用 incidence_batch_feishu_*）
###############################################################################

environment_batch_shared_ck_dir <- function(config) {
  bc <- config$environment_batch %||% list()
  base <- bc$shared_ck_base %||% file.path(
    bc$output_base %||% config$project$output_dir,
    "checkpoints", "_shared", "main"
  )
  if (!is_absolute_path(base)) file.path(getwd(), base) else base
}

environment_batch_voc_output_dir <- function(config, voc) {
  bc <- config$environment_batch %||% list()
  file.path(bc$output_base %||% config$project$output_dir, "by_voc", voc)
}

environment_batch_voc_ck_dir <- function(config, voc) {
  file.path(environment_batch_voc_output_dir(config, voc), "checkpoints")
}

environment_batch_resolve_voc_vars <- function(config) {
  bc <- config$environment_batch %||% list()
  vocs <- as.character(bc$voc_vars %||% character(0))
  vocs <- vocs[nzchar(vocs)]
  if (length(vocs)) return(unique(vocs))
  stop(
    "environment_batch$voc_vars 为空；请先跑共享层，或于 config 中指定 VOC 列名向量。",
    call. = FALSE
  )
}

environment_batch_sync_config_from_ctx <- function(config, ctx) {
  if (is.null(ctx)) return(config)
  ctx_vocs <- as.character(
    ctx$results$voc_columns %||%
      ctx$config$environment$voc_columns %||%
      character(0)
  )
  ctx_vocs <- unique(ctx_vocs[nzchar(ctx_vocs)])
  if (length(ctx_vocs)) {
    if (is.null(config$environment)) config$environment <- list()
    config$environment$voc_columns <- unique(c(
      as.character(config$environment$voc_columns %||% character(0)),
      ctx_vocs
    ))
  }
  idx_excl <- as.character(ctx$config$incidence$index_exclude_vars %||% character(0))
  idx_excl <- unique(idx_excl[nzchar(idx_excl)])
  if (length(idx_excl)) {
    config$incidence$index_exclude_vars <- unique(c(
      as.character(config$incidence$index_exclude_vars %||% character(0)),
      idx_excl
    ))
  }
  config
}

environment_batch_resolve_from_shared_ck <- function(config, candidate_vocs = NULL) {
  ck_dir <- environment_batch_shared_ck_dir(config)
  alias  <- file.path(ck_dir, "bkmr_analysis.rds")
  if (!file.exists(alias)) alias <- file.path(ck_dir, "index.rds")
  if (!file.exists(alias)) {
    stop("共享层检查点不存在: ", ck_dir, call. = FALSE)
  }
  obj <- tryCatch(readRDS(alias), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) {
    stop("无法读取共享检查点: ", alias, call. = FALSE)
  }
  config <- environment_batch_sync_config_from_ctx(config, obj$ctx)
  strict_glm <- if (exists("environment_strict_glm_vocs_enabled", mode = "function")) {
    environment_strict_glm_vocs_enabled(config, "glm_environment_quartile")
  } else {
    isTRUE((config$environment_batch %||% list())$strict_glm_vocs %||% TRUE)
  }
  final <- if (strict_glm && exists("environment_glm_passed_vocs", mode = "function")) {
    environment_glm_passed_vocs(obj$ctx)
  } else {
    as.character(
      obj$ctx$results$select_vocs_glm %||%
        obj$ctx$results$select_vocs_final %||%
        obj$ctx$results$select_vocs_wqs %||%
        obj$ctx$results$select_vocs %||%
        character(0)
    )
  }
  final <- unique(final[nzchar(final)])
  data <- obj$ctx$data$imputed %||% obj$ctx$data$cleaned
  if (exists("environment_intersect_voc_only", mode = "function")) {
    final <- environment_intersect_voc_only(final, data, config)
  }
  if (!strict_glm) {
    min_n <- if (exists("environment_min_mixture_n", mode = "function")) {
      environment_min_mixture_n(config, "glm_environment_quartile", 4L)
    } else 4L
    if (length(final) < min_n &&
        exists("environment_resolve_mixture_vocs", mode = "function")) {
      final <- environment_resolve_mixture_vocs(
        obj$ctx, data, config, "glm_environment_quartile"
      )$vocs
    }
  }
  if (!length(final)) {
    stop("共享层 checkpoint 中 GLM 通过 VOC 为空，无法派发 RCS worker。", call. = FALSE)
  }
  cli::cli_alert_success(
    "从共享层解析 VOC {length(final)} 个: {paste(final, collapse = ', ')}"
  )
  final
}

environment_batch_patch_config_for_voc <- function(config, voc) {
  voc <- as.character(voc)[1L]
  bc  <- config$environment_batch %||% list()
  glm_cfg <- config$glm_environment_quartile %||% list()

  config$incidence$index_var      <- voc
  config$logistic$index_var       <- voc
  config$nhanes$cutoff_index_var  <- voc
  config$prediction$index_vars    <- c(voc)

  extra_voc <- as.character(
    config$incidence$index_exclude_vars %||%
      bc$voc_exclude_vars %||%
      bc$voc_vars %||%
      character(0)
  )
  if (exists("pipeline_apply_index_exclude_patch", mode = "function")) {
    config <- pipeline_apply_index_exclude_patch(config, extra_voc)
  }

  if (!is.null(config$rcs_nhanes)) {
    config$rcs_nhanes$index_var <- voc
    if (!is.null(glm_cfg$model1_factors)) {
      config$rcs_nhanes$model1_factors <- as.character(glm_cfg$model1_factors)
    }
    if (!is.null(glm_cfg$model2_factors)) {
      config$rcs_nhanes$model2_factors <- as.character(glm_cfg$model2_factors)
    }
    disease_lbl <- as.character(config$project$disease %||% "DKD")[1L]
    voc_lbl <- gsub("_", " ", voc, fixed = TRUE)
    config$rcs_nhanes$figure_filename <- sprintf(
      "Figure 7. RCS plot between %s and %s.pdf", voc_lbl, disease_lbl
    )
  }

  config$project$output_dir <- environment_batch_voc_output_dir(config, voc)
  config$project$root       <- bc$project_root %||% config$project$root

  config
}

environment_batch_copy_shared_ck <- function(shared_ck_dir, voc_ck_dir) {
  if (!dir.exists(voc_ck_dir)) dir.create(voc_ck_dir, recursive = TRUE)
  src <- file.path(shared_ck_dir, "bkmr_analysis.rds")
  if (!file.exists(src)) src <- file.path(shared_ck_dir, "index.rds")
  if (!file.exists(src)) {
    cli::cli_alert_warning("共享检查点缺失: {.file {src}}")
    return(FALSE)
  }
  dst <- file.path(voc_ck_dir, "index.rds")
  file.copy(src, dst, overwrite = TRUE)
  alias <- file.path(voc_ck_dir, "bkmr_analysis.rds")
  tryCatch(file.copy(dst, alias, overwrite = TRUE), error = function(e) NULL)
  invisible(TRUE)
}

environment_batch_ensure_cutoff_index <- function(config, root) {
  nh <- config$nhanes %||% list()
  ix <- as.character(
    nh$cutoff_index_var %||%
      config$incidence$index_var %||%
      ""
  )[1L]
  if (nzchar(ix)) return(config)

  vocs <- as.character((config$environment %||% list())$voc_columns %||% character(0))
  vocs <- unique(vocs[nzchar(vocs)])

  if (!length(vocs)) {
    raw_path <- config$data$rawdata_path %||% NULL
    raw_obj  <- config$data$rawdata_obj %||% "EnvResult"
    if (!is.null(raw_path) && nzchar(raw_path)) {
      rp <- raw_path
      if (!is_absolute_path(rp)) rp <- file.path(root, rp)
      if (file.exists(rp)) {
        env <- new.env()
        load(rp, envir = env)
        if (exists(raw_obj, envir = env, inherits = FALSE)) {
          df <- get(raw_obj, envir = env)
          if (exists("environment_resolve_voc_columns", mode = "function")) {
            vocs <- environment_resolve_voc_columns(df, config)
          }
        }
      }
    }
  }

  if (length(vocs)) {
    config$nhanes$cutoff_index_var <- vocs[1L]
    cli::cli_alert_info(
      "共享层 obj: cutoff_index_var={vocs[1L]}（用于 compute_nhanes_new_weight）"
    )
  }
  config
}

environment_batch_run_shared_layer <- function(root, config, pipeline_shared, from_checkpoint = NULL) {
  ck_dir <- environment_batch_shared_ck_dir(config)
  if (is.null(from_checkpoint) || !nzchar(as.character(from_checkpoint)[1L])) {
    if (file.exists(file.path(ck_dir, "bkmr_analysis.rds")) ||
        file.exists(file.path(ck_dir, "index.rds"))) {
      cli::cli_alert_info("共享层 checkpoint 已存在，跳过（删目录可强制重跑）")
      return(invisible(ck_dir))
    }
  }
  bc  <- config$environment_batch %||% list()
  cfg <- environment_batch_ensure_cutoff_index(config, root)
  cfg$project$root <- bc$project_root %||% root
  cfg$project$output_dir <- file.path(
    bc$output_base %||% config$project$output_dir, "_shared"
  )
  pl <- pipeline_shared
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir    <- ck_dir
  cli::cli_h2("共享层 Step01–06 + Step11 — {paste(pl$blocks, collapse = ' → ')}")
  run_opts <- list()
  if (!is.null(from_checkpoint) && nzchar(as.character(from_checkpoint)[1L])) {
    run_opts$from <- as.character(from_checkpoint)[1L]
  }
  run_pipeline(root, config = cfg, pipeline = pl, run_opts = run_opts)
  invisible(ck_dir)
}

environment_batch_load_checkpoint_ctx <- function(ck_dir, prefer_block = NULL) {
  ck_dir <- normalizePath(ck_dir, winslash = "/", mustWork = FALSE)
  if (!dir.exists(ck_dir)) {
    stop("检查点目录不存在: ", ck_dir, call. = FALSE)
  }
  prefer <- as.character(prefer_block %||% character(0))
  prefer <- prefer[nzchar(prefer)]
  candidates <- character(0)
  for (pb in prefer) {
    candidates <- c(candidates, file.path(ck_dir, paste0(pb, ".rds")))
  }
  candidates <- c(
    candidates,
    file.path(ck_dir, "bkmr_analysis.rds"),
    file.path(ck_dir, "index.rds")
  )
  candidates <- unique(candidates[file.exists(candidates)])
  if (!length(candidates)) {
    stop("检查点目录内无可用 .rds: ", ck_dir, call. = FALSE)
  }
  obj <- tryCatch(readRDS(candidates[[1L]]), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) {
    stop("无法读取检查点 ctx: ", candidates[[1L]], call. = FALSE)
  }
  if (!is.null(obj$pub_counters)) {
    .pub_counters_restore(obj$pub_counters)
  } else if (!is.null(obj$ctx$log$pub_counters)) {
    .pub_counters_restore(obj$ctx$log$pub_counters)
  }
  obj$ctx
}

environment_batch_run_tail_layer <- function(root, config, pipeline_tail) {
  ck_dir <- environment_batch_shared_ck_dir(config)
  bc     <- config$environment_batch %||% list()
  cfg    <- config
  cfg$project$root <- bc$project_root %||% root
  cfg$project$output_dir <- file.path(
    bc$output_base %||% config$project$output_dir, "_tail"
  )
  pl <- pipeline_tail
  pl$checkpoint$enable <- TRUE
  pl$checkpoint$dir    <- ck_dir

  shared_ctx <- environment_batch_load_checkpoint_ctx(ck_dir, "bkmr_analysis")
  cfg <- environment_batch_sync_config_from_ctx(cfg, shared_ctx)

  cli::cli_h2("尾段 Step08–09: qgcomp → mediation")
  run_pipeline(
    root, config = cfg, pipeline = pl,
    run_opts = list(
      initial_ctx = shared_ctx,
      only = c("qgcomp_environment", "mediation_ers_environment")
    )
  )

  strata <- bc$subgroup_strata %||% list()
  if (!length(strata)) {
    cli::cli_alert_info("未配置 subgroup_strata，跳过 Step10 亚组")
    return(invisible(NULL))
  }

  for (i in seq_along(strata)) {
    sg <- strata[[i]]
    sg_col <- as.character(sg$stratify_col %||% "")[1L]
    if (!nzchar(sg_col)) next
    cli::cli_h2("尾段 Step10 亚组 [{sg_col}]")
    cfg_i <- cfg
    cfg_i$subgroup_environment_or <- utils::modifyList(
      cfg$subgroup_environment_or %||% list(),
      sg
    )
    run_pipeline(
      root, config = cfg_i, pipeline = pl,
      run_opts = list(
        initial_ctx = shared_ctx,
        only = "subgroup_environment_or"
      )
    )
  }

  if ("environment_target_enrichment" %in% pl$blocks) {
    cli::cli_h2("尾段 Step12: environment_target_enrichment")
    run_pipeline(
      root, config = cfg, pipeline = pl,
      run_opts = list(
        initial_ctx = shared_ctx,
        only = "environment_target_enrichment"
      )
    )
  }
  invisible(NULL)
}

environment_batch_status_path <- function(output_base, voc) {
  candidates <- c(
    file.path(output_base, "by_voc", voc, "_batch_status.json"),
    file.path(output_base, "by_voc", paste0(voc, "\u300c\u6210\u529f\u300d"), "_batch_status.json"),
    file.path(output_base, "by_voc", paste0(voc, "\u300c\u5931\u8d25\u300d"), "_batch_status.json")
  )
  hit <- candidates[file.exists(candidates)]
  if (length(hit)) hit[1L] else candidates[1L]
}

environment_batch_write_status <- function(voc_output_dir, fields) {
  if (!dir.exists(voc_output_dir)) dir.create(voc_output_dir, recursive = TRUE)
  fields$finished_at <- format(Sys.time(), "%Y-%m-%dT%H:%M:%S")
  json_path <- file.path(voc_output_dir, "_batch_status.json")
  tryCatch(
    writeLines(jsonlite::toJSON(fields, auto_unbox = TRUE, pretty = TRUE), json_path),
    error = function(e) message("无法写入 _batch_status.json: ", e$message)
  )
  invisible(json_path)
}

.batch_cli_kv <- function(flag, value) {
  paste0(as.character(flag)[1L], "=", as.character(value)[1L])
}

environment_batch_dispatch_voc_workers <- function(root, config, voc_vars,
                                                    workers = 4L,
                                                    log_dir = NULL,
                                                    only_voc = NULL,
                                                    skip_existing = TRUE,
                                                    config_path = NULL,
                                                    worker_script = "run/environment/run_environment_dkd_batch_worker.R") {
  if (!requireNamespace("jsonlite", quietly = TRUE))
    stop("请先安装 jsonlite", call. = FALSE)

  bc          <- config$environment_batch %||% list()
  output_base <- bc$output_base %||% config$project$output_dir
  workers     <- max(1L, as.integer(workers))

  if (!is.null(only_voc) && length(only_voc))
    voc_vars <- voc_vars[voc_vars %in% only_voc]

  if (is.null(log_dir)) {
    log_slug <- gsub("[^A-Za-z0-9._-]+", "_", basename(output_base))
    log_dir <- file.path(root, ".cache", "environment_voc_batch_logs", log_slug)
  }
  if (!dir.exists(log_dir)) dir.create(log_dir, recursive = TRUE)

  worker_path <- file.path(root, worker_script)
  if (!file.exists(worker_path))
    stop("Worker 脚本不存在: ", worker_path, call. = FALSE)

  is_windows_r <- .Platform$OS.type == "windows"
  # wait=FALSE 的 system2 在 Unix 上会走 shell，含空格路径或重定向时易失败；优先 processx
  use_processx <- is_windows_r || requireNamespace("processx", quietly = TRUE)
  rscript_bin    <- file.path(R.home("bin"), if (is_windows_r) "Rscript.exe" else "Rscript")
  mode_label <- if (use_processx) "processx" else "Linux system2 后台（路径勿含空格）"
  cli::cli_alert_info("Worker 启动模式: {mode_label}")

  shared_ck <- environment_batch_shared_ck_dir(config)

  .status_ok <- function(voc) {
    p <- environment_batch_status_path(output_base, voc)
    if (!file.exists(p)) return(FALSE)
    st <- tryCatch(jsonlite::fromJSON(p), error = function(e) NULL)
    identical(st$status, "success")
  }

  .launch <- function(voc) {
    if (skip_existing && .status_ok(voc)) {
      cli::cli_alert_info("跳过 {.field {voc}}（已完成）")
      return(NULL)
    }
    log_path <- file.path(log_dir, paste0(voc, ".log"))
    root_abs <- normalizePath(root, winslash = "/", mustWork = TRUE)
    worker_abs <- normalizePath(worker_path, winslash = "/", mustWork = TRUE)

    opts_file <- file.path(log_dir, paste0(voc, ".opts.rds"))
    saveRDS(
      list(
        root = root_abs,
        config = if (!is.null(config_path) && nzchar(config_path)) {
          normalizePath(config_path, winslash = "/", mustWork = FALSE)
        } else NULL
      ),
      opts_file
    )

    args <- c(
      worker_abs,
      .batch_cli_kv("--voc", voc),
      .batch_cli_kv("--opts", normalizePath(opts_file, winslash = "/", mustWork = FALSE))
    )

    log_abs <- normalizePath(log_path, winslash = "/", mustWork = FALSE)
    if (!dir.exists(dirname(log_abs))) dir.create(dirname(log_abs), recursive = TRUE)

    child_env <- c(
      PATH   = Sys.getenv("PATH", "/usr/bin:/bin"),
      HOME   = Sys.getenv("HOME", "/root"),
      R_HOME = Sys.getenv("R_HOME", R.home()),
      LANG   = Sys.getenv("LANG", "C.UTF-8"),
      ENVIRONMENT_DKD_WORKER_ROOT = root_abs
    )
    if (!is.null(config_path) && nzchar(as.character(config_path)[1L])) {
      child_env <- c(
        child_env,
        ENVIRONMENT_DKD_WORKER_CONFIG = normalizePath(
          as.character(config_path)[1L], winslash = "/", mustWork = FALSE
        )
      )
    }

    if (use_processx) {
      if (!requireNamespace("processx", quietly = TRUE))
        stop("批量派发需要 processx: install.packages('processx')", call. = FALSE)
      processx::process$new(
        normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
        args,
        stdout = log_abs, stderr = log_abs, cleanup = FALSE, env = child_env
      )
    } else {
      system2(
        normalizePath(rscript_bin, winslash = "/", mustWork = TRUE),
        args, stdout = log_abs, stderr = log_abs, wait = FALSE, env = child_env
      )
    }
    cli::cli_alert_success("启动 worker [{.field {voc}}] → {.file {basename(log_path)}}")
    list(voc = voc, log = log_path, started_at = Sys.time())
  }

  total  <- length(voc_vars)
  done   <- 0L
  active <- list()

  for (voc in voc_vars) {
    while (length(active) >= workers) {
      Sys.sleep(8)
      still <- list()
      for (p in active) {
        sp <- environment_batch_status_path(output_base, p$voc)
        if (file.exists(sp)) {
          done <- done + 1L
          st   <- tryCatch(jsonlite::fromJSON(sp), error = function(e) list(status = "unknown"))
          cli::cli_alert_success("[{done}/{total}] {.field {p$voc}} 完成 (status={st$status})")
        } else {
          still[[length(still) + 1L]] <- p
        }
      }
      active <- still
    }
    proc <- .launch(voc)
    if (!is.null(proc)) active[[length(active) + 1L]] <- proc
  }

  cli::cli_alert_info("等待最后 {length(active)} 个 VOC worker…")
  t0 <- Sys.time()
  while (length(active) > 0 &&
         as.numeric(difftime(Sys.time(), t0, units = "secs")) < 7200) {
    Sys.sleep(15)
    still <- list()
    for (p in active) {
      sp <- environment_batch_status_path(output_base, p$voc)
      if (file.exists(sp)) {
        done <- done + 1L
        st   <- tryCatch(jsonlite::fromJSON(sp), error = function(e) list(status = "unknown"))
        cli::cli_alert_success("[{done}/{total}] {.field {p$voc}} 完成 (status={st$status})")
      } else {
        still[[length(still) + 1L]] <- p
      }
    }
    active <- still
  }

  invisible(done)
}

environment_batch_read_all_status <- function(output_base, voc_vars) {
  .scalar_chr <- function(x, default = NA_character_) {
    if (is.null(x) || length(x) == 0L) return(default)
    out <- as.character(x)[1L]
    if (!nzchar(out)) default else out
  }
  .scalar_num <- function(x, default = NA_real_) {
    if (is.null(x) || length(x) == 0L) return(default)
    suppressWarnings(as.numeric(x)[1L])
  }
  rows <- lapply(voc_vars, function(voc) {
    path <- environment_batch_status_path(output_base, voc)
    if (!file.exists(path)) {
      return(data.frame(
        index = voc, status = "not_run", error_message = NA_character_,
        elapsed_sec = NA_real_, finished_at = NA_character_,
        stringsAsFactors = FALSE
      ))
    }
    st <- tryCatch(jsonlite::fromJSON(path), error = function(e) list(index = voc, status = "parse_error"))
    data.frame(
      index         = voc,
      status        = .scalar_chr(st$status, "unknown"),
      error_message = .scalar_chr(st$error_message),
      elapsed_sec   = .scalar_num(st$elapsed_sec),
      finished_at   = .scalar_chr(st$finished_at),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

run_environment_voc_batch <- function(root, config,
                                       pipeline_shared,
                                       pipeline_voc_batch,
                                       pipeline_tail,
                                       run_opts = list(),
                                       config_path = NULL) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  bc   <- config$environment_batch %||% list()

  shared_only <- isTRUE(run_opts$shared_only)
  tail_only   <- isTRUE(run_opts$tail_only)
  only_voc    <- run_opts$only_voc %||% NULL
  skip_exist  <- isTRUE(run_opts$skip_existing %||% bc$skip_existing %||% TRUE)

  workers_raw  <- run_opts$workers %||% bc$parallel_workers
  auto_workers <- is.null(workers_raw) ||
    identical(tolower(trimws(as.character(workers_raw))), "auto")
  workers <- if (!auto_workers) max(1L, as.integer(workers_raw)) else NA_integer_

  if (!tail_only && !isTRUE(run_opts$rcs_only)) {
    environment_batch_run_shared_layer(
      root, config, pipeline_shared,
      from_checkpoint = run_opts$from %||% NULL
    )
  }

  if (shared_only) {
    vocs <- tryCatch(
      environment_batch_resolve_from_shared_ck(config),
      error = function(e) { cli::cli_alert_warning(e$message); character(0) }
    )
    cli::cli_alert_success("--shared-only 完成，可用 VOC: {length(vocs)} 个")
    return(invisible(vocs))
  }

  if (isTRUE(run_opts$tail_only)) {
    environment_batch_run_tail_layer(root, config, pipeline_tail)
    tryCatch(
      {
        if (!exists("environment_batch_export_voc_pub_tables", mode = "function")) {
          source(file.path(root, "R/environment_voc_pub_tables.R"), local = FALSE)
        }
        environment_batch_export_voc_pub_tables(config, root)
      },
      error = function(e) {
        cli::cli_alert_warning("VOC S3/S4 发表表自动导出失败: {e$message}")
      }
    )
    environment_batch_collect_results_summary(config, root)
    cli::cli_alert_success("--tail-only 完成")
    return(invisible(NULL))
  }

  voc_vars <- environment_batch_resolve_from_shared_ck(config)
  if (!is.null(only_voc) && length(only_voc))
    voc_vars <- intersect(voc_vars, only_voc)

  effective_n <- length(voc_vars)
  if (auto_workers) {
    workers <- incidence_batch_auto_workers(
      n_indices       = effective_n,
      ram_per_worker  = bc$ram_per_worker_gb %||% 2.5,
      cpu_headroom    = bc$cpu_headroom %||% 2L,
      ram_headroom_gb = bc$ram_headroom_gb %||% 4.0,
      max_workers     = bc$max_workers %||% NULL
    )
  } else {
    cli::cli_alert_info("Worker 数: {workers}（手动）| VOC 数: {effective_n}")
  }

  if (!isTRUE(run_opts$skip_rcs_batch %||% FALSE)) {
    environment_batch_dispatch_voc_workers(
      root          = root,
      config        = config,
      voc_vars      = voc_vars,
      workers       = workers,
      only_voc      = only_voc,
      skip_existing = skip_exist,
      config_path   = config_path
    )
  }

  if (!isTRUE(run_opts$rcs_only %||% FALSE)) {
    environment_batch_run_tail_layer(root, config, pipeline_tail)
  }

  output_base <- bc$output_base %||% config$project$output_dir
  statuses    <- environment_batch_read_all_status(output_base, voc_vars)

  cli::cli_h2("VOC Batch 汇总（共 {length(voc_vars)} 个 VOC）")
  cli::cli_alert_success("RCS 成功: {sum(statuses$status == 'success', na.rm = TRUE)}")
  cli::cli_alert_danger("RCS 失败: {sum(statuses$status %in% c('error','failed'), na.rm = TRUE)}")

  out_dir <- file.path(output_base, "Tables")
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  csv_path <- file.path(out_dir, "Batch_summary_all_vocs.csv")
  tryCatch(
    utils::write.csv(statuses, csv_path, row.names = FALSE, fileEncoding = "UTF-8"),
    error = function(e) cli::cli_alert_warning("汇总 CSV 写入失败: {e$message}")
  )
  cli::cli_alert_success("汇总表: {.file {csv_path}}")

  fs <- config$feishu %||% list()
  if (isTRUE(fs$push_on_batch_summary) &&
      exists("incidence_batch_feishu_update_summary", mode = "function")) {
    tryCatch(
      incidence_batch_feishu_update_summary(config, statuses),
      error = function(e) cli::cli_alert_warning("飞书汇总行更新失败: {e$message}")
    )
  }

  if (!isTRUE(run_opts$rcs_only %||% FALSE)) {
    tryCatch(
      {
        if (!exists("environment_batch_export_voc_pub_tables", mode = "function")) {
          source(file.path(root, "R/environment_voc_pub_tables.R"), local = FALSE)
        }
        environment_batch_export_voc_pub_tables(config, root)
      },
      error = function(e) {
        cli::cli_alert_warning("VOC S3/S4 发表表自动导出失败: {e$message}")
      }
    )
    environment_batch_collect_results_summary(config, root)
  }

  invisible(statuses)
}
