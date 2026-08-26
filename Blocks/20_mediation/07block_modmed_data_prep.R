###############################################################################
#  modmed_data_prep — Yan2026 复现：读 OA medition 数据 + 合并 WQS + 编码
#
#  register_block: "modmed_data_prep"
#  config$modmed_data_prep / config$modmed
###############################################################################

block_modmed_data_prep <- function(ctx, ...) {
  root <- ctx$config$project$repo_root %||% ctx$root %||%
    Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(as.character(root %||% ""))) root <- getwd()
  helper <- file.path(root, "R", "moderated_mediation_process.R")
  if (!file.exists(helper)) {
    stop("缺少 R/moderated_mediation_process.R（root=", root, " cwd=", getwd(), ")", call. = FALSE)
  }
  ctx$root <- root
  source(helper, local = FALSE)
  modmed_ensure_pkgs(c("mediation", "ggplot2", "corrplot"))

  cfg <- ctx$config
  bl <- cfg$modmed_data_prep %||% cfg$modmed %||% list()
  data_path <- bl$merged_rdata %||% cfg$data$rawdata_path
  merged_obj <- bl$merged_obj %||% cfg$data$rawdata_obj %||% "merged"
  wqs_path <- bl$wqs_rdata %||% NULL
  wqs_obj <- bl$wqs_obj %||% "wqs_fit"
  wqs_col <- bl$wqs_col %||% "WQS"
  case_lbl <- bl$case_label %||% cfg$project$analysis_group %||% "Osteoarthritis"
  ref_lbl <- bl$ref_label %||% cfg$project$reference_group %||% "Normal"
  male_lbl <- bl$male_label %||% "Male"

  if (is.null(data_path) || !file.exists(data_path)) {
    stop("modmed_data_prep: 找不到 merged RData: ", data_path, call. = FALSE)
  }
  e <- new.env(parent = emptyenv())
  load(data_path, envir = e)
  if (!merged_obj %in% names(e)) {
    stop("modmed_data_prep: 对象 '", merged_obj, "' 不在 ", data_path, call. = FALSE)
  }
  merged <- e[[merged_obj]]
  if (!is.data.frame(merged)) stop("modmed_data_prep: merged 不是 data.frame", call. = FALSE)

  if (!is.null(wqs_path) && file.exists(wqs_path)) {
    ew <- new.env(parent = emptyenv())
    load(wqs_path, envir = ew)
    if (!wqs_obj %in% names(ew)) {
      stop("modmed_data_prep: 对象 '", wqs_obj, "' 不在 ", wqs_path, call. = FALSE)
    }
    merged <- modmed_merge_wqs(merged, ew[[wqs_obj]], wqs_col = wqs_col)
    cli::cli_alert_success("已合并 {wqs_col}（非 NA = {sum(is.finite(merged[[wqs_col]]))}/{nrow(merged)}）")
  } else {
    cli::cli_alert_warning("未提供 WQS RData，跳过 WQS 合并")
  }

  merged$Group_bin <- modmed_encode_outcome(merged$Group, case_lbl, ref_lbl)
  if ("Gender" %in% names(merged)) {
    merged$Gender_num <- modmed_encode_gender_num(merged$Gender, male_lbl)
  }

  n_case <- sum(merged$Group_bin == 1L, na.rm = TRUE)
  n_ctrl <- sum(merged$Group_bin == 0L, na.rm = TRUE)
  cli::cli_alert_info(
    "modmed_data_prep: n={nrow(merged)}, case={n_case}, ctrl={n_ctrl}"
  )

  ctx$data$cleaned <- merged
  ctx$data$imputed <- merged
  ctx$results$modmed_prep <- list(
    n = nrow(merged),
    n_case = n_case,
    n_ctrl = n_ctrl,
    wqs_col = if (wqs_col %in% names(merged)) wqs_col else NA_character_,
    gender_coding = paste0(male_lbl, "=1"),
    outcome_coding = paste0(case_lbl, "=1;", ref_lbl, "=0")
  )
  ctx
}

register_block("modmed_data_prep", block_modmed_data_prep, "OA Yan2026: 数据准备与 WQS 合并")
