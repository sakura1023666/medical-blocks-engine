#!/usr/bin/env Rscript
# =============================================================================
#  双库指标：仅重镜像发表 Figures（可选保护 Tables）
#
#  用法:
#    MEDICAL_BLOCKS_ROOT=/path/to/engine \
#    INCIDENCE_BATCH_ROOT=/path/to/study \
#    Rscript run/incidence/remirror_index_pub_outputs.R \
#      --config /path/to/config_incidence_dual_batch.R \
#      --index LCI \
#      --figures-only \
#      --protect-tables
#
#  说明:
#    - 从 NHANES/CHARLS（或 MIMIC）分库 Figures 拷到指标根并 dual 拼图
#    - --protect-tables：镜像前快照 Tables，结束后强制还原（避免 compact S 号打乱）
#    - 勿在单库 worker finalize 后只剩一侧图时忘记跑本脚本
# =============================================================================

.parse_args <- function(args) {
  opts <- list(
    config = NULL, index = NULL, figures_only = TRUE,
    protect_tables = TRUE, dbs = c("nhanes", "mimic")
  )
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--config" && i < length(args)) {
      opts$config <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--index" && i < length(args)) {
      opts$index <- args[[i + 1L]]; i <- i + 2L
    } else if (a == "--dbs" && i < length(args)) {
      opts$dbs <- tolower(trimws(strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1L]]))
      i <- i + 2L
    } else if (a == "--figures-only") {
      opts$figures_only <- TRUE; i <- i + 1L
    } else if (a == "--protect-tables") {
      opts$protect_tables <- TRUE; i <- i + 1L
    } else if (a == "--no-protect-tables") {
      opts$protect_tables <- FALSE; i <- i + 1L
    } else {
      i <- i + 1L
    }
  }
  if (is.null(opts$config) || !nzchar(opts$config)) stop("--config 必填", call. = FALSE)
  if (is.null(opts$index) || !nzchar(opts$index)) stop("--index 必填", call. = FALSE)
  opts
}

suppressPackageStartupMessages({
  options(stringsAsFactors = FALSE, cli.hyperlink = FALSE, warn = 1)
})

opts <- .parse_args(commandArgs(trailingOnly = TRUE))
engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine)) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  script <- if (length(f)) sub("^--file=", "", f[[1L]]) else NA_character_
  engine <- if (!is.na(script)) {
    normalizePath(file.path(dirname(script), "..", ".."), winslash = "/")
  } else getwd()
}
study <- Sys.getenv("INCIDENCE_BATCH_ROOT", unset = dirname(normalizePath(opts$config)))
setwd(engine)

source(file.path(engine, "R/utils.R"))
source(file.path(engine, "R/dual_db_harmonize.R"))
source(file.path(engine, "R/dual_db_combine_figures.R"))
source(file.path(engine, "R/pub_figure_export.R"))
source(file.path(engine, "R/incidence_dual_batch_runner.R"))
source(file.path(engine, "R/pipeline_runner.R"))

# Gate D 损坏缓存兜底（旧版 character 向量）
.gd_path <- file.path(study, "checkpoints/_global_harmonization/gate_d_subgroup_vars.rds")
if (file.exists(.gd_path)) {
  .gd <- tryCatch(readRDS(.gd_path), error = function(e) NULL)
  if (is.character(.gd) || (is.list(.gd) && is.null(.gd$vars))) {
    vars <- if (is.character(.gd)) as.character(.gd) else character(0)
    saveRDS(
      list(
        vars = vars,
        eligible_by_db = list(nhanes = vars, mimic = vars),
        forced = TRUE,
        saved_at = Sys.time()
      ),
      .gd_path
    )
    cli::cli_alert_info("已修复 Gate D 缓存为 list(vars=...)")
  }
}

env <- new.env(parent = globalenv())
source(opts$config, local = env)
config <- incidence_batch_patch_config_for_index(env$config, opts$index, root = engine)
config$project$root <- engine
config$dual_db$mirror_aggregate <- TRUE

LCI <- incidence_batch_find_index_output_dir(
  (config$incidence_batch %||% list())$output_base %||% study,
  opts$index, "by_index", config = config
)
CK <- file.path(study, "checkpoints/by_index", opts$index)
config$dual_db$checkpoint_base <- CK
config$dual_db$harmonization_dir <- file.path(study, "checkpoints/_global_harmonization")
config$project$output_dir <- LCI
cli::cli_alert_info("index_root={.file {LCI}}")

snap <- NULL
if (isTRUE(opts$protect_tables)) {
  snap <- tempfile("pub_tables_snap_")
  dir.create(snap)
  tdir <- file.path(LCI, "Tables")
  if (dir.exists(tdir)) {
    file.copy(list.files(tdir, full.names = TRUE), snap, overwrite = TRUE)
    cli::cli_alert_info("Tables 快照 n={length(list.files(snap))}")
  }
}

figs <- file.path(LCI, "Figures")
# 先清汇总 Figures，再从分库拷 flat PDF，避免只剩单库
if (dir.exists(figs)) unlink(list.files(figs, full.names = TRUE, recursive = TRUE))
for (sub in c("pdf", "png", "tiff", "image_information")) {
  dir.create(file.path(figs, sub), recursive = TRUE, showWarnings = FALSE)
}
n_copy <- 0L
for (db in opts$dbs) {
  slot <- dual_db_slot_path_name(config, db)
  src <- file.path(LCI, slot, "Figures")
  if (!dir.exists(src)) next
  for (f in list.files(src, pattern = "\\.pdf$", full.names = TRUE, ignore.case = TRUE)) {
    if (file.copy(f, file.path(figs, basename(f)), overwrite = TRUE)) n_copy <- n_copy + 1L
  }
}
cli::cli_alert_info("已从分库拷入 flat PDF: {n_copy}")

if (exists("dual_db_combine_paired_figures", mode = "function")) {
  dual_db_combine_paired_figures(LCI, config)
}
incidence_batch_finalize_index_figures(
  root = study, config = config, ix = opts$index,
  db_seq = opts$dbs, index_root = LCI
)

if (!is.null(snap) && dir.exists(snap) && length(list.files(snap))) {
  tdir <- file.path(LCI, "Tables")
  dir.create(tdir, recursive = TRUE, showWarnings = FALSE)
  unlink(list.files(tdir, full.names = TRUE))
  file.copy(list.files(snap, full.names = TRUE), tdir, overwrite = TRUE)
  cli::cli_alert_success("Tables 已从快照还原 n={length(list.files(tdir))}")
}

cat("\n=== Figures/pdf ===\n")
print(sort(list.files(file.path(figs, "pdf"))))
cli::cli_alert_success("remirror done")
