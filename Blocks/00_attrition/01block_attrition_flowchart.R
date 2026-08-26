###############################################################################
#  attrition_flowchart — 通用纳排表 + Figure 1 PDF（全套路默认末尾）
#
#  register_block: "attrition_flowchart"
#  典型位置: 任意 pipeline 最后一个 block（baseline_pipelines / 研究 batch 末尾）
#
#  config$attrition = list(
#    enable = TRUE,                  # FALSE 时整块跳过
#    db_label = "MIMIC",             # 可选；也可从 dual_db/project 推断；用于文件名后缀与标题
#    steps = list(                   # 队列步骤（无 steps 时仍可出单框/仅记账行，并 warning）
#      list(id = "baseline", label = "ICU first-stay baseline",
#           source = "fixed", n = 65366L),                 # fixed | rawdata | id_file | current
#      list(id = "disease", label = "Disease cohort",
#           source = "id_file", path = ".../disease.csv",
#           id_col = "subject_id", join_on = "ID",
#           join_universe_path = ".../baseline.RData",     # 与分析 dabiao 解耦
#           join_universe_obj = "baseline"),
#      list(id = "analytic", label = "Analytic cohort", source = "current")
#    ),
#    outcome_breakdown = TRUE,       # 末步按 outcome 分列 n_*（若列存在）
#    auto_append = TRUE,             # runner 按 block 前后 nrow 变化自动记账
#    draw_pdf = TRUE,
#    specialty_figure_mode = "skip_if_generic",  # 专用 flowchart 遇通用 Figure 1 时 skip / 1b
#    csv_name = "Flowchart_attrition.csv",
#    figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
#    font_family = "Times New Roman"
#  )
#
#  读: ctx$data$* , ctx$results$attrition$log , config$attrition
#  写: Tables/Flowchart_attrition[_db].csv ,
#      Figures/Figure 1. Inclusion exclusion flowchart[_db].pdf ,
#      ctx$results$attrition_flowchart
###############################################################################

.attrition_db_slug <- function(ctx) {
  db <- .attrition_db_label(ctx)
  if (!nzchar(db)) return("")
  tolower(trimws(db))
}

.attrition_db_label <- function(ctx) {
  cfg <- ctx$config %||% list()
  dual <- cfg$dual_db %||% list()
  db <- as.character(dual$current_db %||% "")[1L]
  if (!nzchar(db)) {
    db <- as.character((cfg$project %||% list())$database %||% "")[1L]
  }
  if (!nzchar(db)) {
    db <- as.character((cfg$attrition %||% list())$db_label %||% "")[1L]
  }
  if (!nzchar(db)) return("")
  trimws(db)
}

.attrition_suffix_filename <- function(base_name, db_slug) {
  if (!nzchar(db_slug)) return(base_name)
  ext <- tools::file_ext(base_name)
  if (nzchar(ext)) {
    stem <- sub(paste0("\\.", ext, "$"), "", base_name, ignore.case = TRUE)
    paste0(stem, "_", db_slug, ".", ext)
  } else {
    paste0(base_name, "_", db_slug)
  }
}

