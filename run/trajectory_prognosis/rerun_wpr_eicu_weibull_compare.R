#!/usr/bin/env Rscript
# 补跑 WPR eICU trajectory_weibull_compare（原文 S2 = 动态 vs 静态时依 AUC，双库）
# ng=5 主文重跑曾跳过 weibull；此处注入 MIMIC JLCM m5 + eICU model_data 后单跑 compare。
#
#   Rscript run/trajectory_prognosis/rerun_wpr_eicu_weibull_compare.R
#   # 可选加速（默认与 MIMIC 一致 2000）：
#   Rscript ... --boot-n 500 --perm-n 500

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
source("Blocks/53_trajectory_prognosis_full/02block_trajectory_weibull_compare.R")
if (file.exists("R/trajectory_survival_utils.R")) source("R/trajectory_survival_utils.R")

Sys.setenv(SMOKE_NO_FEISHU = "1", MEDICAL_BLOCKS_AUTO_PUB_QC = "0")
source("configs/config_trajectory_prognosis_copd_jlcm_batch.R")
config$feishu$enable <- FALSE

ix <- "WPR"
ng <- 5L
boot_n <- as.integer(.get("--boot-n", "2000"))
perm_n <- as.integer(.get("--perm-n", "2000"))
proj <- .get("--proj", "G:/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177")
# WSL 可写 /mnt/g
if (!dir.exists(proj) && dir.exists("/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"))
  proj <- "/mnt/g/02block_result/55_COPD/Prognosis_Trajectory_v2_42558177"

