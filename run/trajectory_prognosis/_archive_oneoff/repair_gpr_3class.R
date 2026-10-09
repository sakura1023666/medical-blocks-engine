#!/usr/bin/env Rscript
# GPR 强制 3 类：复用已有 JLCM m1–m6，不重拟合；重跑下游图/表；双库拼图按文献顺序
# Figure 1–4 + S1–S9（每库齐全），根目录仅保留拼图主文/补充，不多不少。
#
#   Rscript run/trajectory_prognosis/repair_gpr_3class.R \
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

.unwrap_jlcm <- function(m) {
  if (inherits(m, "Jointlcmm")) return(m)
  if (is.list(m) && inherits(m$best, "Jointlcmm")) return(m$best)
  m
}

.write_class_from_ng <- function(ctx, Index, ng, id_col = "subject_id") {
  pack <- ctx$results$trajectory_jlcm_models[[Index]]
  if (is.null(pack) || is.null(pack$models)) {
    # 从 step14 RData 回填
    stop("无 JLCM 模型缓存: ", Index, call. = FALSE)
  }
  m_raw <- pack$models[[paste0("m", ng)]]
  if (is.null(m_raw)) stop("缺少 m", ng, call. = FALSE)
  m <- .unwrap_jlcm(m_raw)
  if (is.null(m$pprob)) stop("m", ng, " 无 pprob", call. = FALSE)

  pprob_df <- as.data.frame(m$pprob)
  class_assign <- pprob_df[, c("subject_id_num", "class")]
  model_data_final <- pack$model_data_final
  subj_class <- unique(model_data_final[, c(id_col, "subject_id_num")])
  subj_class <- dplyr::left_join(subj_class, class_assign, by = "subject_id_num")
  subj_class <- subj_class[, c(id_col, "class")]
  names(subj_class)[2] <- "trajectory_class"
  subj_class$trajectory_class <- as.integer(subj_class$trajectory_class)
  idx_col <- paste0("trajectory_class_", Index)
  subj_class[[idx_col]] <- subj_class$trajectory_class

  for (slot in c("imputed", "cleaned", "mapped")) {
    if (is.null(ctx$data[[slot]]) || !id_col %in% names(ctx$data[[slot]])) next
    tgt <- ctx$data[[slot]]
    tgt[[id_col]] <- as.character(tgt[[id_col]])
    tgt$trajectory_class <- NULL
    tgt[[idx_col]] <- NULL
    tgt <- dplyr::left_join(
      tgt,
      dplyr::mutate(subj_class, !!id_col := as.character(.data[[id_col]])),
      by = id_col
    )
    ctx$data[[slot]] <- tgt
  }

  key <- paste0(Index, "_D", ng)
  if (is.null(ctx$data$trajectory_long)) ctx$data$trajectory_long <- list()
  if (!is.null(model_data_final)) {
    long_with_class <- model_data_final |>
      dplyr::left_join(class_assign, by = "subject_id_num") |>
      dplyr::mutate(Class = paste0("Class", class)) |>
      dplyr::rename(Time = time_day, Value = scr_std)
    ctx$data$trajectory_long[[key]] <- long_with_class
  }

  ctx$results[[paste0("trajectory_optimal_ng_", Index)]] <- as.integer(ng)
  ctx$results$trajectory_optimal_ng <- as.integer(ng)
  cli::cli_alert_success("{Index}: 强制 ng={ng}，类别已回写")
  ctx
}

.ensure_models <- function(ctx, unit_dir, Index) {
  pack <- ctx$results$trajectory_jlcm_models[[Index]]
  if (!is.null(pack) && !is.null(pack$models) && !is.null(pack$models$m3)) return(ctx)
  rdata <- file.path(unit_dir, "step14_trajectory_jlcm/Data", paste0("D01_jlcm_", Index, "_models.RData"))
  if (!file.exists(rdata)) stop("缺 JLCM RData: ", rdata, call. = FALSE)
  env <- new.env(parent = emptyenv())
  load(rdata, envir = env)
  ctx$results$trajectory_jlcm_models[[Index]] <- list(
    models = env$models_list_with_cov,
    model_data_final = env$model_data_final
  )
  cli::cli_alert_info("已从 {.file {basename(rdata)}} 载入 models")
  ctx
}

.root <- .init_root()
setwd(.root)
args <- commandArgs(trailingOnly = TRUE)
study_root <- if (length(args) && nzchar(args[[1L]])) args[[1L]] else
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
source(file.path(.root, "configs/indices/composite_index_vars.R"))
if (file.exists(file.path(.root, "R/dual_db_combine_figures.R")))
  source(file.path(.root, "R/dual_db_combine_figures.R"))
