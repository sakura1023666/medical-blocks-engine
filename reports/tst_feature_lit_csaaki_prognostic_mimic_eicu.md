# CSA-AKI 预后特征海选（第二主线）2026-11-04

> 用途：与 Allyn 统一池版对照。本版目标 =「心脏围术期 AKI 队列上尽量好的 ICU 死亡 + RLoS 预测」。  
> 仍用 TPC / 同一划分 / 同一结局；只改进模动态特征。  
> 纳入泄漏：`creatinine`、`urine_output` **永不进模**（纳排可用，建模不用）。

## 文献依据（动态 / ICU 床旁可重复测）

| 来源 | 要点 |
|---|---|
| BAR score（心外术后 ICU 入院，JCVA 2026） | 乳酸最强；另有 MAP、HR、Hct、PaO2/FiO2、CVP |
| CS-AKI + RRT 死亡（Frontiers Cardiovasc Med 2021） | 高乳酸、低 MAP、高 VIS / APACHE / SOFA |
| CRRT after cardiac surgery（JCVA） | 透析启动时乳酸主导 ICU 死亡 |
| 心外术后时序 DL（JTCVS 2026） | 小时级生命体征、通气、血管活性药、化验 |
| Allyn 2026 Limitation | 药物位点捷径伤外推 → 本版**砍掉**长尾抗感染/杂药，只留 VIS 相关血管活性 |

## 四库可算白名单（进 `DBPOOL_KEEP_TS`）

### 必留（文献核心 ∩ 至少 2 库常见）

- 循环：`heart_rate`, `invasive_mean_blood_pressure`, `noninvasive_mean_blood_pressure`, `invasive_systolic_blood_pressure`, `invasive_diastolic_blood_pressure`, `noninvasive_systolic_blood_pressure`, `noninvasive_diastolic_blood_pressure`
- 氧合/通气：`O2_arterial_saturation`, `temperature`, `respiratory_rate`, `FiO2`, `PEEP`, `paO2`, `paCO2`, `pH`
- 灌注/炎化验：`lactate`, `hemoglobin`, `platelets`, `white_blood_cells`, `sodium`, `potassium`, `chloride`, `bicarbonate`, `blood_glucose`, `blood_urea_nitrogen`, `bilirubine`, `albumin`, `magnesium`, `calcium`, `phosphate`, `PTT`
- 血管活性（VIS 代理；SICdb/INSPIRE 当前小时层常缺 → 缺失掩码）：`norepinephrine`, `epinephrine`, `dopamine`, `dobutamine`, `milrinone`

### 明确排除

- `creatinine`, `urine_output`（KDIGO 纳入）
- Allyn 长尾药物（抗生素、他汀等）与镇静镇痛（位点处方捷径）
- `glasgow_coma_score*`（训练源 SICdb/MIMIC 小时层覆盖差）
- 肝酶 ALT/AST（非本队列纳入轴；非 CSA-AKI 死亡主驱动）

## 覆盖局限（诚实写进 Methods）

- SICdb / INSPIRE：**几乎无**血管活性与 FiO2/PEEP 列 → 外验/单库依赖生命体征+血气+化验；与 MIMIC 比信息更瘦。
- 无统一 CVP / 血球压积列名时用 `hemoglobin` 代理 BAR 的 Hct。
- 无法四库共有的术中 CPB 时间、术式等 → 不进池化主分析。

## 对照设计

| 臂 | 目录 | 特征 |
|---|---|---|
| A Allyn 池 | `Output_database_pooling/` | BlendedLoS keep=1 全表 − Cr/尿 |
| B CSA-AKI 预后 | `Output_database_pooling_prognostic/` | 上表白名单（KEEP）− Cr/尿 |

主比较：同一 `expD`（MIMIC+SICdb 池化）在 eICU/INSPIRE 上的死亡 AUROC 与 RLoS MAPE。
