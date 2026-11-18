#!/usr/bin/env Rscript
# SAR+CrCV 发表图/表：去掉 SOFA 分层，改为全队列（MIMIC-IV / eICU）。
# 只写 /tmp 或本脚本 out_dir，不覆盖终稿；终稿由后续拷贝完成。

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a) || !length(a)) b else a
}

engine <- "/mnt/e/01block/01Block-new-Final"
study <- "/mnt/g/DockerHome/5003/medical-blocks-studies/studies/33_AKI_SAR_CrCV_28天死亡"
out_dir <- "/tmp/sar_overall_redraw"
assets_overall <- file.path(
  study, "by_index", "【success】SAR+CrCV",
  "publication_literature_final", "_assets", "model_assets", "overall"
)
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(out_dir, "Tables"), recursive = TRUE, showWarnings = FALSE)

Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
suppressWarnings(suppressMessages({
  source(file.path(engine, "R/utils.R"))
  source(file.path(engine, "R/ml_assoc_covariate_rule.R"))
  source(file.path(engine, "R/ml_stratified_ctx.R"))
  source(file.path(engine, "R/ml_dual_dev_ext.R"))
  source(file.path(engine, "R/prognosis_reference_assoc.R"))
  source(file.path(engine, "R/prognosis_landmark_ph.R"))
  source(file.path(engine, "R/ml_reference_assoc_figures.R"))
  source(file.path(engine, "R/ml_frozen_model_bundle.R"))
  source(file.path(engine, "R/ml_external_frozen_shap.R"))
  source(file.path(engine, "R/pub_figure_export.R"))
}))
.ref_assoc_set_indices(c("SAR", "CrCV"))

# 本课题主分析不再按 SOFA 切层
ref_assoc_layer_labels <- function(cutoff = c(4L, 10L)) "Overall"
ref_assoc_sofa_layer <- function(data, cutoff = c(4L, 10L)) {
  factor(rep("Overall", nrow(data)), levels = "Overall")
}
.ref_assoc_layer_masks <- function(d, cutoff = c(4L, 10L)) {
  list(Overall = rep(TRUE, nrow(d)))
}
ref_assoc_fig6_subgroups <- c(
  "Age", "Gender", "Ventilation", "Hypertension", "Diabetes", "CKD"
)

