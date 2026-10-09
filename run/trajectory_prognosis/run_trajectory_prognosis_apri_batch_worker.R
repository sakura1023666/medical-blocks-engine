#!/usr/bin/env Rscript
# =============================================================================
#  轨迹预后 APRI 多指标批量 — 单指标 Worker 子进程
#
#  用法（调试）:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch_worker.R --unit APRI
#
#  流程:
#    1. patch config → 收窄为单一 Index
#    2. 双库对齐模式（默认）:
#         阶段1 — 每库独立跑预后前缀至 VIF final
#         取两库 Model2Factors 交集，按主库单因素 P 选 ≤5 个共有 JLCM survival 协变量
#         阶段2 — 两库共用该列表跑 JLCM + 全部图表/表格
#    3. 单库/关闭对齐时：每库一次性跑完整 pipeline_unit
#    4. 写 _batch_status.json
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_worker_args <- function(args) {
  opts <- list(unit = NULL, root = NULL, config = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) {
      opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$unit) || !nzchar(opts$unit)) stop("--unit（Index 名称）参数必填", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

root_guess <- normalizePath(getwd(), winslash = "/")
if (!is.null(wk_opts$root) && nzchar(wk_opts$root))
  root_guess <- normalizePath(wk_opts$root, winslash = "/", mustWork = TRUE)

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

ix <- wk_opts$unit
t_start <- proc.time()

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
}
source(config_path)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

status_dir <- trajectory_batch_status_output_dir(config, ix)

.write_status <- function(status, db_results = list(), db_errors = list(), error_message = NULL) {
  elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
  done_dbs <- names(db_results)[vapply(db_results, Negate(is.null), logical(1L))]
  fail_dbs <- names(db_errors)[nzchar(as.character(db_errors))]
  fields <- list(
    index         = ix,
    unit          = ix,
    status        = status,
    db_done       = paste(done_dbs, collapse = ","),
    db_failed     = paste(fail_dbs, collapse = ","),
    error_message = error_message,
    elapsed_sec   = elapsed,
    disease       = (config$feishu %||% list())$disease_label %||% config$project$disease %||% "",
    protocol      = (config$feishu %||% list())$protocol_label %||% ""
  )
  study_batch_write_status(status_dir, fields)
}

cli::cli_h1("Trajectory Prognosis APRI Worker: index={ix}")

config_ix <- tryCatch(
  trajectory_batch_patch_config_for_index(config, ix),
  error = function(e) { .write_status("error", error_message = conditionMessage(e)); quit(save = "no", status = 1) }
)

tryCatch(
  trajectory_batch_enforce_index_min_n(config_ix, ix),
  error = function(e) {
    .write_status("failed", error_message = conditionMessage(e))
    quit(save = "no", status = 1)
  }
)

tb <- config$trajectory_batch %||% list()
db_seq <- as.character(tb$db_seq %||% c("eicu", "mimic"))
pipeline_prefix <- tb$pipeline_unit_prefix %||% pipeline_unit_prefix
pipeline_suffix <- tb$pipeline_unit_suffix %||% pipeline_unit_suffix
harmonize_jlcm <- isTRUE((config_ix$trajectory_jlcm %||% list())$dual_db_harmonize_survival_covariates %||% TRUE)

