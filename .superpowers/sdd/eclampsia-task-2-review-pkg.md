# Review package Task 2
## Files
-rw-r--r-- 1 root root 6236 Aug 21 14:12 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/_column_review.md
-rw-r--r-- 1 root root 677 Aug 21 14:03 /mnt/g/02block_result/27_eclampsia/small sample prediction_39780007/Data/_column_review_raw.txt

## Column count check
dabiao cols= 76 
review lines with pipe:
78

## Full _column_review.md
```md
# 子痫（Eclampsia）原始列审阅

- 课题: `27_eclampsia / small sample prediction_39780007`
- 日期: 2026-08-21
- 数据: `Data/mimic/D04_dabiao.RData`（`dabiao` n=4756；`DN` 事件=482）
- 结局列: `DN`（0/1；子痫发病）
- 人群: 全女性妊娠队列（`Gender` 全为 Female）
- 审阅原则: 子痫/子痫前期谱系诊断泄漏、尿蛋白轴、血糖轴 → `disease_vars`；不确定默认排除并标【边界·已排除】；复合指标不进 `disease_vars`（由成分排除处理）

## MIMIC（本课题唯一库）

| 列名 | 保留/排除 | 理由 |
|---|---|---|
| `ID` | 保留·ID | 分析 ID；不进协变量池，不进 disease_vars |
| `DN` | 结局 | 子痫病例/对照；不进 disease_vars，由 outcome 处理 |
| `Age` | 保留 | 人口学；协变量 / Model1 / 亚组（age_cutoff=35） |
| `Gender` | 排除·设计列 | 全女性无信息量；进 drop/exclude，**不进** disease_vars |
| `Race` | 保留 | 人口学；可作协变量/亚组 |
| `Language` | 保留 | 人口学/社会经济；可作协变量 |
| `Marital_Status` | 保留 | 人口学；可作协变量 |
| `WBC` | 保留 | 通用血常规；可作协变量或指标组成 |
| `RBC` | 保留 | 通用血常规 |
| `NeutrophilCount` | 保留 | 通用血常规；炎症指标组成 |
| `Lymphocytes` | 保留 | 通用血常规；炎症指标组成 |
| `PlateletCount` | 保留 | 通用血常规（HELLP 相关但 brief 保留通用实验室；成分排除另管） |
| `Hemoglobin` | 保留 | 通用血常规 |
| `RDW` | 保留 | 通用血常规 |
| `Hematocrit` | 保留 | 通用血常规 |
| `Albumin` | 保留 | 血清白蛋白 ≠ 尿白蛋白；通用肝肾营养实验室 |
| `Globulin` | 保留 | 通用蛋白实验室 |
| `TotalProtein` | 保留 | 通用蛋白实验室 |
| `Sodium` | 保留 | 通用电解质 |
| `Potassium` | 保留 | 通用电解质 |
| `CalciumTotal` | 保留 | 通用电解质 |
| `Chloride` | 保留 | 通用电解质 |
| `Glucose` | 排除 | 血糖轴；妊娠期糖尿病/代谢泄漏 |
| `HbA1c` | 排除 | 血糖轴；糖化血红蛋白 |
| `AnionGap` | 保留 | 通用血气/酸碱 |
| `PH` | 保留 | 通用血气 |
| `PCO2` | 保留 | 通用血气 |
| `PO2` | 保留 | 通用血气 |
| `Lactate` | 保留 | 通用代谢/危重症实验室 |
| `TotalCo2` | 保留 | 通用血气 |
| `FreeCalcium` | 保留 | 通用电解质 |
| `TT` | 保留 | 通用凝血 |
| `PT` | 保留 | 通用凝血 |
| `Fibrinogen` | 保留 | 通用凝血 |
| `PTT` | 保留 | 通用凝血 |
| `INR` | 保留 | 通用凝血 |
| `Ddimer` | 保留 | 通用凝血/血栓标志（非子痫定义轴） |
| `TG` | 保留 | 通用血脂 |
| `TC` | 保留 | 通用血脂 |
| `HDL` | 保留 | 通用血脂 |
| `LDL` | 保留 | 通用血脂 |
| `BilirubinTotal` | 保留 | 通用肝功能（指标组成另排除） |
| `BilirubinDirect` | 保留 | 通用肝功能 |
| `BilirubinIndirect` | 保留 | 通用肝功能 |
| `ALT` | 保留 | 通用肝酶 |
| `AST` | 保留 | 通用肝酶 |
| `UreaNitrogen` | 保留 | 通用肾功能实验室（非尿蛋白轴） |
| `Creatinine` | 保留 | 通用肾功能实验室（非尿蛋白轴；成分排除另管） |
| `UricAcid` | 排除【边界·已排除】 | 子痫前期经典严重度/病理相关标志物；不确定默认排除 |
| `LD` | 保留 | 通用酶学（溶血相关但作通用实验室保留） |
| `CK` | 保留 | 通用心肌/肌酶 |
| `CKMb` | 保留 | 通用心肌标志 |
| `TroponinT` | 保留 | 通用心肌损伤标志 |
| `NTproBNP` | 保留 | 通用心衰标志（非子痫定义轴） |
| `UrineProtein` | 排除 | 尿蛋白轴；子痫前期诊断核心标志，结局泄漏风险高 |
| `UrineGlucose` | 排除 | 尿糖；血糖/代谢轴泄漏 |
| `AlbuminUrine` | 排除 | 尿白蛋白轴；蛋白尿/微血管泄漏 |
| `AlbuminCreatinine` | 排除 | 尿白蛋白/肌酐比；蛋白尿轴 |
| `Hypertension` | 排除 | 与子痫/子痫前期定义高度重叠的诊断泄漏 |
| `T2DM` | 排除 | 糖尿病诊断；血糖轴 |
| `T1DM` | 排除 | 糖尿病诊断；血糖轴 |
| `Diabetes` | 排除 | 糖尿病总括诊断；血糖轴 |
| `Heart_Failure` | 保留 | 其它共病；非子痫核心标志 |
| `Myocardial_Infarction` | 保留 | 其它共病 |
| `Malignant_Tumor` | 保留 | 其它共病 |
| `CKD` | 排除【边界·已排除】 | 慢性肾病诊断；与子痫前期肾功能受累谱系易重叠，不确定默认排除 |
| `Acute_Renal_Failure` | 排除【边界·已排除】 | 急性肾衰诊断；重度子痫前期终末器官受累可重叠，不确定默认排除 |
| `Liver_cirrhosis` | 保留 | 其它共病；非子痫核心标志 |
| `Hepatitis` | 保留 | 其它共病 |
| `Tuberculosis` | 保留 | 其它共病 |
| `Pneumonia` | 保留 | 其它共病 |
| `Stroke` | 保留 | 其它共病（脑血管事件 ≠ 子痫抽搐定义列） |
| `Hyperlipidemia` | 保留 | 其它共病 |
| `COPD` | 保留 | 其它共病；brief 保留示例 |
| `Insurance` | 保留 | 社会经济；可作协变量 |
| `ALBI` | 保留·复合指标 | 复合指标本身；**不进** disease_vars，由 `analysis_exclusion` 成分排除处理 |

## 覆盖自检

- 原始列数: **76**
- `_column_review.md` 行数: **76**（上表逐列一一对应 `_column_review_raw.txt`）
- 进 `disease_vars` 列数: **13**（≥8）
- 不进 disease_vars 的特殊列: `ID`, `DN`, `Gender`（设计排除）, `ALBI`（复合指标）

## Task 3 粘贴用：`.disease_exclusion_vars`

```r
.disease_exclusion_vars <- c(
  # 妊娠高血压谱系 / 诊断泄漏
  "Hypertension",
  # 血糖轴
  "T1DM", "T2DM", "Diabetes", "Glucose", "HbA1c",
  # 尿蛋白 / 尿白蛋白轴
  "UrineProtein", "UrineGlucose", "AlbuminUrine", "AlbuminCreatinine",
  # 【边界·已排除】子痫前期肾功能/病理相关
  "UricAcid", "CKD", "Acute_Renal_Failure"
)
```

### 同步提醒（供 Task 3，本 Task 不写 config）

- `analysis_exclusion$disease_vars = .disease_exclusion_vars`
- `Gender` 另列入 `base_exclude_vars` / drop（全女性），勿塞进 disease_vars
- `age_cutoff = 35`；`Age_Group` 仅 `"< 35"` / `"≥ 35"`
- 用 `pipeline_indices_using_vars(.disease_exclusion_vars, .composite_index_vars)` 跳过疾病衍生暴露
```
