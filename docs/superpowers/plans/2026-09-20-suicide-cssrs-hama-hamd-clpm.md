# 自杀门诊 CLPM（HAMD/HAMA/C-SSRS item1）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在门诊队列上跑 Index→1st 两波交叉滞后（HAMD/HAMA 连续 + C-SSRS item1 二分类），含协变量 UV/VIF 锁定、路径主表与精简发表槽位；病房仅 Exploratory。

**Architecture:** 做法 B。不调用 `run_cross_lagged_frailty.R --batch` 全套。Prep 产出单库 `dabiao` → 插补仅协变量 → UV/VIF 锁 Model2 → 9 条预注册路径（线性 + logistic）→ Fig1/Table1/主表/相关。引擎侧只登记 `kind=suicide_cssrs` 与薄脚本/决策树。

**Tech Stack:** R, `mice`, `glm`/`lm`, 现有 `Blocks/03_imputation` / UV / VIF 思路, `scripts/prep_cross_lagged_suicide_cssrs.R`, 研究区 config

**Spec:** `docs/superpowers/specs/2026-09-20-suicide-cssrs-hama-hamd-clpm-design.md`

## Global Constraints

- 产出根：`\\192.168.68.133\02block_result\43_Suicide\cross-laged_40595747`（WSL 经 PowerShell UNC 或挂载）
- 引擎根：`/mnt/e/01block/01Block-new-Final`
- 主队列：**仅门诊入组**；病房 = Exploratory
- 节点：`HAMD_Index/1st`, `HAMA_Index/1st`, `CSSRS_Index/1st`（item1 仅；Yes=1/No=0）
- **六节点任一缺失 → 删例；节点禁止 MICE**；仅协变量可插补
- 不做：三库 Pooled、FI 分位闸门、社区 S9–S17.1、CLPN 1000-boot 默认
- **除非用户明确要求 git commit，否则跳过所有 commit 步骤**
- **用户未说「可以跑/开跑」前，禁止跑全分析；可做 prep/脚本落地与 dry-run**

## File Structure

| 路径 | 职责 |
| ---- | ---- |
| `scripts/prep_cross_lagged_suicide_cssrs.R` | 合并 D01–D06 + 量表 Index/1st → harmonized dabiao + attrition + QC |
| 研究区 `data/harmonized/D04_outpatient_clpm.RData` | 主分析 `dabiao`（门诊、六节点完整） |
| 研究区 `data/harmonized/D04_ward_clpm.RData` | 病房 Exploratory（同规则） |
| 研究区 `data/_column_review.md` | 列审阅 → disease_vars / 协变量池 |
| 研究区 `config_suicide_clpm.R` | 单队列 config（插补排除节点） |
| `R/cross_lagged_study_meta.R` | 登记 `kind = "suicide_cssrs"` |
| `run/cross_lagged/run_suicide_clpm_paths.R` | 9 条路径估计 + 主表导出 |
| `run/cross_lagged/run_suicide_clpm_covariates.R` | UV→VIF→Model2 锁定 |
| `Decisiontree/decision_tree_cross_lagged_suicide_cssrs.md` | 逐步决策树 |
| 研究区 `03*/C01_MI_baseline.R` | 修 1st 文件指向（盘上 QC 脚本） |

---

### Task 1: 修 QC 脚本 1st 指向 + 确认源列名

**Files:**
- Modify (UNC): `...\data\RDATA\RDATA\03*\C01_MI_baseline.R`（1st 三处 load）
- Create: 引擎侧备份注释可写在 prep 头注释

**Interfaces:**
- Produces: 1st 从 `D10_C_SSRS2` / `D07_HAMA2` / `D08_HAMD2` 读取
- Produces: 文档化 Index CSSRS item1 实际列名（探测后写入 prep）

- [ ] **Step 1: 用 PowerShell 打开并定位错误赋值**

当前错误（约 L115–123）：

