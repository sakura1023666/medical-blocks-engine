#!/usr/bin/env Rscript
# =============================================================================
#  ML 双库批量 — 单指标 Worker
#
#  Phase 1: 主库（更大 N）→ UV/VIF → ml_feature_selection_bundle（导出主库特征）
#  Phase 2: 外验库 → imputation/baseline → ml_inherit（不跑 UV/VIF/FS）→ 同构 ML 下游
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
    index = NULL, db_mode = "both", root = NULL, p_trim = 0.01, config = NULL,
    from = NULL, to = NULL, blocks = NULL
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--index" && i < length(args)) {
      opts$index <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--db" && i < length(args)) {
      opts$db_mode <- tolower(trimws(args[[i + 1L]])); i <- i + 2L
    } else if (a == "--ptrim" && i < length(args)) {
      opts$p_trim <- as.numeric(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--from" && i < length(args)) {
      opts$from <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--to" && i < length(args)) {
      opts$to <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--blocks" && i < length(args)) {
      opts$blocks <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      opts$blocks <- opts$blocks[nzchar(opts$blocks)]
      i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$index) || !nzchar(opts$index)) stop("--index 必填", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) %in% c("environment", "incidence", "survival", "ml", "feishu", "hf") &&
    basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

## 引擎根 ≠ 课题根：末参 / INCIDENCE_BATCH_ROOT 是产出目录，源码在 MEDICAL_BLOCKS_ROOT
engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine_root)) {
  engine_root <- normalizePath(script_path, winslash = "/")
} else {
  engine_root <- normalizePath(engine_root, winslash = "/", mustWork = TRUE)
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine_root)

study_root <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
if (!nzchar(study_root) && !is.null(wk_opts$root) && nzchar(wk_opts$root)) {
  study_root <- wk_opts$root
}
if (!nzchar(study_root) && !is.null(wk_opts$config) && nzchar(wk_opts$config) &&
    file.exists(wk_opts$config)) {
  study_root <- dirname(normalizePath(wk_opts$config, winslash = "/"))
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
  "[ml-worker-env] INCIDENCE_BATCH_ROOT=%s MEDICAL_BLOCKS_ROOT=%s study_root=%s",
  Sys.getenv("INCIDENCE_BATCH_ROOT"),
  Sys.getenv("MEDICAL_BLOCKS_ROOT"),
  study_root
))

db_mode <- wk_opts$db_mode
p_trim  <- wk_opts$p_trim
t_start <- proc.time()
ix_label <- wk_opts$index

source(file.path(engine_root, "R/feishu_env.R"))
feishu_load_dotenv(engine_root)
source(file.path(engine_root, "R/utils.R"))
source(file.path(engine_root, "R/dual_db_harmonize.R"))
source(file.path(engine_root, "R/pipeline_runner.R"))
source(file.path(engine_root, "R/ml_dual_pipeline_helpers.R"))
source(file.path(engine_root, "R/ml_dual_dev_ext.R"))
source(file.path(engine_root, "R/ml_cross_db_split.R"))
source(file.path(engine_root, "R/ml_assoc_data_slots.R"))
source(file.path(engine_root, "R/incidence_dual_batch_runner.R"))
source(file.path(engine_root, "R/ml_dual_batch_runner.R"))
source(file.path(engine_root, "R/feishu_bitable.R"))
source(file.path(engine_root, "configs/indices/composite_index_vars.R"))

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(engine_root, "configs/templates/config_ml_dual_batch.template.R")
}
source(config_path)
if (!exists("ml_dual_apply_baseline_index_ns_fail_rule", mode = "function")) {
  shared_ov <- file.path(engine_root, "configs/ml_dual_shared_overrides.R")
  if (file.exists(shared_ov)) source(shared_ov, local = FALSE)
}
if (exists("ml_dual_apply_baseline_index_ns_fail_rule", mode = "function")) {
  config <- ml_dual_apply_baseline_index_ns_fail_rule(config)
}
if (exists("ml_dual_audit_study_inherited_excludes", mode = "function")) {
  ml_dual_audit_study_inherited_excludes(config)
}

