#!/usr/bin/env Rscript
# S3 只留「最优切点天数更少」的那一库单图；双库 Table 3 统一用该切点重算。
# 当前：eICU cut=12，MIMIC cut=25 → 共享切点=12，S3 只留 eICU。
# 不跑 run_pipeline（避免 remirror）。
#
#   Rscript run/trajectory_prognosis/repair_gpr_s3_shared_cut.R [study_root]

.root <- {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    d <- dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
    if (basename(d) == "trajectory_prognosis")
      normalizePath(file.path(d, "..", ".."), winslash = "/")
    else normalizePath(getwd(), winslash = "/")
  } else normalizePath(getwd(), winslash = "/")
}
setwd(.root)
study_root <- if (length(commandArgs(TRUE))) commandArgs(TRUE)[[1L]] else
  "/mnt/g/DockerHome/5006/medical-blocks-studies/01_AKI/tr"
ix <- "GPR"
db_seq <- c("eicu", "mimic")
max_fu <- 28L

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "R/study_batch_runner.R"))
source(file.path(.root, "R/trajectory_prognosis_batch_runner.R"))
source(file.path(.root, "R/trajectory_survival_utils.R"))
source(file.path(.root, "R/trajectory_paper_tables.R"))
source(file.path(.root, "R/pub_figure_export.R"))
source(file.path(.root, "Blocks/53_trajectory_prognosis_full/01block_trajectory_piecewise_cox.R"))
source(file.path(study_root, "config.R"))
config$feishu$enable <- FALSE
config_ix <- trajectory_batch_patch_config_for_index(config, ix)

out_ix <- {
  hits <- list.files(file.path(study_root, "by_index"), full.names = TRUE)
  hits[dir.exists(hits) & grepl(paste0("【success】", ix, "$"), basename(hits))][[1L]]
}
root_fig <- file.path(out_ix, "Figures")
root_tab <- file.path(out_ix, "Tables")
ck_base <- file.path(study_root, "checkpoints", "by_index", ix)
align_csv <- file.path(out_ix, "Tables/Summary/class_align_GPR.csv")

# ── 1) 读双库最优切点，取更小者 ──────────────────────────────────────────────
cli::cli_h1("选定共享切点（取最优天数更少的库）")
.best_cut <- function(db) {
  scan <- file.path(out_ix, db, "Tables",
                    sprintf("Table_Piecewise_Cox_CutScan_%s.csv", db))
  if (!file.exists(scan)) {
    hits <- list.files(file.path(out_ix, db), pattern = "Table_Piecewise_Cox_CutScan",
                       recursive = TRUE, full.names = TRUE)
    hits <- hits[!grepl("archive_messy", hits)]
    scan <- hits[1]
  }
  d <- utils::read.csv(scan, stringsAsFactors = FALSE)
  ok <- d[!is.na(d$loglik), , drop = FALSE]
  if ("stable" %in% names(ok)) {
    st <- ok[ok$stable %in% c(TRUE, "TRUE", "true", 1, "1"), , drop = FALSE]
    if (nrow(st)) ok <- st
  }
  as.integer(ok$cut[which.max(ok$loglik)])
}
cuts <- stats::setNames(vapply(db_seq, .best_cut, 1L), db_seq)
cli::cli_alert_info("各库最优: eICU={cuts[['eicu']]}, MIMIC={cuts[['mimic']]}")
cut_shared <- as.integer(min(cuts, na.rm = TRUE))
db_s3 <- names(cuts)[which.min(cuts)]
db_s3_lab <- if (identical(db_s3, "eicu")) "eICU" else "MIMIC"
cli::cli_alert_success("共享切点 cut={cut_shared} 天；S3 只留 {db_s3_lab}")

# 记录
dir.create(file.path(out_ix, "Tables/Summary"), recursive = TRUE, showWarnings = FALSE)
utils::write.csv(
  data.frame(
    db = names(cuts), best_cut = as.integer(cuts),
    shared_cut = cut_shared, s3_source_db = db_s3,
    stringsAsFactors = FALSE
  ),
  file.path(out_ix, "Tables/Summary/piecewise_shared_cut_GPR.csv"),
  row.names = FALSE
)

# ── 2) 双库 Table 3 按共享切点重算 ───────────────────────────────────────────
cli::cli_h1("Table 3 @ cut={cut_shared}")
.unwrap <- trajectory_unwrap_jointlcmm
al <- utils::read.csv(align_csv, stringsAsFactors = FALSE)

