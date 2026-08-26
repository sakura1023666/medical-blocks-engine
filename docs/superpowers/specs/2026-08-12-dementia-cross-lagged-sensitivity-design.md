# Dementia 交叉滞后敏感性分析设计

日期：2026-08-12  
状态：已批准（含连续性硬约束；用户确认合理性）  
Study root：`/mnt/g/02block_result/20_Dementia/cross-laged_40595747/`  
主分析锚点：`…/141 痴呆 交叉滞后 姜小胖/姜小胖_痴呆20260203 - 副本/`

## 1. 目标

仅跑交叉滞后**敏感性分析**，产出与髋部骨折项目同构的表结构：

- 基线 Table1
- Logistic 三分位（GLM）
- Change（mean + change；含 twowave 合并表）

不跑完整 phase1–3 主分析，不跑 CLPN bootstrap，不跑 competing risk。

### 1.1 连续性硬约束（必须与前面主分析对得上）

本敏感性是**基于已完成主分析的同一套分析再做样本过滤**，不是另起一份数据、另套方法、另出一套不可比结果。

| 维度 | 必须继承的主分析来源 | 禁止 |
|------|----------------------|------|
| 分析人群 | 交付/主分析同一批 `D01_AfterMI_Data_*`（当前 study `data/Step01_RawData` 与交付 n 已一致：ELSA 5049 / HRS 5361 / SHARE 14682 / CLHLS 1032） | 重新插补、重新入排、换另一份 AfterMI |
| 结局定义 | 主分析同一 `Disease` / Dementia 编码 | 另造结局规则或换结局列 |
| 暴露 | `Leisure_activities`；三分位算法同 `Step02_Logistic/C01_LogisticCode_new_3.R`（库内 1/3、2/3） | 四分位、中位数二分、四库共用绝对切点 |
| 协变量 | 与主分析 Table 2 一致的 Model1 / Model2（见 §2） | 套用髋部 FI 的 Age+Alcohol 锁，或另搜一套 VIF |
| Change / 年份 | 同主分析 Step05 C00 各库基线年与随访年；优先复用已有 `D05_long_*` / `*_wide*.RData` | 另写一套波次映射导致 ID/time 与主 Change 表对不上 |
| 角色分工 | medical-blocks 只负责**编排与表壳**（S9–S17.1 目录/命名对齐髋部） | 借编排之便改成与主分析不同的统计口径 |

**可对上的操作定义：**

1. **主分析复现锚点（过滤前）**：在未做三场景过滤时，用同一 AfterMI + 同一 Model1/Model2 + 同一三分位方法跑 logistic，切点与 OR 方向/量级应能对上交付 `Step02_Logistic/Table 2-*.xlsx`（允许四舍五入与软件包细微差异；不允许切点体系或协变量集整体换掉）。
2. **敏感性相对主分析**：三场景只改变纳入 ID（共病 / **未插补 listwise 完整病例** / ≤2 年发病），其余（变量、模型、三分位算法、年份）不变；FILTER_NOTE 记录 n_before→n_after，便于对照主表 n。完整病例允许 N &lt; AfterMI，不以同 N 为目标。
3. **Change**：同一套 wide/long 与主分析 Step05；敏感性 = 主 Change 样本 ∩ 场景保留 ID。

锚点交付路径（只读对照，不改其中代码）：

`/mnt/g/ftp/交付项目备份/临床交付项目及代码/141 痴呆 交叉滞后 姜小胖/姜小胖_痴呆20260203 - 副本/`

## 2. 范围与非目标

### 范围内

| 项 | 决定 |
|----|------|
| 场景 | `exclude_chronic_ge2`、`complete_case`（**组 B：插补前 dabiao + 分析变量 listwise，允许 N&lt;AfterMI**）、`exclude_event_le_2y` |
| 队列 | CLHLS、SHARE、HRS、ELSA（四库；不含 CHARLS） |
| 暴露 | `Leisure_activities` |
| 结局 | `Disease` → 统一为 `Disease_Group`：`Normal` / `Dementia`；case 标签 = `Dementia` |
| Model1 | `Age + Education + Alcohol_drinking`（四库共用） |
| Model2 | `Age + Education + Alcohol_drinking + Hypertension + Total_Cholesterol + HDL`（四库共用） |
| 三分位 | 各库各自 `quantile(probs = c(1/3, 2/3), na.rm = TRUE)` + `cut(breaks = c(-Inf, c1, c2, Inf), right = FALSE, labels = T1/T2/T3)`（对齐交付 `C01_LogisticCode_new_3.R`） |
| 表号 | S9–S17.1（文案中 FI/Hip fracture → Leisure_activities/Dementia） |

### 非目标

