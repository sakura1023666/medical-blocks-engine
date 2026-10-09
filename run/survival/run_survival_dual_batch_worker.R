#!/usr/bin/env Rscript
# =============================================================================
#  预后双库批量 — 单指标 Worker 子进程
#
#  用法（调试）:
#    Rscript run/survival/run_survival_dual_batch_worker.R --index NLR [--db both] [--ptrim 0.01]
#
#  定向重跑（复用已有 checkpoint，不重跑全链）:
#    Rscript run/survival/run_survival_dual_batch_worker.R --index APRI \
#            --config <study>/config_survival.R \
#            --from km_strata --to segmented_cox_binary
#    # --from 后面的块（不含）到 --to（含）重跑；--blocks 逗号列表则只跑这些块
#    # （依赖块 checkpoint 已存在；pub 表号从 checkpoint 恢复，编号不漂移）
#
#  流程:
#    1. patch config → 复制 shared ck → 过滤 NA
#    2. Phase 1: 各库跑到 VIF_final
#    3. Gate B 协变量对齐（both）
#    4. Phase 2: cox_quartile → cox_binary（Cox 闸门链）
#    5. Gate C Cox 分位对齐；Gate D 亚组锁定
#    6. Phase 3: RCS / KM / 分段 Cox / 亚组 / ROC / 箱线 / 中介
#    7. Gate E 双库中介路径图中介统一（mediation_prognosis 存在时自动）
#    8. 写 _batch_status.json + 飞书推送
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
  opts <- list(index = NULL, db_mode = "both", root = NULL, p_trim = NULL, config = NULL,
               from = NULL, to = NULL, blocks = NULL)
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
      opts$blocks <- trimws(strsplit(args[[i+1L]], ",", fixed = TRUE)[[1L]])
      opts$blocks <- opts$blocks[nzchar(opts$blocks)]
      i <- i+2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i+1L
    } else {
      i <- i+1L
    }
  }
  if (is.null(opts$index) || !nzchar(opts$index))
    stop("--index 参数必填", call. = FALSE)
  if (!opts$db_mode %in% c("both", "nhanes", "mimic"))
    stop("--db 仅支持 both|nhanes|mimic", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
    basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

# 与发病 worker 对齐：引擎代码从 MEDICAL_BLOCKS_ROOT 加载；课题根仅作 cwd / 输出
engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine_root)) {
  engine_root <- normalizePath(script_path, winslash = "/")
} else {
  engine_root <- normalizePath(engine_root, winslash = "/", mustWork = TRUE)
}
if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", engine_root)) {
  .drv <- tolower(substr(engine_root, 1L, 1L))
  engine_root <- paste0("/mnt/", .drv, substring(engine_root, 3L))
}

study_root <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
if (!nzchar(study_root) && !is.null(wk_opts$root) && nzchar(wk_opts$root)) {
  study_root <- wk_opts$root
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
  "[worker-env] INCIDENCE_BATCH_ROOT=%s MEDICAL_BLOCKS_ROOT=%s study_root=%s",
  Sys.getenv("INCIDENCE_BATCH_ROOT"),
  Sys.getenv("MEDICAL_BLOCKS_ROOT"),
  study_root
))

ix      <- wk_opts$index
db_mode <- wk_opts$db_mode
t_start <- proc.time()

source(file.path(engine_root, "R/feishu_env.R"))
feishu_load_dotenv(engine_root)

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(engine_root, "configs/templates/config_survival_dual_batch.template.R")
}

source(file.path(engine_root, "R/utils.R"))
source(file.path(engine_root, "R/model3_required.R"))
source(file.path(engine_root, "R/dual_db_harmonize.R"))
source(file.path(engine_root, "R/cox_gate.R"))
source(file.path(engine_root, "R/pipeline_runner.R"))
source(file.path(engine_root, "configs/indices/composite_index_vars.R"))
source(file.path(engine_root, "R/survival_dual_batch_runner.R"))
source(file.path(engine_root, "R/incidence_sensitivity_suite.R"))
source(file.path(engine_root, "R/feishu_bitable.R"))
source(file.path(engine_root, "R/pub_figure_export.R"))
source(file.path(engine_root, "R/subgroup_forest_plot.R"))
.med_common <- file.path(engine_root, "Blocks/20_mediation/00mediation_common.R")
if (file.exists(.med_common)) {
  tryCatch(
    source(.med_common, local = FALSE),
    error = function(e) message("[worker] mediation_common preload failed: ", conditionMessage(e))
  )
}
source(config_path)
config <- .survival_batch_bind_config(config)

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

