#!/usr/bin/env Rscript
# GPR 强制 2 类：复用 m2，双库按平均 GPR 对齐（Class1=低位主类）
# 重跑下游图/表；Fig2 用 2×1 上下拼、不拉长；Fig1 用真实纳排图。
#
#   Rscript run/trajectory_prognosis/repair_gpr_2class.R \
#     [/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr]

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      return(normalizePath(file.path(d, "..", ".."), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

.root <- .init_root()
setwd(.root)
.ca <- commandArgs(TRUE)
study_root <- if (length(.ca) && !startsWith(.ca[[1L]], "--")) .ca[[1L]] else
  "/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr"
ix <- "GPR"
ng <- 2L
db_seq <- c("eicu", "mimic")
if ("mimic" %in% .ca || "--resume-mimic" %in% .ca) db_seq <- "mimic"
.resume_from_dynpred <- isTRUE("--from-dynpred" %in% .ca) ||
  identical(Sys.getenv("GPR_2CLASS_FROM"), "dynpred")

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/pipeline_runner.R"))
source(file.path(.root, "R/study_batch_runner.R"))
source(file.path(.root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(.root, "R/trajectory_paper_tables.R"))
source(file.path(.root, "R/trajectory_pub_curate.R"))
source(file.path(.root, "R/trajectory_survival_utils.R"))
source(file.path(.root, "R/dual_db_combine_figures.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(.root, "configs/indices/composite_index_vars.R"))
source(file.path(.root, "Blocks/26_trajectory/04block_trajectory_plot_jlcm.R"))

source(file.path(study_root, "config.R"))
config$feishu$enable <- FALSE
config_ix <- trajectory_batch_patch_config_for_index(config, ix)
disease <- gsub("_", " ", as.character(config$project$disease %||% "Sepsis AKI")[1L])

out_ix <- {
  hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
  prefer <- hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))]
  if (length(prefer)) prefer[[1L]] else
    hits[dir.exists(hits) & grepl(paste0(ix, "$"), basename(hits))][[1L]]
}
ck_base <- file.path(study_root, "checkpoints", "by_index", ix)

.unwrap <- trajectory_unwrap_jointlcmm
.load_pack <- function(unit) {
  rdata <- file.path(unit, "step14_trajectory_jlcm/Data", paste0("D01_jlcm_", ix, "_models.RData"))
  env <- new.env(parent = emptyenv())
  load(rdata, envir = env)
  list(models = env$models_list_with_cov, model_data_final = env$model_data_final)
}

cli::cli_h1("GPR 强制 {ng} 类 + 双库对齐 + 重排版 Fig2")

packs <- list(); curves <- list(); obs_means <- list()
obs_all <- numeric(0); pred_all <- numeric(0)
for (db in c("eicu", "mimic")) {
  packs[[db]] <- .load_pack(file.path(out_ix, db))
  m <- .unwrap(packs[[db]]$models[[paste0("m", ng)]])
  md <- packs[[db]]$model_data_final
  curves[[db]] <- trajectory_jlcm_pred_curves(m, md, 28L, 50L)
  om <- trajectory_jlcm_obs_class_means(m, md, "scr_std")
  obs_means[[db]] <- om
  pred_all <- c(pred_all, as.numeric(curves[[db]])[as.numeric(curves[[db]]) >= 0.5])
  obs_all <- c(obs_all, md$scr_std)
  cat(db, "conv", m$conv, "n", paste(table(m$pprob$class), collapse = "/"),
      "means", paste(round(om, 3), collapse = "/"), "\n")
}
align <- trajectory_align_class_maps(curves, ref = "eicu", obs_means_by_db = obs_means)
ylim <- trajectory_shared_ylim(obs_all, pred_all, ymin = 1)
cli::cli_alert_success(
  "对齐: {paste(sprintf('%s[%s]', names(align$maps), vapply(align$maps, function(z) paste(paste0(names(z),'→',z), collapse=','), character(1))), collapse=' | ')}  ylim=[{ylim[1]}, {ylim[2]}]"
)
dir.create(file.path(out_ix, "Tables/Summary"), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  do.call(rbind, lapply(names(align$maps), function(db) {
    mp <- align$maps[[db]]
    data.frame(db = db, old_class = as.integer(names(mp)), new_class = as.integer(mp))
  })),
  file.path(out_ix, "Tables/Summary/class_align_GPR.csv"), row.names = FALSE
)

# ── 先画正式 Fig2（patchwork 上下拼，不拉长）────────────────────────────────
.make_one <- function(db) {
  m <- .unwrap(packs[[db]]$models[[paste0("m", ng)]])
  md <- packs[[db]]$model_data_final
  pp <- as.data.frame(m$pprob)
  long <- md |>
    dplyr::left_join(pp[, c("subject_id_num", "class")], by = "subject_id_num") |>
    dplyr::mutate(Class = paste0("Class", class)) |>
    dplyr::rename(Time = time_day, Value = scr_std)
  .tpj04_make_plot(
    m, long, ix, ng, 28L, "subject_id", "sans",
    cov_cols = c("OASIS", "Age", "APSIII", "Temperature"),
    class_map = align$maps[[db]], ylim = ylim
  )
}
.panel_theme <- ggplot2::theme(
  plot.title = ggplot2::element_text(face = "bold", size = 11, hjust = 0,
                                     margin = ggplot2::margin(0, 0, 4, 0)),
  plot.margin = ggplot2::margin(2, 6, 2, 6)
)
p_e <- .make_one("eicu") + ggplot2::labs(title = "A. eICU", x = NULL) + .panel_theme
p_m <- .make_one("mimic") + ggplot2::labs(title = "B. MIMIC") + .panel_theme
if (!requireNamespace("patchwork", quietly = TRUE))
  install.packages("patchwork", repos = "https://cloud.r-project.org")
fig2 <- patchwork::wrap_plots(p_e, p_m, ncol = 1) +
  patchwork::plot_annotation(
    title = "Figure 2. Trajectory of GPR latent classes",
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(face = "bold", size = 12, hjust = 0,
                                         margin = ggplot2::margin(2, 0, 6, 0))
    )
  )
fig2_w <- 7.8; fig2_h <- 6.2
.save_pdf <- function(p, fp, w, h) {
  dir.create(dirname(fp), recursive = TRUE, showWarnings = FALSE)
  ggplot2::ggsave(fp, p, width = w, height = h, device = grDevices::cairo_pdf)
}
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  pp <- if (db == "eicu") p_e else p_m
  .save_pdf(pp, file.path(unit, "Figures", sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix)), 7.8, 2.9)
  .save_pdf(pp, file.path(unit, "Figures", sprintf("Figure Trajectory %s D%d.pdf", ix, ng)), 7.8, 2.9)
  dir.create(file.path(unit, "step16_trajectory_plot_jlcm/Figures"), recursive = TRUE, showWarnings = FALSE)
  .save_pdf(pp, file.path(unit, "step16_trajectory_plot_jlcm/Figures", sprintf("Figure Trajectory %s D%d.pdf", ix, ng)), 7.8, 2.9)
  fc <- file.path(unit, "step24_attrition_flowchart/Figures/Figure 1. Flowchart.pdf")
  if (file.exists(fc)) {
    file.copy(fc, file.path(unit, "Figures", sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab)), overwrite = TRUE)
    file.copy(fc, file.path(unit, "Figures/Figure 1. Flowchart.pdf"), overwrite = TRUE)
  }
}
dir.create(file.path(out_ix, "Figures/pdf"), recursive = TRUE, showWarnings = FALSE)
.save_pdf(fig2, file.path(out_ix, "Figures/pdf/Figure 2. Trajectory of GPR latent classes.pdf"), fig2_w, fig2_h)
.save_pdf(fig2, file.path(out_ix, "Figures/Figure 2. Trajectory of GPR latent classes.pdf"), fig2_w, fig2_h)
cli::cli_alert_success("Fig2 已按 2×1 重排（7.8 × 6.2 in）")

