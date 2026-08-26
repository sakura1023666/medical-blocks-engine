## LASSO 上下拼 → Figure S1
Sys.setenv(MEDICAL_BLOCKS_SKIP_WIN_R = "1")
out_dir <- "E:/01block/01Block-new-Final/.superpowers/sdd/eclampsia_lasso_combine"
a_pdf <- file.path(out_dir, "lassoA.pdf")
b_pdf <- file.path(out_dir, "lassoB.pdf")
out_pdf <- file.path(out_dir, "Figure S1. LASSO feature selection.pdf")

stopifnot(file.exists(a_pdf), file.exists(b_pdf))
need <- c("magick", "cowplot", "ggplot2")
for (p in need) if (!requireNamespace(p, quietly = TRUE)) stop("need ", p)

img_a <- magick::image_read_pdf(a_pdf, density = 200)
img_b <- magick::image_read_pdf(b_pdf, density = 200)
png_a <- file.path(out_dir, "_tmp_a.png")
png_b <- file.path(out_dir, "_tmp_b.png")
magick::image_write(img_a[1], png_a, format = "png")
magick::image_write(img_b[1], png_b, format = "png")

pA <- cowplot::ggdraw() + cowplot::draw_image(png_a)
pB <- cowplot::ggdraw() + cowplot::draw_image(png_b)
pA <- cowplot::ggdraw(pA) +
  cowplot::draw_label("A", x = 0.02, y = 0.98, hjust = 0, vjust = 1,
                      size = 14, fontface = "bold")
pB <- cowplot::ggdraw(pB) +
  cowplot::draw_label("B", x = 0.02, y = 0.98, hjust = 0, vjust = 1,
                      size = 14, fontface = "bold")

## 上下拼：A 上 B 下；B 略高一点（模式热图更宽信息）
comb <- cowplot::plot_grid(pA, pB, ncol = 1L, rel_heights = c(1, 1.15), align = "v")

grDevices::pdf(out_pdf, width = 8.5, height = 10, useDingbats = FALSE)
print(comb)
grDevices::dev.off()

prev <- file.path(out_dir, "FigureS1_LASSO_preview.png")
ggplot2::ggsave(prev, comb, width = 8.5, height = 10, dpi = 140, bg = "white")
unlink(c(png_a, png_b))
cat("OK ->", out_pdf, "\n")
