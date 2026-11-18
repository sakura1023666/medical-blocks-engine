###############################################################################
#  config_easymr_gwas_search.template.R
#  下载 GWAS 之前先查目录。block：easymr_gwas_search
#  只保留发现样本为欧洲人、并且 GWAS Catalog 提供全基因组汇总统计 FTP 的研究。
#  结果按发表日期从新到旧写 csv 和 md。md 里有 Catalog 页、PubMed 和 FTP。
###############################################################################

config <- list(
  project = list(
    name = "gwas_search",
    root = "E:/01block/01Block-new-Final",
    output_dir = "E:/孟德尔/MR/_gwas_search"
  ),
  easymr_gwas_search = list(
    query = "albumin",
    efo_id = NULL,
    ancestry = "European",
    ancestry_mode = "european_only",
    require_summary_stats = TRUE,
    drop_cnv = TRUE,
    save_dir = "E:/孟德尔/MR/_gwas_search",
    page_size = 100L,
    max_studies_per_trait = 300L
  )
)
