# 分析决策树 — CRC 术后 OS 全变量预后 ML

**课题目录**：`/mnt/g/02block_result/31_crc/ml_40395549/`  
**规格**：`docs/superpowers/specs/2026-11-10-crc-os-ml-allvars-design.md`  
**计划**：`docs/superpowers/plans/2026-11-10-crc-os-ml-allvars.md`  
**参考交付角色**：`35_EMs/ml_40395549/summary_results`（单库 all_vars 预后 ML）

## 地基判定

- **地基**：预后（survival）
- **方法后缀**：全变量机器学习预测（UV Cox → VIF → LASSO-Cox → 六模型 + SHAP/Shiny）
- **非**：指标并行 dual-batch；非发病 logistic

## 对抗阅读备案

本课题以 **复用 EMs all_vars 预后 ML 套路决策树 + CRC 数据实例化** 备案，不重跑完整 Q1–Q8。关键方法学差分已在 design spec 写明（先划分再 `fit_on=train`；结局 OS；年龄 65；horizon 60）。

## 核心节点

1. **数据**：`数据3j.xlsx` → `prepare_crc_model_data.R` → `model_data`（n=523，Dead=135）
2. **结局**：`Death`（Alive/Dead）+ `OS_Months`
3. **划分→插补**：`train_validation`（0.75）→ `imputation(fit_on=train)`
4. **特征**：全列候选；`R0_Resection` 零方差排除；分期/分化 protect + 稀疏水平合并
5. **主评价**：`surv_horizon=60`
6. **Fig6**：LASSO 入选连续特征中验证最强者事后钉死（不预写 AMH/NLR）
7. **交付**：对齐 EMs 表图角色清单（CRC Single 命名）

## Config 禁抄

禁止 AMH / rAFS / Is_Recurrence / RFS_Months / Pt_ID / age45 / horizon48 / `fit_on=all` / EMs 病名。
