# 本轮（抑郁背景 × FI × 高血压 Fig1 / 发表收口）复用地图

目的：分清 **引擎可复用** vs **课题产物 / 一次性**，避免「文件散落、不知有没有用」。

## 一句话

| 位置 | 之后所有项目？ |
|------|----------------|
| `01Block-new-Final` 的 `R/` `Blocks/54_…` `run/cross_lagged/` `.cursor/rules` | **是** |
| `Output/22_depression_cross-laged_40595747/`（config / README / 锁文件） | **本课题入口**；大结果在 G 盘 |
| `G:…/22_depression/cross-laged_40595747/summary_result` `reports/` `*_delivery_workspace/` | **否** — 交付/审计产物 |
| `/tmp/fig1_*` 对话里临时拼图命令 | **否** — 可删；改走 `remosaic_fig1.R` |

---

## A. 引擎内（全项目复用）— 已就位

| 路径 | 作用 |
|------|------|
| `R/cross_lagged_study_meta.R` | `kind=depression_htn_frailty`；CHARLS 默认不进 `cohorts_long` |
| `R/cross_lagged_xs_flowchart.R` | `cross_lagged_depression_htn_baseline_attrition`；CHARLS Fig1：FI→抑郁阳性→底部分叉 HTN/无 HTN |
| `R/cross_lagged_fig1_pub.R` | **主文 Fig1 拼图唯一入口** `cross_lagged_remosaic_fig1()` |
| `run/cross_lagged/remosaic_fig1.R` | CLI：`--study <根>` |
| `Blocks/54_…/14block_cross_lagged_long_prepare.R` | ELSA/HRS 纵向 Fig1 前补 FI→抑郁阳性 |
| `Blocks/54_…/phases/collect_summary_result_generic.sh` | 抑郁课题过滤 CHARLS 纵向槽；收口时调 remosaic |
| `R/attrition_log.R` | `attrition_draw_pdf(..., fork=)`；可选 `mid_fork`（中间分叉） |
| `R/dual_db_combine_figures.R` | n 面板矢量拼图 |
| `R/pub_figure_export.R` / `R/pub_delivery_prune.R` | 四目录 600 dpi；交付白名单 |
| `.cursor/rules/cross_lagged_depression_htn_fig1.mdc` | 铁律摘要 |

### 新同类课题怎么用

1. 课题根放 `README_DEPRESSION_HTN_FRAILTY.txt`（或路径含 `22_depression` / `depression_htn`）  
2. 若某库不做纵向：放 `LONGITUDINAL_NO_CHARLS.txt`（或依赖 meta 默认 ELSA+HRS）  
3. 准备 `data/harmonized/D04_*_depression(_htn)_baseline.RData`  
4. 跑 phase / collect；或只重画 Fig1：  
   `Rscript run/cross_lagged/remosaic_fig1.R --study <课题根>`  
5. `Rscript run/pub/run_pub_qc_after_project.R --project <课题根>` + Nature + 中期  

禁止：在 `summary_result/scripts/` 或 `/tmp` 再写 `hotfix_remosaic_*.R`。

---

## B. 课题私有（勿当通用代码）

| 路径 | 说明 |
|------|------|
| `Output/22_depression_…/config_*.R`、锁文件、README | 本课题配置 |
| `G:…/cross-laged_40595747/phase*`、`summary_result/` | 结果与中期 PDF |
| `summary_result_delivery_workspace/` | prune 出来的 content.json / dump，非交付 |
| `scripts/prep_cross_lagged_depression_htn_frailty.R` | 本课题数据准备入口（可仿写下一病） |

---

## C. 本轮对话改动 vs 可删

| 项 | 处置 |
|----|------|
| 引擎上述 R/Blocks/run | **保留** |
| 对话里手工 `Rscript -e '…compose…'` | 已由 `remosaic_fig1.R` 替代 |
| `/tmp/fig1_*.png` 等 | 可删，不影响引擎 |
| E 盘 `Output/.../summary_result*` 镜像 | **禁止**再建；交付只在 G |

---

## D. 检查清单（下一课题）

- [ ] `cross_lagged_study_meta(study)$kind == "depression_htn_frailty"`（或同类 kind）  
- [ ] CHARLS（或 xs-only 库）Fig1 止于背景人群 N + 结局分叉，无误画纵向  
- [ ] 主文 `summary_result/Figures/{pdf,png,tiff}/Figure 1…` 为拼图且 DPI≥600  
- [ ] 未在结果目录留私有 remosaic 脚本  