.inject_class <- function(ctx, db, unit) {
  e <- new.env(parent = emptyenv())
  load(file.path(unit, "step14_trajectory_jlcm/Data/D01_jlcm_GPR_models.RData"), envir = e)
  m <- .unwrap(e$models_list_with_cov$m2)
  md <- e$model_data_final
  pp <- as.data.frame(m$pprob)
  sub <- al[al$db == db, , drop = FALSE]
  mp <- stats::setNames(as.integer(sub$new_class), as.character(sub$old_class))
  pp$trajectory_class <- trajectory_apply_class_swap(pp$class, mp)
  id_col <- config_ix$data$id_column %||% "subject_id"
  subj <- unique(md[, c(id_col, "subject_id_num")])
  subj <- dplyr::left_join(subj, pp[, c("subject_id_num", "trajectory_class")],
                           by = "subject_id_num")
  for (slot in c("imputed", "cleaned")) {
    if (is.null(ctx$data[[slot]])) next
    tgt <- ctx$data[[slot]]
    tgt[[id_col]] <- as.character(tgt[[id_col]])
    tgt$trajectory_class <- NULL
    tgt$trajectory_class_GPR <- NULL
    tgt <- dplyr::left_join(
      tgt,
      dplyr::mutate(subj, !!id_col := as.character(.data[[id_col]]),
                    trajectory_class_GPR = trajectory_class),
      by = id_col
    )
    # 块优先读 trajectory_class_GPR 或 trajectory_class
    if (!"trajectory_class" %in% names(tgt) || all(is.na(tgt$trajectory_class))) {
      tgt$trajectory_class <- tgt$trajectory_class_GPR
    }
    ctx$data[[slot]] <- tgt
  }
  ctx
}

tabs_combined <- list()
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  unit <- file.path(out_ix, db)
  ck <- file.path(ck_base, db)
  db_cfg <- if (identical(db, "eicu")) config_ix$dual_db$primary else config_ix$dual_db$secondary
  ctx <- study_batch_load_checkpoint_ctx(ck, "trajectory_jlcm")
  ctx <- .inject_class(ctx, db, unit)

  cfg <- config_ix
  cfg$project$database <- db_cfg$name %||% db_lab
  cfg$project$output_dir <- unit
  cfg$project$root <- .root
  cfg$trajectory$skip_class_swap <- TRUE
  cfg$trajectory_piecewise_cox <- modifyList(
    cfg$trajectory_piecewise_cox %||% list(),
    list(
      index_vars = c(ix),
      auto_scan = FALSE,
      landmark_times = cut_shared,
      max_followup = max_fu,
      pause_enable = FALSE,
      pause_on_no_output = FALSE,
      database_label = if (grepl("mimic", tolower(db_lab))) "MIMIC-IV" else "eICU-CRD"
    )
  )
  ctx$config <- cfg
  options(pipeline.database_name = cfg$project$database)

  data <- ctx$data$imputed %||% ctx$data$cleaned
  bl <- cfg$trajectory_piecewise_cox
  time_var <- bl$survival_time_var %||% cfg$survival$time_var %||% "futime"
  event_var <- bl$survival_event_var %||% cfg$survival$event_var %||% "Mortality_28d"
  # 常见别名
  if (!time_var %in% names(data)) {
    for (cand in c("futime", "time_28d", "survival_time", "LOS")) {
      if (cand %in% names(data)) { time_var <- cand; break }
    }
  }
  if (!event_var %in% names(data)) {
    for (cand in c("Mortality_28d", "survival_28d", "fustatus", "event_28d", "death_28d")) {
      if (cand %in% names(data)) { event_var <- cand; break }
    }
  }
  class_col <- paste0("trajectory_class_", ix)
  if (!class_col %in% names(data)) class_col <- "trajectory_class"
  if (!class_col %in% names(data) && "trajectory_class_GPR" %in% names(data))
    class_col <- "trajectory_class_GPR"

  res <- .tpc01_run_one(ctx, data, bl, ix, class_col, time_var, event_var, max_fu, NULL)
  stopifnot(!is.null(res), !is.null(res$table), identical(as.integer(res$cut), cut_shared))
  tabs_combined[[db]] <- res$table
  cli::cli_alert_success("[{db_lab}] cut={res$cut}  HR={paste(unlist(res$table[, grepl('^\\\\(', names(res$table))]), collapse=' | ')}")

  # 分库 Table 3
  out_tab <- file.path(unit, "Tables")
  dir.create(out_tab, recursive = TRUE, showWarnings = FALSE)
  fp_t3 <- file.path(out_tab, paste0("Table 3-", db_lab, ". Time-dependent HR for trajectory classes.xlsx"))
  t3_title <- paste0("Table 3-", db_lab, ". Time-dependent HR for trajectory classes")
  trajectory_export_table3_sci(ctx, res$table, cut_shared, fp_t3, t3_title, end_day = max_fu)
  file.copy(fp_t3, file.path(root_tab, basename(fp_t3)), overwrite = TRUE)
  # CutScan 仍保留原扫描；另写强制切点说明
  utils::write.csv(
    data.frame(shared_cut = cut_shared, source_db_for_cut = db_s3,
               local_best_cut = cuts[[db]], note = "Table3 forced to shared_cut"),
    file.path(out_tab, "Table_Piecewise_Cox_SharedCut.txt"),
    row.names = FALSE
  )
}

