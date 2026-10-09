# PE × 阿替普酶 IPW 双库 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `47_PE` 上复用 Jin/IPW 用药模型链，MIMIC+eICU 各出全套 Fig1–5/S1–S4 与 Table1/S1–S4，STEPP 横轴=`composite_risk`，根目录双栏拼图定稿。

**Architecture:** 预后地基 + IPW 后缀（路径 1）。每库独立 `shared → unit=main`；暴露块改为阿替普酶（处方∪输液）；`index` 关闭；VIF→`ipw_jin_composite_risk`→IPTW→KM/亚组/STEPP；收口 remirror 双栏拼图 + pub QC。不覆盖卒中旧 【success】。

**Tech Stack:** R Medical Blocks（`Blocks/69_ipw_*`、IPTW、STEPP）、`run/ipw_*` batch worker、对抗阅读 scripts、pub figure export。

**Spec:** `docs/superpowers/specs/2026-10-09-pe-alteplase-ipw-dual-db-design.md`

## Global Constraints

- 暴露 = 阿替普酶是/否（处方 OR 输液）；结局 = 28 天全因死亡。
- STEPP `index_var = "composite_risk"`；`plot_style = "jin_treatment"`；LP 不含暴露。
- 图键齐套：Fig1–5、S1–S4；表：Table1、S1–S4；分库表不硬拼宽表。
- 根 `Figures/` 仅双栏拼图（A MIMIC | B eICU）+ 四目录。
- 产出根：`/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/`（新建）。
- 数据：`/mnt/g/02block_result/47_PE/DATA/{MIMIC,EICU}/`。
- 文献：`adversarial_lit_reading/papers/用药模型三分.pdf`。
- Rscript：`"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`（Windows 路径用 `G:/02block_result/...`）。
- 未完成对抗阅读门控前禁止写项目 config / 开跑。
- 禁止覆盖 `11_ischemic stroke/Medication_regimen_model_42118193` 已成功产物。

---

## File map（将创建/修改）

| 路径 | 职责 |
|------|------|
| `adversarial_lit_reading/chunks/用药模型三分_*.md` | PDF 切块（若缺） |
| `adversarial_lit_reading/rounds|labels/*PE_alteplase*` 或复用 paper 名 | Q4/Q5/Q8（建议全 Q1–Q8） |
| `Decisiontree/decision_tree_ipw_pe_alteplase.md` | 分析决策树 |
| `47_PE/.../reports/exposure_definition_*.md` | 暴露列语义与 n |
| `47_PE/.../Data/_column_review.md` | 列审阅 / disease_vars |
| `Blocks/69_ipw_diabetes_stroke_full/10block_ipw_alteplase_exposure.R`（新）或泛化现有暴露块 | 阿替普酶暴露 + 28d 结局 |
| `R/pipeline_runner.R` | 注册新 block 名 |
| `configs/templates/config_ipw_pe_alteplase_dual_batch.template.R` | 模板 |
| `run/ipw_pe_alteplase/run_*_batch.R` + `_worker.R` | 双库 batch |
| `run/ipw_pe_alteplase/remirror_dual_panel_figures.R` | 双栏拼图 |
| 项目 config（结果盘）`config_ipw_pe_alteplase_MIMIC.R` / `_eICU.R` | 实例 |

---

### Task 1: 文献切块 + 对抗阅读（门控）

**Files:**
- Create/use: `adversarial_lit_reading/chunks/` for `用药模型三分`
- Create: `adversarial_lit_reading/rounds/A_*.md`, `B_*.md`, `labels/*_training.jsonl`
- Skill: `.cursor/skills/adversarial-lit-reading/SKILL.md`

**Interfaces:**
- Consumes: `adversarial_lit_reading/papers/用药模型三分.pdf`
- Produces: validated JSONL for at least Q4, Q5, Q8（用户要完整则 Q1–Q8）

- [ ] **Step 1: 确认/生成 chunks**

```bash
cd /mnt/e/01block/01Block-new-Final
ls adversarial_lit_reading/chunks/ | rg '用药模型三分' || \
  python3 adversarial_lit_reading/scripts/pdf_to_chunks.py \
    --pdf adversarial_lit_reading/papers/用药模型三分.pdf \
    --out-dir adversarial_lit_reading/chunks
```

