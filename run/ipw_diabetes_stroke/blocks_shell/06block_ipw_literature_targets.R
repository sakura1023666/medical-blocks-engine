###############################################################################
#  ipw_literature_targets — 文献目标产出清单审计（对应 Jin 2026 图表映射，规格 §2）
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_results = ctx$results（尽力探测；缺失项不阻断，仅计入 failed 清单）
#
#  ipw_literature_targets = list(
#    targets = NULL,                     # NULL → 使用块内默认清单（design §2 映射）
#    audit_filename = "Literature_targets_audit.csv",
#    pause_enable            = TRUE,
#    pause_on_missing_targets = FALSE     # batch 默认 FALSE：缺失只警告 + 写 failed 标记
#  )
#
#  register_block: "ipw_literature_targets"
#  典型位置: ... → cox_binary → ipw_overlap_weights → ipw_literature_targets → ipw_pub_export
#
#  读: ctx$results$*（各已实现 block 的产出标记）
#      ctx$log$block_output_dirs（各 step 子目录 Tables/Figures，用于文件名模式匹配）
#      ctx$root_output_dir（若已镜像，Tables/Figures 亦纳入探测）
#  写: ctx$results$ipw_literature_targets（含 all_found 布尔标记、逐项明细）
#
#  判定口径（found）: 以"文件存在"为核心证据。凡带非空 pattern 的目标，必须在
#  候选目录中命中匹配文件（found_via_file = TRUE）才能判定 found=TRUE；
#  result_key 命中（found_via_result）仅作辅助/诊断字段，不能单独让 found 成立，
#  避免"有结果对象但未实际落盘出图/出表"的假阳性掩盖缺文件。仅当目标未配置
#  pattern（无法做文件核验）时才退化为 found_via_result 兜底。
#  额外输出 found_by_result_only 列，标记"有 result_key 命中但文件缺失"的行，
#  便于单独定位假阳性。
#
#  产出: [固定名] Tables/Literature_targets_audit.csv（不占发表表序号）
#
#  行为: 任一必需项缺失时——
#    pause_on_missing_targets = TRUE  → PAUSE_FOR_USER_DECISION（写 pause_point 后 stop）
#    pause_on_missing_targets = FALSE（默认）→ 仅 cli 警告 + ctx$results$ipw_literature_targets$failed = TRUE
#
#  pause: config$ipw_literature_targets$pause_enable
###############################################################################

