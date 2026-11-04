# 分析决策树 — 心脏围术期 AKI × 数据库池化（龚倩）

> 文献方法：Allyn et al. *Critical Care* 2026;30:364（PMID 42151996）  
> 人群：CSAAKI_Pool_20261103（心脏围术期 + KDIGO AKI，DN=1）  
> 客户老师：龚倩  
> 产出：`\\192.168.68.133\02block_result\33_AKI\database_pooled_42151996`  
> 用户确认：2026-11-04（禁 urine_output；expA–D；外验 eICU+INSPIRE；结局死亡+RLoS）

## 地基

| 项 | 结论 |
|---|---|
| 研究问题 | ICU **预后预测**（院内 ICU 死亡 + 剩余住院日 RLoS） |
| 地基 | **预后 `survival`** |
| 方法后缀 | 多源池化 / 迁移 / TPC（`78_database_pooling_full`） |
| 路径 | **3A** 复制肝硬化/ACG 课题实例 |

## 四库角色

| 库 | 角色 | DN=1 n |
|---|---|---|
| SICdb | expA 单库训练（对标 Amsterdam） | 1,067 |
| MIMIC-IV | expB 单库；expC 预训练源；expD 池化 | 6,978 |
| eICU | **全程外验 test**（不进训练） | 2,822 |
| INSPIRE | **全程外验 test**（不进训练） | 1,055 |
| AmsterdamUMCdb | **本轮不做** | — |

```text
expA  SICdb alone
expB  MIMIC-IV alone
expC  Transfer MIMIC → SICdb（全层微调）
expD  Pool MIMIC + SICdb
外验  eICU + INSPIRE（全部进 test）
```

## 特征铁律

- **纳入特征不进模**（对齐 ACG 剔 ALT/AST）：全库剔除 `urine_output` + `creatinine`
  - 纳排仍用肌酐/尿判 KDIGO AKI；建模特征池不含这两项
  - 尿量另因 INSPIRE 术后 ICU 不可用，四库同剔
- MIMIC/eICU 小时层来自 BlendedICU `blendedlos_ready`
- SICdb / INSPIRE 按 BlendedICU 变量名自建小时宽表后并入同一棵 BlendedLoS 树
- 训练环境变量：`DBPOOL_DROP_TS=urine_output,creatinine`

## 结局与划分

- 结局：ICU 死亡 + RLoS（cap=10 天），死亡样本 RLoS mask
- 划分：患者级 70/15/15，seed=974；eICU/INSPIRE 不分 train/val
- 超参：文献级 `n_epochs=200`, `batch=32`, `alpha=20`

## 必须交付（对齐肝硬化 summary_results）

Fig.1 Study pipeline · Fig.2 Training size · Table 1–4 · Table S1–S2 · Methods · 中期（龚倩）

## 跑法

```bash
# 29：建 SICdb/INSPIRE 小时层 + 组装树
python Blocks/78_database_pooling_full/scripts/build_csaaki_sicdb_inspire_hourly.py
python Blocks/78_database_pooling_full/scripts/prepare_csaaki_blendedlos.py

# 34：训练
Rscript run/database_pooling/run_database_pooling_batch.R \
  --config configs/studies/database_pooling/config_database_pooling_csaaki_42151996.R \
  --workers auto
```
