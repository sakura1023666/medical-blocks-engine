#!/usr/bin/env Rscript
# GPR 发表图样式整理（不跑 run_pipeline，避免双库 remirror 打乱编号）：
#  1) Fig1 = 发病/预后同款 CONSORT（attrition_draw_dual_panel_pdf）
#  2) Fig2 = 单库样式上下竖拼
#  3) Fig3 = 动态预测上下竖拼
#  4) S3 = X 轴从 day 1
#  5) S4 = 双库统一亚组列左右拼（假定分库已重跑）
#
#   Rscript run/trajectory_prognosis/repair_gpr_pub_style_fix.R [study_root]

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)
study_root <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1L]] else
  "/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr"
ix <- "GPR"
ng <- 2L
db_seq <- c("eicu", "mimic")

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/trajectory_survival_utils.R"))
source(file.path(.root, "R/attrition_log.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(.root, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"))
source(file.path(.root, "Blocks/53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R"))
source(file.path(study_root, "config.R"))
config$feishu$enable <- FALSE

hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
out_ix <- hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))][[1L]]
root_fig <- file.path(out_ix, "Figures")
dir.create(file.path(root_fig, "pdf"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(root_fig, "png"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(root_fig, "tiff"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(root_fig, "image_information"), recursive = TRUE, showWarnings = FALSE)

.export_one <- function(pdf_path) {
  stem <- sub("\\.pdf$", "", basename(pdf_path), ignore.case = TRUE)
  dest_pdf <- file.path(root_fig, "pdf", paste0(stem, ".pdf"))
  src <- normalizePath(pdf_path, winslash = "/", mustWork = FALSE)
  dst <- normalizePath(dest_pdf, winslash = "/", mustWork = FALSE)
  if (!identical(src, dst)) file.copy(pdf_path, dest_pdf, overwrite = TRUE)
  .pub_figure_rasterize_one(
    dest_pdf,
    file.path(root_fig, "png", paste0(stem, ".png")),
    file.path(root_fig, "tiff", paste0(stem, ".tiff")),
    300L, root_hint = .root
  )
}

# 正式 13 张：Fig1–4 + S1–S9（与 trajectory_pub_curate / 2class finalize 一致）
.keep_stems <- c(
  "Figure 1. Flowchart of patient selection",
  "Figure 2. Trajectory of GPR latent classes",
  "Figure 3. Dynamic prediction of GPR trajectory",
  "Figure 4. Individual dynamic prediction",
  "Figure S1. Missing value overview",
  "Figure S2. Kaplan Meier survival by trajectory class",
  "Figure S3. Piecewise Cox cut point search",
  "Figure S4. Subgroup analysis by trajectory class",
  "Figure S5. Weibull dynamic model comparison AUC",
  "Figure S6. Weibull dynamic model comparison C index",
  "Figure S7. Weibull dynamic model comparison Accuracy",
  "Figure S8. Weibull dynamic model comparison Sensitivity",
  "Figure S9. Weibull dynamic model comparison Specificity"
)

# ── 1) Fig1 CONSORT ──────────────────────────────────────────────────────────
cli::cli_h1("Fig1 CONSORT（发病/预后同款）")
rows_by_db <- list(); titles <- character(0)
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  csv <- file.path(out_ix, db, "step24_attrition_flowchart/Tables",
                   sprintf("Flowchart_attrition_%s.csv", db))
  if (!file.exists(csv))
    csv <- file.path(out_ix, db, "step24_attrition_flowchart/Tables/Flowchart_attrition.csv")
  rows <- utils::read.csv(csv, stringsAsFactors = FALSE)
  rows_by_db[[db_lab]] <- rows
  titles <- c(titles, sprintf("%s — Sepsis-AKI trajectory", db_lab))
  dest_u <- file.path(out_ix, db, "Figures",
                      sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab))
  attrition_draw_pdf(rows, titles[length(titles)], dest_u)
}
fig1 <- file.path(root_fig, "pdf/Figure 1. Flowchart of patient selection.pdf")
stopifnot(isTRUE(attrition_draw_dual_panel_pdf(rows_by_db, fig1, titles = titles)))
.export_one(fig1)
cli::cli_alert_success("Fig1 CONSORT 已更新")

# ── 2) Fig2 单库样式 + 竖拼 ──────────────────────────────────────────────────
cli::cli_h1("Fig2 轨迹（单库样式竖拼）")
.unwrap <- trajectory_unwrap_jointlcmm
.load <- function(db) {
  e <- new.env(parent = emptyenv())
  load(file.path(out_ix, db, "step14_trajectory_jlcm/Data/D01_jlcm_GPR_models.RData"), envir = e)
  list(models = e$models_list_with_cov, md = e$model_data_final)
}
packs <- list(eicu = .load("eicu"), mimic = .load("mimic"))
curves <- list(); obs_means <- list(); obs_all <- numeric(0); pred_all <- numeric(0)
for (db in db_seq) {
  m <- .unwrap(packs[[db]]$models$m2)
  md <- packs[[db]]$md
  curves[[db]] <- trajectory_jlcm_pred_curves(m, md, 28L, 50L)
  obs_means[[db]] <- trajectory_jlcm_obs_class_means(m, md, "scr_std")
  pred_all <- c(pred_all, as.numeric(curves[[db]])[as.numeric(curves[[db]]) >= 0.5])
  obs_all <- c(obs_all, md$scr_std)
}
align <- trajectory_align_class_maps(curves, ref = "eicu", obs_means_by_db = obs_means)
ylim <- trajectory_shared_ylim(obs_all, pred_all, ymin = 1)
.make_one <- function(db) {
  m <- .unwrap(packs[[db]]$models$m2)
  md <- packs[[db]]$md
  pp <- as.data.frame(m$pprob)
  long <- md |>
    dplyr::left_join(pp[, c("subject_id_num", "class")], by = "subject_id_num") |>
    dplyr::mutate(Class = paste0("Class", class)) |>
    dplyr::rename(Time = time_day, Value = scr_std)
  .tpj04_make_plot(
    m, long, ix, ng, 28L, "subject_id", "sans",
    cov_cols = c("OASIS", "Age", "APSIII", "Temperature"),
    class_map = align$maps[[db]], ylim = ylim
  )
}
th <- ggplot2::theme(
  plot.title = ggplot2::element_text(face = "bold", size = 11, hjust = 0,
                                     margin = ggplot2::margin(0, 0, 2, 0)),
  plot.margin = ggplot2::margin(2, 6, 2, 6)
)
p_e <- .make_one("eicu") + ggplot2::labs(title = "A. eICU", x = NULL) + th
p_m <- .make_one("mimic") + ggplot2::labs(title = "B. MIMIC") + th
.w_db <- 7.8; .h_db <- 3.05
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  pp <- if (db == "eicu") p_e else p_m
  fp <- file.path(out_ix, db, "Figures",
                  sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix))
  ggplot2::ggsave(fp, pp, width = .w_db, height = .h_db, device = grDevices::cairo_pdf)
}
fig2 <- patchwork::wrap_plots(p_e, p_m, ncol = 1) +
  patchwork::plot_annotation(
    title = "Figure 2. Trajectory of GPR latent classes",
    theme = ggplot2::theme(plot.title = ggplot2::element_text(face = "bold", size = 12, hjust = 0))
  )
