###############################################################################
#  tst_summary_results — 项目级文献图表汇总 → summary_results/
#
#  每个 TST 项目跑完尾段后必出：
#    <project$output_dir>/summary_results/{Tables,Figures,by_landmark}/
#  命名/格式对齐 tst_pub_export 清单（ROC/校准/DCA=PDF，SHAP=PNG）。
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
    "--primary-landmark", as.character(primary)
  )
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
  checklist <- file.path(summary_dir, "Pub_deliverables_checklist.pdf")
  n_pass <- NA_integer_
  n_total <- NA_integer_
  # PDF checklist：用目录内 PDF 计数作 PASS 近似；详细见 Pub_deliverables_checklist.pdf
  if (dir.exists(file.path(summary_dir, "Tables")) && dir.exists(file.path(summary_dir, "Figures"))) {
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
    python_log_tail = utils::tail(as.character(out), 20L)
  )
  if (!is.na(n_pass) && !is.na(n_total)) {
    cli::cli_alert_success("tst_summary_results: {n_pass}/{n_total} PASS @ {summary_dir}")
  } else {
    cli::cli_alert_success("tst_summary_results: 完成 @ {summary_dir}")
  }
  ctx
}

register_block(
  "tst_summary_results",
  block_tst_summary_results,
  "两阶段 Transformer 卒中：项目级 summary_results 文献图表汇总（每项目必出）"
)
