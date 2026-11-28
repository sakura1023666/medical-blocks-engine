###############################################################################
#  multimorbidity_ingest_panel — 课题壳：确认分析面板已构建 / 可选触发重建
#
#  register_block: "multimorbidity_ingest_panel"
#  正式拼装脚本: run/multimorbidity/scripts/build_multimorbidity_panels.R
#  本块在 pipeline 内校验 rawdata 为 long 面板，并把 cleaned/imputed 对齐
#  （文献完整病例，不做 MICE）
###############################################################################

block_multimorbidity_ingest_panel <- function(ctx, ...) {
  cfg <- ctx$config
  mm <- cfg$multimorbidity %||% list()
  data <- ctx$data$raw %||% ctx$data$cleaned
  if (is.null(data) || !is.data.frame(data)) {
    stop("multimorbidity_ingest_panel: 无 raw/cleaned 数据；请先指向 D01_panel_*.RData", call. = FALSE)
  }

  need <- c(
    as.character(cfg$data$id_column %||% mm$id_col %||% "ID")[1L],
    as.character(mm$wave_col %||% "Followup_wave")[1L]
  )
  miss <- setdiff(need, names(data))
  if (length(miss)) {
    stop("multimorbidity_ingest_panel: 面板缺列 ", paste(miss, collapse = ", "), call. = FALSE)
  }

  # 完整病例：关键分析列
  ind <- toupper(trimws(as.character(mm$obesity_indicator %||% "BMI")[1L]))
  exp_a <- if (identical(ind, "WHTR")) "WHtR" else if (identical(ind, "WWI")) "WWI" else "BMI"
  dep <- as.character(mm$depression_score_col %||% "Depression_Score")[1L]
  cog <- as.character(mm$cognition_z_col %||% "Cognition_z")[1L]

  if (identical(ind, "WHTR") && "WHtR_analysis_eligible" %in% names(data)) {
    data <- data[as.integer(data$WHtR_analysis_eligible) == 1L, , drop = FALSE]
  }

  # ELSA WHtR: drop wave 4 (2016 no WC)
  if (identical(ind, "WHTR") && identical(toupper(as.character(cfg$project$database %||% "")[1L]), "ELSA")) {
    wave_col <- as.character(mm$wave_col %||% "Followup_wave")[1L]
    data <- data[as.integer(data[[wave_col]]) %in% c(1L, 2L, 3L), , drop = FALSE]
    mm$waves <- c(1L, 2L, 3L)
    mm$outcome_wave <- 3L
    ctx$config$multimorbidity <- mm
  }

  ok <- rep(TRUE, nrow(data))
  for (cn in c(exp_a, dep, cog)) {
    if (!cn %in% names(data)) {
      cli::cli_alert_warning("ingest: 缺列 {cn}，跳过该列完整病例过滤")
      next
    }
    ok <- ok & is.finite(suppressWarnings(as.numeric(data[[cn]])))
  }
  n_before <- length(unique(data[[need[1L]]]))
  data <- data[ok, , drop = FALSE]
  n_after <- length(unique(data[[need[1L]]]))

  # 文献：不做插补；直接喂给后续块
  ctx$data$raw <- data
  ctx$data$cleaned <- data
  ctx$data$imputed <- data

  out <- file.path(cfg$project$output_dir %||% "Output", "Tables")
  dir.create(out, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(
    data.frame(
      step = c("panel_in", "complete_case_rows"),
      n_id = c(n_before, n_after),
      n_row = c(NA_integer_, nrow(data)),
      obesity_indicator = ind,
      stringsAsFactors = FALSE
    ),
    file.path(out, "Table_S_Ingest_CompleteCase.csv"),
    row.names = FALSE
  )

  cli::cli_alert_success(
    "ingest_panel: {ind} 完整病例 ID {n_before} → {n_after}（行 {nrow(data)}）"
  )
  ctx
}

register_block(
  "multimorbidity_ingest_panel",
  block_multimorbidity_ingest_panel,
  "多病叠加分析面板校验与完整病例（无MICE）"
)
