#!/usr/bin/env Rscript
# =============================================================================
#  发病双库批量 — 单指标 Worker 子进程 v2
#
#  用法（调试）:
#    Rscript run_incidence_dual_batch_worker.R --index NLR [--db both] [--ptrim 0.01]
#
#  流程:
#    1. 解析参数
#    2. source 依赖 + config
#    3. patch config 为该指标
#    4. 检查 shared checkpoint 中该指标是否可用
#    5. 复制 shared checkpoint → per-index 目录
#    6. 原地过滤：删除 NA 行（保存回 index.rds；不做极端值裁剪）
#    7. 两阶段双库分析（Phase 1→ Gate B → Phase 2/3）
#    8. 写 _batch_status.json（含 N 统计）+ _index_summary.csv
#    9. exit 0/1
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

.parse_worker_args <- function(args) {
  opts <- list(
    index = NULL, db_mode = "both", root = NULL, p_trim = 0.01,
    config = NULL, from = NULL, to = NULL, blocks = NULL
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--index" && i < length(args)) {
      opts$index <- trimws(args[[i+1L]]); i <- i+2L
    } else if (a == "--db" && i < length(args)) {
      opts$db_mode <- tolower(trimws(args[[i+1L]])); i <- i+2L
    } else if (a == "--ptrim" && i < length(args)) {
      opts$p_trim <- as.numeric(args[[i+1L]]); i <- i+2L
    } else if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i+1L]]); i <- i+2L
    } else if (a == "--from" && i < length(args)) {
      opts$from <- trimws(args[[i+1L]]); i <- i+2L
    } else if (a == "--to" && i < length(args)) {
      opts$to <- trimws(args[[i+1L]]); i <- i+2L
    } else if (a == "--blocks" && i < length(args)) {
      opts$blocks <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      opts$blocks <- opts$blocks[nzchar(opts$blocks)]
      i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i+1L
    } else {
      i <- i+1L
    }
  }
  if (is.null(opts$index) || !nzchar(opts$index))
    stop("--index 参数必填", call. = FALSE)
  if (!opts$db_mode %in% c("both","nhanes","mimic"))
    stop("--db 仅支持 both|nhanes|mimic", call. = FALSE)
  opts
}

# ── 初始化 ───────────────────────────────────────────────────────────────────
script_path <- .init_script_dir()
if (basename(script_path) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
    basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine_root)) {
  engine_root <- normalizePath(script_path, winslash = "/")
} else {
  engine_root <- normalizePath(engine_root, winslash = "/", mustWork = TRUE)
}

study_root <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
if (!nzchar(study_root) && !is.null(wk_opts$root) && nzchar(wk_opts$root)) {
  study_root <- wk_opts$root
}
## code 包 / --config 重跑：未显式给课题根时，用 config 所在目录（勿落回引擎根）
if (!nzchar(study_root) && !is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  cfg_try <- wk_opts$config
  if (file.exists(cfg_try)) study_root <- dirname(normalizePath(cfg_try, winslash = "/"))
}
if (nzchar(study_root)) {
  study_root <- normalizePath(study_root, winslash = "/", mustWork = TRUE)
} else {
  study_root <- engine_root
}

owd <- getwd()
setwd(study_root)
on.exit(setwd(owd), add = TRUE)
root <- study_root
message(sprintf(
  "[worker-env] INCIDENCE_BATCH_ROOT=%s MEDICAL_BLOCKS_ROOT=%s study_root=%s shared_ck=%s",
  Sys.getenv("INCIDENCE_BATCH_ROOT"),
  Sys.getenv("MEDICAL_BLOCKS_ROOT"),
  study_root,
  file.path(study_root, "checkpoints/_shared")
))

ix      <- wk_opts$index
db_mode <- wk_opts$db_mode
p_trim  <- wk_opts$p_trim
from_cli <- wk_opts$from
to_cli   <- wk_opts$to
blocks_cli <- wk_opts$blocks %||% character(0)
resume_mode <- (
  (!is.null(from_cli) && nzchar(as.character(from_cli)[1L])) ||
  (!is.null(to_cli) && nzchar(as.character(to_cli)[1L])) ||
  length(blocks_cli) > 0L
)

t_start <- proc.time()

source(file.path(engine_root, "R/feishu_env.R"))
feishu_load_dotenv(engine_root)