.vif_final_block <- function() "multicollinearity_final"
.cox_screen_end  <- function() "cox_binary"

bc          <- utils::modifyList(
  config$survival_batch %||% list(),
  config$incidence_batch %||% list()
)
sb          <- config$survival_batch %||% config$incidence_batch %||% list()
light       <- isTRUE(sb$.sensitivity_light)
output_base <- bc$output_base %||% config$project$output_dir
output_ix   <- if (exists("incidence_batch_find_index_output_dir", mode = "function")) {
  incidence_batch_find_index_output_dir(output_base, ix, "by_index")
} else {
  file.path(output_base, "by_index", ix)
}
filter_stats <- list()

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
    disease  = (config_ix$feishu %||% list())$disease_label %||%
               config_ix$project$disease %||% "",
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

# p_trim：CLI > config$survival_batch$trim_quantile > 0（不硬开极端值）
p_trim <- wk_opts$p_trim
if (is.null(p_trim) || (length(p_trim) == 1L && is.na(p_trim)))
  p_trim <- bc$trim_quantile %||% 0
p_trim <- as.numeric(p_trim)
if (!is.finite(p_trim) || p_trim < 0) p_trim <- 0

cli::cli_h1("Survival Worker: index={ix}, db={db_mode}, ptrim={p_trim*100}%")

config_ix <- survival_batch_patch_config_for_index(config, ix)
config_ix$dual_db$harmonization_dir <- file.path(
  bc$index_ck_base %||% "checkpoints/_by_index", ix, "harmonization"
)
config_ix$dual_db$checkpoint_base <- file.path(
  bc$index_ck_base %||% "checkpoints/_by_index", ix
)
config_ix$survival_batch$trim_quantile <- p_trim

db_seq <- switch(db_mode, nhanes = "nhanes", mimic = "mimic", c("nhanes", "mimic"))

# ── 定向重跑模式（--from/--to 或 --blocks）：复用 per-index checkpoint，
#    只重跑指定块；不走 Gate/Phase 编排（依赖块 ck 必须已存在）。
if (!is.null(wk_opts$from) || !is.null(wk_opts$to) || length(wk_opts$blocks %||% character(0))) {
  has_rerun_deps <- !is.null(wk_opts$blocks) ||
    (is.null(wk_opts$from) || !identical(wk_opts$from, "index"))
  if (has_rerun_deps) {
    cli::cli_h1("[{ix}] 定向重跑: from={wk_opts$from %||% '-'} to={wk_opts$to %||% '-'} blocks={paste(wk_opts$blocks %||% '-', collapse=',')}")
    .rerun_out <- Sys.getenv("MEDICAL_BLOCKS_RERUN_OUT", unset = "")
    if (nzchar(.rerun_out)) {
      rerun_out_lab <- .rerun_out
      cli::cli_alert_info("独立输出目录(--out): {.file {rerun_out_lab}}（不覆盖【success】主结果）")
    }
    # 每库独立选续跑点：CLI --from 若该库无 ck，则回退到该库已有的最晚 pipeline 块
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
      blocks_full <- as.character(pipeline_regular_batch$blocks)
      for (db in db_seq) {
        cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
        per_ck <- file.path(
          bc$index_ck_base %||% "checkpoints/by_index", ix,
          dual_db_slot_path_name(config_ix, db)
        )
        # 兼容旧默认 checkpoints/_by_index
        if (!dir.exists(per_ck)) {
          alt <- file.path("checkpoints/_by_index", ix, dual_db_slot_path_name(config_ix, db))
          if (dir.exists(alt)) per_ck <- alt
        }
        from_db <- if (!is.null(wk_opts$blocks) && length(wk_opts$blocks)) {
          wk_opts$from
        } else {
          .resolve_from_token(per_ck, wk_opts$from, blocks_full)
        }
        pipe <- incidence_batch_set_pipeline_ck(pipeline_regular_batch, per_ck)
        run_opts_rerun <- list(
          from = from_db, to = wk_opts$to,
          only = wk_opts$blocks
        )
        cli::cli_alert_info("[{ix}/{toupper(db)}] 定向续跑 from={from_db %||% '-'}")
        run_pipeline(root, config = cfg_db, pipeline = pipe, run_opts = run_opts_rerun)
      }
      # 定向重跑后刷新汇总：分库镜像 + 双库拼图（含 Figure 4 森林图等）
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
          index_subdir = "by_index",
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
      # 定向 salvage：保留裸名目录，便于再次 --from 续跑（勿改成【failed】）
      quit(save = "no", status = 1)
    })
  }
}

