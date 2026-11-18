#!/usr/bin/env Rscript
# EBV×PET 联合分析发表收口：draft(summary（new）) → summary_results 白名单
#
#   Rscript run/npc_ebv_pet/finalize_summary_delivery.R \
#     --draft "/mnt/g/.../summary（new）" \
#     --summary "/mnt/g/.../summary_results"
#
# 每次 rebuild_pub_consolidate 末尾也应调用本入口（或同函数）。

args <- commandArgs(trailingOnly = TRUE)
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
if (!dir.exists(file.path(engine, "R"))) {
  engine <- "/mnt/e/01block/01Block-new-Final"
}
Sys.setenv(MEDICAL_BLOCKS_ROOT = engine)
source(file.path(engine, "R/npc_ebv_pet_pub.R"), local = FALSE)

draft <- get_opt("--draft", "/mnt/g/02block_result/53_NPC/ml_40395549/summary（new）")
summary <- get_opt("--summary", file.path(dirname(draft), "summary_results"))
proj <- get_opt("--project", dirname(draft))

res <- npc_ebv_pet_finalize_summary_delivery(
  draft_root = draft,
  summary_root = summary,
  project_root = proj,
  rewrite_methods = !has_flag("--keep-methods"),
  prune = !has_flag("--no-prune"),
  sync_draft = !has_flag("--no-sync")
)
cat(
  "NPC_EBV_PET_FINALIZE_OK summary=", res$summary,
  " methods=", isTRUE(res$methods),
  " software=", isTRUE(res$software), "\n",
  sep = ""
)