fig2_path <- file.path(root_fig, "pdf/Figure 2. Trajectory of GPR latent classes.pdf")
ggplot2::ggsave(fig2_path, fig2, width = 7.8, height = 6.4, device = grDevices::cairo_pdf)
.export_one(fig2_path)
cli::cli_alert_success("Fig2 竖拼完成（7.8×6.4）")

# ── 3) Fig3 动态预测竖拼 ─────────────────────────────────────────────────────
cli::cli_h1("Fig3 动态预测竖拼")
.find_dyn <- function(db, db_lab) {
  cands <- c(
    file.path(out_ix, db, "Figures",
              sprintf("Figure 3-%s. Dynamic prediction of GPR trajectory.pdf", db_lab)),
    file.path(out_ix, db, "Figures",
              sprintf("Figure 4-%s. Dynamic prediction of GPR trajectory.pdf", db_lab)),
    file.path(out_ix, db, "Figures/Figure Dynpred GPR D2.pdf")
  )
  cands[file.exists(cands)][1L]
}
f3e <- .find_dyn("eicu", "eICU"); f3m <- .find_dyn("mimic", "MIMIC")
stopifnot(nzchar(f3e), nzchar(f3m), file.exists(f3e), file.exists(f3m))
# 分库正式名回写 Figure 3-*
file.copy(f3e, file.path(out_ix, "eicu/Figures/Figure 3-eICU. Dynamic prediction of GPR trajectory.pdf"),
          overwrite = TRUE)
