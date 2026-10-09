#!/usr/bin/env Rscript

args <- commandArgs(trailingOnly = TRUE)
if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x) || !length(x)) y else x
}
arg_value <- function(flag, default = "") {
  hit <- match(flag, args)
  if (is.na(hit) || hit >= length(args)) return(default)
  args[[hit + 1L]]
}

config_path <- arg_value("--config")
index_label <- arg_value("--index")
dry_run <- "--dry-run" %in% args
if (!nzchar(config_path) || !file.exists(config_path)) {
  stop("--config 必须指向存在的研究 config.R", call. = FALSE)
}
if (!identical(index_label, "SOSM+WPR")) {
  stop("本次终稿构建仅授权 SOSM+WPR", call. = FALSE)
}

engine_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(engine_root)) {
  engine_root <- normalizePath(file.path(dirname(sys.frame(1)$ofile %||% "run/ml"), "../.."))
}
engine_root <- normalizePath(engine_root, winslash = "/", mustWork = TRUE)
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine_root)
source(file.path(engine_root, "R", "ml_dual_literature_final.R"))

study_root <- normalizePath(dirname(config_path), winslash = "/", mustWork = TRUE)
index_root <- file.path(study_root, "by_index", paste0("【success】", index_label))
if (!dir.exists(index_root)) {
  stop("成功指标目录不存在: ", index_root, call. = FALSE)
}
out <- arg_value("--out", file.path(index_root, "publication_final"))

cfg <- tryCatch({
  # 研究 build 脚本会通过 source(..., local=FALSE) 读取 .study，因此 CLI
  # 独立进程内应在全局环境加载；进程退出后不会污染用户会话。
  sys.source(config_path, envir = .GlobalEnv)
  if (exists("config", envir = .GlobalEnv, inherits = FALSE)) {
    get("config", envir = .GlobalEnv, inherits = FALSE)
  } else {
    list()
  }
}, error = function(e) {
  message("config 读取失败，将使用终稿默认格式参数: ", conditionMessage(e))
  list()
})

manifest <- ml_dual_literature_build_final(
  index_root, out, config = cfg, dry_run = dry_run
)
if (dry_run) {
  print(manifest[, c("kind", "number", "role", "db_mode", "target_name")], row.names = FALSE)
  cat(sprintf("PUBLICATION_FINAL_DRY_RUN artifacts=%d\n", nrow(manifest)))
} else {
  cat(sprintf(
    "PUBLICATION_FINAL_OK figures=%d tables=%d out=%s\n",
    sum(manifest$kind == "Figure"),
    sum(grepl("table", manifest$kind, ignore.case = TRUE)),
    normalizePath(out, winslash = "/", mustWork = TRUE)
  ))
}
