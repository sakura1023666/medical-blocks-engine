## 从 checkpoint 抽出各模型 Val AUC + 相关过滤变量；并尝试把 ctx 输出目录内容列出来
Sys.setenv(MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final", MEDICAL_BLOCKS_SKIP_WIN_R = "1")
ck <- "G:/02block_result/27_eclampsia/small sample prediction_39780007/checkpoints/by_index/UA_CR/MIMIC_IV"

pull_eval <- function(obj) {
  ## checkpoint 是整包 ctx
  ctx <- if (is.list(obj) && !is.null(obj$ctx)) obj$ctx else obj
  ev <- ctx$results$ml_eval_by_model
  if (is.null(ev) || !length(ev)) {
    cat("no ml_eval_by_model\n")
    return(invisible(NULL))
  }
  rows <- list()
  for (nm in names(ev)) {
    d <- ev[[nm]]
    if (!is.data.frame(d)) next
    te <- d[d$dataset == "test" | d$dataset == "validation" | grepl("test|valid", d$dataset, ignore.case = TRUE), , drop = FALSE]
    if (!nrow(te)) te <- d
    auc <- te$.estimate[te$.metric == "roc_auc"][1]
    acc <- te$.estimate[te$.metric == "accuracy"][1]
    sens <- te$.estimate[te$.metric %in% c("sens", "sensitivity")][1]
    spec <- te$.estimate[te$.metric %in% c("spec", "specificity")][1]
    rows[[nm]] <- data.frame(model = nm, auc = auc, accuracy = acc, sens = sens, spec = spec)
  }
  tab <- do.call(rbind, rows)
  print(tab)
  tab
}

cat("=== performance_ml ===\n")
p <- readRDS(file.path(ck, "performance_ml.rds"))
ctx <- p$ctx
if (!is.null(ctx$results$ml_eval_by_model)) {
  tab <- pull_eval(p)
} else {
  cat("perf ctx keys results:", paste(names(ctx$results), collapse = ", "), "\n")
}

cat("\n=== ml_models_bundle ===\n")
p2 <- readRDS(file.path(ck, "ml_models_bundle.rds"))
tab2 <- pull_eval(p2)

cat("\n=== correlation low vars / high pairs ===\n")
p3 <- readRDS(file.path(ck, "correlation.rds"))
ctx3 <- p3$ctx
cat("low_correlation_vars:\n")
print(ctx3$results$low_correlation_vars)
cat("high_cor_pairs:\n")
print(ctx3$results$high_cor_pairs)

## 输出目录是否还在
od <- ctx$output_dir %||% ctx3$output_dir
cat("\noutput_dir from perf:", ctx$output_dir, "\n")
cat("output_dir from cor:", ctx3$output_dir, "\n")
if (!is.null(ctx$output_dir) && dir.exists(ctx$output_dir)) {
  cat("exists files:", length(list.files(ctx$output_dir, recursive = TRUE)), "\n")
}
