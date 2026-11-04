# 脓毒症 · Jin2025 方法迁移 · 双库全复合指标并行

| 项 | 值 |
|---|---|
| 决策树 | `Decisiontree/decision_tree_sepsis_jin_prognosis_index_sofa_dual.md` |
| 对抗阅读 | `paper_40295872`（Q1–Q8 PASS） |
| 文献 | Jin et al. Cardiovasc Diabetol 2025;24:422（方法迁脓毒症） |
| 项目根 | `//192.168.68.133/02block_result/36_spesis/prediction_41194138` |
| 地基 | 预后 `survival` dual-batch + **方法目录** Blocks（非 82 套路包） |
| R | `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"` |

## 0. 准备分析集（已跑过可跳过）

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/sepsis_jin_prognosis/prepare_analysis_data.R \
  --project "G:/02block_result/36_spesis/prediction_41194138"
```

写出 `Data/mimic/D04_dabiao.RData`、`Data/eicu/D04_dabiao.RData`（院内死亡主终点；附 30/365 天列）。

当前约：**MIMIC n=8245 / 事件 2302**；**eICU n=13946 / 事件 2684**。

## 1. Config

- 模板：`configs/templates/config_sepsis_jin_prognosis_index_sofa_dual_batch.template.R`
- 项目：`.../prediction_41194138/config_survival.R`（41 指标 single_loop；方法后缀已挂）

## 2. 跑批（须用户确认试跑后再执行）

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
CFG="G:/02block_result/36_spesis/prediction_41194138/config_survival.R"

# 共享层
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/sepsis_jin_prognosis/run_batch.R --config "$CFG" --shared-only

# 并行指标
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/sepsis_jin_prognosis/run_batch.R --config "$CFG" --workers auto
```

等价直接调：`run/survival/run_survival_dual_batch.R`（同参数）。

## 3. Blocks（按方法文件夹，可复用）

| register_block | 路径 | 本课题用途 |
|---|---|---|
| （预后 dual 前缀） | `02_data_clean` … `15_rcs` / `18_subgroup` / `27_KM` | 清洗→指标→插补→Table1→UV→VIF→Cox/RCS/KM/亚组 |
| `cox_tertile` / `cox_interaction` | `10_cox/` | 三分位主 Cox；连续×SOFA 交互（已有） |
| `km_strata` | `27_KM/` | 四组 KM（已有） |
| `derived_grouping` | `02_data_clean/02block_derived_grouping.R` | 暴露×SOFA → Q1–Q4（本课题缺口补） |
| `cox_multi_horizon` | `10_cox/09block_cox_multi_horizon.R` | 院内/30d/365d Cox（缺口补） |
| `logistic_nomogram` | `11_logistic/20block_logistic_nomogram.R` | rms 列线图+校准（缺口补；非 Shiny） |
| `shap_glm` | `17_shap/02block_shap_glm.R` | 解释 nomogram/glm（缺口补；树模型仍用 `shap`） |
| `mediation_prognosis` | `20_mediation/` | TotalCo2 代理 bicarbonate（已有） |
| `simple_ROC` / `boxplot` | `13_roc` / `05_boxplot` | 补充图（已有） |

Helper：`R/literature_jin_index_sofa.R`（分组函数）。**禁止**再复活 `Blocks/82_jin_*` 套路整包。

## 4. 飞书

```bash
Rscript run/feishu/run_feishu_mark_sepsis_jin_prognosis.R
```

Base: https://lcn1in9jd6ie.feishu.cn/base/RBjfb2iwmamW14s4WhKcS7kwnie

## 5. 发表收口 / 质控 / 中期

跑完后按 `pub-qc-after-project` + Nature P0 → 中期 PDF。
