#!/usr/bin/env Rscript
# 从已有 JLCM 检查点回写 trajectory_class + 导出 Table 2/3（跳过重拟合）
#
# 用法:
#   Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_fix_jlcm_assign.R \
#     --config configs/templates/config_trajectory_prognosis_batch.template.R --unit NLR

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(unit = "NLR", config = NULL, dbs = c("eicu", "mimic"))
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) { opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--config" && i < length(args)) { opts$config <- trimws(args[[i + 1L]]); i <- i + 2L }
    else if (a == "--db" && i < length(args)) { opts$dbs <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]; i <- i + 2L }
    else i <- i + 1L
  }
  opts
}

script_path <- .init_script_dir()
root <- if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)

opt <- .parse_args(commandArgs(trailingOnly = TRUE))
ix <- opt$unit

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/trajectory_paper_tables.R"))

.jfix_ic_row <- function(m, Index, D, n_subj) {
  unwrap <- function(x) {
    if (inherits(x, "Jointlcmm")) return(x)
    if (is.list(x) && inherits(x$best, "Jointlcmm")) return(x$best)
    x
  }
  m <- unwrap(m)
  if (is.null(m) || !is.list(m)) return(NULL)
  loglik <- m$loglik %||% NA_real_
  aic    <- m$AIC    %||% NA_real_
  bic    <- m$BIC    %||% NA_real_
  n_params <- if (!is.na(aic) && !is.na(loglik)) (aic + 2 * loglik) / 2 else NA_real_
  sabic  <- if (!is.na(n_params) && !is.na(loglik))
    -2 * loglik + n_params * log((n_subj + 2) / 24) else NA_real_
  entropy <- tryCatch({
    pprob <- as.data.frame(m$pprob)
    prob_cols <- grep("^prob", names(pprob), value = TRUE)
    if (length(prob_cols) == 0 || (m$ng %||% D) == 1L) return(1.0)
    P <- as.matrix(pprob[, prob_cols, drop = FALSE])
    P <- pmax(P, .Machine$double.eps)
    round(1 - (-sum(P * log(P), na.rm = TRUE) / (nrow(P) * log(m$ng))), 4)
  }, error = function(e) NA_real_)
  row <- data.frame(
    Index = Index, D = D, N = n_subj,
    Log_likelihood = round(loglik, 3),
    AIC = round(aic, 3), BIC = round(bic, 3), SABIC = round(sabic, 3),
    Entropy = entropy, Conv = m$conv %||% NA_integer_,
    stringsAsFactors = FALSE
  )
  props <- tryCatch({
    pprob <- as.data.frame(m$pprob)
    if (is.null(pprob$class)) return(NULL)
    pr <- round(100 * as.numeric(prop.table(table(pprob$class))), 1)
    stats::setNames(as.list(pr), paste0("Class_", seq_along(pr)))
  }, error = function(e) NULL)
  if (!is.null(props)) for (cn in names(props)) row[[cn]] <- props[[cn]]
  row
}

.jfix_auto_select_ng <- function(ic_df, bl_cfg) {
  if (!isTRUE(bl_cfg$auto_select_class_ng %||% FALSE)) {
    ng <- suppressWarnings(as.integer(bl_cfg$assign_class_ng %||% bl_cfg$prefer_final_ng)[1L])
    return(if (is.finite(ng)) ng else 2L)
  }
  df <- as.data.frame(ic_df)
  if ("Conv" %in% names(df)) df <- df[df$Conv %in% c(1L, 1), , drop = FALSE]
  if ("D" %in% names(df)) df <- df[as.integer(df$D) >= 2L, , drop = FALSE]
  if (!nrow(df)) return(2L)
  min_prop <- as.numeric(bl_cfg$min_class_proportion_pct %||% 5)
  min_ent  <- as.numeric(bl_cfg$min_entropy_for_selection %||% 0.3)
  ok <- rep(TRUE, nrow(df))
  for (i in seq_len(nrow(df))) {
    if ("Entropy" %in% names(df) && !is.na(df$Entropy[i]) && df$Entropy[i] < min_ent) ok[i] <- FALSE
    ng <- as.integer(df$D[i])
    cls_cols <- paste0("Class_", seq_len(ng))
    cls_cols <- intersect(cls_cols, names(df))
    if (length(cls_cols)) {
      props <- as.numeric(df[i, cls_cols, drop = FALSE])
      props <- props[!is.na(props)]
      if (length(props) && min(props) < min_prop) ok[i] <- FALSE
    }
  }
  cand <- df[ok, , drop = FALSE]
  if (!nrow(cand)) cand <- df
  cand <- cand[order(cand$BIC), , drop = FALSE]
  ng_pick <- suppressWarnings(as.integer(cand$D[1L]))
  if (!is.finite(ng_pick)) 2L else ng_pick
}

config_path <- if (!is.null(opt$config) && nzchar(opt$config)) {
  normalizePath(opt$config, winslash = "/", mustWork = TRUE)
} else file.path(root, "configs/templates/config_trajectory_prognosis_batch.template.R")
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

config_ix <- trajectory_batch_patch_config_for_index(config, ix)
downstream <- c("trajectory_baseline_by_class", "trajectory_piecewise_cox", "trajectory_chisq")

