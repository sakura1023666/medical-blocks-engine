###############################################################################
#  environment_sensitivity_fdr.R
#  环境 VOC 课题：
#    1) 剔除吸烟人群后重跑 GLM / WQS / BKMR / Qgcomp，结果写入独立 Sensitivity/ 目录
#    2) 全人群对 GLM / WQS / BKMR / QGC 主结果做 BH-FDR，表号接在汇总表后（S20–S23）
#    3) 敏感性同样四方法 FDR，表号接在 SA1–SA4 后（SA5–SA8）
###############################################################################

environment_sensitivity_cfg <- function(config) {
  (config$environment_sensitivity %||% list())
}

environment_fdr_cfg <- function(config) {
  (config$environment_fdr %||% list())
}

environment_sensitivity_output_dir <- function(config) {
  sens <- environment_sensitivity_cfg(config)
  bc <- config$environment_batch %||% list()
  root <- bc$output_base %||% config$project$output_dir
  dirname <- as.character(sens$output_dirname %||% "Sensitivity")[1L]
  if (!nzchar(dirname)) dirname <- "Sensitivity"
  file.path(root, dirname)
}

environment_sensitivity_normalize_levels <- function(x) {
  x <- trimws(as.character(x))
  x <- x[!is.na(x) & nzchar(x)]
  tolower(x)
}

#' 吸烟人群识别：默认剔除 Current（当前吸烟）
environment_sensitivity_is_smoker_level <- function(level, exclude_levels = "Current") {
  lv <- environment_sensitivity_normalize_levels(level)
  ex <- environment_sensitivity_normalize_levels(exclude_levels)
  if (!length(lv) || !length(ex)) return(FALSE)
  if (lv %in% ex) return(TRUE)
  if ("current" %in% ex && grepl("current|now|吸烟|现在吸", lv)) return(TRUE)
  if ("former" %in% ex && grepl("former|ex-smok|曾经|既往", lv)) return(TRUE)
  if ("yes" %in% ex && lv %in% c("yes", "y", "1", "true")) return(TRUE)
  FALSE
}

environment_sensitivity_is_never_only <- function(keep_levels = NULL, exclude_levels = NULL) {
  keep_n <- environment_sensitivity_normalize_levels(keep_levels)
  ex_n <- environment_sensitivity_normalize_levels(exclude_levels)
  if (length(keep_n) == 1L && identical(keep_n, "never")) return(TRUE)
  setequal(ex_n, c("current", "former"))
}

environment_sensitivity_pub_tag <- function(keep_levels = NULL, exclude_levels = NULL) {
  if (environment_sensitivity_is_never_only(keep_levels, exclude_levels)) {
    return("sensitivity: never smokers only")
  }
  ex <- as.character(exclude_levels %||% character(0))
  ex <- ex[nzchar(ex)]
  if (length(ex)) {
    return(paste0("sensitivity: excluding ", paste(ex, collapse = "/")))
  }
  "sensitivity: smoking restriction"
}

environment_sensitivity_keep_mask <- function(data, smoke_col = "Smoking",
                                              exclude_levels = "Current",
                                              keep_levels = NULL) {
  if (is.null(data) || !nrow(data)) {
    return(list(keep = integer(0), n_before = 0L, n_drop = 0L))
  }
  n_before <- nrow(data)
  if (!smoke_col %in% names(data)) {
    stop("敏感性分析：数据中无吸烟列 '", smoke_col, "'", call. = FALSE)
  }
  raw <- as.character(data[[smoke_col]])
  keep_levels <- unique(as.character(keep_levels %||% character(0)))
  keep_levels <- keep_levels[nzchar(keep_levels)]
  if (length(keep_levels)) {
    raw_n <- tolower(trimws(raw))
    keep_n <- environment_sensitivity_normalize_levels(keep_levels)
    keep <- which(!is.na(raw) & nzchar(trimws(raw)) & raw_n %in% keep_n)
    drop <- setdiff(seq_len(n_before), keep)
  } else {
    drop_lgl <- vapply(
      raw,
      environment_sensitivity_is_smoker_level,
      logical(1L),
      exclude_levels = exclude_levels
    )
    drop_lgl[is.na(raw) | !nzchar(trimws(raw))] <- FALSE
    keep <- which(!drop_lgl)
    drop <- which(drop_lgl)
  }
  list(
    keep = keep,
    n_before = n_before,
    n_drop = n_before - length(keep),
    smoke_col = smoke_col,
    exclude_levels = as.character(exclude_levels),
    keep_levels = keep_levels,
    dropped_tab = table(raw[drop], useNA = "ifany"),
    remaining_tab = table(raw[keep], useNA = "ifany")
  )
}

environment_sensitivity_subset_df <- function(df, keep) {
  if (is.null(df) || !is.data.frame(df) || !nrow(df)) return(df)
  if (!length(keep)) return(df[0L, , drop = FALSE])
  keep <- keep[keep >= 1L & keep <= nrow(df)]
  out <- df[keep, , drop = FALSE]
  for (cn in names(out)) {
    if (is.factor(out[[cn]])) out[[cn]] <- droplevels(out[[cn]])
  }
  out
}

environment_sensitivity_drop_constant_covs <- function(vars, data) {
  vars <- unique(as.character(vars[nzchar(as.character(vars))]))
  if (!length(vars) || is.null(data)) return(vars)
  keep <- vapply(vars, function(v) {
    if (!v %in% names(data)) return(FALSE)
    length(unique(stats::na.omit(data[[v]]))) >= 2L
  }, logical(1L))
  vars[keep]
}

environment_sensitivity_rebuild_design <- function(ctx, config) {
  if (!requireNamespace("survey", quietly = TRUE)) {
    stop("敏感性分析需要 survey 包", call. = FALSE)
  }
  options(survey.lonely.psu = "adjust")
  nh <- config$nhanes %||% list()
  wt_col  <- as.character(nh$survey_weight  %||% "new_Weight")[1L]
  psu_col <- as.character(nh$survey_cluster %||% "SDMVPSU")[1L]
  str_col <- as.character(nh$survey_strata  %||% "SDMVSTRA")[1L]
  df <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(df)) stop("敏感性分析：无 imputed/cleaned 数据", call. = FALSE)
  need <- c(psu_col, str_col, wt_col)
  miss <- setdiff(need, names(df))
  if (length(miss)) {
    cli::cli_alert_warning("敏感性分析：缺少抽样列 {paste(miss, collapse = ', ')}，不重建 svydesign")
    ctx$results$nhanes_design <- NULL
    return(ctx)
  }
  w <- suppressWarnings(as.numeric(df[[wt_col]]))
  ok <- is.finite(w) & w > 0
  if (!all(ok)) df <- df[ok, , drop = FALSE]
  ctx$results$nhanes_design <- survey::svydesign(
    id      = stats::as.formula(paste0("~", psu_col)),
    strata  = stats::as.formula(paste0("~", str_col)),
    weights = stats::as.formula(paste0("~", wt_col)),
    data    = df,
    nest    = TRUE
  )
  cli::cli_alert_success(
    "敏感性分析：已重建 svydesign（n = {nrow(ctx$results$nhanes_design$variables)}）"
  )
  ctx
}

environment_sensitivity_apply_filter <- function(ctx, config) {
  sens <- environment_sensitivity_cfg(config)
  smoke_col <- as.character(sens$smoke_col %||% "Smoking")[1L]
  keep_levels <- as.character(sens$keep_levels %||% character(0))
  keep_levels <- keep_levels[nzchar(keep_levels)]
  exclude_levels <- as.character(sens$exclude_levels %||% "Current")
  exclude_levels <- exclude_levels[nzchar(exclude_levels)]
  if (!length(keep_levels) && !length(exclude_levels)) exclude_levels <- "Current"

  data <- ctx$data$imputed %||% ctx$data$cleaned
  info <- environment_sensitivity_keep_mask(
    data, smoke_col,
    exclude_levels = exclude_levels,
    keep_levels = keep_levels
  )
  if (info$n_drop < 1L) {
    cli::cli_alert_warning(
      "敏感性分析：吸烟列 {smoke_col} 未匹配到筛选条件，将按全人群继续"
    )
  }
  keep <- info$keep
  for (slot in c("imputed", "cleaned", "mapped", "raw")) {
    if (!is.null(ctx$data[[slot]]) && is.data.frame(ctx$data[[slot]])) {
      ctx$data[[slot]] <- environment_sensitivity_subset_df(ctx$data[[slot]], keep)
    }
  }
  for (rk in grep("^nhanes_data_", names(ctx$results), value = TRUE)) {
    if (is.data.frame(ctx$results[[rk]])) {
      ctx$results[[rk]] <- environment_sensitivity_subset_df(ctx$results[[rk]], keep)
    }
  }
  ctx$results$environment_sensitivity_filter <- list(
    smoke_col = smoke_col,
    exclude_levels = exclude_levels,
    keep_levels = keep_levels,
    n_before = info$n_before,
    n_after = length(keep),
    n_dropped = info$n_drop,
    dropped_tab = as.list(info$dropped_tab),
    remaining_tab = as.list(info$remaining_tab)
  )
  ctx <- environment_sensitivity_rebuild_design(ctx, config)
  data2 <- ctx$data$imputed %||% ctx$data$cleaned
  drop_cov <- function(x) environment_sensitivity_drop_constant_covs(x, data2)
  if (length(config$glm_environment_quartile$model2_factors)) {
    config$glm_environment_quartile$model2_factors <-
      drop_cov(config$glm_environment_quartile$model2_factors)
  }
  if (length(config$wqs_environment$covariates)) {
    config$wqs_environment$covariates <- drop_cov(config$wqs_environment$covariates)
  }
  if (length(config$bkmr_fit$covariates)) {
    config$bkmr_fit$covariates <- drop_cov(config$bkmr_fit$covariates)
  }
  if (length(config$qgcomp_environment$covariates)) {
    config$qgcomp_environment$covariates <- drop_cov(config$qgcomp_environment$covariates)
  }
  ctx$config <- config
  list(ctx = ctx, config = config, filter = ctx$results$environment_sensitivity_filter)
}

environment_sensitivity_lock_mixture_vocs <- function(ctx, vocs) {
  vocs <- unique(as.character(vocs[nzchar(as.character(vocs))]))
  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (!is.null(data)) vocs <- intersect(vocs, names(data))
  ctx$results$select_vocs_glm <- vocs
  ctx$results$select_vocs_final <- vocs
  ctx$results$select_vocs <- vocs
  ctx$results$select_vocs_wqs <- vocs
  ctx$results$bkmr_select_vocs <- vocs
  ctx$results$glm_environment_zero_voc <- FALSE
  ctx
}

