#!/usr/bin/env Rscript
# =============================================================================
# 交叉滞后 frailty 唯一入口（run/cross_lagged 仅此文件）
#
# 用法:
#   # 单库/配置驱动主 pipeline（模板或 --config）
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --config /path/to/config.R
#
#   # 三库 study_batch（原 batch 入口）
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --batch
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --batch --config ... --workers auto
#
#   # 研究后段 phase（逻辑在 Blocks/54_cross_lagged_full/phases/）
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase vif_pooled --study-root /path
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase post_vif --only CHARLS,ELSA
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase relock
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase long_figs --sims 200
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase long_mediation
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase subgroup
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase summary
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase prune
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase pub_figs
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase midterm
#   Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase sync --study-root /path
#
# 课题盘同步（默认开启）:
#   每阶段成功后 rsync → 课题盘（排除 data/、默认排除 checkpoints）
#   --sync-root PATH   指定课题盘路径（或 env CROSS_LAGGED_SYNC_ROOT）
#   --no-sync          关闭同步（或 env CROSS_LAGGED_NO_SYNC=1）
#   study 目录下放 CROSS_LAGGED_SYNC_ROOT 单行路径亦可
#
# phase 逻辑目录: Blocks/54_cross_lagged_full/phases/
# 全流程复跑 shell: .../phases/rerun_study_allages.sh
# 试点脚本: Blocks/54_cross_lagged_full/pilots/
#
# phase 名: vif_pooled | post_vif | relock | long_figs | long_mediation |
#           subgroup | summary | prune | pub_figs | midterm | midterm_rmd |
#           batch | sync
# =============================================================================

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_path <- .init_script_dir()
if (basename(script_path) == "cross_lagged" && basename(dirname(script_path)) == "run") {
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
} else {
  root <- script_path
}
setwd(root)

args <- commandArgs(trailingOnly = TRUE)

