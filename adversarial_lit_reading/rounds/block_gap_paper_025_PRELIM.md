# Block 缺口预登记（待用户确认）— paper_025 数据库池化 / BlendedLoS

> **状态**：PRELIM（对抗阅读 Q1–Q8 进行中；**未实现任何新 Block**）  
> **铁律**：用户确认序号与名单后，才在 `Blocks/78_*` 落地；禁止改动既有 `71_*`/`67_*` 等项目。

## 文献与公开代码

| 项 | 内容 |
|---|---|
| 文献 | Allyn et al. *Critical Care* 2026;30:364. DOI `10.1186/s13054-026-06034-5` |
| 公开训练代码 | **有**：https://github.com/CIC-1410/BlendedLoS （已镜像 `python/blended_los_upstream/`） |
| 公开数据管道 | BlendedICU：https://github.com/USM-CHU-FGuyon/BlendedICU（本课题已有四库真实提取包，可跳过从零 OMOP） |
| 本地数据 | `/mnt/g/02block_result/48_ICU/database_pooled_42151996/data/RealExtraction_4DB_20261009/`（hourly + delivery 已就绪；**训练未跑**） |

## 地基判定（Phase 2 草案）

| 问题 | 判定 |
|---|---|
| 研究问题 | ICU **预后预测**（院内 ICU 死亡 + 剩余住院日 RLoS） |
| 地基 | **预后 `survival`**（与发病地基无关） |
| 方法后缀 | **多源池化 / 迁移学习 + TPC 时序深度模型**（类比 TST 的「方法层」挂法，**不是**第三块地基） |
| 路径类型 | **3B**：地基有、后缀无 → 新建 `Blocks/78_database_pooling_full/`（建议序号 **78**，接在现有最大 **77** 之后） |
| 复用公开代码 | **是**：训练/评估优先封装 `BlendedLoS`（TPC/LSTM/Transformer），R 侧做 batch/表图/飞书编排 |

## 文献必须复现的图表（一个不能少）

| 编号 | 内容 | 数据/代码入口 |
|---|---|---|
| **Fig.1** | 七步流水线 + 四种训练策略示意 | 概念图（可脚本重绘） |
| **Table 1** | 四库 stay 特征对照 | delivery 静态特征 + cohort |
| **Table 2** | 单源内外验：MAPE / AUROC / AUPRC | BlendedLoS dataset_benchmark |
| **Table 3** | 四方案 specialization / generalization + Mcomposite | main_experiment |
| **Fig.2** | 训练样本量↑ 对死亡/RLoS 表现 | training_size_study |
| **Table 4** | 文献对照表（叙述性） | 半自动汇总 |
| **Table S1** | clip 前后分布（MOESM1） | preprocessing + 描述统计 |
| **Table S2** | LSTM vs Transformer vs TPC（MOESM2） | model_benchmark |

## 可复用现有 Block（不新建、不改旧项目逻辑）

| 能力 | 现有入口 | 用法 |
|---|---|---|
| 发表图四目录 | `R/pub_figure_export.R` | finalize 挂接 |
| 发表表 SCI xlsx | `export_sci_table` / utils | Table1–3 导出 |
| 飞书同步 | `run/feishu/` | 新建本套路 setup/sync（仿 TST） |
| 预后 batch 骨架思路 | `run/survival/` / TST `run` | **只抄结构**，新 `run/database_pooling/` |
| 时序 DL 编排经验 | `Blocks/71_two_stage_transformer_stroke` | **参考接口**，不改 71 源码 |

## 建议新建 Blocks（序号 78，请确认）

目录建议：`Blocks/78_database_pooling_full/`

| 建议文件 | block 名 | 作用 | 是否必须新写 |
|---|---|---|---|
| `01block_dbpool_cohort_ingest.R` | `dbpool_cohort_ingest` | 读 RealExtraction delivery/hourly，建分析队列 | **是**（现有无四库池化 ingest） |
| `02block_dbpool_preprocess.R` | `dbpool_preprocess` | clip / 前向填充+缺失 mask / q5–q95 归一化（对齐原文+BlendedLoS） | **是** |
| `03block_dbpool_split.R` | `dbpool_split` | 患者级 70/15/15；四库分区；seed 可配 | 部分可比对 `tst_split`，但多源分区不同 → **建议新写** |
| `04block_dbpool_labels.R` | `dbpool_labels` | ICU 死亡 + 动态 RLoS（cap=10；死亡 mask） | **是** |
| `05block_dbpool_train_eval.py` + R wrapper | `dbpool_train_eval` | 调用上游 BlendedLoS：单源/池化/迁移/架构基准/样本量曲线 | **是**（Python 核心） |
| `06block_dbpool_metrics.R` | `dbpool_metrics` | AUROC/AUPRC/MAPE/Mcomposite + DeLong/bootstrap CI | **是** |
| `07block_dbpool_pub_tables.R` | `dbpool_pub_tables` | Table1–4 + S1–S2 | **是** |
| `08block_dbpool_pub_figures.R` | `dbpool_pub_figures` | Fig.1–2 + 四目录 | **是** |
| `09block_dbpool_batch_finalize.R` | `dbpool_batch_finalize` | batch 汇总、code 包可选、飞书钩子 | **是** |

## 交付件规划（确认 Block 后再写）

- `Decisiontree/decision_tree_database_pooling.md`
- `configs/templates/config_database_pooling_batch.template.R`
- `configs/studies/.../config_database_pooling_*.R`（新目录）
- `run/database_pooling/run_database_pooling_batch.R` + worker（`--shared-only` / `--workers`）
- `run/feishu/run_feishu_setup_database_pooling_tables.R`
- Rscript：`"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`

## 请你确认的选项

1. **新 Block 目录序号用 `78_database_pooling_full`？**（当前最大为 77）  
2. **上表 01–09 是否全部新建？** 有无要删/合并？  
3. **训练是否强制用公开 `BlendedLoS`（推荐）**，还是重写 TPC？  
4. **对抗阅读范围**：按「完整分析深度」跑 **Q1–Q8 全套**（已开 Q1）；确认后继续。  
5. **飞书多维表**：挂到你给的 base `RBjfb2iwmamW14s4WhKcS7kwnie` 新建「数据库池化」表，还是写入现有工作计划表？

**在你回复确认前：不创建 Blocks/78、不写项目 config、不开训练。**
