# Task 4 Review: 交叉滞后 summary_result/figure mosaic + export

**Reviewer:** code-review subagent  
**Date:** 2026-08-20  
**Scope:** Verify implementation against brief, global constraints, and implementer report (read-only; targeted smoke re-run).

---

## Verdict

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

**Review path:** `.superpowers/sdd/pubfig-task-4-review.md`

---

## Spec checklist (brief)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Create `Blocks/54_cross_lagged_full/phases/export_summary_figures.R` | ✅ | File present; 96 lines |
| Resolve engine root via `MEDICAL_BLOCKS_ROOT` or study ancestor | ✅ | L9–17 |
| Source `utils.R`, `dual_db_combine_figures.R`, `pub_figure_export.R`, optional `cross_lagged_study_meta.R` | ✅ | L19–26 |
| Target `summary_result/figure/` | ✅ | L26–31 |
| Grouping from `cross_lagged_study_meta(study_root)$grouping` | ✅ | L33–39 |
| Relock fallback `phase3_relock_acceptance.txt` `main_grouping=` | ✅ | L40–46 |
| Detect cohorts from `-DB.` PDF tags + meta cohort order | ✅ | L48–64 |
| `dual_db_combine_paired_figures(..., figures_dir = fig)` — **no `dirname(fig)` hack** | ✅ | L78; grep confirms sole `figures_dir` usage in cross_lagged block |
| `export_pub_figures(fig, meta, config)` with `formats_dir/dpi/write_image_information` | ✅ | L74–76, L82–93 |
| Hook `collect_summary_result_generic.sh` | ✅ | L554–557 |
| Hook `collect_summary_result_hip.sh` | ✅ | L508–512 |
| Hook `collect_summary_result_circadian.sh` (via generic) | ✅ | `bash collect_summary_result_generic.sh "$@"` |
| Hook `collect_summary_result.sh` (`exec` → `bash`; local override export) | ✅ | L10–17, L33–37 |
| Smoke test | ✅ | Independent re-run below |
| Git commit | N/A | Skipped per global constraints (no `.git`) |

### Verification focus (review request)

| Check | Status | Evidence |
|-------|--------|----------|
| `figures_dir=` not `dirname` hack | ✅ | `export_summary_figures.R` L78; Task 3 param at `R/dual_db_combine_figures.R` L720–730 |
| Grouping from study meta, not hardcoded tertile | ✅ | No literal `"tertile"`/`"quartile"` in export script; injected via `meta_g` chain |
| Collect scripts hooked | ✅ | All four `collect_summary_result*.sh` paths reach `export_summary_figures.R` |
| Four format subdirs | ✅ | Smoke: root holds only `pdf/`, `png/`, `tiff/`, `image_information/` |

---

## Global constraints

| Constraint | Status |
|------------|--------|
| Aggregate figure top level: four subdirs only after export | ✅ | `export_pub_figures` moves top-level `Figure*.pdf` into subdirs and `unlink`s sources (`R/pub_figure_export.R` L160–214) |
| TIFF LZW, 300 DPI, RGB | ✅ | `pub_figures = list(dpi = 300L, ...)`; `.pub_figure_cfg()` hard-codes `tiff_compression = "lzw"` |
| Multi-db: combine + `remove_singles`; per-DB drafts not in aggregate finals | ✅ | `remove_singles = TRUE` in cfg L68; smoke confirms per-DB singles deleted after combine |
| Single-db: finals to four dirs | ✅ | `combine enable = length(dbs) >= 2L`; export always runs |
| Grouping in image_information from caller, not hardcoded | ✅ | `meta$grouping = meta_g` passed to `export_pub_figures` |
| Missing Value Overview excluded | ✅ | Pre-existing in `export_pub_figures` / combine |
| No step-level intermediate mutation | ✅ | Operates only on `summary_result/figure/` |
| No git commit | ✅ | Compliant |

---

## Independent verification (review session)

Temp study `.tmp/cl_export_review_smoke3` with three per-cohort PDFs (`Figure 2-CHARLS. …`, `-ELSA`, `-HRS`) plus single-panel `Figure 5. Change analysis.pdf`:

```text
$ Rscript Blocks/54_cross_lagged_full/phases/export_summary_figures.R .tmp/cl_export_review_smoke3
✔ 多库拼图完成: 1 张（layout=auto; order=CHARLS, ELSA, HRS）
export_summary_figures: .../summary_result/figure
```

Results:

