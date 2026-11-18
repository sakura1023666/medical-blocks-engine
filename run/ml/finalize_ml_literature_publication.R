#!/usr/bin/env Rscript
# finalize_ml_literature_publication.R
#
# ML 文献终稿收口（引擎级）：重编号填空号 → Methods/软件版本 →
# summary_result 同步 → 四目录 → pub_qc 骨架。
#
# 用法:
#   Rscript run/ml/finalize_ml_literature_publication.R \
#     --pub "/mnt/g/02block_result/.../by_index/【success】SAR+CrCV/publication_literature_final" \
#     [--no-renumber] [--no-qc]
#
# Agent 收口后必须继续: nature-statistics + nature-figure（修 P0）+ 中期 PDF。

args <- commandArgs(trailingOnly = TRUE)
`%||%` <- function(a, b) if (is.null(a) || !length(a) || (length(a) == 1 && !nzchar(a))) b else a

get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  args[[hit[[1]] + 1L]]
}
has_flag <- function(flag) flag %in% args

engine <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine) || !dir.exists(file.path(engine, "R"))) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[grep("^--file=", ca)])
  if (length(f)) {
    engine <- normalizePath(file.path(dirname(f[[1]]), "..", ".."),
                            winslash = "/", mustWork = FALSE)
  }
}
if (!nzchar(engine) || !dir.exists(file.path(engine, "R"))) {
  engine <- "/mnt/e/01block/01Block-new-Final"
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)

suppressWarnings(suppressMessages({
  source(file.path(engine, "R/utils.R"))
  source(file.path(engine, "R/pub_xlsx_surgical.R"))
  source(file.path(engine, "R/pub_software_versions.R"))
  source(file.path(engine, "R/pub_figure_export.R"))
  source(file.path(engine, "R/pub_qc_after_finalize.R"))
  source(file.path(engine, "R/ml_literature_pub_finalize.R"))
}))

pub <- get_opt("--pub", get_opt("--project", ""))
if (!nzchar(pub)) {
  stop("需要 --pub <publication_literature_final 绝对路径>", call. = FALSE)
}
pub <- normalizePath(pub, winslash = "/", mustWork = TRUE)
summary_root <- get_opt("--summary", NULL)
project_qc <- get_opt("--qc-project", NULL)

res <- ml_lit_finalize_delivery(
  pub_root = pub,
  summary_root = summary_root,
  renumber = !has_flag("--no-renumber"),
  rewrite_refs = !has_flag("--no-rewrite-refs"),
  write_methods = !has_flag("--no-methods"),
  ensure_figures = !has_flag("--no-figures"),
  run_qc = !has_flag("--no-qc"),
  project_root_for_qc = project_qc
)

cat("FINALIZE_OK\n")
cat("pub_root=", res$pub_root, "\n", sep = "")
cat("summary_result=", res$summary_root, "\n", sep = "")
cat("checklist=", res$checklist, "\n", sep = "")
if (!is.null(res$renumber_plan) && nrow(res$renumber_plan)) {
  cat("renumbered=", nrow(res$renumber_plan), " tables\n", sep = "")
}
