# AKI_TX BUN_Cr P0 复发复用地图（2026-11-05）

课题：`19_AKI_TX_刘雪艳` / `【success】BUN_Cr` / `summary_results`。

## 为何同一批 P0 会反复出现

| P0 | 根因（引擎/模板层） | 典型表现 |
|----|---------------------|----------|
| S1 标题 vs N | Table S1 导出模板默认写 **internal validation set**，而 MI 描述表常按 **complete#1 操作层** 落在 **train** 行（Female+Male=2,390） | 文件名/A1 说内验，单元格是训练集 N |
| Fig1 排除文案 | `attrition` 步名复用 **After imputation** / **Incomplete covariates**，未映射到真实剔除（结局 NA、BUN/Cr 不可算） | CONSORT 框与 Methods/Table1 分母对不上 |
| Fig2 字幕 | LASSO 重导图脚本或旧 patch 在 PDF 上 **stamp「internal validation」** 一行 | pdftotext 与 image_information（training n=2,390）冲突 |
| S4 TabPFN | 超参表从 **全候选算法池** 导出，主文性能表已删 TabPFN 但 **supplementary_ml 未同步 prune** | S4 仍有一行 TabPFN |
| Fig7 md 结局 | 历史流水线列名 **`AKI_TX` / `.pred_AKI_TX`** 被 copy 进 image_information，实际结局为 **`fustatus` 28-day death** | md 写透析/AKI_TX 终点 |
| Methods / software 薄 | `ml_finalize_index_summary_results` 默认 Methods 缺 **seed、VIF 阈值、LASSO bootstrap 次数**；software txt 只列关联包、**缺 xgboost/lightgbm/tidymodels** | 审稿 Methods P0 |

## 下一 ML dual（dev_internal_ext）finalize 检查清单

在 `ml_finalize_index_summary_results` / `run/pub/run_pub_qc_after_project.R` 之后、交付前 **逐条机读**（禁止只跑结构 QC）：

1. **Table S1（eICU）**：文件名 + A1 含 **training set**（若 N=train）；另存 true validation S1 文件名含 **validation set** 且 N≈1,027。Female+Male = 2,390 ⇔ training。
2. **Figure 1**：`pdftotext` 含 **Analytic sample**、**Missing outcome**、**Missing BUN**（或 creatinine）；**不得**出现 `After imputation`、`incomplete baseline`（除非该步真实删人且 Methods 写明）。
3. **Figure 2（LASSO）**：PDF **无** internal validation / development stamp 行；与 `Figures/image_information/Figure 2*.md` 一致（单库 eICU training、n=2,390）。
4. **Table S4**：openpyxl 全表 **无 TabPFN**；Package/函数列非空（DT/RSVM/MLP/KNN/CatBoost）。
5. **SHAP image_information**：结局 = **28-day in-hospital mortality (`fustatus`)**；若提 `AKI_TX` 须标 **historical label only**。
6. **Methods + Methods_software_versions.txt**：`seed_used`（来自 split meta CSV）、VIF 阈值、LASSO `lasso_cv_times`/bootstrap、Rubin m=5；software 含 **xgboost、lightgbm、randomForest、glmnet、tidymodels 栈**。

## 引擎挂点（勿再在课题 scripts 堆 hotfix）

| 修复类型 | 优先入口 |
|----------|----------|
| S1 角色标题 | `R/ml_index_summary_results.R` + `pub_sync_xlsx_a1_titles_to_filenames` / `pub_xlsx_edit_cells` |
| Fig1 标签 | `R/attrition_log.R` + 课题 `config$attrition$steps`（`.cursor/rules/attrition_consort_flowchart.mdc`） |
| Fig2 无 stamp | LASSO 发表重导走引擎块，禁止 PDF 后处理加字幕 |
| S4 与主文算法集同步 | `Blocks/24_ml_supplementary` 导出列表 = Tables 3–5 模型集合 |
| image_information | `R/pub_figure_export.R` → `pub_figure_write_image_md` |
| Methods/software | `ml_index_summary_results.R` / finalize 写 Methods 与 `Methods_software_versions.txt` |

## 相关规则

- `.cursor/rules/ml_dual_dev_ext_pub_p0_gate.mdc`
- `.cursor/rules/attrition_consort_flowchart.mdc`
- `run/ml/repair_aki_tx_bun_cr_p0.R`（一次性返工样例，逻辑应回写引擎）
