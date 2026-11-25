#!/usr/bin/env Rscript
# WPR：复用已有 m5，强制 ng=5，重跑下游 + fcimb 收口（原地改【success】WPR）
#
#   Rscript run/trajectory_prognosis/rerun_wpr_force_ng5_fcimb.R

suppressPackageStartupMessages({ options(warn = 1) })

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)

`%||%` <- function(a, b) if (!is.null(a)) a else b

source("R/utils.R")
source("R/pipeline_runner.R")
source("R/study_batch_runner.R")
source("configs/indices/composite_index_vars.R")
if (file.exists("R/trajectory_survival_utils.R")) source("R/trajectory_survival_utils.R")
if (file.exists("R/trajectory_paper_tables.R")) source("R/trajectory_paper_tables.R")
source("Blocks/26_trajectory/02block_trajectory_jlcm.R")
source("Blocks/26_trajectory/13block_trajectory_lcmm_external_validate.R")
source("Blocks/26_trajectory/06block_trajectory_dynpred.R")
source("Blocks/26_trajectory/30block_trajectory_pamm.R")

Sys.setenv(SMOKE_NO_FEISHU = "1", MEDICAL_BLOCKS_AUTO_PUB_QC = "0")
source("configs/config_trajectory_prognosis_copd_jlcm_batch.R")
config$feishu$enable <- FALSE

ix <- "WPR"
ng <- 5L
proj <- "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"
out_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
ck_root <- file.path(proj, "checkpoints/by_index", ix)
disc_model_dir <- file.path(out_root, "mimic/step14_trajectory_jlcm/Data")
stopifnot(dir.exists(out_root), dir.exists(disc_model_dir))

.unwrap <- function(m) {
  if (inherits(m, "Jointlcmm")) return(m)
  if (is.list(m) && inherits(m$best, "Jointlcmm")) return(m$best)
  m
}

.force_ng_config <- function(cfg) {
  cfg$trajectory_jlcm$auto_select_class_ng <- FALSE
  cfg$trajectory_jlcm$assign_class_ng <- ng
  cfg$trajectory_jlcm$prefer_final_ng <- ng
  cfg$trajectory_plot_jlcm$class_for_plot <- ng
  cfg$trajectory_plot_jlcm$use_optimal_class_ng <- FALSE
  cfg$trajectory_chisq$class_for_test <- ng
  cfg$trajectory_chisq$use_optimal_class_ng <- FALSE
  if (is.null(cfg$trajectory_dynpred$jlcm)) cfg$trajectory_dynpred$jlcm <- list()
  cfg$trajectory_dynpred$jlcm$prefer_ng <- ng
  cfg$trajectory_dynpred$jlcm$assessment_times <- c(3, 5, 7, 12)
  cfg$trajectory_dynpred$pred_scale <- "mortality"
  cfg$trajectory_dynpred_individual$jlcm_ng <- ng
  cfg$trajectory_weibull_compare$jlcm_ng <- ng
  if (is.null(cfg$trajectory_lcmm_external_validate)) cfg$trajectory_lcmm_external_validate <- list()
  cfg$trajectory_lcmm_external_validate$prefer_ng <- ng
  for (v in c(ix)) {
    # index_vars lock
  }
  for (blk in c(
    "trajectory_baseline_by_class", "trajectory_plot_jlcm", "trajectory_km_class",
    "trajectory_dynpred", "trajectory_dynpred_individual", "trajectory_piecewise_cox",
    "trajectory_weibull_compare", "trajectory_subgroup_class", "trajectory_chisq",
    "trajectory_pamm", "trajectory_lcmm_external_validate"
  )) {
    if (!is.null(cfg[[blk]])) {
      cfg[[blk]]$pause_enable <- FALSE
      cfg[[blk]]$pause_on_no_output <- FALSE
      cfg[[blk]]$index_vars <- ix
    }
  }
  if (!is.null(cfg$trajectory)) {
    cfg$trajectory$index_vars <- ix
    cfg$trajectory$cycle <- 28L
    if (is.null(cfg$trajectory$jlcm)) cfg$trajectory$jlcm <- list()
    cfg$trajectory$jlcm$prefer_ng <- ng
    cfg$trajectory$jlcm$assessment_times <- c(3, 5, 7, 12)
  }
  cfg
}

