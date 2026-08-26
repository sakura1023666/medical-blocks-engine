# Task 7 Review — Config + 决策树 + Template

**Reviewer**: subagent (read-only)  
**Date**: 2026-08-26  
**Scope**: brief `task-7-brief.md` + constraints `sle-aki-global-constraints.md` + package `task-7-review-pkg.md`

## Verdict

| Gate | Result |
|------|--------|
| **Spec** | ✅ |
| **Quality** | **Approved** |

## Verification

| Check | Result | Evidence |
|-------|--------|----------|
| Template 存在 | ✅ | `configs/templates/config_sle_aki_inc_prog_batch.template.R`（754 行） |
| 研究 config 落结果根 | ✅ | `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R`（760 行；与 template 仅头部注释差） |
| 决策树 md | ✅ | `Decisiontree/decision_tree_sle_aki_inc_prog.md`（252 行） |
| Config parse | ✅ | Windows Rscript `source`：template + 研究 config 均 `PARSE_OK`，`length(pipeline$blocks)=44` |
| `output_dir` = 结果根 | ✅ | `config$project$output_dir = .batch_project_root`（G:/…42304330） |
| `dual_db$enable = FALSE` | ✅ | `config$dual_db$enable` 与三份 pipeline 均为 FALSE |
| `pub_figure$profile` | ✅ | `"mimic_inc_prog_sle_aki"`；`configs/` 旧课题无此 profile |
| `mirror_pub_outputs_to_root` | ✅ | `TRUE`（相对 `output_dir`） |
| `ip_two_stage` 路径 | ✅ | baseline / SLE / ARF / prognosis / dabiao 均 `…/data/mimic/` |
| `disease_vars` ← Task 1 | ✅ | 15 项与 `data/_column_review.md` 候选名单逐字一致 |
| `age_cutoff` 二分类 | ✅ | `subgroup$age_cutoff=65L`；`level_order$Age_Group = c("< 65", "≥ 65")`；注释含 ACR/EULAR 依据；`sensitivity_suite` / `subgroup_fallback` 同为 65 |
| Pipeline §6 Stage0 | ✅ | `identical(.blocks_stage0, spec_s0)` |
| Pipeline §6 Stage1 | ✅ | 含 Q/T/B `logistic_*_glm_rcs` + `threshold_logistic`；`identical(.blocks_stage1, spec_s1)` |
| Pipeline §6 Bridge | ✅ | `ip_stage2_cohort_28d` |
| Pipeline §6 Stage2 | ✅ | 含 `plot_cutoff` / KM / 三路 `segmented_cox_*`；`identical(.blocks_stage2, spec_s2)` |
| 三胶水块 | ✅ | `ip_cohort_sle_aki`、`ip_stage2_cohort_28d`、`threshold_logistic` 均在 block 序 |
| 28d / `aki_time` 脚注 | ✅ | `ip_two_stage$footnotes`（3 条）+ `aki_window_note`；决策树「脚注清单」5 条（无 aki_time 回退、院内截尾、AKI 窗、 dabiao、28d 非长期随访） |
| 决策树必含项 | ✅ | 15 步对照表、DAG 文字版、规则 C、28 天定义、飞书 **Bxx** 占位 |
| 结构对齐单库发病树 | ✅ | 研究设定 / 总览 mermaid / 分阶段表 / block 序 / CLI；两阶段 + bridge 扩展合理 |
| 未改旧课题 | ✅ | 仅新增 template + 决策树；旧 config 无 `mimic_inc_prog_sle_aki` |
| 无 git commit | ✅ | 符合 global constraints |

## Critical

无。

## Important

1. **敏感性未挂 pipeline block** — `incidence_batch$sensitivity_suite$enable=TRUE`，但 `pipeline$blocks` 末段无 `sensitivity_*` block（spec §6 标注「可选 sensitivity」、流程图 ⑮）。决策树已指向 suite；**Task 8 worker** 须确认 success 后自动补跑或显式挂块，否则 15 步「全绿」仅文档层。
2. **Figure 1 `attrition$steps` 仅 3 步** — spec §4.1 另含 CKD/`disease_vars` 排除与「关键窗可计算」；当前靠 `ip_cohort` 内逻辑 + `analysis_exclusion`，Figure 1 可能不显式逐步 n。Task 8 试跑后核对 `Flowchart_attrition.csv` / image_information 是否需 `auto_append` 或补 step。
3. **Spec §10 表内 config 路径与实现不一致** — 表写 `configs/config_sle_aki_inc_prog_batch.R`，brief/实现为结果根实例 + 引擎 template；功能正确，文档表可 Task 9 同步。
