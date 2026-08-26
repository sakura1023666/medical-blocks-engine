# 子痫 · MIMIC 单库 · by_index 发病 ML 重跑设计

**日期：** 2026-08-24  
**状态：** 用户已口头「同意」方案 1；待审阅本文件后进入实施计划  
**课题路径：** `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/`  
**前序设计：** `docs/superpowers/specs/2026-08-21-eclampsia-mimic-ml-incidence-by-index-design.md`  
**对照：** `21_ovarian cancer/small sample prediction_39780007`（同 PMID 六模型；本课题发病 logistic）

---

## 1. 目标

在 **单库 MIMIC** 上，对当前基线**能算出的全部复合指标**做 `by_index` 发病机器学习批量分析，10 路并行，**仅六模型**，产出 `by_index/`。

**本轮明确不做：**

- 全变量 `all_vars_ml`（曾短暂讨论 A+B，已取消 B）
- `dabiao_clean.RData`（n=296；保留在盘但不使用）
- 双库、预后 Cox、六模型以外模型
- `run_ml_small_sample_pub.R`（Youden + bootstrap Table 4/5 + Figure 4）——另开一轮

---

## 2. 现状（2026-08-24 盘点）

| 项 | 状态 |
|----|------|
| `Data/mimic/D04_dabiao.RData` | 存在；`dabiao` n=4756；DN Case=482 / Control=4274 |
| `Data/_column_review.md` | 存在；disease_vars 13 项已审 |
| `config.R` / `build_merged_data.R` / `by_index/` / `logs/` | **已清除**；需从 SDD 备份重建 config 并重跑 |
| `Data/mimic/dabiao_clean.RData` | 存在（n=296）；**本轮不用** |
| 8/21 批跑 | Task 4 曾启动；非失败指标约 22；产物已不在课题根 |

---

## 3. 数据与变量

| 角色 | 来源 | 说明 |
|------|------|------|
| 分析表 | `Data/mimic/D04_dabiao.RData` → `dabiao` | **唯一分析表**（用户选 A） |
| 结局 | `DN` | Case / Control；`outcome_column = "DN"` |
| ID | `ID` | |
| 人群 | 全女性 | `Gender` 进 drop/exclude，不进协变量/亚组 |

**`analysis_exclusion$disease_vars`（与 `_column_review.md` 对齐，禁止另写）：**

```r
c(
  "Hypertension",
  "T1DM", "T2DM", "Diabetes", "Glucose", "HbA1c",
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  "UricAcid", "CKD", "Acute_Renal_Failure"
)
```

成分排除仍由 `analysis_exclusion` 按当前 index 自动做。

---

## 4. 架构（方案 1）

```
已有: Data/mimic/D04_dabiao.RData + Data/_column_review.md
→ 重建 config.R（内容对齐 .superpowers/sdd/eclampsia-task-3-review-pkg.md 全文）
→ Windows Rscript + bat:
     run/ml/run_ml_dual_batch.R
     --config G:/…/config.R --workers 10 --db nhanes
→ by_index/<INDEX>/ …（fail_policy=continue，skip_existing=TRUE）
```

- **入口：** `run/ml/run_ml_dual_batch.R`
- **构建器：** `configs/study_interface/ml_dual_batch_build.R`（incidence）
- **单库：** 主/次槽均指向同一 `D04_dabiao`；`db_mode = "nhanes"`
- **指标：** `index_group = "all"`，`index_vars = NULL`，`index_mode = "single_loop"`
- **关联：** `assoc_model = "logistic"`（禁止 cox）
- **并行：** 10 workers；启动方式同 Task 4（bat + `MEDICAL_BLOCKS_SKIP_WIN_R=1`，避免路径空格拆参）

---

## 5. 分析规格

| 项 | 取值 |
|----|------|
| 模型 | `adaboost`, `tabpfnv2`, `catboost`, `xgboost`, `lightgbm`, `rf` |
| 年龄亚组 | `age_cutoff = 35`；`Age_Group` = `< 35` / `≥ 35`；禁止 `age_group_cutoffs` |
| 协变量铁律 | Model1=Age；Model2=Age+UV 显著且未进最终 ML；勿写死 model1/2_factors |
| 插补 | `fit_on = "train"` |
| TabPFN | `C:/ProgramData/anaconda3/python.exe`；`HF_*_OFFLINE=1` |
| 飞书 | `feishu_enable = FALSE` |

---

## 6. 成功标准

- [ ] `config.R` 落盘；六模型名单、`age_cutoff=35`、`index_group=all`、`disease_vars` 13 项、`rawdata`→D04 自检通过
- [ ] 批处理 10 worker 启动；`logs/` 可见调度
- [ ] `by_index/` 出现多指标目录；失败不阻断整批
- [ ] 成功指标含六模型性能相关表/图
- [ ] 课题根下无 `all_vars_ml/` 本轮产物；未使用 `dabiao_clean`

---

## 7. 风险与备注

- 缺组分的复合指标失败/跳过属预期。
- 课题目录名含空格：必须用带引号的 Windows 路径 + bat 启动（WSL 直调易拆参）。
- 无 git：design/plan 只落主仓 `docs/superpowers/`，不强制 commit。
- `dabiao_clean` 保留不动，避免误删他人产物。

---

## 8. 用户确认记录

- 2026-08-21：by_index + 全部复合指标 + 年龄 35 + 方案 A 同意
- 2026-08-24：曾要求 A+B，后改为 **只跑 by_index**、六模型、**不跑 all_vars**
- 2026-08-24：分析表选 **A = D04_dabiao（n=4756）**
- 2026-08-24：方案 1（重建 config + 10 worker 重跑）口头「同意」
