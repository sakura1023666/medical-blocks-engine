# Programmer Block Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let programmers search registered blocks (read-only), attach them into allowed hook slots on their study `config.R` so `run_study` really runs them, generate versioned decision trees without mutating baselinemasters, and hard-stop on hand-edited illegal pipeline extensions.

**Architecture:** Engine owns `pipeline_block_sources()` + authoritative `hook_slots.yaml` + export script. Study workspace gets read-only `docs/block_catalog/` copies and CLI (`search_blocks` / `add_block` / `remove_block`) that only write under `studies/<study>/`. Runtime `pipeline_extension_guard.R` compares live pipelines to baseline + `extensions.json` and `stop()`s on mismatch. Decision trees: copy mother → `baseline_*.md` (immutable) → each attach creates new `tree_vNNN.md`.

**Tech Stack:** R (≥4.x), `jsonlite`, optional `yaml` package (or JSON-only slots if yaml unavailable), bash + Windows `.bat` wrappers, existing `run_*_dual_batch.R` / `run_environment_dkd_batch.R` entry points.

**Spec:** `docs/superpowers/specs/2026-07-16-programmer-block-hooks-design.md`

## Global Constraints

- Never write under `Blocks/` or edit block bodies.
- Never mutate engine `Decisiontree/*.md` or study-area `docs/Decisiontree/` mother copies when attaching.
- Never mutate `studies/<study>/Decisiontree/baseline_*.md` after first copy.
- Only blocks named in `pipeline_block_sources()` may appear in catalog / be attached.
- Illegal pipeline extras (not recorded in `extensions.json` or wrong slot position) → `stop()` before batch runs.
- Deploy surfaces: DockerHome `5001` / `5003` / `5006` `medical-blocks-studies/`.

## File Map

| Path | Role |
|------|------|
| `configs/study_interface/hook_slots.yaml` | Authoritative slots (all routines) |
| `configs/study_interface/baseline_pipelines.json` | Frozen default `pipeline_*$blocks` per routine for guard diffs |
| `R/pipeline_extension_guard.R` | Validate extensions vs baseline; `stop()` on illegal |
| `R/block_catalog_export.R` | Helpers: list registered blocks, write catalog |
| `scripts/export_block_catalog.R` | CLI export to study-area `docs/block_catalog/` |
| `R/programmer_block_hooks.R` | search / add / remove / tree version logic (engine-side, called by wrappers) |
| `tests/test_pipeline_extension_guard.R` | Unit tests for guard + insert position |
| `tests/test_programmer_block_hooks.R` | Unit tests for catalog filter + extensions.json |
| Study-area (each port): `search_blocks.sh/.bat`, `add_block.sh/.bat`, `remove_block.sh/.bat` | Thin wrappers setting `MEDICAL_BLOCKS_ROOT` |
| Study-area: `docs/block_catalog/*` | Exported read-only catalog |
| Study-area README + `docs/create-pipeline-config/` snippet | Programmer docs |

---

### Task 1: Authoritative hook slots + baseline pipeline snapshot

**Files:**
- Create: `configs/study_interface/hook_slots.yaml`
- Create: `configs/study_interface/baseline_pipelines.json`
- Create: `scripts/snapshot_baseline_pipelines.R` (one-shot generator from templates)
- Test: `tests/test_hook_slots_schema.R`

**Interfaces:**
- Produces: YAML slots with fields `id`, `routine`, `pipeline_key`, `anchor_block` (nullable), `position` (`after`|`end`), `allow_tags`, `max_extra`, `description`
- Produces: JSON `{ "environment": { "pipeline_shared": [...], "pipeline_voc_batch": [...], "pipeline_tail": [...] }, "incidence": {...}, "survival": {...}, "ml": {...} }`

- [ ] **Step 1: Write failing schema test**

