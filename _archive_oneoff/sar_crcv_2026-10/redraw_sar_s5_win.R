suppressPackageStartupMessages({
  library(workflows); library(parsnip); library(recipes)
  library(xgboost); library(lightgbm)
})
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
}
engine <- "E:/01block/01Block-new-Final"
study <- "G:/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28天死亡"
assets_overall <- paste0(study, "/by_index/【success】SAR+CrCV/publication_literature_final/_assets/model_assets/overall")
out_pdf <- "E:/01block/01Block-new-Final/tmp/FigureS5_overall.pdf"
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
      new_lv <- ifelse(lv == "AKI", "Non-survivor", ifelse(lv == "No AKI", "Survivor", lv))
      out <- new_lv[as.integer(v)]
      keep <- !(lv %in% c("AKI", "No AKI"))
      out[keep[as.integer(v)]] <- as.character(v)[keep[as.integer(v)]]
      factor(out, levels = union(c("Survivor", "Non-survivor"), new_lv[keep]))
    } else {
      raw <- trimws(as.character(v))
      factor(ifelse(raw == "AKI", "Non-survivor", ifelse(raw == "No AKI", "Survivor", raw)),
             levels = c("Survivor", "Non-survivor"))
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
internal <- mi_ml$data$imputed[!is.na(match(as.character(mi_ml$data$imputed[[id_col]]), fb$internal_ids)), , drop = FALSE]
tag <- "logistic"
sh_i <- ml_shap_from_frozen_bundle(fb, internal, tag = tag, sample_n = 200L)
sh_e <- ml_shap_from_frozen_bundle(fb, ei_ext$data$imputed, tag = tag, sample_n = 200L)
one <- function(sh, database) {
  meta <- data.frame(
    database = database, stratum = "Overall",
    row_id = seq_along(sh$truth), truth = sh$truth, prob = sh$pred_prob,
    stringsAsFactors = FALSE
  )
  picks <- ml_pick_paired_cases(meta)
  ns <- picks[picks$outcome_class == "Non-survivor", , drop = FALSE][1, ]
  sv <- picks[picks$outcome_class == "Survivor", , drop = FALSE][1, ]
  list(
    list(database = database, stratum = "Overall", outcome_class = "Non-survivor",
         row_id = ns$row_id, prob = ns$prob, shp = sh$shp),
    list(database = database, stratum = "Overall", outcome_class = "Survivor",
         row_id = sv$row_id, prob = sv$prob, shp = sh$shp)
  )
}
items <- c(one(sh_i, "MIMIC-IV"), one(sh_e, "eICU"))
ml_ref_s5_forces(items, out_pdf = out_pdf)
message("S5_OK")
