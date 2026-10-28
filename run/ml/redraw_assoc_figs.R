#!/usr/bin/env Rscript
# 文献关联图重画（统一 literature_m123 Model3）+ 可选 Fig8 文本层栅格化
# 正式入口（跨课题）。详见 docs/reuse/2026-10-26-ml-literature-m123-assoc-reuse-map.md
#
# MEDICAL_BLOCKS_ROOT=... Rscript run/ml/redraw_assoc_figs.R \
#   --study <study_root> \
#   --delivery .../by_index/【success】A+B \
#   --index A+B
#
# 可选：--rasterize-fig8 "Figure 8. ….pdf"（对已有 PDF 做 image-only 栅格，消 collision FAIL）
args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) {
  if (is.null(a) || !length(a) || (length(a) == 1L && (is.na(a) || (is.character(a) && !nzchar(a))))) b else a
}
get_opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
has_flag <- function(flag) flag %in% args

engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine)) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[grep("^--file=", ca)])
  if (length(f)) {
    engine <- normalizePath(file.path(dirname(f[[1]]), "../.."), winslash = "/", mustWork = FALSE)
  }
}
stopifnot(dir.exists(file.path(engine, "R")))
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
setwd(engine)
for (f in c(
  "R/utils.R", "R/ml_assoc_covariate_rule.R", "R/prognosis_reference_assoc.R",
  "R/ml_reference_assoc_figures.R", "R/pub_figure_export.R"
)) source(file.path(engine, f), local = FALSE)

study <- normalizePath(get_opt("--study", ""), winslash = "/", mustWork = TRUE)
delivery <- normalizePath(get_opt("--delivery", ""), winslash = "/", mustWork = TRUE)
index <- as.character(get_opt("--index", ""))[1L]
if (!nzchar(index)) stop("--index A+B required", call. = FALSE)
indices <- trimws(strsplit(gsub("\\+", ",", index), ",", fixed = TRUE)[[1L]])
if (length(indices) == 1L) {
  indices <- trimws(strsplit(index, "+", fixed = TRUE)[[1L]])
}
stopifnot(length(indices) == 2L)
.ref_assoc_set_indices(indices)
ia <- indices[[1L]]
ib <- indices[[2L]]

ck <- readRDS(file.path(study, "checkpoints/by_index", index, "MIMIC_IV/ml_assoc_bundle.rds"))
ctx <- ck$ctx %||% ck
sev <- unique(c(
  "GCS", "APSIII", "OASIS", "SOFA", "SAPSII", "Ventilation", "CRRT",
  ml_assoc_default_model3_exclude()
))
ctx$config$assoc_covariate <- modifyList(
  ctx$config$assoc_covariate %||% list(),
  list(
    enable = TRUE, scheme = "literature_m123", force_model1 = "Age",
    sex_var = "Gender", model3_exclude = sev
  )
)
ctx2 <- ml_apply_assoc_covariate_rule_to_ctx(ctx)
m2 <- intersect(c("Age", "Gender", "Sex"), names(ctx2$data$imputed))
sex <- intersect(c("Gender", "Sex"), m2)
m2 <- unique(c("Age", if (length(sex)) sex[[1L]] else character(0)))
m3 <- unique(c(m2, setdiff(as.character(ctx2$results$assoc_model3_factors), sev)))
ctx2$results$assoc_model1_factors <- m2
ctx2$results$assoc_model2_factors <- m3
ctx2$results$assoc_model3_factors <- m3
dat <- ctx2$data$imputed
models <- list(Model1 = character(0), Model2 = m2, Model3 = m3)
message("Model2=", paste(m2, collapse = "+"), " Model3=", paste(m3, collapse = "+"))

ref_key <- paste0(index, "_REF")
derived <- file.path(
  delivery, "publication_literature_final/authority/checkpoints/by_index",
  ref_key, "MIMIC_IV/step01_reference_derived.rds"
)
if (!file.exists(derived)) {
  cand <- Sys.glob(file.path(
    delivery, "publication_literature_final/authority/checkpoints/by_index",
    "*_REF", "MIMIC_IV", "step01_reference_derived.rds"
  ))
  if (!length(cand)) stop("reference derived rds not found under delivery", call. = FALSE)
  derived <- cand[[1L]]
}
train_aug <- readRDS(derived)$ctx$data$train
prov <- reference_trusted_development(train_aug, checkpoint_path = derived)
joint_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ib, prov)
sosm_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ia, prov)
wpr_lock <- reference_lock_tertile_cutpoints(train_aug, ib, ib, prov)
cutoff <- NULL
db_frames <- list(list(
  name = "MIMIC_IV", short = "MIMIC-IV", data = dat,
  outcome_cfg = ctx2$config, joint_lock = joint_lock,
  sosm_lock = sosm_lock, wpr_lock = wpr_lock,
  rcs_locks = stats::setNames(list(
    reference_lock_grouped_rcs(train_aug, ia, prov),
    reference_lock_grouped_rcs(train_aug, ib, prov)
  ), c(ia, ib)),
  assoc_ctx = ctx2, models = models, train_ref = train_aug
))

