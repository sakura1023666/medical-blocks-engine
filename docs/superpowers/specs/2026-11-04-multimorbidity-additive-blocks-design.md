# 多病叠加 Block 设计（Wang 2025 BMC Med 04298）

日期：2026-11-04  
入口：`run/multimorbidity/run_multimorbidity_additive.R`  
决策树：`Decisiontree/decision_tree_multimorbidity_additive.md`

## 目标

可配置双纵向暴露（A×B）→ 结局；默认文献：BMI/WHtR × 抑郁 → 认知 z。  
第二示例：Frailty × Depression → Sarcopenia（hrs 变量映射）。

## config$multimorbidity 字段

| 键 | 含义 | 默认 |
|----|------|------|
| `exposure_a_col` / `exposure_b_col` | 连续轨迹列（如 BMI、Depression_Score） | BMI / Depression_Score |
| `obesity_binary_col` / `depression_binary_col` | 二分暴露列名（写出） | Obesity / Depression |
| `obesity_indicator` | `BMI` \| `WHtR` \| `WWI` | BMI |
| `bmi_cutoff` | 肥胖切点（CHARLS 28；欧美 30） | 30 |
| `whtr_cutoff` | 腹型肥胖 | 0.6 |
| `depression_score_col` / `depression_cutoff` | 抑郁量表与切点 | Depression_Score / 3 |
| `bmi_col` / `wc_col` / `height_col` / `weight_col` | 人体测量 | BMI / WC / Height / Weight |
| `category_col` | 四分类列名 | Multimorbidity_cat |
| `wave_col` / `waves` / `baseline_wave` / `outcome_wave` | 波次 | Followup_wave |
| `id_col` | 个体 ID（可回退 data$id_column） | ID |
| `kml3d_k_candidates` / `kml3d_clusters` / `min_cluster_prop` | 聚类 | 2:6 / NULL=CH选 / 0.05 |
| `trajectory_cluster_col` | 轨迹组列 | trajectory_cluster |
| `cognition_raw_col` / `cognition_z_col` | 认知原始与 z | Cognition / Cognition_z |
| `cognition_zscore$enable` | 是否算 z | TRUE |
| `graphical_abstract` | 四栏文案 list | 见 template |

## config$multimorbidity_gee

| 键 | 含义 |
|----|------|
| `outcome_col` | 结局（默认 Cognition_z；肌少症可为 DN） |
| `family` | `gaussian` \| `binomial` |
| `time_col` | 随访时间/波次 |
| `covariates_m1` / `m2` / `m3` | 阶梯协变量 |
| `stratify_vars` | 亚组变量 |
| `ref_category` / `ref_trajectory` | 参照水平 |

## 正式 Fig vs 非正式

- 正式：Fig1 基线；Fig2 四分类 GEE；Fig3 轨迹均值；Fig4 轨迹 GEE；S=纳排/Sankey/经验转移/敏感性  
- 非正式：`Figures/graphical_abstract/` 仅研究过程四栏，不进 Figure N

## Block 注册名与文件

见决策树「落盘位置」表；均在 `pipeline_runner.R` 注册。