indices <- ml_batch_resolve_indices_from_label(ix_label, config)
ix      <- ix_label
cli::cli_h1("Worker: {ix_label} → [{paste(indices, collapse=', ')}], db={db_mode}")

gate_a_bundle <- tryCatch(
  incidence_batch_ensure_gate_a(config, root),
  error = function(e) list(config = config, gate_a = NULL)
)
config <- gate_a_bundle$config

if (!requireNamespace("jsonlite", quietly = TRUE)) stop("需要 jsonlite", call. = FALSE)
options(cli.hyperlink = FALSE, warn = 1)

bc          <- config$ml_batch %||% config$incidence_batch %||% list()
output_base <- bc$output_base %||% config$project$output_dir
ix_subdir   <- incidence_batch_index_output_subdir(bc)
ix_dir      <- incidence_batch_index_dir_label(ix, config)
output_ix   <- file.path(output_base, ix_subdir, ix_dir)
filter_stats <- list()

.write_status <- function(status, db_mode_used = db_mode,
                           nhanes_auc = NULL, mimic_auc = NULL,
                           error_message = NULL) {
  elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
  fields <- list(
    index = ix, status = status, db_mode = db_mode_used,
    nhanes_auc = if (is.null(nhanes_auc) || (length(nhanes_auc) == 1L && is.na(nhanes_auc))) NULL else nhanes_auc,
    mimic_auc = if (is.null(mimic_auc) || (length(mimic_auc) == 1L && is.na(mimic_auc))) NULL else mimic_auc,
    n_nhanes_after = filter_stats$nhanes$imputed$n_after %||% NA,
    n_mimic_after  = filter_stats$mimic$imputed$n_after %||% NA,
    error_message = error_message, elapsed_sec = elapsed,
    disease  = (config_ix$feishu %||% list())$disease_label %||% config_ix$project$disease %||% "",
    protocol = (config_ix$feishu %||% list())$protocol_label %||% ""
  )
  incidence_batch_write_status(output_ix, fields)
  if (exists("ml_batch_feishu_push_result", mode = "function")) {
    tryCatch(ml_batch_feishu_push_result(config_ix, fields), error = function(e) NULL)
  }
}

config_ix <- ml_batch_patch_config_for_indices(config, indices)
config_ix$dual_db$harmonization_dir <- file.path(
  bc$index_ck_base %||% file.path(.batch_ck_root, "by_index"), ix, "harmonization"
)
config_ix$dual_db$checkpoint_base <- file.path(
  bc$index_ck_base %||% file.path(.batch_ck_root, "by_index"), ix
)
config_ix$ml_batch$trim_quantile <- p_trim

db_seq <- switch(db_mode, nhanes = "nhanes", mimic = "mimic", c("nhanes", "mimic"))

from_cli <- wk_opts$from
to_cli <- wk_opts$to
blocks_cli <- wk_opts$blocks %||% character(0)

