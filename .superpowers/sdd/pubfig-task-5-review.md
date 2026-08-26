# Task 5 Review: 竞争风险 + 通用单流水线 `export_pub_figures` 收口

**Reviewer:** code-review subagent  
**Date:** 2026-08-20  
**Scope:** Verify implementation against brief, global constraints, and dual-slot skip requirement (independent test re-run).

---

## Verdict

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

**Review path:** `.superpowers/sdd/pubfig-task-5-review.md`

---

## Spec checklist (brief)

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Hook `export_pub_figures` before `cli_alert_success` in `competing_pub_export` | ✅ | `18block_competing_pub_export.R` L298–341 before L341 success |
| Multi-db: detect ≥2 `-DB.` tags → `dual_db_combine_paired_figures(..., figures_dir=fig_dir)` then export | ✅ | L298–318 combine; L325–338 export with `combined = combined_flag` |
| Lazy-source `R/pub_figure_export.R`; non-fatal `tryCatch` + warning | ✅ | L321–338 |
| Hook `export_pub_figures` at `run_pipeline` end, after `pub_renumber_pub_dir` | ✅ | `pipeline_runner.R` L844–847 renumber; L853–872 export |
| Dual-slot guard: skip per-DB worker `Figures/` export | ✅ | L860–862 `is_dual_slot` from `config$dual_db$current_db` |
| Skip if `Figures/pdf/` already exists (Task 2 finalize / block hook idempotency) | ✅ | L862 `!dir.exists(file.path(figs, "pdf"))` |
| `meta` uses config exposure/outcome/databases; `combined = FALSE` at pipeline tail | ✅ | L864–868 |
| Regression guards extended | ✅ | `tests/test_result_review_guards.R` L506–530 |
| `Rscript tests/test_pub_figure_export.R` + guards | ✅ | Re-run 2026-08-20 — both OK |
| Git commit | N/A | Skipped per global constraints (no `.git`) |

---

## Dual-slot skip verification (review focus)

| Check | Status | Evidence |
|-------|--------|----------|
| Worker sets `dual_db$current_db` before `run_pipeline` | ✅ | `incidence_batch_apply_db_overrides` L1970; shared layer L2101; `run/ml/run_ml_dual.R` L88; `ml_dual_batch_runner.R` L777 |
| `is_dual_slot` TRUE when `current_db` non-empty | ✅ | `pipeline_runner.R` L860–861 |
| Export gated on `!isTRUE(is_dual_slot)` | ✅ | L862 |
| Aggregate export remains Task 2 finalize | ✅ | `incidence_batch_finalize_index_outputs` L1924–1945 unchanged |
| Shared-layer runs also skip (not aggregate) | ✅ | `incidence_batch_run_shared_layer` sets `current_db` L2101; output under `_shared/<DB>/` |
| Competing block export + pipeline tail double-call safe | ✅ | Block creates `Figures/pdf/` first; tail skips via `pdf/` existence check |
| Per-DB worker would NOT export tagged drafts into four dirs | ✅ | `current_db` set → `is_dual_slot` TRUE → no `export_pub_figures` at tail |

**Conclusion:** Dual-slot skip logic is **correct** for all documented dual-batch worker entry points. Per-DB worker `run_pipeline` shutdown does **not** call `export_pub_figures` on slot `Figures/`.

---

## Global constraints

| Constraint | Status |
|------------|--------|
| Aggregate top level: four subdirs only after export | ✅ | `export_pub_figures` moves/deletes top-level PDFs (Task 1) |
| Multi-db: combine before export; per-DB drafts not in aggregate four dirs | ✅ | Competing hook combines when ≥2 DB tags; finalize path unchanged |
| Single-db: finals to four dirs | ✅ | Competing single-db + `run_pipeline` tail |
| No step-level intermediate mutation | ✅ | Only root/slot `Figures/` targets |
| Missing pair: warn, keep single-sided, export | ✅ | Pre-existing combine behavior |
| Grouping not hardcoded in these hooks | ✅ | No tertile/quartile literals; competing meta omits grouping (N/A for competing) |
| No git commit | ✅ | Compliant |

---

## Independent verification (review session)

```text
$ Rscript tests/test_pub_figure_export.R
test_pub_figure_export: OK

$ Rscript tests/test_result_review_guards.R
test_result_review_guards: OK
```

Guard assertions confirmed:

- `export_pub_figures(figs` appears after `pub_renumber_pub_dir` in `pipeline_runner.R`
- `is_dual_slot` present in same file
- `export_pub_figures` before `cli_alert_success("文献级导出完成"` in competing block
- `dual_db_combine_paired_figures` present in competing block

---

## Findings

### Critical

*None.*

### Important

