---
description: Medical Blocks 配置文件修改助手 — 配合 BLOCKS_USAGE_GUIDE / SURVIVAL_BATCH_GUIDE / config_tips 使用
version: 1.0
language: zh-CN
---

# CONFIG_WORKFLOW — 配置文件修改 AI 提示词

> **用途**：用户要改 `configs/config_*.R` 时，在对话中 `@CONFIG_WORKFLOW.md`（并附上数据信息），AI 按本文件及关联文档执行。

---

## 关联文档（修改前必读）

| 文档 | 路径 | 作用 |
|------|------|------|
| Block 开发规范 | [BLOCKS_USAGE_GUIDE.md](../../BLOCKS_USAGE_GUIDE.md) | 配置驱动、ctx 契约、pipeline 编排、SCI 输出、禁止硬编码 |
| 预后 Batch 指南 | [SURVIVAL_BATCH_GUIDE.md](../../SURVIVAL_BATCH_GUIDE.md) | 100 指标并行、`computed_indices`、worker 隔离 |
| Config 修改流程 | [config_tips.md](../../docs/config_tips.md) | 所有 config 套路的提问范围、默认值、改键清单 |

---

## 用户开场模板（复制改括号）

**项目内 config**（`configs/config_*.R`）：

```
@CONFIG_WORKFLOW.md @docs/config_tips.md
我要改 configs/config________.R

【暴露】(...)
【数据】
- 库1：路径 (...)，对象 (...)，ID (...)
- 库2（如有）：路径 (...)，对象 (...)，ID (...)
【附】colnames / str / 报错（粘贴或 @ 文件）

请按 config_tips 提问后修改，并给出运行命令。
```

**batch 双库（数据在 02block_result）**：

```
@CONFIG_WORKFLOW.md @configs/templates/config_incidence_dual_batch.template.R
【数据】G:/02block_result/{疾病编码}_{disease}/{study_type}_{PMID}/Data
请根据数据改 config，保存到该 Data 路径下，并给出运行命令。
```

---

## config 套路对照表

| 配置文件 | 研究类型 | 运行脚本 | pipeline 变量 | 备注 |
|----------|----------|----------|---------------|------|
| `config_incidence_single.R` | 发病 · 单库 | `run_incidence_single.R` | `pipeline` | MIMIC/CHARLS 等普通 Logistic |
| `config_incidence_nhanes.R` | 发病 · NHANES 加权 | `run_incidence_nhanes.R` | `pipeline` | 含 `nhanes` / `obj` / 加权块 |
| `config_incidence_dual.R` | 发病 · 双库 | `run_incidence_dual.R --db both` | `pipeline_nhanes` + `pipeline_regular` | NHANES 加权 + MIMIC 普通 |
| `config_incidence_dual_batch.R` | 发病 · 双库批量 | `run_incidence_dual_batch.R --config "<产出根>/Data/config_incidence_dual_batch.R"` | 共享层 + `pipeline_nhanes_batch` / `pipeline_regular_batch` | config 与数据同放 `Data/`；产出见下文路径规则 |
| `config_survival_sae.R` | 预后 · 单库 | `run_survival_sae.R` | `pipeline` | Cox 闸门、KM、RCS |
| `config_hf_dual_clustering.R` | 预后 · 双库无监督 | `run_hf_dual_clustering.R` | `pipeline` | eICU + MIMIC 聚类/LCA |
| `config_survival_batch.R`（规划） | 预后 · 批量指标 | `run_survival_batch.R` | 共享层 + worker | 见 SURVIVAL_BATCH_GUIDE |

**原则**：优先**同套路旧 config 为模板**，只改研究相关键；**不增删 pipeline blocks**、**不改分析阈值/VIF/logistic 搜索策略**，除非用户明确要求。

---

## AI 执行清单（精简版）

完整分层说明见 [docs/config_tips.md](../../docs/config_tips.md)。

### 只问这些

| 层级 | 必问 |
|------|------|
| 研究骨架 | **疾病编码**（如 `01`，写入 `project$disease_code`）；暴露变量名；结局列名 + 参考组/病例组取值 |
| 数据入口 | 每库路径、对象名、ID 列；NHANES 权重三件套是否变化 |

### 默认不做 / 不问