if (file.exists(file.path(.root, "R/dual_db_harmonize.R")))
  source(file.path(.root, "R/dual_db_harmonize.R"))
if (file.exists(file.path(.root, "R/pub_figure_export.R")))
  source(file.path(.root, "R/pub_figure_export.R"))

source(file.path(study_root, "config.R"))
config$feishu$enable <- FALSE
config_ix <- trajectory_batch_patch_config_for_index(config, ix)
disease <- gsub("_", " ", as.character(config$project$disease %||% "Sepsis AKI")[1L])

out_ix <- {
  hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
  # 优先 【success】GPR
  prefer <- hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))]
  if (length(prefer)) prefer[[1L]] else {
    hits <- hits[dir.exists(hits) & grepl(paste0(ix, "$"), basename(hits))]
    if (length(hits)) hits[[1L]] else file.path(study_root, "by_index", ix)
  }
}
ck_base <- file.path(study_root, "checkpoints", "by_index", ix)

# 强制 3 类
config_ix$trajectory_jlcm$auto_select_class_ng <- FALSE
config_ix$trajectory_jlcm$assign_class_ng <- ng
config_ix$trajectory_jlcm$prefer_final_ng <- ng
config_ix$trajectory_plot_jlcm$class_for_plot <- ng
config_ix$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
config_ix$trajectory_chisq$class_for_test <- ng
config_ix$trajectory_chisq$use_optimal_class_ng <- FALSE
if (is.null(config_ix$trajectory_dynpred$jlcm)) config_ix$trajectory_dynpred$jlcm <- list()
config_ix$trajectory_dynpred$jlcm$prefer_ng <- ng
config_ix$trajectory_dynpred_individual$jlcm_ng <- ng
config_ix$trajectory_weibull_compare$jlcm_ng <- ng
for (blk in c(
  "trajectory_baseline_by_class", "trajectory_plot_jlcm", "trajectory_km_class",
  "trajectory_dynpred", "trajectory_dynpred_individual", "trajectory_piecewise_cox",
  "trajectory_weibull_compare", "trajectory_subgroup_class", "trajectory_chisq"
)) {
  if (!is.null(config_ix[[blk]])) {
    config_ix[[blk]]$pause_enable <- FALSE
    config_ix[[blk]]$pause_on_no_output <- FALSE
    config_ix[[blk]]$index_vars <- c(ix)
  }
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

cli::cli_h1("GPR 强制 {ng} 类（复用 JLCM，重跑下游 + 拼图）")
cli::cli_alert_info("产出: {.file {out_ix}}")

.run_one_db <- function(db) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  ck <- file.path(ck_base, db)
  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary

  ctx <- tryCatch(
    study_batch_load_checkpoint_ctx(ck, "trajectory_jlcm"),
    error = function(e) study_batch_load_checkpoint_ctx(ck, "multicollinearity_final")
  )
  ctx <- .ensure_models(ctx, unit, ix)

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
  dir.create(file.path(ctx$output_dir_tables, "Summary"), recursive = TRUE, showWarnings = FALSE)

  # 清下游 checkpoint（保留 trajectory_jlcm）
  for (b in downstream) {
    f <- file.path(ck, paste0(b, ".rds"))
    if (file.exists(f)) unlink(f)
    ss <- list.files(ck, pattern = paste0("^step[0-9]+_", b, "\\.rds$"), full.names = TRUE)
    if (length(ss)) unlink(ss)
  }
  # 仅清下游轨迹 step 目录；严禁删 step*_trajectory_jlcm（含 m1–m6 RData）
  for (st in list.dirs(unit, full.names = TRUE, recursive = FALSE)) {
    bn <- basename(st)
    if (!grepl("trajectory_", bn)) next
    if (grepl("trajectory_jlcm", bn)) next
    unlink(st, recursive = TRUE)
  }
  # 清单位 Figures（稍后重生成 + curate）；step06 Missing 源图保留
  if (dir.exists(file.path(unit, "Figures"))) {
    unlink(list.files(file.path(unit, "Figures"), full.names = TRUE), recursive = TRUE, force = TRUE)
  }
  dir.create(file.path(unit, "Figures"), recursive = TRUE, showWarnings = FALSE)

  id_col <- cfg$data$id_column %||% "subject_id"
  ctx <- .write_class_from_ng(ctx, ix, ng, id_col = id_col)
  writeLines(as.character(ng), file.path(unit, "Tables/Summary", paste0("optimal_ng_", ix, ".txt")))

  # Table2 + S8（基于已有 models；Table2 仍展示 1–6）
  pack <- ctx$results$trajectory_jlcm_models[[ix]]
  fp_t2 <- file.path(ctx$output_dir_tables, sprintf("Table 2-%s. Metrics for determining the optimal number of classes.xlsx", db_lab))
  t2_title <- paste0("Table 2. Metrics for determining the optimal number of classes (", ix, ")")
  tryCatch(trajectory_export_table2_sci(ctx, pack$models, fp_t2, t2_title),
           error = function(e) cli::cli_alert_warning("Table2: {e$message}"))
  m_sel <- pack$models[[paste0("m", ng)]]
  fp_s8 <- file.path(ctx$output_dir_tables, sprintf("Table S8-%s. Posterior classification table.xlsx", db_lab))
  tryCatch(
    trajectory_export_posterior_classification_sci(
      ctx, m_sel, fp_s8,
      paste0("Table S8. Posterior classification table (", ix, ", ", db_lab, ")")
    ),
    error = function(e) cli::cli_alert_warning("S8: {e$message}")
  )
  if (exists("render_queued_tables", mode = "function")) render_queued_tables(ctx)

  pl <- list(
    name = paste0("gpr_3class_", db),
    blocks = downstream,
    render_tables_after = downstream,
    checkpoint = list(enable = TRUE, dir = ck)
  )
  cli::cli_h2("[{db_lab}] 下游 ng={ng}")
  run_pipeline(
    .root,
    config = cfg,
    pipeline = pl,
    run_opts = list(initial_ctx = ctx, only = downstream)
  )

  # 拷贝 Missing overview → Figures（供 curate 认 Figure S1）
  miss_src <- file.path(unit, "step06_imputation/Figures/Figure Missing Value Overview.pdf")
  if (file.exists(miss_src)) {
    file.copy(miss_src, file.path(unit, "Figures/Figure Missing Value Overview.pdf"), overwrite = TRUE)
  } else {
    cli::cli_alert_warning("[{db_lab}] 未找到 Missing overview: {.file {miss_src}}")
  }
  invisible(TRUE)
}

