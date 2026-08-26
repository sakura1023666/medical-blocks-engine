---
name: split-medical-block
description: >-
  Splits monolithic Medical Blocks (R) into focused sub-blocks under Blocks/NN_<module>/.
  Before creating the folder, MUST ask the user for the two-digit directory prefix (pipeline order).
  Per-block config, ctx contracts, pause_point, register_block; self-contained sub-blocks;
  pipeline-owned data slots. Use when splitting/decomposing blocks or replicating
  baseline_binary / logistic_quartile_glm patterns.
---

# 医学统计 Block 拆分规范

将 `Blocks/block_<parent>.R` 拆成多个可独立 `run_block()` 的子块，便于按场景灵活编排。拆分前阅读 `BLOCKS_USAGE_GUIDE.md` 与现有父块实现。

**参考实现**：`Blocks/04_baseline/`（由 `block_baseline.R` 拆出，父块可保留不删）

| 子块文件 | `register_block` 名 | `config` 键 |
|----------|---------------------|-------------|
| `01block_baseline_binary.R` | `baseline_binary` | `baseline_binary` |
| `02block_baseline_multiclass.R` | `baseline_multiclass` | `baseline_multiclass` |
| `03block_baseline_nhanes.R` | `baseline_nhanes` | `baseline_nhanes` |

---

## 何时拆、何时不拆

**适合拆成独立子块**（业务分支，互斥或追加）：

- 分层水平不同（如 2 组 vs ≥3 组 → 不同检验）
- 数据库/设计不同（如 MIMIC 标准 Table 1 vs NHANES 加权表）
- 用户明确要「只跑其中一条路径」

**不要按每个 `if` 拆文件**：

- 防御性检查（`is.null`、列缺失告警）
- 统计细节（Fisher vs χ²、单变量格式）
- 应留在同一步骤内的逻辑

**粒度目标**：每个子块 = 一条完整分析路径（准备 → 主表 → 导出 → 写 `ctx$results`），通常 **3–8 个**子块，不是 40+。

---

## 硬约束（拆分与修订必守）

### 1. 不抽公共 block：各子块各自内嵌

- **禁止**为「复用」再建 `Blocks/<module>/_helpers.R`、`block_<module>_common.R` 或跨子块 `source` 的共享 block。
- 从父块拆出的 **Tb 表、随机搜索、pause、导出** 等逻辑，按路径 **完整复制** 进每个 `NNblock_<module>_<variant>.R`；允许代码重复，不追求 DRY。
- 若多子块需要同名辅助函数，写在**各自文件内**，用**文件级前缀**（如 `.lqg01_`、`.lqc03_`）避免 `source` 后互相覆盖。
- 用户未明确要求时，**默认不**把三块合成一块、也**不**把一块再拆成「公共 + 薄壳」两层。

**参考**：`Blocks/10_logistic/` 下 `01block_logistic_quartile_glm.R`、`02block_logistic_quintile_glm.R`、`03block_logistic_quartile_clogit.R` 等——每文件自带完整 `Tb_ModelGroup3_OR` 与随机搜索，无共享 logistic helper 文件。

### 2. Pipeline 决定数据，块内不选源

- **由编排顺序决定**本步读哪份数据：上游 block 把结果写入 `ctx$data$*`（如插补 → `imputed`，PSM 后覆盖或写入 `psm_matched`），下游子块**只读约定槽位**，不在块内用 config 切换「用哪张表」。
- **禁止**在子块 config 增加 `data_source`、`use_psm`、`input_dataset` 等键让块内 `if (bl_cfg$data_source == "...")` 选源。
- 块内统一写法（各子块可各复制同一段 3–5 行，不抽公共文件）：

```r
data <- ctx$data$imputed %||% ctx$data$cleaned
if (is.null(data) || !is.data.frame(data)) {
  # pause 或 stop：提示先跑上游数据准备 / 插补 / PSM
}
```

- 文件头 `require_data` 注释写清**依赖槽位**（如 `ctx$data$imputed %||% ctx$data$cleaned`），**不要**写「可选 data_source 配置」。
- 用户要在 config 里规定前后逻辑时，改 **pipeline / run_*.R 的 block 顺序**，而不是在子块里加数据源开关。

### 2b. 候选特征 / 上游 ctx 结果：pipeline 决定，块内不 switch

- 除 `ctx$data$*` 外，**候选特征池**亦由 pipeline 顺序决定：
  - 标准路径：`multicollinearity` → `ctx$results$Model2Factors` → feature_selection 各方法块只读该键。
  - 仅单因素路径：pipeline 跳过 VIF，上游写入 `ctx$results$univar_features`，方法块只读该键。
- **禁止**在子块 config 增加 `candidate_source`、`use_vif_candidates` 等键在块内 `if/else` 切换来源。
- 文件头 `require_ctx_results` 写清依赖键，不要写「可选 candidate_source」。