.write_optimal_ng <- function() {
  paths <- c(
    file.path(out_root, "mimic/step14_trajectory_jlcm/Tables/Summary", paste0("optimal_ng_", ix, ".txt")),
    file.path(out_root, "mimic/Tables/Summary", paste0("optimal_ng_", ix, ".txt")),
    file.path(out_root, "Tables/Summary", paste0("optimal_ng_", ix, ".txt"))
  )
  for (p in paths) {
    dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
    writeLines(as.character(ng), p)
  }
  cli::cli_alert_success("optimal_ng_{ix}.txt → {ng}")
}

.write_class_from_m5 <- function(ctx, id_col = "subject_id") {
  pack <- ctx$results$trajectory_jlcm_models[[ix]]
  if (is.null(pack) || is.null(pack$models)) stop("无 JLCM 模型包")
  m <- .unwrap(pack$models[[paste0("m", ng)]])
  if (is.null(m) || is.null(m$pprob)) stop("无 m", ng)
  pprob_df <- as.data.frame(m$pprob)
  class_assign <- pprob_df[, c("subject_id_num", "class")]
  model_data_final <- pack$model_data_final
  subj_class <- unique(model_data_final[, c(id_col, "subject_id_num")])
  subj_class <- merge(subj_class, class_assign, by = "subject_id_num", all.x = TRUE)
  subj_class <- subj_class[, c(id_col, "class")]
  names(subj_class)[2] <- "trajectory_class"
  subj_class$trajectory_class <- as.integer(subj_class$trajectory_class)
  idx_col <- paste0("trajectory_class_", ix)
  subj_class[[idx_col]] <- subj_class$trajectory_class
  cli::cli_alert_info("m{ng} 分类: {paste(names(table(subj_class$trajectory_class)), table(subj_class$trajectory_class), sep='=', collapse=', ')}")

  for (slot in c("imputed", "cleaned", "mapped")) {
    if (is.null(ctx$data[[slot]]) || !id_col %in% names(ctx$data[[slot]])) next
    tgt <- ctx$data[[slot]]
    tgt[[id_col]] <- as.character(tgt[[id_col]])
    drop <- intersect(c("trajectory_class", idx_col), names(tgt))
    if (length(drop)) tgt <- tgt[, setdiff(names(tgt), drop), drop = FALSE]
    sc <- subj_class
    sc[[id_col]] <- as.character(sc[[id_col]])
    tgt <- merge(tgt, sc, by = id_col, all.x = TRUE)
    ctx$data[[slot]] <- tgt
  }
  ctx$results[[paste0("trajectory_optimal_ng_", ix)]] <- ng
  ctx$results$trajectory_optimal_ng <- ng
  ctx
}

.load_jlcm_into_ctx <- function(ctx) {
  mf <- file.path(disc_model_dir, paste0("D01_jlcm_", ix, "_models.RData"))
  e <- new.env(parent = emptyenv())
  load(mf, envir = e)
  ctx$results$trajectory_jlcm_models[[ix]] <- list(
    models = e$models_list_with_cov,
    model_data_final = e$model_data_final
  )
  ctx$config$trajectory$jlcm_model_dir <- disc_model_dir
  ctx
}

