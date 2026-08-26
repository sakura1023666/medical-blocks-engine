# Task 6 Review: 发表图四目录约定文档

**Reviewer:** code-review subagent  
**Date:** 2026-08-20  
**Scope:** Verify docs change against brief, global constraints, and review package (read-only).

---

## Verdict

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

**Review path:** `.superpowers/sdd/pubfig-task-6-review.md`

---

## Spec checklist (brief)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| MANUAL「发表图」坑位新增四目录约定 bullet | ✅ | `docs/Blocks_catalog.md` L80 |
| 文案与 brief 一致 | ✅ | Verbatim match to brief Step 1 |
| 仅手改 MANUAL:PITFALLS，不碰 AUTO 段 | ✅ | L61–84 MANUAL; L86+ AUTO 未改 |
| `update_blocks_catalog.py` 未改 block 头则跳过 | ✅ | Report + review: 无 `register_block` 变更 |
| Git commit | N/A | Skipped per global constraints (no `.git`) |

**Inserted text (L80):**

> 汇总 `Figures/`（及交叉滞后 `summary_result/figure`）顶层只保留 `pdf/` `png/` `tiff/` `image_information/`；多库先拼图再导出；TIFF=LZW。

---

## Global constraints alignment

| Constraint | Status | Notes |
|------------|--------|-------|
| 汇总顶层只有四子目录 | ✅ | `pdf/` `png/` `tiff/` `image_information/` |
| TIFF LZW | ✅ | Explicit in bullet |
| 多库：先拼图再导出；分库底稿不进汇总四目录 | ✅ | 「多库先拼图再导出」；与 L79 双库拼图 bullet 衔接 |
| 单库终稿进四目录 | ⚠️ implicit | 未单列一句；由 Tasks 1–5 实现与 L79 上下文覆盖，brief 未要求 |
| 交叉滞后 `summary_result/figure` | ✅ | Bridges Task 4 wiring to operator docs |
| DPI 300 / RGB | ⚠️ informational | `pubfig-global-constraints.md` 有写；本 bullet 未写（brief 未要求） |
| No git commit | ✅ | Compliant |

---

## Placement & coherence

| Check | Status | Evidence |
|-------|--------|----------|
| 紧接双库 Figures 拼图坑点之后 | ✅ | L79 拼图/清扫 → L80 四目录 → L81 协变量 |
| 与 preceding bullet 不重复 | ✅ | L79 = 拼图与单图清扫；L80 = 导出后顶层结构 |
| MANUAL 边界完整 | ✅ | `<!-- MANUAL:PITFALLS -->` … `<!-- /MANUAL:PITFALLS -->` intact |

---

## Independent verification (review session)

```text
$ rg -n "汇总 \`Figures/" docs/Blocks_catalog.md
80:- 汇总 `Figures/`（及交叉滞后 `summary_result/figure`）顶层只保留 ...

$ rg -n "MANUAL:PITFALLS|BEGIN AUTO:dir_index" docs/Blocks_catalog.md
61:<!-- MANUAL:PITFALLS -->
84:<!-- /MANUAL:PITFALLS -->
86:<!-- BEGIN AUTO:dir_index -->
```

No code/tests required for this docs-only task.

---

## Findings

### Critical

*None.*

### Important

*None.*

### Informational

1. **DPI / RGB 未写入坑点。** 全局约束默认 DPI 300、RGB；若后续有人只读 catalog 不读 `pubfig-global-constraints.md`，可在 MANUAL 或 `R/pub_figure_export.R` 头注释交叉引用。非 brief 范围，可选增强。

2. **单库路径未显式一句。** 「多库先拼图再导出」已覆盖双库主路径；单库「不拼图、直接四目录」依赖 Tasks 1–2 实现。与 brief 一致，无需改 spec。

---

## Quality assessment

变更范围最小、位置合理：L79 讲拼图与清扫，L80 讲导出后顶层四目录，形成连贯的发表图交付说明。文案与 brief 逐字一致，且与 Tasks 1–5 的全局约束及交叉滞后路径对齐。**Approved** — docs task complete; no re-run required.
