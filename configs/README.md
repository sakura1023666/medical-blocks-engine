# configs 目录说明

仓库内**只保留模板与共享资源**；具体课题实例已移至 `_archive/`。

## 目录结构

| 路径 | 用途 |
|------|------|
| `templates/*.template.R` | 各分析套路的配置模板（**每个套路一个**） |
| `indices/composite_index_vars.R` | 复合指标变量名（全局共享，勿删） |
| `ml_dual_shared_overrides.R` | ML 双库共用覆盖项 |
| `study_interface/` | 程序化生成 config 的构建脚本 |
| `_archive/` | 历史实例 config（仅供参考，新课题勿直接改） |

## 使用方式

1. **复制模板**到研究产出目录（推荐与 `Data/` 同级），或直接在模板内改【必改】路径后用 `--config` 指向模板。
2. 按 `prompt/CONFIG_WORKFLOW.md` 与 `docs/config_tips.md` 修改路径、疾病、暴露、结局等。
3. **不要**在仓库 `templates/` 里堆叠多个课题实例。

```bash
# 示例：轨迹预后双库批量
cp configs/templates/config_trajectory_prognosis_batch.template.R \
   "/path/to/09_HF/Prognosis_Trajectory_xxx/config.R"

Rscript run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R \
  --config "/path/to/09_HF/Prognosis_Trajectory_xxx/config.R"
```

## 套路 → 模板对照

| 套路 | 模板 | 入口脚本 |
|------|------|----------|
| 发病 · 双库批量 | `config_incidence_dual_batch.template.R` | `run/incidence/run_incidence_dual_batch.R`（唯一入口；单库/NHANES/IPTW 等旧入口已并入本批量） |
| 发病 · 单库/IPTW/双库/NHANES（旧模板） | `config_incidence_{single,iptw,dual,nhanes,nhanes_batch}.template.R` | 请改用 `run_incidence_dual_batch.R` + dual_batch 模板 |
| 预后 · 双库批量 | `config_survival_dual_batch.template.R` | `run/survival/run_survival_dual_batch.R` |
| 预后 · 单库 SAE | `config_survival_sae.template.R` | `run/survival/run_survival_sae.R` |
| 轨迹预后 · JLCM 双库 | `config_trajectory_prognosis_batch.template.R` | `run/trajectory_prognosis/run_trajectory_prognosis_apri_batch.R` |
| 轨迹预后 · PLT | `config_trajectory_prognosis_plt.template.R` | `run/trajectory_prognosis/run_trajectory_prognosis_plt.R` |
| 轨迹预后 · PLT 批量 | `config_trajectory_prognosis_plt_batch.template.R` | `run/trajectory_prognosis/run_trajectory_prognosis_plt_batch.R` |
| 轨迹发病 · AKI | `config_trajectory_incidence_aki_batch.template.R` | `run/trajectory_incidence/run_trajectory_incidence_aki_batch.R` |
| 环境毒物 · NHANES 批量 | `config_environment_dkd_batch.template.R` | `run/environment/run_environment_dkd_batch.R` |
| 环境 · Cd 骨 | `config_environment_cd_osteo_nhanes.template.R` | `run/environment/run_environment_cd_osteo_nhanes.R` |
| ML 双库批量 | `config_ml_dual_batch.template.R` | `run/ml/run_ml_dual_batch.R` |
| HF 双库聚类 | `config_hf_dual_clustering.template.R` | `run/Consensus clustering/run_hf_dual_clustering.R` |
| 竞争风险 CHF | `config_competing_risk_chf_batch.template.R` | `run/competing_risk/run_competing_risk_chf_batch.R` |
| 其他 CHARLS/ELSA 等 | `config_*_batch.template.R` | 见 `run/<套路>/` 下脚本注释 |

完整列表：`ls configs/templates/`

## 说明

- 部分批量模板仍 `source("configs/_archive/config_*.R")` 引用旧基础层；**复制模板后**请改为自包含或一并复制 `_archive` 中对应基础文件。
- 环境类 `osteo/htn/full/smoke` 等变体已合并为 **`config_environment_dkd_batch.template.R`** 一个套路模板。
- 旧路径 `configs/config_*.R` 已废弃；`run/` 脚本默认指向 `configs/templates/*.template.R`。
