#!/usr/bin/env Rscript
# 胆结石列线图：汇总对齐文献 Fig1–9（含 Fig2/3 拼图）+ CONSORT Fig1 重画
#
#   "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
#     run/gallstone_nomogram/rebuild_summary_lit_aligned.R \
#     --project "G:/02block_result/45_Gallstone/Nomogram_41815074"

`%||%` <- function(a, b) if (!is.null(a)) a else b
.args <- commandArgs(trailingOnly = TRUE)
.proj <- {
  i <- match("--project", .args)
  if (!is.na(i) && i < length(.args)) .args[[i + 1L]] else
    "G:/02block_result/45_Gallstone/Nomogram_41815074"
}
.proj <- normalizePath(.proj, winslash = "/", mustWork = TRUE)
.message <- function(...) message(paste0(...))
.message("project: ", .proj)

.root <- {
  if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else getwd()
}
source(file.path(.root, "R/attrition_log.R"), local = FALSE)
source(file.path(.root, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.root, "R/literature_gallstone_nomogram.R"), local = FALSE)

.feats <- c("Age", "diameter_cm", "volume_cm3", "ct_min", "ct_max",
            "pct_lt40", "pct_40_80", "pct_gt80", "energy_j", "shots")
# 主文 Fig2/3 拼图：仅列线图连续变量
.feats_fig23 <- c("pct_lt40", "pct_gt80")
.sum <- file.path(.proj, "summary_results")
.fig <- file.path(.sum, "Figures")
.tab <- file.path(.sum, "Tables")
.assoc <- file.path(.proj, "association_by_feature")
.nom <- file.path(.proj, "by_index", "\u3010success\u3011NOMOGRAM", "summary_results")
dir.create(file.path(.fig, "pdf"), recursive = TRUE, showWarnings = FALSE)
dir.create(.tab, recursive = TRUE, showWarnings = FALSE)

# ---------- 人数 ----------
.n <- NA_integer_; .n_train <- 190L; .n_val <- 83L
.note <- file.path(.proj, "Tables", "Methods_split_denominator_note.txt")
if (file.exists(.note)) {
  ln <- readLines(.note, warn = FALSE)
  .get <- function(k) {
    hit <- grep(paste0("^", k, "="), ln, value = TRUE)
    if (!length(hit)) return(NA_integer_)
    as.integer(sub(".*=", "", hit[[1L]]))
  }
  .n_train <- .get("train_n") %||% .n_train
  .n_val <- .get("val_n") %||% .n_val
}
.attr_csv <- file.path(.proj, "Tables", "Flowchart_attrition.csv")
if (file.exists(.attr_csv)) {
  ac <- utils::read.csv(.attr_csv, stringsAsFactors = FALSE)
  if ("n_remain" %in% names(ac) && nrow(ac)) .n <- as.integer(ac$n_remain[1L])
}
if (!is.finite(.n)) .n <- as.integer(.n_train + .n_val)

# ---------- 1) Fig1 文献 CONSORT（白底直角 + 右侧 Exclude + 训练/验证）----------
.steps_csv <- data.frame(
  step = c("N0", "N_analysis", "N_train", "N_val"),
  label = c(
    "Total eligible gallstone lithotripsy records",
    "Final participants included (complete case)",
    "Training set",
    "Validation set"
  ),
  n_remain = c(.n, .n, .n_train, .n_val),
  n_exclude = c(NA_integer_, 0L, NA_integer_, NA_integer_),
  exclude_label = c(NA_character_, "Missing modeling covariates (n = 0)",
                    NA_character_, NA_character_),
  stringsAsFactors = FALSE
)
utils::write.csv(.steps_csv, file.path(.tab, "Flowchart_attrition.csv"), row.names = FALSE)
utils::write.csv(.steps_csv, file.path(.proj, "Tables", "Flowchart_attrition.csv"), row.names = FALSE)

