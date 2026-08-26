#!/usr/bin/env Rscript
# =============================================================================
#  IBD 轨迹预后：按「预后双库」套路生成指标级 / 课题级两库汇总图与表
#
#  - 从 by_index/<ix>/{eicu,mimic}/Tables|Figures 镜像到 by_index/<ix>/Tables|Figures
#  - 成对分库图拼 A/B → 无 -DB 后缀的汇总图
#  - 写出课题 summary_result/table + summary_result/figure
#
#  用法（仓库根）:
#    Rscript run/trajectory_prognosis/run_trajectory_prognosis_ibd_dual_summary.R \
#      --config configs/config_trajectory_prognosis_ibd_batch.R
#    # 仅某一个成功指标:
#    Rscript ... --only-index MCHC
# =============================================================================

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  script_dir <- if (length(f)) {
    dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  } else normalizePath(getwd(), winslash = "/")
  if (basename(script_dir) == "trajectory_prognosis" &&
      basename(dirname(script_dir)) == "run") {
    normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
  } else script_dir
}

.parse_args <- function(args) {
  opts <- list(config = NULL, only_index = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--only-index" && i < length(args)) {
      opts$only_index <- trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]])
      i <- i + 2L
    } else i <- i + 1L
  }
  opts
}

`%||%` <- function(a, b) if (!is.null(a)) a else b

.root <- .init_root()
setwd(.root)
opt <- .parse_args(commandArgs(trailingOnly = TRUE))

source(file.path(.root, "R/utils.R"))
source(file.path(.root, "configs/indices/composite_index_vars.R"))
config_path <- normalizePath(
  opt$config %||% file.path(.root, "configs/config_trajectory_prognosis_ibd_batch.R"),
  winslash = "/", mustWork = TRUE
)
source(config_path)
source(file.path(.root, "R/dual_db_harmonize.R"), local = FALSE)
source(file.path(.root, "R/dual_db_combine_figures.R"), local = FALSE)
source(file.path(.root, "R/trajectory_pub_curate.R"), local = FALSE)
source(file.path(.root, "R/trajectory_paper_tables.R"), local = FALSE)

study_root <- config$project$output_dir
by_index <- file.path(study_root, "by_index")
.stopif <- function(ok, msg) if (!isTRUE(ok)) stop(msg, call. = FALSE)
.stopif(dir.exists(by_index), paste0("缺少 by_index: ", by_index))

# 开启汇总镜像与拼图（本脚本强制）
config$dual_db$mirror_aggregate <- TRUE
config$dual_db$combine_figures <- utils::modifyList(
  list(
    enable = TRUE,
    remove_singles = TRUE,
    drop_missing_overview = TRUE,
    panel_order = "primary_first",
    label_format = "A. {db}"
  ),
  config$dual_db$combine_figures %||% list()
)
config$dual_db$combine_figures$enable <- TRUE

.strip_status_prefix <- function(bn) {
  sub("^【[^】]+】", "", bn)
}

.find_index_dirs <- function(by_index_root, only = NULL) {
  dirs <- list.dirs(by_index_root, recursive = FALSE, full.names = TRUE)
  dirs <- dirs[dir.exists(dirs)]
  out <- list()
  for (d in dirs) {
    bn <- basename(d)
    ix <- .strip_status_prefix(bn)
    if (!is.null(only) && length(only) && !(ix %in% only)) next
    has_e <- dir.exists(file.path(d, "eicu")) || dir.exists(file.path(d, "eICU"))
    has_m <- dir.exists(file.path(d, "mimic")) || dir.exists(file.path(d, "MIMIC"))
    if (!(has_e && has_m)) next
    # 至少一侧已有发表图（curate 后）才汇总
    fig_e <- length(list.files(
      file.path(dual_db_resolve_slot_dir(d, config, "eicu"), "Figures"),
      pattern = "^Figure .*\\.pdf$", ignore.case = TRUE
    ))
    fig_m <- length(list.files(
      file.path(dual_db_resolve_slot_dir(d, config, "mimic"), "Figures"),
      pattern = "^Figure .*\\.pdf$", ignore.case = TRUE
    ))
    if (fig_e < 1L || fig_m < 1L) next
    out[[length(out) + 1L]] <- list(path = d, index = ix, status_dir = bn)
  }
  out
}