file.copy(f3m, file.path(out_ix, "mimic/Figures/Figure 3-MIMIC. Dynamic prediction of GPR trajectory.pdf"),
          overwrite = TRUE)
fig3 <- file.path(root_fig, "pdf/Figure 3. Dynamic prediction of GPR trajectory.pdf")
stopifnot(isTRUE(pub_figure_combine_ab_pdfs(
  f3e, f3m, fig3, stack = TRUE, labels = c("A. eICU", "B. MIMIC")
)))
.export_one(fig3)
cli::cli_alert_success("Fig3 已竖拼")

# ── 3b) Fig4 KM 竖拼（KM PDF 常有空白首页，取内容最丰富页） ─────────────────
cli::cli_h1("Fig4 KM 竖拼")
.km <- function(db, db_lab) {
  cands <- c(
    file.path(out_ix, db, "Figures",
              sprintf("Figure 3-%s. Kaplan Meier survival by trajectory class.pdf", db_lab)),
    file.path(out_ix, db, "Figures/Figure KM TrajectoryClass GPR.pdf")
  )
  cands[file.exists(cands)][1L]
}
.km_content_page_pdf <- function(src, dest) {
  # 用 PyMuPDF 抽出 drawings/images 最多的一页，避免空白首页进拼图
  py <- .pub_figure_python_exe()
  code <- paste(
    "import fitz,sys",
    "d=fitz.open(sys.argv[1])",
    "best=max(range(len(d)), key=lambda i: len(d[i].get_drawings())+10*len(d[i].get_images()))",
    "o=fitz.open(); o.insert_pdf(d, from_page=best, to_page=best)",
    "o.save(sys.argv[2]); o.close(); d.close()",
    sep = "; "
  )
  status <- system2(py, args = c("-c", shQuote(code), src, dest),
                    stdout = FALSE, stderr = FALSE)
  identical(as.integer(status), 0L) && file.exists(dest) &&
    isTRUE(file.info(dest)$size > 1000L)
}
kme <- .km("eicu", "eICU"); kmm <- .km("mimic", "MIMIC")
fig4 <- file.path(root_fig, "pdf/Figure 4. Kaplan Meier survival by trajectory class.pdf")
if (file.exists(kme) && file.exists(kmm)) {
  tmp <- tempfile("km_"); dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  ae <- file.path(tmp, "a.pdf"); am <- file.path(tmp, "b.pdf")
  if (isTRUE(.km_content_page_pdf(kme, ae)) && isTRUE(.km_content_page_pdf(kmm, am))) {
    pub_figure_combine_ab_pdfs(ae, am, fig4, stack = TRUE, labels = c("A. eICU", "B. MIMIC"))
  } else {
    pub_figure_combine_ab_pdfs(kme, kmm, fig4, stack = TRUE, labels = c("A. eICU", "B. MIMIC"))
  }
  .export_one(fig4)
  cli::cli_alert_success("Fig4 KM 已竖拼（size={file.info(fig4)$size}）")
} else {
  cli::cli_alert_warning("KM 源缺失，跳过 Fig4")
}

# ── 4) S3 从 day 1 ───────────────────────────────────────────────────────────
cli::cli_h1("Fig S3 cut search（X 从 day 1）")
.s3_one <- function(db) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  scan <- file.path(out_ix, db, "Tables/_archive",
                    sprintf("Table_Piecewise_Cox_CutScan_%s.csv", db))
  if (!file.exists(scan)) {
    hits <- list.files(file.path(out_ix, db), pattern = "Table_Piecewise_Cox_CutScan",
                       recursive = TRUE, full.names = TRUE)
    hits <- hits[!grepl("/_archive_messy/", hits)]
    if (length(hits)) scan <- hits[1]
  }
  df <- utils::read.csv(scan, stringsAsFactors = FALSE)
  best <- df$cut[which.max(df$loglik)]
  p <- .tpc01_cut_search_plot(df, best, paste(ix, "piecewise Cox cut-off search"), 28L, "sans")
  fp <- file.path(out_ix, db, "Figures",
                  sprintf("Figure S3-%s. Piecewise Cox cut point search.pdf", db_lab))
  ggplot2::ggsave(fp, p, width = 7.2, height = 4.2, device = grDevices::cairo_pdf)
  file.copy(scan, file.path(out_ix, db, "Tables", basename(scan)), overwrite = TRUE)
  fp
}
s3e <- .s3_one("eicu"); s3m <- .s3_one("mimic")
s3 <- file.path(root_fig, "pdf/Figure S3. Piecewise Cox cut point search.pdf")
pub_figure_combine_ab_pdfs(s3e, s3m, s3, stack = FALSE, labels = c("A. eICU", "B. MIMIC"))
.export_one(s3)
cli::cli_alert_success("S3 已重画（xlim 从 1 起）")

