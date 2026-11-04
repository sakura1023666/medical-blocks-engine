#!/usr/bin/env Rscript
###############################################################################
# 脓毒症 Jin2025 方法迁移 · 双库预后批量入口（薄封装 survival dual）
#
#   Rscript run/sepsis_jin_prognosis/run_batch.R \
#     --config "//192.168.68.133/02block_result/36_spesis/prediction_41194138/config_survival.R" \
#     --shared-only
#   Rscript run/sepsis_jin_prognosis/run_batch.R --config ... --workers auto
###############################################################################

{
  skip_win <- identical(Sys.getenv("MEDICAL_BLOCKS_SKIP_WIN_R", unset = ""), "1")
  rscript <- "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"
  if (!skip_win && file.exists(rscript) && .Platform$OS.type != "windows") {
    ca <- commandArgs(trailingOnly = FALSE)
    self <- grep("^--file=", ca, value = TRUE)
    if (length(self)) {
      self <- sub("^--file=", "", self[1L])
      .win_q <- function(x) {
        vapply(as.character(x), function(a) {
          if (!nzchar(a)) return('""')
          if (grepl("[[:space:]]", a) || grepl('"', a, fixed = TRUE))
            paste0('"', gsub('"', '\\"', a, fixed = TRUE), '"')
          else a
        }, character(1), USE.NAMES = FALSE)
      }
      status <- system2(rscript, .win_q(c(self, commandArgs(trailingOnly = TRUE))))
      quit(save = "no", status = status)
    }
  }
}

.init_root <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) {
    sp <- normalizePath(dirname(sub("^--file=", "", f[1L])), winslash = "/")
    if (basename(sp) == "sepsis_jin_prognosis" && basename(dirname(sp)) == "run")
      return(normalizePath(file.path(sp, "..", ".."), winslash = "/"))
  }
  env <- Sys.getenv("MEDICAL_BLOCKS_ROOT", "")
  if (nzchar(env)) return(normalizePath(env, winslash = "/"))
  normalizePath(getwd(), winslash = "/")
}

root <- .init_root()
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
setwd(root)

## 转调引擎 survival dual batch（同 CLI 参数）
## 已在上方切到 Windows Rscript 时，直接 source 入口逻辑会二次包装；
## 这里用同进程 system2 调 survival 脚本即可。
surv_entry <- file.path(root, "run/survival/run_survival_dual_batch.R")
if (!file.exists(surv_entry)) stop("找不到: ", surv_entry, call. = FALSE)
## 避免 WSL 入口再次自举：子进程跳过 win 包装
Sys.setenv(MEDICAL_BLOCKS_SKIP_WIN_R = "1")
status <- system2(
  file.path(R.home("bin"), "Rscript"),
  c(surv_entry, commandArgs(trailingOnly = TRUE))
)
if (is.na(status) || !is.numeric(status)) status <- 1L
quit(save = "no", status = as.integer(status))
