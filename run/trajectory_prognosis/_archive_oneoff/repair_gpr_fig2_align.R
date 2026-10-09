#!/usr/bin/env Rscript
# GPR 3 类：Fig1 用真实纳排图；Fig2 双库类别按曲线对齐 + Y 轴从 1 起；
# 同步 KM / Table3 / S7 / S8；根目录拼图并导入 pdf/png/tiff。

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
study_root <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1L]] else
  "/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr"
ix <- "GPR"
ng <- 3L
db_seq <- c("eicu", "mimic")

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

cli::cli_h1("GPR Fig1 纳排 + Fig2 类别对齐（ng={ng}）")

# ── 1) 预测曲线 + 对齐映射 ──────────────────────────────────────────────
packs <- list()
curves <- list()
obs_means <- list()
obs_all <- numeric(0)
pred_all <- numeric(0)
for (db in db_seq) {
  packs[[db]] <- .load_pack(file.path(out_ix, db))
  m <- .unwrap(packs[[db]]$models[[paste0("m", ng)]])
  md <- packs[[db]]$model_data_final
  cv <- trajectory_jlcm_pred_curves(m, md, cycle = 28L, n = 50L)
  if (is.null(cv)) stop(db, " predictY 失败", call. = FALSE)
  curves[[db]] <- cv
  om <- trajectory_jlcm_obs_class_means(m, md, "scr_std")
  obs_means[[db]] <- om
  pred_clip <- as.numeric(cv)
  pred_clip <- pred_clip[is.finite(pred_clip) & pred_clip >= 0.5]
  pred_all <- c(pred_all, pred_clip)
  if ("scr_std" %in% names(md)) obs_all <- c(obs_all, as.numeric(md$scr_std))
  cat(db, " pred range", range(cv, na.rm = TRUE),
      " obs", range(md$scr_std, na.rm = TRUE), " class means", paste(round(om, 3), collapse=","), "\n")
}
align <- trajectory_align_class_maps(curves, ref = "eicu", obs_means_by_db = obs_means)
ylim <- trajectory_shared_ylim(obs_all, pred_all, ymin = 1)
cli::cli_alert_success("对齐映射: {paste(sprintf('%s[%s]', names(align$maps), vapply(align$maps, function(z) paste(paste0(names(z),'→',z), collapse=','), character(1))), collapse=' | ')}")
cli::cli_alert_info("共享 ylim = [{ylim[1]}, {ylim[2]}]")

align_dir <- file.path(out_ix, "Tables", "Summary")
dir.create(align_dir, recursive = TRUE, showWarnings = FALSE)
align_rows <- do.call(rbind, lapply(names(align$maps), function(db) {
  mp <- align$maps[[db]]
  data.frame(db = db, old_class = as.integer(names(mp)), new_class = as.integer(mp),
             stringsAsFactors = FALSE)
}))
utils::write.csv(align_rows, file.path(align_dir, "class_align_GPR.csv"), row.names = FALSE)

# ── 2) 回写对齐后的 class，重画 Fig2 / KM / S7 / Table3 / S8 ─────────────
downstream <- c(
  "trajectory_baseline_by_class",
  "trajectory_plot_jlcm",
  "trajectory_km_class",
  "trajectory_piecewise_cox"
)

.apply_map_to_ctx <- function(ctx, mp, id_col = "subject_id") {
  pack <- ctx$results$trajectory_jlcm_models[[ix]]
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
      tgt,
      dplyr::mutate(subj, !!id_col := as.character(.data[[id_col]])),
      by = id_col
    )
    ctx$data[[slot]] <- tgt
  }
  # 长数据保留 JLCM 原始 class，由 plot 的 class_map 统一映射（避免二次对齐）
  class_assign_raw <- data.frame(
    subject_id_num = pprob$subject_id_num,
    class = as.integer(pprob$class)
  )
  key <- paste0(ix, "_D", ng)
  if (is.null(ctx$data$trajectory_long)) ctx$data$trajectory_long <- list()
  long_with_class <- md |>
    dplyr::left_join(class_assign_raw, by = "subject_id_num") |>
    dplyr::mutate(Class = paste0("Class", class)) |>
    dplyr::rename(Time = time_day, Value = scr_std)
  ctx$data$trajectory_long[[key]] <- long_with_class
  ctx$results[[paste0("trajectory_optimal_ng_", ix)]] <- as.integer(ng)
  ctx$results$trajectory_optimal_ng <- as.integer(ng)
  ctx
}