for (db in db_seq) .run_one_db(db)

# 发表整理（每库正式名 1–4 + S1–S9）
cli::cli_h2("Curate 分库 Figures/Tables")
trajectory_curate_pub_outputs(
  base_dir = out_ix, index_name = ix, dbs = db_seq, disease = disease
)

# 确保 S1 missing 在分库 Figures
for (db in db_seq) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  dest <- file.path(unit, "Figures", sprintf("Figure S1-%s. Missing value overview.pdf", db_lab))
  if (!file.exists(dest)) {
    src <- file.path(unit, "step06_imputation/Figures/Figure Missing Value Overview.pdf")
    if (file.exists(src)) file.copy(src, dest, overwrite = TRUE)
  }
}

# 双库拼图
cli::cli_h2("双库拼图 + 根目录清理")
cfg_comb <- config_ix
cfg_comb$dual_db$combine_figures <- utils::modifyList(
  cfg_comb$dual_db$combine_figures %||% list(),
  list(enable = TRUE, remove_singles = TRUE, drop_missing_overview = FALSE,
       panel_order = "primary_first", label_format = "A. {db}")
)
cfg_comb$project$output_dir <- out_ix

# 先把分库正式图镜像到根，再 combine
root_fig <- file.path(out_ix, "Figures")
root_tab <- file.path(out_ix, "Tables")
dir.create(root_fig, recursive = TRUE, showWarnings = FALSE)
dir.create(root_tab, recursive = TRUE, showWarnings = FALSE)

# 清根目录旧错乱图（保留四目录结构稍后 export）
old_pdf <- list.files(root_fig, pattern = "\\.pdf$", full.names = TRUE)
if (length(old_pdf)) unlink(old_pdf)
for (sub in c("pdf", "png", "tiff", "image_information")) {
  p <- file.path(root_fig, sub)
  if (dir.exists(p)) unlink(list.files(p, full.names = TRUE), recursive = TRUE, force = TRUE)
}

# 拷贝分库已整理图到根（带库后缀），供 combine 配对
for (db in db_seq) {
  srcs <- list.files(file.path(out_ix, db, "Figures"), pattern = "\\.pdf$", full.names = TRUE)
  for (f in srcs) file.copy(f, file.path(root_fig, basename(f)), overwrite = TRUE)
  # tables
  for (f in list.files(file.path(out_ix, db, "Tables"), pattern = "^Table .*\\.xlsx$", full.names = TRUE))
    file.copy(f, file.path(root_tab, basename(f)), overwrite = TRUE)
}

