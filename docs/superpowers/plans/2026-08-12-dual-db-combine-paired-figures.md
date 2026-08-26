# Dual-DB Paired Figures Combine — Implementation Plan

> **For agentic workers:** Execute task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** At dual-batch finalize, pair `-DB` publication PDFs into one A/B figure (no `Combined` in name), drop Missing Value Overview, and tighten KM/forest overflow; apply to all future dual projects.

**Architecture:** New `R/dual_db_combine_figures.R` implements pairing + PDF compose (magick/pdftools if present, else `pdftoppm` + `cairo_pdf`/`pdf`). Hook into `incidence_batch_finalize_index_outputs` after `mirror_dual_db_aggregate`. Templates default `export_missing_fig=FALSE` and `combine_figures$enable=TRUE`.

**Tech Stack:** R, pdftools/magick (optional), poppler `pdftoppm`, grid, cairo_pdf

## Global Constraints

- Aggregate `Figures/` keeps **only** combined PDFs for paired roles; per-DB subdirs untouched
- Output name = role key **without** `Combined` (e.g. `Figure 4. Subgroup….pdf`)
- Panel labels: `A. {primary}`, `B. {secondary}`
- Layout: stack for forest/KM; side for others
- Missing Value Overview: delete from aggregate; stop generating by default
- Do not fail hard on unpaired figures

---

### Task 1: Core combine module

**Files:**
- Create: `R/dual_db_combine_figures.R`
- Test: ad-hoc on `【success】BAR/Figures` copy

**Interfaces:**
- Produces: `dual_db_combine_paired_figures(index_root, config)` → invisible named list of outcomes

- [ ] Implement parse/pair/compose/delete as in spec §4–5
- [ ] Fallback renderer via `pdftoppm` when magick/pdftools missing
- [ ] Smoke-test on BAR Figures directory

### Task 2: Wire finalize + templates + source overflow

**Files:**
- Modify: `R/incidence_dual_batch_runner.R` (`incidence_batch_finalize_index_outputs`)
- Modify: `configs/templates/config_survival_dual_batch.template.R`
- Modify: `configs/templates/config_incidence_dual_batch.template.R`
- Modify: `Blocks/27_KM/02block_km_strata.R` (default size/margins)
- Modify: `R/subgroup_forest_plot.R` (margins / base_size defaults)
- Modify: live `prognosis_38902748/config_survival.R` if needed for BAR re-finalize

- [ ] Call combine after aggregate mirror
- [ ] Default config keys
- [ ] Mild KM/forest anti-overflow defaults
- [ ] Re-run combine on existing `【success】BAR` for acceptance

### Task 3: Spec status + acceptance check

- [ ] Mark design spec approved
- [ ] Verify BAR aggregate Figures checklist from spec §9
