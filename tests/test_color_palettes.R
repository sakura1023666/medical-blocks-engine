###############################################################################
#  test_color_palettes.R — 统一分类配色库冒烟
###############################################################################

args <- commandArgs(trailingOnly = FALSE)
file_hits <- grep("^--file=", args, value = TRUE)
file_arg <- if (length(file_hits)) sub("^--file=", "", file_hits[[1L]]) else ""
test_dir <- if (nzchar(file_arg)) {
  dirname(normalizePath(file_arg, winslash = "/"))
} else {
  normalizePath(getwd(), winslash = "/")
}
root <- normalizePath(file.path(test_dir, ".."), winslash = "/", mustWork = TRUE)

src <- file.path(root, "R", "color_palettes.R")
stopifnot(file.exists(src))
source(src, local = FALSE)

stopifnot(identical(block_colors(2), color_palettes$two_colors$group1))
stopifnot(identical(block_colors(2, group = 2), color_palettes$two_colors$group2))
stopifnot(identical(block_colors(8), color_palettes$eight_colors$group1))
stopifnot(length(block_colors(1)) == 1L)
stopifnot(length(block_colors(10)) == 10L)
# 无 group2 的四色回落 group1
stopifnot(identical(block_colors(4, group = 2), color_palettes$four_colors$group1))

cfg <- list(plot = list(palette_group = 2L))
stopifnot(identical(block_colors_from_config(cfg, 2L), color_palettes$two_colors$group2))
cfg2 <- list(plot = list(colors = c("#111111", "#222222", "#333333")))
stopifnot(identical(block_colors_from_config(cfg2, 2L), c("#111111", "#222222")))

# utils 尾部应能挂载本文件
utils_path <- file.path(root, "R", "utils.R")
stopifnot(file.exists(utils_path))
# 仅检查 source 片段可解析：不整文件 source（副作用大）
txt <- paste(readLines(utils_path, warn = FALSE), collapse = "\n")
stopifnot(grepl("color_palettes\\.R", txt, perl = TRUE))

message("OK: test_color_palettes")
