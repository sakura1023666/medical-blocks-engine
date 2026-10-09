#!/usr/bin/env Rscript
# GPR 2 类发表终整理：真 Fig1、根 Tables 对齐分库、image_information=2-class、清平铺残留
#
#   Rscript run/trajectory_prognosis/repair_gpr_2class_pub_finalize.R \
#     [/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr]

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
db_seq <- c("eicu", "mimic")

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(.root, "R/trajectory_paper_tables.R"))
source(file.path(.root, "R/trajectory_survival_utils.R"))
source(file.path(study_root, "config.R"))
config$feishu$enable <- FALSE

hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
out_ix <- hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))][[1L]]
root_fig <- file.path(out_ix, "Figures")
root_tab <- file.path(out_ix, "Tables")
dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)

.combine_pair <- function(left, right, dest, lab_a = "A. eICU", lab_b = "B. MIMIC",
                          width = 12, height = 5.2) {
  stopifnot(file.exists(left), file.exists(right))
  a <- magick::image_read_pdf(left, density = 160)[1]
  b <- magick::image_read_pdf(right, density = 160)[1]
  a <- magick::image_annotate(a, lab_a, size = 26, gravity = "northwest", location = "+16+12")
  b <- magick::image_annotate(b, lab_b, size = 26, gravity = "northwest", location = "+16+12")
  tmp <- tempfile(fileext = ".png")
  magick::image_write(magick::image_append(c(a, b)), path = tmp, format = "png")
  img <- png::readPNG(tmp)
  grDevices::pdf(dest, width = width, height = height, useDingbats = FALSE)
  graphics::par(mar = c(0, 0, 0, 0), xaxs = "i", yaxs = "i")
  graphics::plot.new()
  graphics::rasterImage(img, 0, 0, 1, 1)
  grDevices::dev.off()
  unlink(tmp)
  dest
}

cli::cli_h1("1) 真实 Fig1（step24）盖回分库 + 根拼图")

fig1_unit <- list()
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  fig <- file.path(unit, "Figures")
  src <- file.path(unit, "step24_attrition_flowchart/Figures/Figure 1. Flowchart.pdf")
  if (!file.exists(src)) {
    # _raw 里可能是真图
    cand <- file.path(fig, "_raw/Figure 1. Flowchart.pdf")
    if (file.exists(cand) && file.info(cand)$size > 10000) src <- cand
  }
  if (!file.exists(src)) stop("缺少真实纳排图: ", db)
  dest1 <- file.path(fig, sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab))
  dest0 <- file.path(fig, "Figure 1. Flowchart.pdf")
  file.copy(src, dest1, overwrite = TRUE)
  file.copy(src, dest0, overwrite = TRUE)
  fig1_unit[[db]] <- dest1
  txt <- tryCatch(system2("pdftotext", c("-layout", dest1, "-"), stdout = TRUE), error = function(e) "")
  if (any(grepl("PLACEHOLDER", txt, ignore.case = TRUE)))
    stop(db, " Fig1 仍是占位图，源文件异常: ", src)
  cli::cli_alert_success("{db_lab} Fig1 <- {.file {basename(src)}} ({file.info(src)$size} bytes)")
}

fig1_root <- file.path(root_fig, "Figure 1. Flowchart of patient selection.pdf")
.combine_pair(fig1_unit$eicu, fig1_unit$mimic, fig1_root, width = 11, height = 5.0)
dir.create(file.path(root_fig, "pdf"), recursive = TRUE, showWarnings = FALSE)
file.copy(fig1_root, file.path(root_fig, "pdf/Figure 1. Flowchart of patient selection.pdf"), overwrite = TRUE)
.pub_figure_rasterize_one(
  file.path(root_fig, "pdf/Figure 1. Flowchart of patient selection.pdf"),
  file.path(root_fig, "png/Figure 1. Flowchart of patient selection.png"),
  file.path(root_fig, "tiff/Figure 1. Flowchart of patient selection.tiff"),
  300L, root_hint = .root
)
cli::cli_alert_success("根 Fig1 拼图已更新")

cli::cli_h1("2) 根 Tables：按分库正式 S1–S8 + Table1–3 重建")

