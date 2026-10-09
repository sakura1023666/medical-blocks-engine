#!/usr/bin/env Rscript
# =============================================================================
#  SLE → AKI 两阶段 batch — 单指标 Worker
#
#  流程:
#    1. 复制 shared checkpoint → per-index（过滤当前指标 NA）
#    2. Stage1 发病链
#    3. ip_stage2_cohort_28d
#    4. 切换 prognosis（study_type / outcome / 协变量综合）
#    5. Stage2 预后链
#    6. finalize：Tables/Figures 镜像到结果根；index_code_bundle_finalize
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
    index = NULL, db_mode = "mimic", root = NULL, p_trim = 0,
    config = NULL, from = NULL, to = NULL
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
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$index) || !nzchar(opts$index))
    stop("--index 参数必填", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) %in% c(
  "environment", "incidence", "survival", "feishu", "hf", "sle_aki_inc_prog"
) && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
setwd(script_path)

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

root_guess <- normalizePath(getwd(), winslash = "/")
env_root <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = "")
if (!nzchar(env_root)) env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  root_guess <- normalizePath(env_root, winslash = "/", mustWork = TRUE)
} else if (!is.null(wk_opts$root) && nzchar(wk_opts$root)) {
  root_guess <- normalizePath(wk_opts$root, winslash = "/", mustWork = TRUE)
}

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

ix       <- wk_opts$index
p_trim   <- if (is.null(wk_opts$p_trim)) 0 else wk_opts$p_trim
from_cli <- wk_opts$from
to_cli   <- wk_opts$to
resume_mode <- (
  (!is.null(from_cli) && nzchar(as.character(from_cli)[1L])) ||
    (!is.null(to_cli) && nzchar(as.character(to_cli)[1L]))
)
t_start <- proc.time()

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)

