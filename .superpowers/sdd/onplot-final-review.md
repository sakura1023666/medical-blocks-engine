# Final Senior Review — Pub Figure On-Plot Annotations (Tasks 1–9)

**Date:** 2026-08-26  
**Reviewer:** Senior Code Reviewer (whole-branch)  
**Scope:** Scheme 1 — block persists on-plot numbers → harvest → `image_information` 「图上标注」; Cursor rule upgraded. No git / no mass refresh.  
**Spec:** `docs/superpowers/specs/2026-08-26-pub-figure-onplot-annotations-design.md`  
**Plan:** `docs/superpowers/plans/2026-08-26-pub-figure-onplot-annotations.md`  
**Constraints:** `.superpowers/sdd/onplot-global-constraints.md`  
**Method:** Read-only review of spec/plan, review pkg, export diff, task reports, and current sources. Did not re-run test suites (Task 9 already green).

**Verdict: Needs fixes**

---

## Strengths

1. **Architecture matches Scheme 1.** Blocks write lightweight `ctx$results` scalars/lists; `pub_figure_harvest_findings` fills `rcs` / `km` / `forest`; `.pub_figure_detailed_body` always emits a 「图上标注」 section for RCS/KM/Forest (and prefixes ROC/maxstat when numbers exist). Single write path (`pub_figure_export.R`) is preserved — no parallel md templates.

2. **No fabricated P values.** `.pub_figure_harvest_normalize_rcs` returns `NULL` unless a real `rcs_*_panel_stats` key is present. Fixture `ix_miss` locks this. Missing evidence becomes 「未收获：…」, which matches spec §5 and the global constraint.

3. **P-value labels are locked to the agreed surface.** Helpers emit `P-overall` / `P-non-linear` with `< 0.001` or `formatC(..., digits=3, format="f")`. Prognosis plot legend (`.fmt_p_leg` in `01block_rcs_prognosis.R`) uses the same formula and the same Cox indices (`logtest[3]`, `coefficients[2,5]`). Incidence anova extractor uses `an[nrow(an), 3]` / `an[2, 3]`, matching the ggplot annotate cells.

4. **KM log-rank is numerically sourced, not OCR’d.** `km_binary` runs `survdiff` on the same `Surv(time, event) ~ Group` used for `ggsurvplot`. `km_strata` shares `.kms02_logrank_p_numeric` with the plot’s `.kms02_safe_logrank_p`, so figure text and checkpoint P share one computation.

5. **Forest harvest reuses existing `ctx$results$subgroup`** (no new table), with column-name fallbacks (`Variable`/`Point Estimate`/`Lower`/`Upper` + interaction grep) that match the subgroup blocks’ export schema.

6. **Cursor rule is complete and still `alwaysApply: true`.** Iron law 7, checklist items, and the RCS empty-talk anti-example are in place. Flowchart / four-directory layout / no `## 标识` / `## 技术` are untouched.

7. **TDD trail is real.** Task reports show RED→GREEN for helpers, detailed_body, harvest, extractors. Task 9: `test_pub_figure_onplot_annotations.R`, `test_pub_figure_export.R`, `test_pub_figure_profile_gate.R` all OK.

8. **Scope discipline.** No mass refresh of old studies; no git commit; NHANES/IPTW panel_stats built from already-computed `p_overall` / `p_nonlin` rather than refitting.

---

## Issues

### Critical (Must Fix)

None.

### Important (Should Fix before calling the feature done)

1. **Incidence (and NHANES/IPTW) RCS cutoffs in md are not the vlines on the default figure**

   - **Files:** `Blocks/15_rcs/02block_rcs_incidence.R` (~781–797); also `03block_rcs_nhanes.R` (~674–677), `04block_rcs_iptw_weighted.R` (~548–551). Prognosis 4-panel `m3_sig` is the same class of bug: `01block_rcs_prognosis.R` (~511–517 vs ~545–550).
   - **What’s wrong:** Spec §5 / iron law 7 require recording **on-plot** cutoffs. Incidence default is `cutoff_vlines = "primary"` — `.rci01_add_cutoff_vlines` draws **one** primary x. Panel stats still persist `res$cutoffs$all` (all OR=1 / peak intersections). When `length(all) > 1`, md lists cutoffs that are not drawn. NHANES/IPTW always attach `cut_use$all` to the Model2 entry. Prognosis stores `cut_use$all` on **Model2** even when vlines are on **Model3** (`show_cut_d`).
   - **Why it matters:** The whole feature exists so md matches the figure. Extra true cutoffs are still “not on the plot,” which is the same class of error as stuffing Table 2 HR into 「图上标注」.
   - **Fix:** Persist the exact `xs` vector passed to the vline drawer for that panel (incidence: result of `vline_mode`; prognosis: `cutC$all` on Model2 iff `show_cut_c`, `cutD$all` on Model3 iff `show_cut_d`). Empty `cutoffs` when that panel has no vlines.

