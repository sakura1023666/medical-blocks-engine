### Task 6: 现有 Block 图 profile 门控

**Files:**
- Modify（各加只读门控，禁止改默认）:
  - `Blocks/00_attrition/01block_attrition_flowchart.R`
  - `Blocks/13_roc/02block_simple_ROC.R`（及必要时 `01block_ROC.R`）
  - `Blocks/15_rcs/02block_rcs_incidence.R`、`01block_rcs_prognosis.R`
  - `Blocks/18_subgroup/` 发病/预后 subgroup
  - `Blocks/27_KM/*`、`Blocks/28_plot/01block_plot_cutoff.R`
- Create: `tests/test_pub_figure_profile_gate.R`
- Create: `R/pub_figure_profile.R`（`pub_figure_profile(ctx)` → 字符串或 NULL）

**Interfaces:**
- Consumes: `ctx$config$pub_figure$profile`
- Produces: 仅当 profile 匹配时改 theme/面板/标注；否则原函数路径

- [ ] **Step 1: 公共 getter**

```r
# R/pub_figure_profile.R
pub_figure_profile <- function(config) {
  p <- tryCatch(config$pub_figure$profile, error = function(e) NULL)
  if (is.null(p) || !nzchar(as.character(p)[1L])) return(NULL)
  as.character(p)[1L]
}
is_pub_profile <- function(config, name) {
  identical(pub_figure_profile(config), name)
}
```

- [ ] **Step 2: 每个目标 Block 在绑图前**

```r
if (is_pub_profile(ctx$config, "mimic_inc_prog_sle_aki")) {
  # 文献版：例如 ROC 多曲线同面板、RCS 带 knot 标注、森林图交互 P 高亮
} else {
  # 原有代码不动
}
```

优先抽取「只改 ggplot theme / ggsave 尺寸 / 标题」的最小 diff；大改版式放 profile 分支内。

- [ ] **Step 3: 门控测试**

```r
source("R/pub_figure_profile.R")
stopifnot(is.null(pub_figure_profile(list())))
stopifnot(is_pub_profile(list(pub_figure = list(profile = "mimic_inc_prog_sle_aki")),
                         "mimic_inc_prog_sle_aki"))
stopifnot(!is_pub_profile(list(pub_figure = list(profile = "other")),
                          "mimic_inc_prog_sle_aki"))
cat("OK profile gate\n")
```

---
