# Design: 两阶段 Transformer 接入 eICU 真小时长表（方案 A）

**日期**：2026-08-28  
**状态**：用户已口头确认方案 A（2026-08-28）；本文件待书面审阅后进入 implementation plan  
**文献**：Yang et al. 2025 *Precision Clinical Medicine* pbaf003（`adversarial_lit_reading/papers/两阶段transfomer.pdf`）  
**课题数据**：`G:/02block_result/33_AKI/two_stage_transformer_40041421/data/eicu/`  
**不动**：卒中 MIMIC 日宽表默认路径（`lab_format` 缺省仍为 `mimic_day_wide`）

---

## 1. 目标与非目标

### 目标

- 按原文 Methods 把 **eICU 小时长表**接到现有 TST 流水线，产出真 `X(n, D=5, H=24, F)`，**不再**用日快照广播假小时。
- 为 `33_AKI` 课题写可跑 config + 最小队列胶水（dabiao / 院内死亡 / LOS≥24h）。
- 卒中课题现有行为不变。

### 非目标

- 不把特征数强行扩到原文 226（本课题以小时表实际 item 为准，覆盖率筛选后 F≤59）。
- 不重写模型架构 / focal loss / SHAP（已对齐原文）。
- 不在本轮补齐 eICU 原始 `offset` 级 nearest（输入已是按 hour 聚合的长表；值列用 `mean`，脚注标明）。
- 不改 `01–70` 旧 Blocks；只扩展 `71_*` 与 `python/two_stage_transformer/prepare.py`。

---

## 2. 原文规则（证据绑定）

| # | 规则 | 原文位置 | 流水线落点 |
|---|------|----------|------------|
| R1 | 按 ICU 入院时间轴整理 | Methods · Data preprocessing | 小时表 `hour` 已相对入科；`day = hour%/%24+1`，`hour_in_day = hour%%24` |
| R2 | 每天 24 小时槽；槽内取可用值 → 24×F | 同上「nearest available」 | 长表 pivot；空槽靠前向填；`expand_hours=FALSE` |
| R3 | 主看前 5 天；>5 天 sliding window | 同上 | 既有 `prepare.py` sliding；保持 |
| R4 | 时序 forward imputation；静态 RF | Missing data and filling | R：`temporal_forward_fill`；静态：既有 `imputation$method=rf` |
| R5 | 不足 5 天 day mask | Model architecture | 既有 `day_mask` |
| R6 | ICU&lt;24h 排除；记录缺失&gt;30% 排除 | Fig 1 / Methods | cohort：`unitlosday≥1`；timeseries：特征/患者 30% 阈值 |
| R7 | 院内死亡 = 出院 disposition | Methods | `hospdischargestatus`：Expired=1，Alive=0；空/未知剔除或标缺失后排除 |
| R8 | 7:2:1 患者级划分 | Methods | 既有 `tst_split` / prepare split |

**【证据不足 / 降级说明】**  
原文 nearest 基于 eICU `offset` 逐点选最近值。本课题 CSV 已是 `(patient, item, hour, mean/min/max/median)`，**无原始 offset 事件流**。实现约定：每个已有 hour 行用 **`mean` 作为该小时槽观测**；缺失小时槽仅 **forward-fill**（不后向填）。脚注写入 `tst_timeseries$note` 与发表表注。

---

## 3. 数据现状（已核验）

| 文件 | 角色 | 关键字段 |
|------|------|----------|
| `D01_baseline_EICU_ICU_first_0626.RData` | 基线池 | `baseline` · `ID` · n≈158442 |
| `EICU预后数据-all.csv` | 预后 | `patientunitstayid`, `hospdischargestatus`, `unitlosday`, … |
| `eicu_hourly_labs_vitals_AKI.csv` | 小时长表 | `patientunitstayid,item,hour,mean,…` · **634** 人 · hour 0–239 · 59 items |

ID 交集：hourly ∩ baseline ∩ prognosis = **634 / 634**。  
小时队列死亡：Alive 465 / Expired 164 / 空 5。

---

## 4. 架构与数据流

```
baseline RData + EICU预后 + eicu_hourly_labs_vitals_AKI.csv
        ↓
[预写 dabiao.csv]  unique(hourly.patientunitstayid) → patientunitstayid 列
[预后派生表或 cohort 内派生]
  is_hosp_dead = (hospdischargestatus=="Expired")
  icu_day      = unitlosday
  排除 unitlosday < 1（≈ ICU <24h）
        ↓ 共享层
data_clean → column_mapping → tst_cohort(dabiao∩预后)
        → tst_timeseries(lab_format=eicu_hourly_long)   ★ 本设计核心
        → imputation(rf) → baseline_binary
        → tst_landmark → tst_split → checkpoint
        ↓ workers
prepare(expand_hours=FALSE, 真小时槽) → train A1/A2/B/…
```

**配置开关（单一事实来源）**

```r
config$tst_timeseries$lab_format <- "eicu_hourly_long"  # 默认 "mimic_day_wide"
config$tst_timeseries$value_col  <- "mean"              # 可选
config$tst_stroke$expand_hours   <- FALSE
config$data$id_column            <- "patientunitstayid"
config$tst_cohort$dabiao_join_key <- "patientunitstayid"
config$data$outcome_column       <- "is_hosp_dead"      # 派生后列名
```

---

## 5. 组件改动

### 5.1 `02block_tst_timeseries.R`（扩展，不破坏默认）