# ── 5) S4 统一亚组拼图（分库已在上轮重跑） ───────────────────────────────────
cli::cli_h1("Fig S4 双库统一亚组拼图")
s4e <- file.path(out_ix, "eicu/Figures/Figure S4-eICU. Subgroup analysis by trajectory class.pdf")
s4m <- file.path(out_ix, "mimic/Figures/Figure S4-MIMIC. Subgroup analysis by trajectory class.pdf")
if (!file.exists(s4e)) {
  hits <- list.files(file.path(out_ix, "eicu"), pattern = "Figure Subgroup TrajectoryClass GPR\\.pdf$",
                     recursive = TRUE, full.names = TRUE)
  hits <- hits[!grepl("/_raw/", hits)]
  if (length(hits)) {
    s4e <- hits[which.max(file.info(hits)$mtime)]
    file.copy(s4e, file.path(out_ix, "eicu/Figures/Figure S4-eICU. Subgroup analysis by trajectory class.pdf"),
              overwrite = TRUE)
    s4e <- file.path(out_ix, "eicu/Figures/Figure S4-eICU. Subgroup analysis by trajectory class.pdf")
  }
}
if (!file.exists(s4m)) {
  hits <- list.files(file.path(out_ix, "mimic"), pattern = "Figure Subgroup TrajectoryClass GPR\\.pdf$",
                     recursive = TRUE, full.names = TRUE)
  hits <- hits[!grepl("/_raw/", hits)]
  if (length(hits)) {
    s4m <- hits[which.max(file.info(hits)$mtime)]
    file.copy(s4m, file.path(out_ix, "mimic/Figures/Figure S4-MIMIC. Subgroup analysis by trajectory class.pdf"),
              overwrite = TRUE)
    s4m <- file.path(out_ix, "mimic/Figures/Figure S4-MIMIC. Subgroup analysis by trajectory class.pdf")
  }
}
stopifnot(file.exists(s4e), file.exists(s4m))
s4 <- file.path(root_fig, "pdf/Figure S4. Subgroup analysis by trajectory class.pdf")
pub_figure_combine_ab_pdfs(s4e, s4m, s4, stack = FALSE, labels = c("A. eICU", "B. MIMIC"))
.export_one(s4)
cli::cli_alert_success("S4 已拼图")

# ── 可选：个体预测 / Weibull AUC 进补充 ──────────────────────────────────────
.indiv_e <- file.path(out_ix, "eicu/Figures/Figure Dynpred Individual GPR.pdf")
.indiv_m <- file.path(out_ix, "mimic/Figures/Figure Dynpred Individual GPR.pdf")
if (file.exists(.indiv_e) && file.exists(.indiv_m)) {
  s1 <- file.path(root_fig, "pdf/Figure S1. Individual dynamic prediction.pdf")
  pub_figure_combine_ab_pdfs(.indiv_e, .indiv_m, s1, stack = TRUE, labels = c("A. eICU", "B. MIMIC"))
  .export_one(s1)
}
.auc_e <- file.path(out_ix, "eicu/Figures/Figure Weibull Dynamic Compare GPR AUC.pdf")
.auc_m <- file.path(out_ix, "mimic/Figures/Figure Weibull Dynamic Compare GPR AUC.pdf")
if (file.exists(.auc_e) && file.exists(.auc_m)) {
  s2 <- file.path(root_fig, "pdf/Figure S2. Weibull dynamic model comparison AUC.pdf")
  pub_figure_combine_ab_pdfs(.auc_e, .auc_m, s2, stack = FALSE, labels = c("A. eICU", "B. MIMIC"))
  .export_one(s2)
}

# ── 清根：只留白名单发表图 ───────────────────────────────────────────────────
cli::cli_h1("清理 Figures 根目录")
for (subdir in c("pdf", "png", "tiff", "image_information")) {
  dd <- file.path(root_fig, subdir)
  if (!dir.exists(dd)) next
  exts <- switch(subdir,
                 pdf = "\\.pdf$", png = "\\.png$", tiff = "\\.tiff$",
                 image_information = "\\.md$")
  files <- list.files(dd, pattern = exts, full.names = TRUE)
  for (fp in files) {
    stem <- sub("\\.(pdf|png|tiff|md)$", "", basename(fp), ignore.case = TRUE)
    if (stem == "README") next
    if (!(stem %in% .keep_stems)) unlink(fp)
  }
}
# 根平铺 PDF 清掉
unlink(list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE))

