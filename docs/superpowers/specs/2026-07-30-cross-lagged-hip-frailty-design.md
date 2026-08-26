# 交叉滞后 · 髋部骨折 × 虚弱（三库 + Pooled）— 设计规格

> 状态：已确认（2026-07-30）  
> 产出根：`G:/02block_result/16_Hip fracture/cross-laged_40595747`  
> WSL：`/mnt/g/02block_result/16_Hip fracture/cross-laged_40595747`  
> 方案：**方案 1** — 发病式横断面（三单库）+ VIF 后接 Pooled（rbind）+ 纵向扩展块  
> 文献 PMID：`40595747`

## 0. 已确认决策

| 项 | 选择 |
| ---- | ---- |
| 四「库」 | CHARLS + ELSA + HRS + **Pooled**（Pooled = 插补后个体 `rbind`，非 meta） |
| Pooled 时机 | **多因素 → VIF final 之前不跑 Pooled**；logistic / RCS / 亚组 / 纵向中介等之后才进 |
| Pooled 拼法 | 各库插补后 `data_imp` rbind；`Country`：CHARLS=`China`，ELSA=`UK`，HRS=`America` |
| Pooled 协变量 | **必须含 `Country`**；Model1 至少 `Age + Gender + Education + Country` |
| 暴露 | 连续 `FI`（已在 0–1，一般不再除）；二分 `Frailty = I(FI ≥ 0.25)`；**不用** `AIP_FI` |
| 结局 | 髋部骨折；`Disease_Group`：`1`=病例，`0`=对照 |
| 横断面基线波 | CHARLS=2011，ELSA=wave2(2004)，HRS=2012 |
| 纵向中介时序 | **A**：X=基线 FI，M=中间波抑郁，Y=更晚波骨折 |
| Table 1 | **只放连续 `FI`**（二分不进表）；以 FI 组间显著为目标；不显著告警、不默认 stop |
| 架构 | 发病套路前半 + 自有纵向脚本 block 化挂尾；中介进 `Blocks/20_mediation/`；不新建模块目录 |
| 引擎 | 改决策树 / config / run（cross_lagged）；新增/替换相关 block；审查并去重用户 C0* 脚本逻辑 |

## 1. 研究问题

在 CHARLS / ELSA / HRS 中评估 **基线虚弱（FI）** 与 **髋部骨折** 的关联：

1. 横断面（发病式）：单库 Table 1 → 单多因素 → VIF →（拼 Pooled）→ 四路 logistic / RCS / 亚组；
2. 纵向：交叉滞后相关图/网络/森林等 + **纵向中介**（抑郁为中介，X→M→Y 严格时序）。

## 2. 架构与数据流

```
data/{CHARLS,ELSA,HRS}/
  D01_baseline_* + 虚弱_*.csv(FI) + D03_result_*(Disease_Group)
  data/medition/*抑郁*.csv
        ↓ prep
data/harmonized/
  D04_CHARLS_hip_baseline.RData  (dabiao)
  D04_ELSA_hip_baseline.RData
  D04_HRS_hip_baseline.RData
  qc_summary.*
        ↓ 阶段 A（仅三单库，到 Table 1）
data_clean → column_mapping → index(FI) → imputation → trim
→ baseline_binary（Table 1：含 FI，检验组间）
        ↓ 阶段 B（仅三单库）
UV → VIF screen → multivariate → resolve → VIF final
→ 锁定 Model2Factors（三库临床交集）
        ↓ 阶段 C
rbind 三库插补表 + Country → Pooled
Model2_Pooled = 锁定临床协变量 ∪ {Country}
        ↓ 阶段 D（四路：CHARLS/ELSA/HRS/Pooled）
logistic_* → RCS → 亚组 …
        ↓ 阶段 E（纵向）
长表/宽表准备 → 相关/网络/图 → 纵向中介 + 中介图
```

### 硬约束

- 分析对象名统一 `dabiao`；结局列 `Disease_Group`；暴露连续列 `FI`；二分列 `Frailty`（可下游用，Table 1 不展示）。
- Pooled **禁止**进入：`data_clean` … `multicollinearity_*_final`。
- 中介必须纵向：禁止用横断面 `mediation_incidence` 作为本套路主中介；新块读纵向 X/M/Y。
- 不新建 `Blocks/NN_*` 目录：纵向描述/网络等进现有 `54_cross_lagged_full/`；中介进 `20_mediation/`。
- Block 格式遵循 `skills/split-medical-block` + 现有 `NNblock_*.R` 文件头 / `register_block` / ctx 契约（仓库内无独立 `BLOCKS_USAGE_GUIDE.md` 时以 split-medical-block + 现有 block 头为规范）。

## 3. 组件

### 3.1 Prep 脚本

路径：`scripts/prep_cross_lagged_hip_frailty.R`（写出到研究目录 `data/harmonized/`）。

职责：

