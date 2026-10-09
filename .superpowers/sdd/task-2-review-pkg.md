# Review package Task 2
## _column_review.md
# 列审阅 — 骨质疏松 DXA/QCT 与椎体骨折（发病）

**数据对象：** `dabiao`（`D01_osteo_personalized.RData`）  
**审阅日期：** 2026-09-22  
**n：** 208 | **列数：** 40  
**课题类型：** 发病（incidence）；**暴露**为连续骨密度 `QCT_vBMD` / `DXA_T_min`（非复合公式指标）；**结局**为椎体压缩性骨折。

**映射：** 见 `data/harmonized/column_map.csv`（31 列自 CSV 重命名 + 9 列派生）。

---

## 全列清单

| 列名 | 角色 | 协变量池 | Table1 | 说明 |
|------|------|----------|--------|------|
| `SampleID` | ID | 排除 | 否 | 患者唯一标识；不进 UV/MV/亚组/插补协变量。 |
| `Age` | 协变量 | 保留 | 是 | 人口学；Model1 强制 Age；亚组建议 `age_cutoff=65`（骨质疏松/骨折文献常用老年界，见文末）。 |
| `QCT_vBMD` | **暴露（QCT 轴）** | 排除 | 可选† | 连续 QCT 体积骨密度（mg/cm³）；主暴露之一，非协变量。 |
| `QCT_cat` | 诊断/分型标签 | **硬排除** | 否 | QCT 骨质疏松分类（0 正常 / 1 骨量减少 / 2 骨质疏松）；与暴露同源，进协变量致泄漏。 |
| `DXA_T_min` | **暴露（DXA 轴）** | 排除 | 可选† | 腰椎或髋部 DXA T 值最低；主暴露之一。 |
| `DXA_cat_min` | 诊断/分型标签 | **硬排除** | 否 | DXA 最低部位分类（0/1/2）；与 `DXA_T_min` 同源。 |
| `DXA_T_lumbar` | 暴露（次要轴） | 排除 | 否 | 腰椎 DXA T 值；与 `DXA_T_min` 高度相关，仅作敏感性/副暴露，不进协变量池。 |
| `DXA_cat_lumbar` | 诊断/分型标签 | **硬排除** | 否 | 腰椎 DXA 分类；同类泄漏。 |
| `Vertebral_fracture` | **结局（0/1）** | **硬排除** | 否 | 椎体压缩性骨折；建模用二进制结局。 |
| `SBP` | 协变量 | 保留 | 是 | 收缩压；通用心血管协变量。 |
| `DBP` | 协变量 | 保留 | 是 | 舒张压。 |
| `FPG` | 协变量 | 保留 | 是 | 空腹血糖；非本课题 `disease_vars`（用户口径：通用实验室不进疾病排除名单）。 |
| `BMI` | 协变量 | 保留 | 是 | 体重指数；与 `BMI_bin` 二选一入模，连续列进 UV/MV。 |
| `TG` | 协变量 | 保留 | 是 | 甘油三酯。 |
| `CHO` | 协变量 | 保留 | 是 | 总胆固醇。 |
| `HDL_C` | 协变量 | 保留 | 是 | HDL-C。 |
| `LDL_C` | 协变量 | 保留 | 是 | LDL-C。 |
| `Hb` | 协变量 | 保留 | 是 | 血红蛋白。 |
| `Ca` | 协变量 | 保留 | 是 | 血清钙。 |
| `P` | 协变量 | 保留 | 是 | 血清磷。 |
| `UA` | 协变量 | 保留 | 是 | 尿酸。 |
| `CCr` | 协变量 | 保留 | 是 | 肌酐清除率。 |
| `VitD_25OH` | 协变量 | 保留 | 是 | 25-OH 维生素 D；骨代谢相关但作可调整环境/营养因子，不进 `disease_vars`。 |
| `P1NP` | 协变量 | 保留 | 是 | 骨形成标志物；【边界·已保留为协变量】按 Task 接口不把实验室扩入 `disease_vars`，敏感性可另做。 |
| `bCTX` | 协变量 | 保留 | 是 | 骨吸收标志物；同上。 |
| `PTH` | 协变量 | 保留 | 是 | 甲状旁腺激素；同上。 |
| `ALP` | 协变量 | 保留 | 是 | 碱性磷酸酶；同上。 |
| `Calcitonin` | 协变量 | 保留 | 是 | 降钙素；同上。 |
| `Osteocalcin` | 协变量 | 保留 | 是 | 骨钙素；同上。 |
| `Nathan` | 协变量 | 保留 | 是 | 脊柱骨赘分级（退变）；非骨折结局定义列。 |
| `AAC` | 协变量 | 保留 | 是 | 腹主动脉钙化（0/1）。 |
| `QCT_OP` | 派生·OP 标签 | **硬排除** | 否 | `QCT_cat==2`；骨质疏松二元标签。 |
| `DXA_OP` | 派生·OP 标签 | **硬排除** | 否 | `DXA_cat_min==2`。 |
| `need_QCT` | 派生·不一致子集 | **硬排除** | 否 | QCT 骨质疏松且 DXA 未达 OP；用于 QCT 增量价值子集，非通用协变量。 |
| `discordance_group` | 派生·QCT/DXA 不一致 | **硬排除** | 否 | Both_OP / QCT_only_OP / DXA_only_OP / Neither_OP；暴露/诊断交叉标签。 |
| `Nathan_bin` | 分层/展示 | 排除 | 可选 | Nathan 二分类（1–2 vs 3–4）；亚组或 Table1 分层用，不进连续 UV/MV 与 `Nathan` 同入。 |
| `BMI_bin` | 分层/展示 | 排除 | 可选 | 中国超重切点 24；与连续 `BMI` 勿重复入模。 |
| `Age_bin` | 分层/展示 | 排除 | 可选 | 65 岁二分类；森林图用 `Age_Group` 引擎生成，勿与 `Age` 重复入模。 |
| `Fracture_f` | **结局（显示）** | **硬排除** | 否 | factor：`No_Fracture` / `Fracture`；与 `Vertebral_fracture` 同义，防标签列进协变量。 |
| `Disease` | **结局（显示）** | **硬排除** | 否 | 发病套路 `analysis_group` 显示名；与 `Fracture_f` 同级。 |