```r
C_SSRS2 <- load_one(file.path(raw_dir, "D10_C_SSRS1.RData"))  # 错
HAMA2   <- load_one(file.path(raw_dir, "D07_HAMA1.RData"))
HAMD2   <- load_one(file.path(raw_dir, "D08_HAMD1.RData"))
```

改为：

```r
C_SSRS2 <- load_one(file.path(raw_dir, "D10_C_SSRS2.RData"))
HAMA2   <- load_one(file.path(raw_dir, "D07_HAMA2.RData"))
HAMD2   <- load_one(file.path(raw_dir, "D08_HAMD2.RData"))
```

- [ ] **Step 2: 探测 Index/1st 对象列名**

```r
# 在 R 中 load 后：
grep("Ideation.*1$|_all$", names(C_SSRS1), value = TRUE)
grep("Ideation.*1$|_all$", names(C_SSRS2), value = TRUE)
grep("_all$", names(HAMA1), value = TRUE)
grep("_all$", names(HAMD1), value = TRUE)
```

Expected: Index 有 `C_SSRS_Ideation_index_1`（或等价）、`HAMA_intex_all`、`HAMD_index_all`；1st 有 `*_1st_*` 对应列。

- [ ] **Step 3: 断言 Index 与 1st 非同一文件**

```r
stopifnot(!identical(
  digest::digest(C_SSRS1), digest::digest(C_SSRS2)
))
```

Expected: 通过（修前应失败或 digest 相同）。

---

### Task 2: Prep — 门诊/病房 dabiao + 纳排表

**Files:**
- Create: `scripts/prep_cross_lagged_suicide_cssrs.R`
- Create (runtime):  
  `{STUDY}/data/harmonized/D04_outpatient_clpm.RData`  
  `{STUDY}/data/harmonized/D04_ward_clpm.RData`  
  `{STUDY}/data/harmonized/attrition_outpatient.csv`  
  `{STUDY}/data/harmonized/prep_qc.csv`

**Interfaces:**
- Consumes: `01RawData/D01_baseline.RData` + D02–D06 + D07/08/10 的 index/1st RData
- Produces: `dabiao` data.frame，必含：
  - `ID`（自 `新编号`）
  - `patient_group`（`门诊入组` / `病房入组`）
  - `HAMD_Index`, `HAMD_1st`, `HAMA_Index`, `HAMA_1st`（numeric）
  - `CSSRS_Index`, `CSSRS_1st`（integer 0/1）
  - 协变量候选列（人口学/病程/治疗/生活方式；原样合并后由列审阅裁）
- Produces: `attrition_*.csv` 列 `step, n_remain, n_excluded, rule`

- [ ] **Step 1: 写 prep 骨架（路径与 load_one）**

```r
# scripts/prep_cross_lagged_suicide_cssrs.R
STUDY <- Sys.getenv(
  "CROSS_LAGGED_STUDY_ROOT",
  unset = "/mnt/e/02block_result/43_Suicide/cross-laged_40595747"  # 或 UNC 挂载点
)
raw_dir <- file.path(STUDY, "data/RDATA/RDATA/01RawData")
out_dir <- file.path(STUDY, "data/harmonized")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

load_one <- function(path) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  get(ls(e)[1], envir = e)
}

cssrs_item1_01 <- function(x) {
  x <- trimws(as.character(x))
  ifelse(x %in% c("Yes ", "Yes", "A", "是", "1"), 1L,
         ifelse(x %in% c("No ", "No", "B", "否", "0"), 0L, NA_integer_))
}
```

- [ ] **Step 2: 合并基线 D01–D06，挂 Index/1st 节点**

```r
# 伪代码要点：
# baseline <- fix_id(load_one(D01), keep 患者类别)
# merge D02–D06 by 新编号
# join HAMD1/HAMA1/CSSRS1 → Index 总分 / item1
# join HAMD2/HAMA2/CSSRS2 → 1st（必须用 *2 文件）
# rename → HAMD_Index, HAMA_Index, CSSRS_Index, ...
dabiao$CSSRS_Index <- cssrs_item1_01(dabiao[[cssrs_index_col]])
dabiao$CSSRS_1st   <- cssrs_item1_01(dabiao[[cssrs_1st_col]])
```

