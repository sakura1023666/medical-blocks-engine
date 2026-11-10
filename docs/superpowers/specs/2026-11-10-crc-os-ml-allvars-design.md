# CRC 术后总生存 · 全变量预后 ML（对齐 EMs 交付）设计

**日期**：2026-11-10  
**状态**：用户已口头确认设计要点；本文为落盘规格，实现前请再扫一眼  
**参考交付**：`\\192.168.68.133\02block_result\35_EMs\ml_40395549\summary_results`  
**数据**：`\\192.168.68.133\02block_result\31_crc\ml_40395549\DATA\数据3j.xlsx`（sheet `数据3g`）  
**产出根**：`/mnt/g/02block_result/31_crc/ml_40395549/`

---

## 1. 目标

在结直肠癌单中心队列上，做**单库、无主暴露并行、全变量选特征**的预后机器学习预测（总生存），交付表图与 EMs 复发 ML 项目**一一对齐、一个不少**；config **不得**残留 EMs 写死字段（AMH / rAFS / 复发结局 / 45 岁切点 / horizon=48 / `fit_on=all` 等）。

## 2. 已锁定决策

| 项 | 决策 |
|----|------|
| 模式 | 全变量 all_vars（对齐 EMs；非指标并行） |
| 结局 | 总生存：事件 `Death`，时间 `OS_Months`（月） |
| Fig6 暴露 | LASSO 入选连续特征中验证表现最强者（跑完再钉图题；不预写死 NLR/AMH） |
| 年龄亚组 | `age_cutoff = 65` → `< 65` / `≥ 65` |
| 主评价时点 | `surv_horizon = 60`（月；5 年 OS） |
| 插补顺序 | **先** `train_validation`，**再** `imputation(fit_on="train")` |
| 划分比例 | 默认 `train_ratio = 0.75`（对齐 EMs；可按 Age 平衡） |
| MI | `m = 5`，操作层 `complete_action = 1`；推断 Cox 走 Rubin（与引擎默认一致） |

### 数据快照（写 config 依据）

- n ≈ 523；死亡事件 ≈ 135（约 25.8%）
- `OS_Months`：min≈3.8，中位≈50，P90≈88，max≈102
- t=60：在险 ≈192；累计事件 ≈131/135（5 年几乎收齐事件）
- Age 中位 ≈66；≥65 ≈284

## 3. 范围与非目标

**做**

- 清洗 → 列映射 → 硬排除 → 划分 → train-only MICE → 基线/UV/VIF/LASSO → 连续特征 Cox/RCS/KM/亚组 → 六模型 ML → 性能图/表 → SHAP → Shiny → 纳排图 → `summary_results` 白名单收口 → 发表质控 → 中期 PDF

**不做**

- 复合指标并行 job（NLR/PLR/… 各开一套）
- 把 `Death_1y/3y/5y` 当主结局
- 照抄 EMs 工程特征（Age2/logAMH 等）或 EMs 疾病文案
- 为对齐交付而把 PDF 整页栅格进 `Figures/pdf/`

## 4. 列与泄漏门控（实现前必须落盘 `_column_review.md`）

### 4.1 建议保留为候选特征（清洗后英文短名）

人口学/临床：`Age`（←Age_years）、`Sex`、`Smoking`、`Hypertension`、`Diabetes`、`R0_Resection`、`Tumor_Size_cm`、`Differentiation`、`Vascular_Invasion`、`Perineural_Invasion`、`T_Stage`、`M_Stage`、`TNM_Stage`  

实验室/炎症：`NEU`,`LYM`,`MON`,`PLT`,`ALB`,`CEA`,`CA199`,`NLR`,`PLR`,`LMR`,`SII`,`WBC`,`HGB`,`CRP`

### 4.2 必须排除（不作特征）

- ID：`Study_ID`（保留作 id_column，插补后可 strip）、`住院号`
- 时间/日期：`Surgery_Date`、`Last_Followup_Date`、`Death_Date`、`Followup_End_Date`、`OS_Days`、`OS_Months`
- 结局及相关：`Death`、`Death_1y`、`Death_3y`、`Death_5y`、`Followup_Status`、`Loss_to_Followup_Reason`、死亡原文/年份、生存时间口径说明列
- 空/无名列（xlsx 中 `T_Stage` 与 `M_Stage` 之间的空表头列）

### 4.3 类型与重叠

- 分期/分化等编码：`force_factor_vars`（至少 `Differentiation`, `T_Stage`, `M_Stage`, `TNM_Stage`）；**禁止**当连续 RCS / 分位 KM 主暴露
- 炎症评分与成分并存：启用 `feature_selection$dedupe_overlapping_severity_scores` 同类去重逻辑；LASSO 后若成分与 NLR/PLR/LMR/SII 同入选，按引擎重叠规则保留衍生评分优先或按 UV/VIF 结果记录于 Methods
- `disease_vars`：本课题为预测任务，病理/分期本身是预测因子 → **默认空集**（与 EMs 同口径）；不得把 TNM 整批当疾病泄漏删掉

### 4.4 列名清洗

xlsx 列为「英文｜中文」管道名；实现时统一映射为英文短名（无下划线展示层仍走 `display_labels` / `pipeline_display_label`）。分析入口优先落盘 `data/D02_Model_Data.RData`（对象名如 `model_data`），避免流水线直读中文表头。

## 5. Pipeline（相对 EMs 的关键差分）

EMs 实际：`imputation(fit_on=all)` → `train_validation`（轻微乐观，已脚注）。

**本课题**：