avail <- list()
if (light) {
  for (db in db_seq) avail[[db]] <- TRUE
} else {
  for (db in db_seq) {
    shared_ck_dir <- incidence_batch_shared_ck_dir(config, db)
    avail[[db]] <- incidence_batch_index_available(shared_ck_dir, ix)
    cli::cli_alert_info("{toupper(db)}: {ix} 可用 = {isTRUE(avail[[db]])}")
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
    cli::cli_alert_info("{ix} 在 MIMIC 中不可用，降级为 eICU 单库")
  } else if (mimic_ok) {
    actual_db_mode <- "mimic_only"
    actual_db_seq  <- "mimic"
    cli::cli_alert_info("{ix} 在 eICU 中不可用，降级为 MIMIC 单库")
  } else {
    .write_status("failed", error_message = "两库均无法计算该指标")
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

all_computed_ix <- character(0)
for (db_ck in db_seq) {
  s_dir <- incidence_batch_shared_ck_dir(config, db_ck)
  s_obj <- tryCatch(readRDS(file.path(s_dir, "index.rds")), error = function(e) NULL)
  if (!is.null(s_obj))
    all_computed_ix <- union(all_computed_ix, s_obj$ctx$results$computed_index_names %||% character(0))
}
other_ix <- setdiff(all_computed_ix, ix)
# BMI/体重/身高作临床协变量保留，不因「其他复合指标」被剔除
protect_ix <- unique(c(
  "BMI", "Weight", "Height",
  as.character((bc$protect_index_cols %||% character(0)))
))
other_ix <- setdiff(other_ix, protect_ix)

if (isTRUE(sb$.sensitivity_light)) {
  if (isTRUE(sb$.sensitivity_complete_case)) {
    cli::cli_alert_info("[{ix}] 敏感性轻量路径：未插补完整病例，不复制 shared、不插补")
  } else {
    cli::cli_alert_info("[{ix}] 敏感性轻量路径：使用主分析插补后 ck，不复制 shared、不插补")
  }
  scheme <- as.character(sb$.sensitivity_scheme %||% "quartile")[1L]
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
    if (!is.null(df_f) && is.data.frame(df_f)) {
      filter_stats[[db]] <- list(imputed = list(n_after = nrow(df_f)))
    }
  }
} else {
for (db in actual_db_seq) {
  shared_dir   <- incidence_batch_shared_ck_dir(config, db)
  per_index_ck <- file.path(
    bc$index_ck_base %||% "checkpoints/_by_index", ix,
    dual_db_slot_path_name(config, db)
  )
  # p_trim 来自 CLI（默认 0.01）；若 batch 显式设 0 则不裁极端值（本项目沿用 runner 传入值，不强开）
  ok <- incidence_batch_copy_shared_ck(shared_dir, per_index_ck, ix, p_trim)
  if (!isTRUE(ok)) {
    .write_status("failed", error_message = sprintf("复制 %s checkpoint 失败", toupper(db)))
    quit(save = "no", status = 1)
  }
  fs_attr <- attr(ok, "filter_stats")
  if (is.list(fs_attr) && length(fs_attr)) {
    # preferential mapped → imputed
    pick <- fs_attr$mapped %||% fs_attr$imputed %||% fs_attr$cleaned
    filter_stats[[db]] <- list(imputed = pick, mapped = fs_attr$mapped, cleaned = fs_attr$cleaned)
  }

  # 敏感性 / 亚组补救：应用过滤表达式（与发病 worker 对齐）
  sg_expr <- bc$.subgroup_fallback_expr %||% NULL
  if (!is.null(sg_expr) && nzchar(sg_expr)) {
    sg_label <- bc$.subgroup_fallback_label %||% "subgroup"
    cli::cli_h2("[{ix}] 敏感性/亚组过滤 [{toupper(db)}] {sg_label}: {sg_expr}")
    if (exists("incidence_batch_apply_subgroup_filter", mode = "function")) {
      incidence_batch_apply_subgroup_filter(file.path(per_index_ck, "index.rds"), sg_expr, ix)
    } else {
      cli::cli_alert_warning("incidence_batch_apply_subgroup_filter 不可用，跳过行过滤")
    }
  }

  if (length(other_ix) > 0) {
    ck_path <- file.path(per_index_ck, "index.rds")
    obj <- tryCatch(readRDS(ck_path), error = function(e) NULL)
    if (!is.null(obj) && !is.null(obj$ctx)) {
      for (slot in c("mapped", "imputed", "cleaned", "raw")) {
        df <- obj$ctx$data[[slot]]
        if (!is.null(df) && is.data.frame(df)) {
          drop <- intersect(other_ix, names(df))
          if (length(drop)) obj$ctx$data[[slot]] <- df[, setdiff(names(df), drop), drop = FALSE]
          if (exists("dual_db_derive_bmi", mode = "function")) {
            obj$ctx$data[[slot]] <- dual_db_derive_bmi(
              obj$ctx$data[[slot]], list(enable = TRUE)
            )
          }
        }
      }
      obj$ctx$results$computed_index_names <- ix
      saveRDS(obj, ck_path)
    }
  }

  ck_path <- file.path(per_index_ck, "index.rds")
  if (file.exists(ck_path)) {
    obj <- tryCatch(readRDS(ck_path), error = function(e) NULL)
    df_f <- incidence_batch_ctx_data(obj$ctx)
    if (!is.null(df_f) && is.data.frame(df_f)) {
      if (is.null(filter_stats[[db]])) filter_stats[[db]] <- list()
      if (is.null(filter_stats[[db]]$imputed)) filter_stats[[db]]$imputed <- list()
      filter_stats[[db]]$imputed$n_after <- nrow(df_f)
    }
  }
}

for (db in actual_db_seq) {
  shared_dir <- incidence_batch_shared_ck_dir(config, db)
  s_obj <- tryCatch(readRDS(file.path(shared_dir, "index.rds")), error = function(e) NULL)
  df_b <- incidence_batch_ctx_data(s_obj$ctx)
  if (!is.null(df_b) && is.data.frame(df_b)) {
    n_b <- nrow(df_b)
    if (is.null(filter_stats[[db]])) filter_stats[[db]] <- list()
    if (is.null(filter_stats[[db]]$imputed)) filter_stats[[db]]$imputed <- list()
    if (is.null(filter_stats[[db]]$imputed$n_before) ||
        !is.finite(filter_stats[[db]]$imputed$n_before)) {
      filter_stats[[db]]$imputed$n_before <- n_b
    }
    # recompute n_na if only before/after known
    na0 <- filter_stats[[db]]$imputed$n_na
    tr0 <- filter_stats[[db]]$imputed$n_trim %||% 0L
    aft <- filter_stats[[db]]$imputed$n_after
    if ((is.null(na0) || !is.finite(na0)) && is.finite(n_b) && is.finite(aft)) {
      # n_na + n_trim = before - after
      lost <- as.integer(n_b - aft)
      tr0 <- as.integer(tr0 %||% 0L)
      filter_stats[[db]]$imputed$n_na <- max(0L, lost - tr0)
    }
  }
}
}

.run_db_phase <- function(db, from_token, to_token) {
  cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
  pipe   <- pipeline_regular_batch
  if (isTRUE(sb$.sensitivity_light)) {
    scheme <- as.character(sb$.sensitivity_scheme %||% "quartile")[1L]
    keep <- incidence_sensitivity_light_blocks("prognosis", FALSE, scheme)
    pipe <- incidence_sensitivity_trim_pipeline(pipe, keep)
    incidence_sensitivity_assert_prognosis_light_blocks(pipe$blocks)
    pipe$cox_gate$enable <- FALSE
  }
  per_ck <- file.path(
    bc$index_ck_base %||% "checkpoints/_by_index", ix,
    dual_db_slot_path_name(config_ix, db)
  )
  pipe <- incidence_batch_set_pipeline_ck(pipe, per_ck)
  run_opts <- list(from = from_token, to = to_token)
  if (isTRUE(sb$.sensitivity_light)) {
    idx_p <- file.path(per_ck, "index.rds")
    idx_obj <- readRDS(idx_p)
    if (is.null(idx_obj$ctx))
      stop("轻量路径 index.rds 无效（缺 ctx）: ", idx_p, call. = FALSE)
    if (is.null(idx_obj$ctx$results)) idx_obj$ctx$results <- list()
    .cx_nm <- paste0("cox_", scheme)
    .cx_cfg <- cfg_db[[.cx_nm]] %||% list()
    .harm <- (cfg_db$dual_db %||% list())$harmonization %||% list()
    m1 <- as.character(.cx_cfg$model1_factors %||% .harm$harmonized_model1_nhanes %||% character(0))
    m2 <- as.character(.cx_cfg$model2_factors %||% .harm$harmonized_model2_nhanes %||% character(0))
    if (length(m1)) idx_obj$ctx$results$Model1Factors <- m1
    if (length(m2)) idx_obj$ctx$results$Model2Factors <- m2
    idx_obj$ctx$results$dual_db_covariate_harmonized <- TRUE
    run_opts$initial_ctx <- idx_obj$ctx
    run_opts$from <- NULL
    run_opts$to <- to_token
  }
  run_pipeline(root, config = cfg_db, pipeline = pipe, run_opts = run_opts)
}

result_ctx <- list()

tryCatch({
  if (light) {
    cli::cli_h2("[{ix}] 敏感性轻量路径 — landmark + Table 1 + 选中档 Cox Table 2")
    for (db in actual_db_seq) {
      pipe <- pipeline_regular_batch
      scheme <- as.character(sb$.sensitivity_scheme %||% "quartile")[1L]
      keep <- incidence_sensitivity_light_blocks("prognosis", FALSE, scheme)
      pipe <- incidence_sensitivity_trim_pipeline(pipe, keep)
      if (!length(pipe$blocks)) {
        stop("轻量路径截断后 pipeline$blocks 为空: ", db, call. = FALSE)
      }
      result_ctx[[db]] <- .run_db_phase(db, pipe$blocks[1], tail(pipe$blocks, 1))
      # 出表前硬检：futime 不得超过 landmark（防漏跑行政截尾）
      .df_lm <- tryCatch(
        incidence_batch_ctx_data(result_ctx[[db]]),
        error = function(e) NULL
      )
      if (is.null(.df_lm) && is.list(result_ctx[[db]])) {
        .df_lm <- result_ctx[[db]]$data$imputed %||%
          result_ctx[[db]]$data$mapped %||%
          result_ctx[[db]]$data$cleaned
      }
      if (exists("incidence_sensitivity_assert_landmark_futime", mode = "function")) {
        incidence_sensitivity_assert_landmark_futime(.df_lm, config_ix)
      }
    }
    if (identical(actual_db_mode, "both") &&
        exists("survival_batch_realign_cox_to_unified", mode = "function")) {
      unified_cox <- NULL
      if (exists("dual_db_harmonize_unified_cox_branch", mode = "function")) {
        unified_cox <- tryCatch(
          dual_db_harmonize_unified_cox_branch(root, config_ix),
          error = function(e) {
            cli::cli_alert_warning("[{ix}] 轻量 Cox 双库对齐跳过: {e$message}")
            NULL
          }
        )
      }
      if (!is.null(unified_cox)) {
        for (db in actual_db_seq) {
          survival_batch_realign_cox_to_unified(
            root, config_ix, ix, db, unified_cox, pipeline_regular_batch
          )
        }
      }
    }
  } else {
  cli::cli_h2("[{ix}] Phase 1 — 各库跑到 VIF_final")
  for (db in actual_db_seq) {
    result_ctx[[db]] <- .run_db_phase(db, "index", .vif_final_block())
  }

  if (identical(actual_db_mode, "both")) {
    # 插补后列集合取交集并重跑 baseline→VIF，保证后续全部表/图列名一致
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
    if (is.null(gate_b)) {
      stop("GATE_B_SYNC_FAIL: 双库协变量对齐失败，已停止。", call. = FALSE)
    }
  }

  cli::cli_h2("[{ix}] Phase 2 — Cox 闸门链（四分位→三分位→二分）")
  for (db in actual_db_seq) {
    result_ctx[[db]] <- .run_db_phase(
      db, .vif_final_block(), .cox_screen_end()
    )
  }

  unified_cox <- NULL
  if (identical(actual_db_mode, "both")) {
    cli::cli_h2("[{ix}] Gate C — Cox 分位对齐（四降三降二统一）")
    unified_cox <- dual_db_harmonize_unified_cox_branch(root, config_ix)
    if (!is.null(unified_cox)) {
      for (db in actual_db_seq) {
        survival_batch_realign_cox_to_unified(
          root, config_ix, ix, db, unified_cox, pipeline_regular_batch
        )
        survival_batch_seed_cox_unified_ctx(root, config_ix, ix, db, unified_cox)
      }
    }
    # Gate C+：两库 Table 2 协变量取交集后再锁同一集重跑
    if (!is.null(unified_cox) &&
        exists("survival_batch_align_cox_covariates_dual", mode = "function")) {
      survival_batch_align_cox_covariates_dual(
        root, config_ix, ix, actual_db_seq, unified_cox, pipeline_regular_batch
      )
    }
  }

  if (identical(actual_db_mode, "both") &&
      exists("dual_db_force_gate_d_subgroup_sync", mode = "function")) {
    cli::cli_h2("[{ix}] Gate D — 亚组变量对齐（两库交集锁定）")
    locked_sg <- dual_db_force_gate_d_subgroup_sync(root, config_ix)
    if (length(locked_sg)) {
      config_ix$subgroup$locked_subgroup_vars <- locked_sg
      if (!is.null(config_ix$subgroup_prognosis)) {
        config_ix$subgroup_prognosis$locked_subgroup_vars <- locked_sg
      }
    }
  }

  cli::cli_h2("[{ix}] Phase 3 — RCS / KM / 分段 Cox / 亚组")
  for (db in actual_db_seq) {
    per_ck <- file.path(
      bc$index_ck_base %||% "checkpoints/_by_index", ix,
      dual_db_slot_path_name(config_ix, db)
    )
    if (!is.null(unified_cox)) {
      survival_batch_seed_cox_unified_ctx(root, config_ix, ix, db, unified_cox)
      from_t <- survival_batch_cox_block_for_scheme(unified_cox$scheme)
      # 统一方案对应 ck 若不存在，回退到实际落盘的最后一个 cox_*（避免 Gate C+ 删点后空窗）
      last_ck <- survival_batch_last_cox_ck_token(per_ck, pipeline_regular_batch)
      if (!is.null(from_t)) {
        has_from <- file.exists(file.path(per_ck, paste0(from_t, ".rds"))) ||
          length(Sys.glob(file.path(per_ck, paste0("*_", from_t, ".rds")))) > 0L
        if (!isTRUE(has_from)) {
          if (is.null(last_ck)) {
            stop(
              "Phase 3 缺少 Cox 检查点: 需要 ", from_t,
              ".rds（", per_ck, "）",
              call. = FALSE
            )
          }
          cli::cli_alert_warning(
            "[{ix}] {dual_db_slot_path_name(config_ix, db)} 无 {from_t}，Phase 3 改从 {last_ck} 续跑"
          )
          from_t <- last_ck
        }
      } else {
        from_t <- last_ck %||% .cox_screen_end()
      }
    } else {
      from_t <- survival_batch_last_cox_ck_token(per_ck, pipeline_regular_batch)
      if (is.null(from_t)) from_t <- .cox_screen_end()
    }
    result_ctx[[db]] <- .run_db_phase(db, from_t, NULL)
  }

  # Gate E：内置于 survival dual-batch（见 survival_batch_apply_gate_e_mediation）
  if (identical(actual_db_mode, "both") &&
      exists("survival_batch_apply_gate_e_mediation", mode = "function")) {
    locked_med <- survival_batch_apply_gate_e_mediation(
      root, config_ix, ix, actual_db_seq, pipeline_regular_batch,
      result_ctx = result_ctx
    )
    if (!is.null(locked_med) && !is.null(attr(locked_med, "result_ctx"))) {
      result_ctx <- attr(locked_med, "result_ctx")
    }
  }
  }

  incidence_batch_finalize_index_outputs(root, config_ix, ix, actual_db_seq)

  # 覆盖 Figure1 占位：纳排 + 指标缺失；极端值仅 n_trim>0 时出现（含 trim_index_extreme）
  # 轻量敏感性不写流程图
  if (!isTRUE(light)) {
    tryCatch({
      project_root <- normalizePath(
        bc$output_base %||% dirname(config_path),
        winslash = "/", mustWork = FALSE
      )
      font_family <- (config_ix$plot %||% list())$font_family %||% "Times New Roman"
      if (exists("survival_batch_enrich_filter_stats_with_trim", mode = "function")) {
        filter_stats <- survival_batch_enrich_filter_stats_with_trim(
          filter_stats, project_root, ix, actual_db_seq,
          config = config_ix, index_root = output_ix
        )
      }
      if (exists("survival_batch_write_index_flowcharts", mode = "function")) {
        survival_batch_write_index_flowcharts(
          project_root = project_root,
          index_root   = output_ix,
          ix           = ix,
          filter_stats = filter_stats,
          db_seq       = actual_db_seq,
          font_family  = font_family,
          config       = config_ix
        )
      }
    }, error = function(e) {
      cli::cli_alert_warning("[{ix}] Figure 1 流程图写入失败: {e$message}")
    })
  }

  .extract_branch <- function(ctx) {
    if (is.null(ctx)) return(NA_character_)
    as.character(ctx$results$cox_branch %||% NA_character_)
  }
  .extract_hr <- function(ctx) {
    if (is.null(ctx)) return(NA_real_)
    hr <- ctx$results$cox_highest_group_model2_hr %||% NULL
    if (!is.null(hr) && is.finite(suppressWarnings(as.numeric(hr))))
      return(as.numeric(hr))
    tbl <- ctx$results$cox_hr
    if (is.null(tbl) || !is.data.frame(tbl)) return(NA_real_)
    hr_col <- intersect(c("HR", "hr", "Adj_HR"), names(tbl))
    if (!length(hr_col)) return(NA_real_)
    vals <- suppressWarnings(as.numeric(tbl[[hr_col[1L]]]))
    tail(vals[is.finite(vals)], 1)
  }

  .write_status(
    status        = "success",
    db_mode_used  = actual_db_mode,
    nhanes_branch = .extract_branch(result_ctx[["nhanes"]]),
    mimic_branch  = .extract_branch(result_ctx[["mimic"]]),
    nhanes_or     = .extract_hr(result_ctx[["nhanes"]]),
    mimic_or      = .extract_hr(result_ctx[["mimic"]])
  )
  cli::cli_alert_success("[{ix}] 完成！db_mode={actual_db_mode}")
  quit(save = "no", status = 0)

}, error = function(e) {
  msg <- conditionMessage(e)
  cli::cli_alert_danger("[{ix}] 错误: {msg}")
  tryCatch(
    incidence_batch_finalize_index_outputs(root, config_ix, ix, actual_db_seq),
    error = function(e2) NULL
  )
  .write_status("error", error_message = msg)
  quit(save = "no", status = 1)
})
