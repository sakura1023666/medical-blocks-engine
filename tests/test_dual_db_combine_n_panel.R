# tests/test_dual_db_combine_n_panel.R
root <- normalizePath(getwd())
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/dual_db_combine_figures.R"), local = FALSE)

make_min_pdf <- function(path) {
  grDevices::pdf(path, width = 3, height = 2); plot.new(); title(basename(path)); grDevices::dev.off()
}

ix <- tempfile("ix3_")
figs <- file.path(ix, "Figures")
dir.create(figs, recursive = TRUE)
make_min_pdf(file.path(figs, "Figure 2-CHARLS. RCS plot.pdf"))
make_min_pdf(file.path(figs, "Figure 2-ELSA. RCS plot.pdf"))
make_min_pdf(file.path(figs, "Figure 2-HRS. RCS plot.pdf"))

cfg <- list(
  dual_db = list(
    combine_figures = list(enable = TRUE, remove_singles = TRUE, dpi = 72L),
    primary = list(name = "CHARLS"),
    secondary = list(name = "ELSA"),
    tertiary = list(name = "HRS")
  )
)
# 实现后应识别 tertiary；若暂用 databases 向量亦可：
# cfg$dual_db$databases <- c("CHARLS","ELSA","HRS")

dual_db_combine_paired_figures(ix, cfg)
stopifnot(file.exists(file.path(figs, "Figure 2. RCS plot.pdf")))
stopifnot(!file.exists(file.path(figs, "Figure 2-CHARLS. RCS plot.pdf")))
stopifnot(!file.exists(file.path(figs, "Figure 2-ELSA. RCS plot.pdf")))
stopifnot(!file.exists(file.path(figs, "Figure 2-HRS. RCS plot.pdf")))
unlink(ix, recursive = TRUE)

# figures_dir regression: cross-lagged summary_result/figure (not index_root/Figures)
ix2 <- tempfile("ix_figdir_")
fig_sr <- file.path(ix2, "summary_result", "figure")
dir.create(fig_sr, recursive = TRUE)
make_min_pdf(file.path(fig_sr, "Figure 2-eICU. RCS plot.pdf"))
make_min_pdf(file.path(fig_sr, "Figure 2-MIMIC. RCS plot.pdf"))
make_min_pdf(file.path(fig_sr, "Figure 2-HRS. RCS plot.pdf"))

cfg2 <- list(
  dual_db = list(
    combine_figures = list(enable = TRUE, remove_singles = TRUE, dpi = 72L),
    primary = list(name = "eICU"),
    secondary = list(name = "MIMIC"),
    tertiary = list(name = "HRS")
  )
)
dual_db_combine_paired_figures(ix2, cfg2, figures_dir = fig_sr)
stopifnot(file.exists(file.path(fig_sr, "Figure 2. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig_sr, "Figure 2-eICU. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig_sr, "Figure 2-MIMIC. RCS plot.pdf")))
stopifnot(!file.exists(file.path(fig_sr, "Figure 2-HRS. RCS plot.pdf")))
stopifnot(!dir.exists(file.path(ix2, "Figures")))
unlink(ix, recursive = TRUE)

# 标题不一致时按角色拼图（NHANES Weighted RCS vs MIMIC RCS plot）
ix3 <- tempfile("ix_role_")
figs3 <- file.path(ix3, "Figures")
dir.create(figs3, recursive = TRUE)
make_min_pdf(file.path(figs3, "Figure 2-NHANES. Weighted RCS of SOSM and Uterine fibroids.pdf"))
make_min_pdf(file.path(figs3, "Figure 2-MIMIC. RCS plot between SOSM and Uterine fibroids.pdf"))
cfg3 <- list(
  project = list(study_type = "incidence", exposure_var = "SOSM", outcome_label = "Uterine fibroids"),
  dual_db = list(
    combine_figures = list(enable = TRUE, remove_singles = TRUE, dpi = 72L),
    primary = list(name = "NHANES"),
    secondary = list(name = "MIMIC")
  )
)
source(file.path(root, "R/incidence_dual_batch_runner.R"), local = FALSE)
dual_db_combine_paired_figures(ix3, cfg3)
stopifnot(file.exists(file.path(figs3, "Figure 2. RCS of SOSM and Uterine fibroids.pdf")))
stopifnot(!file.exists(file.path(figs3, "Figure 2-NHANES. Weighted RCS of SOSM and Uterine fibroids.pdf")))
stopifnot(!file.exists(file.path(figs3, "Figure 2-MIMIC. RCS plot between SOSM and Uterine fibroids.pdf")))
unlink(ix3, recursive = TRUE)

cat("test_dual_db_combine_n_panel: OK\n")
