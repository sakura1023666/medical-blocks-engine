#!/usr/bin/env Rscript
# Polish eICU 【success】GAR: Lai Table1/3 + restore S1–S6 names; purge junk
root <- "/mnt/e/01block/01Block-new-Final"
setwd(root)
options(warn = 1)
source("R/utils.R")
source("R/mi_rubin_pool.R")
source("R/pipeline_runner.R")
source("R/study_batch_runner.R")
source("configs/indices/composite_index_vars.R")

cfg_path <- "/mnt/g/02block_result/33_AKI/Competing_risk_CRRT_28d/config_competing_risk_aki_crrt_eicu.R"
sys.source(cfg_path, envir = environment())
unit <- "GAR"
unit_dir <- file.path(config$study_batch$output_base, "by_unit", paste0("\u3010success\u3011", unit))
stopifnot(dir.exists(unit_dir))
ck_dir <- file.path(unit_dir, "checkpoints")
tab_dir <- file.path(unit_dir, "Tables")
fig_dir <- file.path(unit_dir, "Figures")

ctx <- tryCatch(study_batch_load_checkpoint_ctx(ck_dir, "competing_pub_export"), error = function(e) NULL)
if (is.null(ctx)) ctx <- study_batch_load_checkpoint_ctx(ck_dir, "competing_supp_tables")
if (is.null(ctx)) stop("no checkpoint")
ctx$config <- config
ctx$config$competing_risk$index_var <- unit
ctx$config$competing_risk$age_cutoff <- 65L
ctx$config$project$output_dir <- unit_dir
ctx$config$project$root <- root
ctx$config$project$database <- "eICU"

for (f in c(
  "Blocks/55_competing_risk/14block_competing_baseline_quartile.R",
  "Blocks/55_competing_risk/15block_competing_baseline_trajectory.R",
  "Blocks/55_competing_risk/18block_competing_pub_export.R",
  "R/competing_risk_pub.R", "R/pub_figure_export.R", "R/pub_xlsx_surgical.R"
)) if (file.exists(f)) try(source(f, local = FALSE), silent = TRUE)

# Rebuild Lai Table 1 / 3
pl <- list(
  name = "gar_eicu_baseline_polish",
  blocks = c("competing_baseline_quartile", "competing_baseline_trajectory"),
  checkpoint = list(enable = FALSE, dir = ck_dir)
)
message(">>> rebuild Table1/3")
ctx2 <- run_pipeline(root, config = ctx$config, pipeline = pl, run_opts = list(initial_ctx = ctx))

# Restore Lai S1–S6 filenames (pipeline renumber may have shifted after UV/MI mirror)
.map <- list(
  list(from = "^Table S1-eICU\\. Subgroup analysis by quartile",
       to = "Table S1-eICU. Subgroup analysis by quartile.xlsx"),
  list(from = "^Table S3-eICU\\. Standard Cox by quartile",
       to = "Table S2-eICU. Standard Cox by quartile (sensitivity).xlsx"),
  list(from = "^Table S5-eICU\\. Competing-risk Cox sensitivity",
       to = "Table S3-eICU. Competing-risk Cox sensitivity (extremes handled).xlsx"),
  list(from = "^Table S6-eICU\\. Standard Cox sensitivity",
       to = "Table S4-eICU. Standard Cox sensitivity (extremes handled).xlsx"),
  list(from = "^Table S7-eICU\\. Subgroup analysis by trajectory",
       to = "Table S5-eICU. Subgroup analysis by trajectory.xlsx"),
  list(from = "^Table S8-eICU\\. Standard Cox by trajectory",
       to = "Table S6-eICU. Standard Cox by trajectory.xlsx"),
  # already-correct names after a prior polish
  list(from = "^Table S2-eICU\\. Standard Cox by quartile",
       to = "Table S2-eICU. Standard Cox by quartile (sensitivity).xlsx"),
  list(from = "^Table S3-eICU\\. Competing-risk Cox sensitivity",
       to = "Table S3-eICU. Competing-risk Cox sensitivity (extremes handled).xlsx"),
  list(from = "^Table S4-eICU\\. Standard Cox sensitivity",
       to = "Table S4-eICU. Standard Cox sensitivity (extremes handled).xlsx"),
  list(from = "^Table S5-eICU\\. Subgroup analysis by trajectory",
       to = "Table S5-eICU. Subgroup analysis by trajectory.xlsx"),
  list(from = "^Table S6-eICU\\. Standard Cox by trajectory",
       to = "Table S6-eICU. Standard Cox by trajectory.xlsx")
)

