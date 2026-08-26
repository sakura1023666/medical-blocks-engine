# Cutoff 边界规则统一（等于进 high）

## Goal

暴露 / index 的 cutoff 二分统一为约定 **A**：

- `x < cut` → low
- `x >= cut` → high（等于 cutoff 归入 high）

标签统一为 `"<cut"` / `">=cut"`（或等价文案），不再使用 `"<=cut"` / `">cut"`。

## In scope

- `rcs_cutoff_factor`（`R/utils.R`）及 RCS incidence 本地副本 `.rci01_cutoff_factor`
- `14_cutoff` binary 分组
- `iptw_balance`、logistic IPTW `group_mode=cutoff`
- NHANES subgroup 重建 `Index_Group` 的同类二分

多 cutoff RCS 分段：`cut(..., right = FALSE)`，标签为 `<c1` / `>=c_{i-1} & <c_i` / `>=c_n`。

## Out of scope

- 已符合 A 的分段 Cox / `cox_binary` / `km_binary`
- 年龄分层、p 阈值、分位数 Q1–Qn
- 根目录旧脚本（`C01_*` 等）
- 不重跑历史结果

## Decision

用户确认采用 A（2026-07-31）。