---

## 拆分工作流（按顺序执行）

### 0. 确认模块目录序号（必做，先问用户）

新建或整理 `Blocks/<module>/` 时，目录名必须为 **`NN_<module>`**（两位数字 + 下划线 + 模块名），数字表示该模块在**整条 pipeline** 中的大致顺序，便于在资源管理器中排序浏览。

**禁止自行猜测序号。** 动手建目录或 `mv` 之前，必须先向用户确认：

> 请指定本模块的**两位目录前缀**（`NN`）：它在你的 `run_*.R` 流水线里，排在哪些步骤之后、哪些步骤之前？  
> 例如本项目已有：`04_baseline`、`06_univariate`、`10_logistic`。你前面已占用的最大序号是多少？本模块拟用 `NN` = ？

执行拆分任务的 Agent 应：

1. **列出** `Blocks/` 下已有 `NN_*` 目录（`ls Blocks/ | grep '^[0-9][0-9]_'`），附在提问里供用户对表。
2. **等待用户明确给出** `NN`（如 `07`、`11`）后再创建 `Blocks/NN_<module>/`，勿默认沿用 baseline=04 / univariate=06 / logistic=10（除非用户明确说「与 xxx 相同」或「就是 04」）。
3. 若用户只给模块名未给序号，**只问一句并暂停**，不要先写进 `Blocks/univariate/` 等无前缀路径。

**目录就绪命令示例**（在 `Blocks/` 下执行，`NN` 与 `<module>` 以用户答复为准）：

```bash
cd Blocks
# 新建拆分输出目录时：
mkdir -p NN_<module>
# 若已误建在无前缀目录，改名：
mv <module> NN_<module>
```

**须同步改路径引用**（`NN` 确定后全局搜索替换）：

- `file.path(root, "Blocks", "<module>")` → `"Blocks", "NN_<module>"`
- 文档/skills 中的 `Blocks/<module>/`
- `source_univariate_blocks` 等 helper 里的目录常量
- `config*.R` 注释中的路径说明

**本项目当前登记（示例，以仓库实际 `ls` 为准）：**

| 目录 | 模块 | 说明 |
|------|------|------|
| `04_baseline` | baseline | Table 1 子块 |
| `06_univariate` | univariate | 单因素/多因素子块 |
| `10_logistic` | logistic | 分位数 Logistic / clogit 子块 |
| `19_feature_selection` | feature_selection | LASSO/Boruta/RFE/LVQ + consensus + venn（6+1+1） |
| `22_ml_models` | ml_models | 16 算法子块 + ml_aggregate（由 `block_ml_models.R` 包装器兼容调度） |
| `23_ml_performance` | performance_ml | 单块 `01block_performance_ml.R`（ML 综合表现图/表，未再拆子路径） |

新增模块（如 `subgroup`、`cox`）由用户指定新 `NN`，避免与上表冲突。

**feature_selection 拆分**（`Blocks/19_feature_selection/`）：

| 子块 | `register_block` |
|------|------------------|
| `01block_feature_selection_lasso.R` | `feature_selection_lasso` |
| `02block_feature_selection_boruta.R` | `feature_selection_boruta` |
| `03block_feature_selection_bayesian.R` | `feature_selection_bayesian` |
| `04block_feature_selection_random_forest.R` | `feature_selection_random_forest` |
| `05block_feature_selection_bagged_trees.R` | `feature_selection_bagged_trees` |
| `06block_feature_selection_lvq.R` | `feature_selection_lvq` |
| `07block_feature_selection_consensus.R` | `feature_selection_consensus` |
| `08block_feature_selection_venn.R` | `feature_selection_venn` |

- 01–06：各含完整 prep + 单方法 + 该方法 Figure S2；写 `ctx$results$feature_selection_by_model[[method]]`。
- 07：投票/共识/final/总表/RDS；写 `feature_selection_venn_input`；不画 S3。
- 08：只读 07 产出，画 Figure S3 韦恩/Euler/UpSet。
- 选哪些方法 = pipeline 里 source + `run_block` 哪些 01–06，不用 `auto_methods`。

### 1. 划定子块边界

1. 通读父块，标出**阶段**（取数、变量分类、建模、导出、写结果）。
2. 标出**互斥分支**（`n_groups == 2` vs `>= 3`、`.is_nhanes_db()` 等）。
3. 画一张表：子块名 | 触发条件 | 读 `ctx` | 写 `ctx$results` | 独有 config 键。

下游若依赖 `sig_vars`、`table_1` 等，**多个子块应写入相同键名**（必要时加 `results$<parent>_mode` 作日志）。

### 2. 目录与文件命名

**模块目录** `NN_<module>` 中的 **`NN`（两位）** = 工作流 §0 向用户确认的**文件夹前缀**；**子块文件名**里的 `01`/`02` = 模块**内部**编排顺序，二者不要混用。

