###############################################################################
#  rscript_study.R — 四套文献流水线批量默认 Rscript（Windows R-4.5.1）
###############################################################################

STUDY_RSCRIPT_BIN <- "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"

study_rscript_bin <- function() {
  bin <- Sys.getenv("RSCRIPT", unset = "")
  if (nzchar(bin) && file.exists(bin)) return(bin)
  wd <- tryCatch(normalizePath(getwd(), winslash = "/", mustWork = FALSE), error = function(e) "")
  if (grepl("^/mnt/", wd)) {
    linux_r <- Sys.which("Rscript")
    if (nzchar(linux_r) && file.exists(linux_r)) return(linux_r)
  }
  if (file.exists(STUDY_RSCRIPT_BIN)) return(STUDY_RSCRIPT_BIN)
  alt <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  if (file.exists(alt)) return(alt)
  stop("未找到 Rscript。请设置 RSCRIPT 或安装 R-4.5.1。", call. = FALSE)
}
