###############################################################################
#  run_entry_utils.R — 薄入口脚本共用：定位项目根目录
###############################################################################

run_entry_init_script_dir <- function() {
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

#' 将 run/<category>/ 下脚本目录解析为 Medical Blocks 项目根
run_entry_resolve_root <- function(script_dir) {
  env_root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
  if (nzchar(env_root)) {
    return(normalizePath(env_root, winslash = "/", mustWork = TRUE))
  }
  script_dir <- normalizePath(script_dir, winslash = "/")
  if (basename(script_dir) %in% c("environment", "incidence", "survival", "feishu", "hf") &&
      basename(dirname(script_dir)) == "run") {
    return(normalizePath(file.path(script_dir, "..", ".."), winslash = "/"))
  }
  script_dir
}

run_entry_default_worker <- function(category, filename) {
  file.path("run", category, filename)
}
