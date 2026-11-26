#!/usr/bin/env Rscript
# 竞争风险单库 unit → summary_results 收口
#   Rscript run/competing_risk/finalize_unit_summary_results.R \
#     --unit-root ".../MIMIC/by_unit/【success】GAR" \
#     --config ".../config_competing_risk_aki_crrt_mimic.R"

args <- commandArgs(trailingOnly = TRUE)
get_opt <- function(flag, default = NULL) {
  hit <- which(args == flag)
  if (!length(hit) || hit[[1]] >= length(args)) return(default)
  i <- hit[[1]] + 1L
  parts <- character(0)
  while (i <= length(args) && !grepl("^--", args[[i]])) {
    parts <- c(parts, args[[i]])
    i <- i + 1L
  }
  if (!length(parts)) return(default)
  paste(parts, collapse = " ")
}

eng <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(eng) || !dir.exists(file.path(eng, "R"))) {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", ca[grep("^--file=", ca)])
  if (length(f)) {
    eng <- normalizePath(file.path(dirname(f[[1]]), "..", ".."),
                         winslash = "/", mustWork = FALSE)
  }
}
if (!dir.exists(file.path(eng, "R"))) eng <- "/mnt/e/01block/01Block-new-Final"
Sys.setenv(MEDICAL_BLOCKS_ROOT = eng)
setwd(eng)

source(file.path(eng, "R/utils.R"), local = FALSE)
source(file.path(eng, "R/competing_risk_pub_finalize.R"), local = FALSE)

cfg_path <- get_opt("--config", "")
unit_root <- get_opt("--unit-root", "")
config <- NULL
if (nzchar(cfg_path)) {
  if (!file.exists(cfg_path)) stop("config not found: ", cfg_path, call. = FALSE)
  source(cfg_path, local = FALSE)
  if (!exists("config", inherits = FALSE)) stop("config object missing after source", call. = FALSE)
}
if (!nzchar(unit_root)) {
  stop("need --unit-root <.../by_unit/【success】INDEX>", call. = FALSE)
}

sr <- competing_finalize_unit_summary_results(unit_root, config = config)
# midterm project info (client / no date from config$pub$midterm)
pub <- (config %||% list())$pub %||% list()
mt <- pub$midterm %||% list()
client <- as.character(mt$client %||% pub$midterm_client %||% "静")[1L]
no_date <- if (!is.null(mt$no_date)) isTRUE(mt$no_date) else isTRUE(pub$midterm_no_date %||% TRUE)
exposure <- as.character(
  (config %||% list())$project$exposure_var %||%
    basename(gsub("【success】|【failed】", "", unit_root))
)[1L]
db <- as.character(((config %||% list())$project %||% list())$database %||% "MIMIC")[1L]
competing_write_midterm_project_info(
  sr,
  exposure = exposure,
  client = client,
  no_date = no_date,
  database = db
)
cat("SUMMARY_OK ", sr, "\n", sep = "")
