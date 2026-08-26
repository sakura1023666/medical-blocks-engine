# Cross-Lagged Hip × Frailty (三库+Pooled) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在髋部骨折交叉滞后研究中，按发病式横断面跑 CHARLS/ELSA/HRS，VIF 后 rbind 出 Pooled（必含 Country），再挂纵向中介与其它 C0* 块；先交付 prep + Table 1。

**Architecture:** Prep 产出三份基线 `dabiao`（含 `FI`/`Frailty`/`Disease_Group`）。一期用精简 `pipeline`（clean→map→impute→trim→baseline_binary）经 `run_incidence_single.R` 出 Table 1。二期扩展为三库 UV→VIF 后拼 Pooled 再四路 logistic/RCS。三期把用户纵向脚本 block 化进 `20_mediation/` 与 `54_cross_lagged_full/`，并重写决策树/config/run。

**Tech Stack:** R, `R/pipeline_runner.R`, `run/incidence/run_incidence_single.R`, `Blocks/04_baseline/01block_baseline_binary.R`, `mediation` 包（三期）, `jsonlite`

**Spec:** `docs/superpowers/specs/2026-07-30-cross-lagged-hip-frailty-design.md`

## Global Constraints

- 产出根：`/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747`（Windows：`G:/02block_result/16_Hip fracture/cross-laged_40595747`）
- 四「库」：CHARLS + ELSA + HRS + Pooled；Pooled = 插补后 `rbind` + `Country`（China/UK/America）
- Pooled **禁止**进入 `data_clean` … `multicollinearity_*_final`
- 暴露：连续 `FI`（已 0–1）；`Frailty = I(FI ≥ 0.25)`；**不用** `AIP_FI`
- Table 1：**只含连续 FI**（二分不进表）；FI 组间不显著 → 告警，不默认 stop
- 基线波：CHARLS 2011 / ELSA wave2 / HRS 2012
- 纵向中介：X 基线 FI → M 中间抑郁 → Y 更晚骨折
- 不新建 `Blocks/NN_*` 目录；中介进 `20_mediation/`；其它纵向进 `54_cross_lagged_full/`
- **除非用户明确要求 git commit，否则跳过所有 commit 步骤**

## File Structure

| 路径 | 职责 |
| ---- | ---- |
| `scripts/prep_cross_lagged_hip_frailty.R` | 三库 merge → harmonized `dabiao` + QC |
| `.../data/harmonized/D04_*_hip_baseline.RData` | 分析入口（obj=`dabiao`） |
| `.../data/harmonized/prep_qc.csv` | n、事件、FI 分布、组间 P |
| `.../config_phase1_CHARLS.R` 等 | 一期到 Table 1 的研究区 config（可后删或并入正式模板） |
| `configs/templates/config_cross_lagged_frailty_batch.template.R` | 二/三期正式模板 |
| `run/cross_lagged/run_cross_lagged_frailty_batch.R` | 三库+Pooled 编排 |
| `Decisiontree/decision_tree_cross_lagged_frailty.md` | 逐步决策树 |
| `Blocks/20_mediation/0Nblock_mediation_longitudinal.R` | 纵向中介 |
| `Blocks/54_cross_lagged_full/1Nblock_*.R` | 长表准备 / pooled_bind / 图网 |

---

### Task 1: Prep — 三库 baseline + FI + 结局

**Files:**
- Create: `scripts/prep_cross_lagged_hip_frailty.R`
- Create (runtime):  
  `/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/data/harmonized/D04_CHARLS_hip_baseline.RData`  
  `.../D04_ELSA_hip_baseline.RData`  
  `.../D04_HRS_hip_baseline.RData`  
  `.../prep_qc.csv`

**Interfaces:**
- Produces: 每个 RData 含 `dabiao`（data.frame），必含列  
  `ID`, `Disease_Group`（`"Hip_Fracture"` / `"No_Fracture"`）, `FI`（numeric 0–1）, `Frailty`（0/1 integer），以及基线协变量列
