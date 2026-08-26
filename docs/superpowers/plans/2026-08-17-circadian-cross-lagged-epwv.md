# Circadian × ePWV Cross-Lagged Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在昼夜节律课题中，以 **ePWV → DN** 跑 CHARLS/ELSA/NHANES 横断面（VIF 后三库 Pooled），并对 CHARLS/ELSA 做 **condition1–7** 纵向网络与 **ePWV→FI→DN** 中介。

**Architecture:** 复用 `run/cross_lagged/run_cross_lagged_frailty.R` 与 `54_cross_lagged_full` phases。Prep 产出三份 `dabiao`（含 `DN→Disease_Group`、昼夜条目、可选 FI）。网络块增加 `node_stems` 强制节点；long 阶段自动剔除 NHANES。

**Tech Stack:** R, `run/cross_lagged/run_cross_lagged_frailty.R`, `Blocks/00_index` (ePWV), `Blocks/54_cross_lagged_full/*`, `Blocks/20_mediation/*`, `glmnet`, `mediation`

**Spec:** `docs/superpowers/specs/2026-08-17-circadian-cross-lagged-epwv-design.md`

## Global Constraints

- 产出根：`/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747`
- 引擎根：`/mnt/e/01block/01Block-new-Final`
- 仅指标 **ePWV**；不做 PHR/HHR/UA_CrR
- 结局：`DN` → `Disease_Group`（`"Circadian_Disorder"` / `"No_Disorder"`）
- Pooled = CHARLS+ELSA+NHANES rbind + `Country`（China/UK/America）；**VIF final 前禁止 Pooled**
- NHANES **禁止**纵向 phase
- 纵向网络节点 **仅** `condition1`…`condition7`
- 中介：X=基线 ePWV，M=中间波 FI，Y=更晚波 DN
- 疾病硬排除：必须落盘 `_column_review.md` 并挂 `analysis_exclusion`
- **除非用户明确要求 git commit，否则跳过所有 commit 步骤**（本工作区可能无 git）

## File Structure

| 路径 | 职责 |
| ---- | ---- |
| `scripts/prep_cross_lagged_circadian.R` | 三库 merge → harmonized `dabiao` + QC |
| `.../data/frailty/` | 从髋部课题拷贝虚弱 CSV |
| `.../data/harmonized/D04_*_circadian_baseline.RData` | 分析入口 `dabiao` |
| `.../data/_column_review.md` | 列审阅 → disease_vars |
| `.../config_circadian_epwv.R` | 研究区主 config |
| `Blocks/54_cross_lagged_full/17block_cross_lagged_network.R` | 支持 `node_stems` |
| `Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R` | 携带 condition 列进宽表（若缺则改） |
| `run/cross_lagged/run_cross_lagged_frailty.R` | 最小改动：long units 剔除 NHANES |

---

### Task 1: Prep — 虚弱拷贝 + ID 对齐 + 三库 dabiao

**Files:**
- Create: `scripts/prep_cross_lagged_circadian.R`
- Create (runtime):  
  `/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/data/frailty/`（拷贝虚弱）  
  `.../data/harmonized/D04_CHARLS_circadian_baseline.RData`  
  `.../D04_ELSA_circadian_baseline.RData`  
  `.../D04_NHANES_circadian_baseline.RData`  
  `.../prep_qc.csv`  
  `.../id_align_report.csv`

**Interfaces:**
- Produces: 每个 RData 含 `dabiao`（data.frame），必含  
  `ID`, `Disease_Group`, `DN`, `met_count`, `condition1`…`condition7`,  
  `Age`, `Gender`, `SBP`, `DBP`（由 NBPS/NBPD 映射；若已有则保留）,  
  `FI`（可 NA；left join）, `Frailty`（FI 非 NA 时 `I(FI>=0.25)`）
- Produces: `prep_qc.csv` 列  
  `cohort, n, n_event, circ_merge_rate, fi_merge_rate, epwv_comp_complete_rate, note`
- CHARLS ID 函数（必须）：

```r
pad_charls_id <- function(x) {
  x <- as.character(trimws(x))
  ifelse(
    nchar(x) == 11L, paste0(substr(x, 1, 9), "0", substr(x, 10, 11)),
    ifelse(nchar(x) == 10L, paste0(substr(x, 1, 8), "0", substr(x, 9, 10)), x)
  )
}
```

（探测结果：该规则下 circ↔baseline ≈9141/10131；三路含 FI ≈6268。）

