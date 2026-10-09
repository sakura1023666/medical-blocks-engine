###############################################################################
# ml_dual_literature_final — 双库预后 ML「关联在前、ML 在后」终稿构建
###############################################################################

ml_dual_literature_figure_spec <- function() {
  data.frame(
    order = 1:12,
    role = c(
      "flowchart", "joint_km", "rcs", "comparator_roc", "landmark",
      "subgroup", "boruta", "three_set_roc", "three_set_calibration",
      "three_set_metrics", "three_set_dca", "shap"
    ),
    db_mode = c(
      "combined", rep("paired", 5L), "primary",
      rep("three_set", 4L), "primary"
    ),
    title = c(
      "Flowchart",
      "Kaplan-Meier curves of joint groups",
      "Restricted cubic spline analysis",
      "ROC comparison with APSIII",
      "Day-7 landmark analysis",
      "Subgroup analyses",
      "Boruta feature selection",
      "ML ROC in training, internal validation, and external validation",
      "ML calibration in training, internal validation, and external validation",
      "ML metrics in training, internal validation, and external validation",
      "ML decision curve analysis in training, internal validation, and external validation",
      "SHAP interpretation of the best model"
    ),
    stringsAsFactors = FALSE
  )
}

ml_dual_literature_table_spec <- function() {
  main_roles <- c(
    "baseline_primary", "joint_cox_paired", "ml_train",
    "ml_internal", "ml_external"
  )
  supp_roles <- c(
    "baseline_external", "train_internal_baseline", "univariate_cox",
    "vif", "comparator_roc_paired", "ph_paired", "hyperparameters",
    "logloss", "delong", "nri_idi"
  )
  data.frame(
    main_no = c(seq_along(main_roles), rep(NA_integer_, length(supp_roles))),
    supp_no = c(rep(NA_integer_, length(main_roles)), seq_along(supp_roles)),
    role = c(main_roles, supp_roles),
    stringsAsFactors = FALSE
  )
}

.mdl_final_pdf_files <- function(path) {
  if (!dir.exists(path)) return(character(0))
  list.files(
    path, pattern = "\\.pdf$", recursive = TRUE,
    full.names = TRUE, ignore.case = TRUE
  )
}

.mdl_final_pick_one <- function(files, pattern, prefer_step = FALSE) {
  hit <- files[grepl(pattern, basename(files), ignore.case = TRUE, perl = TRUE)]
  if (isTRUE(prefer_step) && length(hit) > 1L) {
    in_step <- hit[grepl("[/\\\\]step[0-9]+_", hit, ignore.case = TRUE)]
    if (length(in_step)) hit <- in_step
  }
  unique(normalizePath(hit, winslash = "/", mustWork = FALSE))
}

