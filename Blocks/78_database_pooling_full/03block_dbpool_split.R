# dbpool_split — 患者级 70/15/15（seed=974）；优先复用 delivery split_manifest

block_dbpool_split <- function(ctx) {
  if (!exists(".dbpool_data_root", mode = "function")) {
    root <- ctx$config$project$root %||% getwd()
    source(file.path(root, "Blocks/78_database_pooling_full/00dbpool_common.R"), local = FALSE)
  }
  cfg <- .dbpool_cfg(ctx)
  delivery <- ctx$results$dbpool_delivery %||% file.path(.dbpool_data_root(ctx), "out", "delivery")
  split_csv <- file.path(delivery, "09_split_manifest.csv")
  if (!file.exists(split_csv)) stop("缺少 09_split_manifest.csv", call. = FALSE)
  sp <- utils::read.csv(split_csv, stringsAsFactors = FALSE)
  utils::write.csv(sp, file.path(ctx$output_dir_tables, "Table_Split_Manifest.csv"), row.names = FALSE)
  # also invoke BlendedLoS 1_split when blended_out ready and config asks
  blended <- ctx$results$dbpool_blended_out %||% .dbpool_blended_out(ctx)
  if (isTRUE(cfg$run_upstream_split %||% TRUE) && dir.exists(file.path(blended, "preprocessed_timeseries"))) {
    up <- .dbpool_upstream_dir(ctx)
    # write paths.json into upstream cwd
    paths <- jsonlite::toJSON(list(blendedICU = paste0(normalizePath(blended, winslash = "/"), "/")), auto_unbox = TRUE)
    writeLines(paths, file.path(up, "paths.json"))
    py <- .dbpool_python(ctx)
    logf <- file.path(ctx$output_dir, "upstream_split.log")
    # system2 env must be named character; never pass Sys.getenv() raw vector with "(" values
    env <- Sys.getenv()
    prev_py <- if ("PYTHONPATH" %in% names(env)) env[["PYTHONPATH"]] else ""
    env["PYTHONPATH"] <- paste(c(up, prev_py), collapse = .Platform$path.sep)
    # drop empty names that break sh
    env <- env[nzchar(names(env))]
    status <- system2(
      py,
      args = c(file.path(up, "1_split_train_test.py")),
      stdout = logf, stderr = logf,
      env = env,
      timeout = as.integer(cfg$split_timeout_sec %||% 7200L),
      wait = TRUE
    )
    # Prefer running via wrapper that chdirs into upstream
    if (!identical(as.integer(status), 0L)) {
      wrap <- file.path(ctx$output_dir, "_run_split.py")
      writeLines(sprintf(
        "import os, runpy, sys\nos.chdir(%s)\nsys.path.insert(0, os.getcwd())\nrunpy.run_path('1_split_train_test.py', run_name='__main__')\n",
        jsonlite::toJSON(up, auto_unbox = TRUE)
      ), wrap)
      status <- system2(py, args = wrap, stdout = logf, stderr = logf,
                        timeout = as.integer(cfg$split_timeout_sec %||% 7200L))
    }
    need <- file.path(blended, "extraction", "train_on_amsterdam", "train", "labels.parquet")
    if (!file.exists(need)) {
      stop("DataSplitter 未写出 extraction/train_on_*/…/labels.parquet（见 ", logf, "）", call. = FALSE)
    }
    if (!identical(as.integer(status), 0L)) {
      cli::cli_alert_warning("上游 DataSplitter status={status}; 但 labels 已存在，继续")
    } else {
      cli::cli_alert_success("上游 DataSplitter 完成")
    }
  }
  ctx$results$dbpool_split <- sp
  ctx$results$dbpool_split_seed <- cfg$split_seed %||% 974L
  ctx
}

register_block(
  "dbpool_split", block_dbpool_split,
  "数据库池化：患者级 70/15/15 划分（delivery manifest + 可选上游 DataSplitter）"
)
