###############################################################################
#  tst_landmark — 24/48/72/96/120h landmark 可预测队列 ID
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §2
#    硬约束: "Landmark：预测时点前已发生结局者不得进入该时点队列；禁止用结局后缺失模式
#    泄漏信息。"
#
#  纳入规则【证据绑定，非臆造】：
#    源数据无逐小时死亡/出科时间戳，仅有 icu_day/hosp_day（住院/ICU 天数，来自
#    mimic预后数据-all.csv，已在 tst_cohort 合并进队列）。用
#      los_days(=icu_day 优先，否则 hosp_day) >= landmark_hours / 24
#    近似满足“预测时点前不得已发生结局”：若患者在到达该 landmark 天数之前已死亡/
#    出科（无论存活还是死亡终点），los_days 必然 < landmark_hours/24，天然被排除出
#    该 landmark 队列，不需要额外的死亡时间戳。【证据不足，仅为近似替代规则，
#    非原文逐小时事件时间轴复刻】——已在此处与 decision tree 中标注。
#
#  Consumes:
#    ctx$data$tst_cohort、ctx$results$tst_cohort（patient_key/outcome_column）
#    ctx$config$tst_stroke$landmarks（默认 24/48/72/96/120）
#
#  Produces:
#    ctx$results$landmark_ids = list("24"=<ids>, "48"=<ids>, "72"=<ids>, "96"=<ids>, "120"=<ids>)
#    ctx$results$tst_landmark = list(landmarks=, los_column=, rule=, summary=<data.frame>)
#    Tables/_tst_landmark_summary.csv （每个 landmark 的 n_eligible / n_death_eligible）
#
#  config$tst_landmark（可选）：pause_enable = TRUE
###############################################################################

local({
  common <- file.path("Blocks/71_two_stage_transformer_stroke/00tst_common.R")
  root_guess <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  cands <- c(
    common,
    file.path(root_guess, common),
    "/mnt/e/01block/01Block-new-Final/Blocks/71_two_stage_transformer_stroke/00tst_common.R"
  )
  hit <- cands[file.exists(cands)][1L]
  if (length(hit) && !is.na(hit)) source(hit, local = FALSE)
})

.tst03_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block = "tst_landmark", reason = reason, suggestion = suggestion, data_snapshot = snap
  )
  stop("PAUSE_FOR_USER_DECISION: ", reason, " / ", suggestion, call. = FALSE)
}

block_tst_landmark <- function(ctx, ...) {
  cfg <- ctx$config
  cohort <- ctx$data$tst_cohort
  if (is.null(cohort) || !is.data.frame(cohort) || nrow(cohort) == 0L) {
    .tst03_pause(ctx, "tst_landmark 无 ctx$data$tst_cohort（tst_cohort 未运行或队列为空）",
                 "请先运行 tst_cohort。")
  }
  outcome_col <- ctx$results$tst_cohort$outcome_column %||% cfg$data$outcome_column %||% "is_hosp_dead"
  if (!"tst_patient_id" %in% names(cohort) || !outcome_col %in% names(cohort)) {
    .tst03_pause(ctx, "ctx$data$tst_cohort 缺少 tst_patient_id 或结局列",
                 "检查 tst_cohort 产出。", utils::head(cohort, 5L))
  }

  los_col <- intersect(c("icu_day", "hosp_day"), names(cohort))[1L]
  if (is.na(los_col) || !length(los_col)) {
    .tst03_pause(
      ctx, "队列无 icu_day/hosp_day，无法应用 landmark 纳入规则（禁止在无住院时长信息下臆造纳排）",
      "检查 tst_cohort 是否已从预后表合并 icu_day/hosp_day 列。"
    )
  }
  los_days <- suppressWarnings(as.numeric(cohort[[los_col]]))
  y01 <- if (exists(".tst71_coerce_binary01", mode = "function")) {
    .tst71_coerce_binary01(cohort[[outcome_col]], cfg)
  } else {
    suppressWarnings(as.integer(as.character(cohort[[outcome_col]])))
  }

  landmarks <- as.integer(cfg$tst_stroke$landmarks %||% c(24L, 48L, 72L, 96L, 120L))
  landmark_ids <- setNames(vector("list", length(landmarks)), as.character(landmarks))
  summary_rows <- vector("list", length(landmarks))

  for (i in seq_along(landmarks)) {
    L <- landmarks[[i]]
    lm_days <- L / 24
    eligible <- !is.na(los_days) & los_days >= lm_days
    ids_L <- cohort$tst_patient_id[eligible]
    landmark_ids[[as.character(L)]] <- ids_L
    n_elig <- length(ids_L)
    n_death_elig <- sum(y01[eligible] == 1L, na.rm = TRUE)
    summary_rows[[i]] <- data.frame(
      landmark_hours = L, landmark_days = lm_days,
      n_eligible = n_elig, n_death_eligible = n_death_elig,
      pct_death = if (n_elig > 0) round(100 * n_death_elig / n_elig, 2) else NA_real_,
      stringsAsFactors = FALSE
    )
    cli::cli_alert_success(
      "tst_landmark {L}h: n_eligible={n_elig} n_death={n_death_elig}"
    )
  }
  summary_df <- do.call(rbind, summary_rows)
  ctx <- save_result(ctx, "tst_landmark_summary", summary_df, "_tst_landmark_summary.csv")

  ctx$results$landmark_ids <- landmark_ids
  ctx$results$tst_landmark <- list(
    landmarks = landmarks,
    los_column = los_col,
    rule = sprintf("eligible iff %s(days) >= landmark_hours/24 (approximate no-leak rule, see file header)", los_col),
    summary = summary_df
  )
  ctx
}

register_block(
  "tst_landmark", block_tst_landmark,
  "两阶段 Transformer 卒中：24/48/72/96/120h landmark 可预测队列 ID（基于 los_days 近似防泄漏规则）"
)