ref_assoc_fig2_km <- function(db_frames, cutoff = c(4L, 10L), out_pdf = NULL) {
  ia <- .ref_ia(); ib <- .ref_ib(); ilab <- .ref_ilab()
  db_frames <- .ref_assoc_order_db_frames(db_frames)
  panels <- list(); curves <- list(); k <- 0L
  cols <- list(
    list(column = ia, name = paste0(ia, " tertile")),
    list(column = ib, name = paste0(ib, " tertile")),
    list(column = "Joint", name = paste0(ilab, " joint"))
  )
  for (db in db_frames) {
    d <- .ref_assoc_event01(data.frame(db$data), "fustatus", db$outcome_cfg)
    d$event <- d$fustatus
    joint <- reference_apply_joint_tertiles(d, db$joint_lock)
    d$Joint <- joint$group
    d[[paste0(ia, "_T")]] <- .ref_assoc_tertile3(d, ia, db$sosm_lock, db$train_ref)
    d[[paste0(ib, "_T")]] <- .ref_assoc_tertile3(d, ib, db$wpr_lock, db$train_ref)
    group_of <- stats::setNames(
      c(paste0(ia, "_T"), paste0(ib, "_T"), "Joint"),
      c(ia, ib, "Joint")
    )
    mask <- rep(TRUE, nrow(d))
    for (col in cols) {
      k <- k + 1L
      res <- .ref_assoc_km_panel(d, d[[group_of[[col$column]]]])
      panels[[k]] <- data.frame(
        panel = k, row = 1L, column = col$column, database = db$name,
        stratum = "Overall",
        panel_title = paste0(db$short, " | ", col$name),
        logrank_p = res$p, status = res$status, n = nrow(d),
        stringsAsFactors = FALSE
      )
      if (!is.null(res$curve)) {
        cv <- res$curve
        cv$panel <- k
        curves[[k]] <- cv
      }
    }
  }
  panels <- do.call(rbind, panels)
  rownames(panels) <- NULL
  curve <- if (length(curves)) do.call(rbind, curves) else NULL
  path <- NULL
  if (!is.null(out_pdf) && !is.null(curve)) {
    strip <- paste0(
      panels$panel_title, "\nLog-rank P = ",
      ifelse(is.na(panels$logrank_p), "NE", pub_format_p_cell(panels$logrank_p))
    )
    strip_df <- data.frame(panel = panels$panel, strip = strip, stringsAsFactors = FALSE)
    strip_df <- strip_df[order(strip_df$panel), , drop = FALSE]
    curve <- merge(curve, strip_df, by = "panel", all.x = TRUE, sort = FALSE)
    curve$strip <- factor(curve$strip, levels = strip_df$strip)
    plt <- ggplot2::ggplot(
      curve, ggplot2::aes(x = time, y = surv, colour = grp, fill = grp)
    ) +
      ggplot2::geom_ribbon(
        ggplot2::aes(ymin = lower, ymax = upper),
        alpha = 0.15, linewidth = 0, na.rm = TRUE
      ) +
      ggplot2::geom_step(linewidth = 0.6) +
      ggplot2::facet_wrap(~strip, ncol = 3) +
      ggplot2::scale_y_continuous(limits = c(0, 1), expand = c(0.02, 0)) +
      ggplot2::scale_x_continuous(expand = c(0, 0)) +
      ggplot2::labs(
        x = "Days since ICU admission", y = "Survival probability",
        colour = NULL, fill = NULL,
        title = "Figure 2. Kaplan-Meier curves by SAR tertile, CrCV tertile and joint group"
      ) +
      ggplot2::theme_bw(base_size = 8) +
      ggplot2::theme(
        legend.position = "bottom",
        strip.text = ggplot2::element_text(size = 7),
        panel.grid.minor = ggplot2::element_blank(),
        plot.title = ggplot2::element_text(size = 9, face = "bold")
      )
    dir.create(dirname(out_pdf), recursive = TRUE, showWarnings = FALSE)
    pipeline_ggsave_pdf(out_pdf, plt, width = 10, height = 6.4)
    path <- out_pdf
  }
  list(panels = panels, curve = curve, path = path)
}

sys.source(file.path(study, "config.R"), envir = .GlobalEnv)
cfg <- get("config", envir = .GlobalEnv)
pipeline_apply_pub_digits(cfg)

ck <- file.path(study, "checkpoints", "by_index", "SAR+CrCV")
mi_assoc <- readRDS(file.path(ck, "MIMIC_IV", "step16_ml_assoc_bundle.rds"))$ctx
ei_assoc <- readRDS(file.path(ck, "eICU", "step15_ml_assoc_bundle.rds"))$ctx
mi_ml <- readRDS(file.path(ck, "MIMIC_IV", "step17_ml_models_bundle.rds"))$ctx
ei_ext <- readRDS(file.path(ck, "eICU", "step16_ml_eval_external.rds"))$ctx

