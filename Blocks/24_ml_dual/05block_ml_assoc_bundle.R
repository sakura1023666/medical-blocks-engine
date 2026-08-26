###############################################################################
#  ml_assoc_bundle — 关联分析块按 train/test/imputed 数据槽循环
#
#  register_block: "ml_assoc_bundle"
#  前置: train_validation + multicollinearity_screen
#  依赖: R/ml_assoc_data_slots.R（batch bootstrap 已 source）
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

.ml_assoc_ensure_helpers <- function(ctx) {
  if (exists("ml_assoc_resolve_slots", mode = "function")) return(invisible(NULL))
  root <- ctx$config$project$root %||% getwd()
  helper <- file.path(root, "R/ml_assoc_data_slots.R")
  if (file.exists(helper)) source(helper, local = FALSE)
}

.ml_assoc_file_has_slot_label <- function(filename) {
  grepl("\\(Train\\)|\\(Validation\\)", filename, fixed = FALSE)
}

#' 图/表 stem 追加 slot 标签（如 " (Train)"），避免 root 镜像后再 rename 产生双份
ml_assoc_stem_with_slot <- function(stem, label) {
  stem <- as.character(stem)[1L]
  label <- as.character(label %||% "")[1L]
  if (!nzchar(stem) || !nzchar(label)) return(stem)
  if (.ml_assoc_file_has_slot_label(stem)) return(stem)
  # 已有同标签
  if (grepl(paste0("\\(", label, "\\)"), stem, fixed = FALSE)) return(stem)
  ext <- tools::file_ext(stem)
  if (nzchar(ext)) {
    base <- sub(paste0("\\.", ext, "$"), "", stem, ignore.case = TRUE)
    return(paste0(base, " (", label, ").", ext))
  }
  paste0(stem, " (", label, ")")
}

ml_assoc_apply_slot_to_path <- function(path, label) {
  if (!nzchar(as.character(label %||% "")[1L])) return(path)
  d <- dirname(path)
  file.path(d, ml_assoc_stem_with_slot(basename(path), label))
}

.ml_assoc_suffix_one_file <- function(fp, label, root_output_dir = NULL) {
  if (!file.exists(fp)) return(invisible(NULL))
  bn <- basename(fp)
  if (.ml_assoc_file_has_slot_label(bn)) return(invisible(NULL))
  ext <- tools::file_ext(bn)
  if (!nzchar(ext)) return(invisible(NULL))
  base <- sub(paste0("\\.", ext, "$"), "", bn, ignore.case = TRUE)
  new_bn <- paste0(base, " (", label, ").", ext)
  new_fp <- file.path(dirname(fp), new_bn)
  if (identical(normalizePath(fp, mustWork = FALSE), normalizePath(new_fp, mustWork = FALSE))) {
    return(invisible(NULL))
  }
  if (file.exists(new_fp)) {
    # 已有带槽后缀文件时删除无后缀副本（防止 root/step 双份）
    try(unlink(fp), silent = TRUE)
    if (!is.null(root_output_dir) && nzchar(root_output_dir)) {
      for (sub in c("Figures", "Tables")) {
        bare <- file.path(root_output_dir, sub, bn)
        if (file.exists(bare)) try(unlink(bare), silent = TRUE)
      }
    }
    return(invisible(NULL))
  }
  tryCatch(
    file.rename(fp, new_fp),
    error = function(e) {
      cli::cli_alert_warning("ml_assoc: rename {bn} -> {new_bn}: {conditionMessage(e)}")
    }
  )
  # 同步根目录镜像：无后缀 → 带后缀；避免无后缀残留
  if (!is.null(root_output_dir) && nzchar(root_output_dir)) {
    for (sub in c("Figures", "Tables")) {
      bare <- file.path(root_output_dir, sub, bn)
      labeled <- file.path(root_output_dir, sub, new_bn)
      if (file.exists(bare)) {
        if (file.exists(labeled)) {
          try(unlink(bare), silent = TRUE)
        } else {
          tryCatch(
            file.rename(bare, labeled),
            error = function(e) {
              try(file.copy(bare, labeled, overwrite = TRUE), silent = TRUE)
              try(unlink(bare), silent = TRUE)
            }
          )
        }
      }
    }
  }
  invisible(NULL)
}