Expected: 存在 `用药模型三分_*.md` chunk 文件。

- [ ] **Step 2: 按 skill 跑 Q4 → Q5 → Q8（建议续跑 Q1–Q3、Q6–Q7）**

对每个 QID：AI-A 建树 → `glm_call.py` 真实攻击 → 修正 → Judge JSONL → `validate_jsonl.py`。  
`glm_call` 非零退出必须停；禁止伪造 `B_*.md`。

- [ ] **Step 3: 门控自检**

```bash
python3 adversarial_lit_reading/scripts/validate_jsonl.py \
  --input adversarial_lit_reading/labels/<PAPER>_Q4_training.jsonl --fix-hints
# 对 Q5、Q8 各跑一次；全跑则 Q1–Q8
```

Expected: PASS（或按规定进 review_needed 并报告）。

- [ ] **Step 4: 向用户展示对抗摘要 + 地基判定**

一句话：地基 = **预后 + IPW**；暴露映射放疗→阿替普酶；OS→28d。等用户点头再开 Task 3 写 config。

---

### Task 2: 数据组装 + 暴露核对 + 列审阅

**Files:**
- Create: `/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/data/`
- Create: `.../reports/exposure_definition_2026-10-09.md`
- Create: `.../Data/_column_review.md`（或 `data/_column_review.md`）
- Skill: `.cursor/skills/review-raw-covariate-columns/SKILL.md`

**Interfaces:**
- Consumes: `DATA/MIMIC|EICU` 下 PE CSV、阿替普酶处方/输液、`D01_baseline_*.RData`、`*预后数据-all.csv`
- Produces: 每库分析宽表（含 ID、暴露候选列、预后时间/死亡、基线协变量）+ 暴露 n 报告 + `disease_vars` 草案

- [ ] **Step 1: 建产出目录**

```bash
mkdir -p "/mnt/g/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"/{data,reports,Data,logs}
```

- [ ] **Step 2: 暴露语义核对（人工+脚本）**

用 Linux `Rscript` 统计并写入报告：

```r
# 写入 reports/exposure_definition_2026-10-09.md 的数字须来自实算
# MIMIC: ymtmd / 输液列（确认是否真为 alteplase）
# eICU: gy / sy
# 规则: Alteplase = 1 if rx OR iv else 0
```

Expected 粗算量级（若偏离 >20% 须停并问用户）：MIMIC 并集约 400+/1621；eICU 并集约 100+/1721。

- [ ] **Step 3: 组装每库 dabiao/分析表**

- 以 PE 队列 ID 为骨架，左连阿替普酶处方+输液，衍生 `Alteplase`。  
- 合并预后 CSV：至少 `hosp_survival_day`（或 `hosp_day`）、`death_within_hosp_28days`（或等价）。  
- 合并/对齐 `D01_baseline_*` 临床列；落盘 `data/D01_analysis_MIMIC.RData`、`data/D01_analysis_eICU.RData`（对象名 `baseline`）。

- [ ] **Step 4: 列审阅**

按 `review-raw-covariate-columns` 产出 `_column_review.md` 与 `disease_vars`（PE 诊断泄漏、严重度评分是否进回归等按 skill 判定）。  
`protect_vars` 预留：`Alteplase`, `surv_time_28d`, `surv_event_28d`, `composite_risk`。

- [ ] **Step 5: 验收**

```r
stopifnot(mean(df$Alteplase %in% 0:1) == 1)
stopifnot(all(c("surv_time_28d","surv_event_28d") %in% names(df)) || 
          all(c("hosp_survival_day","death_within_hosp_28days") %in% names(df)))
```

---

### Task 3: 暴露 Block + 注册 + 决策树

**Files:**
- Create: `Blocks/69_ipw_diabetes_stroke_full/10block_ipw_alteplase_exposure.R`
- Modify: `R/pipeline_runner.R`（注册 `ipw_alteplase_exposure`）
- Create: `Decisiontree/decision_tree_ipw_pe_alteplase.md`
- Run: `python3 scripts/update_blocks_catalog.py`（若新增 register_block）