- [ ] **Step 1: 拷贝虚弱文件到课题 `data/frailty/`**

```bash
STUDY="/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747"
SRC="/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747/data"
mkdir -p "$STUDY/data/frailty"
cp -n "$SRC/CHARLS/虚弱_charls_2011.csv" "$STUDY/data/frailty/"
cp -n "$SRC/CHARLS/虚弱_charls_2015.csv" "$STUDY/data/frailty/"
cp -n "$SRC/ELSA/虚弱_elsa_wave4.csv" "$STUDY/data/frailty/"
cp -n "$SRC/ELSA/虚弱_elsa_wave5.csv" "$STUDY/data/frailty/" 2>/dev/null || true
cp -n "$SRC/ELSA/虚弱_elsa_wave6.csv" "$STUDY/data/frailty/"
ls -la "$STUDY/data/frailty"
```

Expected: 至少有 CHARLS 2011/2015、ELSA wave4/wave6；wave5 若无则中介改用最近可用中间波（记入 config）。

- [ ] **Step 2: 写并运行 prep 脚本**

在 `scripts/prep_cross_lagged_circadian.R` 实现要点：

```r
#!/usr/bin/env Rscript
suppressPackageStartupMessages({ library(dplyr) })

study_root <- "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747"
raw <- file.path(study_root, "data")
out <- file.path(raw, "harmonized")
dir.create(out, recursive = TRUE, showWarnings = FALSE)

pad_charls_id <- function(x) { ... }  # 同上
to_id <- function(x) as.character(as.vector(x))

recode_dn <- function(x) {
  ifelse(is.na(x), NA_character_,
         ifelse(as.character(x) %in% c("1"), "Circadian_Disorder",
                ifelse(as.character(x) %in% c("0"), "No_Disorder", NA_character_)))
}

map_bp <- function(df) {
  if (!"SBP" %in% names(df) && "NBPS" %in% names(df)) df$SBP <- df$NBPS
  if (!"DBP" %in% names(df) && "NBPD" %in% names(df)) df$DBP <- df$NBPD
  df
}

# CHARLS 2011:
#   bl <- load D01_baseline_CHARLS_2011_0813.RData (baseline)
#   circ <- 昼夜节律CHARLS_2011.csv；circ$ID <- pad_charls_id(circ$ID)
#   fr <- frailty/虚弱_charls_2011.csv；ID 保持 12 位字符
#   dabiao <- bl %>% inner_join(circ[ID, condition1:7, met_count, DN], by="ID")
#            %>% left_join(fr[ID, FI], by="ID")
#   Disease_Group <- recode_dn(DN); Frailty <- ifelse(!is.na(FI), as.integer(FI>=0.25), NA)
#   map_bp；硬停若 circ_merge_rate = n(inner circ)/n(circ) < 0.70
#   FI merge rate 仅告警写入 note（可 <0.70）

# ELSA wave4:
#   circ ID 列 idauniq→ID；与 baseline$ID 直接对齐（探测 8643/8643）
#   FI: 虚弱_elsa_wave4.csv idauniq→ID，left_join

# NHANES:
#   circ SEQN→ID；与 baseline$ID（探测 ≈全覆盖）
#   无 FI：FI/Frailty 全 NA；note=NO_FI_CROSS_SECTION_ONLY

# 写出三份 RData + prep_qc.csv + id_align_report.csv（各策略 overlap 备查）
```

Run:
```bash
cd /mnt/e/01block/01Block-new-Final && Rscript scripts/prep_cross_lagged_circadian.R
```
Expected: 三份 RData；CHARLS/ELSA `circ_merge_rate≥0.70`；NHANES 接近 1；无 silent 0 合并。

- [ ] **Step 3: 校验 dabiao**

```bash
Rscript -e '
root <- "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/data/harmonized"
need <- c("ID","Disease_Group","DN","met_count", paste0("condition",1:7),"Age","SBP","DBP")
for (f in c("D04_CHARLS_circadian_baseline.RData","D04_ELSA_circadian_baseline.RData","D04_NHANES_circadian_baseline.RData")) {
  e <- new.env(); load(file.path(root,f), e)
  d <- e$dabiao
  stopifnot(all(need %in% names(d)))
  stopifnot(identical(sort(unique(na.omit(d$Disease_Group))),
                      c("Circadian_Disorder","No_Disorder")))
  cat(f, "n=", nrow(d), "events=", sum(d$Disease_Group=="Circadian_Disorder"), "\n")
}
print(read.csv(file.path(root,"prep_qc.csv")))
'
```
Expected: 无 stop；QC 三行。

