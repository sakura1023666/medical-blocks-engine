###############################################################################
#  ipw_dual_db_pub — 双库 IPW 拼图 + summary_result 收口（全项目复用）
#
#  本轮（PE×alteplase）从 run/ipw_pe_alteplase/* 收进引擎。新 IPW 双库课题：
#    1) 配 role_spec（暴露名 / 图题）→ ipw_dual_panel_remirror()
#    2) ipw_finalize_summary_result() → summary_result/ + 600 dpi 四目录
#  禁止在 02block_result 或 /tmp 再堆 remirror/hotfix。
###############################################################################

#' Jin 风格 IPW 双库角色规格（默认对齐 Fig1–5 + S1–S3，跳过 Missing overview）
#' @param exposure_lab 暴露展示名（如 Alteplase / Diabetes_HbA1c）
#' @param cohort_lab Figure 1 队列短语
#' @param outcome_lab 结局短语（图题）
#' @param skip_missing_overview TRUE 时不把 Missing 图纳入拼图
ipw_jin_role_spec <- function(exposure_lab = "Alteplase",
                              cohort_lab = "IPW alteplase cohort",
                              outcome_lab = "28-day all-cause mortality",
                              skip_missing_overview = TRUE) {
  exposure_lab <- as.character(exposure_lab)[1L]
  cohort_lab <- as.character(cohort_lab)[1L]
  outcome_lab <- as.character(outcome_lab)[1L]
  dest <- list(
    fig1_flowchart = sprintf(
      "Figure 1. Flowchart of patient selection (%s).pdf", cohort_lab
    ),
    fig2_ipw_km = sprintf(
      "Figure 2. IPW-weighted Kaplan–Meier curves of %s by %s.pdf",
      outcome_lab, exposure_lab
    ),
    fig3_subgroup = sprintf(
      "Figure 3. Subgroup analysis of %s (IPTW-adjusted).pdf", exposure_lab
    ),
    fig4_age_km = sprintf(
      "Figure 4. Subgroup Kaplan–Meier curves of 28-day mortality by age.pdf"
    ),
    fig5_stepp = sprintf(
      "Figure 5. STEPP of 28-day survival by %s across composite risk.pdf",
      exposure_lab
    ),
    supp_ps_smd = paste0(
      "Figure S1. The distribution of propensity score and standardized mean ",
      "difference before and after weighting.pdf"
    ),
    supp_unweighted = sprintf(
      "Figure S2. Unweighted Kaplan–Meier curves of %s by %s.pdf",
      outcome_lab, exposure_lab
    ),
    supp_calib = paste0(
      "Figure S3. Calibration and receiver operating characteristic curves of ",
      "the prediction model at 28-day.pdf"
    )
  )
  list(
    exposure_lab = exposure_lab,
    skip_missing_overview = isTRUE(skip_missing_overview),
    pub_roles = names(dest),
    dest_name = dest,
    stack_roles = c("fig4_age_km", "fig5_stepp", "supp_calib"),
    role_of = function(bn) {
      bn <- as.character(bn)[1L]
      if (isTRUE(skip_missing_overview) && grepl("Missing", bn, ignore.case = TRUE)) {
        return(NA_character_)
      }
      if (grepl("Figure 1-", bn) && grepl("Flowchart", bn, ignore.case = TRUE)) {
        return("fig1_flowchart")
      }
      if (grepl("Figure 2-", bn) && grepl("IPW-weighted", bn, ignore.case = TRUE)) {
        return("fig2_ipw_km")
      }
      if (grepl("Figure 3-", bn)) return("fig3_subgroup")
      if (grepl("Figure 4-", bn) && grepl("age|Subgroup Kaplan", bn, ignore.case = TRUE)) {
        return("fig4_age_km")
      }
      if (grepl("Figure 5-", bn) && grepl("STEPP", bn, ignore.case = TRUE)) {
        return("fig5_stepp")
      }
      if (grepl("Unweighted Kaplan", bn, ignore.case = TRUE)) return("supp_unweighted")
      if (grepl("Calibration and receiver|Calibration and ROC", bn, ignore.case = TRUE)) {
        return("supp_calib")
      }
      if (grepl("propensity score|standardized mean", bn, ignore.case = TRUE)) {
        return("supp_ps_smd")
      }
      NA_character_
    }
  )
}

