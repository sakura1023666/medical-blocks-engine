#!/usr/bin/env Rscript
# =============================================================================
#  发病双库批量多指标流水线入口
#  配置: configs/templates/config_incidence_dual_batch.template.R（默认）或 --config <外部路径>
#  引擎: R/incidence_dual_batch_runner.R + R/pipeline_runner.R
#
#  用法（项目根目录）:
#    Rscript run_incidence_dual_batch.R                        # 自动推算并行路数
#    Rscript run_incidence_dual_batch.R --workers auto         # 同上（显式指定 auto）
#    Rscript run_incidence_dual_batch.R --workers 8            # 手动固定 8 路
#    Rscript run_incidence_dual_batch.R --workers 4 --db nhanes
#    Rscript run_incidence_dual_batch.R --shared-only
#    Rscript run_incidence_dual_batch.R --only-index NLR,SII,RAR
#    Rscript run_incidence_dual_batch.R --no-skip              # 强制重跑已完成指标
#    Rscript run_incidence_dual_batch.R --sensitivity-only     # 仅跑敏感性（主分析已完成时）
#    Rscript run_incidence_dual_batch.R --sensitivity-only --only-index NLR
#    Rscript run_incidence_dual_batch.R --config "G:/02block_result/.../config.R"
#    # 局部续跑（阶段别名：subgroup|mediation|rcs|logistic；--to 也可为 sensitivity）
#    Rscript run_incidence_dual_batch.R --only-index HGI --from mediation --to mediation
#    Rscript run_incidence_dual_batch.R --only-index HGI --from mediation --to sensitivity
#
#  引擎路径可通过环境变量固定（与工作目录解耦）:
#    MEDICAL_BLOCKS_ROOT=/opt/medical-blocks Rscript run_incidence_dual_batch.R --config ...
#
#  发病入口仅保留本脚本 + worker；Gate B / 亚组森林 / ROC·boxplot / 附表 S 对齐 /
#  中介筛选已在 Blocks 与 runner 内，勿另建 _repair_/_rerun_*.R。
#  局部续跑：本入口 --from/--to（或 --only-index）。
#  汇总 Tables 不收 .tex（LaTeX 仅留在各 step 子目录）。
# =============================================================================