```
Blocks/
  NN_<module>/                # NN 由用户指定（§0）；如 04_baseline、06_univariate、10_logistic
    01block_<module>_<variant>.R
    02block_<module>_<variant>.R
  block_<parent>.R             # 可选保留，不强制删除
```

- 子块文件名：`NNblock_<register_name>.R`（此处 `NN` 为**文件**顺序 01、02…，与目录前缀无关）。
- 函数名：与注册名一致，如 `block_baseline_binary`。
- `register_block("<snake_name>", block_<snake_name>, "简短中文描述")` 写在文件末尾。

### 3. 文件头契约（仅注释，不执行）

每个子块顶部**只写三块**，风格对齐 `config2.R` 的 list 注释：

```r
###############################################################################
#  <register_name> — 一句话说明本块做什么。
#
#  # ── 前置条件 ─────────────────────────────────────────────────────────────
#  require_data = ctx$data$imputed %||% ctx$data$cleaned   # 由 pipeline 决定，块内不选源
#  require_* = ...              # 本块特有（水平数、依赖 block、R 包等）
#
#  <register_name> = list(
#    ...                        # 仅本块控制的参数
#  ),
#
#  块内读取 config$<register_name>；data / project / survival 等见项目主 config。
###############################################################################
```

**不要**在文件头写完整 `input`/`output`/`data`/`project` 清单——那些属于主 `config.R`，只在注释里一句带过。

### 4. Config 读取规则

- 子块**只读** `cfg$<register_name>`，赋给 `bl_cfg`：

```r
bl_cfg <- cfg$baseline_binary %||% list()
strata <- strata_var %||% bl_cfg$strata %||% ...
```

- **禁止**再依赖已废弃的父级键（如拆分后不用 `cfg$baseline`，除非过渡期显式文档说明）。
- 主 config 中为用户准备独立段：

```r
baseline_binary = list(sig_cutoff = 0.05, include_vars = NULL, ...),
baseline_multiclass = list(...),
baseline_nhanes = list(...),
```

- 阈值、列名、路径等**禁止块内字面量**（除统计惯例且文档化的例外）；用 `bl_cfg$xxx %||%` 且 **pause 前不得写死 `0.05`** 作为业务阈值（`sig_cutoff` 进 config）。

### 5. 实现子块主体

从父块**复制**对应路径的完整代码到各文件（**必须**各自内嵌；**禁止**抽共享 `_helpers.R` / 公共 block，见上文「硬约束 §1」）。

取数：**只读** pipeline 已写入的 `ctx$data$*` 槽位（见「硬约束 §2」），块内不设 `data_source`。

每文件建议结构：

1. 文件头契约注释  
2. 本文件私有辅助函数（前缀如 `.bb01_`，避免多文件 `source` 时覆盖）  
3. `block_<name> <- function(ctx, ...) { ...; ctx }`  
4. `register_block(...)`

子块内：

- 只通过 `ctx` 与 `ctx$config` 交互，不调用其他 block 的函数。
- 表格：`export_sci_table()` + `table1_render_spec`；中间表：`save_result()`。
- 需要可重复随机划分/子采样时，可在子块内 `set.seed(bl_cfg$seed %||% cfg$splitting$seed %||% ...)`；种子应来自 config，禁止无来源硬编码。
- 禁止对失败路径静默 `return(ctx)`（见 pause 节）。

### 6. 智能阻断 `pause_point`（必须）

遵循 `BLOCKS_USAGE_GUIDE.md` 模板，每子块实现：

```r
.<prefix>_should_pause <- function(bl_cfg, key, default = TRUE) {
  if (!is.null(bl_cfg$pause_enable) && !isTRUE(bl_cfg$pause_enable)) return(FALSE)
  isTRUE(bl_cfg[[key]] %||% default)
}

.<prefix>_pause <- function(ctx, reason, suggestion, data_snapshot = NULL) {
  snap <- if (is.data.frame(data_snapshot)) utils::head(data_snapshot, 5L) else data.frame(note = "no snapshot")
  ctx$results$pause_point <- list(
    block = "<register_name>",
    reason = reason,
    suggestion = suggestion,
    data_snapshot = snap
  )
  stop(
    "PAUSE_FOR_USER_DECISION: ... See ctx$results$pause_point. / ",
    "发现异常或阴性结果，请查看 ctx$results$pause_point 并指示下一步操作。",
    call. = FALSE
  )
}
```

在 `bl_cfg` 中提供（并写入文件头注释）：

| 键 | 含义 |
|----|------|
| `pause_enable` | 总开关，`FALSE` 时仅 warning/普通 stop |
| `pause_on_table1_fail` | 主表生成失败 |
| `pause_on_min_sig_vars` | 显著变量过少（阴性） |
| `pause_min_sig_vars` | 最少变量个数（默认 3） |
| 子块特有键 | 如 `pause_on_missing_design`（NHANES） |

