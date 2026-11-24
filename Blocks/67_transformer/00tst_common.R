###############################################################################
#  00tst_common.R — 71 两阶段 Transformer 共享辅助（prepare / landmark）
###############################################################################

.tst71_root <- function(ctx) ctx$config$project$root %||% getwd()

#' 将插补后展示型结局（如 "AKI_xxx" / "No AKI_xxx"）强制还原为 0/1 整数。
#' Table 1 可用字符串标签；TST prepare / landmark / 训练必须是数值二分类。
.tst71_coerce_binary01 <- function(x, cfg = list()) {
  if (is.null(x)) return(integer(0))
  n <- length(x)
  out <- rep(NA_integer_, n)
  if (is.numeric(x) || is.logical(x)) {
    out <- as.integer(x)
    out[!(out %in% c(0L, 1L))] <- NA_integer_
    return(out)
  }
  xc <- trimws(as.character(x))
  na_mask <- is.na(x) | !nzchar(xc) | toupper(xc) %in% c("NA", "NAN")
  out[na_mask] <- NA_integer_
  xc_l <- tolower(xc)
  pos <- xc %in% c("1") | xc_l %in% c("yes", "y", "true", "dead", "death", "expired")
  neg <- xc %in% c("0") | xc_l %in% c("no", "n", "false", "alive")
  # 展示标签：reference 常以 "No " 开头；analysis 为疾病名
  lbl <- NULL
  if (exists("pipeline_resolve_outcome_display_labels", mode = "function")) {
    lbl <- tryCatch(pipeline_resolve_outcome_display_labels(cfg %||% list()), error = function(e) NULL)
  }
  if (!is.null(lbl)) {
    pos <- pos | (xc == as.character(lbl$analysis %||% ""))
    neg <- neg | (xc == as.character(lbl$reference %||% ""))
  }
  neg <- neg | grepl("^no\\s+", xc_l)
  # 其余非空字符串：若未匹配 reference，且含病名式大写开头，视为事件=1
  rem <- !na_mask & !pos & !neg
  pos[rem] <- TRUE
  out[pos] <- 1L
  out[neg] <- 0L
  out
}

.tst71_ensure_py <- function(root) {
  if (!exists("run_literature_python", mode = "function")) {
    source(file.path(root, "R/python_literature.R"), local = FALSE)
  }
}

.tst71_tst_cfg <- function(ctx) ctx$config$tst_stroke %||% list()

.tst71_epochs <- function(cfg) as.integer(cfg$worker_epochs %||% cfg$epochs %||% 100L)[1L]

.tst71_baseline_epochs <- function(cfg) {
  as.integer(cfg$baseline_epochs %||% cfg$baseline_worker_epochs %||% 20L)[1L]
}

.tst71_patience <- function(cfg) as.integer(cfg$early_stop_patience %||% 15L)[1L]

#' 早停监控指标（默认 val_auc；与 python/two_stage_transformer/train.py 一致）
.tst71_early_stop_monitor <- function(cfg) {
  mon <- tolower(trimws(as.character(cfg$early_stop_monitor %||% "val_auc")[1L]))
  if (!nzchar(mon)) mon <- "val_auc"
  mon
}

.tst71_train_timeout <- function(cfg) as.integer(cfg$python_train_timeout_sec %||% 43200L)[1L]

#' TST 共享流水线铁律：患者级划分必须先于 MICE，且 fit_on=train
.tst71_assert_shared_mi_split_order <- function(pipeline_shared, config) {
  blocks <- as.character((pipeline_shared %||% list())$blocks %||% character(0))
  if (!length(blocks)) return(invisible(TRUE))
  i_split <- match("tst_split", blocks)
  i_imp <- match("imputation", blocks)
  fit_on <- tolower(trimws(as.character(
    ((config %||% list())$imputation %||% list())$fit_on %||% "all"
  )[1L]))
  if (!is.na(i_imp)) {
    if (!identical(fit_on, "train")) {
      stop(
        "TST 铁律：config$imputation$fit_on 必须为 'train'（仅训练集拟合 MICE，",
        "val/test 用 mice(ignore=TRUE) 套用）。当前 fit_on=", fit_on,
        call. = FALSE
      )
    }
    if (is.na(i_split) || i_split > i_imp) {
      stop(
        "TST 铁律：pipeline_shared$blocks 中 tst_split 必须出现在 imputation 之前",
        "（患者级 7:2:1 先于插补，防泄漏）。当前顺序: ",
        paste(blocks, collapse = " → "),
        call. = FALSE
      )
    }
  }
  invisible(TRUE)
}

.tst71_seed <- function(cfg) as.integer((cfg$split %||% list())$seed %||% 42L)[1L]

