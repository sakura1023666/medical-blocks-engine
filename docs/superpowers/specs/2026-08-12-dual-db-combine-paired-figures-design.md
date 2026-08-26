# 双库发表图全局 A/B 拼图设计

日期：2026-08-12  
状态：已批准并实现  
范围：所有 dual-batch 流水线（survival / incidence / ML）的指标汇总 `Figures/`

## 1. 目标

双库项目在指标汇总目录中，把成对的分库发表图拼成一张带面板标签的图，并去掉不需要的缺失概览图。

已确认决策：

| 项 | 决定 |
|----|------|
| 汇总目录分库单图 | **删除**（只留拼图）；各库子目录底稿保留 |
| 拼哪些图 | 主文 + 附录成对图都拼；跳过已是双库合成图；Missing Value **删除不拼** |
| 版式 | **按图类型自动**：RCS **上下**；KM / 亚组森林 **左右**；其余默认左右 |
| 面板顺序 | A = `dual_db` primary，B = secondary |
| 拼图文件名 | **不带** `Combined`（如 `Figure 4. Subgroup….pdf`） |
| Fig1 分库纳排 | 汇总目录**不要** `Figure 1-*. Inclusion exclusion flowchart.pdf`（仅留 `Figure 1. Flowchart.pdf`；分库底稿可留子目录） |
| 实现路线 | Finalize 后拼 PDF（方案 1），并收紧 KM/森林源端防溢出 |

## 2. 非目标

- 不在各分析 block 内同时读两库重画（改动面过大）
- 不改各库 `by_index/<ix>/<DB>/Figures/` 底稿
- 不强制失败于缺配对（告警并保留单图）
- 不把 Fig 1 类已合成 flowchart 再拼一次

## 3. 挂点与调用顺序

在 `incidence_batch_finalize_index_outputs`（`R/incidence_dual_batch_runner.R`）中：

1. `incidence_batch_sync_db_pub_outputs`（各库）
2. `mirror_dual_db_aggregate` → 汇总目录出现成对 `-DB` PDF
3. **【新增】** `dual_db_combine_paired_figures(index_root, config)`
4. `incidence_batch_curate_index_pub_outputs`（排序 / ML 角色整理）

survival / incidence / ML dual worker 共用该 finalize，故对后续所有 dual 项目默认生效。

## 4. 配对规则

### 4.1 识别

汇总 `Figures/` 下 PDF，匹配现有库标签注入模式：

- 主路径：`Figure N-<DB>. Caption.pdf` 或 `Figure SN-<DB>. Caption.pdf`
- ML 路径：`Figure N. <DB>. Caption.pdf`（点号分隔库名）

库名集合来自 `dual_db$primary$name` / `dual_db$secondary$name`（及实际出现的标签）。

### 4.2 角色键

去掉库标签后的规范名作为配对键，例如：

- `Figure 4-eICU. Subgroup Forest analyses of BAR.pdf`
- `Figure 4-MIMIC. Subgroup Forest analyses of BAR.pdf`

→ 键 = `Figure 4. Subgroup Forest analyses of BAR.pdf`

### 4.3 输出

- 写出配对键同名文件（**无** `Combined` 字样）
- 面板标签：`A. {primary}`、`B. {secondary}`（格式可配，默认 `A. {db}`）
- `remove_singles=TRUE` 时删除两张分库源 PDF（仅汇总目录）

### 4.4 跳过 / 删除

| 情况 | 处理 |
|------|------|
| 文件名已无库标签且非 Missing Value（如 `Figure 1. Flowchart.pdf`） | 跳过 |
| `Figure Missing Value Overview*.pdf`（含带 `-DB`） | 删除，不拼 |
| 仅有一侧库 | 保留单图 + `cli` 告警 |
| 非 PDF / 非 Figure 前缀 | 忽略 |

## 5. 版式启发式

默认（可用 `layout_by_role` 覆盖）：

| 布局 | 匹配（文件名关键词，大小写不敏感） |
|------|-------------------------------------|
| 上下（nrow=2） | `RCS` / Restricted Cubic |
| 左右（ncol=2） | `Subgroup Forest`、`Kaplan-Meier`/`KM`，以及其余成对图（ROC、Boxplot、Cutoff、Mediation 等） |

实现：用 magick / pdftools 读入两页 PDF 光栅或矢量拼版；上方或左侧加标签条；外 margins 避免裁字。优先保持可读分辨率（PDF→高 dpi 渲染再写回 PDF，或 pdftools + grid 贴图）。

## 6. 溢出处理

1. **源端（全局模板/默认）**  
   - KM（`km_strata`）：略增 `plot_width`/`plot_height` 或边距；必要时略降 title/legend 字号。  
   - 亚组森林（`subgroup_forest_plot.R`）：保证 `forest_max_width_in` / 边距足够；`base_size` 可略降，避免列标签出界。
2. **拼图端**  
   - 按两页实际宽高比例缩放对齐；标签占用独立条带，不覆盖原图标题区。  
   - 不对角裁切正文；宁肯拼图画布略大。

## 7. 配置

```r
config$dual_db$combine_figures <- list(
  enable = TRUE,
  remove_singles = TRUE,
  drop_missing_overview = TRUE,
  panel_order = "primary_first",
  label_format = "A. {db}",   # B 自动换成 B.
  layout_by_role = NULL       # 可选：named list，角色 → "stack"|"side"
)
config$imputation$export_missing_fig <- FALSE
```

写入：

- `configs/templates/config_survival_dual_batch.template.R`
- `configs/templates/config_incidence_dual_batch.template.R`（及现有 dual 模板同类项）
- 现有研究若未写该键：代码默认 `enable=TRUE`（与「之后所有项目」一致）；可用 `enable=FALSE` 退出。

## 8. 主要改动文件

| 文件 | 改动 |
|------|------|
| `R/dual_db_harmonize.R`（或新 `R/dual_db_combine_figures.R`） | `dual_db_combine_paired_figures` 实现 |
| `R/incidence_dual_batch_runner.R` | finalize 中调用 |
| `Blocks/03_imputation/01block_imputation.R` / 模板 | 默认 `export_missing_fig=FALSE`；finalize 再清漏网 |
| `Blocks/27_KM/02block_km_strata.R`、`R/subgroup_forest_plot.R` | 源端防溢出微调 |
| dual-batch 模板 | `combine_figures` + `export_missing_fig` |

## 9. 验收（BAR / 任意 survival 指标）

汇总 `by_index/<ix>/Figures/`：

- [ ] 无 `Figure Missing Value Overview*`
- [ ] 存在 `Figure 2. …`、`Figure 3. …`、`Figure 4. …` 及成对附录拼图（无库标签）
- [ ] **无**成对残留的 `Figure *-eICU.*` / `Figure *-MIMIC.*`（已拼成功的角色）
- [ ] 拼图可见 `A. eICU`、`B. MIMIC`（或配置的 primary/secondary 名）
- [ ] KM、亚组森林无明显文字出界
- [ ] `by_index/<ix>/eICU/Figures` 与 `MIMIC/Figures` 仍有分库底稿
- [ ] `Figure 1. Flowchart.pdf` 仍在且未被错误删除/重拼

## 10. 风险与回退

- PDF 拼图依赖 magick/pdftools/cairo；缺包时告警跳过拼图，保留分库单图。  
- `enable=FALSE` 或 `remove_singles=FALSE` 可完整回退到旧行为。  
- ML 点号库名模式需与 survival 破折号模式一并测。
