# 通用纳排流程图 Block 设计（attrition_flowchart）

> 日期: 2026-08-12  
> 状态: 已确认（对话定稿）  
> 范围: 全套路默认产出 Figure 1 纳排表 + PDF

## 1. 目标

所有经 `run_pipeline` / batch worker 运行的分析套路，默认在流水线**末尾**产出：

- `Tables/Flowchart_attrition.csv`（分库时加 `_<db>` 后缀）
- `Figures/Figure 1. Inclusion exclusion flowchart.pdf`

人数来源为 **config 队列步骤 + 上游显式记账 + runner nrow 自动兜底**；禁止无证据编造人数。

## 2. 已确认决策

| 项 | 选择 |
|----|------|
| 覆盖范围 | 真·全覆盖：baseline 中全部 routine（incidence / survival / competing / environment / trajectory / ipw / tst / ml …） |
| 步骤来源 | 混合：config 队列构建 + 过程掉人自动追加 |
| 产出 | 纳排表 + Figure 1 PDF |
| 定稿时机 | 分析末尾出一次终版 |
| 实现路线 | 通用 block + 显式 `attrition_record` API为主；runner 轻量 nrow 兜底 |

## 3. 架构

```text
config$attrition$steps  ──┐
上游 block 显式记账        ──┼─→ ctx$results$attrition$log
runner 自动 nrow 兜底      ──┘
                              ↓
              block: attrition_flowchart  (pipeline 末尾)
                              ↓
         Tables/Flowchart_attrition*.csv
         Figures/Figure 1. Inclusion exclusion flowchart.pdf
```

### 3.1 新增文件

| 路径 | 职责 |
|------|------|
| `R/attrition_log.R` | `attrition_record` / `attrition_n_current` / `attrition_finalize_rows` / `attrition_draw_pdf` / 解析 `config$attrition$steps` |
| `Blocks/00_attrition/01block_attrition_flowchart.R` | `register_block("attrition_flowchart", ...)`；合并步骤、写表、出 PDF |
| （可选）`R/tests` 或 `tests/test_attrition_log.R` | 步骤合并、去重、无证据跳过、空 steps 降级 |

### 3.2 引擎挂接

- `R/pipeline_runner.R`：注册 `attrition_flowchart`；启动时 `source(R/attrition_log.R)`；每个 block 前后在 `auto_append=TRUE` 时记录 nrow 变化
- `configs/study_interface/baseline_pipelines.json`：各 routine 主 pipeline **末尾**追加 `attrition_flowchart`（写入 baseline 后，扩展守卫视为合法基线块，无需 `extensions.json`）
- 各 `configs/templates/*.template.R` 与 build 脚本：默认 `config$attrition`（`enable=TRUE`，`steps` 可空）
- batch worker：pipeline 已含该块则自然执行；若截断 pipeline，worker 收尾补一次调用以防漏

## 4. Config 契约

```r
config$attrition <- list(
  enable = TRUE,
  title  = NULL,          # NULL → 自动生成 Figure 1 标题
  db_label = NULL,        # NULL → project$database / 当前 dual_db 名
  steps = list(
    # 示例（研究侧填写）
    list(id = "baseline", label = "MIMIC-IV ICU first-stay baseline",
         source = "rawdata"),
    list(id = "disease", label = "Disease cohort",
         source = "id_file", path = "...", id_col = "subject_id", join_on = "ID"),
    list(id = "exposure", label = "Disease + exposure filter",
         source = "id_file", path = "...", filter = "rx == 1",
         intersect_with = "disease"),
    list(id = "analytic", label = "Analytic cohort",
         source = "current")
  ),
  outcome_breakdown = TRUE,  # 末行附病例/对照计数（若有 outcome 列）
  auto_append = TRUE,
  draw_pdf = TRUE,
  csv_name = "Flowchart_attrition.csv",
  figure_name = "Figure 1. Inclusion exclusion flowchart.pdf",
  specialty_figure_mode = "skip_if_generic"  # 专用 flowchart 遇通用 Figure 1 已存在则跳过
)
```

### 4.1 `steps[].source` 语义

