#!/usr/bin/env Rscript
# =============================================================================
#  ML 双库批量 — 单指标 Worker
#
#  Phase 1: 主库 → train_validation → ml_feature_selection_bundle（导出主库特征）
#  Phase 2: MIMIC → imputation → ml_inherit → ML 下游
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
  opts <- list(index = NULL, db_mode = "both", root = NULL, p_trim = 0.01, config = NULL)
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
setwd(script_path)

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

root <- normalizePath(
  if (!is.null(wk_opts$root) && nzchar(wk_opts$root)) wk_opts$root else getwd(),
  winslash = "/", mustWork = TRUE
)
owd <- getwd()
setwd(root)
on.exit(setwd(owd), add = TRUE)

db_mode <- wk_opts$db_mode
p_trim  <- wk_opts$p_trim
t_start <- proc.time()
ix_label <- wk_opts$index

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/ml_dual_pipeline_helpers.R"))
source(file.path(root, "R/ml_cross_db_split.R"))
source(file.path(root, "R/ml_assoc_data_slots.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/ml_dual_batch_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_ml_dual_batch.template.R")
}
source(config_path)

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
output_ix   <- file.path(output_base, ix_subdir, ix)
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
## 暴露别名：原始表 UA_Cr 与引擎 UA_CR 同义，必须剔除避免 Table1/特征双行
if (length(indices) == 1L && identical(indices[[1L]], "UA_CR")) {
  other_ix <- unique(c(other_ix, "UA_Cr", "UA_CrR"))
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
    if (length(indices) > 1L) {
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
      pri_pl <- .primary_pipeline()
      cli::cli_h2("[{ix}] 主库 — VIF 分步 + 特征选择（from={nhanes_from}）")
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
    cli::cli_h2("[{ix}] MIMIC — 插补 + 注入主库特征")
    result_ctx[["mimic"]] <- .run_db_phase(
      "mimic", pipeline_mimic_ml_batch,
      mimic_from, "ml_inherit_primary_features"
    )
    cli::cli_h2("[{ix}] MIMIC — ML 下游")
    result_ctx[["mimic"]] <- .run_db_phase(
      "mimic", pipeline_mimic_ml_batch,
      "ml_inherit_primary_features", NULL
    )
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
