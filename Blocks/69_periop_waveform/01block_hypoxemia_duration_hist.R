###############################################################################
#  hypoxemia_duration_hist — 诱导/围术期低氧 Duration + Start_Time 直方图+ECDF
#
#  register_block: "hypoxemia_duration_hist"
#  典型流水线: baseline_binary 之后（描述性；不依赖插补特征）
#
#  hypoxemia_duration_hist = list(
#    enable = FALSE,
#    duration_table = NULL,   # 路径；NULL → <project>/data/derived/SpO2_duration_table.csv
#    id_column = "ID",
#    duration_column = "Duration",
#    start_time_column = "Start_Time",
#    disease_column = "Disease",   # 与 baseline 合并后仅画阳性；NULL=不筛
#    case_level = "Induction period hypoxemia",
#    spo2_threshold = 90,
#    breaks = 30L,
#    width = 10, height = 7,
#    figure_stem_duration = "Figure 2A. Distribution of hypoxemia duration",
#    figure_stem_start = "Figure 2B. Distribution of hypoxemia start time",
#    figure_stem_combined = "Figure 2. Duration and Temporal Distribution of Hypoxemia",
#    combine_panels = TRUE
#  )
###############################################################################

.hdh01_project_root <- function(ctx) {
  candidates <- c(
    ctx$config$project$output_dir %||% "",
    ctx$root_output_dir %||% "",
    ctx$config$ml_batch$output_base %||% ""
  )
  for (p in candidates) {
    p <- as.character(p)[1L]
    if (!nzchar(p)) next
    ## output_dir 常为 by_index/.../VitalDB；向上找含 data/derived 的课题根
    cur <- normalizePath(p, winslash = "/", mustWork = FALSE)
    for (i in seq_len(8L)) {
      der <- file.path(cur, "data", "derived")
      if (dir.exists(der)) return(cur)
      parent <- dirname(cur)
      if (identical(parent, cur)) break
      cur <- parent
    }
  }
  NA_character_
}

.hdh01_resolve_table <- function(ctx, bl_cfg) {
  explicit <- as.character(bl_cfg$duration_table %||% "")[1L]
  if (nzchar(explicit) && file.exists(explicit)) {
    return(normalizePath(explicit, winslash = "/", mustWork = TRUE))
  }
  root <- .hdh01_project_root(ctx)
  if (!is.na(root) && nzchar(root)) {
    for (nm in c(
      "SpO2_duration_table.csv",
      "SpO2_analysis_results.csv"
    )) {
      p <- file.path(root, "data", "derived", nm)
      if (file.exists(p)) return(p)
    }
  }
  NULL
}

.hdh01_draw_hist_ecdf <- function(x, main, xlab, breaks, fill_col = "skyblue") {
  x <- as.numeric(x)
  x <- x[is.finite(x)]
  if (!length(x)) {
    plot.new()
    title(main = paste0(main, " (no data)"))
    return(invisible(NULL))
  }
  hist(
    x, breaks = breaks, col = fill_col, border = "white",
    main = main, xlab = xlab, ylab = "Case count", freq = TRUE
  )
  par(new = TRUE)
  plot(
    ecdf(x), xlab = "", ylab = "", main = "", axes = FALSE,
    col = "red", lwd = 2, lty = 2, verticals = TRUE, do.points = FALSE
  )
  axis(side = 4)
  mtext("Cumulative probability", side = 4, line = 2.5)
  legend(
    "topright",
    legend = c("Frequency distribution", "Cumulative distribution"),
    fill = c(fill_col, NA), col = c(NA, "red"), lty = c(NA, 2), lwd = c(NA, 2),
    border = c("white", NA), bty = "n", bg = NA
  )
  invisible(NULL)
}

.hdh01_write_pdf <- function(path, width, height, draw_fn) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  ok <- FALSE
  if (isTRUE(capabilities("cairo"))) {
    ok <- isTRUE(tryCatch({
      grDevices::cairo_pdf(path, width = width, height = height, family = "Times")
      draw_fn()
      grDevices::dev.off()
      TRUE
    }, error = function(e) {
      if (grDevices::dev.cur() > 1) try(grDevices::dev.off(), silent = TRUE)
      FALSE
    }))
  }
  if (!ok) {
    grDevices::pdf(path, width = width, height = height)
    draw_fn()
    grDevices::dev.off()
  }
  path
}

