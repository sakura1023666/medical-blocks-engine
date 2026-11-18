###############################################################################
#  config_easymr_ieu.template.R
#  block：easymr_ieu
#  query 只查本机 easyMR 的欧洲人目录，不使用 key。
#  extract_ids 填了编号才会用 jwt_file 在线提取工具变量。
#  key 放在 jwt_file 指向的文本里，一行，不要写进本文件。
###############################################################################

config <- list(
  project = list(
    name = "easymr_ieu",
    root = "E:/01block/01Block-new-Final",
    output_dir = "E:/孟德尔/MR/_ieu_search"
  ),
  easymr_ieu = list(
    query = "albumin",
    population = "European",
    drop_eqtl = TRUE,
    jwt_file = "E:/孟德尔/0代码/opengwas_jwt.txt",
    extract_ids = NULL,
    rscript = "C:/Program Files/R/R-4.2.2/bin/Rscript.exe",
    save_dir = "E:/孟德尔/MR/_ieu_search",
    p1 = 5e-8,
    clump = TRUE,
    r2 = 0.001,
    kb = 10000,
    dry_run = FALSE
  )
)