block_attrition_flowchart <- function(ctx, ...) {
  cfg <- ctx$config$attrition %||% list()
  if (!is.null(cfg$enable) && !isTRUE(cfg$enable)) return(ctx)

  if (!exists("attrition_finalize_rows", mode = "function")) {
    root <- ctx$project_root %||% getwd()
    al <- file.path(root, "R/attrition_log.R")
    if (file.exists(al)) source(al, local = FALSE)
  }

  rows <- attrition_finalize_rows(ctx, ctx$config)

  out_root <- ctx$root_output_dir %||%
    (ctx$config$project %||% list())$output_dir %||%
    ctx$output_dir %||%
    "."
  tbl_dir <- ctx$output_dir_tables %||% file.path(out_root, "Tables")
  fig_dir <- ctx$output_dir_figures %||% file.path(out_root, "Figures")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  db_slug <- .attrition_db_slug(ctx)
  csv_base <- as.character(cfg$csv_name %||% "Flowchart_attrition.csv")[1L]
  fig_base <- as.character(cfg$figure_name %||%
    "Figure 1. Inclusion exclusion flowchart.pdf")[1L]
  csv_name <- .attrition_suffix_filename(csv_base, db_slug)
  fig_name <- .attrition_suffix_filename(fig_base, db_slug)
  csv_path <- file.path(tbl_dir, csv_name)
  pdf_path <- file.path(fig_dir, fig_name)

  csv_ok <- isTRUE(tryCatch(
    {
      utils::write.csv(rows, csv_path, row.names = FALSE)
      TRUE
    },
    error = function(e) {
      if (requireNamespace("cli", quietly = TRUE)) {
        cli::cli_alert_warning("attrition_flowchart CSV write failed: {e$message}")
      } else {
        warning("attrition_flowchart CSV write failed: ", e$message, call. = FALSE)
      }
      FALSE
    }
  ))

  pdf_ok <- FALSE
  if (isTRUE(cfg$draw_pdf %||% TRUE)) {
    db_lab <- .attrition_db_label(ctx)
    title <- as.character(cfg$title %||% cfg$figure_title %||% "")[1L]
    if (!nzchar(title)) {
      title <- if (nzchar(db_lab)) {
        paste0("Figure 1. Inclusion exclusion flowchart (", db_lab, ")")
      } else {
        "Figure 1. Inclusion exclusion flowchart"
      }
    }
    font_family <- as.character(cfg$font_family %||% "Times New Roman")[1L]
    box_fill <- "#F7F7F7"
    if (exists("is_pub_profile", mode = "function") &&
        is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki")) {
      font_family <- "Times New Roman"
      box_fill <- "#EAF2F8"
    }
    footnote <- character(0)
    if (isTRUE(cfg$weight_footnote %||% TRUE) &&
        exists("attrition_weight_footnote", mode = "function")) {
      footnote <- tryCatch(
        attrition_weight_footnote(ctx),
        error = function(e) character(0)
      )
    }
    pdf_ok <- isTRUE(tryCatch(
      attrition_draw_pdf(rows, title, pdf_path,
                         font_family = font_family, footnote = footnote,
                         box_fill = box_fill),
      error = function(e) {
        if (requireNamespace("cli", quietly = TRUE)) {
          cli::cli_alert_warning("attrition_flowchart PDF draw failed: {e$message}")
        } else {
          warning("attrition_flowchart PDF draw failed: ", e$message, call. = FALSE)
        }
        FALSE
      }
    ))
    if (isTRUE(pdf_ok)) {
      if (exists("attrition_promote_figure1", mode = "function")) {
        attrition_promote_figure1(fig_dir)
      }
      if (exists("mirror_pub_output_to_root", mode = "function")) {
        mirror_pub_output_to_root(ctx, pdf_path)
        fig1 <- file.path(fig_dir, "Figure 1. Flowchart.pdf")
        if (file.exists(fig1)) mirror_pub_output_to_root(ctx, fig1)
      }
    }
  }

  ctx$results$attrition_flowchart <- list(
    rows = rows,
    csv = if (isTRUE(csv_ok)) csv_path else NA_character_,
    pdf = if (isTRUE(pdf_ok)) pdf_path else NA_character_,
    weight_footnote = footnote %||% character(0)
  )

  if (requireNamespace("cli", quietly = TRUE)) {
    out_files <- character(0)
    if (isTRUE(csv_ok)) out_files <- c(out_files, csv_name)
    if (isTRUE(pdf_ok)) out_files <- c(out_files, fig_name)
    if (length(out_files) > 0L) {
      cli::cli_alert_success(
        "attrition_flowchart: {nrow(rows)} step(s) -> {.file {paste(out_files, collapse = ' + ')}}"
      )
    }
  }
  ctx
}

register_block("attrition_flowchart", block_attrition_flowchart,
               "Write inclusion/exclusion attrition table and Figure 1 PDF")