if (exists("dual_db_combine_paired_figures", mode = "function")) {
  tryCatch(
    dual_db_combine_paired_figures(out_ix, cfg_comb, figures_dir = root_fig),
    error = function(e) cli::cli_alert_warning("拼图失败: {e$message}")
  )
}

# 根目录只保留「无库后缀」的拼图 + Figure 1 Flowchart；删掉 -eICU/-MIMIC 单库残留（若 remove_singles）
singles <- list.files(root_fig, pattern = "-(eICU|MIMIC)\\.pdf$", full.names = TRUE)
if (length(singles) && isTRUE(cfg_comb$dual_db$combine_figures$remove_singles %||% TRUE)) {
  unlink(singles)
}

# 期望根目录图名单（拼图名，无库后缀）
wanted_root <- c(
  "Figure 1. Flowchart of patient selection.pdf",
  "Figure 1. Flowchart.pdf", # 课题可能用此名
  sprintf("Figure 2. Trajectory of %s latent classes.pdf", ix),
  sprintf("Figure 3. Dynamic prediction of %s trajectory.pdf", ix),
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

# 若拼图缺 Figure 1，从课题 attrition / 占位
if (!any(file.exists(file.path(root_fig, c("Figure 1. Flowchart.pdf", "Figure 1. Flowchart of patient selection.pdf"))))) {
  for (db in db_seq) {
    db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
    f1 <- file.path(out_ix, db, "Figures", sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab))
    if (file.exists(f1)) {
      # 无拼图时至少保留双库单图——但用户要拼图；再试 combine 一次或左右拼
      break
    }
  }
}

# 四目录导出
if (exists("export_pub_figures", mode = "function")) {
  tryCatch(
    export_pub_figures(root_fig, index_root = out_ix),
    error = function(e) {
      if (exists("pub_figure_refresh_image_information", mode = "function")) {
        try(pub_figure_refresh_image_information(root_fig), silent = TRUE)
      }
      cli::cli_alert_warning("export_pub_figures: {e$message}")
    }
  )
}

# 分库必须 13 张
cli::cli_h2("核对")
expect_unit <- function(db) {
  db_lab <- if (identical(db, "eicu")) "eICU" else "MIMIC"
  need <- c(
    sprintf("Figure 1-%s. Flowchart of patient selection.pdf", db_lab),
    sprintf("Figure 2-%s. Trajectory of %s latent classes.pdf", db_lab, ix),
    sprintf("Figure 3-%s. Dynamic prediction of %s trajectory.pdf", db_lab, ix),
    sprintf("Figure 4-%s. Individual dynamic prediction.pdf", db_lab),
    sprintf("Figure S1-%s. Missing value overview.pdf", db_lab),
    sprintf("Figure S2-%s. Kaplan Meier survival by trajectory class.pdf", db_lab),
    sprintf("Figure S3-%s. Piecewise Cox cut point search.pdf", db_lab),
    sprintf("Figure S4-%s. Subgroup analysis by trajectory class.pdf", db_lab),
    sprintf("Figure S5-%s. Weibull dynamic model comparison AUC.pdf", db_lab),
    sprintf("Figure S6-%s. Weibull dynamic model comparison C index.pdf", db_lab),
    sprintf("Figure S7-%s. Weibull dynamic model comparison Accuracy.pdf", db_lab),
    sprintf("Figure S8-%s. Weibull dynamic model comparison Sensitivity.pdf", db_lab),
    sprintf("Figure S9-%s. Weibull dynamic model comparison Specificity.pdf", db_lab)
  )
  have <- list.files(file.path(out_ix, db, "Figures"), pattern = "\\.pdf$")
  miss <- setdiff(need, have)
  extra <- setdiff(have, c(need, "_raw"))
  cli::cli_alert_info("[{db_lab}] n={length(have)} miss={length(miss)} extra={length(extra)}")
  if (length(miss)) cli::cli_alert_danger("缺: {paste(miss, collapse=' | ')}")
  if (length(extra)) cli::cli_alert_warning("多: {paste(extra, collapse=' | ')}")
  invisible(list(need = need, have = have, miss = miss, extra = extra))
}
for (db in db_seq) expect_unit(db)
cli::cli_alert_info("根 pdf: {paste(sort(list.files(root_fig, pattern='\\\\.pdf$')), collapse=' | ')}")
cli::cli_alert_success("optimal_ng 已写为 {ng}；JLCM 未重拟合。")