.restore_archived_whitelist_tables <- function(db_tab_dir) {
  if (!dir.exists(db_tab_dir)) return(invisible(0L))
  arch <- file.path(db_tab_dir, "_archive")
  if (!dir.exists(arch)) return(invisible(0L))
  want <- list.files(
    arch,
    pattern = "^Table (1|2|S1|S4|S6)-.*\\.xlsx$",
    full.names = TRUE,
    ignore.case = TRUE
  )
  n <- 0L
  for (f in want) {
    dest <- file.path(db_tab_dir, basename(f))
    if (!file.exists(dest)) {
      if (file.copy(f, dest, overwrite = FALSE)) n <- n + 1L
    }
  }
  invisible(n)
}

.finalize_one_index <- function(ix_info) {
  ix <- ix_info$index
  index_root <- ix_info$path
  cli::cli_h2("汇总双库产出: {ix} → {.file {index_root}}")

  for (db in c("eicu", "mimic")) {
    db_dir <- dual_db_resolve_slot_dir(index_root, config, db)
    n_rest <- .restore_archived_whitelist_tables(file.path(db_dir, "Tables"))
    if (n_rest > 0L) {
      cli::cli_alert_info("[{toupper(db)}] 从 _archive 恢复 {n_rest} 张主表")
    }
  }

  # Table 3 双库合并（若有分段 Cox）
  tryCatch(
    trajectory_merge_table3_dual_db(
      index_root, index_name = ix, cut_from_db = "mimic", end_day = 28L
    ),
    error = function(e) cli::cli_alert_warning("Table3 合并跳过: {e$message}")
  )

  # 镜像分库 Tables/Figures → 指标根
  mirror_dual_db_aggregate(
    .root, config, out_root = index_root, dbs = c("eicu", "mimic")
  )

  # 成对拼图 A/B
  tryCatch(
    dual_db_combine_paired_figures(index_root, config),
    error = function(e) cli::cli_alert_warning("拼图跳过: {e$message}")
  )

  n_fig <- length(list.files(file.path(index_root, "Figures"), pattern = "\\.pdf$", ignore.case = TRUE))
  n_tab <- length(list.files(file.path(index_root, "Tables"), pattern = "\\.xlsx$", ignore.case = TRUE))
  cli::cli_alert_success("[{ix}] 指标根 Figures={n_fig} PDF, Tables={n_tab} xlsx")
  invisible(list(index = ix, path = index_root, n_fig = n_fig, n_tab = n_tab))
}

.copy_tree_files <- function(src_dir, dest_dir, pattern) {
  if (!dir.exists(src_dir)) return(invisible(0L))
  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  files <- list.files(src_dir, pattern = pattern, full.names = TRUE, ignore.case = TRUE)
  files <- files[!file.info(files)$isdir]
  n <- 0L
  for (f in files) {
    if (file.copy(f, file.path(dest_dir, basename(f)), overwrite = TRUE)) n <- n + 1L
  }
  invisible(n)
}