---

### Task 2: 列审阅 + analysis_exclusion

**Files:**
- Create: `/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/data/_column_review.md`
- Create: `.../data/_column_review_raw.txt`
- Modify (later in Task 3 config): `analysis_exclusion$disease_vars`

**Interfaces:**
- Produces: 全列 `保留/排除` 表
- Produces: `.disease_exclusion_vars` 至少含昼夜泄漏列：  
  `condition1`…`condition7`, `met_count`, `DN`  
  （以及审阅认定的昼夜定义组成原始问卷列，若仍留在 dabiao）
- 本课题结局是昼夜紊乱，**不是糖尿病课题**：不要照抄 HbA1c 糖尿病名单；仅排除与 DN 定义/昼夜条目直接泄漏的列。通用血压血脂可保留（ePWV 成分 Age/SBP/DBP/MBP 由 `analysis_exclusion` 成分闭包自动删）。

- [ ] **Step 1: 导出 CHARLS dabiao 全列名**

```bash
Rscript -e '
load("/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/data/harmonized/D04_CHARLS_circadian_baseline.RData")
writeLines(names(dabiao),
  "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/data/_column_review_raw.txt")
'
```

- [ ] **Step 2: 写 `_column_review.md`（逐列一行）并提炼 disease_vars**

模板行：`| 列名 | 保留/排除 | 理由 |`

必排除示例：`condition1–7`（结局组成）、`met_count`（同域评分）、`DN`（结局）、原始睡眠/代谢综合征定义问卷列（若与 DN 同定义且仍在表中）。

- [ ] **Step 3: 自检**

确认 `disease_vars` ∩ `{Age,Gender,Education,SBP,DBP,BMI,Smoke,Alcohol_drinking}` 为空（人口学/通用协变量不被误杀）。

---

### Task 3: 一期 config — 三库跑到 Table 1（含 index ePWV）

**Files:**
- Create:  
  `/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/config_phase1_CHARLS.R`  
  `.../config_phase1_ELSA.R`  
  `.../config_phase1_NHANES.R`  
  （或单文件 + unit override；对齐髋部 `config_phase1_*.R` 风格）

**Interfaces:**
- Consumes: Task 1 `dabiao`；Task 2 `disease_vars`
- Config 关键：

```r
project = list(
  name = "Circadian_ePWV_cross_lagged",
  disease_code = "23",
  disease = "Circadian_rhythm",
  literature_pmid = "40595747",
  database = "<UNIT>",
  study_type = "incidence",
  classification_mode = "binary",
  analysis_group = "Circadian_Disorder",
  reference_group = "No_Disorder",
  output_dir = file.path(study_root, "phase1_<UNIT>")
)
data = list(
  rawdata_path = file.path(study_root, "data/harmonized/D04_<UNIT>_circadian_baseline.RData"),
  rawdata_obj = "dabiao",
  outcome_column = "Disease_Group",
  id_column = "ID"
)
incidence = list(outcome_var = "Disease_Group", index_var = "ePWV")
logistic  = list(index_var = "ePWV")
index = list(enable = TRUE)   # 计算 ePWV（依赖 Age+MBP 链）
analysis_exclusion = list(
  disease_vars = .disease_exclusion_vars,
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
pipeline = list(
  name = "circadian_phase1",
  blocks = c(
    "data_clean", "column_mapping", "index", "analysis_exclusion",
    "imputation", "baseline_binary"
  )
)
```

- [ ] **Step 1: 从髋部 phase1 config 复制并按上表改路径/暴露/结局/exclusion**

- [ ] **Step 2: 跑三库一期**

```bash
cd /mnt/e/01block/01Block-new-Final
# 按仓库实际一期入口（run_incidence_single 或 cross_lagged phase）；优先：
Rscript run/cross_lagged/run_cross_lagged_frailty.R \
  --config "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/config_phase1_CHARLS.R"
# ELSA / NHANES 同理
```

若一期入口是 `run/incidence/run_incidence_single.R`，则用该入口 + 上述 config（与髋部一期一致）。

Expected: 各库 Table 1；`ePWV` 在表中；协变量无 `condition*`/`met_count`/`DN`。

- [ ] **Step 3: 抽查**