.ipw_map_pdf_roles <- function(dir, role_of) {
  fs <- list.files(dir, pattern = "\\.pdf$", full.names = TRUE)
  out <- list()
  for (f in fs) {
    r <- role_of(basename(f))
    if (!is.na(r) && nzchar(r)) out[[r]] <- f
  }
  out
}

.ipw_write_raster_pdf <- function(img, dest, density) {
  info <- magick::image_info(img)
  w_in <- info$width / as.numeric(density)
  h_in <- info$height / as.numeric(density)
  tmp_png <- tempfile(fileext = ".png")
  on.exit(unlink(tmp_png), add = TRUE)
  magick::image_write(img, path = tmp_png, format = "png")
  ok <- FALSE
  if (isTRUE(capabilities("cairo"))) {
    ok <- tryCatch({
      grDevices::cairo_pdf(dest, width = w_in, height = h_in)
      TRUE
    }, error = function(e) FALSE)
  }
  if (!isTRUE(ok)) {
    grDevices::pdf(dest, width = w_in, height = h_in, useDingbats = FALSE)
  }
  grid::grid.newpage()
  if (!requireNamespace("png", quietly = TRUE)) {
    stop("need png package to write dual-panel PDF", call. = FALSE)
  }
  rast <- png::readPNG(tmp_png)
  grid::grid.raster(rast, width = grid::unit(1, "npc"), height = grid::unit(1, "npc"),
                    interpolate = TRUE)
  grDevices::dev.off()
  invisible(dest)
}

#' 等框双栏拼图（顶白带放 A/B，避免压标题）
ipw_compose_equal_panels <- function(pdf_a, pdf_b, dest,
                                     label_a = "A. MIMIC", label_b = "B. eICU",
                                     band_h = 52L, density = 200,
                                     equal_box = TRUE, stack = FALSE,
                                     label_size = 22L) {
  if (!requireNamespace("magick", quietly = TRUE)) {
    stop("need magick", call. = FALSE)
  }
  ia <- magick::image_read_pdf(pdf_a, density = density)[1L]
  ib <- magick::image_read_pdf(pdf_b, density = density)[1L]
  wa <- magick::image_info(ia)$width
  ha <- magick::image_info(ia)$height
  wb <- magick::image_info(ib)$width
  hb <- magick::image_info(ib)$height
  if (isTRUE(stack)) {
    tw <- as.integer(max(wa, wb))
    ia <- magick::image_resize(ia, paste0(tw, "x"))
    ib <- magick::image_resize(ib, paste0(tw, "x"))
  } else {
    th <- as.integer(max(ha, hb))
    ia <- magick::image_resize(ia, paste0("x", th))
    ib <- magick::image_resize(ib, paste0("x", th))
    tw <- as.integer(max(magick::image_info(ia)$width, magick::image_info(ib)$width))
    grav <- if (isTRUE(equal_box)) "north" else "center"
    ia <- magick::image_extent(ia, geometry = paste0(tw, "x", th), gravity = grav, color = "white")
    ib <- magick::image_extent(ib, geometry = paste0(tw, "x", th), gravity = grav, color = "white")
  }
  add_band <- function(im) {
    info <- magick::image_info(im)
    geom_band <- paste0(info$width, "x", info$height + as.integer(band_h))
    magick::image_extent(im, geometry = geom_band, gravity = "south", color = "white")
  }
  ia <- add_band(ia)
  ib <- add_band(ib)
  ia <- magick::image_annotate(
    ia, label_a, size = as.integer(label_size), gravity = "northwest",
    color = "black", weight = 700, location = "+18+12"
  )
  ib <- magick::image_annotate(
    ib, label_b, size = as.integer(label_size), gravity = "northwest",
    color = "black", weight = 700, location = "+18+12"
  )
  combo <- magick::image_append(c(ia, ib), stack = isTRUE(stack))
  png_out <- file.path(dirname(dirname(dest)), "png", sub("\\.pdf$", ".png", basename(dest)))
  dir.create(dirname(png_out), recursive = TRUE, showWarnings = FALSE)
  magick::image_write(combo, path = png_out, format = "png")
  .ipw_write_raster_pdf(combo, dest, density = density)
  invisible(dest)
}

