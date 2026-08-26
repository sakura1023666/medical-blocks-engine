###############################################################################
#  环境毒物 Table S3-VOC / S4-VOC（与临床 S3/S4 同版式，数据来自 voc_clinical_gate）
###############################################################################

.environment_voc_pub_paths <- function(dir, table_no, title_caption, file_caption, ext = "xlsx") {
  table_no <- as.integer(table_no)[1L]
  pref <- paste0("Table S", table_no, ".")
  cap_t <- trimws(as.character(title_caption %||% ""))
  cap_f <- trimws(as.character(file_caption %||% ""))
  title <- if (nzchar(cap_t)) paste(pref, cap_t) else pref
  stem_f <- if (nzchar(cap_f)) paste(pref, cap_f) else pref
  filepath <- if (exists(".inject_db_into_pub_filepath", mode = "function")) {
    .inject_db_into_pub_filepath(file.path(dir, paste0(stem_f, ".", ext)))
  } else {
    file.path(dir, paste0(stem_f, ".", ext))
  }
  list(title = title, filepath = filepath)
}

environment_batch_should_export_voc_pub_tables <- function(config) {
  bc <- config$environment_batch %||% list()
  gate <- config$environment_voc_clinical_gate %||% list()
  isFALSE(bc$include_vocs_in_clinical_screen %||% TRUE) &&
    isTRUE(gate$enable %||% FALSE)
}

environment_batch_load_ctx_for_voc_pub_tables <- function(config, root) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  ck_dir <- if (exists("environment_batch_shared_ck_dir", mode = "function")) {
    environment_batch_shared_ck_dir(config)
  } else {
    file.path(
      config$environment_batch$output_base %||% config$project$output_dir,
      "checkpoints", "_shared", "main"
    )
  }
  ck_candidates <- unique(normalizePath(c(
    file.path(ck_dir, "environment_voc_clinical_gate.rds"),
    file.path(ck_dir, "step10_environment_voc_clinical_gate.rds"),
    file.path(ck_dir, "obj.rds")
  ), mustWork = FALSE))
  ck_path <- ck_candidates[file.exists(ck_candidates)][1L]
  if (is.na(ck_path) || !nzchar(ck_path)) {
    stop("environment_batch_export_voc_pub_tables: 未找到 VOC gate checkpoint。", call. = FALSE)
  }
  ck <- readRDS(ck_path)
  ctx <- ck$ctx
  ctx$config <- config
  if (exists("environment_batch_sync_config_from_ctx", mode = "function")) {
    config <- environment_batch_sync_config_from_ctx(config, ctx)
    ctx$config <- config
  }
  if (!is.null(ctx$data$imputed) && exists("block_obj", mode = "function")) {
    ctx <- block_obj(ctx)
  }
  if (is.null(ctx$results$nhanes_design)) {
    stop("environment_batch_export_voc_pub_tables: nhanes_design 为空。", call. = FALSE)
  }
  ctx
}

environment_batch_export_voc_pub_tables <- function(config, root) {
  if (!environment_batch_should_export_voc_pub_tables(config)) {
    return(invisible(NULL))
  }
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  old_db <- getOption("pipeline.database_name", NULL)
  on.exit(options(pipeline.database_name = old_db), add = TRUE)
  options(pipeline.database_name = "NHANES-VOC")
  if (!exists("environment_export_voc_univariate_vif_tables", mode = "function")) {
    source(file.path(root, "R/environment_voc_pub_tables.R"), local = FALSE)
  }
  if (!exists("block_obj", mode = "function")) {
    obj_block <- file.path(root, "Blocks/12_obj/01block_obj.R")
    if (file.exists(obj_block)) source(obj_block, local = FALSE)
  }
  ctx <- environment_batch_load_ctx_for_voc_pub_tables(config, root)
  out_shared <- file.path(
    config$environment_batch$output_base %||% config$project$output_dir,
    "_shared", "Tables"
  )
  if (!dir.exists(out_shared)) dir.create(out_shared, recursive = TRUE)
  environment_export_voc_univariate_vif_tables(
    ctx,
    output_dir = out_shared,
    mirror_root_tables = TRUE
  )
}

