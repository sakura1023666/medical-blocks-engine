# simple_ROC Multivariable Default Implementation Plan

> **For agentic workers:** Execute task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make `simple_ROC` default to multivariable ROC using locked Model2 covariates; hard-stop if locked set empty; prognosis uses `event_var`.

**Architecture:** Change block defaults and outcome resolution in `02block_simple_ROC.R`; align survival/IPTW templates; pin ML templates to `univariate`; add guard tests + catalog pitfall.

**Tech Stack:** R Medical Blocks, pROC, existing `locked_multivariable_covariates`.

**Spec:** `docs/superpowers/specs/2026-08-14-simple-roc-multivariable-default-design.md`

## Global Constraints

- Do not commit unless user asks.
- ML pipelines: explicit `mode = "univariate"`, do not reorder `baseline_pipelines.json` ML blocks.
- Disease exclusion rules unchanged.

---

### Task 1: Guard tests first

**Files:**
- Modify: `tests/test_result_review_guards.R`

- [ ] Add: default `mode` when omitted is multivariable path (call block logic or document via `.sroc` + expected default string in block source grep).
- [ ] Add: multivariable + empty locked → `stop`.
- [ ] Add: prognosis outcome prefers `survival$event_var`.
- [ ] Run: `Rscript tests/test_result_review_guards.R` — expect FAIL until Task 2.

### Task 2: Block implementation

**Files:**
- Modify: `Blocks/13_roc/02block_simple_ROC.R`

- [ ] Default `mode` → `"multivariable"`.
- [ ] Empty locked covariates → `stop(...)`.
- [ ] Outcome: if study_type prognosis / survival event present, use `survival$event_var`.
- [ ] Update file header comments.
- [ ] Re-run guards — expect PASS.

### Task 3: Templates + catalog

**Files:**
- Modify: `configs/templates/config_survival_dual_batch.template.R`
- Modify: `configs/templates/config_incidence_iptw.template.R` (and any other roc_simple without mode)
- Modify: ML templates that enable simple_ROC → `mode = "univariate"`
- Modify: `docs/Blocks_catalog.md` MANUAL:PITFALLS

- [ ] Survival template: `mode = "multivariable"`, `covariate_source = "locked"`.
- [ ] IPTW incidence: same.
- [ ] ML: explicit univariate.
- [ ] Pitfall line for ROC locked default + hard stop + ML exception.

### Task 4: Smoke

- [ ] `Rscript tests/test_result_review_guards.R`
- [ ] `Rscript tests/test_locked_multivariable.R` if still relevant
- [ ] Mark spec success criteria done in notes
