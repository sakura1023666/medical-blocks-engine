## 仅重画 SHAP：A|B|C 同行 + D 在下（abc_top）
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
source(file.path(root, "Blocks/17_shap/01block_shap.R"), local = FALSE)

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

cfg$shap <- modifyList(cfg$shap %||% list(), list(
  combine = TRUE,
  combine_layout = "abc_top",
  combine_rel_heights = c(1, 1.1),
  combined_width = 16,
  combined_height = 10.5,
  dependence_ncol = 2L,
  n_dependence = 4L,
  pause_enable = FALSE
))
cfg$plot <- modifyList(cfg$plot %||% list(), list(
  font_family = "Times New Roman",
  pdf_device = "cairo_pdf"
))
ctx$config <- cfg

out_base <- file.path(ix_root, "MIMIC_IV")
dir.create(out_base, recursive = TRUE, showWarnings = FALSE)
ctx$output_dir <- file.path(out_base, "step31_shap")
dir.create(ctx$output_dir, recursive = TRUE, showWarnings = FALSE)

cat("\n=== rerun shap (abc_top) ===\n")
ctx <- block_shap(ctx)
if (exists("render_queued_figures", mode = "function")) ctx <- render_queued_figures(ctx)

pub <- file.path(ix_root, "Figures/pdf")
dir.create(pub, recursive = TRUE, showWarnings = FALSE)
shap_pdf <- list.files(
  file.path(out_base, "step31_shap"),
  pattern = "SHAP.*\\.pdf$",
  recursive = TRUE,
  full.names = TRUE
)
pick_latest <- function(paths, prefer = NULL) {
  if (!length(paths)) return(NA_character_)
  if (!is.null(prefer)) {
    hit <- paths[grepl(prefer, basename(paths), ignore.case = TRUE)]
    if (length(hit)) paths <- hit
  }
  paths[which.max(file.info(paths)$mtime)]
}
shap1 <- pick_latest(shap_pdf, prefer = "combined|Figure.*SHAP|SHAP \\(")
if (is.na(shap1) || !nzchar(shap1)) shap1 <- pick_latest(shap_pdf)
cat("SHAP src:", shap1, "\n")
if (is.character(shap1) && file.exists(shap1)) {
  file.copy(shap1, file.path(pub, "Figure 5. SHAP.pdf"), overwrite = TRUE)
  file.copy(shap1, file.path(out_base, "Figures/Figure 5. SHAP.pdf"), overwrite = TRUE)
  cat("copied -> Figure 5. SHAP.pdf\n")
}

md <- file.path(ix_root, "Figures/image_information/Figure 5. SHAP.md")
writeLines(c(
  "# Figure 5. SHAP",
  "",
  "## 图面说明",
  "基于最优 ML 模型（LightGBM）的 SHAP 解释图。排版：上行 A（importance）| B（bee）| C（waterfall）同行；下行 D 为 dependence（2×2）。",
  "特征与 LASSO 最终集一致：UA_CR、ALT、Marital_Status、Hematocrit。",
  "",
  "## 分析上下文",
  "- 暴露: UA_CR",
  "- 结局: DN（Case/Control）",
  "- 样本量: n=509（解释于训练集）",
  "- Grouping: 与主文一致",
  "- 数据库: MIMIC IV",
  "- 是否拼图: 是（A/B/C/D）"
), md)
cat("done\n")