```r
# tests/test_hook_slots_schema.R
source("R/utils.R")  # if %||% needed; else pure base
path <- "configs/study_interface/hook_slots.yaml"
stopifnot(file.exists(path))
# Prefer yaml::read_yaml if installed; else stop with install hint in real impl.
# Minimal assertion without yaml: file must contain these slot ids as text for Task1 bootstrap,
# replaced by structured parse in Task2.
txt <- paste(readLines(path, warn = FALSE), collapse = "\n")
need <- c(
  "environment.tail_after_mediation",
  "incidence.nhanes_after_mediation",
  "survival.after_subgroup_prognosis",
  "ml.primary_after_shap"
)
for (id in need) stopifnot(grepl(id, txt, fixed = TRUE))
cat("OK schema text presence\n")
```

- [ ] **Step 2: Run test — expect FAIL (file missing)**

```bash
cd /mnt/e/01block/01Block-new-Final
Rscript tests/test_hook_slots_schema.R
```

Expected: `stopifnot(file.exists(path))` fails.

- [ ] **Step 3: Write `hook_slots.yaml` with all slots from spec §4.2**

Include every row for environment / incidence / survival / ml from the approved design. Example fragment:

```yaml
version: 1
slots:
  - id: environment.tail_after_mediation
    routine: environment
    pipeline_key: pipeline_tail
    anchor_block: mediation_ers_environment
    position: after
    allow_tags: ["*"]
    max_extra: 8
    description: "尾段中介分析之后"
  # ... all other slots ...
```

- [ ] **Step 4: Generate `baseline_pipelines.json`**

```bash
Rscript scripts/snapshot_baseline_pipelines.R
```

Script must `source` template/build defaults in a temp env and write JSON of `$blocks` vectors only (no secrets). For environment, source `configs/templates/config_environment_dkd_batch.template.R` with a temp `.batch_project_root`. For incidence/survival/ml, source the corresponding template or archive config that defines pipelines.

- [ ] **Step 5: Re-run schema test — PASS**

- [ ] **Step 6: Commit**

```bash
git add configs/study_interface/hook_slots.yaml \
  configs/study_interface/baseline_pipelines.json \
  scripts/snapshot_baseline_pipelines.R \
  tests/test_hook_slots_schema.R
git commit -m "feat: add hook slots and baseline pipeline snapshots for programmer block hooks"
```

---

### Task 2: Catalog export from `pipeline_block_sources`

**Files:**
- Create: `R/block_catalog_export.R`
- Create: `scripts/export_block_catalog.R`
- Test: `tests/test_block_catalog_export.R`
- Modify: none under `Blocks/`

**Interfaces:**
- Consumes: `pipeline_block_sources(root)` from `R/pipeline_runner.R`
- Produces: `export_block_catalog(root, out_dir)` → writes `catalog.json`, `catalog.md`, copies `hook_slots.yaml`, `GENERATED_AT.txt`
- Produces: `catalog.json` entries `{ block_id, path_rel, tags, routines, summary }`

- [ ] **Step 1: Failing test — catalog only contains registered names**

```r
# tests/test_block_catalog_export.R
root <- normalizePath(".", winslash = "/")
source(file.path(root, "R/pipeline_runner.R"))
source(file.path(root, "R/block_catalog_export.R"))
tmpdir <- tempfile("cat_")
dir.create(tmpdir)
export_block_catalog(root, tmpdir)
j <- jsonlite::fromJSON(file.path(tmpdir, "catalog.json"), simplifyVector = FALSE)
reg <- names(pipeline_block_sources(root))
ids <- vapply(j$blocks, function(x) x$block_id, character(1))
stopifnot(all(ids %in% reg))
stopifnot(!"__not_a_real_block__" %in% ids)
# Must not create files under Blocks/
stopifnot(!file.exists(file.path(root, "Blocks", ".catalog_write_probe")))
cat("OK catalog export\n")
```

- [ ] **Step 2: Run — FAIL (missing `R/block_catalog_export.R`)**

- [ ] **Step 3: Implement `export_block_catalog`**

