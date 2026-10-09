###############################################################################
#  ml_stratified_reference_profile — 原文复刻 profile→build 全流程封装
#
#  register_block: "ml_stratified_reference_profile"
#  依赖: R/ml_reference_paper_profile.R（Task 7 公共模块）
#  典型位置: publication_literature_final 组装阶段（Task 8 CLI 调用；本任务
#  只保证可 source + dry-run 列清单，不跑全量）
#
#  config$ml_stratified_reference_profile = list(
#    enable = TRUE,
#    study_index_root = ".../by_index/【success】SOSM+WPR",  # 真实 attrition/旧表来源（只读）
#    asset_dir = ".../staging/task5/model_assets",           # Task5 冻结资产（S3 审计）
#    out_dir = NULL,   # 缺省 = ctx$output_dir（staging）
#    dry_run = FALSE,
#    table1_vars = NULL,          # list(continuous/categorical/levels)
#    table1_db_frames = NULL      # list(MIMIC_IV=..., eICU=...)；缺省时尝试从
#                                 # ctx$data / checkpoint 槽位读取（Task8 全量再供）
#  )
#
#  读: 两库 attrition CSV（MIMIC_IV/step37、eICU/step28；库身份按目录判定）
#  写: out_dir/Figures/Figure 1. ...pdf、out_dir/Tables/Table 1./S1./S3. xlsx、
#      out_dir/MANIFEST.csv（34 角色完整编号 + reference_source/adaptation/
#      source/denominator/status）
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (!is.null(a)) a else b
}

.ml_srp_root <- function(ctx = NULL) {
  er <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (!nzchar(er)) er <- (ctx$config %||% list())$project$root %||% getwd()
  if (.Platform$OS.type != "windows" && grepl("^[A-Za-z]:/", as.character(er))) {
    er <- paste0("/mnt/", tolower(substr(er, 1L, 1L)), substring(er, 3L))
  }
  normalizePath(as.character(er), winslash = "/", mustWork = FALSE)
}

.ml_srp_ensure <- function(ctx = NULL) {
  if (exists("ml_reference_profile_40537296", mode = "function")) {
    return(invisible(NULL))
  }
  f <- file.path(.ml_srp_root(ctx), "R/ml_reference_paper_profile.R")
  if (!file.exists(f)) stop("缺少参考 profile 模块: ", f, call. = FALSE)
  source(f, local = FALSE)
}

