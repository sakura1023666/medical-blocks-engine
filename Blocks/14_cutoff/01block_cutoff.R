###############################################################################
#  cutoff — NHANES 发病路径：ROC Youden 最优截断 + Binary/Tertile/Quartile 分组表。
#
#  register_block: "cutoff"
#  典型流水线: imputation → cutoff → obj（NHANES 专用）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  门控         = .is_nhanes_db(config)，否则跳过
#  指标列       = config$nhanes$cutoff_index_var 或 config$incidence$index_var
#  结局         = config$data$outcome_column；标签见 project$analysis_group / reference_group
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  写: nhanes_cutoff, nhanes_cutoff_index, nhanes_data_binary|_tert|_quart,
#      nhanes_roc_auc, nhanes_roc_auc_ci；cutoff_<index>.csv
#      （可选）单变量 ROC PDF，仅当 config$cutoff$export_roc_figure=TRUE
#  源: Blocks/block_cutoff.R / C00_ROC.R；依赖 pROC, ggplot2, dplyr
#  发表 Figure S* ROC 由 simple_ROC（多变量+锁定协变量）产出，勿与本块抢号
###############################################################################

.is_nhanes_db <- function(cfg) {
  dt <- tolower(trimws(as.character(cfg$project$database_type %||% "")))
  db <- tolower(trimws(as.character(cfg$project$database %||% "")))
  grepl("nhanes|nhance", dt) || grepl("nhanes|nhance", db)
}

