###############################################################################
#  ai_qa_prepare — 医学 QA 数据集加载与导出
#  文献: Jeon — Interactive CoT medical QA
###############################################################################

block_ai_qa_prepare <- function(ctx, ...) {
  bl <- ctx$config$ai_medical_qa %||% list()
  root <- ctx$config$project$root %||% getwd()
  data <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data)) {
    path <- bl$qa_path %||% "Data/smoke/D01_ai_medical_qa.csv"
    if (!is_absolute_path(path)) path <- file.path(root, path)
    if (file.exists(path)) data <- utils::read.csv(path, stringsAsFactors = FALSE)
  }
  if (is.null(data)) stop("ai_qa_prepare: 无 QA 数据", call. = FALSE)

  req <- c("question_id", "dataset", "question", "answer", "correct_option")
  miss <- setdiff(req, names(data))
  if (length(miss)) {
    cli::cli_alert_warning("QA 数据缺少列: {paste(miss, collapse = ', ')}")
  }

  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_QA")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  out_csv <- file.path(out, "qa_prepared.csv")
  utils::write.csv(data, out_csv, row.names = FALSE)

  ctx$data$raw <- data
  ctx$data$cleaned <- data
  ctx$results$ai_qa_prepare <- list(
    n_questions = nrow(data),
    n_datasets = length(unique(data$dataset)),
    output_dir = out,
    prepared_path = out_csv
  )
  cli::cli_alert_success("医学 QA 数据准备完成 (n={nrow(data)})")
  ctx
}

register_block("ai_qa_prepare", block_ai_qa_prepare, "医学 QA 数据准备")
