# 骨质疏松 DXA/QCT 双核画像 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `personalized` 队列上落地「核 A 椎体骨折危险因素 + 核 B DXA/QCT 适用场景」全套分析：复用发病单库 Block，新建 3 个诊断/一致性/不一致画像 Block，产出主文 Table1–4 / Figure1–6 与补充表图。

**Architecture:** CSV→列名标准化 RData → 单库 `config_incidence_single` 扛核 A；核 B 挂三个新 `register_block` + 已有 `cart_decision_path`；核 A 骨密度两套 Model 用同一 dabiao 两次 `index_var`（QCT_vBMD / DXA_T_min）再合并 Table2 Panel。

**Tech Stack:** R, `pROC`, `irr` 或自写 κ, `ggplot2`, `rpart`（`cart_decision_path`）, 现有 `Blocks/04–13/18/22`, `run/incidence/run_incidence_single.R`

**Spec:** `docs/superpowers/specs/2026-09-22-osteoporosis-dxa-qct-personalized-design.md`  
**Decisiontree:** `Decisiontree/decision_tree_osteoporosis_dxa_qct_personalized.md`

## Global Constraints

- 研究根：`/mnt/g/02block_result/10_osteoporosis/personalized`（UNC `\\192.168.68.133\02block_result\10_osteoporosis\personalized`）
- 引擎根：`/mnt/e/01block/01Block-new-Final`
- N=208；源 CSV 无缺失；**无 Sex 列**（Methods 披露）
- 金标准：`Vertebral_fracture`；CART 结局默认：`need_QCT = (QCT_cat==2 & DXA_cat_min!=2)`
- 主分层：Nathan 1–2 vs 3–4；AAC；BMI&lt;24 / ≥24；Age 仅补充
- 核 A 锁变量：`Age+BMI+骨密度轴+bCTX+P1NP+VitD_25OH+PTH`（VIF 时 P1NP/bCTX 二选一）
- **除非用户明确要求 git commit，否则跳过所有 commit 步骤**
- **用户未说「可以跑/开跑」前，禁止 full pipeline；允许 prep、单测、`--dry-run`、单 Block 冒烟**

## File Structure

| 路径 | 职责 |
| ---- | ---- |
| `scripts/prep_osteo_dxa_qct_personalized.R` | CSV→`dabiao` RData + 派生列 + attrition CSV |
| `{STUDY}/data/harmonized/D01_osteo_personalized.RData` | 分析用 `dabiao` |
| `{STUDY}/data/_column_review.md` | 列审阅（无 disease 泄漏进协变量） |
| `{STUDY}/config_osteo_fracture_qct.R` | 核 A：index=`QCT_vBMD` |
| `{STUDY}/config_osteo_fracture_dxa.R` | 核 A Panel B：index=`DXA_T_min`（共享前段 checkpoint 或短跑 MV） |
| `Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R` | **新建** κ/交叉/Bland |
| `Blocks/75_osteo_dxa_qct/02block_diagnostic_vs_fracture.R` | **新建** 金标准诊断+分层 |
| `Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R` | **新建** 不一致四分类画像 |
| `Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R` | 共享：读列名、OP 二分类、分层因子 |
| `tests/test_osteo_dxa_qct_blocks.R` | 三块纯函数/冒烟单测 |
| `{STUDY}/scripts/merge_table2_dual_bmd_panels.R` | 合并 QCT/DXA 两套 MV → Table2 |
| `docs/Blocks_catalog.md` | `update_blocks_catalog.py` 同步 |

---

### Task 1: Prep — CSV → dabiao + 派生列

**Files:**
- Create: `scripts/prep_osteo_dxa_qct_personalized.R`
- Create: `{STUDY}/data/harmonized/D01_osteo_personalized.RData`
- Create: `{STUDY}/data/harmonized/attrition_prep.csv`
- Create: `{STUDY}/data/harmonized/column_map.csv`

