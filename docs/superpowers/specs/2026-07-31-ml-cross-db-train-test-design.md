# ML 跨库 Train/Test + 选指标表 — 设计规格

> 状态：已实现；RAR 验收通过（2026-07-31）  
> 触发研究：`G:/02block_result/17_pancreatic carcinoma/ml_40395549`（PMID 40395549）  
> 方案：**方案 1** — 在现有 `ml` / `ml_dual_batch` 上增加「跨库一份结果」模式（可复用）  
> 验证范围：改完后 **仅重跑指标 RAR**（删该指标结果与检查点）

## 0. 已确认决策

| 项 | 选择 |
| ---- | ---- |
| 双库结果形态 | **A**：人数多的库整库=训练集，人数少的库整库=测试集；流水线只跑一次，只出一套表/图 |
| 选指标 | **A**：共享层出对比表；**不**自动改 `index_group` / `index_vars` 循环名单 |
| 插补 | **A**：先定 train/test 角色 → **仅在训练集拟合插补** → 变换到测试集 |
| 落地方式 | **方案 1**（改现有 ML 双库批量，不新建平行套路） |

## 1. 问题与目标

### 1.1 现状问题

1. 双库时 **每个库各自 70/30**，再各出一套 ML / SHAP / 基线结果 → 「该出一个结果却出了两个」。
2. 图名二次注入库名（如 `Figure 3-MIMIC IV-MIMIC IV`、`Figure 4. MIMIC_IV. Figure 3-MIMIC IV-...`）。
3. 缺少「现有变量能算哪些复合指标 + 单因素 OR/HR」的可复用选指标表。
4. 统计块与 ML 块对 `data_imp` / 内部分割混用，双库外推语义不清晰。

### 1.2 目标（可复用规则）

下个 ML 双库/多库项目默认可复用同一套规则（config 开关），不必再改研究侧脚本逻辑。

## 2. 架构与数据流

```
共享层（各库）: data_clean → column_mapping → harmonize → index
        ↓
选指标表 block（共享层末 / batch 前）→ Tables/Index_screening_OR_HR.csv
        ↓ 仍按 config 的 index_vars / dual_safe 交集循环
按指标 worker（跨库一份）:
  加载各库共享 checkpoint（含 index）
        ↓
  assign_train_test_roles   # 按 n 定 train / test1 / test2...
        ↓
  imputation_fit_train      # 仅 train 拟合；应用到各 test
  trim_index_extreme        # 规则在 train 上定，应用到 test
        ↓
  ctx$data$data_train / data_test[/data_test2...]
  （单库另保留 data_imp = 插补后全样本，供 logistic/RCS/Cox/KM）
        ↓
  单因素（train，logistic）
  VIF（train + 各 test）
  LASSO 等特征选择（train；特征锁定后用于 test）
  关联：logistic / RCS /（有时间则 Cox+KM）
       单库 → data_imp；双库+ → data_train + data_test*
  ML 模型 + performance + SHAP（train 拟合 / test 评估）
  亚组：OR；有时间则再出 HR
        ↓
  by_index/<指标>/          # 不再按库分子目录各跑全流水线
  Figures/ Tables/ 一套命名（Train vs Test 标签，不叠库名前缀两次）
```

**硬约束**

- 测试集不得参与插补模型拟合、LASSO/特征选择拟合、ML 超参搜索的拟合折外信息。
- 无 `survival$time_var`（或列不存在）时：**跳过** Cox、KM、亚组 HR；OR 路径保留。
- 次库不再跑 `pipeline_mimic_ml_batch` 那套「继承特征 + 再 train_validation」的独立全流程（跨库模式下关闭）。

## 3. 划分规则（`assign_train_test_roles`）

| 库数 | 规则 |
| ---- | ---- |
| 1 | 插补后（或插补流程内）**7:3** 随机划分 → `data_train` / `data_test`；种子来自 `config$seed` / `train_validation$seed` |
| 2 | 比较各库 **分析样本 n**（共享层 index 后、进入 worker 时的行数）；**n 大 = train 库，n 小 = test 库**；整库进入对应槽，**不再库内 70/30** |
| ≥3 | n 最大 = train；其余按 n 降序为 `test` / `test2` / `test3`… |

并列 n：稳定打破（优先 `dual_db$primary`，再按库名字母序），并写入 QC 日志。

输出元数据（写入 checkpoint / `Tables/Train_test_assignment.csv`）：

- `role`, `db_name`, `n`, `n_event`（DN/结局=1）, `seed`（仅单库随机划分时）

## 4. 插补与上下文槽位

### 4.1 插补

- 扩展/改造现有 `imputation` 块（或紧随其后的薄封装）：  
  `fit` 仅用 train 行；`transform` 应用到全部 test 行。
- 单库：先对全样本插补得 `data_imp`，再 7:3 切出 `data_train`/`data_test`（与「插补拟合不看 test」一致的实现：也可「先划角色掩码 → 仅 train 拟合 → 变换全队列」再切片；**优先后者**，避免 test 参与拟合）。

### 4.2 下游默认数据源

| 步骤 | 单库 | 双库/多库 |
| ---- | ---- | ---- |
| 单因素（预后+预测，logistic） | `data_train` | `data_train` |
| VIF | `data_train` + `data_test` | 同左（每个 split 各出一表/一节） |
| LASSO / 特征选择 | `data_train`（锁定特征） | 同左 |
| logistic / RCS | `data_imp` | `data_train` + 各 `data_test*` |
| Cox / KM | `data_imp`（无时间则 skip） | train+test*（无时间则 skip） |
| ML / performance / SHAP | train 拟合，test 评估 | 同左；多 test 时 performance 按 test 分面或分文件 |
| 亚组 OR | 与 logistic 同源 | 同左 |
| 亚组 HR | 有时间才跑 | 同左 |