- [ ] **Step 3: 按队列写纳排并落盘**

```r
node_cols <- c("HAMD_Index","HAMD_1st","HAMA_Index","HAMA_1st","CSSRS_Index","CSSRS_1st")
filter_cohort <- function(df, group_label) {
  steps <- list()
  d <- df
  steps[[1]] <- list(step = "has_ID", n = nrow(d))
  d <- d[d$patient_group == group_label, , drop = FALSE]
  steps[[2]] <- list(step = paste0("group_", group_label), n = nrow(d))
  ok <- stats::complete.cases(d[, node_cols, drop = FALSE])
  d <- d[ok, , drop = FALSE]
  steps[[3]] <- list(step = "six_nodes_complete", n = nrow(d))
  list(data = d, attrition = do.call(rbind, lapply(steps, as.data.frame)))
}
```

- [ ] **Step 4: Dry-run prep（用户确认开跑后或本阶段仅验证路径）**

```bash
export CROSS_LAGGED_STUDY_ROOT="（挂载后的课题根）"
Rscript scripts/prep_cross_lagged_suicide_cssrs.R
```

Expected: `prep_qc.csv` 中门诊 `n_nodes_complete` > 0；Index/1st HAMD 均值不同（粗检非同表）。

---

### Task 3: 列审阅 + analysis_exclusion

**Files:**
- Create: `{STUDY}/data/_column_review.md`
- Modify: 研究区 `config_suicide_clpm.R` 的 `analysis_exclusion$disease_vars`

**Interfaces:**
- Consumes: harmonized `dabiao` 列名
- Produces: `disease_vars`（诊断泄漏、自杀结局详述等）；协变量白名单进入 Table1/UV

- [ ] **Step 1: 按 `skills/review-raw-covariate-columns/SKILL.md` 扫列**

必排除出协变量池示例：随访自杀自伤详述、与 CSSRS 同义的结局叙述、诊断名若作泄漏。  
可保留：age/sex/education/marriage、病程、首发、用药大类、住院天数等。

- [ ] **Step 2: 写入 config**

```r
config$analysis_exclusion <- list(
  disease_vars = c(/* 审阅名单 */),
  exclude_exposure_if_uses_disease_var = TRUE
)
config$imputation$exclude_from_mice_cols <- c(
  "HAMD_Index", "HAMD_1st", "HAMA_Index", "HAMA_1st",
  "CSSRS_Index", "CSSRS_1st", "ID"
)
```

---

### Task 4: 研究区 config + study_meta + 决策树

**Files:**
- Create: `{STUDY}/config_suicide_clpm.R`
- Modify: `R/cross_lagged_study_meta.R`（增加 suicide 分支）
- Create: `Decisiontree/decision_tree_cross_lagged_suicide_cssrs.md`

**Interfaces:**
- Produces: `cross_lagged_study_meta(study_root)$kind == "suicide_cssrs"`
- Produces: `grouping = "binary"`（节点用；无 FI 分位主分析）

- [ ] **Step 1: meta 登记**

```r
# 在 cross_lagged_study_meta() 中，hip/dementia/circadian 之前或并列：
if (grepl("43_Suicide|suicide_cssrs|suicide_clpm", study_root, ignore.case = TRUE) ||
    file.exists(file.path(study_root, "config_suicide_clpm.R"))) {
  return(list(
    kind = "suicide_cssrs",
    disease = "suicide_ideation_cssrs",
    cohorts_xs = "outpatient",
    cohorts_long = "outpatient",
    index_var = "HAMD_Index",  # 仅占位；主分析不走分位闸门
    grouping = "binary",
    grouping_labels = c("0", "1"),
    labels = list(
      exposure_label = "Mood/anxiety symptoms",
      outcome_label = "C-SSRS item1 ideation"
    )
  ))
}
```

- [ ] **Step 2: 决策树写清阶段**

阶段：Prep → 纳排 Fig1 → 协变量插补 → Table1 → UV/VIF 锁 Model2 → 9 路径 → 相关 S2 → 病房 Exploratory → collect summary。

