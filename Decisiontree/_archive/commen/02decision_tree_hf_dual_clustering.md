# HF 双库无监督 LCA 流水线分析决策树（已定稿）

- **归档名**: `02decision_tree_hf_dual_clustering`
- **配置**: `configs/config_hf_dual_clustering.R` + `run_hf_dual_clustering.R`
- **实现**: 双库分库跑通同一 `pipeline$blocks`；LCA 用 `config$lca$candidate_vars` 固定聚类变量集；`cox_subphenotype` / `logistic_subphenotype` 输出 Table 2 四模型；`ref_class = NULL` 时按粗事件率自动选最低风险亚型为参照

## 研究问题

| 项 | 设定 |
|----|------|
| 人群 | 心力衰竭（Heart Failure） |
| 研究类型 | `prognosis`（无监督亚型 + 预后验证） |
| 暴露 | LCA 亚型 `Subphenotype`（k=2，两库一致） |
| 结局（28 天） | `survival_28d` + `survival_time_28d` → Cox / KM |
| 结局（院内） | 统一映射列 `in-hospital mortality`（eICU 源=`hospdischargestatus`，MIMIC 源=`is_hosp_dead`）→ Logistic / 柱图 |
| 数据 eICU | `data_cc/eicu/D02_Original_AKD.RData` → `data_imp`，ID=`subject_id` |
| 数据 MIMIC | `data_cc/mimic/D01_baseline_MIMIC.RData` → `data_imp`，ID=`subject_id` |
| 双库 | `TRUE`（`--db eicu\|mimic\|both`） |
| 镜像产出 | `mirror_pub_outputs_to_root = TRUE` |
| 聚类变量 | 两库完全相同 6 个：`Weight, BUN, CalciumTotal, Potassium, HR, SBP`（双库穷举扫描，Crude Cox+Logistic 均显著） |
| 聚类排除 | `Age, Height, BMI, Creatinine, Chloride, DBP`（留作 Cox/Logistic 协变量） |
| 聚类强制 | `SBP` 或 `MAP` 至少其一入模（`required_any_of`） |
| 固定 k | `optimal_k = 2`（不再自动选 k） |
| Cox/Logistic 四模型 | Crude；Model2=`Age`；Model3=`Age+BMI`；Model4=`Age+BMI+BUN+HR+Temperature` |
| 单因素筛选 | `screening_cutoff = 0.1` |
| 多因素筛选 | `sig_cutoff = 0.05` |
| VIF | 严格阈值 `<4`（screen + final） |
| 列缺失 | `data_clean` 剔除缺失 **>30%**；插补前再剔除缺失 **>20%** 的列 |
| 检查点 | `checkpoints_hf_dual/{eicu\|mimic}/` |

## 流程图

```mermaid
flowchart TD
  A[双库 HF 队列] --> A1[eICU: D02 / data_imp]
  A --> A2[MIMIC: D01 / data_imp]

  A1 --> PRE1[data_clean 0.3 → mapping → imputation]
  A2 --> PRE2[data_clean 0.3 → mapping → imputation]

  PRE1 --> H0[闸门⓪ common_vars 连续变量交集]
  PRE2 --> H0

  H0 --> PRE3[baseline → UV p<0.1 → VIF屏 → 多因素 p<0.05 → VIF终]
  PRE3 --> COR[correlation |r|<0.5]

  COR --> H1[闸门① candidate_vars 与 common_vars 完全一致]
  H1 --> LCA[lca: VIF<4 + |r|<0.5，≥6 变量，固定 k=2]
  LCA --> H2{闸门② 两库 k 一致?}
  H2 -->|否| KFIX[统一 optimal_k 后重跑 LCA]
  KFIX --> H2
  H2 -->|是| VIZ[subtype_viz → chord_diagram]

  VIZ --> H3[闸门③ Cox/Logistic 协变量一致且 ≠ 聚类变量]
  H3 --> T2[cox_binary → cox_subphenotype Table 2a]
  H3 --> T2B[logistic_subphenotype Table 2b]

  T2 --> FIG[plot_histogram 院内死亡柱图]
  T2B --> FIG
  FIG --> KM[km_strata 28 天 KM]
  KM --> UCT[unsupervised_clustering_table]

  UCT -.->|未纳入 pipeline| SENS[subgroup + 敏感性 A/B 待扩展]
```

## pipeline$blocks（声明顺序）

1. `data_clean` → `column_mapping` → `imputation`
2. `baseline_binary`（仅 `common_vars`）
3. `univariate_prognosis`（p<0.1）→ `multicollinearity_screen`（VIF<4）
4. `multivariate_prognosis`（p<0.05）→ `multicollinearity_final`（VIF<4）
5. `correlation`（\|r\|<0.5，供 LCA 前参考）
6. `lca` → `subtype_viz` → `chord_diagram`
7. `cox_binary`（亚型多水平 Cox 汇总）
8. `cox_subphenotype`（Table 2a：28 天 Cox 四模型）
9. `logistic_subphenotype`（Table 2b：院内 Logistic 四模型）
10. `plot_histogram` → `km_strata`（Fig.5A/B 类产出）
11. `unsupervised_clustering_table`

**未纳入当前 pipeline**：`logistic_binary_glm`（随机搜索易崩溃）；`subgroup_unsupervised_clustering` 及敏感性分析（决策树中虚线标注，待后续 block）。

## 双库闸门（run 脚本 + config）

| 闸门 | 位置 | 规则 |
|------|------|------|
| ⓪ | 插补后 | 取 eICU/MIMIC 映射后连续变量交集 → `common_vars`；**Table 1、单因素、多因素、VIF 屏/终、相关热图** 均用同一 `prognosis_include_vars` / `include_predictors` |
| ① | LCA 前 | `config$lca$candidate_vars` 必须在两库 `common_vars` 中**全部存在**，否则 `stop`；两库使用**完全相同**的变量列表与顺序 |
| ② | LCA 后 | `dual_db$harmonization$require_same_k = TRUE`；当前配置固定 `optimal_k = 2` |
| ③ | 预后验证前 | `require_same_covariates = TRUE`；Model4 协变量不得与聚类变量重叠 |
| ④ | 亚型编号 | `align_subtype_semantics = TRUE`；`ref_class = NULL` → 各库按粗事件率最低亚型为参照 |

## 主要产出

| Block | 产出 |
|-------|------|
| `imputation` | Table S1（插补前后基线） |
| `baseline_binary` | Table 1 |
| `lca` | 共识矩阵、VIF/相关报告、`Subphenotype` 列 |
| `cox_subphenotype` | `Table_Cox_Subphenotype_MultiModel.csv` → Table 2a |
| `logistic_subphenotype` | `Table_Logistic_Subphenotype_MultiModel.csv` → Table 2b |
| `plot_histogram` | 院内死亡柱图（Fig.5A 类） |
| `km_strata` | 28 天 KM（Fig.5B 类） |

## 续跑与分库

```bash
Rscript run_hf_dual_clustering.R --db both
Rscript run_hf_dual_clustering.R --db eicu --from multicollinearity_final
Rscript run_hf_dual_clustering.R --db mimic --to logistic_subphenotype
```

`--from <block>` 表示从该 block **之后**继续；检查点目录为 `checkpoints_hf_dual/{eicu|mimic}/`。