# ── 确定 config 路径（继承主进程 --config，缺省用引擎内默认路径）────────────
config_path <- {
  env_cfg <- Sys.getenv("INCIDENCE_BATCH_CONFIG", unset = "")
  if (nzchar(env_cfg)) {
    normalizePath(env_cfg, winslash = "/", mustWork = TRUE)
  } else if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
    normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
  } else {
    file.path(engine_root, "configs/templates/config_incidence_dual_batch.template.R")
  }
}
Sys.setenv(STUDY_CONFIG_DIR = dirname(config_path))

# ── 加载依赖 ─────────────────────────────────────────────────────────────────
source(file.path(engine_root, "R/utils.R"))
source(file.path(engine_root, "R/model3_required.R"))
source(file.path(engine_root, "R/baseline_dictionary_labels.R"))
source(file.path(engine_root, "R/dual_db_harmonize.R"))
source(file.path(engine_root, "R/logistic_gate.R"))
source(file.path(engine_root, "R/pipeline_runner.R"))
source(file.path(engine_root, "configs/indices/composite_index_vars.R"))
source(file.path(engine_root, "R/incidence_dual_batch_runner.R"))
source(file.path(engine_root, "R/incidence_sensitivity_suite.R"))
source(file.path(engine_root, "R/incidence_pipeline_brief.R"))
source(file.path(engine_root, "R/feishu_bitable.R"))
source(file.path(engine_root, "R/pub_figure_export.R"))
source(file.path(engine_root, "R/subgroup_vars.R"))
source(file.path(engine_root, "R/subgroup_forest_plot.R"))
source(file.path(engine_root, "Blocks/20_mediation/00mediation_common.R"))
source(config_path)   # 与主进程使用同一份 config

gate_a_bundle <- tryCatch(
  incidence_batch_ensure_gate_a(config, root),
  error = function(e) {
    cli::cli_alert_warning("Worker Gate A 加载失败: {e$message}")
    list(config = config, gate_a = NULL)
  }
)
config <- gate_a_bundle$config

if (!requireNamespace("jsonlite", quietly = TRUE))
  stop("请先安装 jsonlite: install.packages('jsonlite')", call. = FALSE)

options(cli.hyperlink = FALSE, warn = 1)

# ── 辅助 ────────────────────────────────────────────────────────────────────
# 单库 NHANES/KNHANES config 常只定义 pipeline；双库模板才有 pipeline_nhanes_batch
.incidence_worker_pipeline_for_db <- function(cfg, db) {
  if (dual_db_is_weighted(cfg, db)) {
    pl <- get0("pipeline_nhanes_batch", ifnotfound = NULL, inherits = TRUE)
    if (is.null(pl)) pl <- get0("pipeline", ifnotfound = NULL, inherits = TRUE)
    if (is.null(pl)) {
      stop("缺少 pipeline_nhanes_batch / pipeline（加权库敏感性/worker）", call. = FALSE)
    }
    return(pl)
  }
  pl <- get0("pipeline_regular_batch", ifnotfound = NULL, inherits = TRUE)
  if (is.null(pl)) pl <- get0("pipeline", ifnotfound = NULL, inherits = TRUE)
  if (is.null(pl)) {
    stop("缺少 pipeline_regular_batch / pipeline（普通库 worker）", call. = FALSE)
  }
  pl
}

# Phase1 终点：优先 VIF_final；若流水线已跳过多因素/终筛，则落到 dual_db_covariate_harmonize / screen
.vif_final_block_for_db <- function(db) {
  pipe <- .incidence_worker_pipeline_for_db(config, db)
  blocks <- as.character(pipe$blocks %||% character(0))
  cands <- if (dual_db_is_weighted(config, db)) {
    c("multicollinearity_nhanes_final", "dual_db_covariate_harmonize",
      "multicollinearity_nhanes_screen")
  } else {
    c("multicollinearity_final", "dual_db_covariate_harmonize",
      "multicollinearity_screen")
  }
  hit <- cands[cands %in% blocks]
  if (!length(hit)) {
    stop("无法解析 Phase1 终点 block（流水线缺少 VIF_final / covariate_harmonize / screen）",
         call. = FALSE)
  }
  hit[[1L]]
}

.logistic_screen_end_block <- function(db)
  if (dual_db_is_weighted(config, db)) "logistic_binary_nhanes_weighted" else "logistic_binary_glm"

