###############################################################################
#  tst_summary_results — 项目级文献图表汇总 → summary_results/
#
#  每个 TST 项目跑完尾段后必出：
#    <project$output_dir>/summary_results/{Tables,Figures,by_landmark}/
#  Figures 须与预后/发病一致：pdf/png/tiff/image_information 四目录
#  （R/pub_figure_export.R::export_pub_figures）。
#
#  调用: Blocks/71_two_stage_transformer_stroke/scripts/build_summary_results.py
#  配置（可选）:
#    config$tst_stroke$summary_primary_landmark = 72L
#    config$tst_stroke$summary_results_dirname = "summary_results"（仅文档；脚本固定该名）
###############################################################################

`%||%` <- function(a, b) if (is.null(a) || (length(a) == 1L && !nzchar(as.character(a)[1L]))) b else a

.tst71_root <- function(ctx) ctx$config$project$root %||% getwd()

.tst71_ensure_py_lit <- function(root) {
  if (!exists("literature_python_bin", mode = "function")) {
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  }
}

.tst71_quote_sys2 <- function(args) {
  args <- as.character(args)
  vapply(args, function(a) {
    if (!nzchar(a)) return('""')
    if (grepl("[[:space:]]", a, perl = TRUE) && !grepl('^["\'].*["\']$', a)) {
      paste0('"', gsub('"', '""', a, fixed = TRUE), '"')
    } else a
  }, character(1L), USE.NAMES = FALSE)
}

