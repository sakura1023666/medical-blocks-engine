###############################################################################
#  ai_cases_prepare — MIMIC-CDM 风格病例导出
#  文献: Hager 2024 Nat Med — LLM 临床决策评测
###############################################################################

block_ai_cases_prepare <- function(ctx, ...) {
  bl <- ctx$config$ai_clinical %||% list()
  root <- ctx$config$project$root %||% getwd()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) {
    path <- bl$cases_path %||% "Data/smoke/D01_ai_clinical_cases.csv"
    if (!is_absolute_path(path)) path <- file.path(root, path)
    if (file.exists(path)) data <- utils::read.csv(path, stringsAsFactors = FALSE)
  }
  if (is.null(data)) stop("ai_cases_prepare: 无病例数据", call. = FALSE)
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_Cases")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data, file.path(out, "cases_prepared.csv"), row.names = FALSE)
  ctx$data$raw <- data
  ctx$data$cleaned <- data
  ctx$results$ai_cases <- list(n_cases = nrow(data), output_dir = out)
  cli::cli_alert_success("AI 病例准备完成 (n={nrow(data)})")
  ctx
}

register_block("ai_cases_prepare", block_ai_cases_prepare, "AI 病例准备")
