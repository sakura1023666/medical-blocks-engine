#!/usr/bin/env Rscript
# 双库 JLCM 展示类别对齐：Class 1 = 观察均值更低的轨迹（低位），
# 其它库按 trajectory_align_class_maps 重标，使 Class k 跨库可对应。
# 用法（仓库根）:
#   Rscript run/trajectory_prognosis/align_dual_db_class_labels.R \
#     --study "/mnt/g/.../tr" --index ACAG --ng 2

parse_args <- function(args) {
  out <- list(
    study = "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/tr",
    index = "ACAG",
    ng = 2L,
    ndraws = 400L,
    db = "",
    only_dynpred = FALSE,
    blocks = ""
  )
  if (!length(args)) return(out)
  i <- 1L
  while (i <= length(args)) {
    key <- args[[i]]
    if (key %in% c("--study", "--index", "--ng", "--ndraws", "--db", "--blocks") && i < length(args)) {
      val <- args[[i + 1L]]
      if (key == "--study") out$study <- val
      if (key == "--index") out$index <- val
      if (key == "--ng") out$ng <- as.integer(val)
      if (key == "--ndraws") out$ndraws <- as.integer(val)
      if (key == "--db") out$db <- tolower(val)
      if (key == "--blocks") out$blocks <- val
      i <- i + 2L
    } else if (key == "--only-dynpred") {
      out$only_dynpred <- TRUE
      i <- i + 1L
    } else i <- i + 1L
  }
  out
}

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

opt <- parse_args(commandArgs(trailingOnly = TRUE))
.root <- .init_root()
setwd(.root)
study_root <- normalizePath(opt$study, winslash = "/", mustWork = TRUE)
ix <- opt$index
ng <- opt$ng
db_seq <- c("eicu", "mimic")

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/pipeline_runner.R"))
source(file.path(.root, "R/study_batch_runner.R"))
source(file.path(.root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(.root, "R/trajectory_paper_tables.R"))
source(file.path(.root, "R/trajectory_pub_curate.R"))
source(file.path(.root, "R/trajectory_pub_finalize.R"))
source(file.path(.root, "R/trajectory_survival_utils.R"))
source(file.path(.root, "R/dual_db_combine_figures.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(.root, "configs/indices/composite_index_vars.R"))

cfg_fp <- file.path(dirname(study_root), "config_trajectory_prognosis_stroke_batch.R")
if (!file.exists(cfg_fp)) cfg_fp <- file.path(study_root, "config.R")
source(cfg_fp)
config$feishu$enable <- FALSE
config_ix <- trajectory_batch_patch_config_for_index(config, ix)
config_ix$dual_db$primary <- list(name = "eICU", db_type = "eicu")
config_ix$dual_db$secondary <- modifyList(
  config_ix$dual_db$secondary %||% list(),
  list(name = "MIMIC", db_type = "mimic")
)
config_ix$dual_db$combine_figures <- list(
  enable = TRUE, remove_singles = TRUE, drop_missing_overview = FALSE,
  panel_order = "primary_first", label_format = "A. {db}",
  databases = c("eICU", "MIMIC"), primary = "eICU", secondary = "MIMIC"
)

hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
prefer <- hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))]
out_ix <- if (length(prefer)) prefer[[1L]] else
  hits[dir.exists(hits) & grepl(paste0(ix, "$"), basename(hits))][[1L]]
ck_base <- file.path(study_root, "checkpoints", "by_index", ix)
stopifnot(dir.exists(out_ix), dir.exists(ck_base))

.unwrap <- trajectory_unwrap_jointlcmm
.load_pack <- function(unit) {
  rdata <- file.path(unit, "step14_trajectory_jlcm/Data", paste0("D01_jlcm_", ix, "_models.RData"))
  env <- new.env(parent = emptyenv())
  load(rdata, envir = env)
  list(models = env$models_list_with_cov, model_data_final = env$model_data_final)
}

