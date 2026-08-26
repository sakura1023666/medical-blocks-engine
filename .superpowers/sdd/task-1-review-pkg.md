# Task 1 Review Package (no-git)

## Files
-rw-r--r-- 1 root root 7881 Aug 26 11:14 /mnt/g/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_column_review.md
-rwxrwxrwx 1 root root 1002 Aug 26 11:14 /mnt/g/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_column_review_raw.txt
-rwxrwxrwx 1 root root  446 Aug 26 11:02 /mnt/g/02block_result/29_SLE/inincidence_prognosis_39003396_42304330/data/_key_audit.txt

## _key_audit.txt
baseline nrow= 65366 
SLE nrow= 271  ARF nrow= 15536 
baseline has ID= TRUE 
SLE cols= subject_id,stay_id,hadm_id 
prog cols= subject_id,stay_id,hadm_id,admit_time,icu_intime,disch_time,icu_outtime,admission_location,discharge_location,hosp_day,icu_day,is_dead,dead_time,is_hosp_dead,is_icu_dead,hosp_survival_day,icu_survival_day,death_within_hosp_28days,death_within_icu_28days 
SLE in baseline by ID= 271 
ARF in baseline by ID= 15536 

## _column_review.md (first 80 lines)
# 列审阅 — SLE → AKI 发病+28天预后（MIMIC baseline）

**审阅日期**：2026-08-26  
**数据源**：`data/mimic/D01_baseline_MIMIC_ICU_frist_0626 (1).RData` → `baseline`（n=65366，104 列）  
**交叉核对**：`D04_dabiao(1).RData`（n=271，=SLE.csv）；`ARF.csv`（n=15536）；`mimic预后数据-all.csv`（n=65366）  
**课题疾病**：SLE（队列筛入，baseline 无 SLE 诊断列）→ AKI/急性肾衰竭（发病结局）

## 键字段结论

| 表 | 主键 | 与 baseline 关系 |
|----|------|------------------|
| baseline | `ID`（integer，唯一） | 基准表 |
| SLE.csv | `subject_id`, `stay_id`, `hadm_id` | `subject_id` ↔ `baseline$ID`，271/271 命中 |
| ARF.csv | `subject_id`, `stay_id`, `hadm_id` | `subject_id` ↔ `baseline$ID`，15536/15536 命中 |
| mimic预后数据-all.csv | `subject_id`, `stay_id`, `hadm_id` + 随访/死亡 | n=65366=baseline；SLE 271/271 可并 |
| dabiao | `ID` + `DN` | n=271=SLE；`DN` 与 `Acute_Renal_Failure` 一致（110 例 AKI） |

**推荐合并键**：Stage0 筛 SLE 用 `SLE.csv$subject_id == baseline$ID`（或 `stay_id` 与预后表对齐 ICU 层）；预后并 `mimic预后数据-all.csv` 用 `subject_id`/`stay_id`。

---

## 全列审阅（baseline 104 列）

