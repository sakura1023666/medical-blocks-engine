# 5006 轨迹预后 JLCM 双库程序员接口（方案 A）

> 日期：2026-07-17  
> 状态：已批准实施按 A 做」

## 目标

在 `DockerHome/5006/medical-blocks-studies` 与环境 VOC **并列**挂载「轨迹预后 JLCM 双库 · by_index 批量」，程序员只改 `config.R` + `Data/`，不接触引擎 `Blocks/`。

## 范围

- **做**：研究区模板、`run_study` 分发、决策树母版副本、hook slots / baseline_pipelines / mother 映射、入口 guard、文档
- **不做**：重跑卒中结果；改 JLCM 拟合；挂轨迹发病（AKI）

## 研究区布局

```
studies/_template/                 ← 环境（保持）
studies/_template_trajectory/      ← 新建
  config.R                         ← 自包含 + <TO_CONFIRM*>；产出=本研究目录
  STUDY.md
  Data/eicu/  Data/mimic/
templates/config_trajectory_prognosis_batch.template.R
docs/Decisiontree/decision_tree_trajectory_prognosis_apri.md
```

## 运行分发

- 自动识别：`trajectory_batch` / `trajectory_jlcm` / `pipeline_unit_suffix`
- 入口：`run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R`
- CLI：`--routine trajectory`；透传 `--shared-only` / `--workers` / `--only-index` / `--no-skip`

## 引擎补齐

- `hook_slots.yaml`：`trajectory.shared_end` / `unit_after_jlcm` / `unit_end` 等
- `baseline_pipelines.json`：`trajectory` → shared / unit_prefix / unit_suffix
- `.hooks_mother_rel$trajectory` → `Decisiontree/decision_tree_trajectory_prognosis_apri.md`
- batch runner 启动前 `pipeline_extension_guard_check(routine="trajectory", ...)`

## 数据约定

输入：`Data/eicu/`、`Data/mimic/`（RData + 实验室指标）  
产出：研究目录下 `_shared/`、`by_index/`、`checkpoints/`、`data/{db}/`、`Tables/`、`Figures/`