**Interfaces:**
- Consumes: `ctx$data$imputed`；`config$ipw_alteplase` list  
- Produces: columns `Alteplase`, `surv_time_28d`, `surv_event_28d`；替换流水线中原 `ipw_diabetes_exposure` 位

- [ ] **Step 1: 实现暴露块（逻辑）**

```r
# config$ipw_alteplase 示例
# list(
#   exposure_var = "Alteplase",
#   rx_flag_var = "ymtmd",      # 或预合并列 Alteplase_rx
#   iv_flag_var = "...",        # MIMIC/eICU 不同则在 data 层先统一成 Alteplase
#   prefer_precomputed = TRUE,  # 若宽表已有 Alteplase=0/1 则直接用
#   followup_days = 28L,
#   time_source = "hosp_survival_day",
#   event_source = "death_within_hosp_28days",
#   time_var = "surv_time_28d",
#   event_var = "surv_event_28d"
# )
# 28d 结局派生复制 01block_ipw_diabetes_exposure.R 中 pipeline_outcome_as_01 逻辑
```

优先在 Task 2 就把 `Alteplase` 写进宽表，本块 `prefer_precomputed=TRUE` 只校验+派生结局，避免双库列名分叉。

- [ ] **Step 2: `register_block("ipw_alteplase_exposure", ...)` + `pipeline_runner.R` 映射**

- [ ] **Step 3: 写 `Decisiontree/decision_tree_ipw_pe_alteplase.md`**

内容须引用对抗阅读 chosen 结论；流水线块列表与卒中定稿同构，仅暴露块名与库参数不同；注明双栏拼图收口。

- [ ] **Step 4: 更新 catalog**

```bash
python3 scripts/update_blocks_catalog.py
```

- [ ] **Step 5: 用户确认决策树**（聊天展示 mermaid）后方可 Task 4 写项目 config。

---

### Task 4: 模板 + 项目 config + runner

**Files:**
- Create: `configs/templates/config_ipw_pe_alteplase_dual_batch.template.R`
- Create: `run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R`
- Create: `run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch_worker.R`
- Create: `G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R`
- Create: `.../config_ipw_pe_alteplase_eICU.R`

**Interfaces:**
- Consumes: Task 2 宽表路径；Task 3 block 名  
- Produces: 可 `--shared-only` / `--only-unit main` 的两套 config

- [ ] **Step 1: 以卒中 `config_ipw_diabetes_stroke_batch.R` 为底复制模板**

必改字段：

```r
project$disease <- "pe_ipw_alteplase"
project$database <- "MIMIC"  # eICU 配置改为 "eICU"
# index$enable <- FALSE
# ipw_alteplase$...（不用 ipw_diabetes HbA1c）
# iptw_balance$exposure_var <- "Alteplase"
# exposure_level_labels <- list(`0`="No alteplase", `1`="Alteplase")
# stepp_prognosis$index_var <- "composite_risk"
# stepp_prognosis$by_group$stratum_var <- "Alteplase"
# analysis_exclusion$disease_vars <- <from column review>
# analysis_exclusion$allow_no_index <- TRUE
# subgroup age_cutoff <- 65L  # 注释依据
```

pipeline_unit blocks：把 `ipw_diabetes_exposure` 换成 `ipw_alteplase_exposure`，其余保持卒中定稿顺序。

- [ ] **Step 2: runner/worker 从 `run/ipw_diabetes_stroke/` 复制并改默认 config 路径与日志前缀**

- [ ] **Step 3: dry-run**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R \
  --config "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R" \
  --shared-only --dry-run
```

Expected: 打印 shared blocks，无缺文件报错。（若无 `--dry-run`，则 `source(config)` 能成功 `exists("pipeline_unit")`。）

---

### Task 5: MIMIC shared + unit 全链

**Files:**
- Write under: `.../Medication_regimen_model_alteplase_ipw/` checkpoints、`by_unit/【success】main`（或 `main_MIMIC`）

- [ ] **Step 1: shared**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R \
  --config "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R" \
  --shared-only --no-skip
```