.apply_map_to_ctx <- function(ctx, mp, pack, id_col = "subject_id") {
  m <- .unwrap(pack$models[[paste0("m", ng)]])
  pprob <- as.data.frame(m$pprob)
  pprob$new_class <- trajectory_apply_class_swap(pprob$class, mp)
  md <- pack$model_data_final
  subj <- unique(md[, c(id_col, "subject_id_num")])
  subj <- dplyr::left_join(subj, pprob[, c("subject_id_num", "new_class")], by = "subject_id_num")
  names(subj)[names(subj) == "new_class"] <- "trajectory_class"
  subj$trajectory_class <- as.integer(subj$trajectory_class)
  idx_col <- paste0("trajectory_class_", ix)
  subj[[idx_col]] <- subj$trajectory_class
  for (slot in c("imputed", "cleaned", "mapped")) {
    if (is.null(ctx$data[[slot]]) || !id_col %in% names(ctx$data[[slot]])) next
    tgt <- ctx$data[[slot]]
    tgt[[id_col]] <- as.character(tgt[[id_col]])
    tgt$trajectory_class <- NULL
    tgt[[idx_col]] <- NULL
    tgt <- dplyr::left_join(
      tgt, dplyr::mutate(subj, !!id_col := as.character(.data[[id_col]])), by = id_col
    )
    ctx$data[[slot]] <- tgt
  }
  class_assign_raw <- data.frame(subject_id_num = pprob$subject_id_num, class = as.integer(pprob$class))
  key <- paste0(ix, "_D", ng)
  if (is.null(ctx$data$trajectory_long)) ctx$data$trajectory_long <- list()
  ctx$data$trajectory_long[[key]] <- md |>
    dplyr::left_join(class_assign_raw, by = "subject_id_num") |>
    dplyr::mutate(Class = paste0("Class", class)) |>
    dplyr::rename(Time = time_day, Value = scr_std)
  m2 <- .unwrap(pack$models[[paste0("m", ng)]])
  pack$covariate_vars_used <- trajectory_jlcm_cov_cols(pack, m2)
  ctx$results$trajectory_jlcm_models[[ix]] <- pack
  ctx$results[[paste0("trajectory_optimal_ng_", ix)]] <- as.integer(ng)
  ctx$results$trajectory_optimal_ng <- as.integer(ng)
  ctx
}

