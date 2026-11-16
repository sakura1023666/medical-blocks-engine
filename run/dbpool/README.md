# 数据库池化 · 发表收口（薄封装）

训练/建库主入口：`run/database_pooling/` 与 `Blocks/78_database_pooling_full/scripts/`。  
本目录只负责 **summary_results 交付收口**（全项目复用）。

规则：`.cursor/rules/dbpool_pub_reuse.mdc`  
复用地图：`docs/reuse/2026-10-26-dbpool-delivery-midterm-reuse-map.md`

## 一键收口

```bash
Rscript run/dbpool/finalize_summary_delivery.R \
  --dir "/mnt/g/02block_result/<课题>/summary_results" \
  --cohort "ULN-all3 laboratory gate (AST ≥38 U/L, ALT ≥41 U/L and total bilirubin ≥1.3 mg/dL)" \
  --feature-set "Model covariates followed prior multi-database ICU mortality/RLoS prediction literature; laboratories used only to define the cohort were not included as predictors."
```

内部自动：

1. `run/pub/finalize_delivery_root.R --study-type dbpool`  
   - Methods（`R/pub_dbpool_methods.R`）  
   - 软件版本（含 Python modules_only）  
   - `pub_delivery_scrub_display`（禁下划线 + **Times New Roman**）  
   - 图格式 + 白名单 prune  
2. `run/pub/run_pub_qc_after_project.R` 结构 QC  
3. 若已有 `content.json` → 尝试重建中期，再 prune

环境变量：`DBPOOL_COHORT` / `DBPOOL_FEATURE_SET` / `DBPOOL_MODEL`

## 自动挂点（不必手跑时）

| 挂点 | 文件 |
|------|------|
| batch tail | `Blocks/78_database_pooling_full/09block_dbpool_batch_finalize.R` |
| 定稿表图脚本末尾 | `Blocks/78_…/scripts/finalize_easl_paper_pub.py` |
| ULN 三联 pack 末尾 | `Blocks/78_…/scripts/pack_uln_triple_summary.py` |

## 交付白名单

只留：`Figures/` `Tables/` `Methods_statistical_analysis.md` `Methods_software_versions.txt` `*中期*.pdf`  

QC / Nature / content.json → 同级 `*_delivery_workspace/`

## 禁止

- `/tmp/finalize_*.py` 或结果目录私有 Methods/Times hotfix  
- 再复制一套 `xlsx_force_times`（已并入 `python/pub_xlsx_scrub_display.py`）  
