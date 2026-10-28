#!/usr/bin/env Rscript
# 全文统一 literature_m123 Model3（剔除严重度）并重算关联表 + Fig3/Fig6
# 正式入口（跨课题复用）。详见 docs/reuse/2026-10-26-ml-literature-m123-assoc-reuse-map.md
#
# MEDICAL_BLOCKS_ROOT=... Rscript run/ml/rebuild_assoc_unified_model3.R \
#   --study <study_root> \
#   --index A+B \
#   --delivery .../by_index/【success】A+B
#
# 可选：--tables-only（只出表）；图全套+Fig8 栅格化另见 run/ml/redraw_assoc_figs.R
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
  "R/utils.R",
  "R/ml_assoc_covariate_rule.R",
  "R/prognosis_reference_assoc.R",
  "R/prognosis_landmark_ph.R",
  "R/ml_reference_assoc_figures.R",
  "R/pub_figure_export.R"
)) source(file.path(engine, f), local = FALSE)

study <- normalizePath(get_opt("--study", ""), winslash = "/", mustWork = TRUE)
index <- as.character(get_opt("--index", "SAR+CrCV"))[1L]
delivery <- get_opt("--delivery", "")
indices <- trimws(strsplit(gsub("\\+", ",", index), ",", fixed = TRUE)[[1L]])
if (length(indices) == 1L) {
  indices <- trimws(strsplit(index, "+", fixed = TRUE)[[1L]])
}
stopifnot(length(indices) == 2L)
ia <- indices[[1L]]
ib <- indices[[2L]]
.ref_assoc_set_indices(indices)

ck_path <- file.path(study, "checkpoints/by_index", index, "MIMIC_IV/ml_assoc_bundle.rds")
stopifnot(file.exists(ck_path))
ck <- readRDS(ck_path)
ctx <- ck$ctx %||% ck

sev <- unique(c(
  "GCS", "APSIII", "OASIS", "SOFA", "SAPSII", "Ventilation", "CRRT",
  ml_assoc_default_model3_exclude()
))
ctx$config$assoc_covariate <- modifyList(
  ctx$config$assoc_covariate %||% list(),
  list(
    enable = TRUE,
    scheme = "literature_m123",
    force_model1 = "Age",
    sex_var = "Gender",
    model3_exclude = sev,
    clinical_covariates = unique(c(
      as.character((ctx$config$assoc_covariate %||% list())$clinical_covariates %||% character(0)),
      "GCS", "APSIII", "OASIS", "SpO2", "Lactate", "PH", "pH", "BUN", "PT", "INR",
      "Hemoglobin", "Heart_Failure", "Ventilation", "MAP", "WBC", "Glucose"
    ))
  )
)
ctx$config$analysis_exclusion$current_index_vars <- indices
ctx$config$prediction$index_vars <- indices

ctx2 <- ml_apply_assoc_covariate_rule_to_ctx(ctx)
m3_locked <- as.character(ctx2$results$assoc_model3_factors)
m2_locked <- intersect(c("Age", "Gender", "Sex"), names(ctx2$data$imputed %||% ctx2$data$cleaned))
sex <- intersect(c("Gender", "Sex"), m2_locked)
m2_locked <- unique(c("Age", sex[[1L]]))
m3_locked <- unique(c(m2_locked, setdiff(m3_locked, sev)))
message("LOCKED Model2: ", paste(m2_locked, collapse = ", "))
message("LOCKED Model3: ", paste(m3_locked, collapse = ", "))
message("severity held out: ", paste(setdiff(sev, character(0))[setdiff(sev, character(0)) %in% names(ctx2$data$imputed %||% list())], collapse = ", "))

# 写死到 ctx，后续 .reference_assoc_models / resolve 都读到同一套
ctx2$results$assoc_model1_factors <- m2_locked  # literature resolve M1=Age+Sex
ctx2$results$assoc_model2_factors <- m3_locked
ctx2$results$assoc_model3_factors <- m3_locked
ctx2$results$Model3Factors <- m3_locked
ctx2$results$assoc_covariate_note <- sprintf(
  "unified literature_m123: Model2=%s; Model3=%s (excl.severity)",
  paste(m2_locked, collapse = "+"), paste(m3_locked, collapse = "+")
)