1. **Path-based dual guard omitted (defense in depth).** Brief Step 2 notes an additional check: skip when path matches `*/<DB>/Figures`. Implementation relies solely on `config$dual_db$current_db`. All standard dual-batch workers set `current_db`, so behavior is correct today; a misconfigured run with `current_db = NULL` but slot `output_dir` could still export per-DB drafts. Optional hardening: derive slot path from `dual_db_slot_path_name()` and compare to `figs`.

2. **No behavioral unit test for dual-slot skip.** Guards are source-order / string presence only (`grep("is_dual_slot")`). Recommend a small test: mock config with `current_db = "mimic"`, temp `Figures/` without `pdf/`, assert export hook would not run (or simulate the condition block).

3. **Competing combine-before-export ordering not guarded.** Test asserts export before `cli_alert_success` but not `dual_db_combine_paired_figures` before `export_pub_figures`. Runtime order is correct (L308–338); mirror Task 2 optional hardening.

4. **Non-fatal errors (exit 0).** Both hooks use `tryCatch` + `cli_alert_warning` only — parity with Tasks 2/4. Operators must watch logs for export/combine failures.

5. **Export hook outside `sync_all_block_pub_outputs` block.** Export runs even when sync helper is absent; renumber runs only inside sync. Pre-existing pattern; not a Task 5 regression.

6. **No end-to-end competing batch smoke.** Source guards + export unit test only; full competing multi-db batch not exercised in CI.

---

## Quality assessment

Implementation matches brief snippets, places hooks at the correct lifecycle points, and correctly prevents dual-batch worker `run_pipeline` from exporting per-DB slot figures. The `pdf/` subdirectory idempotency cleanly avoids double export when `competing_pub_export` runs inside the same pipeline. Guards and smoke tests pass.

**Approved** for integration with Tasks 1–4.

---

## Re-review after fix

**Reviewer:** code-review subagent  
**Date:** 2026-08-20  
**Fix pass scope:** `pipeline_figures_is_dual_slot()` + strengthened guards / unit checks

### Verdict

| Dimension | Result |
|-----------|--------|
| **Spec** | **PASS** |
| **Quality** | **Approved** |

### Prior Important findings — disposition

| # | Prior finding | Status |
|---|---------------|--------|
| 1 | Path-based dual guard omitted | ✅ **Resolved** — `pipeline_figures_is_dual_slot()` (L632–660): `current_db`; when `dual$enable`, `basename(dirname(figs))` vs sanitized `primary`/`secondary`/`tertiary`/`databases`; `by_index/<ix>/<slot>/Figures` regex |
| 2 | No behavioral unit test for dual-slot skip | ✅ **Resolved** — `test_result_review_guards.R` L521–541: per-DB path → TRUE; aggregate `by_index/<ix>/Figures` → FALSE; `current_db` set → TRUE |
| 3 | Competing combine-before-export not guarded | ✅ **Resolved** — L553–558: `combine < export < cli_alert_success` ordering asserted |
| 4 | Non-fatal errors (exit 0) | ⚠️ **Open (design)** — unchanged; parity with Tasks 2/4 |
| 5 | Export hook outside `sync_all_block_pub_outputs` | ⚠️ **Open (pre-existing)** — not a Task 5 regression |
| 6 | No end-to-end competing batch smoke | ⚠️ **Open** — guards + export unit test only |

### Fix-pass verification

```text
$ Rscript tests/test_pub_figure_export.R
test_pub_figure_export: OK

$ Rscript tests/test_result_review_guards.R
test_result_review_guards: OK
```

Helper behavior confirmed against standard dual-batch layout: slot paths use the same sanitized display names as `dual_db_slot_path_name()`; shared-layer `_shared/<DB>/Figures` is caught via parent-dir match when `dual$enable` is TRUE.

### Findings

#### Critical

*None.*

#### Important

1. **Non-fatal export failures (exit 0).** Both `competing_pub_export` and `run_pipeline` tail still use `tryCatch` + `cli_alert_warning` only. Operators must watch logs for combine/export skips.

2. **No end-to-end competing multi-db batch smoke.** CI covers source guards, `pipeline_figures_is_dual_slot` unit checks, and `test_pub_figure_export.R`; a full competing dual-batch run is still untested.

3. **Export hook remains outside `sync_all_block_pub_outputs`.** Renumber runs only inside sync; export always runs when conditions match. Pre-existing lifecycle split; acceptable but worth noting for operators debugging renumber vs export order.

### Quality assessment

Fix pass closes all three actionable Important items from the first review. Dual-slot skip is now defense-in-depth (`current_db` + path heuristics under `dual$enable`) with behavioral regression coverage. **Approved** for integration with Tasks 1–4.
