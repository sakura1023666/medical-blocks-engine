# 交叉滞后 · ePWV × 昼夜节律 DN（CHARLS + ELSA + NHANES + Pooled）— 设计规格

> 状态：横断面 + CHARLS/ELSA 纵向已跑通（2026-08-17）；实现计划见 `docs/superpowers/plans/2026-08-17-circadian-cross-lagged-epwv.md`  
> 实现备注：无 ELSA wave5 FI → 两波（wave4→6）；中介 M=随访年 FI，与 Y 同年（时序弱化）。CLPN 强制 7 个 condition，零变异条目会被丢掉（CHARLS 剩 4；ELSA 剩 2）。NHANES 无 `phase3_long_*`。  
> 产出根：`G:/02block_result/23_circadian rhythm/cross-laged_40595747`  
> WSL：`/mnt/g/02block_result/23_circadian rhythm/cross-laged_40595747`  
> 方案：**方案 1** — 复用 `cross_lagged_frailty` 套路；暴露改 ePWV；结局改 DN；纵向网络节点改 `condition1–7`  
> 文献套路 PMID：`40595747`（方法同源，结局/暴露不同）

## 0. 已确认决策

| 项 | 选择 |
| ---- | ---- |
| 主方向 | **A**：暴露 = 复合指标，结局 = 昼夜节律 `DN` |
| 指标范围 | **仅 ePWV**；PHR / HHR / UA_CrR **全部不做** |
| 四「库」 | CHARLS + ELSA + NHANES + **Pooled**（三库插补后 `rbind`，非 meta） |
| NHANES | **只做横断面**；禁止进纵向 phase |
| 纵向网络节点 | **仅 `condition1–7`**（不含指标成分、不含 ePWV 得分） |
| 纵向中介 | X=基线 ePWV → M=中间波 FI → Y=更晚波 DN；虚弱不好再开血检 pilot |
| Pooled 时机 | **VIF final 之前不跑 Pooled**；logistic / RCS / 亚组等之后才进 |
| Pooled Country | CHARLS=`China`，ELSA=`UK`，NHANES=`America`；Model 强制含 `Country` |
| 架构 | 发病式前半 + 现有 `54_cross_lagged_full` 纵向尾；不新建 `Blocks/NN_*` |
| 疾病硬排除 | prep 后按 `review-raw-covariate-columns` 落盘 `_column_review.md`；昼夜列不进协变量 |

## 1. 研究问题

在 CHARLS / ELSA / NHANES 中评估 **基线 ePWV** 与 **昼夜节律紊乱（DN）** 的关联：

1. 横断面（发病式）：三单库 Table 1 → 单多因素 → VIF →（拼 Pooled）→ 四路 logistic / RCS / 亚组；
2. 纵向（仅 CHARLS + ELSA）：`condition1–7` 交叉滞后网络 + **纵向中介**（虚弱 FI；失败则血检 pilot）。

ePWV 公式（引擎已有）：

`ePWV = 9.587 - 0.402*Age + 0.00456*Age^2 - 0.00002621*Age^2*MBP + 0.003176*Age*MBP - 0.01832`  
其中 `MBP = DBP + 0.4*(SBP - DBP)`（源列 `NBPS`/`NBPD` 映射为 SBP/DBP）。

## 2. 文件夹布局

```
cross-laged_40595747/
├── data/
│   ├── charls/          # 已有 D01 + 昼夜节律 CSV（2011/2015）
│   ├── elsa/            # 已有 D01 + 昼夜节律 CSV（wave4/wave6）
│   ├── nhanes/          # 已有 D01 + 昼夜节律 CSV
│   ├── medition/        # 抑郁/血检等（中介 fallback）
│   ├── frailty/         # 新建：虚弱 CSV（ID 对齐后可用）
│   └── harmonized/      # prep 产出 dabiao
├── by_index/ePWV/       # 可选：按指标归档运行产物
├── checkpoints/
├── summary_result/
├── config_*.R
└── CROSS_LAGGED_SYNC_ROOT
```

引擎工作区可另有 `Output/23_circadian_...` 镜像；课题盘为权威同步根。

## 3. 架构与数据流

```
data/{charls,elsa,nhanes} + frailty/ + 昼夜节律 CSV
        ↓ prep（ID 对齐是硬门槛）
data/harmonized/
  D04_CHARLS_circadian_baseline.RData  (dabiao)
  D04_ELSA_circadian_baseline.RData
  D04_NHANES_circadian_baseline.RData
  qc_summary.*   # 含 ID 对齐率、DN 事件、ePWV 可算率、FI 合并率
        ↓ 阶段 A（三单库 → Table 1）
data_clean → column_mapping → index(ePWV) → analysis_exclusion
→ imputation → baseline_binary（结局 DN / Disease_Group）
        ↓ 阶段 B（仅三单库）
UV → VIF screen → multivariate → resolve → VIF final
→ 锁定 Model2Factors（三库临床交集）
        ↓ 阶段 C
rbind 三库插补表 + Country → Pooled
        ↓ 阶段 D（四路：CHARLS/ELSA/NHANES/Pooled）
logistic_* → RCS → 亚组 …
        ↓ 阶段 E（仅 CHARLS + ELSA）
long_prepare → condition1–7 网络/相关/森林
→ 纵向中介 ePWV → FI → DN（+ 可选血检 pilot）
```

### 硬约束