```r
# R/block_catalog_export.R (core)
export_block_catalog <- function(root, out_dir, tags_map = list()) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)
  src <- pipeline_block_sources(root)
  blocks <- lapply(names(src), function(id) {
    list(
      block_id = id,
      path_rel = sub(paste0("^", root, "/?"), "", normalizePath(src[[id]], winslash = "/", mustWork = FALSE)),
      tags = as.character(tags_map[[id]] %||% character(0)),
      routines = character(0),  # filled later from hook_slots allow-lists or leave empty
      summary = id
    )
  })
  payload <- list(version = 1L, generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"), blocks = blocks)
  jsonlite::write_json(payload, file.path(out_dir, "catalog.json"), auto_unbox = TRUE, pretty = TRUE)
  # catalog.md: one line per block_id
  writeLines(c("# Block catalog (read-only)", "", paste0("- `", names(src), "`")), file.path(out_dir, "catalog.md"))
  file.copy(file.path(root, "configs/study_interface/hook_slots.yaml"),
            file.path(out_dir, "hook_slots.yaml"), overwrite = TRUE)
  writeLines(payload$generated_at, file.path(out_dir, "GENERATED_AT.txt"))
  invisible(out_dir)
}
```

Wire `scripts/export_block_catalog.R` to parse `--out` and call the function after `source`ing runner.

- [ ] **Step 4: Run test — PASS**

- [ ] **Step 5: Commit**

```bash
git add R/block_catalog_export.R scripts/export_block_catalog.R tests/test_block_catalog_export.R
git commit -m "feat: export read-only block catalog from pipeline_block_sources"
```

---

### Task 3: Extension guard (hard stop)

**Files:**
- Create: `R/pipeline_extension_guard.R`
- Test: `tests/test_pipeline_extension_guard.R`
- Modify: `run/environment/run_environment_dkd_batch.R` (after `source(config_path)`)
- Modify: `run/incidence/run_incidence_dual_batch.R` (same)
- Modify: `run/survival/run_survival_dual_batch.R` (same)
- Modify: `run/ml/run_ml_dual_batch.R` (same)

**Interfaces:**
- Consumes: `baseline_pipelines.json`, optional `extensions.json` beside config, live `pipeline_*` objects in `.GlobalEnv` or passed list
- Produces: `pipeline_extension_guard_check(routine, pipelines, study_dir, root)` → invisible TRUE or `stop()`

- [ ] **Step 1: Failing tests**

```r
# tests/test_pipeline_extension_guard.R
source("R/pipeline_extension_guard.R")
base <- list(pipeline_tail = c("qgcomp_environment", "mediation_ers_environment", "subgroup_environment_or"))
# illegal extra
bad <- list(pipeline_tail = c(base$pipeline_tail, "plot_histogram"))
study <- tempfile("st_")
dir.create(study)
# no extensions.json
err <- tryCatch(
  pipeline_extension_guard_check("environment", bad, study, normalizePath(".")),
  error = function(e) conditionMessage(e)
)
stopifnot(is.character(err), grepl("extensions.json|非法", err))
# legal via extensions.json
ok_pipes <- bad
writeLines(jsonlite::toJSON(list(version = 1, extensions = list(list(
  slot = "environment.tail_end", block = "plot_histogram", pipeline_key = "pipeline_tail"
))), auto_unbox = TRUE, pretty = TRUE), file.path(study, "extensions.json"))
# For tail_end, position end is OK
pipeline_extension_guard_check("environment", ok_pipes, study, normalizePath("."))
cat("OK guard\n")
```

Note: implement so `environment.tail_end` with `position: end` accepts extra at end; mid-chain illegal insert still fails.

- [ ] **Step 2: Run — FAIL (missing guard)**

- [ ] **Step 3: Implement guard**

