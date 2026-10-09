# Review package Task 4
  314 Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R
  103 tests/test_osteo_dxa_qct_blocks.R
  417 total
==== BLOCK ====
###############################################################################
#  dxa_qct_agreement — DXA ↔ QCT 诊断一致性（κ / 交叉表 / Bland–Altman）
#
#  register_block: "dxa_qct_agreement"
#  典型流水线: imputation / baseline_binary 之后；diagnostic_vs_fracture 之前
#  公共 helper: Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R
#
#  # ── 配置 config$dxa_qct_agreement ─────────────────────────────────────────
#  enable          = TRUE
#  qct_cat         = "QCT_cat"          # 三分类（0/1/2）
#  dxa_cat         = "DXA_cat_min"
#  qct_continuous  = "QCT_vBMD"
#  dxa_continuous  = "DXA_T_min"
#  op_level        = 2L                 # 骨质疏松阳性水平
#  bland_zscore    = TRUE               # 连续量先各自 z 化再画 Bland–Altman
#
#  # ── 读写 ctx / 产出 ───────────────────────────────────────────────────────
#  读: ctx$data$imputed %||% cleaned
#  写: ctx$results$dxa_qct_agreement
#  表: DXA-QCT agreement（xlsx 或 CSV fallback）
#  图: Figure 3. DXA vs QCT agreement（左交叉热力，右 Bland–Altman）
###############################################################################