bc          <- config$incidence_batch %||% list()
light       <- isTRUE(bc$.sensitivity_light)
output_base <- bc$output_base %||% config$project$output_dir
# 须与父进程 index_output_subdir 一致（如 by_index(cindychen)）；禁止写死 by_index
.ix_subdir  <- if (exists("incidence_batch_index_output_subdir", mode = "function")) {
  incidence_batch_index_output_subdir(bc)
} else {
  as.character(bc$index_output_subdir %||% "by_index")[1L]
}
output_ix   <- if (resume_mode) {
  incidence_batch_find_index_output_dir(
    output_base, ix, index_subdir = .ix_subdir, config = config
  )
} else {
  file.path(output_base, .ix_subdir, ix)
}

# 状态写入（任何时机可调用）
filter_stats <- list()  # 用于记录过滤统计

.write_status <- function(status, db_mode_used = db_mode,
                           nhanes_branch = NULL, mimic_branch = NULL,
                           nhanes_or = NULL, mimic_or = NULL,
                           error_message = NULL) {
  elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
  fields  <- list(
    index           = ix,
    status          = status,
    db_mode         = db_mode_used,
    nhanes_branch   = nhanes_branch,
    mimic_branch    = mimic_branch,
    nhanes_or       = nhanes_or,
    mimic_or        = mimic_or,
    n_nhanes_before = filter_stats$nhanes$imputed$n_before %||% NA,
    n_nhanes_after  = filter_stats$nhanes$imputed$n_after  %||% NA,
    n_nhanes_na     = filter_stats$nhanes$imputed$n_na     %||% NA,
    n_nhanes_trim   = filter_stats$nhanes$imputed$n_trim   %||% NA,
    n_mimic_before  = filter_stats$mimic$imputed$n_before  %||% NA,
    n_mimic_after   = filter_stats$mimic$imputed$n_after   %||% NA,
    n_mimic_na      = filter_stats$mimic$imputed$n_na      %||% NA,
    n_mimic_trim    = filter_stats$mimic$imputed$n_trim    %||% NA,
    error_message   = error_message,
    elapsed_sec     = elapsed,
    # 三表路由所需额外字段（disease_label 优先，使飞书里显示统一）
    disease  = (config_ix$feishu %||% list())$disease_label %||%
               config_ix$project$disease %||% config_ix$project$analysis_group %||% "",
    protocol = (config_ix$feishu %||% list())$protocol_label %||% ""
  )
  incidence_batch_write_status(output_ix, fields)
  if (exists("incidence_batch_feishu_push_result", mode = "function")) {
    tryCatch(
      incidence_batch_feishu_push_result(config_ix, fields),
      error = function(e) cli::cli_alert_warning("飞书推送异常: {e$message}")
    )
  }
}

cli::cli_h1("Worker: index={ix}, db={db_mode}, ptrim={p_trim*100}%")

# ── Patch config ──────────────────────────────────────────────────────────────
# 先挂指标级 harmonization_dir，再 patch（否则闸门 D 亚组锁读不到 by_index/.../harmonization）
config$dual_db$harmonization_dir <- file.path(
  bc$index_ck_base %||% "checkpoints/_by_index", ix, "harmonization"
)
config$dual_db$checkpoint_base <- file.path(
  bc$index_ck_base %||% "checkpoints/_by_index", ix
)
config_ix <- incidence_batch_patch_config_for_index(config, ix, root = root)
config_ix$dual_db$harmonization_dir <- config$dual_db$harmonization_dir
config_ix$dual_db$checkpoint_base <- config$dual_db$checkpoint_base
# 把 p_trim 注入 config（兼容字段；发病套路已不挂 trim_index_extreme）
config_ix$incidence_batch$trim_quantile <- p_trim

# ── 确定运行库序列 ───────────────────────────────────────────────────────────
db_seq <- switch(db_mode, nhanes="nhanes", mimic="mimic", c("nhanes","mimic"))

