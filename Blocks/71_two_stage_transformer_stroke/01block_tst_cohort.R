###############################################################################
#  tst_cohort — 缺血性脑卒中两阶段 Transformer：dabiao 卒中纳排 / 院内死亡 / 时间零点
#
#  依据: docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md §2 §4
#
#  卒中定义源【2026-07-28 纠正】：
#    dabiao.csv（subject_id / stay_id / hadm_id，n=3347）才是缺血性卒中 ICU stay 名单。
#    baseline + 预后宽表是更大的 MIMIC ICU 池（~65k），必须用 dabiao 内连接后才进入下游。
#    审计：dabiao.stay_id ∩ 预后.stay_id = 3347/3347；院内死亡 606/3347（~18.1%）。
#
#  ID 映射：baseline$ID 与预后 subject_id 重叠 100%；stay_id 为长表/预后主键；本数据 1 subject : 1 stay。
#
#  管线顺序【2026-07-28 纠正】：
#    data_clean → column_mapping → tst_cohort(dabiao∩预后) → tst_timeseries(≥2 天纵向)
#    → imputation(缺失>40% 删列) → baseline_binary → tst_landmark → tst_split
#    禁止全库插补后再 merge。本块读 cleaned（尚未插补），写回 cleaned 供下游。
#
#  Consumes: ctx$data$cleaned %||% ctx$data$mapped %||% ctx$data$raw
#            （column_mapping 之后、imputation 之前）
#
#  Produces:
#    ctx$data$tst_cohort / ctx$data$cleaned  合并 + 纳排后的分析队列（含结局列）
#    ctx$results$tst_cohort = list(...)
#    Tables/_tst_cohort_flowchart.csv
#
#  config$data 需要：
#    dabiao_path（卒中 stay 名单，必需）、baseline_id_column、id_column、
#    prognosis_path、outcome_column、admission_time_column
#  config$tst_cohort（可选）：
#    min_age = 18、id_overlap_pause_threshold = 0.5、
#    dabiao_join_key = "stay_id"（候选 subject_id/stay_id/hadm_id）、pause_enable
###############################################################################

.tst01_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- data_snapshot
  if (is.null(snap)) {
    snap <- data.frame(note = "no snapshot")
  } else if (!is.data.frame(snap)) {
    snap <- utils::head(as.data.frame(snap), 5L)
  } else {
    snap <- utils::head(snap, 5L)
  }
  ctx$results$pause_point <- list(
    block = "tst_cohort", reason = reason, suggestion = suggestion, data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ", reason, " / ", suggestion,
    call. = FALSE
  )
}

.tst01_read_csv <- function(path, label = "csv") {
  if (!nzchar(path %||% "") || !file.exists(path)) {
    stop("tst_cohort: ", label, " 无效或不存在: ", path, call. = FALSE)
  }
  if (requireNamespace("data.table", quietly = TRUE)) {
    as.data.frame(data.table::fread(path, encoding = "UTF-8", showProgress = FALSE))
  } else {
    utils::read.csv(path, stringsAsFactors = FALSE, fileEncoding = "UTF-8")
  }
}

.tst01_read_prognosis <- function(path) {
  .tst01_read_csv(path, "prognosis_path")
}

.tst01_read_dabiao <- function(path) {
  .tst01_read_csv(path, "dabiao_path")
}

#' 用重叠计数（不臆造）在候选列中挑出与 baseline id 重叠率最高的预后表 join key
.tst01_best_id_key <- function(baseline_ids, prognosis, candidates) {
  candidates <- intersect(candidates, names(prognosis))
  if (!length(candidates)) return(NULL)
  n_bl <- length(unique(baseline_ids))
  scored <- lapply(candidates, function(cand) {
    v <- suppressWarnings(as.numeric(prognosis[[cand]]))
    ov <- length(intersect(unique(baseline_ids), unique(v)))
    list(key = cand, overlap_n = ov, overlap_pct = ov / max(1L, n_bl))
  })
  scored[[which.max(vapply(scored, function(s) s$overlap_pct, numeric(1)))]]
}

