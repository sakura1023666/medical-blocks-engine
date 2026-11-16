# Regression: Stroke ANLR 14d P0 lessons must stay in pv2_pub_p0_gate
# Run: Rscript tests/test_pv2_p0_gate_stroke_anlr_lessons.R

.root <- {
  if (dir.exists("/mnt/e/01block/01Block-new-Final")) "/mnt/e/01block/01Block-new-Final"
  else if (dir.exists("E:/01block/01Block-new-Final")) "E:/01block/01Block-new-Final"
  else getwd()
}
src <- file.path(.root, "R/pv2_pub_p0_gate.R")
stopifnot(file.exists(src))
txt <- paste(readLines(src, warn = FALSE), collapse = "\n")

need <- c(
  "rcs_knots",
  "boruta_params",
  "shap_impl",
  "s5_landmark_matches_methods",
  "fig7_overall_in_table3",
  "methods_exposure_missing_selection",
  "primary_day",
  "not computable",
  "Numbers_Master",
  ".pv2_p0_xlsx_text_blob"
)
miss <- need[!vapply(need, function(p) grepl(p, txt, fixed = TRUE), logical(1))]
if (length(miss)) {
  stop("pv2_pub_p0_gate.R missing Stroke ANLR lesson hooks: ", paste(miss, collapse = ", "))
}

# rebuild script must not hardcode 28-day S5 footnote
reb <- file.path(.root, "run/prognosis_v2/_rebuild_stroke_anlr_tables_hip_layout.R")
stopifnot(file.exists(reb))
rtxt <- paste(readLines(reb, warn = FALSE), collapse = "\n")
if (grepl("primary 28-day locked grouping", rtxt, fixed = TRUE)) {
  stop("_rebuild_stroke_anlr_tables_hip_layout.R still hardcodes primary 28-day locked grouping")
}
if (!grepl("\\.day_lab", rtxt)) {
  stop("_rebuild_stroke_anlr_tables_hip_layout.R must use .day_lab for S5 footnote landmark")
}

# remirror must call gate
rem <- file.path(.root, "run/prognosis_v2/remirror_stroke_anlr_pub.R")
stopifnot(file.exists(rem))
mtxt <- paste(readLines(rem, warn = FALSE), collapse = "\n")
if (!grepl("pv2_pub_p0_gate\\(", mtxt)) {
  stop("remirror_stroke_anlr_pub.R must call pv2_pub_p0_gate()")
}

message("OK: Stroke ANLR 14d P0 lesson hooks present")
