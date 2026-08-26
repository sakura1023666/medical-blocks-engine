# Survival Dual-Batch Pub Figure Defaults Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the new main/supp figure numbering and content fixes the default for all survival dual-batch prognosis pipelines, and backfill ALBI deliverables.

**Architecture:** Extend existing per-block `figure_kind` / `figure_number` + `pub_figure_filepath_at` so fixed numbers work for both `main_figure` and `supp_figure`. Update survival template defaults; fix shared bugs (age `≥`, boxplot double page, subgroup `export_table`).

**Tech Stack:** R, existing `R/utils.R` pub helpers, Blocks under `05_boxplot` / `18_subgroup` / `20_mediation` / `27_KM` / `28_plot` / `13_roc`, survival dual-batch templates.

## Global Constraints

- Scope: survival dual-batch defaults only; do not change incidence dual-batch figure defaults.
- Main: Fig 1 flowchart, Fig 2 RCS, Fig 3 KM, Fig 4 subgroup forest.
- Supp: S1 cutoff, S2 boxplot, S3 mediation, S4 ROC.
- Subgroup numeric table: default `export_table = FALSE`.
- Prefer true Unicode `≥`; never leave bare `= 65`.
- Boxplot PDF must be one page.
- ALBI backfill under `prognosis_38902748/by_index/【success】ALBI`.

---

### Task 1: Extend `pub_figure_filepath_at` for supp figures

**Files:**
- Modify: `R/utils.R` (`pub_bump_main_figure_min`, `pub_figure_filepath_at`)

**Interfaces:**
- Produces: `pub_bump_supp_figure_min(min_id)`, `pub_figure_filepath_at(fig_dir, figure_id, caption, ext="pdf", bump_counter=TRUE, kind=c("main_figure","supp_figure"))`

- [ ] **Step 1: Add `pub_bump_supp_figure_min` and extend filepath helper**

```r
pub_bump_supp_figure_min <- function(min_id) {
  min_id <- as.integer(min_id)[1L]
  if (!is.finite(min_id) || min_id < 1L) return(invisible(NULL))
  cur <- as.integer(.pub_state$supp_figure %||% 0L)
  if (cur < min_id) .pub for_state$supp_figure <- min_id
  invisible(.pub_state$supp_figure)
}

pub_figure_filepath_at <- function(fig_dir, figure_id, caption, ext = "pdf",
                                   bump_counter = TRUE,
                                   kind = c("main_figure", "supp_figure")) {
  kind <- match.arg(kind)
  figure_id <- as.integer(figure_id)[1L]
  if (!is.finite(figure_id) || figure_id < 1L) {
    stop("pub_figure_filepath_at: figure_id 须为正整数。")
  }
  if (isTRUE(bump_counter)) {
    if (identical(kind, "supp_figure")) pub_bump_supp_figure_min(figure_id)
    else pub_bump_main_figure_min(figure_id)
  }
  pref <- pub_prefix(kind, figure_id)
  # ... same stem/filename logic as today ...
}
```

(Fix typo in real edit: `.pub_state$supp_figure`, not `.pub for_state`.)

- [ ] **Step 2: Smoke test in R**

```r
source("R/utils.R")  # or via MEDICAL_BLOCKS_ROOT load
.pub_state <<- list(main_figure = 1L, supp_figure = 0L)
p <- pub_figure_filepath_at("/tmp", 1L, "Cutoff", kind = "supp_figure")
stopifnot(grepl("Figure S1", basename(p)))
p2 <- pub_figure_filepath_at("/tmp", 3L, "KM", kind = "main_figure")
stopifnot(grepl("Figure 3", basename(p2)))
```

Expected: no error; basenames contain `Figure S1` and `Figure 3`.

---

### Task 2: Update survival dual-batch template defaults

**Files:**
- Modify: `configs/templates/config_survival_dual_batch.template.R`
- Modify: `configs/config_survival_dual_batch.R` if it embeds the same figure defaults
- Check: `configs/study_interface/survival_dual_batch_build.R` for injected defaults

- [ ] **Step 1: Set block defaults**

```r
km_strata = list(..., figure_number = 3L, ...)
plot_cutoff = list(
  ..., figure_kind = "supp_figure", figure_number = 1L, bump_counter = TRUE, ...
)
roc_simple = list(
  ..., figure_kind = "supp_figure", figure_number = 4L, bump_counter = FALSE, ...
)
boxplot = list(
  ..., figure_kind = "supp_figure", figure_number = 2L, bump_counter = FALSE, ...
)
mediation_prognosis = list(
  ..., figure_kind = "supp_figure", figure_number = 3L, bump_counter = TRUE, ...
)
subgroup = list(..., export_table = FALSE, ...)
subgroup_prognosis = list(
  ..., figure_kind = "main_figure", figure_number = 4L, bump_counter = TRUE, ...
)
```

Also set `km_binary$figure_number = 3L` if present (binary KM alternate path).

- [ ] **Step 2: Grep templates for old main 3–8 assignments and confirm updated**

Run: `rg "figure_number|figure_kind|export_table" configs/templates/config_survival_dual_batch.template.R`

---

### Task 3: Wire blocks to `kind=` and subgroup export gate