for (db in db_seq) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  ck <- file.path(ck_base, db)
  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  ctx <- study_batch_load_checkpoint_ctx(ck, "trajectory_jlcm")
  ctx$results$trajectory_jlcm_models[[ix]] <- packs[[db]]
  cfg <- config_ix
  cfg$project$database <- db_cfg$name %||% toupper(db)
  cfg$project$output_dir <- unit
  options(pipeline.database_name = cfg$project$database)
  ctx$config <- cfg
  ctx$root_output_dir <- unit
  ctx$output_dir <- unit
  ctx$output_dir_tables <- file.path(unit, "Tables")
  ctx$output_dir_figures <- file.path(unit, "Figures")
  dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
  dir.create(ctx$output_dir_figures, recursive = TRUE, showWarnings = FALSE)

  identity_map <- align$maps[[db]]
  cfg$trajectory_jlcm$auto_select_class_ng <- FALSE
  cfg$trajectory_jlcm$assign_class_ng <- ng
  cfg$trajectory_plot_jlcm$class_for_plot <- ng
  cfg$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
  cfg$trajectory_plot_jlcm$ylim <- ylim
  cfg$trajectory_plot_jlcm$class_align_maps <- list()
  cfg$trajectory_plot_jlcm$class_align_maps[[ix]] <- identity_map
  cfg$trajectory_plot_jlcm$index_vars <- c(ix)
  for (b in downstream) {
    if (!is.null(cfg[[b]])) {
      cfg[[b]]$pause_enable <- FALSE
      cfg[[b]]$pause_on_no_output <- FALSE
      cfg[[b]]$index_vars <- c(ix)
    }
  }
  ctx$config <- cfg
  ctx <- .apply_map_to_ctx(ctx, identity_map, id_col = cfg$data$id_column %||% "subject_id")

  for (b in downstream) {
    f <- file.path(ck, paste0(b, ".rds"))
    if (file.exists(f)) unlink(f)
    ss <- list.files(ck, pattern = paste0("^step[0-9]+_", b, "\\.rds$"), full.names = TRUE)
    if (length(ss)) unlink(ss)
  }

  fp_s8 <- file.path(ctx$output_dir_tables, sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab))
  # 后验表：按新 class 重排行/列
  m0 <- .unwrap(packs[[db]]$models[[paste0("m", ng)]])
  tryCatch({
    trajectory_export_posterior_classification_sci(
      ctx, m0, fp_s8,
      paste0("Table S8. Posterior classification table (", ix, ", ", db_lab, ")")
    )
    # 用对齐后的 MAP class 覆盖 S8 展示（若导出仍是原始编号，下面 curate 仍保留文件）
  }, error = function(e) cli::cli_alert_warning("S8: {e$message}"))

  pl <- list(
    name = paste0("gpr_align_", db),
    blocks = downstream,
    render_tables_after = downstream,
    checkpoint = list(enable = TRUE, dir = ck)
  )
  cli::cli_h2("[{db_lab}] 对齐后重出 Fig2 / KM / S7 / Table3")
  run_pipeline(
    .root, config = cfg, pipeline = pl,
    run_opts = list(initial_ctx = ctx, only = downstream)
  )

  # 真实纳排图
  fc <- file.path(unit, "step24_attrition_flowchart/Figures/Figure 1. Flowchart.pdf")
  if (!file.exists(fc)) {
    alts <- list.files(unit, pattern = "Figure 1\\..*Flowchart.*\\.pdf$", recursive = TRUE, full.names = TRUE)
    alts <- alts[!grepl("PLACEHOLDER|patient selection", alts, ignore.case = TRUE)]
    if (length(alts)) fc <- alts[which.max(file.info(alts)$size)]
  }
  if (file.exists(fc)) {
    file.copy(fc, file.path(unit, "Figures/Figure 1. Flowchart.pdf"), overwrite = TRUE)
  }
  miss_src <- file.path(unit, "step06_imputation/Figures/Figure Missing Value Overview.pdf")
  if (file.exists(miss_src)) {
    file.copy(miss_src, file.path(unit, "Figures/Figure Missing Value Overview.pdf"), overwrite = TRUE)
  }
}