- Produces: `prep_qc.csv` 列  
  `cohort, n, n_event, fi_mean, fi_median, frailty_prev, fi_p_vs_outcome, note`

- [ ] **Step 1: 写 prep 脚本并跑通**

```r
#!/usr/bin/env Rscript
# scripts/prep_cross_lagged_hip_frailty.R
suppressPackageStartupMessages({
  library(dplyr)
})

study_root <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
if (!dir.exists(study_root))
  study_root <- "G:/02block_result/16_Hip fracture/cross-laged_40595747"
raw <- file.path(study_root, "data")
out <- file.path(raw, "harmonized")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

load_df <- function(path, obj = NULL) {
  e <- new.env(parent = emptyenv())
  load(path, envir = e)
  if (is.null(obj)) {
    nms <- ls(e)
    if (length(nms) != 1L) stop("期望单对象: ", path, " 有 ", paste(nms, collapse = ","))
    obj <- nms[[1L]]
  }
  as.data.frame(e[[obj]])
}

recode_outcome <- function(x) {
  ifelse(is.na(x), NA_character_,
         ifelse(as.character(x) %in% c("1", "Hip_Fracture"), "Hip_Fracture",
                ifelse(as.character(x) %in% c("0", "No_Fracture"), "No_Fracture", NA_character_)))
}

fi_p <- function(fi, y) {
  ok <- !is.na(fi) & !is.na(y)
  if (sum(ok) < 10L) return(NA_real_)
  tryCatch(wilcox.test(fi[ok] ~ factor(y[ok]))$p.value, error = function(e) NA_real_)
}

# --- CHARLS 2011 ---
bl <- load_df(file.path(raw, "CHARLS", "D01_baseline_CHARLS_2011_0729.RData"), "baseline")
bl$ID <- as.character(bl$ID)
fr <- read.csv(file.path(raw, "CHARLS", "虚弱_charls_2011.csv"), check.names = FALSE)
fr$ID <- as.character(fr$ID)
if (!"FI" %in% names(fr) && "frailty26_total" %in% names(fr))
  fr$FI <- fr$frailty26_total / 26
fr <- fr[, c("ID", "FI")]
outc <- load_df(file.path(raw, "CHARLS", "D03_result_CHARLS_2011.RData"))
names(outc)[names(outc) == setdiff(names(outc), "Disease_Group")[1]] <- "ID"
outc$ID <- as.character(outc$ID)
outc$Disease_Group <- recode_outcome(outc$Disease_Group)
dabiao <- bl %>%
  inner_join(fr, by = "ID") %>%
  inner_join(outc[, c("ID", "Disease_Group")], by = "ID")
dabiao <- dabiao[!is.na(dabiao$FI) & !is.na(dabiao$Disease_Group), ]
dabiao$Frailty <- as.integer(dabiao$FI >= 0.25)
save(dabiao, file = file.path(out, "D04_CHARLS_hip_baseline.RData"))

# ELSA / HRS：同逻辑；ELSA 虚弱 ID 列 idauniq→ID；HRS hhidpn→ID
# 虚弱文件：虚弱_elsa_wave2.csv；虚弱_hrs_2012.csv
# 结局：D03_result_ELSA2.RData；D03_result_HRS12.RData

# 写 prep_qc.csv（三库 rbind）
```

实现时把 ELSA/HRS 对称写全；QC 对每库算 `fi_p_vs_outcome`，若 P≥0.05 在 `note` 写 `FI_NS_WARN`。

- [ ] **Step 2: 运行 prep**

Run:
```bash
cd /mnt/e/01block/01Block-new-Final && Rscript scripts/prep_cross_lagged_hip_frailty.R
```
Expected: 三份 RData + `prep_qc.csv`；`FI` 在 [0,1]；`Disease_Group` 仅两水平。

- [ ] **Step 3: 快速校验**

```bash
Rscript -e '
load("/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/data/harmonized/D04_CHARLS_hip_baseline.RData")
stopifnot(all(c("ID","FI","Frailty","Disease_Group") %in% names(dabiao)))
stopifnot(max(dabiao$FI, na.rm=TRUE) <= 1.0001)
print(table(dabiao$Disease_Group))
print(read.csv("/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/data/harmonized/prep_qc.csv"))
'
```
Expected: 无 stop；QC 打印三行。