.tst71_export_pub_figure_formats <- function(ctx, summary_dir) {
  figs_dir <- file.path(summary_dir, "Figures")
  if (!dir.exists(figs_dir)) {
    cli::cli_alert_warning("tst_summary_results: 无 Figures 目录，跳过四目录导出")
    return(invisible(NULL))
  }
  root <- .tst71_root(ctx)
  pub_r <- file.path(root, "R/pub_figure_export.R")
  if (file.exists(pub_r) && !exists("export_pub_figures", mode = "function")) {
    source(pub_r, local = FALSE)
  }
  if (!exists("export_pub_figures", mode = "function")) {
    stop("tst_summary_results: 缺少 export_pub_figures（R/pub_figure_export.R）", call. = FALSE)
  }

  prj <- ctx$config$project %||% list()
  ts <- ctx$config$tst_stroke %||% list()
  disease <- as.character(prj$disease %||% prj$name %||% "TwoStageTransformer")[1L]
  db <- as.character(prj$database %||% prj$database_type %||% "MIMIC")[1L]
  score <- as.character(ts$comparator_score %||% "SAPSII")[1L]
  primary <- as.integer(ts$summary_primary_landmark %||% 72L)[1L]
  outcome <- as.character(ctx$config$data$outcome_column %||% "is_hosp_dead")[1L]

  n_total <- NA_integer_
  n_by_db <- NULL
  n_alive <- NA_integer_
  n_dead <- NA_integer_
  fig1_json <- file.path(dirname(summary_dir), "_shared/_tst_fig1_counts.json")
  if (file.exists(fig1_json)) {
    js <- tryCatch(jsonlite::fromJSON(fig1_json), error = function(e) NULL)
    if (!is.null(js)) {
      n_total <- suppressWarnings(as.integer(js$included %||% js$after_miss %||% NA_integer_))
      n_alive <- suppressWarnings(as.integer(js$alive %||% NA_integer_))
      n_dead <- suppressWarnings(as.integer(js$dead %||% NA_integer_))
      if (!is.na(n_total) && n_total > 0L) {
        n_by_db <- stats::setNames(list(n_total), db)
      }
    }
  }
  fc_cands <- c(
    file.path(dirname(summary_dir), "_shared/step06_tst_timeseries/Tables/_tst_cohort_flowchart.csv"),
    file.path(dirname(summary_dir), "_shared/step06_tst_timeseries/_tst_cohort_flowchart.csv"),
    file.path(dirname(summary_dir), "_shared/step05_tst_timeseries/Tables/_tst_cohort_flowchart.csv"),
    file.path(dirname(summary_dir), "_shared/step05_tst_timeseries/_tst_cohort_flowchart.csv"),
    file.path(dirname(summary_dir), "_shared/step03_tst_cohort/Tables/_tst_cohort_flowchart.csv")
  )
  if (is.na(n_total) || !n_total) {
    for (fc in fc_cands) {
      if (!file.exists(fc)) next
      dt <- tryCatch(utils::read.csv(fc, stringsAsFactors = FALSE), error = function(e) NULL)
      if (is.null(dt) || !nrow(dt)) next
      hit <- dt[dt$stage %in% c("final_analysis_cohort_n_out", "final_cohort_n_out"), , drop = FALSE]
      if (!nrow(hit)) next
      n_total <- suppressWarnings(as.integer(hit$n[[1L]]))
      if (!is.na(n_total) && n_total > 0L) {
        n_by_db <- stats::setNames(list(n_total), db)
        break
      }
    }
  }
  if (grepl("SepsisAKI|42_AKI", disease, ignore.case = TRUE) ||
      grepl("42_AKI_spesis", summary_dir, ignore.case = TRUE)) {
    disease <- "sepsis-associated AKI"
  }
  outcome_col <- outcome
  if (identical(outcome, "is_hosp_dead") || !nzchar(outcome)) {
    outcome <- "住院死亡"
  }

  meta <- list(
    exposure = paste0("Two-stage Transformer temporal features (", disease, ")"),
    outcome = outcome,
    outcome_column = outcome_col,
    grouping = paste0("L", primary, " landmark; comparator=", score),
    databases = db,
    n_total = if (!is.na(n_total)) n_total else NULL,
    n_by_db = n_by_db,
    combined = FALSE,
    study_type = "tst_two_stage_transformer"
  )

  cli::cli_alert_info("发表图四目录导出: {.file {figs_dir}}")
  res <- export_pub_figures(
    figs_dir,
    meta = meta,
    config = ctx$config %||% list(),
    purge = TRUE
  )
  # 清掉根目录残留 png（consort 旁路）及其他非四目录文件
  loose <- list.files(figs_dir, pattern = "^Figure.*\\.(png|tiff)$", full.names = TRUE, ignore.case = TRUE)
  loose <- loose[file.info(loose)$isdir %in% FALSE]
  if (length(loose)) unlink(loose)

  n_exp <- length(unique(as.character(res$exported %||% character())))
  n_miss <- length(unique(as.character(res$missing_raster %||% character())))
  if (n_miss > 0L) {
    cli::cli_alert_warning("栅格化未齐 {n_miss} 张（见 missing_raster）")
  }
  cli::cli_alert_success("发表图四目录完成: {n_exp} 张 × pdf/png/tiff")
  invisible(res)
}