```bash
Rscript -e '
# 任选一份 Table1 csv/xlsx 路径打印列名，断言无 condition1 且含 ePWV
'
```

---

### Task 4: 二期 — UV→VIF→Pooled(三库)→logistic/RCS

**Files:**
- Create: `/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/config_circadian_epwv.R`  
  （自 `configs/templates/config_cross_lagged_frailty_batch.template.R`）
- Modify if needed: `Blocks/54_cross_lagged_full/phases/phase_vif_pooled.R`（Country map 含 NHANES）

**Interfaces:**
- `study_batch$units = c("CHARLS","ELSA","NHANES")`
- `cross_lagged_pooled_bind$country_map = list(CHARLS="China", ELSA="UK", NHANES="America")`
- `index_var = "ePWV"`；`outcome = Disease_Group`
- Pooled 仅在 `vif_pooled` phase 之后进入 `post_vif`

- [ ] **Step 1: 写研究区正式 config（batch 模板改名改路径）**

关键片段：

```r
.batch_project_root <- "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747"
study_batch = list(
  output_base = .batch_project_root,
  units = c("CHARLS", "ELSA", "NHANES"),
  unit_mode = "cohort",
  pooled_after_vif = TRUE,
  parallel_workers = "auto",
  skip_existing = TRUE
)
cross_lagged_pooled_bind = list(
  country_map = list(CHARLS = "China", ELSA = "UK", NHANES = "America"),
  force_country_in_model = TRUE,
  index_var = "ePWV",
  outcome_column = "Disease_Group",
  id_column = "ID"
)
incidence = list(outcome_var = "Disease_Group", index_var = "ePWV")
index = list(enable = TRUE)
# analysis_exclusion = Task2 名单
```

- [ ] **Step 2: 跑 pre_vif（三单库）→ vif_pooled → post_vif**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript run/cross_lagged/run_cross_lagged_frailty.R --batch \
  --config "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/config_circadian_epwv.R"
Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase vif_pooled \
  --study-root "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747"
Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase post_vif \
  --study-root "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747"
