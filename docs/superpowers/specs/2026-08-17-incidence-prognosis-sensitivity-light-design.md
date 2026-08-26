# 发病 / 预后敏感性分析轻量化设计

日期：2026-08-17  
状态：已确认（2026-08-17）  
范围：发病双库批量（`incidence_dual_batch`）与预后双库批量（`survival_dual_batch`）共用同一套敏感性编排。

## 1. 目标

主分析 **success** 的指标，在**已插补分析队列**上按场景删人，只重跑 Table 1 和 Table 2，并像指标一样给每个场景打 `【success】` / `【failed】`。

不再使用模板里写死的四个场景（排除高血压 / 糖尿病 / 癌症、年龄分层各一份名单）。Yes/No 场景从该指标两库 Table 1 **实际出现过的变量**动态生成；年龄分层作为额外固定场景保留。

### 1.1 必须继承主分析的部分

| 维度 | 继承 | 禁止 |
|------|------|------|
| 分析数据 | 该指标主分析 **插补后** per-index checkpoint（`ctx$data$imputed`） | 回到 shared/raw、重新插补、重新 data_clean / column_mapping / index |
| Table 2 协变量 | 主分析 Gate B 锁定的 Model 1 / Model 2 | 再做单因素、VIF、协变量搜索 |
| 关联 scheme | 主分析选中的分位档（quartile / tertile / binary） | 三档全跑或另选档 |
| 结局 / 暴露 | 与主分析同一结局列、同一指标 | 换结局或重算指标 |

过滤后变成单水平的协变量（例如排除高血压后 Hypertension 全是 No）必须从 Table 1 和 Table 2 中去掉，否则模型无法拟合。这是锁定协变量集的唯一例外。

## 2. 范围与非目标

### 范围内

- 场景发现、删人、Table 1、Table 2（发病 = 加权/GLM logistic 主表；预后 = Cox 主表）
- 双库都跑；Table 2 仍走现有 dual-DB 主表对齐（`dual_db_logistic_main_table_realign` / 预后对应 Cox 对齐），不新写一套表逻辑
- 场景目录打标、S12/S13 文件名、汇总 CSV
- 模板 / study_interface build / 能力层默认场景 / 程序员参考文档

### 非目标

- 敏感性里重跑插补、单因素、VIF、RCS、亚组森林、中介、ROC、箱线、流程图
- Gender / Race / Education 等没有「有病」水平的分类变量
- 每个水平都排除（只排除 Yes / 阳性）
- 改变 `subgroup_fallback`（失败指标补救仍走全流程 worker）
- 新 `register_block`（编排层改 suite + worker 截断，不新增分析块）

## 3. 场景生成

每个主分析 success 指标，在跑敏感性前扫描 **两库主分析 Table 1 用过的变量**（`include_vars` / `table1_var_order` / `categorical_vars.txt`，以主分析输出为准）。

### 3.1 Yes/No 临床标志（动态）

同时满足才生成一场：

1. 变量在 **两库** Table 1 中都出现；
2. 规范化后是 Yes/No（或 1/0 → Yes/No）二分，不是多分类；
3. 两库分析队列（插补后、主分析该指标样本）里 **Yes 组未加权 n 都 > 50**。

任一库缺变量、不是 Yes/No、或 Yes n ≤ 50 → **整场跳过**（不写 failed 目录）。

表达式：删掉 Yes，**保留 No 和 NA**（与现网 `SA_no_hypertension` 同类）。

目录标签：`SA_no_<Var>`（文件系统用英文）。  
发表描述：`非高血压`、`非糖尿病` 等（见 §5.2）。

`disease_vars` 不会进主分析 Table 1，因此不会生成「排除本病」场景。

### 3.2 年龄分层（固定，额外保留）

`age_cutoff` 仍可配，默认 **65**。固定两场：

- `SA_age_ge_{cutoff}`：只留 `Age >= cutoff`
- `SA_age_lt_{cutoff}`：只留 `Age < cutoff`

两库过滤后剩余人数都 ≥ `min_n_per_db`（默认 50）才跑，否则整场跳过。

旧模板 / build 里手写的 `scenarios = list(SA_no_hypertension, …)` **作废**，不再读取。

## 4. 执行路径

采用 **截断 worker**：复制该指标主分析已插补 checkpoint → 按场景删人 → 只跑基线 + 主 Table 2。

### 4.1 数据

1. 定位主分析 per-index ck（`checkpoints/by_index/<ix>/<db>/`，含 `imputed`）。
2. 复制到敏感性 staging ck，**不要**复制 baseline 及之后的 block 检查点。
3. 用现有 `incidence_batch_apply_subgroup_filter` 按表达式裁所有 data slot（掩码优先取含该列的 slot，同步裁 `imputed`）。
4. 加权库在过滤后重跑 `obj`（重建 survey design）；不要用过滤前的 design。

禁止：从 `_shared` 复制再插补（这是现在敏感性/亚组补救的路径）。

### 4.2 截断流水线

发病加权库：`obj` → `baseline_nhanes` → **主分析选中档**的 `logistic_*_nhanes_weighted` → 与主分析相同的 Table 2 导出链（含 `dual_db_logistic_scheme_harmonize` 与 `dual_db_logistic_main_table_realign`）。

发病非加权库：`baseline_binary` → 选中档 `logistic_*_glm` → 同上导出链。

