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
