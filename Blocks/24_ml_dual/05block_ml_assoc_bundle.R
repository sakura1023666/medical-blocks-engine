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
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- ctx$config$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", er)) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  root <- normalizePath(er, winslash = "/", mustWork = FALSE)
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

.ml_assoc_joint_group_prognosis <- function(ctx, slot = "imputed", label = "") {
  cfg <- ctx$config
  jcfg <- cfg$ml_joint_group %||% list()
  if (isFALSE(jcfg$enable %||% TRUE)) return(ctx)
  indices <- unique(as.character(
    (cfg$analysis_exclusion %||% list())$current_index_vars %||%
      (cfg$prediction %||% list())$index_vars %||% character(0)
  ))
  indices <- indices[nzchar(indices)]
  if (length(indices) != 2L) return(ctx)
  dat <- ml_assoc_frame_for_slot(ctx, slot)
  tv <- as.character((cfg$survival %||% list())$time_var %||% "")[1L]
  ev <- as.character((cfg$survival %||% list())$event_var %||% "")[1L]
  need <- c(indices, tv, ev)
  if (!is.data.frame(dat) || !all(need %in% names(dat))) {
    cli::cli_alert_warning(
      "ml_joint_group: 缺少 {.field {paste(setdiff(need, names(dat)), collapse=', ')}}，跳过"
    )
    return(ctx)
  }

  a <- suppressWarnings(as.numeric(dat[[indices[[1L]]]]))
  b <- suppressWarnings(as.numeric(dat[[indices[[2L]]]]))
  time <- suppressWarnings(as.numeric(dat[[tv]]))
  event <- pipeline_outcome_as_01(dat[[ev]], cfg = cfg)
  cut_a <- stats::median(a[is.finite(a)], na.rm = TRUE)
  cut_b <- stats::median(b[is.finite(b)], na.rm = TRUE)
  grp <- ifelse(
    a < cut_a & b < cut_b, "Group 1: low/low",
    ifelse(a >= cut_a & b < cut_b, "Group 2: high/low",
      ifelse(a < cut_a & b >= cut_b, "Group 3: low/high", "Group 4: high/high")
    )
  )
  grp[!is.finite(a) | !is.finite(b)] <- NA_character_
  dd <- dat
  dd$.joint_time <- time
  dd$.joint_event <- event
  dd$.joint_group <- factor(
    grp,
    levels = c(
      "Group 1: low/low", "Group 2: high/low",
      "Group 3: low/high", "Group 4: high/high"
    )
  )
  dd <- dd[
    is.finite(dd$.joint_time) & !is.na(dd$.joint_event) & !is.na(dd$.joint_group),
    , drop = FALSE
  ]
  if (nrow(dd) < 50L || length(unique(dd$.joint_group)) < 4L) {
    cli::cli_alert_warning("ml_joint_group: 有效样本或四组不足，跳过")
    return(ctx)
  }

  m1 <- intersect(as.character(ctx$results$Model1Factors %||% character(0)), names(dd))
  m2 <- intersect(as.character(ctx$results$Model2Factors %||% character(0)), names(dd))
  models <- list(Unadjusted = character(0), `Model 1` = m1, `Model 2` = m2)
  rows <- list()
  for (mn in names(models)) {
    rhs <- c(".joint_group", models[[mn]])
    form <- stats::as.formula(paste(
      "survival::Surv(.joint_time, .joint_event) ~",
      paste(sprintf("`%s`", rhs), collapse = " + ")
    ))
    fit <- tryCatch(survival::coxph(form, data = dd, x = TRUE), error = function(e) NULL)
    if (is.null(fit)) next
    sm <- summary(fit)$coefficients
    ci <- summary(fit)$conf.int
    rn <- grep("^\\.joint_group", rownames(sm))
    if (!length(rn)) next
    for (r in rn) {
      lev <- sub("^\\.joint_group", "", rownames(sm)[r])
      rows[[length(rows) + 1L]] <- data.frame(
        Model = mn,
        Joint_group = lev,
        `HR (95% CI)` = sprintf(
          "%.3f (%.3f, %.3f)", ci[r, "exp(coef)"], ci[r, "lower .95"], ci[r, "upper .95"]
        ),
        P = if (sm[r, "Pr(>|z|)"] < 0.001) "<0.001" else sprintf("%.3f", sm[r, "Pr(>|z|)"]),
        check.names = FALSE
      )
    }
  }
  tab <- if (length(rows)) do.call(rbind, rows) else NULL
  if (!is.null(tab)) {
    fp <- file.path(
      ctx$output_dir_tables,
      sprintf(
        "Table 2. Joint association of %s and %s with 28-day mortality.xlsx",
        indices[[1L]], indices[[2L]]
      )
    )
    export_sci_table(
      tab, fp,
      title = sprintf(
        "Table 2. Joint association of %s and %s with 28-day mortality",
        indices[[1L]], indices[[2L]]
      ),
      table_footnotes = sprintf(
        "Group 1 is the reference. Median cutoffs: %s=%.4f; %s=%.4f.",
        indices[[1L]], cut_a, indices[[2L]], cut_b
      )
    )
  }

  sf <- survival::survfit(
    survival::Surv(.joint_time, .joint_event) ~ .joint_group,
    data = dd
  )
  ss <- summary(sf)
  pd <- data.frame(
    time = ss$time, survival = ss$surv,
    group = sub("^\\.joint_group=", "", as.character(ss$strata)),
    stringsAsFactors = FALSE
  )
  lr <- survival::survdiff(
    survival::Surv(.joint_time, .joint_event) ~ .joint_group,
    data = dd
  )
  p_lr <- stats::pchisq(lr$chisq, df = length(lr$n) - 1L, lower.tail = FALSE)
  gp <- ggplot2::ggplot(
    pd, ggplot2::aes(x = .data$time, y = .data$survival, colour = .data$group)
  ) +
    ggplot2::geom_step(linewidth = 0.8) +
    ggplot2::theme_bw() +
    ggplot2::labs(
      x = "Time (days)", y = "Survival probability", colour = "Joint group",
      subtitle = paste0("Log-rank P ", if (p_lr < 0.001) "<0.001" else sprintf("= %.3f", p_lr))
    )
  ctx <- save_figure(
    ctx,
    sprintf("Figure 2. Kaplan-Meier curves of joint %s and %s groups.pdf", indices[[1L]], indices[[2L]]),
    function() gp, width = 8, height = 6
  )
  ctx$results$ml_joint_group <- list(
    indices = indices, cutoffs = setNames(c(cut_a, cut_b), indices),
    table = tab, logrank_p = p_lr
  )
  cli::cli_alert_success(
    "ml_joint_group: {indices[[1L]]}+{indices[[2L]]} Group1-4 Cox/KM 完成"
  )
  ctx
}

