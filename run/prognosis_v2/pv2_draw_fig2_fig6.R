# 新项目补画 Figure 2 / Figure 6（不重跑 Boruta）
engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "R/utils.R"), local = FALSE)
source(file.path(engine, "run/prognosis_v2/pv2_paths.R"), local = FALSE)
pv2_ensure_dirs()
suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(survival)
  library(grid)
})
tab_dir <- pv2_tab_dir
fig_dir <- pv2_fig_dir
ckpt_dir <- pv2_ckpt_dir
out_root <- pv2_out_root
dbs <- readRDS(pv2_artifact("imputed_dbs.rds"))
for (nm in names(dbs)) {
  dbs[[nm]]$time <- dbs[[nm]]$futime_years
  dbs[[nm]]$event <- dbs[[nm]]$fustatus
}

# ---- Fig 2 ----
src <- readLines(file.path(engine, "run/prognosis_v2/redraw_pub_figures.R"), warn = FALSE)
i0 <- grep("^theme_pub\\s*<-|^pv2_fig2_database\\s*<-", src)[1]
i1 <- grep('^message\\("KM', src)[1] - 1L
eval(parse(text = paste(src[i0:i1], collapse = "\n")), envir = .GlobalEnv)
bor_obj <- readRDS(pv2_artifact("Boruta_objects.rds"))
shap_df <- as.data.frame(readRDS(pv2_artifact("SHAP_long.rds")))
shap_csv <- pv2_artifact("SHAP_by_database.csv")
mean_tab <- as.data.frame(fread(shap_csv))
# 只画主库；CHARLS 外验不进 Figure 2
fig2_dbs <- intersect(pv2_primary_dbs, names(bor_obj))
if (!length(fig2_dbs)) fig2_dbs <- setdiff(names(bor_obj), pv2_validation_dbs)
bor_obj <- bor_obj[fig2_dbs]
mean_tab <- mean_tab[mean_tab$database %in% fig2_dbs, , drop = FALSE]
shap_df <- shap_df[shap_df$database %in% fig2_dbs, , drop = FALSE]
fig2 <- file.path(fig_dir, "Figure 2. Boruta confirmation and SHAP values for all-cause mortality.pdf")
blocks <- lapply(fig2_dbs, function(nm) pv2_fig2_database(bor_obj[[nm]], shap_df, nm, mean_tab))
fig2_h <- if (length(blocks) <= 2L) 11.2 else 16.5
grDevices::cairo_pdf(fig2, width = 10.5, height = fig2_h, family = "Times")
grid::grid.newpage()
nblk <- length(blocks)
for (i in seq_len(nblk)) {
  y0 <- 1 - i / nblk
  grid::pushViewport(grid::viewport(y = y0, height = 1 / nblk, just = c("centre", "bottom")))
  grid::grid.text(blocks[[i]]$title, x = 0.02, y = 0.98, just = c("left", "top"),
                  gp = grid::gpar(fontsize = 11, fontface = "bold", fontfamily = "Times"))
  panels <- blocks[[i]][c("A", "B", "C", "D")]
  for (j in seq_along(panels)) {
    col <- if (j %% 2L == 1L) 0 else 1
    row <- if (j <= 2L) 1 else 0
    print(panels[[j]], vp = grid::viewport(
      x = 0.02 + col * 0.49, y = 0.04 + row * 0.46,
      width = 0.47, height = 0.44, just = c("left", "bottom")
    ))
  }
  grid::popViewport()
}
grDevices::dev.off()
message("fig2: ", fig2, " dbs=", paste(fig2_dbs, collapse = ","))

# ---- Fig 6 ----
source(file.path(engine, "run/prognosis_v2/pv2_mediation.R"), local = FALSE)
pv2_run_mediation(dbs, ckpt_dir, fig_dir)
message("fig6 done")

source(file.path(engine, "R/pub_figure_export.R"), local = FALSE)
pub_figure_ensure_formats(
  file.path(out_root, "Figures"),
  meta = list(
    databases = c("NHANES", "CHARLS", "SHHS"),
    exposure = "Sleep duration",
    outcome = "All-cause mortality",
    tables_dir = tab_dir
  ),
  config = list(pub_figures = list(dpi = 600L, write_image_information = TRUE))
)
message("formats done")