.inject_literature_assoc <- function(ctx, study_cfg) {
  ac <- study_cfg$assoc_covariate %||% list()
  ctx$config$assoc_covariate <- modifyList(ctx$config$assoc_covariate %||% list(), ac)
  dat <- ctx$data$imputed %||% ctx$data$train %||% ctx$data$cleaned
  nm <- if (is.data.frame(dat)) names(dat) else NULL
  res <- ml_resolve_assoc_covariates(ctx, data_names = nm)
  ctx$results$assoc_model1_factors <- res$M1
  ctx$results$assoc_model2_factors <- res$M2
  ctx$results$assoc_model3_factors <- res$M3 %||% res$M2
  ctx$results$Model3Factors <- res$M3 %||% res$M2
  ctx$results$assoc_covariate_note <- res$note
  ctx$results$assoc_covariate_scheme <- res$scheme %||% "literature_m123"
  message("literature_m123: ", res$note)
  ctx
}
mi_assoc <- .inject_literature_assoc(mi_assoc, cfg)
ei_assoc$config$assoc_covariate <- modifyList(
  ei_assoc$config$assoc_covariate %||% list(), cfg$assoc_covariate %||% list()
)
ei_assoc$results$assoc_model1_factors <- mi_assoc$results$assoc_model1_factors
ei_assoc$results$assoc_model2_factors <- mi_assoc$results$assoc_model2_factors
ei_assoc$results$assoc_model3_factors <- mi_assoc$results$assoc_model3_factors
ei_assoc$results$Model3Factors <- mi_assoc$results$Model3Factors
ei_assoc$results$assoc_covariate_scheme <- "literature_m123"
ei_assoc$results$tb1 <- mi_assoc$results$tb1
ei_assoc$results$vif_screen_pass <- mi_assoc$results$vif_screen_pass

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
relabel_ctx <- function(ctx) {
  ctx$config$project$analysis_group <- "Non-survivor"
  ctx$config$project$reference_group <- "Survivor"
  ctx$data <- lapply(ctx$data, relabel_outcome)
  ctx
}
mi_assoc <- relabel_ctx(mi_assoc)
ei_assoc <- relabel_ctx(ei_assoc)
mi_ml <- relabel_ctx(mi_ml)
ei_ext <- relabel_ctx(ei_ext)

d02_env <- function(f) { e <- new.env(); load(f, envir = e); e$data_imp }
d02_mi <- d02_env(file.path(study, "data", "D02_result_MIMIC.RData"))
d02_ei <- d02_env(file.path(study, "data", "D02_result_eICU.RData"))
glucose_from_d02 <- function(d, src) {
  gi <- match(as.character(d$ID), as.character(src$ID))
  data.frame(ID = d$ID, Glucose = src$Glucose[gi], stringsAsFactors = FALSE)
}
m2vars <- intersect(unique(c(
  mi_assoc$results$assoc_model2_factors,
  mi_assoc$results$assoc_model3_factors
)), names(mi_assoc$data$imputed))
cc_frame <- function(d, vars) {
  v <- intersect(c(vars, "futime", "fustatus"), names(d))
  d[stats::complete.cases(d[, v, drop = FALSE]), , drop = FALSE]
}

mimic_in <- list(
  train = mi_assoc$data$train, analysis = mi_assoc$data$imputed,
  complete_case = cc_frame(mi_assoc$data$imputed, c("SAR", "CrCV", m2vars)),
  baseline_glucose = glucose_from_d02(mi_assoc$data$imputed, d02_mi),
  assoc_ctx = mi_assoc, config = mi_assoc$config,
  authority_checkpoint = file.path(ck, "MIMIC_IV", "step16_ml_assoc_bundle.rds")
)
eicu_in <- list(
  analysis = ei_assoc$data$imputed,
  complete_case = cc_frame(ei_assoc$data$imputed, c("SAR", "CrCV", m2vars)),
  baseline_glucose = glucose_from_d02(ei_assoc$data$imputed, d02_ei),
  assoc_ctx = ei_assoc, config = ei_assoc$config
)

message("RUN assoc figures/tables")
res <- ref_assoc_run_all(
  mimic_in, eicu_in, out_dir, cutoff = c(4L, 10L),
  grid_n = 40L, quiet = FALSE, indices = c("SAR", "CrCV")
)
write.csv(res$figures$Fig2$panels, file.path(out_dir, "fig2_panels.csv"), row.names = FALSE)
write.csv(res$figures$Fig3$summary, file.path(out_dir, "fig3_summary.csv"), row.names = FALSE)
write.csv(res$figures$Fig4$auc, file.path(out_dir, "fig4_auc.csv"), row.names = FALSE)
write.csv(res$figures$Fig6$rows, file.path(out_dir, "fig6_rows.csv"), row.names = FALSE)
if (!is.null(res$figures$Fig5$results)) {
  write.csv(res$figures$Fig5$results, file.path(out_dir, "fig5_results.csv"), row.names = FALSE)
}

# Table S6：全队列 PH（不再按 SOFA 拆成 S6–S8）
ph <- res$tables$PH
ph <- ph[as.character(ph$stratum) == "Overall", , drop = FALSE]
ph$exposure_p_fmt <- pub_format_p_cell(ph$exposure_p)
ph$global_p_fmt <- pub_format_p_cell(ph$global_p)
exp_df <- ph[, c("database", "index", "n", "events",
                 "exposure_p_fmt", "global_p_fmt", "status")]
