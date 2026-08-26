# tests/test_pub_figure_onplot_annotations.R
root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/utils.R"))) {
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

stopifnot(exists(".pub_figure_fmt_p_label", mode = "function"))
stopifnot(exists(".pub_figure_extract_cox_rcs_p", mode = "function"))

fake_p <- list(
  logtest = c(NA, NA, 0.001),
  coefficients = matrix(c(rep(NA, 5), c(NA, NA, NA, NA, 0.116)), nrow = 2, byrow = TRUE)
)
pe <- .pub_figure_extract_cox_rcs_p(fake_p)
stopifnot(isTRUE(abs(pe$p_overall - 0.001) < 1e-9))
stopifnot(isTRUE(abs(pe$p_nonlinear - 0.116) < 1e-9))

stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.001), "P-overall = 0.001"))
stopifnot(identical(.pub_figure_fmt_p_label("P-overall", 0.0004), "P-overall < 0.001"))
stopifnot(identical(.pub_figure_fmt_p_label("P-non-linear", NA_real_), "P-non-linear = NA"))

rcs_f <- list(list(
  db = "MIMIC",
  panels = list(
    list(name = "Model2", p_overall = 0.001, p_nonlinear = 0.116, cutoffs = c(0.52))
  )
))
lines <- .pub_figure_rcs_annotation_lines(rcs_f)
stopifnot(any(grepl("P-overall = 0.001", lines)))
stopifnot(any(grepl("P-non-linear = 0.116", lines)))
stopifnot(any(grepl("0\\.52|cutoff", lines, ignore.case = TRUE)))

km_f <- list(list(db = "eICU", logrank_p = 0.023, cutoff = 1.25))
km_lines <- .pub_figure_km_annotation_lines(km_f)
stopifnot(any(grepl("Log-rank", km_lines)), any(grepl("0\\.023", km_lines)))
stopifnot(any(grepl("1\\.25|cutoff", km_lines, ignore.case = TRUE)))

forest_f <- list(list(
  db = "eICU",
  rows = data.frame(
    Variable = c("Overall", "Age < 65", "Age ≥ 65"),
    `Point Estimate` = c(1.20, 1.10, 1.35),
    Lower = c(1.01, 0.90, 1.05),
    Upper = c(1.42, 1.35, 1.74),
    `P for interaction` = c(NA, 0.04, NA),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
))
fo_lines <- .pub_figure_forest_annotation_lines(forest_f)
stopifnot(any(grepl("Overall", fo_lines)), any(grepl("1\\.20", fo_lines)))
stopifnot(any(grepl("interaction|交互", fo_lines, ignore.case = TRUE)))

# Task 3: harvest rcs / km / forest from index_root/<DB>/*.rds
ix_root <- tempfile("ix_")
dir.create(file.path(ix_root, "Figures"), recursive = TRUE)
dir.create(file.path(ix_root, "MIMIC"), recursive = TRUE)
saveRDS(
  list(results = list(
    rcs_prognosis_panel_stats = list(
      Model2 = list(p_overall = 0.001, p_nonlinear = 0.116, cutoffs = 0.52)
    )
  )),
  file.path(ix_root, "MIMIC", "rcs_prognosis.rds")
)
saveRDS(
  list(results = list(
    km_binary = list(logrank_p = 0.023, cutoff = 1.25),
    subgroup = data.frame(
      Variable = c("Overall", "Age"), `Point Estimate` = c(1.2, 1.1),
      Lower = c(1.0, 0.8), Upper = c(1.4, 1.5),
      `P for interaction` = c(NA, 0.04), check.names = FALSE
    )
  )),
  file.path(ix_root, "MIMIC", "km_binary.rds")
)

hf <- pub_figure_harvest_findings(file.path(ix_root, "Figures"), meta = list(databases = "MIMIC"))
stopifnot(length(hf$rcs) >= 1L)
stopifnot(any(vapply(hf$rcs[[1]]$panels, function(p) {
  isTRUE(abs((p$p_overall %||% NA_real_) - 0.001) < 1e-9)
}, logical(1))))
stopifnot(length(hf$km) >= 1L)
stopifnot(length(hf$forest) >= 1L)
unlink(ix_root, recursive = TRUE)

# 无 panel_stats 时不得合成假 P
ix_miss <- tempfile("ixmiss_")
dir.create(file.path(ix_miss, "Figures"), recursive = TRUE)
dir.create(file.path(ix_miss, "MIMIC"), recursive = TRUE)
saveRDS(
  list(results = list(rcs_prognosis = list(note = "plot only"))),
  file.path(ix_miss, "MIMIC", "rcs_prognosis.rds")
)
hf_miss <- pub_figure_harvest_findings(
  file.path(ix_miss, "Figures"), meta = list(databases = "MIMIC")
)
stopifnot(length(hf_miss$rcs %||% list()) == 0L)
unlink(ix_miss, recursive = TRUE)

cat("test_pub_figure_onplot_annotations: OK\n")
