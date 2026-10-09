#!/usr/bin/env Rscript
# test_environment_sensitivity_fdr.R

.test_dir <- local({
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) return(normalizePath(dirname(sub("^--file=", "", f[1L]))))
  normalizePath("tests")
})
.root <- normalizePath(file.path(.test_dir, ".."), winslash = "/")
source(file.path(.root, "R/utils.R"), local = FALSE)
source(file.path(.root, "R/environment_sensitivity_fdr.R"), local = FALSE)

.check <- function(cond, msg) {
  if (!isTRUE(cond)) stop(msg, call. = FALSE)
}

# keep_mask: drop Current only
df <- data.frame(
  Smoking = c("Never", "Former", "Current", "Current", NA, "Never"),
  Age = 1:6,
  stringsAsFactors = FALSE
)
info <- environment_sensitivity_keep_mask(df, "Smoking", "Current")
.check(info$n_before == 6L, "n_before")
.check(info$n_drop == 2L, "drop Current")
.check(length(info$keep) == 4L, "keep Never/Former/NA")
.check(all(df$Smoking[info$keep] %in% c("Never", "Former", NA_character_)), "remaining levels")

sub <- environment_sensitivity_subset_df(df, info$keep)
.check(nrow(sub) == 4L, "subset nrow")
.check(!"Current" %in% sub$Smoking, "no Current after subset")

# factor Smoking
df$Smoking <- factor(df$Smoking, levels = c("Never", "Former", "Current"))
info2 <- environment_sensitivity_keep_mask(df, "Smoking", "Current")
.check(info2$n_drop == 2L, "factor Current drop")

# constant cov drop
d2 <- data.frame(Age = 1:3, Smoking = c("Never", "Never", "Never"), BMI = c(1, 2, 3))
kept <- environment_sensitivity_drop_constant_covs(c("Age", "Smoking", "BMI", "Missing"), d2)
.check(identical(kept, c("Age", "BMI")), paste("constant drop got", paste(kept, collapse = ",")))

# FDR p.adjust order
p <- c(0.001, 0.04, 0.20, 0.80)
q <- stats::p.adjust(p, method = "BH")
.check(q[1] < 0.05 && q[4] > 0.05, "BH sanity")
fmt <- environment_fdr_format_p(c(0.0001, 0.0123, NA))
.check(identical(fmt[1], "<0.001"), "fmt <0.001")
.check(identical(fmt[2], "0.012"), "fmt 3 digits")
.check(identical(fmt[3], ""), "fmt NA")
.check(isTRUE(abs(environment_fdr_parse_p_text("P < 0.001") - 5e-4) < 1e-12), "parse <0.001")
.check(isTRUE(abs(environment_fdr_parse_p_text("0.1212") - 0.1212) < 1e-9), "parse numeric p")
specs <- environment_fdr_method_specs(20L, "Table S", "full population", "X")
.check(length(specs) == 4L, "4 method FDR specs")
.check(identical(specs[[1]]$id, "Table S20"), "S20 GLM")
.check(identical(specs[[4]]$id, "Table S23"), "S23 QGC")
sa <- environment_fdr_method_specs(5L, "Table SA", "sensitivity", "X")
.check(identical(sa[[1]]$id, "Table SA5"), "SA5")
.check(identical(sa[[4]]$id, "Table SA8"), "SA8")

# smoker level matcher
.check(isTRUE(environment_sensitivity_is_smoker_level("Current", "Current")), "match Current")
.check(!isTRUE(environment_sensitivity_is_smoker_level("Never", "Current")), "Never kept")
.check(isTRUE(environment_sensitivity_is_smoker_level("current smoker", "Current")), "current smoker")

# keep Never only
info3 <- environment_sensitivity_keep_mask(
  data.frame(Smoking = c("Never", "Former", "Current", NA), stringsAsFactors = FALSE),
  "Smoking",
  keep_levels = "Never"
)
.check(info3$n_drop == 3L, "never-only drop Former/Current/NA")
.check(length(info3$keep) == 1L, "never-only keep 1")
.check(isTRUE(environment_sensitivity_is_never_only("Never", NULL)), "never-only flag")
.check(identical(
  environment_sensitivity_pub_tag("Never", c("Current", "Former")),
  "sensitivity: never smokers only"
), "never-only tag")

message("OK: test_environment_sensitivity_fdr")
