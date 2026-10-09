#!/usr/bin/env Rscript
# 补全 GPR 发表图至正式 13 张（Fig1–4 + S1–S9），保留已修好的样式：
#   Fig1 CONSORT / Fig2 竖拼轨迹 / Fig3 竖拼动态预测 / S3 从 day1 / S4 统一亚组
# 不跑 run_pipeline。
#
#   Rscript run/trajectory_prognosis/repair_gpr_restore_13figs.R [study_root]

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

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(.root, "R/attrition_log.R"))
source(file.path(study_root, "config.R"))
config$feishu$enable <- FALSE

out_ix <- {
  hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
  hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))][[1L]]
}
root_fig <- file.path(out_ix, "Figures")
pdf_dir <- file.path(root_fig, "pdf")
dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(root_fig, "png"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(root_fig, "tiff"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(root_fig, "image_information"), recursive = TRUE, showWarnings = FALSE)

.need <- c(
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

.export_one <- function(pdf_path) {
  stem <- sub("\\.pdf$", "", basename(pdf_path), ignore.case = TRUE)
  dest_pdf <- file.path(pdf_dir, paste0(stem, ".pdf"))
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

.pick <- function(db, patterns) {
  fig <- file.path(out_ix, db, "Figures")
  for (p in patterns) {
    hits <- list.files(fig, pattern = p, full.names = TRUE)
    hits <- hits[!grepl("/_raw/", hits)]
    if (length(hits)) return(hits[which.max(file.info(hits)$mtime)])
  }
  # step 目录兜底
  for (p in patterns) {
    hits <- list.files(file.path(out_ix, db), pattern = p, recursive = TRUE, full.names = TRUE)
    hits <- hits[!grepl("/_raw/", hits)]
    if (length(hits)) return(hits[which.max(file.info(hits)$mtime)])
  }
  NA_character_
}

.km_content_page <- function(src, dest) {
  # 写临时 .py，避免 system2 -c 空格拆坏；取 drawings 最多的一页
  py <- .pub_figure_python_exe()
  script <- tempfile(fileext = ".py")
  writeLines(c(
    "import fitz, sys",
    "d = fitz.open(sys.argv[1])",
    "best = max(range(len(d)), key=lambda i: len(d[i].get_drawings()) + 10 * len(d[i].get_images()))",
    "o = fitz.open(); o.insert_pdf(d, from_page=best, to_page=best)",
    "o.save(sys.argv[2]); o.close(); d.close()"
  ), script)
  on.exit(unlink(script), add = TRUE)
  status <- system2(py, args = c(script, src, dest), stdout = FALSE, stderr = FALSE)
  identical(as.integer(status), 0L) && file.exists(dest) &&
    isTRUE(file.info(dest)$size > 2000L)
}

.combine <- function(a, b, dest, stack = TRUE, labels = c("A. eICU", "B. MIMIC")) {
  stopifnot(file.exists(a), file.exists(b))
  ok <- pub_figure_combine_ab_pdfs(a, b, dest, stack = stack, labels = labels)
  if (!isTRUE(ok)) stop("拼图失败: ", basename(dest))
  .export_one(dest)
  cli::cli_alert_success("{basename(dest)}  size={file.info(dest)$size}")
}

# ── 保留已修好的 Fig1–3、S3、S4（若缺则报错提示） ────────────────────────────
cli::cli_h1("校验已修好的主图")
.must <- c(
  "Figure 1. Flowchart of patient selection.pdf",
  "Figure 2. Trajectory of GPR latent classes.pdf",
  "Figure 3. Dynamic prediction of GPR trajectory.pdf",
  "Figure S3. Piecewise Cox cut point search.pdf",
  "Figure S4. Subgroup analysis by trajectory class.pdf"
)
for (nm in .must) {
  fp <- file.path(pdf_dir, nm)
  if (!file.exists(fp) || file.info(fp)$size < 5000) {
    # Fig1 可现画
    if (grepl("Figure 1", nm)) {
      rows_by_db <- list()
      titles <- character(0)
      for (db in c("eicu", "mimic")) {
        db_lab <- if (db == "eicu") "eICU" else "MIMIC"
        csv <- file.path(out_ix, db, "step24_attrition_flowchart/Tables",
                         sprintf("Flowchart_attrition_%s.csv", db))
        rows_by_db[[db_lab]] <- utils::read.csv(csv, stringsAsFactors = FALSE)
        titles <- c(titles, sprintf("%s — Sepsis-AKI trajectory", db_lab))
      }
      attrition_draw_dual_panel_pdf(rows_by_db, fp, titles = titles)
      .export_one(fp)
    } else {
      stop("缺少已修好图: ", nm, " — 请先跑 repair_gpr_pub_style_fix.R")
    }
  } else {
    .export_one(fp) # 确保 png/tiff 在
    cli::cli_alert_info("保留 {nm}")
  }
}

# ── Fig4 个体动态预测（竖拼） ────────────────────────────────────────────────
cli::cli_h1("Fig4 Individual")
ie <- .pick("eicu", c("Figure Dynpred Individual GPR\\.pdf$",
                      "Figure 4-eICU\\. Individual",
                      "Figure 5-eICU\\. Individual"))
im <- .pick("mimic", c("Figure Dynpred Individual GPR\\.pdf$",
                       "Figure 4-MIMIC\\. Individual",
                       "Figure 6-MIMIC\\. Individual"))
.combine(ie, im, file.path(pdf_dir, "Figure 4. Individual dynamic prediction.pdf"),
         stack = TRUE)

# ── S1 缺失值总览 ────────────────────────────────────────────────────────────
cli::cli_h1("S1 Missing")
me <- .pick("eicu", c("Figure Missing Value Overview\\.pdf$",
                      "Figure S1-eICU\\. Missing"))
mm <- .pick("mimic", c("Figure Missing Value Overview\\.pdf$",
                       "Figure S1-MIMIC\\. Missing"))
# 拷到分库正式名
file.copy(me, file.path(out_ix, "eicu/Figures/Figure S1-eICU. Missing value overview.pdf"),
          overwrite = TRUE)
file.copy(mm, file.path(out_ix, "mimic/Figures/Figure S1-MIMIC. Missing value overview.pdf"),
          overwrite = TRUE)
.combine(me, mm, file.path(pdf_dir, "Figure S1. Missing value overview.pdf"),
         stack = FALSE)

# ── S2 KM（竖拼；抽内容页） ──────────────────────────────────────────────────
cli::cli_h1("S2 KM")
ke <- .pick("eicu", c("Figure KM TrajectoryClass GPR\\.pdf$",
                      "Kaplan Meier survival by trajectory class"))
km <- .pick("mimic", c("Figure KM TrajectoryClass GPR\\.pdf$",
                       "Kaplan Meier survival by trajectory class"))
tmp <- tempfile("km_"); dir.create(tmp)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
ae <- file.path(tmp, "a.pdf"); am <- file.path(tmp, "b.pdf")
if (!isTRUE(.km_content_page(ke, ae))) file.copy(ke, ae, overwrite = TRUE)
if (!isTRUE(.km_content_page(km, am))) file.copy(km, am, overwrite = TRUE)
.combine(ae, am, file.path(pdf_dir, "Figure S2. Kaplan Meier survival by trajectory class.pdf"),
         stack = TRUE)

# ── S5–S9 Weibull ────────────────────────────────────────────────────────────
cli::cli_h1("S5–S9 Weibull")
.weibull <- list(
  list(stem = "Figure S5. Weibull dynamic model comparison AUC",
       pat = "Weibull Dynamic Compare GPR AUC\\.pdf$"),
  list(stem = "Figure S6. Weibull dynamic model comparison C index",
       pat = "Weibull Dynamic Compare GPR Cindex\\.pdf$"),
  list(stem = "Figure S7. Weibull dynamic model comparison Accuracy",
       pat = "Weibull Dynamic Compare GPR Accuracy\\.pdf$"),
  list(stem = "Figure S8. Weibull dynamic model comparison Sensitivity",
       pat = "Weibull Dynamic Compare GPR Sensitivity\\.pdf$"),
  list(stem = "Figure S9. Weibull dynamic model comparison Specificity",
       pat = "Weibull Dynamic Compare GPR Specificity\\.pdf$")
)
for (w in .weibull) {
  we <- .pick("eicu", w$pat); wm <- .pick("mimic", w$pat)
  .combine(we, wm, file.path(pdf_dir, paste0(w$stem, ".pdf")), stack = FALSE)
}

# ── 删错号旧图（Fig4 KM、S1 Individual、S2 仅 AUC 等） ───────────────────────
cli::cli_h1("清理至 13 张")
# 先确保 S3/S4 png 在
.export_one(file.path(pdf_dir, "Figure S3. Piecewise Cox cut point search.pdf"))
.export_one(file.path(pdf_dir, "Figure S4. Subgroup analysis by trajectory class.pdf"))

for (subdir in c("pdf", "png", "tiff", "image_information")) {
  dd <- file.path(root_fig, subdir)
  if (!dir.exists(dd)) next
  exts <- switch(subdir, pdf = "\\.pdf$", png = "\\.png$", tiff = "\\.tiff$",
                 image_information = "\\.md$")
  for (fp in list.files(dd, pattern = exts, full.names = TRUE)) {
    stem <- sub("\\.(pdf|png|tiff|md)$", "", basename(fp), ignore.case = TRUE)
    if (identical(stem, "README")) next
    if (!(stem %in% .need)) {
      unlink(fp)
      cli::cli_alert_info("删 {basename(fp)}")
    }
  }
}
unlink(list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE))

meta <- list(
  exposure = ix, outcome = "28-day mortality", grouping = "2-class JLCM",
  databases = c("eICU", "MIMIC"), combined = TRUE,
  n_total = "eICU N=6941; MIMIC N=9660",
  study_type = "trajectory_prognosis"
)
pub_figure_refresh_image_information(root_fig, meta = meta, config = config)

# Fig1 逐步人数
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
  "双库 CONSORT 纳排流程图（A. eICU；B. MIMIC），样式与发病/预后 dual-batch Figure 1 一致。",
  "", "### 图上标注 / 逐步人数", .md_steps("eICU", ae), .md_steps("MIMIC", am), "",
  "## 分析上下文",
  "- 暴露: GPR", "- 结局: 28-day mortality",
  "- 样本量: eICU N=6,941; MIMIC N=9,660",
  "- Grouping: 2-class JLCM", "- 数据库: eICU, MIMIC", "- 是否拼图: 是", ""
), file.path(root_fig, "image_information/Figure 1. Flowchart of patient selection.md"), useBytes = TRUE)

have <- list.files(pdf_dir, pattern = "\\.pdf$")
miss <- setdiff(paste0(.need, ".pdf"), have)
cli::cli_alert_success("完成：pdf={length(have)} 张")
if (length(miss)) cli::cli_alert_danger("仍缺: {paste(miss, collapse=', ')}")
print(sort(have))
