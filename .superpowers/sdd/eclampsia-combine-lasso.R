## 将 LASSO 两图拼成 A|B 一张
Sys.setenv(MEDICAL_BLOCKS_SKIP_WIN_R = "1")
out_dir <- "E:/01block/01Block-new-Final/.superpowers/sdd/eclampsia_lasso_combine"
a_pdf <- file.path(out_dir, "lassoA.pdf")
b_pdf <- file.path(out_dir, "lassoB.pdf")
out_pdf <- file.path(out_dir, "Figure 4. LASSO feature selection.pdf")

if (!requireNamespace("magick", quietly = TRUE)) {
  stop("need magick")
}
if (!requireNamespace("cowplot", quietly = TRUE)) {
  stop("need cowplot")
}
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  stop("need ggplot2")
}

## PDF -> 高分辨率图
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
                      size = 14, fontface = "bold", fontfamily = "sans")
pB <- cowplot::ggdraw(pB) +
  cowplot::draw_label("B", x = 0.02, y = 0.98, hjust = 0, vjust = 1,
                      size = 14, fontface = "bold", fontfamily = "sans")

comb <- cowplot::plot_grid(pA, pB, ncol = 2L, rel_widths = c(1, 1.15), align = "h")

grDevices::pdf(out_pdf, width = 12, height = 5.2, useDingbats = FALSE)
print(comb)
grDevices::dev.off()

## 也写一份 PNG 预览
prev <- file.path(out_dir, "Figure4_LASSO_preview.png")
ggplot2::ggsave(prev, comb, width = 12, height = 5.2, dpi = 150, bg = "white")

unlink(c(png_a, png_b))
cat("OK ->", out_pdf, "\n")
cat("preview ->", prev, "\n")
