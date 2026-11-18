# 复用地图：EMs 复发单库 ML — P0 清表 + summary_results 白名单（2026-11-02）

沉淀自 `20_子宫内膜异位症复发_仙人抚我顶` / `35_EMs/ml_40395549`。

## 交付面

课题跑完后客户只打开：

`…/summary_results/` → Figures/ · Tables/ · Methods_statistical_analysis.md · Methods_software_versions.txt · *中期*.pdf

## 已进引擎（勿课题私改）

| 能力 | 入口 |
|------|------|
| 逐格全等表去重 | `R/pub_dedup_identical_tables.R`（`run_pipeline` 收尾 + `ml_finalize_index_summary_results`） |
| 单库 ML 自动写 summary_results | `R/pipeline_runner.R` 收尾（预后+ML 块默认开；`pub$write_summary_results=FALSE` 可关） |
| Methods：MI 先于划分 / 主评价 TD-AUC / SHAP 口径 / predictor 措辞 | `R/ml_index_summary_results.R` ← `config$methods` |
| KM 横轴跟 `RFS_Months` | `Blocks/27_KM/02block_km_strata.R` |
| Cox ML：`Predictor cutoff` + 默认 `main_table` | `Blocks/10_cox/08block_cox_ml_continuous_batch.R` |
| 单因素列头 Training/Overall | `Blocks/06_univariate/01block_univariate_prognosis.R` |
| 一次性 P0 返工 CLI | `run/ml/repair_ems_ml_pub_p0.R` |
| PDF 超大页限幅 + 多页堆叠 | `python/pub_figure_normalize_pdf.py` → `pub_figure_normalize_pdf()` / `.pub_figure_rasterize_one` |
| 栅格渲全部页（非首页） | `python/pub_figure_rasterize.py`（竖向 stack） |
| formats_status 几何门控 | `bad_pdf_geometry`（pages&gt;1 或长边&gt;max_edge_in） |
| RCS 写出即堆叠单页 | `Blocks/15_rcs/01block_rcs_prognosis.R`（pdf_combine 后 normalize） |

## config 必写

```r
config$methods <- list(
  mi_before_split = TRUE,              # 或靠 pipeline 顺序自动探测
  primary_ml_metric = "td_auc_bootstrap",
  shap_model_rationale = "…"           # 校准 slope 等写实理由
)
config$pub$write_summary_results <- TRUE
config$capability$exposure_mode <- "all_ml_features"  # 触发 predictor 措辞
config$cox_ml_continuous_batch$table_kind <- "main_table"
config$cox_ml_continuous_batch$predictor_wording <- TRUE
config$km_strata$xlab <- "Time (months)"
```

## 反例

- 再留 Table 5≡Table 3 双份验证性能表
- Methods 写「先划分再分别插补」而 pipeline 仍是 imputation→train_validation
- 正文一句 “best model” 却混用 Table3 AUC / Table5 TD-AUC / SHAP RSF
- KM 在 months 数据上印 `Time (d)`
- Fig2 多页 RCS、PNG 只渲首页；S2 Shiny PDF 页边长 20+ in 导致 PNG 爆炸

## 图几何返工（本课题已修）

```bash
# 引擎会在 ensure_formats 自动 normalize；手工单图：
python3 python/pub_figure_normalize_pdf.py --pdf in.pdf --out out.pdf --stack-pages --max-edge-in 11
python3 python/pub_figure_rasterize.py --pdf out.pdf --png out.png --tiff out.tiff --dpi 600
```
