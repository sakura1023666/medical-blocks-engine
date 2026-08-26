###############################################################################
#  ipw_diabetes_flowchart — IPW 糖尿病队列 CONSORT 流程图（对应文献 Figure 1）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data   = ctx$data$imputed %||% ctx$data$cleaned
#  require_results = ctx$results$ipw_diabetes_exposure（可选，来自 01block_ipw_diabetes_exposure）
#
#  ipw_diabetes = list(               # 与 01block_ipw_diabetes_exposure 共用
#    exposure_var = "Diabetes_HbA1c",
#    time_var     = "surv_time_28d",  # NULL → ctx$config$survival$time_var
#    event_var    = "surv_event_28d"  # NULL → ctx$config$survival$event_var
#  )
#  ipw_diabetes_flowchart = list(
#    cohort_label     = "Patients with ischemic stroke in MIMIC baseline cohort",
#    figure_number    = 1,            # 固定 Figure 1（CONSORT 流程图）
#    figure_caption   = "Flowchart of patient selection (IPW diabetes cohort)",
#    table_filename   = "Table_IPW_Flowchart_Counts.csv",  # 固定名，不占发表表序号
#    pause_enable        = TRUE,
#    pause_on_no_output  = TRUE
#  )
#
#  register_block: "ipw_diabetes_flowchart"
#  典型位置: iptw_balance → iptw_association → ipw_diabetes_flowchart
#
#  读: ctx$data$imputed %||% ctx$data$cleaned（当前分析集）
#      ctx$results$ipw_diabetes_exposure（暴露派生阶段的队列规模，若存在则优先使用）
#  写: ctx$results$ipw_diabetes_flowchart
#
#  产出:
#    - [main_figure] Figure_1_Flowchart  → pub_figure_filepath_at（固定 Fig.1）+ 基础绘图设备导出 PDF
#    - [固定名]      Table_IPW_Flowchart_Counts.csv → 逐步计数明细（不占发表表序号）
#
#  说明: analysis_exclusion 会在本块之前删除原始 HbA1c 等疾病列（保留派生的
#  Diabetes_HbA1c），因此本块的“HbA1c 相关”计数以 01block_ipw_diabetes_exposure
#  写入 ctx$results$ipw_diabetes_exposure 的快照为准；若该结果不存在，则退化为
#  仅基于当前数据的结局非缺失 / 最终分析集两步计数（原文未明确说明的中间步骤不编造）。
#
#  pause: config$ipw_diabetes_flowchart$pause_enable
###############################################################################

.if02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.if02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "ipw_diabetes_flowchart",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ipw_diabetes_flowchart halted. See ctx$results$pause_point. / ",
    "流程图统计异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

# 基础图形设备绘制 CONSORT 风格流程图（纳入框纵向排列 + 侧向剔除框）
.if02_draw_flowchart <- function(steps, outfile, title = "Flowchart of patient selection") {
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(outfile, width = 8.5, height = max(6, 1.1 * nrow(steps) + 2))
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- graphics::par(mar = c(1, 1, 2.5, 1))
  on.exit(graphics::par(op), add = TRUE)
  graphics::plot.new()
  graphics::title(main = title, cex.main = 1.05)

  n_box <- sum(steps$kind == "include")
  y_pos <- seq(0.90, 0.10, length.out = max(1L, n_box))
  box_i <- 0L
  prev_yc <- NA_real_

  for (i in seq_len(nrow(steps))) {
    kind <- steps$kind[i]
    lab <- steps$label[i]
    n <- steps$n[i]
    if (identical(kind, "include")) {
      box_i <- box_i + 1L
      yc <- y_pos[box_i]
      xc <- 0.38
      graphics::rect(xc - 0.30, yc - 0.055, xc + 0.30, yc + 0.055,
                     border = "black", lwd = 1.4, col = "white")
      graphics::text(xc, yc, sprintf("%s\n(n = %s)", lab, format(n, big.mark = ",")), cex = 0.76)
      if (is.finite(prev_yc)) {
        graphics::arrows(xc, prev_yc - 0.055, xc, yc + 0.055, length = 0.08, lwd = 1.2)
      }
      prev_yc <- yc
    } else if (identical(kind, "exclude") && is.finite(prev_yc)) {
      xe <- 0.80
      ye <- prev_yc - 0.02
      graphics::rect(xe - 0.18, ye - 0.045, xe + 0.18, ye + 0.045,
                     border = "grey30", lwd = 1,
                     col = grDevices::adjustcolor("grey90", 0.8))
      graphics::text(xe, ye, sprintf("Excluded\n%s\n(n = %s)", lab, format(n, big.mark = ",")), cex = 0.62)
      graphics::arrows(0.38 + 0.30, prev_yc, xe - 0.18, ye, length = 0.07, lwd = 1)
    }
  }
  invisible(NULL)
}