.fig1_name <- "Figure 1. Inclusion exclusion flowchart.pdf"
.fig1_paths <- unique(c(
  file.path(.fig, "pdf", .fig1_name),
  file.path(.proj, "Figures", "pdf", .fig1_name),
  file.path(.proj, "Figures", .fig1_name),
  file.path(.proj, "_shared", "Figures", .fig1_name),
  file.path(.nom, "Figures", "pdf", .fig1_name),
  file.path(.nom, "Figures", .fig1_name)
))
for (p in .fig1_paths) {
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  ok <- tryCatch({
    gallstone_draw_fig1_lit(
      p, n_total = .n, n_final = .n, n_exclude = 0L,
      exclude_label = "missing modeling covariates",
      n_train = .n_train, n_val = .n_val
    )
    TRUE
  }, error = function(e) {
    .message("Fig1 FAIL ", p, ": ", conditionMessage(e))
    FALSE
  })
  .message("Fig1 -> ", p, " ok=", ok)
}

# ---------- 2) Fig2 / Fig3 多页汇总（对齐文献：主文有 Fig2、Fig3，不是直接跳 Fig4）----------
.pdfunite <- function(inputs, output) {
  inputs <- inputs[file.exists(inputs)]
  if (!length(inputs)) return(FALSE)
  dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
  if (length(inputs) == 1L) {
    return(isTRUE(file.copy(inputs[[1L]], output, overwrite = TRUE)))
  }
  # 优先 pdfunite（矢量）；失败则 magick 栅格拼接为多页 PDF
  bin <- Sys.which("pdfunite")
  if (nzchar(bin)) {
    st <- system2(bin, args = c(shQuote(inputs), shQuote(output)), stdout = FALSE, stderr = FALSE)
    if (identical(as.integer(st), 0L) && file.exists(output) && file.info(output)$size > 0)
      return(TRUE)
  }
  if (requireNamespace("pdftools", quietly = TRUE) && requireNamespace("magick", quietly = TRUE)) {
    imgs <- lapply(inputs, function(f) {
      magick::image_read_pdf(f, density = 150)
    })
    combined <- do.call(c, imgs)
    magick::image_write(combined, path = output, format = "pdf")
    return(file.exists(output))
  }
  FALSE
}

.resolve_feat_pdf <- function(feat, kind = c("Associations", "RCS")) {
  kind <- match.arg(kind)
  bn <- if (identical(kind, "Associations")) {
    sprintf("Figure 2. Associations %s.pdf", feat)
  } else {
    sprintf("Figure 3. RCS %s.pdf", feat)
  }
  cands <- c(
    file.path(.assoc, feat, "Figures", "pdf", bn),
    file.path(.assoc, feat, "Figures", bn),
    file.path(.proj, "by_unit", paste0("\u3010success\u3011", feat), "Figures", bn),
    file.path(.proj, "by_unit", feat, "Figures", bn),
    file.path(.proj, "by_index", paste0("\u3010success\u3011", feat),
              "summary_results", "Figures", "pdf", bn),
    file.path(.proj, "by_index", paste0("\u3010success\u3011", feat),
              "summary_results", "Figures", bn)
  )
  hit <- cands[file.exists(cands)]
  if (length(hit)) hit[[1L]] else NA_character_
}

.fig2_in <- vapply(.feats_fig23, function(f) .resolve_feat_pdf(f, "Associations"), character(1))
.fig3_in <- vapply(.feats_fig23, function(f) .resolve_feat_pdf(f, "RCS"), character(1))
.message("Fig2 sources: ", sum(file.exists(.fig2_in)), "/", length(.feats_fig23))
.message("Fig3 sources: ", sum(file.exists(.fig3_in)), "/", length(.feats_fig23))

.fig2_out <- file.path(.fig, "pdf", "Figure 2. Associations of continuous features.pdf")
.fig3_out <- file.path(.fig, "pdf", "Figure 3. RCS of continuous features.pdf")
ok2 <- .pdfunite(unname(.fig2_in), .fig2_out)
ok3 <- .pdfunite(unname(.fig3_in), .fig3_out)
.message("Fig2 mosaic ok=", ok2, " -> ", .fig2_out)
.message("Fig3 mosaic ok=", ok3, " -> ", .fig3_out)

