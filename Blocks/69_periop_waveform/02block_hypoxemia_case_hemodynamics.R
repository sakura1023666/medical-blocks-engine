###############################################################################
#  hypoxemia_case_hemodynamics — 单例诱导窗 SpO2 着色的 DBP/HR 轨迹
#
#  register_block: "hypoxemia_case_hemodynamics"
#  典型流水线: baseline_binary 之后
#
#  hypoxemia_case_hemodynamics = list(
#    enable = FALSE,
#    case_id = "0014",
#    waveform_path = NULL,          # NULL → <project>/data/waveforms/<case_id>.csv
#    event_column = "EVENT",
#    spo2_column = "Solar8000.PLETH_SPO2",
#    dbp_column = "Solar8000.NIBP_DBP",
#    hr_column = "Solar8000.HR",
#    window_start_event = "Case started",
#    window_end_event = "Surgery started",
#    time_step_sec = 10,
#    spo2_threshold = 90,
#    width = 8, height = 6,
#    figure_stem_dbp = "Figure 3A. DBP from the start of anesthesia to incision",
#    figure_stem_hr = "Figure 3B. HR from the start of anesthesia to incision",
#    figure_stem_combined = "Figure 3. Hemodynamic measurements in a Single Case",
#    combine_panels = TRUE
#  )
###############################################################################

.hch02_project_root <- function(ctx) {
  candidates <- c(
    ctx$config$project$output_dir %||% "",
    ctx$root_output_dir %||% "",
    ctx$config$ml_batch$output_base %||% ""
  )
  for (p in candidates) {
    p <- as.character(p)[1L]
    if (!nzchar(p)) next
    cur <- normalizePath(p, winslash = "/", mustWork = FALSE)
    for (i in seq_len(8L)) {
      if (dir.exists(file.path(cur, "data", "waveforms")) ||
          dir.exists(file.path(cur, "data", "derived"))) {
        return(cur)
      }
      parent <- dirname(cur)
      if (identical(parent, cur)) break
      cur <- parent
    }
  }
  NA_character_
}

.hch02_resolve_waveform <- function(ctx, bl_cfg) {
  explicit <- as.character(bl_cfg$waveform_path %||% "")[1L]
  if (nzchar(explicit) && file.exists(explicit)) {
    return(normalizePath(explicit, winslash = "/", mustWork = TRUE))
  }
  case_id <- as.character(bl_cfg$case_id %||% "0014")[1L]
  root <- .hch02_project_root(ctx)
  if (is.na(root) || !nzchar(root)) return(NULL)
  cands <- c(
    file.path(root, "data", "waveforms", paste0(case_id, ".csv")),
    file.path(root, "data", "waveforms", sprintf("%04d.csv", suppressWarnings(as.integer(case_id))))
  )
  for (p in cands) if (file.exists(p)) return(p)
  NULL
}

.hch02_mirror_figures <- function(ctx, pdf_path) {
  if (!file.exists(pdf_path)) return(invisible(NULL))
  src <- normalizePath(pdf_path, winslash = "/", mustWork = TRUE)
  roots <- unique(c(
    ctx$output_dir_figures %||% NA_character_,
    file.path(ctx$output_dir %||% NA_character_, "Figures"),
    file.path(ctx$root_output_dir %||% NA_character_, "Figures"),
    file.path(dirname(ctx$root_output_dir %||% "."), "Figures")
  ))
  roots <- roots[!is.na(roots) & nzchar(roots)]
  for (rd in roots) {
    for (sub in c("pdf", "")) {
      d <- if (nzchar(sub)) file.path(rd, sub) else rd
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      dest <- normalizePath(file.path(d, basename(pdf_path)), winslash = "/", mustWork = FALSE)
      if (identical(src, dest)) next
      file.copy(src, dest, overwrite = TRUE)
    }
  }
  invisible(NULL)
}

.hch02_ggsave <- function(path, plot, width, height) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ok <- isTRUE(tryCatch({
    ggplot2::ggsave(
      path, plot, width = width, height = height,
      device = if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else grDevices::pdf,
      limitsize = FALSE
    )
    TRUE
  }, error = function(e) FALSE))
  if (!ok) {
    ggplot2::ggsave(path, plot, width = width, height = height, device = grDevices::pdf, limitsize = FALSE)
  }
  path
}