result_ctx <- list()
db_errors <- list()
tryCatch({
  if (harmonize_jlcm && length(db_seq) >= 2L) {
    cli::cli_h2("[{ix}] 阶段 1/2 — 双库预后前缀（至 VIF final）")
    for (db in db_seq) {
      cli::cli_h3("[{ix}] {toupper(db)} — 预后前缀")
      shared_ck <- trajectory_batch_shared_ck_dir(config_ix, db)
      shared_ck_file <- file.path(shared_ck, "trajectory_calc_28d_index.rds")
      if (!file.exists(shared_ck_file)) {
        msg <- sprintf("%s 共享 checkpoint 不存在", toupper(db))
        cli::cli_alert_warning("[{ix}] {msg}（{shared_ck_file}）")
        db_errors[[db]] <- msg
        next
      }
      ctx_db <- tryCatch(
        trajectory_batch_run_index_db(root, config_ix, ix, db, pipeline_prefix),
        error = function(e) {
          msg <- conditionMessage(e)
          cli::cli_alert_danger("[{ix}/{toupper(db)}] {msg}")
          db_errors[[db]] <<- msg
          NULL
        }
      )
      result_ctx[[db]] <- ctx_db
    }
    done_prefix <- names(result_ctx)[vapply(result_ctx, Negate(is.null), logical(1L))]
    if (length(done_prefix) < length(db_seq)) {
      .write_status("failed", db_results = result_ctx, db_errors = db_errors,
                    error_message = paste(unlist(db_errors), collapse = "; "))
      quit(save = "no", status = 1)
    }

    shared_covs <- trajectory_dual_db_select_shared_jlcm_covariates(
      config_ix, ix, db_seq = db_seq, root = root, primary_db = db_seq[[1L]]
    )
    trajectory_dual_db_write_shared_jlcm_covariates(config_ix, ix, shared_covs)

    cli::cli_h2("[{ix}] 阶段 2/2 — 双库 JLCM + 图表（共有协变量）")
    for (db in db_seq) {
      cli::cli_h3("[{ix}] {toupper(db)} — JLCM 及下游")
      ctx_db <- tryCatch(
        trajectory_batch_run_index_db(
          root, config_ix, ix, db, pipeline_suffix,
          shared_jlcm_covariates = shared_covs,
          resume_from_block = "multicollinearity_final"
        ),
        error = function(e) {
          msg <- conditionMessage(e)
          cli::cli_alert_danger("[{ix}/{toupper(db)}] {msg}")
          db_errors[[db]] <<- msg
          NULL
        }
      )
      result_ctx[[db]] <- ctx_db
    }
  } else {
    for (db in db_seq) {
      cli::cli_h2("[{ix}] {toupper(db)} — 续跑完整链条")
      shared_ck <- trajectory_batch_shared_ck_dir(config_ix, db)
      shared_ck_file <- file.path(shared_ck, "trajectory_calc_28d_index.rds")
      if (!file.exists(shared_ck_file)) {
        msg <- sprintf("%s 共享 checkpoint 不存在", toupper(db))
        cli::cli_alert_warning("[{ix}] {msg}（{shared_ck_file}）")
        db_errors[[db]] <- msg
        next
      }
      ctx_db <- tryCatch(
        trajectory_batch_run_index_db(root, config_ix, ix, db, pipeline_unit),
        error = function(e) {
          msg <- conditionMessage(e)
          cli::cli_alert_danger("[{ix}/{toupper(db)}] {msg}")
          db_errors[[db]] <<- msg
          NULL
        }
      )
      result_ctx[[db]] <- ctx_db
    }
  }

  done_dbs <- names(result_ctx)[vapply(result_ctx, Negate(is.null), logical(1L))]
  if (!length(done_dbs)) {
    .write_status("failed", db_results = result_ctx, db_errors = db_errors,
                  error_message = paste(unlist(db_errors), collapse = "; "))
    quit(save = "no", status = 1)
  }

  if (length(done_dbs) < length(db_seq)) {
    .write_status("partial", db_results = result_ctx, db_errors = db_errors,
                  error_message = paste(unlist(db_errors), collapse = "; "))
    cli::cli_alert_warning("[{ix}] 部分完成: {paste(toupper(done_dbs), collapse=', ')}（失败: {paste(toupper(setdiff(db_seq, done_dbs)), collapse=', ')}）")
    quit(save = "no", status = 1)
  }

  .write_status("success", db_results = result_ctx, db_errors = db_errors)
  # 发表图表整理：分库 curate → 双库 finalize（CONSORT / 竖拼 / 共享 cut / 13 图）
  tryCatch({
    curate_util <- file.path(root, "R/trajectory_pub_curate.R")
    if (file.exists(curate_util)) source(curate_util, local = FALSE)
    fin_util <- file.path(root, "R/trajectory_pub_finalize.R")
    if (file.exists(fin_util)) source(fin_util, local = FALSE)
    out_base <- trajectory_batch_index_output_dir(config_ix, ix)
    disease <- config_ix$project$disease %||%
      (config_ix$feishu %||% list())$disease_label %||% "ischemic stroke"
    disease <- gsub("^\\d+_", "", as.character(disease)[1L])
    disease <- gsub("(?i)[_ ]Trajectory$", "", disease, perl = TRUE)
    disease <- gsub("_", " ", disease)
    disease <- trimws(disease)
    trajectory_curate_pub_outputs(
      base_dir = out_base,
      index_name = ix,
      dbs = done_dbs,
      disease = disease
    )
    if (exists("trajectory_batch_finalize_index_outputs", mode = "function")) {
      trajectory_batch_finalize_index_outputs(
        index_root = out_base,
        config = config_ix,
        index_name = ix,
        dbs = done_dbs
      )
    }
  }, error = function(e) {
    cli::cli_alert_warning("[{ix}] 发表图表整理失败（不影响成功状态）: {conditionMessage(e)}")
  })
  cli::cli_alert_success("[{ix}] 完成！已跑库: {paste(toupper(done_dbs), collapse=', ')}")
  quit(save = "no", status = 0)

}, error = function(e) {
  msg <- conditionMessage(e)
  cli::cli_alert_danger("[{ix}] 错误: {msg}")
  .write_status("error", db_results = result_ctx, db_errors = db_errors, error_message = msg)
  quit(save = "no", status = 1)
})
