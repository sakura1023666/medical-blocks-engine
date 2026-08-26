# Task 8 Report: 升级 Cursor 规则

**Status:** 完成

**Commits:** 无（按约束未提交）

## 变更

修改文件：`.cursor/rules/pub_figure_image_information.mdc`

1. **铁律 #7 图面标注必录**：要求图上可见关键数字/标注写入 `## 图面说明`（建议小标题「图上标注」），覆盖 RCS、KM、Forest、ROC、maxstat、Flowchart；数字只来自可收获产物，缺则写「未收获」，禁止编造。
2. **检查清单**：新增 RCS（P-overall / P-non-linear / cutoff）、KM（Log-rank P / cutoff）、Forest（Overall 与各亚组效应量、P for interaction）三项。
3. **反例**：新增「RCS 图上有 P/cutoff，md 只有空话」。
4. **`alwaysApply: true`**：已确认保留于 frontmatter。

## 关注点

- 本任务仅更新 Cursor 规则，未改 R 代码；后续 Task 1–7 的 `pub_figure_export.R` 实现需与此铁律对齐。
- 其它图种「图上有数字则必录」为泛化要求，具体 harvest 来源依赖各图种产物命名。

## 验证

- [x] 铁律 7 条完整
- [x] 检查清单含 RCS/KM/Forest
- [x] 反例含 RCS 空话
- [x] `alwaysApply: true` 未动