.ml_assoc_literature_roc_predictors <- function(a, b, joint_num, score_values,
                                                indices, score) {
  out <- list(a, b, joint_num, score_values)
  names(out) <- c(indices[[1L]], indices[[2L]], "Joint Group1-4", score)
  out
}

.ml_assoc_literature_extra_figures <- function(ctx, slot = "imputed") {
  cfg <- ctx$config
  ecfg <- cfg$ml_literature_extras %||% list()
  if (isFALSE(ecfg$enable %||% FALSE)) return(ctx)
  indices <- unique(as.character(
    (cfg$analysis_exclusion %||% list())$current_index_vars %||% character(0)
  ))
  indices <- indices[nzchar(indices)]
  if (length(indices) != 2L) return(ctx)
  dat <- ml_assoc_frame_for_slot(ctx, slot)
  tv <- as.character((cfg$survival %||% list())$time_var %||% "")[1L]
  ev <- as.character((cfg$survival %||% list())$event_var %||% "")[1L]
  score <- as.character(ecfg$comparator_score %||% "APSIII")[1L]
  subgroup <- as.character(ecfg$landmark_subgroup %||% "Diabetes")[1L]
  day <- as.numeric(ecfg$landmark_day %||% 7)[1L]
  need <- c(indices, tv, ev, score, subgroup)
  if (!is.data.frame(dat) || !all(need %in% names(dat))) {
    cli::cli_alert_warning(
      "ml_literature_extras: 缺少 {.field {paste(setdiff(need, names(dat)), collapse=', ')}}，跳过"
    )
    return(ctx)
  }
  a <- suppressWarnings(as.numeric(dat[[indices[[1L]]]]))
  b <- suppressWarnings(as.numeric(dat[[indices[[2L]]]]))
  y <- pipeline_outcome_as_01(dat[[ev]], cfg = cfg)
  time <- suppressWarnings(as.numeric(dat[[tv]]))
  cut_a <- stats::median(a[is.finite(a)], na.rm = TRUE)
  cut_b <- stats::median(b[is.finite(b)], na.rm = TRUE)
  joint_num <- ifelse(a < cut_a & b < cut_b, 1,
    ifelse(a >= cut_a & b < cut_b, 2, ifelse(a < cut_a & b >= cut_b, 3, 4))
  )
  joint_num[!is.finite(a) | !is.finite(b)] <- NA_real_

  if (requireNamespace("pROC", quietly = TRUE)) {
    preds <- .ml_assoc_literature_roc_predictors(
      a, b, joint_num,
      suppressWarnings(as.numeric(dat[[score]])),
      indices, score
    )
    roc_rows <- list()
    auc_rows <- list()
    for (nm in names(preds)) {
      x <- preds[[nm]]
      ok <- is.finite(x) & !is.na(y)
      if (sum(ok) < 50L || length(unique(y[ok])) < 2L) next
      rr <- tryCatch(
        pROC::roc(y[ok], x[ok], quiet = TRUE, direction = "<"),
        error = function(e) NULL
      )
      if (is.null(rr)) next
      cc <- pROC::coords(
        rr, x = "all", ret = c("specificity", "sensitivity"),
        transpose = FALSE
      )
      roc_rows[[nm]] <- data.frame(
        FPR = 1 - cc$specificity, TPR = cc$sensitivity, Model = nm
      )
      ci <- as.numeric(pROC::ci.auc(rr))
      auc_rows[[nm]] <- data.frame(
        Predictor = nm,
        `AUC (95% CI)` = sprintf("%.3f (%.3f, %.3f)", as.numeric(pROC::auc(rr)), ci[[1L]], ci[[3L]]),
        N = sum(ok),
        check.names = FALSE
      )
    }
    if (length(roc_rows)) {
      rd <- do.call(rbind, roc_rows)
      ap <- do.call(rbind, auc_rows)
      labs <- setNames(
        paste0(ap$Predictor, " (AUC ", sub(" .*", "", ap$`AUC (95% CI)`), ")"),
        ap$Predictor
      )
      rd$Model <- factor(rd$Model, levels = ap$Predictor, labels = labs[ap$Predictor])
      gp <- ggplot2::ggplot(
        rd, ggplot2::aes(x = .data$FPR, y = .data$TPR, colour = .data$Model)
      ) +
        ggplot2::geom_abline(slope = 1, intercept = 0, linetype = 2, colour = "grey60") +
        ggplot2::geom_line(linewidth = 0.9) +
        ggplot2::coord_equal() +
        ggplot2::theme_bw() +
        ggplot2::labs(
          x = "1 - Specificity", y = "Sensitivity", colour = NULL,
          title = sprintf("%s + %s versus %s", indices[[1L]], indices[[2L]], score)
        )
      ctx <- save_figure(
        ctx,
        sprintf("Figure S2. ROC comparison of joint indices and %s.pdf", score),
        function() gp, width = 7, height = 6
      )
      export_sci_table(
        ap,
        file.path(ctx$output_dir_tables, sprintf("Table S. ROC comparison with %s.xlsx", score)),
        title = sprintf("ROC comparison of %s, %s, their joint group, and %s", indices[[1L]], indices[[2L]], score)
      )
    }
  }

  lm <- data.frame(
    residual_time = time - day,
    event = y,
    joint_group = factor(
      joint_num, levels = 1:4,
      labels = c("Group 1: low/low", "Group 2: high/low", "Group 3: low/high", "Group 4: high/high")
    ),
    baseline = as.character(dat[[subgroup]]),
    stringsAsFactors = FALSE
  )
  lm <- lm[
    is.finite(lm$residual_time) & lm$residual_time > 0 &
      !is.na(lm$event) & !is.na(lm$joint_group) & nzchar(lm$baseline),
    , drop = FALSE
  ]
  curves <- list()
  p_labels <- list()
  for (lev in unique(lm$baseline)) {
    dl <- lm[lm$baseline == lev, , drop = FALSE]
    if (nrow(dl) < 30L || length(unique(dl$joint_group)) < 2L) next
    sf <- survival::survfit(
      survival::Surv(residual_time, event) ~ joint_group, data = dl
    )
    ss <- summary(sf)
    curves[[lev]] <- data.frame(
      time = ss$time + day, survival = ss$surv,
      group = sub("^joint_group=", "", as.character(ss$strata)),
      baseline = lev, stringsAsFactors = FALSE
    )
    lr <- survival::survdiff(
      survival::Surv(residual_time, event) ~ joint_group, data = dl
    )
    pp <- stats::pchisq(lr$chisq, df = length(lr$n) - 1L, lower.tail = FALSE)
    p_labels[[lev]] <- data.frame(
      baseline = lev, x = day, y = 0.05,
      label = paste0("Log-rank P ", if (pp < 0.001) "<0.001" else sprintf("= %.3f", pp))
    )
  }
  if (length(curves)) {
    lcd <- do.call(rbind, curves)
    lpd <- do.call(rbind, p_labels)
    gl <- ggplot2::ggplot(
      lcd, ggplot2::aes(x = .data$time, y = .data$survival, colour = .data$group)
    ) +
      ggplot2::geom_step(linewidth = 0.8) +
      ggplot2::geom_text(
        data = lpd,
        ggplot2::aes(x = .data$x, y = .data$y, label = .data$label),
        inherit.aes = FALSE, hjust = 0
      ) +
      ggplot2::facet_wrap(~baseline) +
      ggplot2::theme_bw() +
      ggplot2::labs(
        x = "Time since ICU admission (days)", y = "Conditional survival probability",
        colour = "Joint group",
        title = sprintf("Day-%s landmark analysis stratified by %s", day, subgroup)
      )
    ctx <- save_figure(
      ctx,
      sprintf("Figure S3. Day %s landmark analysis by %s.pdf", day, subgroup),
      function() gl, width = 10, height = 6
    )
  }
  ctx$results$ml_literature_extras <- list(
    landmark_day = day, landmark_subgroup = subgroup, comparator_score = score
  )
  ctx
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
  if (exists("pipeline_ctx_index_is_categorical", mode = "function") &&
      isTRUE(pipeline_ctx_index_is_categorical(ctx))) {
    base_blocks <- base_blocks[
      !grepl(
        "quartile|tertile|quintile|sextile|_rcs$|rcs_incidence|rcs_prognosis",
        base_blocks
      )
    ]
    cli::cli_alert_info(
      "分类暴露：仅回归变量本身，跳过分位 / RCS / continuous"
    )
  }
  root <- ctx$config$project$root %||% getwd()
  pipe_gate <- list(logistic_gate = list(enable = TRUE))

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
      if (exists("pipeline_logistic_gate_should_skip", mode = "function") &&
          pipeline_logistic_gate_should_skip(bn, ctx, pipe_gate)) {
        cli::cli_alert_info(
          "logistic_gate 跳过 {.field {bn}}（分支: {ctx$results$logistic_branch %||% '?'}）"
        )
        next
      }
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
    ctx <- .ml_assoc_joint_group_prognosis(ctx, slot = slot, label = label)
    ctx <- .ml_assoc_literature_extra_figures(ctx, slot = slot)
  }
  ctx
}

register_block(
  "ml_assoc_bundle",
  block_ml_assoc_bundle,
  "关联分析：logistic/RCS/(Cox/KM) 按数据槽循环"
)