.hch02_panel <- function(df, y_col, y_lab, title, thr) {
  plot_df <- data.frame(
    Time = df$Time,
    Y = as.numeric(df[[y_col]]),
    SpO2 = as.numeric(df$SpO2),
    stringsAsFactors = FALSE
  )
  plot_df$spo2_ok <- !is.na(plot_df$SpO2) & plot_df$SpO2 >= thr
  low <- plot_df[!is.na(plot_df$SpO2) & plot_df$SpO2 < thr, , drop = FALSE]
  ggplot2::ggplot(plot_df, ggplot2::aes(x = .data$Time, y = .data$Y, color = .data$spo2_ok, group = 1)) +
    ggplot2::geom_line(linetype = "dashed", linewidth = 0.5, color = "gray40") +
    ggplot2::geom_point(size = 2.5) +
    {
      if (nrow(low) > 0L) {
        ggplot2::geom_errorbar(
          data = low,
          mapping = ggplot2::aes(x = .data$Time, ymin = .data$Y - 2, ymax = .data$Y + 2),
          width = 0.2, color = "#F7B2A5", inherit.aes = FALSE
        )
      } else {
        NULL
      }
    } +
    ggplot2::scale_color_manual(
      name = "SpO2 Status",
      values = c("FALSE" = "#F7B2A5", "TRUE" = "#A7E0E0"),
      labels = c("SpO2 < 90%", "SpO2 >= 90%")
    ) +
    ggplot2::labs(title = title, x = "Time (s)", y = y_lab) +
    ggplot2::theme_minimal() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 13, face = "bold"),
      axis.title = ggplot2::element_text(size = 11, face = "bold"),
      axis.text = ggplot2::element_text(size = 9),
      legend.title = ggplot2::element_text(size = 10, face = "bold"),
      legend.position = "right",
      legend.background = ggplot2::element_rect(fill = "white", color = "gray80")
    )
}