# ── 定向重跑（--from/--to 或 --blocks）：复用 per-index ck，不走 Gate/Phase ─────
if (length(blocks_cli) > 0L ||
    (!is.null(from_cli) && nzchar(as.character(from_cli)[1L])) ||
    (!is.null(to_cli) && nzchar(as.character(to_cli)[1L]))) {
  has_rerun_deps <- length(blocks_cli) > 0L ||
    (is.null(from_cli) || !identical(as.character(from_cli)[1L], "index"))
  if (isTRUE(has_rerun_deps)) {
    cli::cli_h1(
      "[{ix}] 定向重跑: from={from_cli %||% '-'} to={to_cli %||% '-'} blocks={paste(blocks_cli %||% '-', collapse=',')}"
    )
    .rerun_out <- Sys.getenv("MEDICAL_BLOCKS_RERUN_OUT", unset = "")
    if (nzchar(.rerun_out)) {
      # cli 字面量忌 `{.dotted}`（会被当内联函数）→ 先赋非点号局部名
      rerun_out_lab <- .rerun_out
      cli::cli_alert_info("独立输出目录(--out): {.file {rerun_out_lab}}（不覆盖【success】主结果）")
    }
    .resolve_from_token <- function(per_ck, preferred, blocks) {
      .ck_names <- function() {
        fs <- list.files(per_ck, pattern = "\\.rds$", full.names = FALSE)
        unique(sub("^step[0-9]+_", "", sub("\\.rds$", "", fs)))
      }
      nms <- .ck_names()
      if (!is.null(preferred) && nzchar(preferred) && preferred %in% nms)
        return(preferred)
      for (b in rev(as.character(blocks))) {
        if (b %in% nms) {
          if (!is.null(preferred) && nzchar(preferred) && !identical(b, preferred)) {
            cli::cli_alert_warning(
              "[{ix}] {basename(per_ck)} 无 {.field {preferred}} ck，回退续跑点 {.field {b}}"
            )
          }
          return(b)
        }
      }
      preferred
    }
    tryCatch({
      # 本课题可能是 NHANES 槽跑 regular primary ML（pipeline_regular_primary_ml_batch）
      pipe_base <- if (exists("pipeline_regular_primary_ml_batch", inherits = FALSE)) {
        pipeline_regular_primary_ml_batch
      } else if (exists("pipeline_regular_batch", inherits = FALSE)) {
        pipeline_regular_batch
      } else {
        stop("定向重跑缺少 pipeline_regular_batch / pipeline_regular_primary_ml_batch", call. = FALSE)
      }
      blocks_full <- as.character(pipe_base$blocks %||% character(0))
      for (db in db_seq) {
        cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
        if (dual_db_is_weighted(config_ix, db) && exists("pipeline_nhanes_batch", inherits = FALSE)) {
          pipe_db <- pipeline_nhanes_batch
        } else {
          pipe_db <- pipe_base
        }
        blocks_full_db <- as.character(pipe_db$blocks %||% blocks_full)
        per_ck <- file.path(
          bc$index_ck_base %||% "checkpoints/by_index", ix,
          dual_db_slot_path_name(config_ix, db)
        )
        if (!dir.exists(per_ck)) {
          alt <- file.path("checkpoints/_by_index", ix, dual_db_slot_path_name(config_ix, db))
          if (dir.exists(alt)) per_ck <- alt
        }
        from_db <- if (length(blocks_cli) > 0L) {
          from_cli
        } else {
          .resolve_from_token(per_ck, from_cli, blocks_full_db)
        }
        if (is.null(from_db) || !nzchar(as.character(from_db)[1L])) {
          from_db <- .resolve_from_token(per_ck, NULL, blocks_full_db)
        }
        pipe <- incidence_batch_set_pipeline_ck(pipe_db, per_ck)
        run_opts_rerun <- list(
          from = from_db, to = to_cli,
          only = if (length(blocks_cli)) blocks_cli else NULL
        )
        cli::cli_alert_info("[{ix}/{toupper(db)}] 定向续跑 from={from_db %||% '-'}")
        run_pipeline(root, config = cfg_db, pipeline = pipe, run_opts = run_opts_rerun)
      }
      tryCatch(
        incidence_batch_finalize_index_outputs(root, config_ix, ix, db_seq),
        error = function(e) {
          cli::cli_alert_warning("定向重跑后汇总/拼图失败: {e$message}")
        }
      )
      .write_status(status = "success", db_mode_used = db_mode)
      tryCatch(
        incidence_batch_rename_output_folder(
          output_base, ix, "success",
          overwrite = TRUE,
          index_subdir = .ix_subdir,
          config = config_ix
        ),
        error = function(e) cli::cli_alert_warning("定向重跑后重命名失败: {e$message}")
      )
      cli::cli_alert_success("[{ix}] 定向重跑完成")
      quit(save = "no", status = 0)
    }, error = function(e) {
      msg <- conditionMessage(e)
      cli::cli_alert_danger("[{ix}] 定向重跑错误: {msg}")
      .write_status(status = "error", error_message = msg)
      quit(save = "no", status = 1)
    })
  }
}

# ── 检查各库指标可用性 ───────────────────────────────────────────────────────
avail <- list()
if (light) {
  for (db in db_seq) avail[[db]] <- TRUE
} else {
  for (db in db_seq) {
    shared_ck_dir <- incidence_batch_shared_ck_dir(config, db)
    ok <- incidence_batch_index_available(shared_ck_dir, ix)
    avail[[db]] <- ok
    cli::cli_alert_info("{toupper(db)}: {ix} 可用 = {isTRUE(ok)}")
  }
}

