###############################################################################
#  boxplot_train_validation — 训练/验证集连续变量箱线图（交付 Figure S1 风格）
#
#  register_block: "boxplot_train_validation"
#  典型流水线: train_validation + imputation 之后
#  参考: Figure S1 Boxplot.R（Training set vs Validation set，每行 4 个）
#
#  boxplot_train_validation = list(
#    enable = TRUE,
#    vars = NULL,                 # NULL=自动选连续列；或字符向量
#    ncol = 4L,
#    width = 12, height = NULL,   # NULL 按行数自动
#    font_family = "Times New Roman",
#    figure_stem = NULL           # NULL → Figure S*. Comparison of continuous...
#  )
###############################################################################

.bxtv02_is_continuous <- function(x) {
  if (is.logical(x)) return(FALSE)
  if (is.factor(x) || is.character(x)) return(FALSE)
  is.numeric(x) || is.integer(x)
}

.bxtv02_resolve_vars <- function(train, test, bl_cfg, drop_cols) {
  explicit <- bl_cfg$vars %||% bl_cfg$response_vars %||% NULL
  if (!is.null(explicit) && length(explicit)) {
    return(intersect(as.character(explicit), intersect(names(train), names(test))))
  }
  cand <- intersect(names(train), names(test))
  cand <- setdiff(cand, drop_cols)
  cand[vapply(cand, function(nm) {
    .bxtv02_is_continuous(train[[nm]]) && .bxtv02_is_continuous(test[[nm]])
  }, logical(1))]
}

