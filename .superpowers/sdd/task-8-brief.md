### Task 8: 研究区双 config（QCT / DXA Panel）

**Files:**
- Create: `{STUDY}/config_osteo_fracture_qct.R`
- Create: `{STUDY}/config_osteo_fracture_dxa.R`

**Interfaces:**
- 自 `configs/templates/config_incidence_single.template.R` 复制裁剪
- 共同：`study_type="incidence"`, `outcome_column="Disease"`, `analysis_group="Fracture"`, `reference_group="No_Fracture"`, `id_column="SampleID"`
- `data$rawdata_path` → harmonized RData；`rawdata_obj="dabiao"`
- `output_dir`：QCT 主目录 `{STUDY}/by_index/QCT_vBMD`；DXA `{STUDY}/by_index/DXA_T_min`
- `incidence$index_var` / `logistic$index_var`：分别为 `QCT_vBMD` / `DXA_T_min`
- `analysis_exclusion$disease_vars`：Task2 名单
- `baseline_binary$strata`：由结局推断或显式 `Disease`
- `pause_enable=FALSE`（无人值守）
- `imputation`：可 `enable` 但 miss=0；或 config 注释跳过——若引擎无 skip 开关则跑空操作
- `multivariate_*`：`force` / `locked` 协变量 = spec 锁变量（不含另一骨密度轴）
- `cart_decision_path`：仅挂在 **QCT config** pipeline 末尾

```r
pipeline <- list(blocks = c(
  "data_clean", "column_mapping", "analysis_exclusion", "imputation",
  "baseline_binary", "boxplot", "correlation",
  "univariate_incidence_binary",
  "multicollinearity_screen",
  "multivariate_incidence_binary",
  "multivariate_covariate_resolve",
  "multicollinearity_final",
  "simple_ROC",
  "rcs_incidence",
  "subgroup_incidence",
  "dxa_qct_agreement",
  "diagnostic_vs_fracture",
  "modality_discordance_profile",
  "cart_decision_path",
  "attrition_flowchart"
))
```

DXA config：可去掉核 B 三块与 cart（避免重复），只跑到 multivariate / simple_ROC，供 Panel B。

```r
cart_decision_path = list(
  enable = TRUE,
  data_scope = "analysis",
  features = c("Nathan", "AAC", "BMI", "Age"),
  outcome = "need_QCT",
  maxdepth = 3L,
  minsplit = 15L,
  minbucket = 8L,
  leaf_labels = c("0" = "首选 DXA", "1" = "必须 QCT"),
  root_label = "Analytic cohort (n=208)",
  figure_title = "Figure 6. CART modality pathway"
)
```

- [ ] **Step 1: 写两个 config 文件**
- [ ] **Step 2: Dry-run 打印 blocks**

```bash
Rscript run/incidence/run_incidence_single.R \
  --config /mnt/g/02block_result/10_osteoporosis/personalized/config_osteo_fracture_qct.R \
  --dry-run
```

Expected: 列出含三个新 block + cart；无立刻全量拟合（若入口无 `--dry-run` 则改为只 source config 打印 `pipeline$blocks`）。

---

