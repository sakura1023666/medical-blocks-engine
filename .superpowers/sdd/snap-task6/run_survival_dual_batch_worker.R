#!/usr/bin/env Rscript
# =============================================================================
#  预后双库批量 — 单指标 Worker 子进程
#
#  用法（调试）:
#    Rscript run/survival/run_survival_dual_batch_worker.R --index NLR [--db both] [--ptrim 0.01]
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
  opts <- list(index = NULL, db_mode = "both", root = NULL, p_trim = NULL, config = NULL)
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
setwd(script_path)

args    <- commandArgs(trailingOnly = TRUE)
wk_opts <- .parse_worker_args(args)

root_guess <- normalizePath(getwd(), winslash = "/")
if (!is.null(wk_opts$root) && nzchar(wk_opts$root))
  root_guess <- normalizePath(wk_opts$root, winslash = "/", mustWork = TRUE)

owd <- getwd()
setwd(root_guess)
on.exit(setwd(owd), add = TRUE)
root <- root_guess

ix      <- wk_opts$index
db_mode <- wk_opts$db_mode
t_start <- proc.time()

source(file.path(root, "R/feishu_env.R"))
feishu_load_dotenv(root)

config_path <- if (!is.null(wk_opts$config) && nzchar(wk_opts$config)) {
  normalizePath(wk_opts$config, winslash = "/", mustWork = TRUE)
} else {
  file.path(root, "configs/templates/config_survival_dual_batch.template.R")
}

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/model3_required.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/cox_gate.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "configs/indices/composite_index_vars.R"))
source(file.path(root, "R/survival_dual_batch_runner.R"))
source(file.path(root, "R/feishu_bitable.R"))
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
output_base <- bc$output_base %||% config$project$output_dir
output_ix   <- file.path(output_base, "by_index", ix)
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

avail <- list()
for (db in db_seq) {
  shared_ck_dir <- incidence_batch_shared_ck_dir(config, db)
  avail[[db]] <- incidence_batch_index_available(shared_ck_dir, ix)
  cli::cli_alert_info("{toupper(db)}: {ix} 可用 = {isTRUE(avail[[db]])}")
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

.run_db_phase <- function(db, from_token, to_token) {
  cfg_db <- incidence_batch_apply_db_overrides(config_ix, db, root, ix)
  pipe   <- pipeline_regular_batch
  per_ck <- file.path(
    bc$index_ck_base %||% "checkpoints/_by_index", ix,
    dual_db_slot_path_name(config_ix, db)
  )
  pipe <- incidence_batch_set_pipeline_ck(pipe, per_ck)
  run_pipeline(root, config = cfg_db, pipeline = pipe,
               run_opts = list(from = from_token, to = to_token))
}

result_ctx <- list()

tryCatch({
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

  incidence_batch_finalize_index_outputs(root, config_ix, ix, actual_db_seq)

  # 覆盖 Figure1 占位：纳排 + 指标缺失；极端值仅 n_trim>0 时出现（不因 p_trim 默认硬开）
  tryCatch({
    project_root <- normalizePath(
      bc$output_base %||% dirname(config_path),
      winslash = "/", mustWork = FALSE
    )
    font_family <- (config_ix$plot %||% list())$font_family %||% "Times New Roman"
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
