# 交叉滞后 · 门诊队列 HAMD / HAMA / C-SSRS（Index → 1st）— 设计规格

> 状态：已确认（2026-09-20）  
> 产出根：`\\192.168.68.133\02block_result\43_Suicide\cross-laged_40595747`  
> WSL 访问：经 Windows UNC / 挂载到本地后操作；原始 RData 在 `data/RDATA/RDATA/`  
> 方案来源：`方案(1).docx`  
> 架构选择：**做法 B** — CLPM 主路径（不硬套三库 frailty 全流程）  
> C-SSRS 节点：**① item1 二分类**（有无自杀意念）

## 0. 已确认决策

| 项 | 选择 |
| ---- | ---- |
| 分析架构 | **B**：单队列两波交叉滞后（CLPM）为主；不跑三库 Pooled / Country / FI 分位闸门 |
| 队列 | **仅门诊入组**；病房同规则另跑，标 Exploratory，不进主文 |
| 时点 | **Index**（出院前约 3 天）→ **1st**（出院后约 1 月）；Baseline 量表不进节点 |
| 情绪节点 | 连续：`HAMD_index_all` / `HAMD_1st_all`；`HAMA_intex_all`（现列名）/ `HAMA_1st_all` |
| 自杀风险节点 | **C-SSRS Ideation item1** 二分类：Yes=1，No=0；列名 Index / 1st 分别对应清洗后的 Ideation\_\*\_1 |
| 暴露/疾病缺失 | **六节点任一缺失 → 删例，禁止 MICE**；仅协变量可插补 |
| 与引擎关系 | 复用 prep / Table1 / UV-VIF / 发表导出思路；**不**一键 `run_cross_lagged_frailty.R --batch` 全套出版槽位 |
| 开跑条件 | 本 spec 用户确认 + 实现计划确认后才开跑 |

## 1. 研究问题

在门诊队列中，基于 Index → 1st 两波面板，估计抑郁、焦虑与自杀意念（C-SSRS item1）之间的：

1. **自回归**：症状/风险自身稳定性；  
2. **交叉滞后**：情绪是否净预测后续自杀意念；自杀意念是否阻碍后续情绪改善；焦虑与抑郁是否互相预测。

主文结论绑定预注册路径（见 §5），不以三库发病式 logistic 为主分析。

## 2. 为何不套 frailty「全流程」

现有 `cross_lagged_frailty` 出版清单依赖：多库横断面暴露→疾病、Pooled+Country、logistic 分位闸门、社区随访敏感性（慢性病≥2、2 年内发病等）。

本课题为**单中心临床随访 + 三症状互为节点**，上述槽位多数无对象。硬套会制造与方案不符的「假暴露→假疾病」主文。

**做法 B** 只保留与方案一致的块：纳排 / Table1 / 协变量锁定 / 两波路径 / 相关或简易网络 / 课题适配敏感性。

## 3. 数据与目录

```
cross-laged_40595747/
├── data/
│   └── RDATA/RDATA/
│       ├── 01RawData/          # D01–D24；含 D07/08/10 的 baseline/index/1st
│       ├── 02*table1/          # 既有合并脚本（参考）
│       └── 03*Cssrs_hama_hamd/ # QC；须先修 1st 文件指向
│   └── harmonized/             # 【新建】prep 产出 dabiao
├── checkpoints/
├── summary_result/             # 本课题精简槽位（见 §6）
├── config_*.R
└── CROSS_LAGGED_SYNC_ROOT      # 可选
```

原始清洗入口：`01RawData/01_import_data.R`（患者类别：1=门诊，2=病房）。

### 3.1 Prep 硬门槛（开跑前必须修）

`03…/C01_MI_baseline.R` 当前把 **1st 误读为 Index 文件**（`D10_C_SSRS1` / `D07_HAMA1` / `D08_HAMD1`）。  
正确应为：`D10_C_SSRS2`、`D07_HAMA2`、`D08_HAMD2`。  
不修则两波同表，交叉滞后无效。

### 3.2 节点列定义

| 逻辑名 | 来源 | 类型 | 规则 |
| ---- | ---- | ---- | ---- |
| `HAMD_Index` | `HAMD_index_all` | 连续 | 缺失→该例删除 |
| `HAMD_1st` | `HAMD_1st_all` | 连续 | 同上 |
| `HAMA_Index` | `HAMA_intex_all`（拼写保留源列，分析统一别名） | 连续 | 同上 |
| `HAMA_1st` | `HAMA_1st_all` | 连续 | 同上 |
| `CSSRS_Index` | Index 波 `C_SSRS_Ideation_index_1`（或清洗后等价列） | 0/1 | Yes→1，No→0；缺失删除 |
| `CSSRS_1st` | 1st 波 Ideation item1 | 0/1 | 同上 |

节点命名在 dabiao 中统一为上表逻辑名；Methods 写清 C-SSRS **仅 item1**，不合并 item2–5、不合并行为/企图条目。

