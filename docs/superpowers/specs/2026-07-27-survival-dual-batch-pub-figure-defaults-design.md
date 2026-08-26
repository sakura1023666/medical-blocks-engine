# 预后双库（survival dual-batch）发表图号与内容默认 — 设计规格

> 状态：已批准并实现  
> 范围：所有 **survival dual-batch** 预后流水线的新默认（非单 study 特例）  
> 方案：**C** — 沿用 per-block `figure_kind` / `figure_number`，扩展固定编号工具支持补充图，并修共用内容 bug  
> 触发样例：ARDS ALBI（`prognosis_38902748/【success】ALBI`）图号/年龄标签/箱线双页/Table 3 冗余
> 实现计划：`docs/superpowers/plans/2026-07-27-survival-dual-batch-pub-figure-defaults.md`

## 0. 已确认决策

| 项 | 选择 |
| ---- | ---- |
| 适用范围 | **所有** survival dual-batch 预后流水线新默认 |
| 方案 | **C**（非中央 pub_map 后处理；非仅改 ALBI 文件名） |
| 发病 dual-batch | **不动**既有图号默认（除非另开需求） |
| 亚组数值表 | 默认 **不导出**（与森林图重复）；`export_table=TRUE` 可开 |
| 主文图 | Fig 1 流程 / Fig 2 RCS / Fig 3 KM / Fig 4 亚组森林 |
| 补充图 | S1 cutoff / S2 boxplot / S3 mediation / S4 ROC |

## 1. 问题陈述

1. **图号**：旧模板把 cutoff / KM / 亚组 / ROC / boxplot / mediation 标成主文 Fig 3–8；与目标发表结构不符。  
2. **年龄标签**：亚组森林图 Age 高组显示 `= 65`，应为 `≥ 65`（代码已写 `\u2265`，疑为 PDF 字体缺字或中间字符串被改）。  
3. **Boxplot 双页**：同一箱线图 PDF 两页重复。  
4. **Table 3**：`subgroup_prognosis` 无条件导出与森林图同内容的表；发病侧已有 `export_table=FALSE` 默认，预后侧未对齐。

## 2. 目标默认图号映射

| Block / 产出 | 旧默认（典型） | 新默认 | 配置键 |
| -------------- | -------------- | ------ | ------ |
| flowchart | Figure 1 | Figure 1 | （保持） |
| `rcs_prognosis` | Figure 2 | Figure 2 | （保持） |
| `km_strata` | Figure 4 | **Figure 3** | `km_strata$figure_number = 3` |
| `subgroup_prognosis`（森林图） | Figure 5（常为自增） | **Figure 4** | `subgroup` / `subgroup_prognosis`：`figure_kind=main_figure`, `figure_number=4` |
| `plot_cutoff` | Figure 3 | **Figure S1** | `figure_kind=supp_figure`, `figure_number=1` |
| `boxplot` | Figure 7 | **Figure S2** | `figure_kind=supp_figure`, `figure_number=2` |
| `mediation_prognosis`（path diagram） | Figure 8 | **Figure S3** | `figure_kind=supp_figure`, `figure_number=3` |
| `simple_ROC` / `roc_simple` | Figure 6 | **Figure S4** | `figure_kind=supp_figure`, `figure_number=4` |
| 亚组数值表（原 Table 3） | 总是导出 | **默认不导出** | `subgroup$export_table = FALSE`（默认） |

补充图使用**固定** `figure_number`，不依赖 block 运行顺序（ROC 常早于 boxplot/mediation，若仅靠自增会错号）。

## 3. 引擎改动

### 3.1 `R/utils.R`：固定编号支持补充图

- 扩展 `pub_figure_filepath_at(..., kind = c("main_figure","supp_figure"))`：  
  - 前缀用 `pub_prefix(kind, id)`（`Figure N.` / `Figure SN.`）；  
  - bump 对应计数器（新增 `pub_bump_supp_figure_min`，对称于 `pub_bump_main_figure_min`）。  
- 保持对既有 `main_figure` 调用的向后兼容（`kind` 默认 `"main_figure"`）。

### 3.2 各 block 接线（仅在缺能力时补）

| Block | 现状 | 需要 |
| ----- | ---- | ---- |
| `plot_cutoff` | 已有 `figure_kind` / `figure_number` + `pub_figure_filepath_at` | 改为走带 `kind` 的 API；模板改默认 |
| `km_strata` / `km_binary` | 已有 `figure_number`（主文） | 模板 `figure_number=3`；确认 bump |
| `subgroup_prognosis` | 森林图多靠自增；**总是** `export_sci_table` | 支持固定 `figure_number`；`export_table` 默认 FALSE |
| `boxplot` | 已有 kind/number；默认模板仍是 main 7 | 模板改 S2；修双页 |
| `simple_ROC` | 已有 kind/number；block 内默认已偏 supp | 模板固定 S4 |
| `mediation_prognosis` | 需核对 path 图是否支持 kind/number | 补齐与 incidence/NHANES 一致的 `figure_kind`/`figure_number` |