environment_export_voc_univariate_vif_tables <- function(
    ctx,
    output_dir = NULL,
    mirror_root_tables = TRUE,
    p_cutoff = NULL,
    vif_threshold = NULL
) {
  cfg <- ctx$config %||% list()
  bl  <- cfg$environment_voc_clinical_gate %||% list()
  proj <- cfg$project %||% list()
  disease <- as.character(proj$disease %||% proj$disease_cn %||% "Outcome")[1L]

  p_cutoff <- as.numeric(p_cutoff %||% bl$voc_univariate_p_cutoff %||% 0.05)[1L]
  vif_thr  <- as.numeric(vif_threshold %||% bl$voc_vif_threshold %||% 4)[1L]

  design <- ctx$results$nhanes_design
  if (is.null(design)) {
    stop("environment_export_voc_*: nhanes_design 为空，请先跑 obj。", call. = FALSE)
  }
  data <- ctx$data$imputed %||% ctx$data$mapped %||% ctx$data$cleaned
  if (is.null(data)) stop("environment_export_voc_*: 无 imputed 数据。", call. = FALSE)

  voc_pool <- unique(as.character(ctx$results$voc_columns %||% character(0)))
  voc_pool <- voc_pool[nzchar(voc_pool)]
  if (!length(voc_pool) && exists("environment_voc_allowlist", mode = "function")) {
    voc_pool <- environment_voc_allowlist(data, cfg)
  }
  voc_pool <- intersect(voc_pool, names(data))
  if (!length(voc_pool)) stop("environment_export_voc_*: VOC 池为空。", call. = FALSE)

  label_map <- if (exists("environment_resolve_label_map", mode = "function")) {
    environment_resolve_label_map(cfg, bl$label_mapping)
  } else {
    bl$label_mapping
  }
  .disp <- function(v) {
    if (exists("environment_display_label", mode = "function")) {
      environment_display_label(as.character(v), label_map)
    } else {
      gsub("_", " ", as.character(v), fixed = TRUE)
    }
  }

  if (is.null(output_dir) || !nzchar(output_dir)) {
    output_dir <- ctx$output_dir_tables %||%
      file.path(ctx$root_output_dir %||% ctx$output_dir %||% ".", "Tables")
  }
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  uni_res <- environment_voc_survey_univariate(ctx, voc_pool, bl)
  uni_tbl <- uni_res$table
  if (!nrow(uni_tbl)) stop("environment_export_voc_*: VOC 单因素表为空。", call. = FALSE)

  normal_vars <- as.character(ctx$results$normal_vars %||% character(0))
  skewed_vars <- as.character(ctx$results$skewed_vars %||% character(0))

  .fmt_p_inline <- function(p) {
    if (length(p) != 1L || is.na(p)) return("")
    p <- as.numeric(p)
    if (p < 0.001) return("p<0.001")
    paste0("p=", formatC(round(p, 3), format = "f", digits = 3))
  }
  .fmt_ci_p <- function(est, lo, hi, p) {
    if (length(est) != 1L || is.na(est)) return("")
    pt <- .fmt_p_inline(p)
    if (is.na(lo) || is.na(hi)) {
      if (!nzchar(pt)) return(paste0(fmt_num(est)))
      return(paste0(fmt_num(est), " (", pt, ")"))
    }
    if (!nzchar(pt)) {
      return(paste0(fmt_num(est), " (", fmt_num(lo), "-", fmt_num(hi), ")"))
    }
    paste0(fmt_num(est), " (", fmt_num(lo), "-", fmt_num(hi), ", ", pt, ")")
  }

  uni_ord <- uni_tbl[match(voc_pool, uni_tbl$Variable), , drop = FALSE]
  uni_ord <- uni_ord[!is.na(uni_ord$Variable), , drop = FALSE]

  outcome_col <- cfg$data$outcome_column %||% "Group"
  disease_lbl <- proj$analysis_group %||% disease
  des_u <- stats::update(
    design,
    Disease_Group = as.numeric(design$variables[[outcome_col]] == disease_lbl)
  )

  s3_rows <- list()
  for (i in seq_len(nrow(uni_ord))) {
    v <- as.character(uni_ord$Variable[i])
    if (!v %in% names(des_u$variables)) next
    is_norm <- if (exists("is_var_normal_for_table", mode = "function")) {
      is_var_normal_for_table(v, normal_vars, skewed_vars)
    } else {
      TRUE
    }
    stat_lab <- if (exists("continuous_statistic_label", mode = "function")) {
      continuous_statistic_label(is_norm)
    } else {
      "Median (Q1, Q3)"
    }
    all_txt <- if (exists("fmt_continuous_svy", mode = "function")) {
      fmt_continuous_svy(des_u, v, is_norm)
    } else {
      ""
    }
    or_v <- uni_ord$OR[i]
    lo_v <- if ("CI_lo" %in% names(uni_ord)) uni_ord$CI_lo[i] else NA_real_
    hi_v <- if ("CI_hi" %in% names(uni_ord)) uni_ord$CI_hi[i] else NA_real_
    p_v  <- uni_ord$P[i]
    ci_txt <- if (is.finite(or_v)) .fmt_ci_p(or_v, lo_v, hi_v, p_v) else ""
    s3_rows[[length(s3_rows) + 1L]] <- data.frame(
      Characteristic = .disp(v),
      Statistic = stat_lab,
      Overall = all_txt,
      `OR (univariable)` = ci_txt,
      check.names = FALSE,
      stringsAsFactors = FALSE
    )
  }
  if (!length(s3_rows)) stop("environment_export_voc_*: 无法构建 S3-VOC 行。", call. = FALSE)
  tbl_s3 <- do.call(rbind, s3_rows)

  base_title <- paste0("Logistic Regression Analysis of ", disease)
  pub_s3 <- .environment_voc_pub_paths(
    output_dir, 3L,
    title_caption = paste0(base_title, " (Environmental Toxicants)"),
    file_caption = "Univariate Regression Analysis (Environmental Toxicants)"
  )
  export_sci_table(tbl_s3, pub_s3$filepath, title = pub_s3$title)
  s3_file <- pub_s3$filepath

  # ── S4-VOC: 单因素显著 VOC 的 VIF（仅 VIF < 阈值，与门禁一致）────────────────
  uni_pass <- unique(as.character(ctx$results$voc_univariate_pass %||% uni_res$keep))
  if (!length(uni_pass)) uni_pass <- uni_res$keep
  uni_pass <- intersect(uni_pass, voc_pool)

  detail <- ctx$results$environment_voc_clinical_gate_detail
  if (!is.null(detail) && nrow(detail)) {
    vif_df <- detail[
      detail$Univariate %in% TRUE & is.finite(detail$VIF) & detail$VIF < vif_thr,
      c("VOC", "VIF"),
      drop = FALSE
    ]
    names(vif_df) <- c("Variable", "VIF")
  } else {
    vif_res <- environment_calculate_vif_from_vars(uni_pass, data)
    if (is.null(vif_res$vif_df)) {
      stop("environment_export_voc_*: 无法计算 VOC VIF。", call. = FALSE)
    }
    vif_df <- vif_res$vif_df[
      is.finite(vif_res$vif_df$VIF) & vif_res$vif_df$VIF < vif_thr,
      ,
      drop = FALSE
    ]
  }
  if (!nrow(vif_df)) {
    cli::cli_alert_warning("S4-VOC: 无 VIF < {vif_thr} 的 VOC 行")
  }
  if (exists("order_vars_like_table1", mode = "function")) {
    ord <- order_vars_like_table1(vif_df$Variable, ctx, cfg)
    vif_df <- vif_df[match(ord, vif_df$Variable), , drop = FALSE]
    vif_df <- vif_df[!is.na(vif_df$Variable), , drop = FALSE]
  }
  vif_df$Variable <- vapply(vif_df$Variable, .disp, character(1L))
  vif_df$VIF <- format_vif_pub_column(vif_df$VIF)

  cap_vif <- paste0(
    "Weighted Multicollinearity Analysis (VIF, univariate screen, NHANES) for ",
    disease, " — Environmental Toxicants"
  )
  pub_s4 <- .environment_voc_pub_paths(
    output_dir, 4L,
    title_caption = cap_vif,
    file_caption = "Weighted Multicollinearity Analysis (VIF, univariate p<0.05 screen)"
  )
  export_sci_table(
    vif_df, pub_s4$filepath, title = pub_s4$title,
    blank_na_cells = FALSE, excel_use_prepared = FALSE
  )
  s4_file <- pub_s4$filepath

  if (exists("render_queued_tables", mode = "function")) {
    render_queued_tables(list())
  }

  cli::cli_alert_success("VOC 单因素表: {.file {basename(s3_file)}}")
  cli::cli_alert_success("VOC VIF 表: {.file {basename(s4_file)}}")

  if (isTRUE(mirror_root_tables)) {
    root <- cfg$environment_batch$output_base %||% proj$output_dir
    if (nzchar(root)) {
      root_tables <- file.path(root, "Tables")
      if (!dir.exists(root_tables)) dir.create(root_tables, recursive = TRUE)
      for (src in c(s3_file, s4_file)) {
        if (file.exists(src)) {
          file.copy(src, file.path(root_tables, basename(src)), overwrite = TRUE)
          cli::cli_alert_info("Mirrored: {.file {basename(src)}}")
        }
      }
    }
  }

  invisible(list(s3 = s3_file, s4 = s4_file, s3_data = tbl_s3, s4_data = vif_df))
}
