###############################################################################
#  crm_nhanes_flowchart — NHANES CRM 队列入排流程图（对应文献 Figure S2）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data    = ctx$data$cleaned %||% ctx$data$raw（须先运行 crm_nhanes_derive）
#  require_results = ctx$results$crm_nhanes_derive（可选，用于起始队列 n / min_age 快照）
#
#  说明（证据链约束 / Task 3 fix）：本块的五级漏斗——原始/合并 n → 年龄入排 →
#  SUA 非缺失 → 死亡随访合格 → 最终分析集——优先直接读取 crm_nhanes_derive 写入
#  ctx$results$crm_nhanes_derive 的 n_merged/n_age/n_sua/n_mort_elig/n 快照（该
#  block 在合并死亡链接后、年龄入排前后均已记录计数，见其文件头）。若某次运行的
#  crm_nhanes_derive 未提供完整快照（例如旧版产物），本块会：
#    (a) 就地基于当前 data 重算 SUA/死亡随访/CRM_count 三级可得阶段并发出警告；
#    (b) 对无法从 data 反推的"原始/合并 n"如实省略该框，绝不用已清洗后的
#        nrow(data) 冒充原始/合并 n；
#    (c) 若 config$crm_nhanes_flowchart$pause_on_missing_funnel = TRUE，则改为
#        pause 而不是仅警告。
#
#  crm_nhanes_flowchart = list(
#    cohort_label            = NULL,     # NULL → 自动生成合并/年龄入排框文案（覆盖首个可用框）
#    sua_col                 = "SUA",
#    time_var                = "futime",
#    event_var               = "fustatus",
#    crm_col                 = "CRM_count",
#    eligibility_col         = "eligstat",  # NHANES 死亡链接可用标记；不存在则退化为 time/event 非缺失判定
#    figure_basename         = "Figure_S2_Flowchart",   # 固定文件名（不经过发表编号计数器）
#    figure_caption          = "Flowchart of participant selection (NHANES, CRM cohort)",
#    table_filename          = "Table_CRM_NHANES_Flowchart_Counts.csv",  # 固定名，不占发表表序号
#    pause_enable            = TRUE,
#    pause_on_no_output      = TRUE,
#    pause_on_missing_funnel = FALSE    # TRUE → crm_nhanes_derive 漏斗快照不完整时 pause 而非仅警告
#  )
#
#  register_block: "crm_nhanes_flowchart"
#  典型位置: crm_nhanes_derive → crm_nhanes_flowchart → crm_nhanes_baseline_weighted → ...
#
#  读: ctx$data$cleaned %||% ctx$data$raw；ctx$results$crm_nhanes_derive（起始 n / min_age）
#  写: ctx$results$crm_nhanes_flowchart
#
#  产出:
#    - [固定名] Figures/Figure_S2_Flowchart.pdf / .png
#    - [固定名] Tables/Table_CRM_NHANES_Flowchart_Counts.csv（逐步计数明细）
#
#  pause: config$crm_nhanes_flowchart$pause_enable
###############################################################################

.crm70f_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.crm70f_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "crm_nhanes_flowchart",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: crm_nhanes_flowchart halted. See ctx$results$pause_point. / ",
    "NHANES 流程图统计异常，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

# 基础图形设备绘制 CONSORT 风格流程图（纳入框纵向排列 + 侧向剔除框）
.crm70f_draw_flowchart_device <- function(steps, title) {
  graphics::plot.new()
  graphics::title(main = title, cex.main = 1.0)

  n_box <- sum(steps$kind == "include")
  y_pos <- seq(0.92, 0.08, length.out = max(1L, n_box))
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
      graphics::rect(xc - 0.32, yc - 0.052, xc + 0.32, yc + 0.052,
                     border = "black", lwd = 1.4, col = "white")
      graphics::text(xc, yc, sprintf("%s\n(n = %s)", lab, format(n, big.mark = ",")), cex = 0.70)
      if (is.finite(prev_yc)) {
        graphics::arrows(xc, prev_yc - 0.052, xc, yc + 0.052, length = 0.08, lwd = 1.2)
      }
      prev_yc <- yc
    } else if (identical(kind, "exclude") && is.finite(prev_yc)) {
      xe <- 0.83
      ye <- prev_yc - 0.02
      graphics::rect(xe - 0.18, ye - 0.045, xe + 0.18, ye + 0.045,
                     border = "grey30", lwd = 1,
                     col = grDevices::adjustcolor("grey90", 0.8))
      graphics::text(xe, ye, sprintf("Excluded\n%s\n(n = %s)", lab, format(n, big.mark = ",")), cex = 0.56)
      graphics::arrows(0.38 + 0.32, prev_yc, xe - 0.18, ye, length = 0.07, lwd = 1)
    }
  }
  invisible(NULL)
}