- [ ] **Step 3: config 指向 outpatient RData**

```r
config$data$rawdata_path <- file.path(.batch_project_root, "data/harmonized/D04_outpatient_clpm.RData")
config$data$rawdata_obj <- "dabiao"
config$data$id_column <- "ID"
config$project$study_type <- "cross_lagged_clpm"
```

---

### Task 5: 协变量筛选（UV → VIF → Model2）

**Files:**
- Create: `run/cross_lagged/run_suicide_clpm_covariates.R`
- Create (runtime): `{STUDY}/covariates/Model2Factors.txt`, `uv_table.csv`, `vif_screen.csv`

**Interfaces:**
- Consumes: 插补后 `dabiao`；候选协变量（不含六节点、不含 disease_vars）
- Produces: 字符向量 `Model2Factors`（写入 txt）；主路径全部使用同一向量

- [ ] **Step 1: 定义筛选结局（用于 UV）**

用 `CSSRS_1st` 作为筛选用二分类结局（与自杀风险节点一致），对候选协变量做单因素 logistic；p&lt;0.10 进 VIF；VIF&lt;4 保留。

```r
# 核心循环示意
fit_uv <- function(df, y, x) {
  f <- stats::as.formula(paste(y, "~", x))
  m <- stats::glm(f, data = df, family = binomial())
  sm <- summary(m)$coefficients
  # 返回该 x 的总体 LRT p 或首个非截距系数 p（分类用 drop1）
}
```

- [ ] **Step 2: 强制保留人口学**

```r
force_keep <- intersect(c("age", "sex", "Age", "Sex", "gender", "Gender"), names(df))
Model2Factors <- unique(c(force_keep, vif_pass))
```

- [ ] **Step 3: 落盘并在日志打印**

Expected: `Model2Factors.txt` 非空；节点列不在列表中。

---

### Task 6: 九条路径估计 + 主表

**Files:**
- Create: `run/cross_lagged/run_suicide_clpm_paths.R`
- Create (runtime): `{STUDY}/summary_result/table/Table2_CLPM_paths.csv`（及 xlsx 若走 export_sci_table）

**Interfaces:**
- Consumes: 插补数据 + `Model2Factors`
- Produces: 9 行路径表，列至少：  
  `path, model, estimate, ci_low, ci_high, p, n, effect_type`  
  （`effect_type` = `std_beta` | `OR`）

- [ ] **Step 1: 定义路径规格**

```r
paths <- list(
  list(name="HAMD_AR",   y="HAMD_1st",   x=c("HAMD_Index"),               type="lm"),
  list(name="HAMA_AR",   y="HAMA_1st",   x=c("HAMA_Index"),               type="lm"),
  list(name="CSSRS_AR",  y="CSSRS_1st",  x=c("CSSRS_Index"),              type="logit"),
  list(name="HAMD_to_CSSRS", y="CSSRS_1st", x=c("HAMD_Index","HAMA_Index","CSSRS_Index"), type="logit", focus="HAMD_Index"),
  list(name="HAMA_to_CSSRS", y="CSSRS_1st", x=c("HAMA_Index","HAMD_Index","CSSRS_Index"), type="logit", focus="HAMA_Index"),
  list(name="CSSRS_to_HAMD", y="HAMD_1st",  x=c("CSSRS_Index","HAMD_Index","HAMA_Index"), type="lm", focus="CSSRS_Index"),
  list(name="CSSRS_to_HAMA", y="HAMA_1st",  x=c("CSSRS_Index","HAMA_Index","HAMD_Index"), type="lm", focus="CSSRS_Index"),
  list(name="HAMD_to_HAMA",  y="HAMA_1st",  x=c("HAMD_Index","HAMA_Index"), type="lm", focus="HAMD_Index"),
  list(name="HAMA_to_HAMD",  y="HAMD_1st",  x=c("HAMA_Index","HAMD_Index"), type="lm", focus="HAMA_Index")
)
# 每个模型 rhs 再追加 Model2Factors
```

