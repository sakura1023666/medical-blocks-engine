#!/usr/bin/env Rscript
# =============================================================================
#  MCV：仅重跑 trajectory_weibull_compare（Acc/Sens/Spec 默认 Youden）+ 发表整理
#
#  用法（仓库根目录）:
#    SMOKE_NO_FEISHU=1 Rscript run/trajectory_prognosis/run_mcv_weibull_youden_rerun.R \
#      --config "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552/config_trajectory_prognosis_stroke_batch.R"
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_args <- function(args) {
  opts <- list(config = NULL, ng = 2L, db = "mimic")
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--ng" && i < length(args)) {
      opts$ng <- as.integer(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--db" && i < length(args)) {
      opts$db <- trimws(args[[i + 1L]]); i <- i + 2L
    } else i <- i + 1L
  }
  opts
}

script_path <- .init_script_dir()
root <- if (basename(script_path) == "trajectory_prognosis" && basename(dirname(script_path)) == "run") {
  normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else script_path
setwd(root)

opt <- .parse_args(commandArgs(trailingOnly = TRUE))
ix <- "MCV"
ng <- as.integer(opt$ng)
db <- opt$db

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))
source(file.path(root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(root, "R/trajectory_pub_curate.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

config_path <- normalizePath(
  opt$config %||% file.path(
    "/mnt/g/02block_result/11_ischemic stroke/Prognosis_Trajectory_38882552",
    "config_trajectory_prognosis_stroke_batch.R"
  ),
  winslash = "/", mustWork = TRUE
)
source(config_path)
config$feishu$enable <- FALSE
options(cli.hyperlink = FALSE, warn = 1)

config_ix <- trajectory_batch_patch_config_for_index(config, ix)
out_root <- file.path(trajectory_batch_index_output_dir(config_ix, ix), db)
out_ck <- trajectory_batch_index_ck_dir(config_ix, ix, db)

cli::cli_h1("MCV Weibull Youden 重跑")
cli::cli_alert_info("output = {.file {out_root}}")
cli::cli_alert_info("checkpoint = {.file {out_ck}}")

ctx <- study_batch_load_checkpoint_ctx(out_ck, "trajectory_jlcm")
if (is.null(ctx)) cli::cli_abort("缺少 trajectory_jlcm 检查点，无法重跑 weibull_compare")

# 尽量带上 piecewise（Table3/cut 无关，但保持上下文完整）
ctx_p <- tryCatch(study_batch_load_checkpoint_ctx(out_ck, "trajectory_piecewise_cox"), error = function(e) NULL)
if (!is.null(ctx_p)) {
  for (nm in names(ctx_p$results)) {
    if (is.null(ctx$results[[nm]])) ctx$results[[nm]] <- ctx_p$results[[nm]]
  }
}

db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
cfg_db <- config_ix
cfg_db$project$database   <- db_cfg$name %||% toupper(db)
cfg_db$project$output_dir <- out_root
cfg_db$trajectory_weibull_compare$index_vars <- c(ix)
cfg_db$trajectory_weibull_compare$jlcm_ng <- ng
cfg_db$trajectory_weibull_compare$class_metric <- "youden"
cfg_db$trajectory_weibull_compare$include_youden_metrics <- TRUE
cfg_db$trajectory_weibull_compare$top_prop <- 0.2
cfg_db$trajectory_weibull_compare$replay_from_results <- FALSE
cfg_db$trajectory_weibull_compare$pause_enable <- FALSE
cfg_db$trajectory_weibull_compare$pause_on_no_output <- FALSE

ctx$config <- cfg_db
ctx$root_output_dir <- out_root
ctx$output_dir <- out_root
ctx$output_dir_tables <- file.path(out_root, "Tables")
ctx$output_dir_figures <- file.path(out_root, "Figures")
dir.create(ctx$output_dir_tables, recursive = TRUE, showWarnings = FALSE)
dir.create(ctx$output_dir_figures, recursive = TRUE, showWarnings = FALSE)

pl <- list(
  name = "mcv_weibull_youden_rerun",
  blocks = "trajectory_weibull_compare",
  checkpoint = list(enable = TRUE, dir = out_ck)
)

t0 <- Sys.time()
ctx <- run_pipeline(
  root, config = cfg_db, pipeline = pl,
  run_opts = list(initial_ctx = ctx, only = "trajectory_weibull_compare")
)
elapsed <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
cli::cli_alert_success("weibull_compare 完成（{round(elapsed, 1)} min）")

# 发表整理：把新图同步进根 Figures（S5–S9）
tryCatch({
  trajectory_curate_pub_outputs(
    base_dir = dirname(out_root),
    index_name = ix,
    dbs = c(db),
    disease = "ischemic stroke"
  )
}, error = function(e) cli::cli_alert_warning("curate 失败: {e$message}"))

# 确保对比 CSV 留在根 Tables（正式白名单不含它，会进 _archive，属预期）
csv_src <- file.path(out_root, "Tables", paste0("Table_Weibull_Dynamic_Compare_", ix, ".csv"))
if (!file.exists(csv_src)) {
  # block 可能写到 step 目录；再搜一遍
  hits <- list.files(out_root, pattern = paste0("^Table_Weibull_Dynamic_Compare_", ix, "\\.csv$"),
                     recursive = TRUE, full.names = TRUE)
  if (length(hits)) csv_src <- hits[1L]
}
if (file.exists(csv_src)) {
  cli::cli_alert_info("对比表: {.file {csv_src}}")
  d <- utils::read.csv(csv_src, stringsAsFactors = FALSE)
  if (all(c("sens_dyn", "sens_weib", "spec_dyn", "spec_weib") %in% names(d))) {
    cli::cli_alert_info(
      "Youden Sens dyn={round(mean(d$sens_dyn, na.rm=TRUE), 3)} weib={round(mean(d$sens_weib, na.rm=TRUE), 3)}; Spec dyn={round(mean(d$spec_dyn, na.rm=TRUE), 3)} weib={round(mean(d$spec_weib, na.rm=TRUE), 3)}"
    )
  }
}

cli::cli_alert_success("完成 → {.file {out_root}}")