downstream <- c(
  "trajectory_baseline_by_class",
  "trajectory_plot_jlcm",
  "trajectory_km_class",
  "trajectory_dynpred",
  "trajectory_dynpred_individual",
  "trajectory_piecewise_cox",
  "trajectory_weibull_compare",
  "trajectory_subgroup_class",
  "trajectory_chisq"
)
if (isTRUE(.resume_from_dynpred)) {
  downstream <- c(
    "trajectory_dynpred",
    "trajectory_dynpred_individual",
    "trajectory_piecewise_cox",
    "trajectory_weibull_compare",
    "trajectory_subgroup_class",
    "trajectory_chisq"
  )
  cli::cli_alert_info("续跑：仅 {paste(db_seq, collapse=', ')}，从 dynpred 起")
}

for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  ck <- file.path(ck_base, db)
  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  ctx <- study_batch_load_checkpoint_ctx(ck, "trajectory_jlcm")
  cfg <- config_ix
  cfg$project$database <- db_cfg$name %||% toupper(db)
  cfg$project$output_dir <- unit
  options(pipeline.database_name = cfg$project$database)
  cfg$trajectory_jlcm$auto_select_class_ng <- FALSE
  cfg$trajectory_jlcm$assign_class_ng <- ng
  cfg$trajectory_jlcm$prefer_final_ng <- ng
  cfg$trajectory_plot_jlcm$class_for_plot <- ng
  cfg$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
  cfg$trajectory_plot_jlcm$ylim <- ylim
  cfg$trajectory_plot_jlcm$plot_width <- 7.8
  cfg$trajectory_plot_jlcm$plot_height <- 2.9
  cfg$trajectory_plot_jlcm$class_align_maps <- list()
  cfg$trajectory_plot_jlcm$class_align_maps[[ix]] <- align$maps[[db]]
  cfg$trajectory_plot_jlcm$skip_class_swap <- TRUE
  if (is.null(cfg$trajectory)) cfg$trajectory <- list()
  cfg$trajectory$index_vars <- c(ix)
  cfg$trajectory$skip_class_swap <- TRUE
  cfg$trajectory$class_align_maps <- list()
  cfg$trajectory$class_align_maps[[ix]] <- align$maps[[db]]
  cfg$trajectory_km_class$skip_class_swap <- TRUE
  cfg$trajectory_chisq$class_for_test <- ng
  cfg$trajectory_chisq$use_optimal_class_ng <- FALSE
  if (is.null(cfg$trajectory_dynpred$jlcm)) cfg$trajectory_dynpred$jlcm <- list()
  cfg$trajectory_dynpred$jlcm$prefer_ng <- ng
  cfg$trajectory_dynpred$class_align_maps <- list()
  cfg$trajectory_dynpred$class_align_maps[[ix]] <- align$maps[[db]]
  cfg$trajectory_dynpred_individual$jlcm_ng <- ng
  cfg$trajectory_weibull_compare$jlcm_ng <- ng
  cfg$trajectory_weibull_compare$covariate_vars <-
    trajectory_jlcm_cov_cols(packs[[db]], .unwrap(packs[[db]]$models[[paste0("m", ng)]]))
  cfg$trajectory_dynpred_individual$covariate_vars <- cfg$trajectory_weibull_compare$covariate_vars
  for (b in downstream) {
    if (!is.null(cfg[[b]])) {
      cfg[[b]]$pause_enable <- FALSE
      cfg[[b]]$pause_on_no_output <- FALSE
      cfg[[b]]$index_vars <- c(ix)
    }
  }
  ctx$config <- cfg
  ctx$root_output_dir <- unit
  ctx$output_dir <- unit
  ctx$output_dir_tables <- file.path(unit, "Tables")
  ctx$output_dir_figures <- file.path(unit, "Figures")
  dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
  ctx <- .apply_map_to_ctx(ctx, align$maps[[db]], packs[[db]], cfg$data$id_column %||% "subject_id")
  writeLines(as.character(ng), file.path(unit, "Tables/Summary", paste0("optimal_ng_", ix, ".txt")))

  fp_t2 <- file.path(ctx$output_dir_tables, sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab))
  tryCatch(trajectory_export_table2_sci(ctx, packs[[db]]$models, fp_t2,
    paste0("Table 2. Metrics for determining the optimal number of classes (", ix, ")")),
    error = function(e) cli::cli_alert_warning("Table2: {e$message}"))
  fp_s8 <- file.path(ctx$output_dir_tables, sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab))
  tryCatch(trajectory_export_posterior_classification_sci(
    ctx, packs[[db]]$models[[paste0("m", ng)]], fp_s8,
    paste0("Table S8. Posterior classification table (", ix, ", ", db_lab, ")"),
    class_map = align$maps[[db]]
  ), error = function(e) cli::cli_alert_warning("S8: {e$message}"))

  for (b in downstream) {
    f <- file.path(ck, paste0(b, ".rds"))
    if (file.exists(f)) unlink(f)
    ss <- list.files(ck, pattern = paste0("^step[0-9]+_", b, "\\.rds$"), full.names = TRUE)
    if (length(ss)) unlink(ss)
  }

  pl <- list(
    name = paste0("gpr_2class_", db),
    blocks = downstream,
    render_tables_after = downstream,
    checkpoint = list(enable = TRUE, dir = ck)
  )
  cli::cli_h2("[{db_lab}] 下游 ng=2")
  run_pipeline(.root, config = cfg, pipeline = pl,
               run_opts = list(initial_ctx = ctx, only = downstream))

  # 覆盖 pipeline 可能写歪的 Fig2
  pp <- if (db == "eicu") p_e else p_m
  .save_pdf(pp, file.path(unit, "Figures", sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix)), 7.8, 2.9)
  .save_pdf(pp, file.path(unit, "Figures", sprintf("Figure Trajectory %s D%d.pdf", ix, ng)), 7.8, 2.9)
  miss <- file.path(unit, "step06_imputation/Figures/Figure Missing Value Overview.pdf")
  if (file.exists(miss))
    file.copy(miss, file.path(unit, "Figures/Figure Missing Value Overview.pdf"), overwrite = TRUE)
  fc <- file.path(unit, "step24_attrition_flowchart/Figures/Figure 1. Flowchart.pdf")
  if (file.exists(fc)) {
    file.copy(fc, file.path(unit, "Figures", sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab)), overwrite = TRUE)
    file.copy(fc, file.path(unit, "Figures/Figure 1. Flowchart.pdf"), overwrite = TRUE)
  }
}

