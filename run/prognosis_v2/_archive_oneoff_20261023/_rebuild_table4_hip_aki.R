#!/usr/bin/env Rscript
# 已退役：用户不要主文 Table 4。
# 排除 28 天内死亡的敏感性只保留在 Table S5（见 remirror_hip_aki_pub.R）。
# 误跑本脚本时：归档任何 Table 4 xlsx，不写出新主文表。
.out <- "G:/02block_result/52_Hip_arthroplasty_aki/prognosis_v2_41904528/summary_results"
.tab <- file.path(.out, "Tables")
.arch <- file.path(dirname(.out), "summary_results_delivery_workspace", "_archive_table4_retired")
dir.create(.arch, recursive = TRUE, showWarnings = FALSE)
olds <- list.files(.tab, pattern = "^Table 4\\.", full.names = TRUE)
for (f in olds) {
  file.rename(f, file.path(.arch, basename(f)))
  message("archived ", basename(f))
}
message("Table 4 skipped (user retired). Use Table S5 for early-death exclusion sensitivity.")