**Files:**
- Modify: `Blocks/28_plot/01block_plot_cutoff.R` — pass `kind = fig_kind` into `pub_figure_filepath_at`
- Modify: `Blocks/13_roc/02block_simple_ROC.R` — same when using fixed number
- Modify: `Blocks/05_boxplot/01block_boxplot.R` — use filepath_at for both main and supp when `figure_number` set
- Modify: `Blocks/20_mediation/01block_mediation_prognosis.R` — honor `figure_kind` + `kind=`
- Modify: `Blocks/18_subgroup/01block_subgroup_prognosis.R` — fixed figure number for forest; wrap table export in `export_table`
- Modify: `Blocks/18_subgroup/04block_subgroup_prognosis_continuous.R` — same `export_table` gate if it always exports
- Modify: `Blocks/27_KM/02block_km_strata.R` — ensure number 3 works (already main-only OK)

- [ ] **Step 1: plot_cutoff / ROC / boxplot / mediation pass `kind`**

Pattern:

```r
pub_figure_filepath_at(
  fig_dir, fig_no, fig_cap, ext = "pdf",
  bump_counter = isTRUE(bl_cfg$bump_counter %||% TRUE),
  kind = fig_kind
)
```

For boxplot: if `figure_number` finite, always use `pub_figure_filepath_at` with `kind=fig_kind` (not only when main).

- [ ] **Step 2: subgroup forest fixed number + export_table**

In `01block_subgroup_prognosis.R` around table export (~644):

```r
if (isTRUE(sub_cfg$export_table %||% FALSE)) {
  # existing export_sci_table ...
} else {
  cli::cli_alert_info("subgroup_prognosis: export_table=FALSE，跳过亚组数值表（森林图已覆盖）")
}
```

Pass `figure_number` / `figure_kind` into `subgroup_render_forest_figure` or set filename before save (match how other blocks name files). Inspect `subgroup_render_forest_figure` args and extend minimally if needed.

- [ ] **Step 3: Spot-check mediation uses `supp_figure` when configured**

---

### Task 4: Fix age `≥ 65` display

**Files:**
- Modify: `R/subgroup_forest_plot.R` and/or forest PDF device path
- Possibly: `Blocks/18_subgroup/01block_subgroup_prognosis.R` label creation (already `\u2265`)

- [ ] **Step 1: Reproduce** — confirm Levels entering plot still contain `\u2265`

- [ ] **Step 2: Fix rendering**

Preferred: forest PDF via cairo / font that has U+2265; if forestploter strips glyphs, sanitize display labels:

```r
# keep ≥; if device cannot, map only for draw:
# do NOT map ≥ → =
```

If Times pdf() drops ≥ to =, force `cairo_pdf` for subgroup forest or substitute a font known to work (`resolve_plot_font_family` + cairo).

- [ ] **Step 3: Regenerate one MIMIC forest page and `pdftotext` / PNG check — must not show `= 65`**

---

### Task 5: Fix boxplot double-page PDF

**Files:**
- Modify: `Blocks/05_boxplot/01block_boxplot.R`
- Possibly: `R/utils.R` `save_figure` / render path if double `print`

- [ ] **Step 1: Reproduce with minimal ggplot queue → confirm Pages=2 cause**

- [ ] **Step 2: Ensure plot_fn returns ggplot only; single `print` in renderer; no extra `print`/`plot` in closure**

- [ ] **Step 3: Regenerate ALBI boxplot; `pdfinfo` → `Pages: 1`**

---

### Task 6: ALBI backfill

**Files:**
- Create: `run/survival_dual_batch/fix_albi_pub_figures.R` (or `/tmp` then keep under `run/` if reusable)
- Modify on disk: ALBI `Figures/` + delete `Table 3-*`

- [ ] **Step 1: Rename mapping**

```
Figure 3*Cutoff*     → Figure S1*
Figure 4*Kaplan*     → Figure 3*
Figure 5*Subgroup*   → Figure 4*
Figure 7*Boxplot*    → Figure S2*
Figure 8*Mediation*  → Figure S3*
Figure 6*ROC*        → Figure S4*
```

Apply under root / eICU / MIMIC `Figures/` (and step dirs if present).

- [ ] **Step 2: Delete Table 3 subgroup xlsx/tex copies**

- [ ] **Step 3: Redraw forest + boxplot with fixed code; verify labels and page count**

- [ ] **Step 4: List final `Figures/` and `Tables/` for user confirmation**

---

### Task 7: Spec status + self-check

- [ ] Mark design spec status to 已批准/已实现
- [ ] Grep: no remaining template `figure_number = 7L` / `6L` as main for boxplot/ROC in survival template
- [ ] Confirm incidence templates untouched

---

## Spec coverage

| Spec section | Task |
| ------------ | ---- |
| 3.1 pub_figure_filepath_at supp | Task 1 |
| 3.2–3.3 template + block wiring | Tasks 2–3 |
| 3.4 age ≥ | Task 4 |
| 3.5 boxplot pages | Task 5 |
| 3.6 export_table | Task 3 |
| 4 ALBI backfill | Task 6 |
| 5 acceptance | Tasks 4–6 checks |
| 6 non-goals incidence | Task 7 |
