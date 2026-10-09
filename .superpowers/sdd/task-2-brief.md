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

