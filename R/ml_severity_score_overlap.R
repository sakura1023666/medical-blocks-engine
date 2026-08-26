###############################################################################
#  ml_severity_score_overlap.R — ICU 严重度评分成分重叠去重（ML 特征用）
#
#  APSIII / SAPSII / OASIS / SOFA 均含 GCS 与多项生命体征/实验室；
#  同时进 ML 会造成成分双重计入。规则：同一家族最多保留 1 个评分。
#
#  定义来源（MIMIC 常用）：
#    APSIII  — APACHE III：GCS + 生命体征 + 尿量 + 多项实验室 + 慢性健康
#    SAPSII  — GCS + HR/SBP/temp + 氧合 + 实验室 + 入院类型 + 合并症
#    OASIS   — Age + GCS + HR/MAP/RR/temp + 尿量 + 通气 + 术前 LOS
#    SOFA    — 呼吸/凝血/肝/循环/CNS(GCS)/肾 六系统
#    GCS     — 上述评分的共同成分；单独与任一评分并存即重叠
#
#  去重后必须回写 feature_selection_final.rds/.txt（见
#  ml_rewrite_feature_selection_final_artifacts），否则磁盘清单仍含被剔变量，
#  易被误判为「最终 ML 含 GCS 且 Cox Model2 也含 GCS」铁律违规。
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

#' ICU 严重度评分家族（有成分重叠，不可同时进 ML）
ml_overlapping_severity_scores <- function() {
  c("APSIII", "SAPSII", "OASIS", "SOFA", "GCS")
}

#' 保留优先级：越综合越优先（可被 config 覆盖）
ml_severity_score_keep_priority <- function() {
  c("APSIII", "SAPSII", "OASIS", "SOFA", "GCS")
}

#' 从特征集中去掉重叠评分，最多保留 1 个
#'
#' @param feats 字符向量
#' @param keep_priority 优先级；NULL 用默认
#' @param force_keep 始终保留（如暴露指标 AnionGap）
#' @return list(kept, dropped, kept_score)
ml_dedupe_overlapping_severity_scores <- function(feats,
                                                  keep_priority = NULL,
                                                  force_keep = character()) {
  feats <- unique(as.character(feats[nzchar(as.character(feats))]))
  force_keep <- unique(as.character(force_keep[nzchar(as.character(force_keep))]))
  family <- ml_overlapping_severity_scores()
  pri <- as.character(keep_priority %||% ml_severity_score_keep_priority())
  pri <- unique(c(pri, family))

  in_fam <- intersect(feats, family)
  if (length(in_fam) <= 1L) {
    return(list(kept = feats, dropped = character(0), kept_score = if (length(in_fam)) in_fam else NA_character_))
  }
  # 按优先级选一个
  keep_one <- NA_character_
  for (s in pri) {
    if (s %in% in_fam) {
      keep_one <- s
      break
    }
  }
  if (!is.finite(match(keep_one, in_fam))) keep_one <- in_fam[[1L]]
  drop <- setdiff(in_fam, keep_one)
  kept <- unique(c(intersect(feats, force_keep), setdiff(feats, drop)))
  # 保持原顺序
  kept <- feats[feats %in% kept]
  list(kept = kept, dropped = drop, kept_score = keep_one)
}