.apply_map_to_ctx <- function(ctx, mp, id_col = "subject_id") {
  pack <- ctx$results$trajectory_jlcm_models[[ix]]
  if (is.null(pack)) stop("checkpoint 缺少 trajectory_jlcm_models", call. = FALSE)
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

cli::cli_h1("{ix} 双库类别对齐（Class 1 = 较低均值）")
packs <- list()
curves <- list()
obs_means <- list()
for (db in db_seq) {
  packs[[db]] <- .load_pack(file.path(out_ix, db))
  m <- .unwrap(packs[[db]]$models[[paste0("m", ng)]])
  md <- packs[[db]]$model_data_final
  cv <- trajectory_jlcm_pred_curves(m, md, cycle = 28L, n = 40L)
  curves[[db]] <- cv
  om <- trajectory_jlcm_obs_class_means(m, md, "scr_std")
  obs_means[[db]] <- om
  cat(db, "obs means", paste(names(om), round(om, 3), sep = "=", collapse = " "), "\n")
}
align <- trajectory_align_class_maps(curves, ref = "mimic", obs_means_by_db = obs_means)
for (db in names(align$maps)) {
  mp <- align$maps[[db]]
  cli::cli_alert_success("{db}: {paste(paste0(names(mp), '->', mp), collapse = ', ')}")
}

align_dir <- file.path(out_ix, "Tables", "Summary")
dir.create(align_dir, recursive = TRUE, showWarnings = FALSE)
align_rows <- do.call(rbind, lapply(names(align$maps), function(db) {
  mp <- align$maps[[db]]
  data.frame(
    db = db, old_class = as.integer(names(mp)), new_class = as.integer(mp),
    rule = "Class1=lower observed mean",
    stringsAsFactors = FALSE
  )
}))
utils::write.csv(align_rows, file.path(align_dir, paste0("class_align_", ix, ".csv")), row.names = FALSE)

downstream <- c(
  "trajectory_baseline_by_class",
  "trajectory_plot_jlcm",
  "trajectory_km_class",
  "trajectory_dynpred",
  "trajectory_piecewise_cox",
  "trajectory_subgroup_class"
)

for (db in db_seq) {
  if (nzchar(opt$db) && db != opt$db) next
  mp <- align$maps[[db]]
  identity <- all(as.character(names(mp)) == as.character(unname(mp)))
  # 恒等映射也必须写进 class_align_maps，否则画图/dynpred 会走 majority-swap，
  # 和 KM、Table 3 的原始编号对不上。
  run_blocks <- if (nzchar(opt$blocks)) {
    trimws(strsplit(opt$blocks, ",", fixed = TRUE)[[1L]])
  } else if (isTRUE(opt$only_dynpred)) {
    "trajectory_dynpred"
  } else if (isTRUE(identity)) {
    c("trajectory_plot_jlcm", "trajectory_dynpred")
  } else {
    downstream
  }
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  ck <- file.path(ck_base, db)
  ctx <- study_batch_load_checkpoint_ctx(ck, "trajectory_jlcm")
  ctx$results$trajectory_jlcm_models[[ix]] <- packs[[db]]
  cfg <- config_ix
  cfg$project$database <- db_lab
  cfg$project$output_dir <- unit
  cfg$project$root <- .root
  options(pipeline.database_name = db_lab)
  ctx$config <- cfg
  ctx$root_output_dir <- unit
  ctx$output_dir <- unit
  ctx$output_dir_tables <- file.path(unit, "Tables")
  ctx$output_dir_figures <- file.path(unit, "Figures")

  cfg$trajectory_jlcm$auto_select_class_ng <- FALSE
  cfg$trajectory_jlcm$assign_class_ng <- ng
  cfg$trajectory_plot_jlcm$class_for_plot <- ng
  cfg$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
  cfg$trajectory_plot_jlcm$class_align_maps <- stats::setNames(list(mp), ix)
  cfg$trajectory_plot_jlcm$index_vars <- c(ix)
  cfg$trajectory <- cfg$trajectory %||% list()
  cfg$trajectory$class_align_maps <- stats::setNames(list(mp), ix)
  cfg$trajectory$skip_class_swap <- FALSE
  cfg$trajectory$index_vars <- c(ix)
  cfg$trajectory$jlcm <- modifyList(cfg$trajectory$jlcm %||% list(), list(
    prefer_ng = ng, assessment_times = c(4, 7, 14, 21), ndraws = opt$ndraws
  ))
  cfg$trajectory_dynpred$jlcm <- cfg$trajectory$jlcm
  cfg$trajectory_plot_jlcm$ylim <- c(5, 32)
  cfg$trajectory_dynpred$ylim <- c(5, 32)
  cfg$trajectory$jlcm$ylim <- c(5, 32)
  cfg$trajectory_subgroup_class$auto_scan_categorical <- FALSE
  cfg$trajectory_subgroup_class$age_var <- "Age"
  cfg$trajectory_subgroup_class$age_cutoff <- 65
  cfg$trajectory_subgroup_class$subgroup_vars <- c("Gender", "Ventilation")
  cfg$trajectory_subgroup_class$forbid_subgroup_vars <- c(
    "Hypertension", "T2DM", "T1DM", "Diabetes", "Heart_Failure",
    "Myocardial_Infarction", "Malignant_Tumor", "CKD", "Liver_cirrhosis",
    "Hepatitis", "Pneumonia", "Stroke", "Hyperlipidemia", "COPD", "Race"
  )
  cfg$trajectory_piecewise_cox$force_cut <- 7L
  cfg$trajectory_piecewise_cox$auto_scan <- TRUE
  for (b in downstream) {
    if (!is.null(cfg[[b]])) {
      cfg[[b]]$pause_enable <- FALSE
      cfg[[b]]$pause_on_no_output <- FALSE
      cfg[[b]]$index_vars <- c(ix)
    }
  }
  ctx$config <- cfg
  ctx <- .apply_map_to_ctx(ctx, mp, id_col = cfg$data$id_column %||% "subject_id")
  tab_n <- table(ctx$data$imputed[[paste0("trajectory_class_", ix)]])
  cli::cli_alert_info("{db_lab} 展示类人数: {paste(names(tab_n), tab_n, sep='=', collapse=' ')}")

  for (b in run_blocks) {
    f <- file.path(ck, paste0(b, ".rds"))
    if (file.exists(f)) unlink(f)
    ss <- list.files(ck, pattern = paste0("^step[0-9]+_", b, "\\.rds$"), full.names = TRUE)
    if (length(ss)) unlink(ss)
  }

  m0 <- .unwrap(packs[[db]]$models[[paste0("m", ng)]])
  fp_s8 <- file.path(ctx$output_dir_tables, sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab))
  tryCatch(
    trajectory_export_posterior_classification_sci(
      ctx, m0, fp_s8,
      sprintf("Table S8-%s. Posterior classification table", db_lab),
      class_map = mp
    ),
    error = function(e) cli::cli_alert_warning("S8: {e$message}")
  )

  pl <- list(
    name = paste0("align_", ix, "_", db),
    blocks = run_blocks,
    render_tables_after = run_blocks,
    checkpoint = list(enable = TRUE, dir = ck)
  )
  cli::cli_h2("[{db_lab}] 按对齐映射重出类别相关表图")
  run_pipeline(.root, config = cfg, pipeline = pl, run_opts = list(initial_ctx = ctx, only = run_blocks))

  t2 <- file.path(unit, "Tables", sprintf(
    "Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab
  ))
  trajectory_xlsx_align_table2_class_props(t2, mp, ng = ng)

  trajectory_curate_pub_outputs(
    base_dir = out_ix, index_name = ix, dbs = db, disease = "Ischemic Stroke"
  )
}

