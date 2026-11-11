#!/usr/bin/env Rscript
###############################################################################
# WPR 内容层补洞：TotalCo2 中介 / 30d·365d 多时点 / Fig S1 流程图 / 双库拼图
#
#   Rscript run/sepsis_jin_prognosis/repair_wpr_content_gaps.R \
#     --config "G:/02block_result/36_spesis/prediction_41194138/config_survival.R"
###############################################################################

{
  skip_win <- identical(Sys.getenv("MEDICAL_BLOCKS_SKIP_WIN_R", unset = ""), "1")
  rscript <- "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
  if (!skip_win && file.exists(rscript) && .Platform$OS.type != "windows") {
    ca <- commandArgs(trailingOnly = FALSE)
    self <- grep("^--file=", ca, value = TRUE)
    if (length(self)) {
      self <- sub("^--file=", "", self[1L])
      .win_q <- function(x) {
        vapply(as.character(x), function(a) {
          if (!nzchar(a)) return('""')
          if (grepl("[[:space:]]", a) || grepl('"', a, fixed = TRUE))
            paste0('"', gsub('"', '\\"', a, fixed = TRUE), '"')
          else a
        }, character(1), USE.NAMES = FALSE)
      }
      status <- system2(rscript, .win_q(c(self, commandArgs(trailingOnly = TRUE))))
      quit(save = "no", status = status)
    }
  }
}

`%||%` <- function(a, b) if (is.null(a)) b else a

.args <- commandArgs(trailingOnly = TRUE)
.cfg_i <- match("--config", .args)
if (is.na(.cfg_i) || .cfg_i >= length(.args)) {
  stop("需要 --config <config_survival.R>", call. = FALSE)
}
config_path <- normalizePath(.args[[.cfg_i + 1L]], winslash = "/", mustWork = TRUE)
project_root <- dirname(config_path)
ix <- "WPR"

engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine_root)) {
  for (.ef in c("/mnt/e/01block/01Block-new-Final", "E:/01block/01Block-new-Final")) {
    if (dir.exists(.ef)) { engine_root <- .ef; break }
  }
}
engine_root <- gsub("\\\\", "/", engine_root)
if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", engine_root)) {
  .drv <- tolower(substr(engine_root, 1L, 1L))
  engine_root <- paste0("/mnt/", .drv, substring(engine_root, 3L))
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine_root, MEDICAL_BLOCKS_SKIP_WIN_R = "1")
setwd(engine_root)

