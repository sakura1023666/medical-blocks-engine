# 复用地图：缺血性卒中 ANLR 14d P0（2026-11-16）

踩坑课题：`11_ischemic stroke/prognosis_v2_41904528/summary_results_14d`  
目的：下次预后 v2 / landmark 变体 **不得再犯** 本批 8 类 P0。

## 已进引擎 / 规则（勿课题私改绕过）

| 能力 | 入口 |
|---|---|
| Methods 必含 RCS knots / Boruta / SHAP | `R/pv2_pub_p0_gate.R` Methods token 组 |
| S5 脚注 landmark = Methods 主文天数 | 同上 + `_rebuild_stroke_anlr_tables_hip_layout.R` 用 `.day_lab` |
| Fig7 Overall = Table 3 M1 | `pv2_pub_p0_gate` 数字锁（`.pv2_p0_xlsx_text_blob` / openxlsx，兼容 inlineStr）+ `_fix_stroke_anlr_fig7_lit_forest.R` 写前锁 |
| 回归钩子 | `tests/test_pv2_p0_gate_stroke_anlr_lessons.R` |
| Fig1「not computable」⇒ Methods 选择偏倚句 | `pv2_pub_p0_gate` |
| remirror 收尾硬闸 | `run/prognosis_v2/remirror_stroke_anlr_pub.R` → `pv2_pub_p0_gate(..., stop_on_fail=TRUE)` |
| Agent 清单 | `.cursor/skills/pub-qc-after-project/checklist.md` §B4 |
| Nature 失败模式 | `nature-statistics/references/common-failure-modes.md`「预后 v2 漏检」 |
| 规则全文 | `.cursor/rules/prognosis_v2_pub_p0_gate.mdc` + `nature_pub_qc_after_project.mdc` |

## 新课题检查（Agent 必勾）

1. Fig1 首框 N 是否已含项目信息里的 ESRD/透析/姑息/ICU≥2？写实 Methods；未执行禁止假装。
2. 最终 ICD 码表（含语义）在交付或 AUTHOR_INPUT。
3. 暴露不可计算 >40% → Limitations 承认选择偏倚。
4. 敏感性脚注禁止残留他 landmark（如 14d 交付写 28-day）。
5. Fig7 Overall 与 Table 3 Model1 同字符串。
6. Methods：Boruta maxRuns/ntree/seed + SHAP 包/实现 + RCS 结点位置。
7. remirror / finalize 后跑通 `pv2_pub_p0_gate`。

## 反例（禁止）

- remirror 用薄 Methods 模板冲掉 knots/Boruta/选择偏倚句
- S5 脚注写死 `primary 28-day locked grouping`
- Fig7 Overall 用 complete#1 而 Table 3 用 Rubin，差 0.001 仍交差
- 项目信息列排除项，Fig1 只画 Age/暴露缺失却 Methods 暗示已排除