ck_root <- file.path(proj, "checkpoints/by_index", ix)
out_root <- file.path(proj, paste0("by_index/\u3010success\u3011", ix))
disc_model_dir <- file.path(out_root, "mimic/step14_trajectory_jlcm/Data")
db_out <- file.path(out_root, "eicu")
step_out <- file.path(db_out, "step21_trajectory_weibull_compare")
dir.create(file.path(step_out, "Figures"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(step_out, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(db_out, "Tables"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(db_out, "Figures"), recursive = TRUE, showWarnings = FALSE)

cli::cli_h1("WPR eICU weibull_compare 补跑 (ng={ng}, boot={boot_n}, perm={perm_n})")

# 起点：eICU dynpred（已有外验 model_data）
prev <- file.path(ck_root, "eicu/trajectory_dynpred.rds")
if (!file.exists(prev)) stop("缺 eICU dynpred checkpoint: ", prev)
packed <- readRDS(prev)
ctx <- packed$ctx %||% packed

# MIMIC JLCM 模型
mf <- file.path(disc_model_dir, paste0("D01_jlcm_", ix, "_models.RData"))
if (!file.exists(mf)) stop("缺发现集模型: ", mf)
e <- new.env(parent = emptyenv())
load(mf, envir = e)

# 外验铁律：协变量 = MIMIC 发现集锁定名单（与 config$trajectory_jlcm$covariate_vars 一致）
cov_used <- as.character(config$trajectory_jlcm$covariate_vars %||% character(0))
mw <- file.path(ck_root, "mimic/trajectory_weibull_compare.rds")
if (!length(cov_used) && file.exists(mw)) {
  mw_obj <- readRDS(mw)
  cov_used <- as.character(
    mw_obj$ctx$results$trajectory_jlcm_models[[ix]]$covariate_vars_used %||% character(0)
  )
}
if (!length(cov_used))
  cov_used <- c("CHARLSON", "Age", "RDW", "NeutrophilCount")
cli::cli_alert_info("锁定 MIMIC 协变量（外验套用）: {paste(cov_used, collapse=', ')}")

# eICU 纵向 + 生存（dynpred 已组装）；缺列用发现集中位数补齐，名单不删
built <- ctx$results$trajectory_dynpred[[ix]]
if (is.null(built) || is.null(built$model_data_final))
  stop("eICU dynpred 无 model_data_final")
md <- built$model_data_final
mimic_md <- e$model_data_final
for (cv in cov_used) {
  med <- if (!is.null(mimic_md) && cv %in% names(mimic_md)) {
    stats::median(suppressWarnings(as.numeric(mimic_md[[cv]])), na.rm = TRUE)
  } else NA_real_
  if (!cv %in% names(md) || all(!is.finite(suppressWarnings(as.numeric(md[[cv]]))))) {
    if (!is.finite(med)) stop("eICU 缺 ", cv, " 且发现集无中位数可填")
    md[[cv]] <- med
    cli::cli_alert_warning("eICU 缺 {cv}，发现集中位数 {round(med, 4)} 整列填入（可能零方差）")
  } else {
    v <- suppressWarnings(as.numeric(md[[cv]]))
    if (any(!is.finite(v))) {
      if (!is.finite(med)) med <- stats::median(v, na.rm = TRUE)
      v[!is.finite(v)] <- med
      md[[cv]] <- v
      cli::cli_alert_warning("eICU {cv} 部分 NA，已用发现集中位数填补")
    }
  }
}
# 零方差仅告警：Weibull 拟合由引擎自动剔奇异列；covariate_vars_used 仍保留完整 MIMIC 名单
base0 <- md[order(md$subject_id_num, md$time_day), , drop = FALSE]
base0 <- base0[!duplicated(base0$subject_id_num), , drop = FALSE]
zv <- cov_used[vapply(cov_used, function(v) {
  x <- suppressWarnings(as.numeric(base0[[v]]))
  !is.finite(stats::sd(x, na.rm = TRUE)) || stats::sd(x, na.rm = TRUE) <= 1e-8
}, logical(1))]
if (length(zv))
  cli::cli_alert_warning(
    "外验零方差（拟合时引擎可剔，名单仍锁定）: {paste(zv, collapse=', ')}"
  )
cli::cli_alert_info(
  "eICU model_data: rows={nrow(md)}, ids={length(unique(md$subject_id_num))}, covs={paste(cov_used, collapse='+')}"
)

# 落盘锁定名单（发表可核）
lock_dir <- file.path(out_root, "Tables", "Summary")
dir.create(lock_dir, recursive = TRUE, showWarnings = FALSE)
lock_fp <- file.path(lock_dir, paste0("JLCM_discovery_survival_covariates_", ix, ".txt"))
writeLines(c(
  sprintf("# WPR external validation locks MIMIC discovery survival covariates"),
  paste0("# Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
  paste0("# zero_variance_on_eicu: ", if (length(zv)) paste(zv, collapse = ",") else "(none)"),
  "",
  cov_used
), lock_fp)
cli::cli_alert_success("锁定名单 → {lock_fp}")

ctx$results$trajectory_jlcm_models <- list()
ctx$results$trajectory_jlcm_models[[ix]] <- list(
  models = e$models_list_with_cov,
  model_data_final = md,
  covariate_vars_used = cov_used
)
ctx$results[[paste0("trajectory_optimal_ng_", ix)]] <- ng
ctx$results$trajectory_optimal_ng <- ng

config$trajectory_jlcm$covariate_vars <- cov_used
config$trajectory_jlcm$covariate_vars_from_vif <- FALSE
config$trajectory_weibull_compare$index_vars <- ix
config$trajectory_weibull_compare$jlcm_ng <- ng
config$trajectory_weibull_compare$landmarks <- 4:14
config$trajectory_weibull_compare$boot_n <- boot_n
config$trajectory_weibull_compare$perm_n <- perm_n
config$trajectory_weibull_compare$covariate_vars <- cov_used
config$trajectory_weibull_compare$pause_enable <- FALSE
config$trajectory_weibull_compare$pause_on_no_output <- FALSE
config$project$database <- "eICU"
config$project$output_dir <- db_out
config$project$mirror_pub_outputs_to_root <- TRUE
config$trajectory$jlcm_model_dir <- disc_model_dir
ctx$config <- config
ctx$root_output_dir <- db_out
ctx$output_dir <- step_out
ctx$output_dir_tables <- file.path(step_out, "Tables")
ctx$output_dir_figures <- file.path(step_out, "Figures")
ctx$config$project$output_dir <- db_out

t0 <- Sys.time()
ctx <- block_trajectory_weibull_compare(ctx)
if (exists("flush_pub_output_queues", mode = "function")) {
  ctx <- flush_pub_output_queues(ctx)
} else if (exists("render_queued_figures", mode = "function")) {
  ctx <- render_queued_figures(ctx)
}
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
cli::cli_alert_success("weibull_compare 完成，耗时 {round(elapsed, 1)} min")

res <- ctx$results$trajectory_weibull_compare[[ix]]
if (is.null(res) || !is.data.frame(res) || !nrow(res))
  stop("无有效 trajectory_weibull_compare$WPR 结果")

# 落盘 CSV（summary + eicu Tables）
csv_paths <- c(
  file.path(step_out, "Tables", paste0("Table_Weibull_Dynamic_Compare_", ix, ".csv")),
  file.path(db_out, "Tables", paste0("Table_Weibull_Dynamic_Compare_", ix, ".csv")),
  file.path(db_out, "Tables/_archive", paste0("Table_Weibull_Dynamic_Compare_", ix, ".csv")),
  file.path(out_root, "summary_results/Tables", paste0("Table_Weibull_Dynamic_Compare_", ix, "_eICU.csv"))
)
for (p in csv_paths) {
  dir.create(dirname(p), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(res, p, row.names = FALSE)
  cli::cli_alert_info("CSV → {p}")
}

dir.create(file.path(ck_root, "eicu"), recursive = TRUE, showWarnings = FALSE)
saveRDS(
  list(ctx = ctx, saved_at = Sys.time(), block = "trajectory_weibull_compare"),
  file.path(ck_root, "eicu/trajectory_weibull_compare.rds")
)
cli::cli_alert_success("checkpoint → checkpoints/by_index/WPR/eicu/trajectory_weibull_compare.rds")
print(res[, c("landmark", "n_landmark", "auc_dyn", "auc_weib", "p_auc")])
cli::cli_alert_success("下一步：python3 run/trajectory_prognosis/redraw_wpr_fig_s2_fcimb_style.py（将改用双库 AUC）")
