###############################################################################
#  ipw_pub_export — IPW 糖尿病批次发表产出汇总镜像（Tables/Figures → 单元根目录）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_config = config$project$mirror_pub_outputs_to_root（TRUE 才执行镜像）
#
#  ipw_pub_export = list(
#    manifest_filename = "00_Literature_Output_Manifest.csv",
#    pause_enable         = TRUE,
#    pause_on_empty_root  = FALSE
#  )
#
#  register_block: "ipw_pub_export"
#  典型位置: ... → ipw_literature_targets → ipw_pub_export（pipeline 末尾）
#
#  读: ctx$root_output_dir, ctx$log$block_output_dirs（各 step 子目录 Tables/Figures）
#  写: 无新增分析结果；仅镜像文件 + 写出根目录清单
#
#  产出:
#    - 各 step 子目录下已落盘的 .xlsx/.csv（Tables）与 .pdf/.png/.jpg（Figures）
#      被镜像/同步到 <单元根目录>/Tables、/Figures（sync_all_block_pub_outputs_to_root）
#    - [固定名] <root>/Tables/00_Literature_Output_Manifest.csv（Figure/Table 清单）
#
#  说明: run_block() 已在每个 block 结束后自动调用 mirror_block_pub_outputs()
#  镶镜像当前 block 子目录；本块作为流水线末尾的兜底/汇总步骤，调用现有通用工具
#  sync_all_block_pub_outputs_to_root() 补齐可能遗漏的历史 step 子目录，并输出
#  清单，不重复实现镜像逻辑（复用 R/utils.R 现有函数，不新增/修改基础设施代码）。
#
#  pause: config$ipw_pub_export$pause_enable
###############################################################################

.pe07_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.pe07_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 10L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "ipw_pub_export",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ipw_pub_export halted. See ctx$results$pause_point. / ",
    "发表导出异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

block_ipw_pub_export <- function(ctx, ...) {
  cfg <- ctx$config
  bl_cfg <- cfg$ipw_pub_export %||% list()
  prj <- cfg$project %||% list()

  mirror_on <- isTRUE(prj$mirror_pub_outputs_to_root %||% FALSE)
  if (!mirror_on) {
    cli::cli_alert_info("ipw_pub_export: config$project$mirror_pub_outputs_to_root 非 TRUE，跳过镜像。")
    ctx$results$ipw_pub_export <- list(mirrored = FALSE, reason = "mirror_pub_outputs_to_root=FALSE")
    return(ctx)
  }

  root <- ctx$root_output_dir %||% NULL
  if (is.null(root) || !nzchar(root) || !dir.exists(root)) {
    msg <- "ipw_pub_export: ctx$root_output_dir 不存在，无法镜像到单元根目录。"
    if (.pe07_should_pause(bl_cfg, "pause_on_empty_root", FALSE)) {
      .pe07_pause(ctx, msg, "检查 config$project$output_dir 是否已设置且目录存在。", NULL)
    }
    cli::cli_alert_warning(msg)
    ctx$results$ipw_pub_export <- list(mirrored = FALSE, reason = "root_output_dir missing")
    return(ctx)
  }

  if (exists("sync_all_block_pub_outputs_to_root", mode = "function")) {
    ctx <- sync_all_block_pub_outputs_to_root(ctx)
  } else if (exists("mirror_block_pub_outputs", mode = "function")) {
    ctx <- mirror_block_pub_outputs(ctx)
  }

  root_tables <- file.path(root, "Tables")
  root_figs <- file.path(root, "Figures")
  figs <- if (dir.exists(root_figs)) {
    sort(list.files(root_figs, pattern = "\\.(pdf|png|jpg|jpeg)$", ignore.case = TRUE))
  } else character(0)
  tabs <- if (dir.exists(root_tables)) {
    sort(list.files(root_tables, pattern = "\\.(xlsx|csv)$", ignore.case = TRUE))
  } else character(0)

  manifest <- data.frame(
    type = c(rep("Figure", length(figs)), rep("Table", length(tabs))),
    file = c(figs, tabs),
    stringsAsFactors = FALSE
  )
  manifest_fn <- as.character(bl_cfg$manifest_filename %||% "00_Literature_Output_Manifest.csv")[1L]
  if (dir.exists(root_tables)) {
    tryCatch(
      utils::write.csv(manifest, file.path(root_tables, manifest_fn), row.names = FALSE),
      error = function(e) cli::cli_alert_warning("发表产出清单写出失败: {e$message}")
    )
  }

  ctx$results$ipw_pub_export <- list(
    mirrored = TRUE,
    root_output_dir = root,
    n_figures = length(figs),
    n_tables = length(tabs),
    figures = figs,
    tables = tabs
  )
  cli::cli_alert_success(
    "ipw_pub_export 完成（root={.file {root}}, figures={length(figs)}, tables={length(tabs)}）"
  )
  ctx
}

register_block(
  "ipw_pub_export",
  block_ipw_pub_export,
  "IPW 糖尿病批次发表产出汇总镜像（Tables/Figures → 单元根目录）"
)