# ── 3) S3 只留切点更少库的单图 ───────────────────────────────────────────────
cli::cli_h1("Figure S3 单库（{db_s3_lab}, cut={cut_shared}）")
scan_s3 <- file.path(out_ix, db_s3, "Tables",
                     sprintf("Table_Piecewise_Cox_CutScan_%s.csv", db_s3))
df <- utils::read.csv(scan_s3, stringsAsFactors = FALSE)
# 竖线标共享切点（=该库最优）
p <- .tpc01_cut_search_plot(
  df, cut_shared,
  paste0(ix, " piecewise Cox cut-off search (", db_s3_lab, ")"),
  max_fu, "sans"
)
# 分库正式名
s3_unit <- file.path(out_ix, db_s3, "Figures",
                     sprintf("Figure S3-%s. Piecewise Cox cut point search.pdf", db_s3_lab))
ggplot2::ggsave(s3_unit, p, width = 7.2, height = 4.2, device = grDevices::cairo_pdf)
# 另一库的 S3 正式名去掉（避免误用）
other <- setdiff(db_seq, db_s3)
other_lab <- if (identical(other, "eicu")) "eICU" else "MIMIC"
unlink(file.path(out_ix, other, "Figures",
                 sprintf("Figure S3-%s. Piecewise Cox cut point search.pdf", other_lab)))

# 根目录：单图，非拼图
s3_root <- file.path(root_fig, "pdf/Figure S3. Piecewise Cox cut point search.pdf")
file.copy(s3_unit, s3_root, overwrite = TRUE)
.pub_figure_rasterize_one(
  s3_root,
  file.path(root_fig, "png/Figure S3. Piecewise Cox cut point search.png"),
  file.path(root_fig, "tiff/Figure S3. Piecewise Cox cut point search.tiff"),
  300L, root_hint = .root
)

writeLines(c(
  "# Figure S3. Piecewise Cox cut point search", "",
  "## 图面说明",
  sprintf("仅展示最优切点天数更少的数据库（%s）：逐天扫描分段 Cox 偏对数似然，竖线为最优切点 day %d。", db_s3_lab, cut_shared),
  sprintf("双库各自最优为 eICU=%d、MIMIC=%d；发表统一采用较小切点 day %d，两库 Table 3 均按此切点分段。",
          cuts[["eicu"]], cuts[["mimic"]], cut_shared),
  "",
  "### 图上标注",
  sprintf("- 竖线：最优切点 day %d", cut_shared),
  sprintf("- X 轴：ICU 入科后天数 1–%d；早期不可估 cut 见脚注", max_fu),
  "",
  "## 分析上下文",
  "- 暴露: GPR 轨迹类别（2-class）",
  "- 结局: 28-day mortality",
  sprintf("- Grouping: 2-class JLCM；共享分段切点 day %d（取自 %s）", cut_shared, db_s3_lab),
  "- 数据库: 本图仅 eICU（切点选型库）；Table 3 双库同切点",
  "- 是否拼图: 否（单库）", ""
), file.path(root_fig, "image_information/Figure S3. Piecewise Cox cut point search.md"),
useBytes = TRUE)

cli::cli_alert_success(
  "完成：S3={db_s3_lab} 单图；Table3 双库均 cut={cut_shared}"
)
# 打印 Table3 摘要
for (db in db_seq) {
  db_lab <- if (db == "eicu") "eICU" else "MIMIC"
  fp <- file.path(root_tab, paste0("Table 3-", db_lab, ". Time-dependent HR for trajectory classes.xlsx"))
  d <- suppressMessages(readxl::read_excel(fp, col_names = FALSE))
  cat("\n", db_lab, ":\n", sep = "")
  print(as.data.frame(d), row.names = FALSE)
}
