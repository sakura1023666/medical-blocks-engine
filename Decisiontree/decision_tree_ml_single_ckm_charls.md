# 分析决策树 — 46 CKM · CHARLS 单库 ML 发病（全可算复合指标）

- 课题根：`/mnt/g/02block_result/46_CKM/ml_40395549/`
- 表图角色对齐：`15_hearing_loss/.../【success】TyG_WHtR/summary_results`
- 地基：**发病** + 方法后缀 **ML**（`config_ml_single_batch` / `single_db=TRUE`，非 NHANES 加权）
- 用户确认（2026-11-05）：结局 `dn`；以 34 的 7,645 为主，缺基线协变量插补；`workers=1`

## 节点

1. **研究问题** → 复合代谢/体格指标 × **CKM Stage ≥ 1**（二分类发病）
2. **结局** → `dn`（Stage≥1 vs Stage0）；Case n=6,802 / Control n=843
3. **暴露** → `index_mode=single_loop`，可算真复合指标约 44（无 NLR 系；无 eGDR）
4. **合并** → 34 CKM CSV ⟕ 133 baseline；ID pad12；Height m→cm
5. **纳排** → 上游已完成：17,708→7,645（变量齐全 ∩ Age≥45 ∩ 无临床 CVD）
6. **年龄亚组** → `age_cutoff=60`
7. **插补** → m=5 cart，`fit_on=train`，`rubin_pool=TRUE`
8. **关联** → logistic；Model1=Age+Gender；Model2=UV→VIF→MV→VIF final
9. **ML** → 关 TabPFN/mlp；LASSO 定特征；SHAP=验证集最优；`summary_results/`
10. **disease_vars** → 分期权威/组分/用药/CVD 闸 + Hypertension/Diabetes/Kidney/Hyperlipidemia

## 跑批顺序

`--shared-only` → `--only-index TyG --workers 1` → 其余指标一路一路 `--only-index`