block_tst_summary_results <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  root <- .tst71_root(ctx)
  prj  <- ctx$config$project %||% list()
  ts   <- ctx$config$tst_stroke %||% list()

  project_root <- as.character(prj$output_dir %||% "")[1L]
  if (!nzchar(project_root) || !dir.exists(project_root)) {
    stop(
      "tst_summary_results: config$project$output_dir 无效或不存在: ", project_root,
      call. = FALSE
    )
  }
  primary <- as.integer(ts$summary_primary_landmark %||% 72L)[1L]
  if (is.na(primary) || primary <= 0L) primary <- 72L
  score_name <- as.character(ts$comparator_score %||% "SAPSII")[1L]
  if (!nzchar(score_name)) score_name <- "SAPSII"
  fig3_lm <- as.integer(ts$summary_fig3_landmark %||% 0L)[1L]

  script <- file.path(root, "Blocks/71_two_stage_transformer_stroke/scripts/build_summary_results.py")
  if (!file.exists(script)) {
    stop("tst_summary_results: 脚本不存在: ", script, call. = FALSE)
  }

  .tst71_ensure_py_lit(root)
  py <- literature_python_bin()
  # Windows Python 需要 Windows 路径
  if (exists(".wsl_to_win_path", mode = "function") && grepl("python\\.exe$", py, ignore.case = TRUE)) {
    script <- .wsl_to_win_path(script)
    project_root_arg <- .wsl_to_win_path(project_root)
  } else {
    project_root_arg <- project_root
  }

  cmd_args <- c(
    script,
    "--project-root", project_root_arg,
    "--primary-landmark", as.character(primary),
    "--comparator-score", score_name
  )
  if (!is.na(fig3_lm) && fig3_lm > 0L) {
    cmd_args <- c(cmd_args, "--fig3-landmark", as.character(fig3_lm))
  }
  if (grepl("python\\.exe$", py, ignore.case = TRUE) || identical(.Platform$OS.type, "windows")) {
    if (exists(".system2_quote_args", mode = "function")) {
      cmd_args <- .system2_quote_args(cmd_args)
    } else {
      cmd_args <- .tst71_quote_sys2(cmd_args)
    }
  }

  cli::cli_alert_info("Python [tst_summary_results]: build_summary_results.py")
  out <- system2(py, cmd_args, stdout = TRUE, stderr = TRUE, timeout = 1800L)
  code <- attr(out, "status") %||% 0L
  if (!identical(as.integer(code), 0L)) {
    stop(
      "tst_summary_results 失败 (exit=", code, "):\n",
      paste(utils::tail(out, 30L), collapse = "\n"),
      call. = FALSE
    )
  }
  if (length(out)) {
    for (ln in utils::tail(out, 16L)) cli::cli_text("{ln}")
  }

  summary_dir <- file.path(project_root, "summary_results")
  pub_res <- tryCatch(
    .tst71_export_pub_figure_formats(ctx, summary_dir),
    error = function(e) {
      stop("tst_summary_results 四目录导出失败: ", conditionMessage(e), call. = FALSE)
    }
  )

  checklist <- file.path(summary_dir, "Pub_deliverables_checklist.pdf")
  n_pass <- NA_integer_
  n_total <- NA_integer_
  figs_pdf_dir <- file.path(summary_dir, "Figures", "pdf")
  if (dir.exists(figs_pdf_dir)) {
    n_total <- length(list.files(figs_pdf_dir, pattern = "^Figure.*\\.pdf$", ignore.case = TRUE))
    n_pass <- n_total
  } else if (dir.exists(file.path(summary_dir, "Tables")) && dir.exists(file.path(summary_dir, "Figures"))) {
    pdfs <- list.files(summary_dir, pattern = "\\.pdf$", recursive = TRUE, ignore.case = TRUE)
    n_total <- length(pdfs)
    n_pass <- n_total
  }

  ctx$results$tst_summary_results <- list(
    summary_dir = summary_dir,
    checklist_path = if (file.exists(checklist)) checklist else NA_character_,
    primary_landmark = primary,
    n_pass = n_pass,
    n_total = n_total,
    pub_figures = pub_res,
    python_log_tail = utils::tail(as.character(out), 20L)
  )
  if (!is.na(n_pass) && !is.na(n_total)) {
    cli::cli_alert_success("tst_summary_results: {n_pass}/{n_total} PASS @ {summary_dir}")
  } else {
    cli::cli_alert_success("tst_summary_results: 完成 @ {summary_dir}")
  }

  tryCatch({
    eng_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
    qc_src <- c(
      if (nzchar(eng_root)) file.path(eng_root, "R/pub_qc_after_finalize.R") else character(0),
      file.path(getwd(), "R/pub_qc_after_finalize.R"),
      "/mnt/e/01block/01Block-new-Final/R/pub_qc_after_finalize.R"
    )
    qc_src <- qc_src[file.exists(qc_src)]
    if (length(qc_src)) source(qc_src[[1L]], local = FALSE)
    if (exists("pub_qc_run_after_project", mode = "function")) {
      pub_qc_run_after_project(project_root, config = ctx$config %||% list())
    }
  }, error = function(e) {
    cli::cli_alert_warning("tst_summary_results pub-qc 跳过: {conditionMessage(e)}")
  })

  ctx
}

register_block(
  "tst_summary_results",
  block_tst_summary_results,
  "两阶段 Transformer：summary_results 汇总 + 发表图四目录（pdf/png/tiff/image_information）"
)