names(exp_df) <- c("Database", "Index", "N", "Events",
                   "PH P (exposure)", "PH P (global)", "Status")
.ref_assoc_export_xlsx(
  file.path(out_dir, "Tables", "Table S6 PH overall cohort.xlsx"),
  "Table S6. Proportional-hazards (Schoenfeld) tests, overall cohort.",
  exp_df,
  footnotes = c(
    "Schoenfeld test of the unadjusted Cox model for SAR or CrCV.",
    "Overall cohort; no SOFA split. Outcome: 28-day all-cause mortality."
  )
)
write.csv(exp_df, file.path(out_dir, "s6_overall.csv"), row.names = FALSE)

# Figure S1：双库全队列联合分组的 beta(t)
message("RUN figure S1")
locks <- res$locks
fit_zph <- function(d, dbname, config) {
  d <- data.frame(d)
  d$Group <- as.numeric(reference_apply_joint_tertiles(d, locks$joint)$group)
  d <- .ref_assoc_event01(d, "fustatus", config)
  d$T <- suppressWarnings(as.numeric(d$futime))
  d$D <- as.integer(d$fustatus)
  covs <- intersect(c("Age", "Gender"), names(d))
  need <- c("T", "D", "Group", covs)
  dd <- d[stats::complete.cases(d[, need, drop = FALSE]), , drop = FALSE]
  dd <- dd[is.finite(dd$T) & dd$T > 0 & dd$T <= 28, , drop = FALSE]
  form <- stats::as.formula(sprintf(
    "survival::Surv(T, D) ~ Group + %s",
    paste(.reference_bt(covs), collapse = " + ")
  ))
  fit <- survival::coxph(form, data = dd, x = TRUE, y = TRUE, model = TRUE)
  zph <- survival::cox.zph(fit)
  p_g <- as.numeric(as.data.frame(zph$table)[match("Group", rownames(zph$table)), "p"])
  list(zph = zph, n = nrow(dd), events = sum(dd$D == 1L), p = p_g, database = dbname)
}
mi_z <- fit_zph(mi_assoc$data$imputed, "MIMIC-IV", mi_assoc$config)
ei_z <- fit_zph(ei_assoc$data$imputed, "eICU", ei_assoc$config)
.plot_one <- function(z, letter, db, p) {
  idx <- match("Group", colnames(z$y)); if (is.na(idx)) idx <- 1L
  survival:::plot.cox.zph(
    z, resid = TRUE, se = TRUE, df = 4, nsmo = 40, var = idx,
    xlab = "Time", ylab = "Beta(t) for joint group",
    main = sprintf("%s  %s\nOverall cohort, joint group", letter, db),
    col = 1, lwd = 1, lty = 1:2, pch = 1, cex = 0.55
  )
  graphics::abline(h = 0, col = "pink", lty = 2, lwd = 1.5)
  graphics::mtext(
    sprintf("Schoenfeld P (joint group) = %s",
            format.pval(p, digits = 3, eps = 1e-3)),
    side = 1, line = 3.6, cex = 0.75, adj = 0
  )
}
s1_pdf <- file.path(out_dir, "Figures",
                    "Figure S1. Time-varying PH coefficient trends by SOFA strata.pdf")
grDevices::pdf(s1_pdf, width = 11.2, height = 5.6)
graphics::par(mfrow = c(1, 2), mar = c(5.2, 4.2, 3.8, 1.2), oma = c(2.8, 0.2, 0.2, 0.2))
.plot_one(mi_z$zph, "A", mi_z$database, mi_z$p)
.plot_one(ei_z$zph, "B", ei_z$database, ei_z$p)
graphics::mtext(
  "Fig. S1  Proportional-hazards trend for the SAR+CrCV joint tertile score, overall cohort, Age and sex adjusted. Pink dashed line: Beta(t)=0.",
  side = 1, outer = TRUE, line = 1.4, cex = 0.72, adj = 0
)
grDevices::dev.off()
write.csv(data.frame(
  database = c(mi_z$database, ei_z$database),
  n = c(mi_z$n, ei_z$n), events = c(mi_z$events, ei_z$events),
  ph_p_group = c(mi_z$p, ei_z$p)
), file.path(out_dir, "figs1_ph.csv"), row.names = FALSE)

