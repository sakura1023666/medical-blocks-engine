# Task 10 Report — 授权后开跑 + 四目录发表图

**Status:** DONE（Fig2 MV OR 已补齐）  
**Date:** 2026-09-22  
**Study:** `/mnt/g/02block_result/10_osteoporosis/personalized`

## What ran

1. QCT full pipeline (`config_osteo_fracture_qct.R`) — EXIT 0  
2. DXA full pipeline (`config_osteo_fracture_dxa.R`) — EXIT 0  
3. First QCT pass: CART 未分裂（BMI 被 `exclude_other_composite_indices` 删掉 + `cp=0.01`）  
4. Minimal fix → re-run both configs:
   - `protect_vars` 加入 `BMI`（双 config）
   - CART：`cp=0.001`, `minsplit=10`, `minbucket=5`
   - `cart_decision_path` 出图文件名尊重 `figure_title`
5. `merge_table2_dual_bmd_panels.R`（显式 `--panel-a/--panel-b` → 两侧 Multivariable S5）
6. `summary_results/Figures` 按设计编号对齐 Fig1–6 + `pub_figure_ensure_formats`

## Logs

- `logs/task10_qct_20260922_133533.log`（首跑）
- `logs/task10_dxa_20260922_133654.log`（首跑）
- `logs/task10_qct_full_20260922_134050.log`（BMI+CART 修复后）
- `logs/task10_dxa_full_20260922_134253.log`
- `logs/task10_merge_table2_*.log`
- `logs/task10_pub_figures_*.log`

## Key output dirs

| 路径 | 内容 |
| --- | --- |
| `by_index/QCT_vBMD/` | 主链 + 核 B + CART；四目录已有 |
| `by_index/DXA_T_min/` | Panel B 回归短链；四目录已有 |
| `summary_results/Tables/` | 设计口径 Table 1–4（含双 Panel Table 2） |
| `summary_results/Figures/{pdf,png,tiff,image_information}/` | 设计口径 Figure 1–6 × 四目录 |

## Acceptance (§8)

| 项 | 结果 |
| --- | --- |
| Table 1–4 | **PASS**（`summary_results/Tables/`） |
| Figure 1–6 | **PASS**（summary 四目录；无根目录平铺 PDF） |
| κ 有限 | **PASS**（Cohen κ binary OP = 0.3158，n=208） |
| QCT_only n=40 | **PASS**（discordance Table S5 列头 `QCT_only_OP N=40`） |
| CART 叶标签中文 | **PASS**（图面「首选 DXA」「必须 QCT」） |
| Table3/4 ↔ Fig4/5 同源 | **PASS**（同 `diagnostic_vs_fracture` 产物） |
| Figures 四目录 | **PASS**（summary 6×3 + QCT/DXA by_index 亦已导出） |

## Concerns（不阻塞交付）

1. ~~**设计 Fig2 = 多因素 OR 森林**~~ → **已修复**（见下方 Fix notes）。  
2. **by_index 自动重排**：QCT 根 Figures 中 CART 被顺延为 Fig7；**以 `summary_results/Figures` 设计编号为准**。  
3. **锁协变量**：config 写了 Age+BMI+bCTX+P1NP+VitD+PTH，但 UV/VIF 筛选后实际进多因素的集合可能小于锁池（暴露轴仍强制保留在表行）；Fig2 仅画表中有 OR 的优先行（P1NP/VitD/PTH 未入最终多因素则图中不出现）。  
4. **CART 规则表**：xlsx 目前主要落 Splits 页；叶标签以 Fig6 图面为准。  
5. **QCT Figures 补充箱线**：重跑后残留部分重复 S 编号箱线图（不影响 summary 主文 6 图）。

## Fix notes — Fig2 multivariable OR forest（2026-09-22）

- **问题**：summary Figure 2 误用亚组森林（`Figure 2. Subgroup Forest analyses of QCT vBMD`），与设计「多因素 OR 森林」不符。  
- **脚本**：`scripts/redraw_fig2_mv_or_forest.R`  
  - 解析 `summary_results/Tables/Table 2. … (QCT Panel A, DXA Panel B).csv` 中 `OR (lo-hi, p…)`  
  - 优先行：Age / BMI / bCTX / P / Osteocalcin / QCT vBMD（Panel A）与 DXA T min（Panel B）；跳过 discordance / QCT OP / need QCT / cat  
  - 双面板堆叠 `forestploter` 森林图  
- **归档**：旧亚组 Fig2 → `summary_results/Figures/_archive/`（pdf/png/tiff/md）  
- **新 Fig2 题名**：`Figure 2. Multivariable OR for vertebral fracture (QCT vs DXA BMD axes)`  
- **四目录**：`pdf/` + `png/` + `tiff/` + `image_information/` 均已有；`pub_figure_formats_status` ok；无根目录平铺 PDF  
- **NO git commit**（按任务要求）

## Decisiontree

已更新 `Decisiontree/decision_tree_osteoporosis_dxa_qct_personalized.md`：开跑状态 → **已跑**。