**Interfaces:**
- Consumes: `{STUDY}/data/研究数据_完整版(数据整理)(1).csv`（GBK）
- Produces: `dabiao` data.frame，n=208，必含列：
  - `SampleID` (chr), `Age`, `BMI` (num)
  - `QCT_vBMD`, `QCT_cat` (0/1/2 int), `DXA_T_min`, `DXA_cat_min`, `DXA_T_lumbar`, `DXA_cat_lumbar`
  - `Vertebral_fracture` (0/1), 显示用 factor 可选 `Fracture_f`
  - `Nathan` (1–4), `Nathan_bin` (`"1-2"`/`"3-4"`), `AAC` (0/1), `BMI_bin` (`"<24"`/`">=24"`), `Age_bin` (`"<65"`/`">=65"`)
  - `QCT_OP`, `DXA_OP` (0/1), `discordance_group` (`Both_OP`/`QCT_only_OP`/`DXA_only_OP`/`Neither_OP`)
  - `need_QCT` (0/1) = QCT_only_OP
  - 代谢/骨代谢原列（短名见下 Step 2）
- Produces: attrition 至少一步 `raw_csv → analytic_n=208`

- [ ] **Step 1: 写 prep 读入与编码**

```r
# scripts/prep_osteo_dxa_qct_personalized.R
STUDY <- Sys.getenv(
  "OSTEO_PERSONALIZED_ROOT",
  unset = "/mnt/g/02block_result/10_osteoporosis/personalized"
)
raw <- file.path(STUDY, "data", "研究数据_完整版(数据整理)(1).csv")
stopifnot(file.exists(raw))
df <- utils::read.csv(raw, fileEncoding = "GBK", check.names = FALSE, stringsAsFactors = FALSE)
stopifnot(nrow(df) == 208L)
```

- [ ] **Step 2: 列重命名表（写入 column_map.csv 并 apply）**

标准名 ← 源列（精确匹配源 CSV 表头）：

| 标准名 | 源列关键字/全名 |
| ---- | ---- |
| SampleID | SampleID |
| Age | Age |
| QCT_vBMD | QCT-vBMD(mg/cm3) |
| QCT_cat | QCT category |
| DXA_T_min | DXA T-score腰椎或髋部取最低 |
| DXA_cat_min | DXA category腰椎或髋部取最低 |
| DXA_T_lumbar | 腰椎DXA T-score |
| DXA_cat_lumbar | 腰椎DXA category |
| Vertebral_fracture | Vertebral compression fracture |
| SBP, DBP, FPG, BMI, TG, CHO, HDL_C, LDL_C, Hb, Ca, P, UA, CCr | 对应中英列 |
| VitD_25OH, P1NP, bCTX, PTH, ALP, Calcitonin, Osteocalcin | 对应列 |
| Nathan | Nathan Osteophyte Grading |
| AAC | abdominal aortic calcification |

- [ ] **Step 3: 派生列与断言**

```r
dabiao$QCT_OP <- as.integer(dabiao$QCT_cat == 2L)
dabiao$DXA_OP <- as.integer(dabiao$DXA_cat_min == 2L)
dabiao$need_QCT <- as.integer(dabiao$QCT_OP == 1L & dabiao$DXA_OP == 0L)
dabiao$discordance_group <- ifelse(
  dabiao$QCT_OP == 1L & dabiao$DXA_OP == 1L, "Both_OP",
  ifelse(dabiao$QCT_OP == 1L & dabiao$DXA_OP == 0L, "QCT_only_OP",
  ifelse(dabiao$QCT_OP == 0L & dabiao$DXA_OP == 1L, "DXA_only_OP", "Neither_OP")))
dabiao$Nathan_bin <- ifelse(dabiao$Nathan %in% c(3L, 4L), "3-4", "1-2")
dabiao$BMI_bin <- ifelse(dabiao$BMI >= 24, ">=24", "<24")
dabiao$Age_bin <- ifelse(dabiao$Age >= 65, ">=65", "<65")
# 发病套路结局显示名
dabiao$Disease <- factor(
  ifelse(dabiao$Vertebral_fracture == 1L, "Fracture", "No_Fracture"),
  levels = c("No_Fracture", "Fracture")
)
stopifnot(sum(dabiao$need_QCT) == 40L)
stopifnot(sum(dabiao$Vertebral_fracture) == 85L)
out_dir <- file.path(STUDY, "data", "harmonized")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
save(dabiao, file = file.path(out_dir, "D01_osteo_personalized.RData"))
```