# Figure 7：全队列 Boruta（只在 MIMIC 训练集）
message("RUN figure 7 boruta")
fig7_ok <- tryCatch({
  tr <- mi_ml$data$train
  cand <- .ml_frozen_candidate_features(mi_ml, stratum = NULL)
  cand <- setdiff(cand, c("futime", "fustatus", "ID", "Group", "SAR", "CrCV", "SOFA"))
  cand <- intersect(cand, names(tr))
  d <- tr[, c("Group", cand), drop = FALSE]
  d <- d[stats::complete.cases(d), , drop = FALSE]
  for (cn in names(d)) if (is.character(d[[cn]])) d[[cn]] <- as.factor(d[[cn]])
  b <- ml_ref_boruta_run(d, max_runs = 50L, seed = 42L, database = "MIMIC_IV")
  r <- ml_ref_boruta_panels(list(Overall = b))
  plt <- r$plots[["Overall"]] +
    ggplot2::labs(
      title = "Figure 7. Boruta feature selection, MIMIC-IV overall cohort",
      caption = "Training set only. SAR and CrCV are the exposures and are not candidate predictors."
    )
  fig7_pdf <- file.path(out_dir, "Figures",
                        "Figure 7. Stratified Boruta feature selection in MIMIC-IV.pdf")
  .ml_fshap_save(plt, fig7_pdf, width = 7.2, height = 5.6)
  message("FIG7 features=", length(cand), " rows=", nrow(d))
  TRUE
}, error = function(e) {
  message("FIG7 FAIL: ", conditionMessage(e))
  FALSE
})

# Figure 8：全队列五模型 ROC + 最优模型 SHAP
message("RUN figure 8")
fig8_ok <- tryCatch({
  fb <- ml_load_frozen_bundle(assets_overall)
  id_col <- as.character(mi_ml$config$data$id_column %||% "ID")[1L]
  mi_all <- mi_ml$data$imputed
  internal <- mi_all[!is.na(match(as.character(mi_all[[id_col]]), fb$internal_ids)), , drop = FALSE]
  mi_res <- ml_predict_external_bundle(fb, internal, stratum = NULL, database = "MIMIC-IV")
  ei_res <- ml_predict_external_bundle(fb, ei_ext$data$imputed, stratum = NULL, database = "eICU")
  stopifnot(isTRUE(ei_res$provenance$no_refit))
  tag <- ml_frozen_best_tag(fb) %||% names(fb$models)[[1]]
  message("FIG8 best tag=", tag)
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
  p <- ml_ref_fig8_grid(
    cells,
    out_pdf = file.path(out_dir, "Figures",
                        "Figure 8. Stratified five-model ROC and SHAP.pdf")
  )
  write.csv(p$auc, file.path(out_dir, "fig8_auc.csv"), row.names = FALSE)
  TRUE
}, error = function(e) {
  message("FIG8 FAIL: ", conditionMessage(e))
  FALSE
})

# S11：只保留 Overall 行，用引擎三线表重写
message("RUN table S11 overall")
s11_ok <- tryCatch({
  old <- file.path(
    study, "by_index", "【success】SAR+CrCV",
    "publication_literature_final", "Tables",
    "Table S11. Stratified five-model machine-learning performance.xlsx"
  )
  s11 <- openxlsx::read.xlsx(old, sheet = 1)
  # 三线表前两行是标题和表头，openxlsx 可能把第一行当表头
  message("S11 colnames: ", paste(names(s11), collapse = " | "))
  message("S11 nrow=", nrow(s11))
  TRUE
}, error = function(e) {
  message("S11 READ FAIL: ", conditionMessage(e))
  FALSE
})

cat("ASSOC_OK fig7=", fig7_ok, " fig8=", fig8_ok, " s11=", s11_ok, "\n")
cat(paste(res$audit$notes, collapse = "\n"), "\n")
