###############################################################################
#  tst_split — 患者级 7:2:1 划分（种子固定）+ 可选时间外（证据不足则显式跳过）
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §0 §2
#    §0: "内部分割 患者级随机 7:2:1（对齐原文 Methods）"
#    §0: "时间外 若入院年份可用则跑；否则决策树标注跳过原因"
#    §2 硬约束: "患者级划分必须先于插补/标准化/特征选择；验证/测试只应用训练集参数。"
#
#  时间外证据核查【DONE_WITH_CONCERNS，按证据跳过】：
#    mimic预后数据-all.csv 的 admit_time /
#    icu_intime 为 MIMIC-IV 去标识化的“逐患者随机日期偏移”（同一患者内部时间差真实，
#    但跨患者的绝对年份无意义，样本年份跨度可达 2100s-2200s 逾百年）。这不满足“真实
#    跨患者时间轴”的时间外验证前提，若强行按 admit_time 年份切分会产出无意义甚至误导
#    的“时间外”结果。本块在运行时重新核验年份跨度（不臆造，evidence-bound），跨度超过
#    阈值（默认 50 年）则判定不可用并记录 skip 理由；跨度合理时会执行时间外切分代码路径
#    （保留完整实现，非仅注释占位）。
#
#  防泄漏【硬约束，本块自身不拟合任何参数】：
#    本块只产出 ID 划分；插补/标准化/特征选择等参数必须只用训练集拟合——该约束由
#    下游消费方（tst_train_eval / python prepare.py）负责遵守，此处仅记录约束文本，
#    不在此块内做任何拟合。
#
#  Consumes:
#    ctx$data$tst_cohort、ctx$results$tst_cohort（patient_key/tst_time_zero）
#    ctx$config$tst_stroke$split（train/val/test/seed，默认 0.7/0.2/0.1/42）
#
#  Produces:
#    ctx$data$tst_split = list(train=<ids>, val=<ids>, test=<ids>,
#                               temporal_train=<ids>|NULL, temporal_test=<ids>|NULL)
#    Tables/train_ids.csv / val_ids.csv / test_ids.csv （列名 "patient"）
#    Tables/temporal_train_ids.csv / temporal_test_ids.csv （仅时间外可用时写出）
#    ctx$results$tst_split = list(
#      n_train=, n_val=, n_test=, seed=, ratios=,
#      temporal_available=, temporal_skip_reason=|NULL,
#      no_fit_on_test_constraint=<文本>
#    )
###############################################################################

.tst04_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block = "tst_split", reason = reason, suggestion = suggestion, data_snapshot = snap
  )
  stop("PAUSE_FOR_USER_DECISION: ", reason, " / ", suggestion, call. = FALSE)
}

.tst04_write_ids <- function(ids, path) {
  utils::write.csv(data.frame(patient = ids, stringsAsFactors = FALSE), path, row.names = FALSE)
  path
}

