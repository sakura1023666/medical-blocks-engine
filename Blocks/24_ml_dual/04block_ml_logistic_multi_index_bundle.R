###############################################################################
#  ml_logistic_multi_index_bundle — Phase2 多指标：各指标独立 cutoff/logistic/RCS/亚组
#
#  register_block: "ml_logistic_multi_index_bundle"
#  当 prediction$index_vars 长度 > 1 时，对每个指标依次跑发病 NHANES 暴露分析支路，
#  各出一张 logistic 主表（Table 2）及对应 RCS/亚组图；ML 下游仍用合并指标。
###############################################################################

.ml_lmi_sub_blocks <- function() {
  c(
    "cutoff", "obj", "baseline_nhanes", "boxplot",
    "logistic_quartile_nhanes_weighted", "logistic_tertile_nhanes_weighted",
    "logistic_binary_nhanes_weighted",
    "rcs_nhanes",
    "logistic_quartile_nhanes_weighted_rcs", "logistic_tertile_nhanes_weighted_rcs",
    "logistic_binary_nhanes_weighted_rcs",
    "subgroup_nhanes_weighted"
  )
}

.ml_lmi_reset_logistic_state <- function(ctx) {
  keys <- c(
    "logistic_branch", "nhanes_logistic_selected_scheme", "nhanes_logistic_unified_scheme",
    "dual_db_logistic_unified_scheme", "dual_db_logistic_needs_realign",
    "nhanes_cutoff", "nhanes_cutoff_index", "nhanes_roc_auc"
  )
  for (k in keys) ctx$results[[k]] <- NULL
  ctx
}

.ml_lmi_run_sub_block <- function(ctx, block_name, pipeline) {
  if (exists("pipeline_logistic_gate_should_skip", mode = "function") &&
      pipeline_logistic_gate_should_skip(block_name, ctx, pipeline)) {
    cli::cli_alert_info("logistic_gate 跳过 {.field {block_name}}（分支: {ctx$results$logistic_branch %||% '?'}）")
    return(ctx)
  }
  if (exists(".lnw00_should_skip_cascade_block", mode = "function") &&
      .lnw00_should_skip_cascade_block(block_name, ctx)) {
    cli::cli_alert_info(
      "logistic cascade 跳过 {.field {block_name}}（已选定 {ctx$results$nhanes_logistic_selected_scheme}）"
    )
    return(ctx)
  }
  run_block(ctx, block_name)
}

block_ml_logistic_multi_index_bundle <- function(ctx) {
  cfg <- ctx$config
  indices <- unique(as.character(cfg$prediction$index_vars %||% character(0)))
  indices <- indices[nzchar(indices)]
  if (length(indices) <= 1L) {
    cli::cli_alert_info("ml_logistic_multi_index_bundle: 单指标模式，跳过（由 pipeline 各 block 执行）。")
    return(ctx)
  }

  if (!exists("incidence_batch_patch_config_for_index", mode = "function")) {
    root <- cfg$project$root %||% getwd()
    inc_path <- file.path(root, "R", "incidence_dual_batch_runner.R")
    if (file.exists(inc_path)) source(inc_path, local = FALSE)
  }

  sub_blocks <- .ml_lmi_sub_blocks()
  pipe_stub <- list(
    blocks = sub_blocks,
    logistic_gate = list(enable = TRUE, weighted = TRUE)
  )
  render_tables_after <- sub_blocks
  render_figures_after <- c("cutoff", "boxplot", "rcs_nhanes", "subgroup_nhanes_weighted")

  combined_indices <- indices
  ok_ix <- character(0)
  err_ix <- list()

  for (ix in indices) {
    cli::cli_h2("multi-index logistic 支路: {ix}")
    ctx_ix <- .ml_lmi_reset_logistic_state(ctx)
    if (exists("incidence_batch_patch_config_for_index", mode = "function")) {
      cfg_ix <- incidence_batch_patch_config_for_index(cfg, ix)
      cfg_ix$prediction$index_vars <- combined_indices
      cfg_ix$feature_selection$composite_features <- combined_indices
      ctx_ix$config <- cfg_ix
    }

    failed <- FALSE
    for (b in sub_blocks) {
      ctx_ix <- tryCatch(
        {
          out <- .ml_lmi_run_sub_block(ctx_ix, b, pipe_stub)
          if (b %in% render_tables_after && exists("render_queued_tables", mode = "function")) {
            out <- render_queued_tables(out)
          }
          if (b %in% render_figures_after && exists("render_queued_figures", mode = "function")) {
            out <- render_queued_figures(out)
          }
          out
        },
        error = function(e) {
          msg <- conditionMessage(e)
          if (grepl("^BASELINE_INDEX_NS_STOP:", msg)) {
            cli::cli_alert_warning("[{ix}] baseline 早停: {msg}")
          } else {
            cli::cli_alert_warning("[{ix}] block {b} 失败: {msg}")
          }
          failed <<- TRUE
          ctx_ix
        }
      )
      if (failed) break
    }
    if (failed) {
      err_ix[[ix]] <- "logistic branch failed"
    } else {
      ok_ix <- c(ok_ix, ix)
    }
  }

  ctx$results$ml_multi_index_logistic_indices <- ok_ix
  ctx$results$ml_multi_index_logistic_errors <- err_ix
  if (length(ok_ix)) {
    cli::cli_alert_success(
      "multi-index logistic 完成 {length(ok_ix)}/{length(indices)}: {paste(ok_ix, collapse=', ')}"
    )
  } else {
    cli::cli_alert_warning("multi-index logistic 全部失败或未产出主表。")
  }
  ctx
}

register_block(
  "ml_logistic_multi_index_bundle",
  block_ml_logistic_multi_index_bundle,
  "Multi-index NHANES logistic/RCS/subgroup bundle (one Table 2 per index)"
)