.dqa75_source_common <- function(ctx = NULL) {
  if (exists(".osteo75_cohen_kappa", mode = "function") &&
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

#' 内部计算：κ（二分类 OP）、三分类一致率、交叉表、Bland–Altman 坐标
.dqa75_compute <- function(data, cfg = list()) {
  if (!is.data.frame(data)) stop("data must be a data.frame", call. = FALSE)
  cfg <- cfg %||% list()
  .dqa75_source_common(NULL)

  qct_cat_nm <- as.character(
    cfg$qct_cat %||% .osteo75_pick_col(data, c("QCT_cat", "qct_cat"))
  )[1L]
  dxa_cat_nm <- as.character(
    cfg$dxa_cat %||% .osteo75_pick_col(data, c("DXA_cat_min", "DXA_cat", "dxa_cat"))
  )[1L]
  qct_cont_nm <- as.character(
    cfg$qct_continuous %||% .osteo75_pick_col(data, c("QCT_vBMD", "qct_vbmd"))
  )[1L]
  dxa_cont_nm <- as.character(
    cfg$dxa_continuous %||% .osteo75_pick_col(data, c("DXA_T_min", "DXA_T", "dxa_t"))
  )[1L]
  op_level <- as.integer(cfg$op_level %||% 2L)[1L]
  bland_z <- isTRUE(cfg$bland_zscore %||% TRUE)

  qct_cat <- suppressWarnings(as.integer(data[[qct_cat_nm]]))
  dxa_cat <- suppressWarnings(as.integer(data[[dxa_cat_nm]]))
  qct_cont <- suppressWarnings(as.numeric(data[[qct_cont_nm]]))
  dxa_cont <- suppressWarnings(as.numeric(data[[dxa_cont_nm]]))

  ok_cat <- is.finite(qct_cat) & is.finite(dxa_cat)
  n <- as.integer(sum(ok_cat))
  qct_ok <- qct_cat[ok_cat]
  dxa_ok <- dxa_cat[ok_cat]

  qct_op <- as.integer(qct_ok == op_level)
  dxa_op <- as.integer(dxa_ok == op_level)
  kap <- .osteo75_cohen_kappa(qct_op, dxa_op)

  agree_3cat <- if (n > 0L) mean(qct_ok == dxa_ok) else NA_real_

  lev3 <- sort(unique(c(qct_ok, dxa_ok)))
  if (!length(lev3)) lev3 <- 0:2
  cross_3cat <- as.data.frame.matrix(
    table(
      factor(qct_ok, levels = lev3, labels = paste0("QCT_", lev3)),
      factor(dxa_ok, levels = lev3, labels = paste0("DXA_", lev3))
    )
  )
  cross_3cat$QCT_level <- rownames(cross_3cat)
  rownames(cross_3cat) <- NULL
  cross_3cat <- cross_3cat[, c("QCT_level", setdiff(names(cross_3cat), "QCT_level")), drop = FALSE]

  cross_2x2 <- as.data.frame.matrix(
    table(
      factor(qct_op, levels = c(0L, 1L), labels = c("QCT_nonOP", "QCT_OP")),
      factor(dxa_op, levels = c(0L, 1L), labels = c("DXA_nonOP", "DXA_OP"))
    )
  )
  cross_2x2$QCT <- rownames(cross_2x2)
  rownames(cross_2x2) <- NULL
  cross_2x2 <- cross_2x2[, c("QCT", setdiff(names(cross_2x2), "QCT")), drop = FALSE]

  ok_cont <- is.finite(qct_cont) & is.finite(dxa_cont)
  qc <- qct_cont[ok_cont]
  dc <- dxa_cont[ok_cont]
  if (bland_z && length(qc) >= 2L) {
    zq <- as.numeric(scale(qc))
    zd <- as.numeric(scale(dc))
  } else {
    zq <- qc
    zd <- dc
  }
  bland <- data.frame(
    mean = (zq + zd) / 2,
    diff = zq - zd,
    qct = qc,
    dxa = dc,
    zscored = bland_z,
    stringsAsFactors = FALSE
  )
  bias <- if (nrow(bland)) mean(bland$diff, na.rm = TRUE) else NA_real_
  sd_diff <- if (nrow(bland) >= 2L) stats::sd(bland$diff, na.rm = TRUE) else NA_real_

  table_df <- data.frame(
    Metric = c(
      "n (paired categories)",
      "Cohen kappa (binary OP)",
      "n (kappa)",
      "Three-class exact agreement",
      "Bland-Altman bias (z-diff mean)",
      "Bland-Altman LoA lower",
      "Bland-Altman LoA upper",
      "bland_zscore"
    ),
    Value = c(
      as.character(n),
      sprintf("%.4f", kap$kappa),
      as.character(kap$n),
      sprintf("%.4f", agree_3cat),
      sprintf("%.4f", bias),
      sprintf("%.4f", bias - 1.96 * sd_diff),
      sprintf("%.4f", bias + 1.96 * sd_diff),
      as.character(bland_z)
    ),
    stringsAsFactors = FALSE
  )

  list(
    n = n,
    kappa_binary = as.numeric(kap$kappa),
    n_kappa = as.integer(kap$n),
    agree_3cat = as.numeric(agree_3cat),
    op_level = op_level,
    columns = list(
      qct_cat = qct_cat_nm,
      dxa_cat = dxa_cat_nm,
      qct_continuous = qct_cont_nm,
      dxa_continuous = dxa_cont_nm
    ),
    cross_3cat = cross_3cat,
    cross_2x2 = cross_2x2,
    bland = bland,
    bland_bias = bias,
    bland_sd = sd_diff,
    table = table_df
  )
}

.dqa75_draw_figure <- function(comp, file_pdf) {
  dir.create(dirname(file_pdf), recursive = TRUE, showWarnings = FALSE)
  grDevices::pdf(file_pdf, width = 10, height = 4.5)
  on.exit(grDevices::dev.off(), add = TRUE)
  old_par <- graphics::par(no.readonly = TRUE)
  on.exit(graphics::par(old_par), add = TRUE)
  graphics::par(mfrow = c(1L, 2L), mar = c(4.2, 4.2, 3, 1.5))

  # Left: 2x2 OP heatmap-style image from counts
  row_labs <- as.character(comp$cross_2x2$QCT)
  m2 <- as.matrix(comp$cross_2x2[, setdiff(names(comp$cross_2x2), "QCT"), drop = FALSE])
  storage.mode(m2) <- "double"
  graphics::image(
    x = seq_len(ncol(m2)),
    y = seq_len(nrow(m2)),
    z = t(m2[nrow(m2):1L, , drop = FALSE]),
    col = grDevices::colorRampPalette(c("#f7fbff", "#08306b"))(9),
    axes = FALSE,
    xlab = "DXA",
    ylab = "QCT",
    main = "OP binary cross-tab"
  )
  graphics::axis(1, at = seq_len(ncol(m2)), labels = colnames(m2), cex.axis = 0.75)
  graphics::axis(2, at = seq_len(nrow(m2)), labels = rev(row_labs),
                 cex.axis = 0.75, las = 1)
  for (i in seq_len(nrow(m2))) {
    for (j in seq_len(ncol(m2))) {
      graphics::text(j, nrow(m2) - i + 1L, labels = as.character(m2[i, j]), cex = 1.1)
    }
  }

  # Right: Bland–Altman
  bd <- comp$bland
  if (is.data.frame(bd) && nrow(bd) > 0L && any(is.finite(bd$mean) & is.finite(bd$diff))) {
    graphics::plot(
      bd$mean, bd$diff,
      pch = 19, col = grDevices::adjustcolor("#2166ac", 0.7),
      xlab = if (isTRUE(bd$zscored[1L])) "Mean of z(QCT), z(DXA)" else "Mean (QCT, DXA)",
      ylab = if (isTRUE(bd$zscored[1L])) "Diff z(QCT)-z(DXA)" else "Diff QCT-DXA",
      main = "Bland-Altman"
    )
    bias <- comp$bland_bias %||% mean(bd$diff, na.rm = TRUE)
    sdd <- comp$bland_sd %||% stats::sd(bd$diff, na.rm = TRUE)
    graphics::abline(h = bias, col = "#b2182b", lwd = 2)
    if (is.finite(sdd)) {
      graphics::abline(h = bias + 1.96 * sdd, col = "#b2182b", lty = 2)
      graphics::abline(h = bias - 1.96 * sdd, col = "#b2182b", lty = 2)
    }
    graphics::abline(h = 0, col = "grey50", lty = 3)
  } else {
    graphics::plot.new()
    graphics::title("Bland-Altman (insufficient continuous pairs)")
  }
  invisible(file_pdf)
}

.dqa75_export_table <- function(table_df, out_dir) {
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  base <- "DXA-QCT agreement"
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

block_dxa_qct_agreement <- function(ctx, ...) {
  .dqa75_source_common(ctx)
  cfg_all <- ctx$config %||% list()
  cfg <- cfg_all$dxa_qct_agreement %||% list()
  if (!is.null(cfg$enable) && !isTRUE(cfg$enable)) {
    return(ctx)
  }

  data <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("dxa_qct_agreement: need ctx$data$imputed or ctx$data$cleaned", call. = FALSE)
  }

  comp <- .dqa75_compute(data, cfg)

  out_dir <- as.character(
    cfg_all$project$output_dir %||%
      cfg_all$paths$output_dir %||%
      file.path(tempdir(), "dxa_qct_agreement")
  )[1L]
  tables_dir <- file.path(out_dir, "Tables")
  figs_dir <- file.path(out_dir, "Figures")
  dir.create(tables_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(figs_dir, recursive = TRUE, showWarnings = FALSE)

  exp <- .dqa75_export_table(comp$table, tables_dir)
  fig_name <- "Figure 3. DXA vs QCT agreement.pdf"
  fig_path <- file.path(figs_dir, fig_name)

  fig_ok <- tryCatch({
    .dqa75_draw_figure(comp, fig_path)
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(fig_ok)) {
    stop("dxa_qct_agreement: failed to write Figure 3 PDF", call. = FALSE)
  }
  if (exists("save_figure", mode = "function")) {
    ctx <- tryCatch(
      save_figure(
        ctx,
        filename = fig_name,
        path = fig_path,
        title = "Figure 3. DXA vs QCT agreement"
      ),
      error = function(e) ctx
    )
  }

  ctx$results$dxa_qct_agreement <- c(
    comp,
    list(
      table_path = exp$table_path,
      csv_path = exp$csv_path,
      figure_path = fig_path
    )
  )
  ctx
}

register_block(
  "dxa_qct_agreement",
  block_dxa_qct_agreement,
  "DXA vs QCT agreement: kappa, cross-tab, Bland-Altman (Figure 3)"
)
==== TEST TAIL ====
stopifnot(identical(.osteo75_pick_col(df, c("missing", "QCT_vBMD")), "QCT_vBMD"))

# make_strata
mini <- data.frame(
  Nathan = c(1L, 2L, 3L, 4L),
  AAC = c(0L, 1L, 0L, 1L),
  BMI = c(22, 25, 30, 23),
  Age = c(60, 70, 55, 66),
  stringsAsFactors = FALSE
)
st <- .osteo75_make_strata(mini, list())
stopifnot(all(c("Nathan", "AAC", "BMI", "Age") %in% names(st)))
stopifnot(length(st$Nathan) == 4L)

if (requireNamespace("pROC", quietly = TRUE)) {
  set.seed(42)
  truth <- c(rep(1L, 10), rep(0L, 10))
  score_good <- c(rnorm(10, 2), rnorm(10, 0))
  auc <- .osteo75_auc_continuous(truth, score_good)
  stopifnot(is.finite(auc$auc), auc$auc > 0.5)
} else {
  message("note: pROC not installed; AUC helper not exercised in test")
}

cat("helper OK\n")

# ── dxa_qct_agreement: .dqa75_compute on mini data ───────────────────────────
if (!exists("register_block", mode = "function")) {
  register_block <- function(...) invisible(NULL)
}
agree_path <- file.path(root, "Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R")
stopifnot(file.exists(agree_path))
source(agree_path, local = FALSE)
stopifnot(exists(".dqa75_compute", mode = "function"))

mini_agree <- data.frame(
  QCT_cat = c(0L, 1L, 2L, 0L, 1L, 2L),
  DXA_cat_min = c(0L, 1L, 2L, 1L, 1L, 2L),
  QCT_vBMD = c(120, 100, 80, 110, 95, 70),
  DXA_T_min = c(-1.0, -1.8, -2.8, -1.2, -2.0, -3.0),
  stringsAsFactors = FALSE
)
cfg_agree <- list(
  enable = TRUE,
  qct_cat = "QCT_cat",
  dxa_cat = "DXA_cat_min",
  qct_continuous = "QCT_vBMD",
  dxa_continuous = "DXA_T_min",
  op_level = 2L,
  bland_zscore = TRUE
)
comp <- .dqa75_compute(mini_agree, cfg_agree)
stopifnot(is.list(comp))
stopifnot(identical(as.integer(comp$n), 6L))
# OP binary (cat==2): QCT 001001 vs DXA 001001 → perfect κ=1
stopifnot(is.finite(comp$kappa_binary), abs(comp$kappa_binary - 1) < 1e-8)
stopifnot(identical(as.integer(comp$n_kappa), 6L))
# 3-class exact agreement: 5/6 (row 4: 0 vs 1)
stopifnot(is.finite(comp$agree_3cat), abs(comp$agree_3cat - 5 / 6) < 1e-8)
stopifnot(is.data.frame(comp$table), nrow(comp$table) >= 1L)
stopifnot(is.data.frame(comp$cross_3cat) || is.matrix(comp$cross_3cat))
stopifnot(is.data.frame(comp$bland) || is.list(comp$bland))

# Block path: mini ctx → results filled (CSV/PDF fallback OK in temp out)
out_tmp <- tempfile("dqa75_")
dir.create(out_tmp, recursive = TRUE, showWarnings = FALSE)
ctx <- list(
  data = list(cleaned = mini_agree, imputed = NULL),
  config = list(
    project = list(output_dir = out_tmp, root = root),
    dxa_qct_agreement = cfg_agree
  ),
  results = list()
)
ctx2 <- block_dxa_qct_agreement(ctx)
stopifnot(!is.null(ctx2$results$dxa_qct_agreement))
stopifnot(identical(as.integer(ctx2$results$dxa_qct_agreement$n), 6L))
stopifnot(is.finite(ctx2$results$dxa_qct_agreement$kappa_binary))

cat("agreement OK\n")