预后：`baseline_binary` → 选中档 `cox_*` → 与主分析相同的 Cox Table 2 导出/双库对齐链。

关闭 logistic/Cox 早停闸门（与现网敏感性一致），避免子集上 crude NS 直接整场崩掉；成败改由 §6 判定。

分位切点在 **过滤后样本** 上按主分析同一 scheme 重算。协变量集锁定主分析，再去掉滤后零方差/单水平变量。

Table 1 的 `include_vars` 与主分析同一名单（再去掉单水平列）。

## 5. 产物路径与文件名

### 5.1 目录打标

```
by_index/【success】<ix>/sensitivity/【success】SA_no_Hypertension/
by_index/【success】<ix>/sensitivity/【failed】SA_no_Hypertension/
```

复用 `incidence_batch_output_dir_name(label, status)`。跳过已成功场景（`--no-skip` 时重跑）。失败目录保留表（若已写出）和 `worker.log`。

### 5.2 表号与文件名

所有场景共用：

- **S12** = 该场景基线（Table 1）
- **S13** = 该场景关联表（Table 2）

文件名必须含 `Sensitivity analysis` 和中文场景描述。示例（库名按课题 primary/secondary）：

```
Table S12-eICU. Sensitivity analysis-非高血压. Baseline characteristics.xlsx
Table S13-eICU. Sensitivity analysis-非高血压. Logistic regression of NLR quartile.xlsx
Table S12-eICU. Sensitivity analysis-年龄≥65. Baseline characteristics.xlsx
Table S13-MIMIC. Sensitivity analysis-年龄<65. Cox regression of NLR quartile.xlsx
```

场景描述规则：

| 场景 | 描述 |
|------|------|
| `SA_no_Hypertension` | 非高血压 |
| `SA_no_T2DM` / `SA_no_Diabetes` | 非糖尿病 |
| 其它 Yes/No | `非` + Table 1 展示名；无展示名则 `非` + 变量名 |
| `SA_age_ge_{c}` | `年龄≥{c}` |
| `SA_age_lt_{c}` | `年龄<{c}` |

xlsx 首行标题与文件名一致。这些文件在 `sensitivity/【status】<label>/` 下，不进入主分析 `Tables/` 的 S1–S11 重编号。

## 6. 成败判定

写表与打标分开：能出的表照出。

`【success】` 当且仅当：

1. 两库 Table 1 与 Table 2 都写出且无报错；
2. 两库 Table 2 **Model 2 主对比**（选中档：最高组 vs 参照，或 binary 的暴露组 vs 参照）p < `sig_cutoff`（默认 0.05）。

否则 `【failed】`（拟合失败、缺表、或任一库 Model 2 主对比不显著）。

## 7. Config

```r
sensitivity_suite = list(
  enable         = TRUE,   # 现有开关不变
  age_cutoff     = 65L,
  min_n_per_db   = 50L,    # 年龄分层：过滤后剩余
  min_yes_n      = 50L     # Yes/No 场景：两库 Yes 组未加权 n
)
```

不再需要 `scenarios`。旧课题 config 里残留的四个 list **忽略**。  
`--sensitivity-only` / `--to sensitivity` 行为保持，只是内部改成轻量路径。

## 8. 主要改动面

| 文件 | 职责 |
|------|------|
| `R/incidence_sensitivity_suite.R` | 场景发现、复制主分析 imputed ck、打标、S12/S13 命名、NS 判定 |
| worker（发病 / 预后） | 识别轻量敏感性：不 copy shared、不跑 imputation；截断 pipeline |
| `R/pipeline_capability_layer.R` | 默认场景不再返回写死四场 |
| `configs/templates/config_incidence_dual_batch.template.R` | 去掉手写 scenarios |
| `configs/study_interface/incidence_dual_batch_build.R` | 同上 |
| `configs/templates/config_survival_dual_batch.template.R` | 打开并与发病同构（现多为 `enable=FALSE`） |
| `configs/study_interface/survival_dual_batch_build.R` | 去掉手写 scenarios |
| `R/incidence_pipeline_brief.R` | 敏感性说明改为动态场景 + 轻量 Table1/2 |
| `tests/` | 场景发现、n 门槛、文件名、打标、禁止走 raw/shared 插补 |
| 程序员参考 `skills/deploy-programmer-interface/reference.md` | 同步口径 |

## 9. 测试要点

- Yes/No 发现：两库 Yes n 分别为 51/51 → 生成；51/50 → 跳过。
- 非 Yes/No（Race、Gender）不生成。
- 年龄分层：一库剩余 <50 → 跳过该年龄场。
- 文件名含 `Sensitivity analysis`、`非高血压`、`年龄≥65`，表号 S12/S13。
- 目录名为 `【success】` / `【failed】` + 场景标签。
- Model 2 主对比一库 p≥0.05 → 目录 `【failed】` 但仍有 S12/S13。
- 轻量路径复制的是主分析 imputed ck，断言没有重新执行 `imputation` block。

## 10. 风险

- 加权 Table 1 必须在过滤后重建 survey design；漏了会与主分析加权口径不一致。
- 主分析 per-index ck 若被清掉，敏感性无法跑：报错并 `【failed】`，提示先跑主分析。
- 多场景共用 S12/S13 编号，靠中文描述区分；不要把它们 merge 进主 `Tables/` 以免被 dual-db 重编号冲掉。