# 定位两库 attrition CSV：优先 config 显式路径；否则在 study_index_root 的
# 库目录下按 stepNN_attrition_flowchart 匹配（文件名槽名不可信，目录定库）。
.ml_srp_find_csv <- function(study_index_root, db_dir, prefer_dir_regex) {
  root <- file.path(study_index_root, db_dir)
  if (!dir.exists(root)) return(NA_character_)
  hits <- list.files(root, pattern = "attrition_flowchart[/\\\\]Tables[/\\\\].*\\.csv$",
                     recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
  hits <- hits[!grepl("image_information", hits)]
  if (!length(hits)) {
    # 更宽：任意 Flowchart_attrition*.csv
    hits <- list.files(root, pattern = "(?i)Flowchart_attrition.*\\.csv$",
                       recursive = TRUE, full.names = TRUE)
  }
  if (!length(hits)) return(NA_character_)
  # 同目录多文件时取 step 号最大的（最新记账）
  steps <- suppressWarnings(as.integer(sub(".*(step\\d+).*", "\\1", hits)))
  steps <- suppressWarnings(as.integer(gsub("step", "", sub(".*(step[0-9]+).*", "\\1", hits))))
  hits <- hits[order(steps, decreasing = TRUE)]
  normalizePath(hits[1], winslash = "/", mustWork = FALSE)
}

#' 公共封装入口（非 ctx 依赖）：dry-run 只列清单；full 模式构建 Figure1 /
#' Table1 / S1 / S3 + MANIFEST。供 Task8 CLI 与 block 共用。
ml_reference_profile_block <- function(dry_run = FALSE,
                                       out_dir = NULL,
                                       study_index_root = NA_character_,
                                       asset_dir = NULL,
                                       db_frames = NULL,
                                       table1_vars = NULL,
                                       ctx = NULL) {
  .ml_srp_ensure(ctx)
  prof <- ml_reference_profile_40537296()
  out_dir <- as.character(out_dir %||%
    (ctx$output_dir %||% file.path(.ml_srp_root(ctx),
                                   ".superpowers/sdd/staging/task7"))[1L])
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  man <- ml_reference_build_manifest(
    profile = prof, out_dir = out_dir,
    study_index_root = study_index_root, asset_dir = asset_dir
  )
  if (isTRUE(dry_run)) {
    return(list(profile = prof, manifest = utils::read.csv(
      man, stringsAsFactors = FALSE, check.names = FALSE),
      manifest_path = man, built_figures = FALSE, built_tables = FALSE))
  }

  figs <- list(); tabs <- list()
  # ---- Figure 1（真实 attrition；缺 CSV → 硬失败，不静默跳过） ----
  if (!is.na(study_index_root) && dir.exists(study_index_root)) {
    mc_cfg <- (ctx$config %||% list())$ml_stratified_reference_profile %||% list()
    mimic_csv <- as.character(mc_cfg$mimic_attrition_csv %||% NA_character_)[1L]
    eicu_csv <- as.character(mc_cfg$eicu_attrition_csv %||% NA_character_)[1L]
    if (is.na(mimic_csv)) {
      mimic_csv <- .ml_srp_find_csv(study_index_root, "MIMIC_IV", "MIMIC")
    }
    if (is.na(eicu_csv)) {
      eicu_csv <- .ml_srp_find_csv(study_index_root, "eICU", "eICU")
    }
    if (is.na(mimic_csv) || is.na(eicu_csv)) {
      stop("ml_stratified_reference_profile: 缺真实 attrition CSV（MIMIC-IV/eICU）",
           "——Figure 1 禁止编造，请检查 study_index_root 路径。", call. = FALSE)
    }
    figs$figure1 <- ml_reference_build_flowchart(mimic_csv, eicu_csv, out_dir)
    tabs$s1 <- ml_reference_build_s1(study_index_root, out_dir)
  } else {
    cli_alert <- if (requireNamespace("cli", quietly = TRUE))
      cli::cli_alert_warning else function(...) invisible(NULL)
    cli_alert("ml_stratified_reference_profile: study_index_root 未提供，跳过 Figure 1/S1。")
  }
  # ---- Table 1（需双库数据帧；缺省从 ctx 槽位尽力取，否则 pending） ----
  if (is.null(db_frames) && !is.null(ctx)) {
    cand_m <- ctx$data$train_all %||% ctx$results$analysis_frame_mimic
    cand_e <- ctx$results$analysis_frame_eicu
    if (!is.null(cand_m) && !is.null(cand_e)) {
      db_frames <- list(MIMIC_IV = cand_m, eICU = cand_e)
    }
  }
  if (!is.null(db_frames)) {
    tabs$table1 <- ml_reference_build_table1(db_frames, out_dir, vars = table1_vars)
  }
  if (!is.null(asset_dir)) {
    tabs$s3 <- ml_reference_build_s3(asset_dir, out_dir)
  }
  # manifest 重建（刷新 ready 状态）
  man <- ml_reference_build_manifest(
    profile = prof, out_dir = out_dir,
    study_index_root = study_index_root, asset_dir = asset_dir
  )
  list(profile = prof,
       manifest = utils::read.csv(man, stringsAsFactors = FALSE, check.names = FALSE),
       manifest_path = man, figures = figs, tables = tabs,
       built_figures = length(figs) > 0L, built_tables = length(tabs) > 0L)
}

block_ml_stratified_reference_profile <- function(ctx, ...) {
  cfg <- ctx$config$ml_stratified_reference_profile %||% list()
  if (!is.null(cfg$enable) && !isTRUE(cfg$enable)) {
    cli::cli_alert_info("ml_stratified_reference_profile$enable 未开，跳过。")
    return(ctx)
  }
  .ml_srp_ensure(ctx)
  study_index_root <- cfg$study_index_root %||% NA_character_
  if (is.na(study_index_root) && !is.null(ctx$config$project$index_root)) {
    study_index_root <- ctx$config$project$index_root
  }
  res <- ml_reference_profile_block(
    dry_run = isTRUE(cfg$dry_run %||% FALSE),
    out_dir = cfg$out_dir %||% ctx$output_dir,
    study_index_root = study_index_root,
    asset_dir = cfg$asset_dir,
    db_frames = cfg$table1_db_frames,
    table1_vars = cfg$table1_vars,
    ctx = ctx
  )
  ctx$results$ml_reference_profile <- res$profile
  ctx$results$ml_reference_manifest <- res$manifest
  ctx$results$ml_reference_manifest_path <- res$manifest_path
  n_ready <- sum(res$manifest$status == "ready")
  cli::cli_alert_success(
    "ml_stratified_reference_profile: {nrow(res$manifest)} 角色清单，ready={n_ready}",
    if (isTRUE(res$built_figures)) "，Figure 1 已构建" else ""
  )
  ctx
}

register_block(
  "ml_stratified_reference_profile",
  block_ml_stratified_reference_profile,
  "原文复刻 profile：Figure 1 双库纳排、Table 1、S1/S3 与完整编号 MANIFEST"
)