- [ ] **Step 4: 跑 prep 并核对**

Run: `Rscript scripts/prep_osteo_dxa_qct_personalized.R`  
Expected: 写出 RData；控制台打印 `n=208, fracture=85, need_QCT=40`。

---

### Task 2: 列审阅 `_column_review.md`

**Files:**
- Create: `{STUDY}/data/_column_review.md`

**Interfaces:**
- Produces: `disease_vars` 建议名单（结局与诊断泄漏）；协变量可进 UV/MV 名单
- Note: 本课题暴露是骨密度连续值，不是复合指标公式；`analysis_exclusion$disease_vars` 至少含 `Vertebral_fracture`, `Disease`, `QCT_cat`, `DXA_cat_*`, `discordance_group`, `need_QCT`, `QCT_OP`, `DXA_OP`（分类结局/标签不进协变量池）

- [ ] **Step 1: 按 `skills/review-raw-covariate-columns/SKILL.md` 写 md**

列出每列：用途（暴露/结局/协变量/分层/ID/排除）+ 是否进 Table1。

- [ ] **Step 2: 固化 config 将用的 `analysis_exclusion$disease_vars` 向量进 md 末尾代码块**

```r
disease_vars <- c(
  "Vertebral_fracture", "Disease",
  "QCT_cat", "DXA_cat_min", "DXA_cat_lumbar",
  "QCT_OP", "DXA_OP", "need_QCT", "discordance_group"
)
```

---

### Task 3: 公共 helper `00osteo_dxa_qct_common.R`

**Files:**
- Create: `Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R`
- Test: `tests/test_osteo_dxa_qct_blocks.R`（先写 helper 测）

**Interfaces:**
- Produces:
  - `.osteo75_pick_col(data, candidates)` → character(1)
  - `.osteo75_cohen_kappa(x, y)` → list(kappa=, n=)
  - `.osteo75_make_strata(data, cfg)` → named list of logical/factor vectors for Nathan/AAC/BMI/Age
  - `.osteo75_diag_metrics(truth01, pred01)` → data.frame(sens, spec, ppv, npv, n, n_pos)
  - `.osteo75_auc_continuous(truth01, score)` → list(auc=, ci_lo=, ci_hi=) via pROC

- [ ] **Step 1: 写失败单测（κ 已知表）**

```r
# tests/test_osteo_dxa_qct_blocks.R
source("Blocks/75_osteo_dxa_qct/00osteo_dxa_qct_common.R")
x <- c(1,1,1,0,0,0)
y <- c(1,1,0,0,0,1)
k <- .osteo75_cohen_kappa(x, y)
stopifnot(is.finite(k$kappa), k$n == 6L)
m <- .osteo75_diag_metrics(c(1,1,1,0,0), c(1,1,0,0,0))
stopifnot(abs(m$sens - 2/3) < 1e-8, abs(m$spec - 1) < 1e-8)
cat("helper OK\n")
```

- [ ] **Step 2: 实现 helper 使单测通过**

κ 用混淆矩阵公式（勿强依赖 `irr` 包；若已装可用并交叉校验）。

- [ ] **Step 3: Run**

`Rscript tests/test_osteo_dxa_qct_blocks.R`  
Expected: 打印 `helper OK`。

---

### Task 4: 新建 Block `dxa_qct_agreement`

**Files:**
- Create: `Blocks/75_osteo_dxa_qct/01block_dxa_qct_agreement.R`
- Modify: `tests/test_osteo_dxa_qct_blocks.R`

**Interfaces:**
- Consumes: `ctx$data$imputed %||% ctx$data$cleaned`；列 `QCT_cat`, `DXA_cat_min`, `QCT_vBMD`, `DXA_T_min`
- Config: `config$dxa_qct_agreement = list(enable=TRUE, qct_cat=, dxa_cat=, qct_continuous=, dxa_continuous=, op_level=2L, bland_zscore=TRUE)`
- Produces: Table「DXA-QCT agreement」xlsx；Figure「Figure 3. DXA vs QCT agreement」；`ctx$results$dxa_qct_agreement`
- register_block: `"dxa_qct_agreement"`