---

### Task 2: 一期 config — 三库跑到 Table 1

**Files:**
- Create:  
  `/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/config_phase1_CHARLS.R`  
  `.../config_phase1_ELSA.R`  
  `.../config_phase1_HRS.R`  
  （也可一个文件用函数生成三份；以研究区可直接 `--config` 为准）

**Interfaces:**
- Consumes: Task 1 的 `dabiao` RData
- Produces: `config`, `pipeline`；`pipeline$blocks` 仅到 `baseline_binary`
- `project$analysis_group = "Hip_Fracture"`，`reference_group = "No_Fracture"`
- `incidence$index_var = "FI"`，`logistic$index_var = "FI"`
- `index$enable = FALSE`（FI 已在表中，跳过公式计算）
- `baseline_binary$include_vars` 含 `"FI"`（及其它拟入表协变量）；**不含** `"Frailty"`
- `baseline_binary$pause_enable = FALSE`（一期避免人工 pause 卡住）

- [ ] **Step 1: 写 CHARLS 一期 config（ELSA/HRS 改 path/name 即可）**

```r
# config_phase1_CHARLS.R — 放到研究产出根
.study_root <- "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747"
.config_dir <- .study_root

config <- list(
  data = list(
    rawdata_path = file.path(.study_root, "data/harmonized/D04_CHARLS_hip_baseline.RData"),
    rawdata_obj  = "dabiao",
    outcome_column = "Disease_Group",
    id_column = "ID",
    strip_id_columns_after_imputation = c("ID")
  ),
  project = list(
    name = "Hip_Frailty_CHARLS_phase1",
    disease_code = "16",
    disease = "Hip_fracture",
    literature_pmid = "40595747",
    database = "CHARLS",
    database_type = "regular",
    study_type = "incidence",
    classification_mode = "binary",
    analysis_group = "Hip_Fracture",
    reference_group = "No_Fracture",
    output_dir = file.path(.study_root, "phase1_CHARLS"),
    use_step_prefixed_block_dirs = TRUE,
    block_steps_prefix = "step",
    mirror_pub_outputs_to_root = TRUE
  ),
  incidence = list(outcome_var = "Disease_Group", index_var = "FI"),
  logistic  = list(index_var = "FI"),
  prediction = list(index_vars = "FI", keep_index_vars_in_regression_table = TRUE),
  data_clean = list(missing_threshold = 0.3, age_filter = NULL, drop_columns = NULL),
  column_mapping = list(enable = TRUE, database_type = "CHARLS"),
  index = list(enable = FALSE),
  imputation = list(
    missing_col_threshold = 0.2, method = "cart", m = 5L, max_iter = 5L,
    seed = 1234L, complete_action = 1L, export_missing_fig = TRUE, export_table_s1 = TRUE
  ),
  trim_index_extreme = list(enable = TRUE, index_var = "FI", lower_q = 0.01, upper_q = 0.99),
  baseline_binary = list(
    sig_cutoff = 0.05,
    strata = "Disease_Group",
    include_vars = NULL,  # NULL=全候选；实现时确保 FI 在表中且 Frailty 进 exclude
    exclude_vars = c("Frailty"),
    pause_enable = FALSE,
    pause_on_table1_fail = FALSE,
    pause_on_min_sig_vars = FALSE
  )
)

pipeline <- list(
  name = "cross_lagged_phase1_table1",
  blocks = c(
    "data_clean", "column_mapping",
    "imputation", "trim_index_extreme",
    "baseline_binary"
  ),
  logistic_gate = list(enable = FALSE),
  checkpoint = list(
    enable = TRUE,
    dir = file.path(.study_root, "phase1_CHARLS", "checkpoints")
  ),
  render_tables_after = c("imputation", "baseline_binary"),
  render_figures_after = character(0)
)
```