source(config_path, local = FALSE)
source(file.path(engine_root, "R/utils.R"), local = FALSE)
source(file.path(engine_root, "R/literature_jin_index_sofa.R"), local = FALSE)
source(file.path(engine_root, "R/jin_index_sofa_pub.R"), local = FALSE)
source(file.path(engine_root, "R/incidence_dual_batch_runner.R"), local = FALSE)
source(file.path(engine_root, "R/survival_dual_batch_runner.R"), local = FALSE)
source(file.path(engine_root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(engine_root, "R/pub_figure_export.R"), local = FALSE)

need_cols <- unique(c(
  as.character((config$analysis_exclusion %||% list())$protect_vars %||% character(0)),
  as.character((config$mediation_prognosis %||% list())$mediators %||% character(0)),
  as.character((config$mediation_prognosis %||% list())$best_mediator %||% character(0)),
  as.character((config$logistic_nomogram %||% list())$candidate_features %||% character(0)),
  "TotalCo2"
))
need_cols <- need_cols[nzchar(need_cols)]
id_col <- as.character(config$data$id_column %||% "ID")[1L]

.inject_cols_from_shared <- function(db_slot) {
  shared_ck <- file.path(project_root, "checkpoints", "_shared", db_slot, "index.rds")
  per_ck_dir <- file.path(project_root, "checkpoints", "by_index", ix, db_slot)
  if (!file.exists(shared_ck) || !dir.exists(per_ck_dir)) {
    cli::cli_alert_warning("跳过注入 [{db_slot}]：缺 shared 或 per-index 目录")
    return(invisible(FALSE))
  }
  s_obj <- readRDS(shared_ck)
  src <- s_obj$ctx$data$mapped %||% s_obj$ctx$data$cleaned %||% s_obj$ctx$data$raw
  if (!is.data.frame(src) || !id_col %in% names(src)) {
    cli::cli_alert_warning("[{db_slot}] shared 无可用源表")
    return(invisible(FALSE))
  }
  avail <- intersect(need_cols, names(src))
  if (!length(avail)) {
    cli::cli_alert_warning("[{db_slot}] shared 无 need_cols")
    return(invisible(FALSE))
  }
  add0 <- src[, c(id_col, avail), drop = FALSE]
  rds_files <- list.files(per_ck_dir, pattern = "\\.rds$", full.names = TRUE)
  n_files <- 0L
  for (fp in rds_files) {
    obj <- tryCatch(readRDS(fp), error = function(e) NULL)
    if (is.null(obj) || is.null(obj$ctx$data)) next
    changed <- FALSE
    for (slot in names(obj$ctx$data)) {
      df <- obj$ctx$data[[slot]]
      if (!is.data.frame(df) || !nrow(df) || !id_col %in% names(df)) next
      miss <- setdiff(avail, names(df))
      if (!length(miss)) {
        ## 仍补 horizon 别名
        df2 <- if (exists("jin_ensure_horizon_columns", mode = "function")) {
          jin_ensure_horizon_columns(
            df,
            db = if (grepl("eicu", db_slot, ignore.case = TRUE)) "eicu" else "mimic"
          )
        } else df
        if (!identical(names(df2), names(df)) ||
            !identical(ncol(df2), ncol(df))) {
          obj$ctx$data[[slot]] <- df2
          changed <- TRUE
        }
        next
      }
      add <- add0[, c(id_col, miss), drop = FALSE]
      df2 <- merge(df, add, by = id_col, all.x = TRUE, sort = FALSE)
      ord <- match(df[[id_col]], df2[[id_col]])
      if (anyNA(ord)) next
      df2 <- df2[ord, , drop = FALSE]
      if (exists("jin_ensure_horizon_columns", mode = "function")) {
        df2 <- jin_ensure_horizon_columns(
          df2,
          db = if (grepl("eicu", db_slot, ignore.case = TRUE)) "eicu" else "mimic"
        )
      }
      obj$ctx$data[[slot]] <- df2
      changed <- TRUE
    }
    if (changed) {
      saveRDS(obj, fp)
      n_files <- n_files + 1L
    }
  }
  cli::cli_alert_success(
    "[{db_slot}] 已注入 {paste(avail, collapse=', ')} → 更新 {n_files} 个 checkpoint"
  )
  invisible(TRUE)
}

cli::cli_h1("1/4 从 shared 注入 TotalCo2 等 protect 列 → WPR checkpoints")
for (db in c("MIMIC", "eICU")) .inject_cols_from_shared(db)

cli::cli_h1("2/4 重跑 cox_multi_horizon + mediation_prognosis")
worker <- file.path(engine_root, "run/survival/run_survival_dual_batch_worker.R")
status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(
    worker,
    "--config", config_path,
    "--index", ix,
    "--db", "both",
    "--blocks", "cox_multi_horizon,mediation_prognosis"
  )
)
if (!identical(as.integer(status), 0L)) {
  stop("worker 定向重跑失败 status=", status, call. = FALSE)
}

index_root <- file.path(project_root, "by_index", paste0("【success】", ix))
if (!dir.exists(index_root)) {
  index_root <- file.path(project_root, "by_index", ix)
}
if (!dir.exists(index_root)) stop("找不到指标目录: ", index_root, call. = FALSE)

cli::cli_h1("3/4 Fig S1 流程图 + Jin curate + 双库拼图")
db_seq <- c("mimic", "eicu")
tryCatch(
  incidence_batch_ensure_real_figure1(
    index_root = index_root,
    config = config,
    ix = ix,
    db_seq = db_seq,
    project_root = project_root,
    force = TRUE
  ),
  error = function(e) cli::cli_alert_warning("ensure_real_figure1: {e$message}")
)

## 过滤统计：尽量从 _batch_status / ck 行数推
filter_stats <- tryCatch(
  incidence_batch_filter_stats_from_status(index_root),
  error = function(e) list()
)
if (!length(filter_stats)) {
  filter_stats <- list()
  for (db in c("MIMIC", "eICU")) {
    ck <- file.path(project_root, "checkpoints", "by_index", ix, db, "imputation.rds")
    if (!file.exists(ck)) {
      ck <- file.path(project_root, "checkpoints", "by_index", ix, db, "index.rds")
    }
    obj <- tryCatch(readRDS(ck), error = function(e) NULL)
    df <- if (!is.null(obj)) incidence_batch_ctx_data(obj$ctx) else NULL
    sh <- tryCatch(
      readRDS(file.path(project_root, "checkpoints", "_shared", db, "index.rds")),
      error = function(e) NULL
    )
    df0 <- if (!is.null(sh)) incidence_batch_ctx_data(sh$ctx) else NULL
    if (is.data.frame(df)) {
      n0 <- if (is.data.frame(df0)) nrow(df0) else nrow(df)
      filter_stats[[tolower(db)]] <- list(
        imputed = list(
          n_before = n0,
          n_after = nrow(df),
          n_na = max(0L, as.integer(n0 - nrow(df))),
          n_trim = 0L
        )
      )
      filter_stats[[db]] <- filter_stats[[tolower(db)]]
    }
  }
}

