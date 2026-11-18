# 复用地图 — 联合轨迹发病套路进引擎（2026-11-18）

沉淀自 ELSA×CVD 文献复现（`56_CVD/incidence_trajectory_13393250`，
Liu et al. Cardiovasc Diabetol 2026）。**下一「双指标联合轨迹 → 新发结局」课题直接走引擎**，
禁止再在课题目录堆 bespoke phase 脚本。

## 引擎入口

| 能力 | 入口 |
|---|---|
| 六块流水线 | `Blocks/82_trajectory_incidence_joint/01–06block_tj_*.R` |
| register_block 名 | `tj_data_ingest` → `tj_gbmtm_fit` → `imputation` → `tj_cox_rubin` → `tj_subgroup` → `tj_sensitivity` → `tj_pub_export` |
| GBMTM 内核 | `R/gbmtm_core.R`（`gbmtm_to_long/select/label`；AIC/BIC + AvePP/最小类软门控） |
| 公共 helper | `R/literature_trajectory_joint.R`（波次指标重算 / Rubin 向量 / KM / 森林 / 轨迹面板 / Table1 按类） |
| config 模板 | `configs/templates/config_trajectory_incidence_joint.template.R` |
| 单跑 | `run/trajectory_incidence/run_trajectory_incidence_joint.R --config …`（`--from/--to/--blocks/--list`） |
| 指标池预检 | `run/trajectory_incidence/screen_trajectory_joint_index_pool.R --config …` → `reports/tj_index_screen_<db>.md` |
| 筛选门控规则 | `.cursor/rules/trajectory_joint_index_screening.mdc`（Gate 0/1/2 + 用户确认） |
| 证据链模板 | `configs/templates/reports_tj_index_screen.template.md` |
| 决策树 | `Decisiontree/decision_tree_trajectory_incidence_joint.md` |
| Blocks 目录 | `docs/Blocks_catalog.md` §`82_trajectory_incidence_joint`（536 blocks） |
| 冒烟 | `tests/smoke_trajectory_joint.R`（SMOKE_OK） |

## 本次进引擎的修复（勿课题私改绕过）

1. **`tj_calc_index_waves` 公式求值 bug**：`eval(~expr)` 返回 formula 而非数值
   → 改 `eval(parse(text = expr), envir = env)`。影响所有 `recompute_indices=TRUE` 课题。
2. **`.tj_comp_env` parent**：`stats::globalenv()` 不存在 → `globalenv()`。
3. **模板插补接线**：pipeline 必须含 `imputation`（gbmtm_fit 之后、cox 之前），
   且 `config$imputation$exclude_from_mice_cols` 锁 `grp_* / event / time / .tj_row_id`
   —— 否则 `mi_rubin_enabled` 恒 FALSE，单套 Cox 冒充多重插补（违反 `mi_m5_rubin_pool`）。
4. **单跑入口 `--list`** 检查点早退，不空跑全链。

## 新课题标准顺序

```
1. 列审阅（review-raw-covariate-columns）→ disease_vars
2. screen_trajectory_joint_index_pool.R → Gate 0/1 落盘
3. PubMed Gate 2（疾病×A / ×B / ×A+B）→ 证据链 md → 用户确认 index_pairs
4. 拷 config 模板 → 改 waves/index_pairs/model_sets/outcome/age_filter
5. run_trajectory_incidence_joint.R 全链 → 发表收口
6. run_pub_qc_after_project.R + nature 两 skill → P0 清零 → 中期 → prune
```

## 反例（禁止）

- 在课题 scripts/ 重写 phase0–9 脚本而不调 tj_* blocks
- 穷举 combn 指标对不经 Gate 2 / 用户确认
- pipeline 漏 `imputation` 块后用 complete#1 Cox 交差
- 换病种照抄 ELSA `model_sets`（bpmed/fvc 等列不存在须裁剪）