# 分库补 S8（后验分类）
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  tab <- file.path(unit, "Tables")
  dest_s8 <- file.path(tab, sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab))
  if (!file.exists(dest_s8)) {
    arch <- list.files(file.path(tab, "_archive"), pattern = "Posterior classification", full.names = TRUE)
    arch <- arch[grepl(db_lab, basename(arch), fixed = TRUE)]
    if (length(arch)) {
      file.copy(arch[which.max(file.info(arch)$mtime)], dest_s8, overwrite = TRUE)
    } else {
      # 从 JLCM m2 + 对齐映射重导
      align_csv <- file.path(root_tab, "Summary/class_align_GPR.csv")
      mp <- NULL
      if (file.exists(align_csv)) {
        al <- utils::read.csv(align_csv, stringsAsFactors = FALSE)
        sub <- al[al$db == db, , drop = FALSE]
        if (nrow(sub)) mp <- stats::setNames(as.integer(sub$new_class), as.character(sub$old_class))
      }
      rdata <- file.path(unit, "step14_trajectory_jlcm/Data/D01_jlcm_GPR_models.RData")
      if (file.exists(rdata)) {
        env <- new.env(parent = emptyenv())
        load(rdata, envir = env)
        tryCatch(
          trajectory_export_posterior_classification_sci(
            list(output_dir_tables = tab), env$models_list_with_cov$m2, dest_s8,
            sprintf("Table S8. Posterior classification table (%s, %s)", ix, db_lab),
            class_map = mp
          ),
          error = function(e) cli::cli_alert_warning("S8 {db_lab}: {e$message}")
        )
      }
    }
  }
  # Weibull / KM 从 archive 恢复到分库 Tables（不改号，附名）
  for (nm in c("Table_Weibull_Dynamic_Compare_GPR.csv",
               "Table_KM_TrajectoryClass_GPR_Events.csv",
               "Table_KM_TrajectoryClass_GPR_LogRank.csv")) {
    a <- file.path(tab, "_archive", nm)
    if (file.exists(a) && !file.exists(file.path(tab, nm)))
      file.copy(a, file.path(tab, nm), overwrite = TRUE)
  }
}

# 根 Tables 归档旧乱号
arch_root <- file.path(root_tab, "_archive_messy")
dir.create(arch_root, recursive = TRUE, showWarnings = FALSE)
keep_summary <- file.path(root_tab, "Summary")
for (f in list.files(root_tab, full.names = TRUE)) {
  if (identical(normalizePath(f, mustWork = FALSE), normalizePath(keep_summary, mustWork = FALSE))) next
  if (identical(basename(f), "_archive_messy")) next
  if (dir.exists(f)) next
  file.rename(f, file.path(arch_root, basename(f)))
}

# 从分库拷正式表到根
canon <- function(db_lab) {
  c(
    sprintf("Table 1-%s. Baseline characteristics of Sepsis AKI.xlsx", db_lab),
    sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab),
    sprintf("Table 3-%s. Time-dependent HR for trajectory classes.xlsx", db_lab),
    sprintf("Table S1-%s. Baseline characteristics of patients before and after multiple imputation.xlsx", db_lab),
    sprintf("Table S2-%s. Normality test results for continuous variables.xlsx", db_lab),
    sprintf("Table S3-%s. Univariate Regression Analysis.xlsx", db_lab),
    sprintf("Table S4-%s. Multicollinearity Analysis (VIF, univariate screen).xlsx", db_lab),
    sprintf("Table S5-%s. Multivariable Regression Analysis.xlsx", db_lab),
    sprintf("Table S6-%s. Multicollinearity Analysis (VIF, multivariate final).xlsx", db_lab),
    sprintf("Table S7-%s. Baseline characteristics by trajectory class (%s).xlsx", db_lab, ix),
    sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab)
  )
}
n_copy <- 0L
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  tab <- file.path(out_ix, db, "Tables")
  for (nm in canon(db_lab)) {
    src <- file.path(tab, nm)
    if (!file.exists(src)) {
      cli::cli_alert_warning("缺表: {nm}")
      next
    }
    file.copy(src, file.path(root_tab, nm), overwrite = TRUE)
    n_copy <- n_copy + 1L
  }
}
# README
writeLines(c(
  "# Tables（GPR 2-class 发表用）",
  "",
  "根目录表与分库 `eicu/Tables`、`mimic/Tables` 同号同角色。",
  "",
  "| 编号 | 内容 |",
  "|---|---|",
  "| Table 1 | 基线特征 |",
  "| Table 2 | 选类指标（m1–m6） |",
  "| Table 3 | 分段/时变 HR |",
  "| Table S1 | 插补前后基线 |",
  "| Table S2 | 正态性 |",
  "| Table S3 | 单因素 |",
  "| Table S4 | VIF（单因素筛） |",
  "| Table S5 | 多因素 |",
  "| Table S6 | VIF（多因素终） |",
  "| Table S7 | 按轨迹类基线（2 类） |",
  "| Table S8 | 后验分类表（2 类） |",
  "",
  "旧乱号表已移至 `_archive_messy/`。",
  paste0("整理时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
), file.path(root_tab, "README.md"))
cli::cli_alert_success("根 Tables 已重建：{n_copy} 个文件")

cli::cli_h1("3) 清平铺残留 + image_information → 2-class")

unlink(list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE))
# 确保 pdf/ 有齐 13 张（Fig1 已写；其余保留）
need <- c(
  "Figure 1. Flowchart of patient selection.pdf",
  "Figure 2. Trajectory of GPR latent classes.pdf",
  "Figure 3. Dynamic prediction of GPR trajectory.pdf",
  "Figure 4. Individual dynamic prediction.pdf",
  "Figure S1. Missing value overview.pdf",
  "Figure S2. Kaplan Meier survival by trajectory class.pdf",
  "Figure S3. Piecewise Cox cut point search.pdf",
  "Figure S4. Subgroup analysis by trajectory class.pdf",
  "Figure S5. Weibull dynamic model comparison AUC.pdf",
  "Figure S6. Weibull dynamic model comparison C index.pdf",
  "Figure S7. Weibull dynamic model comparison Accuracy.pdf",
  "Figure S8. Weibull dynamic model comparison Sensitivity.pdf",
  "Figure S9. Weibull dynamic model comparison Specificity.pdf"
)
pdf_dir <- file.path(root_fig, "pdf")
have <- list.files(pdf_dir, pattern = "\\.pdf$")
miss <- setdiff(need, have)
if (length(miss)) cli::cli_alert_warning("pdf 仍缺: {paste(miss, collapse=', ')}")

