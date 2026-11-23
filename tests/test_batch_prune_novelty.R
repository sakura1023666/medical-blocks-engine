source("R/batch_prune_failed.R")
source("R/pubmed_novelty_prune.R")

tmp <- tempfile("prune_nov_")
dir.create(file.path(tmp, "by_index", "【success】KEEP"), recursive = TRUE)
dir.create(file.path(tmp, "by_index", "【success】DROP"), recursive = TRUE)
dir.create(file.path(tmp, "checkpoints", "by_index", "DROP"), recursive = TRUE)
dir.create(file.path(tmp, "reports"), recursive = TRUE)
utils::write.csv(
  data.frame(
    index = c("KEEP", "DROP"),
    pubmed_sepsis_index_outcome_methodSOFA = c(0, 2)
  ),
  file.path(tmp, "reports", "pubmed_novelty_4d_all_on_disk.csv"),
  row.names = FALSE
)

cfg <- list(pubmed_novelty = list(
  enable = TRUE,
  keep_max = 0L,
  result_csv = file.path(tmp, "reports", "pubmed_novelty_4d_all_on_disk.csv"),
  count_col = "pubmed_sepsis_index_outcome_methodSOFA"
))
fails <- pubmed_novelty_fail_indices(tmp, cfg)
stopifnot(identical(fails, "DROP"))
out <- batch_prune_novelty_failed_outputs(tmp, config = cfg, dry_run = FALSE)
stopifnot(dir.exists(file.path(tmp, "by_index", "【success】KEEP")))
stopifnot(!dir.exists(file.path(tmp, "by_index", "【success】DROP")))
stopifnot(!dir.exists(file.path(tmp, "checkpoints", "by_index", "DROP")))
unlink(tmp, recursive = TRUE, force = TRUE)
message("OK test_batch_prune_novelty")
