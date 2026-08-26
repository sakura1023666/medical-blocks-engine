###############################################################################
#  multimodal_early_fusion — 临床+组学早期融合分类（TBI 手术/输血预测）
#
#  register_block: "multimodal_early_fusion"
#  对齐文献: Deng 2025 npj Digital Med — Interpretable Multiomics Models
###############################################################################

block_multimodal_early_fusion <- function(ctx, ...) {
  bl <- ctx$config$multimodal %||% list()
  outcome <- ctx$config$data$outcome_column %||% "Outcome"
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || nrow(data) == 0L) data <- ctx$data$cleaned
  if (is.null(data) || nrow(data) == 0L) data <- ctx$data$raw
  if (is.null(data)) stop("multimodal_early_fusion: 无数据", call. = FALSE)
  clinical <- intersect(bl$clinical_vars %||% c("Age", "Gender", "GCS", "SBP"), names(data))
  omics    <- intersect(bl$omics_vars %||% grep("^Omics_", names(data), value = TRUE), names(data))
  preds    <- unique(c(clinical, omics))
  preds    <- setdiff(preds, outcome)

  if (!outcome %in% names(data)) stop("multimodal_early_fusion: 缺结局列 ", outcome, call. = FALSE)
  if (length(preds) < 2L) stop("multimodal_early_fusion: 预测变量不足", call. = FALSE)

  df <- data[stats::complete.cases(data[, c(outcome, preds), drop = FALSE]), , drop = FALSE]
  if (nrow(df) < 30L) stop("multimodal_early_fusion: 有效样本不足 (n=", nrow(df), ")", call. = FALSE)

  case_lbl <- pipeline_outcome_case_label(ctx$config)
  ref_lbl  <- pipeline_outcome_reference_label(ctx$config)
  ov <- df[[outcome]]
  if (is.character(ov) || is.factor(ov)) {
    y <- as.integer(as.character(ov) == case_lbl)
  } else {
    y_raw <- suppressWarnings(as.numeric(ov))
    if (all(stats::na.omit(unique(y_raw)) %in% c(0, 1))) {
      y <- as.integer(y_raw)
    } else {
      y <- as.integer(y_raw >= (bl$outcome_positive %||% 1L))
    }
  }
  df$.outcome01 <- y
  outcome_fit <- ".outcome01"

  set.seed(bl$seed %||% 2025L)
  n_train <- max(20L, min(nrow(df) - 10L, floor(0.7 * nrow(df))))
  idx <- sample(seq_len(nrow(df)), size = n_train)
  train <- df[idx, , drop = FALSE]
  test  <- df[-idx, , drop = FALSE]
  y_tr <- y[idx]
  y_te <- y[-idx]

  batch_mode <- tolower(as.character(bl$batch_mode %||% "all")[1L])
  mode_map <- list(
    clinical = "Clinical_only", clinical_only = "Clinical_only",
    omics = "Omics_only", omics_only = "Omics_only",
    fusion = "Early_fusion", early_fusion = "Early_fusion"
  )
  run_modes <- if (batch_mode %in% c("all", "")) {
    c("Clinical_only", "Omics_only", "Early_fusion")
  } else {
    m <- mode_map[[batch_mode]] %||% batch_mode
    c(m)
  }

  fit_clin <- fit_omics <- fit_fusion <- NULL
  if ("Clinical_only" %in% run_modes) {
    fit_clin <- stats::glm(
      as.formula(paste(outcome_fit, "~", paste(intersect(clinical, preds), collapse = " + "))),
      data = train, family = binomial()
    )
  }
  if ("Omics_only" %in% run_modes) {
    fit_omics <- stats::glm(
      as.formula(paste(outcome_fit, "~", paste(intersect(omics, preds), collapse = " + "))),
      data = train, family = binomial()
    )
  }
  if ("Early_fusion" %in% run_modes) {
    fit_fusion <- stats::glm(
      as.formula(paste(outcome_fit, "~", paste(preds, collapse = " + "))),
      data = train, family = binomial()
    )
  }

  .auc <- function(fit, newdata, ytrue) {
    if (is.null(fit)) return(NA_real_)
    if (!requireNamespace("pROC", quietly = TRUE)) {
      utils::install.packages("pROC", repos = "https://cloud.r-project.org", quiet = TRUE)
    }
    pr <- stats::predict(fit, newdata = newdata, type = "response")
    as.numeric(pROC::auc(pROC::roc(ytrue, pr, quiet = TRUE)))
  }

  res <- data.frame(
    model = run_modes,
    AUC_train = vapply(run_modes, function(m) {
      switch(m, Clinical_only = .auc(fit_clin, train, y_tr),
             Omics_only = .auc(fit_omics, train, y_tr),
             Early_fusion = .auc(fit_fusion, train, y_tr), NA_real_)
    }, numeric(1)),
    AUC_test = vapply(run_modes, function(m) {
      switch(m, Clinical_only = .auc(fit_clin, test, y_te),
             Omics_only = .auc(fit_omics, test, y_te),
             Early_fusion = .auc(fit_fusion, test, y_te), NA_real_)
    }, numeric(1)),
    n_train = nrow(train),
    n_test = nrow(test),
    stringsAsFactors = FALSE
  )

  out_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  out_csv <- if (length(run_modes) == 1L) {
    sprintf("Table_Multimodal_%s_AUC.csv", run_modes[1L])
  } else {
    "Table_Multimodal_Fusion_AUC.csv"
  }
  utils::write.csv(res, file.path(out_dir, out_csv), row.names = FALSE)
  ctx$results$multimodal_fusion <- list(
    metrics = res,
    models = list(clinical = fit_clin, omics = fit_omics, fusion = fit_fusion),
    batch_mode = batch_mode
  )
  cli::cli_alert_success("多模态早期融合完成（{paste(run_modes, collapse=', ')}）")
  ctx
}

register_block(
  "multimodal_early_fusion",
  block_multimodal_early_fusion,
  "临床+组学早期融合二分类"
)