environment_sensitivity_resolve_locked_vocs <- function(main_ctx, config) {
  vocs <- as.character(
    main_ctx$results$select_vocs_final %||%
      main_ctx$results$select_vocs_glm %||%
      main_ctx$results$bkmr_select_vocs %||%
      main_ctx$results$select_vocs_wqs %||%
      character(0)
  )
  vocs <- unique(vocs[nzchar(vocs)])
  if (!length(vocs)) {
    stop("敏感性分析：主分析 checkpoint 中无锁定 VOC（select_vocs_final 为空）", call. = FALSE)
  }
  vocs
}

# 敏感性铁律：GLM 协变量与主分析一致（仅换样本，不换调整集）。
# 优先 ctx$results$glm_voc_covariates，回退 Table_GLM_VOC_Covariates.csv，再回退 Model1/Model2Factors。
environment_sensitivity_resolve_locked_covariates <- function(main_ctx, config) {
  if (isTRUE((config$environment_sensitivity %||% list())$lock_covariates %||% TRUE)) {
    # keep default
  }
  df <- main_ctx$results$glm_voc_covariates
  if (is.null(df) || !nrow(df)) {
    bc <- config$environment_batch %||% list()
    cands <- c(
      file.path(bc$output_base %||% NA_character_, "_shared", "Tables", "Table_GLM_VOC_Covariates.csv"),
      file.path(bc$output_base %||% NA_character_, "_shared", "step16_glm_environment_quartile", "Tables", "Table_GLM_VOC_Covariates.csv")
    )
    for (p in cands[!is.na(cands)]) {
      if (file.exists(p)) {
        df <- tryCatch(
          utils::read.csv(p, stringsAsFactors = FALSE, fileEncoding = "UTF-8"),
          error = function(e) NULL
        )
        if (!is.null(df) && nrow(df)) break
      }
    }
  }
  if (is.null(df) || !nrow(df)) {
    m1 <- unique(as.character(main_ctx$results$Model1Factors %||% character(0)))
    m2 <- unique(as.character(main_ctx$results$Model2Factors %||% character(0)))
    m2 <- unique(c(m1, setdiff(m2, m1)))
    if (!length(m1) || !length(m2)) {
      cli::cli_alert_warning("敏感性：未找到主分析逐 VOC 协变量，回退默认搜索（协变量可能与主分析不一致）")
      return(NULL)
    }
    df <- data.frame(
      VOC = "*", Model1 = paste(m1, collapse = "; "),
      Model2_full = paste(m2, collapse = "; "),
      stringsAsFactors = FALSE
    )
  }
  vcol <- if ("VOC" %in% names(df)) "VOC" else names(df)[1L]
  parse_list <- function(x) {
    x <- as.character(x)[1L]
    if (is.na(x) || !nzchar(x)) return(character(0))
    trimws(strsplit(gsub("[;|]", ";", x), ";")[[1L]])
  }
  out <- list()
  for (r in seq_len(nrow(df))) {
    voc <- trimws(as.character(df[[vcol]][r]))
    m1 <- parse_list(df$Model1[r])
    m2 <- parse_list(if ("Model2_full" %in% names(df)) df$Model2_full[r] else df$Model2[r])
    m2 <- unique(c(m1, setdiff(m2, m1)))
    if (!length(m1) || !length(m2)) next
    out[[voc]] <- list(model1 = m1, model2 = m2)
  }
  if (!length(out)) {
    cli::cli_alert_warning("敏感性：主分析协变量表解析为空，回退默认搜索")
    return(NULL)
  }
  out
}

environment_sensitivity_table_manifest <- function() {
  list(
    list(
      order = 1L, id = "SA1", kind = "GLM",
      pattern = "Table S8.*GLM|Selection of Environmental exposure variables for GLM",
      title = "Table SA1. Selection of Environmental exposure variables for GLM"
    ),
    list(
      order = 2L, id = "SA2", kind = "WQS",
      pattern = "Table S9.*WQS|Associations of WQS",
      title = "Table SA2. Associations of WQS regression index"
    ),
    list(
      order = 3L, id = "SA3", kind = "BKMR",
      pattern = "Table S10.*PIP|PIP values in BKMR",
      title = "Table SA3. PIP values in BKMR model"
    ),
    list(
      order = 4L, id = "SA4", kind = "Qgcomp",
      pattern = "Table S19.*Quantile g-Computation|Quantile g-Computation",
      title = "Table SA4. Associations by Quantile g-Computation"
    )
  )
}

environment_sensitivity_figure_manifest <- function() {
  list(
    list(
      order = 1L, id = "SA1",
      pattern = "Figure_WQS_Weights",
      title = "Figure SA1. WQS model weights"
    ),
    list(
      order = 2L, id = "SA2",
      pattern = "Figure_BKMR_Overall",
      title = "Figure SA2. BKMR overall mixture effect"
    ),
    list(
      order = 3L, id = "SA3",
      pattern = "Figure_BKMR_SingVar",
      title = "Figure SA3. BKMR single-variable effect"
    ),
    list(
      order = 4L, id = "SA4",
      pattern = "Figure_BKMR_DoseResponse",
      title = "Figure SA4. BKMR dose-response"
    ),
    list(
      order = 5L, id = "SA5",
      pattern = "Figure_QGComp_Weights|Figure_QGC",
      title = "Figure SA5. Quantile g-computation weights"
    )
  )
}

environment_sensitivity_safe_stem <- function(title, ext = NULL) {
  stem <- as.character(title)[1L]
  stem <- gsub(":", " -", stem, fixed = TRUE)
  stem <- gsub("[<>:\"/\\\\|?*]", "_", stem)
  stem <- gsub("[[:space:]]+", " ", stem)
  stem <- trimws(stem)
  stem <- sub("\\.+$", "", stem)
  if (is.null(ext) || !nzchar(as.character(ext)[1L])) return(stem)
  paste0(stem, ".", tolower(as.character(ext)[1L]))
}

environment_sensitivity_pick_one <- function(files, prefer_ext = c("xlsx", "csv")) {
  files <- files[file.exists(files)]
  if (!length(files)) return(NA_character_)
  ext <- tolower(tools::file_ext(files))
  for (pe in prefer_ext) {
    hit <- files[ext == pe]
    if (length(hit)) return(hit[[1L]])
  }
  files[[1L]]
}

#' 敏感性汇总收口：表只留一份（xlsx/csv，无 tex）、图只留 pdf/png/tiff/image_information，并编 SA 序号
environment_sensitivity_finalize_outputs <- function(sens_out, disease = "Outcome", tag = "") {
  sens_out <- normalizePath(as.character(sens_out)[1L], winslash = "/", mustWork = FALSE)
  dir_t <- file.path(sens_out, "Tables")
  dir_f <- file.path(sens_out, "Figures")
  dir.create(dir_t, recursive = TRUE, showWarnings = FALSE)
  dir.create(dir_f, recursive = TRUE, showWarnings = FALSE)
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    dir.create(file.path(dir_f, sub), recursive = TRUE, showWarnings = FALSE)
  }

  disease <- as.character(disease)[1L]
  tag <- as.character(tag %||% "")[1L]
  tag_suf <- if (nzchar(tag)) paste0(" (", tag, ")") else ""

  # ── 从表：step 目录收集，每类只留 1 份（优先 xlsx，其次 csv；丢弃 tex / 内部 csv）──
  steps <- list.dirs(sens_out, recursive = FALSE, full.names = TRUE)
  steps <- steps[grepl("step\\d+_", basename(steps))]
  step_tables <- unlist(lapply(steps, function(st) {
    list.files(file.path(st, "Tables"), full.names = TRUE, recursive = FALSE)
  }), use.names = FALSE)
  step_tables <- step_tables[file.exists(step_tables)]
  # 汇总根先清空旧表，避免 tex / 内部审计表残留；保留方法 FDR（SA5–SA8）以免被收口冲掉
  old_tbl <- list.files(dir_t, full.names = TRUE, recursive = FALSE)
  old_tbl <- old_tbl[!grepl(
    "FDR|Table SA[5-8]\\b",
    basename(old_tbl),
    ignore.case = TRUE
  )]
  if (length(old_tbl)) unlink(old_tbl)

  tbl_rows <- list()
  for (spec in environment_sensitivity_table_manifest()) {
    hits <- step_tables[grepl(spec$pattern, basename(step_tables), ignore.case = TRUE)]
    # 排除内部协变量审计
    hits <- hits[!grepl("Table_GLM_VOC_Covariates|covariates\\.csv$", basename(hits), ignore.case = TRUE)]
    # 不要 tex
    hits <- hits[!grepl("\\.tex$", basename(hits), ignore.case = TRUE)]
    src <- environment_sensitivity_pick_one(hits, prefer_ext = c("xlsx", "csv"))
    if (!nzchar(src) || is.na(src)) {
      tbl_rows[[length(tbl_rows) + 1L]] <- data.frame(
        order = spec$order, id = spec$id, kind = spec$kind,
        status = "missing", dest = "", stringsAsFactors = FALSE
      )
      next
    }
    ext <- tolower(tools::file_ext(src))
    title <- paste0(spec$title, " with ", disease, tag_suf)
    dest <- file.path(dir_t, environment_sensitivity_safe_stem(title, ext))
    file.copy(src, dest, overwrite = TRUE)
    tbl_rows[[length(tbl_rows) + 1L]] <- data.frame(
      order = spec$order, id = spec$id, kind = spec$kind,
      status = "ok", dest = dest, stringsAsFactors = FALSE
    )
  }
  tbl_manifest <- if (length(tbl_rows)) do.call(rbind, tbl_rows) else data.frame()

  # ── 图：从 step 收 PDF → 先放到 Figures 根（供 export_pub_figures）→ 再进四目录 ──
  step_figs <- unlist(lapply(steps, function(st) {
    list.files(
      file.path(st, "Figures"), full.names = TRUE, recursive = FALSE,
      pattern = "\\.pdf$", ignore.case = TRUE
    )
  }), use.names = FALSE)
  existing_pdf <- unique(c(
    step_figs,
    list.files(file.path(dir_f, "pdf"), full.names = TRUE, pattern = "\\.pdf$", ignore.case = TRUE),
    list.files(dir_f, full.names = TRUE, recursive = FALSE, pattern = "\\.pdf$", ignore.case = TRUE)
  ))
  existing_pdf <- existing_pdf[file.exists(existing_pdf)]

  # 清空根散落 + 旧格式子目录，避免双份
  loose <- list.files(dir_f, full.names = TRUE, recursive = FALSE)
  loose <- loose[file.exists(loose) & !dir.exists(loose)]
  if (length(loose)) unlink(loose)
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    old <- list.files(file.path(dir_f, sub), full.names = TRUE)
    if (length(old)) unlink(old, recursive = TRUE, force = TRUE)
    dir.create(file.path(dir_f, sub), recursive = TRUE, showWarnings = FALSE)
  }

  fig_rows <- list()
  root_pdfs <- character(0)
  for (spec in environment_sensitivity_figure_manifest()) {
    hits <- existing_pdf[grepl(spec$pattern, basename(existing_pdf), ignore.case = TRUE)]
    src <- if (length(hits)) hits[[1L]] else NA_character_
    title <- paste0(spec$title, " on ", disease, tag_suf)
    stem <- environment_sensitivity_safe_stem(title)
    dest_root <- file.path(dir_f, paste0(stem, ".pdf"))
    if (!nzchar(src) || is.na(src) || !file.exists(src)) {
      fig_rows[[length(fig_rows) + 1L]] <- data.frame(
        order = spec$order, id = spec$id, status = "missing",
        stem = stem, stringsAsFactors = FALSE
      )
      next
    }
    file.copy(src, dest_root, overwrite = TRUE)
    root_pdfs <- c(root_pdfs, dest_root)
    fig_rows[[length(fig_rows) + 1L]] <- data.frame(
      order = spec$order, id = spec$id, status = "ok",
      stem = stem, stringsAsFactors = FALSE
    )
  }
  fig_manifest <- if (length(fig_rows)) do.call(rbind, fig_rows) else data.frame()

  if (length(root_pdfs) && exists("export_pub_figures", mode = "function")) {
    tryCatch(
      export_pub_figures(
        dir_f,
        meta = list(
          outcome = disease,
          exposure = "Environmental Toxicants",
          database = "NHANES",
          study_type = "sensitivity"
        ),
        config = list(pub_figures = list(enable = TRUE)),
        purge = TRUE
      ),
      error = function(e) cli::cli_alert_warning("敏感性图格式导出失败: {e$message}")
    )
  } else if (length(root_pdfs)) {
    # 无 export 工具时至少放进 pdf/
    for (fp in root_pdfs) {
      file.copy(fp, file.path(dir_f, "pdf", basename(fp)), overwrite = TRUE)
      unlink(fp)
    }
  }

  # 根目录不应再留散落 PDF
  leftover <- list.files(dir_f, full.names = TRUE, recursive = FALSE, pattern = "\\.(pdf|png)$", ignore.case = TRUE)
  leftover <- leftover[file.exists(leftover) & !dir.exists(leftover)]
  if (length(leftover)) unlink(leftover)

  man_path <- file.path(sens_out, "sensitivity_manifest.csv")
  man <- rbind(
    if (nrow(tbl_manifest)) {
      data.frame(type = "Table", tbl_manifest, stringsAsFactors = FALSE)
    },
    if (nrow(fig_manifest)) {
      data.frame(
        type = "Figure",
        order = fig_manifest$order,
        id = fig_manifest$id,
        kind = NA_character_,
        status = fig_manifest$status,
        dest = fig_manifest$stem,
        stringsAsFactors = FALSE
      )
    }
  )
  if (!is.null(man) && nrow(man)) {
    utils::write.csv(man, man_path, row.names = FALSE, fileEncoding = "UTF-8")
  }

  n_t <- if (nrow(tbl_manifest)) sum(tbl_manifest$status == "ok") else 0L
  n_f <- if (nrow(fig_manifest)) sum(fig_manifest$status == "ok") else 0L
  cli::cli_alert_success(
    "敏感性汇总收口: Tables {n_t} / Figures {n_f}（无 tex；图仅在 pdf/png/tiff/image_information）"
  )
  list(tables = tbl_manifest, figures = fig_manifest, manifest_path = man_path,
       n_tables = n_t, n_figures = n_f)
}

