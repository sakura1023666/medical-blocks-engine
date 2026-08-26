# 术后 AKI · VitalDB 术前血钠 · 单库发病设计

**日期：** 2026-08-21  
**状态：** 用户已口头确认设计方向；本文件待用户审阅后进入实施计划  
**课题路径：** `/mnt/g/02block_result/26_Postoperative AKI/incidence_38341157/`  
**依据：** `data/陈萌要求(2).docx` + VitalDB 基线 `data/vitaldb/D01_baseline_VitaIDB_CM(1).Rdata`

---

## 1. 目标

在 **单库 VitalDB** 上，按老师修订意见重跑「术前血钠 → 术后 48 小时内急性肾损伤（Postoperative AKI within 48 hours）」发病分析，交付可发表表图，并优先交出老师点名的 3 个关键数值。

**不在本轮：** IOH/MAP 波形提取；PSM 1:1 重匹配；复合指标批量。

---

## 2. 数据与变量

| 角色 | 字段 / 派生 | 说明 |
|------|-------------|------|
| 队列 | `baseline`，N≈6388 | 对象名 `baseline` |
| 暴露 | `Sodium` | 术前血钠；约 54 缺失 |
| 结局 | `judge`（0/1） | 文案统一为 Postoperative AKI within 48 hours；约 268 例（4.2%） |
| ID | `ID` | |
| Model 3 强制协变量 | Age, Gender, BMI, Hypertension, T2DM, OpType, Approach, Hemoglobin, Albumin, Potassium, **Creatinine** | **禁止**纳入 `icu_days`/`ICU_Days`、`UreaNitrogen`(BUN) |
| Model 4 追加（无 IOH） | `IntraopCrystalloid`(mL)、`IntraopColloid`(mL)、`OpDuration_min`=(opend−opstart)/60、`Vasopressor_use`=(任一 IntraopEPH/PHE/EPI/CA > 0) | 液体单位本轮用 **mL**（mL/kg 可后补敏感性） |
| 本轮不可用 | `IOH_duration_minutes`、`IOH_prolonged`、MAP | 基线无波形；后补 |

**疾病硬排除（`analysis_exclusion$disease_vars`）至少包含：**  
结局与术后/术中肾相关泄漏与标志物，例如（审阅落盘时最终定稿）：`judge` 不进协变量池；`Creatinine`/`GFR`/`CreatinineClearance`/`UreaNitrogen` 中——**Creatinine 因老师强制进 Model 3 作为混杂调整保留进模型，但不作为暴露、不进亚组分层暴露、不进指标组成池**；`icu_days`/`ICU_Days`/`Death_Inhosp`/`death_inhosp` 作结局/术后变量排除出协变量自动池；`IntraopUO`（术中尿量）默认排除（与 AKI 定义相关）。  
完整逐列审阅写入 `data/_column_review.md`（skill：`review-raw-covariate-columns`）。

**纳排建议（attrition）：** 有 ID → 有 Sodium → 有 judge；敏感性另排除 `Creatinine > 4`。

---

## 3. 架构（方案 1）

```
prep（派生列 + 标签） → config_incidence_single
  → run_incidence_single.R
     clean → map → analysis_exclusion → imputation
     → baseline_binary → UV/VIF/MV（对照）
     → logistic（强制 Model1/Model2≡老师 Model3 名单）→ RCS → subgroup(FDR)
  → 附加脚本：Model4、敏感性 Cr>4、关键数值汇总
```

- **入口：** `Rscript run/incidence/run_incidence_single.R --config <study>/config_incidence_single.R`
- **模板：** `configs/templates/config_incidence_single.template.R`
- **config / 输出根：** 课题目录 `incidence_38341157/`（与子宫肌瘤等同 PMID 目录习惯一致）
- **暴露不当复合指标：** `index$enable = FALSE` 或 `only` 不用公式；`incidence$index_var = "Sodium"`，`logistic$index_var = "Sodium"`

**协变量铁律落地方式：**  
跳过「自动 UV 显著 → Model2」作为主文依据；在 logistic 配置中 **写死** `model1_factors` / `model2_factors` 为老师名单（Model2 = 老师口中的 Model 3）。UV/VIF 块可保留出表，但 **不** `write_model_factors` 覆盖强制名单（或跑完后由 config 强制覆盖）。

