### Task 7: Config + 决策树 + Template

**Files:**
- Create: `configs/templates/config_sle_aki_inc_prog_batch.template.R`
- Create: `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/config_sle_aki_inc_prog_batch.R`（研究 config，可从 template 复制）
- Create: `Decisiontree/decision_tree_sle_aki_inc_prog.md`

**Interfaces:**
- `project$output_dir` → 结果根  
- `project$study_type` Stage1 为 `incidence`；Stage2 块前由胶水切换 survival 字段  
- `pub_figure$profile = "mimic_inc_prog_sle_aki"`  
- `mirror_pub_outputs_to_root = TRUE`（相对于 **output_dir**）  
- `analysis_exclusion$disease_vars` ← Task 1  
- `subgroup$age_cutoff`：SLE 常用 65（注释写依据；二分类 `Age_Group`）  
- `ip_two_stage` 路径全部指向 `G:/02block_result/.../data/mimic/`

Pipeline 列表按 spec §6 完整写入 `pipeline$blocks` / `pipeline_regular_batch`。

决策树必须含：15 步对照表、DAG 文字版、时间零点规则 C、28 天定义、飞书编号占位。

- [ ] **Step 1: 从 `config_incidence_dual_batch.template.R` + survival 模板拼单库两阶段 template**（`dual_db$enable=FALSE`）
- [ ] **Step 2: 写决策树 md（结构对齐 `decision_tree_incidence_single.md`）**
- [ ] **Step 3: 结果根落研究 config**

---
