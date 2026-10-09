# 发表收口后触发质控骨架（Phase 6）
# 默认开启；config$pub$auto_qc = FALSE 或环境变量 MEDICAL_BLOCKS_AUTO_PUB_QC=0 可关

pub_qc_run_after_project <- function(project_root, config = NULL) {
  project_root <- as.character(project_root %||% "")[1L]
  if (!nzchar(project_root) || !dir.exists(project_root)) {
    cli::cli_alert_warning("pub_qc_run_after_project: 无效 project_root")
    return(invisible(FALSE))
  }
  cfg_pub <- if (is.list(config)) (config$pub %||% list()) else list()
  env_flag <- Sys.getenv("MEDICAL_BLOCKS_AUTO_PUB_QC", unset = "1")
  if (identical(as.character(cfg_pub$auto_qc %||% TRUE), "FALSE") ||
      identical(tolower(env_flag), "0") || identical(tolower(env_flag), "false")) {
    cli::cli_alert_info("pub_qc_run_after_project: 已跳过（auto_qc 关闭）")
    return(invisible(FALSE))
  }
  eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  script <- c(
    if (nzchar(eng)) file.path(eng, "run/pub/run_pub_qc_after_project.R") else character(0),
    file.path(getwd(), "run/pub/run_pub_qc_after_project.R"),
    "/mnt/e/01block/01Block-new-Final/run/pub/run_pub_qc_after_project.R",
    "E:/01block/01Block-new-Final/run/pub/run_pub_qc_after_project.R"
  )
  script <- script[file.exists(script)]
  if (!length(script)) {
    cli::cli_alert_warning("找不到 run/pub/run_pub_qc_after_project.R")
    return(invisible(FALSE))
  }
  cli::cli_alert_info("Phase 6 pub-qc: {project_root}")
  st <- tryCatch(
    system2("Rscript", c("--vanilla", script[[1L]], "--project", project_root),
            stdout = TRUE, stderr = TRUE),
    error = function(e) {
      cli::cli_alert_warning("pub-qc 失败: {e$message}")
      character(0)
    }
  )
  if (length(st)) cli::cli_alert_info("{paste(utils::tail(st, 3), collapse = ' | ')}")
  invisible(TRUE)
}