# 再写一次根 Fig2（避免 remirror 覆盖）
.save_pdf(fig2, file.path(out_ix, "Figures/pdf/Figure 2. Trajectory of GPR latent classes.pdf"), fig2_w, fig2_h)
.save_pdf(fig2, file.path(out_ix, "Figures/Figure 2. Trajectory of GPR latent classes.pdf"), fig2_w, fig2_h)

trajectory_curate_pub_outputs(base_dir = out_ix, index_name = ix, dbs = db_seq, disease = disease)
# curate 后再盖一次漂亮 Fig2
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  pp <- if (db == "eicu") p_e else p_m
  .save_pdf(pp, file.path(out_ix, db, "Figures",
                          sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix)), 7.8, 2.9)
}

root_fig <- file.path(out_ix, "Figures")
unlink(list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE))
for (db in db_seq) {
  srcs <- list.files(file.path(out_ix, db, "Figures"), pattern = "\\.pdf$", full.names = TRUE)
  srcs <- srcs[!grepl("/_raw/", srcs)]
  for (f in srcs) file.copy(f, file.path(root_fig, basename(f)), overwrite = TRUE)
}
cfg_comb <- config_ix
cfg_comb$dual_db$combine_figures <- utils::modifyList(
  cfg_comb$dual_db$combine_figures %||% list(),
  list(enable = TRUE, remove_singles = TRUE, drop_missing_overview = FALSE,
       panel_order = "primary_first", label_format = "A. {db}",
       layout_by_role = list(Trajectory = "stack", latent = "stack", Dynpred = "stack"))
)
dual_db_combine_paired_figures(out_ix, cfg_comb, figures_dir = root_fig)
.save_pdf(fig2, file.path(root_fig, "Figure 2. Trajectory of GPR latent classes.pdf"), fig2_w, fig2_h)

