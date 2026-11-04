# tests/test_pub_figure_vector_pdf_gate.R — 交付 PDF 禁止整页栅格
root <- normalizePath(getwd())
if (!file.exists(file.path(root, "R/pub_figure_export.R"))) {
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/pub_figure_export.R"))) root <- cand
}
source(file.path(root, "R/pub_figure_export.R"), local = FALSE)

stopifnot(isTRUE(.pub_figure_cfg(list())$require_vector_pdf))
stopifnot(.pub_figure_stem_allows_raster_pdf(
  "Figure S2-EMs Single. Shiny web calculator (RSF)",
  .pub_figure_cfg(list())$allow_raster_pdf_patterns
))
stopifnot(!.pub_figure_stem_allows_raster_pdf(
  "Figure 3. Combined KM Plots",
  .pub_figure_cfg(list())$allow_raster_pdf_patterns
))

fd <- tempfile("pub_vec_gate_")
dir.create(file.path(fd, "pdf"), recursive = TRUE)
# vector-ish pdf
vec_p <- file.path(fd, "pdf", "Figure 1. Vector.pdf")
grDevices::pdf(vec_p, width = 4, height = 3)
plot(1:10, 1:10, type = "l", main = "vector line")
grDevices::dev.off()

# image-only pdf via pub_figure_rasterize_pdf_page
ras_p <- file.path(fd, "pdf", "Figure 2. Rasterized.pdf")
pub_figure_rasterize_pdf_page(vec_p, ras_p, dpi = 72L)
stopifnot(file.exists(ras_p))

vp_v <- .pub_figure_pdf_vector_probe(vec_p)
vp_r <- .pub_figure_pdf_vector_probe(ras_p)
stopifnot(!isTRUE(vp_v$image_only))
stopifnot(isTRUE(vp_r$image_only))

st <- pub_figure_formats_status(fd, config = list())
stopifnot("Figure 2. Rasterized" %in% (st$bad_pdf_raster %||% character(0)))
stopifnot(isFALSE(st$ok))

# Shiny stem allowlist
file.rename(ras_p, file.path(fd, "pdf", "Figure S2. Shiny web calculator.pdf"))
st2 <- pub_figure_formats_status(fd, config = list())
stopifnot(!length(st2$bad_pdf_raster %||% character(0)))
stopifnot(isTRUE(st2$ok) || length(st2$flat_leftovers %||% character(0)) == 0L)

message("OK test_pub_figure_vector_pdf_gate")