actual_db_mode <- db_mode
actual_db_seq  <- db_seq
if (db_mode == "both") {
  nhanes_ok <- isTRUE(avail[["nhanes"]])
  mimic_ok  <- isTRUE(avail[["mimic"]])
  if (nhanes_ok && mimic_ok) {
    actual_db_mode <- "both"
  } else if (nhanes_ok) {
    actual_db_mode <- "nhanes_only"
    actual_db_seq  <- "nhanes"
    cli::cli_alert_info("{ix} 在 MIMIC 中不可用，降级为 NHANES 单库")
  } else if (mimic_ok) {
    actual_db_mode <- "mimic_only"
    actual_db_seq  <- "mimic"
    cli::cli_alert_info("{ix} 在 NHANES 中不可用，降级为 MIMIC 单库")
  } else {
    .write_status("failed", error_message = "两库均无法计算该指标")
    cli::cli_alert_danger("{ix}: 两库均无该指标")
    quit(save = "no", status = 1)
  }
} else {
  for (db in actual_db_seq) {
    if (!isTRUE(avail[[db]])) {
      .write_status("failed", error_message = sprintf("%s 中无法计算 %s", toupper(db), ix))
      quit(save = "no", status = 1)
    }
  }
}

# ── 读取共享层所有已算指标名（用于后续从 ck 删掉其他指标列）──────────────────
all_computed_ix <- character(0)
for (db_ck in db_seq) {
  s_dir <- incidence_batch_shared_ck_dir(config, db_ck)
  s_obj <- tryCatch(readRDS(file.path(s_dir, "index.rds")), error = function(e) NULL)
  if (!is.null(s_obj))
    all_computed_ix <- union(all_computed_ix, s_obj$ctx$results$computed_index_names %||% character(0))
}
# 兜底纳入“指标注册池”，防止原始数据里已存在 UA_CR/UACR 等列泄漏到其他指标表
registry_ix <- tryCatch(
  incidence_batch_resolve_index_vars(config),
  error = function(e) character(0)
)
all_ix_pool <- unique(c(
  all_computed_ix,
  registry_ix,
  get0(".composite_index_vars", inherits = TRUE) %||% character(0),
  get0(".composite_index_vars_dual_safe", inherits = TRUE) %||% character(0)
))
other_ix <- setdiff(all_ix_pool, ix)   # 其他指标列，分析时排除
protect_ix <- unique(c(
  "BMI", "Weight", "Height",
  as.character((bc$protect_index_cols %||% character(0)))
))
other_ix <- setdiff(other_ix, protect_ix)

