# 多算法融合 TCF · 脓毒症AKI（PMID 40295871）

## 入口

Config（优先）：`…/multi-algorithm fusion_40295871/config/config_ml_tcf_sa_aki_linux.R`  
FS 口径：先双库统一可算池（`dual_db_intersect`）→ 熵逐步路径 **argmax**；`n_jobs=5`。

```bat
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run\ml_tcf_sepsis_aki\01_prepare_analytic_dabiao.R
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run\ml_tcf_sepsis_aki\run_ml_tcf_sa_aki_batch.R --shared-only
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run\ml_tcf_sepsis_aki\run_ml_tcf_sa_aki_batch.R --workers 5
```

WSL：

```bash
CFG="/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/config/config_ml_tcf_sa_aki_linux.R"
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/ml_tcf_sepsis_aki/01_prepare_analytic_dabiao.R
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/ml_tcf_sepsis_aki/run_ml_tcf_sa_aki_batch.R --config "$CFG" --workers 5
```

可选纯 Python TCF（七模型+TOPSIS）：

```bash
python python/ml_tcf/train_tcf_bundle.py --train train.csv --valid valid.csv --out-dir OUT --smote
```

## 发表重建（引擎 canonical，2026-11-02 上收）

**真相源在引擎**，课题 `scripts/rebuild_wang2025_tcf_*` 仅为薄跳转。复用地图：
`docs/reuse/2026-11-02-tcf-pub-pdf-only-delivery-reuse-map.md`。

```bash
export MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final
SUCCESS="/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/by_index/【success】ALLVARS"

# 图：PDF + image_information（默认不出 png/tiff）
Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R --success-root "$SUCCESS"

# 表：Table 1–2 + S1–S13
Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_tables.R --success-root "$SUCCESS"
```

引擎文件：

| 角色 | 路径 |
|------|------|
| 图 | `python/ml_tcf/pub/rebuild_wang2025_figures.py` |
| 表计算 | `python/ml_tcf/pub/rebuild_wang2025_tables_compute.py` |
| bootstrap 种子 | `python/ml_tcf/pub/bootstrap.py` |
| 表组装 | `run/ml_tcf_sepsis_aki/rebuild_wang2025_tables_core.R` |

config 须设 `methods = list(kind = "tcf")` 与 `pub_figures$export_png/tiff = FALSE`（见模板）。

交付根只留：`Figures/` `Tables/` `Methods_statistical_analysis.md` `Methods_software_versions.txt` `*中期*.pdf`。

## 产物位置

- 课题根：`\\192.168.68.133\02block_result\42_AKI_spesis\multi-algorithm fusion_40295871\`
- config：`config/config_ml_tcf_sa_aki_linux.R`
- 决策树：`Decisiontree/decision_tree_ml_tcf_sepsis_aki_40295871.md`
