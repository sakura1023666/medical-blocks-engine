#!/usr/bin/env Rscript
# Backfill ALBI pub figures to survival dual-batch defaults + redraw forest/boxplot.
Sys.setenv(MEDICAL_BLOCKS_ROOT = "/mnt/e/01block/01Block-new-Final")
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
source(file.path(root, "R/utils.R"))
source(file.path(root, "R/subgroup_forest_plot.R"), local = FALSE)
source(file.path(root, "Blocks/05_boxplot/01block_boxplot.R"), local = FALSE)

suppressPackageStartupMessages({
  library(survival)
  library(ggplot2)
})

study <- "/mnt/g/DockerHome/5001/medical-blocks-studies/studies/01_ARDS/prognosis_38902748"
albi <- file.path(study, "by_index", "【success】ALBI")
cp_root <- file.path(study, "checkpoints/by_index/ALBI")

`%||%` <- function(a, b) if (!is.null(a)) a else b

# ---- 1) Rename figures (collision-safe order) ---------------------------------
# Fig3→S1, Fig6→S4, Fig7→S2, Fig8→S3, then Fig4→Fig3, Fig5→Fig4
rename_rules <- list(
  list(from = "^Figure 3", to = "Figure S1"),
  list(from = "^Figure 6", to = "Figure S4"),
  list(from = "^Figure 7", to = "Figure S2"),
  list(from = "^Figure 8", to = "Figure S3"),
  list(from = "^Figure 4", to = "Figure 3"),
  list(from = "^Figure 5", to = "Figure 4")
)

fig_dirs <- unique(c(
  file.path(albi, "Figures"),
  file.path(albi, "eICU", "Figures"),
  file.path(albi, "MIMIC", "Figures"),
  list.dirs(albi, recursive = TRUE, full.names = TRUE)
))
fig_dirs <- fig_dirs[basename(fig_dirs) == "Figures" | grepl("/Figures$", fig_dirs)]
fig_dirs <- unique(fig_dirs[dir.exists(fig_dirs)])

rename_in_dir <- function(d) {
  files <- list.files(d, full.names = TRUE)
  files <- files[grepl("\\.(pdf|svg)$", files, ignore.case = TRUE)]
  for (rule in rename_rules) {
    hit <- files[grepl(rule$from, basename(files))]
    # skip already-supplementary if rule is for main Fig 3-8 only
    hit <- hit[!grepl("^Figure S", basename(hit))]
    for (f in hit) {
      bn <- basename(f)
      new_bn <- sub(rule$from, rule$to, bn)
      if (identical(bn, new_bn)) next
      dest <- file.path(dirname(f), new_bn)
      if (file.exists(dest)) unlink(dest)
      ok <- file.rename(f, dest)
      if (!isTRUE(ok)) {
        file.copy(f, dest, overwrite = TRUE)
        unlink(f)
      }
      message("RENAME ", bn, " -> ", new_bn)
    }
    files <- list.files(d, full.names = TRUE)
  }
}

for (d in fig_dirs) rename_in_dir(d)

# ---- 2) Delete Table 3 subgroup tables ----------------------------------------
tab_hits <- list.files(albi, pattern = "^Table 3-.*Subgroup Analysis of ALBI\\.(xlsx|tex)$",
                       recursive = TRUE, full.names = TRUE)
n_del <- sum(file.exists(tab_hits) & file.remove(tab_hits))
message("Deleted Table 3 files: ", n_del)