- 分析对象名统一 `dabiao`；结局列统一为 `Disease_Group`（由 `DN` 映射：1=紊乱病例，0=对照）或 config 直指 `DN`（二选一，prep 写死一种并全文一致，**默认映射为 `Disease_Group`** 以复用现有 block）。
- 暴露连续列 `ePWV`；可由 `index` block 计算。
- Pooled **禁止**进入：`data_clean` … `multicollinearity_*_final`。
- NHANES **禁止**进入阶段 E 任何纵向 block。
- 网络节点固定 `condition1–7`；不做指标成分网络。
- `analysis_exclusion`：`condition1–7` / `met_count` / `DN`（及映射前同义列）不进协变量池；ePWV 成分（Age/SBP/DBP/MBP）按传递闭包排除。
- 不新建顶层 `Blocks/NN_*`；纵向描述/网络继续用 `54_cross_lagged_full/`；纵向中介用 `20_mediation/` 或现有 longitudinal mediation block。

## 4. 组件

### 4.1 Prep 脚本

路径：`scripts/prep_cross_lagged_circadian.R`（写出到研究目录 `data/harmonized/`）。

职责：

1. 读各库基线 `D01_baseline_*` 与对应波次昼夜节律 CSV；
2. **ID 对齐**（已知风险：昼夜 CHARLS ID 与髋部课题虚弱 ID 格式不一致、当前 0 重叠；必须在 QC 报告对齐规则与合并率，合并率过低则 stop）；
3. 合并虚弱 FI（`data/frailty/`）；生成可选 `Frailty = I(FI ≥ 0.25)`；
4. 列标准化：`PlateletCount→Platelet_Count` 等（本课题主指标不依赖血小板，但仍统一命名）；`NBPS/NBPD→SBP/DBP`；`DN→Disease_Group`；
5. 写出三份 `dabiao` + QC（n、DN 事件数、ePWV 非缺失率、FI 合并率、与结局交叉表）；
6. **不**在 prep 阶段拼 Pooled。

### 4.2 Config / Run

| 产物 | 动作 |
| ---- | ---- |
| 研究区 config | 自 `configs/templates/config_cross_lagged_frailty_batch.template.R` 复制并改：路径、units、`index=ePWV`、`outcome=DN/Disease_Group`、网络节点、中介 treat/mediator/outcome、Country 含 NHANES |
| `run/cross_lagged/run_cross_lagged_frailty.R` | 复用；`--study-root` 指本课题；必要时最小改动支持「网络节点列表 config 化」与「units 含 NHANES 且 long 阶段自动剔除」 |
| `_column_review.md` | 研究 `data/` 下落盘；写入 `analysis_exclusion$disease_vars` |

暴露：`index` enable，计算 `ePWV`（依赖 Age + MBP 链）。

### 4.3 纵向中介时序（默认）

| 库 | X（ePWV） | M（FI） | Y（DN） |
| ---- | ---- | ---- | ---- |
| CHARLS | 2011 | 2013（若无该年 FI 则用最近可用中间波，写入 config） | 2015 |
| ELSA | wave4 | wave5（若无 FI 则最近可用中间波） | wave6 |
| NHANES | — | — | —（不做纵向） |
| Pooled 横断面 | 三库 rbind + Country | — | — |
| Pooled 纵向 | **不做**（或仅 CHARLS+ELSA rbind；默认不做三库纵向 Pooled） | | |

血检 fallback（三期后 pilot）：仅当 FI 中介效应不成立/不稳定时，试用 `medition` 中共有血检；不挡主流程。

### 4.4 网络

- 节点：`condition1` … `condition7`（两波）
- 不纳入 ePWV、不纳入指标成分
- 复用现有 CLPN / network bootstrap phase；改节点名单即可

## 5. 分期交付

| 期 | 范围 | 成功标准 |
| ---- | ---- | ---- |
| **一期（先做）** | Prep + 列审阅 + 三库到 Table 1 | 三份 harmonized；ID/FI 合并率合格；三份 Table 1；ePWV 可算 |
| 二期 | UV→VIF→Pooled→logistic/RCS/亚组 | 四路主表；Pooled 含 Country；NHANES 无纵向产物 |
| 三期 | CHARLS/ELSA：condition1–7 网络 + ePWV→FI→DN 中介 | 网络表/图；中介表；可选血检 pilot |

## 6. 错误处理与边界

- CHARLS/ELSA/虚弱 ID 无法对齐：prep **硬停**并输出对照样例，不静默 0 合并。
- 某库 ePWV 成分缺失导致大面积 NA：QC 告警；若可用 n 低于预设阈值则该库 skip 并报告。
- ELSA 中间波无 FI：改用 config 声明的最近波；仍无则该库纵向中介 skip，横断面继续。
- Table 1 组间不显著：告警、默认继续（与髋部套路一致）。
- 不把已放弃的 PHR/HHR/UA_CrR 写进 batch `only-index`。

## 7. 测试计划

1. Prep：三库 n、DN 事件、ePWV 范围合理、FI 合并率 > 约定阈值（实现计划中写死数字，建议先以 ≥70% 为目标，不足则修 ID）。  
2. 一期：三库 Table 1 产出；`analysis_exclusion` 后协变量无 `condition*`/`met_count`/`DN`。  
3. 二期：Pooled 检查点仅出现在 VIF 后；Model 含 `Country`；NHANES 无 `phase3_long_*`。  
4. 三期：网络节点恰好 7 个 condition；中介 `treat=ePWV`，`mediator=FI`，`outcome=Disease_Group`。

## 8. 非目标（本期不做）

- PHR / HHR / UA_CrR（含 NHANES 单库试跑）。  
- HRS 队列。  
- 指标成分 × 昼夜条目混合网络。  
- 新建顶层 Blocks 编号目录。  
- 改发病 dual_batch 引擎核心（除非三库编排必须的最小薄封装）。
