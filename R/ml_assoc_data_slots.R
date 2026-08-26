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

#' VIF dual slots: train+test whenever both exist (independent of split_mode).
ml_vif_resolve_slots <- function(ctx) {
  mc <- ctx$config$multicollinearity %||% list()
  requested <- as.character(mc$data_slots %||% c("train", "test"))
  has_tt <- is.data.frame(ctx$data$train) && is.data.frame(ctx$data$test) &&
    nrow(ctx$data$train) > 0L && nrow(ctx$data$test) > 0L
  if (has_tt && all(c("train", "test") %in% requested)) {
    return(data.frame(
      slot = c("train", "test"), label = c("Train", "Validation"),
      stringsAsFactors = FALSE
    ))
  }
  if (has_tt && length(intersect(requested, c("train", "test"))) >= 1L) {
    cli::cli_alert_warning(
      "ml_vif: train/test present but data_slots incomplete, falling back to imputed once"
    )
  } else if (length(intersect(requested, c("train", "test"))) >= 1L && !has_tt) {
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