# ---- 3) Redraw forest (Figure 4) + boxplot (Figure S2) per DB -----------------
redraw_one <- function(db) {
  message("=== redraw ", db, " ===")
  options(pipeline.database_name = db)
  obj <- readRDS(file.path(cp_root, db, "subgroup_prognosis.rds"))
  ctx <- obj$ctx
  cfg <- ctx$config
  cfg$subgroup <- utils::modifyList(cfg$subgroup %||% list(), list(
    export_table = FALSE,
    forest_force_single_page = TRUE,
    figure_kind = "main_figure",
    figure_number = 4L,
    bump_counter = TRUE
  ))
  cfg$subgroup_prognosis <- utils::modifyList(cfg$subgroup_prognosis %||% list(), list(
    figure_kind = "main_figure", figure_number = 4L, bump_counter = TRUE
  ))
  cfg$boxplot <- utils::modifyList(cfg$boxplot %||% list(), list(
    figure_kind = "supp_figure", figure_number = 2L, bump_counter = FALSE
  ))
  cfg$project <- utils::modifyList(cfg$project %||% list(), list(
    mirror_pub_outputs_to_root = TRUE,
    database = db,
    database_type = db
  ))
  ctx$config <- cfg
  # output dirs → ALBI db folders
  out_db <- file.path(albi, db)
  ctx$output_dir <- out_db
  ctx$output_dir_figures <- file.path(out_db, "Figures")
  ctx$output_dir_tables <- file.path(out_db, "Tables")
  ctx$root_output_dir <- albi
  dir.create(ctx$output_dir_figures, recursive = TRUE, showWarnings = FALSE)

  # reset pub counters so fixed numbers land correctly
  if (exists("pub_state_reset", mode = "function")) {
    try(pub_state_reset(), silent = TRUE)
  }
  .pub_state <<- list(main_figure = 1L, supp_figure = 0L, main_table = 0L, supp_table = 0L)

  res <- ctx$results$subgroup
  if (is.null(res) || !is.data.frame(res) || !nrow(res)) {
    message("No subgroup table in checkpoint; skip forest")
  } else {
    effect_sym <- ctx$results$subgroup_effect %||% "HR"
    plot_df <- subgroup_prepare_forest_plot_df(res, effect_sym)
    sub_cfg <- utils::modifyList(cfg$subgroup %||% list(), cfg$subgroup_prognosis %||% list())
    arrow_lab <- c(
      paste0("Decreased Risk for ", cfg$project$analysis_group %||% "Non-survivor"),
      paste0("Increased Risk for ", cfg$project$analysis_group %||% "Non-survivor")
    )
    # remove old Fig4/Fig5 forest names if any leftover
    old_f <- list.files(ctx$output_dir_figures, pattern = "Subgroup Forest", full.names = TRUE)
    if (length(old_f)) file.remove(old_f)
    old_root <- list.files(file.path(albi, "Figures"), pattern = paste0("Subgroup Forest.*", db), full.names = TRUE)
    if (length(old_root)) file.remove(old_root)

    subgroup_render_forest_figure(
      ctx, plot_df, ctx$results$subgroup_vars_used %||% character(0),
      sub_cfg,
      fig_caption = paste0("Subgroup Forest analyses of ALBI"),
      effect_sym = effect_sym,
      arrow_lab = arrow_lab
    )
  }

  # boxplot from imputed
  data <- as.data.frame(ctx$data$imputed %||% ctx$data$cleaned)
  ev <- cfg$survival$event_var %||% "fustatus"
  # map 0/1 to Survivor/Non-survivor labels if needed
  if (is.numeric(data[[ev]]) || all(unique(na.omit(as.character(data[[ev]]))) %in% c("0", "1"))) {
    lab0 <- cfg$project$reference_group %||% "Survivor"
    lab1 <- cfg$project$analysis_group %||% "Non-survivor"
    data[[ev]] <- factor(
      ifelse(as.numeric(as.character(data[[ev]])) == 1, lab1, lab0),
      levels = c(lab0, lab1)
    )
  }
  ctx$data$imputed <- data
  ctx$config$boxplot$group_var <- ev
  ctx$config$boxplot$response_vars <- "ALBI"
  # remove old boxplots
  old_b <- list.files(ctx$output_dir_figures, pattern = "Boxplot", full.names = TRUE)
  if (length(old_b)) file.remove(old_b)
  old_br <- list.files(file.path(albi, "Figures"), pattern = paste0("Boxplot.*", db), full.names = TRUE)
  if (length(old_br)) file.remove(old_br)

  ctx2 <- block_boxplot(ctx)
  invisible(TRUE)
}

for (db in c("eICU", "MIMIC")) redraw_one(db)

# Also copy renamed/new files to root Figures if mirror missed some
# Verify
cat("\n===== ROOT Figures =====\n")
print(sort(list.files(file.path(albi, "Figures"), pattern = "\\.pdf$")))
cat("\n===== Table 3 left? =====\n")
print(list.files(albi, pattern = "Table 3-", recursive = TRUE))

for (db in c("eICU", "MIMIC")) {
  f4 <- list.files(file.path(albi, "Figures"), pattern = paste0("^Figure 4-", db, ".*Subgroup"), full.names = TRUE)
  s2 <- list.files(file.path(albi, "Figures"), pattern = paste0("^Figure S2-", db, ".*Boxplot"), full.names = TRUE)
  cat("\n", db, " forest:", f4, "\n")
  if (length(f4)) {
    cat(pdftotext <- system2("pdftotext", c("-layout", f4[1], "-"), stdout = TRUE)[1:8], sep = "\n")
    cat("\n--- age lines ---\n")
    txt <- paste(system2("pdftotext", c("-layout", f4[1], "-"), stdout = TRUE), collapse = "\n")
    cat(grep("65", strsplit(txt, "\n")[[1]], value = TRUE), sep = "\n")
  }
  if (length(s2)) {
    info <- system2("pdfinfo", s2[1], stdout = TRUE)
    cat("\nboxplot pages:\n", paste(grep("^Pages", info, value = TRUE), collapse = "\n"), "\n")
  }
}

cat("\nDONE\n")