# ── 复制 shared checkpoint + 过滤当前指标 NA 行 + 删除其他指标列 ─────────────
# 续跑模式：保留已有 per-index 检查点，禁止覆盖 index.rds
# 轻量敏感性：suite 已拷主分析插补 ck 并滤人，禁止再 copy shared
if (isTRUE(bc$.sensitivity_light)) {
  if (isTRUE(bc$.sensitivity_complete_case)) {
    cli::cli_alert_info("[{ix}] 敏感性轻量路径：未插补完整病例，不复制 shared、不插补")
  } else {
    cli::cli_alert_info("[{ix}] 敏感性轻量路径：使用主分析插补后 ck，不复制 shared、不插补")
  }
  scheme <- as.character(bc$.sensitivity_scheme %||% "quartile")[1L]
  for (db in actual_db_seq) {
    per_index_ck <- file.path(
      bc$index_ck_base %||% "checkpoints/_by_index", ix,
      dual_db_slot_path_name(config, db)
    )
    idx_p <- file.path(per_index_ck, "index.rds")
    if (!file.exists(idx_p)) {
      .write_status(
        "failed",
        error_message = sprintf("轻量路径缺少 %s/index.rds（suite 应已拷+过滤）", per_index_ck)
      )
      quit(save = "no", status = 1)
    }
    obj <- tryCatch(readRDS(idx_p), error = function(e) NULL)
    df_f <- incidence_batch_ctx_data(obj$ctx)
    if (!is.null(df_f) && is.data.frame(df_f))
      filter_stats[[db]] <- list(imputed = list(n_after = nrow(df_f)))
  }
} else if (!resume_mode) {
  # 注意：此处只过滤 NA 行（p_trim=0 跳过极值裁剪）
  # 发病套路不再挂 trim_index_extreme，不做百分位极端值裁剪
  for (db in actual_db_seq) {
    shared_dir   <- incidence_batch_shared_ck_dir(config, db)
    per_index_ck <- file.path(
      bc$index_ck_base %||% "checkpoints/_by_index", ix,
      dual_db_slot_path_name(config, db)
    )
    ok <- incidence_batch_copy_shared_ck(shared_dir, per_index_ck, ix, 0, config = config)  # p_trim=0: 只过滤NA
    if (!ok) {
      .write_status("failed", error_message = sprintf("复制 %s checkpoint 失败", toupper(db)))
      quit(save = "no", status = 1)
    }

    # ── 亚组补救重跑：在 per-index ck 上按亚组表达式剔除行（由 config 注入）──────
    sg_expr <- bc$.subgroup_fallback_expr %||% NULL
    if (!is.null(sg_expr) && nzchar(sg_expr)) {
      sg_label <- bc$.subgroup_fallback_label %||% "subgroup"
      cli::cli_h2("[{ix}] 亚组补救过滤 [{toupper(db)}] {sg_label}: {sg_expr}")
      incidence_batch_apply_subgroup_filter(file.path(per_index_ck, "index.rds"), sg_expr, ix)
    }

    # ── 从 per-index checkpoint 删除其他指标列（只保留当前 ix 作为暴露变量）────────
    if (length(other_ix) > 0) {
      ck_path <- file.path(per_index_ck, "index.rds")
      obj <- tryCatch(readRDS(ck_path), error = function(e) NULL)
      if (!is.null(obj) && !is.null(obj$ctx)) {
        for (slot in c("mapped", "imputed", "cleaned", "raw")) {
          df <- obj$ctx$data[[slot]]
          if (!is.null(df) && is.data.frame(df)) {
            drop <- intersect(other_ix, names(df))
            if (length(drop)) obj$ctx$data[[slot]] <- df[, setdiff(names(df), drop), drop = FALSE]
          }
        }
        obj$ctx$results$computed_index_names <- ix  # 仅当前指标
        saveRDS(obj, ck_path)
        cli::cli_alert_info("  [{toupper(db)}] 已从 per-index ck 删除其他指标列: {paste(other_ix, collapse=', ')}")
      }
    }

    # 记录过滤统计
    ck_path <- file.path(per_index_ck, "index.rds")
    if (file.exists(ck_path)) {
      obj   <- tryCatch(readRDS(ck_path), error = function(e) NULL)
      df_f <- incidence_batch_ctx_data(obj$ctx)
      if (!is.null(df_f) && is.data.frame(df_f))
        filter_stats[[db]] <- list(imputed = list(n_after = nrow(df_f)))
    }
  }

  # 补充 n_before（从 shared checkpoint 读取，过滤前）
  for (db in actual_db_seq) {
    shared_dir <- incidence_batch_shared_ck_dir(config, db)
    s_obj <- tryCatch(readRDS(file.path(shared_dir, "index.rds")), error = function(e) NULL)
    df_b <- incidence_batch_ctx_data(s_obj$ctx)
    if (!is.null(df_b) && is.data.frame(df_b)) {
      n_b <- nrow(df_b)
      if (is.null(filter_stats[[db]])) filter_stats[[db]] <- list()
      if (is.null(filter_stats[[db]]$imputed)) filter_stats[[db]]$imputed <- list()
      filter_stats[[db]]$imputed$n_before <- n_b
    }
  }
} else {
  cli::cli_alert_info(
    "[{ix}] 续跑模式 from={from_cli %||% '-'} to={to_cli %||% '-'}；保留已有检查点，输出目录={.file {output_ix}}"
  )
}