- 主分析 phase1/2/3 全量重跑（主分析已在交付项目完成；本批只做敏感性）
- CLPN / network bootstrap
- competing_risk
- 旧 Step09 的中位数二分 logistic（与主分析三分位不一致，弃用）
- 把 CHARLS 纳入本批敏感性
- 任何与主分析平行的「第二套」插补/切点/协变量/波次定义

## 3. 方法选择

采用**扩展 medical-blocks 现有敏感性管线**（`phase_sensitivity.R` + `R/cross_lagged_sensitivity.R`）做编排与表输出，**统计口径锁定痴呆主分析**（Step02 三分位 logistic + Step05 Change 年份/数据），而不是在 NAS 另写一套、也不是照搬髋部 FI 默认。

理由：表号/目录与髋部同构便于交付；数据与方法与姜小胖主分析连续，敏感性结果可解释为「同一分析在收紧样本后是否稳健」。

## 4. 架构

```
study_root (Dementia)
├── data/Step01_RawData/     # AfterMI / dabiao / 痴呆随访 CSV 来源
├── code/Step05_Change/      # 年份与 wide 参考；可复用 *_wide*.RData
├── sensitivity/
│   ├── exclude_chronic_ge2/{CLHLS,SHARE,HRS,ELSA}/
│   ├── complete_case/...
│   ├── exclude_event_le_2y/...
│   └── README_sensitivity.txt
└── summary_result/table/    # S9–S17.1 汇总副本
```

入口：

```bash
Rscript run/cross_lagged/run_cross_lagged_frailty.R \
  --phase sensitivity \
  --study-root "/mnt/g/02block_result/20_Dementia/cross-laged_40595747"
```

或直接：

```bash
Rscript Blocks/54_cross_lagged_full/phases/phase_sensitivity.R \
  --study-root "/mnt/g/02block_result/20_Dementia/cross-laged_40595747"
```

可选：`--only CLHLS,HRS`、`--scenario exclude_chronic_ge2`。

## 5. 组件与改动点

### 5.1 `R/cross_lagged_sensitivity.R`

1. **表名模板参数化**  
   `cross_lagged_sens_table_basename` 不再硬编码 `FI` / `Hip fracture`；改为读 study 元数据（或函数参数）：
   - `index_display` 默认可仍为 FI；Dementia 传 `Leisure_activities`
   - `disease_display` 默认 Hip fracture；Dementia 传 `Dementia`
   - Change 标题：`Mean Leisure_activities and Leisure_activities change`

2. **数据加载适配 Dementia 布局**（在现有 phase1/data/harmonized 路径之后 fallback）：
   - 插补后：`data/Step01_RawData/D01_AfterMI_Data_{db}.RData`（对象 `data_imp`）
   - dabiao：`data/Step01_RawData/D01_dabiao_{db}.RData`（对象名按文件实际探测：`dabiao` / `data_imp` / 首对象）
   - 文件名大小写别名：`ELSA`/`elsa`、`SHARE`/`share`、`CLHLS`/`clhls`、`HRS`/`hrs`

3. **结局标准化**  
   加载后若存在 `Disease` 而无规范 `Disease_Group`：  
   - character/factor：`Dementia`→case，其余非缺失→`Normal`  
   - 0/1：`1`→`Dementia`，`0`→`Normal`  
   写入 `Disease_Group`，供 baseline/logistic 使用。

4. **协变量锁**  
   Dementia 无 `phase3_relock_acceptance.txt` 时，写固定锁文件（实现时生成）：

   ```
   Model1=Age+Education+Alcohol_drinking
   Model2_single=Age+Education+Alcohol_drinking+Hypertension+Total_Cholesterol+HDL
   ```

   `cross_lagged_sens_read_lock` 优先读该文件；缺省时 Dementia study 也可用上述硬默认（由 phase 检测 disease_code/study 元数据触发）。

5. **纵向 / early-event（优先复用主分析产物，禁止 silently 另造）**  
   - 优先顺序：`data/Step01_RawData/D05_long_{db}.RData` → `code/Step05_Change/*_wide*.RData` → 交付项目同名 long/wide（只读复制进 study 或直接读路径）  
   - 仅当上述均不存在时，才按 C00 年份从痴呆 CSV **按主分析同规则**重建最小 long；重建脚本必须记录来源与 n，并与主分析 wide 的 ID 交集校验  
   - Change：必须用与主分析同一套 wide；缺则该库 Change 跳过并 FILTER_NOTE，**不得**用另一套 change 定义凑表

### 5.2 `phases/phase_sensitivity.R`

