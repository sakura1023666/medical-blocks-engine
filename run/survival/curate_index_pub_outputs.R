#!/usr/bin/env Rscript
# 清理单指标汇总目录：去重图/表、重编号、双库拼图
# 用法:
#   Rscript run/survival/curate_index_pub_outputs.R \
#     --config "/path/to/config_survival.R" --index APRI

.parse_args <- function(args) {
  opts <- list(config = NULL, index = NULL, root = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--index" && i < length(args)) {
      opts$index <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$config) || !nzchar(opts$config))
    stop("--config 必填", call. = FALSE)
  if (is.null(opts$index) || !nzchar(opts$index))
    stop("--index 必填", call. = FALSE)
  opts
}

script_dir <- dirname(normalizePath(
  sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)[1L]),
  winslash = "/", mustWork = FALSE
))
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
setwd(root)

opts <- .parse_args(commandArgs(trailingOnly = TRUE))
config_path <- normalizePath(opts$config, winslash = "/", mustWork = TRUE)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/dual_db_harmonize.R"))
source(file.path(root, "R/incidence_dual_batch_runner.R"))
source(file.path(root, "R/survival_dual_batch_runner.R"))
combine_src <- file.path(root, "R/dual_db_combine_figures.R")
if (file.exists(combine_src)) source(combine_src, local = FALSE)
source(config_path)
if (exists(".survival_batch_bind_config", mode = "function")) {
  config <- .survival_batch_bind_config(config)
}
if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("请先安装 jsonlite", call. = FALSE)
}

ix <- opts$index
bc <- config$survival_batch %||% config$incidence_batch %||% list()
# 研究目录 = config 所在目录（避免 getwd=引擎根时 output_base 指错）
study_root <- normalizePath(dirname(config_path), winslash = "/", mustWork = TRUE)
output_base <- bc$output_base %||% config$project$output_dir %||% study_root
if (!nzchar(as.character(output_base)[1L]) ||
    !dir.exists(file.path(output_base, "by_index"))) {
  output_base <- study_root
}
index_root <- incidence_batch_find_index_output_dir(output_base, ix, "by_index")
if (!dir.exists(index_root)) {
  parent <- file.path(output_base, "by_index")
  hits <- list.dirs(parent, recursive = FALSE, full.names = TRUE)
  hits <- hits[endsWith(basename(hits), paste0("】", ix))]
  if (length(hits)) index_root <- hits[1L]
}
if (!dir.exists(index_root)) stop("找不到指标目录: ", ix, call. = FALSE)

db_seq <- c("nhanes", "mimic")
db_names <- vapply(db_seq, function(db) dual_db_slot_path_name(config, db), character(1L))

# 图角色去重统一走引擎（含 jin_index_sofa：Fig1=RCS / Fig2=Nomogram）
source(file.path(root, "R/jin_index_sofa_pub.R"), local = FALSE)
dedupe_prognosis_figures_dir <- function(figures_dir, db_names, label = "") {
  invisible(incidence_batch_dedupe_prognosis_figures_dir(figures_dir, config))
}

cli::cli_h1("整理指标发表输出: {ix}")
cli::cli_alert_info("目录: {.file {index_root}}")

# 1) 清理全树 realign 临时文件
table_dirs <- c(
  file.path(index_root, "Tables"),
  vapply(db_seq, function(db) {
    file.path(index_root, dual_db_slot_path_name(config, db), "Tables")
  }, character(1L))
)
for (td in unique(table_dirs)) .incidence_batch_purge_realign_temp_tables(td)

# 2) 各库 Figures 去重 + 固定编号
for (db in db_seq) {
  db_nm <- dual_db_slot_path_name(config, db)
  dedupe_prognosis_figures_dir(
    file.path(index_root, db_nm, "Figures"), db_names, label = db_nm
  )
}

# 3) 清空汇总 Figures（由 mirror + 拼图重建）
agg_figs <- file.path(index_root, "Figures")
if (dir.exists(agg_figs)) {
  old <- list.files(agg_figs, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (length(old)) {
    unlink(old)
    cli::cli_alert_info("已清空汇总 Figures {length(old)} 个，待重建")
  }
}

# 4) 附表去重 + S 号重排（aggregate + 各库）
table_targets <- unique(table_dirs)
for (td in table_targets) {
  if (!dir.exists(td)) next
  incidence_batch_realign_dual_supp_tables(td, config)
  incidence_batch_compact_supp_s_numbers(td, config)
  incidence_batch_shorten_pub_table_names(td, config)
  if (exists("jin_index_sofa_is_pub_scheme", mode = "function") &&
      isTRUE(jin_index_sofa_is_pub_scheme(config)) &&
      exists("jin_index_sofa_curate_tables_dir", mode = "function")) {
    jin_index_sofa_curate_tables_dir(td, index_lab = ix)
  }
}

# 5) mirror 汇总 + 双库拼图 + 图表整理（必须用实际 tagged 目录，非裸 ix 名）
mirror_dual_db_aggregate(root, config, out_root = index_root, dbs = db_seq)
if (exists("dual_db_combine_paired_figures", mode = "function")) {
  tryCatch(
    dual_db_combine_paired_figures(index_root, config),
    error = function(e) cli::cli_alert_warning("双库拼图: {e$message}")
  )
}
incidence_batch_curate_index_pub_outputs(index_root, config, db_seq)
if (exists("incidence_batch_ensure_real_figure1", mode = "function")) {
  tryCatch(
    incidence_batch_ensure_real_figure1(
      index_root = index_root,
      config = config,
      ix = ix,
      db_seq = db_seq,
      project_root = output_base
    ),
    error = function(e) cli::cli_alert_warning("Figure 1 纳排图保障: {e$message}")
  )
}
if (exists("survival_batch_write_index_flowcharts", mode = "function") &&
    exists("incidence_batch_is_prognosis_config", mode = "function") &&
    isTRUE(incidence_batch_is_prognosis_config(config))) {
  tryCatch({
    filter_stats <- if (exists("incidence_batch_filter_stats_from_status", mode = "function")) {
      incidence_batch_filter_stats_from_status(index_root)
    } else {
      list()
    }
    survival_batch_write_index_flowcharts(
      project_root = output_base,
      index_root   = index_root,
      ix           = ix,
      filter_stats = filter_stats,
      db_seq       = db_seq,
      font_family  = (config$plot %||% list())$font_family %||% "Times New Roman",
      config       = config
    )
  }, error = function(e) cli::cli_alert_warning("Figure 1 流程图: {e$message}"))
}

# 清理误写的裸目录 by_index/<ix>（仅当为空壳且无 checkpoint）
bare_ix <- file.path(output_base, "by_index", ix)
if (dir.exists(bare_ix) &&
    normalizePath(bare_ix, winslash = "/", mustWork = FALSE) !=
    normalizePath(index_root, winslash = "/", mustWork = FALSE)) {
  bare_ck <- file.path(output_base, "checkpoints", "by_index", ix)
  has_ck <- dir.exists(bare_ck)
  bare_children <- list.dirs(bare_ix, recursive = FALSE, full.names = FALSE)
  bare_children <- setdiff(bare_children, c("Figures", "Tables"))
  if (!has_ck && !length(bare_children)) {
    unlink(bare_ix, recursive = TRUE)
    cli::cli_alert_info("已删除误建裸目录 {.file {basename(bare_ix)}}")
  }
}

cli::cli_alert_success("整理完成: {ix}")
