# tests/test_pub_figure_export.R
root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/utils.R"))) {
  # allow running from tests/
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}
source(file.path(root, "R/utils.R"), local = FALSE)
stopifnot(file.exists(file.path(root, "R/pub_figure_export.R")))
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

# 最小可栅格 PDF（1 页空白）
make_min_pdf <- function(path) {
  grDevices::pdf(path, width = 4, height = 3, onefile = TRUE)
  plot.new()
  title("test fig")
  grDevices::dev.off()
}

fd <- tempfile("pub_figs_")
dir.create(fd)
f1 <- file.path(fd, "Figure 1. Flowchart.pdf")
f2 <- file.path(fd, "Figure 2. RCS plot.pdf")
make_min_pdf(f1)
make_min_pdf(f2)
# 不应进入交付
file.create(file.path(fd, "Figure Missing Value Overview.pdf"))

meta <- list(
  exposure = "BAR",
  outcome = "Death",
  n_total = 1000L,
  n_by_db = c(eICU = 600L, MIMIC = 400L),
  databases = c("eICU", "MIMIC"),
  combined = TRUE,
  layout = "side",
  grouping = "quartile"
)

res <- export_pub_figures(fd, meta = meta, config = list(pub_figures = list(dpi = 72L)))
stopifnot(dir.exists(file.path(fd, "pdf")))
stopifnot(dir.exists(file.path(fd, "png")))
stopifnot(dir.exists(file.path(fd, "tiff")))
stopifnot(dir.exists(file.path(fd, "image_information")))
stopifnot(file.exists(file.path(fd, "pdf", "Figure 1. Flowchart.pdf")))
stopifnot(file.exists(file.path(fd, "png", "Figure 1. Flowchart.png")))
stopifnot(file.exists(file.path(fd, "tiff", "Figure 1. Flowchart.tiff")))
stopifnot(file.exists(file.path(fd, "image_information", "Figure 1. Flowchart.md")))
stopifnot(file.exists(file.path(fd, "image_information", "README.md")))
# 顶层无散落图
top <- list.files(fd, pattern = "\\.(pdf|png|tiff|tif)$", ignore.case = TRUE)
stopifnot(length(top) == 0L)
# Missing overview 不得进 pdf/
stopifnot(!file.exists(file.path(fd, "pdf", "Figure Missing Value Overview.pdf")))
md <- paste(readLines(file.path(fd, "image_information", "Figure 2. RCS plot.md"), warn = FALSE), collapse = "\n")
stopifnot(grepl("BAR", md), grepl("死亡|Death", md), grepl("quartile|四分", md))
stopifnot(grepl("剂量|反应|RCS|样条", md))
stopifnot(grepl("图面说明", md))
stopifnot(!grepl("## 标识", md), !grepl("## 技术", md))
stopifnot(!grepl("DPI:", md), !grepl("TIFF 压缩", md))

# Flowchart：逐步纳排人数应写入图面说明
meta_fc <- meta
meta_fc$findings <- list(
  attrition = list(
    list(db = "eICU", step = "Raw extract", n = 1000L),
    list(db = "eICU", step = "After exclude ESRD", n = 900L),
    list(db = "eICU", step = "Final APRI", n = 600L),
    list(db = "MIMIC", step = "Raw extract", n = 800L),
    list(db = "MIMIC", step = "Final APRI", n = 400L)
  )
)
fc_md <- tempfile("fc_md_")
pub_figure_write_image_md(fc_md, "Figure 1. Flowchart", meta = meta_fc, raster_ok = TRUE)
fc_txt <- paste(readLines(fc_md, warn = FALSE), collapse = "\n")
stopifnot(grepl("本步排除 100", fc_txt), grepl("n=900", fc_txt), grepl("### eICU", fc_txt))
stopifnot(grepl("图面说明", fc_txt), !grepl("## 标识", fc_txt))
unlink(fc_md)