# ── 定向重跑（code 包 / --blocks）：不重拷 shared、不走完整 Phase ─────────────
if (length(blocks_cli) > 0L ||
    (!is.null(from_cli) && nzchar(as.character(from_cli)[1L])) ||
    (!is.null(to_cli) && nzchar(as.character(to_cli)[1L]))) {
  cli::cli_h1(
    "[{ix}] ML 定向重跑: from={from_cli %||% '-'} to={to_cli %||% '-'} blocks={paste(blocks_cli %||% '-', collapse=',')}"
  )
  .resolve_from_token <- function(per_ck, preferred, blocks) {
    fs <- list.files(per_ck, pattern = "\\.rds$", full.names = FALSE)
    nms <- unique(sub("^step[0-9]+_", "", sub("\\.rds$", "", fs)))
    if (!is.null(preferred) && nzchar(preferred) && preferred %in% nms) return(preferred)
    for (b in rev(as.character(blocks))) {
      if (b %in% nms) {
        if (!is.null(preferred) && nzchar(preferred) && !identical(b, preferred)) {
          cli::cli_alert_warning("[{ix}] 无 {.field {preferred}} ck，回退 {.field {b}}")
        }
        return(b)
      }
    }
    preferred
  }
  tryCatch({
    pri_pl <- if (dual_db_is_weighted(config_ix, "nhanes")) {
      pipeline_nhanes_batch
    } else {
      pipeline_regular_primary_ml_batch
    }
    blocks_full <- as.character(pri_pl$blocks %||% character(0))
    for (db in db_seq) {
      if (!isTRUE(all(vapply(indices, function(v) {
        isTRUE(incidence_batch_index_available(incidence_batch_shared_ck_dir(config, db), v))
      }, logical(1)))) && length(blocks_cli) == 0L) {
        ## 定向重跑以 per-index ck 为准；shared 缺失时仍可从已有 ck 续跑
        cli::cli_alert_warning("[{ix}/{toupper(db)}] shared 指标检查未通过，仍尝试 per-index 定向续跑")
      }
      cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
      per_ck <- file.path(
        bc$index_ck_base %||% file.path(.batch_ck_root, "by_index"), ix,
        dual_db_slot_path_name(config_ix, db)
      )
      pipe_db <- if (identical(db, "nhanes")) pri_pl else pipeline_mimic_ml_batch
      blocks_db <- as.character(pipe_db$blocks %||% character(0))
      from_db <- if (length(blocks_cli) > 0L) from_cli else from_cli
      if (is.null(from_db) || !nzchar(as.character(from_db)[1L])) {
        if (length(blocks_cli) > 0L) {
          target_pos <- match(blocks_cli, blocks_db)
          target_pos <- target_pos[is.finite(target_pos)]
          if (!length(target_pos)) {
            stop("--blocks 与当前数据库 pipeline 无交集", call. = FALSE)
          }
          first_pos <- min(target_pos)
          if (first_pos > 1L) {
            previous_blocks <- blocks_db[seq_len(first_pos - 1L)]
            from_db <- .resolve_from_token(
              per_ck, previous_blocks[[length(previous_blocks)]], previous_blocks
            )
          } else {
            from_db <- NULL
          }
        } else {
          from_db <- .resolve_from_token(per_ck, NULL, blocks_db)
        }
      } else {
        from_db <- .resolve_from_token(per_ck, from_db, blocks_db)
      }
      pipe <- incidence_batch_set_pipeline_ck(pipe_db, per_ck)
      run_opts_rerun <- list(
        from = from_db, to = to_cli,
        only = if (length(blocks_cli)) blocks_cli else NULL
      )
      cli::cli_alert_info("[{ix}/{toupper(db)}] 定向续跑 from={from_db %||% '-'}")
      run_pipeline(root, config = cfg_db, pipeline = pipe, run_opts = run_opts_rerun)
    }
    ## 单槽定向重跑仍双库汇总，避免 --db mimic 把主库表从图根冲掉
    fin_dbs <- unique(c("nhanes", "mimic"))
    tryCatch(
      incidence_batch_finalize_index_outputs(root, config_ix, ix, fin_dbs),
      error = function(e) cli::cli_alert_warning("定向重跑后汇总失败: {e$message}")
    )
    .write_status(status = "success", db_mode_used = db_mode)
    tryCatch(
      incidence_batch_rename_output_folder(
        output_base, ix, "success",
        overwrite = TRUE,
        index_subdir = ix_subdir,
        config = config_ix
      ),
      error = function(e) cli::cli_alert_warning("定向重跑后重命名失败: {e$message}")
    )
    cli::cli_alert_success("[{ix}] ML 定向重跑完成")
    quit(save = "no", status = 0)
  }, error = function(e) {
    msg <- conditionMessage(e)
    cli::cli_alert_danger("[{ix}] ML 定向重跑错误: {msg}")
    .write_status(status = "error", error_message = msg)
    quit(save = "no", status = 1)
  })
}

