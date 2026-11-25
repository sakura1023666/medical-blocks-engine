#!/usr/bin/env Rscript
# 重跑 dynpred：Fig3=MIMIC，Fig4=eICU；landmark 3/5/7/12 + mortality
#   Rscript run/trajectory_prognosis/rerun_index_dynpred_fcimb.R --index GPR

suppressPackageStartupMessages({ options(warn = 1) })

.args <- commandArgs(trailingOnly = TRUE)
.get <- function(flag, default = NULL) {
  i <- match(flag, .args)
  if (is.na(i) || i >= length(.args)) return(default)
  .args[[i + 1L]]
}

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

source("R/utils.R")
source("R/pipeline_runner.R")
source("configs/indices/composite_index_vars.R")
source("Blocks/26_trajectory/06block_trajectory_dynpred.R")
if (file.exists("R/trajectory_survival_utils.R")) source("R/trajectory_survival_utils.R")

Sys.setenv(SMOKE_NO_FEISHU = "1", MEDICAL_BLOCKS_AUTO_PUB_QC = "0")
source("configs/config_trajectory_prognosis_copd_jlcm_batch.R")
config$feishu$enable <- FALSE

ix <- .get("--index", "GPR")
proj <- .get("--proj", "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
ck_root <- file.path(proj, "checkpoints/by_index", ix)
out_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
disc_model_dir <- file.path(out_root, "mimic/step14_trajectory_jlcm/Data")
if (!dir.exists(out_root)) stop("缺少指标根: ", out_root)

opt_ng <- file.path(disc_model_dir, "..", "Tables", "Summary", paste0("optimal_ng_", ix, ".txt"))
opt_ng <- normalizePath(opt_ng, winslash = "/", mustWork = FALSE)
if (!file.exists(opt_ng))
  opt_ng <- file.path(out_root, "mimic/Tables/Summary", paste0("optimal_ng_", ix, ".txt"))
prefer_ng <- if (file.exists(opt_ng)) {
  suppressWarnings(as.integer(trimws(readLines(opt_ng, warn = FALSE)[1L])))
} else 3L
if (!is.finite(prefer_ng) || prefer_ng < 2L) prefer_ng <- 3L

config$trajectory_dynpred$pred_scale <- "mortality"
config$trajectory_dynpred$index_vars <- ix
config$trajectory_dynpred$jlcm$prefer_ng <- as.integer(prefer_ng)
config$trajectory_dynpred$jlcm$assessment_times <- c(3, 5, 7, 12)
config$trajectory_dynpred$jlcm$ndraws <- 200L
if (is.null(config$trajectory)) config$trajectory <- list()
config$trajectory$index_vars <- ix
config$trajectory$cycle <- 28L
config$trajectory$jlcm <- config$trajectory_dynpred$jlcm

.wide_to_long <- function(index_df, id_col, index_name, time_end = 28L) {
  day_cols <- paste0(index_name, "_", seq_len(time_end))
  day_cols <- day_cols[day_cols %in% names(index_df)]
  if (!length(day_cols)) stop("宽表缺 ", index_name, "_* 日列")
  out <- lapply(day_cols, function(dc) {
    day <- as.integer(sub(paste0("^", index_name, "_"), "", dc))
    data.frame(
      id = as.character(index_df[[id_col]]),
      time_day = day,
      Value = suppressWarnings(as.numeric(index_df[[dc]])),
      stringsAsFactors = FALSE
    )
  })
  long <- do.call(rbind, out)
  long <- long[is.finite(long$Value), , drop = FALSE]
  names(long)[1L] <- id_col
  long
}

.build_eicu_newdata <- function(ctx, models_env) {
  id_col <- "subject_id"
  wide_path <- file.path(proj, "data/eicu", paste0("12_", ix, ".RData"))
  if (!file.exists(wide_path)) stop("缺 eICU 宽表: ", wide_path)
  e2 <- new.env(parent = emptyenv())
  load(wide_path, envir = e2)
  index_df <- e2$index_df
  long <- .wide_to_long(index_df, id_col, ix, 28L)

  asg_path <- file.path(
    out_root, "eicu/step14_trajectory_lcmm_external_validate/Tables/LCMM",
    paste0("Table_LCMM_Assignment_External_", ix, ".csv")
  )
  if (!file.exists(asg_path)) stop("缺外验 assignment: ", asg_path)
  asg <- utils::read.csv(asg_path, stringsAsFactors = FALSE)
  asg[[id_col]] <- as.character(asg[[id_col]])
  cls_col <- if ("trajectory_class" %in% names(asg)) "trajectory_class" else "class"

  # 与外验块同口径：Value → scr_std（未再 scale）
  id_chr <- as.character(long[[id_col]])
  id_levels <- unique(id_chr)
  id_num <- match(id_chr, id_levels)

  mdata <- models_env$model_data_final
  # 协变量 = 发现集 model_data_final 中除 id/时间/暴露/结局外的列（按指标而变，禁止写死）
  meta_drop <- c(
    id_col, "subject_id_num", "time_day", "scr_std", "Value",
    "survival_time_28d", "survival_28d", "surv_time", "surv_event",
    "event", "event_28d", "time_28d", "class", "trajectory_class"
  )
  cov_need <- setdiff(names(mdata), meta_drop)
  # 别名：外验表常见无下划线写法
  .alias <- c(
    Platelet_Count = "PlateletCount", Neutrophil_Count = "NeutrophilCount",
    Monocyte_Count = "MonocyteCount", Lymphocyte_Count = "LymphocyteCount",
    White_Blood_Cell = "WBC", Red_Blood_Cell = "RBC"
  )
  base <- ctx$data$imputed %||% ctx$data$cleaned
  if (is.null(base)) stop("eICU checkpoint 无 imputed/cleaned")
  base[[id_col]] <- as.character(base[[id_col]])
  for (nm in names(.alias)) {
    alt <- .alias[[nm]]
    if (nm %in% cov_need && !(nm %in% names(base)) && alt %in% names(base))
      base[[nm]] <- base[[alt]]
  }

  keep_b <- intersect(c(id_col, cov_need, "survival_time_28d", "survival_28d",
                        "surv_time", "surv_event"), names(base))
  b1 <- unique(base[, keep_b, drop = FALSE])
  if (!"surv_time" %in% names(b1) && "survival_time_28d" %in% names(b1))
    b1$surv_time <- pmin(as.numeric(b1$survival_time_28d), 28)
  if (!"surv_event" %in% names(b1) && "survival_28d" %in% names(b1)) {
    raw <- b1$survival_28d
    if (exists("pipeline_outcome_as_01", mode = "function"))
      b1$surv_event <- as.integer(pipeline_outcome_as_01(raw, ctx$config))
    else
      b1$surv_event <- as.integer(as.character(raw) %in% c("1", "Non-survivor", "Yes", "TRUE"))
  }

  md <- data.frame(
    subject_id = id_chr,
    subject_id_num = as.integer(id_num),
    time_day = as.numeric(long$time_day),
    scr_std = as.numeric(long$Value),
    stringsAsFactors = FALSE
  )
  md <- merge(md, b1, by = id_col, all.x = TRUE)

  # 缺协变量 / 全 NA：发现集中位数填（外验无该列时常见，如 PCO2）
  for (cv in cov_need) {
    if (!cv %in% names(mdata)) next
    med <- stats::median(as.numeric(mdata[[cv]]), na.rm = TRUE)
    if (!cv %in% names(md) || all(!is.finite(as.numeric(md[[cv]])))) {
      md[[cv]] <- med
      cli::cli_alert_warning("eICU 缺 {cv}，发现集中位数 {round(med, 4)}")
    } else {
      v <- as.numeric(md[[cv]])
      if (any(!is.finite(v))) {
        v[!is.finite(v)] <- med
        md[[cv]] <- v
        cli::cli_alert_warning("eICU {cv} 部分 NA，已用发现集中位数填补")
      }
    }
  }
  # 保证生存列存在（dynpred 块硬要求）
  if (!"surv_time" %in% names(md)) md$surv_time <- 28
  if (!"surv_event" %in% names(md)) md$surv_event <- 0L
  na_st <- !is.finite(as.numeric(md$surv_time))
  if (any(na_st)) md$surv_time[na_st] <- 28
  cli::cli_alert_info(
    "eICU cov_need=[{paste(cov_need, collapse=', ')}]; md cols=[{paste(names(md), collapse=', ')}]"
  )

  # class_df：assignment × subject_id_num
  map_id <- unique(md[, c("subject_id", "subject_id_num")])
  asg2 <- merge(asg[, c(id_col, cls_col)], map_id, by = id_col, all.x = FALSE)
  class_df <- data.frame(
    subject_id_num = as.integer(asg2$subject_id_num),
    class = as.integer(asg2[[cls_col]]),
    stringsAsFactors = FALSE
  )
  class_df <- class_df[!duplicated(class_df$subject_id_num), , drop = FALSE]

  list(model_data_final = md, class_df = class_df, n_id = length(id_levels))
}

.run_one <- function(db) {
  cli::cli_h1("dynpred {toupper(db)}")
  prev <- file.path(ck_root, db, "trajectory_km_class.rds")
  if (!file.exists(prev)) prev <- file.path(ck_root, db, "trajectory_plot_jlcm.rds")
  if (!file.exists(prev)) prev <- file.path(ck_root, db, "trajectory_baseline_by_class.rds")
  if (!file.exists(prev)) stop("无前序 checkpoint: ", db)
  packed <- readRDS(prev)
  ctx <- packed$ctx %||% packed
  ctx$config <- config

  db_out <- file.path(out_root, db)
  step_out <- file.path(db_out, "step18_trajectory_dynpred")
  dir.create(file.path(step_out, "Figures"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(db_out, "Figures"), recursive = TRUE, showWarnings = FALSE)
  ctx$root_output_dir <- db_out
  ctx$output_dir <- step_out
  ctx$output_dir_figures <- file.path(step_out, "Figures")
  ctx$config$project$output_dir <- db_out
  ctx$config$project$mirror_pub_outputs_to_root <- TRUE
  ctx$config$trajectory$jlcm_model_dir <- disc_model_dir

  mf <- file.path(disc_model_dir, paste0("D01_jlcm_", ix, "_models.RData"))
  if (!file.exists(mf)) stop("缺发现集模型: ", mf)
  e <- new.env(parent = emptyenv())
  load(mf, envir = e)
  ctx$results$trajectory_jlcm_models[[ix]] <- list(
    models = e$models_list_with_cov,
    model_data_final = e$model_data_final
  )
  cli::cli_alert_info("已加载发现模型 {.file {mf}} (prefer_ng={prefer_ng})")

  if (identical(db, "eicu")) {
    built <- .build_eicu_newdata(ctx, e)
    ctx$results$trajectory_dynpred_newdata <- list()
    ctx$results$trajectory_dynpred_newdata[[ix]] <- list(
      model_data_final = built$model_data_final,
      class_df = built$class_df
    )
    cli::cli_alert_info(
      "eICU newdata: rows={nrow(built$model_data_final)}, ids={built$n_id}, classed={nrow(built$class_df)}"
    )
  } else {
    ctx$results$trajectory_dynpred_newdata <- NULL
  }

  step_fig <- file.path(db_out, "step18_trajectory_dynpred/Figures")
  dir.create(step_fig, recursive = TRUE, showWarnings = FALSE)
  unlink(list.files(step_fig, pattern = "Dynpred|Dynamic", full.names = TRUE))

  ctx <- block_trajectory_dynpred(ctx)
  # 入队图必须 render（无 pipeline_flush_figure_queue 此名）
  if (exists("flush_pub_output_queues", mode = "function")) {
    ctx <- flush_pub_output_queues(ctx)
  } else if (exists("render_queued_figures", mode = "function")) {
    ctx <- render_queued_figures(ctx)
  }

  dir.create(file.path(ck_root, db), recursive = TRUE, showWarnings = FALSE)
  saveRDS(
    list(ctx = ctx, saved_at = Sys.time(), block = "trajectory_dynpred"),
    file.path(ck_root, db, "trajectory_dynpred.rds")
  )

  src <- list.files(step_fig, pattern = "Dynpred.*\\.pdf$", full.names = TRUE)
  if (!length(src))
    src <- list.files(file.path(db_out, "Figures"), pattern = "Dynpred.*\\.pdf$", full.names = TRUE)
  if (!length(src)) {
    src <- list.files(db_out, pattern = paste0("Figure Dynpred ", ix, "|Figure_Dynpred_", ix), recursive = TRUE, full.names = TRUE)
    src <- src[!grepl("summary_results|Individual", src)]
  }
  # 只取本次新写（mtime 近 2h）
  if (length(src)) {
    info <- file.info(src)
    recent <- src[is.finite(info$mtime) & info$mtime > (Sys.time() - as.difftime(2, units = "hours"))]
    if (length(recent)) src <- recent
  }
  if (!length(src)) {
    cli::cli_alert_danger("{toupper(db)}: 未找到 Dynpred PDF")
    return(invisible(FALSE))
  }
  src <- src[which.max(file.info(src)$mtime)]
  dest_name <- if (identical(db, "mimic"))
    sprintf("Figure 3-MIMIC. Dynamic prediction of %s trajectory.pdf", ix)
  else
    sprintf("Figure 4-eICU. Dynamic prediction of %s trajectory.pdf", ix)
  dest <- file.path(db_out, "Figures", dest_name)
  file.copy(src, dest, overwrite = TRUE)
  file.copy(src, file.path(db_out, "Figures", sprintf("Figure Dynpred %s D%d.pdf", ix, prefer_ng)), overwrite = TRUE)
  cli::cli_alert_success("{toupper(db)} → {.file {dest}} (from {basename(src)})")
  invisible(TRUE)
}

.run_one("mimic")
# 图入队后须 flush：若 .run_one 内已 flush 则 OK；否则补 flush 旧 ckpt
# （脚本内已含 flush_pub_output_queues）
.run_one("eicu")
cli::cli_alert_success("dynpred 双库重跑完成（{ix}: Fig3=MIMIC, Fig4=eICU）")