block_ipw_diabetes_flowchart <- function(ctx, ...) {
  mode <- (ctx$config$attrition %||% list())$specialty_figure_mode %||% "skip_if_generic"
  pipe_blocks <- ctx$pipeline_blocks %||% character(0)
  if (identical(mode, "skip_if_generic") && "attrition_flowchart" %in% pipe_blocks) {
    cli::cli_alert_info("pipeline 含 attrition_flowchart，跳过专用 Figure 1")
    return(ctx)
  }

  cfg <- ctx$config
  bl_cfg <- cfg$ipw_diabetes_flowchart %||% list()
  ipw_cfg <- cfg$ipw_diabetes %||% list()

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.if02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .if02_pause(ctx, "未找到分析数据（ctx$data$imputed 与 cleaned 均为空）。",
                 "请先运行 imputation / ipw_diabetes_exposure。", NULL)
    }
    stop("ipw_diabetes_flowchart: 无分析数据。", call. = FALSE)
  }

  exp_var <- as.character(ipw_cfg$exposure_var %||% "Diabetes_HbA1c")[1L]
  tvar <- as.character(ipw_cfg$time_var %||% cfg$survival$time_var %||% "surv_time_28d")[1L]
  yvar <- as.character(ipw_cfg$event_var %||% cfg$survival$event_var %||% "surv_event_28d")[1L]

  exposure_snap <- ctx$results$ipw_diabetes_exposure %||% list()
  n_exposure_stage <- suppressWarnings(as.integer(exposure_snap$n %||% NA_integer_))
  if (!is.finite(n_exposure_stage)) n_exposure_stage <- nrow(data)

  steps <- data.frame(step = integer(0), kind = character(0), label = character(0),
                      n = integer(0), stringsAsFactors = FALSE)
  .add <- function(kind, label, n) {
    steps <<- rbind(steps, data.frame(
      step = nrow(steps) + 1L, kind = kind, label = label, n = as.integer(n),
      stringsAsFactors = FALSE
    ))
  }

  cohort_lbl <- as.character(bl_cfg$cohort_label %||%
    "Patients with ischemic stroke in MIMIC baseline cohort")[1L]
  .add("include", cohort_lbl, n_exposure_stage)

  n_missing_time <- if (tvar %in% names(data)) sum(is.na(data[[tvar]])) else NA_integer_
  n_missing_event <- if (yvar %in% names(data)) sum(is.na(data[[yvar]])) else NA_integer_
  n_missing_outcome <- suppressWarnings(sum(c(n_missing_time, n_missing_event), na.rm = TRUE))
  if (is.finite(n_missing_outcome) && n_missing_outcome > 0L) {
    .add("exclude", "missing 28-day survival time / status", n_missing_outcome)
  }

  keep_idx <- rep(TRUE, nrow(data))
  if (tvar %in% names(data)) keep_idx <- keep_idx & !is.na(data[[tvar]])
  if (yvar %in% names(data)) keep_idx <- keep_idx & !is.na(data[[yvar]])
  if (exp_var %in% names(data)) keep_idx <- keep_idx & !is.na(data[[exp_var]])
  n_analytic <- sum(keep_idx)
  .add("include", "Final analytic cohort with Diabetes_HbA1c defined", n_analytic)

  data_analytic <- data[keep_idx, , drop = FALSE]
  exp_tab <- if (exp_var %in% names(data_analytic)) {
    table(data_analytic[[exp_var]], useNA = "ifany")
  } else {
    table(character(0))
  }
  n_diabetic <- as.integer(exp_tab[["1"]] %||% exposure_snap$n_diabetes %||% 0L)
  n_nondiabetic <- as.integer(exp_tab[["0"]] %||% max(0L, n_analytic - n_diabetic))

  counts <- rbind(
    steps[, c("step", "kind", "label", "n")],
    data.frame(
      step = nrow(steps) + 1:2,
      kind = "outcome",
      label = c(
        paste0(exp_var, " = 1 (diabetes, HbA1c \u2265 threshold)"),
        paste0(exp_var, " = 0 (no diabetes)")
      ),
      n = c(n_diabetic, n_nondiabetic),
      stringsAsFactors = FALSE
    )
  )

  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_IPW_Flowchart_Counts.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(counts, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("流程图计数表写出失败: {e$message}")
  )

  db_lab <- as.character(cfg$project$database %||% "MIMIC")[1L]
  fig_caption <- as.character(bl_cfg$figure_caption %||%
    paste0("Flowchart of patient selection (", db_lab, ", IPW diabetes cohort)"))[1L]
  fig_no <- suppressWarnings(as.integer(bl_cfg$figure_number %||% 1L))[1L]

  fig_path <- NULL
  saved <- FALSE
  if (exists("pub_figure_filepath_at", mode = "function") && is.finite(fig_no) && fig_no >= 1L) {
    fig_path <- pub_figure_filepath_at(fig_dir, fig_no, fig_caption, ext = "pdf", bump_counter = TRUE)
  } else if (exists("pub_figure_file", mode = "function")) {
    fig_path <- file.path(fig_dir, pub_figure_file(ctx, "main_figure", fig_caption))
  } else {
    fig_path <- file.path(fig_dir, "Figure_1_Flowchart.pdf")
  }

  tryCatch({
    .if02_draw_flowchart(steps, fig_path, title = paste0("Figure 1. ", fig_caption))
    saved <- file.exists(fig_path) && isTRUE(file.info(fig_path)$size > 10)
  }, error = function(e) {
    cli::cli_alert_warning("流程图绘制失败: {e$message}")
  })

  if (isTRUE(saved) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, fig_path)
  }

  if (!isTRUE(saved) && .if02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .if02_pause(ctx, "ipw_diabetes_flowchart 未能生成流程图 PDF。",
               "检查 ipw_diabetes_exposure 是否已运行、time/event 列是否存在。", data_analytic)
  }

  ctx$results$ipw_diabetes_flowchart <- list(
    table = counts,
    steps = steps,
    n_cohort = n_exposure_stage,
    n_analytic = n_analytic,
    n_diabetic = n_diabetic,
    n_nondiabetic = n_nondiabetic,
    figure_path = if (isTRUE(saved)) fig_path else NA_character_,
    table_path = tbl_path
  )
  cli::cli_alert_success(
    "ipw_diabetes_flowchart 完成（analytic n={n_analytic}, diabetes n={n_diabetic}）"
  )
  ctx
}

register_block(
  "ipw_diabetes_flowchart",
  block_ipw_diabetes_flowchart,
  "IPW 糖尿病队列 CONSORT 流程图（Figure 1）"
)
