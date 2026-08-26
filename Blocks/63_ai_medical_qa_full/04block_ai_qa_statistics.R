###############################################################################
#  ai_qa_statistics — ANOVA / Kruskal-Wallis + Cohen d（vs Control）
#  文献: Jeon — medical QA chain-of-thought
###############################################################################

.cohen_d <- function(x, y) {
  x <- x[is.finite(x)]; y <- y[is.finite(y)]
  if (length(x) < 2L || length(y) < 2L) return(NA_real_)
  nx <- length(x); ny <- length(y)
  sp <- sqrt(((nx - 1) * stats::var(x) + (ny - 1) * stats::var(y)) / (nx + ny - 2))
  if (!is.finite(sp) || sp == 0) return(NA_real_)
  (mean(x) - mean(y)) / sp
}

block_ai_qa_statistics <- function(ctx, ...) {
  bl <- ctx$config$ai_medical_qa %||% list()
  eval_dir <- (ctx$results$ai_qa_cot_eval %||% list())$output_dir
  if (is.null(eval_dir))
    eval_dir <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "AI_QA_CoT")

  detail_path <- file.path(eval_dir, "Table_CoT_Eval_Results.csv")
  det <- if (file.exists(detail_path)) utils::read.csv(detail_path, stringsAsFactors = FALSE) else data.frame()

  prompt_methods <- bl$prompt_methods %||% c("Control", "Traditional_CoT", "Interactive_CoT")
  datasets <- bl$datasets %||% c("MedQA", "MedMCQA", "EHRNoteQA")
  rows <- list()

  for (ds in datasets) {
    sub <- if (nrow(det) && "dataset" %in% names(det)) det[det$dataset == ds, , drop = FALSE] else data.frame()
    acc_by_pm <- list()
    for (pm in prompt_methods) {
      if (nrow(sub) && "prompt_method" %in% names(sub) && "correct" %in% names(sub)) {
        acc_by_pm[[pm]] <- as.numeric(sub$correct[sub$prompt_method == pm])
      } else {
        cmp <- (ctx$results$ai_qa_prompt_compare %||% list())$table
        if (!is.null(cmp) && nrow(cmp)) {
          hit <- cmp[cmp$dataset == ds & cmp$prompt_method == pm, , drop = FALSE]
          if (nrow(hit)) acc_by_pm[[pm]] <- rep(hit$accuracy[1L], hit$n[1L] %||% 100L)
        }
      }
    }
    vals <- unlist(acc_by_pm[prompt_methods], use.names = FALSE)
    grp <- rep(prompt_methods, vapply(acc_by_pm[prompt_methods], length, integer(1L)))
    if (length(vals) < 6L || length(unique(grp)) < 2L) next

    use_anova <- TRUE
    if (length(unique(vals)) >= 3L) {
      sh <- tryCatch(stats::shapiro.test(vals)$p.value, error = function(e) 0)
      use_anova <- is.finite(sh) && sh >= 0.05
    }
    test_name <- if (use_anova) "anova" else "kruskal.test"
    p_overall <- tryCatch({
      if (use_anova) {
        fit <- stats::aov(vals ~ grp)
        summary(fit)[[1]][["Pr(>F)"]][1L]
      } else {
        stats::kruskal.test(vals ~ grp)$p.value
      }
    }, error = function(e) NA_real_)

    ctrl <- acc_by_pm[["Control"]]
    for (pm in setdiff(prompt_methods, "Control")) {
      treat <- acc_by_pm[[pm]]
      rows[[length(rows) + 1L]] <- data.frame(
        dataset = ds,
        comparison = paste0(pm, "_vs_Control"),
        test = test_name,
        p_overall = round(p_overall, 6),
        mean_treat = round(mean(treat, na.rm = TRUE), 4),
        mean_control = round(mean(ctrl, na.rm = TRUE), 4),
        cohen_d = round(.cohen_d(treat, ctrl), 4),
        n_treat = length(treat),
        n_control = length(ctrl),
        stringsAsFactors = FALSE
      )
    }
  }

  stat_df <- if (length(rows)) do.call(rbind, rows) else data.frame()
  if (nrow(stat_df) && "p_overall" %in% names(stat_df)) {
    root <- ctx$config$project$root %||% getwd()
    if (file.exists(file.path(root, "R/literature_validation.R")))
      source(file.path(root, "R/literature_validation.R"), local = FALSE)
    stat_df$p_fdr_BH <- literature_fdr_adjust(stat_df$p_overall, bl$fdr_method %||% "BH")
    stat_df$sig_fdr_05 <- stat_df$p_fdr_BH < 0.05
  }
  out <- file.path(ctx$config$project$output_dir %||% "Output", "Tables", "Table_AI_QA_CoT_Statistics.csv")
  dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(stat_df, out, row.names = FALSE)

  ctx$results$ai_qa_statistics <- list(table = stat_df, output_path = out)
  cli::cli_alert_success("CoT 统计检验完成 ({nrow(stat_df)} 比较)")
  ctx
}

register_block("ai_qa_statistics", block_ai_qa_statistics, "CoT 统计检验与效应量")
