#!/usr/bin/env Rscript
###############################################################################
# assemble_pub_figures.R — 拼 Fig.2 / Fig.4 多库面板 + Fig.S1 纳排
# Fig.3 本轮不动
#
# 用法（项目根）:
#   Rscript run/multimorbidity/scripts/assemble_pub_figures.R
###############################################################################

args <- commandArgs(trailingOnly = TRUE)
.root_candidates <- c(
  normalizePath(getwd(), winslash = "/", mustWork = FALSE),
  "E:/01block/01Block",
  "/mnt/e/01block/01Block"
)
root <- NA_character_
for (cand in .root_candidates) {
  if (file.exists(file.path(cand, "R", "pipeline_runner.R"))) {
    root <- cand
    break
  }
}
if (is.na(root)) stop("Cannot locate 01Block root", call. = FALSE)
setwd(root)

`%||%` <- function(a, b) if (!is.null(a) && length(a)) a else b

.out_root <- "G:/02block_result/60_abdominal_obesity"
.panel_dir <- file.path(root, "Data/multimorbidity_04298/panels")
.fig_dir <- file.path(.out_root, "Figures", "pdf")
.tbl_dir <- file.path(.out_root, "Tables")
dir.create(.fig_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(.tbl_dir, recursive = TRUE, showWarnings = FALSE)

.unit_dir <- function(unit) {
  cands <- c(
    file.path(.out_root, "by_unit", paste0("【success】", unit)),
    file.path(.out_root, "by_unit", unit),
    file.path(.out_root, unit)
  )
  hit <- cands[dir.exists(cands)]
  if (!length(hit)) return(NA_character_)
  hit[[1L]]
}

.find_csv <- function(unit, pattern) {
  d <- .unit_dir(unit)
  if (is.na(d)) return(NA_character_)
  hits <- list.files(d, pattern = pattern, recursive = TRUE, full.names = TRUE)
  if (!length(hits)) return(NA_character_)
  hits[[1L]]
}

.pick_model <- function(tab, prefer = c("Model3", "Model2", "Model1")) {
  mods <- unique(as.character(tab$model))
  for (m in prefer) if (m %in% mods) return(m)
  mods[[1L]]
}

.extract_cat_gee <- function(unit, cat_prefix = "Multimorbidity_cat") {
  p <- .find_csv(unit, "^Table_GEE_Cognition_Multimorbidity\\.csv$")
  if (is.na(p)) p <- .find_csv(unit, "Table_GEE_Cognition_Multimorbidity\\.csv$")
  if (is.na(p)) return(NULL)
  tab <- utils::read.csv(p, stringsAsFactors = FALSE)
  mod <- .pick_model(tab)
  fd <- tab[tab$model == mod & grepl(paste0("^", cat_prefix), tab$term), , drop = FALSE]
  if (!nrow(fd)) return(NULL)
  fd$label <- sub(paste0("^", cat_prefix), "", fd$term)
  fd$cohort <- sub("_.*$", "", unit)
  fd$indicator <- sub("^.*_", "", unit)
  fd$model_used <- mod
  .normalize_gee_cols(fd)
}

.normalize_gee_cols <- function(fd) {
  need <- c("model", "term", "beta", "se", "lo95", "hi95", "p", "n",
            "label", "cohort", "indicator", "model_used")
  for (nm in need) if (!nm %in% names(fd)) fd[[nm]] <- NA
  fd[, need, drop = FALSE]
}

.extract_traj_gee <- function(unit) {
  p <- .find_csv(unit, "Table_GEE_Trajectory_Multimorbidity\\.csv$")
  if (is.na(p)) return(NULL)
  tab <- utils::read.csv(p, stringsAsFactors = FALSE)
  mod <- .pick_model(tab)
  fd <- tab[tab$model == mod & grepl("^trajectory_cluster", tab$term), , drop = FALSE]
  if (!nrow(fd)) return(NULL)
  fd$label <- sub("^trajectory_cluster", "", fd$term)
  fd$cohort <- sub("_.*$", "", unit)
  fd$indicator <- sub("^.*_", "", unit)
  fd$model_used <- mod
  .normalize_gee_cols(fd)
}

.forest_panel <- function(df, title, outfile) {
  if (is.null(df) || !nrow(df)) {
    message("skip empty panel: ", title)
    return(invisible(NULL))
  }
  if (!requireNamespace("ggplot2", quietly = TRUE)) stop("need ggplot2")
  df$cohort <- factor(df$cohort, levels = c("CHARLS", "ELSA", "HRS"))
  p <- ggplot2::ggplot(df, ggplot2::aes(beta, label)) +
    ggplot2::geom_vline(xintercept = 0, linetype = 2, color = "grey50") +
    ggplot2::geom_point(size = 2.2) +
    ggplot2::geom_errorbar(
      ggplot2::aes(xmin = lo95, xmax = hi95),
      orientation = "y", width = 0.2
    ) +
    ggplot2::facet_wrap(~cohort, ncol = 1, scales = "free_y") +
    ggplot2::theme_bw(base_family = "serif") +
    ggplot2::labs(
      title = title,
      x = "Standardized beta (95% CI)", y = NULL
    )
  ggplot2::ggsave(outfile, p, width = 7.5, height = max(5, 1.6 * length(unique(df$cohort)) + 0.8 * length(unique(df$label))))
  message("wrote ", outfile)
}

# ---- Fig.2 panels (BMI / WHtR) ----
bmi_units <- c("CHARLS_BMI", "ELSA_BMI", "HRS_BMI")
whtr_units <- c("CHARLS_WHtR", "ELSA_WHtR", "HRS_WHtR")

fig2_bmi <- do.call(rbind, lapply(bmi_units, .extract_cat_gee))
fig2_whtr <- do.call(rbind, lapply(whtr_units, .extract_cat_gee))
.forest_panel(
  fig2_bmi,
  "Figure 2A. Baseline multimorbidity GEE (BMI)",
  file.path(.fig_dir, "Figure 2A. Baseline multimorbidity GEE BMI.pdf")
)
.forest_panel(
  fig2_whtr,
  "Figure 2B. Baseline multimorbidity GEE (WHtR)",
  file.path(.fig_dir, "Figure 2B. Baseline multimorbidity GEE WHtR.pdf")
)
if (!is.null(fig2_bmi)) utils::write.csv(fig2_bmi, file.path(.tbl_dir, "Figure2A_panel_source.csv"), row.names = FALSE)
if (!is.null(fig2_whtr)) utils::write.csv(fig2_whtr, file.path(.tbl_dir, "Figure2B_panel_source.csv"), row.names = FALSE)

# ---- Fig.4 panels ----
fig4_bmi <- do.call(rbind, lapply(bmi_units, .extract_traj_gee))
fig4_whtr <- do.call(rbind, lapply(whtr_units, .extract_traj_gee))
.forest_panel(
  fig4_bmi,
  "Figure 4A. Joint trajectory GEE (BMI)",
  file.path(.fig_dir, "Figure 4A. Trajectory GEE BMI.pdf")
)
.forest_panel(
  fig4_whtr,
  "Figure 4B. Joint trajectory GEE (WHtR)",
  file.path(.fig_dir, "Figure 4B. Trajectory GEE WHtR.pdf")
)
if (!is.null(fig4_bmi)) utils::write.csv(fig4_bmi, file.path(.tbl_dir, "Figure4A_panel_source.csv"), row.names = FALSE)
if (!is.null(fig4_whtr)) utils::write.csv(fig4_whtr, file.path(.tbl_dir, "Figure4B_panel_source.csv"), row.names = FALSE)

# ---- Fig.S1 attrition from panel attrition CSVs ----
.draw_s1 <- function() {
  files <- list.files(file.path(.panel_dir, "attrition"), pattern = "^attrition_.*\\.csv$", full.names = TRUE)
  files <- files[!grepl("early|late", basename(files), ignore.case = TRUE)]
  if (!length(files)) {
    message("no attrition CSVs for S1")
    return(invisible(NULL))
  }
  rows <- lapply(files, function(f) {
    d <- utils::read.csv(f, stringsAsFactors = FALSE)
    co <- sub("^attrition_", "", tools::file_path_sans_ext(basename(f)))
    d$cohort <- toupper(co)
    d
  })
  all <- do.call(rbind, rows)
  utils::write.csv(all, file.path(.tbl_dir, "Figure S1. Attrition steps source.csv"), row.names = FALSE)

  if (!requireNamespace("ggplot2", quietly = TRUE)) return(invisible(NULL))
  # 取关键步骤人数做阶梯条：每队列一条线
  all$step_order <- as.integer(factor(all$step, levels = unique(all$step)))
  p <- ggplot2::ggplot(all, ggplot2::aes(step_order, n_id, color = cohort, group = cohort)) +
    ggplot2::geom_line(linewidth = 1) +
    ggplot2::geom_point(size = 2) +
    ggplot2::scale_x_continuous(
      breaks = seq_along(unique(all$step)),
      labels = unique(all$step)
    ) +
    ggplot2::theme_bw(base_family = "serif") +
    ggplot2::theme(axis.text.x = ggplot2::element_text(angle = 25, hjust = 1, size = 7)) +
    ggplot2::labs(
      title = "Figure S1. Participant selection (three cohorts)",
      subtitle = "Panel build attrition (pre-analysis); MHAS skipped",
      x = NULL, y = "N individuals", color = NULL
    )
  ggplot2::ggsave(
    file.path(.fig_dir, "Figure S1. Participant selection.pdf"),
    p, width = 10, height = 5
  )
  message("wrote Figure S1")
}
.draw_s1()

message("assemble_pub_figures done -> ", .fig_dir)