block_tst_cohort <- function(ctx, ...) {
  cfg    <- ctx$config
  dc     <- cfg$data %||% list()
  bl_cfg <- cfg$tst_cohort %||% list()

  data <- ctx$data$cleaned %||% ctx$data$mapped %||% ctx$data$raw
  if (is.null(data) || !is.data.frame(data)) {
    .tst01_pause(
      ctx, "tst_cohort 无输入数据（ctx$data$cleaned/mapped/raw 均为空）",
      "请先运行 data_clean / column_mapping。本块必须在 imputation 之前（先 merge 再插补）。"
    )
  }
  n_in <- nrow(data)

  baseline_id_col <- as.character(dc$baseline_id_column %||% "ID")[1L]
  if (!baseline_id_col %in% names(data)) {
    .tst01_pause(
      ctx, paste0("baseline_id_column 不在数据中: ", baseline_id_col),
      "检查 config$data$baseline_id_column 或上游列名映射（column_mapping）。",
      utils::head(data, 5L)
    )
  }
  baseline_ids <- suppressWarnings(as.numeric(data[[baseline_id_col]]))

  dabiao_path <- as.character(dc$dabiao_path %||% dc$stroke_id_path %||% "")[1L]
  if (!nzchar(dabiao_path)) {
    .tst01_pause(
      ctx, "缺少 config$data$dabiao_path（缺血性卒中 stay 名单）",
      "请指向 data/dabiao.csv（列：subject_id, stay_id, hadm_id）。"
    )
  }
  dabiao <- .tst01_read_dabiao(dabiao_path)
  n_dabiao <- nrow(dabiao)
  dabiao_key_cfg <- as.character(bl_cfg$dabiao_join_key %||% "stay_id")[1L]
  dabiao_key_cands <- unique(c(dabiao_key_cfg, "stay_id", "subject_id", "hadm_id"))
  dabiao_key <- dabiao_key_cands[dabiao_key_cands %in% names(dabiao)][1L]
  if (is.na(dabiao_key) || !nzchar(dabiao_key %||% "")) {
    .tst01_pause(
      ctx, "dabiao.csv 缺少 stay_id / subject_id / hadm_id",
      "核对 dabiao_path 表头。", utils::head(dabiao, 5L)
    )
  }
  dabiao_ids <- unique(suppressWarnings(as.numeric(dabiao[[dabiao_key]])))
  dabiao_ids <- dabiao_ids[!is.na(dabiao_ids)]
  cli::cli_alert_info(
    "tst_cohort: dabiao n={n_dabiao}，join_key={dabiao_key}，unique_ids={length(dabiao_ids)}"
  )

  prog_path <- as.character(dc$prognosis_path %||% "")[1L]
  prognosis <- .tst01_read_prognosis(prog_path)

  outcome_col <- as.character(dc$outcome_column %||% "is_hosp_dead")[1L]
  if (!outcome_col %in% names(prognosis)) {
    .tst01_pause(
      ctx, paste0("预后表缺少 outcome_column: ", outcome_col),
      "核对 config$data$outcome_column 与 prognosis_path 文件表头是否一致。",
      utils::head(prognosis, 5L)
    )
  }

  id_col_cfg <- as.character(dc$id_column %||% "stay_id")[1L]
  candidates <- unique(c(id_col_cfg, "subject_id", "stay_id", "hadm_id"))
  best <- .tst01_best_id_key(baseline_ids, prognosis, candidates)
  if (is.null(best)) {
    .tst01_pause(
      ctx, "预后表未找到任何 subject_id / stay_id / hadm_id 候选列",
      "核对 prognosis_path 表头与 config$data$id_column。", utils::head(prognosis, 5L)
    )
  }
  overlap_threshold <- as.numeric(bl_cfg$id_overlap_pause_threshold %||% 0.5)[1L]
  if (best$overlap_pct < overlap_threshold) {
    .tst01_pause(
      ctx,
      sprintf(
        "baseline_id_column(%s) 与预后表最佳候选 key(%s) 重叠率仅 %.1f%%，低于阈值 %.0f%%，禁止臆造 ID 映射。",
        baseline_id_col, best$key, 100 * best$overlap_pct, 100 * overlap_threshold
      ),
      "人工核实 baseline ID 与预后表/长表 ID 体系的对应关系后在 config$data 中显式指定，或调整 config$tst_cohort$id_overlap_pause_threshold。",
      utils::head(prognosis, 5L)
    )
  }
  matched_key <- best$key
  cli::cli_alert_success(
    "tst_cohort: ID 映射证据 baseline.{baseline_id_col} == prognosis.{matched_key} 重叠 {round(100 * best$overlap_pct, 1)}% ({best$overlap_n}/{length(unique(baseline_ids))})"
  )

  prognosis$.tst_join_key <- suppressWarnings(as.numeric(prognosis[[matched_key]]))
  data$.tst_join_key <- baseline_ids

  keep_prog_cols <- unique(c(
    ".tst_join_key", "subject_id", "stay_id", "hadm_id", outcome_col,
    intersect(c("admit_time", "icu_intime", "disch_time", "icu_outtime",
                "hosp_day", "icu_day"), names(prognosis))
  ))
  keep_prog_cols <- intersect(keep_prog_cols, names(prognosis))
  prog_small <- prognosis[, keep_prog_cols, drop = FALSE]

  # 若同一 join key 存在多条预后记录（多次住院/多次 ICU），取入院时间最早的一条作为
  # “时间零点”（spec §2：时间零点 = 首次 hospital/ICU 到达）。本数据审计显示两侧唯一值
  # 均为 65366（1 subject : 1 stay），此去重分支通用性防御，非本次数据实际触发路径。
  admit_col <- intersect(c("admit_time", "icu_intime"), names(prog_small))[1L]
  if (length(admit_col) && !is.na(admit_col) && anyDuplicated(prog_small$.tst_join_key)) {
    ord <- order(prog_small$.tst_join_key, suppressWarnings(as.POSIXct(prog_small[[admit_col]])))
    prog_small <- prog_small[ord, , drop = FALSE]
    prog_small <- prog_small[!duplicated(prog_small$.tst_join_key), , drop = FALSE]
  }

  merged <- merge(data, prog_small, by = ".tst_join_key", all.x = TRUE)
  matched <- !is.na(merged[[outcome_col]])
  n_id_matched <- sum(matched)

  # —— dabiao 卒中 stay 内连接（必需；禁止用全库 ICU 冒充卒中）——
  dabiao_col_in_merged <- dabiao_key
  if (!dabiao_col_in_merged %in% names(merged)) {
    # dabiao 按 stay_id，但预后 join 后若只有 subject_id：尝试用 dabiao 的 subject_id
    alt <- dabiao_key_cands[dabiao_key_cands %in% names(merged)][1L]
    if (is.na(alt) || !nzchar(alt %||% "")) {
      .tst01_pause(
        ctx,
        sprintf("合并预后后无 dabiao join 列（需要 %s）", paste(dabiao_key_cands, collapse = "/")),
        "检查预后表是否带出 stay_id/subject_id。",
        utils::head(merged, 5L)
      )
    }
    dabiao_col_in_merged <- alt
    dabiao_ids <- unique(suppressWarnings(as.numeric(dabiao[[dabiao_col_in_merged]])))
    dabiao_ids <- dabiao_ids[!is.na(dabiao_ids)]
    dabiao_key <- dabiao_col_in_merged
  }
  merged_ids <- suppressWarnings(as.numeric(merged[[dabiao_col_in_merged]]))
  in_dabiao <- matched & !is.na(merged_ids) & (merged_ids %in% dabiao_ids)
  n_dabiao_matched <- sum(in_dabiao)
  if (n_dabiao_matched == 0L) {
    .tst01_pause(
      ctx,
      sprintf("dabiao 与合并表按 %s 重叠为 0", dabiao_col_in_merged),
      "核对 dabiao_path 与预后/baseline ID 是否同一体系。",
      utils::head(dabiao, 5L)
    )
  }
  cli::cli_alert_success(
    "tst_cohort: dabiao 内连接 {dabiao_col_in_merged} → {n_dabiao_matched}/{n_dabiao}（相对 dabiao）; 相对 baseline-matched {n_dabiao_matched}/{n_id_matched}"
  )
  merged <- merged[in_dabiao, , drop = FALSE]
  matched <- rep(TRUE, nrow(merged))

  admission_col_cfg <- as.character(dc$admission_time_column %||% "icu_intime")[1L]
  merged$tst_time_zero <- if (admission_col_cfg %in% names(merged)) {
    suppressWarnings(as.POSIXct(merged[[admission_col_cfg]]))
  } else {
    as.POSIXct(rep(NA, nrow(merged)))
  }

  min_age <- as.numeric(bl_cfg$min_age %||% 18)[1L]
  age_col <- if ("Age" %in% names(merged)) "Age" else NULL
  if (is.null(age_col)) {
    cli::cli_alert_warning("tst_cohort: 数据无 Age 列，跳过年龄纳排（【证据不足】不臆造年龄）")
    age_ok <- rep(TRUE, nrow(merged))
  } else {
    age_ok <- !is.na(merged[[age_col]]) & merged[[age_col]] >= min_age
  }
  n_age_ok <- sum(age_ok)

  outcome_vals <- suppressWarnings(as.numeric(merged[[outcome_col]]))
  outcome_valid <- outcome_vals %in% c(0, 1)

  keep <- age_ok & outcome_valid
  n_outcome_valid <- sum(keep)

  cohort <- merged[keep, , drop = FALSE]
  cohort[[outcome_col]] <- as.integer(outcome_vals[keep])
  cohort$.tst_join_key <- NULL
  n_out <- nrow(cohort)

  if (n_out == 0L) {
    .tst01_pause(
      ctx, "纳排后队列为空（0 名患者）",
      "检查 ID 映射 key、min_age、outcome_column 取值范围是否符合预期。",
      utils::head(merged, 5L)
    )
  }
  n_death <- sum(cohort[[outcome_col]] == 1L)
  if (n_death == 0L || n_death == n_out) {
    cli::cli_alert_warning(
      "tst_cohort: 结局列单一水平（n_death={n_death}/{n_out}），下游 baseline_binary/二分类建模将无法进行。"
    )
  }

  # 供下游 lab-long 关联使用的稳定患者 key：优先预后表 stay_id（长表主键），
  # 否则退回 baseline_id_column（【证据不足】需人工确认时可切换）。
  patient_key <- if ("stay_id" %in% names(cohort)) "stay_id" else baseline_id_col
  cohort$tst_patient_id <- cohort[[patient_key]]

  ctx$data$tst_cohort <- cohort
  # 写回 cleaned，供后续 tst_timeseries / imputation / baseline 使用（此时尚未插补）
  ctx$data$cleaned <- cohort
  if (!is.null(ctx$data$mapped)) ctx$data$mapped <- cohort

  flow <- data.frame(
    stage = c(
      "baseline_n_in", "id_matched_to_prognosis", "dabiao_stroke_inner_join",
      "age_ge_min_age", "outcome_valid_0_1", "final_cohort_n_out"
    ),
    n = c(n_in, n_id_matched, n_dabiao_matched, n_age_ok, n_outcome_valid, n_out),
    stringsAsFactors = FALSE
  )
  ctx <- save_result(ctx, "tst_cohort_flowchart", flow, "_tst_cohort_flowchart.csv")

  ctx$results$tst_cohort <- list(
    n_in = n_in, n_id_matched = n_id_matched, n_dabiao = n_dabiao,
    n_dabiao_matched = n_dabiao_matched, dabiao_path = dabiao_path,
    dabiao_join_key = dabiao_key,
    n_age_ok = n_age_ok, n_outcome_valid = n_outcome_valid,
    n_out = n_out, n_death = n_death,
    id_map_rule = sprintf(
      "baseline.%s == prognosis.%s (overlap=%.3f, n=%d/%d); dabiao.%s inner-join",
      baseline_id_col, matched_key, best$overlap_pct, best$overlap_n,
      length(unique(baseline_ids)), dabiao_key
    ),
    baseline_id_column = baseline_id_col,
    matched_prognosis_key = matched_key,
    overlap_pct = best$overlap_pct,
    outcome_column = outcome_col,
    min_age = min_age,
    patient_key = patient_key,
    flowchart = flow
  )
  cli::cli_alert_success(
    "tst_cohort: n_in={n_in} -> prog={n_id_matched} -> dabiao={n_dabiao_matched} -> age_ok={n_age_ok} -> outcome_valid={n_outcome_valid} -> n_out={n_out} (n_death={n_death})"
  )
  ctx
}

register_block(
  "tst_cohort", block_tst_cohort,
  "两阶段 Transformer 卒中：dabiao 纳排 + 院内死亡结局合并 + 时间零点（R 实现，evidence-bound ID 映射）"
)
