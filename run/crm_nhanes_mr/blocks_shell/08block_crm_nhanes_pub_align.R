###############################################################################
#  crm_nhanes_pub_align — NHANES CRM 发表产出对齐核对（Pub_align_checklist）
#
#  依据：本仓库设计 docs/superpowers/specs/2026-07-24-crm-nhanes-mr-design.md
#  （70_crm_nhanes_pub 产出清单：Figure S2 / Table S4 / Figure 1 / Table 2 / Table 4 /
#  Figure 3 及其数值伴随表）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  典型位置: pipeline 末尾（... → crm_nhanes_rcs_pub → crm_nhanes_pub_align）
#
#  说明（检查范围，证据链）：本块**只核对文件是否存在**（并在满足
#  config$project$mirror_pub_outputs_to_root 时调用 mirror_pub_output_to_root 补齐
#  尚未镜像到单元根目录的产出），**不**校验表内数值是否与原文一致（原文数值口径部分
#  【证据不足】，见各上游 block 文件头注释）。required_artifacts 默认清单覆盖
#  Task 3 + Task 4 已实现的产出；MR 相关产出（Task 5，尚未实现）不在默认清单中，
#  避免在其未实现阶段被误判为 FAIL——如需纳入，可在 config 中追加。
#
#  crm_nhanes_pub_align = list(
#    required_artifacts = NULL,   # NULL → 使用下方 .crm70a_default_required_artifacts()
#    checklist_filename = "Pub_align_checklist.csv",   # 固定名
#    pause_enable          = TRUE,
#    pause_on_any_fail      = FALSE   # TRUE → 有任一 FAIL 时 PAUSE_FOR_USER_DECISION
#  )
#
#  register_block: "crm_nhanes_pub_align"
#
#  读: ctx$output_dir_tables / ctx$output_dir_figures（及镜像目标 ctx$root_output_dir）
#  写: 无新增分析结果；仅镜像已存在但未同步到根目录的文件 + 写出核对清单
#
#  产出:
#    - [固定名] Tables/Pub_align_checklist.csv（Artifact/Expected_filename/Found/Path/Status）
#
#  pause: config$crm_nhanes_pub_align$pause_enable（仅当 pause_on_any_fail=TRUE 且存在 FAIL 时触发）
###############################################################################

.crm70a_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70a_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 20L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_pub_align",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_pub_align halted. See ctx$results$pause_point. / ",
    "NHANES 发表产出对齐核对存在 FAIL 项，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

#' 默认必需产出清单（Task 3 + Task 4 已实现范围；每项给出候选文件名——图形类给出
#' pdf/png 两个候选，命中任一即视为 Found）
.crm70a_default_required_artifacts <- function() {
  list(
    list(artifact = "Figure_S2_Flowchart", dir = "Figures",
         candidates = c(
           "Figure S2-NHANES-Study_population_flowchart.pdf",
           "Figure_S2_Flowchart.pdf", "Figure_S2_Flowchart.png"
         )),
    list(artifact = "Table_S4_Baseline_NHANES", dir = "Tables",
         candidates = c("Table_S4_Baseline_NHANES.csv")),
    list(artifact = "Figure_1_KM_NHANES", dir = "Figures",
         candidates = c(
           "Figure 1-NHANES-Kaplan-Meier_all-cause_mortality_by_CRM_count.pdf",
           "Figure_1_KM_NHANES.pdf", "Figure_1_KM_NHANES.png"
         )),
    list(artifact = "Table_2_Ordinal_NHANES", dir = "Tables",
         candidates = c("Table_2_Ordinal_NHANES.csv")),
    list(artifact = "Table_4_Cox_NHANES", dir = "Tables",
         candidates = c("Table_4_Cox_NHANES.csv")),
    list(artifact = "Figure_3_RCS_NHANES", dir = "Figures",
         candidates = c(
           "Figure 3-NHANES-RCS_SUA_all-cause_mortality_by_CRM.pdf",
           "Figure_3_RCS_NHANES.pdf", "Figure_3_RCS_NHANES.png"
         )),
    list(artifact = "Table_3_RCS_NHANES", dir = "Tables",
         candidates = c("Table_3_RCS_NHANES.csv"))
  )
}