block_tst_split <- function(ctx, ...) {
  cfg <- ctx$config
  cohort <- ctx$data$tst_cohort
  if (is.null(cohort) || !is.data.frame(cohort) || nrow(cohort) == 0L) {
    .tst04_pause(ctx, "tst_split 无 ctx$data$tst_cohort（tst_cohort 未运行或队列为空）",
                 "请先运行 tst_cohort。")
  }
  if (!"tst_patient_id" %in% names(cohort)) {
    .tst04_pause(ctx, "ctx$data$tst_cohort 缺少 tst_patient_id", "检查 tst_cohort 产出。",
                 utils::head(cohort, 5L))
  }

  split_cfg <- cfg$tst_stroke$split %||% list()
  p_train <- as.numeric(split_cfg$train %||% 0.7)[1L]
  p_val   <- as.numeric(split_cfg$val   %||% 0.2)[1L]
  p_test  <- as.numeric(split_cfg$test  %||% 0.1)[1L]
  seed    <- as.integer(split_cfg$seed  %||% 42L)[1L]
  ratio_sum <- p_train + p_val + p_test
  if (abs(ratio_sum - 1) > 1e-6) {
    .tst04_pause(
      ctx, sprintf("split 比例之和 = %.4f（应为 1）", ratio_sum),
      "检查 config$tst_stroke$split 的 train/val/test。"
    )
  }

  ids <- unique(cohort$tst_patient_id)
  n <- length(ids)
  set.seed(seed)
  shuffled <- sample(ids, n, replace = FALSE)
  n_train <- round(n * p_train)
  n_val   <- round(n * p_val)
  n_test  <- n - n_train - n_val

  train_ids <- shuffled[seq_len(n_train)]
  val_ids   <- shuffled[seq.int(n_train + 1L, n_train + n_val)]
  test_ids  <- shuffled[seq.int(n_train + n_val + 1L, n)]

  stopifnot(length(intersect(train_ids, test_ids)) == 0L,
            length(intersect(train_ids, val_ids)) == 0L,
            length(intersect(val_ids, test_ids)) == 0L)

  train_path <- .tst04_write_ids(train_ids, file.path(ctx$output_dir_tables, "train_ids.csv"))
  val_path   <- .tst04_write_ids(val_ids,   file.path(ctx$output_dir_tables, "val_ids.csv"))
  test_path  <- .tst04_write_ids(test_ids,  file.path(ctx$output_dir_tables, "test_ids.csv"))

  cli::cli_alert_success(
    "tst_split: n_train={length(train_ids)} n_val={length(val_ids)} n_test={length(test_ids)} (seed={seed})"
  )

  # ---- 时间外：MIMIC 去标识日期不可用时强制跳过（对齐「原文做地理外推、非时间外」）----
  temporal_available <- FALSE
  temporal_skip_reason <- NA_character_
  temporal_train_ids <- NULL
  temporal_test_ids <- NULL
  temporal_train_path <- NA_character_
  temporal_test_path <- NA_character_

  force_skip_temporal <- isTRUE(cfg$tst_stroke$temporal_force_skip %||% TRUE)
  time_zero <- cohort$tst_time_zero
  if (force_skip_temporal) {
    temporal_skip_reason <- paste0(
      "config$tst_stroke$temporal_force_skip=TRUE：MIMIC 入院时间为去标识偏移，",
      "非真实跨患者时间轴；原文以地理外推为主，本套路时间外强制跳过。"
    )
  } else if (is.null(time_zero) || all(is.na(time_zero))) {
    temporal_skip_reason <- "队列无可用 tst_time_zero（admission_time_column 缺失或全部无法解析）"
  } else {
    years <- suppressWarnings(as.integer(format(time_zero, "%Y")))
    year_span <- suppressWarnings(diff(range(years, na.rm = TRUE)))
    max_year_span <- as.numeric(cfg$tst_stroke$max_plausible_year_span %||% 50)[1L]
    if (!is.finite(year_span)) {
      temporal_skip_reason <- "admission time 年份解析后仍全部为 NA"
    } else if (year_span > max_year_span) {
      temporal_skip_reason <- sprintf(
        "admit/icu 入院年份跨度达 %d 年（%d-%d），超过合理阈值 %d 年——符合 MIMIC-IV 去标识化逐患者随机日期偏移特征，非真实跨患者时间轴，判定时间外验证前提不满足，跳过（见文件头证据说明）。",
        year_span, min(years, na.rm = TRUE), max(years, na.rm = TRUE), max_year_span
      )
    } else {
      temporal_available <- TRUE
      cutoff <- stats::quantile(time_zero, probs = 1 - p_test, na.rm = TRUE, type = 1)
      is_test_time <- !is.na(time_zero) & time_zero >= cutoff
      temporal_test_ids <- cohort$tst_patient_id[is_test_time]
      temporal_train_ids <- cohort$tst_patient_id[!is_test_time]
      temporal_train_path <- .tst04_write_ids(
        temporal_train_ids, file.path(ctx$output_dir_tables, "temporal_train_ids.csv")
      )
      temporal_test_path <- .tst04_write_ids(
        temporal_test_ids, file.path(ctx$output_dir_tables, "temporal_test_ids.csv")
      )
      cli::cli_alert_success(
        "tst_split(temporal): n_train={length(temporal_train_ids)} n_test={length(temporal_test_ids)}（按 tst_time_zero 最近 {round(100*p_test)}% 为 holdout）"
      )
    }
  }
  if (!temporal_available) {
    cli::cli_alert_info("tst_split: 时间外切分跳过 — {temporal_skip_reason}")
  }

  ctx$data$tst_split <- list(
    train = train_ids, val = val_ids, test = test_ids,
    temporal_train = temporal_train_ids, temporal_test = temporal_test_ids
  )

  # 为 imputation(fit_on=train) 物化宽表：train vs (val∪test)
  # 正确做法：只在训练集拟合 MICE；val/test 不各自重拟合，由同一 mice 模型套用
  base <- ctx$data$tst_cohort
  if (!is.null(base) && is.data.frame(base) && nrow(base) > 0L &&
      "tst_patient_id" %in% names(base)) {
    pid <- as.character(base$tst_patient_id)
    hold_ids <- unique(c(as.character(val_ids), as.character(test_ids)))
    ctx$data$train <- base[pid %in% as.character(train_ids), , drop = FALSE]
    ctx$data$test <- base[pid %in% hold_ids, , drop = FALSE]
    ctx$data$val <- base[pid %in% as.character(val_ids), , drop = FALSE]
    cli::cli_alert_info(
      "tst_split: materialized train/test frames for MICE fit_on=train ",
      "(train={nrow(ctx$data$train)}, holdout val∪test={nrow(ctx$data$test)})"
    )
  }

  note_path <- file.path(ctx$output_dir_tables, "Methods_split_denominator_note.txt")
  writeLines(
    c(
      "TST patient-level split and modeling denominators",
      paste0("Split ratios: train=", p_train, " val=", p_val, " test=", p_test, " seed=", seed),
      paste0("Split cohort n (at tst_split): ", n),
      paste0("n_train=", length(train_ids), " n_val=", length(val_ids), " n_test=", length(test_ids)),
      "",
      "A1 Methods wording:",
      "- Patient-level 7:2:1 is performed once on the cohort present at tst_split.",
      "- Landmark L{hours} modeling uses eligible IDs (e.g. LOS>=landmark_days) INTERSECTED with this split;",
      "  therefore test n at L120 (e.g. 515) is ~10% of the L120-eligible subset (~5105), NOT 10% of a later",
      "  larger descriptive cohort if filters differ.",
      "- Do not equate analysis-cohort N (e.g. Table1 after timeseries filters) with the DL train/val/test sum",
      "  without writing the landmark eligibility bridge sentence.",
      "",
      "A2 MICE:",
      "- Downstream imputation MUST use fit_on=train: fit MICE on train IDs only;",
      "  apply to val∪test via mice(ignore=TRUE). Do NOT fit separate MICE on val or test.",
      paste0("Generated: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"))
    ),
    note_path
  )

  ctx$results$tst_split <- list(
    n_train = length(train_ids), n_val = length(val_ids), n_test = length(test_ids),
    seed = seed, ratios = c(train = p_train, val = p_val, test = p_test),
    train_ids_path = train_path, val_ids_path = val_path, test_ids_path = test_path,
    temporal_available = temporal_available,
    temporal_skip_reason = if (temporal_available) NA_character_ else temporal_skip_reason,
    temporal_train_ids_path = temporal_train_path,
    temporal_test_ids_path = temporal_test_path,
    methods_note_path = note_path,
    mi_holdout = "val_union_test",
    no_fit_on_test_constraint = paste0(
      "本块只产出患者级 ID 划分，并物化 ctx$data$train / test(val∪test) 供 MICE；",
      "插补必须 fit_on=train；下游 prepare/标准化只能用 train_ids 拟合参数，",
      "val/test 仅 transform，不得重新拟合。"
    )
  )
  ctx
}

register_block(
  "tst_split", block_tst_split,
  "两阶段 Transformer 卒中：患者级 7:2:1 划分（seed 固定）+ 时间外（证据不足则显式跳过）"
)
