# 发表图 image_information「图面标注必录」设计

日期：2026-08-26  
状态：已确认  
前置：`docs/superpowers/specs/2026-08-20-pub-figures-formats-and-image-information-design.md`  
范围：发病 / 预后 / ML dual-batch 等所有经 `export_pub_figures` / `pub_figure_refresh_image_information` 写出 `Figures/image_information/*.md` 的套路。

## 1. 目标

`image_information` 的「图面说明」必须包含**图上实际可见的关键数字与标注**（例如 RCS 的 `P-overall`、`P-non-linear`、cutoff；KM 的 Log-rank P；ROC 的 AUC 等），与图面文案口径一致，禁止空话或漏写图上信息。

全项目通过：

1. Cursor 规则（`alwaysApply`）约束人工 / AI；
2. 引擎单一写出入口自动生成合规 md。

旧课题不批量补刷；缺 checkpoint 字段时 md 明示「未收获」，禁止编造。

## 2. 已确认决策

| 项 | 决定 |
|----|------|
| 实现路径 | 方案 1：block 落盘图上数字 → harvest → 写入图面说明；同步升级 Cursor 规则 |
| 图类型范围 | 本轮主文常见图：Flowchart / RCS / KM / Forest / ROC / maxstat Cutoff |
| 旧结果 | 不批量补刷；需要时再点名 refresh / 重跑对应 block |
| 数字来源 | 仅可收获产物；禁止 OCR、禁止编造 |
| md 结构 | 保持 `# Figure …` + `## 图面说明` + `## 分析上下文`；禁止「标识」「技术」两段 |
| 图面说明内 | 增加固定段 **「图上标注」**（多库按库分条） |

## 3. 非目标

- 不批量重刷既有 `by_index/【success】*` 结果（含 ischemic stroke APRI 示例，除非用户另点名）。
- 本轮不改相关热图 / 中介路径图 / SHAP / 箱线图等 block 落盘（规则文案可写「有图上数字时同理」）。
- 不改变 PDF/PNG/TIFF 四目录布局与拼图逻辑。
- 不把完整 Table 2 行表整表贴进 md（「图上标注」只录图上出现或同面板图注的数字；Forest 例外：按图面行从 `subgroup` 结果表摘录）。

## 4. 架构与数据流

```
各图 block 出图
  → 把图上标注写入 ctx$results（轻量标量 / 短表）
  → checkpoint / cutoff CSV（沿用现有路径）
        ↓
finalize / refresh_image_information
  → pub_figure_harvest_findings() 按图类型收取
  → .pub_figure_detailed_body() 写「图上标注」段
  → 缺字段 →「未收获：…」；禁止假数
```

| 层 | 改动 |
|----|------|
| Block 落盘 | RCS / KM 等补写图上 P 值等到 `ctx$results` |
| Harvest | `pub_figure_harvest_findings` 增 `rcs` / `km` / `forest` 等槽 |
| 图面说明 | `.pub_figure_detailed_body` 强制输出「图上标注」 |
| Cursor 规则 | 升级 `pub_figure_image_information.mdc` |
| 补刷入口 | `run/pub/refresh_image_information.R` 走同一路径 |

## 5. 各图类型必录清单

md 在 `## 图面说明` 中单独一段 **「图上标注」**。格式尽量与图面文字一致（如 `P-overall = 0.001`）。

| 图类型 | 必录（图上有则写） | 主要收获来源 |
|--------|-------------------|--------------|
| Flowchart | 逐步保留 n、本步排除 n | 已有 `Flowchart_attrition*.csv` |
| RCS | 各面板（至少 Model2；有则含 Crude/M1/M3）的 P-overall（或 P for overall）、P-non-linear（或 P for nonlinear）；竖线 cutoff（图上标注的全部） | 见 §6 panel_stats；已有 `cutoff_*.csv` / `rcs_cutoffs_all` |
| KM | Log-rank P；二分 KM 的 cutoff；高低组标签 | block 补写 log-rank；`km_binary$cutoff` |
| Forest | Overall HR/OR(95%CI)；各亚组点估计与 95%CI；P for interaction | 已有 `ctx$results$subgroup` |
| ROC | AUC、95%CI、Youden、灵敏度/特异度（图上有则写） | 已有 `simple_ROC.rds` |
| maxstat Cutoff | 图上 maxstat 切点；上游 RCS 切点若图上无则标「不在图上」 | 已有 `plot_cutoff.rds` |

