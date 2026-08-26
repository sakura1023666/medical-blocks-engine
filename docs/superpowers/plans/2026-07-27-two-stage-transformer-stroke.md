# Two-Stage Transformer Stroke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a MIMIC ischemic-stroke two-stage Transformer dual-track pipeline (Yang 2025 PCM + 双轨复现方案), with R shared front-end through baseline/cohort, Python training under `python/`, task-parallel workers, Feishu sync, and synthetic external-validation smoke.

**Architecture:** Shared R layer does clean→map→impute→baseline→cohort→timeseries→landmark→split once; workers run units like `L72_B_twostage` / `external_synthetic` via processx. Python package lives in `python/two_stage_transformer/` with CLI `python/block_two_stage_transformer.py` (migrated from `code/`). New R blocks only under `Blocks/71_*`.

**Tech Stack:** R 4.5.1 Windows `Rscript.exe`, PyTorch via Anaconda3, `processx`, Feishu bitable API, existing `R/pipeline_runner.R` + `R/python_literature.R`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-27-two-stage-transformer-stroke-design.md`
- R binary: `"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe"`
- Python binary: `C:/ProgramData/anaconda3/python.exe` (via `literature_python_bin()`)
- Data root (Windows in R): `G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421/data`
- Output: `Output/TwoStage_Transformer_Stroke/` with `mirror_pub_outputs_to_root = FALSE`
- New module only: `Blocks/71_two_stage_transformer_stroke/`
- Do **not** modify `Blocks/01–70`, `67_transformer_shortseq_full`, existing `run/transformer_shortseq/*`, or rewrite modes inside `python/block_literature_extensions.py`
- Feishu app_token: `RBjfb2iwmamW14s4WhKcS7kwnie` (process-local `Sys.setenv`; do not rewrite `.env.feishu` token file)
- Primary outcome: in-hospital death; split 7:2:1; geographic external uses synthetic data by default (`is_synthetic=TRUE`)
- Do not create a git commit unless the user explicitly requests one

## File map

| Path | Role |
|------|------|
| `Decisiontree/decision_tree_two_stage_transformer_stroke.md` | Pipeline decision tree |
| `code/README.md` | Pointer: runtime uses `python/` only |
| `python/two_stage_transformer/*.py` | Migrated model/data/train/eval/shap/synthetic |
| `python/block_two_stage_transformer.py` | `--mode` CLI |
| `python/requirements-two-stage-transformer.txt` | torch/sklearn/shap deps |
| `Blocks/71_two_stage_transformer_stroke/01–11block_*.R` | Cohort through pub_export |
| `R/pipeline_runner.R` | Append 71 block source mappings only |
| `R/tst_stroke_task_runner.R` | Shared + task dispatch + summary |
| `configs/templates/config_two_stage_transformer_stroke.template.R` | Single-run |
| `configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R` | Task-parallel |
| `run/two_stage_transformer_stroke/run_*.R` | Entries + worker |
| `run/feishu/run_feishu_setup_tst_stroke_tables.R` | Feishu tables |
| `scripts/smoke_tst_stroke_data_audit.R` | Column/outcome audit |
| `scripts/smoke_tst_stroke_python_synthetic.py` | Synthetic external CLI smoke |

**Reuse (source only):** `Blocks/02_data_clean`, `01_column_mappings`, `03_imputation`, `04_baseline/01block_baseline_binary.R`; call pattern from `67` + `R/python_literature.R`.

---

### Task 1: Decision tree + data audit smoke

**Files:**
- Create: `Decisiontree/decision_tree_two_stage_transformer_stroke.md`
- Create: `scripts/smoke_tst_stroke_data_audit.R`

**Interfaces:**
- Produces documented column candidates for config: patient id, admission time, death/discharge disposition, lab long-table time + feature columns.

- [ ] **Step 1: Write decision tree**

Create `Decisiontree/decision_tree_two_stage_transformer_stroke.md` with:

- Research question (院内死亡, landmark 24–120h)
- Mermaid: shared R front → task workers → validate/export
- Block table mapping 01–11
- Python modes list
- Skip rules: no real second-center external; synthetic only; no index-batch; `mirror=FALSE`
- Feishu / R / Python paths from spec

- [ ] **Step 2: Write audit smoke**

Create `scripts/smoke_tst_stroke_data_audit.R`:

```r
root <- normalizePath(getwd(), winslash = "/")
data_dir <- "G:/02block_result/11_ischemic stroke/two_stage_transformer_40041421/data"
if (!dir.exists(data_dir)) data_dir <- "/mnt/g/02block_result/11_ischemic stroke/two_stage_transformer_40041421/data"
stopifnot(dir.exists(data_dir))
e <- new.env()
rdata <- list.files(data_dir, pattern = "D01_baseline.*\\.RData$", full.names = TRUE)[1]
stopifnot(length(rdata) == 1, file.exists(rdata))
load(rdata, envir = e)
objs <- ls(e)
cat("RData objects:", paste(objs, collapse = ", "), "\n")
df <- e[[objs[1]]]
if (!is.data.frame(df)) {
  for (nm in objs) if (is.data.frame(e[[nm]])) { df <- e[[nm]]; break }
}
stopifnot(is.data.frame(df))
cat("dim=", paste(dim(df), collapse = "x"), "\n")
death_cand <- grep("death|mort|expire|hospital_expire|dod|discharge", names(df), TRUE, value = TRUE)
id_cand <- grep("subject|hadm|stay_id|patient|ID", names(df), TRUE, value = TRUE)
cat("death_candidates:", paste(head(death_cand, 20), collapse = ", "), "\n")
cat("id_candidates:", paste(head(id_cand, 20), collapse = ", "), "\n")
lab <- file.path(data_dir, "mimic-实验室指标-all-1~30天.csv")
stopifnot(file.exists(lab))
con <- file(lab, "r", encoding = "UTF-8"); on.exit(close(con), add = TRUE)
hdr <- readLines(con, n = 1L)
cat("lab_header_snip:", substr(hdr, 1, 300), "\n")
cat("AUDIT_OK\n")
```

- [ ] **Step 3: Run audit**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" scripts/smoke_tst_stroke_data_audit.R
```

Expected: `AUDIT_OK` plus non-empty `death_candidates` / `id_candidates`. If death column ambiguous, Task 3 config must set explicit `outcome_column` after human pick from printed list (do not invent).

---

### Task 2: Migrate `code/` → `python/two_stage_transformer/` + CLI

**Files:**
- Create: `python/two_stage_transformer/__init__.py`
- Create: `python/two_stage_transformer/model.py` (from `code/model_5day.py`)
- Create: `python/two_stage_transformer/dataloader.py` (from `code/custom_dataloader_5day.py`)
- Create: `python/two_stage_transformer/focal.py` (from `code/focalloss.py`)
- Create: `python/two_stage_transformer/prepare.py` (from `code/prepare_data.py`)
- Create: `python/two_stage_transformer/train.py` (from `code/main_5day.py`, add `arch=a1|a2|b`)
- Create: `python/two_stage_transformer/eval.py` (from `code/plot_roc_5day.py` + metrics CSV writer)
- Create: `python/two_stage_transformer/shap_plot.py` (from `code/shap_5day.py`)
- Create: `python/two_stage_transformer/baselines.py`
- Create: `python/two_stage_transformer/synthetic_external.py`
- Create: `python/block_two_stage_transformer.py`
- Create: `python/requirements-two-stage-transformer.txt`
- Create: `code/README.md`

**Interfaces:**
- Produces CLI: `python block_two_stage_transformer.py --mode <mode> --out-dir <dir> [args...]`
- Modes: `tst_prepare`, `tst_train_a1`, `tst_train_a2`, `tst_train_b`, `tst_baselines`, `tst_ablation`, `tst_calibrate`, `tst_shap`, `tst_external_synthetic`, `tst_external`
- `synthetic_external.generate(out_dir, n=200, n_days=5, n_hours=24, n_features=16, seed=42) -> Path` writing `patients.csv`/`events-like long CSV`/`labels` + npz

- [ ] **Step 1: Copy modules into package; keep algorithms intact**

Move logic from `code/*.py` into `python/two_stage_transformer/` with relative imports. Do not delete `code/*.py`; add `code/README.md`:

```markdown
# code/（只读参考）

运行时请使用 `python/block_two_stage_transformer.py` 与 `python/two_stage_transformer/`。
本目录保留原始 5day 脚本，流水线不再直接调用。
```

- [ ] **Step 2: Implement `synthetic_external.py`**

```python
def generate(out_dir: Path, n: int = 200, n_days: int = 5, n_hours: int = 24,
             n_features: int = 16, seed: int = 42) -> Path:
    rng = np.random.default_rng(seed)
    out_dir = Path(out_dir); out_dir.mkdir(parents=True, exist_ok=True)
    X = rng.normal(0, 1, size=(n, n_days, n_hours, n_features)).astype(np.float32)
    y = rng.integers(0, 2, size=(n,)).astype(np.int64)
    day_mask = np.ones((n, n_days), dtype=np.float32)
    meta = {"is_synthetic": True, "n": n, "seed": seed}
    np.savez_compressed(out_dir / "synthetic_external.npz", X=X, y=y, day_mask=day_mask,
                        feature_names=np.array([f"f{i}" for i in range(n_features)]))
    (out_dir / "meta.json").write_text(json.dumps(meta), encoding="utf-8")
    return out_dir
```

- [ ] **Step 3: Wire CLI `block_two_stage_transformer.py`**

Mirror argparse style of `block_literature_extensions.py` (`--mode`, `--out-dir`, `--data-path`, `--arch`, `--seed`, `--epochs`). For `tst_external_synthetic`: call `generate` then run eval/metrics stub writing `Table_External_Synthetic_Metrics.csv` with column `is_synthetic=TRUE`.

- [ ] **Step 4: Smoke synthetic mode**

```bash
"/mnt/c/ProgramData/anaconda3/python.exe" python/block_two_stage_transformer.py \
  --mode tst_external_synthetic \
  --out-dir Output/TwoStage_Transformer_Stroke/_smoke_synthetic \
  --seed 42 --epochs 1
```

Expected: exit 0; `meta.json` contains `"is_synthetic": true`; metrics CSV exists.

- [ ] **Step 5: Write requirements file**

`python/requirements-two-stage-transformer.txt`:

```
torch
numpy
pandas
scikit-learn
shap
tqdm
matplotlib
```

Install missing packages into the Anaconda env used by that python.exe (user-approved path only).

---

### Task 3: Config templates + thin run entries

**Files:**
- Create: `configs/templates/config_two_stage_transformer_stroke.template.R`
- Create: `configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R`
- Create: `run/two_stage_transformer_stroke/run_two_stage_transformer_stroke.R`
- Create: `run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R`
- Create: `run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_worker.R`

**Interfaces:**
- `config$project$mirror_pub_outputs_to_root <- FALSE`
- `config$data$rawdata_path` / `lab_long_path` / `outcome_column` / `id_column` from Task 1 audit
- `config$tst_stroke$landmarks <- c(24L,48L,72L,96L,120L)`
- `config$tst_stroke$split <- list(train=0.7, val=0.2, test=0.1, seed=42L)`
- `config$tst_stroke$external <- list(mode="synthetic", is_synthetic=TRUE, n=200L, seed=42L)`
- `config$feishu` with disease_label `11_IschemicStroke_TwoStageTransformer`, protocol `two_stage_transformer_stroke`, project_id `TST_STROKE_001`, app_token from env/process override
- Task-parallel template: `task_units` character vector of unit names; `pipeline_shared$blocks`; `branch_map` unit→blocks

- [ ] **Step 1: Write single-run template** including `pipeline$blocks` shared+full chain for smoke.

- [ ] **Step 2: Write task-parallel template** with units at least:

```r
c(
  "L72_B_twostage", "L72_A2_single", "L72_A1_repo",
  "L72_logistic", "L72_xgb", "L72_mlp", "L72_lstm",
  "L72_ablation_mask", "external_synthetic", "temporal_holdout"
)
```

(Full landmark×model matrix can be generated in runner from landmarks × model_families.)

- [ ] **Step 3: Thin run scripts** following `run/transformer_shortseq/run_transformer_aki_single.R` pattern: resolve root, `feishu_load_dotenv`, source utils/pipeline_runner/config, `run_pipeline` or task runner.

---

### Task 4: Shared-layer R blocks 01–04 (`tst_cohort` … `tst_split`)

**Files:**
- Create: `Blocks/71_two_stage_transformer_stroke/01block_tst_cohort.R`
- Create: `Blocks/71_two_stage_transformer_stroke/02block_tst_timeseries.R`
- Create: `Blocks/71_two_stage_transformer_stroke/03block_tst_landmark.R`
- Create: `Blocks/71_two_stage_transformer_stroke/04block_tst_split.R`
- Modify: `R/pipeline_runner.R` (append `.block_sources` entries for 71 only)

**Interfaces:**
- `tst_cohort` reads `ctx$data$imputed %||% cleaned`; writes `ctx$data$tst_cohort`, `ctx$results$tst_cohort` (n_in/n_out, exclusion counts); exports flowchart counts CSV
- `tst_timeseries` writes long CSV path under output `Tables/_tst_hourly_long.csv` and audit table
- `tst_landmark` writes `ctx$results$landmark_ids` list named `"24","48",...`
- `tst_split` writes patient id lists `train_ids.csv`/`val_ids.csv`/`test_ids.csv` and optional `temporal_*`; never fit imputer on test

- [ ] **Step 1: Implement `01block_tst_cohort.R` in R only** (include/exclude age≥18, valid death label, time zero = first hospital/ICU arrival per config; pause_point on missing outcome column).

- [ ] **Step 2: Implement timeseries + landmark + split** exporting files Python can consume (`patient,day,hour,<features>,label,los_days`).

- [ ] **Step 3: Register blocks in `pipeline_runner.R`** without changing existing keys.

- [ ] **Step 4: Shared-only smoke** after Task 3/5 wiring:

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R --shared-only
```

Expected: checkpoint under `checkpoints/.../_shared` and baseline + cohort artifacts; no Python train yet.

---

### Task 5: Train/eval/calibrate/shap/external R blocks 05–09 + Python hooks

**Files:**
- Create: `Blocks/71_two_stage_transformer_stroke/05block_tst_repo_a1.R`
- Create: `Blocks/71_two_stage_transformer_stroke/06block_tst_train_eval.R`
- Create: `Blocks/71_two_stage_transformer_stroke/07block_tst_calibration_dca.R`
- Create: `Blocks/71_two_stage_transformer_stroke/08block_tst_shap.R`
- Create: `Blocks/71_two_stage_transformer_stroke/09block_tst_external.R`

**Interfaces:**
- Each block calls `run_literature_python(root, mode=..., args=c("--out-dir", out, "--data-path", path, ...))` with `literature_python_script(..., name="block_two_stage_transformer.py")` — if helper only hardcodes literature script name, add optional `script=` argument **without breaking** existing callers (default remains `block_literature_extensions.py`).
- `tst_external`: if `config$tst_stroke$external$mode=="synthetic"`, force `--mode tst_external_synthetic` and stamp outputs with `is_synthetic`.

- [ ] **Step 1: Extend `literature_python_script` / `run_literature_python` with optional script name parameter (backward compatible).**

- [ ] **Step 2: Implement blocks 05–09** writing metrics tables under step dirs.

- [ ] **Step 3: Worker smoke**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_worker.R \
  --unit L72_B_twostage --epochs 1
```

Expected: metrics CSV for B at 72h; exit 0 or clear PAUSE reason.

---

### Task 6: Literature validate + pub export (10–11)

**Files:**
- Create: `Blocks/71_two_stage_transformer_stroke/10block_tst_literature_validate.R`
- Create: `Blocks/71_two_stage_transformer_stroke/11block_tst_pub_export.R`

**Interfaces:**
- Writes `Table_Literature_Validation.csv` with rows for原文 Day5 AUC 0.92、外推 AUC 0.73/0.84；columns `target`, `observed`, `status` ∈ {match, migrate, skip, synthetic}
- `tst_pub_export` copies/renames publication figures into step folder only; **must not** call `mirror_pub_output_to_root` when config flag FALSE

- [ ] **Step 1: Implement validation against `config$literature_targets` list.**

- [ ] **Step 2: Implement pub_export checklist** covering flowchart, Table1, performance tables, ROC, calibration, DCA, SHAP, ablation, synthetic external (labeled).

---

### Task 7: Task runner + Feishu setup

**Files:**
- Create: `R/tst_stroke_task_runner.R`
- Create: `run/feishu/run_feishu_setup_tst_stroke_tables.R`
- Modify: task-parallel run entry to call runner

**Interfaces:**
- Runner API: `tst_stroke_run_task_parallel(root, config, pipeline_shared, units, workers)`
- Dispatch via `processx::process$new` on Windows R; `system2(..., wait=FALSE)` on Linux
- On worker finish: upsert Feishu success/failure using task unit as「指标名」field
- Feishu setup script clone structure from `run_feishu_setup_crm_nhanes_mr_tables.R` with protocol `two_stage_transformer_stroke`

- [ ] **Step 1: Implement runner with `--shared-only`, `--only-unit`, `--workers`.**

- [ ] **Step 2: Feishu setup script** (idempotent tables on `RBjfb...`).

- [ ] **Step 3: End-to-end smoke**

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/two_stage_transformer_stroke/run_two_stage_transformer_stroke_task_parallel.R \
  --only-unit L72_B_twostage,external_synthetic --workers 2
```

Expected: both units finish with status JSON; synthetic metrics marked synthetic; optional Feishu lines if credentials present (`SMOKE_NO_FEISHU=1` allowed).

---

### Task 8: Expand unit matrix to full E1–E12 depth

**Files:**
- Modify: `configs/templates/config_two_stage_transformer_stroke_task_parallel.template.R`
- Modify: `R/tst_stroke_task_runner.R` unit expander
- Modify: `Decisiontree/decision_tree_two_stage_transformer_stroke.md` unit table

**Interfaces:**
- Expander builds cartesian product `landmarks × {A1,A2,B,logistic,xgb,mlp,lstm}` plus ablation + temporal + external_synthetic
- Default full run may be large; template documents `--only-unit` for subset

- [ ] **Step 1: Implement expander + document full unit list in decision tree.**

- [ ] **Step 2: Dry-run print units without training** (`--list-units` flag) and verify count ≥ 5 landmarks × 7 models + extras.

---

## Spec coverage check

| Spec section | Task |
|--------------|------|
| §0 decisions / constraints | Global + Tasks 3,7 |
| §2 data flow shared→worker | Tasks 4,5,7 |
| §3 Python migrate from `code/` | Task 2 |
| §3 `tst_cohort` in R | Task 4 |
| §4 Blocks 01–11 | Tasks 4–6 |
| §5 directory落点 | Tasks 1–7 |
| §6 task parallel | Tasks 3,7,8 |
| §7 deliverables | Tasks 5–6 |
| §8 external + synthetic | Tasks 2,5 |
| §9 QC / no modify old | Global Constraints |
| Feishu | Task 7 |

## Placeholder / consistency self-review

- No TBD left in tasks.
- CLI script name consistently `block_two_stage_transformer.py`.
- Config key namespace `tst_stroke` / register names `tst_*` consistent.
- Commit steps omitted (user must request commits explicitly).
