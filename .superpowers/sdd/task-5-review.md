# Task 5 Review — `threshold_logistic`

**Reviewer**: subagent (read-only)  
**Date**: 2026-08-26  
**Scope**: brief `task-5-brief.md` + constraints（旧课题不动 / block 注册）

## Verdict

| Gate | Result |
|------|--------|
| **Spec** | ✅ |
| **Quality** | **Approved** |

## Verification

| Check | Result | Evidence |
|-------|--------|----------|
| Block 新建 | ✅ | `Blocks/72_incidence_prognosis_two_stage/03block_threshold_logistic.R`（466 行） |
| `register_block` | ✅ | L464–465；catalog AUTO 卡片 `threshold_logistic` |
| `pipeline_block_sources` | ✅ | `R/pipeline_runner.R:418` 仅追加一行 |
| 消费：连续暴露 + 锁定协变量 | ✅ | `index_var` / `outcome_var`；`covariates` → Model2 → Model1 |
| 阈值搜索 | ✅ | Q10–Q90 网格 + `segmented` 精修；`ctx$results$cutoff_value` 作初值 |
| 产出 CSV / PDF | ✅ | `Table_Threshold_logistic_<Index>.csv`；`Figure_Threshold_<Index>.pdf`（经 `.pub_figure_filename`） |
| 发病侧门控 | ✅ | 非 `incidence` 跳过、不写表（测试断言） |
| 缺包安装 | ✅ | `.thl03_need_pkg` → `install.packages` 回退 |
| TDD / 测试 | ✅ | 复核 Rscript PASS（假数据 segmented τ≈8.79；真数据 n=270 events=110 τ=63） |
| 旧课题未改 | ✅ | `configs/` 无 `threshold_logistic`；无 baseline pipeline 挂载 |
| 无 git commit | ✅ | 符合 global constraints |

## Critical

无。

## Important

1. **Brief Step 2 流水线单指标冒烟** — 仍属 Task 8 通跑验收；当前仅单测 + Age 代理暴露，真实 index 端到端未验。
2. **假数据阈值未锚定 DGP hinge=5** — segmented 得 ~8.8；测试只检有限 τ 与 OR>0，回归力偏弱。
3. **文献 Figure 3 版式** — lit profile 为 theme_classic + 相对 OR 曲线 + 竖线；更深面板待 Task 6 `is_pub_profile`。
4. **`export_sci_table` 单测不 flush** — xlsx 仅入队；CSV 已即时落盘，流水线 finalize 后才有三线表。

## Strengths

- TDD 顺序正确；块头注释含 config / 流水线 / ctx 读写说明。
- 共线协变量自动剔除；`ctx$results$threshold_value` 供下游复用。
- catalog AUTO 已同步；MANUAL §1–§3 未动。
