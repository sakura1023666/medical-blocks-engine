###############################################################################
#  plot_histogram — In-hospital mortality rate bar chart by subphenotype.
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned
#  require_lca  = ctx$results$df_final  (Subphenotype column from block_lca)
#
#  plot_histogram = list(
#    subtype_col    = "Subphenotype",   # subphenotype label column (from df_final)
#    event_var      = NULL,             # NULL → config$data$outcome_column,
#                                       #   then fallback: hospdischargestatus
#    dead_values    = NULL,             # NULL → auto-detect "Expired" / "Non-survivor"
#                                       #   / "non-survivor" / 1 as death
#    class_prefix   = "Subphenotype",   # x-axis label prefix (e.g. "Class" → "Class 1")
#    palette        = NULL,             # NULL → ggplot2 default
#    bar_width      = 0.65,
#    show_pct_label = TRUE,             # annotate % on top of each bar
#    show_chi2_p    = TRUE,             # show chi-square p in subtitle
#    x_label        = "Subphenotype",
#    y_label        = "In-hospital mortality (%)",
#    plot_title     = NULL,             # NULL → auto
#    plot_width     = 6.5,
#    plot_height    = 5.5,
#    figure_filename = NULL,            # NULL → pub_figure_file auto name
#    pause_enable   = TRUE,
#    pause_on_no_output = TRUE
#  ),
#
#  register_block: "plot_histogram"
#  输出: Figures/Figure n. In-hospital Mortality Rate by Subphenotype.pdf
###############################################################################

# ── Private helpers (prefix .ph02_ to avoid post-source collisions) ──────────

.ph02_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.ph02_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else
    data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block         = "plot_histogram",
    reason        = reason,
    suggestion    = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: See ctx$results$pause_point. / ",
    "\u53d1\u73b0\u5f02\u5e38\uff0c\u8bf7\u67e5\u770b ctx$results$pause_point \u5e76\u6307\u793a\u4e0b\u4e00\u6b65\u64cd\u4f5c\u3002",
    call. = FALSE
  )
}

# Convert an event column to 0/1 integer.
# dead_values: character vector of values treated as death (1); anything else → 0.
.ph02_to_dead <- function(x, dead_values) {
  if (is.numeric(x) || is.integer(x)) return(as.integer(x == 1L))
  xu <- toupper(trimws(as.character(x)))
  dv <- toupper(trimws(as.character(dead_values)))
  as.integer(xu %in% dv)
}

# Detect dead_values automatically from the event column.
.ph02_detect_dead_values <- function(x) {
  xu <- unique(toupper(trimws(as.character(x[!is.na(x)]))))
  candidates <- c("EXPIRED", "NON-SURVIVOR", "NON SURVIVOR", "NONSURVIVOR",
                  "DEAD", "DIED", "DEATH", "YES", "Y", "TRUE", "1")
  matched <- xu[xu %in% candidates]
  if (length(matched) > 0) return(matched)
  NULL
}

# ── Main block function ───────────────────────────────────────────────────────