| source | 行为 |
|--------|------|
| `rawdata` | 从 `config$data$rawdata_path` + `rawdata_obj` 取 nrow |
| `id_file` | 读 `path` CSV/名单，按 `id_col` 与基线 `join_on` 求交集人数；可选 `filter` 表达式；可选 `intersect_with` 引用先前 step id 的 ID 集 |
| `current` | `nrow(imputed %||% cleaned %||% raw)` |
| `fixed` | 直接使用步骤内给定的 `n`（须研究侧有据；仍写入 meta 说明来源） |

### 4.2 合并优先级

1. `config$attrition$steps`（队列构建，按顺序）
2. `ctx$results$attrition$log` 显式记录（按 `step_id` 去重更新）
3. runner 自动 nrow 行（仅当 `auto_append=TRUE` 且该区间无显式记录；`source="auto"`，label=`After <block_id>`）

无证据算不出 N 的步骤：`cli_alert_warning` 后跳过，**不 stop、不编造**。

`steps` 为空时：仍产出至少「当前分析集 N」+ 过程行；warning 提示建议补队列步骤。

## 5. 记账 API 与上游挂点

### 5.1 API

- `attrition_record(ctx, step_id, label, n, kind = "include", meta = list())`
- `attrition_n_current(ctx)`
- `attrition_finalize_rows(ctx, config)` → data.frame(`step`, `n`, …)
- `attrition_draw_pdf(rows, title, pdf_path, font_family)`

### 5.2 一期必挂显式记账

| 位置 | 记录内容 |
|------|----------|
| `data_clean` 结束 | age_filter / 行过滤后的 N |
| `imputation` 结束 | 分析集 N（列剔除不记为人掉，除非真删行） |
| 指标缺失剔除（batch clean index NA） | Exclude missing \<index\> 后 N |
| `trim_index_extreme`（若执行） | 修剪后 N |

其余 block 不强制修改；依赖 runner 自动兜底。

## 6. 产出与镜像

- 表：`Tables/` + 可选 `mirror_pub_outputs_to_root`
- 图：固定 Figure 1 文件名；Times 系字体，缺失则回退默认字体
- `ctx$results$attrition_flowchart`：最终 rows、csv/pdf 路径
- 双库/分库：文件名加库后缀；批量多指标时项目级以队列为主，worker 内可追加指标缺失步骤

## 7. 与专用 flowchart 并存

- 保留：`competing_flowchart` / `ipw_diabetes_flowchart` / `crm_nhanes_flowchart`
- 通用块占用 **Figure 1** 标准文件名
- 专用块默认 `specialty_figure_mode = "skip_if_generic"`：若通用 Figure 1 已存在则跳过；否则可写 `Figure 1b.*`
- 一期抽取共用绘图函数；不删除专用块代码

## 8. 错误处理

| 情况 | 行为 |
|------|------|
| `enable=FALSE` | 静默跳过 |
| 单步无法计 N | warning + 跳过该步 |
| 有效步骤为 0 | warning；若能取得当前分析集 N 则出单框 PDF + 单行 CSV，否则跳过 PDF |
| 字体不可用 | 回退默认字体，不因字体失败 |

## 9. 验收标准

1. 任一 baseline routine 跑通后，产出根出现纳排 CSV + Figure 1 PDF  
2. RA+GC→ASCVD 类研究只需在 config 填 `steps`，无需手写 `prep_*` 出图脚本  
3. 无 `steps` 时流水线仍成功，并有 warning  
4. `python3 scripts/update_blocks_catalog.py` 后 `docs/Blocks_catalog.md` 含 `attrition_flowchart`  
5. 现有专用 flowchart 套路不因通用块引入硬失败（skip 或 1b）

## 10. 非目标（本期不做）

- 删除或重写全部专用 flowchart 业务逻辑  
- 在每个 block 都强制插入记账  
- CONSORT 侧向多排除框的完整复杂版式（本期沿用纵向纳入框 + 右侧掉人标注；与现 survival 绘制风格对齐）  
- 自动从任意 CSV 列名推断疾病/用药语义（必须由 config steps 声明）

## 11. 实现顺序（供后续 plan）

1. `R/attrition_log.R` + 单元测试  
2. `Blocks/00_attrition/01block_attrition_flowchart.R` + runner 注册  
3. runner nrow 自动兜底  
4. 上游四处显式记账  
5. `baseline_pipelines.json` + templates 默认 config  
6. 专用块 skip_if_generic  
7. 目录同步 + RA 研究 config 迁移验证  