- [ ] **Step 1: 扩展单测 — 合成 data 上 κ 与 n**

```r
# stub register_block if needed
if (!exists("register_block", mode = "function"))
  register_block <- function(...) invisible(NULL)
# 构造 6 行 mini ctx 调用内部函数（导出 .dqa75_compute）
```

- [ ] **Step 2: 实现 block**

文件头注释按引擎规范；`block_dxa_qct_agreement <- function(ctx, ...) { ...; ctx }`；末尾 `register_block(...)`。

图：左面板 2×2 或三分类马赛克/热力交叉；右面板 Bland–Altman（`bland_zscore=TRUE` 时对 vBMD 与 T-score 分别 z 化后画差 vs 均）。

表：κ（二分类 OP）、三分类一致率、n。

- [ ] **Step 3: Run 单测**

Expected: PASS；无依赖完整 pipeline。

---

### Task 5: 新建 Block `diagnostic_vs_fracture`

**Files:**
- Create: `Blocks/75_osteo_dxa_qct/02block_diagnostic_vs_fracture.R`
- Modify: `tests/test_osteo_dxa_qct_blocks.R`

**Interfaces:**
- Consumes: `Vertebral_fracture`；`QCT_OP`/`DXA_OP` 或由 cat==`op_level` 派生；连续 `QCT_vBMD`, `DXA_T_min`
- Config: `config$diagnostic_vs_fracture = list(enable=TRUE, strata=c("Nathan_bin","AAC","BMI_bin"), strata_supplemental=c("Age_bin"), export_roc=TRUE, export_sens_bar=TRUE)`
- Produces: Table3 overall；Table4 stratified；Figure4 ROC（双曲线）；Figure5 分层 Sens；可选 Figure S3 Age；`ctx$results$diagnostic_vs_fracture`
- register_block: `"diagnostic_vs_fracture"`

- [ ] **Step 1: 单测 — 已知真值向量的 sens/AUC 有限**

```r
truth <- c(rep(1L, 10), rep(0L, 10))
score_good <- c(rnorm(10, 2), rnorm(10, 0))
auc <- .osteo75_auc_continuous(truth, score_good)
stopifnot(auc$auc > 0.5)
```

- [ ] **Step 2: 实现 block**

- 分类阳性：`cat == op_level`（默认 2）  
- ROC：`pROC::roc(fracture ~ score, direction = "<")` 对 vBMD（越低越病）与 T-score（越低越病）均 `direction="<"`  
- 分层行：每层 n、n_frac、DXA sens、QCT sens、Δsens  
- 脚注写清分母

- [ ] **Step 3: Run 单测 Expected PASS**

---

### Task 6: 新建 Block `modality_discordance_profile`

**Files:**
- Create: `Blocks/75_osteo_dxa_qct/03block_modality_discordance_profile.R`
- Modify: `tests/test_osteo_dxa_qct_blocks.R`

**Interfaces:**
- Consumes: `discordance_group` + 协变量列（复用 baseline 统计：连续 mean±SD / 分类 n(%)）
- Config: `config$modality_discordance_profile = list(enable=TRUE, group_var="discordance_group", exclude_vars=c("SampleID"))`
- Produces: Table S5 xlsx；`ctx$results$modality_discordance_profile`
- register_block: `"modality_discordance_profile"`

- [ ] **Step 1: 单测 — 四组水平齐全时 n 之和=208（用真实 dabiao 若存在）**

```r
load("/mnt/g/02block_result/10_osteoporosis/personalized/data/harmonized/D01_osteo_personalized.RData")
stopifnot(all(c("Both_OP","QCT_only_OP","DXA_only_OP","Neither_OP") %in% dabiao$discordance_group))
stopifnot(sum(dabiao$discordance_group == "QCT_only_OP") == 40L)
```

- [ ] **Step 2: 实现 block**

