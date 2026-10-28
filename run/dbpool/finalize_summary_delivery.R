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
cohort <- get_opt("--cohort", "ACG-style enzyme elevation (ALT/AST ≥2×ULN)")
Sys.setenv(DBPOOL_COHORT = cohort)
drop_feat <- get_opt("--drop-features", "ALT and AST")
Sys.setenv(DBPOOL_DROP_FEATURES = drop_feat)

cli <- file.path(engine, "run/pub/finalize_delivery_root.R")
status <- system2(
  "Rscript",
  c(
    cli,
    "--dir", normalizePath(dir),
    "--study-type", "dbpool",
    "--outcome", "ICU mortality and remaining length of stay",
    "--exposure", "Multi-database pooling / transfer learning (TPC)",
    "--databases", "AmsterdamUMC,MIMIC-IV,eICU,HiRID"
  ),
  stdout = TRUE, stderr = TRUE
)
cat(paste(status, collapse = "\n"), "\n")

qc <- file.path(engine, "run/pub/run_pub_qc_after_project.R")
if (file.exists(qc)) {
  system2("Rscript", c(qc, "--project", normalizePath(dir)), stdout = TRUE, stderr = TRUE)
}

cat("DBPOOL_DELIVERY_OK dir=", normalizePath(dir), "\n", sep = "")
