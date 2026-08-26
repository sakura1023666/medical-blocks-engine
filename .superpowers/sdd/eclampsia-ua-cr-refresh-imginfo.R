## 仅补写 image_information（与当前 pdf 对齐）
Sys.setenv(
  MEDICAL_BLOCKS_ROOT = "E:/01block/01Block-new-Final",
  MEDICAL_BLOCKS_SKIP_WIN_R = "1"
)
root <- Sys.getenv("MEDICAL_BLOCKS_ROOT")
study <- "G:/02block_result/27_eclampsia/small sample prediction_39780007"
source(file.path(root, "R/pub_figure_export.R"))
source(file.path(study, "config_ua_cr.R"))
figs <- file.path(study, "by_index/【success】UA_CR/Figures")
meta <- list(
  exposure = "UA_CR",
  outcome = "DN",
  databases = "nhanes",
  combined = FALSE,
  grouping = "quartile"
)
pub_figure_refresh_image_information(figs, meta = meta, config = config)
print(sort(list.files(file.path(figs, "image_information"), pattern = "\\.md$")))