注意：从 `configs/templates/config_incidence_single.template.R` 补齐 runner 所需的其余默认段（`plot`、`splitting` 等），避免缺键；**不要**把 logistic/RCS 块放进一期 `pipeline$blocks`。

- [ ] **Step 2: 跑 CHARLS 到 Table 1**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript run/incidence/run_incidence_single.R \
  --config "/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/config_phase1_CHARLS.R"
```
Expected: `phase1_CHARLS/` 下出现 Table 1 xlsx/tex；日志无 fatal。

- [ ] **Step 3: 同样跑 ELSA、HRS**

Expected: 三库均有 Table 1；表中有 `FI` 行与组间 P；无 `Frailty` 行。

- [ ] **Step 4: 核对 FI 显著性**

读取三库 Table 1 或 `prep_qc.csv` 的 `fi_p_vs_outcome`；若某库 NS，在研究区写 `phase1_FI_significance_notes.md` 一行告警（不 stop）。

---

### Task 3: 决策树重写（发病前半 + Pooled 分叉 + 纵向尾）

**Files:**
- Modify: `Decisiontree/decision_tree_cross_lagged_frailty.md`

**Interfaces:**
- Produces: 与最终 `pipeline` block 名一致的逐步 mermaid + 表（含 Pooled 禁止进入的块列表）

- [ ] **Step 1: 按 spec §2 重写全文**

必须写明：

1. 共享/单库：`data_clean` → … → `multicollinearity_final`（仅 CHARLS/ELSA/HRS）  
2. `cross_lagged_pooled_bind`：rbind + Country  
3. 四路：`logistic_*_glm` → RCS → 亚组  
4. 纵向：`cross_lagged_long_prepare` → 图/网 → `mediation_longitudinal`  
5. 本套路 **不调用** `cross_lagged_mediation` / `mediation_incidence`

- [ ] **Step 2: 人工对照** `Decisiontree/decision_tree_incidence_dual_batch.md` 与归档 `03decision_tree_incidence_single.md` 的闸门列索引，保证 logistic_gate 描述一致。

---

### Task 4: Pooled bind 块 + 二期 config/run 骨架

**Files:**
- Create: `Blocks/54_cross_lagged_full/13block_cross_lagged_pooled_bind.R`
- Modify: `configs/templates/config_cross_lagged_frailty_batch.template.R`
- Modify: `run/cross_lagged/run_cross_lagged_frailty_batch.R`

**Interfaces:**
- Consumes: 三库 checkpoint 中 `ctx$data$imputed` 与 `ctx$results$Model2Factors`
- Produces: Pooled `imputed`；`Model1Factors`/`Model2Factors` 强制含 `Country`；`Country` 因子水平 `China/UK/America`

- [ ] **Step 1: 实现 `block_cross_lagged_pooled_bind`**

```r
# Blocks/54_cross_lagged_full/13block_cross_lagged_pooled_bind.R
# register_block("cross_lagged_pooled_bind", ...)
# 从 config$cross_lagged_pooled_bind$sources 读三库 imputed 路径或 ctx$results$cohort_imputed_list
# 每库 mutate(Country = ...)；取列交集；rbind
# Model2 <- union(intersect_clinical, "Country")
```

文件头注释含 `require_data` / `require_ctx_results`；禁止再跑 UV/VIF。

- [ ] **Step 2: 模板 pipeline 分段**

- `pipeline_unit_pre_vif`: 到 `multicollinearity_final`（units 不含 Pooled）  
- 然后 run 调 `cross_lagged_pooled_bind`  
- `pipeline_unit_post`: logistic…RCS…（units 含 Pooled）

- [ ] **Step 3: 烟雾跑** 一库到 VIF final → bind → Pooled `baseline` 或 logistic 一步（可选，时间不够可延后到二期完整跑）。

---

### Task 5: 纵向中介块（审查 C04/C05/相关 table3）

**Files:**
- Create: `Blocks/20_mediation/06block_mediation_longitudinal.R`  
  （若已有 05，用下一序号；以目录现有最大号 +1）
- Create: `Blocks/20_mediation/07block_mediation_longitudinal_diagram.R`（若图与拟合宜拆分；否则合并进 06）
- Review in place: 根目录 `C04发病-中介.R`、`C05_中介图.R`、`C01相关性分析-table3.R`（逻辑修正；重复删除）

**Interfaces:**
- Consumes: `ctx$data$longitudinal_mediation` 或 `imputed` 宽表，含 `FI`, `Depression_cont`, `Disease_Group`/`outcome`, `Model2Factors`
- Produces: Table 中介效应；`ctx$results$mediation_longitudinal`；路径图文件
- Config 键：`mediation_longitudinal = list(treat="FI", mediator="Depression_cont", outcome=..., sims=1000, cohorts=...)`

- [ ] **Step 1: 读三份用户脚本，列出重复与错误**（硬编码路径、`AIP_FI`、肌少症名、非纵向 merge）写入块内注释 `CHANGELOG` 段。

- [ ] **Step 2: 实现纵向 mediate**

```r
# med: Depression_cont ~ FI + covariates
# out: Disease_Group ~ Depression_cont + FI + covariates  (binomial)
# mediation::mediate(..., treat="FI", mediator="Depression_cont")
```

时序数据由 `cross_lagged_long_prepare` 预先按 spec §3.4 拼好。

- [ ] **Step 3: 用 CHARLS 小样本烟雾**（`sims=50`）确认出表无报错。

---

### Task 6: 纵向 prepare + 其余 C0* 块

**Files:**
- Create: `Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R`
- Create/Replace as needed:  
  `15block_cross_lagged_corr_table.R` ← `C01相关性分析-table3` 中相关部分（若未并入中介）  
  `16block_cross_lagged_forest_or.R` ← `C01_ForestPlot - nolevel-OR.R`  
  `17block_cross_lagged_network.R` ← `C01_network_analysis.R`  
  `18block_cross_lagged_country_year_bar.R` ← 保留 `C01.Country_Year_barplot_new.R`，删除旧 `...barplot.R` 重复逻辑  
  `19block_cross_lagged_fig1_group.R` ← `C02_Fig1_year_or_country_group.R`  
  `20block_cross_lagged_change_logistic.R` ← `C02.1_Change_Logistic.R`

**Interfaces:**
- `long_prepare` 读 `config$cross_lagged_long_prepare$waves`（每库 X/M/Y 路径）；写 `ctx$data$longitudinal` / `longitudinal_mediation`
- 各图块只读约定槽位；暴露/结局名从 config 读 `FI` / 骨折，禁止写死 `AIP_FI`/`Sarcopenia`

- [ ] **Step 1: long_prepare**（含 `medition/` 抑郁列映射）  
- [ ] **Step 2: 逐个移植图块，删重复 barplot 旧版逻辑**  
- [ ] **Step 3: 更新 batch template `pipeline` 尾部顺序** 与决策树一致  

---

### Task 7: 端到端验收

- [ ] **Step 1: 一期验收清单**

| 检查项 | 期望 |
| ---- | ---- |
| 三份 harmonized | 存在且 `dabiao` 含 FI |
| 三份 Table 1 | 含 FI，不含 Frailty |
| prep_qc | 有 fi_p；NS 有 WARN |

- [ ] **Step 2: 二期验收** Pooled 检查点不出现在 VIF 前；Pooled Model 含 `Country`  
- [ ] **Step 3: 三期验收** 纵向中介表 + 图；主暴露为 `FI`

---

## Spec coverage (self-review)

| Spec 要求 | Task |
| ---- | ---- |
| Prep 三库 + FI/Frailty/结局 | T1 |
| 一期到 Table 1，仅连续 FI | T2 |
| 决策树重写 | T3 |
| Pooled rbind + Country，VIF 后 | T4 |
| 纵向中介进 20_mediation | T5 |
| C0* → 54_*，去重改逻辑 | T6 |
| 分期成功标准 | T7 |
| 不用 AIP_FI / 不新建 Blocks 目录 | Global + T5/T6 |

无 TBD；commit 步骤全局跳过（除非用户要求）。