# ── CLI parse ────────────────────────────────────────────────────────────────
.cli <- list(
  mode = "pipeline",          # pipeline | batch | phase
  config = NULL,
  phase = NULL,
  study_root = NULL,
  only = NULL,
  only_unit = NULL,
  workers = NULL,
  sims = 200L,
  shared_only = FALSE,
  skip_existing = TRUE,
  pooled_only = FALSE,
  rcs_only = FALSE,
  change_only = FALSE,
  scenario = NULL,
  rescreen_med_covars = FALSE,
  with_pooled = FALSE,
  sync_root = NULL,
  no_sync = FALSE
)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--config" && i < length(args)) {
    .cli$config <- normalizePath(args[[i + 1L]], winslash = "/", mustWork = FALSE)
    i <- i + 2L
  } else if (a %in% c("--batch", "--study-batch")) {
    .cli$mode <- "batch"; i <- i + 1L
  } else if (a == "--phase" && i < length(args)) {
    .cli$mode <- "phase"; .cli$phase <- trimws(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--study-root" && i < length(args)) {
    # 容错：路径含空格被 split 时拼回
    j <- i + 1L
    parts <- character(0)
    while (j <= length(args) && !startsWith(args[[j]], "--")) {
      parts <- c(parts, args[[j]]); j <- j + 1L
    }
    .cli$study_root <- paste(parts, collapse = " ")
    i <- j
  } else if (a == "--only" && i < length(args)) {
    .cli$only <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else if (a == "--only-unit" && i < length(args)) {
    .cli$only_unit <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else if (a == "--workers" && i < length(args)) {
    w <- trimws(args[[i + 1L]])
    .cli$workers <- if (tolower(w) == "auto") "auto" else as.integer(w)
    i <- i + 2L
  } else if (a == "--sims" && i < length(args)) {
    .cli$sims <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--shared-only") {
    .cli$shared_only <- TRUE; i <- i + 1L
  } else if (a == "--no-skip") {
    .cli$skip_existing <- FALSE; i <- i + 1L
  } else if (a == "--pooled-only") {
    .cli$pooled_only <- TRUE; i <- i + 1L
  } else if (a == "--rcs-only") {
    .cli$rcs_only <- TRUE; i <- i + 1L
  } else if (a %in% c("--change-only", "--only-change")) {
    .cli$change_only <- TRUE; i <- i + 1L
  } else if (a == "--scenario" && i < length(args)) {
    .cli$scenario <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]); i <- i + 2L
  } else if (a %in% c("--rescreen-mediation-covars", "--rescreen-med-covars")) {
    .cli$rescreen_med_covars <- TRUE; i <- i + 1L
  } else if (a %in% c("--with-pooled", "--pooled")) {
    .cli$with_pooled <- TRUE; i <- i + 1L
  } else if (a %in% c("--no-pooled")) {
    .cli$with_pooled <- FALSE; i <- i + 1L
  } else if (a == "--sync-root" && i < length(args)) {
    j <- i + 1L
    parts <- character(0)
    while (j <= length(args) && !startsWith(args[[j]], "--")) {
      parts <- c(parts, args[[j]]); j <- j + 1L
    }
    .cli$sync_root <- paste(parts, collapse = " ")
    i <- j
  } else if (a %in% c("--no-sync")) {
    .cli$no_sync <- TRUE; i <- i + 1L
  } else if (a %in% c("-h", "--help")) {
    cat(
      "run_cross_lagged_frailty.R — run/cross_lagged 唯一入口\n",
      "  (default)          single-config pipeline\n",
      "  --batch            multi-cohort study_batch\n",
      "  --phase NAME       study phase → Blocks/54_cross_lagged_full/phases/\n",
      "  --config PATH      config R file\n",
      "  --study-root PATH  study output root (for --phase)\n",
      "  --sync-root PATH   课题盘镜像目标（默认读 env/指针文件）\n",
      "  --no-sync          关闭同步到课题盘\n",
      "\n",
      "phase 名:\n",
      "  vif_pooled | post_vif | relock | long_figs | long_mediation\n",
      "  subgroup | summary | prune | pub_figs | sensitivity | midterm | midterm_rmd\n",
      "  batch | sync\n",
      "  各分析 phase 结束后自动收集 summary_result/figure + table（可用 --phase summary 再收一次）\n",
      "  sensitivity 可用 --only DB --scenario exclude_chronic_ge2|complete_case|exclude_event_le_2y|external_validation\n",
      "实现文件: Blocks/54_cross_lagged_full/phases/\n",
      sep = ""
    )
    quit(save = "no", status = 0)
  } else {
    i <- i + 1L
  }
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "Blocks/54_cross_lagged_full/21block_cross_lagged_study_phases.R"))
options(cli.hyperlink = FALSE, warn = 1)

# 同步目标：CLI 写入 env，供 phase / shell 统一读取
if (!is.null(.cli$sync_root) && nzchar(as.character(.cli$sync_root)[1L])) {
  Sys.setenv(CROSS_LAGGED_SYNC_ROOT = as.character(.cli$sync_root)[1L])
}
if (isTRUE(.cli$no_sync)) {
  Sys.setenv(CROSS_LAGGED_NO_SYNC = "1")
}

# ── batch ────────────────────────────────────────────────────────────────────
if (identical(.cli$mode, "batch") || identical(tolower(.cli$phase %||% ""), "batch")) {
  cross_lagged_phase_study_batch(
    root,
    config_path = .cli$config,
    workers = .cli$workers,
    shared_only = isTRUE(.cli$shared_only),
    only_unit = .cli$only_unit,
    skip_existing = isTRUE(.cli$skip_existing)
  )
  # batch 后：若 config 旁有 study 根则同步
  tryCatch({
    cfg <- .cli$config
    if (!is.null(cfg) && file.exists(cfg)) {
      sr <- dirname(normalizePath(cfg, winslash = "/"))
      cross_lagged_sync_to_project_disk(root, sr, no_sync = isTRUE(.cli$no_sync))
    }
  }, error = function(e) cli::cli_alert_warning("batch 后同步: {conditionMessage(e)}"))
  quit(save = "no", status = 0)
}

