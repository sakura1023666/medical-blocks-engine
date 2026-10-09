# SOSM+WPR 双库预后 ML 终稿整理设计

> **已废止（2026-09-17）：** 本设计仅重排既有产物，未复刻参考论文的多面板和分层分析。请以 `2026-09-17-aki-sosm-wpr-original-paper-replication-design.md` 为准。

## 目标与边界

- 唯一入选组合：`SOSM+WPR`。
- 从已完成、已验证的 MIMIC-IV 主库和 eICU 外验产物重组终稿，不重训模型。
- 新建 `by_index/【success】SOSM+WPR/publication_final/`；原 `Tables/`、`Figures/`、分库 step 结果保持不变，作为审计底稿。
- 最终目录不得混入单指标 SOSM KM、旧图号、未编号草稿或同一角色的分库重复图。

## Figures 终稿顺序

| 编号 | 内容 | 双库处理 |
|---|---|---|
| Figure 1 | 纳排流程图 | MIMIC-IV/eICU A/B 拼图 |
| Figure 2 | SOSM×WPR Group1–4 KM | A=MIMIC-IV，B=eICU |
| Figure 3 | SOSM RCS | A=MIMIC-IV，B=eICU |
| Figure 4 | SOSM、WPR、联合组与 APSIII ROC | A=MIMIC-IV，B=eICU |
| Figure 5 | Day-7 Landmark，Diabetes 分层 | A=MIMIC-IV，B=eICU |
| Figure 6 | SOSM 预后亚组森林 | A=MIMIC-IV，B=eICU |
| Figure 7 | Boruta 特征选择 | 仅 MIMIC-IV（特征选择只在主库） |
| Figure 8 | 五模型三集 ROC | train/internal/eICU 三面板 |
| Figure 9 | 五模型三集校准 | train/internal/eICU 三面板 |
| Figure 10 | 五模型三集判别指标 | train/internal/eICU 三面板 |
| Figure 11 | 五模型三集 DCA | train/internal/eICU 三面板 |
| Figure 12 | 最优模型 SHAP | 仅 MIMIC-IV（外验不重训/不重新解释） |

每张 Figure 仅保留一个终稿 PDF；需要双库的图必须为单个 A/B PDF，不保留 `-MIMIC IV`、`-eICU` 两张重复终稿。最终统一导出 `pdf/png/tiff/image_information` 四目录。

## Tables 终稿顺序

### 主文

1. Table 1：MIMIC-IV 28 天死亡/存活基线。
2. Table 2：SOSM×WPR Group1–4 Cox，单个工作簿内 Panel A=MIMIC-IV、Panel B=eICU。
3. Table 3：MIMIC-IV training ML performance。
4. Table 4：MIMIC-IV internal validation ML performance。
5. Table 5：eICU external validation ML performance。

### 补充

- S1：eICU 外验基线。
- S2：MIMIC-IV train/internal validation 基线比较。
- S3：MIMIC-IV 单因素 Cox。
- S4：VIF（Panel A=train，Panel B=internal validation；eICU 继承特征审计另列）。
- S5：SOSM/WPR/联合组与 APSIII 的 ROC 数值，Panel A/B。
- S6：比例风险假设，Panel A/B。
- S7：模型超参数。
- S8：Log-Loss。
- S9：DeLong。
- S10：NRI/IDI。

已导出的 xlsx 不直接整表覆盖。终稿通过公共发表表工具从来源工作簿复制/合并；原工作簿不变。合并后执行可读性、样式数和损坏单元格校验。

## 实现方式

1. 在公共 ML dual finalize 中增加可配置的“literature-first”发表映射，不写课题私有 hotfix。
2. 图像配对按角色而非旧 Figure 编号识别，避免 KM 与三集 ROC 同为 Figure 3。
3. 使用公共 PDF A/B 合图与 `pub_figure_ensure_formats()`；生成详细 image_information。
4. 表格按上述唯一角色映射生成终稿，双库角色合并为 Panel A/B。
5. 输出 `MANIFEST.csv`，记录终稿文件、来源文件、数据库、角色和校验状态。

## 验收标准

- `publication_final/Figures/pdf` 恰有 Figure 1–12，各一张，无图号重复。
- Figure 1–6 中要求双库者均为 A/B 拼图；Figure 7/12 明确为主库专属；Figure 8–11 为三集图。
- PDF/PNG/TIFF/MD 数量均为 12，Figures 根无平铺 PDF。
- 主表恰为 Table 1–5；补充表按 S1–S10 连续，无同号多文件。
- Table 2、S5、S6 的双库结果位于同一终稿工作簿并标明 Panel A/B。
- xlsx 校验 `readable=TRUE`、`corrupt_cells=0`、`styles>0`。
- 所有数值来自现有 SOSM+WPR 结果；不重新拟合、不改变模型性能。