# 同步到根 Figures/pdf 与 NOMOGRAM
.sync_pdf <- function(src, name) {
  if (!file.exists(src)) return(invisible(FALSE))
  src_n <- normalizePath(src, winslash = "/", mustWork = TRUE)
  dests <- c(
    file.path(.proj, "Figures", "pdf", name),
    file.path(.proj, "Figures", name),
    file.path(.nom, "Figures", "pdf", name),
    file.path(.nom, "Figures", name)
  )
  for (d in dests) {
    dir.create(dirname(d), recursive = TRUE, showWarnings = FALSE)
    dn <- normalizePath(d, winslash = "/", mustWork = FALSE)
    if (identical(src_n, dn)) next
    file.copy(src, d, overwrite = TRUE)
  }
  invisible(TRUE)
}
.sync_pdf(.fig2_out, basename(.fig2_out))
.sync_pdf(.fig3_out, basename(.fig3_out))
.sync_pdf(file.path(.fig, "pdf", .fig1_name), .fig1_name)

# ---------- 3) Fig4–9：从 NOMOGRAM / 根目录收齐，保证连续 ----------
.pred_names <- c(
  "Figure 4. LASSO regression analysis.pdf",
  "Figure 5. Multivariate logistic regression.pdf",
  "Figure 6. Nomogram prediction model.pdf",
  "Figure 7. ROC and calibration.pdf",
  "Figure 8. DCA.pdf",
  "Figure 9. CIC.pdf"
)
.find_pred <- function(name) {
  cands <- c(
    file.path(.nom, "Figures", "pdf", name),
    file.path(.nom, "Figures", name),
    file.path(.proj, "Figures", "pdf", name),
    file.path(.proj, "Figures", name),
    file.path(.proj, "_shared", "Figures", name)
  )
  hit <- cands[file.exists(cands)]
  if (length(hit)) hit[[1L]] else NA_character_
}
for (nm in .pred_names) {
  src <- .find_pred(nm)
  if (is.na(src)) {
    .message("WARN missing ", nm)
    next
  }
  file.copy(src, file.path(.fig, "pdf", nm), overwrite = TRUE)
  .sync_pdf(src, nm)
  .message("kept ", nm)
}

# 清掉汇总里旧的「只有 Fig1+4–9」残留错误命名（若有）
# 不清 association 单特征

# ---------- 4) 表：交给 Chen 顺序整理脚本（禁止再写 Table3/4 主表）----------
# 原文主文仅 Table1–2；多因素/AUC 是 Fig5/Fig7。详见 reorganize_tables_chen_order.R
.message("→ tables: call reorganize_tables_chen_order.R …")
tryCatch(
  source(file.path(.root, "run/gallstone_nomogram/reorganize_tables_chen_order.R"),
         local = FALSE),
  error = function(e) .message("table reorganize WARN: ", conditionMessage(e))
)

# ---------- 5) 四目录 + README ----------
tryCatch(
  pub_figure_ensure_formats(.fig, config = list(pub = list(renumber = FALSE))),
  error = function(e) .message("formats WARN: ", conditionMessage(e))
)
# 根 Figures 若有平铺 pdf，也刷四目录
if (dir.exists(file.path(.proj, "Figures"))) {
  tryCatch(
    pub_figure_ensure_formats(file.path(.proj, "Figures"),
                              config = list(pub = list(renumber = FALSE))),
    error = function(e) .message(conditionMessage(e))
  )
}

# README 由 reorganize_tables_chen_order.R 写入（Chen Table1–2 + S1–S4）
if (!file.exists(file.path(.sum, "README.md"))) {
  writeLines(c(
    "# 发表汇总 — 对齐 Chen JAD",
    "Figures: Fig1–9 + S1/S2；Tables: Table1–2 + Table S1–S4（见 Tables/README.md）。"
  ), file.path(.sum, "README.md"))
}

tryCatch({
  .qc <- file.path(.root, "run/pub/run_pub_qc_after_project.R")
  if (file.exists(.qc)) {
    .message("→ pub-qc-after-project …")
    system2("Rscript", c("--vanilla", .qc, "--project", .proj), stdout = TRUE, stderr = TRUE)
  }
}, error = function(e) .message("pub-qc WARN: ", conditionMessage(e)))

.message("DONE lit-aligned summary: Fig1–9 + tables → ", .sum)
