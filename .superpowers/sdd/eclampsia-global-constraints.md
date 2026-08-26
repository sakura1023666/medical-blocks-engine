## Global Constraints

- 课题根：`/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/`
- 主仓：`/mnt/e/01block/01Block-new-Final`（`MEDICAL_BLOCKS_ROOT`）
- 仅六模型：`adaboost`, `tabpfnv2`, `catboost`, `xgboost`, `lightgbm`, `rf`
- `index_group=all`，`index_vars=NULL`，10 workers，`fail_policy=continue`
- 发病 logistic（禁止 `assoc_model="cox"`）
- `age_cutoff=35`；`Age_Group` 仅 `"< 35"` / `"≥ 35"`；禁止多档 `age_group_cutoffs`
- 全女性：`Gender` 进 drop/exclude
- 无 git：跳过所有 commit 步骤
- Spec：`docs/superpowers/specs/2026-08-21-eclampsia-mimic-ml-incidence-by-index-design.md`

---