---

## 4. 分析规格

### 4.1 主分析 Logistic

- 连续 Sodium + 分位（闸门与主文一致；若历史文稿 Q2 为 138–140，优先核对是否为固定切点分箱；**默认先走引擎分位闸门**，若与文稿切点不一致，在 `code/` 或附加表注明切点来源并出固定切点敏感性表）。
- **Model 1：** Age + Gender（对应老师 Sex；不以单因素是否显著为踢出条件）  
- **Model 2（= 老师 Model 3）：** 强制名单（含 Creatinine，不含 BUN、不含 ICU stay）
- 输出：OR、95%CI、P；重点回报连续 Na 的 OR/P 与 Q2 的 P

### 4.2 Model 4（Secondary）

- 在 Model 2 上追加液体（mL）、手术时长、升压药使用  
- **解释为敏感性/次要**，不替代 Model 2 主结论  
- 无 IOH：表注写明「IOH 待 VitalDB 波形后补」

### 4.3 RCS

- 节点数 **固定 4**：百分位 **5, 35, 65, 95**  
- 报告：拐点（1 位小数）、**P-nonlinear**；仅当 P-nonlinear < 0.05 才强调非线性

### 4.4 敏感性

- 排除术前 `Creatinine > 4` mg/dL 后重跑 Model 2；若 Na 的 OR 方向与显著性与主分析一致，正文可写「敏感性稳健」

### 4.5 亚组 / Table 1

- 亚组 P 展示 **FDR（Benjamini–Hochberg）**；图注与方法写明  
- Table 1：连续变量注明 Mean (SD)；偏态（如 ICU stay，若仍展示）用 Median (IQR)+Wilcoxon；组标签 **Postoperative AKI**（禁止「术中 AKI」）  
- 年龄亚组：二分类，默认 `age_cutoff = 65`（注释：无病种特异切点则用默认 65；若文献常用其它切点可改）

### 4.6 本轮明确不做

- IOH log / 0·1–10·>10 分层  
- PSM 重匹配（老师第 4 点 → 二期）  
- 把 ICU stay 调进任何主模型

---

## 5. 落盘与交付

| 产物 | 位置 |
|------|------|
| config / prep / `_column_review.md` | `incidence_38341157/` 与 `data/` |
| 主分析表图 | 同目录 `Tables/` `Figures/` `by_index/`（若启用） |
| 成功指标 code 包 | 按全项目铁律：成功输出根下 `code/`（本课题单暴露时可对 Sodium 输出根写 code 包） |
| 老师三关键数 | 单独 `KEY_RESULTS.md` 或 `Tables/Teacher_key_numbers.csv`：① Model2 连续 Na OR/P；② Q2 P；③ RCS 拐点 + P-nonlinear |

---

## 6. 风险与依赖

1. **强制名单 vs 引擎自动写回：** 必须防止 MV/VIF 覆盖 `Model2Factors`。  
2. **Creatinine 既是混杂又是疾病标志：** 仅按老师要求进 Model 2；不得进暴露、不得当亚组分层变量的「疾病泄漏」用途以外的自动池滥用。  
3. **分位切点：** 文稿 Q2=138–140 可能非等频四分位；实施计划须含「对照文稿切点」一步。  
4. **IOH 后补：** Model 4 表结构预留 IOH 列位或脚注，避免二次改表结构。

---

## 7. 成功标准

- [ ] 单库流水线跑通，术语与 Table 1 组名为 Postoperative AKI  
- [ ] Model 2 协变量 = 老师名单（有 Cr、无 BUN、无 ICU stay）  
- [ ] Model 4（无 IOH）与 Cr>4 敏感性已出表  
- [ ] RCS 4 节点 + 拐点(1 位小数) + P-nonlinear  
- [ ] 亚组图为 FDR-P  
- [ ] `KEY_RESULTS` 含老师三个关键数  
- [ ] `_column_review.md` 与 `analysis_exclusion` 已落盘  

---

## 8. 决策记录

| 项 | 选择 |
|----|------|
| 暴露 | A：术前 Sodium |
| IOH | A：本轮不做；Model 4 用液体+时长+升压药 |
| Model 3 协变量 | A：强制老师名单 |
| 总体方案 | 方案 1：incidence_single + 强制因子 + 附加 Model4/敏感性 |
