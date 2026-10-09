# 单库发病 ML 预测定稿 Implementation Plan

> **For agentic workers:** implement task-by-task; verify on `08_术中低体温症`.

**Goal:** 单库发病 ML 预测发表包：主图 Fig1–5 连续（ML=Fig3）；主/附表全部顺延；仅胜出分位；train/val 标题清晰；修 python/code-bundle。

**Architecture:** 改 `incidence_batch_ml_pub_figure_*`、`ml_dual_pub_table_curate`、`pub_caption_strip_parentheses`、overrides 闸门、`pub_figure_export`、`index_code_bundle_validate`；对本课题跑一次 curate finalize。

**Tech Stack:** R

## Global Constraints

- 主图：1 Flowchart → 2 RCS → 3 ML 2×4 → 4 SHAP → 5 Subgroup
- 主表：1 Baseline → 2 Logistic(胜出) → 3 ML train → 4 ML val；无 tertile/binary
- 附表全部顺延且 train/val 标签不可剥
- Figure S1：仅 LASSO → 上下拼 S2A+S2B；其它单方法直接升 S1；≥2 方法才韦恩
- 全 ML dual 单库发病预测默认生效

---

### Task 1: 主图编号

- [ ] `incidence_batch_ml_pub_figure_target_bn`：无 cor/km 时 ML→Fig3, SHAP→Fig4, Subgroup→Fig5
- [ ] 排序权重同步

### Task 2: 表 curate 顺延

- [ ] 单库也走完整 role 重编号
- [ ] 非胜出 logistic 标 drop
- [ ] ML train/val → Table 3/4
- [ ] imputation/DeLong/NRI 分 train/val 角色后连续 S 号

### Task 3: 标题保留 train/val

- [ ] `pub_caption_strip_parentheses` 保留 training/validation set
- [ ] shorten 不把插补压成同一短标题

### Task 4: 闸门 + python + code bundle

- [ ] overrides：`force_export=FALSE`, `gate_enable=TRUE`（发病 logistic）
- [ ] python3 fallback
- [ ] validate 按唯一源路径

### Task 5: 本课题重排验证

- [ ] 对 `【success】Preop_Cr` 跑 curate + export_pub_figures
- [ ] 列出 Tables/Figures 确认连续编号