- Combined `Figure 2. RCS plot between FI and Hip Fracture.pdf`; per-DB singles removed.
- Figure root: **only** `pdf/`, `png/`, `tiff/`, `image_information/` (no loose PDF/PNG).
- `pdf/` holds combined Figure 2 + single Figure 5.
- Rasterization succeeded for valid page-count PDFs (300 DPI).

---

## Findings

### Critical

*None.*

### Important

1. **Errors swallowed with exit 0.** Both `dual_db_combine_paired_figures` and `export_pub_figures` are wrapped in `tryCatch(..., message only)` (L77–94). Collect pipelines will not fail on mosaic/export errors. Acceptable for non-fatal hook parity with Task 2, but operators must watch log output.

2. **No committed regression test for cross-lagged export path.** Task 3 test covers combine; this script has no `tests/test_*` counterpart. Recommend a small smoke test (temp dir + `Figure N-DB.` stubs) before production collect runs.

3. **Local collect override caveat** (implementer disclosure). `collect_summary_result.sh` runs export after `collect_summary_result.local.sh` even when local script does not populate `summary_result/figure/` — export then no-ops or processes stale content. Document for study maintainers.

4. **Grouping precedence is study-meta-first.** `phase3_relock_acceptance.txt` is used only when `cross_lagged_study_meta()` returns empty grouping. For default hip temp dirs, meta returns `tertile` (correct per `R/cross_lagged_study_meta.R` L114); relock `quartile` is not overridden — consistent with quantile-scheme rule (meta is primary).

---

## Quality assessment

Implementation matches brief intent: Task 3 `figures_dir` is wired correctly (no directory-name workaround), grouping flows from study meta / relock acceptance without script-level hardcoding, all collect entry points invoke export after successful collect, and the four-format directory layout is enforced. Independent smoke confirms multi-cohort mosaic + clean root.

**Approved** for integration with Tasks 1–3.

---

## Re-review after fix

**Reviewer:** code-review subagent (re-review)  
**Date:** 2026-08-20  
**Trigger:** Fix pass added `tests/test_cross_lagged_export_summary_figures.R` per Important #2.

### Verdict (unchanged)

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

### Important #2 — regression test — **RESOLVED**

| Check | Status | Evidence |
|-------|--------|----------|
| Committed `tests/test_*` counterpart for export phase | ✅ | `tests/test_cross_lagged_export_summary_figures.R` (73 lines) |
| Temp study + per-cohort `-DB.` PDF stubs | ✅ | L18–24: three `Figure 2-CHARLS/ELSA/HRS. RCS plot.pdf` |
| Invokes `export_summary_figures.R` via `Rscript` | ✅ | L44–48; `MEDICAL_BLOCKS_ROOT` set to repo root (L38–42) |
| Asserts combined mosaic + four-format export | ✅ | L58–62: `pdf/` + `png/` + `tiff/` + `image_information/*.md` |
| Asserts clean figure root (no loose PDF) | ✅ | L64–65 |
| Asserts per-cohort singles removed | ✅ | L67–70 |
| Independent re-run | ✅ | `Rscript tests/test_cross_lagged_export_summary_figures.R` → `test_cross_lagged_export_summary_figures: OK` |

Test coverage complements Task 3 combine test by exercising the full cross-lagged export phase script end-to-end (combine → `export_pub_figures` → directory layout), not just the combine helper in isolation.

### Important #1 — tryCatch swallow — **Minor / accepted (unchanged)**

`export_summary_figures.R` L77–93 still wraps combine and export in `tryCatch(..., message only)`; collect pipelines exit 0 on mosaic/export failure. Fix pass intentionally left this unchanged — plan-aligned with Task 2 dual-batch finalize hook parity. Operators must watch log output. **Not a blocker.**

### Remaining findings

#### Critical

*None.*

#### Important

1. **Local collect override caveat** (Important #3, unchanged). `collect_summary_result.sh` runs export after `collect_summary_result.local.sh` even when local script does not populate `summary_result/figure/` — export then no-ops or processes stale content. Document for study maintainers.

2. **Grouping precedence is study-meta-first** (Important #4, unchanged / informational). `phase3_relock_acceptance.txt` applies only when `cross_lagged_study_meta()` returns empty grouping. Default hip temp dirs get `tertile` from meta; relock `quartile` is not overridden — consistent with quantile-scheme rule. Test writes relock file but does not assert grouping in `image_information` (acceptable for smoke scope).

### Spec / Quality summary

- **Spec:** All brief items remain satisfied; no implementation drift since initial review.
- **Quality:** Approved. Important #2 closed by substantive end-to-end regression test; remaining Important items are operational/documentation notes, not code defects.