config_path <- {
  env_cfg <- Sys.getenv("INCIDENCE_BATCH_CONFIG", unset = "")
  if (nzchar(env_cfg)) {
    normalizePath(env_cfg, winslash = "/", mustWork = TRUE)
  } else if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
    normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
  } else {
    file.path(root, "configs/templates/config_sle_aki_inc_prog_batch.template.R")
  }
}
Sys.setenv(STUDY_CONFIG_DIR = dirname(config_path))

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/model3_required.R"))
source(file.path(root, "R/baseline_dictionary_labels.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/logistic_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/incidence_sensitivity_suite.R"))
source(file.path(root, "R/index_code_bundle.R"))
source(file.path(root, "R/ip_two_stage_batch_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
source(config_path)

if (!requireNamespace("jsonlite", quietly = TRUE))
  stop("请先安装 jsonlite: install.packages('jsonlite')", call. = FALSE)

options(cli.hyperlink = FALSE, warn = 1)

config <- ip_two_stage_sync_batch_cfg(config)
bc <- ip_two_stage_batch_cfg(config)
light <- isTRUE(bc$.sensitivity_light)
output_base <- bc$output_base %||% config$project$output_dir
output_ix <- ip_two_stage_index_output_dir(config, ix, resume = resume_mode)
per_ck <- ip_two_stage_index_ck_dir(config, ix)
shared_dir <- ip_two_stage_shared_ck_dir(config)

filter_stats <- list()
config_ix <- config

.write_status <- function(status, error_message = NULL, extra = list()) {
  elapsed <- round(as.numeric((proc.time() - t_start)["elapsed"]), 1)
  fields <- modifyList(list(
    index         = ix,
    status        = status,
    db_mode       = "mimic",
    n_before      = filter_stats$n_before %||% NA,
    n_after       = filter_stats$n_after %||% NA,
    error_message = error_message,
    elapsed_sec   = elapsed,
    disease       = (config_ix$feishu %||% list())$disease_label %||%
      config_ix$project$disease %||% "",
    protocol      = (config_ix$feishu %||% list())$protocol_label %||% ""
  ), extra)
  incidence_batch_write_status(output_ix, fields)
}

cli::cli_h1(paste0(
  "Worker two-stage: index=", ix,
  if (light) " [sensitivity light]" else ""
))

config_ix <- incidence_batch_patch_config_for_index(config, ix, root = root)
config_ix <- ip_two_stage_patch_km_strata_for_index(config_ix, ix)
config_ix <- ip_two_stage_patch_stage2_blocks_for_index(config_ix, ix)
config_ix$project$root <- root
config_ix$project$output_dir <- output_ix
config_ix$dual_db$enable <- FALSE
# Table1 暴露组间不显著 → 早停记失败（见 config$baseline_binary$early_stop_if_index_ns）
if (!is.null(pipeline_regular_batch)) {
  config_ix$pipeline <- pipeline_regular_batch
  config_ix$pipeline_regular_batch <- pipeline_regular_batch
  config_ix$incidence_batch$.pipeline_blocks <- pipeline_regular_batch$blocks
  # 勿建空 survival_batch：否则 code bundle 把 output_base 读丢，检查点找不到
  if (!is.null(config_ix$survival_batch) && is.list(config_ix$survival_batch)) {
    config_ix$survival_batch$.pipeline_blocks <- pipeline_regular_batch$blocks
    if (is.null(config_ix$survival_batch$output_base)) {
      config_ix$survival_batch$output_base <- output_base
    }
  }
}

if (!light) {
  ip_two_stage_ensure_index_alias(shared_dir)
  ok_ix <- tryCatch(incidence_batch_index_available(shared_dir, ix), error = function(e) NA)
  if (isFALSE(ok_ix)) {
    .write_status("failed", error_message = sprintf("共享层无法计算 %s", ix))
    quit(save = "no", status = 1)
  }
}

# 其他指标列：分析时从 per-index ck 删除
all_ix_pool <- unique(c(
  as.character(ip_two_stage_resolve_index_vars(config)),
  get0(".composite_index_vars", inherits = TRUE) %||% character(0)
))
protect_ix <- unique(c("BMI", "Weight", "Height",
                       as.character(bc$protect_index_cols %||% character(0))))
other_ix <- setdiff(all_ix_pool, c(ix, protect_ix))

if (light) {
  if (isTRUE(bc$.sensitivity_complete_case)) {
    cli::cli_alert_info("[{ix}] 敏感性轻量路径：未插补完整病例，不复制 shared、不插补")
  } else {
    cli::cli_alert_info("[{ix}] 敏感性轻量路径：使用主分析插补后 ck，不复制 shared、不插补")
  }
  idx_p <- file.path(per_ck, "index.rds")
  if (!file.exists(idx_p)) {
    .write_status(
      "failed",
      error_message = sprintf("轻量路径缺少 %s/index.rds（suite 应已拷+过滤）", per_ck)
    )
    quit(save = "no", status = 1)
  }
  obj <- tryCatch(readRDS(idx_p), error = function(e) NULL)
  df_f <- incidence_batch_ctx_data(obj$ctx)
  if (!is.null(df_f) && is.data.frame(df_f)) {
    filter_stats$n_after <- nrow(df_f)
    filter_stats$n_before <- nrow(df_f)
  }
} else if (!resume_mode) {
  ok <- incidence_batch_copy_shared_ck(shared_dir, per_ck, ix, 0)
  if (!ok) {
    .write_status("failed", error_message = "复制 shared checkpoint 失败")
    quit(save = "no", status = 1)
  }
  if (length(other_ix) > 0) {
    ck_path <- file.path(per_ck, "index.rds")
    obj <- tryCatch(readRDS(ck_path), error = function(e) NULL)
    if (!is.null(obj) && !is.null(obj$ctx)) {
      for (slot in c("mapped", "imputed", "cleaned", "raw")) {
        df <- obj$ctx$data[[slot]]
        if (!is.null(df) && is.data.frame(df)) {
          drop <- intersect(other_ix, names(df))
          if (length(drop)) obj$ctx$data[[slot]] <- df[, setdiff(names(df), drop), drop = FALSE]
        }
      }
      obj$ctx$results$computed_index_names <- ix
      saveRDS(obj, ck_path)
    }
  }
  obj <- tryCatch(readRDS(file.path(per_ck, "index.rds")), error = function(e) NULL)
  df_f <- incidence_batch_ctx_data(obj$ctx)
  if (!is.null(df_f) && is.data.frame(df_f))
    filter_stats$n_after <- nrow(df_f)
  s_obj <- tryCatch(readRDS(file.path(shared_dir, "index.rds")), error = function(e) NULL)
  if (is.null(s_obj)) {
    s_obj <- tryCatch(readRDS(ip_two_stage_latest_shared_ck(shared_dir)), error = function(e) NULL)
  }
  df_b <- incidence_batch_ctx_data(s_obj$ctx)
  if (!is.null(df_b) && is.data.frame(df_b))
    filter_stats$n_before <- nrow(df_b)
} else {
  cli::cli_alert_info(
    "[{ix}] 续跑 from={from_cli %||% '-'} to={to_cli %||% '-'}；输出={.file {output_ix}}"
  )
  if (!dir.exists(per_ck)) {
    .write_status("failed", error_message = paste("续跑缺少检查点:", per_ck))
    quit(save = "no", status = 1)
  }
}

plan <- if (light) {
  list(
    run_stage1 = TRUE, run_bridge = FALSE, run_stage2 = FALSE,
    stage1_from = NULL, stage1_to = NULL,
    stage2_from = NULL, stage2_to = NULL,
    from_phase = "stage1", to_phase = "stage1"
  )
} else {
  ip_two_stage_plan_worker_phases(
    pipeline_stage1$blocks, pipeline_stage2$blocks, from_cli, to_cli
  )
}
if (!light && identical(plan$from_phase, "shared")) {
  cli::cli_alert_info("[{ix}] --from 落在 shared，worker 从 Stage1 开头跑")
  plan$run_stage1 <- TRUE
  plan$stage1_from <- NULL
}

.load_ctx <- function(prefer = c(
    "ip_stage2_cohort_28d.rds",
    "subgroup_incidence.rds",
    "threshold_logistic.rds",
    "index.rds",
    "imputation.rds"
  )) {
  for (bn in prefer) {
    p <- file.path(per_ck, bn)
    if (file.exists(p)) {
      obj <- tryCatch(readRDS(p), error = function(e) NULL)
      if (!is.null(obj$ctx)) return(obj$ctx)
    }
  }
  latest <- ip_two_stage_latest_shared_ck(per_ck)
  if (!is.na(latest) && file.exists(latest)) {
    obj <- tryCatch(readRDS(latest), error = function(e) NULL)
    if (!is.null(obj$ctx)) return(obj$ctx)
  }
  NULL
}

.run_phase <- function(pipe, from_token, to_token, initial_ctx, cfg) {
  pipe <- incidence_batch_set_pipeline_ck(pipe, per_ck)
  ro <- list()
  if (!is.null(from_token) && nzchar(as.character(from_token)[1L])) {
    alias <- file.path(per_ck, paste0(from_token, ".rds"))
    if (file.exists(alias)) {
      obj <- tryCatch(readRDS(alias), error = function(e) NULL)
      if (!is.null(obj$ctx)) initial_ctx <- obj$ctx
      bl <- as.character(pipe$blocks %||% character(0))
      idx <- match(from_token, bl)
      if (!is.na(idx) && idx < length(bl)) {
        rest <- bl[seq.int(idx + 1L, length(bl))]
        if (!is.null(to_token) && nzchar(as.character(to_token)[1L])) {
          end <- match(to_token, rest)
          if (!is.na(end)) rest <- rest[seq_len(end)]
        }
        pipe$blocks <- rest
        from_token <- NULL
        to_token <- NULL
      }
    } else {
      ro$from <- from_token
    }
  }
  if (is.null(ro$from) && !is.null(initial_ctx)) {
    ro$initial_ctx <- initial_ctx
  }
  if (!is.null(to_token) && nzchar(as.character(to_token)[1L])) {
    ro$to <- to_token
  }
  run_pipeline(root, config = cfg, pipeline = pipe, run_opts = ro)
}

ctx <- NULL
tryCatch({
  if (isTRUE(plan$run_stage1)) {
    cli::cli_h2(paste0(
      "[", ix, "] Stage1 发病",
      if (light) "（敏感性轻量：Table1 + Logistic）" else ""
    ))
    ctx0 <- if (is.null(plan$stage1_from)) .load_ctx() else NULL
    pipe_s1 <- pipeline_stage1
    if (light) {
      scheme <- as.character(bc$.sensitivity_scheme %||% "quartile")[1L]
      if (!scheme %in% c("quartile", "tertile", "binary")) scheme <- "quartile"
      keep <- incidence_sensitivity_light_blocks("incidence", FALSE, scheme)
      pipe_s1 <- incidence_sensitivity_trim_pipeline(pipe_s1, keep)
      if (!is.null(pipe_s1$logistic_gate) && is.list(pipe_s1$logistic_gate)) {
        pipe_s1$logistic_gate$enable <- FALSE
      }
      if (!length(as.character(pipe_s1$blocks %||% character(0)))) {
        stop("敏感性轻量路径截断后 Stage1 blocks 为空", call. = FALSE)
      }
      idx_p <- file.path(per_ck, "index.rds")
      idx_obj <- readRDS(idx_p)
      if (is.null(idx_obj$ctx)) {
        stop("轻量路径 index.rds 无效（缺 ctx）: ", idx_p, call. = FALSE)
      }
      if (is.null(idx_obj$ctx$results)) idx_obj$ctx$results <- list()
      .lg_nm <- paste0("logistic_", scheme, "_glm")
      .lg_cfg <- config_ix[[.lg_nm]] %||% list()
      .harm <- (config_ix$dual_db %||% list())$harmonization %||% list()
      m1 <- as.character(
        .lg_cfg$model1_factors %||% .harm$harmonized_model1_mimic %||%
          .harm$harmonized_model1_nhanes %||% character(0)
      )
      m2 <- as.character(
        .lg_cfg$model2_factors %||% .harm$harmonized_model2_mimic %||%
          .harm$harmonized_model2_nhanes %||% character(0)
      )
      if (length(m1)) idx_obj$ctx$results$Model1Factors <- m1
      if (length(m2)) idx_obj$ctx$results$Model2Factors <- m2
      ctx0 <- idx_obj$ctx
      plan$stage1_from <- NULL
      plan$stage1_to <- NULL
    } else if (!"analysis_exclusion" %in% as.character(pipe_s1$blocks %||% character(0))) {
      pipe_s1$blocks <- c("analysis_exclusion", as.character(pipe_s1$blocks))
    }
    ctx <- .run_phase(
      pipe_s1, plan$stage1_from, plan$stage1_to, ctx0, config_ix
    )
    if (!light) ctx <- ip_two_stage_snapshot_stage1_covariates(ctx)
    if (!light) ctx <- ip_two_stage_snapshot_stage1_subgroup(ctx, config_ix)
  } else {
    ctx <- .load_ctx()
    if (!is.null(ctx)) {
      ctx <- ip_two_stage_snapshot_stage1_covariates(ctx)
      ctx <- ip_two_stage_snapshot_stage1_subgroup(ctx, config_ix)
    }
  }

  if (isTRUE(plan$run_bridge)) {
    cli::cli_h2("[{ix}] 桥接 ip_stage2_cohort_28d")
    if (is.null(ctx)) ctx <- .load_ctx()
    pipe_b <- list(
      name = "sle_aki_inc_prog_bridge",
      blocks = "ip_stage2_cohort_28d",
      logistic_gate = list(enable = FALSE),
      cox_gate = list(enable = FALSE),
      render_tables_after = character(0),
      render_figures_after = character(0),
      dual_db = list(enable = FALSE),
      checkpoint = list(enable = TRUE, dir = per_ck)
    )
    ctx <- .run_phase(pipe_b, NULL, NULL, ctx, config_ix)
  }

  if (isTRUE(plan$run_stage2)) {
    cli::cli_h2("[{ix}] Stage2 预后（28d）")
    if (is.null(ctx)) ctx <- .load_ctx(c("ip_stage2_cohort_28d.rds", "index.rds"))
    for (nm in c("cox_quartile", "cox_tertile", "cox_binary")) {
      if (is.null(config_ix[[nm]]) || !is.list(config_ix[[nm]])) next
      config_ix[[nm]]$stop_if_crude_highest_ns <- FALSE
      if (is.null(config_ix[[nm]]$covariate_search) || !is.list(config_ix[[nm]]$covariate_search)) {
        config_ix[[nm]]$covariate_search <- list()
      }
      config_ix[[nm]]$covariate_search$enable <- FALSE
      config_ix[[nm]]$covariate_search$on_search_fail <- "degrade"
      if (identical(nm, "cox_binary") &&
          !nzchar(as.character(config_ix[[nm]]$degrade_branch %||% "")[1L])) {
        config_ix[[nm]]$degrade_branch <- "degrade_done"
      }
    }
    if (!is.null(config_ix$cox_binary) && is.list(config_ix$cox_binary)) {
      config_ix$cox_binary$gate_enable <- FALSE
      config_ix$cox_binary$require_both_models_sig <- FALSE
      config_ix$cox_binary$stop_if_crude_highest_ns <- FALSE
    }
    sw <- ip_two_stage_switch_to_prognosis(config_ix, ctx)
    config_ix <- sw$config
    ctx <- sw$ctx
    if (length(ctx$results$locked_subgroup_vars %||% character(0))) {
      lk <- as.character(ctx$results$locked_subgroup_vars)
      config_ix$subgroup$locked_subgroup_vars <- lk
      config_ix$subgroup_prognosis$locked_subgroup_vars <- lk
    }

    pipe_s2 <- ip_two_stage_trim_stage2_pipeline(config_ix, pipeline_stage2)
    reuse_m12 <- ip_two_stage_reuse_stage1_covariates(config_ix)

    if (reuse_m12) {
      prep <- ip_two_stage_prepare_stage2_locked_covariates(config_ix, ctx)
      config_ix <- prep$config
      ctx <- prep$ctx
      ctx <- .run_phase(
        pipe_s2, plan$stage2_from, plan$stage2_to, ctx, config_ix
      )
    } else {
      if (!is.null(ctx)) {
        ctx <- ip_two_stage_apply_covariate_union(ctx, config_ix, "before_stage2")
        config_ix$univariate_prognosis$required_predictors <-
          ctx$config$univariate_prognosis$required_predictors
        config_ix$multivariate_prognosis$required_predictors <-
          ctx$config$multivariate_prognosis$required_predictors
        ctx$config <- config_ix
      }
      bl2 <- as.character(pipe_s2$blocks %||% character(0))
      i_lock <- which(bl2 %in% c(
        "cox_quartile", "cox_tertile", "cox_binary", "rcs_prognosis"
      ))[1L]
      if (is.finite(i_lock) && i_lock > 1L) {
        pipe_pre <- pipe_s2
        pipe_pre$blocks <- bl2[seq_len(i_lock - 1L)]
        pipe_post <- pipe_s2
        pipe_post$blocks <- bl2[seq.int(i_lock, length(bl2))]
        to_pre <- if (!is.null(plan$stage2_to) &&
                      as.character(plan$stage2_to)[1L] %in% pipe_pre$blocks) {
          plan$stage2_to
        } else {
          tail(pipe_pre$blocks, 1L)
        }
        from_pre <- if (!is.null(plan$stage2_from) &&
                        as.character(plan$stage2_from)[1L] %in% pipe_pre$blocks) {
          plan$stage2_from
        } else {
          NULL
        }
        from_b <- as.character(plan$stage2_from %||% "")[1L]
        skip_pre <- nzchar(from_b) && from_b %in% pipe_post$blocks
        if (!skip_pre) {
          ctx <- .run_phase(pipe_pre, from_pre, to_pre, ctx, config_ix)
        }
        ctx <- ip_two_stage_apply_covariate_union(ctx, config_ix, "after_stage2")
        config_ix <- ip_two_stage_lock_cox_rcs_covariates(config_ix, ctx)
        ctx$config <- config_ix
        to_b <- as.character(plan$stage2_to %||% "")[1L]
        skip_post <- nzchar(to_b) && to_b %in% pipe_pre$blocks &&
          !(to_b %in% pipe_post$blocks)
        if (!skip_post) {
          from_post <- if (nzchar(from_b) && from_b %in% pipe_post$blocks) from_b else NULL
          to_post <- if (nzchar(to_b) && to_b %in% pipe_post$blocks) to_b else NULL
          ctx <- .run_phase(pipe_post, from_post, to_post, ctx, config_ix)
        }
      } else {
        ctx <- .run_phase(
          pipe_s2, plan$stage2_from, plan$stage2_to, ctx, config_ix
        )
      }
      ctx <- ip_two_stage_apply_covariate_union(ctx, config_ix, "after_stage2")
    }
  }

  ip_two_stage_finalize_index_outputs(root, config_ix, ix, ctx)
  extra <- list(
    study_type = if (light) "incidence" else (config_ix$project$study_type %||% NA_character_),
    n_stage2 = if (light) NA else (ctx$results$ip_stage2$n_stage2 %||% NA),
    n_event  = if (light) NA else (ctx$results$ip_stage2$n_event %||% NA),
    mimic_branch = if (light) {
      paste0("logistic_", as.character(bc$.sensitivity_scheme %||% "quartile")[1L])
    } else {
      NULL
    }
  )
  .write_status("success", extra = extra)
  cli::cli_alert_success(paste0(
    "[", ix, "] ",
    if (light) "敏感性轻量路径" else "两阶段",
    "完成"
  ))
  quit(save = "no", status = 0)

}, error = function(e) {
  msg <- conditionMessage(e)
  cli::cli_alert_danger("[{ix}] 错误: {msg}")
  tryCatch(
    ip_two_stage_finalize_index_outputs(root, config_ix, ix, ctx),
    error = function(e2) cli::cli_alert_warning("[{ix}] finalize 失败: {e2$message}")
  )
  .write_status("error", error_message = msg)
  quit(save = "no", status = 1)
})