优先调用引擎已有 table1 工具函数（若可 `gtsummary` by=`discordance_group`）；否则手写汇总表。表注写：QCT_only 骨折例数。

- [ ] **Step 3: Run 单测 Expected PASS**

---

### Task 7: Catalog 同步

**Files:**
- Modify: `docs/Blocks_catalog.md`（AUTO 段）

- [ ] **Step 1: 确认三文件均 `register_block`**

- [ ] **Step 2: Run**

```bash
cd /mnt/e/01block/01Block-new-Final
python3 scripts/update_blocks_catalog.py
```

Expected: catalog 出现 `dxa_qct_agreement`, `diagnostic_vs_fracture`, `modality_discordance_profile`。

- [ ] **Step 3: `rg "dxa_qct_agreement" docs/Blocks_catalog.md` 有命中**

---

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

### Task 9: Table2 Panel 合并脚本

**Files:**
- Create: `{STUDY}/scripts/merge_table2_dual_bmd_panels.R`

**Interfaces:**
- Consumes: QCT / DXA 两次 multivariate 导出的 Table2 xlsx（或 `ctx` 落盘 csv）
- Produces: 单一 `Table 2. ...xlsx`，Panel A=QCT-vBMD，Panel B=DXA T-score；脚注两套 n 与变量锁

- [ ] **Step 1: 实现读写合并（优先 `openxlsx`/`pub_xlsx` 外科式；若尚无表则先 csv rbind + `export_sci_table`）**
- [ ] **Step 2: 冒烟用两张假 Panel csv 合并出文件**

---

### Task 10: 授权后开跑 + 四目录发表图

**Files:**
- Runtime under `{STUDY}/by_index/...`
- Modify: `Decisiontree/decision_tree_osteoporosis_dxa_qct_personalized.md` 状态表

**Gate:** 仅当用户明确「可以跑/开跑」后执行本 Task。

- [ ] **Step 1: 跑 QCT 主 config 全 pipeline**

```bash
Rscript run/incidence/run_incidence_single.R \
  --config /mnt/g/02block_result/10_osteoporosis/personalized/config_osteo_fracture_qct.R
```

- [ ] **Step 2: 跑 DXA config（核 A Panel B）**
- [ ] **Step 3: `merge_table2_dual_bmd_panels.R`**
- [ ] **Step 4: `pub_figure_ensure_formats` 对汇总 Figures**

```r
# 在引擎 R 中
source("R/pub_figure_export.R")
pub_figure_ensure_formats(file.path(Sys.getenv("OSTEO_PERSONALIZED_ROOT"), "summary_results", "Figures"))
```

- [ ] **Step 5: 验收对照 spec §8**

- Table1–4、Fig1–6 存在  
- Table3/4 与 Fig4/5 数字同源  
- κ 有限；QCT_only n=40  
- CART 叶标签中文  
- Figures 四目录；无根目录平铺 PDF  
- 更新 Decisiontree 落地状态为「已跑」

---

## Spec coverage（自审）

| Spec 要求 | Task |
| ---- | ---- |
| Prep / 无 Sex / need_QCT | T1 |
| 列审阅 / disease_vars | T2 |
| dxa_qct_agreement | T3–T4 |
| diagnostic_vs_fracture | T5 |
| modality_discordance_profile | T6 |
| catalog | T7 |
| 发病 pipeline + cart | T8 |
| Table2 双 Panel | T9 |
| 开跑 + 四目录 + 验收 | T10 |
| 方案1 主文精简 / Age 补充 | T5 strata_supplemental + T8 config |
| 不新建以外的 ML 竞品 | 未列入（YAGNI） |

## Placeholder scan

无 TBD/TODO；CART 结局与锁变量已写死；开跑门控在 T10。

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-22-osteoporosis-dxa-qct-personalized.md`.

两种执行方式：

1. **Subagent-Driven（推荐）** — 每 Task 新开子代理，Task 间复审  
2. **Inline Execution** — 本会话按 `executing-plans` 连续做，关键点暂停

选哪个？选 1 或 2 即可。（未说「开跑」前我只做到 T1–T9 的代码/单测，不动全量拟合。）