dat <- ctx2$data$imputed
stopifnot(is.data.frame(dat))

ref_key <- paste0(index, "_REF")
derived_path <- file.path(
  delivery, "publication_literature_final/authority/checkpoints/by_index",
  ref_key, "MIMIC_IV/step01_reference_derived.rds"
)
if (!nzchar(delivery) || !file.exists(derived_path)) {
  derived_path <- file.path(
    study, "by_index", paste0("【success】", index),
    "publication_literature_final/authority/checkpoints/by_index",
    ref_key, "MIMIC_IV/step01_reference_derived.rds"
  )
}
if (!file.exists(derived_path)) {
  # 兼容旧权威目录命名（SOSM+WPR_REF 等）
  cand <- Sys.glob(file.path(
    if (nzchar(delivery)) delivery else file.path(study, "by_index", paste0("【success】", index)),
    "publication_literature_final/authority/checkpoints/by_index",
    "*_REF", "MIMIC_IV", "step01_reference_derived.rds"
  ))
  if (length(cand)) derived_path <- cand[[1L]]
}
stopifnot(file.exists(derived_path))
train_aug <- readRDS(derived_path)$ctx$data$train
provenance <- reference_trusted_development(train_aug, checkpoint_path = derived_path)
joint_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ib, provenance)
sosm_lock <- reference_lock_tertile_cutpoints(train_aug, ia, ia, provenance)
wpr_lock <- reference_lock_tertile_cutpoints(train_aug, ib, ib, provenance)
cutoff <- NULL  # overall-only

.export_flush <- function(wide_or_df, fp, title, footnotes = NULL) {
  dir.create(dirname(fp), recursive = TRUE, showWarnings = FALSE)
  export_sci_table(wide_or_df, fp, title = title, table_footnotes = footnotes)
}

# ---- helpers: joint cox long for one frame ----
.fit_joint_long <- function(d, label = "analysis") {
  models <- .reference_assoc_models(ctx2, d, c(ia, ib), "SOFA_layer")
  # 强制覆盖 Model3 为锁定集（防 resolve 再带入严重度）
  models$Model3 <- intersect(m3_locked, names(d))
  models$Model2 <- intersect(m2_locked, names(d))
  models$Model1 <- character(0)
  res <- .ref_assoc_joint_table_core("MIMIC_IV", d, joint_lock, models, cutoff, ctx2$config)
  refs <- .ref_assoc_ref_rows(res, "Group1", "MIMIC_IV")
  cols <- intersect(
    c("database", "stratum", "model", "group", "hr_ci", "p", "p_cell", "n", "events", "status"),
    intersect(names(res), names(refs))
  )
  out <- rbind(refs[, cols, drop = FALSE], res[, cols, drop = FALSE])
  out[order(out$stratum, out$model, out$group), , drop = FALSE]
}

.wide_table2 <- function(tb) {
  grp_order <- c("Group1", "Group2", "Group3", "Group4")
  wide <- data.frame(Group = grp_order, stringsAsFactors = FALSE)
  for (mn in c("Model1", "Model2", "Model3")) {
    sub <- tb[as.character(tb$model) == mn, , drop = FALSE]
    wide[[paste0(mn, " HR (95% CI)")]] <- vapply(grp_order, function(g) {
      if (identical(g, "Group1")) return("1.00 (Reference)")
      hit <- sub$hr_ci[as.character(sub$group) == g]
      if (length(hit) && nzchar(hit[[1]])) hit[[1]] else "NE"
    }, character(1))
    wide[[paste0(mn, " P")]] <- vapply(grp_order, function(g) {
      if (identical(g, "Group1")) return("")
      hit <- sub$p_cell[as.character(sub$group) == g]
      if (length(hit) && nzchar(hit[[1]])) hit[[1]] else ""
    }, character(1))
  }
  names(wide) <- c(
    "Group",
    "Model 1 HR (95% CI)", "Model 1 P",
    "Model 2 HR (95% CI)", "Model 2 P",
    "Model 3 HR (95% CI)", "Model 3 P"
  )
  wide
}

