# 复用地图：文献 Model1–3 统一 + 关联图（2026-10-26）

沉淀自 AKI **SAR+CrCV**（MIMIC 主分析）对话：全文关联表/图同一套 Model3（踢严重度），Nature collision 用栅格化消文本层 FAIL。

**新课题直接走引擎 / `run/ml` 正式入口，勿再抄结果目录 hotfix 或 `/tmp`。**

## 口径（literature_m123）

| 表列 | 含义 |
|------|------|
| Model 1 | 未调整 |
| Model 2 | Age + Sex/Gender |
| Model 3 | `clinical_covariates ∩ UV-sig ∩ VIF-pass`，**排除** `model3_exclude`（默认 APSIII/OASIS/SOFA/GCS/通气/CRRT 等） |

严重度被踢出的变量可写敏感性表，**不得**进主文 Model3 / Fig6 主估计（Fig6 优先 Model3，层内不可估回退 Age+Sex）。

与全局默认铁律（Model1=Age+Gender；Model2=VIF final 全池）**并存**：仅当 `assoc_covariate$scheme = "literature_m123"` 时走本套路。

## 引擎入口（改这里）

| 能力 | 文件 |
|------|------|
| scheme + `model3_exclude` + resolve | `R/ml_assoc_covariate_rule.R` |
| Block 挂点 | `Blocks/24_ml_dual/07block_ml_assoc_covariate_resolve.R` |
| 关联 Cox 表核心 | `R/prognosis_reference_assoc.R` |
| Fig2/3/4/6（Fig6 prefer M3） | `R/ml_reference_assoc_figures.R` |
| 外验冻结 SHAP | `R/ml_external_frozen_shap.R` |
| 文献 paper profile | `R/ml_reference_paper_profile.R` |
| PDF 文本层栅格化 | `R/pub_figure_export.R` → `pub_figure_rasterize_pdf_page()` |
| AKI 文献 config 片段 | `configs/ml_literature_aki_dev_ext_assoc_overrides.R` → `ml_literature_aki_dev_ext_apply_assoc_overrides()` |
| 决策树 D5 | `Decisiontree/decision_tree_ml_dual_prognosis_aki_dev_ext.md` |
| Cursor 规则 | `.cursor/rules/assoc_covariate_ml_iron_rule.mdc`、`ml_prognosis_pub_reuse.mdc` |

## CLI（返工 / 统一 Model3）

| 用途 | 入口 |
|------|------|
| 重算 Table2/S4/S8/S9 + Fig3/6 + Methods 句 + harmonization 锁 | `run/ml/rebuild_assoc_unified_model3.R` |
| 重画 Fig2/3/4/6 + 可选 Fig8 image-PDF | `run/ml/redraw_assoc_figs.R` |
| 目录说明 | `run/ml/README.md` |

```bash
MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
  Rscript run/ml/rebuild_assoc_unified_model3.R \
  --study <study_root> --index A+B \
  --delivery <study>/by_index/【success】A+B

MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
  Rscript run/ml/redraw_assoc_figs.R \
  --study <study_root> --index A+B \
  --delivery <study>/by_index/【success】A+B
# 指定 Fig8 文件名：--rasterize-fig8 "Figure 8. ….pdf"
# 跳过 Fig8：--no-rasterize-fig8
```

## 写 config（新课题）

```r
source(file.path(Sys.getenv("MEDICAL_BLOCKS_ROOT"),
                 "configs/ml_literature_aki_dev_ext_assoc_overrides.R"))
config <- ml_literature_aki_dev_ext_apply_assoc_overrides(
  config,
  clinical_covariates = c("SpO2", "BUN", "MAP", "WBC", "Glucose", ...),  # 按本病裁剪
  sex_var = "Gender"
)
# pipeline 须含 ml_assoc_covariate_resolve（在 FS 之后、assoc 之前）
```

换病种时：**改 `clinical_covariates` 名单**，勿照抄 SAR 的 SpO2/BUN…；`model3_exclude` 默认已够用，除非本病另有过度调整项。

## 已归档（勿复活）

| 位置 | 说明 |
|------|------|
| `_archive_oneoff/sar_crcv_2026-10/run_ml_superseded/` | 旧 `rebuild_joint_*`、`redraw_sar_crcv_*`、`fix_fig4_*` 等 |
| `_archive_oneoff/sar_crcv_2026-10/tmp_oneoff/` | 从 `/tmp` 拷来的草稿 |
| `_archive_oneoff/sar_crcv_2026-10/lit_pub_SAR_CrCV/` | 课题交付中间表样例 |

交付面白名单另见 `docs/reuse/2026-10-22-ml-lit-delivery-whitelist-reuse-map.md`。

## 新课题检查清单

- [ ] config：`scheme = "literature_m123"` + `clinical_covariates` + `model3_exclude`（或走 `ml_literature_aki_dev_ext_apply_assoc_overrides`）
- [ ] 日志：`Model3=…` 不含 APSIII/OASIS/SOFA/GCS/Ventilation
- [ ] Table2 / S4 / S8 / S9 / Fig6 Overall 同一 Model3 点估计口径
- [ ] Fig6 脚注/image_info 写 prefer Model3（非误标 Model2）
- [ ] 碰撞 FAIL 的密文本图用 `pub_figure_rasterize_pdf_page` / `redraw_assoc_figs.R`，勿手写 `/tmp` 栅格脚本
- [ ] 未从 `_archive_oneoff` 复制脚本到下一课题 `scripts/`
