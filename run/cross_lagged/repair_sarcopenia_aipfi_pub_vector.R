#!/usr/bin/env Rscript
# 肌少症 AIP×FI（54_Sarcopenia/cross-laged_40595747）交付返工：
# 1) 用 attrition CSV 重画详细 CONSORT Fig1（箭头+Exclude+分叉）
# 2) 从 _no_trim_work 矢量面板重拼 Fig2/3/5/S3/S4（可编辑 PDF）
# 3) Fig4/S1/S2 从 111 网络/稳定性格面板矢量拼装（网络本体多为栅格内嵌，拼页不二次整页栅格）
# 4) 删除 png/tiff；ensure_formats 仅 PDF+image_information
#
# 用法：
#   MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#   Rscript run/cross_lagged/repair_sarcopenia_aipfi_pub_vector.R \
#     --study /mnt/g/02block_result/54_Sarcopenia/cross-laged_40595747

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (is.null(a) || !length(a) || (length(a) == 1L && is.na(a))) b else a
get_opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}

study <- normalizePath(
  get_opt("--study", Sys.getenv("CROSS_LAGGED_STUDY_ROOT", unset = "")),
  winslash = "/", mustWork = TRUE
)
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) {
  cmd <- commandArgs(trailingOnly = FALSE)
  fa <- sub("^--file=", "", cmd[grepl("^--file=", cmd)][1L])
  root <- normalizePath(file.path(dirname(fa), "../.."), winslash = "/", mustWork = TRUE)
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)

for (f in c(
  "R/utils.R", "R/attrition_log.R", "R/dual_db_combine_figures.R",
  "R/pub_figure_export.R", "R/cross_lagged_study_meta.R"
)) {
  source(file.path(root, f), local = FALSE)
}

sum_fig <- file.path(study, "summary_result", "Figures")
pdf_dir <- file.path(sum_fig, "pdf")
work <- file.path(study, "summary_result_delivery_workspace", "_no_trim_work")
attr_dir <- file.path(study, "summary_result_delivery_workspace", "Tables_attrition_csv")
panel_dir <- file.path(study, "summary_result_delivery_workspace", "_repair_fig1_panels_20261104")
dir.create(panel_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)

# ---- Fig1 panels from attrition CSV ----
.read_attr <- function(db) {
  p <- file.path(attr_dir, sprintf("Flowchart attrition %s.csv", db))
  if (!file.exists(p)) stop("missing attrition: ", p, call. = FALSE)
  utils::read.csv(p, stringsAsFactors = FALSE, check.names = FALSE)
}

.prepare_draw_rows <- function(df, db) {
  stopifnot(all(c("step", "n") %in% names(df)))
  # 末两行若为结局分叉，从主链剥离
  lab <- as.character(df$step)
  is_fork_row <- grepl("^(Sarcopenia|Normal)$", lab, ignore.case = TRUE)
  fork <- NULL
  if (sum(is_fork_row) >= 2L) {
    fr <- df[is_fork_row, , drop = FALSE]
    # 病例在前
    i_case <- which(grepl("^Sarcopenia$", fr$step, ignore.case = TRUE))[1L]
    i_ref <- which(grepl("^Normal$", fr$step, ignore.case = TRUE))[1L]
    fork <- list(
      left_label = "Sarcopenia",
      left_n = as.integer(fr$n[i_case]),
      right_label = "Normal",
      right_n = as.integer(fr$n[i_ref])
    )
    df <- df[!is_fork_row, , drop = FALSE]
  }
  # 主链：写清 exclude_label；增强文案细节
  n <- nrow(df)
  if (!("exclude_label" %in% names(df))) df$exclude_label <- NA_character_
  if (!("excluded" %in% names(df))) df$excluded <- NA_real_
  for (i in seq_len(n)) {
    if (i == 1L) next
    drop_n <- as.integer(df$n[i - 1L]) - as.integer(df$n[i])
    el <- as.character(df$exclude_label[i])[1L]
    if (is.na(el) || !nzchar(el)) {
      if (is.finite(as.numeric(df$excluded[i])) && as.numeric(df$excluded[i]) > 0) {
        # keep NA; attrition_draw will invent
      }
    } else {
      # 更详细展示标签（不改人数）
      el2 <- el
      if (grepl("Missing AIP", el, ignore.case = TRUE)) {
        el2 <- "Missing AIP and/or Frailty Index (AIP × FI not calculable)"
      } else if (grepl("baseline link", el, ignore.case = TRUE)) {
        el2 <- "Could not link wave-1 AIP × FI to baseline covariate file"
      } else if (grepl("Incomplete sarcopenia phenotype|DN = 1", el, ignore.case = TRUE)) {
        el2 <- "Incomplete sarcopenia phenotype (DN=1; cannot classify as Sarcopenia or Normal)"
      } else if (grepl("Missing DN", el, ignore.case = TRUE)) {
        el2 <- "Missing sarcopenia phenotype (DN unavailable)"
      }
      df$exclude_label[i] <- el2
    }
    if ((!is.finite(as.numeric(df$excluded[i])) || as.numeric(df$excluded[i]) <= 0) &&
        is.finite(drop_n) && drop_n > 0L) {
      df$excluded[i] <- drop_n
    }
  }
  # 末步 fork 列
  df$fork_left_label <- NA_character_
  df$fork_left_n <- NA_integer_
  df$fork_right_label <- NA_character_
  df$fork_right_n <- NA_integer_
  if (!is.null(fork)) {
    last <- nrow(df)
    df$fork_left_label[last] <- fork$left_label
    df$fork_left_n[last] <- fork$left_n
    df$fork_right_label[last] <- fork$right_label
    df$fork_right_n[last] <- fork$right_n
  }
  list(rows = df, fork = fork)
}