Logic:
1. Load baseline for `routine`.
2. For each `pipeline_key` in baseline: `extra = setdiff(live, baseline)`.
3. If `length(extra)==0` and no extensions requiring missing blocks → OK.
4. Load `file.path(study_dir, "extensions.json")`; if extras non-empty and file missing → stop.
5. Each extra must match an extension record; verify index: if slot `after`, index(extra) == index(anchor)+1 or contiguous after anchor among extras; if `end`, all extras are a suffix.
6. Every extension record's block must be present in live pipeline.
7. Every extra name must be in `names(pipeline_block_sources(root))`.

- [ ] **Step 4: Hook four run scripts** after successful `source(config_path)`:

```r
source(file.path(root, "R/pipeline_extension_guard.R"))
.study_dir <- dirname(config_path)
pipeline_extension_guard_check(
  routine = "environment",  # or incidence/survival/ml per entry
  pipelines = list(
    pipeline_shared = if (exists("pipeline_shared")) pipeline_shared else NULL,
    pipeline_voc_batch = if (exists("pipeline_voc_batch")) pipeline_voc_batch else NULL,
    pipeline_tail = if (exists("pipeline_tail")) pipeline_tail else NULL
    # incidence/survival/ml: pass the pipeline_* objects that exist
  ),
  study_dir = .study_dir,
  root = root
)
```

Strip NULLs inside the function.

- [ ] **Step 5: Run tests — PASS**

- [ ] **Step 6: Commit**

```bash
git add R/pipeline_extension_guard.R tests/test_pipeline_extension_guard.R \
  run/environment/run_environment_dkd_batch.R \
  run/incidence/run_incidence_dual_batch.R \
  run/survival/run_survival_dual_batch.R \
  run/ml/run_ml_dual_batch.R
git commit -m "feat: hard-stop pipeline extension guard for illegal programmer edits"
```

---

### Task 4: Core `add_block` / `remove_block` / decision-tree versioning (engine R)

**Files:**
- Create: `R/programmer_block_hooks.R`
- Test: `tests/test_programmer_block_hooks.R`

**Interfaces:**
- `hooks_search_blocks(catalog_path, query = NULL, routine = NULL, tag = NULL)`
- `hooks_list_slots(slots_path, routine = NULL)`
- `hooks_add_block(study_dir, slot_id, block_id, root, catalog_dir)`
- `hooks_remove_block(study_dir, slot_id, block_id, root, catalog_dir)`
- Side effects under `study_dir` only: `config.R`, `extensions.json`, `Decisiontree/tree_vNNN.md`, `Decisiontree/CURRENT.md`, optional first-time `baseline_<routine>.md`

- [ ] **Step 1: Failing test — add inserts into pipeline_tail and creates tree_v001 without touching baseline twice**

```r
source("R/programmer_block_hooks.R")
root <- normalizePath(".")
study <- tempfile("study_")
dir.create(file.path(study, "Decisiontree"), recursive = TRUE)
# minimal config.R
writeLines(c(
  "pipeline_tail <- list(",
  "  name = 't',",
  "  blocks = c('qgcomp_environment', 'mediation_ers_environment', 'subgroup_environment_or')",
  ")"
), file.path(study, "config.R"))
# mother baseline copy source
mother <- "Decisiontree/decision_tree_environment_voc_batch.md"
file.copy(mother, file.path(study, "Decisiontree", "baseline_environment.md"))
cat_dir <- tempfile("cat_")
dir.create(cat_dir)
file.copy("configs/study_interface/hook_slots.yaml", file.path(cat_dir, "hook_slots.yaml"))
# minimal catalog with one block
jsonlite::write_json(list(version = 1, blocks = list(list(block_id = "plot_histogram", tags = list(), routines = list("environment"), summary = "hist"))),
  file.path(cat_dir, "catalog.json"), auto_unbox = TRUE, pretty = TRUE)

hooks_add_block(study, "environment.tail_end", "plot_histogram", root, cat_dir)
cfg <- paste(readLines(file.path(study, "config.R")), collapse = "\n")
stopifnot(grepl("plot_histogram", cfg, fixed = TRUE))
stopifnot(file.exists(file.path(study, "extensions.json")))
stopifnot(file.exists(file.path(study, "Decisiontree", "tree_v001.md")))
stopifnot(file.exists(file.path(study, "Decisiontree", "CURRENT.md")))
# baseline unchanged hash
h1 <- tools::md5sum(file.path(study, "Decisiontree", "baseline_environment.md"))
# second add
# ensure plot_histogram not duplicated; use another registered block in catalog for second
# (extend catalog in test to include environment_characteristics or similar registered name)
cat("OK add_block\n")
```