.fix_jlcm_assign <- function(ctx, cfg_db, Index = ix) {
  bl_cfg <- cfg_db$trajectory_jlcm %||% list()
  id_col <- cfg_db$data$id_column %||% "subject_id"
  pack <- ctx$results$trajectory_jlcm_models[[Index]]
  if (is.null(pack) || is.null(pack$models)) {
    cli::cli_alert_danger("{Index}: 无 JLCM 模型缓存")
    return(ctx)
  }
  models_list <- pack$models
  model_data_final <- pack$model_data_final
  nms <- names(models_list)
  class_range_eff <- suppressWarnings(as.integer(gsub("^m", "", nms)))
  class_range_eff <- sort(class_range_eff[is.finite(class_range_eff)])

  index_ic_rows <- list()
  for (g in class_range_eff) {
    m_g_raw <- models_list[[paste0("m", g)]]
    if (is.null(m_g_raw)) next
    n_subj <- length(unique(model_data_final$subject_id_num))
    ic_row <- .jfix_ic_row(m_g_raw, Index, g, n_subj)
    if (is.data.frame(ic_row) && nrow(ic_row)) index_ic_rows[[length(index_ic_rows) + 1L]] <- ic_row
  }
  index_ic_df <- if (length(index_ic_rows)) tryCatch(dplyr::bind_rows(index_ic_rows), error = function(e) NULL) else NULL
  selected_ng <- if (!is.null(index_ic_df) && nrow(index_ic_df)) {
    .jfix_auto_select_ng(index_ic_df, bl_cfg)
  } else {
    2L
  }
  ctx$results[[paste0("trajectory_optimal_ng_", Index)]] <- selected_ng
  ctx$results$trajectory_optimal_ng <- selected_ng
  cli::cli_alert_success("{Index}: 回写 ng={selected_ng}")

  if (length(index_ic_rows)) {
    ic_table <- dplyr::bind_rows(index_ic_rows)
    ctx$results$trajectory_ic_table <- ic_table
    db_lab <- cfg_db$project$database %||% "Study"
    fp_t2 <- file.path(
      ctx$output_dir_tables,
      paste0("Table 2-", db_lab, ". Metrics for determining the optimal number of classes.xlsx")
    )
    trajectory_export_table2_xlsx(ic_table, fp_t2, index_name = Index)
    trajectory_export_table2_xlsx(
      ic_table,
      file.path(ctx$output_dir_tables, "Table_Trajectory_IC_JLCM.xlsx"),
      index_name = Index
    )
    cli::cli_alert_success("Table 2 已输出: {.file {basename(fp_t2)}}")
  }

  .jfix_write_class <- function(ctx, Index, assign_ng, model_data_final, models_list, id_col) {
    assign_ng <- suppressWarnings(as.integer(assign_ng)[1L])
    if (!is.finite(assign_ng)) return(ctx)
    m_g_raw <- models_list[[paste0("m", assign_ng)]]
    if (is.null(m_g_raw)) return(ctx)
    if (inherits(m_g_raw, "Jointlcmm")) m_g <- m_g_raw else if (is.list(m_g_raw) && inherits(m_g_raw$best, "Jointlcmm")) m_g <- m_g_raw$best else m_g <- m_g_raw
    if (is.null(m_g$pprob)) return(ctx)
    pprob_df <- as.data.frame(m_g$pprob)
    class_assign <- pprob_df[, c("subject_id_num", "class")]
    subj_class <- unique(model_data_final[, c(id_col, "subject_id_num")])
    subj_class <- dplyr::left_join(subj_class, class_assign, by = "subject_id_num")
    subj_class <- subj_class[, c(id_col, "class")]
    names(subj_class)[2] <- "trajectory_class"
    subj_class$trajectory_class <- as.integer(subj_class$trajectory_class)
    for (slot in c("imputed", "cleaned")) {
      if (!is.null(ctx$data[[slot]]) && id_col %in% names(ctx$data[[slot]])) {
        tgt <- ctx$data[[slot]]
        tgt[[id_col]] <- as.character(tgt[[id_col]])
        tgt$trajectory_class <- NULL
        tgt <- dplyr::left_join(tgt, dplyr::mutate(subj_class, !!id_col := as.character(.data[[id_col]])), by = id_col)
        ctx$data[[slot]] <- tgt
      }
    }
    cli::cli_alert_success("{Index}: ng={assign_ng} 类别已回写")
    ctx
  }

  ctx <- .jfix_write_class(ctx, Index, selected_ng, model_data_final, models_list, id_col)
  ctx
}

for (db in opt$dbs) {
  cli::cli_h1("[{ix}] {toupper(db)} — 修复 JLCM 类别回写 + 下游表")
  ck_dir <- trajectory_batch_index_ck_dir(config_ix, ix, db)
  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(ck_dir, "trajectory_jlcm"),
    error = function(e) { cli::cli_alert_danger("载入检查点失败: {conditionMessage(e)}"); NULL }
  )
  if (is.null(ctx)) next

  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  cfg_db <- config_ix
  cfg_db$project$database   <- db_cfg$name %||% toupper(db)
  cfg_db$project$output_dir <- file.path(config_ix$project$output_dir, db)
  ctx$config <- cfg_db
  ctx$root_output_dir <- cfg_db$project$output_dir

  ctx <- .fix_jlcm_assign(ctx, cfg_db, ix)

  pl <- pipeline_unit
  pl$checkpoint <- list(enable = TRUE, dir = ck_dir)
  cfg_db$trajectory_piecewise_cox$pause_on_no_output <- FALSE
  cfg_db$trajectory_baseline_by_class$pause_on_no_output <- FALSE

  tryCatch({
    run_pipeline(root, config = cfg_db, pipeline = pl,
                 run_opts = list(initial_ctx = ctx, only = downstream))
    cli::cli_alert_success("[{ix}/{toupper(db)}] 下游完成")
  }, error = function(e) cli::cli_alert_danger("{conditionMessage(e)}"))
}

trajectory_merge_table3_dual_db(config_ix$project$output_dir, index_name = ix, cut_from_db = "mimic", end_day = 28L)
message("修复脚本完成。")