ml_dual_literature_resolve_sources <- function(index_root, config = list()) {
  index_root <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
  spec <- ml_dual_literature_figure_spec()
  primary_dir <- file.path(index_root, "MIMIC_IV")
  external_dir <- file.path(index_root, "eICU")
  aggregate_dir <- file.path(index_root, "Figures", "pdf")
  pri <- .mdl_final_pdf_files(primary_dir)
  ext <- .mdl_final_pdf_files(external_dir)
  agg <- .mdl_final_pdf_files(aggregate_dir)

  patterns <- c(
    flowchart = "^Figure 1\\. Flowchart\\.pdf$",
    joint_km = "Kaplan.Meier curves of joint .+ groups\\.pdf$",
    rcs = "RCS Analysis.*SOSM.*Mortality.*AKI\\.pdf$",
    comparator_roc = "ROC comparison of joint indices and APSIII\\.pdf$",
    landmark = "Day 7 landmark analysis by Diabetes\\.pdf$",
    subgroup = "Subgroup Forest analyses of SOSM\\.pdf$",
    boruta = "Boruta\\.pdf$",
    three_set_roc = "ML ROC training internal and external\\.pdf$",
    three_set_calibration = "ML calibration training internal and external\\.pdf$",
    three_set_metrics = "ML metrics training internal and external\\.pdf$",
    three_set_dca = "ML DCA training internal and external\\.pdf$",
    shap = "SHAP\\.pdf$"
  )

  rows <- vector("list", nrow(spec))
  missing <- character(0)
  duplicates <- character(0)
  for (i in seq_len(nrow(spec))) {
    role <- spec$role[[i]]
    mode <- spec$db_mode[[i]]
    pa <- pb <- character(0)
    if (identical(mode, "paired")) {
      pa <- .mdl_final_pick_one(pri, patterns[[role]], prefer_step = TRUE)
      pb <- .mdl_final_pick_one(ext, patterns[[role]], prefer_step = TRUE)
    } else if (identical(mode, "primary")) {
      source_pool <- if (identical(role, "boruta")) pri else agg
      pa <- .mdl_final_pick_one(
        source_pool, patterns[[role]],
        prefer_step = identical(role, "boruta")
      )
    } else {
      pa <- .mdl_final_pick_one(agg, patterns[[role]])
    }
    n_source <- length(pa) + length(pb)
    expected <- if (identical(mode, "paired")) 2L else 1L
    if (n_source < expected) missing <- c(missing, role)
    if (length(pa) > 1L || length(pb) > 1L || n_source > expected) {
      duplicates <- c(duplicates, role)
    }
    rows[[i]] <- data.frame(
      order = spec$order[[i]],
      role = role,
      db_mode = mode,
      source_a = if (length(pa)) pa[[1L]] else NA_character_,
      source_b = if (length(pb)) pb[[1L]] else NA_character_,
      n_source = n_source,
      stringsAsFactors = FALSE
    )
  }
  list(
    figures = do.call(rbind, rows),
    tables = data.frame(),
    missing = unique(missing),
    duplicates = unique(duplicates)
  )
}

.mdl_final_engine_root <- function() {
  root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
  normalizePath(root, winslash = "/", mustWork = TRUE)
}

.mdl_final_ensure_figure_helpers <- function() {
  if (exists("pub_figure_combine_ab_pdfs", mode = "function") &&
      exists("pub_figure_ensure_formats", mode = "function")) {
    return(invisible(TRUE))
  }
  root <- .mdl_final_engine_root()
  if (!exists("%||%", mode = "function")) {
    source(file.path(root, "R", "utils.R"), local = FALSE)
  }
  source(file.path(root, "R", "pub_figure_export.R"), local = FALSE)
  invisible(TRUE)
}