.tst71_hourly_csv <- function(ctx) {
  path <- ctx$results$tst_timeseries$hourly_long_path %||% ""
  if (nzchar(path) && file.exists(path)) return(path)
  override <- (ctx$config$tst_stroke %||% list())$hourly_long_path %||% ""
  if (nzchar(override) && file.exists(override)) return(override)
  smoke <- file.path(
    .tst71_root(ctx),
    "Output/_smoke_task4_shared/step06_tst_timeseries/Tables/_tst_hourly_long.csv"
  )
  if (file.exists(smoke)) return(smoke)
  NULL
}

.tst71_npz_dir <- function(ctx) file.path(ctx$output_dir_tables, "npz")

.tst71_run_tst_python <- function(root, mode, args, timeout_sec = 1200L) {
  .tst71_ensure_py(root)
  run_literature_python(
    root, mode, args,
    timeout_sec = timeout_sec,
    script = "block_two_stage_transformer.py"
  )
}

.tst71_branch_spec <- function(ctx) {
  cfg  <- .tst71_tst_cfg(ctx)
  unit <- (ctx$config$study_batch %||% list())$active_unit %||% ""
  bm   <- cfg$branch_map %||% list()
  if (nzchar(unit) && unit %in% names(bm)) return(bm[[unit]])
  list(
    python_mode = cfg$python_mode %||% "tst_train_b",
    landmark = cfg$active_landmark %||% 72L,
    model = cfg$baseline_model %||% NULL,
    ablation = cfg$ablation %||% NULL,
    arch = cfg$arch %||% "b"
  )
}

#' Landmark 小时 → 可用天数（24h→1, …, 120h→5）
.tst71_landmark_n_days <- function(landmark_hours) {
  lh <- as.integer(landmark_hours)[1L]
  if (!is.finite(lh) || lh < 1L) lh <- 72L
  max(1L, as.integer(ceiling(lh / 24)))
}

.tst71_shared_split_dir <- function(ctx) {
  # Prefer paths written by tst_split on shared layer
  base <- ctx$config$study_batch$output_base %||% ctx$config$project$output_dir %||% ""
  cand <- c(
    file.path(base, "_shared", "step08_tst_split", "Tables"),
    file.path(dirname(ctx$output_dir %||% ""), "_shared", "step08_tst_split", "Tables"),
    file.path(base, "_shared", "Tables")
  )
  for (p in cand) {
    if (file.exists(file.path(p, "train_ids.csv"))) return(normalizePath(p, winslash = "/", mustWork = FALSE))
  }
  NULL
}

.tst71_write_eligible_ids <- function(ctx, landmark_hours, out_path) {
  ts <- .tst71_tst_cfg(ctx)
  # day_mask_mode：固定 5 天窗 + 窗内短住靠 day_mask；
  # 默认仍按 landmark 做 LOS≥landmark 纳排（对齐 TBI L120：Day1–5 同分母）。
  # 仅当显式 day_mask_all_comers=TRUE 时才「全员进窗、不按 landmark 剔人」（旧 SA-AKI 坑）。
  mask_mode <- isTRUE(ts$day_mask_mode %||% ts$cohort_mask_mode %||% FALSE)
  all_comers <- isTRUE(ts$day_mask_all_comers %||% FALSE)
  if (mask_mode && all_comers) {
    ids <- as.character(ctx$results$tst_timeseries$eligible_ids %||% character(0))
    if (!length(ids)) {
      hl <- as.character(ctx$results$tst_timeseries$hourly_long_path %||% "")[1L]
      if (nzchar(hl) && file.exists(hl)) {
        ids <- unique(as.character(utils::read.csv(hl, nrows = 5e6L, stringsAsFactors = FALSE)[[1]]))
      }
    }
    if (!length(ids)) {
      cohort <- ctx$data$tst_cohort
      if (is.data.frame(cohort) && "tst_patient_id" %in% names(cohort)) {
        ids <- as.character(cohort$tst_patient_id)
      }
    }
    if (!length(ids)) {
      stop("day_mask_all_comers=TRUE 但无 timeseries/cohort 患者 ID", call. = FALSE)
    }
    return(.tst71_flush_eligible_csv(out_path, ids))
  }

  ids <- NULL
  lm_key <- as.character(as.integer(landmark_hours)[1L])
  lid <- ctx$results$landmark_ids
  if (is.list(lid) && lm_key %in% names(lid)) {
    ids <- as.character(lid[[lm_key]])
  }
  if (is.null(ids) || !length(ids)) {
    # Fallback: LOS rule on cohort
    cohort <- ctx$data$tst_cohort
    if (is.data.frame(cohort) && nrow(cohort) && "tst_patient_id" %in% names(cohort)) {
      los_col <- if ("icu_day" %in% names(cohort)) "icu_day" else if ("hosp_day" %in% names(cohort)) "hosp_day" else NA_character_
      if (!is.na(los_col)) {
        need <- .tst71_landmark_n_days(landmark_hours)
        ok <- is.finite(cohort[[los_col]]) & as.numeric(cohort[[los_col]]) >= need
        ids <- as.character(cohort$tst_patient_id[ok])
      }
    }
  }
  if (is.null(ids) || !length(ids)) {
    stop("landmark=", landmark_hours, "h 无可用 eligible IDs（检查 tst_landmark / landmark_ids）", call. = FALSE)
  }
  .tst71_flush_eligible_csv(out_path, ids)
}

