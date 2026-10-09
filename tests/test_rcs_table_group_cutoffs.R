#!/usr/bin/env Rscript
source("R/utils.R")

cut_use <- list(or1 = c(10.1, 19.9), peak = 14.0, all = c(10.1, 14.0, 19.9))
stopifnot(identical(rcs_table_group_cutoffs(cut_use, mode = "primary"), 14.0))
stopifnot(identical(rcs_table_group_cutoffs(cut_use, primary = 14.0, mode = "primary"), 14.0))
stopifnot(identical(
  rcs_table_group_cutoffs(cut_use, mode = "all"),
  c(10.1, 14.0, 19.9)
))

x <- c(5, 15, 25)
grp <- rcs_cutoff_factor(x, rcs_table_group_cutoffs(cut_use, primary = 14.0), "LCI")
stopifnot(grp$n_groups == 2L)
stopifnot(length(levels(grp$factor)) == 2L)

cat("test_rcs_table_group_cutoffs: OK\n")
