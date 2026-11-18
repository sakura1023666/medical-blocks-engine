#!/usr/bin/env Rscript
# 胃癌 × 环境 ExWAS 批量入口
# 用法:
#   Rscript run/environment_exwas/run_environment_exwas_batch.R --config <config.R> --shared-only
#   Rscript run/environment_exwas/run_environment_exwas_batch.R --config <config.R> --workers 4
#   Rscript run/environment_exwas/run_environment_exwas_batch.R --config <config.R> --tail-only
# Rscript 约定: "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"

args <- commandArgs(trailingOnly = TRUE)
opt <- list(config = NULL, workers = 1L, shared_only = FALSE, tail_only = FALSE, only = NULL)
i <- 1L
while (i <= length(args)) {
  a <- args[[i]]
  if (a == "--config" && i < length(args)) { opt$config <- args[[i + 1L]]; i <- i + 2L
  } else if (a == "--workers" && i < length(args)) { opt$workers <- as.integer(args[[i + 1L]]); i <- i + 2L
  } else if (a == "--shared-only") { opt$shared_only <- TRUE; i <- i + 1L
  } else if (a == "--tail-only") { opt$tail_only <- TRUE; i <- i + 1L
  } else if (a == "--only" && i < length(args)) { opt$only <- strsplit(args[[i + 1L]], ",", fixed = TRUE)[[1]]; i <- i + 2L
  } else stop("未知参数: ", a, call. = FALSE)
}
if (is.null(opt$config)) stop("需要 --config", call. = FALSE)

ca <- commandArgs(trailingOnly = FALSE)
f <- grep("^--file=", ca, value = TRUE)
root <- if (length(f)) normalizePath(file.path(dirname(sub("^--file=", "", f[[1]])), "..", ".."), winslash = "/") else getwd()
setwd(root)
Sys.setenv(MEDICAL_BLOCKS_ROOT = root)
Sys.setenv(EXWAS_WORKERS = as.character(max(1L, opt$workers)))
source(file.path(root, "R/utils.R"))
cfg_path <- opt$config
to_host_path <- function(p) {
  if (.Platform$OS.type != "windows") return(p)
  p <- chartr("\\", "/", p)
  if (grepl("^/mnt/[A-Za-z]/", p)) {
    paste0(toupper(substr(p, 6, 6)), ":/", substring(p, 8))
  } else p
}
cfg_path <- to_host_path(cfg_path)
if (!grepl("^(/|[A-Za-z]:)", cfg_path)) cfg_path <- file.path(root, cfg_path)
source(cfg_path, local = FALSE)
config$exwas_gastric_assemble$nutrition_csv <- to_host_path(config$exwas_gastric_assemble$nutrition_csv %||% "")
config$project$output_dir <- to_host_path(config$project$output_dir)

source(file.path(root, "Blocks/35_environment_function/09block_exwas_gastric_assemble.R"))
source(file.path(root, "Blocks/42_environment_single/02block_exwas_unweighted.R"))
source(file.path(root, "Blocks/36_environment_glm/02block_ers_elastic_net.R"))
source(file.path(root, "Blocks/37_environment_wqs/02block_wqs_exwas_fixed.R"))

ctx <- list(config = config, data = list(), results = list())
out <- config$project$output_dir
if (!dir.exists(out)) dir.create(out, recursive = TRUE)

if (!opt$tail_only) {
  ctx <- block_exwas_gastric_assemble(ctx)
  saveRDS(ctx, file.path(out, "ctx_shared.rds"))
  exwas_write_descriptives(ctx$data$cleaned, ctx$results$exwas_outcome %||% "DN", out)
  if (opt$shared_only) {
    message("shared-only 完成: ", out)
    quit(save = "no", status = 0)
  }
  exposures <- ctx$results$exwas_exposures
  # 先在主进程完成筛查与插补（exwas_unweighted 内），再按暴露并行只重复拟合会重复插补。
  # 并行策略：插补一次后把暴露列表拆给 worker，worker 只跑 glm。
  if (is.null(opt$only)) {
    ctx <- block_exwas_unweighted(ctx)
  }
  saveRDS(ctx, file.path(out, "ctx_exwas.rds"))
}

if (opt$tail_only) {
  ctx <- readRDS(file.path(out, "ctx_exwas.rds"))
  ctx$config <- config
}

if (!opt$shared_only) {
  ctx <- block_ers_elastic_net(ctx)
  ctx <- block_wqs_exwas_fixed(ctx)
  saveRDS(ctx, file.path(out, "ctx_tail.rds"))
  message("尾段完成: ", out)
}