.write_study_summary_result <- function(finalized) {
  sum_root <- file.path(study_root, "summary_result")
  tab_dir <- file.path(sum_root, "table")
  fig_dir <- file.path(sum_root, "figure")
  dir.create(tab_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

  # 批量状态表
  batch_csv <- file.path(study_root, "Tables", "Batch_summary_all_indices.csv")
  if (file.exists(batch_csv)) {
    file.copy(batch_csv, file.path(tab_dir, "Batch_summary_all_indices.csv"), overwrite = TRUE)
  }
  prep_csv <- file.path(study_root, "Data", "Flowchart_attrition_prepare.csv")
  if (file.exists(prep_csv)) {
    file.copy(prep_csv, file.path(tab_dir, "Flowchart_attrition_prepare.csv"), overwrite = TRUE)
  }

  # 优先 success 指标；否则取第一个 finalized
  pick <- finalized
  if (!length(pick)) {
    cli::cli_alert_warning("无可用指标汇总，仅写入 Batch_summary")
    return(invisible(sum_root))
  }
  # 若有 MCHC 优先
  ix_names <- vapply(pick, function(x) x$index, character(1L))
  ord <- order(ix_names != "MCHC", ix_names)
  pick <- pick[ord]

  for (item in pick) {
    ix <- item$index
    src_tab <- file.path(item$path, "Tables")
    src_fig <- file.path(item$path, "Figures")
    # 多指标时分子目录；单指标也写一份到根
    dest_tab_ix <- file.path(tab_dir, ix)
    dest_fig_ix <- file.path(fig_dir, ix)
    n1 <- .copy_tree_files(src_tab, dest_tab_ix, "\\.(xlsx|csv)$")
    n2 <- .copy_tree_files(src_fig, dest_fig_ix, "\\.(pdf|png|jpg)$")
    cli::cli_alert_info("summary_result/{ix}: tables={n1}, figures={n2}")
  }

  # 首选指标再平铺一份到 summary_result/table|figure 根（便于直接打开）
  top <- pick[[1L]]
  .copy_tree_files(file.path(top$path, "Tables"), tab_dir, "\\.(xlsx|csv)$")
  .copy_tree_files(file.path(top$path, "Figures"), fig_dir, "\\.(pdf|png|jpg)$")

  # 同步课题根 Tables/Figures（预后习惯）
  root_tab <- file.path(study_root, "Tables")
  root_fig <- file.path(study_root, "Figures")
  dir.create(root_fig, recursive = TRUE, showWarnings = FALSE)
  .copy_tree_files(file.path(top$path, "Tables"), root_tab, "\\.(xlsx|csv)$")
  .copy_tree_files(file.path(top$path, "Figures"), root_fig, "\\.(pdf|png|jpg)$")

  readme <- c(
    "# IBD 轨迹预后 — 双库汇总",
    "",
    paste0("生成时间: ", format(Sys.time(), "%Y-%m-%d %H:%M:%S")),
    "",
    "## 目录",
    "",
    "- `summary_result/table/` — 两库汇总表（分库 `-eICU`/`-MIMIC` + Batch_summary）",
    "- `summary_result/figure/` — 两库拼图（A/B）及分库底稿（若未 remove）",
    "- `by_index/<指标>/Tables|Figures` — 单指标双库汇总（与预后 by_index 一致）",
    "",
    paste0("首选平铺指标: **", top$index, "**"),
    "",
    "## 说明",
    "",
    "- 本课题 Table1 **不做** Gate A 列交集；两库表可列不同。",
    "- 拼图规则同预后 `dual_db_combine_paired_figures`。"
  )
  writeLines(readme, file.path(sum_root, "README.md"), useBytes = TRUE)
  cli::cli_alert_success("课题汇总: {.file {sum_root}}")
  invisible(sum_root)
}

# ── main ─────────────────────────────────────────────────────────────────────
cli::cli_h1("IBD 轨迹预后 — 双库汇总图/表")
targets <- .find_index_dirs(by_index, only = opt$only_index)
if (!length(targets)) {
  # 若用户指定 only 但带【success】前缀目录名
  if (!is.null(opt$only_index)) {
    for (ix in opt$only_index) {
      cands <- Sys.glob(file.path(by_index, paste0("*", ix)))
      for (d in cands) {
        if (dir.exists(file.path(d, "eicu")) || dir.exists(file.path(d, "mimic"))) {
          targets[[length(targets) + 1L]] <- list(
            path = d, index = ix, status_dir = basename(d)
          )
        }
      }
    }
  }
}
.stopif(length(targets) > 0L, "未找到同时具备 eicu+mimic 发表产出的指标目录（请先有成功/可汇总指标）")

cli::cli_alert_info("待汇总指标: {paste(vapply(targets, function(x) x$index, character(1)), collapse=', ')}")

finalized <- lapply(targets, function(ti) {
  tryCatch(
    .finalize_one_index(ti),
    error = function(e) {
      cli::cli_alert_danger("[{ti$index}] 汇总失败: {e$message}")
      NULL
    }
  )
})
finalized <- Filter(Negate(is.null), finalized)

.write_study_summary_result(finalized)
cli::cli_alert_success("完成。共汇总 {length(finalized)} 个指标。")
