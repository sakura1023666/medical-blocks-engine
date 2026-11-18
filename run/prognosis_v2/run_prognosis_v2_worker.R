#!/usr/bin/env Rscript
# 预后 2.0 单库 worker。不依赖旧预后共享检查点。
# 用法由 run_prognosis_v2_batch.R 派发:
#   Rscript run/prognosis_v2/run_prognosis_v2_worker.R --unit SHHS --config configs/config_prognosis_v2_sleep_dyslipid.R <repo>

.init_script_dir <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1L]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}

.parse_worker_args <- function(args) {
  opts <- list(unit = NULL, root = NULL, config = NULL)
  i <- 1L
  while (i <= length(args)) {
    a <- args[[i]]
    if (a == "--unit" && i < length(args)) {
      opts$unit <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (a == "--config" && i < length(args)) {
      opts$config <- trimws(args[[i + 1L]]); i <- i + 2L
    } else if (!startsWith(a, "--") && is.null(opts$root)) {
      opts$root <- a; i <- i + 1L
    } else i <- i + 1L
  }
  if (is.null(opts$unit) || !nzchar(opts$unit)) stop("--unit 必填", call. = FALSE)
  opts
}

script_path <- .init_script_dir()
if (basename(script_path) == "prognosis_v2" && basename(dirname(script_path)) == "run") {
  script_path <- normalizePath(file.path(script_path, "..", ".."), winslash = "/")
}
args <- .parse_worker_args(commandArgs(trailingOnly = TRUE))
root <- if (!is.null(args$root) && nzchar(args$root)) {
  normalizePath(args$root, winslash = "/", mustWork = TRUE)
} else script_path
setwd(root)

source(file.path(root, "R/utils.R"))
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/study_batch_runner.R"))

config_path <- normalizePath(args$config %||% file.path(root, "configs/config_prognosis_v2_sleep_dyslipid.R"),
                             winslash = "/", mustWork = TRUE)
source(config_path)

unit <- args$unit
config$prognosis_v2$database <- unit
output_unit <- study_batch_unit_output_dir(config, unit)
config$project$output_dir <- output_unit
config$project$database <- unit
if (!dir.exists(output_unit)) dir.create(output_unit, recursive = TRUE)

pl <- pipeline_unit
pl$checkpoint$enable <- TRUE
pl$checkpoint$dir <- file.path(output_unit, "checkpoints")

t0 <- proc.time()
ok <- tryCatch({
  run_pipeline(root, config = config, pipeline = pl)
  TRUE
}, error = function(e) {
  study_batch_write_status(output_unit, list(
    unit = unit, status = "failed", error_message = conditionMessage(e),
    elapsed_sec = round(as.numeric((proc.time() - t0)["elapsed"]), 1),
    disease = "血脂异常", protocol = "预后2.0"
  ))
  message(conditionMessage(e))
  FALSE
})
if (isTRUE(ok)) {
  study_batch_write_status(output_unit, list(
    unit = unit, status = "success", error_message = NA_character_,
    elapsed_sec = round(as.numeric((proc.time() - t0)["elapsed"]), 1),
    disease = "血脂异常", protocol = "预后2.0"
  ))
  quit(save = "no", status = 0)
}
quit(save = "no", status = 1)