```

Expected: 四路（含 Pooled）logistic/RCS；Pooled Model 含 `Country`；检查点目录无 VIF 前的 Pooled。

- [ ] **Step 3: 验收**

确认 `phase2_Pooled`（或等价）存在；抽查 Model2 协变量无昼夜列、无 ePWV 成分（Age 若在 Model1 保留则按发病惯例；**成分排除以 analysis_exclusion 块行为为准**——Age 作为临床协变量可留，SBP/DBP/MBP 作为 ePWV 成分应被成分闭包从候选中删；若 Age 被误删，在 QC note 记录并按引擎既有 ePWV 行为处理，不私自改闭包语义）。

---

### Task 5: 网络块支持 `node_stems` + long_prepare 携带 condition

**Files:**
- Modify: `Blocks/54_cross_lagged_full/17block_cross_lagged_network.R`
- Modify: `Blocks/54_cross_lagged_full/14block_cross_lagged_long_prepare.R`（若宽表未带 condition）
- Modify: `Blocks/54_cross_lagged_full/phases/phase_long_figs.R`（传入 node_stems；units 跳过 NHANES）
- Test: `tests/test_cross_lagged_network_node_stems.R`（可选轻量）

**Interfaces:**
- Config:

```r
cross_lagged_network = list(
  node_stems = paste0("condition", 1:7),
  fi_items_only = FALSE,
  include_outcome = FALSE,
  include_lipids = FALSE,
  max_nodes = 7L
)
```

- [ ] **Step 1: 在 network 块开头强制节点**

在 stem 过滤逻辑最前（约现有 `stems <- intersect(...)` 之后）加入：

```r
force <- as.character(bl$node_stems %||% character(0))
force <- force[nzchar(force)]
if (length(force)) {
  missing_force <- setdiff(force, stems)
  if (length(missing_force))
    stop("cross_lagged_network: node_stems 缺失于宽表: ",
         paste(missing_force, collapse = ","), call. = FALSE)
  stems <- force
  cli::cli_alert_info("CLPN 使用强制 node_stems ({length(stems)})")
}
```

当 `length(force)>0` 时，跳过后续 `fi_items_only` 重组逻辑（直接进入缺失/变异过滤）。

- [ ] **Step 2: long_prepare 保证 T1_/T2_condition1…7 进入 `longitudinal_wide`**

若当前只拉 FI 条目：增加 config 键 `carry_vars = paste0("condition",1:7)`，从各波 circadian/基线合并进长表再 pivot。

- [ ] **Step 3: phase long 仅 CHARLS,ELSA**

在 `phase_long_figs.R` / `phase_long_mediation` 入口：

```r
units <- setdiff(units, "NHANES")
```

- [ ] **Step 4: 冒烟**（可用玩具宽表 30 行）

```r
# 构造 T1_condition1..7 / T2_condition1..7，调用 block，断言 adj 为 7x7
```

Expected: 7 节点邻接矩阵；无 FI 条目名。

---

### Task 6: 三期 — 纵向中介 ePWV→FI→DN +（可选）血检 pilot

**Files:**
- Modify: 研究区 `config_circadian_epwv.R` 的 `mediation_longitudinal` / `cross_lagged_long_prepare$waves`
- Reuse: `Blocks/20_mediation/06block_mediation_longitudinal.R`（或现用纵向中介块）
- Optional: 复制改名 `pilots/pilot_blood4_mediators.R` → circadian 版（仅 FI 失败后）

**Interfaces:**
- Waves:

```r
cross_lagged_long_prepare = list(
  carry_vars = paste0("condition", 1:7),
  waves = list(
    CHARLS = list(
      x_year = 2011L, m_year = 2013L, y_year = 2015L,
      # M=FI：优先 2013 虚弱；若无文件则用 2015 FI 作 M 并在 note 声明时序弱化，或跳过
      frailty_m = "虚弱_charls_2015.csv",  # 若无 2013：实现时探测 frailty/ 目录
      y_circadian_csv = "charls/昼夜节律CHARLS_2015.csv"
    ),
    ELSA = list(
      x_wave = 4L, m_wave = 5L, y_wave = 6L,
      # 若无 wave5 虚弱：m_wave=6 且跳过中介或改用 wave4→wave6 两波敏感分析
      frailty_m = "虚弱_elsa_wave6.csv",
      y_circadian_csv = "elsa/昼夜节律ELSA_wave6.csv"
    )
  )
)
mediation_longitudinal = list(
  treat = "ePWV",
  mediator = "FI",
  outcome = "Disease_Group",
  outcome_event_level = "Circadian_Disorder",
  sims = 1000L,
  seed = 40595747L
)
```

- [ ] **Step 1: 探测 frailty 中间波文件；写入最终 waves（无则文档化 fallback）**

```bash
ls "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747/data/frailty"
```

- [ ] **Step 2: 跑 long_figs（网络）+ long_mediation**

```bash
Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase long_figs \
  --study-root "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747"
Rscript run/cross_lagged/run_cross_lagged_frailty.R --phase long_mediation \
  --study-root "/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747" \
  --sims 200
```

Expected: CHARLS/ELSA 有 condition1–7 网络产物；中介表 `treat=ePWV`；无 NHANES long 目录。

- [ ] **Step 3: 若 FI 中介 ACME 不显著/不收敛** → 再跑血检 pilot（不挡主流程）

---

### Task 7: 规格状态更新

**Files:**
- Modify: `docs/superpowers/specs/2026-08-17-circadian-cross-lagged-epwv-design.md`  
  将状态改为 `已确认并进入实现`；FI 合并阈值改为：circ-baseline 硬停 0.70；FI left-join 告警。

- [ ] **Step 1: 更新 spec 状态与 ID 规则（写入 `pad_charls_id`）**

---

## Spec coverage (self-review)

| Spec 要求 | Task |
| ---- | ---- |
| 仅 ePWV | 全局 + Task 3/4 |
| DN 结局 / Disease_Group 映射 | Task 1 |
| 三库 + Pooled 含 NHANES | Task 4 |
| NHANES 无纵向 | Task 5/6 |
| 网络仅 condition1–7 | Task 5 |
| 中介 ePWV→FI→DN | Task 6 |
| 列审阅 / analysis_exclusion | Task 2 |
| PHR/HHR/UA_CrR 不做 | 全局（无任务） |
| CHARLS ID 对齐硬停 | Task 1 |

## Placeholder scan

无 TBD；中间波 FI 文件缺失时的 fallback 已写明探测步骤。

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-17-circadian-cross-lagged-epwv.md`.

**Two execution options:**

1. **Subagent-Driven（推荐）** — 每任务新开子代理，任务间审查  
2. **Inline Execution** — 本会话按 executing-plans 连续执行并设检查点  

选哪种？
