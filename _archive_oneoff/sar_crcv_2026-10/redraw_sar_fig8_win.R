# Figure 8 on Windows R so the frozen XGBoost booster matches the training build.
suppressPackageStartupMessages({
  library(workflows)
  library(parsnip)
  library(recipes)
  library(xgboost)
  library(lightgbm)
})
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
}
engine <- "E:/01block/01Block-new-Final"
study <- "G:/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28天死亡"
out_pdf <- "E:/01block/01Block-new-Final/tmp/Figure8_overall.pdf"
auc_csv <- "E:/01block/01Block-new-Final/tmp/fig8_auc.csv"
assets_overall <- paste0(
  study, "/by_index/【success】SAR+CrCV/publication_literature_final/_assets/model_assets/overall"
)
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
suppressWarnings(suppressMessages({
  source(file.path(engine, "R/utils.R"))
  source(file.path(engine, "R/ml_dual_dev_ext.R"))
  source(file.path(engine, "R/ml_frozen_model_bundle.R"))
  source(file.path(engine, "R/ml_external_frozen_shap.R"))
}))
ck <- file.path(study, "checkpoints", "by_index", "SAR+CrCV")
mi_ml <- readRDS(file.path(ck, "MIMIC_IV", "step17_ml_models_bundle.rds"))$ctx
ei_ext <- readRDS(file.path(ck, "eICU", "step16_ml_eval_external.rds"))$ctx
relabel_outcome <- function(df) {
  if (!is.data.frame(df)) return(df)
  map_lvl <- function(v) {
    lv <- levels(v) %||% character(0)
    if (length(lv)) {
      new_lv <- ifelse(lv == "AKI", "Non-survivor",
                       ifelse(lv == "No AKI", "Survivor", lv))
      out <- new_lv[as.integer(v)]
      keep <- !(lv %in% c("AKI", "No AKI"))
      out[keep[as.integer(v)]] <- as.character(v)[keep[as.integer(v)]]
      factor(out, levels = union(c("Survivor", "Non-survivor"), new_lv[keep]))
    } else {
      raw <- trimws(as.character(v))
      out <- ifelse(raw == "AKI", "Non-survivor",
                    ifelse(raw == "No AKI", "Survivor", raw))
      factor(out, levels = c("Survivor", "Non-survivor"))
    }
  }
  if ("Group" %in% names(df)) df$Group <- map_lvl(df$Group)
  if ("fustatus" %in% names(df)) df$fustatus <- map_lvl(df$fustatus)
  df
}
mi_ml$data <- lapply(mi_ml$data, relabel_outcome)
ei_ext$data <- lapply(ei_ext$data, relabel_outcome)
fb <- ml_load_frozen_bundle(assets_overall)
id_col <- as.character(mi_ml$config$data$id_column %||% "ID")[1L]
mi_all <- mi_ml$data$imputed
internal <- mi_all[!is.na(match(as.character(mi_all[[id_col]]), fb$internal_ids)), , drop = FALSE]
mi_res <- ml_predict_external_bundle(fb, internal, stratum = NULL, database = "MIMIC-IV")
ei_res <- ml_predict_external_bundle(fb, ei_ext$data$imputed, stratum = NULL, database = "eICU")
stopifnot(isTRUE(ei_res$provenance$no_refit))
tag <- ml_frozen_best_tag(fb) %||% names(fb$models)[[1]]
message("best tag=", tag)
sh_i <- ml_shap_from_frozen_bundle(fb, internal, tag = tag, sample_n = 200L)
sh_e <- ml_shap_from_frozen_bundle(fb, ei_ext$data$imputed, tag = tag, sample_n = 200L)
roc_multi <- function(res, database) {
  lapply(names(fb$models), function(m) list(
    model = m,
    roc = ml_ref_roc_rows(
      res$predictions[[m]], res$predictions$truth,
      dataset = if (database == "eICU") "external_validation" else "internal_validation",
      model = m, stratum = "Overall", database = database
    )
  ))
}
cells <- list(
  list(database = "MIMIC-IV", stratum = "Overall", tag = tag,
       roc = roc_multi(mi_res, "MIMIC-IV"), shp = sh_i$shp),
  list(database = "eICU", stratum = "Overall", tag = tag,
       roc = roc_multi(ei_res, "eICU"), shp = sh_e$shp)
)
p <- ml_ref_fig8_grid(cells, out_pdf = out_pdf)
utils::write.csv(p$auc, auc_csv, row.names = FALSE)
message("FIG8_OK")
