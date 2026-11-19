#!/usr/bin/env Rscript
# 防再发：cairo 选字不得嵌入 Noto/CJK；QC deny 须命中 CJK token
args <- commandArgs(trailingOnly = FALSE)
file_arg <- grep("^--file=", args, value = TRUE)
this_file <- if (length(file_arg)) sub("^--file=", "", file_arg[[1]]) else NA_character_
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) {
  root <- if (nzchar(this_file)) {
    normalizePath(file.path(dirname(this_file), ".."), mustWork = FALSE)
  } else {
    getwd()
  }
}
source(file.path(root, "R/utils.R"), local = FALSE)
source(file.path(root, "R/pub_qc_fonts.R"), local = FALSE)

fail <- function(msg) {
  message("FAIL: ", msg)
  quit(status = 1L)
}
ok <- function(msg) message("OK: ", msg)

ff <- resolve_plot_font_family("Times New Roman")
ok(paste0("resolve_plot_font_family -> ", ff))
if (grepl("(?i)noto|cjk|source.?han", ff)) {
  fail(paste0("resolved family looks CJK: ", ff))
}

tmp <- tempfile(fileext = ".pdf")
on.exit(unlink(tmp), add = TRUE)
grDevices::cairo_pdf(tmp, width = 3, height = 2, family = ff)
grid::grid.text("Mg ALBI Age < 18", gp = grid::gpar(fontfamily = ff, fontsize = 12))
grDevices::dev.off()
if (!file.exists(tmp) || isTRUE(file.info(tmp)$size < 1000)) fail("probe PDF too small")

if (isTRUE(pub_pdf_has_unsafe_cjk_font(tmp))) {
  fail(paste0(
    "probe PDF embeds unsafe CJK fonts: ",
    paste(pub_pdf_font_names(tmp), collapse = ", ")
  ))
}
ok(paste0("probe PDF fonts: ", paste(pub_pdf_font_names(tmp), collapse = ", ")))

deny <- .pub_qc_font_deny_re()
for (bad in c("ABC+NotoSerifCJK-Regular", "NotoSansCJK", "SourceHanSerif")) {
  if (!grepl(deny, bad, perl = TRUE)) fail(paste0("deny_re missed: ", bad))
}
ok("deny_re catches Noto/SourceHan")

message("ALL PASS")
quit(status = 0L)