.init_script_dir <- function() {
  sp <- tryCatch(
    normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path), winslash = "/"),
    error = function(e) NA_character_
  )
  if (!is.na(sp) && nzchar(sp)) return(sp)
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[1L])
    if (nzchar(fp)) return(normalizePath(dirname(fp), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

.parse_batch_args <- function(args) {
  opts <- list(
    config        = NULL,   # --config <path>：外部研究 config 路径（覆盖引擎默认）
    root          = NULL,
    workers       = NULL,
    db_mode       = NULL,
    shared_only   = FALSE,
    only_index    = NULL,
    skip_existing = TRUE,
    p_trim        = 0.01,  # 前后 1% 极端值裁剪
    subgroup_fallback_only = FALSE,   # --subgroup-fallback-only [<ix1,ix2>]
    sfb_only_index = NULL,
    sensitivity_only = FALSE,         # --sensitivity-only [<ix1,ix2>]
    only_scenario = NULL,             # --only-scenario SA_complete_case
    from          = NULL,             # --from <alias|block>
    to            = NULL              # --to <alias|block|sensitivity>
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--workers" && i < length(args)) {
      raw_w <- trimws(args[[i + 1L]])
      opts$workers <- if (tolower(raw_w) == "auto") "auto" else as.integer(raw_w)
      i <- i + 2L
    } else if (a == "--db" && i < length(args)) {
      opts$db_mode <- tolower(trimws(args[[i + 1L]])); i <- i + 2L
    } else if (a == "--shared-only") {
      opts$shared_only <- TRUE; i <- i + 1L
    } else if (a == "--only-index" && i < length(args)) {
      opts$only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else if (a == "--no-skip") {
      opts$skip_existing <- FALSE; i <- i + 1L
    } else if (a == "--ptrim" && i < length(args)) {
      opts$p_trim <- as.numeric(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--from" && i < length(args)) {
      opts$from <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--to" && i < length(args)) {
      opts$to <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--subgroup-fallback-only") {
      # 仅跑亚组补救（跳过主批量）：可带指标列表，缺省=所有【failed】指标
      opts$subgroup_fallback_only <- TRUE
      if (i < length(args) && !startsWith(args[[i + 1L]], "--")) {
        opts$sfb_only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
        i <- i + 2L
      } else {
        i <- i + 1L
      }
    } else if (a == "--sensitivity-only") {
      opts$sensitivity_only <- TRUE
      i <- i + 1L
    } else if (a == "--only-scenario" && i < length(args)) {
      opts$only_scenario <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else if (startsWith(a, "--")) {
      stop("未知参数: ", a, call. = FALSE)
    } else {
      i <- i + 1L
    }
  }
  opts
}

# ── 初始化目录 ──────────────────────────────────────────────────────────────
script_path <- .init_script_dir()

# 支持 MEDICAL_BLOCKS_ROOT 环境变量（引擎路径与工作目录解耦）
env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  script_path <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (basename(script_path) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
           basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args     <- commandArgs(trailingOnly = TRUE)
run_opts <- .parse_batch_args(args)

# 引擎 root：用于 source R/Blocks；课题 root：INCIDENCE_BATCH_ROOT / 位置参数
engine_root <- normalizePath(getwd(), winslash = "/")
.study_env <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
if (!is.null(run_opts$root) && nzchar(run_opts$root)) {
  study_root <- normalizePath(run_opts$root, winslash = "/", mustWork = TRUE)
} else if (nzchar(.study_env) && dir.exists(.study_env)) {
  study_root <- normalizePath(.study_env, winslash = "/", mustWork = TRUE)
} else {
  study_root <- engine_root
}
# 保持向后兼容：root 仍表示引擎（source 路径）；课题路径靠 env + config output_base
Sys.setenv(INCIDENCE_BATCH_ROOT = study_root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine_root)
root <- engine_root

owd <- getwd()
setwd(engine_root)
on.exit(setwd(owd), add = TRUE)

# ── 确定 config 路径（--config 优先，缺省用引擎内默认路径）──────────────────
config_path <- if (!is.null(run_opts$config) && nzchar(run_opts$config)) {
  normalizePath(run_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(engine_root, "configs/templates/config_incidence_dual_batch.template.R")
}

source(file.path(engine_root, "R/feishu_env.R"))
feishu_load_dotenv(engine_root)

# ── 加载依赖 ─────────────────────────────────────────────────────────────────
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/model3_required.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))  # 注入指标名单
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/incidence_pipeline_brief.R"))     # 每指标步骤说明 txt
source(file.path(root, "R/incidence_subgroup_fallback.R"))   # 失败指标亚组补救重跑
source(file.path(root, "R/incidence_sensitivity_suite.R")) # 主分析成功后敏感性重跑
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)   # 支持外部研究 config（--config 指定时不再读引擎内默认路径）

source(file.path(root, "R/pipeline_extension_guard.R"))
.study_dir <- dirname(config_path)
pipeline_extension_guard_check(
  routine = "incidence",
  pipelines = list(
    pipeline_nhanes_batch = if (exists("pipeline_nhanes_batch")) pipeline_nhanes_batch else NULL,
    pipeline_regular_batch = if (exists("pipeline_regular_batch")) pipeline_regular_batch else NULL,
    pipeline_shared_nhanes = if (exists("pipeline_shared_nhanes")) pipeline_shared_nhanes else NULL,
    pipeline_shared_regular = if (exists("pipeline_shared_regular")) pipeline_shared_regular else NULL
  ),
  study_dir = .study_dir,
  root = root
)

options(cli.hyperlink = FALSE)
options(warn = 1)
if (is.null(getOption("repos")) || identical(getOption("repos"), "@CRAN@")) {
  options(repos = c(CRAN = "https://cloud.r-project.org"))
}

# ── 检查 jsonlite ─────────────────────────────────────────────────────────────
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("请先安装 jsonlite 包: install.packages('jsonlite')", call. = FALSE)
}

# ── 仅跑敏感性分析（跳过共享层与主批量）──────────────────────────────────────
if (isTRUE(run_opts$sensitivity_only)) {
  incidence_sensitivity_pass(
    root         = root,
    config       = config,
    config_path  = config_path,
    only_index   = run_opts$only_index,
    only_labels  = run_opts$only_scenario,
    force        = !isTRUE(run_opts$skip_existing)
  )
  quit(save = "no", status = 0)
}

# ── 仅跑亚组补救（跳过主批量）：手动补跑/调试用 ──────────────────────────────
if (isTRUE(run_opts$subgroup_fallback_only)) {
  bc <- config$incidence_batch %||% list()
  output_base <- bc$output_base %||% config$project$output_dir
  failed_ix <- if (!is.null(run_opts$sfb_only_index) && length(run_opts$sfb_only_index)) {
    run_opts$sfb_only_index
  } else {
    incidence_subgroup_find_failed_indices(output_base)
  }
  incidence_subgroup_fallback_pass(root, config, failed_ix, config_path)
  quit(save = "no", status = 0)
}

# ── 启动批量流水线 ────────────────────────────────────────────────────────────
run_incidence_dual_batch(
  root                    = root,
  config                  = config,
  pipeline_nhanes_batch   = pipeline_nhanes_batch,
  pipeline_regular_batch  = pipeline_regular_batch,
  pipeline_shared_nhanes  = pipeline_shared_nhanes,
  pipeline_shared_regular = pipeline_shared_regular,
  run_opts                = run_opts,
  config_path             = config_path   # 传递给 worker 子进程，确保主进程与 worker 读同一份 config
)
