# 骨关节炎环境暴露：中介 + 调节复现（Yan 2026 方法）

日期：2026-08-12  
状态：已批准；实现中（block 挂 `20_mediation/07–12`）  
文献：`adversarial_lit_reading/papers/中介调节.pdf`  
（Yan et al., J Expo Sci Environ Epidemiol — heat → inflammatory cells → ALT/AST；age moderated mediation）  
数据：`/mnt/g/02block_result/04_Osteoarthritis/medition/data/`  
结果：`/mnt/g/02block_result/04_Osteoarthritis/medition/yan2026_modmed_reproduce/`

## 1. 目标

只复现文献图中的 9 步方法链，迁移到骨关节炎–环境毒物数据：

1. Spearman  
2–3. 批量中介（文献中的 ALT/AST 中介 → 本课题对每个暴露各跑一轮中介）  
4. 筛选显著中介  
5–6. 调节（文献年龄 → 本课题 Age / BMI / Gender）  
7. 有调节中介  
8. 简单斜率  
9. Fig.6 类图  

**不做**：改动既有 osteo / environment 课题 config、结果或流水线；不跑完整环境批次其它 block。

## 2. 因果结构（已确认）

| 角色 | 变量 |
|------|------|
| 暴露 X | `URXOTD`, `URXNPIP`, `URXMB2`, `URXDHB`, `URXCEM`, `URX4BP`, `URXP01`, `URX1NP`，以及 **WQS**（从 `D01_WQS_Result.RData` 合并） |
| 中介 M | `Creatinine_mol`, `Red_blood_cells`, `Mean_cell_hemoglobin`, `TBIL_mol`, `Total_Protein_gdL`, `BUN_mol`, `Potassium`, `Sodium`, `White_blood_cells`, `Neutrophil_count`, `Mononuclear_cell_count`, `lymphocyte_count` |
| 结局 Y | 仅 `Group`（Osteoarthritis=1，Normal=0） |
| 调节 W | `Age`, `BMI`, `Gender` |

用户原文中的「混合评分」= WQS，作为**暴露**之一，不是结局。

## 3. 分析设定（已确认）

- **协变量**：主分析 **crude（无协变量）**  
- **权重**：不用 NHANES survey 权重；普通 GLM + bootstrap（对齐 SPSS PROCESS）  
- **中介推断**：bias-corrected percentile bootstrap，正式 **5000** 次；冒烟可用 500  
- **Y 模型**：logit GLM；**M 模型**：线性 GLM  
- **显著中介**：间接效应 BC 95%CI 不含 0  
- **调节检验**：对显著 X–M，分别测 a（X×W→M）、b（M×W→Y|X）、c'（X×W→Y|M）  
- **有调节中介**：交互显著者进入；连续 W 取 Mean / Mean±1SD；Gender 分层；输出简单斜率 + Fig.6 类图  

## 4. 工程方案（方案 1，已确认）

独立课题流水线 + 在 **`Blocks/20_mediation/`** 下续号新增 block（**不**新建 `72_*` 目录包）。

### 4.1 目录

| 路径 | 用途 |
|------|------|
| 数据（只读） | `…/medition/data/结局_8环境毒物_基线全指标.RData`、`D01_WQS_Result.RData` |
| 结果（新建） | `…/medition/yan2026_modmed_reproduce/{Tables,Figures,checkpoints,logs}/` |
| Blocks | `Blocks/20_mediation/07`–`12`（见下） |
| Config | `configs/config_osteo_yan2026_modmed.R`（新建） |
| 入口 | `run/run_osteo_yan2026_modmed.R`（新建） |
| 可选共用 | `R/moderated_mediation_process.R`（PROCESS 式 bootstrap / 简单斜率；仅被新 block 调用） |

### 4.2 新 block（挂在 `20_mediation`）

现有：`00` common … `06` longitudinal。新增：

| 文件 | register_block | 对应步 |
|------|----------------|--------|
| `07block_modmed_data_prep.R` | `modmed_data_prep` | 读 merged + 合并 WQS、列名对齐、Group 编码 |
| `08block_modmed_spearman.R` | `modmed_spearman` | 步1；可复用 `09_correlation` / Spearman 逻辑 |
| `09block_modmed_mediation_batch.R` | `modmed_mediation_batch` | 步2–4；复用 `00mediation_common` 出图习惯 |
| `10block_modmed_moderation.R` | `modmed_moderation` | 步5–6 |
| `11block_modmed_moderated_mediation.R` | `modmed_moderated_mediation` | 步7 |
| `12block_modmed_simple_slopes.R` | `modmed_simple_slopes` | 步8–9 |

流水线顺序：

`modmed_data_prep` → `modmed_spearman` → `modmed_mediation_batch` → `modmed_moderation` → `modmed_moderated_mediation` → `modmed_simple_slopes`

### 4.3 运行环境

- R：`/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe`；缺包装入该 R 的 library  
- Python：默认不用；仅 R 无法实现时用仓库 `.venv`，并在该 venv 装包  
- 实现后按规则跑 `scripts/update_blocks_catalog.py` 更新 `docs/Blocks_catalog.md`

## 5. 疾病变量硬排除

- 本课题主模型无协变量，仍在 config 登记 `analysis_exclusion$disease_vars`（至少含 `Diabetes`、`Group`；课题相关诊断/用药若后续加入须同步登记）  
- `exclude_exposure_if_uses_disease_var = TRUE`  
- 禁止把 `SII`/`NLR`/`SIRI` 等其它复合指标当作当前血检中介的协变量  
- 当前中介组成变量不得进入协变量池（防以后把 crude 改成 adjusted 时泄漏）  
- `clinical_factor_names` / 亚组名单不得含 `disease_vars`

## 6. 产出物

- `Tables/Table_Spearman_*.csv/xlsx`  
- `Tables/Table_Mediation_Batch.csv`（每 X×M 一行：ACME/ADE/total/prop + CI）  
- `Tables/Table_Mediation_Significant.csv`  
- `Tables/Table_Moderation.csv`  
- `Tables/Table_Moderated_Mediation.csv`  
- `Tables/Table_Simple_Slopes.csv`  
- `Figures/Fig_Spearman_*.pdf`、中介路径图、简单斜率 Fig.6 类图  
- checkpoint：显著名单供下游 block 读取  

## 7. 非目标 / 明确不做

- 不修改 `configs/config_environment_osteo_full_batch.R` 及既有 osteo 结果目录  
- 不把 Group / 各 URX 同时当作结局；Y 固定为 Group  
- 不做 survey-weighted 中介（除非后续另开敏感性 spec）  
- 不把文献的 ALT/AST 当作本课题结局  

## 8. 风险与规模

- 约 9×X × 12×M = **108** 次中介 × 5000 bootstrap，运行时间可能较长；入口支持 `sims` 配置与按 X 断点续跑  
- WQS 向量长度若与 `merged` 行对齐方式依赖 `wqs_fit` 内部索引，`modmed_data_prep` 必须显式校验 SEQN/行对齐并记录 n  
- Gender 编码需在 prep 中固定并写入日志  

## 9. 自检清单（实现前）

- [ ] 新文件仅新增于 `Blocks/20_mediation/07+`、新 config、新 run；无改旧项目  
- [ ] 列名与数据一致（`BUN_mol` 非 LBUN；`Total_Protein_gdL` 等）  
- [ ] 硬排除写入 config  
- [ ] catalog 同步脚本在 register_block 后执行  
