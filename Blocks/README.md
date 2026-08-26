# Blocks/

通用分析引擎模块（按编号）。**不要删编号目录**；正式跑批由 `R/pipeline_runner.R` 按名加载。

| 区间 | 含义 |
|------|------|
| `00_*`–`34_*` | 共享基础：清洗/插补/基线/回归/ML/KM/环境… |
| `35_*`–`46_*` | 环境暴露等专题块 |
| `47_*`–`68_*` | 各文献「*_full」专题流水线块 |
| `69_*`–`71_*` | 较新专题（IPW / CRM NHANES / 两阶段 Transformer） |
| `Figures_Blocks/` `Tables_Blocks/` | 出图/出表渲染钩子（pipeline 引用） |

专题辅助脚本放在对应目录的 `scripts/`（如 `71_two_stage_transformer_stroke/scripts/`），不要堆到仓库根目录。