block_boxplot_train_validation <- function(ctx, ...) {
  bl_cfg <- ctx$config$boxplot_train_validation %||% list()
  if (isFALSE(bl_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("config$boxplot_train_validation$enable=FALSE，跳过。")
    return(ctx)
  }
  if (!requireNamespace("ggplot2", quietly = TRUE) ||
      !requireNamespace("cowplot", quietly = TRUE)) {
    cli::cli_alert_warning("需要 ggplot2 + cowplot，跳过 boxplot_train_validation。")
    return(ctx)
  }

  train <- ctx$data$train %||% NULL
  test <- ctx$data$validation %||% ctx$data$test %||% NULL
  if (is.null(train) || !is.data.frame(train) || is.null(test) || !is.data.frame(test)) {
    cli::cli_alert_warning("boxplot_train_validation: 需要 ctx$data$train 与 validation/test。")
    return(ctx)
  }

  drop_cols <- unique(c(
    as.character(ctx$config$data$id_column %||% character(0)),
    as.character((ctx$config$data %||% list())$strip_id_columns_after_imputation %||% character(0)),
    "Group", "Disease_Group", "Disease", "SEQN", "SEQN_original", "id", "ID",
    "predicted_prob", "dataset", ".row", ".weights", "weights", "sample_weight",
    "fustatus", as.character((ctx$config$survival %||% list())$event_var %||% ""),
    as.character((ctx$config$survival %||% list())$time_var %||% "")
  ))
  drop_cols <- drop_cols[nzchar(drop_cols)]

  vars <- .bxtv02_resolve_vars(train, test, bl_cfg, drop_cols)
  if (!length(vars)) {
    cli::cli_alert_warning("boxplot_train_validation: 无连续变量可画。")
    return(ctx)
  }

  labels <- bl_cfg$variable_labels %||% NULL
  font_family <- as.character(bl_cfg$font_family %||% "Times New Roman")[1L]
  plots <- lapply(vars, function(nm) {
    lab <- if (!is.null(labels) && nm %in% names(labels)) {
      as.character(labels[[nm]])[1L]
    } else {
      nm
    }
    data_long <- data.frame(
      value = c(train[[nm]], test[[nm]]),
      dataset = factor(
        c(rep("Training set", nrow(train)), rep("Validation set", nrow(test))),
        levels = c("Training set", "Validation set")
      ),
      stringsAsFactors = FALSE
    )
    data_long$value <- suppressWarnings(as.numeric(data_long$value))
    ggplot2::ggplot(data_long, ggplot2::aes(x = .data$dataset, y = .data$value)) +
      ggplot2::geom_boxplot(fill = "white", outlier.size = 0.6) +
      ggplot2::ylab(lab) +
      ggplot2::labs(x = NULL) +
      ggplot2::theme_bw() +
      ggplot2::theme(
        text = ggplot2::element_text(family = font_family, size = 8),
        axis.title.y = ggplot2::element_text(
          family = font_family, size = 8,
          margin = ggplot2::margin(t = 0, r = 12, b = 0, l = 0)
        ),
        axis.text = ggplot2::element_text(family = font_family, size = 7),
        plot.margin = ggplot2::margin(4, 6, 4, 6)
      )
  })

  ncol <- as.integer(bl_cfg$ncol %||% 4L)[1L]
  if (!is.finite(ncol) || ncol < 1L) ncol <- 4L
  n_plots <- length(plots)
  n_rows <- as.integer(ceiling(n_plots / ncol))
  row_plots <- lapply(seq_len(n_rows), function(i) {
    i0 <- (i - 1L) * ncol + 1L
    i1 <- min(i * ncol, n_plots)
    cowplot::plot_grid(plotlist = plots[i0:i1], ncol = ncol)
  })
  combined <- cowplot::plot_grid(plotlist = row_plots, ncol = 1L)

  w <- as.numeric(bl_cfg$width %||% 12)[1L]
  h <- as.numeric(bl_cfg$height %||% (max(6, 2.2 * n_rows)))[1L]
  stem <- bl_cfg$figure_stem %||% NULL
  if (is.null(stem) || !nzchar(as.character(stem)[1L])) {
    if (exists("pub_figure_file", mode = "function") && isTRUE(bl_cfg$use_pub_numbering %||% TRUE)) {
      stem <- pub_figure_file(
        ctx, "supp_figure",
        "Comparison of continuous variable outliers before and after processing"
      )
      stem <- sub("\\.pdf$", "", stem, ignore.case = TRUE)
    } else {
      stem <- "Figure S1. Comparison of continuous variable outliers before and after processing"
    }
  }
  stem <- sub("\\.pdf$", "", as.character(stem)[1L], ignore.case = TRUE)

  fig_dir <- ctx$output_dir_figures %||% file.path(ctx$output_dir %||% ".", "Figures")
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
  out_pdf <- file.path(fig_dir, paste0(stem, ".pdf"))

  ok <- isTRUE(tryCatch({
    ggplot2::ggsave(
      out_pdf, combined, width = w, height = h,
      device = if (isTRUE(capabilities("cairo"))) grDevices::cairo_pdf else grDevices::pdf,
      limitsize = FALSE
    )
    TRUE
  }, error = function(e) FALSE))
  if (!ok) {
    ggplot2::ggsave(out_pdf, combined, width = w, height = h, device = grDevices::pdf, limitsize = FALSE)
  }

  ## 同步到根 Figures/pdf
  root_fig <- file.path(ctx$root_output_dir %||% dirname(ctx$output_dir %||% "."), "Figures")
  if (!dir.exists(root_fig)) {
    root_fig <- file.path(dirname(ctx$root_output_dir %||% "."), "Figures")
  }
  ## ALLVARS 惯例：root_output_dir=.../Clinical → 上级 Figures
  pub_pdf <- file.path(dirname(ctx$root_output_dir %||% ctx$output_dir %||% "."), "Figures", "pdf")
  if (dir.exists(dirname(pub_pdf)) || grepl("ALLVARS|Figures", pub_pdf)) {
    dir.create(pub_pdf, recursive = TRUE, showWarnings = FALSE)
    file.copy(out_pdf, file.path(pub_pdf, basename(out_pdf)), overwrite = TRUE)
  }
  if (dir.exists(dirname(root_fig))) {
    for (sub in c("pdf", "")) {
      d <- if (nzchar(sub)) file.path(root_fig, sub) else root_fig
      dir.create(d, recursive = TRUE, showWarnings = FALSE)
      file.copy(out_pdf, file.path(d, basename(out_pdf)), overwrite = TRUE)
    }
  }

  cli::cli_alert_success("train/val 箱线图已写出: {.file {out_pdf}}（n_var={n_plots}）")
  ctx$results$boxplot_train_validation <- list(
    n_vars = n_plots,
    vars = vars,
    pdf = out_pdf
  )
  ctx
}

register_block(
  "boxplot_train_validation",
  block_boxplot_train_validation,
  "训练/验证集连续变量箱线图（交付 Figure S1 风格）"
)
