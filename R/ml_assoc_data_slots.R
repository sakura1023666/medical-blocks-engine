###############################################################################
#  ml_assoc_data_slots.R — resolve train/test/imputed slots for assoc blocks
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

ml_assoc_has_time <- function(ctx) {
  tv <- ctx$config$survival$time_var %||% ""
  nzchar(as.character(tv)[1L])
}

ml_assoc_is_dual <- function(ctx) {
  split_mode <- ctx$config$ml_batch$split_mode %||%
    ctx$config$incidence_batch$split_mode %||% "per_db_internal"
  identical(split_mode, "cross_db")
}

ml_assoc_resolve_slots <- function(ctx) {
  split_mode <- ctx$config$ml_batch$split_mode %||%
    ctx$config$incidence_batch$split_mode %||% "per_db_internal"
  has_tt <- is.data.frame(ctx$data$train) && is.data.frame(ctx$data$test) &&
    nrow(ctx$data$train) > 0L && nrow(ctx$data$test) > 0L
  if (identical(split_mode, "cross_db")) {
    if (has_tt) {
      return(data.frame(slot = c("train", "test"), label = c("Train", "Validation"),
                        stringsAsFactors = FALSE))
    }
    cli::cli_alert_warning(
      "ml_assoc: cross_db but train/test missing, falling back to imputed"
    )
  }
  data.frame(slot = "imputed", label = "", stringsAsFactors = FALSE)
}

ml_assoc_frame_for_slot <- function(ctx, slot) {
  if (identical(slot, "imputed")) return(ctx$data$imputed %||% ctx$data$cleaned)
  ctx$data[[slot]]
}

#' VIF slots: honour data_slots ("train" / "test" / both). Train-only must NOT fall back to full imputed.
ml_vif_resolve_slots <- function(ctx) {
  mc <- ctx$config$multicollinearity %||% list()
  requested <- unique(as.character(mc$data_slots %||% c("train", "test")))
  requested <- requested[nzchar(requested)]
  has_tt <- is.data.frame(ctx$data$train) && is.data.frame(ctx$data$test) &&
    nrow(ctx$data$train) > 0L && nrow(ctx$data$test) > 0L
  want <- intersect(requested, c("train", "test"))
  if (has_tt && length(want) >= 1L) {
    lab <- ifelse(want == "train", "Train", "Validation")
    return(data.frame(slot = want, label = lab, stringsAsFactors = FALSE))
  }
  if (length(want) >= 1L && !has_tt) {
    cli::cli_alert_warning(
      "ml_vif: data_slots request train/test but slots missing, falling back to imputed"
    )
  }
  data.frame(slot = "imputed", label = "", stringsAsFactors = FALSE)
}

ml_vif_preserve_downstream_keys <- function() {
  c(
    "Model1Factors", "Model2Factors", "vif_screen_pass", "univar_features",
    "vif_screen_table", "tb_screen", "tb1"
  )
}

#' 将 block 在 temp imputed 上新增/更新的列写回 train/test，并视情况合并到全局 imputed。
#' 典型：rcs_incidence → <Index>_RCS_Group；缺失会令后续 glm_rcs 找不到分组列。
ml_assoc_merge_slot_cols_back <- function(ctx, slot, fr_before, fr_after) {
  if (!is.data.frame(fr_after) || !is.data.frame(fr_before)) return(ctx)
  new_cols <- setdiff(names(fr_after), names(fr_before))
  # 已有列也可能被更新（同上次 cutoff 不同）；对 *_RCS_Group / Group 类列始终覆盖
  rcs_like <- names(fr_after)[grepl("_RCS_Group$|_rcs_group$", names(fr_after), ignore.case = TRUE)]
  merge_cols <- unique(c(new_cols, rcs_like))
  if (!length(merge_cols)) return(ctx)

  .paste_cols <- function(dst, src, cols) {
    if (!is.data.frame(dst) || !is.data.frame(src)) return(dst)
    for (cn in cols) {
      if (!cn %in% names(src)) next
      if (nrow(dst) == nrow(src)) {
        dst[[cn]] <- src[[cn]]
      } else if (!is.null(rownames(dst)) && !is.null(rownames(src))) {
        m <- match(rownames(dst), rownames(src))
        if (all(is.finite(m))) {
          dst[[cn]] <- src[[cn]][m]
        } else {
          cli::cli_alert_warning(
            "ml_assoc: cannot row-align column '{cn}' for slot merge (nrow {nrow(dst)} vs {nrow(src)})"
          )
        }
      } else {
        cli::cli_alert_warning(
          "ml_assoc: cannot merge column '{cn}' without matching rows"
        )
      }
    }
    dst
  }

  if (identical(slot, "train") || identical(slot, "test")) {
    ctx$data[[slot]] <- .paste_cols(ctx$data[[slot]], fr_after, merge_cols)
  }
  # 全局 imputed：仅合并本 slot 可对齐的行（通常 id 不同；按行名或跳过）
  if (is.data.frame(ctx$data$imputed)) {
    # rcs 也会直接写 impute 时无效（我们用临时 slot）；清理无意义
    invisible(NULL)
  }
  # cleaned 同步
  if (is.data.frame(ctx$data$cleaned) && nrow(ctx$data$cleaned) == nrow(fr_after)) {
    ctx$data$cleaned <- .paste_cols(ctx$data$cleaned, fr_after, merge_cols)
  }
  if (length(merge_cols)) {
    cli::cli_alert_info(
      "ml_assoc: wrote back {length(merge_cols)} col(s) to slot {slot}: {paste(merge_cols, collapse = ', ')}"
    )
  }
  ctx
}

