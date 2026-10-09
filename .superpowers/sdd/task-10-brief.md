### Task 10: 授权后开跑 + 四目录发表图

**Files:**
- Runtime under `{STUDY}/by_index/...`
- Modify: `Decisiontree/decision_tree_osteoporosis_dxa_qct_personalized.md` 状态表

**Gate:** 仅当用户明确「可以跑/开跑」后执行本 Task。

- [ ] **Step 1: 跑 QCT 主 config 全 pipeline**

```bash
Rscript run/incidence/run_incidence_single.R \
  --config /mnt/g/02block_result/10_osteoporosis/personalized/config_osteo_fracture_qct.R
```

- [ ] **Step 2: 跑 DXA config（核 A Panel B）**
- [ ] **Step 3: `merge_table2_dual_bmd_panels.R`**
- [ ] **Step 4: `pub_figure_ensure_formats` 对汇总 Figures**

```r
# 在引擎 R 中
source("R/pub_figure_export.R")
pub_figure_ensure_formats(file.path(Sys.getenv("OSTEO_PERSONALIZED_ROOT"), "summary_results", "Figures"))
```

- [ ] **Step 5: 验收对照 spec §8**

- Table1–4、Fig1–6 存在  
- Table3/4 与 Fig4/5 数字同源  
- κ 有限；QCT_only n=40  
- CART 叶标签中文  
- Figures 四目录；无根目录平铺 PDF  
- 更新 Decisiontree 落地状态为「已跑」

---

## Spec coverage（自审）

| Spec 要求 | Task |
| ---- | ---- |
| Prep / 无 Sex / need_QCT | T1 |
| 列审阅 / disease_vars | T2 |
| dxa_qct_agreement | T3–T4 |
| diagnostic_vs_fracture | T5 |
| modality_discordance_profile | T6 |
| catalog | T7 |
| 发病 pipeline + cart | T8 |
| Table2 双 Panel | T9 |
| 开跑 + 四目录 + 验收 | T10 |
| 方案1 主文精简 / Age 补充 | T5 strata_supplemental + T8 config |
| 不新建以外的 ML 竞品 | 未列入（YAGNI） |

## Placeholder scan

无 TBD/TODO；CART 结局与锁变量已写死；开跑门控在 T10。

---

## Execution handoff

Plan complete and saved to `docs/superpowers/plans/2026-09-22-osteoporosis-dxa-qct-personalized.md`.

两种执行方式：

1. **Subagent-Driven（推荐）** — 每 Task 新开子代理，Task 间复审  
2. **Inline Execution** — 本会话按 `executing-plans` 连续做，关键点暂停

选哪个？选 1 或 2 即可。（未说「开跑」前我只做到 T1–T9 的代码/单测，不动全量拟合。）