block_plot_histogram <- function(ctx, ...) {

  suppressPackageStartupMessages({
    library(ggplot2)
    library(dplyr)
    library(cli)
  })

  `%||%` <- function(a, b) if (!is.null(a)) a else b

  cfg    <- ctx$config
  bl_cfg <- cfg$plot_histogram %||% list()

  # ── Step 1: Configuration ──────────────────────────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 1: Configuration")

  subtype_col    <- bl_cfg$subtype_col    %||% "Subphenotype"
  event_var      <- bl_cfg$event_var      %||% cfg$data$outcome_column %||% "hospdischargestatus"
  class_prefix   <- bl_cfg$class_prefix   %||% "Subphenotype"
  bar_width      <- bl_cfg$bar_width      %||% 0.65
  show_pct_label <- isTRUE(bl_cfg$show_pct_label %||% TRUE)
  show_chi2_p    <- isTRUE(bl_cfg$show_chi2_p    %||% TRUE)
  x_label        <- bl_cfg$x_label        %||% "Subphenotype"
  y_label        <- bl_cfg$y_label        %||% "In-hospital mortality (%)"
  plot_w         <- bl_cfg$plot_width     %||% 6.5
  plot_h         <- bl_cfg$plot_height    %||% 5.5
  palette        <- bl_cfg$palette        %||% NULL
  font_family    <- plot_font_from_config(cfg)

  cli::cli_alert_info("event_var   : {event_var}")
  cli::cli_alert_info("subtype_col : {subtype_col}")

  # ── Step 2: Load main data ─────────────────────────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 2: Load data")

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    if (.ph02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .ph02_pause(ctx,
        "\u65e0\u5206\u6790\u6570\u636e\uff08imputed / cleaned \u5747\u4e3a\u7a7a\uff09\u3002",
        "\u8bf7\u5148\u8fd0\u884c imputation \u6216 data_clean\u3002")
    }
    stop("plot_histogram: no data available.", call. = FALSE)
  }

  if (!event_var %in% names(data)) {
    if (.ph02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .ph02_pause(ctx,
        paste0("event_var '", event_var, "' not found in data."),
        paste0("Check config$plot_histogram$event_var. Available: ",
               paste(head(names(data), 30), collapse = ", ")),
        utils::head(data, 3L))
    }
    stop("plot_histogram: event_var '", event_var, "' not found.", call. = FALSE)
  }

  # ── Step 3: Merge Subphenotype from df_final ───────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 3: Merge subphenotype labels")

  df_final    <- ctx$results$df_final
  analysis_df <- as.data.frame(data, stringsAsFactors = FALSE)

  if (!is.null(df_final) && subtype_col %in% names(df_final)) {
    # Merge by rownames (subject identity index used in lca block)
    sub_df <- data.frame(
      .rowkey    = rownames(df_final),
      .subtype   = as.character(df_final[[subtype_col]]),
      stringsAsFactors = FALSE
    )
    analysis_df$.rowkey <- rownames(analysis_df)
    analysis_df <- merge(analysis_df, sub_df, by = ".rowkey", all.x = FALSE)
    analysis_df$.rowkey <- NULL
    subtype_use <- ".subtype"
    cli::cli_alert_success("Subphenotype merged from ctx$results$df_final ({nrow(analysis_df)} rows retained).")
  } else if (subtype_col %in% names(analysis_df)) {
    subtype_use <- subtype_col
    cli::cli_alert_info("Subphenotype column '{subtype_col}' found directly in data.")
  } else {
    if (.ph02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .ph02_pause(ctx,
        paste0("Subphenotype column '", subtype_col,
               "' not found in data or df_final."),
        "Run block_lca first, or set config$plot_histogram$subtype_col to the correct column name.",
        utils::head(analysis_df, 3L))
    }
    stop("plot_histogram: subtype column not found.", call. = FALSE)
  }

  # ── Step 4: Convert event to 0/1 ──────────────────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 4: Convert event column")

  raw_event <- analysis_df[[event_var]]
  dead_values <- bl_cfg$dead_values
  if (is.null(dead_values)) {
    dead_values <- .ph02_detect_dead_values(raw_event)
    if (is.null(dead_values)) {
      if (.ph02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
        .ph02_pause(ctx,
          paste0("Cannot auto-detect death values from '", event_var,
                 "'. Unique values: ", paste(unique(raw_event), collapse = ", ")),
          "Set config$plot_histogram$dead_values explicitly, e.g. c('Expired').",
          utils::head(analysis_df[, c(subtype_use, event_var), drop = FALSE], 5L))
      }
      stop("plot_histogram: cannot detect dead_values.", call. = FALSE)
    }
    cli::cli_alert_info("Auto-detected dead_values: {paste(dead_values, collapse=', ')}")
  }

  analysis_df$.dead <- .ph02_to_dead(raw_event, dead_values)

  # ── Step 5: Build subtype factor ───────────────────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 5: Build subtype factor")

  raw_sub  <- analysis_df[[subtype_use]]
  sub_levs <- sort(unique(na.omit(as.integer(raw_sub))))
  if (length(sub_levs) == 0) sub_levs <- sort(unique(na.omit(raw_sub)))

  sub_labels <- paste0(class_prefix, " ", sub_levs)
  analysis_df$.ClassF <- factor(
    paste0(class_prefix, " ", raw_sub),
    levels = sub_labels
  )

  n_subtypes <- nlevels(analysis_df$.ClassF)
  cli::cli_alert_info("Subtypes detected: {n_subtypes} ({paste(sub_labels, collapse=', ')})")
  if (is.null(palette)) {
    palette <- block_default_palette(max(1L, as.integer(n_subtypes)[1L]), cfg)
  }

  # Drop rows with NA subtype or NA event
  n_before <- nrow(analysis_df)
  analysis_df <- analysis_df[!is.na(analysis_df$.ClassF) & !is.na(analysis_df$.dead), ]
  n_after  <- nrow(analysis_df)
  if (n_before > n_after)
    cli::cli_alert_warning("Dropped {n_before - n_after} rows with NA subtype or event.")

  if (nrow(analysis_df) == 0) {
    if (.ph02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .ph02_pause(ctx, "No rows after NA filter.", "Check subtype_col and event_var for NAs.")
    }
    stop("plot_histogram: empty data after NA filter.", call. = FALSE)
  }

  # ── Step 6: Compute mortality summary ─────────────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 6: Compute mortality summary")

  summary_df <- analysis_df %>%
    group_by(.data$.ClassF) %>%
    summarise(
      N         = dplyr::n(),
      Deaths    = sum(.data$.dead, na.rm = TRUE),
      Mortality = .data$Deaths / .data$N,
      .groups   = "drop"
    )

  cli::cli_alert_info("Mortality by subtype:")
  print(as.data.frame(summary_df))

  # Chi-square test across subtypes
  chi_p <- tryCatch({
    ct <- table(analysis_df$.ClassF, analysis_df$.dead)
    stats::chisq.test(ct)$p.value
  }, error = function(e) NA_real_)

  fmt_p <- function(p) {
    if (is.na(p)) return("")
    if (p < 0.001) "<0.001" else sprintf("p = %.3f", p)
  }

  # ── Step 7: Draw histogram ─────────────────────────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 7: Draw bar chart")

  plot_title <- bl_cfg$plot_title %||%
    "In-hospital Mortality Rate by Subphenotype"

  subtitle_text <- if (show_chi2_p && !is.na(chi_p)) {
    paste0("Chi-square test: ", fmt_p(chi_p))
  } else {
    NULL
  }

  y_upper <- max(summary_df$Mortality, na.rm = TRUE) * 1.20

  p_hist <- ggplot(summary_df, aes(x = .data$.ClassF, y = .data$Mortality * 100)) +
    (if (!is.null(palette)) {
      geom_col(aes(fill = .data$.ClassF), width = bar_width, color = "white", linewidth = 0.3)
    } else {
      geom_col(width = bar_width, color = "white", linewidth = 0.3)
    }) +
    (if (!is.null(palette)) scale_fill_manual(values = palette) else list()) +
    (if (show_pct_label) {
      geom_text(
        aes(label = sprintf("%.1f%%", .data$Mortality * 100)),
        vjust = -0.35, size = 3.8,
        family = font_family
      )
    } else list()) +
    scale_y_continuous(
      limits = c(0, y_upper * 100),
      expand = expansion(mult = c(0, 0.02))
    ) +
    labs(
      title    = plot_title,
      subtitle = subtitle_text,
      x        = x_label,
      y        = y_label
    ) +
    theme_bw(base_size = 12) +
    theme(
      text             = element_text(family = font_family),
      plot.title       = element_text(face = "bold", size = 13, hjust = 0),
      plot.subtitle    = element_text(size = 10, hjust = 0),
      axis.title       = element_text(size = 11),
      axis.text        = element_text(size = 10),
      panel.grid.major.x = element_blank(),
      panel.grid.minor   = element_blank(),
      legend.position  = "none"
    )

  # ── Step 8: Save figure ────────────────────────────────────────────────────
  cli::cli_h1("[block_plot_histogram] Step 8: Save figure")

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir, "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  fig_name <- bl_cfg$figure_filename %||% tryCatch(
    pub_figure_file(ctx, "main_figure",
                    "In-hospital Mortality Rate by Subphenotype"),
    error = function(e) "Figure_InHospitalMortality_Histogram.pdf"
  )

  fig_path <- file.path(fig_dir, fig_name)

  saved <- tryCatch({
    grDevices::cairo_pdf(fig_path, width = plot_w, height = plot_h,
                         family = font_family)
    print(p_hist)
    grDevices::dev.off()
    TRUE
  }, error = function(e) {
    cli::cli_alert_warning("cairo_pdf failed ({e$message}), trying pdf().")
    try(grDevices::dev.off(), silent = TRUE)
    tryCatch({
      grDevices::pdf(fig_path, width = plot_w, height = plot_h)
      print(p_hist)
      grDevices::dev.off()
      TRUE
    }, error = function(e2) {
      try(grDevices::dev.off(), silent = TRUE)
      FALSE
    })
  })

  if (!saved) {
    if (.ph02_should_pause(bl_cfg, "pause_on_no_output", TRUE)) {
      .ph02_pause(ctx,
        "plot_histogram: failed to write PDF figure.",
        paste0("Check write permissions for: ", fig_dir),
        utils::head(summary_df, 5L))
    }
    cli::cli_alert_warning("plot_histogram: figure not saved.")
  } else {
    cli::cli_alert_success("Figure saved: {.file {basename(fig_path)}}")
  }

  # ── Step 9: Write results to ctx ───────────────────────────────────────────
  ctx$results$plot_histogram <- list(
    summary_df   = as.data.frame(summary_df),
    chi2_p       = chi_p,
    event_var    = event_var,
    dead_values  = dead_values,
    subtype_col  = subtype_use,
    n_subtypes   = n_subtypes,
    figure_path  = if (saved) fig_path else NULL
  )

  cli::cli_alert_success("[block_plot_histogram] Done.")
  ctx
}

register_block(
  "plot_histogram",
  block_plot_histogram,
  "In-hospital mortality rate bar chart by LCA subphenotype (SCI publication quality)"
)
