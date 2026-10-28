# 列审阅：预后 2.0 血脂异常 × 睡眠 × 死亡

审阅日期：2026-10-13。疾病是血脂异常。睡眠小时是暴露，不是疾病标志物。

## 硬排除（disease_vars）

诊断与用药：`Hyperlipidemia`，`Lipid_lowering_agents`。

定义血脂异常用的实验室列：`TG`，`TC`，`HDL`，`LDL`，`LBDLDL_calc`，以及 SHHS 原名 `chol` / `hdl` / `trig`。这些列一旦进 Model，等于把纳排标准又放进协变量。

## 可留作协变量或中介

人口学：`Age`，`Gender`，`Race`，`Education`。

体格：`BMI`，`Height`，`Weight`，`Waist_circumference`。

血压与血糖：`NBPS`，`NBPD`，`Hypertension`，`Diabetes`，`Glucose`，`HbA1c`。中介默认 `HbA1c`，没有则用 `BMI`。

## 不进协变量，但也不算 disease_vars

`ID`，随访 `futime_years` / `fustatus` / `cvd_status`，权重 `WTMEC2YR` / `survey_weight`，设计列 `SDMVPSU` / `SDMVSTRA`。

## 三库现况

| 库 | 睡眠 | 血脂异常 | 死亡时间 |
|---|---|---|---|
| NHANES | `SLD01` | 化验切点，且已排除心血管病 | `nhanes-死亡.Rdata`：`permth_exm/12`，`mortstat` |
| CHARLS | `da049`，按 `ID_h_charls` 连接 | 同一化验切点，不用自报 Hyperlipidemia | `exb001_1` 年、`exb001_2` 月、`exb002` 公历/农历 |
| SHHS | `hrswd02` | 同一化验切点 | `censdate` 天；`vital==0` 为死亡 |

对齐后的标准名见 `run/prognosis_v2/pv2_front.R`。插补只填协变量（Age、Gender、BMI、Smoke、Alcohol、Hypertension、Diabetes、Education、SBP），不填睡眠、随访、死亡和权重。

暴露组成不是复合指标公式，没有「指标成分泄漏」需要再套 `pipeline_indices_using_vars`。