| 列名 | 保留/排除 | 理由 |
|------|-----------|------|
| ID | 排除 | 标识符，非协变量 |
| Age | 保留 | 人口学；Model1 强制候选 |
| Gender | 保留 | 人口学 |
| Race | 保留 | 人口学 |
| Weight | 保留 | 体测；GNRI 等指标成分 |
| Height | 保留 | 体测 |
| BMI | 保留 | 体测/营养；文献暴露候选 |
| Language | 保留 | 社会人口学 |
| Marital_Status | 保留 | 社会人口学 |
| HR | 保留 | 生命体征 |
| NBPS | 保留 | 无创收缩压 |
| NBPD | 保留 | 无创舒张压 |
| NBPM | 保留 | 无创平均压 |
| ABPS | 保留 | 有创收缩压 |
| ABPD | 保留 | 有创舒张压 |
| ABPM | 保留 | 有创平均压 |
| PP | 保留 | 脉压 |
| RR | 保留 | 呼吸频率 |
| SpO2 | 保留 | 血氧 |
| Temperature | 保留 | 体温 |
| WBC | 保留 | 通用 CBC |
| RBC | 保留 | 通用 CBC |
| NeutrophilCount | 保留 | 通用 CBC；NLR/SII 等成分由指标组成排除 |
| Lymphocytes | 保留 | 通用 CBC；NLR/LMR 等成分由指标组成排除 |
| PlateletCount | 保留 | 通用 CBC；SII 等成分由指标组成排除 |
| Hemoglobin | 保留 | 通用 CBC |
| RDW | 保留 | 通用 CBC |
| Hematocrit | 保留 | 通用 CBC |
| Albumin | 保留 | 血清白蛋白（≠尿白蛋白）；PNI/CONUT 成分 |
| Globulin | 保留 | 通用生化 |
| TotalProtein | 保留 | 通用生化 |
| Sodium | 保留 | 电解质 |
| Potassium | 保留 | 电解质 |
| CalciumTotal | 保留 | 电解质 |
| Chloride | 保留 | 电解质 |
| Glucose | 保留 | 通用代谢；非本课题主病标志物（糖尿病用 T1DM/T2DM 列） |
| HbA1c | 保留 | 通用糖代谢；非 SLE/AKI 专属（T2DM 已单列） |
| AnionGap | 保留 | 通用生化 |
| PH | 保留 | 血气 |
| PCO2 | 保留 | 血气 |
| PO2 | 保留 | 血气 |
| Lactate | 保留 | 通用 ICU 严重程度 |
| TotalCo2 | 保留 | 血气 |
| FreeCalcium | 保留 | 电解质 |
| TT | 保留 | 凝血 |
| PT | 保留 | 凝血 |
| Fibrinogen | 保留 | 凝血 |
| PTT | 保留 | 凝血 |
| INR | 保留 | 凝血 |
| Ddimer | 保留 | 凝血 |
| TG | 保留 | 血脂 |
| TC | 保留 | 血脂 |
| HDL | 保留 | 血脂 |
| LDL | 保留 | 血脂 |
| BilirubinTotal | 保留 | 肝功能 |

## disease_vars section (grep)
24:| 列名 | 保留/排除 | 理由 |
26:| ID | 排除 | 标识符，非协变量 |
27:| Age | 保留 | 人口学；Model1 强制候选 |
28:| Gender | 保留 | 人口学 |
29:| Race | 保留 | 人口学 |
30:| Weight | 保留 | 体测；GNRI 等指标成分 |
31:| Height | 保留 | 体测 |
32:| BMI | 保留 | 体测/营养；文献暴露候选 |
33:| Language | 保留 | 社会人口学 |
34:| Marital_Status | 保留 | 社会人口学 |
35:| HR | 保留 | 生命体征 |
36:| NBPS | 保留 | 无创收缩压 |
37:| NBPD | 保留 | 无创舒张压 |
38:| NBPM | 保留 | 无创平均压 |
39:| ABPS | 保留 | 有创收缩压 |
40:| ABPD | 保留 | 有创舒张压 |
41:| ABPM | 保留 | 有创平均压 |
42:| PP | 保留 | 脉压 |
43:| RR | 保留 | 呼吸频率 |
44:| SpO2 | 保留 | 血氧 |
45:| Temperature | 保留 | 体温 |
46:| WBC | 保留 | 通用 CBC |
47:| RBC | 保留 | 通用 CBC |
48:| NeutrophilCount | 保留 | 通用 CBC；NLR/SII 等成分由指标组成排除 |
49:| Lymphocytes | 保留 | 通用 CBC；NLR/LMR 等成分由指标组成排除 |
50:| PlateletCount | 保留 | 通用 CBC；SII 等成分由指标组成排除 |
51:| Hemoglobin | 保留 | 通用 CBC |
52:| RDW | 保留 | 通用 CBC |
53:| Hematocrit | 保留 | 通用 CBC |
54:| Albumin | 保留 | 血清白蛋白（≠尿白蛋白）；PNI/CONUT 成分 |
55:| Globulin | 保留 | 通用生化 |
56:| TotalProtein | 保留 | 通用生化 |
57:| Sodium | 保留 | 电解质 |
58:| Potassium | 保留 | 电解质 |
59:| CalciumTotal | 保留 | 电解质 |
60:| Chloride | 保留 | 电解质 |
61:| Glucose | 保留 | 通用代谢；非本课题主病标志物（糖尿病用 T1DM/T2DM 列） |
62:| HbA1c | 保留 | 通用糖代谢；非 SLE/AKI 专属（T2DM 已单列） |
63:| AnionGap | 保留 | 通用生化 |
64:| PH | 保留 | 血气 |

## Report
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
