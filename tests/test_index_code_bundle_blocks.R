#!/usr/bin/env Rscript
# 成功指标 code 包：必须镜像实际用过的 Block 源码
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pipeline_runner.R"), local = FALSE)
source(file.path(root, "R/index_code_bundle.R"), local = FALSE)

td <- tempfile("code_bundle_")
dir.create(td, recursive = TRUE)
# 伪造 checkpoint：只用 cox_quartile（不用 tertile）
ck <- file.path(td, "checkpoints", "by_index", "FAKEIX", "MIMIC")
dir.create(ck, recursive = TRUE)
saveRDS(list(ctx = list(results = list())), file.path(ck, "cox_quartile.rds"))
saveRDS(list(ctx = list(results = list())), file.path(ck, "logistic_binary_glm.rds"))

ix_root <- file.path(td, "by_index", "FAKEIX")
dir.create(ix_root, recursive = TRUE)
cfg <- list(
  project = list(output_dir = td),
  survival_batch = list(
    .pipeline_blocks = c("cox_quartile", "cox_tertile", "logistic_binary_glm")
  )
)
incidence_batch_is_prognosis_config <<- function(config) TRUE

ok <- index_code_bundle_write(
  index_root = ix_root,
  project_root = td,
  ix = "FAKEIX",
  config = cfg,
  engine_root = root,
  db_seq = "MIMIC"
)
stopifnot(isTRUE(ok))
used <- readLines(file.path(ix_root, "code", "blocks_used.txt"))
stopifnot("cox_quartile" %in% used)
stopifnot(!"cox_tertile" %in% used)  # 未跑过的不得进 used
stopifnot("logistic_binary_glm" %in% used)
cox_src <- file.path(
  ix_root, "code", "blocks", "Blocks", "10_cox", "03block_cox_quartile.R"
)
stopifnot(file.exists(cox_src))
man <- file.path(ix_root, "code", "blocks", "MANIFEST.md")
stopifnot(file.exists(man))
val <- index_code_bundle_validate(file.path(ix_root, "code"))
stopifnot(isTRUE(val$ok))
unlink(td, recursive = TRUE)
message("test_index_code_bundle_blocks: OK")