## 有序编码 1..k 的 Cox trend（P for trend）
.fit_ordinal_trend <- function(d, group_vals, covs, time = "futime", event = "fustatus") {
  dd <- data.frame(d)
  dd$.__g <- suppressWarnings(as.integer(group_vals))
  dd$.__tm <- suppressWarnings(as.numeric(dd[[time]]))
  dd$.__ev <- suppressWarnings(as.integer(dd[[event]]))
  covs <- intersect(as.character(covs %||% character(0)), names(dd))
  keep <- is.finite(dd$.__g) & is.finite(dd$.__tm) & dd$.__tm > 0 & !is.na(dd$.__ev)
  dd <- dd[keep, , drop = FALSE]
  if (nrow(dd) < 40L || sum(dd$.__ev == 1L) < 5L ||
      length(unique(dd$.__g)) < 2L) {
    return(list(hr_ci = "NE", p_cell = "", p = NA_real_))
  }
  rhs <- paste(c(".__g", covs), collapse = " + ")
  fml <- stats::as.formula(sprintf("survival::Surv(.__tm, .__ev) ~ %s", rhs))
  fit <- tryCatch(survival::coxph(fml, data = dd), error = function(e) NULL)
  if (is.null(fit) || anyNA(stats::coef(fit))) {
    return(list(hr_ci = "NE", p_cell = "", p = NA_real_))
  }
  sm <- summary(fit)$coefficients
  rn <- rownames(sm)
  hit <- grep("\\.\\.__g$|^\\.__g$", rn)
  if (!length(hit)) hit <- which(rn == ".__g")
  if (!length(hit)) return(list(hr_ci = "NE", p_cell = "", p = NA_real_))
  i <- hit[[1L]]
  hr <- exp(sm[i, "coef"])
  se <- sm[i, "se(coef)"]
  p <- sm[i, "Pr(>|z|)"]
  lo <- exp(sm[i, "coef"] - 1.96 * se)
  hi <- exp(sm[i, "coef"] + 1.96 * se)
  list(
    hr_ci = sprintf("%.3f (%.3f, %.3f)", hr, lo, hi),
    p_cell = pub_format_p_cell(p),
    p = as.numeric(p)
  )
}

.append_table2_trend <- function(wide, d, joint_lock, models) {
  jt <- reference_apply_joint_tertiles(d, joint_lock)
  gnum <- as.integer(jt$group)
  trend_row <- data.frame(
    Group = "P for trend",
    `Model 1 HR (95% CI)` = "", `Model 1 P` = "",
    `Model 2 HR (95% CI)` = "", `Model 2 P` = "",
    `Model 3 HR (95% CI)` = "", `Model 3 P` = "",
    check.names = FALSE, stringsAsFactors = FALSE
  )
  for (mn in c("Model1", "Model2", "Model3")) {
    tr <- .fit_ordinal_trend(d, gnum, models[[mn]])
    trend_row[[paste0(gsub("Model", "Model ", mn), " HR (95% CI)")]] <- tr$hr_ci
    trend_row[[paste0(gsub("Model", "Model ", mn), " P")]] <- tr$p_cell
  }
  rbind(wide, trend_row)
}

.append_s4_trend_rows <- function(s4_df, d, sosm_lock, wpr_lock, train_aug, models) {
  ia_loc <- .ref_ia(); ib_loc <- .ref_ib()
  rows <- list()
  for (ix in c(ia_loc, ib_loc)) {
    lock <- if (identical(ix, ia_loc)) sosm_lock else wpr_lock
    ## tertile 1/2/3 from development-frozen cutpoints
    tfac <- .ref_assoc_tertile3(d, ix, lock, train_aug)
    tnum <- suppressWarnings(as.integer(tfac))
    for (mn in c("Model1", "Model2", "Model3")) {
      tr <- .fit_ordinal_trend(d, tnum, models[[mn]])
      rows[[length(rows) + 1L]] <- data.frame(
        database = "MIMIC IV", stratum = "Overall", index = ix,
        coding = "tertile", model = mn, group = "P for trend",
        hr_ci = tr$hr_ci, p_cell = tr$p_cell, p = tr$p,
        n = nrow(d),
        events = sum(suppressWarnings(as.integer(d$fustatus)) == 1L, na.rm = TRUE),
        status = if (nzchar(tr$hr_ci) && !identical(tr$hr_ci, "NE")) {
          "estimable"
        } else {
          "not_estimable"
        },
        stringsAsFactors = FALSE
      )
    }
  }
  keep <- intersect(names(s4_df), names(rows[[1L]]))
  rbind(s4_df[, keep, drop = FALSE], do.call(rbind, rows)[, keep, drop = FALSE])
}