# ── named phase ──────────────────────────────────────────────────────────────
if (identical(.cli$mode, "phase")) {
  if (is.null(.cli$phase) || !nzchar(.cli$phase))
    stop("使用 --phase 时必须给出 phase 名", call. = FALSE)
  cross_lagged_dispatch_phase(root, .cli$phase, list(
    study_root = .cli$study_root,
    only = .cli$only,
    only_unit = .cli$only_unit,
    workers = .cli$workers,
    sims = .cli$sims,
    config = .cli$config,
    shared_only = .cli$shared_only,
    skip_existing = .cli$skip_existing,
    pooled_only = .cli$pooled_only,
    rcs_only = .cli$rcs_only,
    change_only = .cli$change_only,
    scenario = .cli$scenario,
    rescreen_med_covars = .cli$rescreen_med_covars,
    with_pooled = .cli$with_pooled,
    sync_root = .cli$sync_root,
    no_sync = isTRUE(.cli$no_sync)
  ))
  quit(save = "no", status = 0)
}

# ── default: single pipeline ─────────────────────────────────────────────────
config_path <- .cli$config %||%
  file.path(root, "configs/templates/config_cross_lagged_frailty.template.R")
if (!file.exists(config_path)) {
  # 批量模板亦可用作单跑参考；优先 batch 若主模板不存在
  alt <- file.path(root, "configs/templates/config_cross_lagged_frailty_batch.template.R")
  if (file.exists(alt) && is.null(.cli$config)) {
    cli::cli_alert_warning(
      "无 config_cross_lagged_frailty.template.R；请用 --config 或 --batch"
    )
  }
  stop("config 不存在: ", config_path, call. = FALSE)
}
config_path <- normalizePath(config_path, winslash = "/")

source(file.path(root, "R/feishu_env.R")); feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "R/cross_lagged_table1_harmonize.R"))
source(config_path)
config <- cross_lagged_apply_table1_harmonized(config, root)

if (identical(Sys.getenv("SMOKE_NO_FEISHU", ""), "1")) config$feishu$enable <- FALSE

# pipeline_parse_cli：去掉本入口已消费的 flag，剩余透传（--from/--to 等）
pass <- args
drop_next <- FALSE
pass2 <- character(0)
known_take2 <- c(
  "--config", "--phase", "--study-root", "--only", "--only-unit",
  "--workers", "--sims", "--sync-root", "--scenario"
)
known_take1 <- c(
  "--batch", "--study-batch", "--shared-only", "--no-skip", "--pooled-only",
  "--rcs-only", "--change-only", "--only-change",
  "--rescreen-mediation-covars", "--rescreen-med-covars",
  "--with-pooled", "--pooled", "--no-pooled", "--no-sync", "-h", "--help"
)
j <- 1L
while (j <= length(pass)) {
  a <- pass[[j]]
  if (a %in% known_take2) {
    j <- j + 2L
  } else if (a %in% known_take1) {
    j <- j + 1L
  } else {
    pass2 <- c(pass2, a); j <- j + 1L
  }
}
run_opts <- pipeline_parse_cli(pass2)

t0 <- Sys.time(); status <- "success"; err_msg <- ""
tryCatch(run_pipeline(root, config, pipeline, run_opts), error = function(e) {
  status <<- "error"; err_msg <<- conditionMessage(e); stop(e)
})
# 单库 pipeline 成功后 → 课题盘
tryCatch({
  sr <- cross_lagged_infer_study_root_from_config(config)
  if (!is.null(sr) && nzchar(sr)) {
    cross_lagged_sync_to_project_disk(root, sr, no_sync = isTRUE(.cli$no_sync))
  }
}, error = function(e) cli::cli_alert_warning("pipeline 后同步: {conditionMessage(e)}"))
if (isTRUE((config$feishu %||% list())$enable)) {
  tryCatch(incidence_batch_feishu_push_result(config, list(
    index = "CrossLagged", status = status, db_mode = "Multi_Cohort",
    disease = config$feishu$disease_label, protocol = config$feishu$protocol_label,
    elapsed_sec = as.numeric(difftime(Sys.time(), t0, units = "secs")),
    error_message = err_msg
  )), error = function(e) cli::cli_alert_warning("飞书: {conditionMessage(e)}"))
}