avail <- list()
for (db in db_seq) {
  ok <- all(vapply(indices, function(v) {
    isTRUE(incidence_batch_index_available(incidence_batch_shared_ck_dir(config, db), v))
  }, logical(1)))
  avail[[db]] <- ok
  cli::cli_alert_info("{toupper(db)}: {paste(indices, collapse=', ')} 可用 = {isTRUE(ok)}")
}

actual_db_mode <- db_mode
actual_db_seq  <- db_seq
if (db_mode == "both") {
  if (isTRUE(avail[["nhanes"]]) && isTRUE(avail[["mimic"]])) {
    actual_db_mode <- "both"
  } else if (isTRUE(avail[["nhanes"]])) {
    actual_db_mode <- "nhanes_only"; actual_db_seq <- "nhanes"
  } else if (isTRUE(avail[["mimic"]])) {
    actual_db_mode <- "mimic_only"; actual_db_seq <- "mimic"
  } else {
    .write_status("failed", error_message = "两库均无该指标")
    quit(save = "no", status = 1)
  }
}

.run_db_phase <- function(db, pipe, from_token, to_token) {
  cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
  per_ck <- file.path(
    bc$index_ck_base %||% file.path(.batch_ck_root, "by_index"), ix,
    dual_db_slot_path_name(config_ix, db)
  )
  pipe <- incidence_batch_set_pipeline_ck(pipe, per_ck)
  run_pipeline(root, config = cfg_db, pipeline = pipe,
               run_opts = list(from = from_token, to = to_token))
}

# 复制 shared ck + 删除非本任务指标列 + 过滤多指标 NA
registry_ix <- tryCatch(
  incidence_batch_resolve_index_vars(config),
  error = function(e) character(0)
)
all_computed_ix <- character(0)
for (db_ck in db_seq) {
  s_dir <- incidence_batch_shared_ck_dir(config, db_ck)
  s_obj <- tryCatch(readRDS(file.path(s_dir, "index.rds")), error = function(e) NULL)
  if (!is.null(s_obj))
    all_computed_ix <- union(all_computed_ix, s_obj$ctx$results$computed_index_names %||% character(0))
}
# 防止“其他复合指标”泄漏到 Table1/单因素：直接用全量复合指标池做剔除基线
all_ix_pool <- unique(c(
  all_computed_ix,
  registry_ix,
  get0(".composite_index_vars", inherits = TRUE) %||% character(0),
  get0(".composite_index_vars_dual_safe", inherits = TRUE) %||% character(0)
))
other_ix <- setdiff(all_ix_pool, indices)
if (exists("index_expand_alias_exclusions", mode = "function")) {
  other_ix <- index_expand_alias_exclusions(indices, other_ix)
}
#' 显式 opt-out：config$ml_batch$keep_other_index_cols = TRUE 时，
#' 本批 index_vars 的“同伴列”不按泄漏列剔除（无固定暴露设计需要
#' LASSO 入选变量互为协变量 → 每个 index 的数据须保留全部入选列）。
if (identical(as.logical((config$ml_batch %||% config$incidence_batch %||% list())$keep_other_index_cols)[1L], TRUE)) {
  .keep_ix <- as.character((config$ml_batch %||% config$incidence_batch)$index_vars %||% character(0))
  if (length(.keep_ix)) other_ix <- setdiff(other_ix, .keep_ix)
  rm(.keep_ix)
}