.tst71_flush_eligible_csv <- function(out_path, ids) {
  dir.create(dirname(out_path), recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(data.frame(patient = unique(ids), stringsAsFactors = FALSE), out_path, row.names = FALSE)
  # WSL(/mnt/g) → Windows(G:) Python：写完后 sync，避免 system2 立刻读到「文件不存在」
  try(system2("sync", stdout = FALSE, stderr = FALSE), silent = TRUE)
  Sys.sleep(1)
  if (!file.exists(out_path)) {
    stop("eligible IDs 写出后文件不存在: ", out_path, call. = FALSE)
  }
  normalizePath(out_path, winslash = "/", mustWork = TRUE)
}

#' Prepare npz：按 unit landmark 设 n_days、eligible 过滤、共享 split IDs
.tst71_prepare_npz <- function(ctx, root, npz_dir, hourly_csv, seed,
                                    timeout_sec = 1200L, branch = NULL) {
  dir.create(npz_dir, recursive = TRUE, showWarnings = FALSE)
  train_npz <- file.path(npz_dir, "train.npz")
  if (file.exists(train_npz)) return(invisible(train_npz))

  ts <- .tst71_tst_cfg(ctx)
  ts_ts <- ctx$config$tst_timeseries %||% list()
  if (is.null(branch)) branch <- .tst71_branch_spec(ctx)
  landmark <- as.integer(branch$landmark %||% ts$active_landmark %||% 72L)[1L]
  mask_mode <- isTRUE(ts$day_mask_mode %||% ts$cohort_mask_mode %||% FALSE)
  # mask 模式：固定 5 天窗（对齐原文）；否则按 landmark 截断天数
  n_days <- if (mask_mode) {
    as.integer(ts$max_calendar_day %||% ts_ts$max_export_day %||% 5L)[1L]
  } else {
    .tst71_landmark_n_days(landmark)
  }
  n_hours <- as.integer(ts$n_hours %||% ts_ts$n_hours %||% 24L)[1L]
  max_cal <- n_days
  max_cal_cfg <- as.integer(ts$max_calendar_day %||% ts_ts$max_export_day %||% 30L)[1L]
  if (is.finite(max_cal_cfg) && max_cal_cfg > 0L) {
    max_cal <- min(max_cal, max_cal_cfg)
  }

  eligible_path <- file.path(npz_dir, paste0("_eligible_L", landmark, ".csv"))
  eligible_path <- .tst71_write_eligible_ids(ctx, landmark, eligible_path)

  split_dir <- .tst71_shared_split_dir(ctx)

  # Landmark 预测：仅用入院起连续 n_days（不对 landmark 窗外滑窗，防泄漏）
  # mask 模式默认仍允许滑窗；对齐 TBI 时 landmark_allow_sliding=FALSE
  allow_slide <- isTRUE(ts$landmark_allow_sliding %||% ts_ts$landmark_allow_sliding %||% FALSE)
  if (mask_mode && isTRUE(ts$day_mask_all_comers %||% FALSE)) {
    allow_slide <- isTRUE(ts$sliding_window %||% ts_ts$sliding_window %||% TRUE)
  }
  use_sliding <- isTRUE(ts$sliding_window %||% ts_ts$sliding_window %||% TRUE) && allow_slide
  expand_h <- isTRUE(ts$expand_hours %||% ts_ts$expand_hours %||% TRUE)

  args <- c(
    "--out-dir", npz_dir, "--data-path", hourly_csv,
    "--seed", as.character(seed),
    "--n-days", as.character(n_days),
    "--n-hours", as.character(n_hours),
    "--max-calendar-day", as.character(max_cal),
    "--landmark-hours", as.character(landmark),
    "--patient-ids-file", eligible_path
  )
  if (!is.null(split_dir) && nzchar(split_dir)) {
    args <- c(args, "--split-ids-dir", split_dir)
  }
  if (use_sliding) args <- c(args, "--sliding-window") else args <- c(args, "--no-sliding-window")
  if (expand_h) args <- c(args, "--expand-hours") else args <- c(args, "--no-expand-hours")

  cli::cli_alert_info(
    "tst_prepare: landmark={landmark}h → n_days={n_days}, eligible={length(utils::read.csv(eligible_path)$patient)}, sliding={use_sliding}, split_ids={!is.null(split_dir)}, mask_mode={mask_mode}"
  )
  .tst71_run_tst_python(root, "tst_prepare", args, timeout_sec = timeout_sec)
  invisible(train_npz)
}