# ── 运行单库某阶段 ────────────────────────────────────────────────────────────
.run_db_phase <- function(db, from_token, to_token) {
  cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
  if (resume_mode) {
    cfg_db$project$output_dir <- file.path(output_ix, dual_db_slot_path_name(config_ix, db))
    cfg_db$incidence_batch$output_base <- output_base
  }
  pipe   <- .incidence_worker_pipeline_for_db(config, db)
  if (isTRUE((config_ix$incidence_batch %||% list())$.sensitivity_light)) {
    scheme <- as.character(config_ix$incidence_batch$.sensitivity_scheme %||% "quartile")[1L]
    keep <- incidence_sensitivity_light_blocks(
      "incidence", dual_db_is_weighted(config, db), scheme
    )
    pipe <- incidence_sensitivity_trim_pipeline(pipe, keep)
    pipe$logistic_gate$enable <- FALSE
  }
  per_ck <- file.path(
    bc$index_ck_base %||% "checkpoints/_by_index", ix,
    dual_db_slot_path_name(config_ix, db)
  )
  if (resume_mode && !dir.exists(per_ck)) {
    stop("续跑缺少检查点目录: ", per_ck, call. = FALSE)
  }
  pipe   <- incidence_batch_set_pipeline_ck(pipe, per_ck)
  run_opts <- list(from = from_token, to = to_token)
  if (isTRUE((config_ix$incidence_batch %||% list())$.sensitivity_light)) {
    # 从过滤后 index.rds 注入 ctx，含首块跑起；禁止续跑 leftover imputation.rds
    idx_p <- file.path(per_ck, "index.rds")
    idx_obj <- readRDS(idx_p)
    if (is.null(idx_obj$ctx))
      stop("轻量路径 index.rds 无效（缺 ctx）: ", idx_p, call. = FALSE)
    if (is.null(idx_obj$ctx$results)) idx_obj$ctx$results <- list()
    scheme <- as.character(config_ix$incidence_batch$.sensitivity_scheme %||% "quartile")[1L]
    .lg_nm <- if (dual_db_is_weighted(config, db)) {
      paste0("logistic_", scheme, "_nhanes_weighted")
    } else {
      paste0("logistic_", scheme, "_glm")
    }
    .lg_cfg <- cfg_db[[.lg_nm]] %||% list()
    .harm <- (cfg_db$dual_db %||% list())$harmonization %||% list()
    m1 <- as.character(.lg_cfg$model1_factors %||% .harm$harmonized_model1_nhanes %||% character(0))
    m2 <- as.character(.lg_cfg$model2_factors %||% .harm$harmonized_model2_nhanes %||% character(0))
    if (length(m1)) idx_obj$ctx$results$Model1Factors <- m1
    if (length(m2)) idx_obj$ctx$results$Model2Factors <- m2
    run_opts$initial_ctx <- idx_obj$ctx
    run_opts$from <- NULL
    run_opts$to <- to_token
  }
  run_pipeline(root, config = cfg_db, pipeline = pipe, run_opts = run_opts)
}

# ── 分析主路径：续跑单段 / 轻量敏感性 / 完整三阶段 ────────────────────────────
result_ctx <- list()

