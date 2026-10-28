# Engine guards for the next cum-exposure k-means publication.
root <- Sys.getenv("BLOCK_REPO_ROOT", unset = "/mnt/e/01block/01Block-new-Final")
source(file.path(root, "R", "cum_egdr_kmeans_pub.R"), local = FALSE)

stopifnot(identical(ckm_stroke_p_for_estimate_cell("NE", 0.996), "\u2014"))
stopifnot(identical(ckm_stroke_fmt_p(0.04), ckm_stroke_p_for_estimate_cell("1.100 (1.000\u20131.200)", 0.04)))

ok <- tryCatch(ckm_stroke_assert_mice_footnote("Table 2. Logistic", "mirror complete-case"), error = function(e) e)
stopifnot(!inherits(ok, "error"))
bad <- tryCatch(
  ckm_stroke_assert_mice_footnote("Table S4 after multiple imputation", "missingness is near-zero; estimates mirror complete-case"),
  error = function(e) e
)
stopifnot(inherits(bad, "error"))

ok2 <- tryCatch(ckm_stroke_assert_forest_scale("unit", "Fig. S2 per 1-unit"), error = function(e) e)
stopifnot(!inherits(ok2, "error"))
bad2 <- tryCatch(ckm_stroke_assert_forest_scale("sd", "Fig. S2 per 1-SD"), error = function(e) e)
stopifnot(inherits(bad2, "error"))
ok3 <- tryCatch(ckm_stroke_assert_forest_scale("sd", "historical", allow_per_sd = TRUE), error = function(e) e)
stopifnot(!inherits(ok3, "error"))
bad3 <- tryCatch(ckm_stroke_assert_forest_scale("unit", "Fig. S2 per 1-SD"), error = function(e) e)
stopifnot(inherits(bad3, "error"))

cc <- data.frame(
  Variable = c("Cumulative WWI", "  Class 1"),
  M2e = c("1.100 (1.000\u20131.200)", "1.200 (1.000\u20131.400)"),
  M2p = c("0.040", "0.050"),
  M3e = c("1.110 (1.000\u20131.220)", "1.210 (1.000\u20131.420)"),
  M3p = c("0.030", "0.040"),
  stringsAsFactors = FALSE
)
blank <- cc
blank$M2e <- c("", "")
blank$M3e <- c("", "")
bad4 <- tryCatch(ckm_stroke_assert_mice_not_shell(cc, blank), error = function(e) e)
stopifnot(inherits(bad4, "error"))
bad5 <- tryCatch(ckm_stroke_assert_mice_not_shell(cc, cc), error = function(e) e)
stopifnot(inherits(bad5, "error"))
filled <- cc
filled$M3e <- c("1.200 (1.050\u20131.360)", "1.400 (1.100\u20131.780)")
ok4 <- tryCatch(ckm_stroke_assert_mice_not_shell(cc, filled), error = function(e) e)
stopifnot(!inherits(ok4, "error"))

message("test_cum_kmeans_pub_guards: PASS")
