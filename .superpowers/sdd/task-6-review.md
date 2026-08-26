# Task 6 Review — 现有 Block 图 profile 门控

**Reviewer**: subagent (read-only)  
**Date**: 2026-08-26  
**Scope**: brief `task-6-brief.md` + constraints（缺省=旧图 / 禁止静默改 theme）

## Verdict

| Gate | Result |
|------|--------|
| **Spec** | ✅ |
| **Quality** | **Approved** |

## Verification

| Check | Result | Evidence |
|-------|--------|----------|
| 公共 getter | ✅ | `R/pub_figure_profile.R`：缺省/空白/`NA` → `NULL`；`is_pub_profile` 仅 `identical(..., "mimic_inc_prog_sle_aki")` |
| NULL 时 helper 不改对象 | ✅ | `pub_figure_profile_apply_ggplot` 早退同一对象；单测 `identical(p0, p0)`；无 `theme_set` |
| 森林覆盖项缺省 | ✅ | `pub_figure_profile_forest_overrides` 非匹配返回 `NULL`；调用方仅在 `if (is_pub_profile)` 内写 `ci_col` / 交互 P |
| 目标 Block 只读门控 | ✅ | attrition / simple_ROC / ROC / rcs_inc+prog / subgroup 01·02·04·05 / km_binary+strata / plot_cutoff：美学改动均在 `if` 内 |
| KM router | ✅ | `03block_km_continuous_router.R` 不绑图，无需门控 |
| utils 挂载 | ✅ | `R/utils.R` 尾部 source `pub_figure_profile.R` |
| 旧课题 config | ✅ | `configs/` 无 `mimic_inc_prog_sle_aki` |
| TDD | ✅ | 本会话 `Rscript tests/test_pub_figure_profile_gate.R` → `OK profile gate` |
| 无 git commit | ✅ | 符合 global constraints |

**缺省路径抽查（profile NULL/absent → 原构造不变）**

- attrition：`box_fill` 仍 `#F7F7F7`（`attrition_draw_pdf` 默认同值）；浅蓝仅 profile
- simple_ROC：默认仍 `theme_bw` + 原尺寸；Youden 点 / 方形画布仅 profile
- ROC / RCS 发病 / KM / plot_cutoff：`apply_ggplot` 仅 `is_pub_profile && exists`
- RCS 预后：仅 profile 内 `par(lwd/cex)`；base 绑图函数未改
- 森林：`forest_ci_col` / `forest_highlight_interaction_sig` 仅 profile 写入；公共渲染 `isTRUE(flag)` 缺省跳过

## Critical

无。

## Important

1. **Block 级「缺省图不变」未做对象/出图回归** — 单测只 `identical` helper + `grepl("is_pub_profile")` 扫源码；spec §7「任选旧 incidence config，图路径与样式无变化」本任务未跑。代码结构满足铁律，但 grep 挡不住 `if` 外改 theme。
2. **`pub_figure_profile_forest_overrides(list())` 未断言 NULL** — 实现正确（非匹配 return NULL），缺与 `apply_ggplot` 对称的 stopifnot。
3. **文献版 RCS 预后偏薄** — 发病有 knot `geom_rug`；预后仅 `par` 微调。brief 允许最小 theme diff，非缺省路径回归；Task 8 对照文献 PDF 再加深即可。
