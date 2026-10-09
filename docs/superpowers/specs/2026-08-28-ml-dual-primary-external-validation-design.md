# ML 双库：主库筛选 + 外验继承（方案 A）

## 目标

双库机器学习中，**主库完整跑 UV→VIF→特征选择**；**外部验证库不跑**上述三步，注入主库 `feature_selection_final` 后仍自训 ML，两库发表物同构。

## 铁律

1. **主库** = 纳排/插补后 **N 更大** 的库；另一库 = 外部验证。
2. 主库：单因素 → VIF → FS → 协变量铁律 → 关联 → ML → 表现/SHAP/亚组。
3. 外验：跳过 UV/VIF/FS；`ml_inherit_primary_features` → 与主库同一套下游。
4. 两库 Table/Figure 角色与编号同构；禁止外验单独重筛特征。

## 实现挂点

- `ml_dual_secondary_ml_symmetric_blocks()`：仅 inherit + 下游（无 UV/VIF）
- `pipeline_mimic_ml_batch` / worker 次库相位文案与 render 列表对齐
- `ml_dual_assert_primary_larger_n()`：worker 启动后校验主库 N ≥ 外验 N
- 课题 `.study`：`primary_*` / `secondary_*` 按 N 配置（本课题 CHARLS 主、NHANES 外验）

## 本课题

| 角色 | 库 | 插补后 N |
|------|-----|----------|
| 主库 | CHARLS | ~3254 |
| 外验 | NHANES | ~1164 |