ml_assoc_run_on_slot <- function(ctx, slot, label, block_name) {
  old_imp <- ctx$data$imputed
  pub_before <- ctx$config$pub
  slot_label_before <- if (is.null(pub_before)) NULL else pub_before$slot_label
  # restrict_to_train=TRUE 时 pipeline_upstream_modeling_data 永远读 train，
  # 导致 train/test 槽的 VIF 值完全相同；显式跑 slot 时必须临时关闭。
  old_up_restrict <- ctx$config$upstream$restrict_to_train
  old_fs_restrict <- ctx$config$feature_selection$restrict_to_train
  fr <- ml_assoc_frame_for_slot(ctx, slot)
  if (is.null(fr) || (is.data.frame(fr) && nrow(fr) == 0L)) {
    cli::cli_alert_warning("ml_assoc: slot {slot} empty, skip {block_name}")
    return(ctx)
  }
  # Ensure association outcomes still present if only Group remains
  outcome_col <- ctx$config$data$outcome_column %||% "Disease"
  if (is.data.frame(fr) && !outcome_col %in% names(fr) && "Group" %in% names(fr)) {
    fr[[outcome_col]] <- fr$Group
  }
  fr_before <- fr
  root <- ctx$config$project$root %||% getwd()
  if (exists("pipeline_source_block", mode = "function")) {
    try(pipeline_source_block(root, block_name), silent = TRUE)
  }
  if (identical(slot, "train") || identical(slot, "test") ||
      identical(slot, "validation")) {
    ctx$config$upstream <- modifyList(
      ctx$config$upstream %||% list(),
      list(restrict_to_train = FALSE)
    )
    if (!is.null(ctx$config$feature_selection)) {
      ctx$config$feature_selection$restrict_to_train <- FALSE
    }
    cli::cli_alert_info(
      "ml_assoc: slot={slot} (n={nrow(fr)})，临时关闭 restrict_to_train 以使用槽数据"
    )
  }
  ctx$data$imputed <- fr
  ctx$config$pub <- modifyList(pub_before %||% list(), list(slot_label = label))
  ctx <- tryCatch(run_block(ctx, block_name), error = function(e) {
    cli::cli_alert_warning("{block_name}@{slot}: {conditionMessage(e)}"); ctx
  })
  # 写回 RCS 分组等新增列到 train/test，供后续 glm_rcs 使用；然后再恢复全局 imputed
  fr_after <- ctx$data$imputed
  if (is.data.frame(fr_after)) {
    ctx <- ml_assoc_merge_slot_cols_back(ctx, slot, fr_before, fr_after)
  }
  ctx$data$imputed <- old_imp
  if (!is.null(ctx$config$upstream)) {
    ctx$config$upstream$restrict_to_train <- old_up_restrict
  }
  if (!is.null(ctx$config$feature_selection)) {
    ctx$config$feature_selection$restrict_to_train <- old_fs_restrict
  }
  if (is.null(pub_before)) {
    if (!is.null(ctx$config$pub)) ctx$config$pub$slot_label <- NULL
  } else {
    ctx$config$pub$slot_label <- slot_label_before
  }
  ctx
}

ml_vif_ensure_mcol_helpers <- function(ctx = NULL) {
  if (exists(".mcol_build_orig_var_vif_table", mode = "function")) {
    return(invisible(TRUE))
  }
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er) && !is.null(ctx)) er <- ctx$config$project$root %||% getwd()
  if (!nzchar(er)) er <- getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
  vif_f <- file.path(root, "Blocks/08_vif/01block_multicollinearity.R")
  if (!file.exists(vif_f)) return(invisible(FALSE))
  if (!exists("register_block", mode = "function")) {
    register_block <- function(...) invisible(NULL)
    assign("register_block", register_block, envir = .GlobalEnv)
  }
  source(vif_f, local = FALSE)
  invisible(exists(".mcol_build_orig_var_vif_table", mode = "function"))
}