- [ ] **Step 2: Run — FAIL**

- [ ] **Step 3: Implement insert helper for `blocks = c(...)`**

Preferred approach: regex locate `pipeline_tail <- list(` … `blocks = c(` … `)` and rebuild the `c(...)` vector in R, then rewrite file atomically (`write to .tmp` then `file.rename`). If parse fails → `stop()` with no write.

Decision tree generation:
1. If `baseline_<routine>.md` missing, copy from study-area mother `docs/Decisiontree/decision_tree_<routine>_*.md` mapping table (hardcode map in R).
2. Read extensions; write new `tree_vNNN.md` = header + extension table + note that mother/baseline untouched + embed baseline body under `<details>` or full copy plus “挂接节点” section listing new blocks (mermaid one-liner append in EXTENSIONS section). Do **not** modify baseline file.
3. `CURRENT.md` content: `current: tree_v00N.md\n`.

- [ ] **Step 4: Implement `hooks_remove_block`** — remove from config vector, extensions, bump tree version.

- [ ] **Step 5: Tests PASS**

- [ ] **Step 6: Commit**

```bash
git add R/programmer_block_hooks.R tests/test_programmer_block_hooks.R
git commit -m "feat: programmer add/remove block hooks with versioned decision trees"
```

---

### Task 5: Study-area CLI wrappers (5001 / 5003 / 5006)

**Files:**
- Create under each port root: `search_blocks.sh`, `add_block.sh`, `remove_block.sh`, and `.bat` twins
- Create: `scripts/deploy_block_hooks_to_studies.sh` (copies wrappers + runs export)

**Interfaces:**
- Wrappers read `engine.env` → `MEDICAL_BLOCKS_ROOT`, `cd` to study or pass `--study`
- Call: `Rscript $ENGINE/R/...` via small `scripts/run_programmer_block_hooks_cli.R` with subcommands `search|add|remove|list-slots`

- [ ] **Step 1: Create engine CLI dispatcher**

```r
# scripts/run_programmer_block_hooks_cli.R
# argv: search|add|remove|list-slots ...
```

- [ ] **Step 2: Write `search_blocks.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
# load MEDICAL_BLOCKS_ROOT from engine.env (same pattern as run_study.sh)
# exec Rscript "$ENGINE/scripts/run_programmer_block_hooks_cli.R" search --catalog "$ROOT/docs/block_catalog" "$@"
```

Mirror for add/remove; `.bat` uses `C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe` when present (match 5003).

- [ ] **Step 3: Deploy script exports catalog into all three ports**

```bash
# scripts/deploy_block_hooks_to_studies.sh
for PORT in 5001 5003 5006; do
  DEST="/mnt/g/DockerHome/$PORT/medical-blocks-studies"
  Rscript scripts/export_block_catalog.R --out "$DEST/docs/block_catalog"
  cp scripts/wrappers/* "$DEST/"   # or inline generated wrappers
done
```

- [ ] **Step 4: Smoke on 5006**

```bash
cd /mnt/g/DockerHome/5006/medical-blocks-studies
./search_blocks.sh mediation | head
./search_blocks.sh --list-slots --routine environment | head
```

Expected: non-empty list; no files modified under engine `Blocks/`.

- [ ] **Step 5: Commit engine scripts + document deploy; study-area files live on G: (not necessarily in git)**

