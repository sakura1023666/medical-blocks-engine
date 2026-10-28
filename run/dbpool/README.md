# 数据库池化 · 发表收口（薄封装）

训练/建库主入口仍在 `run/database_pooling/`。  
本目录只负责 **summary_results 交付收口**（Methods + 软件版本 + 四目录图 + 白名单 + 结构 QC）。

## 一键收口

```bash
Rscript run/dbpool/finalize_summary_delivery.R \
  --dir "/mnt/g/02block_result/<课题>/summary_results" \
  --cohort "ACG-style enzyme elevation (ALT/AST ≥2×ULN)"
```

内部转调：

- `run/pub/finalize_delivery_root.R --study-type dbpool`
- `run/pub/run_pub_qc_after_project.R --project <dir>`

Methods 文案：`R/pub_dbpool_methods.R`（可用环境变量 `DBPOOL_COHORT` / `DBPOOL_DROP_FEATURES` 覆盖）。

## 自动挂点（不必手跑时）

| 挂点 | 文件 |
|------|------|
| batch tail | `Blocks/78_database_pooling_full/09block_dbpool_batch_finalize.R` |
| 定稿表图脚本末尾 | `Blocks/78_database_pooling_full/scripts/finalize_easl_paper_pub.py` |

## 交付白名单

只留：`Figures/` `Tables/` `Methods_statistical_analysis.md` `Methods_software_versions.txt` `*中期*.pdf`  
详见：`docs/reuse/2026-10-26-dbpool-delivery-midterm-reuse-map.md`

## 禁止

- 不要用 `/tmp/finalize_*.py` 或对话临时目录当长期入口  
- 不要在结果目录再写一套 Methods / prune hotfix  
