#!/usr/bin/env Rscript
###############################################################################
# redraw_shap_pub_figure.R — 薄 CLI（方法在 Blocks/17_shap，禁止本文件写业务）
#
# 加载链：
#   00shap_router.R              — 符号对齐
#   01block_shap.R               — 面板 helper + source 00shap_display_common.R
#   .shap_build_pub_combined_figure — 发表拼图（display_common）
#
# 用法（引擎根）：
#   MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
#   Rscript run/ml/redraw_shap_pub_figure.R \
#     --index-root ".../by_index/【success】UA_CR" \
#     --analysis-group "CKM stage 2-3" \
#     --reference-group "CKM stage 0-1" \
#     --tag xgboost
#
# 可选：--config <config.R>；--out <pdf>；--layout grid2x2|abc_top|waterfall_top
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  args[[hit[[1]] + 1L]]
}

eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(eng) || !dir.exists(file.path(eng, "R"))) {
  eng <- "/mnt/e/01block/01Block-new-Final"
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = eng)
setwd(eng)

suppressPackageStartupMessages({
  ## 只 source SHAP 方法块：01block 会挂 router + display_common
  source(file.path(eng, "R/utils.R"), local = FALSE)
  source(file.path(eng, "Blocks/17_shap/01block_shap.R"), local = FALSE)
})

ix_root <- get_opt("--index-root", NULL)
if (is.null(ix_root) || !nzchar(ix_root)) {
  stop("必须传 --index-root <指标【success】根目录>", call. = FALSE)
}
ix_root <- normalizePath(ix_root, winslash = "/", mustWork = TRUE)

cfg_path <- get_opt("--config", NULL)
ana <- get_opt("--analysis-group", NULL)
ref <- get_opt("--reference-group", NULL)
disease <- get_opt("--disease", "Case")
tag <- as.character(get_opt("--tag", "xgboost"))[1L]
layout <- as.character(get_opt("--layout", "grid2x2"))[1L]
out_pdf <- get_opt("--out", NULL)

if (!is.null(cfg_path) && nzchar(cfg_path) && file.exists(cfg_path)) {
  source(normalizePath(cfg_path, winslash = "/", mustWork = TRUE), local = FALSE)
  if (exists("config") && is.list(config)) {
    ana <- ana %||% config$project$analysis_group %||% config$project$disease
    ref <- ref %||% config$project$reference_group
    disease <- config$project$disease %||% disease
  }
}
ana <- as.character(ana %||% "Case")[1L]
ref <- as.character(ref %||% "Control")[1L]

shiny_dir <- file.path(ix_root, "summary_results", "Shiny")
if (!dir.exists(shiny_dir)) shiny_dir <- file.path(ix_root, "Shiny")
if (!dir.exists(shiny_dir)) shiny_dir <- file.path(ix_root, "ShinyApp")
rdata <- file.path(shiny_dir, paste0("evalresult_", tag, ".RData"))
if (!file.exists(rdata)) {
  cands <- list.files(shiny_dir, pattern = "^evalresult_.*\\.RData$", full.names = TRUE)
  if (!length(cands)) stop("找不到 evalresult_*.RData: ", shiny_dir, call. = FALSE)
  rdata <- cands[[1L]]
  tag <- sub("^evalresult_", "", sub("\\.RData$", "", basename(rdata)))
}
load(rdata)
wf_nm <- paste0("final_", tag)
if (!exists(wf_nm, inherits = FALSE)) {
  alts <- grep("^final_", ls(envir = .GlobalEnv), value = TRUE)
  if (!length(alts)) stop("RData 内无 final_* workflow: ", rdata, call. = FALSE)
  wf_nm <- alts[[1L]]
  tag <- sub("^final_", "", wf_nm)
}
wf <- get(wf_nm, envir = .GlobalEnv)

ctx <- list(config = list(
  project = list(
    analysis_group = ana,
    reference_group = ref,
    disease = disease
  ),
  shap = list(combine_layout = layout, collapse_baked_dummies = TRUE)
))

sh <- ctx$config$shap
if (!exists(".shap_build_pub_combined_figure", mode = "function")) {
  stop("未加载 .shap_build_pub_combined_figure（检查 Blocks/17_shap/00shap_display_common.R）",
       call. = FALSE)
}
built <- .shap_build_pub_combined_figure(wf, ctx = ctx, sh = sh, tag = tag)
cli::cli_alert_info(
  "SHAP redraw: flipped={built$flipped}; layout={built$layout}; waterfall_row={built$waterfall_row}"
)

if (is.null(out_pdf) || !nzchar(out_pdf)) {
  out_pdf <- file.path(ix_root, "summary_results", "Figures", "pdf", "Figure 4. SHAP.pdf")
}
dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
ff <- built$font_family
ggplot2::ggsave(
  out_pdf, built$fig,
  width = 16, height = 11,
  device = grDevices::cairo_pdf, family = ff
)
cli::cli_alert_success("wrote {out_pdf}")

## 镜像到常见分库/step 路径（存在则覆盖）
mirrors <- c(
  file.path(ix_root, "Figures", "pdf", "Figure 4. SHAP.pdf"),
  file.path(ix_root, "CHARLS", "Figures", "pdf", "Figure 4. SHAP.pdf"),
  file.path(ix_root, "CHARLS", "step36_shap", "Figures",
            paste0("Figure 4. SHAP — ", .shap_model_display_name(ctx, tag), ".pdf"))
)
for (m in mirrors) {
  if (!dir.exists(dirname(dirname(m))) && !dir.exists(dirname(m))) next
  dir.create(dirname(m), recursive = TRUE, showWarnings = FALSE)
  ok <- tryCatch({
    file.copy(out_pdf, m, overwrite = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (isTRUE(ok)) cli::cli_alert_info("mirror {m}")
}

md_paths <- c(
  file.path(ix_root, "summary_results", "Figures", "image_information", "Figure 4. SHAP.md"),
  file.path(ix_root, "Figures", "image_information", "Figure 4. SHAP.md")
)
md <- paste0(
  "# Figure 4. SHAP\n\n",
  "## 图面说明\n",
  "版式为引擎默认 **", built$layout, "**：A 重要性、B 蜂群、C 瀑布、D 依赖。",
  "符号对齐 analysis_group「", ana, "」",
  if (isTRUE(built$flipped)) "（已翻转）" else "",
  "；分类 recipe dummy 已折叠为临床变量名。\n\n",
  "## 分析上下文\n",
  "- 结局: ", ana, " vs ", ref, "\n",
  "- 模型: ", tag, "\n",
  "- 瀑布行: ", built$waterfall_row, "\n",
  "- 依赖特征: ", paste(built$dependence_features, collapse = ", "), "\n"
)
for (mp in md_paths) {
  dir.create(dirname(mp), recursive = TRUE, showWarnings = FALSE)
  writeLines(md, mp)
}
cli::cli_alert_success("DONE")