#' 用训练集选出的变量，在指定数据上出 VIF 报告表（不再重筛、不按本集 VIF 砍列）
ml_vif_export_fixed_set <- function(ctx, data, vars, caption, csv_name = NULL) {
  vars <- unique(as.character(vars)[nzchar(as.character(vars))])
  if (!is.data.frame(data) || !nrow(data) || !length(vars)) {
    return(invisible(FALSE))
  }
  ml_vif_ensure_mcol_helpers(ctx)
  if (!exists(".mcol_build_orig_var_vif_table", mode = "function")) {
    cli::cli_alert_warning("ml_vif_export_fixed_set: 缺少 VIF 计算函数，跳过。")
    return(invisible(FALSE))
  }
  cfg <- ctx$config %||% list()
  exposure <- character(0)
  if (exists("pipeline_index_exposure_var", mode = "function")) {
    exposure <- as.character(pipeline_index_exposure_var(cfg))
    exposure <- exposure[nzchar(exposure)]
  }
  vars_use <- unique(c(vars, exposure))
  present <- intersect(vars_use, names(data))
  missing <- setdiff(vars_use, names(data))
  if (length(missing)) {
    cli::cli_alert_warning(
      "VIF 固定名单本集缺失 {length(missing)} 个: {paste(head(missing, 8), collapse = ', ')}"
    )
  }
  if (!length(present)) return(invisible(FALSE))
  tbl <- .mcol_build_orig_var_vif_table(present, data)
  if (is.null(tbl) || !nrow(tbl)) return(invisible(FALSE))
  if (exists("order_vars_like_table1", mode = "function")) {
    ord <- order_vars_like_table1(tbl$Variable, ctx, cfg)
    ord <- ord[ord %in% tbl$Variable]
    if (length(ord)) tbl <- tbl[match(ord, tbl$Variable), , drop = FALSE]
  }
  cap <- as.character(caption)[1L]
  cap <- sub("^Table S\\d+[a-z]?\\.\\s*", "", cap)
  if (!nzchar(cap)) cap <- "Multicollinearity Analysis VIF screen"
  out_dir <- ctx$output_dir %||% getwd()
  tbl_dir <- ctx$output_dir_tables %||% file.path(out_dir, "Tables")
  dir.create(tbl_dir, recursive = TRUE, showWarnings = FALSE)
  if (is.null(csv_name) || !nzchar(csv_name)) {
    csv_name <- paste0(gsub("[^A-Za-z0-9]+", "_", cap), ".csv")
  }
  tbl_csv <- tbl
  tbl_csv$Variable_display <- gsub("_", " ", tbl_csv$Variable, fixed = TRUE)
  write.csv(
    tbl_csv[, c("Variable_display", "VIF"), drop = FALSE],
    file.path(out_dir, csv_name),
    row.names = FALSE
  )
  tbl_pub <- data.frame(
    Variable = gsub("_", " ", tbl$Variable, fixed = TRUE),
    VIF = if (exists("format_vif_pub_column", mode = "function")) {
      format_vif_pub_column(tbl$VIF)
    } else {
      tbl$VIF
    },
    stringsAsFactors = FALSE
  )
  if (exists("pub_paths", mode = "function") && exists("export_sci_table", mode = "function")) {
    paths_vif <- pub_paths(ctx, tbl_dir, "supp_table", cap, "xlsx")
    tryCatch(
      export_sci_table(
        tbl_pub, paths_vif$filepath, title = paths_vif$title,
        blank_na_cells = FALSE, excel_use_prepared = FALSE
      ),
      error = function(e) cli::cli_alert_warning("VIF Excel export failed: {e$message}")
    )
    if (exists("flush_pub_output_queues", mode = "function")) {
      tryCatch(flush_pub_output_queues(ctx), error = function(e) NULL)
    }
  } else if (requireNamespace("openxlsx", quietly = TRUE)) {
    openxlsx::write.xlsx(tbl_pub, file.path(tbl_dir, paste0(cap, ".xlsx")), overwrite = TRUE)
  }
  cli::cli_alert_success("VIF 固定名单报告: {cap}（n={nrow(tbl_pub)}）")
  invisible(TRUE)
}

ml_vif_holdout_caption <- function(slot, config = list()) {
  slot <- tolower(as.character(slot)[1L])
  dev_ext <- exists("ml_dual_is_dev_ext_mode", mode = "function") &&
    isTRUE(ml_dual_is_dev_ext_mode(config))
  if (identical(slot, "train")) {
    return("Multicollinearity Analysis VIF screen (training set)")
  }
  if (identical(slot, "test")) {
    return(if (dev_ext) {
      "Multicollinearity Analysis VIF screen (internal validation set)"
    } else {
      "Multicollinearity Analysis VIF screen (validation set)"
    })
  }
  if (dev_ext) {
    return("Multicollinearity Analysis VIF screen (external validation set)")
  }
  "Multicollinearity Analysis VIF screen (validation set)"
}