fs <- list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)
# First move known shifted roles via content-ish basename match (prefer highest current number first)
role_moves <- c(
  "Subgroup analysis by quartile" = "Table S1-eICU. Subgroup analysis by quartile.xlsx",
  "Standard Cox by quartile \\(sensitivity\\)" = "Table S2-eICU. Standard Cox by quartile (sensitivity).xlsx",
  "Competing-risk Cox sensitivity \\(extremes handled\\)" = "Table S3-eICU. Competing-risk Cox sensitivity (extremes handled).xlsx",
  "Standard Cox sensitivity \\(extremes handled\\)" = "Table S4-eICU. Standard Cox sensitivity (extremes handled).xlsx",
  "Subgroup analysis by trajectory" = "Table S5-eICU. Subgroup analysis by trajectory.xlsx",
  "Standard Cox by trajectory" = "Table S6-eICU. Standard Cox by trajectory.xlsx"
)
for (pat in names(role_moves)) {
  hit <- fs[grepl(pat, basename(fs), perl = TRUE)]
  hit <- hit[grepl("-eICU\\.", basename(hit))]
  if (!length(hit)) next
  dest <- file.path(tab_dir, role_moves[[pat]])
  if (!identical(normalizePath(hit[1], mustWork = FALSE), normalizePath(dest, mustWork = FALSE))) {
    if (file.exists(dest) && !identical(hit[1], dest)) unlink(dest)
    file.rename(hit[1], dest)
    message("rename: ", basename(hit[1]), " -> ", basename(dest))
  }
}

# Purge non-Lai tables
ws <- file.path(dirname(unit_dir), paste0(basename(unit_dir), "_delivery_workspace"), "Tables_internal")
dir.create(ws, recursive = TRUE, showWarnings = FALSE)
keep_re <- "^(Table [1-4]-eICU\\.|Table S[1-6]-eICU\\.)"
for (f in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
  if (!grepl(keep_re, basename(f), perl = TRUE)) {
    dest <- file.path(ws, basename(f))
    if (file.exists(dest)) unlink(dest)
    file.rename(f, dest)
    message("prune table: ", basename(f))
  }
}

# Purge Figure S / Lasso junk
.purge_fig <- function(dir) {
  if (!dir.exists(dir)) return(invisible(NULL))
  fs <- list.files(dir, full.names = TRUE, recursive = FALSE)
  bn <- basename(fs)
  drop <- grepl("(?i)(^Figure\\s*S|Missing|Lasso|Random\\s*forest|S2[A-G]\\.)", bn, perl = TRUE)
  drop <- drop | (grepl("(?i)\\.pdf$", bn) & !grepl("^Figure [0-9]+-", bn) & !dir.exists(fs))
  if (any(drop)) {
    unlink(fs[drop])
    message("purged figs in ", dir, ": ", sum(drop))
  }
}
.purge_fig(fig_dir)
.purge_fig(file.path(fig_dir, "pdf"))
.purge_fig(file.path(fig_dir, "image_information"))

# Sync A1 titles
if (exists("pub_sync_xlsx_a1_titles_to_filenames", mode = "function")) {
  try(pub_sync_xlsx_a1_titles_to_filenames(tab_dir), silent = TRUE)
}
scrub <- file.path(root, "python/pub_xlsx_scrub_display.py")
for (f in list.files(tab_dir, pattern = "\\.xlsx$", full.names = TRUE)) {
  system2("python3", c(scrub, f, "--times-only"))
}

message("DONE polish; tables:")
print(list.files(tab_dir, pattern = "\\.xlsx$"))
message("figures pdf:")
print(list.files(file.path(fig_dir, "pdf"), pattern = "\\.pdf$"))