ml_dual_literature_build_figures <- function(index_root, final_root,
                                             config = list(), dry_run = FALSE) {
  resolved <- ml_dual_literature_resolve_sources(index_root, config)
  if (length(resolved$missing) || length(resolved$duplicates)) {
    stop(
      "终稿图来源闸门失败；missing=", paste(resolved$missing, collapse = ","),
      "; duplicates=", paste(resolved$duplicates, collapse = ","),
      call. = FALSE
    )
  }
  spec <- ml_dual_literature_figure_spec()
  src <- resolved$figures
  target_name <- sprintf("Figure %d. %s.pdf", spec$order, spec$title)
  manifest <- data.frame(
    kind = "Figure",
    number = spec$order,
    role = spec$role,
    title = spec$title,
    db_mode = spec$db_mode,
    source_files = ifelse(
      is.na(src$source_b), src$source_a,
      paste(src$source_a, src$source_b, sep = " | ")
    ),
    target_name = target_name,
    status = "planned",
    stringsAsFactors = FALSE
  )
  if (isTRUE(dry_run)) return(manifest)

  .mdl_final_ensure_figure_helpers()
  combine_ab <- get("pub_figure_combine_ab_pdfs", mode = "function")
  ensure_formats <- get("pub_figure_ensure_formats", mode = "function")
  harvest_findings <- get("pub_figure_harvest_findings", mode = "function")
  write_image_md <- get("pub_figure_write_image_md", mode = "function")
  figures_dir <- file.path(final_root, "Figures")
  dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(nrow(manifest))) {
    target <- file.path(figures_dir, manifest$target_name[[i]])
    mode <- manifest$db_mode[[i]]
    ok <- if (identical(mode, "paired")) {
      combine_ab(
        src$source_a[[i]], src$source_b[[i]], target,
        labels = c("A  MIMIC-IV", "B  eICU"),
        stack = FALSE,
        best_content_page = TRUE,
        label_band = 24
      )
    } else {
      isTRUE(file.copy(src$source_a[[i]], target, overwrite = TRUE))
    }
    if (!isTRUE(ok) || !file.exists(target) || file.info(target)$size < 800L) {
      stop("终稿图构建失败: ", manifest$role[[i]], call. = FALSE)
    }
    manifest$status[[i]] <- "built"
  }

  meta <- list(
    exposure = "SOSM+WPR",
    outcome = "28-day all-cause mortality",
    databases = c("MIMIC-IV", "eICU"),
    combined = TRUE,
    grouping = "median × median (Group1-4)"
  )
  fmt <- ensure_formats(
    figures_dir, meta = meta, config = config, purge = TRUE
  )
  if (!isTRUE(fmt$ok)) stop("终稿图四格式导出失败", call. = FALSE)

  findings <- tryCatch(
    harvest_findings(figures_dir, meta),
    error = function(e) list()
  )
  for (i in seq_len(nrow(manifest))) {
    stem <- sub("\\.pdf$", "", manifest$target_name[[i]], ignore.case = TRUE)
    local_meta <- meta
    local_meta$findings <- findings
    if (identical(manifest$db_mode[[i]], "primary")) {
      local_meta$combined <- FALSE
      local_meta$databases <- "MIMIC-IV"
    }
    write_image_md(
      file.path(figures_dir, "image_information", paste0(stem, ".md")),
      stem, meta = local_meta, raster_ok = TRUE
    )
  }
  manifest
}

.mdl_final_xlsx_files <- function(path, recursive = FALSE) {
  if (!dir.exists(path)) return(character(0))
  list.files(
    path, pattern = "\\.xlsx$", recursive = recursive,
    full.names = TRUE, ignore.case = TRUE
  )
}

.mdl_final_pick_xlsx <- function(files, pattern) {
  hit <- files[grepl(pattern, basename(files), ignore.case = TRUE, perl = TRUE)]
  unique(normalizePath(hit, winslash = "/", mustWork = FALSE))
}