- [ ] **Step 2: unit main**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ipw_pe_alteplase/run_ipw_pe_alteplase_batch.R \
  --config "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw/config_ipw_pe_alteplase_MIMIC.R" \
  --only-unit main --workers 1 --no-skip
```

- [ ] **Step 3: 清单验收（对照卒中键）**

```bash
SUCCESS=".../by_unit/【success】main"   # 以实际目录名为准
ls "$SUCCESS/Figures" | rg 'Figure (1|2|3|4|5|S1|S2|S3|S4)'
ls "$SUCCESS/Tables"  | rg 'Table (1|S1|S2|S3|S4)'
```

Expected: 角色齐全；Fig5 标题含 STEPP / composite risk；Table1 为 sIPTW 基线。

---

### Task 6: eICU shared + unit 全链

**Files:** 同 Task 5，换 eICU config / database。

- [ ] **Step 1–2:** 同 Task 5 命令，换 `config_ipw_pe_alteplase_eICU.R`。  
- [ ] **Step 3:** 同样图/表键验收。  
- [ ] **Step 4:** 若 STEPP/PS 因暴露稀缺失败：按 spec 下调 `window_size`/`step_size` 重跑 `stepp_prognosis`（及必要上游），**不删 Fig5 键**；脚注写入 image_information。

---

### Task 7: 双栏拼图 + 四目录

**Files:**
- Create: `run/ipw_pe_alteplase/remirror_dual_panel_figures.R`
- Write: 课题根 `Figures/pdf|png|tiff|image_information/`

**Interfaces:**
- Consumes: 两库 `by_unit/.../Figures/Figure *.pdf`
- Produces: 无库后缀的 `Figure 1.…pdf` … `Figure S4.…pdf` 双栏拼图

- [ ] **Step 1: 实现 remirror**

对 Fig1–5、S1–S4：读取 MIMIC/eICU 对应 PDF（或 PNG），`patchwork`/`cowplot`/`magick` 拼 A|B，标题去掉单库后缀；统一 xlim 策略写进脚本注释。  
Flowchart 若已有 `attrition_draw_dual_panel_pdf` 可优先复用该 API。

- [ ] **Step 2: 跑拼图**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/ipw_pe_alteplase/remirror_dual_panel_figures.R \
  --project "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
```

- [ ] **Step 3: 四目录**

```r
source("R/pub_figure_export.R")
pub_figure_ensure_formats(file.path(project_root, "Figures"), config = config)
st <- pub_figure_formats_status(file.path(project_root, "Figures"))
stopifnot(isTRUE(st$ok))
```

Expected: 根 `Figures/` 无平铺残留单库 `Figure*-MIMIC.pdf`；每张有 png+tiff+image_information；image_information 含「图面说明」「分析上下文」，无「标识/技术」段。

---

### Task 8: 发表质控

**Files:**
- Create: `.../reports/pub_qc_YYYY-MM-DD.md`
- Create: `.../reports/nature_statistics_qc_YYYY-MM-DD.md`
- Create: `.../reports/nature_figure_qc_YYYY-MM-DD.md`
- Skills: `pub-qc-after-project`, `nature-statistics`, `nature-figure`

- [ ] **Step 1:**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/pub/run_pub_qc_after_project.R \
  --project "G:/02block_result/47_PE/Medication_regimen_model_alteplase_ipw"
```

- [ ] **Step 2:** 按 skill 填实 Layer A–D；**修清全部 Nature P0** 后复检。  
- [ ] **Step 3:** 口头给出 PASS / WARN / FAIL；未清 P0 不得宣称完成。

---

## Spec coverage 自检

| Spec 要求 | Task |
|-----------|------|
| 对抗阅读门控 | T1 |
| 暴露∪处方/输液 + 28d | T2–T3 |
| 列审阅 / disease_vars | T2 |
| 路径 1 双库全链 | T5–T6 |
| STEPP composite_risk | T3–T4 config + 链内 stepp |
| 图/表键齐套 | T5–T6 验收 |
| 双栏拼图 + 四目录 | T7 |
| pub QC | T8 |
| 不覆盖卒中旧目录 | Global + 新产出根 |

## Placeholder scan

无 TBD；暴露优先预计算列；eICU 稀缺处理写在 T6 Step 4。
