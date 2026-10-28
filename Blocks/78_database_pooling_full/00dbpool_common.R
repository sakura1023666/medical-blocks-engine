# 数据库池化 / BlendedLoS 公共工具（Blocks/78）
# 不修改既有 71/67 等项目。

.dbpool_cfg <- function(ctx) {
  cfg <- ctx$config$dbpool %||% list()
  cfg
}

.dbpool_data_root <- function(ctx) {
  cfg <- .dbpool_cfg(ctx)
  p <- as.character(cfg$data_root %||% "")[1L]
  if (!nzchar(p)) stop("config$dbpool$data_root 未设置", call. = FALSE)
  normalizePath(p, winslash = "/", mustWork = FALSE)
}

.dbpool_python <- function(ctx) {
  cfg <- .dbpool_cfg(ctx)
  py <- as.character(cfg$python_bin %||% Sys.getenv("DBPOOL_PYTHON", ""))[1L]
  if (!nzchar(py)) {
    cands <- c(
      file.path(ctx$config$project$root %||% getwd(), ".venv_dbpool", "bin", "python"),
      file.path(ctx$config$project$root %||% getwd(), ".venv_ml_pub", "bin", "python"),
      "python3"
    )
    for (c in cands) if (nzchar(c) && file.exists(c)) return(c)
    return("python3")
  }
  py
}

.dbpool_env_optional_int <- function(key, value) {
  if (is.null(value) || length(value) == 0L || is.na(value[[1L]]) || !nzchar(as.character(value[[1L]]))) {
    Sys.unsetenv(key)
    return(invisible(NULL))
  }
  Sys.setenv(key, as.character(as.integer(value[[1L]])))
  invisible(as.integer(value[[1L]]))
}

.dbpool_apply_train_mode_env <- function(ctx) {
  cfg <- .dbpool_cfg(ctx)
  # Literature default: 200 epoch / batch 32. Fast only if explicitly requested.
  # Optional caps (NULL = 不限制，走全文口径):
  #   n_epochs, max_n_batch, stays_per_db, percentage_test
  fast <- isTRUE(cfg$fast_train %||% FALSE)
  if (fast) {
    Sys.setenv(DBPOOL_FAST_TRAIN = "1", DBPOOL_FULL_EPOCHS = "0")
    Sys.unsetenv("DBPOOL_N_EPOCHS")
    cli::cli_alert_warning("dbpool FAST train: n_epochs=40 batch=64 (not literature-grade)")
  } else {
    Sys.setenv(DBPOOL_FULL_EPOCHS = "1", DBPOOL_FAST_TRAIN = "0")
    ep <- .dbpool_env_optional_int("DBPOOL_N_EPOCHS", cfg$n_epochs %||% NULL)
    ep_show <- ep %||% 200L
    cli::cli_alert_info("dbpool LITERATURE train: n_epochs={ep_show} batch=32 alpha=20")
  }
  .dbpool_env_optional_int("DBPOOL_MAX_N_BATCH", cfg$max_n_batch %||% NULL)
  .dbpool_env_optional_int("DBPOOL_TRAIN_STAYS_PER_DB", cfg$stays_per_db %||% NULL)
  .dbpool_env_optional_int("DBPOOL_PERCENTAGE_TEST", cfg$percentage_test %||% NULL)
  invisible(fast)
}

.dbpool_run_py <- function(ctx, script, args = character(), timeout_sec = 86400L) {
  root <- ctx$config$project$root %||% getwd()
  py <- .dbpool_python(ctx)
  script_abs <- if (grepl("^/", script) || grepl("^[A-Za-z]:", script)) script else file.path(root, script)
  if (!file.exists(script_abs)) stop("Python script not found: ", script_abs, call. = FALSE)
  .dbpool_apply_train_mode_env(ctx)
  cmd <- c(py, script_abs, args)
  cli::cli_alert_info("dbpool py: {paste(cmd, collapse = ' ')}")
  out_log <- file.path(ctx$output_dir %||% tempdir(), "dbpool_py.log")
  status <- system2(cmd[[1]], args = cmd[-1], stdout = out_log, stderr = out_log, timeout = timeout_sec)
  if (!identical(as.integer(status), 0L)) {
    msg <- if (file.exists(out_log)) paste(readLines(out_log, warn = FALSE), collapse = "\n") else ""
    stop("dbpool python failed status=", status, "\n", msg, call. = FALSE)
  }
  invisible(out_log)
}

.dbpool_blended_out <- function(ctx) {
  cfg <- .dbpool_cfg(ctx)
  p <- as.character(cfg$blended_out %||% file.path(ctx$root_output_dir %||% "Output", "blendedICU_adapted"))[1L]
  dir.create(p, recursive = TRUE, showWarnings = FALSE)
  normalizePath(p, winslash = "/", mustWork = FALSE)
}

.dbpool_block78_dir <- function(ctx) {
  root <- ctx$config$project$root %||% getwd()
  normalizePath(file.path(root, "Blocks/78_database_pooling_full"), winslash = "/", mustWork = FALSE)
}

.dbpool_upstream_dir <- function(ctx) {
  cfg <- .dbpool_cfg(ctx)
  custom <- as.character(cfg$upstream_dir %||% "")[1L]
  if (nzchar(custom) && dir.exists(custom)) {
    return(normalizePath(custom, winslash = "/", mustWork = TRUE))
  }
  p <- file.path(.dbpool_block78_dir(ctx), "upstream", "BlendedLoS")
  if (!dir.exists(p)) {
    legacy <- file.path(ctx$config$project$root %||% getwd(), "python/blended_los_upstream")
    if (dir.exists(legacy)) return(normalizePath(legacy, winslash = "/", mustWork = TRUE))
    stop("BlendedLoS upstream 未找到: ", p, call. = FALSE)
  }
  normalizePath(p, winslash = "/", mustWork = TRUE)
}

.dbpool_scripts_dir <- function(ctx) {
  file.path(.dbpool_block78_dir(ctx), "scripts")
}
