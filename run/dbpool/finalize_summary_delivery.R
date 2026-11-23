#!/usr/bin/env Rscript
# Database-pooling / BlendedLoS 发表收口（引擎级）
#   Rscript run/dbpool/finalize_summary_delivery.R \
#     --dir ".../summary_results" \
#     --cohort "ACG-style enzyme elevation (ALT/AST ≥2×ULN)"
#
# 写出 Methods_statistical_analysis.md + Methods_software_versions.txt，
# 刷新四目录图格式，并按交付白名单修剪（仅 Figures/Tables/Methods_*/中期PDF）。

args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  args[[hit[[1]] + 1L]]
}

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

dir <- get_opt("--dir", "")
if (!nzchar(dir) || !dir.exists(dir)) {
  stop("需要 --dir <summary_results>", call. = FALSE)
}
cohort <- get_opt(
  "--cohort",
  "ULN-all3 enzyme elevation (AST≥38 U/L, ALT≥41 U/L, and total bilirubin≥1.3 mg/dL)"
)
Sys.setenv(DBPOOL_COHORT = cohort)
feat <- get_opt(
  "--feature-set",
  paste0(
    "Model inputs followed prior published multi-database ICU modelling inventories ",
    "(hourly vitals + laboratories + selected medications; respiratory off unless enabled; ",
    "static age/sex/height/weight). Cohort-defining laboratories dropped from predictors; ",
    "variable-level inventory is Table S9 (dbpool_feature_inventory.py at pack/finalize)."
  )
)
Sys.setenv(DBPOOL_FEATURE_SET = feat)

cli <- file.path(engine, "run/pub/finalize_delivery_root.R")
# Quote every arg for sh (paths like summary(new) break unquoted system2)
.sh_quote <- function(x) {
  x <- as.character(x)
  paste0("'", gsub("'", "'\"'\"'", x, fixed = TRUE), "'")
}
.status_run <- function(...) {
  args <- as.character(unlist(list(...), use.names = FALSE))
  cmd <- paste(c("Rscript", vapply(args, .sh_quote, character(1))), collapse = " ")
  out <- system(cmd, intern = TRUE)
  status <- attr(out, "status")
  if (is.null(status)) status <- 0L
  list(out = out, status = as.integer(status)[1L])
}
dir_abs <- normalizePath(dir, winslash = "/", mustWork = TRUE)
status <- .status_run(
  cli,
  "--dir", dir_abs,
  "--study-type", "dbpool",
  "--outcome", "ICU mortality and remaining length of stay",
  "--exposure", "Multi-database pooling / transfer learning TPC",
  "--databases", "AmsterdamUMC,MIMIC-IV,eICU,HiRID"
)
cat(paste(status$out, collapse = "\n"), "\n")
if (!identical(status$status, 0L)) {
  stop("finalize_delivery_root failed status=", status$status, call. = FALSE)
}

qc <- file.path(engine, "run/pub/run_pub_qc_after_project.R")
if (file.exists(qc)) {
  qc_res <- .status_run(qc, "--project", dir_abs)
  cat(paste(qc_res$out, collapse = "\n"), "\n")
}

# Midterm rebuild if content.json already present (engine hook; Agent writes content once)
mid_py <- file.path(engine, ".cursor/skills/Aiya-NB004-midterm-report/engine/build_report.py")
content_json <- file.path(dir, "content.json")
if (file.exists(mid_py) && file.exists(content_json)) {
  message("Rebuilding midterm PDF from existing content.json …")
  mid_res <- .status_run(
    "python3", mid_py,
    "--build",
    "--project", dir_abs,
    "--content", normalizePath(content_json, winslash = "/", mustWork = TRUE)
  )
  cat(paste(mid_res$out, collapse = "\n"), "\n")
  # prune again so midterm workspace junk leaves delivery root
  prune_res <- .status_run(cli, "--dir", dir_abs, "--prune-only")
  cat(paste(prune_res$out, collapse = "\n"), "\n")
}

cat("DBPOOL_DELIVERY_OK dir=", normalizePath(dir), "\n", sep = "")