cov_foot <- paste0(
  "Model 1: unadjusted. Model 2: age and sex. Model 3: age, sex, and univariate-significant ",
  "clinical covariates with VIF < 5 (", paste(m3_locked, collapse = ", "),
  "), excluding disease-severity scores and organ support (APSIII, OASIS, SOFA, GCS, ",
  "mechanical ventilation) for a unified total-association adjustment set across all association tables."
)

# ---- Table 2 ----
t2 <- .fit_joint_long(dat)
models_locked <- list(
  Model1 = character(0),
  Model2 = intersect(m2_locked, names(dat)),
  Model3 = intersect(m3_locked, names(dat))
)
t2_w <- .append_table2_trend(.wide_table2(t2), dat, joint_lock, models_locked)
n_lab <- sprintf(
  "N (events) = %s (%s).",
  format(t2$n[[1]], big.mark = ","), format(t2$events[[1]], big.mark = ",")
)
t2_title <- sprintf(
  "Table 2. Association of %s and %s joint groups with 28-day all-cause mortality (MIMIC-IV).",
  ia, ib
)
t2_notes <- c(
  cov_foot,
  "Group1 is the low/low reference (each index high = upper tertile frozen on the MIMIC-IV development set).",
  "P for trend: ordinal coding of joint groups (1–4) in the same Cox model.",
  n_lab,
  "Outcome: 28-day all-cause mortality."
)

# ---- Table S4 ----
s4 <- ref_assoc_index_cox_table(
  "MIMIC_IV", dat, sosm_lock, wpr_lock, train_aug, ctx2, cutoff, ctx2$config
)
s4 <- .append_s4_trend_rows(s4, dat, sosm_lock, wpr_lock, train_aug, models_locked)
# force Model3 rows already from models; re-check Group not needed
s4_title <- sprintf(
  "Table S4. Cox associations of %s and %s (continuous and tertiles) with 28-day all-cause mortality, overall cohort.",
  ia, ib
)
s4_export <- s4
names(s4_export) <- c(
  "Database", "Stratum", "Index", "Coding", "Model", "Group",
  "HR (95% CI)", "P", "p raw", "N", "Events", "Status"
)
s4_notes <- c(
  cov_foot,
  "Overall cohort. Continuous = per 1 unit; tertiles use development-frozen cutpoints.",
  "P for trend: ordinal coding of tertiles (1–3) in the same Cox model.",
  "Outcome: 28-day all-cause mortality."
)

# ---- Table S8 glucose exclude ----
d_glu <- dat
if ("Glucose" %in% names(d_glu)) {
  g <- suppressWarnings(as.numeric(d_glu$Glucose))
  d_glu <- d_glu[is.na(g) | g >= 70, , drop = FALSE]
}
s8 <- .fit_joint_long(d_glu)
s8_export <- s8[, c("stratum", "model", "group", "hr_ci", "p", "p_cell", "n", "events", "status"), drop = FALSE]
names(s8_export) <- c("Stratum", "Model", "Group", "HR (95% CI)", "p raw", "P", "N", "Events", "Status")
s8_title <- "Table S8. Joint-group Cox after excluding baseline glucose <70 mg/dL (MIMIC-IV)."
s8_notes <- c(
  cov_foot,
  "Sensitivity analysis on the overall cohort. Group1 is the low/low reference.",
  "Outcome: 28-day all-cause mortality."
)