dbs <- c("CHARLS", "ELSA", "HRS")
panel_paths <- character(0)
for (db in dbs) {
  prep <- .prepare_draw_rows(.read_attr(db), db)
  out_p <- file.path(panel_dir, sprintf("%s.pdf", db))
  title <- sprintf("Figure 1. %s — Inclusion / Exclusion (cross-section)", db)
  ok <- isTRUE(attrition_draw_pdf(prep$rows, title, out_p, fork = prep$fork))
  if (!isTRUE(ok) || !file.exists(out_p)) stop("Fig1 panel failed: ", db, call. = FALSE)
  panel_paths <- c(panel_paths, out_p)
  message("Fig1 panel OK: ", out_p)
}

fig1_out <- file.path(pdf_dir, "Figure 1. Inclusion exclusion flowchart.pdf")
.dual_db_compose_n_pdf_vector(
  panel_paths,
  paste0(LETTERS[seq_along(dbs)], ". ", dbs),
  fig1_out,
  layout = "side"
)
message("Fig1 mosaic: ", fig1_out)

# ---- helper: compose from panels ----
.compose <- function(paths, labels, out_name, layout = "side") {
  paths <- as.character(paths)
  stopifnot(all(file.exists(paths)))
  out <- file.path(pdf_dir, out_name)
  .dual_db_compose_n_pdf_vector(paths, labels, out, layout = layout)
  message("composed: ", out)
  invisible(out)
}

# Fig2 RCS 4 panels stack
.compose(
  file.path(work, c("Fig2_RCS_CHARLS.pdf", "Fig2_RCS_ELSA.pdf", "Fig2_RCS_HRS.pdf", "Fig2_RCS_Pooled.pdf")),
  c("A. CHARLS", "B. ELSA", "C. HRS", "D. Pooled"),
  "Figure 2. RCS of AIP x FI and Sarcopenia.pdf",
  layout = "stack"
)

# Fig3 forest stack
.compose(
  file.path(work, "fig3_forest", c("CHARLS.pdf", "ELSA.pdf", "HRS.pdf")),
  c("A. CHARLS", "B. ELSA", "C. HRS"),
  "Figure 3. Subgroup analyses of AIP x FI.pdf",
  layout = "stack"
)

# Fig5 mediation：用引擎风格面板（fig5_mediation_dep），竖拼；勿用字体重叠的 DiagrammeR 面板
.compose(
  file.path(work, "fig5_mediation_dep", c("med_CHARLS.pdf", "med_ELSA.pdf")),
  c("A. CHARLS (N = 1,366)", "B. ELSA (N = 861)"),
  "Figure 5. Cross-sectional mediation path diagram of AIP x FI hsCRP and Sarcopenia.pdf",
  layout = "stack"
)