ml_dual_literature_resolve_table_sources <- function(index_root) {
  index_root <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
  agg <- .mdl_final_xlsx_files(file.path(index_root, "Tables"))
  pri <- .mdl_final_xlsx_files(file.path(index_root, "MIMIC_IV"), recursive = TRUE)
  ext <- .mdl_final_xlsx_files(file.path(index_root, "eICU"), recursive = TRUE)
  one <- function(pool, pattern, role) {
    hit <- .mdl_final_pick_xlsx(pool, pattern)
    if (length(hit) != 1L) {
      stop("表来源解析失败 [", role, "]：候选数=", length(hit), call. = FALSE)
    }
    hit[[1L]]
  }
  list(
    baseline_primary = one(agg, "^Table 1-MIMIC IV\\. Baseline characteristics of AKI", "baseline_primary"),
    joint_cox_paired = c(
      one(agg, "^Table 2-MIMIC IV\\. Joint association", "joint_cox_mimic"),
      one(agg, "^Table 2-eICU\\. Joint association", "joint_cox_eicu")
    ),
    ml_train = one(agg, "^Table 3-MIMIC IV\\. ML performance wide training", "ml_train"),
    ml_internal = one(agg, "^Table 4-MIMIC IV\\. ML performance wide validation", "ml_internal"),
    ml_external = one(agg, "^Table 5-eICU\\. ML performance wide external validation", "ml_external"),
    baseline_external = one(agg, "^Table 1-eICU\\. Baseline characteristics of AKI", "baseline_external"),
    train_internal_baseline = one(agg, "^Table S4-MIMIC IV\\. Baseline characteristics by training", "train_internal_baseline"),
    univariate_cox = one(agg, "^Table S5-MIMIC IV\\. Univariate Regression Analysis", "univariate_cox"),
    vif = c(
      one(pri, "^Table S6-MIMIC IV\\. Multicollinearity Analysis VIF screen \\(Train\\)", "vif_train"),
      one(pri, "^Table S7-MIMIC IV\\. Multicollinearity Analysis VIF screen \\(internal validation", "vif_internal"),
      one(ext, "^Table S3-eICU\\. Multicollinearity Analysis VIF screen \\(external validation", "vif_external")
    ),
    comparator_roc_paired = c(
      one(pri, "^Table S-MIMIC IV\\. ROC comparison with APSIII", "roc_mimic"),
      one(ext, "^Table S-eICU\\. ROC comparison with APSIII", "roc_eicu")
    ),
    ph_paired = c(
      one(agg, "^Table S11-MIMIC IV\\. Proportional hazards assumption", "ph_mimic"),
      one(agg, "^Table S11-eICU\\. Proportional hazards assumption", "ph_eicu")
    ),
    hyperparameters = one(agg, "^Table S7-MIMIC IV\\. Hyperparameters", "hyperparameters"),
    logloss = one(agg, "^Table S8-MIMIC IV\\. Log-Loss", "logloss"),
    delong = one(agg, "^Table S9-MIMIC IV\\. DeLong tests", "delong"),
    nri_idi = one(agg, "^Table S10-MIMIC IV\\. NRI and IDI", "nri_idi")
  )
}

.mdl_final_table_title <- function(role) {
  switch(
    role,
    baseline_primary = "Table 1. Baseline characteristics of the MIMIC-IV cohort",
    joint_cox_paired = "Table 2. Joint association of SOSM and WPR with 28-day mortality",
    ml_train = "Table 3. Machine-learning performance in the training set",
    ml_internal = "Table 4. Machine-learning performance in the internal validation set",
    ml_external = "Table 5. Machine-learning performance in the eICU external validation set",
    baseline_external = "Table S1. Baseline characteristics of the eICU external validation cohort",
    train_internal_baseline = "Table S2. Baseline characteristics by training and internal validation sets",
    univariate_cox = "Table S3. Univariate Cox regression analysis",
    vif = "Table S4. Multicollinearity assessment in model-development and external-validation datasets",
    comparator_roc_paired = "Table S5. ROC comparison of SOSM, WPR, joint groups, and APSIII",
    ph_paired = "Table S6. Proportional hazards assumption tests",
    hyperparameters = "Table S7. Hyperparameters for machine-learning models",
    logloss = "Table S8. Log-Loss of machine-learning models",
    delong = "Table S9. DeLong tests in the training set",
    nri_idi = "Table S10. NRI and IDI in the training set",
    stop("未知终稿表角色: ", role, call. = FALSE)
  )
}

.mdl_final_read_table_body <- function(path) {
  if (!requireNamespace("openxlsx", quietly = TRUE)) {
    stop("需要 openxlsx", call. = FALSE)
  }
  raw <- as.data.frame(
    openxlsx::read.xlsx(
      path, colNames = FALSE, skipEmptyRows = FALSE, skipEmptyCols = FALSE
    ),
    stringsAsFactors = FALSE, check.names = FALSE
  )
  if (nrow(raw) < 2L) stop("表结构不足两行: ", path, call. = FALSE)
  hdr <- trimws(as.character(unlist(raw[2L, , drop = TRUE])))
  keep_col <- nzchar(hdr) & !is.na(hdr)
  hdr <- hdr[keep_col]
  body <- raw[-c(1L, 2L), keep_col, drop = FALSE]
  names(body) <- make.unique(hdr)
  is_note <- grepl("^(Note|Abbreviation|Panel)\\b", trimws(as.character(body[[1L]])), ignore.case = TRUE)
  body <- body[!is_note & rowSums(!is.na(body) & trimws(as.character(as.matrix(body))) != "") > 0L, , drop = FALSE]
  rownames(body) <- NULL
  body
}