.run_downstream <- function(db) {
  cli::cli_h1("{toupper(db)} · 强制 ng={ng}")
  db_out <- file.path(out_root, db)
  ck_db <- file.path(ck_root, db)
  dir.create(db_out, recursive = TRUE, showWarnings = FALSE)

  # 起点：jlcm / km / external；MIMIC 可从已完成的 dynpred 续跑
  prev <- file.path(ck_db, "trajectory_jlcm.rds")
  if (!file.exists(prev)) prev <- file.path(ck_db, "step09_trajectory_jlcm.rds")
  if (identical(db, "eicu")) {
    prev2 <- file.path(ck_db, "trajectory_lcmm_external_validate.rds")
    if (file.exists(prev2)) prev <- prev2
    else if (!file.exists(prev))
      prev <- file.path(ck_db, "trajectory_km_class.rds")
  }
  resume_from <- NULL
  if (identical(db, "mimic")) {
    dyn_ck <- file.path(ck_db, "trajectory_dynpred.rds")
    if (file.exists(dyn_ck) && isTRUE(file.info(dyn_ck)$mtime > Sys.time() - as.difftime(6, units = "hours"))) {
      prev <- dyn_ck
      resume_from <- "piecewise"
      cli::cli_alert_info("MIMIC 续跑：已有今日 dynpred，从 piecewise 起")
    }
  }
  if (!file.exists(prev)) stop("无 checkpoint: ", prev)
  packed <- readRDS(prev)
  ctx <- packed$ctx %||% packed
  ctx <- .load_jlcm_into_ctx(ctx)

  cfg <- .force_ng_config(config)
  cfg$project$database <- if (identical(db, "mimic")) "MIMIC" else "eICU"
  cfg$project$output_dir <- db_out
  cfg$project$mirror_pub_outputs_to_root <- TRUE
  ctx$config <- cfg
  ctx$root_output_dir <- db_out
  ctx$output_dir <- db_out
  ctx$output_dir_tables <- file.path(db_out, "Tables")
  ctx$output_dir_figures <- file.path(db_out, "Figures")
  dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
  dir.create(ctx$output_dir_figures, recursive = TRUE, showWarnings = FALSE)

  id_col <- cfg$data$id_column %||% "subject_id"

  if (identical(db, "mimic")) {
    if (!identical(resume_from, "piecewise")) {
      ctx <- .write_class_from_m5(ctx, id_col = id_col)
      if (exists("trajectory_export_posterior_classification_sci", mode = "function")) {
        m5 <- .unwrap(ctx$results$trajectory_jlcm_models[[ix]]$models[[paste0("m", ng)]])
        fp <- file.path(db_out, "Tables", "Table S8-MIMIC. Posterior classification table.xlsx")
        tryCatch(
          trajectory_export_posterior_classification_sci(
            ctx, m5, fp, paste0("Table S8. Posterior classification table (", ix, ", MIMIC, ng=", ng, ")")
          ),
          error = function(e) cli::cli_alert_warning("后验表: {conditionMessage(e)}")
        )
      }
    } else {
      # 续跑也确保 optimal_ng / 类别列仍是 5
      ctx$results[[paste0("trajectory_optimal_ng_", ix)]] <- ng
      ctx$results$trajectory_optimal_ng <- ng
    }
    # 主文 Fig1–6 必需；跳过 individual/weibull（慢且仅附图）
    blocks <- if (identical(resume_from, "piecewise")) {
      c("trajectory_piecewise_cox", "trajectory_subgroup_class", "trajectory_chisq", "trajectory_pamm")
    } else {
      c(
        "trajectory_baseline_by_class", "trajectory_plot_jlcm", "trajectory_km_class",
        "trajectory_dynpred",
        "trajectory_piecewise_cox",
        "trajectory_subgroup_class", "trajectory_chisq", "trajectory_pamm"
      )
    }
  } else {
    # 外验：用发现集 m5 重新 assignment
    blocks <- c(
      "trajectory_lcmm_external_validate",
      "trajectory_baseline_by_class", "trajectory_plot_jlcm", "trajectory_km_class",
      "trajectory_dynpred",
      "trajectory_piecewise_cox",
      "trajectory_subgroup_class", "trajectory_chisq", "trajectory_pamm"
    )
  }

  pl <- list(
    name = paste0("wpr_ng5_", db),
    blocks = blocks,
    checkpoint = list(enable = TRUE, dir = ck_db)
  )
  ctx <- run_pipeline(
    .root,
    config = cfg,
    pipeline = pl,
    run_opts = list(initial_ctx = ctx, only = blocks)
  )
  # 保存标记
  saveRDS(
    list(ctx = ctx, saved_at = Sys.time(), block = "wpr_force_ng5", ng = ng),
    file.path(ck_db, "wpr_force_ng5.rds")
  )
  invisible(ctx)
}

# ── main ──────────────────────────────────────────────────────────────────────
.write_optimal_ng()
.run_downstream("mimic")
.run_downstream("eicu")

# fcimb 图序收口
rbin <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
scripts <- c(
  "redraw_fcimb_fig1_trajectory.R",
  "redraw_fcimb_fig2_landmark_km.R",
  "rerun_index_dynpred_fcimb.R",
  "rerun_index_pamm_fcimb.R",
  "build_fcimb_summary_results.R"
)
for (s in scripts) {
  sp <- file.path(.root, "run/trajectory_prognosis", s)
  cli::cli_h2("fcimb: {s}")
  st <- system2(rbin, args = c("--vanilla", sp, "--index", ix, "--proj", proj),
                stdout = TRUE, stderr = TRUE)
  if (length(st)) cat(paste(utils::tail(st, 12), collapse = "\n"), "\n")
}

cli::cli_alert_success("WPR 已改为 ng=5 并完成 fcimb 收口 → {.file {out_root}}")