ml_assoc_suffix_recent_outputs <- function(ctx, label, since = Sys.time() - 120) {
  if (!nzchar(label)) return(invisible(NULL))
  since <- as.POSIXct(since)[1L]
  root_out <- ctx$root_output_dir %||% NULL
  for (dir_key in c("output_dir_figures", "output_dir_tables")) {
    d <- ctx[[dir_key]] %||% NULL
    if (is.null(d) || !dir.exists(d)) next
    files <- list.files(d, full.names = TRUE, recursive = TRUE, no.. = TRUE)
    for (fp in files) {
      info <- tryCatch(file.info(fp), error = function(e) NULL)
      if (is.null(info) || !isTRUE(info$isdir)) {
        if (is.null(info) || is.na(info$mtime) || info$mtime < since) next
        .ml_assoc_suffix_one_file(fp, label, root_output_dir = root_out)
      }
    }
  }
  # 根目录仍可能残留下无槽标签的陈旧副本（镜像时戳更早）
  if (!is.null(root_out) && dir.exists(root_out)) {
    for (sub in c("Figures", "Tables")) {
      rd <- file.path(root_out, sub)
      if (!dir.exists(rd)) next
      for (fp in list.files(rd, full.names = TRUE, no.. = TRUE)) {
        bn <- basename(fp)
        if (.ml_assoc_file_has_slot_label(bn)) next
        # 若同基名已有 (Train)/(Validation) 版，删无后缀（避免正则转义 {} 等字符）
        base <- tools::file_path_sans_ext(bn)
        ext <- tools::file_ext(bn)
        has_labeled <- FALSE
        for (lab in c("Train", "Validation")) {
          cand <- file.path(
            rd,
            if (nzchar(ext)) paste0(base, " (", lab, ").", ext) else paste0(base, " (", lab, ")")
          )
          if (file.exists(cand)) {
            has_labeled <- TRUE
            break
          }
        }
        if (isTRUE(has_labeled)) try(unlink(fp), silent = TRUE)
      }
    }
  }
  invisible(NULL)
}

#' 强制 Model1 严格为 Model2 真子集（至少差 1 个协变量）
ml_assoc_ensure_m1_ne_m2 <- function(m1, m2) {
  m1 <- unique(as.character(m1[nzchar(as.character(m1))]))
  m2 <- unique(as.character(m2[nzchar(as.character(m2))]))
  if (!length(m2)) return(list(M1 = m1, M2 = m2))
  if (!length(m1)) {
    n1 <- max(1L, min(length(m2) - 1L, max(2L, as.integer(ceiling(length(m2) / 3)))))
    if (length(m2) < 2L) n1 <- 1L
    m1 <- m2[seq_len(min(n1, max(1L, length(m2) - 1L)))]
  }
  if (!length(setdiff(m2, m1))) {
    if (length(m2) < 2L) {
      cli::cli_alert_warning(
        "ml_assoc: 仅 1 个协变量无法拆出不同的 Model1/Model2，保持原状"
      )
      return(list(M1 = m1, M2 = m2))
    }
    # Model2 保留全集，Model1 去掉末尾至少 1 个
    m1 <- m2[seq_len(length(m2) - 1L)]
    cli::cli_alert_info(
      "ml_assoc: Model1 须≠Model2 → M1={paste(m1, collapse=', ')}; M2 exclusive+={m2[length(m2)]}"
    )
  }
  list(M1 = m1, M2 = m2)
}