1. `.cohorts` 可配置：Dementia 默认 `c("CLHLS","SHARE","HRS","ELSA")`；髋部保持 `CHARLS,ELSA,HRS`
2. `.make_base_config`：
   - `disease` / `disease_code` / `analysis_group` / `reference_group` 按 Dementia：`Dementia` / `20` / `Dementia` / `Normal`
   - `index_var` = `Leisure_activities`（logistic / incidence / prediction）
3. Change block：`outcome_event_level = "Dementia"`；`scheme = "tertile"`；协变量 = Model2
4. Change 合并：四库路径向量（缺库跳过，合并已成功库）
5. `competing_risk = FALSE` 保持

### 5.3 共病 stems（exclude_chronic_ge2）

沿用默认短码解析；Dementia after_mi 有临床名列时映射到：

- Hypertension → hibpe  
- Diabetes → diabe  
- Cancer → cancre  

其余 stems（arthre/lunge/psyche/memrye）列不存在则不计。`chronic_min_count = 2`。

### 5.4 随访年份（early-event / Change 对齐 C00）

| 队列 | 基线年 | 随访年 |
|------|--------|--------|
| HRS | 2010 | 2012, 2014, 2016 |
| SHARE | 2015 | 2017, 2019, 2021 |
| CLHLS | 2008 | 2012, 2014 |
| ELSA | 2008 | 2014 |

`exclude_event_le_2y`：首次发病年 − 基线年 ≤ 2 则剔除该 ID。

## 6. 产出表清单

每个场景 × 每库：

- `Table S{9|12|15}-{DB}. Sensitivity … — Baseline characteristics of Dementia.xlsx`
- `Table S{10|13|16}-{DB}. Sensitivity … — Logistic regression Leisure_activities and Dementia - tertile (GLM).xlsx`

每场景合并（四库）：

- `Table S{11|14|17}. … — Change analysis Mean Leisure_activities and Leisure_activities change.xlsx`
- `Table S{11.1|14.1|17.1}. …`（twowave）

另：每库 `FILTER_NOTE.txt`；根目录 `README_sensitivity.txt`。

目录：`sensitivity/<scenario>/<DB>/Tables/`，并复制到 `summary_result/table/`。

## 7. 数据流

```
AfterMI / dabiao / long
    → 场景过滤（共病 / complete.case / ≤2y）
    → 标准化 Disease_Group + 锁 Model1/2
    → baseline_binary → promote S9/S12/S15
    → logistic_tertile_glm（库内三分位）→ S10/S13/S16
    → change_logistic（过滤后 ID ∩ wide）→ per-db rds
    → build S11/S14/S17 (+ .1)
    → sync summary_result
```

## 8. 错误处理

- 某库缺 AfterMI / dabiao：该库该场景跳过，cli 警告，不中断其余库
- complete_case 后 n < 分析最小阈值：跳过 logistic/change，FILTER_NOTE 记录
- Change 缺 wide：跳过该库 Change，合并表仅含成功库；若 0 库成功则跳过 build
- 列名缺失（Model2 某变量）：complete_case 只用存在列；logistic 由既有 block 报错并 catch 为警告

## 9. 验证

### 9.1 与主分析对得上（优先于表壳检查）

1. **数据身份**：各库 AfterMI `nrow` 与交付 Step01 一致（已核：四库一致）；实现时在 README 打印路径与 n  
2. **过滤前锚点**：对 ELSA（及至少再抽一库）在无场景过滤下复现三分位切点算法与 Model2 footnote，对照 `Step02_Logistic/Table 2-*.xlsx`；切点允许因 `cut`/`round` 显示差 0–1，但不得变成另一套分位  
3. **敏感性相对主表**：FILTER_NOTE 的 n_before 应等于主分析 AfterMI n（该库）；n_after < n_before 且排除原因可解释  
4. **Change ID**：场景保留 ID ⊆ 主分析 wide ID；合并 Change 表队列名与主 Step05 一致

### 9.2 表壳与跑通

5. 冒烟：`--only ELSA --scenario exclude_chronic_ge2` 产出 Table1 + logistic +（若有 wide）Change  
6. 四库 × 三场景：S9–S17.1 存在且非空（缺 wide 的 Change 允许缺，但须在 README 标明）  
7. 与髋部对照：目录/表号/双 Change 表（含 .1）同构；文案为 Dementia / Leisure_activities

## 10. 实现边界

- 优先最小改动：loader fallback + 元数据参数 + cohorts/config 分支
- 统计口径以痴呆主分析为准；髋部管线只提供表号与编排
- 不重构无关 blocks
- 不修改交付项目旧代码；新结果只写 Dementia study_root 的 `sensitivity/` + `summary_result/`
- 若实现中发现 medical-blocks 默认与主分析冲突，**改默认以迁就主分析**，并在 FILTER_NOTE / README 写明差异已消除
