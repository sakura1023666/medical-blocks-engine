###############################################################################
#  config_easymr_twosample.template.R
#  下载完暴露 GWAS 和 FinnGen 结局后，填 exposures / outcome_raw / N，再跑
#  block easymr_twosample。必须用本机 R 4.2.2，由 block 自己调用 Rscript.exe。
#
#  full_mr 默认 TRUE：跑 easyMR 删点节点（MR-PRESSO，必要时 RadialMR）。
#  设为 FALSE 则只做 IVW + cML/dIVW/RAPS/robust。
#  SNP 等列名不写死。block 会读暴露文件表头，并用前几十行判断哪一列是 rs 号。
###############################################################################

config <- list(
  project = list(
    name = "easyMR",
    root = "E:/01block/01Block-new-Final",
    output_dir = "E:/孟德尔/MR/_easymr_block"
  ),
  easymr = list(
    rscript = "C:/Program Files/R/R-4.2.2/bin/Rscript.exe",
    mr_database = "D:/easyMR/MRmyy_refer_file",
    exposure_dir = "E:/孟德尔/1暴露数据",
    exposure_out_dir = "E:/孟德尔/复合指标",
    outcome_raw = "E:/孟德尔/1结局数据/finngen_R12_NAFLD.gz",
    outcome_dir = "E:/孟德尔/结局",
    outcome_rds = "E:/孟德尔/结局/Nonalcoholic_fatty_liver_disease_R12_full_outcome.rds",
    outcome_kind = "finn",
    outcome_label = "NAFLD",
    save_root = "E:/孟德尔/MR/新课题",
    full_mr = TRUE,
    force_reformat = FALSE,
    dry_run = FALSE,
    clump_kb = 10000,
    clump_r2 = 0.001,
    pval_threshold = 5e-8,
    proxies = TRUE,
    pop = "EUR",
    action = 2L,
    run_steiger = TRUE,
    exposures = list(
      list(
        file = "GCST90309892.h.tsv.gz",
        id = "AST_GCST90309892",
        label = "AST",
        N = 174488
      )
    )
  )
)