统一规则：

1. 只写图上实际出现（或同面板图注）的数字；图上没有的主表效应量不硬塞进「图上标注」（Forest 按图面行摘录除外）。
2. 收获不到 →「未收获：…」。
3. 拼图：A/B 面板分别写各库标注。
4. P 值格式与出图一致：`< 0.001` 或三位小数。

### 5.1 RCS 目标文案形态（示例）

```markdown
图上标注（与面板一致）：
- MIMIC Model2：P-overall = 0.001；P-non-linear = 0.116；cutoff ≈ …
- eICU Model2：…
```

## 6. Block 落盘键名

| Block | 键 | 说明 |
|-------|-----|------|
| `rcs_prognosis` | `rcs_prognosis_panel_stats` | list：Crude / Model1 / Model2 [/ Model3] → `p_overall`, `p_nonlinear`, `cutoffs`；从已有 `res*$p` 抽取，与图例同一公式（`logtest[3]`、`coefficients[2,5]`） |
| `rcs_incidence` | `rcs_incidence_panel_stats` | 同上口径；与 `anova` 图注同源 |
| `rcs_nhanes` / `rcs_iptw` | 对齐进统一 panel_stats 或等价结构 | 已有 p_overall / p_nonlinear 时少改、命名对齐 |
| `km_binary` / `km_strata` | `logrank_p`（binary 另保留 cutoff） | 与 `pval=TRUE` / 安全 log-rank 计算同源 |
| subgroup forest | 不新增表 | harvest 读已有 `subgroup` |

Harvest 优先顺序：index 下分库目录 / `checkpoints/by_index/<ix>/<DB>/` 中含上述键的 rds → 既有 CSV（cutoff、attrition）。

## 7. Cursor 规则改动要点

文件：`.cursor/rules/pub_figure_image_information.mdc`（`alwaysApply: true`）

新增铁律大意：

> **图面标注必录**：图上可见的关键数字/标注（P-overall、P-non-linear、cutoff、Log-rank P、AUC、亚组 HR/OR 与 P for interaction、纳排 n 等）必须出现在 `## 图面说明`；只写可收获证据；缺则明示未收获；禁止编造。

检查清单增加：RCS md 是否含 P-overall / P-non-linear / cutoff。  
反例增加：RCS 图上有 P 值与 cutoff，md 却只有空泛「剂量反应曲线」描述。

## 8. 验收标准

- [ ] 新跑预后/发病指标：RCS md 含 P-overall、P-non-linear、cutoff（与图一致）
- [ ] KM md 含 Log-rank P（及 binary cutoff）
- [ ] Forest md 含 Overall + 亚组效应 + 交互 P（来自 subgroup 表）
- [ ] ROC / maxstat / Flowchart 保持或加强现有收获
- [ ] 故意缺 checkpoint 时出现「未收获」，无假数
- [ ] 规则始终全局生效（`alwaysApply: true`）

## 9. 实现入口（实现阶段）

- `R/pub_figure_export.R`：`pub_figure_harvest_findings` / `.pub_figure_detailed_body` / `pub_figure_write_image_md`
- `Blocks/15_rcs/01block_rcs_prognosis.R`、`02block_rcs_incidence.R`（及 nhanes/iptw 对齐）
- `Blocks/27_KM/01block_km_binary.R`、`02block_km_strata.R`
- `.cursor/rules/pub_figure_image_information.mdc`
- 可选单测：`tests/` 下对 harvest + RCS 文案片段的 fixture 测试
- 补刷：`run/pub/refresh_image_information.R`（不改流程，受益于新 harvest）

## 10. 与既有设计的关系

本设计是对 2026-08-20 发表图设计的**增量**：四目录、拼图、禁止「标识/技术」不变；把「图信息内容」从笼统描述升级为**图面标注必录**。
