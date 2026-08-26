# Task 6 Review Package
# Task 6 Report: pub_figure profile gating

**Status**: DONE · **Commits**: none

`R/pub_figure_profile.R`：`pub_figure_profile()` 缺省/空白→NULL；`is_pub_profile()` 仅 `identical(..., "mimic_inc_prog_sle_aki")` 为 TRUE。`pub_figure_profile_apply_ggplot()` 在 NULL profile 时返回同一对象。`utils.R` 尾部 source 挂载。

门控（仅 if 分支改 theme/标注；else 原路径）：attrition 浅蓝框、simple_ROC Youden 点+方形画布、ROC/RCS/KM/plot_cutoff ggplot classic overlay、RCS 结点 rug、森林图显著交互 P 高亮。`threshold_logistic` 已走公共 getter。

TDD：RED `file.exists(src) is not TRUE` → GREEN `OK profile gate`；`test_attrition_log` / `test_threshold_logistic` / parse 均 OK。未 git commit。

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

#!/usr/bin/env Rscript
# TDD: pub_figure$profile 门控 — 缺省 NULL；匹配才 TRUE；NULL 时绑图 helper 不改对象
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = "")
if (!nzchar(root)) root <- normalizePath(".", winslash = "/")
if (!file.exists(file.path(root, "R/utils.R"))) {
  cand <- normalizePath(file.path(".."), winslash = "/")
  if (file.exists(file.path(cand, "R/utils.R"))) root <- cand
}

src <- file.path(root, "R/pub_figure_profile.R")
stopifnot(file.exists(src))
source(src, local = FALSE)

stopifnot(is.null(pub_figure_profile(list())))
stopifnot(is.null(pub_figure_profile(list(pub_figure = list()))))
stopifnot(is.null(pub_figure_profile(list(pub_figure = list(profile = "")))))
stopifnot(is.null(pub_figure_profile(list(pub_figure = list(profile = NA_character_)))))
stopifnot(is_pub_profile(list(pub_figure = list(profile = "mimic_inc_prog_sle_aki")),
                         "mimic_inc_prog_sle_aki"))
stopifnot(!is_pub_profile(list(pub_figure = list(profile = "other")),
                          "mimic_inc_prog_sle_aki"))
stopifnot(!is_pub_profile(list(), "mimic_inc_prog_sle_aki"))

# NULL/缺省 profile：绑图 helper 必须返回同一对象（默认图路径不变）
stopifnot(exists("pub_figure_profile_apply_ggplot", mode = "function"))
sentinel <- structure(list(tag = "unchanged"), class = "dummy_plot")
stopifnot(identical(pub_figure_profile_apply_ggplot(sentinel, list()), sentinel))
stopifnot(identical(
  pub_figure_profile_apply_ggplot(sentinel, list(pub_figure = list(profile = ""))),
  sentinel
))
if (requireNamespace("ggplot2", quietly = TRUE)) {
  p0 <- ggplot2::ggplot()
  stopifnot(identical(pub_figure_profile_apply_ggplot(p0, list()), p0))
}

# utils 尾部应挂载本文件
utils_path <- file.path(root, "R/utils.R")
stopifnot(file.exists(utils_path))
utils_txt <- paste(readLines(utils_path, warn = FALSE), collapse = "\n")
stopifnot(grepl("pub_figure_profile\\.R", utils_txt, perl = TRUE))

# 目标 Block 含 profile 门控（缺省分支不得改美学）
gate_files <- c(
  "Blocks/00_attrition/01block_attrition_flowchart.R",
  "Blocks/13_roc/02block_simple_ROC.R",
  "Blocks/13_roc/01block_ROC.R",
  "Blocks/15_rcs/02block_rcs_incidence.R",
  "Blocks/15_rcs/01block_rcs_prognosis.R",
  "Blocks/18_subgroup/01block_subgroup_prognosis.R",
  "Blocks/18_subgroup/02block_subgroup_incidence.R",
  "Blocks/18_subgroup/04block_subgroup_prognosis_continuous.R",
  "Blocks/18_subgroup/05block_subgroup_incidence_continuous.R",
  "Blocks/27_KM/01block_km_binary.R",
  "Blocks/27_KM/02block_km_strata.R",
  "Blocks/28_plot/01block_plot_cutoff.R"
)
for (rel in gate_files) {
  fp <- file.path(root, rel)
  stopifnot(file.exists(fp))
  txt <- paste(readLines(fp, warn = FALSE), collapse = "\n")
  stopifnot(grepl("is_pub_profile", txt, fixed = TRUE))
  stopifnot(grepl("mimic_inc_prog_sle_aki", txt, fixed = TRUE))
}

cat("OK profile gate\n")