.hdh01_mirror_figures <- function(ctx, pdf_path) {
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

block_hypoxemia_duration_hist <- function(ctx, ...) {
  bl_cfg <- ctx$config$hypoxemia_duration_hist %||% list()
  if (!isTRUE(bl_cfg$enable %||% FALSE)) {
    cli::cli_alert_info("config$hypoxemia_duration_hist$enable=FALSE，跳过。")
    return(ctx)
  }

  tab_path <- .hdh01_resolve_table(ctx, bl_cfg)
  if (is.null(tab_path)) {
    cli::cli_alert_warning("hypoxemia_duration_hist: 未找到 duration 表，跳过。")
    return(ctx)
  }
  spo2 <- utils::read.csv(tab_path, stringsAsFactors = FALSE, check.names = FALSE)
  id_col <- as.character(bl_cfg$id_column %||% "ID")[1L]
  dur_col <- as.character(bl_cfg$duration_column %||% "Duration")[1L]
  st_col <- as.character(bl_cfg$start_time_column %||% "Start_Time")[1L]
  if (!all(c(id_col, dur_col, st_col) %in% names(spo2))) {
    cli::cli_alert_warning("hypoxemia_duration_hist: 表缺列 {id_col}/{dur_col}/{st_col}，跳过。")
    return(ctx)
  }
  spo2[[id_col]] <- as.character(spo2[[id_col]])

  disease_col <- as.character(bl_cfg$disease_column %||% "Disease")[1L]
  case_level <- as.character(bl_cfg$case_level %||% "Induction period hypoxemia")[1L]
  base <- ctx$data$imputed %||% ctx$data$cleaned %||% ctx$data$mapped %||% NULL
  if (!is.null(base) && is.data.frame(base) && disease_col %in% names(base)) {
    bid <- as.character(ctx$config$data$id_column %||% "ID")[1L]
    if (!bid %in% names(base) && "ID" %in% names(base)) bid <- "ID"
    if (bid %in% names(base)) {
      keep_ids <- as.character(base[[bid]][as.character(base[[disease_col]]) == case_level])
      spo2 <- spo2[spo2[[id_col]] %in% keep_ids, , drop = FALSE]
    }
  } else if (disease_col %in% names(spo2)) {
    spo2 <- spo2[as.character(spo2[[disease_col]]) == case_level, , drop = FALSE]
  }

  breaks <- as.integer(bl_cfg$breaks %||% 30L)[1L]
  if (!is.finite(breaks) || breaks < 5L) breaks <- 30L
  w <- as.numeric(bl_cfg$width %||% 10)[1L]
  h <- as.numeric(bl_cfg$height %||% 7)[1L]
  stem_d <- sub("\\.pdf$", "", as.character(
    bl_cfg$figure_stem_duration %||% "Figure 2A. Distribution of hypoxemia duration"
  )[1L], ignore.case = TRUE)
  stem_s <- sub("\\.pdf$", "", as.character(
    bl_cfg$figure_stem_start %||% "Figure 2B. Distribution of hypoxemia start time"
  )[1L], ignore.case = TRUE)
  stem_c <- sub("\\.pdf$", "", as.character(
    bl_cfg$figure_stem_combined %||%
      "Figure 2. Duration and Temporal Distribution of Hypoxemia"
  )[1L], ignore.case = TRUE)

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  pdf_d <- file.path(fig_dir, paste0(stem_d, ".pdf"))
  pdf_s <- file.path(fig_dir, paste0(stem_s, ".pdf"))
  .hdh01_write_pdf(pdf_d, w, h, function() {
    .hdh01_draw_hist_ecdf(
      spo2[[dur_col]],
      main = "Distribution of hypoxemia duration",
      xlab = "Duration of induction period hypoxemia (seconds)",
      breaks = breaks
    )
  })
  .hdh01_write_pdf(pdf_s, w, h, function() {
    .hdh01_draw_hist_ecdf(
      spo2[[st_col]],
      main = "Distribution of hypoxemia start time",
      xlab = "Start time of hypoxemia (seconds from baseline)",
      breaks = breaks
    )
  })

  pdf_c <- NULL
  if (isTRUE(bl_cfg$combine_panels %||% TRUE)) {
    pdf_c <- file.path(fig_dir, paste0(stem_c, ".pdf"))
    .hdh01_write_pdf(pdf_c, w, h * 2, function() {
      old <- par(mfrow = c(2, 1), mar = c(5, 4, 3, 4))
      on.exit(par(old), add = TRUE)
      .hdh01_draw_hist_ecdf(
        spo2[[dur_col]],
        main = "Distribution of hypoxemia duration",
        xlab = "Duration of induction period hypoxemia (seconds)",
        breaks = breaks
      )
      .hdh01_draw_hist_ecdf(
        spo2[[st_col]],
        main = "Distribution of hypoxemia start time",
        xlab = "Start time of hypoxemia (seconds from baseline)",
        breaks = breaks
      )
    })
  }

  for (p in c(pdf_d, pdf_s, pdf_c)) {
    if (!is.null(p) && file.exists(p)) .hdh01_mirror_figures(ctx, p)
  }

  ctx$results$hypoxemia_duration_hist <- list(
    n = nrow(spo2),
    table = tab_path,
    pdf_duration = pdf_d,
    pdf_start = pdf_s,
    pdf_combined = pdf_c
  )
  cli::cli_alert_success(
    "hypoxemia_duration_hist: n={nrow(spo2)} → {.file {basename(pdf_d)}} / {.file {basename(pdf_s)}}"
  )
  ctx
}

register_block(
  "hypoxemia_duration_hist",
  block_hypoxemia_duration_hist,
  "围术期低氧 Duration/Start_Time 直方图 + ECDF（Fig2）"
)