tryCatch(
  survival_batch_write_index_flowcharts(
    project_root = project_root,
    index_root = index_root,
    ix = ix,
    filter_stats = filter_stats,
    db_seq = db_seq,
    font_family = (config$plot %||% list())$font_family %||% "Times New Roman",
    config = config
  ),
  error = function(e) cli::cli_alert_warning("write_index_flowcharts: {e$message}")
)

fig_dir <- file.path(index_root, "Figures")
if (exists("dual_db_combine_paired_figures", mode = "function")) {
  tryCatch(
    dual_db_combine_paired_figures(index_root, config),
    error = function(e) cli::cli_alert_warning("dual combine: {e$message}")
  )
}
if (exists("jin_index_sofa_curate_figures_dir", mode = "function")) {
  tryCatch(
    jin_index_sofa_curate_figures_dir(fig_dir, config),
    error = function(e) cli::cli_alert_warning("jin curate figs: {e$message}")
  )
}
if (exists("jin_index_sofa_curate_tables_dir", mode = "function")) {
  tryCatch(
    jin_index_sofa_curate_tables_dir(file.path(index_root, "Tables"), index_lab = ix),
    error = function(e) cli::cli_alert_warning("jin curate tables: {e$message}")
  )
}
if (exists("pub_figure_ensure_formats", mode = "function")) {
  tryCatch(
    pub_figure_ensure_formats(fig_dir, config = config),
    error = function(e) cli::cli_alert_warning("ensure_formats: {e$message}")
  )
}

cli::cli_h1("4/4 同步 summary_results")
if (exists("ml_finalize_index_summary_results", mode = "function") ||
    exists("incidence_batch_finalize_index_outputs", mode = "function")) {
  ## 轻量：复制 Figures/Tables 到 summary_results 并 prune 白名单
  sr <- file.path(index_root, "summary_results")
  dir.create(sr, recursive = TRUE, showWarnings = FALSE)
  for (sub in c("Figures", "Tables")) {
    src <- file.path(index_root, sub)
    dst <- file.path(sr, sub)
    if (!dir.exists(src)) next
    if (dir.exists(dst)) unlink(dst, recursive = TRUE)
    dir.create(dirname(dst), recursive = TRUE, showWarnings = FALSE)
    ok <- FALSE
    if (.Platform$OS.type == "windows") {
      ok <- isTRUE(dir.create(dst, recursive = TRUE, showWarnings = FALSE))
    }
    ## file.copy 递归
    file.copy(src, sr, recursive = TRUE, overwrite = TRUE)
  }
  ## Methods 若已有则保留
  for (mf in c("Methods_statistical_analysis.md", "Methods_software_versions.txt")) {
    src <- file.path(index_root, mf)
    if (file.exists(src)) file.copy(src, file.path(sr, mf), overwrite = TRUE)
  }
  if (exists("pub_prune_delivery_root", mode = "function")) {
    tryCatch(
      pub_prune_delivery_root(sr, study_type = "survival"),
      error = function(e) cli::cli_alert_warning("prune: {e$message}")
    )
  }
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(file.path(sr, "Figures"), config = config),
      error = function(e) NULL
    )
  }
}

## 验收摘录
cli::cli_h1("验收")
sr_pdf <- file.path(index_root, "summary_results", "Figures", "pdf")
if (!dir.exists(sr_pdf)) sr_pdf <- file.path(index_root, "Figures", "pdf")
if (!dir.exists(sr_pdf)) sr_pdf <- file.path(index_root, "Figures")
figs <- if (dir.exists(sr_pdf)) list.files(sr_pdf, pattern = "\\.pdf$", recursive = TRUE) else character(0)
cli::cli_alert_info("Figures: {paste(figs, collapse = ' | ')}")

mh_csv <- list.files(
  file.path(index_root, "MIMIC"),
  pattern = "Table_multi_horizon_cox\\.csv$",
  recursive = TRUE, full.names = TRUE
)
if (length(mh_csv)) {
  d <- utils::read.csv(mh_csv[[1L]], stringsAsFactors = FALSE)
  cli::cli_alert_info(
    "multi_horizon horizons: {paste(unique(d$horizon_id %||% d$horizon), collapse=', ')} (n_row={nrow(d)})"
  )
}
med_fig <- list.files(
  index_root, pattern = "Mediation|Path diagram|Figure 4",
  recursive = TRUE, full.names = FALSE, ignore.case = TRUE
)
cli::cli_alert_info("mediation artifacts: {paste(head(med_fig, 12), collapse=' | ')}")
s1 <- list.files(
  index_root, pattern = "Figure S1.*flowchart|Inclusion exclusion",
  recursive = TRUE, full.names = FALSE, ignore.case = TRUE
)
cli::cli_alert_info("flowchart S1: {paste(s1, collapse=' | ')}")

cli::cli_alert_success("repair_wpr_content_gaps 完成 → {index_root}")