# S3 SHAP 4panel（竖拼，勿用 grid/side）
.compose(
  file.path(work, "xgb_shap_4panel", c("SHAP_CHARLS.pdf", "SHAP_ELSA.pdf", "SHAP_HRS.pdf", "SHAP_Pooled.pdf")),
  c("A. CHARLS", "B. ELSA", "C. HRS", "D. Pooled"),
  "Figure S3. SHAP summary and dependence plots.pdf",
  layout = "stack"
)

# S4 ROC 4panel
.compose(
  file.path(work, "xgb_shap_4panel", c("ROC_CHARLS.pdf", "ROC_ELSA.pdf", "ROC_HRS.pdf", "ROC_Pooled.pdf")),
  c("A. CHARLS", "B. ELSA", "C. HRS", "D. Pooled"),
  "Figure S4. XGBoost ROC of AIP x FI for Sarcopenia.pdf",
  layout = "grid"
)

# Fig4 network + S1/S2 from Step07
net <- file.path(study, "111", "Step07_network_analysis")
.compose(
  file.path(net, c("network_CHARLS.pdf", "network_ELSA.pdf")),
  c("A. CHARLS", "B. ELSA"),
  "Figure 4. CLPN network of frailty index items.pdf",
  layout = "stack"
)
.compose(
  file.path(net, c("edgeStability_CHARLS.pdf", "edgeStability_ELSA.pdf")),
  c("A. CHARLS", "B. ELSA"),
  "Figure S1. CLPN case-dropping stability.pdf",
  layout = "side"
)
.compose(
  file.path(net, c("edgeCI_CHARLS.pdf", "edgeCI_ELSA.pdf")),
  c("A. CHARLS", "B. ELSA"),
  "Figure S2. CLPN edge-weight accuracy.pdf",
  layout = "side"
)

# ---- PDF-only delivery: drop png/tiff ----
cfg <- list(pub_figures = list(export_png = FALSE, export_tiff = FALSE, formats_dir = TRUE, dpi = 600L))
pub_figure_ensure_formats(sum_fig, config = cfg, purge = TRUE)
st <- pub_figure_formats_status(sum_fig, config = cfg)
message("formats_status ok=", isTRUE(st$ok), " stems=", length(st$stems %||% character()),
        " missing_png=", length(st$missing_png %||% character()),
        " missing_tiff=", length(st$missing_tiff %||% character()))

# Refresh Fig1 image_information with detailed steps
md <- file.path(sum_fig, "image_information", "Figure 1. Inclusion exclusion flowchart.md")
writeLines(c(
  "# Figure 1. Inclusion exclusion flowchart",
  "",
  "## 图面说明",
  "三栏 CONSORT 纳排拼图（A CHARLS / B ELSA / C HRS）。每栏：主列纳入框 + 实心下箭头；",
  "右侧 Exclude 框（虚线箭头）写明剔除原因与 n；底部分叉 Sarcopenia（粉）/ Normal（绿）。",
  "",
  "### DN 编码",
  "- CHARLS / ELSA：DN=0 Normal；DN=1 表型不全无法判定（排除）；DN=2 Sarcopenia。",
  "- HRS：DN=0 Normal；DN=1 Sarcopenia；缺 DN 单独排除。",
  "",
  "### A. CHARLS wave 1 (2011)",
  "17,708（有 DN 评估）→ Exclude Missing AIP/FI 9,554 → 8,154 → Exclude Missing baseline link 741 → 7,413 → Exclude Incomplete phenotype (DN=1) 3,890 → 3,523（Sarcopenia 893 / Normal 2,630）。",
  "",
  "### B. ELSA wave 2 (2004–2005)",
  "9,432 → Exclude Missing AIP/FI 3,598 → 5,834 → Exclude Incomplete phenotype (DN=1) 3,186 → 2,648（Sarcopenia 772 / Normal 1,876）。",
  "",
  "### C. HRS wave 13",
  "20,912（AIPFI 提取）→ Exclude Missing AIP/FI 15,829 → 5,083 → Exclude Missing DN 3,030 → 2,053（Sarcopenia 675 / Normal 1,378）。",
  "",
  "## 分析上下文",
  "- 暴露: AIP × FI",
  "- 结局: Sarcopenia（横断面现患）",
  "- 样本量: CHARLS 3,523；ELSA 2,648；HRS 2,053",
  "- Grouping: quintile（主文 Table 2）",
  "- 数据库: CHARLS / ELSA / HRS",
  "- 是否拼图: 是"
), md)

message("DONE repair_sarcopenia_aipfi_pub_vector")