.lt06_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.lt06_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 10L) else {
    data.frame(note = "no snapshot")
  }
  ctx$results$pause_point <- list(
    block = "ipw_literature_targets",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ipw_literature_targets halted. See ctx$results$pause_point. / ",
    "文献目标缺失，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}

# 默认目标清单：对应 docs/superpowers/specs/2026-07-21-ipw-diabetes-stroke-batch-design.md §2
.lt06_default_targets <- function() {
  data.frame(
    key = c(
      "Figure_1_Flowchart", "Table_1_Baseline_IPW", "Figure_2_IPW_KM",
      "Figure_3_Subgroup_Forest", "Figure_4_Subgroup_KM", "Figure_5_STEPP",
      "Figure_S1_Missing", "Figure_S2_PS_SMD", "Figure_S3_Unweighted_KM",
      "Figure_S4_Calibration_ROC",
      "Table_S1_Uno_Cindex", "Table_S2_MI_Baseline",
      "Table_S3_Univariate", "Table_S4_VIF"
    ),
    description = c(
      "CONSORT flowchart of patient selection",
      "Baseline characteristics before/after sIPTW (Jin Table 1 header)",
      "IPW-weighted KM of 28-day mortality",
      "Subgroup forest plot + P-interaction",
      "Key subgroup (age) KM curves",
      "STEPP curve for composite risk index",
      "Supplementary missing-value overview (project S1)",
      "Supplementary PS distribution + SMD Love (aligns Jin Fig.S1; project S2)",
      "Supplementary unweighted KM curves (aligns Jin Fig.S2; project S3)",
      "Supplementary calibration + ROC (aligns Jin Fig.S3; project S4)",
      "Uno concordance index at 28-day (aligns Jin Table S1)",
      "Baseline before/after multiple imputation",
      "Univariate regression analysis",
      "Multicollinearity VIF screen"
    ),
    pattern = c(
      "Figure[ _]?1|Figure_1|Flowchart",
      "Table[ _]?1.*sIPTW|before and after sIPTW",
      "Figure[ _]?2|IPW.?weighted|Weighted.*Kaplan",
      "Subgroup.*Forest|Forest.*Subgroup",
      "Figure[ _]?4.*[Kk]aplan|Subgroup.*[Kk]aplan|by age",
      "STEPP",
      "Figure[ _]?S1.*[Mm]issing|[Mm]issing.*[Oo]verview|Figure Missing",
      "propensity score|PS.*SMD|SMD.*Love|standardized mean difference|Figure[ _]?S2",
      "Unweighted.*[Kk]aplan|Unweighted.*KM|Figure[ _]?S3",
      "Calibration|ROC|receiver operating|Figure[ _]?S4",
      "Uno|concordance index",
      "Table[ _]?S2.*multiple imputation|before and after multiple imputation",
      "Table[ _]?S3.*[Uu]nivariate|Univariate Regression",
      "Table[ _]?S4.*[Mm]ulticollinearity|VIF"
    ),
    result_key = c(
      "ipw_diabetes_flowchart", "iptw_balance_table", "ipw_weighted_km_pub",
      "subgroup_treatment_forest", "ipw_subgroup_km_pub", "stepp_prognosis",
      "imputation_missing_figure", "iptw_ps_smd_figure", "ipw_weighted_km_pub",
      "ipw_surv_calibration_roc", "ipw_surv_calibration_roc",
      "imputation", "univariate_prognosis", "multicollinearity_screen"
    ),
    stringsAsFactors = FALSE
  )
}

.lt06_candidate_dirs <- function(ctx) {
  dirs <- character(0)
  bod <- ctx$log$block_output_dirs %||% list()
  for (d in bod) {
    if (is.character(d) && nzchar(d)) dirs <- c(dirs, file.path(d, "Tables"), file.path(d, "Figures"))
  }
  root <- ctx$root_output_dir %||% NULL
  if (!is.null(root) && nzchar(root)) dirs <- c(dirs, file.path(root, "Tables"), file.path(root, "Figures"))
  unique(dirs[dir.exists(dirs)])
}

.lt06_file_found <- function(pattern, dirs) {
  if (is.na(pattern) || !nzchar(pattern) || !length(dirs)) return(FALSE)
  for (d in dirs) {
    hits <- tryCatch(
      list.files(d, pattern = pattern, ignore.case = TRUE, full.names = FALSE),
      error = function(e) character(0)
    )
    if (length(hits)) return(TRUE)
  }
  FALSE
}

block_ipw_literature_targets <- function(ctx, ...) {
  cfg <- ctx$config
  bl_cfg <- cfg$ipw_literature_targets %||% list()

  targets <- bl_cfg$targets
  if (is.null(targets) || !is.data.frame(targets) || !nrow(targets)) {
    targets <- .lt06_default_targets()
  }

  dirs <- .lt06_candidate_dirs(ctx)
  targets$found_via_result <- FALSE
  targets$found_via_file <- FALSE
  targets$has_pattern <- FALSE
  for (i in seq_len(nrow(targets))) {
    rk <- targets$result_key[i]
    if (!is.na(rk) && nzchar(rk)) {
      targets$found_via_result[i] <- !is.null(ctx$results[[rk]])
    }
    pat <- targets$pattern[i]
    targets$has_pattern[i] <- !is.na(pat) && nzchar(trimws(as.character(pat)))
    targets$found_via_file[i] <- .lt06_file_found(pat, dirs)
  }
  # found 判定：带 pattern 的目标必须"文件存在"才算 found，result_key 不可单独
  # 掩盖缺文件；仅无 pattern（无法做文件核验）的目标才退化为 result_key 兜底。
  targets$found <- ifelse(
    targets$has_pattern,
    targets$found_via_file,
    targets$found_via_result | targets$found_via_file
  )
  # 辅助诊断列：有 result_key 命中但文件缺失（假阳性来源），便于单独定位。
  targets$found_by_result_only <- targets$found_via_result & !targets$found_via_file
  targets$status <- ifelse(targets$found, "PASS", "MISSING")

  missing_rows <- targets[!targets$found, , drop = FALSE]
  all_found <- !nrow(missing_rows)
  result_only_rows <- targets[targets$found_by_result_only, , drop = FALSE]

  out_dir <- ctx$output_dir_tables %||% file.path(ctx$output_dir, "Tables")
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  audit_fn <- as.character(bl_cfg$audit_filename %||% "Literature_targets_audit.csv")[1L]
  audit_path <- file.path(out_dir, audit_fn)
  tryCatch(
    utils::write.csv(
      targets[, c(
        "key", "description", "status", "found_via_result", "found_via_file",
        "found_by_result_only", "has_pattern", "pattern"
      )],
      audit_path, row.names = FALSE
    ),
    error = function(e) cli::cli_alert_warning("文献目标审计表写出失败: {e$message}")
  )
  if (exists("mirror_pub_output_to_root", mode = "function")) {
    mirror_pub_output_to_root(ctx, audit_path)
  }

  if (!all_found) {
    cli::cli_alert_warning(
      "ipw_literature_targets: {nrow(missing_rows)} 项缺失: {paste(missing_rows$key, collapse = ', ')}"
    )
    if (.lt06_should_pause(bl_cfg, "pause_on_missing_targets", FALSE)) {
      .lt06_pause(
        ctx,
        paste0("文献目标缺失 ", nrow(missing_rows), " 项: ", paste(missing_rows$key, collapse = ", ")),
        "检查对应 block 是否已在 pipeline 中运行并成功产出文件。",
        missing_rows
      )
    }
  } else {
    cli::cli_alert_success("ipw_literature_targets: 全部 {nrow(targets)} 项目标均已找到")
  }
  if (nrow(result_only_rows)) {
    cli::cli_alert_warning(
      "ipw_literature_targets: {nrow(result_only_rows)} 项仅命中 result_key 但未命中文件（已按 MISSING 处理，见 found_by_result_only）: {paste(result_only_rows$key, collapse = ', ')}"
    )
  }

  ctx$results$ipw_literature_targets <- list(
    table = targets,
    all_found = all_found,
    failed = !all_found,
    missing = missing_rows$key,
    found_by_result_only = result_only_rows$key,
    audit_path = audit_path
  )
  ctx
}

register_block(
  "ipw_literature_targets",
  block_ipw_literature_targets,
  "文献目标产出清单审计（Literature_targets_audit.csv）"
)
