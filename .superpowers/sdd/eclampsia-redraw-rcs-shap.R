## 从 UA_CR checkpoint 重画 RCS（抬高 y）+ SHAP（C 置顶）
Sys.setenv(
  MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final",
  MEDICAL_BLOCKS_SKIP_WIN_R = "1"
)
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
ix_root <- file.path(study, "by_index/【success】UA_CR")
ck_dir <- file.path(study, "checkpoints/by_index/UA_CR/MIMIC_IV")

owd <- getwd()
setwd(root)
on.exit(setwd(owd), add = TRUE)
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
source(file.path(root, "R/ml_dual_pipeline_helpers.R"), local = FALSE)
source(file.path(root, "Blocks/15_rcs/02block_rcs_incidence.R"), local = FALSE)
source(file.path(root, "Blocks/17_shap/01block_shap.R"), local = FALSE)
if (!exists("run_block", mode = "function")) {
  ## 直接调用 block 函数
  run_block <- function(ctx, name, ...) {
    fn <- switch(name,
      rcs_incidence = block_rcs_incidence,
      shap = block_shap,
      stop("unknown block ", name)
    )
    fn(ctx, ...)
  }
}

cand <- c(
  file.path(ck_dir, "performance_ml.rds"),
  file.path(ck_dir, "ml_models_bundle.rds"),
  file.path(ck_dir, "ml_assoc_bundle.rds")
)
cand <- cand[file.exists(cand)]
if (!length(cand)) stop("no usable checkpoint in ", ck_dir)
ck_path <- cand[[1L]]
cat("load checkpoint:", ck_path, "\n")
pack <- readRDS(ck_path)
ctx <- pack$ctx
cfg <- ctx$config

## 覆盖 RCS / SHAP / 仅 quartile
cfg$rcs_incidence <- modifyList(cfg$rcs_incidence %||% list(), list(y_min = 0, y_max = 12))
cfg$shap <- modifyList(cfg$shap %||% list(), list(
  combine = TRUE,
  combine_layout = "waterfall_top",
  combine_rel_heights = c(1.2, 1.0, 1.4),
  combined_width = 12,
  combined_height = 16,
  dependence_ncol = 2L,
  n_dependence = 4L,
  pause_enable = FALSE
))
cfg$ml_batch$assoc_schemes <- "quartile"
cfg$logistic_tertile <- modifyList(cfg$logistic_tertile %||% list(), list(enable = FALSE))
cfg$logistic_binary <- modifyList(cfg$logistic_binary %||% list(), list(enable = FALSE))
cfg$plot <- modifyList(cfg$plot %||% list(), list(font_family = "Times New Roman", pdf_device = "cairo_pdf"))
ctx$config <- cfg

## 输出仍写回 success 指标目录对应 step
out_base <- file.path(ix_root, "MIMIC_IV")
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)

## 重跑 RCS
cat("\n=== rerun rcs_incidence ===\n")
ctx$output_dir <- file.path(out_base, "step20_rcs_incidence")
dir.create(ctx$output_dir, recursive = TRUE, showWarnings = FALSE)
ctx <- run_block(ctx, "rcs_incidence")
if (exists("render_queued_figures", mode = "function")) ctx <- render_queued_figures(ctx)

## 重跑 SHAP（需要 ml models 结果）
cat("\n=== rerun shap ===\n")
ctx$output_dir <- file.path(out_base, "step31_shap")
dir.create(ctx$output_dir, recursive = TRUE, showWarnings = FALSE)
ctx <- run_block(ctx, "shap")
if (exists("render_queued_figures", mode = "function")) ctx <- render_queued_figures(ctx)

## 把定稿 PDF 拷到 Figures/pdf
pub <- file.path(ix_root, "Figures/pdf")
dir.create(pub, recursive = TRUE, showWarnings = FALSE)
## 找最新 RCS / SHAP pdf
rcs_pdf <- list.files(file.path(out_base, "step20_rcs_incidence"), pattern = "RCS.*\\.pdf$",
                      recursive = TRUE, full.names = TRUE)
shap_pdf <- list.files(file.path(out_base, "step31_shap"), pattern = "SHAP.*\\.pdf$",
                       recursive = TRUE, full.names = TRUE)
## 优先 combined / Figure 命名
pick_latest <- function(paths, prefer = NULL) {
  if (!length(paths)) return(NA_character_)
  if (!is.null(prefer)) {
    hit <- paths[grepl(prefer, basename(paths), ignore.case = TRUE)]
    if (length(hit)) paths <- hit
  }
  paths[which.max(file.info(paths)$mtime)]
}
rcs1 <- pick_latest(rcs_pdf)
shap1 <- pick_latest(shap_pdf, prefer = "combined|Figure.*SHAP|SHAP \\(")
if (is.na(shap1) || !nzchar(shap1)) shap1 <- pick_latest(shap_pdf)
cat("RCS src:", rcs1, "\n")
cat("SHAP src:", shap1, "\n")
if (is.character(rcs1) && file.exists(rcs1)) {
  file.copy(rcs1, file.path(pub, "Figure 2. RCS plot between UA CR and Case.pdf"), overwrite = TRUE)
  file.copy(rcs1, file.path(out_base, "Figures/Figure 2. RCS plot between UA CR and Case.pdf"), overwrite = TRUE)
}
if (is.character(shap1) && file.exists(shap1)) {
  file.copy(shap1, file.path(pub, "Figure 5. SHAP.pdf"), overwrite = TRUE)
  file.copy(shap1, file.path(out_base, "Figures/Figure 5. SHAP.pdf"), overwrite = TRUE)
}

## 更新 image_information 简要说明
writeLines(c(
  "# Figure 2. RCS plot between UA CR and Case",
  "",
  "## 图面说明",
  "限制性立方样条（RCS）展示 UA_CR 与 Case 的剂量-反应关系：A 粗模型、B Model1（Age）、C Model2（Age+Language+RBC）。",
  "实线为 OR，阴影为 95%CI；C 面板标注 OR=1 主切点。纵轴已抬高至 OR=12，避免高位 CI 被裁切。",
  "",
  "## 分析上下文",
  "- 暴露: UA_CR",
  "- 结局: DN（Case/Control）",
  "- 样本量: n=509",
  "- Grouping: 与 Table 2 四分位闸门一致",
  "- 数据库: MIMIC IV",
  "- 是否拼图: 是（A/B/C）"
), file.path(ix_root, "Figures/image_information/Figure 2. RCS plot between UA CR and Case.md"))

writeLines(c(
  "# Figure 5. SHAP",
  "",
  "## 图面说明",
  "基于最优 ML 模型（LightGBM）的 SHAP 解释图。排版：C（waterfall）置顶全宽；中行 A 重要性条形 + B 蜂群；底行 D 为 dependence（2×2）。",
  "特征与 LASSO 最终集一致：UA_CR、ALT、Marital_Status、Hematocrit。",
  "",
  "## 分析上下文",
  "- 暴露: UA_CR",
  "- 结局: DN（Case/Control）",
  "- 样本量: n=509（解释于训练集）",
  "- Grouping: 与主文一致",
  "- 数据库: MIMIC IV",
  "- 是否拼图: 是（A/B/C/D）"
), file.path(ix_root, "Figures/image_information/Figure 5. SHAP.md"))

cat("DONE redraw\n")