environment_sensitivity_copy_pub_outputs <- function(sens_out, disease = "Outcome", tag = "") {
  environment_sensitivity_finalize_outputs(sens_out, disease = disease, tag = tag)
}

environment_sensitivity_write_readme <- function(sens_out, filter_info, locked_vocs, disease,
                                                 table_manifest = NULL, figure_manifest = NULL) {
  title <- if (environment_sensitivity_is_never_only(
    filter_info$keep_levels, filter_info$exclude_levels
  )) {
    "# 敏感性分析：仅保留从不吸烟（Never）"
  } else {
    paste0("# 敏感性分析：剔除 ", paste(filter_info$exclude_levels, collapse = "/"))
  }
  filter_txt <- if (length(filter_info$keep_levels)) {
    paste0(filter_info$smoke_col, " 仅保留 ",
           paste(filter_info$keep_levels, collapse = ", "))
  } else {
    paste0(filter_info$smoke_col, " 剔除 ",
           paste(filter_info$exclude_levels, collapse = ", "))
  }
  lines <- c(
    title,
    "",
    paste0("- 疾病：", disease),
    paste0("- 筛选：", filter_txt),
    paste0("- 人数：剔除前 ", filter_info$n_before,
           " / 剔除后 ", filter_info$n_after,
           " / 剔除 ", filter_info$n_dropped),
    paste0("- 混合物 VOC 锁定主分析：", paste(locked_vocs, collapse = ", ")),
    "- 重跑方法：GLM（四分位）、WQS、BKMR、Quantile g-computation（Qgcomp/QQC）",
    "- GLM 表展示主分析锁定 VOC（含不显著）；WQS/BKMR/Qgcomp 锁定同一 VOC 集。",
    "- 汇总 Tables/：SA1–SA4 主敏感性表 + SA5–SA8 方法 FDR；Figures/：SA1–SA5 主图 + SA6–SA10 FDR 图（含 BKMR dose-response；pdf/png/tiff/image_information）。",
    "- 全人群方法 FDR 表 S20–S23；图 Figure 9–12 复用主文 WQS/BKMR/QGC 图面（非自制森林图）。",
    ""
  )
  if (!is.null(table_manifest) && nrow(table_manifest)) {
    lines <- c(lines, "## 表顺序", "")
    for (i in seq_len(nrow(table_manifest))) {
      lines <- c(lines, paste0(
        "- ", table_manifest$id[i], " (", table_manifest$kind[i], "): ",
        table_manifest$status[i]
      ))
    }
    lines <- c(lines, "")
  }
  if (!is.null(figure_manifest) && nrow(figure_manifest)) {
    lines <- c(lines, "## 图顺序", "")
    for (i in seq_len(nrow(figure_manifest))) {
      lines <- c(lines, paste0(
        "- Figure ", figure_manifest$id[i], ": ", figure_manifest$status[i]
      ))
    }
    lines <- c(lines, "")
  }
  writeLines(lines, file.path(sens_out, "README.md"), useBytes = TRUE)
}