```text
data_clean → column_mapping → analysis_exclusion
  → train_validation
  → imputation(fit_on=train)
  → baseline_binary
  → univariate_prognosis → multicollinearity_screen
  → ml_feature_selection_bundle
  → cox_ml_continuous_batch → rcs_prognosis → km_continuous_router
  → subgroup_prognosis
  → ml_models_bundle → performance_ml → supplementary_ml
  → shap → shiny_ml_app
  → attrition_flowchart
```

引擎依据：`train_validation` 可读 `cleaned`；`imputation$fit_on="train"` 需要已物化的 `ctx$data$train/test`。Methods 必须写实该顺序。

## 6. 发表交付对齐清单（文件角色，非照抄 EMs 文件名中的病名）

### 6.1 Figures（`summary_results/Figures/pdf` + `image_information`）

| 角色 | EMs 参考 | CRC 命名原则 |
|------|----------|--------------|
| Fig1 | Inclusion exclusion flowchart | `Figure 1-CRC Single. …` |
| Fig2 | RCS continuous features | 连续入选特征 RCS |
| Fig3 | Combined KM | 连续特征合并 KM |
| Fig4 | ML performance combined 2×4 | 同角色 |
| Fig5 | SHAP — best/校准优选模型 | 图题写清模型与选定规则 |
| Fig6 | Subgroup forest（暴露钉死后） | 暴露 = 跑完选定的连续特征；Q4 vs Q1 |
| Fig S1 | LASSO-Cox | 同角色 |
| Fig S2 | Shiny web calculator | 同角色 |

### 6.2 Tables

| 角色 | 说明 |
|------|------|
| Table 1 | 基线（按死亡分层） |
| Table 2 / 3 | ML performance wide（train / validation） |
| Table 4 | Cox for ML continuous features |
| Table 5 | Train+Val bootstrap（TD-AUC / C-index / Brier @60m） |
| Table S1 | 插补前后（脚注：MICE fit on train） |
| Table S2 | 正态性 |
| Table S3 | train/val 基线 |
| Table S4 | 单因素 Cox |
| Table S5 | VIF |
| Table S6 | 超参 |
| Table S7 | 校准 intercept/slope（validation） |

另：`Methods_statistical_analysis.md`、`Methods_software_versions.txt`、中期 PDF；交付根白名单 prune。

## 7. Config 禁抄清单（P0）

下列键若出现且值仍属 EMs，视为不合格：

- `outcome_column` / `event_var` = `Is_Recurrence`；`time_var` = `RFS_Months`
- `id_column` = `Pt_ID`；强制 `AMH` / `rAFS_Stage` / EMs `display_labels`
- `age_cutoff = 45`；`surv_horizon = 48`；`fit_on = "all"`（本课题禁止）
- `disease` / 图文件名仍写 Endometriosis / EMs
- `force_include = c("Age","AMH")` → 改为本病（至少 `Age`；第二项待 UV/临床再定，勿写 AMH）
- `literature_pmid = "40395549"` 仅当确认为本 CRC 文献；否则删或改真实 PMID，禁止假装共用 EMs PMID

## 8. Fig6 / 主连续暴露钉死流程

1. LASSO 入选特征落盘后，筛连续变量集合 C  
2. 在验证集上比较 C 中各变量的单变量判别（或与 Table4/验证 C-index 一致的口径）  
3. 取最强者写入 `survival$index_var` / `logistic$index_var` / 亚组图题，**重跑** `subgroup_prognosis`（及必要时 RCS/KM 标题）  
4. Methods / image_information 写明选定规则与最终变量名  

禁止在首跑 config 写死 `NLR` 只为「看起来像有主暴露」。

## 9. 质控与中期

跑完后强制：

1. `Rscript run/pub/run_pub_qc_after_project.R --project <study_root>`  
2. Agent Layer D：`nature-statistics` + `nature-figure`；P0 清零  
3. 核对交付表图角色齐全（§6）  
4. PASS/WARN 后出中期 PDF，再 `pub_prune_delivery_root`

## 10. 风险与开放点

| 风险 | 处理 |
|------|------|
| 空表头列 / N 分期缺失 | 列审阅时确认是否应有 `N_Stage`；缺失则 Methods 一句 |
| 成分+炎症评分共线 | VIF + severity/成分去重；脚注写实 |
| `train_validation` 在 MI 前：结局为 0/1 需正确 `analysis_group` 标签 | 清洗时把 `Death` 编码为可读结局标签或保持 0/1 并配置 analysis/reference |
| 对抗阅读 Phase1 | 地基技能要求接套路前 Q4/Q5/Q8；若用户以本规格+参考课题豁免完整 Q1–Q8，须在决策树注明「复用 EMs 套路决策树 + CRC 数据实例化」 |
| 小样本验证集不稳定 | `allow_m2_eq_m1`；FS `target_n_features` 保持 5–12 量级 |

## 11. 成功标准

- [ ] config 无 §7 禁抄项  
- [ ] pipeline 为 train_validation → imputation(fit_on=train)  
- [ ] `summary_results` 含 §6 全部图/表角色 + Methods + 软件版本  
- [ ] Fig6 暴露为本病选定连续特征，非 AMH  
- [ ] Table5 / 校准 horizon = 60  
- [ ] 发表质控无未处理 P0；中期已出  

---

**自检（spec self-review）**

- 无 TBD/TODO 占位关键决策（Fig6 为流程钉死，非未决）  
- 与口头确认一致：all_vars / OS / age65 / h=60 / MI train-only  
- 范围未混入指标并行  
- 相对 EMs 的唯一结构性变更（插补顺序）已显式写出  