#' 双库 unit PDF → 根 Figures/ 拼图 + 四目录 @ ≥600 dpi
#' @param project_root 课题根
#' @param unit_a,unit_b by_unit 下 【success】 后缀（如 main / eICU）
#' @param role_spec `ipw_jin_role_spec()` 返回值
#' @param out_figures 默认 `project_root/Figures`
ipw_dual_panel_remirror <- function(project_root,
                                    unit_a = "main",
                                    unit_b = "eICU",
                                    label_a = "A. MIMIC",
                                    label_b = "B. eICU",
                                    role_spec = ipw_jin_role_spec(),
                                    out_figures = NULL,
                                    purge = TRUE) {
  project_root <- as.character(project_root)[1L]
  stopifnot(dir.exists(project_root))
  if (!requireNamespace("magick", quietly = TRUE)) stop("need magick", call. = FALSE)
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli", call. = FALSE)

  tag_a <- paste0("\u3010success\u3011", unit_a)
  tag_b <- paste0("\u3010success\u3011", unit_b)
  pdf_a <- file.path(project_root, "by_unit", tag_a, "Figures", "pdf")
  pdf_b <- file.path(project_root, "by_unit", tag_b, "Figures", "pdf")
  if (!dir.exists(pdf_a) || !dir.exists(pdf_b)) {
    stop("missing unit Figures/pdf: ", pdf_a, " | ", pdf_b, call. = FALSE)
  }
  out_fig <- out_figures %||% file.path(project_root, "Figures")
  dir.create(file.path(out_fig, "pdf"), recursive = TRUE, showWarnings = FALSE)

  m_map <- .ipw_map_pdf_roles(pdf_a, role_spec$role_of)
  e_map <- .ipw_map_pdf_roles(pdf_b, role_spec$role_of)

  if (isTRUE(purge)) {
    for (sub in c("pdf", "png", "tiff", "image_information")) {
      d <- file.path(out_fig, sub)
      if (!dir.exists(d)) next
      unlink(list.files(d, pattern = "^Figure", full.names = TRUE))
    }
    unlink(list.files(out_fig, pattern = "^Figure.*\\.(pdf|png|tiff|md)$", full.names = TRUE))
  }

  n_ok <- 0L
  missing <- character(0)
  for (r in role_spec$pub_roles) {
    dest_bn <- role_spec$dest_name[[r]]
    if (is.null(dest_bn) || !nzchar(dest_bn)) next
    pa <- m_map[[r]]
    pb <- e_map[[r]]
    if (is.null(pa) || is.null(pb) || !file.exists(pa) || !file.exists(pb)) {
      missing <- c(missing, r)
      cli::cli_alert_danger("pair missing for {r}")
      next
    }
    dest <- file.path(out_fig, "pdf", dest_bn)
    do_stack <- r %in% (role_spec$stack_roles %||% character(0))
    ipw_compose_equal_panels(pa, pb, dest, label_a = label_a, label_b = label_b,
                             stack = do_stack)
    cli::cli_alert_success("{dest_bn}{if (do_stack) ' [stack]' else ''}")
    n_ok <- n_ok + 1L
  }

  if (exists("pub_figure_ensure_formats", mode = "function")) {
    pub_figure_ensure_formats(out_fig, config = list())
  }
  st <- if (exists("pub_figure_formats_status", mode = "function")) {
    pub_figure_formats_status(out_fig)
  } else {
    list(ok = NA)
  }
  list(
    ok = isTRUE(st$ok) && !length(missing),
    n_ok = n_ok,
    missing_roles = missing,
    out_figures = out_fig,
    status = st
  )
}