for (db in actual_db_seq) {
  shared_dir   <- incidence_batch_shared_ck_dir(config, db)
  per_index_ck <- file.path(
    bc$index_ck_base %||% file.path(.batch_ck_root, "by_index"), ix,
    dual_db_slot_path_name(config, db)
  )
  if (!dir.exists(per_index_ck)) dir.create(per_index_ck, recursive = TRUE)
  alias_src <- file.path(shared_dir, "index.rds")
  alias_dst <- file.path(per_index_ck, "index.rds")
  if (!file.exists(alias_src)) {
    .write_status("failed", error_message = sprintf("复制 %s checkpoint 失败", toupper(db)))
    quit(save = "no", status = 1)
  }
  file.copy(alias_src, alias_dst, overwrite = TRUE)
  ml_batch_seed_index_checkpoint(alias_dst, indices, other_ix, config_ix)

  if (length(indices) == 1L) {
    incidence_batch_apply_filter_and_trim(alias_dst, indices[[1L]], 0)
  } else if (file.exists(alias_dst)) {
    obj <- tryCatch(readRDS(alias_dst), error = function(e) NULL)
    if (!is.null(obj) && !is.null(obj$ctx)) {
      for (slot in c("mapped", "imputed", "cleaned")) {
        df <- obj$ctx$data[[slot]]
        if (is.null(df) || !is.data.frame(df)) next
        keep <- rep(TRUE, nrow(df))
        for (v in indices) if (v %in% names(df)) keep <- keep & !is.na(df[[v]])
        obj$ctx$data[[slot]] <- df[keep, , drop = FALSE]
      }
      saveRDS(obj, alias_dst)
    }
  }

  if (file.exists(alias_dst)) {
    obj <- tryCatch(readRDS(alias_dst), error = function(e) NULL)
    df_f <- incidence_batch_ctx_data(obj$ctx)
    if (!is.null(df_f)) filter_stats[[db]] <- list(imputed = list(n_after = nrow(df_f)))
  }
}

if (length(actual_db_seq) >= 2L &&
    exists("ml_dual_assert_primary_larger_n", mode = "function")) {
  tryCatch(
    ml_dual_assert_primary_larger_n(config_ix, ix = ix, stop_on_fail = TRUE),
    error = function(e) {
      .write_status("failed", error_message = conditionMessage(e))
      quit(save = "no", status = 1)
    }
  )
}

.split_mode <- as.character(
  config_ix$ml_batch$split_mode %||% config_ix$incidence_batch$split_mode %||% "per_db_internal"
)[1L]

.extract_auc <- function(ctx) {
  if (is.null(ctx)) return(NA_real_)
  v <- ctx$results$ml_best_auc %||% ctx$results$best_auc %||% ctx$results$auc_test
  suppressWarnings(as.numeric(v)[1])
}

result_ctx <- list()

.primary_pipeline <- function() {
  if (dual_db_is_weighted(config_ix, "nhanes")) pipeline_nhanes_batch else pipeline_regular_primary_ml_batch
}

# ── cross_db: 一份结果（大库 train / 小库 test），跳过每库独立 70/30 与次库 ML ──
if (identical(.split_mode, "cross_db")) {
  tryCatch({
    if (length(actual_db_seq) < 2L) {
      cli::cli_alert_warning(
        "split_mode=cross_db 但可用库 < 2，回退 per_db_internal 路径（单库）"
      )
    } else {
      ctx_x <- ml_batch_run_cross_db_index(
        root = root,
        config_ix = config_ix,
        ix = ix,
        indices = indices,
        actual_db_seq = actual_db_seq,
        bc = bc,
        primary_pipeline = .primary_pipeline()
      )
      .write_status(
        status = "success",
        db_mode_used = paste0(actual_db_mode, "+cross_db"),
        nhanes_auc = .extract_auc(ctx_x),
        mimic_auc = .extract_auc(ctx_x)
      )
      quit(save = "no", status = 0)
    }
  }, error = function(e) {
    .write_status("error", error_message = paste0("cross_db: ", conditionMessage(e)))
    quit(save = "no", status = 1)
  })
}

result_ctx <- list()