block_cutoff <- function(ctx, ...) {
  cfg <- ctx$config

  if (!.is_nhanes_db(cfg)) {
    cli::cli_alert_info("block_cutoff: database_type 非 NHANES，跳过（直接返回 ctx）。")
    return(ctx)
  }

  suppressPackageStartupMessages({
    library(pROC)
    library(ggplot2)
    library(dplyr)
  })

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data)) stop("block_cutoff: 无数据，请先运行 imputation。")

  nhanes_cfg  <- cfg$nhanes %||% list()
  inc_cfg     <- cfg$incidence %||% list()
  proj_cfg    <- cfg$project  %||% list()

  index_var   <- as.character(nhanes_cfg$cutoff_index_var %||% inc_cfg$index_var %||% "")[1L]
  if (!nzchar(index_var)) stop("block_cutoff: 未指定 cutoff_index_var，请在 config$nhanes$cutoff_index_var 或 config$incidence$index_var 中设置。")

  .cutoff_coerce_numeric <- function(vec) {
    if (is.numeric(vec) && !is.factor(vec)) return(vec)
    # factor 必须走 character，避免 levels 编码 1..k 错位（如 0–3 变成 1–4）
    suppressWarnings(as.numeric(as.character(vec)))
  }
  .cutoff_pick_index_col <- function(ctx, index_var) {
    for (slot in c("imputed", "cleaned", "mapped")) {
      df <- ctx$data[[slot]]
      if (is.null(df) || !index_var %in% names(df)) next
      xv <- .cutoff_coerce_numeric(df[[index_var]])
      if (any(is.finite(xv))) return(list(data = df, vec = xv, slot = slot))
    }
    NULL
  }
  picked <- .cutoff_pick_index_col(ctx, index_var)
  if (is.null(picked)) {
    stop("block_cutoff: 列 '", index_var, "' 不在数据中或无法转为数值。", call. = FALSE)
  }
  data <- picked$data
  data[[index_var]] <- picked$vec
  ctx$data[[picked$slot]] <- data
  # trim 后 imputed/cleaned 行数可不同，禁止把同一向量写回其它槽；各槽独立 coerce
  for (slot in c("imputed", "cleaned", "mapped")) {
    if (identical(slot, picked$slot)) next
    df <- ctx$data[[slot]]
    if (is.null(df) || !is.data.frame(df) || !index_var %in% names(df)) next
    ctx$data[[slot]][[index_var]] <- .cutoff_coerce_numeric(df[[index_var]])
  }

  outcome_col  <- cfg$data$outcome_column %||% "Disease"
  disease_lbl  <- proj_cfg$analysis_group %||% proj_cfg$disease %||% "Case"
  normal_lbl   <- proj_cfg$reference_group %||% "Control"
  db_name      <- proj_cfg$database %||% "NHANES"

  if (!outcome_col %in% names(data)) stop("block_cutoff: 结局列 '", outcome_col, "' 不在数据中。")

  # ── Youden 截断值（基于原始指标 ROC）─────────────────────────────────────
  y <- data[[outcome_col]]
  x <- data[[index_var]]
  ok <- !is.na(x) & !is.na(y) & y %in% c(disease_lbl, normal_lbl)
  if (sum(ok) < 20L) stop("block_cutoff: 有效样本不足 20 行，请检查数据与标签。")

  roc_raw <- tryCatch(
    pROC::roc(
      response  = y[ok],
      predictor = x[ok],
      levels    = c(normal_lbl, disease_lbl),
      direction = "<",
      quiet     = TRUE
    ),
    error = function(e) NULL
  )
  if (is.null(roc_raw)) {
    roc_raw <- tryCatch(
      pROC::roc(
        response  = y[ok],
        predictor = x[ok],
        levels    = c(normal_lbl, disease_lbl),
        direction = ">",
        quiet     = TRUE
      ),
      error = function(e) NULL
    )
  }
  roc_fallback <- is.null(roc_raw)
  if (roc_fallback) {
    cutoff_val <- round(stats::median(x[ok], na.rm = TRUE), 4)
    auc_val <- NA_real_
    auc_ci <- c(NA_real_, NA_real_, NA_real_)
    cli::cli_alert_warning(
      "block_cutoff: pROC 失败，回退中位数截断 = {cutoff_val}（常见于 PIR 等社会经济指标）。"
    )
  } else {
    youden_idx <- which.max(roc_raw$sensitivities + roc_raw$specificities - 1)
    cutoff_val <- round(roc_raw$thresholds[youden_idx], 4)
    cli::cli_alert_success("block_cutoff: Youden 截断值 = {cutoff_val}")
  }

  # 保存截断值 CSV
  cutoff_csv <- file.path(ctx$output_dir, paste0("cutoff_", index_var, ".csv"))
  write.csv(data.frame(cutoff = cutoff_val, index = index_var), cutoff_csv, row.names = FALSE)
  cli::cli_alert_success("Saved: {basename(cutoff_csv)}")

  # ── AUC + 可选单变量 ROC 图（默认不发表；发表 ROC 见 simple_ROC）──────────
  if (!roc_fallback) {
    auc_val <- as.numeric(pROC::auc(roc_raw))
    auc_ci  <- as.numeric(pROC::ci.auc(roc_raw, quiet = TRUE))
    export_roc_figure <- isTRUE((cfg$cutoff %||% list())$export_roc_figure %||% FALSE)
    if (export_roc_figure) {
      best_spec <- roc_raw$specificities[youden_idx]
      best_sens <- roc_raw$sensitivities[youden_idx]

      ff <- if (exists("plot_font_from_config", mode = "function")) {
        plot_font_from_config(cfg)
      } else if (exists("resolve_plot_font_family", mode = "function")) {
        resolve_plot_font_family(cfg$plot$font_family %||% "Times New Roman")
      } else {
        "Times New Roman"
      }

      roc_df <- data.frame(
        FPR         = 1 - roc_raw$specificities,
        Sensitivity = roc_raw$sensitivities
      )
      ix_disp <- gsub("_", " ", index_var, fixed = TRUE)
      lbl_auc <- paste0(
        "AUC = ", format(round(auc_val, 3), nsmall = 3),
        "\n95% CI: [", format(round(auc_ci[1], 3), nsmall = 3), ", ",
        format(round(auc_ci[3], 3), nsmall = 3), "]"
      )
      # 旧行为：不标 Youden 切点；标题与 simple_ROC 风格对齐
      p_roc <- ggplot(roc_df, aes(x = FPR, y = Sensitivity)) +
        geom_path(linewidth = 1, color = "#C6524A") +
        geom_abline(slope = 1, intercept = 0, linetype = "longdash", color = "gray50", linewidth = 0.8) +
        scale_x_continuous("1 - Specificity", breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
        scale_y_continuous("Sensitivity", breaks = seq(0, 1, 0.2), limits = c(0, 1)) +
        annotate(
          "text", x = 1, y = 0.2, hjust = 1, size = 4.2, color = "#C6524A",
          fontface = "bold", family = ff, label = lbl_auc
        ) +
        labs(title = paste0("ROC Curve for ", ix_disp)) +
        theme_bw(base_family = ff) +
        theme(
          plot.title       = element_text(hjust = 0.5, size = 14, face = "bold", family = ff),
          axis.title       = element_text(size = 11, family = ff),
          axis.text        = element_text(family = ff),
          panel.grid.major = element_blank(),
          panel.grid.minor = element_blank(),
          panel.background = element_rect(fill = "white", color = NA),
          plot.background  = element_rect(fill = "white", color = NA),
          panel.border     = element_rect(color = "black", fill = NA, linewidth = 0.5)
        )

      fig_dir <- ctx$output_dir_figures %||% ctx$output_dir
      if (!dir.exists(fig_dir)) dir.create(fig_dir, recursive = TRUE)
      roc_caption <- paste0("ROC curve for ", ix_disp)
      roc_bn <- if (exists("pub_figure_file", mode = "function")) {
        pub_figure_file(ctx, "supp_figure", roc_caption)
      } else {
        paste0("Figure ROC ", ix_disp, ".pdf")
      }
      if (exists(".pub_figure_filename", mode = "function")) {
        roc_bn <- .pub_figure_filename(.inject_db_into_pub_label(roc_bn, sanitize_for_file = TRUE))
      }
      roc_pdf <- file.path(fig_dir, roc_bn)
      tryCatch({
        grDevices::cairo_pdf(roc_pdf, width = 8, height = 7, family = ff)
        print(p_roc)
        grDevices::dev.off()
        cli::cli_alert_success("Saved: {basename(roc_pdf)}")
        if (exists("mirror_pub_output_to_root", mode = "function")) {
          mirror_pub_output_to_root(ctx, roc_pdf)
        }
      }, error = function(e) {
        try(grDevices::dev.off(), silent = TRUE)
        cli::cli_alert_warning("cairo_pdf 失败 ({e$message})，回退 ggsave…")
        tryCatch({
          ggplot2::ggsave(roc_pdf, plot = p_roc, width = 8, height = 7)
          cli::cli_alert_success("Saved: {basename(roc_pdf)}")
          if (exists("mirror_pub_output_to_root", mode = "function")) {
            mirror_pub_output_to_root(ctx, roc_pdf)
          }
        }, error = function(e2) cli::cli_alert_warning("ROC 图保存失败: {e2$message}"))
      })
    } else {
      cli::cli_alert_info(
        "block_cutoff: export_roc_figure=FALSE，跳过发表 ROC 图（Youden 截断与分组仍计算；发表 ROC 见 simple_ROC）"
      )
    }
  }

  .cutoff_assign_groups <- function(x, n_groups, prefix) {
    xv <- as.numeric(x)
    u <- sort(unique(xv[is.finite(xv)]))
    if (length(u) < 2L) {
      return(factor(rep(NA_character_, length(xv)), levels = paste0(prefix, seq_len(n_groups))))
    }
    if (length(u) <= n_groups) {
      return(factor(xv, levels = u, labels = paste0(prefix, seq_along(u))))
    }
    probs <- seq(0, 1, length.out = n_groups + 1L)
    brks <- unique(as.numeric(stats::quantile(xv, probs, na.rm = TRUE)))
    if (length(brks) < 3L) {
      return(factor(xv, levels = u, labels = paste0(prefix, seq_along(u))))
    }
    labs <- paste0(prefix, seq_len(length(brks) - 1L))
    cut(xv, breaks = brks, include.lowest = TRUE, labels = labs)
  }

  # ── Binary 分组（Convention A: equals → high）────────────────────────────
  data_bin <- data
  lbl_lo <- paste0("<", cutoff_val)
  lbl_hi <- paste0(">=",  cutoff_val)
  data_bin$Index_Group <- factor(
    ifelse(data_bin[[index_var]] < cutoff_val, lbl_lo, lbl_hi),
    levels = c(lbl_lo, lbl_hi)
  )
  cli::cli_alert_info("Binary 分组: {paste(names(table(data_bin$Index_Group)), '=', table(data_bin$Index_Group), collapse = ', ')}")

  # ── Tertile 分组 ─────────────────────────────────────────────────────────
  data_tert <- data
  data_tert$Index_Group_Tertile <- .cutoff_assign_groups(data[[index_var]], 3L, "T")
  cli::cli_alert_info("Tertile 分组: {paste(names(table(data_tert$Index_Group_Tertile)), '=', table(data_tert$Index_Group_Tertile), collapse = ', ')}")

  # ── Quartile 分组 ────────────────────────────────────────────────────────
  data_quart <- data
  data_quart$Index_Group_Quartile <- .cutoff_assign_groups(data[[index_var]], 4L, "Q")
  cli::cli_alert_info("Quartile 分组: {paste(names(table(data_quart$Index_Group_Quartile)), '=', table(data_quart$Index_Group_Quartile), collapse = ', ')}")

  # ── 写入 ctx ─────────────────────────────────────────────────────────────
  ctx$results$nhanes_cutoff       <- cutoff_val
  ctx$results$nhanes_cutoff_index <- index_var
  ctx$results$nhanes_data_binary  <- data_bin
  ctx$results$nhanes_data_tert    <- data_tert
  ctx$results$nhanes_data_quart   <- data_quart
  ctx$results$nhanes_roc_auc      <- auc_val
  ctx$results$nhanes_roc_auc_ci   <- auc_ci

  cli::cli_alert_success(
    if (roc_fallback) {
      "block_cutoff 完成（中位数截断 = {cutoff_val}，未绘制 ROC）"
    } else {
      paste0(
        "block_cutoff 完成（AUC = ", round(auc_val, 3), ", cutoff = ", cutoff_val,
        if (isTRUE((cfg$cutoff %||% list())$export_roc_figure %||% FALSE)) {
          "，已导出单变量 ROC 图"
        } else {
          "，未导出发表 ROC 图"
        },
        "）"
      )
    }
  )
  ctx
}

register_block("cutoff", block_cutoff,
               "NHANES ROC cutoff (Youden) + Binary/Tertile/Quartile groupings (C00_ROC style)")