environment_run_exclude_smoke_sensitivity <- function(root, config,
                                                      pipeline_shared = NULL,
                                                      pipeline_tail = NULL) {
  sens <- environment_sensitivity_cfg(config)
  if (isFALSE(sens$enable %||% TRUE)) {
    cli::cli_alert_info("environment_sensitivity$enable = FALSE，跳过剔除吸烟敏感性")
    return(invisible(NULL))
  }
  root <- normalizePath(as.character(root)[1L], winslash = "/", mustWork = TRUE)
  ck_dir <- environment_batch_shared_ck_dir(config)
  glm_ck <- file.path(ck_dir, "lasso_environment_voc.rds")
  if (!file.exists(glm_ck)) glm_ck <- file.path(ck_dir, "glm_environment_quartile.rds")
  if (!file.exists(glm_ck)) {
    stop("敏感性分析：未找到 LASSO/GLM checkpoint: ", ck_dir, call. = FALSE)
  }
  main_glm <- tryCatch(readRDS(file.path(ck_dir, "glm_environment_quartile.rds")), error = function(e) NULL)
  main_ctx_lock <- if (!is.null(main_glm) && !is.null(main_glm$ctx)) main_glm$ctx else {
    environment_batch_load_checkpoint_ctx(ck_dir, "glm_environment_quartile")
  }
  locked_vocs <- environment_sensitivity_resolve_locked_vocs(main_ctx_lock, config)

  obj <- tryCatch(readRDS(glm_ck), error = function(e) NULL)
  if (is.null(obj) || is.null(obj$ctx)) {
    stop("敏感性分析：无法读取 ", glm_ck, call. = FALSE)
  }
  ctx <- obj$ctx

  sens_out <- environment_sensitivity_output_dir(config)
  glm_only <- isTRUE(sens$glm_only %||% FALSE)
  if (dir.exists(sens_out) && !glm_only) {
    unlink(sens_out, recursive = TRUE, force = TRUE)
    cli::cli_alert_warning("已清空旧敏感性目录: {.file {sens_out}}")
  } else if (glm_only && dir.exists(sens_out)) {
    # 仅重跑 GLM：清掉旧 GLM step / Tables 中的 S8，保留 WQS/BKMR/Qgcomp
    old_glm <- list.files(sens_out, pattern = "step\\d+_glm_environment", full.names = TRUE)
    if (length(old_glm)) unlink(old_glm, recursive = TRUE, force = TRUE)
    old_s8 <- list.files(
      file.path(sens_out, "Tables"),
      pattern = "Table S8.*GLM",
      full.names = TRUE,
      ignore.case = TRUE
    )
    if (length(old_s8)) unlink(old_s8)
    cli::cli_alert_info("glm_only：保留既有 WQS/BKMR/Qgcomp，仅刷新 GLM")
  }
  sens_ck  <- file.path(sens_out, "checkpoints")
  dir.create(sens_out, recursive = TRUE, showWarnings = FALSE)
  dir.create(sens_ck, recursive = TRUE, showWarnings = FALSE)

  cfg <- config
  orch <- (cfg$environment_batch %||% list())$orchestrator %||% list()
  bkmr_iter <- as.integer(
    sens$bkmr_iter %||% orch$bkmr_iter_final %||% cfg$bkmr_fit$iter %||% 1000L
  )[1L]
  if (!is.finite(bkmr_iter) || bkmr_iter < 1L) bkmr_iter <- 1000L
  cfg$bkmr_fit$auto_iter <- FALSE
  cfg$bkmr_fit$iter <- bkmr_iter
  disease <- as.character(cfg$project$disease %||% "Outcome")[1L]
  tag <- environment_sensitivity_pub_tag(
    sens$keep_levels, sens$exclude_levels
  )
  # 仅敏感性：GLM 表展示全部锁定 VOC（含不显著）；主流程默认 report_all_vocs=FALSE
  cfg$glm_environment_quartile$report_all_vocs <- TRUE
  cfg$glm_environment_quartile$match_lasso_vocs <- FALSE
  cfg$glm_environment_quartile$require_lasso_passed <- FALSE
  cfg$glm_environment_quartile$select_vocs <- locked_vocs
  # 审稿口径：敏感性 GLM 协变量与主分析完全一致（仅换样本）；锁主分析逐 VOC Model1/Model2
  locked_covs <- environment_sensitivity_resolve_locked_covariates(main_ctx_lock, config)
  if (!is.null(locked_covs)) {
    cfg$glm_environment_quartile$locked_covariates <- locked_covs
    cfg$glm_environment_quartile$covariate_search <- FALSE
    n_star <- if (!is.null(locked_covs[["*"]])) "（含兜底 * 规则）" else ""
    cli::cli_alert_info(
      "敏感性锁协变量{n_star}: {paste(vapply(locked_vocs, function(v) paste0(v, '=M1[', paste(locked_covs[[v]]$model1 %||% character(0), collapse = ','), ']'), ''), collapse = ' | ')}"
    )
  }
  cfg$glm_environment_quartile$table_filename <-
    paste0("Table S8. Selection of Environmental exposure variables for GLM (", tag, ").xlsx")
  cfg$glm_environment_quartile$table_title <-
    paste0("Table S8. Selection of Environmental exposure variables for GLM (", tag, ")")
  cfg$wqs_environment$table_filename <-
    paste0("Table S9. Associations of WQS regression index with ", disease, " (", tag, ").xlsx")
  cfg$wqs_environment$table_title <-
    paste0("Table S9. Associations of WQS regression index with ", disease, " (", tag, ")")
  cfg$bkmr_analysis$table_pip_filename <-
    paste0("Table S10. PIP values in BKMR model in ", disease, " (", tag, ").xlsx")
  cfg$bkmr_analysis$table_pip_title <-
    paste0("Table S10. PIP values in BKMR model in ", disease, " (", tag, ")")
  cfg$qgcomp_environment$table_filename <-
    paste0("Table S19. Associations of Environmental Toxicants with ", disease,
           " by using Quantile g-Computation (", tag, ").csv")
  cfg$qgcomp_environment$table_title <-
    paste0("Table S19. Associations of Environmental Toxicants with ", disease,
           " by using Quantile g-Computation (", tag, ")")

  applied <- environment_sensitivity_apply_filter(ctx, cfg)
  ctx <- applied$ctx
  cfg <- applied$config
  filt <- applied$filter
  # GLM 候选锁定主分析 VOC，敏感性表与主文同一套暴露对照
  ctx <- environment_sensitivity_lock_mixture_vocs(ctx, locked_vocs)
  ctx$results$select_vocs_lasso <- locked_vocs

  utils::write.csv(
    data.frame(
      smoke_col = filt$smoke_col,
      keep_levels = paste(filt$keep_levels, collapse = "|"),
      exclude_levels = paste(filt$exclude_levels, collapse = "|"),
      n_before = filt$n_before,
      n_after = filt$n_after,
      n_dropped = filt$n_dropped,
      locked_vocs = paste(locked_vocs, collapse = "|"),
      stringsAsFactors = FALSE
    ),
    file.path(sens_out, "sample_filter.csv"),
    row.names = FALSE,
    fileEncoding = "UTF-8"
  )

  cfg$project$output_dir <- sens_out
  cfg$project$root <- cfg$project$root %||% root
  if (is.null(cfg$pub)) cfg$pub <- list()
  cfg$pub$renumber <- FALSE
  ctx$config <- cfg
  ctx$root_output_dir <- sens_out
  ctx$log$block_step_counter <- 0L

  glm_only <- isTRUE(sens$glm_only %||% FALSE)

  pl_glm <- list(
    name = "env_sens_glm",
    blocks = "glm_environment_quartile",
    render_tables_after = "glm_environment_quartile",
    render_figures_after = character(0),
    dual_db = list(enable = FALSE),
    checkpoint = list(enable = TRUE, dir = sens_ck)
  )
  cli::cli_h1("敏感性分析 GLM（{tag}；report_all_vocs=TRUE）")
  run_pipeline(root, config = cfg, pipeline = pl_glm, run_opts = list(initial_ctx = ctx))

  if (!glm_only) {
    ctx2 <- environment_batch_load_checkpoint_ctx(sens_ck, "glm_environment_quartile")
    ctx2 <- environment_sensitivity_lock_mixture_vocs(ctx2, locked_vocs)
    ctx2$config <- cfg
    ctx2$root_output_dir <- sens_out
    cli::cli_alert_info(
      "混合物 VOC 锁定为主分析: {paste(locked_vocs, collapse = ', ')}"
    )

    pl_mix <- list(
      name = "env_sens_mixture",
      blocks = c("wqs_environment", "bkmr_fit", "bkmr_analysis", "qgcomp_environment"),
      render_tables_after = c("wqs_environment", "bkmr_analysis", "qgcomp_environment"),
      render_figures_after = c("wqs_environment", "bkmr_analysis", "qgcomp_environment"),
      dual_db = list(enable = FALSE),
      checkpoint = list(enable = TRUE, dir = sens_ck)
    )
    cli::cli_h1("敏感性分析 WQS / BKMR / Qgcomp（{tag}）")
    run_pipeline(root, config = cfg, pipeline = pl_mix, run_opts = list(initial_ctx = ctx2))
  } else {
    cli::cli_alert_info("glm_only=TRUE：跳过 WQS/BKMR/Qgcomp，仅刷新 GLM 表")
  }

  # 收口前 source 发表图导出，便于重建 png/tiff/image_information
  pub_fig <- file.path(root, "R/pub_figure_export.R")
  if (file.exists(pub_fig) && !exists("export_pub_figures", mode = "function")) {
    tryCatch(source(pub_fig, local = FALSE), error = function(e) NULL)
  }
  copied <- environment_sensitivity_copy_pub_outputs(
    sens_out, disease = disease, tag = tag
  )
  fdr_sa <- tryCatch(
    environment_build_sensitivity_method_fdr_tables(
      config = config,
      result_root = dirname(sens_out),
      project_root = root
    ),
    error = function(e) {
      cli::cli_alert_warning("敏感性方法 FDR 失败: {e$message}")
      NULL
    }
  )
  environment_sensitivity_write_readme(
    sens_out, filt, locked_vocs, disease,
    table_manifest = copied$tables,
    figure_manifest = copied$figures
  )
  cli::cli_alert_success(
    "敏感性分析完成 -> {.file {sens_out}}（Tables {copied$n_tables} / Figures {copied$n_figures}）"
  )
  invisible(list(
    output_dir = sens_out,
    filter = filt,
    locked_vocs = locked_vocs,
    copied = copied,
    fdr = fdr_sa
  ))
}

# ── 方法 FDR：GLM / WQS / BKMR / QGC（全人群 + 敏感性）─────────────────────

environment_fdr_format_p <- function(p) {
  p <- suppressWarnings(as.numeric(p))
  vapply(p, function(x) {
    if (!is.finite(x)) return("")
    if (x < 0.001) return("<0.001")
    formatC(x, format = "f", digits = 3)
  }, character(1L))
}

environment_fdr_parse_p_text <- function(x) {
  x <- trimws(as.character(x %||% ""))
  if (!nzchar(x)) return(NA_real_)
  if (grepl("^ref$", x, ignore.case = TRUE)) return(NA_real_)
  x2 <- sub("^P\\s*", "", x, ignore.case = TRUE)
  x2 <- trimws(x2)
  if (grepl("^<\\s*0\\.001", x2, ignore.case = TRUE)) return(5e-4)
  if (grepl("^<", x2)) {
    v <- suppressWarnings(as.numeric(sub("^<\\s*", "", x2)))
    if (is.finite(v)) return(v)
  }
  suppressWarnings(as.numeric(x2))
}

environment_fdr_label_map <- function(config) {
  bl <- config$environment_voc_clinical_gate %||% list()
  if (exists("environment_resolve_label_map", mode = "function")) {
    return(environment_resolve_label_map(config, bl$label_mapping))
  }
  NULL
}

environment_fdr_display <- function(codes, config) {
  codes <- as.character(codes)
  label_map <- environment_fdr_label_map(config)
  out <- if (exists("environment_display_label", mode = "function")) {
    environment_display_label(codes, label_map)
  } else {
    codes
  }
  # label_map 子集可能带上 NA names，data.frame 会报 row names contain missing values
  unname(as.character(out))
}

environment_fdr_load_ctx <- function(ck_dir, prefer_block) {
  ck_dir <- normalizePath(as.character(ck_dir)[1L], winslash = "/", mustWork = FALSE)
  fp <- file.path(ck_dir, paste0(prefer_block, ".rds"))
  if (file.exists(fp)) {
    obj <- tryCatch(readRDS(fp), error = function(e) NULL)
    if (!is.null(obj$ctx)) return(obj$ctx)
  }
  if (exists("environment_batch_load_checkpoint_ctx", mode = "function")) {
    return(environment_batch_load_checkpoint_ctx(ck_dir, prefer_block))
  }
  stop("无法加载 checkpoint: ", prefer_block, " @ ", ck_dir, call. = FALSE)
}

