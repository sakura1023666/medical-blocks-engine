# 多算法融合 TCF · 脓毒症AKI（PMID 40295871）

## 入口

```bat
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run\ml_tcf_sepsis_aki\01_prepare_analytic_dabiao.R
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run\ml_tcf_sepsis_aki\run_ml_tcf_sa_aki_batch.R --shared-only
"C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run\ml_tcf_sepsis_aki\run_ml_tcf_sa_aki_batch.R --workers 2
```

WSL：

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/ml_tcf_sepsis_aki/01_prepare_analytic_dabiao.R
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/ml_tcf_sepsis_aki/run_ml_tcf_sa_aki_batch.R --shared-only
```

可选纯 Python TCF（七模型+TOPSIS）：

```bash
python python/ml_tcf/train_tcf_bundle.py --train train.csv --valid valid.csv --out-dir OUT --smote
```

## 发表图重建（Wang 2025 角色：Fig1–6 + S1–S7，跳过 Fig7）

项目脚本（推荐；内部调用引擎 `pub_figure_ensure_formats` @600 dpi）：

```bash
python3 "/mnt/g/02block_result/42_AKI_spesis/multi-algorithm fusion_40295871/scripts/rebuild_wang2025_tcf_figures.py"
```

或引擎薄封装：

```bash
Rscript run/ml_tcf_sepsis_aki/rebuild_wang2025_figures.R
```

产物：`by_index/【success】ALLVARS/summary_results/Figures/{pdf,png,tiff,image_information}/`（并镜像到指标根 `Figures/`）。

## 产物位置

- 课题根：`\\192.168.68.133\02block_result\42_AKI_spesis\multi-algorithm fusion_40295871\`
- config：`config_ml_tcf_sa_aki.R`
- 决策树：`Decisiontree/decision_tree_ml_tcf_sepsis_aki_40295871.md`
- 飞书：`run/feishu/run_feishu_mark_ml_tcf_sepsis_aki.R`
