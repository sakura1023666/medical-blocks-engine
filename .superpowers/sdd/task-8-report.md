# Task 8 Report — 研究区双 config（QCT / DXA Panel）

**Status:** Complete  
**Date:** 2026-09-22  
**Commits:** none

## Deliverables

| Path | Note |
|------|------|
| `/mnt/g/02block_result/10_osteoporosis/personalized/config_osteo_fracture_qct.R` | Panel A + 核 B + CART |
| `/mnt/g/02block_result/10_osteoporosis/personalized/config_osteo_fracture_dxa.R` | Panel B 短链（至 `simple_ROC`） |
| `R/pipeline_runner.R` | 增补三新 block → 源文件映射（引擎可发现，config 无需额外 source） |

## Config 要点

- 共同：`study_type=incidence`，`outcome_column=Disease`，`analysis_group=Fracture`，`reference_group=No_Fracture`，`id_column=SampleID`
- 数据：`data/harmonized/D01_osteo_personalized.RData` → `dabiao`
- `index_var`：QCT=`QCT_vBMD`；DXA=`DXA_T_min`
- `output_dir`：`by_index/QCT_vBMD` / `by_index/DXA_T_min`
- `analysis_exclusion$disease_vars`：Task2 名单；QCT 用 `protect_vars` 保核 B/CART 列
- 锁协变量：`Age, BMI, bCTX, P1NP, VitD_25OH, PTH`（不含另一骨密度轴）
- 全部 `pause_enable=FALSE`
- CART（仅 QCT）：`outcome=need_QCT`；叶标签「首选 DXA / 必须 QCT」

## Dry-run（source config，无全量拟合）

入口无 `--dry-run`，改为 source + 打印 `pipeline$blocks` + 校验 `pipeline_block_sources`。

**QCT（20 blocks）：**  
`data_clean → … → simple_ROC → rcs_incidence → subgroup_incidence → dxa_qct_agreement → diagnostic_vs_fracture → modality_discordance_profile → cart_decision_path → attrition_flowchart`  
未映射 block：`NONE`

**DXA（13 blocks）：**  
止于 `simple_ROC`；无核 B 三块 / cart。未映射：`NONE`

## 未做

- 全量拟合 / Task 10 开跑（需用户授权）
- git commit