# ---- Table S9 complete-case on Model3 covariates ----
need_cc <- unique(c(ia, ib, "futime", "fustatus", m3_locked))
need_cc <- intersect(need_cc, names(dat))
d_cc <- dat[stats::complete.cases(dat[, need_cc, drop = FALSE]), , drop = FALSE]
s9 <- .fit_joint_long(d_cc)
s9_export <- s9[, c("stratum", "model", "group", "hr_ci", "p", "p_cell", "n", "events", "status"), drop = FALSE]
names(s9_export) <- c("Stratum", "Model", "Group", "HR (95% CI)", "p raw", "P", "N", "Events", "Status")
s9_title <- "Table S9. Joint-group Cox restricted to complete cases (MIMIC-IV)."
s9_notes <- c(
  cov_foot,
  paste0("Complete cases on exposure, outcome and Model 3 covariates (n=", nrow(d_cc), ")."),
  "Group1 is the low/low reference. Outcome: 28-day all-cause mortality."
)

# ---- write tables to all mirrors ----
tab_dirs <- character(0)
if (nzchar(as.character(delivery %||% ""))) {
  delivery <- normalizePath(delivery, winslash = "/", mustWork = TRUE)
  tab_dirs <- c(
    file.path(delivery, "summary_result", "Tables"),
    file.path(delivery, "publication_literature_final", "Tables"),
    file.path(delivery, "Tables")
  )
}
tab_dirs <- c(
  tab_dirs,
  file.path(study, "by_index", paste0("【success】", index), "summary_result", "Tables"),
  file.path(study, "by_index", paste0("【success】", index), "Tables")
)
tab_dirs <- unique(tab_dirs)

jobs <- list(
  list(file = "Table 2 Joint group Cox.xlsx", df = t2_w, title = t2_title, notes = t2_notes),
  list(
    file = sprintf("Table S4 %s %s Cox.xlsx", ia, ib),
    df = s4_export, title = s4_title, notes = s4_notes
  ),
  list(file = "Table S8 baseline glucose excluded joint Cox.xlsx", df = s8_export, title = s8_title, notes = s8_notes),
  list(file = "Table S9 complete-case joint Cox.xlsx", df = s9_export, title = s9_title, notes = s9_notes)
)

for (od in tab_dirs) {
  dir.create(od, recursive = TRUE, showWarnings = FALSE)
  for (j in jobs) {
    export_sci_table(j$df, file.path(od, j$file), title = j$title, table_footnotes = j$notes)
  }
}
invisible(render_queued_tables(list()))
for (od in tab_dirs) {
  for (j in jobs) {
    bad <- file.path(od, sub("\\.xlsx$", "-UnknownDB.xlsx", j$file))
    good <- file.path(od, j$file)
    if (file.exists(bad)) {
      if (file.exists(good)) unlink(good)
      file.rename(bad, good)
      message("table OK ", good)
    } else if (file.exists(good)) {
      message("table OK ", good)
    }
  }
}

# ---- figures: Fig3 RCS + Fig6 forest with locked ctx ----
if (!has_flag("--tables-only")) {
  db_frames <- list(list(
    name = "MIMIC_IV", short = "MIMIC-IV", data = dat,
    outcome_cfg = ctx2$config, joint_lock = joint_lock,
    sosm_lock = sosm_lock, wpr_lock = wpr_lock,
    rcs_locks = stats::setNames(list(
      reference_lock_grouped_rcs(train_aug, ia, provenance),
      reference_lock_grouped_rcs(train_aug, ib, provenance)
    ), c(ia, ib)),
    assoc_ctx = ctx2, train_ref = train_aug
  ))
  tmp <- tempfile("assoc_unified_")
  dir.create(tmp)
  f3 <- file.path(tmp, sprintf("Figure 3. Grouped RCS %s %s.pdf", ia, ib))
  r3 <- tryCatch(
    ref_assoc_fig3_rcs(db_frames, cutoff = cutoff, grid_n = 40L, out_pdf = f3),
    error = function(e) {
      message("Fig3 fail: ", conditionMessage(e)); NULL
    }
  )
  f6 <- file.path(tmp, "Figure 6. Forest tertile association.pdf")
  r6 <- tryCatch(
    ref_assoc_fig6_forest(db_frames, cutoff = cutoff, out_pdf = f6),
    error = function(e) {
      message("Fig6 fail: ", conditionMessage(e)); NULL
    }
  )
  fig_roots <- character(0)
  if (nzchar(as.character(delivery %||% ""))) {
    fig_roots <- c(
      file.path(delivery, "summary_result", "Figures"),
      file.path(delivery, "publication_literature_final", "Figures")
    )
  }
  fig_roots <- c(
    fig_roots,
    file.path(study, "by_index", paste0("【success】", index), "summary_result", "Figures"),
    file.path(study, "by_index", paste0("【success】", index), "publication_literature_final", "Figures")
  )
  built <- character(0)
  if (!is.null(r3$path) && file.exists(r3$path)) built <- c(built, r3$path)
  if (!is.null(r6$path) && file.exists(r6$path)) built <- c(built, r6$path)
  for (fr in unique(fig_roots)) {
    if (!length(built)) break
    pdf_dir <- file.path(fr, "pdf")
    dir.create(pdf_dir, recursive = TRUE, showWarnings = FALSE)
    for (src in built) {
      file.copy(src, file.path(pdf_dir, basename(src)), overwrite = TRUE)
      message("fig ", file.path(pdf_dir, basename(src)))
    }
    tryCatch(
      pub_figure_ensure_formats(fr, purge = FALSE),
      error = function(e) message("ensure: ", conditionMessage(e))
    )
  }
}