tryCatch({
  if (resume_mode) {
    cli::cli_h2("[{ix}] 续跑 --from/--to")
    for (db in actual_db_seq) {
      ft <- incidence_batch_resolve_from_to(config, db, from_cli, to_cli)
      cli::cli_alert_info(
        "[{dual_db_slot_path_name(config, db)}] pipeline from={ft$from %||% '(start)'} to={ft$to %||% '(end)'}"
      )
      result_ctx[[db]] <- .run_db_phase(db, ft$from, ft$to)
    }
  } else if (light) {
    cli::cli_h2("[{ix}] 敏感性轻量路径 — Table 1 + 选中档 Table 2")
    for (db in actual_db_seq) {
      pipe <- .incidence_worker_pipeline_for_db(config, db)
      scheme <- as.character(bc$.sensitivity_scheme %||% "quartile")[1L]
      keep <- incidence_sensitivity_light_blocks(
        "incidence", dual_db_is_weighted(config, db), scheme
      )
      pipe <- incidence_sensitivity_trim_pipeline(pipe, keep)
      if (!length(pipe$blocks)) {
        stop("轻量路径截断后 pipeline$blocks 为空: ", db, call. = FALSE)
      }
      result_ctx[[db]] <- .run_db_phase(db, pipe$blocks[1], tail(pipe$blocks, 1))
    }
  } else {
    cli::cli_h2("[{ix}] Phase 1 — 各库跑到 VIF_final")
    for (db in actual_db_seq) {
      result_ctx[[db]] <- .run_db_phase(db, "index", .vif_final_block_for_db(db))
    }

    if (identical(actual_db_mode, "both")) {
      if (exists("survival_batch_dual_lock_analysis_columns", mode = "function")) {
        tryCatch(
          survival_batch_dual_lock_analysis_columns(
            root, config_ix, ix, actual_db_seq, pipeline_regular_batch
          ),
          error = function(e) {
            cli::cli_alert_warning("双库分析列对齐失败: {e$message}")
          }
        )
      }
      cli::cli_h2("[{ix}] Gate B 同步（协变量对齐）")
      gate_b <- dual_db_force_gate_b_sync(root, config_ix)
      if (is.null(gate_b))
        cli::cli_alert_warning("{ix}: Gate B 同步失败，Model1/2 可能未对齐")
    }

    cli::cli_h2("[{ix}] Phase 2 — logistic 筛选")
    for (db in actual_db_seq) {
      result_ctx[[db]] <- .run_db_phase(
        db, .vif_final_block_for_db(db), .logistic_screen_end_block(db)
      )
    }

    if (identical(actual_db_mode, "both")) {
      cli::cli_h2("[{ix}] Logistic 分支对齐")
      dual_db_harmonize_unified_logistic_branch(root, config_ix)
    }

    cli::cli_h2("[{ix}] Phase 3 — RCS / 亚组 / 中介")
    for (db in actual_db_seq) {
      pipe   <- .incidence_worker_pipeline_for_db(config, db)
      per_ck <- file.path(
        bc$index_ck_base %||% "checkpoints/_by_index", ix,
        dual_db_slot_path_name(config_ix, db)
      )
      from_t <- incidence_batch_last_logistic_ck_token(per_ck, pipe)
      if (is.null(from_t)) from_t <- .logistic_screen_end_block(db)
      result_ctx[[db]] <- .run_db_phase(db, from_t, NULL)
    }
  }

  incidence_batch_finalize_index_outputs(root, config_ix, ix, actual_db_seq)

  # ── 提取关键结果 ──
  .extract_branch <- function(ctx) {
    if (is.null(ctx)) return(NA_character_)
    ctx$results$nhanes_logistic_selected_scheme %||%
      ctx$results$logistic_branch %||% NA_character_
  }
  .extract_or <- function(ctx) {
    if (is.null(ctx)) return(NA_real_)
    tbl <- ctx$results$logistic_main_table %||% ctx$results$logistic_crude_table
    if (is.null(tbl) || !is.data.frame(tbl)) return(NA_real_)
    or_col <- intersect(c("OR","or","Crude_OR"), names(tbl))
    if (!length(or_col)) return(NA_real_)
    vals <- suppressWarnings(as.numeric(tbl[[or_col[1]]]))
    tail(vals[is.finite(vals)], 1)
  }

  # 先写完目录内全部产物，再落 status json —— 避免父进程过早 mv 目录
  # （SMB 上 Permission denied 的主因：status 已出现但 worker 仍在写 brief）
  tryCatch(
    incidence_write_pipeline_brief(output_ix, config = config_ix, ix = ix),
    error = function(e) cli::cli_alert_warning("写 Pipeline_steps_brief.txt 失败: {e$message}")
  )
  .write_status(
    status        = "success",
    db_mode_used  = actual_db_mode,
    nhanes_branch = .extract_branch(result_ctx[["nhanes"]]),
    mimic_branch  = .extract_branch(result_ctx[["mimic"]]),
    nhanes_or     = .extract_or(result_ctx[["nhanes"]]),
    mimic_or      = .extract_or(result_ctx[["mimic"]])
  )
  # status 落盘后补刷 image_information（首遍 finalize 在 status 之前，N 读不到 →
  # 「样本量/Grouping 未记录」）。仅重写 md，不重新栅格化。
  tryCatch({
    figs_ix <- file.path(output_ix, "Figures")
    if (dir.exists(figs_ix) &&
        exists("incidence_batch_pub_figure_meta", mode = "function") &&
        exists("pub_figure_refresh_image_information", mode = "function")) {
      meta_ix <- incidence_batch_pub_figure_meta(output_ix, config_ix, ix, actual_db_seq)
      pub_figure_refresh_image_information(figs_ix, meta = meta_ix, config = config_ix)
      cli::cli_alert_info("image_information 已按 _batch_status.json 补刷（N/Grouping/结局展示名）")
    }
  }, error = function(e) cli::cli_alert_warning("image_information 补刷跳过: {e$message}"))
  cli::cli_alert_success("[{ix}] 完成！db_mode={actual_db_mode}")
  quit(save = "no", status = 0)

}, error = function(e) {
  msg <- conditionMessage(e)
  cli::cli_alert_danger("[{ix}] 错误: {msg}")
  tryCatch(
    incidence_batch_finalize_index_outputs(root, config_ix, ix, actual_db_seq),
    error = function(e2) {
      cli::cli_alert_warning("[{ix}] 输出镜像汇总失败: {e2$message}")
    }
  )
  .write_status("error", error_message = msg)
  quit(save = "no", status = 1)
})
