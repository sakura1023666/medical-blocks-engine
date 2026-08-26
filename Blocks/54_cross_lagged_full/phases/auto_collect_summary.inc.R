# 由各 phase_*.R 末尾 source。要求调用方已有 root + study_root。
# 分析失败不应被汇总拖死：失败只告警。
if (!exists("study_root") || !exists("root")) {
  # study_batch：config 旁即课题根
  if (exists("config_path") && file.exists(config_path)) {
    .sr <- dirname(normalizePath(config_path, winslash = "/", mustWork = FALSE))
    if (length(Sys.glob(file.path(.sr, "phase1_*"))) ||
        length(Sys.glob(file.path(.sr, "phase3_*")))) {
      if (!exists("study_root")) study_root <- .sr
    }
  }
}
if (exists("study_root") && exists("root") &&
    !is.null(study_root) && nzchar(as.character(study_root)[1L])) {
  .sh <- file.path(root, "Blocks/54_cross_lagged_full/phases/collect_summary_result.sh")
  if (file.exists(.sh) && dir.exists(as.character(study_root)[1L])) {
    cli::cli_h2("自动收集 summary_result/figure + table")
    .sr <- as.character(study_root)[1L]
    Sys.setenv(CROSS_LAGGED_STUDY_ROOT = .sr)
    .st <- tryCatch(
      # system2 向量参数勿再 shQuote（路径空格会变成字面引号 → need study_root）
      system2("bash", c(.sh, .sr), stdout = TRUE, stderr = TRUE),
      error = function(e) {
        cli::cli_alert_warning("自动汇总失败: {conditionMessage(e)}")
        character(0)
      }
    )
    .ec <- as.integer(attr(.st, "status") %||% 0L)
    if (!identical(.ec, 0L)) {
      cli::cli_alert_warning(
        "自动汇总失败（分析已完成）: phase shell 失败 (collect_summary_result.sh) exit={(.ec)}"
      )
    }
    if (length(.st)) {
      .tail <- utils::tail(.st, 8L)
      cli::cli_inform("{.val {paste(.tail, collapse = '\n')}}")
    }
  }
}