tmp <- tempfile("redraw_assoc_")
dir.create(tmp)
built <- character(0)

f2 <- file.path(tmp, sprintf("Figure 2. KM %s %s joint groups.pdf", ia, ib))
r2 <- tryCatch(
  ref_assoc_fig2_km(db_frames, cutoff = cutoff, out_pdf = f2),
  error = function(e) { message("Fig2: ", conditionMessage(e)); NULL }
)
if (!is.null(r2$path) && file.exists(r2$path)) built <- c(built, r2$path)

f3 <- file.path(tmp, sprintf("Figure 3. Grouped RCS %s %s.pdf", ia, ib))
r3 <- tryCatch(
  ref_assoc_fig3_rcs(db_frames, cutoff = cutoff, grid_n = 40L, out_pdf = f3),
  error = function(e) { message("Fig3: ", conditionMessage(e)); NULL }
)
if (!is.null(r3$path) && file.exists(r3$path)) built <- c(built, r3$path)

f4 <- file.path(tmp, sprintf("Figure 4. ROC %s %s joint scores.pdf", ia, ib))
r4 <- tryCatch(
  ref_assoc_fig4_roc(db_frames, cutoff = cutoff, out_pdf = f4),
  error = function(e) { message("Fig4: ", conditionMessage(e)); NULL }
)
if (!is.null(r4$path) && file.exists(r4$path)) built <- c(built, r4$path)

f6 <- file.path(tmp, "Figure 6. Forest tertile association.pdf")
r6 <- tryCatch(
  ref_assoc_fig6_forest(db_frames, cutoff = cutoff, out_pdf = f6),
  error = function(e) { message("Fig6: ", conditionMessage(e)); NULL }
)
if (!is.null(r6$path) && file.exists(r6$path)) built <- c(built, r6$path)

fig_roots <- unique(c(
  file.path(delivery, "summary_result", "Figures"),
  file.path(delivery, "publication_literature_final", "Figures"),
  file.path(study, "by_index", paste0("【success】", index), "summary_result", "Figures"),
  file.path(study, "by_index", paste0("【success】", index), "publication_literature_final", "Figures")
))

f8_name <- as.character(get_opt(
  "--rasterize-fig8",
  "Figure 8. Five-model ROC and SHAP in MIMIC-IV and eICU.pdf"
))[1L]
do_f8 <- !has_flag("--no-rasterize-fig8")

for (fr in fig_roots) {
  if (!dir.exists(fr)) next
  pdf_dir <- file.path(fr, "pdf")
  dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
  for (src in built) {
    file.copy(src, file.path(pdf_dir, basename(src)), overwrite = TRUE)
    message("fig ", file.path(pdf_dir, basename(src)))
    unlink(file.path(fr, "png", sub("\\.pdf$", ".png", basename(src))))
    unlink(file.path(fr, "tiff", sub("\\.pdf$", ".tiff", basename(src))))
  }
  if (isTRUE(do_f8) && nzchar(f8_name)) {
    f8_src <- file.path(pdf_dir, f8_name)
    if (file.exists(f8_src)) {
      f8_tmp <- file.path(tmp, f8_name)
      tryCatch({
        pub_figure_rasterize_pdf_page(f8_src, f8_tmp, dpi = 300L)
        file.copy(f8_tmp, f8_src, overwrite = TRUE)
        unlink(file.path(fr, "png", sub("\\.pdf$", ".png", f8_name)))
        unlink(file.path(fr, "tiff", sub("\\.pdf$", ".tiff", f8_name)))
        message("fig8 rasterized ", f8_src)
      }, error = function(e) message("fig8 raster fail: ", conditionMessage(e)))
    }
  }
  tryCatch(pub_figure_ensure_formats(fr), error = function(e) message("ensure: ", conditionMessage(e)))
  st <- pub_figure_formats_status(fr)
  message("status ", fr, " ok=", isTRUE(st$ok), " bad_dpi=", length(st$bad_dpi %||% character(0)))
}

if (!is.null(r6$rows)) {
  ov <- r6$rows[r6$rows$subgroup == "Overall", c("index", "hr", "conf_low", "conf_high", "p", "status")]
  message("Fig6 Overall rows:")
  print(ov)
}
message("REDRAW_ASSOC_FIGS_OK")