**建议 pause 的场景**：无数据、配置缺失、前置结果缺失、主分析失败、显著变量数 &lt; `pause_min_sig_vars`。  
**普通 `stop()`** 仍可用于硬性错误（如分层列不存在），最好也写入 `pause_point`。

显著性筛选：读 `bl_cfg$sig_cutoff`（可保留 `p_threshold` 作 legacy 别名），日志与 pause 文案用 `config$<register_name>$sig_cutoff`，避免在块内「定义 P 值」的措辞。

### 7. 编排脚本（`run_*.R`）

- 用户自行决定调用顺序；子块**不**自动串联。
- 示例：

```r
source("Blocks/04_baseline/01block_baseline_binary.R")
ctx <- run_block(ctx, "baseline_binary")

# NHANES 仅加权路径
source("Blocks/04_baseline/03block_baseline_nhanes.R")
ctx <- run_block(ctx, "obj")
ctx <- run_block(ctx, "baseline_nhanes")
```

按 `n_groups` 或 `database_type` 分支选择子块，**不要**再 `source` 父块 wrapper。

### 8. 验证

- [ ] `Rscript -e 'parse("Blocks/.../NNblock_....R")'` 语法通过  
- [ ] 各子块 `register_block` 名唯一  
- [ ] `grep 'cfg\\$<old_parent_key>' Blocks/NN_<module>/` 无残留（已迁移到 `cfg$<register_name>`）  
- [ ] 下游需要的 `ctx$results` 键在对应子块中仍被写入  
- [ ] `pause_enable = TRUE` 时失败路径会 `stop` 且带 `pause_point`  

---

## 拆分检查清单（复制使用）

```
规划
- [ ] 已向用户确认模块目录两位前缀 `NN`，并列出已有 `Blocks/NN_*` 避免冲突
- [ ] 子块按业务路径划分（非按 if 个数）
- [ ] 每块前置条件与触发条件已写明
- [ ] ctx 输入/输出与下游兼容
- [ ] 无公共 helper / 公共 block；重复逻辑已内嵌到各子块
- [ ] 数据入口仅 `ctx$data$*` 槽位，无 `data_source` 类 config

文件
- [ ] Blocks/NN_<module>/（非无前缀的 Blocks/<module>/）
- [ ] NNblock_<name>.R 位于上述目录内
- [ ] 文件头：前置条件 + <register_name> = list(...) 仅块内参数
- [ ] register_block 与函数名一致

Config
- [ ] 主 config 增加 <register_name> = list(...)
- [ ] 块内 bl_cfg <- cfg$<register_name> %||% list()
- [ ] 无 cfg$<旧父键> 依赖（除非用户要求过渡 fallback）

质量（BLOCKS_USAGE_GUIDE）
- [ ] export_sci_table / save_result
- [ ] pause_point + pause_* 配置项
- [ ] 未修改父块（若用户要求保留）

编排
- [ ] run_*.R 改为 source 子块 + run_block 新名称
```

---

## 常见错误

| 错误 | 正确做法 |
|------|----------|
| 拆成 30 个碎片 block | 合并为少量完整路径块 |
| 文件头写满 data/project/config | 只写 `<register_name> = list(...)` |
| 仍读 `cfg$baseline` | 读 `cfg$baseline_binary` 等 |
| NHANES 先跑标准表再加权 | 子块只做该路径该做的事 |
| 失败只 `warning` + `return(ctx)` | `pause_point` + `PAUSE_FOR_USER_DECISION` |
| 三个文件共用 `.test_normality` 无前缀 | 每文件 `.bb01_*` / `.bb02_*` 前缀 |
| 抽 `block_*_common.R` 或 `_helpers.R` | 各子块内嵌完整逻辑，允许重复 |
| `data_source = "psm"` / `"imputed"` 在块内切换 | pipeline 顺序 + `ctx$data$imputed %||% cleaned` |
| 块内 `if (use_psm) data <- ctx$data$psm_matched` | 上游写入约定槽位，本块只读该槽位 |
| 未问用户就建 `Blocks/baseline/` | 先问 `NN`，再建 `Blocks/NN_baseline/` |
| 目录前缀与子块文件 `01block_` 混为一谈 | 目录 `04_baseline`；文件 `01block_baseline_binary.R` |
| `candidate_source = "intersect"` 等在块内切换 | pipeline 顺序 + 固定读约定 `ctx$results$*` 键 |

---

## 延伸阅读

- 项目规范：`BLOCKS_USAGE_GUIDE.md`
- 父块参考：`Blocks/block_baseline.R`
- 拆分结果：`Blocks/04_baseline/01block_*.R` … `03block_*.R`