# ── 3) curate + 拼图 + 四目录 ──────────────────────────────────────────
trajectory_curate_pub_outputs(
  base_dir = out_ix, index_name = ix, dbs = db_seq, disease = disease
)

root_fig <- file.path(out_ix, "Figures")
root_tab <- file.path(out_ix, "Tables")
dir.create(root_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)
old_pdf <- list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE)
if (length(old_pdf)) unlink(old_pdf)

for (db in db_seq) {
  srcs <- list.files(file.path(out_ix, db, "Figures"), pattern = "\\.pdf$", full.names = TRUE)
  srcs <- srcs[!grepl("/_raw/", srcs)]
  for (f in srcs) file.copy(f, file.path(root_fig, basename(f)), overwrite = TRUE)
  for (f in list.files(file.path(out_ix, db, "Tables"), pattern = "^Table .*\\.xlsx$", full.names = TRUE))
    file.copy(f, file.path(root_tab, basename(f)), overwrite = TRUE)
}

cfg_comb <- config_ix
cfg_comb$dual_db$combine_figures <- utils::modifyList(
  cfg_comb$dual_db$combine_figures %||% list(),
  list(enable = TRUE, remove_singles = TRUE, drop_missing_overview = FALSE,
       panel_order = "primary_first", label_format = "A. {db}")
)
cfg_comb$project$output_dir <- out_ix
dual_db_combine_paired_figures(out_ix, cfg_comb, figures_dir = root_fig)

singles <- list.files(root_fig, pattern = "-(eICU|MIMIC)\\.pdf$", full.names = TRUE)
# S1 缺失总览保留拼图名；单库 S1 若未拼上则拼一次
s1_e <- file.path(root_fig, "Figure S1-eICU. Missing value overview.pdf")
s1_m <- file.path(root_fig, "Figure S1-MIMIC. Missing value overview.pdf")
s1_c <- file.path(root_fig, "Figure S1. Missing value overview.pdf")
if (file.exists(s1_e) && file.exists(s1_m) && !file.exists(s1_c)) {
  tryCatch({
    # 用已有配对逻辑：临时改名再 combine 太重，直接 magick 左右拼
    if (requireNamespace("magick", quietly = TRUE)) {
      a <- magick::image_read_pdf(s1_e, density = 150)
      b <- magick::image_read_pdf(s1_m, density = 150)
      a <- magick::image_annotate(a[1], "A. eICU", size = 28, gravity = "northwest", location = "+20+16")
      b <- magick::image_annotate(b[1], "B. MIMIC", size = 28, gravity = "northwest", location = "+20+16")
      comb <- magick::image_append(c(a, b))
      magick::image_write(comb, path = s1_c, format = "pdf")
    }
  }, error = function(e) cli::cli_alert_warning("S1 拼图: {e$message}"))
}
if (length(singles)) unlink(singles)

export_pub_figures(root_fig, meta = list(
  exposure = ix, outcome = "28-day mortality", grouping = "3-class JLCM",
  databases = c("eICU", "MIMIC"), combined = TRUE
), config = config_ix, purge = TRUE)

cli::cli_h2("核对")
cli::cli_alert_info("根目录 PDF: {paste(sort(list.files(root_fig, pattern='\\\\.pdf$')), collapse=' | ')}")
cli::cli_alert_info("pdf/: {length(list.files(file.path(root_fig,'pdf'), pattern='\\\\.pdf$'))}  png/: {length(list.files(file.path(root_fig,'png'), pattern='\\\\.png$'))}  tiff/: {length(list.files(file.path(root_fig,'tiff')))}")
cli::cli_alert_success("完成。类别对齐表: Tables/Summary/class_align_GPR.csv")