# 拼图：把两库单图放到汇总 Figures 再合并
root_fig <- file.path(out_ix, "Figures")
root_tab <- file.path(out_ix, "Tables")
dir.create(root_fig, recursive = TRUE, showWarnings = FALSE)
for (db in db_seq) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  srcs <- list.files(file.path(out_ix, db, "Figures"), pattern = "\\.pdf$", full.names = TRUE)
  srcs <- srcs[!grepl("/_raw/", srcs)]
  srcs <- srcs[grepl(paste0("-", db_lab, "\\."), basename(srcs))]
  srcs <- srcs[!grepl("Missing value overview", basename(srcs), ignore.case = TRUE)]
  for (f in srcs) file.copy(f, file.path(root_fig, basename(f)), overwrite = TRUE)
  for (bn in c(
    sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab),
    sprintf("Table 3-%s. Time-dependent HR for trajectory classes.xlsx", db_lab),
    sprintf("Table S7-%s. Baseline characteristics by trajectory class (%s).xlsx", db_lab, ix),
    sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab)
  )) {
    src <- file.path(out_ix, db, "Tables", bn)
    if (file.exists(src)) file.copy(src, file.path(root_tab, bn), overwrite = TRUE)
  }
}

cfg_comb <- config_ix
cfg_comb$project$output_dir <- out_ix
dual_db_combine_paired_figures(out_ix, cfg_comb, figures_dir = root_fig)
export_pub_figures(root_fig, meta = list(
  exposure = ix, outcome = "28-day mortality", grouping = "2-class JLCM",
  databases = c("eICU", "MIMIC"), combined = TRUE
), config = config_ix, purge = TRUE)

cli::cli_alert_success("对齐完成: {file.path(align_dir, paste0('class_align_', ix, '.csv'))}")
