#!/usr/bin/env Rscript
# =============================================================================
#  为单库平链（all-vars ML）课题补写 code 包
#  用法:
#    Rscript run/ml/generate_single_pipeline_code_bundle.R \
#      --study /mnt/g/02block_result/35_EMs/ml_40395549
# =============================================================================

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

args <- commandArgs(trailingOnly = TRUE)
study <- NA_character_
i <- 1L
while (i <= length(args)) {
  if (identical(args[[i]], "--study") && i < length(args)) {
    study <- args[[i + 1L]]
    i <- i + 2L
  } else {
    i <- i + 1L
  }
}
if (is.na(study) || !nzchar(as.character(study)[1L])) {
  stop("请传 --study <课题根目录>", call. = FALSE)
}
study <- normalizePath(study, winslash = "/", mustWork = TRUE)

.self <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (length(.self)) {
  .sp <- dirname(normalizePath(sub("^--file=", "", .self[1L]), winslash = "/"))
  eng_cand <- normalizePath(file.path(.sp, "../.."), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(eng_cand, "R/index_code_bundle.R"))) {
    eng <- eng_cand
  }
}
if (!nzchar(eng)) {
  envf <- file.path(study, "engine.env")
  if (file.exists(envf)) {
    lines <- readLines(envf, warn = FALSE)
    kv <- grep("^MEDICAL_BLOCKS_ROOT\\s*=", lines, value = TRUE)
    if (length(kv)) {
      eng <- trimws(sub("^MEDICAL_BLOCKS_ROOT\\s*=", "", kv[1L]))
      eng <- gsub('^"|"$', "", eng)
      if (grepl("^[A-Za-z]:/", eng) && .Platform$OS.type != "windows") {
        eng <- paste0("/mnt/", tolower(substr(eng, 1L, 1L)), "/", substring(eng, 4L))
      }
    }
  }
}
if (!nzchar(eng) || !file.exists(file.path(eng, "R/index_code_bundle.R"))) {
  stop("找不到 MEDICAL_BLOCKS_ROOT / 引擎 R/index_code_bundle.R", call. = FALSE)
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = eng)

source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/pipeline_runner.R"), local = FALSE)
source(file.path(eng, "R/index_code_bundle.R"), local = FALSE)

cfg_path <- file.path(study, "config.R")
if (!file.exists(cfg_path)) stop("课题无 config.R: ", cfg_path, call. = FALSE)
options(ems.config_path = cfg_path)
# config.R 里 source 引擎模板需要 MEDICAL_BLOCKS_ROOT
source(cfg_path, local = FALSE)
if (!exists("config", inherits = TRUE)) stop("config.R 未定义 config", call. = FALSE)
.pipe <- if (exists("pipeline", inherits = TRUE)) get("pipeline", inherits = TRUE) else NULL

ok <- index_code_bundle_write_single_pipeline(
  study_root = study,
  config = config,
  engine_root = eng,
  pipeline = .pipe
)
if (!isTRUE(ok)) quit(save = "no", status = 1L)
message("OK: ", file.path(study, "code"))
quit(save = "no", status = 0L)