2. **Harvest reads every `*.rds` in each DB checkpoint dir with no early exit**

   - **File:** `R/pub_figure_export.R` ~598–637.
   - **What’s wrong:** After priority-sorting names matching `rcs|km|subgroup`, the loop still `readRDS`s **all** remaining checkpoints (full `ctx` payloads: imputed data, models). It never breaks after `seen_rcs` / `seen_km_bin` / `seen_forest` are filled, and still walks km items on every file.
   - **Why it matters:** Dual-batch `export_pub_figures` / refresh will re-load tens of large checkpoints per index. Latency/memory risk on finalize; not a correctness bug (first-hit dedupe is sound).
   - **Fix:** Only open files whose basename matches `rcs|km|subgroup` (plus known aliases), and skip remaining files once RCS + forest + km_binary are filled **and** no unread `km*` files remain for strata.

These two are the only items I would not ship as “feature complete.” Item 1 is the spec invariant; item 2 is production cost.

### Minor (Nice to Have — defer)

Triaged from Tasks 1–7 plus review findings.

| ID | Source | Issue | Before merge? |
|----|--------|--------|----------------|
| M1 | Task 1 | Forest point estimate `formatC(digits=2)` vs CI `signif(..., 4)` (e.g. `1.20 (95%CI 1.01–1.42)`). Plan brief used `signif` for all three; test forced `1.20`. | **Defer.** Readable; matches forest plot 2-decimal HR convention. Unify later if desired. |
| M2 | Task 2 | KM/Forest empty-state tests only exist for RCS. Code paths do emit 「未收获」. | **Defer.** Optional coverage. |
| M3 | Task 3 | Harvest fixture is flat `index_root/<DB>/*.rds`, not nested step dirs. Production checkpoints are also flat (`pipeline_save_checkpoint`), so depth is OK. | **Defer.** |
| M4 | Task 3/6 | `db_dirs` hardcodes eICU/MIMIC + `checkpoints/.../nhanes|mimic`; no `index_root/NHANES` / CHARLS/ELSA/HRS. `nhanes` basename remapped to **eICU** (`~595`). This is the **dual-batch primary-slot convention** (`incidence_dual_batch_runner` treats nhanes/eicu/primary as the same slot), not a new bug. True NHANES studies using `export_pub_figures` will get eICU labels / miss `index_root/NHANES`. | **Defer** for dual-batch ICU landing. Track a follow-up if a dedicated NHANES pub-figure study is next. Do **not** blindly drop the remap — that would mislabel dual-batch eICU. |
| M5 | Task 4–5 | No full Cox/`lrm` block fixtures; extractors tested with synthetic `logtest` / anova matrices. | **Defer.** Indices are locked to the plot code; block tests would be heavy. |
| M6 | Task 6 | Same cutoff `$all` vs primary (elevated to Important #1). | **Fix** as Important #1. |
| M7 | Task 7 | `km_binary` inlines survdiff; strata uses `.kms02_logrank_p_numeric`. Both match their plot formulas. | **Defer.** DRY later. |
| M8 | Rule | Iron law 5 still lists only attrition/Table2/cutoff CSV/`simple_ROC.rds`/`plot_cutoff.rds`/`_batch_status.json`. New sources (`rcs_*_panel_stats`, `km_binary$logrank_p`, `subgroup`) live only in law 7. | **Defer** (or one-line amend in a follow-up). Not a behavior bug. |
| M9 | Task 2 | ROC/maxstat get 「图上标注」 only when findings exist; no empty 「未收获」 line. Plan Step 3 explicitly allowed this. Flowchart keeps stepwise n without forcing the four characters 「图上标注」. | **Defer.** Plan-aligned. |
| M10 | Harvest | Same `res` with both prognosis and incidence `panel_stats` keys keeps the first key in `.PUB_FIGURE_RCS_PANEL_STATS_KEYS` (prognosis). Dual-batch studies do not run both RCS flavors in one ctx. | **Defer.** |
| M11 | KM binary | Plot uses survminer `pval=TRUE`; md uses independent `survdiff`+`formatC`. Same test, possibly different printed digits vs survminer’s default. | **Defer.** |

---

## Plan alignment

| Spec / plan item | Status |
|------------------|--------|
| Scheme 1 persist → harvest → md | **Met** (Tasks 2–7 + 1) |
| RCS P-overall / P-non-linear / cutoff | **Met** for persistence and labels; **partial** for cutoff = on-plot vector (Important #1) |
| KM Log-rank / binary cutoff | **Met** |
| Forest Overall + subgroup + interaction P | **Met** (harvest `res$subgroup`) |
| ROC / maxstat / Flowchart keep or strengthen | **Met** (prefix 「图上标注」 when numbers exist; Flowchart unchanged) |
| 未收获, no fake P | **Met** |
| Cursor rule #7 + checklist + anti-example | **Met** (`alwaysApply: true`) |
| No mass refresh of old studies | **Met** |
| No four-dir / combine-figure changes | **Met** |
| No git commit | **Met** |
| Labels `P-overall` / `P-non-linear` | **Met** (incidence **figure** still says “P for overall / P for nonlinear”; md uses locked labels per plan 「锁定口径」) |
| Task 1 forest `signif` vs test `1.20` | Justified deviation (`formatC` on the point estimate only) |

No unexplained extra scope. Task 3 scanning **all** `*.rds` goes slightly beyond the plan’s “prefer rcs/km/subgroup names” and should be tightened (Important #2).

---

## Testing

- Task 9 evidence (not re-run):  
  `test_pub_figure_onplot_annotations.R` OK  
  `test_pub_figure_export.R` OK  
  `test_pub_figure_profile_gate.R` OK  
- Coverage is strong at **pure-function + tempfile harvest fixture** level: P formatting, Cox/LRM extractors, annotation lines, harvest keys (prognosis/incidence/nhanes), no-fake-P lock, strata KM, detailed_body injection + RCS empty state.
- Gaps (acceptable to defer): no live Cox/lrm/survdiff block test; no KM/Forest empty-md test; harvest fixture does not assert NHANES `db` label (so the eICU remap is invisible to CI); no test that panel `cutoffs` equal vline `xs`.

Add a small fixture for Important #1 when fixing: incidence `vline_mode=primary` with `all = c(0.5, 1.2)` must persist only `0.5`.

---

## Production readiness

- **New dual-batch MIMIC/eICU runs** after this code: RCS/KM/Forest md will populate once those blocks have run (old checkpoints without `panel_stats` / `logrank_p` correctly show 「未收获」). Forest can already fill from existing `subgroup` tables.
- **Refresh of old studies** is out of scope by design; `run/pub/refresh_image_information.R` will pick up new harvest only where checkpoint keys exist.
- **Backward compatible:** new result keys are additive; md structure still `# Figure` + `## 图面说明` + `## 分析上下文`.
- **Risks to watch on first real finalize:** (1) extra RCS cutoffs on incidence figures (Important #1); (2) harvest wall-clock from reading every checkpoint (Important #2); (3) true NHANES pub-figure studies inheriting dual-batch `nhanes`→eICU labels (M4, defer).
- **Documentation:** rule law 5 should eventually list the new harvest artifacts so agents do not treat `panel_stats` as illicit numbers.

---

## Recommendations

1. Patch Important #1 in the three RCS blocks (and prognosis Model2 vs Model3 vline assignment) so `cutoffs` == drawn xs. This is the only functional gap vs spec.
2. Narrow harvest `readRDS` to name-matched files + early exit (Important #2).
3. Optionally append `rcs_*_panel_stats` / `km_binary` / `subgroup` to rule iron law 5.
4. Do not drop `nhanes`→eICU remapping without a `meta$databases`-aware branch; dual-batch depends on it.
5. No mass refresh; no git until the user asks.

---

## Assessment

**Ready to merge? No — Needs fixes**

**Reasoning:** The branch delivers Scheme 1 correctly: persist, harvest, 「图上标注」, 未收获, locked P labels, and a global Cursor rule, with a solid TDD trail and no Critical defects. It is not feature-complete against spec §5 until RCS `cutoffs` equal the vlines actually drawn (incidence default `primary`, plus prognosis Model3-sig). Tighten harvest I/O at the same time. All listed Task 1–7 Minors except the cutoff mismatch can wait.

**Must fix before merge**
- Important #1 (on-plot cutoff vector)
- Important #2 recommended in the same patch if cheap; acceptable as immediate follow-up if cutoff lands first

**Can defer**
- M1–M5, M7–M11 (formatC/signif, extra tests, db_dirs/NHANES collision, block-level fixtures, KM DRY, rule law 5 wording, ROC empty-state)