# ---- Methods + harmonization lock file ----
harm <- file.path(study, "checkpoints/by_index", index, "harmonization")
dir.create(harm, recursive = TRUE, showWarnings = FALSE)
writeLines(
  c(
    "Model1 (table): unadjusted",
    paste0("Model2 (table): ", paste(m2_locked, collapse = ", ")),
    paste0("Model3 (table, unified, no severity): ", paste(m3_locked, collapse = ", ")),
    paste0("severity_held_out: ", paste(intersect(sev, names(dat)), collapse = ", ")),
    "Applies to: Table 2, Table S4, Table S8, Table S9, Figure 3 (RCS), Figure 6 (forest)."
  ),
  file.path(harm, "assoc_covariates_primary.txt")
)
saveRDS(
  list(Model2 = m2_locked, Model3 = m3_locked, severity_held_out = intersect(sev, names(dat))),
  file.path(harm, "assoc_covariates_primary.rds")
)

meth_paths <- character(0)
if (nzchar(as.character(delivery %||% ""))) {
  meth_paths <- c(
    file.path(delivery, "summary_result", "Methods_statistical_analysis.md"),
    file.path(delivery, "publication_literature_final", "Methods_statistical_analysis.md")
  )
}
meth_paths <- c(
  meth_paths,
  file.path(study, "by_index", paste0("【success】", index), "summary_result", "Methods_statistical_analysis.md")
)
meth_sentence <- paste0(
  "Model 1 was unadjusted; Model 2 adjusted for age and sex; Model 3 further adjusted for ",
  paste(m3_locked, collapse = ", "),
  " (univariate-significant clinical covariates with VIF < 5), excluding disease-severity scores ",
  "and organ-support variables (APSIII, OASIS, SOFA, GCS, mechanical ventilation). ",
  "The same Model 1–3 covariate sets were used for Table 2, Table S4 and joint-group sensitivity tables."
)
for (mp in unique(meth_paths)) {
  if (!file.exists(mp)) next
  txt <- readLines(mp, warn = FALSE)
  # replace Model 1/2/3 sentence if present
  hit <- grepl("Model 1 was unadjusted", txt, fixed = TRUE)
  if (any(hit)) {
    txt[which(hit)[1L]] <- sub(
      "Model 1 was unadjusted.*?(?=\\. |$)",
      meth_sentence,
      txt[which(hit)[1L]],
      perl = TRUE
    )
  } else {
    txt <- c(txt, "", meth_sentence)
  }
  writeLines(txt, mp)
  message("methods ", mp)
}

message("Group4 Table2:")
print(t2[as.character(t2$group) == "Group4", c("model", "hr_ci", "p_cell")])
message("Group4 S8:")
print(s8[as.character(s8$group) == "Group4", c("model", "hr_ci", "p_cell")])
message("Group4 S9:")
print(s9[as.character(s9$group) == "Group4", c("model", "hr_ci", "p_cell")])
message("UNIFIED_MODEL3_OK")
