# 子痫 · MIMIC 单库 · by_index 发病 ML 设计

**日期：** 2026-08-21  
**状态：** 用户已口头确认设计方向；本文件待用户审阅后进入实施计划  
**课题路径：** `/mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/`  
**对照套路：** `21_ovarian cancer/small sample prediction_39780007`（同 PMID 六模型；本课题改为**发病 logistic**）

---

## 1. 目标

在 **单库 MIMIC** 上，对当前基线**能算出的全部复合指标**做 `by_index` 发病机器学习批量分析，10 路并行，仅跑约定六模型，产出 `by_index/` 下各指标表图。

**不在本轮：** 全变量 `all_vars_ml`；双库；预后 Cox；额外模型（logistic/KNN 等）。

---

## 2. 数据与变量

| 角色 | 来源 | 说明 |
|------|------|------|
| 基线 | `data/D01_baseline_MIMIC_GW_0804.RData` → `baseline` | n≈223452，实验室/共病/ALBI 等 75 列 |
| 结局队列 | `data/D03_result_子痫_MIMIC(1).RData` → `result` | n=4756；`subject_id` + `DN`（1=482，0=4274） |
| 分析表 | `Data/mimic/D04_dabiao.RData` → `dabiao` | `result` ⟕ `baseline`（按 ID；重叠 4756，无丢失） |
| 结局 | `DN` | 分析组 Case / 对照组 Control；`outcome_column = "DN"` |
| ID | `ID`（由 `subject_id` 对齐） | |
| 人群 | 全女性；Age 约 19–52（中位 33；4 例 Age NA） | Gender 不进协变量/亚组 |

**疾病硬排除（`analysis_exclusion$disease_vars`）：**  
实施前按 `review-raw-covariate-columns` 对合并后 `dabiao` **逐列审阅**，落盘 `Data/_column_review.md`。子痫相关至少审阅并通常排除：妊娠高血压谱系与诊断泄漏（如 `Hypertension` 若与子痫定义重叠）、血糖轴（`T1DM`/`T2DM`/`Diabetes`/`Glucose`/`HbA1c`）、尿蛋白/尿白蛋白轴（`UrineProtein`/`AlbuminUrine`/`AlbuminCreatinine`）等；不确定默认排除。成分排除仍由 `analysis_exclusion` 按当前 index 自动做。

---

## 3. 架构（方案 A）

```
prep: merge D01+D03 → Data/mimic/D04_dabiao.RData
  + Data/_column_review.md
→ config.R（.study + ml_dual_batch_build + 六模型/年龄/排除覆盖）
→ Rscript run/ml/run_ml_dual_batch.R --config <study>/config.R --workers 10 --db nhanes
→ by_index/<INDEX>/ …（fail_policy=continue，skip_existing=TRUE）
```

- **入口：** `run/ml/run_ml_dual_batch.R`
- **构建器：** `configs/study_interface/ml_dual_batch_build.R`（默认 `study_type = incidence`）
- **单库技巧：** 主/次槽位均指向同一 `D04_dabiao`；`db_mode = "nhanes"` 只跑主库槽（与卵巢癌小样本一致）
- **指标：** `index_group = "all"`，`index_vars = NULL`，`index_mode = "single_loop"`
- **关联：** 发病 logistic（**不要**设 `assoc_model = "cox"`）
- **并行：** `parallel_workers = 10L`，`max_workers = 10L`，命令行 `--workers 10`

---

## 4. 分析规格

| 项 | 取值 |
|----|------|
| 模型 | `adaboost`, `tabpfnv2`, `catboost`, `xgboost`, `lightgbm`, `rf` |
| 年龄亚组 | `age_cutoff = 35`（高龄产妇常用界）；`Age_Group` 仅 `< 35` / `≥ 35` |
| 协变量铁律 | `assoc_covariate`：Model1=Age；Model2=Age+UV 显著且未进最终 ML；勿写死 model1/2_factors |
| 插补 | 训练集拟合 MICE（`fit_on = "train"`），与卵巢癌一致 |
| TabPFN | 沿用本机可用 Python（Windows 研究机路径或 WSL 等价）；`HF_*_OFFLINE=1` |
| 飞书 | `feishu_enable = FALSE` |

---

## 5. 成功标准

- [ ] `Data/mimic/D04_dabiao.RData` 存在且 n=4756，`DN` 事件数=482  
- [ ] `Data/_column_review.md` 已落盘，`config$analysis_exclusion$disease_vars` 与之对齐  
- [ ] `config.R` 中六模型名单正确；`age_cutoff=35`；`index_group=all`  
- [ ] 批处理以 10 worker 启动；日志可见并行调度  
- [ ] `by_index/` 下出现多个指标目录；失败指标不阻断整批（`fail_policy=continue`）  
- [ ] 成功指标含 ML 六模型性能相关表/图（引擎默认编号）

---

## 6. 风险与备注

- 本库缺组分的复合指标会在 index 步失败或被跳过，属预期。  
- Age 最大值 52，切点 35 两侧均有人；切点 65 禁用。  
- 工作区若无 git remote/仓库，design 文档仅落盘主仓 `docs/superpowers/specs/`，不强制 commit。  
- 本轮不跑 `run_ml_small_sample_pub.R` 全变量后处理；若后续要对成功指标做 Youden+bootstrap Table 4/5，另开一轮。

---

## 7. 用户确认记录

- 特征模式：by_index，本库可算全部复合指标（`index_group=all`）  
- 并行：10 路  
- 年龄切点：35（选项 A）  
- 设计方案 A：口头「同意」（2026-08-21）