#' 严重度去重后，把磁盘上的 feature_selection_final 产物改写成真正最终 ML 集
#'
#' consensus/venn 在去重前已 saveRDS；若不回写，下游探测 RDS / 人工审阅会仍见 GCS，
#' 造成「Model2 含 GCS 且最终特征也含 GCS」的假铁律违规。
ml_rewrite_feature_selection_final_artifacts <- function(ctx, feats = NULL) {
  feats <- as.character(feats %||% ctx$results$feature_selection_final %||% character(0))
  feats <- unique(feats[nzchar(feats)])
  if (!length(feats)) return(invisible(ctx))

  ro <- as.character(ctx$root_output_dir %||% "")[1L]
  od <- as.character((ctx$config$project %||% list())$output_dir %||% "")[1L]
  out_dir <- as.character(ctx$output_dir %||% "")[1L]
  ck <- trimws(as.character((ctx$config$checkpoint %||% list())$dir %||% "checkpoints")[1L])
  ck_dir <- if (grepl("^(/|[A-Za-z]:[/\\\\])", ck)) ck else file.path(getwd(), ck)

  cands <- unique(c(
    if (nzchar(ro)) file.path(ro, "feature_selection_final.rds") else character(0),
    if (nzchar(od)) file.path(od, "feature_selection_final.rds") else character(0),
    if (nzchar(out_dir)) file.path(out_dir, "feature_selection_final.rds") else character(0),
    if (dir.exists(ck_dir)) file.path(ck_dir, "feature_selection_final.rds") else character(0)
  ))
  roots <- unique(c(ro, od)[nzchar(c(ro, od))])
  for (rt in roots) {
    if (!dir.exists(rt)) next
    more <- list.files(
      rt, pattern = "^feature_selection_final\\.rds$",
      recursive = TRUE, full.names = TRUE
    )
    cands <- unique(c(cands, more))
  }

  n_ok <- 0L
  for (p in cands) {
    if (!isTRUE(file.exists(p))) next
    obj <- tryCatch(readRDS(p), error = function(e) NULL)
    if (is.null(obj)) next
    if (is.list(obj) && !is.null(obj$features)) {
      obj$features <- feats
      if (!is.null(obj$feature_selection_final)) obj$feature_selection_final <- feats
      obj$severity_score_deduped_at <- Sys.time()
      obj$ml_severity_scores_dropped <- ctx$results$ml_severity_scores_dropped
      obj$ml_severity_score_kept <- ctx$results$ml_severity_score_kept
      ok <- tryCatch({ saveRDS(obj, p); TRUE }, error = function(e) FALSE)
    } else if (is.character(obj) || is.factor(obj)) {
      ok <- tryCatch({ saveRDS(as.character(feats), p); TRUE }, error = function(e) FALSE)
    } else {
      next
    }
    if (!isTRUE(ok)) next
    n_ok <- n_ok + 1L
    txt <- sub("\\.rds$", ".txt", p, ignore.case = TRUE)
    tryCatch(writeLines(feats, txt), error = function(e) invisible(NULL))
    # consensus 旁路 D08 csv（若存在）
    d08 <- file.path(dirname(dirname(p)), "D08_FeatureSelection_Final.csv")
    if (file.exists(d08) || identical(basename(dirname(p)), "Data")) {
      d08b <- file.path(dirname(dirname(p)), "D08_FeatureSelection_Final.csv")
      tryCatch(
        utils::write.csv(
          data.frame(feature = feats, stringsAsFactors = FALSE),
          d08b, row.names = FALSE
        ),
        error = function(e) invisible(NULL)
      )
    }
  }
  if (n_ok > 0L && requireNamespace("cli", quietly = TRUE)) {
    cli::cli_alert_info(
      "严重度去重后已回写 feature_selection_final 产物 {n_ok} 处（n={length(feats)}）"
    )
  }
  invisible(ctx)
}

#' 应用到 ctx$results 的 ML 特征键
ml_apply_severity_score_dedupe_to_ctx <- function(ctx, force_keep = character()) {
  cfg <- ctx$config %||% list()
  fs <- cfg$feature_selection %||% list()
  ms <- cfg$ml_small_sample %||% list()
  enable <- isTRUE(fs$dedupe_overlapping_severity_scores %||%
                     ms$dedupe_overlapping_severity_scores %||% TRUE)
  if (!enable) return(ctx)

  pri <- fs$severity_score_keep_priority %||% ms$severity_score_keep_priority %||% NULL
  if (!length(force_keep)) {
    if (exists("pipeline_index_exposure_var", mode = "function")) {
      force_keep <- as.character(pipeline_index_exposure_var(cfg) %||% character(0))
    }
    force_keep <- unique(c(
      force_keep,
      as.character((cfg$prediction %||% list())$index_vars %||% character(0)),
      as.character((cfg$ml_batch %||% list())$current_index %||% character(0))
    ))
    force_keep <- force_keep[nzchar(force_keep)]
  }

  keys <- c(
    "feature_selection_final", "ml_feature_names",
    "feature_selection_venn_center", "Model2Factors"
  )
  pre <- as.character(ctx$results$feature_selection_final %||% character(0))
  any_drop <- character(0)
  kept_score <- NA_character_
  for (k in keys) {
    v <- as.character(ctx$results[[k]] %||% character(0))
    if (!length(v)) next
    # Model2Factors 是协变量池，不去掉评分（Cox Model2 可能需要）；只处理 ML 特征键
    if (identical(k, "Model2Factors")) next
    res <- ml_dedupe_overlapping_severity_scores(v, keep_priority = pri, force_keep = force_keep)
    if (length(res$dropped)) {
      ctx$results[[k]] <- res$kept
      any_drop <- unique(c(any_drop, res$dropped))
      kept_score <- res$kept_score
    }
  }
  if (length(any_drop)) {
    if (length(pre)) {
      ctx$results$feature_selection_final_pre_severity_dedupe <- pre
    }
    ctx$results$ml_severity_scores_dropped <- any_drop
    ctx$results$ml_severity_score_kept <- kept_score
    if (requireNamespace("cli", quietly = TRUE)) {
      cli::cli_alert_warning(
        "ML 特征去重叠评分：保留 {kept_score}，剔除 {paste(any_drop, collapse = ', ')}（APSIII/SAPSII/OASIS/SOFA/GCS 成分重叠）"
      )
    }
    # 回写磁盘，避免探测 RDS / 审阅清单仍含被剔除变量
    ctx <- ml_rewrite_feature_selection_final_artifacts(ctx)
  }
  ctx
}