environment_fdr_write_table <- function(out_df, tables_dir, title, footnote,
                                        config = NULL, root_for_render = NULL,
                                        header_row1 = NULL, header_row2 = NULL) {
  dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
  out_df <- as.data.frame(out_df, stringsAsFactors = FALSE, check.names = FALSE)
  # 允许 extract 通过 attribute 传入双行表头（对齐 Table S8）
  if (is.null(header_row1)) header_row1 <- attr(out_df, "header_row1")
  if (is.null(header_row2)) header_row2 <- attr(out_df, "header_row2")
  for (j in seq_along(out_df)) {
    if (is.character(out_df[[j]])) {
      out_df[[j]] <- gsub("_", " ", out_df[[j]], fixed = TRUE)
    }
  }
  names(out_df) <- gsub("_", " ", names(out_df), fixed = TRUE)
  if (!is.null(header_row1)) header_row1 <- gsub("_", " ", as.character(header_row1), fixed = TRUE)
  if (!is.null(header_row2)) header_row2 <- gsub("_", " ", as.character(header_row2), fixed = TRUE)

  title <- as.character(title)[1L]
  safe_title <- gsub(":", " -", title, fixed = TRUE)
  safe_title <- gsub("[<>\"/\\\\|?*]", "_", safe_title)
  safe_title <- gsub("[[:space:]]+", " ", safe_title)
  safe_title <- trimws(safe_title)
  xlsx_path <- file.path(tables_dir, paste0(safe_title, ".xlsx"))

  old_db <- getOption("pipeline.database_name", NULL)
  on.exit(options(pipeline.database_name = old_db), add = TRUE)
  options(pipeline.database_name = "NHANES")

  title_sci <- title
  if (exists(".inject_db_into_pub_label", mode = "function")) {
    title_sci <- .inject_db_into_pub_label(title_sci, sanitize_for_file = FALSE)
  } else if (!grepl("-NHANES", title_sci, fixed = TRUE)) {
    title_sci <- sub("^(Table S(A)?[0-9]+)", "\\1-NHANES", title_sci)
  }
  if (exists("pub_caption_strip_parentheses", mode = "function")) {
    title_sci <- pub_caption_strip_parentheses(title_sci)
  }
  title_sci <- gsub("_", " ", title_sci, fixed = TRUE)

  foot <- as.character(footnote %||% "")
  foot <- foot[nzchar(trimws(foot))]
  if (length(foot)) foot <- gsub("_", " ", foot, fixed = TRUE)

  use_dbl <- !is.null(header_row1) && !is.null(header_row2) &&
    length(header_row1) == ncol(out_df) && length(header_row2) == ncol(out_df)

  wrote <- FALSE
  if (use_dbl && exists(".sci_xlsx_double_header_booktabs", mode = "function")) {
    tryCatch({
      .sci_xlsx_double_header_booktabs(
        filepath = xlsx_path,
        title = title_sci,
        df_body = out_df,
        h1 = header_row1,
        h2 = header_row2,
        sheet = "Table",
        footnotes = if (length(foot)) foot else NULL
      )
      wrote <- file.exists(xlsx_path)
    }, error = function(e) {
      cli::cli_alert_warning("双行表头 SCI 失败，回退单行: {e$message}")
    })
  }
  if (!wrote && exists("sci_xlsx_single_header_booktabs", mode = "function")) {
    tryCatch({
      sci_xlsx_single_header_booktabs(
        filepath = xlsx_path,
        title = title_sci,
        df_body = out_df,
        sheet = "Table",
        footnotes = if (length(foot)) foot else NULL,
        blank_na_cells = TRUE
      )
      wrote <- file.exists(xlsx_path)
    }, error = function(e) {
      cli::cli_alert_warning("sci_xlsx_single_header_booktabs 失败: {e$message}")
    })
  }

  if (!wrote &&
      exists("export_sci_table", mode = "function") &&
      exists("render_queued_tables", mode = "function")) {
    if (exists(".table_queue_env")) .table_queue_env$items <- list()
    tryCatch({
      export_sci_table(
        out_df, xlsx_path, title = title,
        table_footnotes = footnote,
        header_row1 = if (use_dbl) header_row1 else NULL,
        header_row2 = if (use_dbl) header_row2 else NULL
      )
      queued <- .table_queue_env$items %||% list()
      sci_path <- if (length(queued)) queued[[length(queued)]]$filepath else xlsx_path
      render_queued_tables(list(
        root_output_dir = root_for_render %||% dirname(tables_dir),
        output_dir_tables = tables_dir,
        config = config %||% list()
      ))
      if (is.character(sci_path) && nzchar(sci_path) && file.exists(sci_path)) {
        if (!identical(
          normalizePath(sci_path, winslash = "/", mustWork = FALSE),
          normalizePath(xlsx_path, winslash = "/", mustWork = FALSE)
        )) {
          file.copy(sci_path, xlsx_path, overwrite = TRUE)
          unlink(sci_path)
        }
        wrote <- file.exists(xlsx_path)
      }
    }, error = function(e) {
      cli::cli_alert_warning("SCI 队列导出失败: {e$message}")
    })
  }

  if (!wrote) stop("无法写出文献级 FDR 表: ", xlsx_path, call. = FALSE)

  junk <- list.files(
    tables_dir,
    pattern = "UnknownDB.*FDR|FDR.*UnknownDB",
    full.names = TRUE,
    ignore.case = TRUE
  )
  id_token <- sub("^((Table S(A)?[0-9]+)).*", "\\1", safe_title)
  if (nzchar(id_token)) {
    junk <- c(junk, list.files(
      tables_dir,
      pattern = paste0("^", gsub("([.()\\[\\]])", "\\\\\\1", id_token), "-NHANES\\."),
      full.names = TRUE,
      ignore.case = TRUE
    ))
  }
  junk <- unique(junk[file.exists(junk)])
  junk <- junk[
    normalizePath(junk, winslash = "/", mustWork = FALSE) !=
      normalizePath(xlsx_path, winslash = "/", mustWork = FALSE)
  ]
  if (length(junk)) unlink(junk)
  cli::cli_alert_success("SCI FDR 表: {.file {basename(xlsx_path)}}")
  xlsx_path
}