# image_information
meta <- list(
  exposure = ix, outcome = "28-day mortality", grouping = "2-class JLCM",
  databases = c("eICU", "MIMIC"), combined = TRUE,
  n_total = "eICU N=6941; MIMIC N=9660"
)
pub_figure_refresh_image_information(root_fig, meta = meta, config = config)

ae <- utils::read.csv(file.path(out_ix, "eicu/step24_attrition_flowchart/Tables/Flowchart_attrition_eicu.csv"),
                      stringsAsFactors = FALSE)
am <- utils::read.csv(file.path(out_ix, "mimic/step24_attrition_flowchart/Tables/Flowchart_attrition_mimic.csv"),
                      stringsAsFactors = FALSE)
.md_steps <- function(db, d) {
  out <- character(0)
  for (i in seq_len(nrow(d))) {
    n <- as.integer(d$n[i]); step <- as.character(d$step[i])
    if (i == 1L) out <- c(out, sprintf("- %s：%s，保留 n=%s", db, step, format(n, big.mark = ",")))
    else out <- c(out, sprintf("- %s：%s，保留 n=%s（本步排除 %s 人）",
                               db, step, format(n, big.mark = ","),
                               format(as.integer(d$n[i - 1L]) - n, big.mark = ",")))
  }
  out
}
writeLines(c(
  "# Figure 1. Flowchart of patient selection", "",
  "## 图面说明",
  "双库 CONSORT 纳排流程图（A. eICU；B. MIMIC），样式与发病/预后 dual-batch Figure 1 一致：主列圆角纳入框、右侧 Exclude、Times 字体。",
  "", "### 图上标注 / 逐步人数", .md_steps("eICU", ae), .md_steps("MIMIC", am), "",
  "## 分析上下文",
  "- 暴露: GPR", "- 结局: 28-day mortality",
  "- 样本量: eICU N=6,941; MIMIC N=9,660（插补后分析集）",
  "- Grouping: 2-class JLCM", "- 数据库: eICU, MIMIC", "- 是否拼图: 是", ""
), file.path(root_fig, "image_information/Figure 1. Flowchart of patient selection.md"), useBytes = TRUE)

writeLines(c(
  "# Figure S3. Piecewise Cox cut point search", "",
  "## 图面说明",
  "双库拼图：按天扫描分段 Cox 切点的偏对数似然。横轴为 ICU 入科后天数（从第 1 天到第 28 天），纵轴为两段模型对数似然之和；橙点为可估切点，竖线为最优切点。",
  "",
  "### 图上标注",
  "- X 轴从 day 1 起标度；早期 cut 因前段事件数不足（stable=FALSE / loglik 缺失）不连线，图注标明起始可估日。",
  "- eICU / MIMIC 最优切点见 Table 3 / CutScan CSV。",
  "",
  "## 分析上下文",
  "- 暴露: GPR 轨迹类别（2-class）",
  "- 结局: 28-day mortality",
  "- Grouping: 2-class JLCM",
  "- 数据库: eICU, MIMIC",
  "- 是否拼图: 是", ""
), file.path(root_fig, "image_information/Figure S3. Piecewise Cox cut point search.md"), useBytes = TRUE)

writeLines(c(
  "# Figure S4. Subgroup analysis by trajectory class", "",
  "## 图面说明",
  "双库亚组森林图（A. eICU；B. MIMIC）。两库共用同一亚组变量集（Age@65 + Gender/Race/Ventilation 及共病），禁止 auto_scan 扩库特异列。",
  "",
  "## 分析上下文",
  "- 暴露: GPR 轨迹 Class2 vs Class1",
  "- 结局: 28-day mortality",
  "- Grouping: 2-class JLCM",
  "- 数据库: eICU, MIMIC",
  "- 是否拼图: 是", ""
), file.path(root_fig, "image_information/Figure S4. Subgroup analysis by trajectory class.md"), useBytes = TRUE)

n_pdf <- length(list.files(file.path(root_fig, "pdf"), pattern = "\\.pdf$"))
cli::cli_alert_success("样式整理完成。pdf={n_pdf} 张（白名单）")
invisible(list.files(file.path(root_fig, "pdf")))
