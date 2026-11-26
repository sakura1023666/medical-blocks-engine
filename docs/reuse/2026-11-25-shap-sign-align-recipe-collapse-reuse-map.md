# 复用地图：SHAP 符号对齐 + baked dummy 折叠（2026-11-25）

本轮（CHARLS Age≥50 CKM，`UA_CR`）可复用能力**只进 `Blocks/17_shap`**，按文件分工，禁止塞进课题 `scripts/` / `tmp/` / `R/` 杂项。

## Blocks/17_shap 分工（强制）

| 文件 | 职责 | 规范函数名 |
|------|------|------------|
| `00shap_router.R` | 算法路由 + **analysis_group 符号对齐** | `.shap_align_shapviz_to_analysis_group` / `.shap_flip_shapviz_signs` / `.shap_build_tree_shapviz` |
| `00shap_display_common.R` | **发表展示**：baked dummy 折叠 + 拼图构建 | `.shap_infer_feature_names_from_baked` / `.shap_collapse_shapviz_baked_dummies` / `.shap_build_pub_combined_figure` |
| `01block_shap.R` | `register_block("shap")` 主流程；source 上二者 | `.shap_collapse_shapviz_to_venn_features` / `.shap_combine_panels` / `block_shap` |
| `02block_shap_glm.R` | GLM SHAP | `block_shap_glm` |
| `02block_shap_dl_mlp.R` | MLP/DL SHAP | `block_shap_dl_mlp` |

**禁止**：把对齐写进 display_common；把拼图构建写进 router；在 `run/ml` 写业务逻辑。

## 薄 CLI（仅转调）

```bash
MEDICAL_BLOCKS_ROOT=/mnt/e/01block/01Block-new-Final \
Rscript run/ml/redraw_shap_pub_figure.R \
  --index-root "/path/to/by_index/【success】INDEX" \
  --analysis-group "CKM stage 2-3" \
  --reference-group "CKM stage 0-1" \
  --tag xgboost
```

→ 调用 `.shap_build_pub_combined_figure`（`00shap_display_common.R`）。

## config$shap

```r
shap = list(
  combine_layout = "grid2x2",       # grid2x2 | abc_top | waterfall_top
  collapse_baked_dummies = TRUE     # 兼容旧键 collapse_recipe_dummies
)
```

## 已删除（禁止复活）

- `tmp/redraw_ua_cr_shap_aligned.R`（硬编码 Gender/Residence）
- `/tmp/ua_cr_*`、`/tmp/redraw_shap*` 调试产物

## 新课题检查

- [ ] 改 SHAP 方法只动 `Blocks/17_shap/00*` / `01block_shap.R`
- [ ] 函数名 `.shap_*`；折叠与 `.shap_collapse_shapviz_to_venn_features` 平行命名
- [ ] CLI 不复制面板代码
- [ ] bee / dependence 与 analysis_group 同向；图面无 `Gender_Male` 类 dummy 名
