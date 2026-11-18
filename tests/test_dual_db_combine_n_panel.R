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

# 假拼图守卫：无标签图实为单库拷贝时不得跳过；purge 不得删对侧底稿
ix4 <- tempfile("ix_fake_dual_")
figs4 <- file.path(ix4, "Figures")
dir.create(file.path(figs4, "pdf"), recursive = TRUE)
make_min_pdf(file.path(figs4, "Figure 8-eICU. Subgroup Forest analyses of ACAG.pdf"))
make_min_pdf(file.path(figs4, "Figure 8-MIMIC IV. Subgroup Forest analyses of ACAG.pdf"))
# 冒充已拼图：拷贝 MIMIC 单库为无标签
file.copy(
  file.path(figs4, "Figure 8-MIMIC IV. Subgroup Forest analyses of ACAG.pdf"),
  file.path(figs4, "Figure 8. Subgroup Forest analyses of ACAG.pdf"),
  overwrite = TRUE
)
file.copy(
  file.path(figs4, "Figure 8. Subgroup Forest analyses of ACAG.pdf"),
  file.path(figs4, "pdf/Figure 8. Subgroup Forest analyses of ACAG.pdf"),
  overwrite = TRUE
)
cfg4 <- list(
  project = list(study_type = "incidence", exposure_var = "ACAG", disease = "T2DM"),
  ml_batch = list(pub_figure_scheme = "ml_dual_dev_ext"),
  dual_db = list(
    combine_figures = list(enable = TRUE, remove_singles = TRUE, dpi = 72L),
    primary = list(name = "eICU"),
    secondary = list(name = "MIMIC IV")
  )
)
stopifnot(!isTRUE(.dual_db_pdf_looks_like_dual_panel(
  file.path(figs4, "Figure 8. Subgroup Forest analyses of ACAG.pdf"),
  ref_singles = file.path(figs4, "Figure 8-MIMIC IV. Subgroup Forest analyses of ACAG.pdf")
)))
fake_sz <- file.info(file.path(figs4, "Figure 8. Subgroup Forest analyses of ACAG.pdf"))$size
dual_db_combine_paired_figures(ix4, cfg4)
out4 <- file.path(figs4, "Figure 8. Subgroup Forest analyses of ACAG.pdf")
stopifnot(file.exists(out4))
# 重拼后不应仍是单库拷贝尺寸
stopifnot(!identical(as.integer(file.info(out4)$size), as.integer(fake_sz)) ||
            isTRUE(.dual_db_pdf_looks_like_dual_panel(out4)))
# purge：同尺寸假无标签不得清掉分库底稿
make_min_pdf(file.path(figs4, "pdf/_single_ref.pdf"))
file.copy(file.path(figs4, "pdf/_single_ref.pdf"),
          file.path(figs4, "pdf/Figure 8. Subgroup Forest analyses of ACAG.pdf"),
          overwrite = TRUE)
file.copy(file.path(figs4, "pdf/_single_ref.pdf"),
          file.path(figs4, "pdf/Figure 8-eICU. Subgroup Forest analyses of ACAG.pdf"),
          overwrite = TRUE)
purged4 <- dual_db_purge_redundant_split_figures(
  figs4, db_names = c("eICU", "MIMIC IV", "MIMIC")
)
stopifnot(!any(grepl("Figure 8-eICU", purged4, fixed = TRUE)))
unlink(ix4, recursive = TRUE)

cat("test_dual_db_combine_n_panel: OK\n")
