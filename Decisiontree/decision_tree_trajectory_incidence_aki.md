# 分析决策树 — 轨迹发病（脓毒症 AKI 肌酐 LCMM）

> 配置：`configs/config_trajectory_incidence_aki.R`  
> Batch：`run/trajectory_incidence/run_trajectory_incidence_aki_batch.R`  
> 文献：Takkavatakarn 2024 *Critical Care*

## 完整流水线

```mermaid
flowchart TD
  Q["早期肌酐轨迹亚型 → AKD / 死亡"]
  D1["data_clean → imputation"]
  T1["trajectory_wide_to_long"]
  T2["trajectory_lcmm_fit\nlcmm::hlme 或 Python 回退"]
  T3["trajectory_outcome_models\nlogistic + Cox"]
  Q --> D1 --> T1 --> T2 --> T3
```

## Block 映射

| Step | Block | 文件夹 |
|------|-------|--------|
| 1-3 | `trajectory_*` | `Blocks/52_trajectory_incidence/` |

## 飞书

- 工作计划编号：**B08**
- Batch 单元：MIMIC / eICU 并行