meta <- list(
  exposure = ix,
  outcome = "28-day mortality",
  grouping = "2-class JLCM",
  databases = c("eICU", "MIMIC"),
  combined = TRUE,
  n_total = "eICU N=6941; MIMIC N=9660",
  study_type = "trajectory_prognosis"
)
# 把 attrition CSV 挂到 findings，供 Fig1 md 写逐步人数
meta$findings <- list(
  attrition = list(
    eICU = utils::read.csv(
      file.path(out_ix, "eicu/step24_attrition_flowchart/Tables/Flowchart_attrition_eicu.csv"),
      stringsAsFactors = FALSE
    ),
    MIMIC = utils::read.csv(
      file.path(out_ix, "mimic/step24_attrition_flowchart/Tables/Flowchart_attrition_mimic.csv"),
      stringsAsFactors = FALSE
    )
  ),
  association = list(),
  cutoffs = list(),
  roc = list(),
  maxstat = list()
)

# 若 harvest 支持从 Tables 读 KM，再补一层
meta$findings <- tryCatch({
  h <- pub_figure_harvest_findings(root_fig, meta)
  h$attrition <- meta$findings$attrition
  h
}, error = function(e) meta$findings)

n_md <- pub_figure_refresh_image_information(root_fig, meta = meta, config = config)
cli::cli_alert_success("image_information 已刷 {length(n_md)} 份（Grouping=2-class JLCM）")

# Fig1 md 强制写入逐步人数（避免 harvest 结构不认）
.md_fig1 <- function() {
  md <- file.path(root_fig, "image_information/Figure 1. Flowchart of patient selection.md")
  ae <- meta$findings$attrition$eICU
  am <- meta$findings$attrition$MIMIC
  .steps <- function(db, d) {
    if (is.null(d) || !nrow(d)) return(paste0(db, ": 未收获"))
    lines <- character(0)
    for (i in seq_len(nrow(d))) {
      n <- as.integer(d$n[i])
      step <- as.character(d$step[i])
      if (i == 1L) {
        lines <- c(lines, sprintf("- %s：%s，保留 n=%s", db, step, format(n, big.mark = ",")))
      } else {
        drop <- as.integer(d$n[i - 1L]) - n
        lines <- c(lines, sprintf("- %s：%s，保留 n=%s（本步排除 %s 人）",
                                  db, step, format(n, big.mark = ","), format(drop, big.mark = ",")))
      }
    }
    lines
  }
  lines <- c(
    "# Figure 1. Flowchart of patient selection",
    "",
    "## 图面说明",
    "双库拼图纳排流程图（A. eICU；B. MIMIC）。展示从数据清洗到插补后进入轨迹分析队列的逐步保留人数。",
    "",
    "### 图上标注 / 逐步人数",
    .steps("eICU", ae),
    .steps("MIMIC", am),
    "",
    "## 分析上下文",
    "- 暴露: GPR",
    "- 结局: 28-day mortality",
    "- 样本量: eICU N=6,941; MIMIC N=9,660（插补后分析集）",
    "- Grouping: 2-class JLCM",
    "- 数据库: eICU, MIMIC",
    "- 是否拼图: 是",
    ""
  )
  writeLines(lines, md, useBytes = TRUE)
}
.md_fig1()

# 核验（pdftotext 写临时文件；拼图可能无文本层，改查分库单图）
.tmp_txt <- tempfile(fileext = ".txt")
on.exit(unlink(.tmp_txt), add = TRUE)
system2("pdftotext", c("-layout", fig1_unit$eicu, .tmp_txt), stdout = FALSE, stderr = FALSE)
chk_txt <- if (file.exists(.tmp_txt)) readLines(.tmp_txt, warn = FALSE) else character(0)
if (any(grepl("PLACEHOLDER", chk_txt, ignore.case = TRUE)))
  stop("分库 Fig1 仍含 PLACEHOLDER")
grp_bad <- tryCatch(
  system2("rg", c("-l", "3-class JLCM", file.path(root_fig, "image_information")),
          stdout = TRUE, stderr = FALSE),
  error = function(e) character(0)
)
if (length(grp_bad)) {
  cli::cli_alert_warning("仍含 3-class 的 md: {paste(basename(grp_bad), collapse=', ')}")
} else {
  cli::cli_alert_success("image_information 已无 3-class 残留")
}

cli::cli_alert_success(
  "完成。pdf={length(list.files(file.path(root_fig,'pdf'), pattern='\\\\.pdf$'))}  tables_root={length(list.files(root_tab, pattern='\\\\.xlsx$'))}"
)
