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

sev <- unique(c(
  "GCS", "APSIII", "OASIS", "SOFA", "SAPSII", "Ventilation", "CRRT",
  ml_assoc_default_model3_exclude()
))
.prep_assoc_ctx <- function(ck_path) {
  ck <- readRDS(ck_path)
  ctx <- ck$ctx %||% ck
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
  list(ctx = ctx2, models = list(Model1 = character(0), Model2 = m2, Model3 = m3))
}
mi_ck <- file.path(study, "checkpoints/by_index", index, "MIMIC_IV/ml_assoc_bundle.rds")
ei_ck <- file.path(study, "checkpoints/by_index", index, "eICU/ml_assoc_bundle.rds")
if (!file.exists(mi_ck)) stop("缺 MIMIC assoc checkpoint: ", mi_ck, call. = FALSE)
mi_prep <- .prep_assoc_ctx(mi_ck)
message("MIMIC Model2=", paste(mi_prep$models$Model2, collapse = "+"),
        " Model3=", paste(mi_prep$models$Model3, collapse = "+"))
if (!file.exists(ei_ck)) {
  stop("缺 eICU assoc checkpoint（双库 Fig2–6 禁止只画主库）: ", ei_ck, call. = FALSE)
}
ei_prep <- .prep_assoc_ctx(ei_ck)
# 外验继承主库 Model2/3（与 literature finalize 一致）
ei_prep$ctx$results$assoc_model1_factors <- mi_prep$models$Model2
ei_prep$ctx$results$assoc_model2_factors <- mi_prep$models$Model3
ei_prep$ctx$results$assoc_model3_factors <- mi_prep$models$Model3
ei_prep$models <- mi_prep$models

ref_key <- paste0(index, "_REF")
derived_cands <- c(
  file.path(
    delivery, "publication_literature_final/authority/checkpoints/by_index",
    ref_key, "MIMIC_IV/step01_reference_derived.rds"
  ),
  file.path(
    study, "by_index", paste0("【success】", index),
    "publication_literature_final/authority/checkpoints/by_index",
    ref_key, "MIMIC_IV/step01_reference_derived.rds"
  ),
  Sys.glob(file.path(
    delivery, "publication_literature_final/authority/checkpoints/by_index",
    "*_REF", "MIMIC_IV", "step01_reference_derived.rds"
  )),
  Sys.glob(file.path(
    study, "by_index", paste0("【success】", index),
    "publication_literature_final/authority/checkpoints/by_index",
    "*_REF", "MIMIC_IV", "step01_reference_derived.rds"
  ))
)
derived_cands <- unique(derived_cands[file.exists(derived_cands)])
if (!length(derived_cands)) {
  stop("reference derived rds not found under delivery or study", call. = FALSE)
}
derived <- derived_cands[[1L]]
message("derived=", derived)
train_aug <- readRDS(derived)$ctx$data$train
prov <- reference_trusted_development(train_aug, checkpoint_path = derived)
joint_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ib, prov)
sosm_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ia, prov)
wpr_lock <- reference_lock_tertile_cutpoints(train_aug, ib, ib, prov)
rcs_locks <- stats::setNames(list(
  reference_lock_grouped_rcs(train_aug, ia, prov),
  reference_lock_grouped_rcs(train_aug, ib, prov)
), c(ia, ib))
cutoff <- NULL
db_frames <- list(
  list(
    name = "MIMIC_IV", short = "MIMIC-IV", data = mi_prep$ctx$data$imputed,
    outcome_cfg = mi_prep$ctx$config, joint_lock = joint_lock,
    sosm_lock = sosm_lock, wpr_lock = wpr_lock, rcs_locks = rcs_locks,
    assoc_ctx = mi_prep$ctx, models = mi_prep$models, train_ref = train_aug
  ),
  list(
    name = "eICU", short = "eICU", data = ei_prep$ctx$data$imputed,
    outcome_cfg = ei_prep$ctx$config, joint_lock = joint_lock,
    sosm_lock = sosm_lock, wpr_lock = wpr_lock, rcs_locks = rcs_locks,
    assoc_ctx = ei_prep$ctx, models = ei_prep$models, train_ref = train_aug
  )
)
message("db_frames=", paste(vapply(db_frames, `[[`, "", "short"), collapse = "+"))

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
## 同步重写 Table S5（联合改为连续 LP 后数字必变）
s5_paths <- character(0)
if (!is.null(r4) && is.data.frame(r4$auc) && nrow(r4$auc)) {
  s5_title <- paste0(
    "Table S5. Discrimination (AUC with 95% CI) and DeLong tests versus ",
    ia, " for ", ia, ", ", ib, ", continuous joint linear predictor (", ia, "+", ib,
    " logistic LP locked on MIMIC train), APSIII, OASIS and GCS, by database ",
    "(overall cohort, 28-day all-cause mortality)."
  )
  s5_out <- r4$auc
  s5_out$predictor[s5_out$predictor == "Joint"] <- .ref_assoc_fig4_joint_lab()
  s5_out$auc_fmt <- pub_format_est(s5_out$auc)
  s5_out$ci_fmt <- ifelse(
    is.finite(s5_out$ci_low),
    paste0("(", pub_format_est(s5_out$ci_low), ", ",
           pub_format_est(s5_out$ci_high), ")"),
    "NE"
  )
  s5_out$delong_fmt <- ifelse(
    s5_out$predictor == ia, "reference",
    pub_format_p_cell(s5_out$delong_p)
  )
  s5_export <- s5_out[, c("database", "stratum", "predictor", "n", "events",
                          "auc_fmt", "ci_fmt", "delong_fmt", "status")]
  names(s5_export) <- c(
    "Database", "Stratum", "Predictor", "N", "Events", "AUC", "95% CI",
    paste0("DeLong P vs ", ia), "Status"
  )
  s5_tmp <- file.path(tmp, "Table S5 ROC discrimination DeLong.xlsx")
  s5_fn <- c(
    paste0(
      "Joint = continuous logistic linear predictor of ", ia, " + ", ib,
      " with coefficients locked on MIMIC development/train ",
      "(applied to both databases; no refit on eICU)."
    ),
    "Not the four-level joint tertile group code used in Table 2 / KM.",
    paste0("DeLong P compares each predictor with ", ia, " within the same database."),
    "Outcome: 28-day all-cause mortality (Survivor / Non-survivor)."
  )
  tryCatch({
    if (exists(".ref_assoc_export_xlsx", mode = "function")) {
      .ref_assoc_export_xlsx(s5_tmp, s5_title, s5_export, footnotes = s5_fn)
    } else {
      sci_xlsx_single_header_booktabs(
        s5_tmp, title = s5_title, df_body = s5_export, sheet = "Table S5",
        footnotes = s5_fn
      )
    }
    if (file.exists(s5_tmp)) s5_paths <- c(s5_paths, s5_tmp)
  }, error = function(e) message("S5 export: ", conditionMessage(e)))
  if (!is.null(r4$joint_lp)) {
    message(
      "Fig4 joint LP betas: ", ia, "=", signif(r4$joint_lp$beta_a, 4),
      " ", ib, "=", signif(r4$joint_lp$beta_b, 4),
      " | Overall Joint AUCs:"
    )
    jr <- s5_out[s5_out$predictor == .ref_assoc_fig4_joint_lab() |
                   s5_out$predictor == "Joint",
                 c("database", "auc_fmt", "ci_fmt"), drop = FALSE]
    print(jr)
  }
}