- [ ] **Step 2: 连续结局标准化 β**

```r
# 对 y 与 focus x 做 scale 后 lm；或报告 raw β 同时附 std β
# P 用原尺度 lm 的系数 P；CI 用 confint
```

- [ ] **Step 3: CSSRS 结局 logistic OR**

```r
m <- glm(CSSRS_1st ~ HAMD_Index + HAMA_Index + CSSRS_Index + ..., family = binomial(), data = df)
OR <- exp(coef(m)[focus])
ci <- exp(confint.default(m)[focus, ])
```

- [ ] **Step 4: 单元测试（引擎 tests）**

```r
# tests/test_suicide_clpm_paths_spec.R
# 断言 paths 长度 == 9；logit 路径 focus 列存在；节点不在 Model2 样例中
```

Run: `Rscript tests/test_suicide_clpm_paths_spec.R`  
Expected: 退出码 0。

---

### Task 7: Fig1 / Table1 / 相关 S2 / 路径 Fig2 / README

**Files:**
- Create: `run/cross_lagged/run_suicide_clpm_pub.R`（或拆小脚本）
- Create (runtime): `summary_result/figure|table|README_*`

**Interfaces:**
- Fig1：读 `attrition_outpatient.csv` 逐步 n  
- Table1：按 `CSSRS_Index` 分层或总体；不含节点插补说明脚注  
- S2：六节点 Spearman/Pearson 相关  
- Fig2：路径图（显著交叉滞后加粗）  
- README：门诊；item1；六节点完整；节点不 MICE

- [ ] **Step 1: 导出 attrition → Fig1 文本/流程图**
- [ ] **Step 2: Table1 + S1（插补前后协变量；节点列注明 excluded from MICE）**
- [ ] **Step 3: 相关矩阵 S2**
- [ ] **Step 4: 路径图 Fig2（可用 DiagrammeR / ggplot 边列表）**
- [ ] **Step 5: `pub_figure_ensure_formats` 若落 PDF（遵守四目录铁律）**

---

### Task 8: 病房 Exploratory + 汇总清单

**Files:**
- Reuse: paths/covariates 脚本加 `--cohort ward`
- Create: `summary_result/table/TableS3_ward_CLPM_paths.csv`
- Create: `summary_result/README.md`

- [ ] **Step 1: 对 `D04_ward_clpm.RData` 重跑 Task 5–6，表头加 `Exploratory`**
- [ ] **Step 2: README 写明主文 = 门诊；病房不合并主表**
- [ ] **Step 3: 验收对照 spec §8 打勾**

---

## Spec coverage (self-review)

| Spec 要求 | Task |
| ---- | ---- |
| 做法 B / 不套 frailty batch | Global + Task 4–6 |
| 门诊主 / 病房 Exploratory | Task 2, 8 |
| Index→1st；Baseline 不进节点 | Task 2 |
| C-SSRS item1 二分类 | Task 1–2, 6 |
| 六节点缺失删例、禁 MICE | Task 2–3, 5 |
| UV/VIF 锁协变量 | Task 5 |
| 9 条路径；logit OR / lm β | Task 6 |
| 精简发表槽位 | Task 7–8 |
| 修 1st 文件 bug | Task 1 |
| 列审阅 / disease_vars | Task 3 |
| 开跑门控 | Global Constraints |

Placeholder scan: 无 TBD；列名以 Task 1 探测结果写入 Task 2（实现时固化，禁止留「或等价」不落地）。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-20-suicide-cssrs-hama-hamd-clpm.md`.

**执行方式（确认计划后选一种）：**

1. **Subagent-Driven（推荐）** — 每 Task 新开子代理，任务间复查  
2. **Inline Execution** — 本会话按 executing-plans 连续做，设检查点  

**说明：** 当前只完成「实现计划」。真正跑 prep/分析前仍需你再说一声「可以跑」或「按计划执行」。

你更想用哪种执行方式？是否同时把本 plan 复制到 `\\192.168.68.133\02block_result\43_Suicide\`？