# S1 手工拼
s1_e <- file.path(root_fig, "Figure S1-eICU. Missing value overview.pdf")
s1_m <- file.path(root_fig, "Figure S1-MIMIC. Missing value overview.pdf")
s1_c <- file.path(root_fig, "Figure S1. Missing value overview.pdf")
if (file.exists(s1_e) && file.exists(s1_m) && requireNamespace("magick", quietly = TRUE)) {
  a <- magick::image_read_pdf(s1_e, density = 140)[1]
  b <- magick::image_read_pdf(s1_m, density = 140)[1]
  a <- magick::image_annotate(a, "A. eICU", size = 24, gravity = "northwest", location = "+14+10")
  b <- magick::image_annotate(b, "B. MIMIC", size = 24, gravity = "northwest", location = "+14+10")
  tmp <- tempfile(fileext = ".png")
  magick::image_write(magick::image_append(c(a, b)), path = tmp, format = "png")
  img <- png::readPNG(tmp)
  grDevices::pdf(s1_c, width = 11, height = 4.8, useDingbats = FALSE)
  graphics::par(mar = c(0, 0, 0, 0)); graphics::plot.new(); graphics::rasterImage(img, 0, 0, 1, 1)
  grDevices::dev.off(); unlink(tmp)
}
unlink(list.files(root_fig, pattern = "-(eICU|MIMIC)\\.pdf$", full.names = TRUE))
keep <- c(
  "Figure 1. Flowchart of patient selection.pdf", "Figure 1. Flowchart.pdf",
  "Figure 2. Trajectory of GPR latent classes.pdf",
  "Figure 3. Dynamic prediction of GPR trajectory.pdf",
  "Figure 4. Individual dynamic prediction.pdf",
  "Figure S1. Missing value overview.pdf",
  "Figure S2. Kaplan Meier survival by trajectory class.pdf",
  "Figure S3. Piecewise Cox cut point search.pdf",
  "Figure S4. Subgroup analysis by trajectory class.pdf",
  "Figure S5. Weibull dynamic model comparison AUC.pdf",
  "Figure S6. Weibull dynamic model comparison C index.pdf",
  "Figure S7. Weibull dynamic model comparison Accuracy.pdf",
  "Figure S8. Weibull dynamic model comparison Sensitivity.pdf",
  "Figure S9. Weibull dynamic model comparison Specificity.pdf"
)
for (f in list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE)) {
  if (!basename(f) %in% keep) unlink(f)
}
f1a <- file.path(root_fig, "Figure 1. Flowchart.pdf")
f1b <- file.path(root_fig, "Figure 1. Flowchart of patient selection.pdf")
if (file.exists(f1a) && !file.exists(f1b)) file.rename(f1a, f1b)

export_pub_figures(root_fig, meta = list(
  exposure = ix, outcome = "28-day mortality", grouping = "2-class JLCM",
  databases = c("eICU", "MIMIC"), combined = TRUE
), config = config_ix, purge = TRUE)
.save_pdf(fig2, file.path(root_fig, "pdf/Figure 2. Trajectory of GPR latent classes.pdf"), fig2_w, fig2_h)
tryCatch(
  .pub_figure_rasterize_one(
    file.path(root_fig, "pdf/Figure 2. Trajectory of GPR latent classes.pdf"),
    file.path(root_fig, "png/Figure 2. Trajectory of GPR latent classes.png"),
    file.path(root_fig, "tiff/Figure 2. Trajectory of GPR latent classes.tiff"),
    300L, root_hint = .root
  ),
  error = function(e) cli::cli_alert_warning("Fig2 raster: {e$message}")
)

cli::cli_alert_success("2 类全套已重跑。Fig2 在 Figures/pdf/。optimal_ng=2")