- 读 `lab_format`：
  - **`mimic_day_wide`**（默认）：现有逻辑不变。
  - **`eicu_hourly_long`**：
    1. `fread` 长表；校验列 `patientunitstayid|stay_id`、`item`、`hour`、`value_col`。
    2. 限制 hour ∈ [0, max_export_day×24−1]。
    3. `dcast` / pivot：`item → 列`，值=`mean`（或 config）。
    4. `day = hour %/% 24 + 1`；导出列 `hour` 写 **日内小时 0..23**（或统一 1..24，与 prepare 约定一致；见 5.2）。
    5. 与 `tst_cohort` 内连接；day1（hour 0–23）缺失率筛特征；前 `patient_missing_days` 天筛患者（阈值同现逻辑）。
    6. **按 patient × (day, hour_in_day) 升序 forward-fill**（比日级更细，对齐 R4）。
    7. 导出 `_tst_hourly_long.csv`：`patient, day, hour, <feats>, label, los_days`；**每个患者每天最多 24 行**（有观测或 ffill 后仍可只写有 mask 的日；空日可不写行，由 prepare 的 day_mask 处理）。

### 5.2 `python/two_stage_transformer/prepare.py`（真小时）

当前 `expand_hours=False` 只把日向量塞进 **最后一小时槽**——对真小时错误。

改为：

- 新增 `_patient_day_hour_table`：当 CSV 在同一 `patient×day` 下存在多个 `hour` 时，构建 `day → (H,F)`。
- `_expand_windows`：
  - `expand_hours=True`：保持日向量广播（卒中兼容）。
  - `expand_hours=False`：写入对应小时槽；缺槽保持 0（R 侧已尽量 ffill）。
- `hour` 列约定：**日内 0–23**（与 eICU 长表 `hour%%24` 一致）。若检测到 `hour>=24` 且同日仅一行，回退旧「日终点」语义（兼容卒中导出 `hour=day*24`）。

### 5.3 `01block_tst_cohort.R`（eICU 键兼容）

- `dabiao_join_key` / prognosis ID 候选增加 **`patientunitstayid`**。
- 若预后无 `is_hosp_dead` 但有 `hospdischargestatus`：在块内派生（或要求预生成派生 CSV——实现时优先 **块内派生**，减少手工文件）。
- LOS：优先 `icu_day` / `unitlosday` / `hosp_day`。
- 纳排：`unitlosday < 1`（或 `icu_day < 1`）剔除，对齐 R6。
- `admission_time_column`：eICU 预后无 `icu_intime` 时允许缺失时间零点列，landmark 仅靠 LOS（既有 landmark 已用 los_days）；缺时间戳时日志标明【场景迁移】。

### 5.4 课题侧（`33_AKI/...`）

- 生成 `data/eicu/dabiao.csv`（`patientunitstayid`）。
- 新增 `config_two_stage_transformer_stroke_task_parallel.R`（或隔离 `config.R`）：指向 eicu 三件套 + 上述开关；`disease_code=33`；`database=EICU`。
- 产出根：`.../33_AKI/two_stage_transformer_40041421/`（与卒中同模式）。

### 5.5 决策树 / 模板（可选本轮）

- `Decisiontree` 或 STUDY.md 补一句：`lab_format=eicu_hourly_long` + `expand_hours=FALSE`。
- 5006 isolation 模板增加注释示例；**不强制**改默认占位。

---

## 6. 错误处理与门控

- 长表与队列 ID 交集为 0 → `PAUSE_FOR_USER_DECISION`（同现逻辑）。
- `lab_format` 未知 → pause。
- 覆盖率后 F=0 或患者=0 → pause。
- `expand_hours=FALSE` 但 CSV 每日仅 1 行且 hour=day×24 → 打印警告，走兼容分支（卒中）。
- 空 `hospdischargestatus` 的患者不进分析集。

---

## 7. 测试计划

1. **单元**：用 2 个假患者的 eICU 风格长表 → R 导出 → prepare `expand_hours=FALSE` → 断言 `X.shape == (n,5,24,F)` 且同日内不同小时值不全相等。
2. **回归**：卒中既有 `_tst_hourly_long.csv` + `expand_hours=True` 形状与死亡率与改前一致（抽样 smoke）。
3. **课题**：`33_AKI` `--shared-only` 跑通至 `tst_split`；日志含 `lab_format=eicu_hourly_long`、`expand_hours=FALSE`、保留特征数、634→入选 n。
4. **单 unit**：`--only-unit L72_B_twostage`（需 GPU/时长，可后置）。

---

## 8. 实现顺序

1. `prepare.py` 真小时写入 + 兼容分支  
2. `02block_tst_timeseries.R` 分支 `eicu_hourly_long`  
3. `01block_tst_cohort.R` eICU 键 / 结局派生 / LOS&lt;1  
4. 写 `dabiao.csv` + AKI config  
5. `--shared-only` 冒烟 → 再开 worker  

---

## 9. 风险

| 风险 | 缓解 |
|------|------|
| F≪226，与原文不可直接数值对标 | literature_validate 标「特征集场景迁移」 |
| 用 mean 非 offset-nearest | 脚注；若日后有事件流再换 value 规则 |
| 小样本 634、7:2:1 分层不稳 | 允许 stratify 失败回退；日志记录 |
| cohort 改动影响卒中 | 仅扩展候选列与条件派生；卒中路径单测/冒烟 |

---

## 10. 验收标准

- [ ] 卒中默认 `mimic_day_wide` + `expand_hours=True` 行为不变  
- [ ] AKI config 下导出长表为 **真小时行**（同 patient×day 多 hour）  
- [ ] npz `X` 的 H 维在至少部分特征上 **小时间有变异**  
- [ ] shared-only 成功；flowchart / coverage audit 落盘  
- [ ] 表注/note 写明 Grouping 无关本套路，但写明 `lab_format` 与 mean/forward-fill 约定  