tryCatch({
  # 从 index 检查点续跑（shared index.rds）；imputation 及之后 per-index 重跑
  nhanes_from <- "index"
  mimic_from  <- "index"

  if ("nhanes" %in% actual_db_seq) {
    if (length(indices) > 1L && dual_db_is_weighted(config_ix, "nhanes")) {
      cli::cli_h2("[{ix}] NHANES — 共享 VIF + 多指标 logistic + ML（{length(indices)} 指标）")
      result_ctx[["nhanes"]] <- .run_db_phase(
        "nhanes", pipeline_nhanes_upstream,
        nhanes_from, "multicollinearity_nhanes_final"
      )
      result_ctx[["nhanes"]] <- .run_db_phase(
        "nhanes", pipeline_nhanes_multi_logistic,
        "multicollinearity_nhanes_final", "ml_logistic_multi_index_bundle"
      )
      result_ctx[["nhanes"]] <- .run_db_phase(
        "nhanes", pipeline_nhanes_ml_tail,
        "ml_logistic_multi_index_bundle", NULL
      )
    } else {
      ## 单指标 或 普通双库组合（combo_loop）：两端点同走主库上游→ML
      ## （regular 主库无 NHANES 专属分段流水线；两指标一起进 VIF/FS/assoc/ML）
      pri_pl <- .primary_pipeline()
      cli::cli_h2("[{ix}] 主库 — VIF 分步 + 特征选择（from={nhanes_from}, {length(indices)} 指标）")
      result_ctx[["nhanes"]] <- .run_db_phase(
        "nhanes", pri_pl,
        nhanes_from, "ml_feature_selection_bundle"
      )
      result_ctx[["nhanes"]] <- .run_db_phase(
        "nhanes", pri_pl,
        "ml_feature_selection_bundle", NULL
      )
    }
  }

  if ("mimic" %in% actual_db_seq) {
    cli::cli_h2("[{ix}] 外验库 — baseline → 继承主库特征（跳过 UV/VIF/FS）")
    result_ctx[["mimic"]] <- .run_db_phase(
      "mimic", pipeline_mimic_ml_batch,
      mimic_from, "ml_inherit_primary_features"
    )
    cli::cli_h2("[{ix}] 外验库 — 同构 ML 下游（自训）")
    result_ctx[["mimic"]] <- .run_db_phase(
      "mimic", pipeline_mimic_ml_batch,
      "ml_inherit_primary_features", NULL
    )
  }

  # 发病 ML 双库：与 run_incidence_dual_batch_worker 一致 — 闸门 B 协变量对齐 + 闸门 C 分位统一
  # Gate C 落盘后须把统一锁写入 ck，并重跑 assoc（Table 2/RCS）与亚组
  if (identical(actual_db_mode, "both") && length(actual_db_seq) >= 2L) {
    st <- tolower(trimws(as.character(config_ix$project$study_type %||% "incidence")[1L]))
    if (identical(st, "incidence") &&
        exists("dual_db_force_gate_b_sync", mode = "function") &&
        exists("dual_db_harmonize_unified_logistic_branch", mode = "function")) {
      cli::cli_h2("[{ix}] Gate B 同步（双库协变量对齐）")
      tryCatch(
        dual_db_force_gate_b_sync(root, config_ix),
        error = function(e) cli::cli_alert_warning("Gate B 同步失败: {e$message}")
      )
      cli::cli_h2("[{ix}] Gate C — Logistic 分位双库统一")
      uni <- tryCatch(
        dual_db_harmonize_unified_logistic_branch(root, config_ix),
        error = function(e) {
          cli::cli_alert_warning("Gate C 分位统一失败: {e$message}")
          NULL
        }
      )
      uni_info <- dual_db_load_logistic_branch(root, config_ix)
      if (is.null(uni_info) && !is.null(uni)) {
        uni_info <- list(branch = uni$branch, scheme = uni$scheme, detail = uni$detail)
      }
      if (!is.null(uni_info) && nzchar(as.character(uni_info$scheme %||% "")[1L])) {
        cli::cli_h2(
          "[{ix}] Gate C 后重导 Table 2 / RCS / 亚组（统一分位={uni_info$scheme}）"
        )
        gate_b <- if (exists("dual_db_load_gate_b", mode = "function")) {
          tryCatch(dual_db_load_gate_b(root, config_ix), error = function(e) NULL)
        } else {
          NULL
        }
        for (db in actual_db_seq) {
          per_ck <- file.path(
            bc$index_ck_base %||% file.path(.batch_ck_root, "by_index"), ix,
            dual_db_slot_path_name(config_ix, db)
          )
          # from=X 表示「从 X 之后」续跑；要重跑 resolve，须从上一块续跑
          from_before <- if (identical(db, "nhanes")) {
            "ml_feature_selection_bundle"
          } else {
            "ml_inherit_primary_features"
          }
          .patch_ck_ctx <- function(ck_p) {
            if (!file.exists(ck_p)) return(invisible(FALSE))
            obj <- tryCatch(readRDS(ck_p), error = function(e) NULL)
            if (is.null(obj$ctx)) return(invisible(FALSE))
            if (!is.null(gate_b) &&
                exists("dual_db_apply_gate_b_to_ctx", mode = "function")) {
              obj$ctx <- tryCatch(
                dual_db_apply_gate_b_to_ctx(obj$ctx, db, gate_b),
                error = function(e) obj$ctx
              )
            }
            if (exists("dual_db_seed_logistic_branch_to_ctx", mode = "function")) {
              obj$ctx <- dual_db_seed_logistic_branch_to_ctx(obj$ctx, uni_info)
            }
            obj$ctx$results$dual_db_logistic_unified_locked <- TRUE
            obj$ctx$results$dual_db_logistic_unified_scheme <- uni_info$scheme
            obj$ctx$results$logistic_branch <- uni_info$branch %||%
              paste0("extend_", uni_info$scheme)
            tryCatch(saveRDS(obj, ck_p), error = function(e) NULL)
            invisible(TRUE)
          }
          # 同时补丁 stepNN_* 与裸名 alias（续跑优先读 stepNN_*）
          ck_files <- list.files(per_ck, pattern = "\\.rds$", full.names = TRUE)
          for (ck_p in ck_files) {
            bn <- basename(ck_p)
            if (grepl(
              paste0(
                "(^|_)(", from_before,
                "|ml_assoc_covariate_resolve|dual_db_covariate_harmonize|ml_assoc_bundle)(\\.rds$)"
              ),
              bn
            )) {
              .patch_ck_ctx(ck_p)
            }
          }
          # 删掉 resolve/harmonize/assoc 检查点，强制重算（避免脏 Model1Factors 残留）
          for (pat in c(
            "ml_assoc_covariate_resolve", "dual_db_covariate_harmonize", "ml_assoc_bundle"
          )) {
            olds <- list.files(per_ck, pattern = paste0(pat, "\\.rds$"), full.names = TRUE)
            if (length(olds)) unlink(olds)
          }
          pipe <- if (identical(db, "nhanes")) {
            .primary_pipeline()
          } else {
            pipeline_mimic_ml_batch
          }
          result_ctx[[db]] <- tryCatch(
            .run_db_phase(db, pipe, from_before, "ml_assoc_bundle"),
            error = function(e) {
              cli::cli_alert_warning("[{toupper(db)}] Gate C 重导 assoc 失败: {e$message}")
              result_ctx[[db]]
            }
          )
          # 亚组跟主文 grouping；从 shiny ck 后续跑 subgroup_*（不重训 ML）
          if ("shiny_ml_app" %in% as.character(pipe$blocks %||% character(0))) {
            result_ctx[[db]] <- tryCatch(
              .run_db_phase(db, pipe, "shiny_ml_app", "subgroup_prognosis"),
              error = function(e) {
                cli::cli_alert_warning("[{toupper(db)}] Gate C 重导亚组失败: {e$message}")
                result_ctx[[db]]
              }
            )
          }
        }
      }
    }
  }

  incidence_batch_finalize_index_outputs(root, config_ix, ix, actual_db_seq)

  .write_status(
    status = "success",
    db_mode_used = actual_db_mode,
    nhanes_auc = .extract_auc(result_ctx[["nhanes"]]),
    mimic_auc  = .extract_auc(result_ctx[["mimic"]])
  )
  quit(save = "no", status = 0)

}, error = function(e) {
  msg <- conditionMessage(e)
  tryCatch(
    incidence_batch_finalize_index_outputs(root, config_ix, ix, actual_db_seq),
    error = function(e2) NULL
  )
  .write_status("error", error_message = msg)
  quit(save = "no", status = 1)
})
