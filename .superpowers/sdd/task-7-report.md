# Task 7 Report: Config + 决策树 + Template（SLE→AKI 两阶段）

**Status**: DONE  
**Date**: 2026-08-26  
**Commits**: none（禁止 commit）

**Deliverables**: `configs/templates/config_sle_aki_inc_prog_batch.template.R`；研究 config `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R`；`Decisiontree/decision_tree_sle_aki_inc_prog.md`（15 步、DAG、规则 C、28d、院内截尾/无 aki_time 脚注、飞书 **Bxx**）。

**Config**: `output_dir`=结果根；`dual_db$enable=FALSE`；`pub_figure$profile=mimic_inc_prog_sle_aki`；`mirror_pub_outputs_to_root=TRUE`；`ip_two_stage` 指向 `data/mimic/`；`disease_vars`=Task1 15 项；`age_cutoff=65` 且 Age_Group 两级；Stage0/1/2 按 spec §6（含三胶水块）。Figure 1 用 `attrition$steps`（rdata/id_file/current）对齐 `ip_attrition_steps`（flowchart 不读该对象）。

**Parse**: Windows Rscript source 研究 config + 引擎 template 均 `PARSE_OK`（full=44 blocks）。未改旧课题 config。
