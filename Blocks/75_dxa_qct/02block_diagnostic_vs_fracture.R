###############################################################################
#  diagnostic_vs_fracture — 椎体骨折金标准下 DXA vs QCT 诊断效能 + 分层
#
#  register_block: "diagnostic_vs_fracture"
#  典型流水线: dxa_qct_agreement 之后；modality_discordance_profile 之前
#  公共 helper: Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R
#
#  # ── 配置 config$diagnostic_vs_fracture ────────────────────────────────────
#  enable              = TRUE
#  fracture            = "Vertebral_fracture"   # 金标准 0/1
#  qct_cat / dxa_cat   = "QCT_cat" / "DXA_cat_min"  # 或直接给 qct_op / dxa_op
#  qct_continuous      = "QCT_vBMD"
#  dxa_continuous      = "DXA_T_min"
#  op_level            = 2L                     # cat==op_level → OP 阳性
#  strata              = c("Nathan_bin","AAC","BMI_bin")
#  strata_supplemental = c("Age_bin")           # Figure S3
#  export_roc          = TRUE                   # Figure 4
#  export_sens_bar     = TRUE                   # Figure 5
#  roc_direction       = ">"                    # pROC: controls > cases（BMD/T 越低越病）
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: ctx$data$imputed %||% cleaned
#  写: ctx$results$diagnostic_vs_fracture
#  表: Table 3 overall；Table 4 stratified
#  图: Figure 4 ROC；Figure 5 分层 Sens；可选 Figure S3 Age
###############################################################################

.dvf75_source_common <- function(ctx = NULL) {
  if (exists(".osteo75_diag_metrics", mode = "function") &&
      exists(".osteo75_auc_continuous", mode = "function") &&
      exists(".osteo75_pick_col", mode = "function")) {
    return(invisible(TRUE))
  }
  roots <- character(0)
  if (!is.null(ctx) && !is.null(ctx$config$project$root)) {
    roots <- c(roots, as.character(ctx$config$project$root)[1L])
  }
  env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (nzchar(env_root)) roots <- c(roots, env_root)
  roots <- c(roots, getwd())
  roots <- unique(roots[nzchar(roots)])
  for (r in roots) {
    p <- file.path(r, "Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R")
    if (file.exists(p)) {
      source(p, local = FALSE)
      return(invisible(TRUE))
    }
  }
  stop("Cannot locate 00osteo_dxa_qct_common.R", call. = FALSE)
}

.dvf75_resolve_op <- function(data, cfg, modality = c("qct", "dxa")) {
  modality <- match.arg(modality)
  if (modality == "qct") {
    if (!is.null(cfg$qct_op) && cfg$qct_op %in% names(data)) {
      return(as.integer(data[[cfg$qct_op]] != 0L))
    }
    if ("QCT_OP" %in% names(data)) {
      return(as.integer(data[["QCT_OP"]] != 0L))
    }
    cat_nm <- as.character(
      cfg$qct_cat %||% .osteo75_pick_col(data, c("QCT_cat", "qct_cat"))
    )[1L]
  } else {
    if (!is.null(cfg$dxa_op) && cfg$dxa_op %in% names(data)) {
      return(as.integer(data[[cfg$dxa_op]] != 0L))
    }
    if ("DXA_OP" %in% names(data)) {
      return(as.integer(data[["DXA_OP"]] != 0L))
    }
    cat_nm <- as.character(
      cfg$dxa_cat %||% .osteo75_pick_col(data, c("DXA_cat_min", "DXA_cat", "dxa_cat"))
    )[1L]
  }
  op_level <- as.integer(cfg$op_level %||% 2L)[1L]
  cat_v <- suppressWarnings(as.integer(data[[cat_nm]]))
  as.integer(cat_v == op_level)
}