废弃跨库模式下「每库 `train_validation` 再切 70/30」作为 ML 主路径；`train_validation` 块改为：

- 若已存在 `data_train`/`data_test` → **透传/基线表**（可出 Table 1 train vs test），不再重切；或  
- `config$train_validation$mode = "passthrough"`。

## 5. Pipeline / Runner 改动挂点

| 组件 | 路径 | 改动要点 |
| ---- | ---- | ---- |
| Pipeline 定义 | `configs/study_interface/ml_dual_batch_pipelines.R` | 跨库模式：单条 `pipeline_cross_db_ml`；去掉 secondary 独立 ML 全流程 |
| Batch runner | `R/ml_dual_batch_runner.R` / `R/incidence_dual_batch_runner.R` 共用逻辑 | worker 一次跑跨库 pipeline；输出 `by_index/<ix>/` 不按库分子流水线目录 |
| 划分块 | 新建 `Blocks/.../block_assign_train_test.R`（或并入 train_validation） | §3 规则 |
| 插补 | `Blocks/.../imputation` | train-fit / test-transform |
| 统计上游 | `ml_dual_primary_ml_stat_upstream_blocks` | 单因素/VIF/LASSO 数据源按 §4 |
| 图名 | `R/ml_dual_pub_table_curate.R`、performance/SHAP/subgroup 出图 | **禁止**对已含库名/角色标签的 basename 再次 `prefix_db`；跨库图用 `Train`/`Test` 或一次 `Train(DB)-Test(DB)` |
| Config 开关 | `config$ml_batch$split_mode` | `"cross_db"`（新默认建议）\| `"per_db_internal"`（旧行为，兼容） |
| 选指标块 | 新建 block + 挂共享层后 | §6 |

研究 config（胰腺癌）验证时：

- `split_mode = "cross_db"`
- `--only-index RAR`（或等价）重跑；删 `by_index/**/RAR*`、`checkpoints/**/RAR*`、相关 logs

## 6. 选指标对比表（共享层，不改循环）

**输入**：共享层后各库（或主分析库）可用列 + Blocks 复合指标目录（`dual_safe` / 全量公式表）。

**对每个可计算指标**（组分变量齐全且 `n_valid` 达阈值，默认与现筛查一致 ≥50）：

| 列 | 含义 |
| ---- | ---- |
| 复合指标名 | 如 RAR、APRI |
| 变量名 | 组分列（逗号分隔） |
| 计算公式 | 来自 index 定义原文/引擎公式字符串 |
| 总样本量 | 非缺失指标的 n |
| DN=1 的人数 | 结局阳性数（列名取 `outcome` / `DN` / `Disease` 配置） |
| OR | 单因素 logistic（指标连续或默认编码） |
| P_OR | |
| HR | 有时间变量时 Cox；否则 NA + 注明 skip |
| P_HR | |

**输出**：

- `Tables/Index_screening_OR_HR.csv`（及可选 xlsx）
- 日志打印：可计算个数；**不**写入 `index_vars` 自动过滤

OR/HR 拟合库：默认用 **拟定 train 库**（双库下 n 最大者）全样本（共享层已 index、未强制插补前可用完整病例；缺失策略写进表注）。

## 7. 图表去重与「够用」最小集（跨库一份）

跨库模式下每个指标至少产出（有则保留，无时间则跳过带 †）：

| 类型 | 内容 |
| ---- | ---- |
| Table | Train/Test assignment；基线 train vs test；单因素；VIF；LASSO；ML 性能汇总；选指标表在研究根/共享层 |
| Figure | ROC/PR 或 ML combined 2×4（**一份**，train vs test）；SHAP（最佳模型，一份）；亚组森林 OR（†HR）；Venn/特征共识（一份） |

修复：

1. 出图 basename 已含角色/库名时不再 `mirror_aggregate_prefix_db` 二次拼接。  
2. 汇总 curate 剥前缀逻辑与注入对称，避免 `Figure 3-X. Figure 3-X-...`。  
3. 跨库不再为每个库各渲一套 Figure 3/4。

## 8. 兼容性

- `split_mode = "per_db_internal"`：保持现网「每库内部划分 + 次库继承特征」行为，供旧项目续跑。  
- 新研究 / 胰腺癌验证：`cross_db`。  
- TabPFN 离线 / `COMSPEC`/`APPDATA` 修复保持不变。

## 9. 验证计划（本轮）

1. 实现 §3–§7 后，删除  
   `.../ml_40395549/by_index/**RAR**`、`checkpoints/**RAR**`、`logs/RAR.log`（及 `【success】RAR` 等）。  
2. `--only-index RAR --no-skip` 重跑。  
3. 检查：  
   - 仅一套 ML Figure 3 / SHAP / 亚组；无双重库名；  
   - `Train_test_assignment.csv` 中 MIMIC vs eICU 角色符合 n 大小；  
   - 无 `'/c'` / HF 下载回归；  
   - 共享层或研究根存在 `Index_screening_OR_HR.csv`。

## 10. 非目标（本轮不做）

- 不自动按 P 值筛选要跑的指标（选指标表仅信息）。  
- 不改 incidence 非 ML 套路的双库语义（除非显式复用同一 `assign` 块）。  
- 不重跑全部 6 指标（仅 RAR），除非验证通过后用户要求全量。