# RCS：注入 findings$rcs 后必须出现「图上标注」与 P-overall
meta_rcs <- meta
meta_rcs$findings <- list(
  rcs = list(list(
    db = "MIMIC",
    panels = list(list(
      name = "Model2", p_overall = 0.001, p_nonlinear = 0.116, cutoffs = 0.52
    ))
  ))
)
rcs_md <- tempfile("rcs_md_")
pub_figure_write_image_md(rcs_md, "Figure 2. RCS plot", meta = meta_rcs, raster_ok = TRUE)
rcs_txt <- paste(readLines(rcs_md, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", rcs_txt))
stopifnot(grepl("P-overall = 0.001", rcs_txt))
stopifnot(grepl("P-non-linear = 0.116", rcs_txt))
stopifnot(grepl("0\\.52", rcs_txt))
unlink(rcs_md)

# RCS：无 findings$rcs → 明示未收获
meta_rcs_empty <- meta
meta_rcs_empty$findings <- list()
rcs_md2 <- tempfile("rcs_md2_")
pub_figure_write_image_md(rcs_md2, "Figure 2. RCS plot", meta = meta_rcs_empty, raster_ok = TRUE)
rcs_txt2 <- paste(readLines(rcs_md2, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", rcs_txt2))
stopifnot(grepl("未收获", rcs_txt2))
unlink(rcs_md2)

# KM
meta_km <- meta
meta_km$findings <- list(km = list(list(db = "eICU", logrank_p = 0.023, cutoff = 1.25)))
km_md <- tempfile("km_md_")
pub_figure_write_image_md(km_md, "Figure 3. KM curve", meta = meta_km, raster_ok = TRUE)
km_txt <- paste(readLines(km_md, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", km_txt), grepl("Log-rank", km_txt), grepl("0\\.023", km_txt))
unlink(km_md)

# Forest
meta_fo <- meta
meta_fo$findings <- list(forest = list(list(
  db = "eICU",
  rows = data.frame(
    Variable = c("Overall", "Sex: Male"),
    `Point Estimate` = c(1.2, 1.3),
    Lower = c(1.0, 0.9), Upper = c(1.4, 1.8),
    `P for interaction` = c(NA, 0.12),
    check.names = FALSE, stringsAsFactors = FALSE
  )
)))
fo_md <- tempfile("fo_md_")
pub_figure_write_image_md(fo_md, "Figure 4. Subgroup forest plot", meta = meta_fo, raster_ok = TRUE)
fo_txt <- paste(readLines(fo_md, warn = FALSE), collapse = "\n")
stopifnot(grepl("图上标注", fo_txt), grepl("Overall", fo_txt), grepl("1\\.2", fo_txt))
unlink(fo_md)

# KM：有 Table 2 数字时应写进正文一句话
meta_find <- meta
meta_find$findings <- list(
  association = list(list(
    db = "eICU", metric = "HR", high_label = "Q4",
    estimate = "1.651", ci = "(1.068, 2.552)", p = "0.0242", trend_p = "0.0179",
    continuous_est = "1.011", continuous_ci = "(1.001, 1.020)", continuous_p = "0.0273"
  )),
  cutoffs = list(list(db = "eICU", values = c(10.03, 13.61, 15.00)))
)
km_sent <- .pub_figure_manuscript_sentence("Figure 3. KM curve", meta_find)
stopifnot(grepl("Kaplan", km_sent), grepl("死亡", km_sent), grepl("1\\.651", km_sent), grepl("0\\.024", km_sent))
rcs_sent <- .pub_figure_manuscript_sentence("Figure 2. RCS plot", meta_find)
stopifnot(grepl("10\\.03|切点|参考", rcs_sent), grepl("1\\.011", rcs_sent))

# 解析真实 Table 2（若本机有样本路径）
sample_t2 <- "/mnt/g/02block_result/18_SAE/prognosis_38902748/by_index/【success】BAR/Tables/Table 2-eICU. The Association Between BAR and SAE.xlsx"
if (file.exists(sample_t2)) {
  mat <- .pub_figure_read_xlsx_mat(sample_t2)
  parsed <- .pub_figure_parse_table2_mat(mat, db = "eICU")
  stopifnot(!is.null(parsed), grepl("Q4", parsed$high_label), nzchar(parsed$estimate))
}

readme <- paste(readLines(file.path(fd, "image_information", "README.md"), warn = FALSE), collapse = "\n")
stopifnot(grepl("图题", readme), grepl("RCS plot", readme))

# raster_ok=FALSE → md 注明缺失 png/tiff（spec §7）
md_fail <- tempfile("pub_fig_md_")
on.exit(unlink(md_fail), add = TRUE)
pub_figure_write_image_md(md_fail, "Figure 9. Test raster fail", meta = meta, raster_ok = FALSE)
md_fail_txt <- paste(readLines(md_fail, warn = FALSE), collapse = "\n")
stopifnot(grepl("缺失.*png.*tiff|栅格化失败", md_fail_txt), grepl("格式交付", md_fail_txt))
stopifnot(!grepl("## 标识", md_fail_txt), !grepl("## 技术", md_fail_txt))

# TIFF LZW：用 Python 读 compression
py <- file.path(root, "python", "pub_figure_rasterize.py")
stopifnot(file.exists(py))
tiff_path <- file.path(fd, "tiff", "Figure 1. Flowchart.tiff")
chk <- system(
  paste(
    "python3 -c",
    shQuote(sprintf(
      "from PIL import Image; im=Image.open(%s); print(im.info.get('compression'))",
      shQuote(tiff_path)
    ))
  ),
  intern = TRUE
)
stopifnot(any(grepl("tiff_lzw|lzw", chk, ignore.case = TRUE)))

unlink(fd, recursive = TRUE)
cat("test_pub_figure_export: OK\n")