#' 根 Tables/Figures → summary_result/ + 软件版本 + 可选 Methods md
#' @param methods_lines 字符向量；NULL 则不写 Methods_statistical_analysis.md
#' @param readme_lines 字符向量；NULL 用默认短 README
ipw_finalize_summary_result <- function(project_root,
                                        methods_lines = NULL,
                                        readme_lines = NULL,
                                        extra_pkgs = c(
                                          "WeightIt", "survey", "MatchIt", "cobalt",
                                          "forestploter", "survminer", "magick", "ipw"
                                        ),
                                        software_roles = NULL) {
  project_root <- as.character(project_root)[1L]
  stopifnot(dir.exists(project_root))
  if (!requireNamespace("cli", quietly = TRUE)) stop("need cli", call. = FALSE)

  sum_root <- file.path(project_root, "summary_result")
  tab_dir <- file.path(sum_root, "Tables")
  fig_dir <- file.path(sum_root, "Figures")
  for (d in c(sum_root, tab_dir, fig_dir)) {
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }

  src_tabs <- character(0)
  root_tabs <- file.path(project_root, "Tables")
  if (dir.exists(root_tabs)) {
    src_tabs <- list.files(root_tabs, pattern = "\\.(xlsx|csv)$", full.names = TRUE)
  }
  for (tag in list.files(file.path(project_root, "by_unit"), pattern = "^\u3010success\u3011")) {
    ut <- file.path(project_root, "by_unit", tag, "Tables")
    if (!dir.exists(ut)) next
    src_tabs <- c(src_tabs, list.files(
      ut, pattern = "^Table (1|S[1-4]|Sens)-.*\\.(xlsx|csv)$", full.names = TRUE
    ))
  }
  src_tabs <- unique(src_tabs)
  unlink(list.files(tab_dir, full.names = TRUE))
  by_bn <- split(src_tabs, basename(src_tabs))
  for (bn in names(by_bn)) {
    paths <- by_bn[[bn]]
    paths <- paths[order(file.info(paths)$mtime, decreasing = TRUE)]
    file.copy(paths[[1L]], file.path(tab_dir, bn), overwrite = TRUE)
  }
  cli::cli_alert_success("Tables -> {tab_dir} ({length(list.files(tab_dir))} files)")

  src_fig <- file.path(project_root, "Figures")
  if (!dir.exists(src_fig)) stop("missing root Figures: ", src_fig, call. = FALSE)
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    d <- file.path(fig_dir, sub)
    if (dir.exists(d)) unlink(list.files(d, full.names = TRUE))
    dir.create(d, recursive = TRUE, showWarnings = FALSE)
    src_sub <- file.path(src_fig, sub)
    if (!dir.exists(src_sub)) next
    fs <- list.files(src_sub, full.names = TRUE)
    if (length(fs)) file.copy(fs, d, overwrite = TRUE)
  }
  if (exists("pub_figure_ensure_formats", mode = "function")) {
    pub_figure_ensure_formats(fig_dir, config = list())
  }
  st <- if (exists("pub_figure_formats_status", mode = "function")) {
    pub_figure_formats_status(fig_dir)
  } else list(ok = NA)
  cli::cli_alert_info(
    "Figures four-format ok={isTRUE(st$ok)}; n_pdf={length(list.files(file.path(fig_dir,'pdf')))}"
  )

  if (exists("pub_write_software_versions", mode = "function")) {
    pub_write_software_versions(
      index_root = sum_root,
      project_root = project_root,
      config = list(software_versions = list(extra_pkgs = extra_pkgs))
    )
  }
  if (exists("pub_write_methods_software_section", mode = "function")) {
    roles <- software_roles %||% c(
      survival = "Cox models / Surv objects",
      survminer = "Kaplan–Meier and risk tables",
      WeightIt = "Overlap weights (ATO)",
      survey = "IPTW-weighted designs / subgroup",
      tableone = "Baseline Table 1 + SMD",
      mice = "Multiple imputation",
      forestploter = "Subgroup forest (Fig 3)",
      ggplot2 = "STEPP / calibration panels",
      magick = "Dual-panel figure composition",
      openxlsx = "SCI three-line xlsx"
    )
    pub_write_methods_software_section(
      out_path = sum_root, roles = roles, extra_pkgs = extra_pkgs
    )
  }

  if (!is.null(methods_lines) && length(methods_lines)) {
    writeLines(methods_lines, file.path(sum_root, "Methods_statistical_analysis.md"),
               useBytes = TRUE)
  }

  if (is.null(readme_lines)) {
    readme_lines <- c(
      "# summary_result — IPW dual-database publication bundle",
      "",
      "- `Tables/` — baseline / supp / Sens",
      "- `Figures/` — dual-panel set (pdf/png/tiff + image_information) @ ≥600 dpi",
      "- `Methods_software_versions.txt` / `Methods_software_section.md`",
      "",
      "## QC",
      "",
      "```bash",
      "Rscript run/pub/run_pub_qc_after_project.R --project <project_root>",
      "```",
      ""
    )
  }
  writeLines(readme_lines, file.path(sum_root, "README.md"), useBytes = TRUE)

  list(ok = isTRUE(st$ok), summary_root = sum_root, status = st)
}
