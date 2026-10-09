###############################################################################
#  trajectory_dynpred — JLCM 动态生存预测图（Fig3 封装，仅 JLCM 路径）
#
#  路径: Blocks/26_trajectory/06block_trajectory_dynpred.R
#  register_block: "trajectory_dynpred"
#  读 config$trajectory$jlcm（assessment_times, prefer_ng 等）
#  依赖: trajectory_jlcm 产出
#
#  Block: trajectory_dynpred — JLCM 动态生存预测图（Fig3 封装）
#
#  功能：
#    在多个 landmark 时间点（assessment_times），对每个轨迹类别的存活患者
#    用 lcmm::dynpred() 预测未来生存概率，绘制：
#      左半部分：landmark 前各类别的历史轨迹均值线
#      右半部分：landmark 后的动态生存概率曲线 + 95% 置信带
#    双 y 轴（主轴=指标值，副轴=生存概率），按 landmark 时间点分面
#
#  依赖：需先运行 trajectory_jlcm（pipeline 决定，块内不检查 model_type）
#
#  输入：
#    ctx$results$trajectory_jlcm_models[["Index"]]   — JLCM 模型（优先）
#    config$trajectory$jlcm_model_dir                — 模型磁盘兜底目录
#    config$trajectory$jlcm_model_filename_tpl       — 模型文件名模板
#    config$trajectory$index_vars
#    config$trajectory$cycle                         — 最大随访天数
#    config$trajectory$jlcm$prefer_ng                — 首选类别数
#    config$trajectory$jlcm$assessment_times         — landmark 时间点列表
#    config$trajectory$jlcm$ndraws                   — 贝叶斯抽样数（置信带）
#    config$trajectory$jlcm$dynpred_width/height     — 图形尺寸
#    config$trajectory$jlcm$survival_offset          — 生存概率映射下界偏移
#    config$trajectory$jlcm$survival_scale           — 生存概率映射高度比例
#    config$plot$font_family
#
#  输出：
#    Figures/Figure_Dynpred_{Index}_D{D}.pdf  — 每个 Index×ng 一张 PDF
###############################################################################

# ── 内部辅助：安全均值 ──────────────────────────────────────────────────────────
.safe_mean_dyn <- function(x) {
  x <- x[!is.na(x) & !is.infinite(x)]
  if (length(x) == 0) NA_real_ else mean(x)
}

# ── 内部辅助：unwrap gridsearch 结果 ────────────────────────────────────────────
.unwrap_jlcm_model <- function(m) {
  if (is.null(m) || !is.list(m)) return(NULL)
  if (!is.null(m$best) && is.list(m$best) && !is.null(m$best$ng)) return(m$best)
  if (!is.null(m$ng)) return(m)
  NULL
}

