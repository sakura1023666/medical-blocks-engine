# Task 3 Review: ≥3 库拼图 + `figures_dir`

**Reviewer:** code-review subagent  
**Date:** 2026-08-20  
**Scope:** Verify implementation against brief, global constraints, and implementer report (read-only; targeted test re-run only).

---

## Verdict

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

**Review path:** `.superpowers/sdd/pubfig-task-3-review.md`

---

## Spec checklist (brief)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Create `tests/test_dual_db_combine_n_panel.R` (Step 1) | ✅ | Matches brief verbatim; 3× CHARLS/ELSA/HRS → `Figure 2. RCS plot.pdf`, singles removed |
| RED → GREEN TDD (Steps 2–4) | ✅ | Report RED: only 2-DB combine, HRS single remained; GREEN log matches current run |
| `.dual_db_combine_cfg`: `tertiary` + `databases` vector | ✅ | `R/dual_db_combine_figures.R` L34–43 |
| `length(dbs_have) >= 2`: combine all resolved DBs in `order_dbs` | ✅ | L775–853: resolve → filter → N==2 pair / N>2 n-panel |
| N>2 → `.dual_db_compose_n_pdf` | ✅ | L850–853 |
| N==2 → existing `.dual_db_compose_pair_pdf` unchanged | ✅ | L842–848 |
| New `R/dual_db_compose_n_panel.py` (1×N row; N==4 → 2×2) | ✅ | `_grid_shape(n)` L136–140; R sets `layout=grid` when `length(paths)==4` L564 |
| Raster fallback for n-panel | ✅ | `.dual_db_compose_n_pdf_raster` L598–692; vector→raster in `.dual_db_compose_n_pdf` L694–714 |
| Replace hardcoded `(eICU\|MIMIC\|NHANES)` with config-driven pattern | ✅ | `.dual_db_per_db_tag_pattern(db_names)` L528–534; used in detection L758–762, same-role skip L802 |
| Output key without per-DB tag | ✅ | Parsed key `Figure 2. RCS plot.pdf`; test asserts |
| Consumes `.dual_db_parse_paired_figure_bn`, `.dual_db_panel_label` | ✅ | L768, L837–838; labels C/D via `LETTERS[[i]]` |
| Git commit (Step 5) | N/A | Skipped per global constraints (no `.git`) |

### `figures_dir` (plan / review scope extension)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Optional `figures_dir = NULL` on `dual_db_combine_paired_figures` | ✅ | L720–730; default `file.path(index_root, "Figures")` |
| Combine works outside default `Figures/` | ✅ | Independent smoke: `summary_result/figure` + 2-DB eICU/MIMIC → OK (review session) |

---

## Global constraints

| Constraint | Status |
|------------|--------|
| Multi-db: combine then `remove_singles`; per-DB drafts not in aggregate finals | ✅ | `remove_singles` deletes resolved inputs L865–872; purge via `dual_db_purge_single_db_figures(figs, tags=db_names)` L883–885 |
| Missing pair: warn, keep single-sided | ✅ | L788–791 unchanged behavior |
| Missing Value Overview excluded | ✅ | Pre-existing `.dual_db_is_missing_overview` + drop L737–741 |
| No step-level intermediate mutation | ✅ | Operates on caller-supplied figures directory only |
| No git commit | ✅ | Compliant |

---

## Independent verification (review session)

```text
$ Rscript tests/test_dual_db_combine_n_panel.R
✔ 多库拼图完成: 1 张（layout=auto; order=CHARLS, ELSA, HRS）
test_dual_db_combine_n_panel: OK
```

`figures_dir` smoke (2-DB, non-default path): **OK**.

---

## Findings

### Critical

*None.*

### Important

1. **`figures_dir` has no committed regression test.** Parameter is implemented and smoke-verified, but `tests/test_dual_db_combine_n_panel.R` only exercises default `index_root/Figures`. Recommend a small second block (or sibling test) before Task 4 wiring, so cross-lagged `summary_result/figure` paths cannot regress silently.

2. **`tests/test_result_review_guards.R` dual_db sections not re-run** (implementer disclosure). 2-DB inline smoke passed per report; full guard suite still advisable before integration sign-off.

### Minor

3. **Roxygen incomplete:** `@param config` still mentions only primary/secondary (L719); should document `tertiary`, `databases`, and `figures_dir` for downstream Task 4 callers.

4. **Alternate config path untested:** brief allows `dual_db$databases <- c(...)` without tertiary objects; logic supports it (L35–42) but no test asserts order/parsing via vector-only config.

5. **N==4 2×2 layout untested:** Python + raster paths both implement grid (L564, L615–616); acceptable for Task 3 scope but worth a follow-up fixture if 4-cohort studies are expected soon.

6. **`dual_db_purge_single_db_figures` default `tags`** still lists eICU/MIMIC/NHANES (L896–897); caller now passes dynamic `db_names` (L884), so runtime behavior is correct—defaults are misleading only for direct calls without `tags`.

---

## Quality assessment

Implementation matches brief interfaces and loop structure; CHARLS/ELSA/HRS detection no longer depends on hardcoded cohort names; n-panel vector compose with raster fallback mirrors existing pair-compose pattern; 2-DB path preserved. TDD evidence is credible and independently confirmed on the primary test.

Non-blocking gaps: `figures_dir` test coverage and guard re-run. **Approved** for Task 4 integration (`figures_dir = summary_result/figure`).

---

## Re-review after fix

**Reviewer:** code-review subagent  
**Date:** 2026-08-20  
**Scope:** Confirm Important findings from initial review are resolved; re-run targeted tests.

### Verdict

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

**Review path:** `.superpowers/sdd/pubfig-task-3-review.md`

### Important findings — resolution

| # | Initial finding | Status | Evidence |
|---|-----------------|--------|----------|
| 1 | `figures_dir` had no committed regression test | ✅ **Resolved** | `tests/test_dual_db_combine_n_panel.R` L35–57: second block uses `summary_result/figure`, `figures_dir = fig_sr`, asserts combined output + singles removed + `!dir.exists(.../Figures)` |
| 2 | `tests/test_result_review_guards.R` dual_db sections not re-run | ✅ **Resolved** | Fix pass re-run; independently confirmed exit 0, `test_result_review_guards: OK` |

### Independent verification (re-review session)

```text
$ Rscript tests/test_dual_db_combine_n_panel.R
✔ 多库拼图完成: 1 张（layout=auto; order=CHARLS, ELSA, HRS）
✔ 多库拼图完成: 1 张（layout=auto; order=eICU, MIMIC, HRS）
test_dual_db_combine_n_panel: OK

$ Rscript tests/test_result_review_guards.R
test_result_review_guards: OK
```

### Remaining findings

#### Critical

*None.*

#### Important

*None.*

#### Minor (unchanged, non-blocking)

1. **Roxygen incomplete:** `@param config` still documents only primary/secondary (L719); `tertiary`, `databases` not in roxygen.
2. **Alternate config path untested:** `dual_db$databases` vector-only config supported in code but not asserted in tests.
3. **N==4 2×2 layout untested:** Python/raster grid paths exist; no 4-cohort fixture yet.
4. **`dual_db_purge_single_db_figures` default `tags`** still lists eICU/MIMIC/NHANES; runtime uses dynamic `db_names` from caller.

### Quality assessment

Both Important gaps from the initial review are closed with committed test coverage and guard re-run. Spec requirements unchanged and still satisfied. **Approved** for Task 4 integration.