.mdl_final_bind_rows_fill <- function(parts) {
  all_names <- unique(unlist(lapply(parts, names), use.names = FALSE))
  parts <- lapply(parts, function(x) {
    miss <- setdiff(all_names, names(x))
    for (nm in miss) x[[nm]] <- NA_character_
    x[, all_names, drop = FALSE]
  })
  do.call(rbind, parts)
}

.mdl_final_ensure_xlsx_helpers <- function() {
  root <- .mdl_final_engine_root()
  if (!exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    source(file.path(root, "R", "utils.R"), local = FALSE)
  }
  if (!exists("pub_xlsx_verify", mode = "function")) {
    source(file.path(root, "R", "pub_xlsx_surgical.R"), local = FALSE)
  }
  invisible(TRUE)
}

.mdl_final_merge_panel_xlsx <- function(files, labels, target, title) {
  parts <- lapply(seq_along(files), function(i) {
    d <- .mdl_final_read_table_body(files[[i]])
    d <- cbind(Panel = labels[[i]], d, stringsAsFactors = FALSE)
    d
  })
  merged <- .mdl_final_bind_rows_fill(parts)
  write_booktabs <- get("sci_xlsx_single_header_booktabs", mode = "function")
  write_booktabs(
    target, title, merged,
    footnotes = paste("Panels:", paste(labels, collapse = "; "))
  )
  invisible(target)
}

ml_dual_literature_build_tables <- function(index_root, final_root,
                                            config = list(), dry_run = FALSE) {
  sources <- ml_dual_literature_resolve_table_sources(index_root)
  spec <- ml_dual_literature_table_spec()
  titles <- vapply(spec$role, .mdl_final_table_title, character(1L))
  target_name <- paste0(titles, ".xlsx")
  manifest <- data.frame(
    kind = ifelse(is.na(spec$main_no), "Supplementary table", "Main table"),
    number = ifelse(is.na(spec$main_no), spec$supp_no, spec$main_no),
    role = spec$role,
    title = titles,
    db_mode = ifelse(
      spec$role %in% c("joint_cox_paired", "comparator_roc_paired", "ph_paired"),
      "paired",
      ifelse(spec$role == "vif", "three_panel", "single")
    ),
    source_files = vapply(
      spec$role, function(r) paste(sources[[r]], collapse = " | "), character(1L)
    ),
    target_name = target_name,
    status = "planned",
    stringsAsFactors = FALSE
  )
  if (isTRUE(dry_run)) return(manifest)

  .mdl_final_ensure_xlsx_helpers()
  edit_cells <- get("pub_xlsx_edit_cells", mode = "function")
  verify_xlsx <- get("pub_xlsx_verify", mode = "function")
  tables_dir <- file.path(final_root, "Tables")
  dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
  for (i in seq_len(nrow(manifest))) {
    role <- manifest$role[[i]]
    target <- file.path(tables_dir, manifest$target_name[[i]])
    src <- sources[[role]]
    if (length(src) == 1L) {
      if (!file.copy(src, target, overwrite = TRUE)) {
        stop("终稿表复制失败: ", role, call. = FALSE)
      }
      edit_cells(
        target,
        data.frame(row = 1L, col = 1L, value = manifest$title[[i]])
      )
    } else {
      labels <- if (identical(role, "vif")) {
        c(
          "Panel A. MIMIC-IV training",
          "Panel B. MIMIC-IV internal validation",
          "Panel C. eICU external validation"
        )
      } else {
        c("Panel A. MIMIC-IV", "Panel B. eICU")
      }
      .mdl_final_merge_panel_xlsx(
        src, labels, target, manifest$title[[i]]
      )
    }
    verified <- verify_xlsx(target)
    if (!isTRUE(verified$readable) ||
        !identical(as.integer(verified$corrupt_cells), 0L) ||
        !is.finite(verified$styles) || verified$styles < 1L) {
      stop("终稿 xlsx 校验失败: ", basename(target), call. = FALSE)
    }
    manifest$status[[i]] <- "verified"
  }
  manifest
}