† Table1 若按暴露三分/四分位展示，可描述性报告对应连续 BMD/T 值，但不作为协变量调整项。

---

## 协变量候选摘要（可进 UV / VIF / Model1–2 / 亚组，需与 `disease_vars` 无交）

`Age`, `SBP`, `DBP`, `FPG`, `BMI`, `TG`, `CHO`, `HDL_C`, `LDL_C`, `Hb`, `Ca`, `P`, `UA`, `CCr`, `VitD_25OH`, `P1NP`, `bCTX`, `PTH`, `ALP`, `Calcitonin`, `Osteocalcin`, `Nathan`, `AAC`

**暴露（单独建模轴，非协变量池）：** `QCT_vBMD`；和/或 `DXA_T_min`（副轴 `DXA_T_lumbar` 仅敏感性）。

**结局字段：** 建模 `Vertebral_fracture`（0/1）；显示 `Disease` / `Fracture_f`（经 `pipeline_outcome_as_01` 口径）。

---

## 年龄亚组（写 config 时同步）

- **切点：** 65 岁（骨质疏松与脆性骨折队列常用；无更特异文献时采用项目默认二分类）。
- **配置：** 仅 `subgroup$age_cutoff = 65L`，`level_order$Age_Group = c("< 65", "≥ 65")`；禁止无依据四档 `age_group_cutoffs`。
- **勿用** `Age_bin` 与引擎 `Age_Group` 双轨入模。

---

## `analysis_exclusion$disease_vars`（config 用）

以下列不得进入 Table1/S1 协变量列、UV/MV/VIF、Model1–2、亚组（除作结局/暴露定义外）、中介协变量池。

```r
disease_vars <- c(
  "Vertebral_fracture", "Disease", "Fracture_f",
  "QCT_cat", "DXA_cat_min", "DXA_cat_lumbar",
  "QCT_OP", "DXA_OP", "need_QCT", "discordance_group"
)
```

建议同步：

```r
analysis_exclusion = list(
  disease_vars = disease_vars,
  component_scope = "current_transitive",
  exclude_other_composite_indices = TRUE,
  exclude_exposure_if_uses_disease_var = TRUE
)
```

**流水线：** 发病链 `index` → **`analysis_exclusion`** → `imputation` → …（写 config 时挂载并清旧 checkpoint）。

---

## 自检

- [x] 40 列均有审阅行
- [x] 结局 / BMD 分类 / QCT–DXA 不一致派生列已入 `disease_vars`
- [x] `Fracture_f` 已扩展（与 `Vertebral_fracture` / `Disease` 同锁）
- [x] Age/BMI/通用与骨代谢实验室未扩入 `disease_vars`（按 Task 2 接口）
- [x] 复合指标暴露不适用（本课题为连续 BMD 轴）
