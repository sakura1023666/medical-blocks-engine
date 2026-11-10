###############################################################################
# gallstone_pub_finalize — 四目录收口
# 规则：预测套图（Fig1/4–9）不进各连续特征 unit；unit 只留 Fig2/3/S
###############################################################################

block_gallstone_pub_finalize <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  source(file.path(root, "R/literature_gallstone_nomogram.R"), local = FALSE)
  if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
    source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
  }
  unit <- as.character(ctx$config$incidence$index_var %||% "ALL")[1L]
  dirs <- gallstone_nomogram_out_dirs(ctx, unit)

  # unit 本征图：仅 Associations / RCS / Subgroup
  unit_fig <- dirs$figures
  dir.create(unit_fig, recursive = TRUE, showWarnings = FALSE)
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    tryCatch(
      pub_figure_ensure_formats(unit_fig, meta = list(index = unit), config = ctx$config),
      error = function(e) cli::cli_alert_warning("四目录: {e$message}")
    )
  }

  sr <- dirs$summary
  dir.create(file.path(sr, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(sr, "Figures"), recursive = TRUE, showWarnings = FALSE)

  # 表：unit 表 + 共享描述表（不含把预测图拷进来）
  for (td in c(dirs$tables, dirs$shared_tables)) {
    if (!dir.exists(td)) next
    for (f in list.files(td, full.names = TRUE)) {
      if (!dir.exists(f)) file.copy(f, file.path(sr, "Tables", basename(f)), overwrite = TRUE)
    }
  }

  # 图：只拷 unit 自己的 Fig2/3/S（按文件名过滤）
  if (dir.exists(unit_fig)) {
    keep_re <- paste0("(Associations|RCS|Subgroup).*", unit, "|Associations ", unit, "|RCS ", unit)
    for (f in list.files(unit_fig, recursive = TRUE, full.names = TRUE)) {
      if (dir.exists(f)) next
      bn <- basename(f)
      if (!grepl("Associations|RCS|Subgroup", bn, ignore.case = TRUE)) next
      # 跳过误入的预测图
      if (grepl("LASSO|Nomogram|ROC|DCA|CIC|Multivariate|flowchart|Inclusion",
                bn, ignore.case = TRUE)) next
      rel <- substring(normalizePath(f, winslash = "/"),
                       nchar(normalizePath(unit_fig, winslash = "/")) + 2L)
      dest <- file.path(sr, "Figures", rel)
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      file.copy(f, dest, overwrite = TRUE)
    }
  }

  # 项目根 summary_results：方法 + 软件版本 + PDF-only + 白名单（全项目同口径）
  proj_sr <- file.path(dirs$project %||% dirname(dirname(sr)), "summary_results")
  if (!dir.exists(proj_sr)) {
    # dirs$project 来自 gallstone_nomogram_out_dirs
    proj_sr <- file.path(ctx$config$project$output_dir %||% ctx$config$project$root %||% root,
                         "summary_results")
  }
  # 更稳：从 unit summary 上溯到课题根
  cand <- normalizePath(file.path(sr, "..", "..", "..", "summary_results"),
                        winslash = "/", mustWork = FALSE)
  if (dir.exists(cand)) proj_sr <- cand
  if (file.exists(file.path(root, "R/pub_gallstone_methods.R"))) {
    source(file.path(root, "R/pub_gallstone_methods.R"), local = FALSE)
  }
  if (exists("gallstone_finalize_summary_delivery", mode = "function") &&
      dir.exists(proj_sr)) {
    tryCatch(
      gallstone_finalize_summary_delivery(
        summary_root = proj_sr,
        project_root = dirname(proj_sr),
        config = ctx$config,
        rewrite_methods = FALSE,
        prune = TRUE
      ),
      error = function(e) cli::cli_alert_warning("根 summary 收口: {e$message}")
    )
  }

  ctx$results$gallstone_pub_finalize <- list(summary = sr, unit = unit, project_summary = proj_sr)
  cli::cli_alert_success("发表收口(关联段) → {sr}")
  ctx
}

register_block("gallstone_pub_finalize", block_gallstone_pub_finalize, "胆结石发表四目录收口")
