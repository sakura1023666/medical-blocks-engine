# Task 1 Report: 列审阅 + 键与结局核对

**Status**: DONE  
**Date**: 2026-08-26  
**Worker**: Task 1 subagent  
**Commits**: none (skipped per plan)

---

## 1. 执行摘要

已完成 SLE→AKI 两阶段套路的 baseline 列审阅、键字段核对与 dabiao 交叉验证。Windows Rscript 审计脚本按 brief verbatim 执行，生成 `_column_review_raw.txt` 与 `_key_audit.txt`；按 `review-raw-covariate-columns` SKILL 写出 `_column_review.md`（104 列全覆盖 + dabiao 额外 2 列说明 + `disease_vars` 候选名单）。

---

## 2. 审计命令与产物

### 2.1 Rscript 审计（brief Step 1）

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" -e '...'
```

**输出**: `wrote audits`（exit 0）

### 2.2 产物路径（均已存在）

| 文件 | 路径 | 状态 |
|------|------|------|
| 原始列名 | `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_column_review_raw.txt` | ✅ 104 行 |
| 键审计 | `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_key_audit.txt` | ✅ |
| 列审阅 | `G:/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_column_review.md` | ✅ |

WSL 等价路径：`/mnt/g/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/`

---

## 3. 键字段结论

### 3.1 脚本输出（`_key_audit.txt`）

```
baseline nrow= 65366
SLE nrow= 271  ARF nrow= 15536
baseline has ID= TRUE
SLE cols= subject_id,stay_id,hadm_id
prog cols= subject_id,stay_id,hadm_id,admit_time,icu_intime,...
SLE in baseline by ID= 271
ARF in baseline by ID= 15536
```

### 3.2 扩展核对（补充 R 审计）

| 检查项 | 结果 |
|--------|------|
| baseline `ID` 唯一性 | 65366 行，65366 唯一，无重复 |
| SLE `subject_id` / `stay_id` 唯一性 | 271 行，均无重复 |
| SLE ↔ baseline | 271/271 `subject_id ∈ baseline$ID` |
| ARF ↔ baseline | 15536/15536 |
| SLE ↔ ARF 交集 | 110 例（SLE 队列中 AKI 阳性） |
| 预后表 n | 65366 = baseline n；65366 唯一 `subject_id` |
| SLE ↔ 预后 | 271/271 `subject_id` 与 `stay_id` 均可并 |
| `ID` 类型 | integer；与 SLE `subject_id` 数值一致 |

**结论**：

- **主并键**：`baseline$ID` ↔ `SLE.csv$subject_id` ↔ `ARF.csv$subject_id` ↔ `mimic预后数据-all.csv$subject_id`
- **ICU 层键**：`stay_id` / `hadm_id` 三表齐全，预后并表可用 `stay_id`
- baseline **无** `subject_id` 列名，仅有 `ID`（实现 `ip_cohort_sle_aki` 时需显式映射）

---

## 4. dabiao 交叉核对

**文件**：`data/mimic/D04_dabiao(1).RData`（brief 未列入脚本，按 global constraints「dabiao 仅核对」补查）

| 项 | 值 |
|----|-----|
| dabiao n | 271（= SLE.csv） |
| ID 与 SLE 双向包含 | 100% 一一对应 |
| 较 baseline 多列 | `DN`（numeric 0/1）、`Diabetes`（factor） |
| `Acute_Renal_Failure` | No=161, Yes=110 |
| `DN` | 0=161, 1=110（与 ARF 结局一致） |
| `CKD` | Yes=44 |
| `CRRT` | Yes=26 |

**人数差异**：spec 要求「dabiao 271 vs 现场筛入以筛入为准」——当前 SLE.csv 与 dabiao 均为 271，无差异。

---

## 5. 列审阅摘要

### 5.1 规模

- baseline：**104 列**，均在 `_column_review.md` 逐行列出
- dabiao 额外 2 列（`DN`, `Diabetes`）单独说明

### 5.2 `disease_vars` 候选（14 项，供 Task 2 config）

```r
.disease_exclusion_vars <- c(
  "Acute_Renal_Failure", "CRRT", "CRRT_Day", "CKD",
  "Creatinine", "UreaNitrogen",
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  "UrineCreatinine", "UrineVolume",
  "SOFA", "CHARLSON", "DN"
)
```

### 5.3 分类统计

| 类别 | 列数 | 代表 |
|------|------|------|
| 排除（disease/outcome/ID） | 18 | ID, Acute_Renal_Failure, CKD, CRRT*, 尿检*, Creatinine, UreaNitrogen, SOFA, CHARLSON |
| 保留（协变量候选） | 87 | 人口学、生命体征、CBC、通用生化/血脂/肝酶/凝血、合并症诊断（除 CKD/ARF） |
| SLE 专属列 | 0 | 队列由 SLE.csv 外部定义 |

### 5.4 关键排除理由

- **结局泄漏**：`Acute_Renal_Failure`、`CRRT`/`CRRT_Day`、`DN`
- **AKI 病理标志物**：肌酐、BUN、尿检全套、尿量
- **纳排准则**：`CKD`（基线 ESRD/CKD 排除，不作协变量）
- **边界排除**：`SOFA`（含肾分项）、`CHARLSON`（含肾病权重）
- **保留澄清**：血清 `Albumin` ≠ `AlbuminUrine`；`T1DM`/`T2DM` 作合并症保留

---

## 6. 预后结局列（Stage2，不进协变量）

来自 `mimic预后数据-all.csv`：

- 死亡：`is_dead`, `dead_time`, `is_hosp_dead`, `is_icu_dead`
- 28 天：`death_within_hosp_28days`, `death_within_icu_28days`
- 生存时间：`hosp_survival_day`, `icu_survival_day`
- 时间戳/位置：`admit_time`, `icu_intime`, `disch_time`, `icu_outtime`, `admission_location`, `discharge_location`, `hosp_day`, `icu_day`

全库 28 天院内死亡 8583 例；ICU 28 天死亡 8838 例（Stage2 需按 spec 规则 C 构造 `futime`/`fustatus`）。

---

## 7. 下游 Task 接口

| 产出 | 消费方 |
|------|--------|
| `disease_vars` 候选 14 项 | Task 2 `config_sle_aki_inc_prog_batch.R` → `analysis_exclusion$disease_vars` |
| 键结论 `ID`= `subject_id` | Task 3 `ip_cohort_sle_aki` 合并逻辑 |
| AKI 110/271 | attrition / 发病率 sanity check |
| dabiao=271 | Figure 1 脚注交叉核对 |

---

## 8. Concerns / 待后续确认

1. **AKI 时间窗**：baseline `Acute_Renal_Failure` 为 ICU 期二分类，无精确 `aki_time`；Stage2 规则 C 回退 `icu_intime` 需在 config 脚注（spec §4.4 已预期）。
2. **SOFA / CHARLSON 边界排除**：已保守列入 `disease_vars`；若文献 force 集需 SOFA，Task 2 可讨论是否移出 disease_vars 改作分层/敏感性。
3. **dabiao `Diabetes` vs baseline `T1DM`/`T2DM`**：column_mapping 应映射到 T2DM/T1DM，勿双计。
4. **无 git commit**：按 global constraints 跳过。

---

## 9. 自检清单

- [x] brief Rscript 已运行，`wrote audits`
- [x] `_column_review_raw.txt` 存在（104 列）
- [x] `_key_audit.txt` 存在
- [x] `_column_review.md` 全列覆盖 + disease_vars 候选
- [x] SKILL 格式：`列名 | 保留/排除 | 理由`
- [x] 未 git commit
- [x] 本 report 已写入 `.superpowers/sdd/task-1-report.md`