## Fig5：文献式 PH landmark（MIMIC cox.zph → 最显违反层 → Schoenfeld β 过零选日）
## 可选覆盖：--force-landmark-day N / --force-landmark-stratum Overall
source(file.path(engine, "R/prognosis_landmark_ph.R"), local = FALSE)
source(file.path(engine, "R/ml_stratified_ctx.R"), local = FALSE)
fd_cli <- suppressWarnings(as.numeric(get_opt("--force-landmark-day", NA_real_))[1L])
fs_cli <- as.character(get_opt("--force-landmark-stratum", "Overall"))[1L]
age_sex <- intersect(c("Age", "Gender", "Sex"), names(train_aug))
## 确保开发集带 Joint_score / SOFA_layer（PH 扫描所需）
train_fig5 <- train_aug
if (!"SOFA_layer" %in% names(train_fig5)) {
  train_fig5$SOFA_layer <- ref_assoc_sofa_layer(train_fig5, cutoff %||% c(4L, 10L))
}
if (!"Joint_score" %in% names(train_fig5)) {
  jt0 <- reference_apply_joint_tertiles(train_fig5, joint_lock)
  train_fig5$Joint_score <- as.numeric(jt0$group)
  if (!"JointGroup" %in% names(train_fig5) && "group" %in% names(jt0)) {
    train_fig5$JointGroup <- jt0$group
  }
}
f5 <- file.path(tmp, "Figure 5. Landmark before after Cox.pdf")
r5 <- tryCatch(
  ref_assoc_fig5_landmark(
    train_aug = train_fig5,
    mimic_analysis = mi_prep$ctx$data$imputed,
    eicu_analysis = ei_prep$ctx$data$imputed,
    provenance = prov,
    outcome_cfg = mi_prep$ctx$config,
    covariates = age_sex,
    cutoff = cutoff %||% c(4L, 10L),
    joint_lock = joint_lock,
    out_pdf = f5,
    force_landmark_day = if (is.finite(fd_cli)) fd_cli else NULL,
    force_landmark_stratum = fs_cli
  ),
  error = function(e) { message("Fig5: ", conditionMessage(e)); NULL }
)
if (!is.null(r5$path) && file.exists(r5$path)) built <- c(built, r5$path)
if (!is.null(r5$locked_spec)) {
  message(
    "Fig5 lock strata=", paste(r5$locked_spec$strata, collapse = ","),
    " days=", paste(as.numeric(r5$locked_spec$landmark_times), collapse = ","),
    " forced=", isTRUE(r5$locked_spec$forced_landmark)
  )
  sc <- r5$locked_spec$scan
  if (is.data.frame(sc) && nrow(sc)) {
    keep <- intersect(
      c("stratum", "exposure_p", "landmark_time", "landmark_method",
        "approximate", "status"),
      names(sc)
    )
    print(sc[, keep, drop = FALSE])
  }
}

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
tab_roots <- unique(c(
  file.path(delivery, "summary_result", "Tables"),
  file.path(delivery, "publication_literature_final", "Tables"),
  file.path(study, "by_index", paste0("【success】", index), "summary_result", "Tables"),
  file.path(study, "by_index", paste0("【success】", index), "publication_literature_final", "Tables")
))
for (tr in tab_roots) {
  if (!dir.exists(tr) || !length(s5_paths)) next
  for (src in s5_paths) {
    file.copy(src, file.path(tr, basename(src)), overwrite = TRUE)
    message("table ", file.path(tr, basename(src)))
  }
}

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
