# 复用地图：NPC OS-ML 对话沉淀（2026-10-27）

本轮（鼻咽癌总生存 ML，`53_NPC/ml_40395549`）可复用能力**已进引擎**。新课题直接走 `Blocks/` / `R/` / 规则，**禁止**再在课题 `scripts/` 或 `/tmp` 堆 hotfix。

## 已进引擎（正式入口）

| 能力 | 入口 | 说明 |
|------|------|------|
| 单因素 Cox → Rubin | `Blocks/06_univariate/01block_univariate_prognosis.R` | `mi_coxph`；Rubin 时**保留** `id_column` 供对齐；脚注 `mi_append_table_footnotes` |
| ML 连续特征 Cox 表 → Rubin | `Blocks/10_cox/08block_cox_ml_continuous_batch.R` | 同上；分位切点锁操作层模板；`dt` 须带 ID |
| 多因素 Cox → Rubin | `Blocks/07_multivariate/01block_multivariate_prognosis.R` | `mi_coxph` + 兼容 `mi_pooled` conf.int 列名 |
| 分位 Cox（主文）→ Rubin | `Blocks/10_cox/03block_cox_quartile.R` | 早已挂 `mi_coxph` |
| Rubin API | `R/mi_rubin_pool.R` | `mi_coxph` / `mi_complete_aligned` / `mi_append_table_footnotes` |
| 插补铁律 | `.cursor/rules/mi_m5_rubin_pool.mdc` | m=5 + `rubin_pool=TRUE`；complete#1 仅操作层 |
| Fig1 无 Exclude 时主列居中 | `R/attrition_log.R` → `attrition_draw_pdf` | 相邻步 n 不降且无权重步 → `cx=0.50` |
| Methods 写 Rubin / complete#1 | `R/ml_index_summary_results.R` | 预后 ML finalize 自动文案 |

## 课题专用（勿升引擎）

| 文件 | 用途 |
|------|------|
| `02block_result/.../scripts/prepare_npc_model_data.R` | 原始表 → model_data：OS Time 日期重算、空白 OS Status→存活删失、EBV LOD、AJCC 归并 |
| 课题 `config.R` | `missing_threshold=0.4`、`rcs`/`km` 变量名单、attrition 步 |

## 已归档（禁止当入口）

课题 `scripts/_archive_oneoff/`：

- `polish_npc_pub.R` — 手绘 Fig1（已被引擎 attrition 居中替代）
- `redraw_fig2_rcs_row.R` — Fig2 RCS 热修（正式走 `rcs_prognosis`）

`/tmp/run_npc_*.R`、`/tmp/npc_*.log` — 一次性调试，不入库。

## 新课题检查清单

- [ ] `imputation`: `m=5L`, `rubin_pool=TRUE`, `complete_action=1L`
- [ ] `data$id_column` 与 `mice_row_ids` 可对齐；日志出现「Rubin 启用：保留 … 供 MI 行对齐」或 Cox 脚注含 Rubin's rules
- [ ] 单因素 / ML 连续 Cox / 多因素表脚注有 Rubin；**无**「回退单套 complete」刷屏仍当主推断
- [ ] Table1/S1/KM/RCS/ML 可用 complete#1；Methods 写清操作层 vs Rubin
- [ ] 无 Exclude 的 Fig1 主列居中（勿再手绘）
- [ ] 课题 `scripts/` 无复活 `_archive_oneoff` 或 `/tmp` hotfix

## 反例

- Methods 写 m=5 Rubin，S4/S6 却单套 `coxph` 且无脚注  
- UV 剥掉 ID 导致 `mi_coxph` 0/5 回退仍交差  
- 把 `prepare_npc_model_data.R` 当通用引擎入口  
- 继续维护 `polish_npc_pub.R` 当 Fig1 正式方案  
