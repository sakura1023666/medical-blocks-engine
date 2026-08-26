# 成功指标 code 包设计

**日期**: 2026-08-21  
**状态**: 已批准并实现（方案 1）

## 目标

每个课题指标主分析成功后，在  
`by_index/【success】<INDEX>/code/`  
自动生成可：

1. 修改协变量（Model1/2、中介协变量、best_mediator）
2. 修改森林图（亚组变量、age_cutoff、forest_xlim / ticks / 字号等）
3. 按 `--from` / `--to` / `--blocks` 单步重跑（含 `subgroup_prognosis`）

全发病 / 预后 dual-batch 项目共用。

## 产物

| 文件 | 作用 |
|------|------|
| `README.md` | 用法与人数警告 |
| `00_config_overrides.R` | 用户唯一编辑面；含 `code_bundle_apply(config)` |
| `run.R` | 组装临时 config → 调用 survival/incidence worker |
| `paths.R` | 课题 / 引擎 / 指标绝对路径 |
| `blocks_menu.txt` | 可用 block 列表 |

## 触发

`incidence_batch_finalize_index_outputs()` 末尾调用 `index_code_bundle_write()`。  
敏感性路径不写。

## 协变量来源

从 `checkpoints/by_index/<INDEX>/<db>/` 的 cox / harmonize / multivariate / mediation checkpoint 读取 Model1/2/cox_final；`preferred_mediator.rds` 读取 best_mediator。

## 单步重跑与人数

- `run.R` 默认 `patch_checkpoint_covariates=TRUE`，把 force_model* 写入相关 ck，便于从 `cox_*` / `mediation_*` 续跑立即生效。
- 文档明确：勿轻易 `--from imputation` / `trim_index_extreme`。

## 非目标（本版不做）

- 整条 pipeline 每步独立脚本拆分
- R Markdown / Quarto
- ML-only / IPW / competing 专用 worker（后续可复用同一生成器）
