###############################################################################
# ckm_pub_finalize — 每指标独立 summary_results（并行不串台）
# 落盘：by_index/【success】<INDEX>/summary_results/{Tables,Figures}
###############################################################################

.ckm_pub_index_summary_root <- function(ctx, idx = NULL) {
  idx <- as.character(idx %||% ctx$config$incidence$index_var %||% "eGDR")[1L]
  out_root <- ctx$config$project$output_dir %||% "Output"
  # study_batch 时 output_dir 常是 by_unit/<unit>；发表层统一回到项目根 by_index
  sb_base <- (ctx$config$study_batch %||% list())$output_base %||% NULL
  proj_root <- sb_base %||% {
    # 若当前在 by_unit/... 下，上溯到项目根
    p <- normalizePath(out_root, winslash = "/", mustWork = FALSE)
    if (grepl("/by_unit(/|$)", p)) {
      sub("/by_unit(/.*)?$", "", p)
    } else {
      p
    }
  }
  file.path(proj_root, "by_index", paste0("\u3010success\u3011", idx), "summary_results")
}

block_ckm_pub_finalize <- function(ctx, ...) {
  root <- ctx$config$project$root %||% getwd()
  idx <- ctx$config$incidence$index_var %||% "eGDR"
  out_root <- ctx$config$project$output_dir %||% "Output"
  sr <- .ckm_pub_index_summary_root(ctx, idx)

  legacy <- file.path(out_root, "by_index", idx)
  unit_fig <- if (dir.exists(file.path(legacy, "Figures"))) {
    file.path(legacy, "Figures")
  } else if (dir.exists(file.path(out_root, "Figures"))) {
    file.path(out_root, "Figures")
  } else {
    file.path(out_root, "by_index", idx, "Figures")
  }
  unit_tab <- if (dir.exists(file.path(legacy, "Tables"))) {
    file.path(legacy, "Tables")
  } else {
    file.path(out_root, "Tables")
  }

  dir.create(file.path(sr, "Tables"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(sr, "Figures"), recursive = TRUE, showWarnings = FALSE)

  if (dir.exists(unit_tab)) {
    for (f in list.files(unit_tab, full.names = TRUE)) {
      if (!dir.exists(f)) file.copy(f, file.path(sr, "Tables", basename(f)), overwrite = TRUE)
    }
  }
  if (dir.exists(unit_fig)) {
    if (file.exists(file.path(root, "R/pub_figure_export.R"))) {
      source(file.path(root, "R/pub_figure_export.R"), local = FALSE)
      tryCatch(
        pub_figure_ensure_formats(unit_fig, meta = list(index = idx), config = ctx$config),
        error = function(e) cli::cli_alert_warning("四目录: {e$message}")
      )
    }
    fig_files <- list.files(unit_fig, recursive = TRUE, full.names = TRUE)
    unit_fig_n <- normalizePath(unit_fig, winslash = "/", mustWork = FALSE)
    for (f in fig_files) {
      if (dir.exists(f)) next
      fn <- normalizePath(f, winslash = "/", mustWork = FALSE)
      rel <- substring(fn, nchar(unit_fig_n) + 2L)
      dest <- file.path(sr, "Figures", rel)
      dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
      file.copy(f, dest, overwrite = TRUE)
    }
  }

  writeLines(c(
    paste0("# summary_results — ", idx),
    "",
    "本目录为**该指标**的发表交付（并行时各指标互不覆盖）。",
    "",
    "路径约定：`by_index/【success】<INDEX>/summary_results/`",
    "禁止写到项目根单一 `summary_results/`。",
    "",
    "## Post-batch publication rebuild（必做一次）",
    "",
    "Batch/finalize 只汇总 unit 产物。**文献版式 Tables 1–3/S1–S4 + Figures 1–3/S1–S3**",
    "请在 batch 结束后运行：",
    "",
    "```bash",
    "Rscript run/cum_egdr_kmeans_ckm/rebuild_publication.R",
    "```",
    "",
    "Helpers：`R/literature_ckm_cum_egdr.R` + `R/cum_egdr_kmeans_pub.R`",
    "勿复活 `run/cum_egdr_kmeans_ckm/_archive/` 下旧 rebuild 脚本。"
  ), file.path(sr, "README.md"))

  figs <- list.files(file.path(sr, "Figures"), recursive = TRUE, pattern = "\\.(pdf|png|tiff|md)$")
  tabs <- list.files(file.path(sr, "Tables"), recursive = TRUE)
  ctx$results$ckm_pub_finalize <- list(
    summary_results = sr, index = idx, n_fig = length(figs), n_tab = length(tabs)
  )
  cli::cli_alert_success(
    "发表收口 → by_index/\u3010success\u3011{idx}/summary_results: tables={length(tabs)} figures={length(figs)}"
  )
  ctx
}

register_block("ckm_pub_finalize", block_ckm_pub_finalize, "CKM每指标summary_results收口")
