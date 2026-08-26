###############################################################################
#  pub_figure_profile — 发表图 profile 门控
#
#  config$pub_figure$profile 缺省 / 空白 → NULL（所有绑图保持历史默认）。
#  仅 identical(profile, "mimic_inc_prog_sle_aki") 时走文献版 theme/标注。
###############################################################################

pub_figure_profile <- function(config) {
  p <- tryCatch(config$pub_figure$profile, error = function(e) NULL)
  if (is.null(p) || length(p) < 1L) return(NULL)
  p1 <- as.character(p)[1L]
  if (!nzchar(p1) || is.na(p1)) return(NULL)
  p1
}

is_pub_profile <- function(config, name) {
  identical(pub_figure_profile(config), name)
}

# 文献版 ggplot 叠加。profile 缺省时原样返回同一对象（默认图路径不变）。
pub_figure_profile_apply_ggplot <- function(plot, config) {
  if (is.null(plot)) return(plot)
  if (!is_pub_profile(config, "mimic_inc_prog_sle_aki")) return(plot)
  if (!requireNamespace("ggplot2", quietly = TRUE)) return(plot)
  if (!inherits(plot, c("ggplot", "gg", "patchwork"))) return(plot)
  plot +
    ggplot2::theme_classic(base_family = "Times New Roman") +
    ggplot2::theme(
      text = ggplot2::element_text(family = "Times New Roman"),
      plot.title = ggplot2::element_text(
        hjust = 0.5, face = "bold", family = "Times New Roman"
      ),
      axis.title = ggplot2::element_text(family = "Times New Roman"),
      axis.text = ggplot2::element_text(family = "Times New Roman"),
      legend.text = ggplot2::element_text(family = "Times New Roman"),
      legend.title = ggplot2::element_text(family = "Times New Roman"),
      panel.grid.major = ggplot2::element_blank(),
      panel.grid.minor = ggplot2::element_blank(),
      legend.background = ggplot2::element_blank()
    )
}

# 森林图文献版覆盖项；缺省返回 NULL，调用方不得改默认 ci_col / P 高亮。
pub_figure_profile_forest_overrides <- function(config) {
  if (!is_pub_profile(config, "mimic_inc_prog_sle_aki")) return(NULL)
  list(
    ci_col = "#1B4F72",
    highlight_interaction_sig = TRUE
  )
}