## gated call sites
/mnt/e/01block/01Block-new-Final/Blocks/28_plot/01block_plot_cutoff.R:268:        if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/28_plot/01block_plot_cutoff.R:269:            is_pub_profile(cfg, "mimic_inc_prog_sle_aki") &&
/mnt/e/01block/01Block-new-Final/Blocks/28_plot/01block_plot_cutoff.R:270:            exists("pub_figure_profile_apply_ggplot", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/28_plot/01block_plot_cutoff.R:271:          pin <- pub_figure_profile_apply_ggplot(pin, cfg)
/mnt/e/01block/01Block-new-Final/Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R:9:#  pub_figure$profile == "mimic_inc_prog_sle_aki" 时走文献版主题（Task 6 可再加深）。
/mnt/e/01block/01Block-new-Final/Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R:59:  if (exists("is_pub_profile", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R:60:    return(isTRUE(is_pub_profile(config, "mimic_inc_prog_sle_aki")))
/mnt/e/01block/01Block-new-Final/Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R:63:  identical(as.character(p %||% "")[1L], "mimic_inc_prog_sle_aki")
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/02block_km_strata.R:614:    if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/02block_km_strata.R:615:        is_pub_profile(config, "mimic_inc_prog_sle_aki") &&
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/02block_km_strata.R:616:        exists("pub_figure_profile_apply_ggplot", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/02block_km_strata.R:618:        p$plot <- pub_figure_profile_apply_ggplot(p$plot, config)
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/02block_km_strata.R:621:        p$table <- pub_figure_profile_apply_ggplot(p$table, config)
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/01block_km_binary.R:253:        exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/01block_km_binary.R:254:        is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki") &&
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/01block_km_binary.R:255:        exists("pub_figure_profile_apply_ggplot", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/01block_km_binary.R:257:        p$plot <- pub_figure_profile_apply_ggplot(p$plot, ctx$config)
/mnt/e/01block/01Block-new-Final/Blocks/27_KM/01block_km_binary.R:260:        p$table <- pub_figure_profile_apply_ggplot(p$table, ctx$config)
/mnt/e/01block/01Block-new-Final/Blocks/15_rcs/02block_rcs_incidence.R:528:  if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/15_rcs/02block_rcs_incidence.R:529:      is_pub_profile(config, "mimic_inc_prog_sle_aki")) {
/mnt/e/01block/01Block-new-Final/Blocks/15_rcs/02block_rcs_incidence.R:539:    if (exists("pub_figure_profile_apply_ggplot", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/15_rcs/02block_rcs_incidence.R:540:      plot_obj <- pub_figure_profile_apply_ggplot(plot_obj, config)
/mnt/e/01block/01Block-new-Final/Blocks/15_rcs/01block_rcs_prognosis.R:458:  if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/15_rcs/01block_rcs_prognosis.R:459:      is_pub_profile(cfg, "mimic_inc_prog_sle_aki")) {
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/02block_simple_ROC.R:431:  if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/02block_simple_ROC.R:432:      is_pub_profile(cfg, "mimic_inc_prog_sle_aki")) {
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/02block_simple_ROC.R:445:    if (exists("pub_figure_profile_apply_ggplot", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/02block_simple_ROC.R:446:      g <- pub_figure_profile_apply_ggplot(g, cfg)
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/02block_simple_ROC.R:453:  if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/02block_simple_ROC.R:454:      is_pub_profile(cfg, "mimic_inc_prog_sle_aki")) {
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/01block_ROC.R:247:  if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/01block_ROC.R:248:      is_pub_profile(config, "mimic_inc_prog_sle_aki") &&
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/01block_ROC.R:249:      exists("pub_figure_profile_apply_ggplot", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/13_roc/01block_ROC.R:250:    g <- pub_figure_profile_apply_ggplot(g, config)
/mnt/e/01block/01Block-new-Final/Blocks/18_subgroup/05block_subgroup_incidence_continuous.R:460:  if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/18_subgroup/05block_subgroup_incidence_continuous.R:461:      is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki")) {
/mnt/e/01block/01Block-new-Final/Blocks/18_subgroup/05block_subgroup_incidence_continuous.R:462:    ov <- if (exists("pub_figure_profile_forest_overrides", mode = "function")) {
/mnt/e/01block/01Block-new-Final/Blocks/18_subgroup/05block_subgroup_incidence_continuous.R:463:      pub_figure_profile_forest_overrides(ctx$config)
/mnt/e/01block/01Block-new-Final/Blocks/18_subgroup/04block_subgroup_prognosis_continuous.R:454:  if (exists("is_pub_profile", mode = "function") &&
/mnt/e/01block/01Block-new-Final/Blocks/18_subgroup/04block_subgroup_prognosis_continuous.R:455:      is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki")) {

7035:    if (!is.null(rdir)) file.path(rdir, "pub_figure_profile.R"),
7036:    file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT", unset = ""), "R", "pub_figure_profile.R"),
7037:    file.path("R", "pub_figure_profile.R")