#' 在给定的一组目录中查找候选文件名，返回第一个命中的绝对路径（未命中则 NA）
.crm70a_find_first <- function(dirs, candidates) {
  for (dd in dirs) {
    if (is.null(dd) || !nzchar(dd) || !dir.exists(dd)) next
    for (fn in candidates) {
      p <- file.path(dd, fn)
      if (file.exists(p)) {
        fi <- tryCatch(file.info(p), error = function(e) NULL)
        if (!is.null(fi) && !is.na(fi$size) && fi$size > 0) return(p)
      }
    }
  }
  NA_character_
}

block_crm_nhanes_pub_align <- function(ctx, ...) {
  suppressPackageStartupMessages(library(cli))
  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_pub_align %||% list()
  prj <- cfg$project %||% list()

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  root <- ctx$root_output_dir %||% NULL
  root_fig_dir <- if (!is.null(root) && nzchar(root)) file.path(root, "Figures") else NULL
  root_tbl_dir <- if (!is.null(root) && nzchar(root)) file.path(root, "Tables") else NULL

  artifacts <- bl_cfg$required_artifacts %||% .crm70a_default_required_artifacts()

  rows <- vector("list", length(artifacts))
  n_mirrored <- 0L
  mirror_on <- isTRUE(prj$mirror_pub_outputs_to_root %||% FALSE)

  for (i in seq_along(artifacts)) {
    a <- artifacts[[i]]
    search_dirs <- if (identical(a$dir, "Figures")) c(fig_dir, root_fig_dir) else c(tbl_dir, root_tbl_dir)
    found_path <- .crm70a_find_first(search_dirs, a$candidates)
    found <- !is.na(found_path)

    if (found && mirror_on && exists("mirror_pub_output_to_root", mode = "function")) {
      # 若根目录尚无同名文件，补齐镜像；按文件名（而非 found_path 具体来自哪个目录）判断，
      # 避免 .crm70a_find_first() 优先命中 step 子目录副本时，对已镜像过的文件重复复制。
      root_dir_i <- if (identical(a$dir, "Figures")) root_fig_dir else root_tbl_dir
      already_in_root <- !is.null(root_dir_i) &&
        file.exists(file.path(root_dir_i, basename(found_path)))
      if (!already_in_root) {
        ok <- tryCatch(mirror_pub_output_to_root(ctx, found_path), error = function(e) FALSE)
        if (isTRUE(ok)) n_mirrored <- n_mirrored + 1L
      }
    }

    rows[[i]] <- data.frame(
      Artifact = a$artifact,
      Expected_filename = paste(a$candidates, collapse = " | "),
      Found = found,
      Path = if (found) found_path else NA_character_,
      Status = if (found) "PASS" else "FAIL",
      stringsAsFactors = FALSE
    )
  }
  checklist <- do.call(rbind, rows)
  n_fail <- sum(checklist$Status == "FAIL")

  tbl_fn <- as.character(bl_cfg$checklist_filename %||% "Pub_align_checklist.csv")[1L]
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(checklist, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_pub_align 清单写出失败: {e$message}")
  )
  if (mirror_on && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
  }

  if (n_fail > 0L) {
    cli::cli_alert_warning(
      "crm_nhanes_pub_align: {n_fail}/{nrow(checklist)} 项 FAIL — {paste(checklist$Artifact[checklist$Status=='FAIL'], collapse=', ')}"
    )
    if (.crm70a_should_pause(bl_cfg, "pause_on_any_fail", FALSE)) {
      .crm70a_pause(ctx, paste0(n_fail, " 项发表产出缺失。"),
                   "检查对应上游 block 是否已成功运行并产出文件。", checklist)
    }
  }

  ctx$results$crm_nhanes_pub_align <- list(
    checklist = checklist,
    n_pass = nrow(checklist) - n_fail,
    n_fail = n_fail,
    n_mirrored = n_mirrored,
    checklist_path = tbl_path
  )
  cli::cli_alert_success(
    "crm_nhanes_pub_align 完成（PASS={nrow(checklist) - n_fail}/{nrow(checklist)}, mirrored={n_mirrored}）"
  )
  ctx
}

register_block(
  "crm_nhanes_pub_align",
  block_crm_nhanes_pub_align,
  "NHANES 发表产出对齐核对清单（Pub_align_checklist.csv）"
)