block_hypoxemia_case_hemodynamics <- function(ctx, ...) {
  bl_cfg <- ctx$config$hypoxemia_case_hemodynamics %||% list()
  if (!isTRUE(bl_cfg$enable %||% FALSE)) {
    cli::cli_alert_info("config$hypoxemia_case_hemodynamics$enable=FALSE，跳过。")
    return(ctx)
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    cli::cli_alert_warning("hypoxemia_case_hemodynamics 需要 ggplot2，跳过。")
    return(ctx)
  }

  path <- .hch02_resolve_waveform(ctx, bl_cfg)
  if (is.null(path)) {
    cli::cli_alert_warning("hypoxemia_case_hemodynamics: 未找到波形 CSV，跳过。")
    return(ctx)
  }

  ## VitalDB 原 CSV 用 Solar8000/...；R check.names=TRUE 会变成 Solar8000....
  raw <- utils::read.csv(path, stringsAsFactors = FALSE, check.names = TRUE)
  .hch02_pick_col <- function(prefer, alts = character(0)) {
    cands <- unique(c(prefer, alts, gsub("/", ".", prefer, fixed = TRUE),
                      gsub(".", "/", prefer, fixed = TRUE)))
    hit <- cands[cands %in% names(raw)]
    if (length(hit)) hit[[1L]] else prefer
  }
  event_col <- .hch02_pick_col(as.character(bl_cfg$event_column %||% "EVENT")[1L])
  spo2_col <- .hch02_pick_col(
    as.character(bl_cfg$spo2_column %||% "Solar8000.PLETH_SPO2")[1L],
    "Solar8000/PLETH_SPO2"
  )
  dbp_col <- .hch02_pick_col(
    as.character(bl_cfg$dbp_column %||% "Solar8000.NIBP_DBP")[1L],
    "Solar8000/NIBP_DBP"
  )
  hr_col <- .hch02_pick_col(
    as.character(bl_cfg$hr_column %||% "Solar8000.HR")[1L],
    "Solar8000/HR"
  )
  need <- c(event_col, spo2_col, dbp_col, hr_col)
  if (!all(need %in% names(raw))) {
    cli::cli_alert_warning(
      "hypoxemia_case_hemodynamics: CSV 缺列 {paste(setdiff(need, names(raw)), collapse=', ')}，跳过。"
    )
    return(ctx)
  }

  df <- raw[, need, drop = FALSE]
  names(df) <- c("Time_Node", "SpO2", "DBP", "HR")
  step <- as.numeric(bl_cfg$time_step_sec %||% 10)[1L]
  if (!is.finite(step) || step <= 0) step <- 10
  df$Time <- seq(from = 0, by = step, length.out = nrow(df))

  start_ev <- as.character(bl_cfg$window_start_event %||% "Case started")[1L]
  end_ev <- as.character(bl_cfg$window_end_event %||% "Surgery started")[1L]
  start_idx <- which(df$Time_Node == start_ev)
  end_idx <- which(df$Time_Node == end_ev)
  if (!length(start_idx) || !length(end_idx)) {
    cli::cli_alert_warning(
      "hypoxemia_case_hemodynamics: 未找到窗口事件 '{start_ev}' / '{end_ev}'，用全序列。"
    )
  } else {
    i0 <- min(start_idx)
    i1 <- max(end_idx)
    if (i1 < i0) {
      cli::cli_alert_warning("hypoxemia_case_hemodynamics: 窗口起止颠倒，用全序列。")
    } else {
      df <- df[i0:i1, , drop = FALSE]
      df$Time <- seq(from = 0, by = step, length.out = nrow(df))
    }
  }

  thr <- as.numeric(bl_cfg$spo2_threshold %||% 90)[1L]
  if (!is.finite(thr)) thr <- 90
  w <- as.numeric(bl_cfg$width %||% 8)[1L]
  h <- as.numeric(bl_cfg$height %||% 6)[1L]

  stem_dbp <- sub("\\.pdf$", "", as.character(
    bl_cfg$figure_stem_dbp %||% "Figure 3A. DBP from the start of anesthesia to incision"
  )[1L], ignore.case = TRUE)
  stem_hr <- sub("\\.pdf$", "", as.character(
    bl_cfg$figure_stem_hr %||% "Figure 3B. HR from the start of anesthesia to incision"
  )[1L], ignore.case = TRUE)
  stem_c <- sub("\\.pdf$", "", as.character(
    bl_cfg$figure_stem_combined %||%
      "Figure 3. Hemodynamic measurements in a Single Case"
  )[1L], ignore.case = TRUE)

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  p_dbp <- .hch02_panel(
    df, "DBP", "DBP (mmHg)",
    "DBP from the start of anesthesia to incision", thr
  )
  p_hr <- .hch02_panel(
    df, "HR", "HR (bpm)",
    "HR from the start of anesthesia to incision", thr
  )

  pdf_dbp <- .hch02_ggsave(file.path(fig_dir, paste0(stem_dbp, ".pdf")), p_dbp, w, h)
  pdf_hr <- .hch02_ggsave(file.path(fig_dir, paste0(stem_hr, ".pdf")), p_hr, w, h)

  pdf_c <- NULL
  if (isTRUE(bl_cfg$combine_panels %||% TRUE) && requireNamespace("cowplot", quietly = TRUE)) {
    pdf_c <- file.path(fig_dir, paste0(stem_c, ".pdf"))
    combined <- cowplot::plot_grid(p_dbp, p_hr, ncol = 1L, align = "v")
    .hch02_ggsave(pdf_c, combined, w, h * 2)
  }

  for (p in c(pdf_dbp, pdf_hr, pdf_c)) {
    if (!is.null(p) && file.exists(p)) .hch02_mirror_figures(ctx, p)
  }

  ctx$results$hypoxemia_case_hemodynamics <- list(
    case_id = as.character(bl_cfg$case_id %||% "0014")[1L],
    waveform = path,
    n_rows = nrow(df),
    pdf_dbp = pdf_dbp,
    pdf_hr = pdf_hr,
    pdf_combined = pdf_c
  )
  cli::cli_alert_success(
    "hypoxemia_case_hemodynamics: case={ctx$results$hypoxemia_case_hemodynamics$case_id} n={nrow(df)}"
  )
  ctx
}

register_block(
  "hypoxemia_case_hemodynamics",
  block_hypoxemia_case_hemodynamics,
  "单例诱导窗 SpO2 着色 DBP/HR 轨迹（Fig3）"
)
