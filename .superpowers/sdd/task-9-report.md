# Task 9 Report — 目录同步 + RA 研究迁移验证

**Date:** 2026-08-12  
**Status:** DONE

## Work done

1. **Block header** — Expanded `Blocks/00_attrition/01block_attrition_flowchart.R` banner (purpose, `register_block` id, pipeline position, fuller `config$attrition` example incl. `fixed`/`id_file`/`join_universe_*`/`specialty_figure_mode`, ctx I/O).
2. **Catalog** — Ran `python3 scripts/update_blocks_catalog.py` then `--check` → exit 0; `docs/Blocks_catalog.md` includes `attrition_flowchart`.
3. **RA config** — `/mnt/g/02block_result/19_Rheumatoid Arthritis/incidence_38341157/Data/config_incidence_mimic_batch.R`:
   - Added `config$attrition` with steps: fixed 65366 → RA csv → GC csv (intersect RA) → current analytic.
   - Appended `attrition_flowchart` to end of `pipeline_regular_batch$blocks` and `pipeline_nhanes_batch$blocks`.
4. **Smoke** — Sourced `attrition_log` + block with RA dabiao/config (no full NLR batch). Outputs under study root:
   - `Tables/Flowchart_attrition_mimic.csv` (65366 → 898 → 399 → 399; ASCVD 70 / Non_ASCVD 329)
   - `Figures/Figure 1. Inclusion exclusion flowchart_mimic.pdf` (non-placeholder, ~4.7KB)
5. **Deprecation** — Note at top of `run/rheumatoid_ascvd/draw_flowchart_ra_ascvd.R`.
6. **join_universe** — Already implemented in Task 1 (`attrition_load_id_universe`); no further code change needed.

## Spec §9 checklist

| # | Criterion | Result |
|---|-----------|--------|
| 1 | Baseline routine 跑通后产出根有纳排 CSV + Figure 1 PDF | ✅ Smoke via block → study `Tables/` + `Figures/`（全指标 batch 未跑；API/block 路径已验证） |
| 2 | RA+GC→ASCVD 只需 config `steps`，无需手写 prep 出图脚本 | ✅ Config steps 已填；legacy `draw_flowchart_ra_ascvd.R` 标 deprecated |
| 3 | 无 `steps` 时流水线仍成功，并有 warning | ✅ Task 1/2 行为；本任务未重复测 empty steps |
| 4 | `update_blocks_catalog.py` 后 catalog 含 `attrition_flowchart` | ✅ `--check` OK |
| 5 | 专用 flowchart 不因通用块硬失败（skip 或 1b） | ✅ `specialty_figure_mode = "skip_if_generic"` 写入 RA config；Task 7 实现 |

## Brief steps

- [x] Step 1: catalog update + check  
- [x] Step 2: RA config steps + pipeline 末尾挂块  
- [x] Step 3: smoke（source finalize/draw；未跑全量 `--only-index NLR`）  
- [x] Step 4: spec §9 勾选  

## Notes

- Filename slug 为小写 `_mimic`（来自 `.attrition_db_slug`），与旧手写 `*_MIMIC.csv` 大小写不同；内容为全链 65366→898→399。
- No git commit (per request).

## Final fix

**Changes**

1. `configs/study_interface/baseline_pipelines.json` — appended `attrition_flowchart` to `survival.pipeline_regular_batch` (was ending at `subgroup_prognosis`).
2. `Blocks/00_attrition/01block_attrition_flowchart.R` — PDF title resolution: `cfg$title` → `cfg$figure_title` → auto-generated default.
3. `R/attrition_log.R` — `attrition_load_rawdata_n`: `.rds`/`.RDS` via `readRDS`, `.RData`/`.rda` via `load`, else `read.csv`.

**Verify**

```bash
python3 -c 'import json;from pathlib import Path;d=json.loads(Path("configs/study_interface/baseline_pipelines.json").read_text());b=d["survival"]["pipeline_regular_batch"]; print(b[-1])'
# attrition_flowchart

Rscript --vanilla tests/test_attrition_log.R
# OK attrition_log
```

Both commands exit 0.