### 3.3 模板与 build 源

- 更新：`configs/templates/config_survival_dual_batch.template.R`  
- 同步：`configs/config_survival_dual_batch.R`（若含同样默认块）及 `configs/study_interface/survival_dual_batch_build.R` 所注入的默认，确保 **新 study / 新跑** 即用新图号。  
- 不改发病 `config_incidence_dual_batch*` 的图号默认。

### 3.4 年龄标签 `≥ 65`

- 根因排查顺序：  
  1) `Age_Group` 水平字符串是否在进森林图前仍为 `\u2265 65`；  
  2) `subgroup_pretty_label` / forestploter / PDF 设备字体是否把 `≥` 画成 `=`。  
- 修复策略（可组合）：  
  - 保证标签在数据层为 `≥ 65`；  
  - 森林图 PDF 使用能显示 U+2265 的设备/字体（优先 cairo + 已解析的 Times 系或回退字体）；  
  - 若设备仍无法画 `≥`，显示层用 `>= 65` 作为可读 ASCII 回退，并在注释中说明（优先仍争取真 `≥`）。  
- 改动放在 **共用** `subgroup_prognosis` + `subgroup_forest_plot.R`，使所有预后亚组图受益。

### 3.5 Boxplot 双页

- 目标：每个 response 一个 PDF、**一页**。  
- 排查：`save_figure` 队列渲染是否对 ggplot 双重 `print`；`ggpubr::stat_compare_means` 是否额外开页；旧闭包是否既绘图又返回。  
- 修复后在 boxplot 注释中保持「只返回 ggplot，由统一渲染 print」约定；必要时在 PDF 落盘后校验 `pdfinfo Pages==1`（开发期断言即可，不必强加运行时依赖）。

### 3.6 亚组表默认关闭

- `01block_subgroup_prognosis.R`（及如需要：`04block_subgroup_prognosis_continuous.R`）对齐发病：  
  `if (isTRUE(sub_cfg$export_table %||% FALSE)) { ... export ... }`  
- 模板写明：`subgroup$export_table = FALSE`。

## 4. ALBI 现有产物处理

对 `.../prognosis_38902748/by_index/【success】ALBI`：

1. 按新映射重命名/重出 Figures（eICU、MIMIC、根 `Figures/`）。  
2. 删除已导出的 `Table 3-*. Subgroup Analysis of ALBI.xlsx`（及 step 副本）；不重建除非 `export_table=TRUE`。  
3. 重跑或定点重绘：亚组森林图（验证 `≥ 65`）、boxplot（验证单页）。  
4. 不改动与本次无关的 Table S* / Fig 1–2 内容（仅图号受影响的文件按映射更新）。

可用一次性 `run/` 脚本完成 ALBI 回填，但**逻辑必须已进入引擎默认**，避免只修磁盘文件。

## 5. 验收标准

1. 新跑 survival dual-batch：主文仅 Fig 1–4（流程/RCS/KM/亚组）；补充为 S1–S4（cutoff/boxplot/mediation/ROC）。  
2. 亚组森林图 Age 高组显示 `≥ 65`（或已文档化的 `>= 65` 回退，且不再出现 `= 65`）。  
3. Boxplot PDF `Pages = 1`，无重复页。  
4. 默认无 `Table 3` / `Subgroup Analysis of <index>` 数值表；`export_table=TRUE` 可再出。  
5. 发病 dual-batch 既有默认行为回归无破坏（抽查 ROC/boxplot 仍为既有 supp 约定即可）。

## 6. 非目标

- 不引入第二套中央 `pub_map` 后处理系统。  
- 不批量重跑历史全部 success 指标（除用户点名的 ALBI 与验证所需）。  
- 不改 CRM/NHANES/trajectory 等其他管线的图号体系。

## 7. 实现顺序（批准后）

1. `pub_figure_filepath_at` + supp bump。  
2. 模板 / build 默认图号与 `export_table`。  
3. subgroup / mediation /（必要时）ROC·boxplot 接线。  
4. 修 `≥ 65` 与 boxplot 双页。  
5. ALBI 产物回填 + 验收。  
6. 短测：空/最小 config 读入后检查默认值；定点重绘 ALBI 两库图。