1. 按基线波读 `D01_baseline_*`、对应 `虚弱_*.csv`、`D03_result_*`；
2. 统一 ID（CHARLS `ID`；ELSA `idauniq`→`ID`；HRS `hhidpn`→`ID`）；
3. 取 `FI`；若发现计数总分且 max>1 而 FI 缺失，则 `FI = total / n_items`；生成 `Frailty = as.integer(FI >= 0.25)`；
4. 合并结局；写出 `dabiao` RData + QC（n、事件数、FI 均值/分位、Frailty 比例、与结局交叉表、FI 组间 P）；
5. **不**在 prep 阶段拼 Pooled（Pooled 在插补后、VIF 后由 run/block 拼）。

### 3.2 Config / Run / 决策树

| 产物 | 动作 |
| ---- | ---- |
| `Decisiontree/decision_tree_cross_lagged_frailty.md` | 重写为发病前半 + Pooled 分叉 + 纵向尾部（逐步 block） |
| `configs/templates/config_cross_lagged_frailty_batch.template.R` | 对齐发病 regular 块序；units=`CHARLS,ELSA,HRS`；Pooled 后置；中介换纵向块 |
| `run/cross_lagged/run_cross_lagged_frailty_batch.R` | 支持三库并行、VIF 后拼 Pooled、四路后段、纵向段 |
| 研究区 config | 复制模板到产出根，指 `data/harmonized/` |

暴露：`index` 指向已有列 `FI`（或 `index$only` / 直读列，避免误算 AIP_FI）。

### 3.3 新/改 Blocks

| Block（拟定名） | 目录 | 来源 | 说明 |
| ---- | ---- | ---- | ---- |
| `mediation_longitudinal`（+ 可选图块） | `Blocks/20_mediation/` | `C01相关性分析-table3.R`、`C04发病-中介.R`、`C05_中介图.R` | 纵向 X/M/Y；`mediation` 包；出表+路径图；审查去重 |
| `cross_lagged_long_prepare` | `54_cross_lagged_full/` | `c00_charls_long2013.R`、`C01.1_Changedata.R` | 长/宽表；基线无病→随访；抑郁合并自 `medition/` |
| `cross_lagged_corr_table` 等 | `54_*` | 森林 / 网络 / bar / Fig1 / Change_Logistic | 一脚本一块或按用途合并；删除与发病块重复的横断面逻辑 |
| 现有 `cross_lagged_mediation*` | `54_*` | — | 本套路 pipeline **不再调用**（保留文件以免影响旧研究） |

Pooled 拼表：优先在 run 层或薄 block `cross_lagged_pooled_bind`（若需要可放 `54_*`），输入三库 `ctx$data$imputed`，输出 Pooled 检查点。

### 3.4 纵向中介时序（默认映射）

| 库 | X（FI） | M（抑郁） | Y（骨折） |
| ---- | ---- | ---- | ---- |
| CHARLS | 2011 | 2013（`medition/CHARLS_2013_抑郁.csv`） | 2015 `Disease_Group` |
| ELSA | wave2 | wave3 抑郁 | wave4 结局（若波次不对齐，以「基线→中间→更晚」最近可用波为准，写入 config） |
| HRS | 2012 | 2014 抑郁 | 2016 结局 |
| Pooled | 各库按上表构造后 rbind + `Country` | 同左 | 同左 |

抑郁列：CHARLS `cesd10_total`→`Depression_cont`；ELSA `cesd8_total`；HRS 以 CSV 实际列名为准，统一映射为 `Depression_cont`。

## 4. 分期交付

| 期 | 范围 | 成功标准 |
| ---- | ---- | ---- |
| **一期（先做）** | Prep + 三库跑到 Table 1 | 三份 harmonized `dabiao`；三份 Table 1；QC 含 FI 组间 P |
| 二期 | UV→VIF→Pooled→logistic/RCS | 四路主表；Pooled 含 Country |
| 三期 | 纵向 prepare + 中介/图 + 其余 C0* block | 纵向中介表+图；脚本逻辑审查与去重 |

## 5. 错误处理与边界

- FI 缺失：与结局 merge 后行删或按发病 `data_clean` 阈值；QC 记录。
- 某库 FI 组间不显著：告警写入 QC，默认继续（用户可后续改 hard-stop）。
- 抑郁波缺失：该库纵向中介 skip + warning，不影响横断面。
- 用户脚本硬编码路径 / `AIP_FI` / 肌少症：block 化时改为 config（`FI`、髋部 `Disease_Group`、研究 data 根）。

## 6. 测试计划

1. Prep dry-run：三库 n、事件、FI 范围∈[0,1]、Frailty 比例合理。  
2. 一期：`--to baseline_binary`（或等价）出 Table 1。  
3. 二期：确认 Pooled 未出现在 VIF 前检查点；Pooled Model 含 `Country`。  
4. 三期：中介 `treat=FI`（或配置暴露名），`mediator=Depression_cont`，结局二分类；路径图导出。

## 7. 非目标（本期不做）

- 不把 SHARE 加回四库实体数据（除非另补数据）。  
- 不以 `AIP_FI` 为主暴露。  
- 不新建顶层 Blocks 编号目录。  
- 不改发病 dual_batch 引擎核心（除非三库编排必须的最小薄封装）。