- **文献 ID**（PubMed ID / DOI / `literature_pmid`）— **不向用户提问**；沿用当前 config 模板或项目既定值（如 batch 模板中的 `38341157`），仅随 config 文件修改
- 双库自动额外排除 `Hemoglobin`
- 所有库都跑（双库 `--db both`）
- **单库 / 非 batch 双库**：`output_dir` 按 `{暴露}_{analysis_group}` + 后缀（`_NHANES` / `_dual`）自动命名
- **batch 双库**（`config_incidence_dual_batch.R`）：
  - **数据目录**：`G:/02block_result/{疾病编码}_{disease}/{study_type}_{literature_pmid}/Data/`（各库子目录如 `eicu/`、`mimic/`、`nhanes/`）
  - **config 保存位置**：与数据同目录 → `.../Data/config_incidence_dual_batch.R`（**不问用户放哪**，默认写 Data）
  - **产出根目录**（`.batch_project_root`）：`Data` 的**上一级**，即 `G:/02block_result/{疾病编码}_{disease}/{study_type}_{literature_pmid}/`（WSL：`/mnt/g/02block_result/...`）；`literature_pmid` 取自 config，**不问用户**
  - **运行**：必须用 `--config` 指向 Data 下 config，**不要**依赖项目内 `configs/config_incidence_dual_batch.R`
- `column_mapping` 始终启用；人口学/Model1/Model2/亚组从数据推断或沿用模板
- 阈值、VIF、logistic 搜索、pipeline blocks — 全部沿用模板
- checkpoint 路径 — 随 output 自动推导
- **R 可执行文件路径** — 固定使用用户环境，**不问用户 R 装在哪**：
  - WSL：`/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe`
  - Windows：`C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe`
- 改完后自动给出带完整 `Rscript` 路径 + `--config` 的运行命令，不问用户怎么跑

### 执行顺序

```
识别套路 → 读数据 → 最小提问 → 输出拟改键清单 → 用户确认 → 改 config → 给运行命令
```

### batch 双库运行命令（改 config 后自动给出）

在项目根目录 `01Block-new-Final` 执行；`--config` 指向 **Data 目录下**的 config。

**R 路径（默认，所有套路通用）**：

| 环境 | `Rscript` 完整路径 |
|------|-------------------|
| WSL | `/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe` |
| Windows PowerShell | `C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe` |

**Windows PowerShell**（将 `{...}` 替换为实际研究路径）：

```powershell
cd "G:\01block\01Block-new-Final"

# 共享层（复合指标 + Gate A）
& "C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run_incidence_dual_batch.R --shared-only --config "G:/02block_result/{疾病编码}_{disease}/{study_type}_{literature_pmid}/Data/config_incidence_dual_batch.R"

# 全量批量（自动推算并行路数）
& "C:\Program Files\R\R-4.5.1\bin\x64\Rscript.exe" run_incidence_dual_batch.R --config "G:/02block_result/{疾病编码}_{disease}/{study_type}_{literature_pmid}/Data/config_incidence_dual_batch.R"
```

**WSL**（`--config` 用 `02block_result/...`，**不要**加 `/mnt/g/` 前缀）：

```bash
cd /mnt/g/01block/01Block-new-Final

# 共享层
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run_incidence_dual_batch.R --shared-only --config "02block_result/01_ARDS/incidence_38341157/Data/config_incidence_dual_batch.R"

# 全量批量
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run_incidence_dual_batch.R --config "02block_result/01_ARDS/incidence_38341157/Data/config_incidence_dual_batch.R"
```

---

## 与 BLOCKS_USAGE_GUIDE 的衔接

- config 只描述**统计行为与路径**；**不**在 block config 里切换 `imputed` / `nhanes_design`
- 换数据源 → 改 `data` / `dual_db` 与 pipeline 顺序，**不**改 block 内逻辑
- 新建套路 → 先读 `.cursor/skills/create-pipeline-config/SKILL.md`，再按 config_tips 填骨架

---

## 与 SURVIVAL_BATCH_GUIDE 的衔接

- 100 指标：**一份** batch config + `computed_indices` 在共享层 `data_clean` 算列
- **不要**为每个指标复制 100 份 config
- 单指标预后仍用 `config_survival_sae.R` 套路；batch 为扩展场景

---

*最后更新：2026-06-12*
