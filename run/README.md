# 流水线入口脚本（按研究类型分类）

从项目根目录调用，例如：

```bash
Rscript run/environment/run_environment_dkd_batch.R --shared-only
Rscript run/incidence/run_incidence_dual_batch.R --workers auto
Rscript run/feishu/run_feishu_test.R --write-test
```

## 目录

| 目录 | 脚本 | 用途 |
|------|------|------|
| `environment/` | `run_environment_dkd_batch.R` | DKD × 环境 VOC 批量（共享层 + 并行 RCS + 尾段） |
| | `run_environment_dkd_batch_worker.R` | 单 VOC RCS worker（由 batch 调度） |
| | `run_environment_dkd_nhanes.R` | 单次串行调试 |
| `incidence/` | `run_incidence_dual_batch.R` | 发病双库批量（唯一入口） |
| | `run_incidence_dual_batch_worker.R` | 单指标 worker（由 batch 调度；也可 `--from/--to` 续跑某段） |
| `survival/` | `run_survival_sae.R` | 预后 SAE / Cox |
| `complex_network/` | `run_complex_network_clhls_batch.R` | CLHLS 抑郁焦虑 GGM 网络 |
| `bayesian_comorbidity/` | `run_bayesian_comorbidity_batch.R` | Health Octo / BODN 贝叶斯共病 |
| `trajectory_incidence/` | `run_trajectory_incidence_aki_batch.R` | 脓毒症 AKI 肌酐 LCMM 发病 |
| `trajectory_prognosis/` | `run_trajectory_prognosis_plt_batch.R` | 血小板 JLCM 轨迹预后 |
| `study/` | `run_four_literature_studies_parallel_batch.R` | 四套文献流水线并行总入口 |
| | `run_four_paper_pipelines_parallel_batch.R` | 交叉滞后/竞争风险/AI临床/双库MR 四套并行 |
| `cross_lagged/` | `run_cross_lagged_frailty.R` | 交叉滞后**唯一**入口（`--batch` / `--phase`；阶段在 `Blocks/54_cross_lagged_full/phases/`；试点在 `.../pilots/`） |
| `competing_risk/` | `run_competing_risk_chf_batch.R` | TyG 竞争风险（B22） |
| `ai_clinical/` | `run_ai_clinical_cdm_batch.R` | LLM 临床决策评测（B24） |
| `dual_incidence_mr/` | `run_dual_incidence_mr_crm_batch.R` | 双库发病+MR（B13） |
| `medication_regimen/` | `run_medication_regimen_text_soft_batch.R` | TEXT/SOFT STEPP（B30） |
| `markov_cognitive/` | `run_markov_cognitive_clhls_batch.R` | CLHLS 三状态 Markov（B31） |
| `cdc_wonder/` | `run_cdc_wonder_dobbs_batch.R` | CDC WONDER CITS（B15） |
| `network_temperature/` | `run_network_temperature_adolescent_batch.R` | 网络温度（B29） |
| `sem_chain_mediation/` | `run_sem_chain_mediation_charls_batch.R` | SEM+链式中介 CHARLS（B25/B27） |
| `ai_medical_qa/` | `run_ai_medical_qa_cot_batch.R` | 医学 QA CoT（B26） |
| `causal_forest_trajectory/` | `run_cftraj_charls_batch.R` | 因果森林+认知轨迹（B28） |
| `study/` | `run_four_user_paper_pipelines_parallel_batch.R` | 四套用户文献（SEM/QA/CfTraj/NetTemp）并行 |
| `study/` | `run_four_new_paper_pipelines_parallel_batch.R` | 用药/马尔可夫/CDC/网络温度 四套并行 |
| `incidence_prepost/` | `run_incidence_prepost_charls_batch.R` | 发病前后认知轨迹（B18） |
| `target_trial/` | `run_target_trial_rasi_aki_batch.R` | 目标试验 RASi-AKI（B19） |
| `transformer_shortseq/` | `run_transformer_aki_single_batch.R` | 单库短序列 Transformer（B17） |
| `dual_change_score/` | `run_dual_change_score_elsa_batch.R` | 双向变化分数 ELSA（B25 结构方程） |
| `study/` | `run_four_target_paper_pipelines_parallel_batch.R` | 四套目标文献（B17/B18/B19/B25）并行 |
| `crm_nhanes_mr/` | `run_crm_nhanes_mr_batch.R` | NHANES CRM×MR 批量（唯一入口；交付表在 `Blocks/70_*`） |
| | `run_crm_nhanes_mr_batch_worker.R` | 单 unit worker |
| | `run_crm_nhanes_mr.R` | 单次串行调试 |
| `feishu/` | `run_feishu_*.R` | 飞书多维表初始化与同步 |

## 已移除的占位入口

以下仅为文献 GAP 模板、Blocks 未落地，已删除：

- `run_association_nhanes.R`（关联分析模板）
- `run_burden_gbd.R`（GBD 负担模板）
- `run_survival_iptw_pooled.R`（预后 IPTW 模板）

发病侧已并入 `run_incidence_dual_batch.R`，以下旧入口与临时补跑脚本已删除：

- `run_incidence_{dual,single,iptw,nhanes,nhanes_batch}.R`
- `rerun_gate_b_logistic.R` / `rerun_subgroup_forest_fix.R` / `_redraw_ac_roc_boxplot.R`
- `run/crm_nhanes_mr/rerun_table*.R`（已并入 `Blocks/70_crm_nhanes_pub/14block_crm_nhanes_table_builders.R`）

对应 config 模板仍保留在 `configs/templates/`（请改指向 dual_batch）。

勿在 `run/` 再加 `_repair_` / `rerun_` 旁路脚本；表逻辑进 `Blocks/`，入口只留薄 wrapper。

## 环境变量

`MEDICAL_BLOCKS_ROOT` 可指向项目根，与当前工作目录无关。
