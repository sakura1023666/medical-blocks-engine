# NHANES 纳排图调查权重完整记账设计

## 目标

后续 NHANES 项目的纳排图必须完整记录调查权重资格筛选，使流程图最终分析人数、病例/对照分叉人数与加权 Table 1 使用的分析集一致。现有 AIP_WHtR 项目不回刷。

## 设计

1. `Blocks/12_obj/01block_obj.R` 成功构建基础 `svydesign` 后，将有效调查权重分析集写入纳排日志：
   - `step_id = after_survey_weight`
   - `n = nrow(design_base$variables)`
   - 排除原因明确为调查权重缺失或非正。
2. `R/attrition_log.R` 生成病例/对照分叉时，若存在 `nhanes_design$variables`，优先从该数据计算分叉；否则保持现有数据源兜底。
3. 纳排图的权重筛选步骤只在确有权重排除时增加，避免人数未变化时产生冗余步骤。
4. 不缩减 `ctx$data$imputed`，避免改变下游既有数据对象语义；只让纳排日志和分叉使用与 Table 1 相同的调查设计分析集。

## 验收标准

- 存在无效调查权重时，纳排 CSV 包含 `after_survey_weight`。
- 该步骤人数等于 `nrow(ctx$results$nhanes_design$variables)`。
- 最后一行病例数与对照数之和等于调查设计分析集人数。
- 无调查设计的普通项目行为不变。
- 当前 AIP_WHtR 已有结果不重跑、不修改。

## 测试

在 `tests/test_attrition_log.R` 增加调查设计分析集场景，先复现分叉错误，再验证：

- 权重步骤正确进入日志；
- 分叉从调查设计变量计算；
- 普通非 NHANES 场景继续通过。