## 4. 纳排与插补

### 4.1 逐步纳排（Fig1）

1. 基线有 `新编号`  
2. `患者类别 = 门诊入组`  
3. 六节点均非缺失（及 CSSRS item1 可编码为 0/1）  
4. 可选：关键人口学（如 sex）缺失则删（与现 import 一致）  
5. 对剩余样本：仅对**协变量**做 MICE  

病房：重复 2–5，产物标 Exploratory。

### 4.2 插补铁律

- **禁止**对六节点、以及对任何以节点为「暴露/疾病」的附属分析中的暴露/结局列做 MICE。  
- 实现：插补前 listwise 完整六节点；`exclude_from_mice_cols` 含全部节点列。  
- 协变量候选：人口学、病程/首发、用药与治疗相关、生活方式等（prep 后列审阅落盘 `Data/_column_review.md`；疾病泄漏列进 `analysis_exclusion`）。

## 5. 主分析路径（预注册）

控制锁定 Model2 协变量后估计：

**自回归（3）**

- `HAMD_Index → HAMD_1st`  
- `HAMA_Index → HAMA_1st`  
- `CSSRS_Index → CSSRS_1st`

**交叉滞后（6）**

- `HAMD_Index → CSSRS_1st`（控 HAMA_Index、CSSRS_Index）  
- `HAMA_Index → CSSRS_1st`（控 HAMD_Index、CSSRS_Index）  
- `CSSRS_Index → HAMD_1st`（控 HAMD_Index、HAMA_Index）  
- `CSSRS_Index → HAMA_1st`（控 HAMA_Index、HAMD_Index）  
- `HAMD_Index → HAMA_1st`  
- `HAMA_Index → HAMD_1st`

模型形式：

- 连续因变量：线性模型（报告标准化 β）  
- `CSSRS_1st`：logistic（报告 OR）  
- 可选：同一结构方程/路径模型汇总图（样本与软件允许时）

多重比较：主文报告上述 9 条；其余为探索并标注。

## 6. 发表产物（精简槽位）

相对 `PUBLICATION_SLOTS.md` **裁剪**，本课题只强制：

| 槽位 | 内容 |
| ---- | ---- |
| Fig1 | 门诊纳排流程图（逐步 n + 排除数） |
| Table1 | 基线特征（可按 Index CSSRS 分层或总体+分层附录） |
| Table2 / 主表 | 交叉滞后路径汇总（β/OR + 95%CI + P） |
| Fig2 | 路径示意图（自回归 + 显著交叉滞后） |
| S1 | 插补前后协变量；节点不参与插补的说明 |
| S2 | 相关矩阵（Index/1st 节点） |
| S3 | 病房 Exploratory 路径表（若跑） |
| README | 口径：门诊主分析；item1；六节点完整病例 |

**明确不做（除非用户后开）**：三库 Pooled、RCS 分位闸门、社区 S9–S17.1 慢性病/2 年内发病套件、CLPN 1000 bootstrap 社区 frailty 网络默认。

## 7. 组件与实现边界

| 产物 | 动作 |
| ---- | ---- |
| `scripts/prep_cross_lagged_suicide_cssrs.R` | 合并门诊 dabiao；修 1st 指向；编码六节点；QC n |
| 研究区 `config_*.R` | 单 unit；`outcome`/`index` 按附属分析需要配置；主分析读节点列 |
| `R/cross_lagged_study_meta.R` | 登记 `kind = "suicide_cssrs"`（grouping 若无分位主分析可固定为 `binary` 仅节点） |
| 路径估计脚本或 block | 优先挂 `54_cross_lagged_full` 可复用相关/图块；CLPM 主表可新建薄脚本，**不**新建 `Blocks/NN_*` 大目录 |
| 决策树 | `Decisiontree/decision_tree_cross_lagged_suicide_cssrs.md` |

## 8. 验收标准

- [ ] 1st 文件指向已修正，QC 显示 Index 与 1st 非同一对象  
- [ ] 门诊 Fig1 逐步 n 可追溯；六节点完整 N 写入 Methods  
- [ ] 节点列未进入 MICE；协变量可插补  
- [ ] 主表含预注册 9 条路径，CSSRS 终点为 item1 OR  
- [ ] 病房结果（若有）不与主文混表  
- [ ] 未输出 frailty 三库默认空壳槽位冒充完成  

## 9. 非目标

- 不把 Baseline HAMA/HAMD/CSSRS 作为主节点（门诊 Baseline 完整率过低）  
- 不用 item2–5 并集或行为条目做主节点（已否决 ②/③）  
- 不开跑完整 `run_cross_lagged_frailty.R --batch` 作为本课题定义的「成功」  

## 10. 开跑门控

用户确认本文件后 → 写实现计划 → 用户确认计划 → 再 prep / 跑分析。  
**在用户明确说可以跑之前，不开全流程。**
