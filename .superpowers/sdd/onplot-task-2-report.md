# Task 2 Report: detailed_body 强制输出「图上标注」段

**Date:** 2026-08-26  
**Scope:** Wire Task 1 annotation helpers into `.pub_figure_detailed_body` (RCS/KM/Forest + ROC/maxstat title prefix).  
**Out of scope:** checkpoint harvest (Task 3), RCS/KM block changes, git commits.

---

## Summary

`.pub_figure_detailed_body` now always emits a literal **图上标注** section for RCS, KM, and Forest figures. When `meta$findings$rcs|km|forest` is populated, helper lines from Task 1 are appended; otherwise an explicit **未收获** placeholder is written. ROC and maxstat branches prefix existing numeric bullet lists with **图上标注：** when findings exist. Flowchart unchanged (no forced 图上标注).

---

## TDD Evidence

### Step 1 — Add failing assertions

Extended `tests/test_pub_figure_export.R` after Flowchart tests with four blocks:

| Block | meta injection | Key assertions |
|-------|----------------|----------------|
| RCS with data | `findings$rcs` → MIMIC Model2 P-overall/P-non-linear/cutoff | `图上标注`, `P-overall = 0.001`, `P-non-linear = 0.116`, `0.52` |
| RCS empty | `findings = list()` | `图上标注`, `未收获` |
| KM | `findings$km` → eICU logrank_p=0.023 | `图上标注`, `Log-rank`, `0.023` |
| Forest | `findings$forest` → Overall HR 1.2 | `图上标注`, `Overall`, `1.20` |

### Step 2 — RED (expected fail)

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_pub_figure_export.R
```

```
Error: grepl("图上标注", rcs_txt) is not TRUE
Execution halted
```

First new assertion failed: RCS md body lacked **图上标注** before implementation.

### Step 3 — Implementation

**File:** `R/pub_figure_export.R` → `.pub_figure_detailed_body`

| Branch | Change |
|--------|--------|
| **RCS** | After Table 2 summary: `图上标注（与面板一致）：` + `.pub_figure_rcs_annotation_lines(find$rcs)` or 未收获 placeholder |
| **KM** | After Table 2 summary: `图上标注：` + `.pub_figure_km_annotation_lines(find$km)` or 未收获 placeholder |
| **Forest** | After Table 2 summary: `图上标注（按图面行摘录）：` + `.pub_figure_forest_annotation_lines(find$forest)` or 未收获 placeholder |
| **maxstat** | When `find$maxstat` non-empty: prefix section with `图上标注：` before `各库切点：` |
| **ROC** | When `find$roc` non-empty: prefix section with `图上标注：` before `各库判别指标：` |
| **Flowchart** | No change (逐步人数段 retained) |

Labels use **P-overall** / **P-non-linear** (not P-overall / P for non-linearity variants).

### Step 4 — GREEN

```bash
Rscript tests/test_pub_figure_onplot_annotations.R
# test_pub_figure_onplot_annotations: OK

Rscript tests/test_pub_figure_export.R
# test_pub_figure_export: OK
```

Both test files pass.

---

## Files Changed

| File | Change |
|------|--------|
| `R/pub_figure_export.R` | `.pub_figure_detailed_body` RCS/KM/Forest/ROC/maxstat branches |
| `tests/test_pub_figure_export.R` | +4 onplot integration test blocks (~55 lines) |

---

## Sample Output Snippets (from test run)

**RCS (with findings):**
```
图上标注（与面板一致）：

- MIMIC Model2：P-overall = 0.001；P-non-linear = 0.116；cutoff = 0.52
```

**RCS (empty findings):**
```
图上标注（与面板一致）：

- 未收获：各库 RCS panel_stats / P-overall / P-non-linear / cutoff
```

**KM:**
```
图上标注：

- eICU：Log-rank P = 0.023；cutoff = 1.25
```

**Forest:**
```
图上标注（按图面行摘录）：

#### eICU

- Overall：1.20 (95%CI 1–1.4)
- Sex: Male：1.30 (95%CI 0.9–1.8)；P for interaction = 0.120
```

---

## Constraints Verified

- [x] No `## 标识` / `## 技术` in generated md (existing tests still pass)
- [x] Forest CI uses `formatC(digits=2)` → `1.20` in output
- [x] No RCS/KM block modifications
- [x] No checkpoint harvest (Task 3)
- [x] No git commits

---

## Concerns / Follow-ups

1. **Task 3 dependency:** Production md will show **未收获** until `pub_figure_harvest_findings` populates `meta$findings$rcs|km|forest` from checkpoints/Tables.
2. **Forest Overall row:** Test uses `1.2` input; helper formats as `1.20` — consistent with Task 1 spec.
3. **maxstat/ROC:** Only prefixed when findings exist; no empty-state 未收获 line added (brief did not require it for those branches).

---

## Commits

None (per task constraint).