# GLM：Crude / Model1 / Model2 连续暴露均做 BH-FDR（各模型内跨 VOC 校正）
environment_fdr_extract_glm <- function(ctx, config, method, alpha) {
  cov <- ctx$results$glm_voc_covariates
  tab <- ctx$results$glm_environment_table
  rows <- list()

  .pull_cont <- function(code) {
    out <- list(
      or_c = "", ci_c = "", p_c = NA_real_,
      or_1 = "", ci_1 = "", p_1 = NA_real_,
      or_2 = "", ci_2 = "", p_2 = NA_real_
    )
    if (!is.null(cov) && is.data.frame(cov) && nrow(cov)) {
      i <- which(as.character(cov$VOC) == code)
      if (!length(i) && !is.null(rownames(cov))) i <- which(rownames(cov) == code)
      if (length(i)) {
        i <- i[1L]
        out$p_c <- suppressWarnings(as.numeric(cov$p_crude[i]))
        out$p_1 <- suppressWarnings(as.numeric(cov$p_model1[i]))
        out$p_2 <- suppressWarnings(as.numeric(cov$p_model2[i]))
      }
    }
    if (!is.null(tab) && is.data.frame(tab)) {
      x1 <- trimws(as.character(tab$X1))
      hit <- which(x1 == paste0(code, " continuous"))
      if (length(hit)) {
        j <- hit[1L]
        out$or_c <- as.character(tab$X4[j] %||% "")
        out$ci_c <- as.character(tab$X5[j] %||% "")
        out$or_1 <- as.character(tab$X7[j] %||% "")
        out$ci_1 <- as.character(tab$X8[j] %||% "")
        out$or_2 <- as.character(tab$X10[j] %||% "")
        out$ci_2 <- as.character(tab$X11[j] %||% "")
        if (!is.finite(out$p_c)) out$p_c <- environment_fdr_parse_p_text(tab$X6[j])
        if (!is.finite(out$p_1)) out$p_1 <- environment_fdr_parse_p_text(tab$X9[j])
        if (!is.finite(out$p_2)) out$p_2 <- environment_fdr_parse_p_text(tab$X12[j])
      }
    }
    out
  }

  codes <- character(0)
  if (!is.null(cov) && is.data.frame(cov) && nrow(cov)) {
    codes <- unique(as.character(cov$VOC))
  } else if (!is.null(tab) && is.data.frame(tab)) {
    x1 <- trimws(as.character(tab$X1))
    codes <- unique(sub(" continuous$", "", x1[grepl(" continuous$", x1)]))
  }
  codes <- codes[nzchar(codes)]
  if (!length(codes)) return(NULL)

  for (code in codes) {
    v <- .pull_cont(code)
    rows[[length(rows) + 1L]] <- data.frame(
      Code = code,
      or_c = v$or_c, ci_c = v$ci_c, p_c = v$p_c,
      or_1 = v$or_1, ci_1 = v$ci_1, p_1 = v$p_1,
      or_2 = v$or_2, ci_2 = v$ci_2, p_2 = v$p_2,
      stringsAsFactors = FALSE
    )
  }
  df <- do.call(rbind, rows)
  # 各模型内跨 VOC 做 BH-FDR（不跨模型混校）
  df$fdr_c <- stats::p.adjust(df$p_c, method = method)
  df$fdr_1 <- stats::p.adjust(df$p_1, method = method)
  df$fdr_2 <- stats::p.adjust(df$p_2, method = method)

  out <- data.frame(
    Exposure = environment_fdr_display(df$Code, config),
    Code = df$Code,
    c_or = df$or_c,
    c_ci = df$ci_c,
    c_p = environment_fdr_format_p(df$p_c),
    c_fdr = environment_fdr_format_p(df$fdr_c),
    m1_or = df$or_1,
    m1_ci = df$ci_1,
    m1_p = environment_fdr_format_p(df$p_1),
    m1_fdr = environment_fdr_format_p(df$fdr_1),
    m2_or = df$or_2,
    m2_ci = df$ci_2,
    m2_p = environment_fdr_format_p(df$p_2),
    m2_fdr = environment_fdr_format_p(df$fdr_2),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  h1 <- c(
    "", "",
    "Crude Model", "", "", "",
    "Model1", "", "", "",
    "Model2", "", "", ""
  )
  h2 <- c(
    "Exposure", "Code",
    "OR", "95%CI", "P-value", "P FDR (BH)",
    "OR", "95%CI", "P-value", "P FDR (BH)",
    "OR", "95%CI", "P-value", "P FDR (BH)"
  )
  colnames(out) <- h2
  attr(out, "header_row1") <- h1
  attr(out, "header_row2") <- h2
  out
}

environment_fdr_extract_wqs <- function(ctx, config, method, alpha) {
  or_tab <- ctx$results$wqs_or_table
  if (is.null(or_tab) || !nrow(or_tab)) return(NULL)
  var_col <- names(or_tab)[1L]
  p_col <- grep("Wald|P\\(", names(or_tab), value = TRUE)[1L]
  if (!nzchar(p_col %||% "")) p_col <- names(or_tab)[min(4L, ncol(or_tab))]
  or_col <- grep("adj", names(or_tab), value = TRUE)[1L]
  if (!nzchar(or_col %||% "")) or_col <- names(or_tab)[min(3L, ncol(or_tab))]
  is_wqs <- grepl("wqs|WQS", as.character(or_tab[[var_col]]), ignore.case = TRUE)
  if (!any(is_wqs)) is_wqs <- seq_len(nrow(or_tab)) == 1L
  sub <- or_tab[is_wqs, , drop = FALSE]
  p_raw <- vapply(as.character(sub[[p_col]]), environment_fdr_parse_p_text, numeric(1L))
  p_fdr <- stats::p.adjust(p_raw, method = method)
  or_ci <- as.character(sub[[or_col]])
  or_v <- trimws(sub("\\s*\\(.*$", "", or_ci))
  ci_v <- ifelse(
    grepl("\\(", or_ci),
    paste0("(", trimws(sub("^[^\\(]*\\(([^\\)]*)\\).*$", "\\1", or_ci)), ")"),
    ""
  )
  data.frame(
    Exposure = as.character(sub[[var_col]]),
    Code = "WQS",
    OR = or_v,
    `95% CI` = ci_v,
    P = environment_fdr_format_p(p_raw),
    `P FDR (BH)` = environment_fdr_format_p(p_fdr),
    `P < 0.05` = ifelse(is.finite(p_raw) & p_raw < alpha, "Yes", "No"),
    `FDR < 0.05` = ifelse(is.finite(p_fdr) & p_fdr < alpha, "Yes", "No"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

environment_fdr_extract_bkmr <- function(ctx, config, method, alpha) {
  pip <- ctx$results$bkmr_pip_table
  if (is.null(pip) || !nrow(pip)) return(NULL)
  var <- as.character(pip$variable)
  pip_v <- suppressWarnings(as.numeric(pip$PIP))
  # 审稿口径（PIP 为贝叶斯包含概率，非频率派 P 值）：不再把 (1-PIP) 喂 BH 冒充 FDR；
  # 改为描述性 PIP 表，按常用阈值 PIP>0.5 标注主要变量。
  pip_threshold <- suppressWarnings(as.numeric(
    (config$bkmr_analysis %||% list())$pip_threshold[1L] %||%
      (config$environment_fdr %||% list())$pip_threshold[1L] %||% 0.5
  ))
  if (!is.finite(pip_threshold)) pip_threshold <- 0.5
  data.frame(
    Exposure = environment_fdr_display(var, config),
    Code = var,
    PIP = formatC(pip_v, format = "f", digits = 3),
    `PIP > 0.5` = ifelse(is.finite(pip_v) & pip_v > pip_threshold, "Yes", "No"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

environment_fdr_extract_qgc <- function(ctx, config, method, alpha) {
  coef_tab <- ctx$results$qgcomp_coef_table
  fit <- ctx$results$qgcomp_fit
  rows <- list()
  if (!is.null(coef_tab) && nrow(coef_tab)) {
    rn <- rownames(coef_tab)
    if (is.null(rn) || !length(rn)) rn <- as.character(seq_len(nrow(coef_tab)))
    pcol <- grep("Pr\\(", names(coef_tab), value = TRUE)[1L]
    if (!nzchar(pcol %||% "")) pcol <- names(coef_tab)[ncol(coef_tab)]
    for (i in seq_len(nrow(coef_tab))) {
      term <- rn[i]
      if (grepl("intercept", term, ignore.case = TRUE)) next
      est <- suppressWarnings(as.numeric(coef_tab$Estimate[i]))
      p <- suppressWarnings(as.numeric(coef_tab[[pcol]][i]))
      se <- suppressWarnings(as.numeric(coef_tab[["Std. Error"]][i]))
      lo <- hi <- NA_real_
      if (is.finite(est) && is.finite(se)) {
        lo <- exp(est - 1.96 * se)
        hi <- exp(est + 1.96 * se)
      }
      rows[[length(rows) + 1L]] <- data.frame(
        Code = term,
        OR = if (is.finite(est)) formatC(exp(est), format = "f", digits = 2) else "",
        `95% CI` = if (is.finite(lo) && is.finite(hi)) {
          paste0("(", formatC(lo, format = "f", digits = 2), ",",
                 formatC(hi, format = "f", digits = 2), ")")
        } else "",
        P = p,
        check.names = FALSE, stringsAsFactors = FALSE
      )
    }
  }
  if (!is.null(fit)) {
    psi <- suppressWarnings(as.numeric(fit$psi)[1L])
    p_psi <- NA_real_
    pv <- suppressWarnings(as.numeric(fit$pval))
    if (length(pv) >= 2L) p_psi <- pv[2L] else if (length(pv) == 1L) p_psi <- pv[1L]
    se_psi <- if (!is.null(fit$var.psi)) sqrt(suppressWarnings(as.numeric(fit$var.psi)[1L])) else NA_real_
    lo <- hi <- NA_real_
    if (is.finite(psi) && is.finite(se_psi)) {
      lo <- exp(psi - 1.96 * se_psi)
      hi <- exp(psi + 1.96 * se_psi)
    }
    rows[[length(rows) + 1L]] <- data.frame(
      Code = "psi (overall mixture)",
      OR = if (is.finite(psi)) formatC(exp(psi), format = "f", digits = 2) else "",
      `95% CI` = if (is.finite(lo) && is.finite(hi)) {
        paste0("(", formatC(lo, format = "f", digits = 2), ",",
               formatC(hi, format = "f", digits = 2), ")")
      } else "",
      P = p_psi,
      check.names = FALSE, stringsAsFactors = FALSE
    )
  }
  if (!length(rows)) return(NULL)
  df <- do.call(rbind, rows)
  df$P_FDR <- stats::p.adjust(df$P, method = method)
  disp <- ifelse(
    grepl("^psi", df$Code, ignore.case = TRUE),
    df$Code,
    environment_fdr_display(df$Code, config)
  )
  data.frame(
    Exposure = disp,
    Code = df$Code,
    OR = df$OR,
    `95% CI` = df$`95% CI`,
    P = environment_fdr_format_p(df$P),
    `P FDR (BH)` = environment_fdr_format_p(df$P_FDR),
    `P < 0.05` = ifelse(is.finite(df$P) & df$P < alpha, "Yes", "No"),
    `FDR < 0.05` = ifelse(is.finite(df$P_FDR) & df$P_FDR < alpha, "Yes", "No"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

environment_fdr_method_specs <- function(start_id, id_prefix, population_label, disease) {
  # start_id: 全人群 20 → S20..；敏感性 5 → SA5..
  disease <- gsub("_", " ", as.character(disease)[1L], fixed = TRUE)
  population_label <- gsub("_", " ", as.character(population_label)[1L], fixed = TRUE)
  ids <- paste0(id_prefix, start_id + 0:3)
  list(
    list(
      id = ids[1], key = "glm", block = "glm_environment_quartile",
      title = paste0(
        ids[1], ". FDR-adjusted GLM continuous associations of Environmental Toxicants with ",
        disease, " (", population_label, ")"
      ),
      footnote = paste0(
        population_label,
        ". BH-FDR on continuous P within each of Crude / Model1 / Model2 ",
        "(across VOCs; models not pooled). Aligned with GLM Table S8 structure."
      )
    ),
    list(
      id = ids[2], key = "wqs", block = "wqs_environment",
      title = paste0(
        ids[2], ". FDR-adjusted WQS index association with ",
        disease, " (", population_label, ")"
      ),
      footnote = paste0(
        population_label, ". BH-FDR on WQS index Wald P (mixture overall). ",
        "Covariate rows in the main WQS table are not re-tested here."
      )
    ),
    list(
      id = ids[3], key = "bkmr", block = "bkmr_analysis",
      title = paste0(
        ids[3], ". Posterior inclusion probabilities (PIP) of Environmental Toxicants for ",
        disease, " (", population_label, ")"
      ),
      footnote = paste0(
        population_label, ". Descriptive summary of BKMR posterior inclusion probabilities. ",
        "PIP is a Bayesian inclusion probability, not a frequentist P-value; ",
        "no BH/FDR conversion of (1-PIP) is applied. ",
        "Variables with PIP > 0.5 are highlighted (conventional threshold)."
      )
    ),
    list(
      id = ids[4], key = "qgc", block = "qgcomp_environment",
      title = paste0(
        ids[4], ". FDR-adjusted Quantile g-Computation associations with ",
        disease, " (", population_label, ")"
      ),
      footnote = paste0(
        population_label, ". BH-FDR on qgcomp component coefficients (excl. intercept) ",
        "plus the overall psi mixture effect."
      )
    )
  )
}


# ── FDR 图：主文 Figure 9–13；敏感性 Figure SA6–SA10（含 BKMR dose-response）──────

environment_fdr_parse_or_ci <- function(or_txt, ci_txt) {
  or <- suppressWarnings(as.numeric(trimws(as.character(or_txt %||% ""))))
  ci <- as.character(ci_txt %||% "")
  lo <- hi <- NA_real_
  m <- regmatches(ci, regexpr("[-0-9.]+\\s*,\\s*[-0-9.]+", ci))
  if (length(m) && nzchar(m)) {
    parts <- strsplit(m, ",", fixed = TRUE)[[1L]]
    if (length(parts) >= 2L) {
      lo <- suppressWarnings(as.numeric(trimws(parts[1L])))
      hi <- suppressWarnings(as.numeric(trimws(parts[2L])))
    }
  }
  list(or = or, lo = lo, hi = hi)
}


# FDR 图：复用原方法出图（WQS / BKMR overall+singvar+dose / QGC），仅换图号标题

environment_fdr_figure_specs <- function(start_id, id_prefix, population_label, disease) {
  disease <- gsub("_", " ", as.character(disease)[1L], fixed = TRUE)
  population_label <- gsub("_", " ", as.character(population_label)[1L], fixed = TRUE)
  # 原 FDR 四图编号不动（主文 9-12 / 敏感性 SA6-SA9）；dose 顺延为第 5 张（13 / SA10）
  ids <- paste0(id_prefix, start_id + 0:4)
  list(
    list(
      id = ids[1], key = "wqs", source_key = "wqs",
      title = paste0(ids[1], ". WQS model weights with FDR tables (", disease, "; ", population_label, ")"),
      findings = "与主文 WQS 权重图同款：横条为各 VOC 平均权重；本图与 FDR 表（WQS）配套。"
    ),
    list(
      id = ids[2], key = "bkmr_overall", source_key = "bkmr_overall",
      title = paste0(ids[2], ". BKMR overall mixture effect with PIP tables (", disease, "; ", population_label, ")"),
      findings = "与主文 BKMR overall 图同款：联合分位上的总体混合物效应及区间；本图与 PIP 汇总表（BKMR）配套。"
    ),
    list(
      id = ids[3], key = "bkmr_singvar", source_key = "bkmr_singvar",
      title = paste0(ids[3], ". BKMR single-variable effect with PIP tables (", disease, "; ", population_label, ")"),
      findings = "与主文 BKMR 单变量效应图同款；本图与 PIP 汇总表（BKMR）配套。"
    ),
    list(
      id = ids[4], key = "qgc", source_key = "qgc",
      title = paste0(ids[4], ". QGC model weights with FDR tables (", disease, "; ", population_label, ")"),
      findings = "与主文 Quantile g-computation 权重图同款；本图与 FDR 表（QGC）配套。"
    ),
    list(
      id = ids[5], key = "bkmr_dose", source_key = "bkmr_dose",
      title = paste0(ids[5], ". BKMR dose-response with PIP tables (", disease, "; ", population_label, ")"),
      findings = "与主文 BKMR dose-response 图同款：各 VOC 暴露-响应单变量剂量反应曲线；本图与 PIP 汇总表（BKMR）配套。"
    )
  )
}

environment_fdr_resolve_source_pdf <- function(config, source_key, figures_dir = NULL) {
  bc <- config$environment_batch %||% list()
  result_root <- bc$output_base %||% config$project$output_dir
  result_root <- normalizePath(as.character(result_root)[1L], winslash = "/", mustWork = FALSE)
  sens_out <- tryCatch(environment_sensitivity_output_dir(config), error = function(e) NULL)
  is_sens <- FALSE
  if (!is.null(figures_dir) && !is.null(sens_out)) {
    fig_n <- normalizePath(as.character(figures_dir)[1L], winslash = "/", mustWork = FALSE)
    sens_n <- normalizePath(file.path(sens_out, "Figures"), winslash = "/", mustWork = FALSE)
    is_sens <- identical(fig_n, sens_n) || grepl("/Sensitivity", fig_n, fixed = TRUE)
  }
  cands <- character(0)
  if (isTRUE(is_sens)) {
    step_map <- list(
      wqs = file.path(sens_out, "step02_wqs_environment/Figures/Figure_WQS_Weights.pdf"),
      bkmr_overall = file.path(sens_out, "step04_bkmr_analysis/Figures/Figure_BKMR_Overall.pdf"),
      bkmr_singvar = file.path(sens_out, "step04_bkmr_analysis/Figures/Figure_BKMR_SingVar.pdf"),
      bkmr_dose = file.path(sens_out, "step04_bkmr_analysis/Figures/Figure_BKMR_DoseResponse.pdf"),
      qgc = file.path(sens_out, "step05_qgcomp_environment/Figures/Figure_QGComp_Weights.pdf")
    )
    pub_map <- list(
      wqs = file.path(sens_out, "Figures/pdf/Figure SA1. WQS model weights*.pdf"),
      bkmr_overall = file.path(sens_out, "Figures/pdf/Figure SA2. BKMR overall*.pdf"),
      bkmr_singvar = file.path(sens_out, "Figures/pdf/Figure SA3. BKMR single-variable*.pdf"),
      bkmr_dose = file.path(sens_out, "Figures/pdf/Figure SA4. BKMR dose-response*.pdf"),
      qgc = file.path(sens_out, "Figures/pdf/Figure SA5. Quantile g-computation*.pdf")
    )
    if (!is.null(step_map[[source_key]]) && file.exists(step_map[[source_key]])) {
      return(step_map[[source_key]])
    }
    hits <- Sys.glob(pub_map[[source_key]] %||% "")
    if (length(hits)) return(hits[[1L]])
  } else {
    shared <- file.path(result_root, "_shared/Figures")
    tailf <- file.path(result_root, "_tail/Figures")
    sumf <- file.path(result_root, "Results_Summary/Figures")
    step_map <- list(
      wqs = c(
        file.path(shared, "pdf/Figure_WQS_Weights.pdf"),
        file.path(shared, "Figure_WQS_Weights.pdf"),
        file.path(result_root, "_shared/step19_wqs_environment/Figures/Figure_WQS_Weights.pdf"),
        file.path(sumf, "Figure 3. The WQS model weights*.pdf"),
        file.path(sumf, "pdf/Figure 3. The WQS model weights*.pdf")
      ),
      bkmr_overall = c(
        file.path(shared, "pdf/Figure_BKMR_Overall.pdf"),
        file.path(shared, "Figure_BKMR_Overall.pdf"),
        file.path(result_root, "_shared/step21_bkmr_analysis/Figures/Figure_BKMR_Overall.pdf"),
        file.path(sumf, "Figure 4. The combined effect*.pdf"),
        file.path(sumf, "pdf/Figure 4. The combined effect*.pdf")
      ),
      bkmr_singvar = c(
        file.path(shared, "pdf/Figure_BKMR_SingVar.pdf"),
        file.path(shared, "Figure_BKMR_SingVar.pdf"),
        file.path(result_root, "_shared/step21_bkmr_analysis/Figures/Figure_BKMR_SingVar.pdf"),
        file.path(sumf, "Figure 5. Association of individual*.pdf"),
        file.path(sumf, "pdf/Figure 5. Association of individual*.pdf")
      ),
      bkmr_dose = c(
        file.path(shared, "pdf/Figure_BKMR_DoseResponse.pdf"),
        file.path(shared, "Figure_BKMR_DoseResponse.pdf"),
        file.path(result_root, "_shared/step21_bkmr_analysis/Figures/Figure_BKMR_DoseResponse.pdf"),
        file.path(sumf, "Figure 6. Dose-response*.pdf"),
        file.path(sumf, "pdf/Figure 6. Dose-response*.pdf")
      ),
      qgc = c(
        file.path(tailf, "pdf/Figure_QGComp_Weights.pdf"),
        file.path(tailf, "Figure_QGComp_Weights.pdf"),
        file.path(result_root, "_tail/step22_qgcomp_environment/Figures/Figure_QGComp_Weights.pdf"),
        file.path(sumf, "Figure 8. QGC model weights*.pdf"),
        file.path(sumf, "pdf/Figure 8. QGC model weights*.pdf")
      )
    )
    for (p in step_map[[source_key]] %||% character(0)) {
      if (grepl("\\*", p)) {
        hits <- Sys.glob(p)
        if (length(hits)) return(hits[[1L]])
      } else if (file.exists(p)) {
        return(p)
      }
    }
  }
  NA_character_
}

environment_fdr_save_figure <- function(source_pdf, figures_dir, title, meta = list()) {
  source_pdf <- as.character(source_pdf %||% "")[1L]
  if (!nzchar(source_pdf) || !file.exists(source_pdf)) {
    cli::cli_alert_warning("FDR 图源 PDF 缺失，跳过: {title}")
    return(NA_character_)
  }
  dir.create(figures_dir, recursive = TRUE, showWarnings = FALSE)
  if (exists("pub_figure_ensure_format_dirs", mode = "function")) {
    dirs <- pub_figure_ensure_format_dirs(figures_dir)
  } else {
    dirs <- c(
      pdf = file.path(figures_dir, "pdf"),
      png = file.path(figures_dir, "png"),
      tiff = file.path(figures_dir, "tiff"),
      image_information = file.path(figures_dir, "image_information")
    )
    for (d in dirs) dir.create(d, recursive = TRUE, showWarnings = FALSE)
  }
  safe <- gsub(":", " -", as.character(title)[1L], fixed = TRUE)
  safe <- gsub("[<>\"/\\\\|?*]", "_", safe)
  safe <- gsub("[[:space:]]+", " ", trimws(safe))
  stem <- safe
  pdf_path <- file.path(unname(dirs[["pdf"]]), paste0(stem, ".pdf"))
  for (sub in c("pdf", "png", "tiff", "image_information")) {
    old <- list.files(
      file.path(figures_dir, sub),
      pattern = paste0("^", gsub("([.()\\[\\]])", "\\\\\\1", stem)),
      full.names = TRUE
    )
    if (length(old)) unlink(old)
  }
  root_old <- file.path(figures_dir, paste0(stem, ".pdf"))
  if (file.exists(root_old)) unlink(root_old)

  # 直接复用原方法 PDF（图面与原来一致）
  if (!isTRUE(file.copy(source_pdf, pdf_path, overwrite = TRUE))) {
    stop("无法复制 FDR 图源: ", source_pdf, call. = FALSE)
  }

  dest_png <- file.path(unname(dirs[["png"]]), paste0(stem, ".png"))
  dest_tiff <- file.path(unname(dirs[["tiff"]]), paste0(stem, ".tiff"))
  if (exists(".pub_figure_rasterize_one", mode = "function")) {
    root_hint <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = getwd())
    tryCatch(
      .pub_figure_rasterize_one(pdf_path, dest_png, dest_tiff, 300L, root_hint = root_hint),
      error = function(e) cli::cli_alert_warning("FDR 图栅格化失败: {e$message}")
    )
  }
  md_path <- file.path(unname(dirs[["image_information"]]), paste0(stem, ".md"))
  findings <- as.character(meta$fdr_findings %||% "")
  body <- c(
    paste0("本图与课题原方法图同款（直接复用分析块出图），图号顺延后与 FDR 表配套。"),
    "",
    "### 图面要点",
    if (nzchar(findings)) findings else "图面内容与对应主文/敏感性方法图一致。",
    "",
    "### 图上标注",
    "- 图面数字/曲线与原方法图相同（非另绘 FDR 森林图）",
    paste0("- 人群：", meta$population %||% "未记录")
  )
  writeLines(c(
    paste0("# ", stem),
    "",
    "## 图面说明",
    body,
    "",
    "## 分析上下文",
    paste0("- 暴露: ", meta$exposure %||% "Environmental Toxicants"),
    paste0("- 结局: ", meta$outcome %||% "未记录"),
    paste0("- 样本量: ", meta$n_total %||% "未记录"),
    paste0("- Grouping: FDR (BH) tables companion figure"),
    paste0("- 数据库: ", meta$database %||% "NHANES"),
    paste0("- 是否拼图: 否"),
    ""
  ), md_path, useBytes = TRUE)
  cli::cli_alert_success("SCI FDR 图(复用原图): {.file {basename(pdf_path)}} <- {.file {basename(source_pdf)}}")
  pdf_path
}

environment_build_method_fdr_suite <- function(config, ck_dir, tables_dir,
                                               start_id, id_prefix,
                                               population_label,
                                               root_for_render = NULL,
                                               figures_dir = NULL,
                                               fig_start_id = NULL,
                                               fig_id_prefix = NULL) {
  fdr_cfg <- environment_fdr_cfg(config)
  method <- as.character(fdr_cfg$method %||% "BH")[1L]
  alpha <- as.numeric(fdr_cfg$alpha %||% 0.05)[1L]
  disease <- as.character(config$project$disease %||% "Outcome")[1L]
  disease_disp <- gsub("_", " ", disease, fixed = TRUE)
  specs <- environment_fdr_method_specs(start_id, id_prefix, population_label, disease)
  extractors <- list(
    glm = environment_fdr_extract_glm,
    wqs = environment_fdr_extract_wqs,
    bkmr = environment_fdr_extract_bkmr,
    qgc = environment_fdr_extract_qgc
  )
  do_fig <- !is.null(figures_dir) && nzchar(as.character(figures_dir)[1L])
  if (do_fig) {
    fig_start <- as.integer(fig_start_id %||% fdr_cfg$start_figure_id %||% 9L)[1L]
    if (!is.finite(fig_start) || fig_start < 1L) fig_start <- 9L
    fig_prefix <- as.character(fig_id_prefix %||% fdr_cfg$figure_id_prefix %||% "Figure ")[1L]
    fig_specs <- environment_fdr_figure_specs(fig_start, fig_prefix, population_label, disease)
  } else {
    fig_specs <- list()
  }
  meta <- list(
    outcome = disease_disp,
    exposure = "Environmental Toxicants",
    database = "NHANES",
    grouping = "FDR (BH)",
    population = gsub("_", " ", as.character(population_label)[1L], fixed = TRUE),
    study_type = "environment_fdr"
  )
  out <- list()
  for (spec in specs) {
    ctx <- tryCatch(
      environment_fdr_load_ctx(ck_dir, spec$block),
      error = function(e) {
        cli::cli_alert_warning("{spec$id} 跳过：{e$message}")
        NULL
      }
    )
    if (is.null(ctx)) next
    fun <- extractors[[spec$key]]
    df <- tryCatch(
      fun(ctx, config, method, alpha),
      error = function(e) {
        cli::cli_alert_warning("{spec$id} 提取失败: {e$message}")
        NULL
      }
    )
    if (is.null(df) || !nrow(df)) {
      cli::cli_alert_warning("{spec$id} 无可用结果行，跳过")
      next
    }
    footnote <- paste0(
      spec$footnote, " Adjustment=", method, "; alpha=", alpha, "."
    )
    path <- environment_fdr_write_table(
      df, tables_dir, spec$title, footnote,
      config = config, root_for_render = root_for_render
    )
    fig_path <- NA_character_
    cli::cli_alert_success("{spec$id} -> {.file {path}}")
    out[[spec$key]] <- list(
      id = spec$id, path = path, title = spec$title, n = nrow(df),
      figure = NA_character_
    )
  }
  # 表做完后再出 FDR 图：复用原 WQS/BKMR/QGC 图面
  if (do_fig && length(fig_specs)) {
    out$figures <- list()
    for (fs in fig_specs) {
      src <- environment_fdr_resolve_source_pdf(config, fs$source_key, figures_dir)
      meta_i <- meta
      meta_i$fdr_findings <- fs$findings
      fp <- tryCatch(
        environment_fdr_save_figure(src, figures_dir, fs$title, meta = meta_i),
        error = function(e) {
          cli::cli_alert_warning("{fs$id} 复用原图失败: {e$message}")
          NA_character_
        }
      )
      out$figures[[fs$key]] <- list(id = fs$id, path = fp, title = fs$title, source = src)
    }
  }
  out
}


environment_fdr_cleanup_univariate <- function(tables_dir) {
  junk <- list.files(
    tables_dir,
    pattern = "FDR-adjusted univariate|univariate associations.*FDR|FDR.*univariate",
    full.names = TRUE,
    ignore.case = TRUE
  )
  if (!length(junk)) {
    # fall through to underscore-twin cleanup
  } else {
  ok <- character(0)
  for (f in junk) {
    if (unlink(f) == 0L && !file.exists(f)) {
      ok <- c(ok, f)
      next
    }
    alt <- paste0(f, ".DEPRECATED_PLEASE_DELETE")
    if (isTRUE(file.rename(f, alt))) {
      ok <- c(ok, alt)
      cli::cli_alert_warning("旧单因素 FDR 被占用，已改名为: {.file {basename(alt)}}")
    } else {
      cli::cli_alert_danger(
        "无法删除旧单因素 FDR（文件被占用，请在 Excel/资源管理器关闭后删）: {.file {basename(f)}}"
      )
    }
  }
  if (length(ok)) cli::cli_alert_info("已处理旧单因素 FDR {length(ok)} 个")
  }
  # 删掉 Female_Infertility 与 Female Infertility 双份中的下划线版
  environment_fdr_dedupe_underscore_twins(tables_dir)
  invisible(TRUE)
}

#' 同一 FDR 表若同时有「病名空格」与「病名下划线」文件，只保留空格版
environment_fdr_dedupe_underscore_twins <- function(tables_dir) {
  tables_dir <- as.character(tables_dir)[1L]
  if (!dir.exists(tables_dir)) return(invisible(character(0)))
  files <- list.files(tables_dir, pattern = "FDR-adjusted", full.names = TRUE, ignore.case = TRUE)
  files <- files[file.exists(files) & grepl("\\.xlsx$", files, ignore.case = TRUE)]
  if (!length(files)) return(invisible(character(0)))
  # 下划线病名副本：文件名含 Female_Infertility 等，且存在对应空格版
  unders <- files[grepl("_[A-Za-z]", basename(files)) & grepl("FDR", basename(files), ignore.case = TRUE)]
  # 更稳：显式匹配「空格病名」对应的「下划线病名」
  removed <- character(0)
  for (f in files) {
    bn <- basename(f)
    if (!grepl("_", bn, fixed = TRUE)) next
    spaced <- file.path(dirname(f), gsub("_", " ", bn, fixed = TRUE))
    if (identical(normalizePath(f, winslash = "/", mustWork = FALSE),
                  normalizePath(spaced, winslash = "/", mustWork = FALSE))) next
    if (file.exists(spaced) && !identical(f, spaced)) {
      if (unlink(f) == 0L || !file.exists(f)) {
        removed <- c(removed, f)
      }
    }
  }
  if (length(removed)) {
    cli::cli_alert_info("已去掉 FDR 下划线重复件 {length(removed)} 个")
  }
  invisible(removed)
}

#' 全人群：GLM/WQS/BKMR/QGC 方法 FDR → Results_Summary/Tables（默认 S20–S23）
environment_build_full_population_fdr_table <- function(config, result_root = NULL,
                                                        project_root = NULL) {
  fdr_cfg <- environment_fdr_cfg(config)
  if (isFALSE(fdr_cfg$enable %||% TRUE)) {
    cli::cli_alert_info("environment_fdr$enable = FALSE，跳过全人群方法 FDR")
    return(invisible(NULL))
  }
  bc <- config$environment_batch %||% list()
  result_root <- result_root %||% bc$output_base %||% config$project$output_dir
  result_root <- normalizePath(as.character(result_root)[1L], winslash = "/", mustWork = FALSE)
  ck_dir <- environment_batch_shared_ck_dir(config)
  sum_tables <- file.path(result_root, "Results_Summary", "Tables")
  dir.create(sum_tables, recursive = TRUE, showWarnings = FALSE)
  environment_fdr_cleanup_univariate(sum_tables)

  start_id <- as.integer(fdr_cfg$start_table_id %||% fdr_cfg$table_start %||% 20L)[1L]
  if (!is.finite(start_id) || start_id < 1L) start_id <- 20L
  id_prefix <- as.character(fdr_cfg$id_prefix %||% "Table S")[1L]

  sum_figs <- file.path(result_root, "Results_Summary", "Figures")
  dir.create(sum_figs, recursive = TRUE, showWarnings = FALSE)
  fig_start <- as.integer(fdr_cfg$start_figure_id %||% 9L)[1L]
  if (!is.finite(fig_start) || fig_start < 1L) fig_start <- 9L

  pop_lab <- as.character(fdr_cfg$population_label %||% "full population")[1L]
  if (!nzchar(pop_lab)) pop_lab <- "full population"
  cli::cli_h2("全人群方法 FDR 表+图（GLM / WQS / BKMR / QGC；{pop_lab}）")
  environment_build_method_fdr_suite(
    config = config,
    ck_dir = ck_dir,
    tables_dir = sum_tables,
    start_id = start_id,
    id_prefix = id_prefix,
    population_label = pop_lab,
    root_for_render = file.path(result_root, "Results_Summary"),
    figures_dir = sum_figs,
    fig_start_id = fig_start,
    fig_id_prefix = as.character(fdr_cfg$figure_id_prefix %||% "Figure ")[1L]
  )
}

#' 敏感性：同上四方法 FDR → Sensitivity/Tables（默认 SA5–SA8）
environment_build_sensitivity_method_fdr_tables <- function(config, result_root = NULL,
                                                           project_root = NULL) {
  fdr_cfg <- environment_fdr_cfg(config)
  if (isFALSE(fdr_cfg$enable %||% TRUE)) {
    return(invisible(NULL))
  }
  sens <- environment_sensitivity_cfg(config)
  if (isFALSE(sens$enable %||% TRUE)) {
    cli::cli_alert_info("敏感性未启用，跳过敏感性方法 FDR")
    return(invisible(NULL))
  }
  bc <- config$environment_batch %||% list()
  result_root <- result_root %||% bc$output_base %||% config$project$output_dir
  result_root <- normalizePath(as.character(result_root)[1L], winslash = "/", mustWork = FALSE)
  sens_out <- environment_sensitivity_output_dir(config)
  sens_ck <- file.path(sens_out, "checkpoints")
  if (!dir.exists(sens_ck)) {
    cli::cli_alert_warning("敏感性 checkpoint 不存在，跳过 SA FDR: {.file {sens_ck}}")
    return(invisible(NULL))
  }
  tables_dir <- file.path(sens_out, "Tables")
  dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)

  start_id <- as.integer(fdr_cfg$sensitivity_start_id %||% 5L)[1L]
  if (!is.finite(start_id) || start_id < 1L) start_id <- 5L
  id_prefix <- as.character(fdr_cfg$sensitivity_id_prefix %||% "Table SA")[1L]
  pop_lab <- environment_sensitivity_pub_tag(
    sens$keep_levels, sens$exclude_levels
  )

  cli::cli_h2("敏感性方法 FDR 表+图（GLM / WQS / BKMR / QGC）")
  # 先确保 SA1–SA4 主表仍在（避免仅跑 FDR 时表目录只剩 SA5–SA8）
  tryCatch({
    tag <- environment_sensitivity_pub_tag(sens$keep_levels, sens$exclude_levels)
    disease_disp <- gsub("_", " ", as.character(config$project$disease %||% "Outcome")[1L], fixed = TRUE)
    fdr_bak <- list.files(tables_dir, pattern = "FDR-adjusted", full.names = TRUE)
    bak <- tempfile("sa_fdr_")
    dir.create(bak)
    if (length(fdr_bak)) file.copy(fdr_bak, bak)
    environment_sensitivity_finalize_outputs(sens_out, disease = disease_disp, tag = tag)
    if (length(list.files(bak))) {
      file.copy(list.files(bak, full.names = TRUE), tables_dir, overwrite = TRUE)
    }
  }, error = function(e) cli::cli_alert_warning("敏感性 SA1–SA4 恢复失败: {e$message}"))

  fig_start <- as.integer(fdr_cfg$sensitivity_figure_start_id %||% 6L)[1L]
  if (!is.finite(fig_start) || fig_start < 1L) fig_start <- 6L
  sens_figs <- file.path(sens_out, "Figures")
  dir.create(sens_figs, recursive = TRUE, showWarnings = FALSE)

  environment_build_method_fdr_suite(
    config = config,
    ck_dir = sens_ck,
    tables_dir = tables_dir,
    start_id = start_id,
    id_prefix = id_prefix,
    population_label = pop_lab,
    root_for_render = sens_out,
    figures_dir = sens_figs,
    fig_start_id = fig_start,
    fig_id_prefix = as.character(fdr_cfg$sensitivity_figure_id_prefix %||% "Figure SA")[1L]
  )
}
