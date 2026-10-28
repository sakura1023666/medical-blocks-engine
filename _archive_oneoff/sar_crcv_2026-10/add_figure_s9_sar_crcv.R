# 一次性补齐 SAR+CrCV publication_literature_final 缺失的 Figure S9
# （引擎 build 已挂 figureS9_three_set_roc；本脚本只修当前终稿）

engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine)) {
  engine <- if (.Platform$OS.type == "windows") "E:/01block/01Block-new-Final" else
    "/mnt/e/01block/01Block-new-Final"
}
# Windows Rscript 读 E:/；WSL R 读 /mnt/e/
.wsl_path <- function(p) {
  if (.Platform$OS.type == "windows") return(p)
  if (grepl("^E:/|^e:/", p)) sub("^[Ee]:/", "/mnt/e/", p)
  else if (grepl("^//192\\.168\\.68\\.133/", p))
    sub("^//192\\.168\\.68\\.133/", "/mnt/g/", p)
  else p
}
.win_unc <- function(p) {
  if (.Platform$OS.type != "windows") return(p)
  if (grepl("^/mnt/g/", p)) sub("^/mnt/g/", "//192.168.68.133/", p)
  else if (grepl("^/mnt/e/", p)) sub("^/mnt/e/", "E:/", p)
  else p
}
engine <- .wsl_path(engine)
if (.Platform$OS.type == "windows" && grepl("^/mnt/e/", engine)) {
  engine <- sub("^/mnt/e/", "E:/", engine)
}
suppressWarnings(suppressMessages({
  source(file.path(engine, "R/utils.R"))
  source(file.path(engine, "R/ml_dual_dev_ext.R"))
  source(file.path(engine, "R/ml_frozen_model_bundle.R"))
  source(file.path(engine, "R/ml_external_frozen_shap.R"))
  source(file.path(engine, "R/pub_figure_export.R"))
  for (pkg in c("workflows", "parsnip", "recipes", "yardstick", "dplyr",
                "ggplot2", "patchwork", "pROC", "shapviz")) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      suppressPackageStartupMessages(library(pkg, character.only = TRUE))
    }
  }
}))

pub <- .win_unc("/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28天死亡/by_index/【success】SAR+CrCV/publication_literature_final")
ck <- .win_unc("/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28天死亡/checkpoints/by_index/SAR+CrCV")
assets <- file.path(pub, "_assets/model_assets/overall")
stopifnot(dir.exists(assets), dir.exists(ck))

mi_ml <- readRDS(file.path(ck, "MIMIC_IV/step17_ml_models_bundle.rds"))$ctx
ei_ext <- readRDS(file.path(ck, "eICU/step16_ml_eval_external.rds"))$ctx
fb <- ml_load_frozen_bundle(assets)
id_col <- as.character(mi_ml$config$data$id_column %||% "ID")[1L]
mi_all <- mi_ml$data$imputed

train_df <- mi_all[!is.na(match(as.character(mi_all[[id_col]]), fb$train_ids)),
                   , drop = FALSE]
internal_df <- mi_all[!is.na(match(as.character(mi_all[[id_col]]),
                                   fb$internal_ids)), , drop = FALSE]

tr <- ml_predict_external_bundle(fb, train_df, database = "MIMIC-IV")
mi <- ml_predict_external_bundle(fb, internal_df, database = "MIMIC-IV")
ei <- ml_predict_external_bundle(fb, ei_ext$data$imputed, database = "eICU")
stopifnot(isTRUE(ei$provenance$no_refit))

cells <- list()
for (m in names(fb$models)) {
  cells[[length(cells) + 1L]] <- list(
    model = m, dataset = "training",
    roc = ml_ref_roc_rows(tr$predictions[[m]], tr$predictions$truth,
                          dataset = "training", model = m))
  cells[[length(cells) + 1L]] <- list(
    model = m, dataset = "internal_validation",
    roc = ml_ref_roc_rows(mi$predictions[[m]], mi$predictions$truth,
                          dataset = "internal_validation", model = m))
  cells[[length(cells) + 1L]] <- list(
    model = m, dataset = "external_validation",
    roc = ml_ref_roc_rows(ei$predictions[[m]], ei$predictions$truth,
                          dataset = "external_validation", model = m))
}

out_pdf <- file.path(
  pub, "Figures",
  "Figure S9. Overall five-model ROC train internal external.pdf")
# ml_ref_s9 writes into Figures/ then ensure_formats moves to pdf/
# Prefer write flat then ensure_formats
tmp_pdf <- file.path(pub, "Figures",
  "Figure S9. Overall five-model ROC train internal external.pdf")
p9 <- ml_ref_s9_three_set_auc(cells, out_pdf = tmp_pdf)
if (is.null(p9$path) || !file.exists(p9$path)) {
  stop("Figure S9 PDF missing", call. = FALSE)
}
write.csv(p9$auc, file.path(pub, "_assets/FigureS9_three_set_auc.csv"),
          row.names = FALSE)

st <- pub_figure_ensure_formats(file.path(pub, "Figures"))
cat("ensure_formats ok=", isTRUE(st$ok), " action=", st$action %||% NA, "\n")
st2 <- pub_figure_formats_status(file.path(pub, "Figures"))
cat("status ok=", isTRUE(st2$ok), " stems=", length(st2$stems),
    " bad_dpi=", length(st2$bad_dpi %||% character()), "\n")
has_s9 <- any(grepl("^Figure S9\\.", st2$stems))
cat("has_S9=", has_s9, "\n")
if (!has_s9) stop("S9 still missing after ensure_formats", call. = FALSE)
if (length(st2$bad_dpi %||% character())) {
  stop("bad_dpi: ", paste(st2$bad_dpi, collapse = ", "), call. = FALSE)
}

# append MANIFEST row if absent
mf <- file.path(pub, "MANIFEST.csv")
md <- utils::read.csv(mf, stringsAsFactors = FALSE, check.names = FALSE)
if (!any(grepl("Figure S9", md$target_file %||% ""))) {
  row <- data.frame(
    kind = NA_character_, number = NA_character_,
    role = "overall 五模型三集 ROC（train/internal/eICU，1×3）",
    title = paste0(
      "Figure S9. Receiver operating characteristic curves of five ML models ",
      "across train, internal validation and eICU external sets."),
    db_mode = "A train | B internal | C eICU",
    reference_source = "本课题额外补充图（三集 ROC）",
    adaptation = "Frozen MIMIC overall models；A/B/C 三面",
    source_files = "publication_literature_final/_assets/model_assets/overall",
    target_file = "Figures/pdf/Figure S9. Overall five-model ROC train internal external.pdf",
    status = "ready",
    verification = sprintf(
      "four_formats=pdf:TRUE,png:TRUE,tiff:TRUE,md:TRUE; n_auc_rows=%d; layout=1x3",
      nrow(p9$auc)),
    stringsAsFactors = FALSE
  )
  # align columns
  for (nm in setdiff(names(md), names(row))) row[[nm]] <- NA
  row <- row[, names(md), drop = FALSE]
  md <- rbind(md, row)
  utils::write.csv(md, mf, row.names = FALSE)
  cat("MANIFEST row appended\n")
}
cat("DONE figures=", length(list.files(file.path(pub, "Figures/pdf"),
                                       pattern = "\\.pdf$")),
    " tables=", length(list.files(file.path(pub, "Tables"),
                                  pattern = "\\.xlsx$")), "\n")