.mdl_final_assert_safe_target <- function(index_root, final_root) {
  ix <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
  out <- normalizePath(final_root, winslash = "/", mustWork = FALSE)
  if (!startsWith(out, paste0(ix, "/")) ||
      basename(out) %in% c("Tables", "Figures", "MIMIC_IV", "eICU")) {
    stop("终稿输出必须位于成功指标目录内，且不得覆盖原始产物: ", out, call. = FALSE)
  }
  invisible(out)
}

ml_dual_literature_build_final <- function(index_root, final_root,
                                           config = list(), dry_run = FALSE) {
  index_root <- normalizePath(index_root, winslash = "/", mustWork = TRUE)
  final_root <- .mdl_final_assert_safe_target(index_root, final_root)
  fig_dry <- ml_dual_literature_build_figures(
    index_root, final_root, config = config, dry_run = TRUE
  )
  tab_dry <- ml_dual_literature_build_tables(
    index_root, final_root, config = config, dry_run = TRUE
  )
  dry <- rbind(fig_dry, tab_dry)
  if (isTRUE(dry_run)) return(dry)

  staging <- paste0(final_root, ".__staging__")
  backup <- paste0(final_root, ".__previous__")
  unlink(staging, recursive = TRUE, force = TRUE)
  dir.create(staging, recursive = TRUE, showWarnings = FALSE)
  ok <- FALSE
  on.exit({
    if (!ok && dir.exists(staging)) {
      message("构建未完成，staging 保留于: ", staging)
    }
  }, add = TRUE)

  figures <- ml_dual_literature_build_figures(
    index_root, staging, config = config, dry_run = FALSE
  )
  tables <- ml_dual_literature_build_tables(
    index_root, staging, config = config, dry_run = FALSE
  )
  manifest <- rbind(figures, tables)
  manifest$target_file <- ifelse(
    manifest$kind == "Figure",
    file.path("Figures", "pdf", manifest$target_name),
    file.path("Tables", manifest$target_name)
  )
  manifest$verification <- manifest$status
  utils::write.csv(
    manifest[, c(
      "kind", "number", "role", "title", "db_mode", "source_files",
      "target_file", "verification"
    )],
    file.path(staging, "MANIFEST.csv"),
    row.names = FALSE, fileEncoding = "UTF-8"
  )
  writeLines(
    c(
      "# SOSM+WPR publication final",
      "",
      "- Primary/development database: MIMIC-IV",
      "- External validation database: eICU",
      "- Figure scheme: literature-first (association analyses before ML validation)",
      "- Figures: 1–12; paired database analyses are combined as Panel A/B",
      "- Tables: 1–5 and S1–S10",
      "- Models were not retrained; all values originate from the completed SOSM+WPR run.",
      "- Original Tables/Figures and step artifacts remain unchanged."
    ),
    file.path(staging, "README.md"),
    useBytes = TRUE
  )

  if (nrow(figures) != 12L || nrow(tables) != 15L ||
      !all(figures$status == "built") || !all(tables$status == "verified")) {
    stop("终稿数量或校验状态不符合规格", call. = FALSE)
  }

  unlink(backup, recursive = TRUE, force = TRUE)
  had_previous <- dir.exists(final_root)
  if (had_previous && !file.rename(final_root, backup)) {
    stop("无法备份现有 publication_final", call. = FALSE)
  }
  if (!file.rename(staging, final_root)) {
    if (had_previous && dir.exists(backup)) file.rename(backup, final_root)
    stop("无法将 staging 原子替换为 publication_final", call. = FALSE)
  }
  unlink(backup, recursive = TRUE, force = TRUE)
  ok <- TRUE
  manifest
}