block_ml_assoc_bundle <- function(ctx, ...) {
  .ml_assoc_ensure_helpers(ctx)
  mode <- ctx$config$ml_batch$assoc_blocks %||% "full"
  if (!identical(mode, "full")) return(ctx)
  slots <- ml_assoc_resolve_slots(ctx)
  base_blocks <- if (exists("ml_dual_primary_ml_assoc_blocks", mode = "function")) {
    ml_dual_primary_ml_assoc_blocks(ctx$config)
  } else {
    blocks <- c(
      "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
      "rcs_incidence",
      "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs"
    )
    if (ml_assoc_has_time(ctx)) blocks <- c(blocks, "cox_binary", "km_binary")
    blocks
  }
  ## 允许 config$logistic_tertile/binary$enable=FALSE 或 assoc_schemes 只留 quartile
  schemes <- tolower(as.character(ctx$config$ml_batch$assoc_schemes %||% character(0)))
  schemes <- schemes[nzchar(schemes)]
  if (length(schemes)) {
    keep_pat <- paste0("(", paste(schemes, collapse = "|"), ")")
    base_blocks <- base_blocks[
      !grepl("logistic_(quartile|tertile|binary)", base_blocks) |
        grepl(paste0("logistic_", keep_pat), base_blocks)
    ]
  }
  for (sch in c("quartile", "tertile", "binary")) {
    cfg_nm <- paste0("logistic_", sch)
    if (isFALSE((ctx$config[[cfg_nm]] %||% list())$enable %||% TRUE)) {
      base_blocks <- base_blocks[!grepl(paste0("logistic_", sch), base_blocks)]
    }
  }
  root <- ctx$config$project$root %||% getwd()

  # 全局保证 M1 ≠ 严格子集关系：至少有 1 个仅 Model2 拥有
  .as_chr_vars <- function(x) {
    if (is.null(x)) return(character(0))
    if (is.data.frame(x)) {
      if ("Variable" %in% names(x)) return(as.character(x$Variable))
      if ("variable" %in% names(x)) return(as.character(x$variable))
      return(character(0))
    }
    as.character(unlist(x, use.names = FALSE))
  }
  m1_all <- .as_chr_vars(ctx$results$Model1Factors)
  m2_all <- .as_chr_vars(
    ctx$results$Model2Factors %||%
      ctx$results$vif_screen_pass %||%
      ctx$results$logistic_model2_factors
  )
  if (!length(m2_all) && length(m1_all)) m2_all <- m1_all
  sm <- ml_assoc_ensure_m1_ne_m2(m1_all, m2_all)
  if (length(sm$M1)) ctx$results$Model1Factors <- sm$M1
  if (length(sm$M2)) ctx$results$Model2Factors <- sm$M2

  for (i in seq_len(nrow(slots))) {
    slot <- slots$slot[[i]]
    label <- slots$label[[i]]
    for (bn in base_blocks) {
      if (exists("pipeline_source_block", mode = "function")) {
        try(pipeline_source_block(root, bn), silent = TRUE)
      }
      if (bn %in% c("rcs_incidence", "rcs_prognosis", "cox_quartile", "cox_tertile", "cox_binary",
                    "km_binary",
                    "logistic_quartile_glm", "logistic_tertile_glm", "logistic_binary_glm",
                    "logistic_quartile_glm_rcs", "logistic_tertile_glm_rcs", "logistic_binary_glm_rcs")) {
        # Ensure Cox/KM/RCS use the batch index (e.g. RAR), not a stale preset
        ix <- ctx$config$logistic$index_var %||%
          ctx$config$incidence$index_var %||%
          (ctx$config$prediction$index_vars %||% character(0))[1L]
        if (nzchar(as.character(ix)[1L])) {
          ctx$config$survival <- modifyList(
            ctx$config$survival %||% list(), list(index_var = as.character(ix)[1L])
          )
          if (!is.null(ctx$config[[bn]])) {
            ctx$config[[bn]]$index_var <- as.character(ix)[1L]
          } else if (bn %in% c("cox_quartile", "cox_tertile", "cox_binary", "km_binary", "rcs_incidence", "rcs_prognosis")) {
            ctx$config[[bn]] <- list(index_var = as.character(ix)[1L])
          }
        }
        fr <- ml_assoc_frame_for_slot(ctx, slot)
        if (is.data.frame(fr)) {
          ctx$results$Model1Factors <- intersect(
            as.character(ctx$results$Model1Factors %||% character(0)), names(fr)
          )
          ctx$results$Model2Factors <- intersect(
            as.character(ctx$results$Model2Factors %||% character(0)), names(fr)
          )
          sm2 <- ml_assoc_ensure_m1_ne_m2(
            ctx$results$Model1Factors, ctx$results$Model2Factors
          )
          ctx$results$Model1Factors <- sm2$M1
          ctx$results$Model2Factors <- sm2$M2
        }
      }
      t0 <- Sys.time()
      ctx <- ml_assoc_run_on_slot(ctx, slot, label, bn)
      ml_assoc_suffix_recent_outputs(ctx, label, since = t0)
    }
  }
  ctx
}

register_block(
  "ml_assoc_bundle",
  block_ml_assoc_bundle,
  "关联分析：logistic/RCS/(Cox/KM) 按数据槽循环"
)