# ══════════════════════════════════════════════════════════════════════════════
block_trajectory_dynpred <- function(ctx, ...) {
  suppressPackageStartupMessages({
    library(lcmm); library(survival); library(splines)
    library(dplyr); library(tidyr); library(ggplot2); library(scales)
    library(tibble); library(cli)
  })
  traj_util <- file.path(ctx$config$project$root %||% getwd(), "R/trajectory_survival_utils.R")
  if (file.exists(traj_util)) source(traj_util, local = FALSE)

  cfg      <- ctx$config
  traj_cfg <- cfg$trajectory %||% cfg$trajectory_dynpred %||% list()
  jlcm_cfg <- traj_cfg$jlcm %||% (cfg$trajectory_dynpred$jlcm %||% list())
  dyn_bl   <- cfg$trajectory_dynpred %||% list()

  index_vars       <- traj_cfg$index_vars %||% stop("trajectory$index_vars 未配置。")
  cycle            <- as.numeric(traj_cfg$cycle         %||% 28)
  assessment_times <- as.numeric(jlcm_cfg$assessment_times %||% c(4, 7, 14, 21))
  ndraws           <- as.integer(jlcm_cfg$ndraws        %||% 2000L)
  dyn_width        <- jlcm_cfg$dynpred_width            %||% 12
  dyn_height       <- jlcm_cfg$dynpred_height           %||% 8
  surv_offset      <- jlcm_cfg$survival_offset          %||% 0.02
  surv_scale       <- jlcm_cfg$survival_scale           %||% 0.96
  font_family      <- plot_font_from_config(cfg)

  jlcm_model_dir <- traj_cfg$jlcm_model_dir          %||% NULL
  jlcm_model_tpl <- traj_cfg$jlcm_model_filename_tpl %||%
    "D01_jlcm_{Index}_models.RData"

  # 固定颜色映射（最多 6 类）
  class_colors <- c(
    "Class 1" = "#D55E00", "Class 2" = "#E69F00",
    "Class 3" = "#56B4E9", "Class 4" = "#009E73",
    "Class 5" = "#E87A90", "Class 6" = "#7B68EE"
  )

  n_plotted <- 0L

  for (Index in index_vars) {
    cli::cli_h1("dynpred: {Index}")

    # ── 加载模型 ────────────────────────────────────────────────────────────
    jlcm_entry <- ctx$results$trajectory_jlcm_models[[Index]]
    models_raw  <- if (!is.null(jlcm_entry)) jlcm_entry$models else NULL
    model_data_final <- if (!is.null(jlcm_entry)) jlcm_entry$model_data_final else NULL

    if (is.null(models_raw) && !is.null(jlcm_model_dir)) {
      mfname <- gsub("\\{Index\\}", Index, jlcm_model_tpl)
      mfpath <- if (grepl("^(/|[A-Za-z]:[/\\\\])", jlcm_model_dir))
        file.path(jlcm_model_dir, mfname)
      else
        file.path(getwd(), jlcm_model_dir, mfname)

      if (file.exists(mfpath)) {
        e_m <- new.env(parent = emptyenv())
        load(mfpath, envir = e_m)
        models_raw       <- tryCatch(get("models_list_with_cov", envir = e_m), error = function(e2) NULL)
        model_data_final <- tryCatch(get("model_data_final",     envir = e_m), error = function(e2) NULL)
        if (!is.null(models_raw))
          cli::cli_alert_info("从磁盘加载 JLCM 模型: {.file {mfpath}}")
      }
    }

    if (is.null(models_raw) || is.null(model_data_final)) {
      cli::cli_alert_warning("{Index}: 模型或 model_data_final 不可用，跳过"); next
    }

    # ── 选择目标模型（优先 JLCM 自动选定的最优 ng）────────────────────────────
    prefer_ng <- if (!is.null(jlcm_cfg$prefer_ng)) {
      as.integer(jlcm_cfg$prefer_ng)
    } else {
      trajectory_resolve_optimal_ng(ctx, Index, cfg, fallback = 2L)
    }
    cli::cli_alert_info("dynpred [{Index}]: 使用 ng={prefer_ng}")
    target_key <- paste0("m", prefer_ng)
    m_raw <- models_raw[[target_key]]
    if (is.null(m_raw)) {
      ngs  <- sapply(models_raw, function(m) {
        mu <- .unwrap_jlcm_model(m); if (is.null(mu)) NA_integer_ else mu$ng
      })
      ngs <- ngs[!is.na(ngs)]
      if (!length(ngs)) {
        cli::cli_alert_warning("{Index}: 无有效 JLCM 模型，跳过 dynpred"); next
      }
      best_key <- names(which.max(ngs))
      if (!length(best_key)) {
        cli::cli_alert_warning("{Index}: JLCM 模型列表为空，跳过 dynpred"); next
      }
      m_raw    <- models_raw[[best_key[1L]]]
      cli::cli_alert_warning("m{prefer_ng} 不存在，改用 {best_key[1L]}")
    }
    final_model <- trajectory_unwrap_jointlcmm(m_raw)
    if (is.null(final_model) || is.null(final_model$pprob)) {
      cli::cli_alert_danger("{Index}: 最终模型无 pprob，跳过"); next
    }

    cov_cols <- trajectory_jlcm_cov_cols(jlcm_entry, final_model)

    ng_use <- final_model$ng
    cli::cli_alert_info("使用模型 ng={ng_use}，conv={final_model$conv %||% NA}")

    # ── 提取类别：优先双库 align maps（Class1=低位主类），禁止再 majority-swap
    pprob_df    <- as.data.frame(final_model$pprob)
    swap_map    <- if (exists("trajectory_resolve_class_map", mode = "function")) {
      trajectory_resolve_class_map(pprob_df$class, cfg, Index, source = "raw")
    } else if (exists("trajectory_class_swap_map", mode = "function")) {
      trajectory_class_swap_map(pprob_df$class)
    } else {
      NULL
    }
    if (!is.null(swap_map))
      pprob_df$class <- trajectory_apply_class_swap(pprob_df$class, swap_map)
    all_classes <- sort(unique(pprob_df$class))
    class_df    <- pprob_df[, c("subject_id_num", "class")]

    # ── 合并类别到模型数据 ────────────────────────────────────────────────────
    model_data_with_class <- model_data_final |>
      dplyr::left_join(class_df, by = "subject_id_num") |>
      dplyr::filter(!is.na(class), !is.na(scr_std))

    if (nrow(model_data_with_class) == 0) {
      cli::cli_alert_danger("{Index}: 合并后无有效数据，跳过"); next
    }

    # ── 各类每日轨迹均值 ─────────────────────────────────────────────────────
    class_traj_list <- lapply(all_classes, function(cl) {
      model_data_with_class |>
        dplyr::filter(class == cl) |>
        dplyr::group_by(time_day) |>
        dplyr::summarise(mean_outcome = .safe_mean_dyn(scr_std), .groups = "drop") |>
        dplyr::filter(!is.na(mean_outcome))
    })
    names(class_traj_list) <- as.character(all_classes)

    # ── 生存信息 ─────────────────────────────────────────────────────────────
    time_col  <- intersect(c("surv_time", "time_28d", "survival_time_28d"), names(model_data_final))[1]
    event_col <- intersect(c("surv_event", "event_28d", "survival_28d"), names(model_data_final))[1]
    if (is.na(time_col) || is.na(event_col)) {
      cli::cli_alert_danger("{Index}: model_data_final 缺少生存时间/事件列，跳过"); next
    }
    surv_info <- model_data_final |>
      dplyr::distinct(subject_id_num, .data[[time_col]], .data[[event_col]]) |>
      dplyr::transmute(
        subject_id_num,
        surv_time = suppressWarnings(as.numeric(.data[[time_col]])),
        event     = as.integer(.data[[event_col]])
      ) |>
      dplyr::filter(!is.na(surv_time), !is.na(event))

    # ── dynpred 循环 ──────────────────────────────────────────────────────────
    dyn_rows <- list()
    unify_time_var    <- "time_day"
    unify_outcome_var <- "scr_std"

    for (assess_t in assessment_times) {
      cli::cli_h2("landmark = {assess_t}d")

      surv_newdata <- model_data_final |>
        dplyr::select(-dplyr::any_of(c("surv_time", "event", "surv_event"))) |>
        dplyr::left_join(class_df,  by = "subject_id_num") |>
        dplyr::left_join(surv_info, by = "subject_id_num") |>
        dplyr::filter(!is.na(class), !is.na(event), !is.na(surv_time)) |>
        dplyr::filter(surv_time > assess_t |
                        (surv_time == assess_t & event == 0)) |>
        dplyr::filter(.data[[unify_time_var]] <= assess_t)

      if (nrow(surv_newdata) == 0) {
        cli::cli_alert_warning("landmark={assess_t}: 无可用数据，跳过"); next
      }

      horizons <- round(seq(0.1, cycle - assess_t, by = 1), 1)
      if (length(horizons) == 0) next

      need_cols <- unique(c("subject_id_num", unify_time_var, unify_outcome_var, cov_cols))
      need_cols <- need_cols[need_cols %in% names(surv_newdata)]

      for (cl in all_classes) {
        cli::cli_alert_info("  类别 {cl}")
        surv_cl <- surv_newdata |>
          dplyr::filter(class == cl) |>
          dplyr::select(dplyr::any_of(need_cols))

        if (nrow(surv_cl) == 0) next

        pred_surv <- tryCatch({
          res <- NULL
          # lcmm::dynpred 会把整张 pred 矩阵 print 到控制台，极大拖慢批量跑
          zz <- file(nullfile(), open = "wt")
          sink(zz); sink(zz, type = "message")
          on.exit({
            try(sink(type = "message"), silent = TRUE)
            try(sink(), silent = TRUE)
            try(close(zz), silent = TRUE)
          }, add = TRUE)
          res <- lcmm::dynpred(
            final_model,
            landmark = assess_t, horizon = horizons,
            newdata  = surv_cl,
            var.time = unify_time_var,
            draws = TRUE, ndraws = ndraws
          )
          try(sink(type = "message"), silent = TRUE)
          try(sink(), silent = TRUE)
          try(close(zz), silent = TRUE)
          on.exit(NULL)
          res
        }, error = function(e) {
          try(sink(type = "message"), silent = TRUE)
          try(sink(), silent = TRUE)
          cli::cli_alert_warning("  dynpred 失败: {e$message}"); NULL
        })

        if (is.null(pred_surv)) next

        pred_raw <- as.data.frame(pred_surv$pred)
        if ("pred_50" %in% names(pred_raw) && !"pred" %in% names(pred_raw))
          pred_raw <- dplyr::rename(pred_raw, pred = pred_50)

        df_sub <- pred_raw |>
          dplyr::group_by(landmark, horizon) |>
          dplyr::summarise(
            pred      = .safe_mean_dyn(pred),
            pred_lo   = if ("pred_2.5"  %in% names(pred_raw)) .safe_mean_dyn(pred_2.5)  else NA_real_,
            pred_hi   = if ("pred_97.5" %in% names(pred_raw)) .safe_mean_dyn(pred_97.5) else NA_real_,
            .groups   = "drop"
          ) |>
          dplyr::mutate(
            assessment_time = assess_t, class = cl,
            class_label     = paste("Class", cl),
            # 转换为生存概率（1 - 风险）
            surv      = 1 - pred,
            surv_lo   = if (!is.na(pred_hi[1])) 1 - pred_hi else NA_real_,
            surv_hi   = if (!is.na(pred_lo[1])) 1 - pred_lo else NA_real_
          )
        dyn_rows[[paste0(assess_t, "_", cl)]] <- df_sub
        cli::cli_alert_success("  预测完成（{nrow(df_sub)} 行）")
      }
    }

    if (length(dyn_rows) == 0) {
      cli::cli_alert_danger("{Index}: 所有 dynpred 均失败，跳过绘图"); next
    }

    dyn_df <- dplyr::bind_rows(dyn_rows)

    # ── 准备绘图 ─────────────────────────────────────────────────────────────
    class_levels  <- paste("Class", all_classes)
    palette_use   <- unname(class_colors[class_levels])

    # 主坐标轴范围（基于历史轨迹）
    all_traj_vals <- unlist(lapply(class_traj_list, `[[`, "mean_outcome"))
    y_min <- min(all_traj_vals, na.rm = TRUE)
    y_max <- max(all_traj_vals, na.rm = TRUE)

    # 生存概率显示范围
    pred_vals <- dyn_df$surv[!is.na(dyn_df$surv)]
    pred_min  <- max(0, min(pred_vals) - diff(range(pred_vals)) * 0.05)
    pred_max  <- min(1, max(pred_vals) + diff(range(pred_vals)) * 0.05)

    # 生存概率 → 主坐标轴映射
    s_min_y <- y_min + surv_offset * (y_max - y_min)
    s_max_y <- min(y_max, y_min + (surv_offset + surv_scale) * (y_max - y_min))
    map_surv <- function(p)
      s_min_y + (pmin(pmax(p, pred_min), pred_max) - pred_min) /
        (pred_max - pred_min) * (s_max_y - s_min_y)

    # 历史轨迹数据（按 assessment_time 展开）
    hist_data <- lapply(all_classes, function(cl) {
      traj <- class_traj_list[[as.character(cl)]]
      if (is.null(traj) || nrow(traj) == 0) return(NULL)
      tidyr::expand_grid(assessment_time = assessment_times) |>
        dplyr::mutate(class = cl, class_label = paste("Class", cl)) |>
        tidyr::crossing(traj) |>
        dplyr::filter(time_day <= assessment_time) |>
        dplyr::mutate(plot_time = time_day)
    }) |>
      dplyr::bind_rows() |>
      dplyr::mutate(class_label = factor(class_label, levels = class_levels))

    # 预测数据（映射到主坐标轴）
    pred_plot <- dyn_df |>
      dplyr::mutate(
        time_abs    = landmark + horizon,
        class_label = factor(class_label, levels = class_levels),
        mapped_surv = map_surv(surv),
        mapped_lo   = if (!all(is.na(surv_lo))) map_surv(surv_lo) else NA_real_,
        mapped_hi   = if (!all(is.na(surv_hi))) map_surv(surv_hi) else NA_real_
      ) |>
      dplyr::filter(!is.na(mapped_surv))

    # ── 绘图 ─────────────────────────────────────────────────────────────────
    p <- ggplot2::ggplot() +
      ggplot2::geom_line(
        data = hist_data,
        ggplot2::aes(x = plot_time, y = mean_outcome, color = class_label),
        linewidth = 0.9, alpha = 0.9
      ) +
      ggplot2::geom_point(
        data = hist_data,
        ggplot2::aes(x = plot_time, y = mean_outcome, color = class_label),
        shape = 16, size = 1.8, alpha = 0.95
      ) +
      ggplot2::geom_vline(
        data = tibble::tibble(assessment_time = assessment_times),
        ggplot2::aes(xintercept = assessment_time),
        linewidth = 1, linetype = "dashed", color = "gray50"
      ) +
      ggplot2::geom_line(
        data = pred_plot,
        ggplot2::aes(x = time_abs, y = mapped_surv, color = class_label),
        linewidth = 1.2
      ) +
      ggplot2::geom_ribbon(
        data = pred_plot,
        ggplot2::aes(x = time_abs, ymin = mapped_lo, ymax = mapped_hi,
                     fill = class_label),
        alpha = 0.2, na.rm = TRUE
      ) +
      ggplot2::facet_wrap(~ assessment_time, labeller = ggplot2::label_both) +
      ggplot2::scale_x_continuous(
        name   = "Day",
        limits = c(0, cycle),
        breaks = seq(0, cycle, by = 3)
      ) +
      ggplot2::scale_y_continuous(
        name = Index,
        limits = c(y_min, y_max),
        sec.axis = ggplot2::sec_axis(
          trans  = ~ (. - s_min_y) / (s_max_y - s_min_y) *
            (pred_max - pred_min) + pred_min,
          name   = "Survival Probability",
          breaks = seq(round(pred_min, 2), round(pred_max, 2), by = 0.05),
          labels = scales::percent_format(accuracy = 1)
        )
      ) +
      ggplot2::scale_color_manual(
        name = "Latent Class", values = palette_use,
        breaks = class_levels, limits = class_levels, drop = FALSE
      ) +
      ggplot2::scale_fill_manual(
        name = "Latent Class", values = palette_use,
        breaks = class_levels, limits = class_levels, drop = FALSE
      ) +
      ggplot2::theme_light(base_size = 12) +
      ggplot2::theme(
        text               = ggplot2::element_text(family = font_family),
        legend.position    = "top",
        legend.title       = ggplot2::element_text(face = "bold", size = 11),
        strip.background   = ggplot2::element_blank(),
        strip.text         = ggplot2::element_text(size = 11, face = "bold", color = "black"),
        panel.grid.minor   = ggplot2::element_blank(),
        axis.title.y.right = ggplot2::element_text(margin = ggplot2::margin(l = 10)),
        plot.margin        = ggplot2::margin(0.5, 0.5, 0.5, 0.5, "cm")
      )

    fig_name <- paste0("Figure_Dynpred_", Index, "_D", ng_use, ".pdf")
    local({
      pp <- p; fn <- fig_name; pw <- dyn_width; ph <- dyn_height
      ctx <<- save_figure(ctx, filename = fn,
                          plot_fn = local({ x <- pp; function() x }),
                          width = pw, height = ph)
    })
    n_plotted <- n_plotted + 1L
    cli::cli_alert_success("{Index}: dynpred 图已入队 → {fig_name}")
  }

  if (n_plotted == 0L) {
    pause_enable <- isTRUE(dyn_bl$pause_enable %||% jlcm_cfg$pause_enable %||% FALSE)
    pause_on_no <- isTRUE(dyn_bl$pause_on_no_output %||% jlcm_cfg$pause_on_no_output %||% TRUE)
    if (pause_enable && pause_on_no) {
      stop(
        "PAUSE_FOR_USER_DECISION: trajectory_dynpred 未产出任何图形。",
        "请检查 JLCM 协变量是否已写入 dynpred newdata，或 landmark 是否有存活样本。",
        call. = FALSE
      )
    }
    cli::cli_alert_danger("trajectory_dynpred: 所有 Index 均未产出图形")
  } else {
    cli::cli_alert_success("trajectory_dynpred 完成：{n_plotted} 张图入队。")
  }
  return(ctx)
}

register_block(
  "trajectory_dynpred", block_trajectory_dynpred,
  "JLCM 动态生存预测图：历史轨迹均值 + dynpred 置信带，按 landmark 分面"
)
