###############################################################################
#  color_palettes.R — Block 统一分类配色库
#
#  真源：下方 color_palettes。KM / boxplot / cutoff / 森林图等分类色
#  一律经 block_colors() / block_colors_from_config() 取色，禁止在各 block
#  再写死另一套 hex。
#
#  用法:
#    cols <- block_colors(8)                         # 八色 group1
#    cols <- block_colors(2, group = 2)               # 双色 group2（对比更强）
#    cols <- block_colors_from_config(cfg, n = 4)     # 尊重 config$plot
#    ggplot2::scale_fill_manual(values = cols)
#
#  config$plot 可选:
#    colors         — 显式色向量（优先）
#    palette_group  — 1 或 2（同 n 下选 group1/group2；缺省 1）
###############################################################################

if (!exists("%||%", mode = "function")) {
  `%||%` <- function(a, b) if (is.null(a)) b else a
}

color_palettes <- list(
  # --- 双色 (Two Colors) ---
  two_colors = list(
    group1 = c("#E7CACC", "#B6CAE7"),
    group2 = c("#CE4844", "#2A73BA")
  ),

  # --- 三色 (Three Colors) ---
  three_colors = list(
    group1 = c("#63C6A1", "#9E96DC", "#609FD8"),
    group2 = c("#62B7A0", "#EA9A99", "#8CC2E0")
  ),

  # --- 四色 (Four Colors) ---
  four_colors = list(
    group1 = c("#EEADAB", "#8DB18D", "#A5C7E0", "#E8E0AD")
  ),

  # --- 五色 (Five Colors) ---
  five_colors = list(
    group1 = c("#DADADA", "#3F83A4", "#6BAED3", "#EDC3A1", "#A53E34")
  ),

  # --- 六色 (Six Colors) ---
  six_colors = list(
    group1 = c("#009391", "#EFB47A", "#B3A9ED", "#C4E3F2", "#F1BFDA", "#DBDBDB"),
    group2 = c("#525252", "#F6847A", "#F8B583", "#4194C6", "#CA87A7", "#80A0CB")
  ),

  # --- 七色 (Seven Colors) ---
  seven_colors = list(
    group1 = c("#F6E7C6", "#CFDBCC", "#ACBFE0", "#D7B3D5", "#F4C6C7", "#7ABBCF", "#C3C4C9")
  ),

  # --- 八色 (Eight Colors) ---
  eight_colors = list(
    group1 = c("#C4C2C3", "#D18B96", "#7CD3A3", "#ADDBE1", "#FADBAD", "#616566", "#6A9DB9", "#F8C7C5"),
    group2 = c("#B0D5DB", "#ACC3E5", "#D7DAD8", "#C05F60", "#808080", "#ED708C", "#A1D3B8", "#E5C9B9")
  )
)

.block_palette_key_for_n <- function(n) {
  n <- as.integer(n)[1L]
  if (!is.finite(n) || n < 1L) {
    stop("block_colors: n 须为正整数。", call. = FALSE)
  }
  if (n <= 1L) return("two_colors")
  if (n >= 8L) return("eight_colors")
  c(
    "two_colors", "three_colors", "four_colors", "five_colors",
    "six_colors", "seven_colors", "eight_colors"
  )[[n - 1L]]
}

.block_palette_pick_group <- function(pal_list, group = 1L) {
  if (!is.list(pal_list) || !length(pal_list)) {
    stop("block_colors: 色板为空。", call. = FALSE)
  }
  g <- suppressWarnings(as.integer(group)[1L])
  if (!is.finite(g) || g < 1L) g <- 1L
  gname <- paste0("group", g)
  if (gname %in% names(pal_list)) return(unname(as.character(pal_list[[gname]])))
  # 无 group2 时回落到 group1 / 首个可用组
  if ("group1" %in% names(pal_list)) return(unname(as.character(pal_list$group1)))
  unname(as.character(pal_list[[1L]]))
}

#' 按分组数取统一配色（2–8 对应库内色板；n=1 取双色首色；n>8 循环/插值）
#'
#' @param n 需要的颜色个数
#' @param group 同 n 下的备选组（1=group1，2=group2；无该组则回落 group1）
#' @param recycle TRUE：n 超过色板长度时循环；FALSE：用 colorRampPalette 插值
#' @return 长度为 n 的 hex 字符向量
block_colors <- function(n, group = 1L, recycle = TRUE) {
  n <- as.integer(n)[1L]
  if (!is.finite(n) || n < 1L) {
    stop("block_colors: n 须为正整数。", call. = FALSE)
  }
  key <- .block_palette_key_for_n(min(n, 8L))
  cols <- .block_palette_pick_group(color_palettes[[key]], group = group)
  if (!length(cols)) {
    stop("block_colors: 色板 '", key, "' 无可用颜色。", call. = FALSE)
  }
  if (n == 1L) return(cols[[1L]])
  if (n <= length(cols)) return(cols[seq_len(n)])
  if (isTRUE(recycle)) return(rep(cols, length.out = n))
  grDevices::colorRampPalette(cols)(n)
}

#' 从 config$plot 取色（显式 colors > palette_group + block_colors）
block_colors_from_config <- function(cfg = NULL, n, group = NULL, recycle = TRUE) {
  n <- as.integer(n)[1L]
  plot_cfg <- list()
  if (is.list(cfg)) plot_cfg <- cfg$plot %||% list()
  explicit <- plot_cfg$colors %||% NULL
  if (!is.null(explicit)) {
    cols <- as.character(unlist(explicit, use.names = FALSE))
    cols <- cols[nzchar(cols)]
    if (length(cols)) {
      if (length(cols) >= n) return(cols[seq_len(n)])
      if (isTRUE(recycle)) return(rep(cols, length.out = n))
      return(grDevices::colorRampPalette(cols)(n))
    }
  }
  g <- group %||% plot_cfg$palette_group %||% 1L
  block_colors(n, group = g, recycle = recycle)
}

#' 块内默认色：有 block_colors 则用之，否则极简兜底（仅 source 顺序异常时）
block_default_palette <- function(n, cfg = NULL, group = NULL) {
  n <- as.integer(n)[1L]
  if (exists("block_colors_from_config", mode = "function")) {
    return(block_colors_from_config(cfg, n = n, group = group))
  }
  if (exists("block_colors", mode = "function")) {
    return(block_colors(n, group = group %||% 1L))
  }
  # 与 color_palettes$eight_colors$group1 对齐的硬兜底
  fb <- c(
    "#C4C2C3", "#D18B96", "#7CD3A3", "#ADDBE1",
    "#FADBAD", "#616566", "#6A9DB9", "#F8C7C5"
  )
  rep(fb, length.out = max(1L, n))
}
