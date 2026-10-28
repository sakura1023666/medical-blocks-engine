# 课题薄封装。引擎在 Blocks/15_rcs/05block_rcs_cox_models_panel.R。
engine <- if (dir.exists("E:/01block/01Block-new-Final")) {
  "E:/01block/01Block-new-Final"
} else {
  "/mnt/e/01block/01Block-new-Final"
}
source(file.path(engine, "Blocks/15_rcs/05block_rcs_cox_models_panel.R"), local = FALSE)