.crm70f_draw_flowchart_to <- function(steps, outfile, title, device = c("pdf", "png")) {
  device <- match.arg(device)
  dir.create(dirname(outfile), recursive = TRUE, showWarnings = FALSE)
  n_box <- max(1L, sum(steps$kind == "include"))
  if (identical(device, "pdf")) {
    grDevices::pdf(outfile, width = 8.5, height = max(6, 1.1 * n_box + 2))
  } else {
    grDevices::png(outfile, width = 1700, height = max(1300, 240 * n_box + 400), res = 200)
  }
  on.exit(grDevices::dev.off(), add = TRUE)
  op <- graphics::par(mar = c(1, 1, 2.5, 1))
  on.exit(graphics::par(op), add = TRUE)
  .crm70f_draw_flowchart_device(steps, title)
  invisible(NULL)
}

.crm70f_file_ok <- function(path) {
  fi <- tryCatch(file.info(path), error = function(e) NULL)
  !is.null(fi) && isTRUE(nrow(fi) == 1L) && !is.na(fi$size) && fi$size > 10L
}

block_crm_nhanes_flowchart <- function(ctx, ...) {
  mode <- (ctx$config$attrition %||% list())$specialty_figure_mode %||% "skip_if_generic"
  pipe_blocks <- ctx$pipeline_blocks %||% character(0)
  if (identical(mode, "skip_if_generic") && "attrition_flowchart" %in% pipe_blocks) {
    cli::cli_alert_info("pipeline 含 attrition_flowchart，跳过专用 Figure 1")
    return(ctx)
  }

  cfg <- ctx$config
  bl_cfg <- cfg$crm_nhanes_flowchart %||% list()

  data <- ctx$data$cleaned %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data) || !nrow(data)) {
    if (.crm70f_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .crm70f_pause(ctx, "未找到分析数据（ctx$data$cleaned 与 raw 均为空）。",
                   "请先运行 crm_nhanes_derive。", NULL)
    }
    stop("crm_nhanes_flowchart: 无分析数据。", call. = FALSE)
  }

  derive_snap <- ctx$results$crm_nhanes_derive %||% list()
  sua_col <- as.character(bl_cfg$sua_col %||% "SUA")[1L]
  time_var <- as.character(bl_cfg$time_var %||% "futime")[1L]
  event_var <- as.character(bl_cfg$event_var %||% "fustatus")[1L]
  crm_col <- as.character(bl_cfg$crm_col %||% "CRM_count")[1L]
  elig_col <- as.character(bl_cfg$eligibility_col %||% "eligstat")[1L]

  min_age <- suppressWarnings(as.numeric(
    derive_snap$min_age %||% (cfg$crm_nhanes_pub %||% list())$min_age %||% 45
  ))[1L]

  # ── 漏斗计数：优先读取 crm_nhanes_derive 记录的 n_merged/n_age/n_sua/
  #    n_mort_elig/n；缺失时就地基于 data 重算对应阶段（并发出警告/可选 pause），
  #    但绝不用已清洗后的 nrow(data) 冒充 raw/merged n（见文件头说明）。
  .crm70f_num_or_na <- function(x) {
    v <- suppressWarnings(as.integer(x %||% NA_integer_))[1L]
    if (!length(v) || !is.finite(v)) NA_integer_ else v
  }
  n_merged_snap <- .crm70f_num_or_na(derive_snap$n_merged)
  n_age_snap    <- .crm70f_num_or_na(derive_snap$n_age)
  n_sua_snap    <- .crm70f_num_or_na(derive_snap$n_sua)
  n_elig_snap   <- .crm70f_num_or_na(derive_snap$n_mort_elig)
  n_final_snap  <- .crm70f_num_or_na(derive_snap$n)

  funnel_complete <- all(is.finite(c(n_merged_snap, n_age_snap, n_sua_snap, n_elig_snap, n_final_snap)))
  if (!funnel_complete) {
    funnel_warn <- paste0(
      "crm_nhanes_flowchart: ctx$results$crm_nhanes_derive 缺少完整漏斗计数",
      "（n_merged/n_age/n_sua/n_mort_elig/n 至少一项缺失，可能是旧版 crm_nhanes_derive ",
      "产物）。将基于当前 data 就地重算可得阶段；raw/merged n 若不可得会如实省略，",
      "不会用已清洗后的 nrow(data) 冒充原始/合并 n。"
    )
    if (.crm70f_should_pause(bl_cfg, "pause_on_missing_funnel", FALSE)) {
      .crm70f_pause(ctx, funnel_warn,
                   "请先运行已记录漏斗计数的 crm_nhanes_derive（Task 3 fix），或设 pause_on_missing_funnel = FALSE。",
                   data)
    }
    cli::cli_alert_warning(funnel_warn)
  }

  steps <- data.frame(step = integer(0), kind = character(0), label = character(0),
                      n = integer(0), stringsAsFactors = FALSE)
  .add <- function(kind, label, n) {
    steps <<- rbind(steps, data.frame(
      step = nrow(steps) + 1L, kind = kind, label = label, n = as.integer(n),
      stringsAsFactors = FALSE
    ))
  }

  cohort_override <- if (!is.null(bl_cfg$cohort_label)) as.character(bl_cfg$cohort_label)[1L] else NULL
  merged_label <- "NHANES participants after mortality-linkage merge (pre age-filter)"
  age_label <- paste0("Age \u2265 ", min_age)
  if (!is.null(cohort_override)) {
    if (is.finite(n_merged_snap)) merged_label <- cohort_override else age_label <- cohort_override
  }

  # ---- Stage 1: raw/merged n（仅当 derive 快照提供 n_merged 时展示） ----
  if (is.finite(n_merged_snap)) {
    .add("include", merged_label, n_merged_snap)
  }

  # ---- Stage 2: 年龄入排。data 在传入本 block 前已由 crm_nhanes_derive 应用
  #      年龄入排，因此即使 n_age_snap 缺失，nrow(data) 本身就是诚实的"年龄入排后"
  #      计数（不是原始/合并 n，只是碰巧与之同源）。----
  n_age_use <- if (is.finite(n_age_snap)) n_age_snap else nrow(data)
  if (is.finite(n_merged_snap)) {
    n_excl_age <- n_merged_snap - n_age_use
    if (is.finite(n_excl_age) && n_excl_age > 0L) {
      .add("exclude", paste0("Age < ", min_age, " or missing"), n_excl_age)
    }
  }
  .add("include", age_label, n_age_use)

  # ---- Stage 3: SUA 非缺失 ----
  cur <- data
  if (sua_col %in% names(cur)) {
    cur <- cur[!is.na(cur[[sua_col]]), , drop = FALSE]
  }
  n_sua_local <- nrow(cur)
  n_sua_use <- if (is.finite(n_sua_snap)) n_sua_snap else n_sua_local
  if (is.finite(n_sua_snap) && n_sua_snap != n_sua_local) {
    cli::cli_alert_warning(
      "crm_nhanes_flowchart: n_sua 快照({n_sua_snap}) 与就地重算({n_sua_local}) 不一致，图中采用快照值。"
    )
  }
  n_excl_sua <- n_age_use - n_sua_use
  if (is.finite(n_excl_sua) && n_excl_sua > 0L) {
    .add("exclude", paste0("Missing ", sua_col), n_excl_sua)
  }
  .add("include", paste0(sua_col, " non-missing"), n_sua_use)

  # ---- Stage 4: 死亡随访合格 ----
  if (elig_col %in% names(cur)) {
    keep_elig <- cur[[elig_col]] %in% c(1, "1")
    cur <- cur[keep_elig, , drop = FALSE]
  } else if (all(c(time_var, event_var) %in% names(cur))) {
    keep_fu <- !is.na(cur[[time_var]]) & !is.na(cur[[event_var]]) &
      suppressWarnings(as.numeric(cur[[time_var]])) >= 0
    keep_fu[is.na(keep_fu)] <- FALSE
    cur <- cur[keep_fu, , drop = FALSE]
  }
  n_elig_local <- nrow(cur)
  n_elig_use <- if (is.finite(n_elig_snap)) n_elig_snap else n_elig_local
  if (is.finite(n_elig_snap) && n_elig_snap != n_elig_local) {
    cli::cli_alert_warning(
      "crm_nhanes_flowchart: n_mort_elig 快照({n_elig_snap}) 与就地重算({n_elig_local}) 不一致，图中采用快照值。"
    )
  }
  n_excl_elig <- n_sua_use - n_elig_use
  if (is.finite(n_excl_elig) && n_excl_elig > 0L) {
    .add("exclude", "Not eligible for mortality follow-up (eligstat \u2260 1 or missing time/status)", n_excl_elig)
  }
  .add("include", "Mortality follow-up eligible", n_elig_use)

  # ---- Stage 5: 最终分析集（CRM_count 有值） ----
  if (crm_col %in% names(cur)) {
    cur <- cur[!is.na(cur[[crm_col]]), , drop = FALSE]
  }
  n_final_local <- nrow(cur)
  n_final_use <- if (is.finite(n_final_snap)) n_final_snap else n_final_local
  if (is.finite(n_final_snap) && n_final_snap != n_final_local) {
    cli::cli_alert_warning(
      "crm_nhanes_flowchart: 最终分析 n 快照({n_final_snap}) 与就地重算({n_final_local}) 不一致，图中采用快照值。"
    )
  }
  n_excl_final <- n_elig_use - n_final_use
  if (is.finite(n_excl_final) && n_excl_final > 0L) {
    .add("exclude", paste0("Missing ", crm_col, " (CVD/CKD/Diabetes component incomplete)"), n_excl_final)
  }
  .add("include", "Final analytic cohort (CRM_count defined)", n_final_use)

  n_start <- if (is.finite(n_merged_snap)) n_merged_snap else n_age_use
  n_analytic <- n_final_use
  outcome_rows <- data.frame(
    step = integer(0), kind = character(0), label = character(0), n = integer(0),
    stringsAsFactors = FALSE
  )
  if (crm_col %in% names(cur) && n_analytic > 0L) {
    crm_tab <- table(cur[[crm_col]])
    outcome_rows <- data.frame(
      step = nrow(steps) + seq_along(crm_tab),
      kind = "outcome",
      label = paste0(crm_col, " = ", names(crm_tab)),
      n = as.integer(crm_tab),
      stringsAsFactors = FALSE
    )
  }
  counts <- rbind(steps[, c("step", "kind", "label", "n")], outcome_rows)

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  tbl_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)

  fig_base <- as.character(bl_cfg$figure_basename %||%
    "Figure S1-NHANES-Study_population_flowchart")[1L]
  fig_caption <- as.character(bl_cfg$figure_caption %||%
    "Flowchart of participant selection (NHANES, CRM cohort)")[1L]
  pdf_path <- file.path(fig_dir, paste0(fig_base, ".pdf"))
  png_path <- file.path(fig_dir, paste0(fig_base, ".png"))

  saved_pdf <- tryCatch({
    .crm70f_draw_flowchart_to(counts, pdf_path, paste0("Figure S2. ", fig_caption), "pdf")
    .crm70f_file_ok(pdf_path)
  }, error = function(e) {
    cli::cli_alert_warning("crm_nhanes_flowchart PDF 绘制失败: {e$message}")
    FALSE
  })
  saved_png <- tryCatch({
    .crm70f_draw_flowchart_to(counts, png_path, paste0("Figure S2. ", fig_caption), "png")
    .crm70f_file_ok(png_path)
  }, error = function(e) {
    cli::cli_alert_warning("crm_nhanes_flowchart PNG 绘制失败: {e$message}")
    FALSE
  })

  if (isTRUE(saved_pdf) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, pdf_path)
  }
  if (isTRUE(saved_png) && exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, png_path)
  }

  tbl_fn <- as.character(bl_cfg$table_filename %||% "Table_CRM_NHANES_Flowchart_Counts.csv")[1L]
  tbl_path <- file.path(tbl_dir, tbl_fn)
  tryCatch(
    utils::write.csv(counts, tbl_path, row.names = FALSE),
    error = function(e) cli::cli_alert_warning("crm_nhanes_flowchart 计数表写出失败: {e$message}")
  )
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, tbl_path)
  }

  if (!isTRUE(saved_pdf) && !isTRUE(saved_png) &&
      .crm70f_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
    .crm70f_pause(ctx, "crm_nhanes_flowchart 未能生成流程图 PDF/PNG。",
                 "检查绘图设备是否可用、data 是否为空。", cur)
  }

  ctx$results$crm_nhanes_flowchart <- list(
    table = counts,
    steps = steps,
    n_start = n_start,
    n_analytic = n_analytic,
    n_merged = n_merged_snap,
    n_age = n_age_use,
    n_sua = n_sua_use,
    n_mort_elig = n_elig_use,
    funnel_from_snapshot = funnel_complete,
    figure_pdf = if (isTRUE(saved_pdf)) pdf_path else NA_character_,
    figure_png = if (isTRUE(saved_png)) png_path else NA_character_,
    table_path = tbl_path
  )
  cli::cli_alert_success(
    "crm_nhanes_flowchart 完成（n_start={n_start}, n_analytic={n_analytic}, funnel_from_snapshot={funnel_complete}）"
  )
  ctx
}

register_block(
  "crm_nhanes_flowchart",
  block_crm_nhanes_flowchart,
  "NHANES CRM 队列入排流程图（Figure S2）"
)
