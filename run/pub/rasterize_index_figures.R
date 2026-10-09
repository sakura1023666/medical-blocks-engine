#!/usr/bin/env Rscript
# 从 Figures/pdf/ 栅格化生成 png/ + tiff/，并刷新 image_information
args <- commandArgs(trailingOnly = TRUE)
index_dir <- if (length(args)) args[[1L]] else stop("用法: Rscript rasterize_index_figures.R <index_dir>")

.init_script_dir <- function() {
  sp <- tryCatch(
    normalizePath(dirname(rstudioapi::getActiveDocumentContext()$path), winslash = "/"),
    error = function(e) NA_character_
  )
  if (!is.na(sp) && nzchar(sp)) return(sp)
  ca <- commandArgs(trailingOnly = FALSE)
  f  <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    fp <- sub("^--file=", "", f[1L])
    if (nzchar(fp)) return(normalizePath(dirname(fp), winslash = "/"))
  }
  normalizePath(getwd(), winslash = "/")
}

env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (nzchar(env_root)) {
  root <- tryCatch(normalizePath(env_root, winslash = "/", mustWork = TRUE), error = function(e) NA_character_)
} else {
  script_path <- .init_script_dir()
  root <- normalizePath(file.path(script_path, "..", ".."), winslash = "/", mustWork = FALSE)
}
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pub_figure_export.R"))
if (file.exists(file.path(root, "R/incidence_dual_batch_runner.R"))) {
    source(file.path(root, "R/incidence_dual_batch_runner.R"))
}

figs_dir <- file.path(index_dir, "Figures")
dirs <- pub_figure_ensure_format_dirs(figs_dir)
config <- list(pub_figures = list(dpi = 300L, write_image_information = TRUE))
cfg <- .pub_figure_cfg(config)

pdfs <- sort(list.files(
  dirs[["pdf"]], pattern = "^Figure.*\\.pdf$",
  full.names = TRUE, ignore.case = TRUE
))
if (!length(pdfs)) stop("Figures/pdf 下无 Figure*.pdf")

cli::cli_alert_info("栅格化 {length(pdfs)} 张 PDF → png/tiff (dpi={cfg$dpi})")
ok <- 0L
fail <- character(0)
for (fp in pdfs) {
  stem <- sub("\\.pdf$", "", basename(fp), ignore.case = TRUE)
  dest_png <- file.path(dirs[["png"]], paste0(stem, ".png"))
  dest_tiff <- file.path(dirs[["tiff"]], paste0(stem, ".tiff"))
  res <- tryCatch({
    .pub_figure_rasterize_one(fp, dest_png, dest_tiff, cfg$dpi, root_hint = root)
    TRUE
  }, error = function(e) {
    fail <<- c(fail, paste(stem, ":", conditionMessage(e)))
    FALSE
  })
  if (isTRUE(res)) ok <- ok + 1L
}

ix <- sub("^【[^】]+】", "", basename(index_dir))
meta <- list(
  exposure = ix,
  outcome = "Hypothermia",
  databases = character(0),
  combined = FALSE,
  grouping = "quartile"
)
if (exists("incidence_batch_pub_figure_meta_n", mode = "function")) {
  meta_n <- tryCatch(
    incidence_batch_pub_figure_meta_n(index_dir, config, character(0)),
    error = function(e) list()
  )
  if (length(meta_n)) meta <- c(meta, meta_n)
}
pub_figure_refresh_image_information(figs_dir, meta = meta, config = config)

cli::cli_alert_success("完成: ok={ok}, fail={length(fail)}")
if (length(fail)) cat(paste(fail, collapse = "\n"), "\n")
cat("png:\n"); print(list.files(dirs[["png"]]))
cat("tiff:\n"); print(list.files(dirs[["tiff"]]))
