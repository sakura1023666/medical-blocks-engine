#!/usr/bin/env Rscript
# Fig2 重画：禁止 majority-swap，与 Table S5/S7/S8/KM 同一原始类别标签
# Class1 = 多数低风险，Class2 = 少数高风险
#
#   Rscript run/trajectory_prognosis/fix_ap_wpr_dual_fig2_class_labels.R

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(lcmm)
})

`%||%` <- function(a, b) if (is.null(a)) b else a

.engine <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.engine)
source(file.path(.engine, "R/utils.R"), local = FALSE)
source(file.path(.engine, "R/trajectory_survival_utils.R"), local = FALSE)
source(file.path(.engine, "R/pub_figure_export.R"), local = FALSE)
source(file.path(.engine, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.engine, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"), local = FALSE)

block_root <- {
  x <- Sys.getenv("BLOCK_RESULT_ROOT", "")
  if (nzchar(x) && dir.exists(x)) x
  else if (dir.exists("/mnt/g/02block_result")) "/mnt/g/02block_result"
  else "G:/02block_result"
}
index_root <- file.path(
  block_root, "41_AP/Prognosis_Trajectory_38882552_WPR_dual/by_index/WPR"
)
fig_root <- file.path(index_root, "Figures")
pdf_dir <- file.path(fig_root, "pdf")
stopifnot(dir.exists(index_root))

# identity map = raw JLCM labels (no majority swap)
id_map <- stats::setNames(c(1L, 2L), c("1", "2"))

.redraw_db <- function(db, db_lab) {
  jlcm_path <- file.path(
    index_root, db, "step14_trajectory_jlcm/Data/D01_jlcm_WPR_models.RData"
  )
  long2_path <- file.path(
    index_root, db, "step14_trajectory_jlcm/Data/D01_long_WPR_D_2.RData"
  )
  stopifnot(file.exists(jlcm_path), file.exists(long2_path))
  e <- new.env(parent = emptyenv())
  load(jlcm_path, envir = e)
  e_long <- new.env(parent = emptyenv())
  load(long2_path, envir = e_long)
  long2 <- e_long$long
  p <- .tpj04_make_plot(
    model_obj = e$models_list_with_cov$m2,
    long_data = long2,
    Index = "WPR",
    D = 2L,
    cycle = 28L,
    id_col = "subject_id",
    font_family = "sans",
    class_map = id_map
  )
  stopifnot(!is.null(p))
  out_db <- file.path(
    index_root, db, "Figures",
    sprintf("Figure 2-%s. Trajectory of WPR latent classes.pdf", db_lab)
  )
  dir.create(dirname(out_db), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(out_db, p, width = 7.8, height = 3.45, device = grDevices::cairo_pdf)
  file.copy(out_db, file.path(fig_root, basename(out_db)), overwrite = TRUE)
  cli::cli_alert_success("[{db_lab}] Fig2 redrawn (no majority-swap)")
  invisible(out_db)
}

.redraw_db("mimic", "MIMIC")
.redraw_db("eicu", "eICU")

a <- file.path(fig_root, "Figure 2-MIMIC. Trajectory of WPR latent classes.pdf")
b <- file.path(fig_root, "Figure 2-eICU. Trajectory of WPR latent classes.pdf")
out <- file.path(fig_root, "Figure 2. Trajectory of WPR latent classes.pdf")
ok <- tryCatch({
  .dual_db_compose_pair_pdf(
    a, b, out, layout = "stack",
    label_a = "A. MIMIC", label_b = "B. eICU",
    dpi = 200L, label_cex = 1.15
  )
  TRUE
}, error = function(e) {
  cli::cli_alert_danger("拼图失败: {e$message}")
  FALSE
})
stopifnot(isTRUE(ok), file.exists(out))
unlink(c(a, b))
dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
file.copy(out, file.path(pdf_dir, basename(out)), overwrite = TRUE)

# refresh four formats for Fig2 only
source(file.path(.engine, "configs/config_trajectory_prognosis_ap_wpr_dual.R"))
pub_figure_ensure_formats(fig_root, config = config)

# rewrite Fig2 image_information briefly
md <- file.path(fig_root, "image_information", "Figure 2. Trajectory of WPR latent classes.md")
writeLines(c(
  "# Figure 2. Trajectory of WPR latent classes",
  "",
  "## 图面说明",
  "本图为 2 类（主分析）WPR 轨迹均值曲线双库拼图（A. MIMIC，B. eICU）。",
  "类别标签与 Table S5 / S6 / S7 / S8 / KM / Table 3 一致，未做多数类交换：",
  "Class 1 = 多数、低均值 WPR、低 28 天死亡；Class 2 = 少数、高均值 WPR、高死亡。",
  "配色：Class 1 橙 (#D55E00)，Class 2 黄 (#E69F00)。",
  "",
  "图上标注：",
  "",
  "- MIMIC：Class1 n=865（死亡 10.2%）；Class2 n=45（死亡 68.9%）",
  "- eICU：Class1 n=431（死亡 5.8%）；Class2 n=16（死亡 50.0%）",
  "",
  "## 分析上下文",
  "- 暴露: WPR 2-class latent trajectory (primary)",
  "- 结局: 28-day in-hospital death（原字段 survival_28d）",
  "- 样本量: MIMIC=910; eICU=447",
  "- Grouping: 2-class (raw JLCM labels; Class1 majority)",
  "- 数据库: MIMIC, eICU",
  "- 是否拼图: 是",
  ""
), md, useBytes = TRUE)

cli::cli_alert_success("Fig2 已与表侧类别标签对齐")
