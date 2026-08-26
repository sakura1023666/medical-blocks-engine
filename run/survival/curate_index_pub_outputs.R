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

.prognosis_figure_role <- function(bn) {
  bn <- as.character(bn)[1L]
  if (grepl("Missing\\s*Value\\s*Overview", bn, ignore.case = TRUE)) return("drop")
  if (grepl("Flowchart|Inclusion exclusion", bn, ignore.case = TRUE)) return("fig1")
  if (grepl("RCS Analysis|RCS of|Restricted Cubic", bn, ignore.case = TRUE)) return("fig2_rcs")
  if (grepl("Kaplan", bn, ignore.case = TRUE)) return("fig3_km")
  if (grepl("Subgroup Forest", bn, ignore.case = TRUE)) return("fig4_subgroup")
  if (grepl("Cutoff Point|maxstat", bn, ignore.case = TRUE)) return("s1_cutoff")
  if (grepl("Boxplot", bn, ignore.case = TRUE)) return("s2_boxplot")
  if (grepl("Mediation|mediator|path diagram", bn, ignore.case = TRUE)) return("s3_mediation")
  if (grepl("\\bROC\\b", bn, ignore.case = TRUE)) return("s4_roc")
  "drop"
}

.extract_fig_db <- function(bn, db_names) {
  for (db in db_names) {
    if (grepl(paste0("-", db, "\\."), bn, fixed = FALSE)) return(db)
  }
  NA_character_
}

.prognosis_figure_target <- function(role, src_bn, db = NA_character_) {
  db_sfx <- if (!is.na(db) && nzchar(db)) paste0("-", db) else ""
  cap <- sub("^Figure (?:S)?[0-9]+(?:-[A-Za-z0-9_]+)?\\. ", "", src_bn, perl = TRUE)
  cap <- sub("\\.pdf$", "", cap, ignore.case = TRUE)
  switch(role,
    fig1 = if (grepl("Inclusion exclusion", cap, ignore.case = TRUE)) {
      sprintf("Figure 1%s. Inclusion exclusion flowchart.pdf", db_sfx)
    } else {
      sprintf("Figure 1%s. %s.pdf", db_sfx, cap)
    },
    fig2_rcs = sprintf("Figure 2%s. %s.pdf", db_sfx, cap),
    fig3_km = sprintf("Figure 3%s. %s.pdf", db_sfx, cap),
    fig4_subgroup = sprintf("Figure 4%s. %s.pdf", db_sfx, cap),
    s1_cutoff = sprintf("Figure S1%s. %s.pdf", db_sfx, cap),
    s2_boxplot = sprintf("Figure S2%s. %s.pdf", db_sfx, cap),
    s3_mediation = sprintf("Figure S3%s. %s.pdf", db_sfx, cap),
    s4_roc = sprintf("Figure S4%s. %s.pdf", db_sfx, cap),
    NULL
  )
}

dedupe_prognosis_figures_dir <- function(figures_dir, db_names, label = "") {
  if (!dir.exists(figures_dir)) return(invisible(0L))
  files <- list.files(figures_dir, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)
  if (!length(files)) return(invisible(0L))
  fi <- file.info(files)
  ord <- order(fi$mtime, decreasing = TRUE, na.last = TRUE)
  files <- files[ord]
  keep <- list()
  n_drop <- 0L
  for (f in files) {
    bn <- basename(f)
    role <- .prognosis_figure_role(bn)
    if (identical(role, "drop")) {
      unlink(f); n_drop <- n_drop + 1L; next
    }
    db <- .extract_fig_db(bn, db_names)
    if (is.na(db) && nzchar(label)) db <- label
    key <- paste(role, db %||% "", sep = "\x01")
    if (key %in% names(keep)) {
      unlink(f); n_drop <- n_drop + 1L; next
    }
    keep[[key]] <- f
  }
  n_ren <- 0L
  for (key in names(keep)) {
    parts <- strsplit(key, "\x01", fixed = TRUE)[[1L]]
    role <- parts[[1L]]
    db <- if (length(parts) >= 2L && nzchar(parts[[2L]])) parts[[2L]] else NA_character_
    src <- keep[[key]]
    tgt_bn <- .prognosis_figure_target(role, basename(src), db)
    if (is.null(tgt_bn)) next
    tgt <- file.path(figures_dir, tgt_bn)
    if (!identical(normalizePath(src, winslash = "/", mustWork = FALSE),
                   normalizePath(tgt, winslash = "/", mustWork = FALSE))) {
      if (file.exists(tgt)) unlink(tgt)
      ok <- file.rename(src, tgt)
      if (!isTRUE(ok)) file.copy(src, tgt, overwrite = TRUE)
      if (!identical(src, tgt) && file.exists(src)) unlink(src)
      n_ren <- n_ren + 1L
    }
  }
  if (n_drop > 0L || n_ren > 0L) {
    cli::cli_alert_info(
      "[{label}] 图去重: 删 {n_drop}，重命名 {n_ren}: {.file {basename(figures_dir)}}"
    )
  }
  invisible(n_drop)
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
