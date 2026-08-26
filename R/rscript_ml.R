###############################################################################
#  rscript_ml.R — ML 流水线固定使用 Windows R 4.5.1（WSL 路径）
###############################################################################

ML_RSCRIPT_BIN <- "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"

ml_rscript_bin <- function() {
  bin <- ML_RSCRIPT_BIN
  if (!file.exists(bin)) {
    stop(
      "ML 流水线要求 Windows Rscript，未找到: ", bin,
      "\n请确认 R-4.5.1 已安装于 C:/Program Files/R/R-4.5.1/",
      call. = FALSE
    )
  }
  normalizePath(bin, winslash = "/", mustWork = TRUE)
}

ml_use_windows_r <- function() {
  isTRUE(file.exists(ML_RSCRIPT_BIN))
}

#' WSL/Linux R 下自动转调 Windows Rscript.exe（ML 流水线入口脚本调用）
ml_rscript_reexec_if_needed <- function() {
  if (isTRUE(getOption("ml.rscript.reexec_done", FALSE))) return(invisible(FALSE))
  if (!file.exists(ML_RSCRIPT_BIN)) return(invisible(FALSE))
  if (.Platform$OS.type == "windows") return(invisible(FALSE))
  ca <- commandArgs(trailingOnly = FALSE)
  self <- grep("^--file=", ca, value = TRUE)
  if (!length(self)) return(invisible(FALSE))
  self <- normalizePath(sub("^--file=", "", self[1L]), winslash = "/", mustWork = FALSE)
  if (!file.exists(self)) return(invisible(FALSE))
  args <- commandArgs(trailingOnly = TRUE)
  cmd <- ML_RSCRIPT_BIN
  status <- system2(cmd, c(self, args), stdout = "", stderr = "")
  quit(save = "no", status = status)
}
