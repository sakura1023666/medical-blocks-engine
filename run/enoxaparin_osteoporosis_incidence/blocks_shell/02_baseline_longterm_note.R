###############################################################################
# 02_baseline_longterm_note.R — 课题壳说明（非独立 register_block）
#
# 文献 Table2：按长期≥30天分层的基线表。
# 引擎 baseline_binary 单次只支持一套 strata。
# 做法：主 pipeline 用 strata=Disease；长期表用同一 config 复制后改：
#   baseline_binary$strata <- "long_term_label"
#   project$analysis_group / reference_group 对应 LongTerm / Non_LongTerm
# 现成 config：
#   run/enoxaparin_osteoporosis_incidence/config_enoxaparin_op_longterm_table2.R
# 然后：
#   Rscript run/incidence/run_incidence_single.R \
#     --config run/enoxaparin_osteoporosis_incidence/config_enoxaparin_op_longterm_table2.R \
#     --to baseline_binary
# 对齐进主文 Table 2：
#   Rscript run/enoxaparin_osteoporosis_incidence/blocks_shell/03_liu_clinical_pub_align.R
###############################################################################

message(paste(
  "长期暴露 → 正文 Table 2：用 config_enoxaparin_op_longterm_table2.R 跑至 baseline_binary，",
  "再跑 03_liu_clinical_pub_align.R。详见 Decisiontree/decision_tree_enoxaparin_op_incidence.md"
))
