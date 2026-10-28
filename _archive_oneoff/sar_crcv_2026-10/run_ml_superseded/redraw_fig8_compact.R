#!/usr/bin/env Rscript
# Fig8 紧凑重排：上排 ROC | mean(|SHAP|)，下排 beeswarm；正方形 ROC。
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
index_root <- get_arg(
  "--index-root",
  "/mnt/g/02block_result/33_AKI/prognosis_ml_40346649/by_index/\u3010success\u3011SAR+CrCV"
)

engine <- "/mnt/e/01block/01Block-new-Final"
setwd(engine)
suppressWarnings(suppressMessages({
  if (requireNamespace("workflows", quietly = TRUE)) {
    library(workflows)
  }
  if (requireNamespace("parsnip", quietly = TRUE)) library(parsnip)
  if (requireNamespace("recipes", quietly = TRUE)) library(recipes)
  source("R/utils.R")
  source("R/ml_stratified_ctx.R")
  source("R/ml_dual_dev_ext.R")
  source("R/ml_frozen_model_bundle.R")
  source("R/ml_external_frozen_shap.R")
  source("R/pub_figure_export.R")
}))

assets <- file.path(index_root, "publication_literature_final/_assets/model_assets/overall")
if (!dir.exists(assets)) {
  assets <- file.path(
    "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1",
    "by_index/\u3010success\u3011SAR+CrCV/publication_literature_final/_assets/model_assets/overall"
  )
}
stopifnot(dir.exists(assets))
fb <- ml_load_frozen_bundle(assets, expected_stratum = NULL)
tag_best <- ml_frozen_best_tag(fb) %||% names(fb$models)[[1]]
message("bundle models=", paste(names(fb$models), collapse = ","),
        " best=", tag_best)

mi <- readRDS("/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/checkpoints/by_index/SAR+CrCV/MIMIC_IV/ml_assoc_bundle.rds")
ei <- readRDS("/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/checkpoints/by_index/SAR+CrCV/eICU/ml_assoc_bundle.rds")
mi_imp <- mi$ctx$data$imputed
ei_imp <- ei$ctx$data$imputed
id_col <- as.character(mi$ctx$config$data$id_column %||% "ID")[1L]
mi_internal <- mi_imp[!is.na(match(as.character(mi_imp[[id_col]]),
                                   fb$internal_ids)), , drop = FALSE]
message("MIMIC internal n=", nrow(mi_internal), " eICU n=", nrow(ei_imp))

# 逐模型预测：个别引擎版本不兼容（如 xgboost）时跳过该模型曲线，不拖垮整图
predict_safe <- function(newdata, database) {
  ok_tags <- character(0)
  preds <- list()
  truth <- NULL
  for (m in names(fb$models)) {
    one <- tryCatch(
      ml_predict_external_bundle(fb, newdata, stratum = NULL,
                                 database = database, tags = m),
      error = function(e) {
        message("skip predict ", database, "/", m, ": ", conditionMessage(e))
        NULL
      }
    )
    if (is.null(one)) next
    preds[[m]] <- one$predictions[[m]]
    if (is.null(truth) && !is.null(one$predictions$truth)) {
      truth <- one$predictions$truth
    }
    ok_tags <- c(ok_tags, m)
    if (identical(database, "eICU") && !isTRUE(one$provenance$no_refit)) {
      stop("eICU refit detected for ", m, call. = FALSE)
    }
  }
  stopifnot(length(ok_tags) >= 1L, !is.null(truth))
  list(predictions = c(preds, list(truth = truth)), ok_tags = ok_tags)
}
mi_res <- predict_safe(mi_internal, "MIMIC-IV")
ei_res <- predict_safe(ei_imp, "eICU")
message("predict OK MIMIC=", paste(mi_res$ok_tags, collapse = ","),
        " eICU=", paste(ei_res$ok_tags, collapse = ","))

roc_multi <- function(res, database) {
  tags <- intersect(names(fb$models), res$ok_tags)
  lapply(tags, function(m) list(
    model = m,
    roc = ml_ref_roc_rows(
      res$predictions[[m]], res$predictions$truth,
      dataset = if (identical(database, "eICU")) "external_validation"
      else "internal_validation",
      model = m, stratum = "Overall", database = database
    )
  ))
}

message("SHAP MIMIC ...")
sh_i <- ml_shap_from_frozen_bundle(fb, mi_internal, tag = tag_best,
                                   sample_n = 200L, stratum = NULL)
message("SHAP eICU ...")
sh_e <- ml_shap_from_frozen_bundle(fb, ei_imp, tag = tag_best,
                                   sample_n = 200L, stratum = NULL)
stopifnot(identical(sh_i$model_checksum, sh_e$model_checksum))

cells <- list(
  list(database = "MIMIC-IV", stratum = "Overall", tag = tag_best,
       roc = roc_multi(mi_res, "MIMIC-IV"), shp = sh_i$shp),
  list(database = "eICU", stratum = "Overall", tag = tag_best,
       roc = roc_multi(ei_res, "eICU"), shp = sh_e$shp)
)

fig_name <- "Figure 8. Five-model ROC and SHAP in MIMIC-IV and eICU.pdf"
out <- file.path(tempdir(), fig_name)
p <- ml_ref_fig8_grid(cells, out_pdf = out)
stopifnot(file.exists(p$path))
message("built ", p$path, " size=", file.info(p$path)$size)

dests <- unique(c(
  file.path(index_root, "publication_literature_final", "Figures"),
  file.path(index_root, "summary_result", "Figures"),
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/publication_literature_final/Figures",
  "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28\u5929\u6b7b\u4ea1/by_index/\u3010success\u3011SAR+CrCV/summary_result/Figures"
))
for (fr in dests) {
  if (!dir.exists(dirname(fr))) next
  pdf_dir <- file.path(fr, "pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  file.copy(p$path, file.path(pdf_dir, fig_name), overwrite = TRUE)
  message("wrote ", file.path(pdf_dir, fig_name))
  tryCatch(
    pub_figure_ensure_formats(fr, config = list(pub_figures = list(dpi = 600L))),
    error = function(e) message("ensure: ", conditionMessage(e))
  )
  md <- file.path(fr, "image_information", sub("\\.pdf$", ".md", fig_name))
  dir.create(dirname(md), recursive = TRUE, showWarnings = FALSE)
  writeLines(c(
    "# Figure 8. Five-model ROC and SHAP in MIMIC-IV and eICU",
    "",
    "## 图面说明",
    "",
    "每库一块：上排左为五模型 ROC（正方形坐标），上排右为 mean(|SHAP|) 条形图；",
    "下排为 SHAP beeswarm（通栏）。MIMIC-IV 内验 + eICU 冻结外验（不重训）。",
    "",
    "### 图上标注",
    "",
    paste0("- best tag: ", tag_best),
    "",
    "## 分析上下文",
    "",
    "- 结局：28 天全因死亡",
    "- 数据库：MIMIC-IV（internal）+ eICU（external, no refit）",
    "- 分层：Overall（不按 SOFA）"
  ), md)
}
message("DONE fig8 compact")
