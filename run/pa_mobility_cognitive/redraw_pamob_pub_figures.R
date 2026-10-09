#!/usr/bin/env Rscript
# 仅重绘 Figure 1–4 + Figure S1（发表级），不重跑模型
# "/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/pa_mobility_cognitive/redraw_pamob_pub_figures.R

.init <- function() {
  ca <- commandArgs(trailingOnly = FALSE)
  f <- grep("^--file=", ca, value = TRUE)
  if (length(f)) dirname(normalizePath(sub("^--file=", "", f[1]), winslash = "/"))
  else normalizePath(getwd(), winslash = "/")
}
script_dir <- .init()
root <- if (basename(script_dir) == "pa_mobility_cognitive") {
  normalizePath(file.path(script_dir, "..", ".."), winslash = "/")
} else script_dir
setwd(root)

source("R/pamob_utils.R")
source("R/pub_figure_export.R")

batch <- "G:/02block_result/02_Cognitive_impairment/pa_mobility_cognitive_charls_nhanes"
charls_u <- file.path(batch, "by_unit", "【success】CHARLS")
nhanes_u <- file.path(batch, "by_unit", "【success】NHANES")

# ---- Fig1 ----
pamob_draw_fig1_concept(file.path(charls_u, "Figures", "Figure 1. PA-mobility phenotype framework.pdf"))
message("Fig1 OK")

# ---- Fig2 ----
steps_path <- file.path(charls_u, "Tables", "Flowchart_attrition_CHARLS.csv")
steps <- read.csv(steps_path, stringsAsFactors = FALSE)
pamob_draw_fig2_flowchart(steps, file.path(charls_u, "Figures", "Figure 2. CHARLS flowchart.pdf"))
message("Fig2 OK")

# ---- Fig3 ----
traj <- read.csv(file.path(charls_u, "Tables", "CHARLS", "Table_Pamob_Predicted_Trajectories.csv"),
                 stringsAsFactors = FALSE)
# 必须保留 outcome + CI；勿按 Time×phenotype 丢 outcome（否则双面板塌成单面板）
if (all(c("Time_years", "phenotype", "outcome", "pred") %in% names(traj))) {
  form <- cbind(pred, se, lo, hi) ~ Time_years + phenotype + outcome
  if (!all(c("se", "lo", "hi") %in% names(traj))) form <- pred ~ Time_years + phenotype + outcome
  traj <- aggregate(form, data = traj, FUN = mean)
} else if (nrow(traj) > 50L && all(c("Time_years", "phenotype", "pred") %in% names(traj))) {
  traj <- aggregate(pred ~ Time_years + phenotype, data = traj, FUN = mean)
}
pamob_draw_fig3_traj(traj, file.path(charls_u, "Figures", "Figure 3. CHARLS cognitive trajectories.pdf"))
message("Fig3 OK")

# ---- Fig4 ----
means <- read.csv(file.path(nhanes_u, "Tables", "NHANES", "Table_Pamob_Fig4_Means.csv"),
                  stringsAsFactors = FALSE)
if (!"se" %in% names(means)) means$se <- NA_real_
fig4_dir <- file.path(nhanes_u, "Figures")
dir.create(fig4_dir, recursive = TRUE, showWarnings = FALSE)
pamob_draw_fig4_panel(means, file.path(fig4_dir, "Figure 4. NHANES DSST and NfL panel.pdf"))
message("Fig4 OK")

# ---- Figure S1 (NHANES flowchart; was S2) ----
steps_nh <- read.csv(file.path(nhanes_u, "Tables", "Flowchart_attrition_NHANES.csv"),
                     stringsAsFactors = FALSE)
pamob_draw_figs1_nhanes_flowchart(
  steps_nh, file.path(nhanes_u, "Figures", "Figure S1. NHANES flowchart.pdf")
)
old_s2_u <- list.files(file.path(nhanes_u, "Figures"), pattern = "Figure S2\\. NHANES flowchart",
                       recursive = TRUE, full.names = TRUE)
if (length(old_s2_u)) unlink(old_s2_u)
message("Fig S1 OK")

# ---- 汇总到根目录四目录 ----
config <- list(pub_figures = list(formats_dir = TRUE, write_image_information = TRUE, dpi = 300L))
for (u in c(charls_u, nhanes_u)) {
  fu <- file.path(u, "Figures")
  tryCatch(export_pub_figures(fu, config = config), error = function(e) {
    message("unit export warn: ", conditionMessage(e))
    try(pub_figure_ensure_formats(fu, config = config), silent = TRUE)
  })
}
coll <- pamob_collect_main_figures(batch)
print(coll$copied)
export_pub_figures(coll$figures_dir, config = config)
message("DONE: ", coll$figures_dir)