.dvf75_one_modality <- function(truth, pred01, score, direction = "<") {
  m <- .osteo75_diag_metrics(truth, pred01)
  auc <- .osteo75_auc_continuous(truth, score, direction = direction)
  list(
    sens = m$sens,
    spec = m$spec,
    ppv = m$ppv,
    npv = m$npv,
    n = m$n,
    n_pos = m$n_pos,
    auc = auc$auc,
    auc_ci_lo = auc$ci_lo,
    auc_ci_hi = auc$ci_hi
  )
}

.dvf75_fmt_pct <- function(x, digits = 1L) {
  if (!is.finite(x)) return("NA")
  sprintf(paste0("%.", as.integer(digits), "f"), 100 * x)
}

.dvf75_fmt_auc <- function(x, digits = 3L) {
  if (!is.finite(x)) return("NA")
  sprintf(paste0("%.", as.integer(digits), "f"), x)
}

.dvf75_stratum_rows <- function(truth, dxa_op, qct_op, stratum_vec, stratum_name) {
  if (is.factor(stratum_vec)) {
    lev <- levels(stratum_vec)
    lev <- lev[lev %in% as.character(stratum_vec)]
  } else {
    lev <- unique(as.character(stratum_vec[!is.na(stratum_vec)]))
  }
  rows <- lapply(lev, function(lv) {
    idx <- which(as.character(stratum_vec) == lv & is.finite(truth))
    if (!length(idx)) {
      return(data.frame(
        stratum = stratum_name,
        level = lv,
        n = 0L,
        n_frac = 0L,
        DXA_sens = NA_real_,
        QCT_sens = NA_real_,
        delta_sens = NA_real_,
        stringsAsFactors = FALSE
      ))
    }
    t <- truth[idx]
    md <- .osteo75_diag_metrics(t, dxa_op[idx])
    mq <- .osteo75_diag_metrics(t, qct_op[idx])
    data.frame(
      stratum = stratum_name,
      level = lv,
      n = as.integer(md$n),
      n_frac = as.integer(md$n_pos),
      DXA_sens = md$sens,
      QCT_sens = mq$sens,
      delta_sens = if (is.finite(mq$sens) && is.finite(md$sens)) mq$sens - md$sens else NA_real_,
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

#' 内部计算：总体 Sens/Spec/PPV/NPV/AUC + 分层 Sens
.dvf75_compute <- function(data, cfg = list()) {
  if (!is.data.frame(data)) stop("data must be a data.frame", call. = FALSE)
  cfg <- cfg %||% list()
  .dvf75_source_common(NULL)

  frac_nm <- as.character(
    cfg$fracture %||% .osteo75_pick_col(data, c("Vertebral_fracture", "vertebral_fracture", "Fracture"))
  )[1L]
  qct_cont_nm <- as.character(
    cfg$qct_continuous %||% .osteo75_pick_col(data, c("QCT_vBMD", "qct_vbmd"))
  )[1L]
  dxa_cont_nm <- as.character(
    cfg$dxa_continuous %||% .osteo75_pick_col(data, c("DXA_T_min", "DXA_T", "dxa_t"))
  )[1L]
  # pROC: ">" = controls have higher values than cases (lower BMD/T = disease).
  # Brief's colloquial "direction <" (= score below cutoff) maps to pROC ">".
  direction <- as.character(cfg$roc_direction %||% ">")[1L]
  op_level <- as.integer(cfg$op_level %||% 2L)[1L]

  truth_raw <- suppressWarnings(as.integer(data[[frac_nm]]))
  truth <- ifelse(is.finite(truth_raw) & truth_raw != 0L, 1L, ifelse(is.finite(truth_raw), 0L, NA_integer_))
  qct_op <- .dvf75_resolve_op(data, cfg, "qct")
  dxa_op <- .dvf75_resolve_op(data, cfg, "dxa")
  qct_score <- suppressWarnings(as.numeric(data[[qct_cont_nm]]))
  dxa_score <- suppressWarnings(as.numeric(data[[dxa_cont_nm]]))

  ok <- is.finite(truth)
  n <- as.integer(sum(ok))
  n_frac <- as.integer(sum(truth[ok] == 1L))

  overall_qct <- .dvf75_one_modality(truth[ok], qct_op[ok], qct_score[ok], direction)
  overall_dxa <- .dvf75_one_modality(truth[ok], dxa_op[ok], dxa_score[ok], direction)

  table3 <- data.frame(
    Modality = c("DXA", "QCT"),
    n = c(overall_dxa$n, overall_qct$n),
    n_frac = c(overall_dxa$n_pos, overall_qct$n_pos),
    Sens = c(overall_dxa$sens, overall_qct$sens),
    Spec = c(overall_dxa$spec, overall_qct$spec),
    PPV = c(overall_dxa$ppv, overall_qct$ppv),
    NPV = c(overall_dxa$npv, overall_qct$npv),
    AUC = c(overall_dxa$auc, overall_qct$auc),
    AUC_CI_lo = c(overall_dxa$auc_ci_lo, overall_qct$auc_ci_lo),
    AUC_CI_hi = c(overall_dxa$auc_ci_hi, overall_qct$auc_ci_hi),
    stringsAsFactors = FALSE
  )
  table3$Sens_pct <- vapply(table3$Sens, .dvf75_fmt_pct, character(1))
  table3$Spec_pct <- vapply(table3$Spec, .dvf75_fmt_pct, character(1))
  table3$AUC_fmt <- vapply(table3$AUC, .dvf75_fmt_auc, character(1))
  table3$footnote <- paste0(
    "Denominator: patients with non-missing Vertebral_fracture (n=", n,
    "; fracture events n_frac=", n_frac,
    "). OP positive = category == ", op_level,
    ". AUC direction='", direction, "' (lower BMD/T worse)."
  )

  strata_main <- as.character(cfg$strata %||% c("Nathan_bin", "AAC", "BMI_bin"))
  strata_supp <- as.character(cfg$strata_supplemental %||% c("Age_bin"))

  resolve_stratum <- function(nm) {
    if (nm %in% names(data)) return(data[[nm]])
    # map short names via .osteo75_make_strata
    st <- tryCatch(
      .osteo75_make_strata(data, list(
        nathan_col = "Nathan_bin",
        aac_col = "AAC",
        bmi_col = "BMI_bin",
        age_col = "Age_bin"
      )),
      error = function(e) NULL
    )
    if (is.null(st)) stop("Cannot resolve stratum column: ", nm, call. = FALSE)
    key <- if (grepl("Nathan", nm, ignore.case = TRUE)) {
      "Nathan"
    } else if (grepl("AAC", nm, ignore.case = TRUE)) {
      "AAC"
    } else if (grepl("BMI", nm, ignore.case = TRUE)) {
      "BMI"
    } else if (grepl("Age", nm, ignore.case = TRUE)) {
      "Age"
    } else {
      stop("Unknown stratum: ", nm, call. = FALSE)
    }
    st[[key]]
  }

  table4_parts <- lapply(strata_main, function(nm) {
    .dvf75_stratum_rows(truth, dxa_op, qct_op, resolve_stratum(nm), nm)
  })
  table4 <- do.call(rbind, table4_parts)
  rownames(table4) <- NULL
  table4$footnote <- paste0(
    "Per-stratum denominator = non-missing fracture within level; ",
    "n_frac = fracture events. delta_sens = QCT_sens - DXA_sens."
  )

  table_s3 <- NULL
  if (length(strata_supp)) {
    s3_parts <- lapply(strata_supp, function(nm) {
      .dvf75_stratum_rows(truth, dxa_op, qct_op, resolve_stratum(nm), nm)
    })
    table_s3 <- do.call(rbind, s3_parts)
    rownames(table_s3) <- NULL
  }

  list(
    n = n,
    n_frac = n_frac,
    op_level = op_level,
    roc_direction = direction,
    columns = list(
      fracture = frac_nm,
      qct_continuous = qct_cont_nm,
      dxa_continuous = dxa_cont_nm
    ),
    overall = list(DXA = overall_dxa, QCT = overall_qct),
    table3 = table3,
    table4 = table4,
    table_s3 = table_s3,
    truth = truth,
    dxa_op = dxa_op,
    qct_op = qct_op,
    dxa_score = dxa_score,
    qct_score = qct_score,
    strata_main = strata_main,
    strata_supplemental = strata_supp
  )
}

.dvf75_draw_roc <- function(comp, file_pdf) {
  dir.create(dirname(file_pdf), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(file_pdf, width = 6.5, height = 5.5)
  on.exit(grDevices::dev.off(), add = TRUE)
  ok <- is.finite(comp$truth) & is.finite(comp$dxa_score) & is.finite(comp$qct_score)
  y <- comp$truth[ok]
  if (length(unique(y)) < 2L || !requireNamespace("pROC", quietly = TRUE)) {
    graphics::plot.new()
    graphics::title("Figure 4 ROC (insufficient data or pROC missing)")
    return(invisible(file_pdf))
  }
  roc_dxa <- suppressWarnings(
    pROC::roc(y, comp$dxa_score[ok], quiet = TRUE, direction = comp$roc_direction)
  )
  roc_qct <- suppressWarnings(
    pROC::roc(y, comp$qct_score[ok], quiet = TRUE, direction = comp$roc_direction)
  )
  graphics::plot(
    roc_dxa,
    col = "#2166ac",
    lwd = 2,
    main = "Figure 4. ROC vs vertebral fracture",
    print.auc = FALSE,
    legacy.axes = TRUE
  )
  graphics::plot(roc_qct, col = "#b2182b", lwd = 2, add = TRUE, print.auc = FALSE)
  graphics::legend(
    "bottomright",
    legend = c(
      sprintf("DXA T-min AUC=%.3f", as.numeric(pROC::auc(roc_dxa))),
      sprintf("QCT vBMD AUC=%.3f", as.numeric(pROC::auc(roc_qct)))
    ),
    col = c("#2166ac", "#b2182b"),
    lwd = 2,
    bty = "n"
  )
  invisible(file_pdf)
}

.dvf75_draw_sens_bar <- function(table_df, file_pdf, title) {
  dir.create(dirname(file_pdf), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(file_pdf, width = 8, height = 5)
  on.exit(grDevices::dev.off(), add = TRUE)
  if (!is.data.frame(table_df) || !nrow(table_df)) {
    graphics::plot.new()
    graphics::title(paste0(title, " (empty)"))
    return(invisible(file_pdf))
  }
  labs <- paste(table_df$stratum, table_df$level, sep = "\n")
  mat <- rbind(table_df$DXA_sens, table_df$QCT_sens)
  mat[!is.finite(mat)] <- 0
  bp <- graphics::barplot(
    mat,
    beside = TRUE,
    names.arg = labs,
    col = c("#2166ac", "#b2182b"),
    ylim = c(0, 1.15),
    ylab = "Sensitivity",
    main = title,
    cex.names = 0.7,
    legend.text = c("DXA", "QCT"),
    args.legend = list(x = "topright", bty = "n")
  )
  graphics::abline(h = 0, col = "grey70")
  invisible(file_pdf)
}

.dvf75_export_table <- function(table_df, out_dir, base) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  xlsx_path <- file.path(out_dir, paste0(base, ".xlsx"))
  csv_path <- file.path(out_dir, paste0(base, ".csv"))
  exported <- NULL
  if (exists("export_sci_table", mode = "function")) {
    tryCatch({
      export_sci_table(table_df, xlsx_path, title = base)
      exported <- xlsx_path
    }, error = function(e) NULL)
  }
  if (is.null(exported) && requireNamespace("openxlsx", quietly = TRUE)) {
    tryCatch({
      openxlsx::write.xlsx(table_df, xlsx_path, overwrite = TRUE)
      exported <- xlsx_path
    }, error = function(e) NULL)
  }
  utils::write.csv(table_df, csv_path, row.names = FALSE)
  if (is.null(exported)) exported <- csv_path
  list(table_path = exported, csv_path = csv_path)
}

block_diagnostic_vs_fracture <- function(ctx, ...) {
  .dvf75_source_common(ctx)
  cfg_all <- ctx$config %||% list()
  cfg <- cfg_all$diagnostic_vs_fracture %||% list()
  if (!is.null(cfg$enable) && !isTRUE(cfg$enable)) {
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("diagnostic_vs_fracture: need ctx$data$imputed or ctx$data$cleaned", call. = FALSE)
  }

  comp <- .dvf75_compute(data, cfg)

  out_dir <- as.character(
    cfg_all$project$output_dir %||%
      cfg_all$paths$output_dir %||%
      file.path(tempdir(), "diagnostic_vs_fracture")
  )[1L]
  tables_dir <- file.path(out_dir, "Tables")
  figs_dir <- file.path(out_dir, "Figures")
  dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(figs_dir, recursive = TRUE, showWarnings = FALSE)

  exp3 <- .dvf75_export_table(
    comp$table3,
    tables_dir,
    "Table 3. Diagnostic performance vs vertebral fracture"
  )
  exp4 <- .dvf75_export_table(
    comp$table4,
    tables_dir,
    "Table 4. Stratified sensitivity vs vertebral fracture"
  )

  fig4_path <- NULL
  fig5_path <- NULL
  fig_s3_path <- NULL

  if (isTRUE(cfg$export_roc %||% TRUE)) {
    fig4_name <- "Figure 4. ROC DXA vs QCT for vertebral fracture.pdf"
    fig4_path <- file.path(figs_dir, fig4_name)
    ok4 <- tryCatch({
      .dvf75_draw_roc(comp, fig4_path)
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(ok4)) stop("diagnostic_vs_fracture: failed Figure 4 ROC", call. = FALSE)
    if (exists("save_figure", mode = "function")) {
      ctx <- tryCatch(
        save_figure(ctx, filename = fig4_name, path = fig4_path, title = fig4_name),
        error = function(e) ctx
      )
    }
  }

  if (isTRUE(cfg$export_sens_bar %||% TRUE)) {
    fig5_name <- "Figure 5. Stratified sensitivity DXA vs QCT.pdf"
    fig5_path <- file.path(figs_dir, fig5_name)
    ok5 <- tryCatch({
      .dvf75_draw_sens_bar(comp$table4, fig5_path, "Figure 5. Stratified sensitivity")
      TRUE
    }, error = function(e) FALSE)
    if (!isTRUE(ok5)) stop("diagnostic_vs_fracture: failed Figure 5 sens bar", call. = FALSE)
    if (exists("save_figure", mode = "function")) {
      ctx <- tryCatch(
        save_figure(ctx, filename = fig5_name, path = fig5_path, title = fig5_name),
        error = function(e) ctx
      )
    }
  }

  if (!is.null(comp$table_s3) && nrow(comp$table_s3) > 0L) {
    fig_s3_name <- "Figure S3. Age-stratified sensitivity vs vertebral fracture.pdf"
    fig_s3_path <- file.path(figs_dir, fig_s3_name)
    tryCatch({
      .dvf75_draw_sens_bar(comp$table_s3, fig_s3_path, "Figure S3. Age-stratified sensitivity")
    }, error = function(e) {
      fig_s3_path <<- NULL
    })
  }

  ctx$results$diagnostic_vs_fracture <- c(
    comp[c(
      "n", "n_frac", "op_level", "roc_direction", "columns",
      "overall", "table3", "table4", "table_s3",
      "strata_main", "strata_supplemental"
    )],
    list(
      table3_path = exp3$table_path,
      csv3_path = exp3$csv_path,
      table4_path = exp4$table_path,
      csv4_path = exp4$csv_path,
      figure4_path = fig4_path,
      figure5_path = fig5_path,
      figure_s3_path = fig_s3_path
    )
  )
  ctx
}

register_block(
  "diagnostic_vs_fracture",
  block_diagnostic_vs_fracture,
  "Diagnostic performance vs vertebral fracture: Table3/4, Figure4 ROC, Figure5 sens"
)
