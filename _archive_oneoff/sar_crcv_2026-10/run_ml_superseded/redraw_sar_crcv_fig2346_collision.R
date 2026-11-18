#!/usr/bin/env Rscript
# Redraw Fig2/3/4/6 with unified Model3 + collision-safe layout; rasterize Fig8 text layer.
args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) {
  if (is.null(a) || !length(a) || (length(a) == 1L && (is.na(a) || (is.character(a) && !nzchar(a))))) b else a
}
get_opt <- function(flag, default = NULL) {
  i <- match(flag, args)
  if (is.na(i) || i >= length(args)) return(default)
  args[[i + 1L]]
}
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
index <- as.character(get_opt("--index", "SAR+CrCV"))[1L]
indices <- c("SAR", "CrCV")
.ref_assoc_set_indices(indices)
ia <- "SAR"; ib <- "CrCV"

ck <- readRDS(file.path(study, "checkpoints/by_index", index, "MIMIC_IV/ml_assoc_bundle.rds"))
ctx <- ck$ctx %||% ck
sev <- unique(c(
  "GCS", "APSIII", "OASIS", "SOFA", "SAPSII", "Ventilation", "CRRT",
  ml_assoc_default_model3_exclude()
))
ctx$config$assoc_covariate <- modifyList(
  ctx$config$assoc_covariate %||% list(),
  list(enable = TRUE, scheme = "literature_m123", force_model1 = "Age",
       sex_var = "Gender", model3_exclude = sev)
)
ctx2 <- ml_apply_assoc_covariate_rule_to_ctx(ctx)
m2 <- intersect(c("Age", "Gender"), names(ctx2$data$imputed))
m3 <- unique(c(m2, setdiff(as.character(ctx2$results$assoc_model3_factors), sev)))
ctx2$results$assoc_model1_factors <- m2
ctx2$results$assoc_model2_factors <- m3
ctx2$results$assoc_model3_factors <- m3
dat <- ctx2$data$imputed
models <- list(Model1 = character(0), Model2 = m2, Model3 = m3)
message("Model2=", paste(m2, collapse = "+"), " Model3=", paste(m3, collapse = "+"))

derived <- file.path(
  delivery, "publication_literature_final/authority/checkpoints/by_index",
  "SAR+CrCV_REF/MIMIC_IV/step01_reference_derived.rds"
)
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

f2 <- file.path(tmp, "Figure 2. KM SAR CrCV joint groups.pdf")
r2 <- tryCatch(ref_assoc_fig2_km(db_frames, cutoff = cutoff, out_pdf = f2),
               error = function(e) { message("Fig2: ", conditionMessage(e)); NULL })
if (!is.null(r2$path) && file.exists(r2$path)) built <- c(built, r2$path)

f3 <- file.path(tmp, "Figure 3. Grouped RCS SAR CrCV.pdf")
r3 <- tryCatch(ref_assoc_fig3_rcs(db_frames, cutoff = cutoff, grid_n = 40L, out_pdf = f3),
               error = function(e) { message("Fig3: ", conditionMessage(e)); NULL })
if (!is.null(r3$path) && file.exists(r3$path)) built <- c(built, r3$path)

f4 <- file.path(tmp, "Figure 4. ROC SAR CrCV joint scores.pdf")
r4 <- tryCatch(ref_assoc_fig4_roc(db_frames, cutoff = cutoff, out_pdf = f4),
               error = function(e) { message("Fig4: ", conditionMessage(e)); NULL })
if (!is.null(r4$path) && file.exists(r4$path)) built <- c(built, r4$path)

f6 <- file.path(tmp, "Figure 6. Forest tertile association.pdf")
r6 <- tryCatch(ref_assoc_fig6_forest(db_frames, cutoff = cutoff, out_pdf = f6),
               error = function(e) { message("Fig6: ", conditionMessage(e)); NULL })
if (!is.null(r6$path) && file.exists(r6$path)) built <- c(built, r6$path)

# Fig8: rasterize existing PDF → cairo image PDF (clear text-layer collision FAILs on SHAP)
.rasterize_pdf_page <- function(src, dest, dpi = 300) {
  if (!requireNamespace("magick", quietly = TRUE)) {
    stop("magick required to rasterize Figure 8", call. = FALSE)
  }
  im <- magick::image_read_pdf(src, density = dpi)
  info <- magick::image_info(im)
  w_in <- info$width[[1]] / dpi
  h_in <- info$height[[1]] / dpi
  tmp_png <- tempfile(fileext = ".png")
  magick::image_write(im, path = tmp_png, format = "png")
  ras <- as.raster(magick::image_read(tmp_png))
  if (is.function(grDevices::cairo_pdf)) {
    grDevices::cairo_pdf(dest, width = w_in, height = h_in)
  } else {
    grDevices::pdf(dest, width = w_in, height = h_in)
  }
  grid::grid.newpage()
  grid::grid.raster(ras, interpolate = TRUE)
  grDevices::dev.off()
  unlink(tmp_png)
  invisible(dest)
}

fig_roots <- unique(c(
  file.path(delivery, "summary_result", "Figures"),
  file.path(delivery, "publication_literature_final", "Figures"),
  file.path(study, "by_index", paste0("【success】", index), "summary_result", "Figures"),
  file.path(study, "by_index", paste0("【success】", index), "publication_literature_final", "Figures")
))

f8_name <- "Figure 8. Five-model ROC and SHAP in MIMIC-IV and eICU.pdf"
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
  f8_src <- file.path(pdf_dir, f8_name)
  if (file.exists(f8_src)) {
    f8_tmp <- file.path(tmp, f8_name)
    tryCatch({
      .rasterize_pdf_page(f8_src, f8_tmp, dpi = 300)
      file.copy(f8_tmp, f8_src, overwrite = TRUE)
      unlink(file.path(fr, "png", sub("\\.pdf$", ".png", f8_name)))
      unlink(file.path(fr, "tiff", sub("\\.pdf$", ".tiff", f8_name)))
      message("fig8 rasterized ", f8_src)
    }, error = function(e) message("fig8 raster fail: ", conditionMessage(e)))
  }
  tryCatch(pub_figure_ensure_formats(fr), error = function(e) message("ensure: ", conditionMessage(e)))
  st <- pub_figure_formats_status(fr)
  message("status ", fr, " ok=", isTRUE(st$ok), " bad_dpi=", length(st$bad_dpi %||% character(0)))
}

# Fig6 Overall HR under Model3 for logging
if (!is.null(r6$rows)) {
  ov <- r6$rows[r6$rows$subgroup == "Overall", c("index", "hr", "conf_low", "conf_high", "p", "status")]
  message("Fig6 Overall rows:")
  print(ov)
}
message("REDRAW_OK")