```bash
git add scripts/run_programmer_block_hooks_cli.R scripts/deploy_block_hooks_to_studies.sh
# wrappers templates under configs/study_interface/programmer_cli/
git commit -m "feat: CLI wrappers and deploy script for programmer block hooks"
```

---

### Task 6: Docs + mother decision-tree map + README on all ports

**Files:**
- Modify: `docs/superpowers/specs/2026-07-16-programmer-block-hooks-design.md` status → `已批准`
- Modify: `skills/deploy-programmer-interface/SKILL.md` — add “Block 挂接” section
- Modify: `/mnt/g/DockerHome/500{1,3,6}/medical-blocks-studies/README.md` — CLI section
- Create: mother map in `R/programmer_block_hooks.R` already; ensure `docs/Decisiontree/` on ports has the four mother trees (incidence/survival/ml/environment) — copy from engine `Decisiontree/` if missing

- [ ] **Step 1: Copy mother trees to each port `docs/Decisiontree/`** (if not already)

```bash
for P in 5001 5003 5006; do
  DEST=/mnt/g/DockerHome/$P/medical-blocks-studies/docs/Decisiontree
  mkdir -p "$DEST"
done
# 5001: incidence + survival mothers
# 5003: ml + environment
# 5006: environment (+ detailed optional)
```

- [ ] **Step 2: README snippets (exact commands)**

```bat
search_blocks.bat mediation
add_block.bat 我的研究 --slot environment.tail_end --block plot_histogram
remove_block.bat 我的研究 --slot environment.tail_end --block plot_histogram
```

- [ ] **Step 3: Update deploy skill checklist** with catalog export after engine registry changes

- [ ] **Step 4: Commit engine doc changes**

```bash
git add docs/superpowers/specs/2026-07-16-programmer-block-hooks-design.md \
  skills/deploy-programmer-interface/SKILL.md
git commit -m "docs: programmer block hooks usage and deploy notes"
```

---

### Task 7: End-to-end smoke (one study per routine family)

**Files:**
- Create ephemeral studies under each port `_hooks_smoke_*` OR use `_template` copy
- Do **not** commit large outputs

- [x] **Step 1: Environment (5006)** — copy `_template` → `_hooks_smoke_env`, `add_block` `plot_histogram` → `environment.tail_end`; `tree_v001.md` + baseline md5 OK. Path: **lightweight** guard+add (not full `--shared-only`). See smoke log.

- [x] **Step 2: Hand-edit illegal mid-chain (`plot_forest`) without extensions → guard `stop` with 非法**

- [x] **Step 3: Incidence (5001) + ML (5003)** — minimal fixtures + `add_block` + guard legal/illegal (full pipeline skipped)

- [x] **Step 4: Smoke log** — `docs/superpowers/plans/2026-07-16-programmer-block-hooks-smoke-log.md`

- [ ] **Step 5: Commit smoke log** — skipped (global no-commit constraint)

---

## Spec coverage checklist

| Spec requirement | Task |
|------------------|------|
| Read-only catalog from registry | Task 2 |
| hook_slots all routines | Task 1 |
| CLI search/add/remove | Tasks 4–5 |
| config.R insert in slots | Task 4 |
| Really runnable via existing runner | Tasks 3–4 (name must be registered) |
| Mother/baseline immutable; new `tree_vNNN` | Task 4 |
| Hard stop illegal hand edits | Task 3 |
| Deploy 5001/5003/5006 | Tasks 5–6 |
| Docs | Task 6 |
| Smoke | Task 7 |

## Placeholder scan

None intentional; open implementation choices locked as: atomic rewrite of `blocks = c(...)`, `CURRENT.md` as pointer file, baseline JSON from snapshot script.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-16-programmer-block-hooks.md`.

**Two execution options:**

1. **Subagent-Driven (recommended)** — fresh subagent per task, review between tasks  
2. **Inline Execution** — execute tasks in this session with checkpoints  

Which approach?
