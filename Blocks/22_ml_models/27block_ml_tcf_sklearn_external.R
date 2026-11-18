###############################################################################
#  ml_tcf_sklearn_external — 冻结 MIMIC TCF_sklearn 权重评 eICU（不重训、不重调 α）
#
#  register_block: "ml_tcf_sklearn_external"
###############################################################################

block_ml_tcf_sklearn_external <- function(ctx, ...) {
  cfg <- ctx$config$ml_tcf_sklearn_external %||% list(enable = TRUE)
  if (isFALSE(cfg$enable %||% TRUE)) return(ctx)

  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(root)) root <- ctx$config$project$root %||% getwd()

  ## 定位主库 TCF_sklearn
  meta_cands <- character(0)
  pri <- ctx$config$dual_db$primary$name %||% "MIMIC"
  out_base <- ctx$config$ml_batch$output_base %||% ctx$config$project$output_dir %||% ""
  idx <- ctx$results$index_label %||% ctx$config$ml_batch$current_index %||% "ALLVARS"
  for (base in unique(c(
    out_base,
    file.path(out_base, "by_index", paste0("【success】", idx)),
    file.path(out_base, "by_index", idx)
  ))) {
    meta_cands <- c(
      meta_cands,
      Sys.glob(file.path(base, pri, "*", "Models", "TCF_sklearn", "tcf_summary.json")),
      Sys.glob(file.path(base, "*", pri, "*", "Models", "TCF_sklearn", "tcf_summary.json"))
    )
  }
  ## ctx 指针
  if (!is.null(ctx$results$ml_tcf_sklearn$out_dir)) {
    meta_cands <- c(file.path(ctx$results$ml_tcf_sklearn$out_dir, "tcf_summary.json"), meta_cands)
  }
  meta_cands <- unique(meta_cands[file.exists(meta_cands)])
  if (!length(meta_cands)) {
    stop("ml_tcf_sklearn_external: 找不到主库 TCF_sklearn/tcf_summary.json", call. = FALSE)
  }
  model_dir <- dirname(meta_cands[[1L]])
  summary <- jsonlite::fromJSON(file.path(model_dir, "tcf_summary.json"))
  feats <- as.character(summary$features)

  outcome_col <- ctx$config$data$outcome_column
  ana <- as.character(ctx$config$project$analysis_group %||% "1")[1L]
  ## 外验整库：优先 test；若 train 也在则 rbind unique
  te <- ctx$data$test %||% ctx$data$imputed %||% ctx$data$mapped
  if (is.null(te)) stop("ml_tcf_sklearn_external: 无外验数据", call. = FALSE)
  miss <- setdiff(feats, names(te))
  if (length(miss)) {
    stop("ml_tcf_sklearn_external: 外验缺特征: ", paste(miss, collapse = ", "), call. = FALSE)
  }
  y <- as.integer(as.character(te[[outcome_col]]) == ana | as.character(te[[outcome_col]]) == "1")
  ext <- cbind(as.data.frame(te[, feats, drop = FALSE]), y = y)
  for (f in feats) ext[[f]] <- as.numeric(ext[[f]])

  out_dir <- file.path(ctx$output_dir %||% ".", "Models", "TCF_sklearn_external")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  ext_csv <- file.path(out_dir, "external.csv")
  utils::write.csv(ext, ext_csv, row.names = FALSE)

  py <- Sys.getenv("MEDICAL_BLOCKS_PYTHON", unset = "")
  if (!nzchar(py)) {
    if (.Platform$OS.type == "windows" && file.exists("C:/ProgramData/anaconda3/python.exe")) {
      py <- "C:/ProgramData/anaconda3/python.exe"
    } else {
      py <- Sys.which("python3")
      if (!nzchar(py)) py <- Sys.which("python")
    }
  }
  script <- file.path(root, "python", "ml_tcf", "eval_external_tcf.py")
  args_ext <- c(
    script,
    "--model-dir", model_dir,
    "--external", ext_csv,
    "--out-dir", out_dir,
    "--outcome", "y"
  )
  if (.Platform$OS.type == "windows") {
    args_ext <- vapply(args_ext, function(a) {
      a <- as.character(a)
      if (grepl("[[:space:]]", a) || grepl('"', a, fixed = TRUE)) shQuote(a, type = "cmd") else a
    }, character(1), USE.NAMES = FALSE)
  }
  st <- system2(py, args = args_ext, stdout = TRUE, stderr = TRUE)
  writeLines(st, file.path(out_dir, "eval_external.log"))
  if (!is.null(attr(st, "status")) && attr(st, "status") != 0) {
    stop("ml_tcf_sklearn_external 失败\n", paste(st, collapse = "\n"), call. = FALSE)
  }

  met <- utils::read.csv(file.path(out_dir, "metrics_external.csv"), row.names = 1L, check.names = FALSE)
  ctx$results$ml_eval_external_sklearn <- met
  ctx$results$ml_eval_all <- {
    rows <- lapply(rownames(met), function(m) {
      data.frame(
        .metric = "roc_auc", .estimator = "binary",
        .estimate = as.numeric(met[m, "AUC"]),
        dataset = "external", model = m, stringsAsFactors = FALSE
      )
    })
    dplyr::bind_rows(rows)
  }
  cli::cli_alert_success(
    "ml_tcf_sklearn_external: n={nrow(ext)}；TCF AUC={round(as.numeric(met['TCF','AUC']),3)}（α 冻结自 {model_dir}）"
  )
  ctx
}

register_block(
  "ml_tcf_sklearn_external",
  block_ml_tcf_sklearn_external,
  "TCF sklearn 冻结模型外验（eICU）"
)
