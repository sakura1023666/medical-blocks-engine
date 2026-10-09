# Blocks/76 — cum-eGDR × k-means × CKM（两波轨迹聚类）

CHARLS 类「两波暴露 → k-means 轨迹类 → 累积指数关联结局」流水线。引擎可复用入口见下。

## 何时用

- 索引文献是两波生命体征/代谢指数 + k-means 亚型 + CKM/卒中等结局
- 需要 elbow、Class 语义锚定、Table1 by class、Class/连续/三分位 Model1–3、RCS、亚组森林

## 模板 / 批跑

- 模板：`configs/templates/config_cum_egdr_kmeans_ckm_batch.template.R`
- 批跑：`run/cum_egdr_kmeans_ckm/run_cum_egdr_kmeans_ckm_batch.R`
- **发表定稿**（batch 后必跑一次）：`run/cum_egdr_kmeans_ckm/rebuild_publication.R`

## Helpers（跨课题）

| 文件 | 职责 |
|------|------|
| `R/literature_ckm_cum_egdr.R` | 读数、列对齐、eGDR 公式、kmeans、OR/HR、Age_Group、model sets |
| `R/cum_egdr_kmeans_pub.R` | 发表表图：Class map、Table1–3/S1–S2、Fig2 ABC、RCS、Free-Statistics 森林 |

下一课题换暴露列/Class 标签时，用 `ckm_stroke_class_map_paper(map=...)` 与 build_* 的 `cont_col`/`t1_col`/`t2_col` 覆盖，勿复制整份 rebuild。

## Block 一览

| 文件 | register_block | 作用 |
|------|----------------|------|
| `00block_ckm_attrition_flowchart.R` | `ckm_attrition_flowchart` | 纳排 flowchart |
| `01block_ckm_stroke_data_ingest.R` | `ckm_stroke_data_ingest` | 读 wide + 列对齐 |
| `02block_cum_exposure_build.R` | `cum_exposure_build` | 累积暴露 / tertile |
| `03block_kmeans_elbow_bivar.R` | `kmeans_elbow_bivar` | 二维 kmeans + elbow + Class 锚定 |
| `04block_kmeans_trajectory_panels.R` | `kmeans_trajectory_panels` | Fig2 草稿；优先写合并 `ckm_stroke_fig2_abc` |
| `04b_block_table1_by_class_ckm.R` | `table1_by_class_ckm` | Table1；优先 `ckm_stroke_build_table1_by_class` |
| `05block_logistic_cum_index_bundle.R` | `logistic_cum_index_bundle` | Table2 工作底稿（发表版式见 rebuild） |
| `06block_rcs_ckm_strata_panels.R` | `rcs_ckm_strata_panels` | RCS 草稿面板 |
| `07block_sensitivity_cox_mice_bundle.R` | `sensitivity_cox_mice_bundle` | Cox/MICE 敏感性底稿 |
| `08block_table3_class_subgroup_forests.R` | `table3_class_subgroup_forests` | 亚组草稿；定稿用 helper |
| `09block_ckm_pub_finalize.R` | `ckm_pub_finalize` | 拷到 `by_index/【success】<INDEX>/summary_results` + 提示 rebuild |

`pipeline_runner.R` 已注册上述 block 名；勿改名除非同步 runner。

## Fig2 / Table 铁律（发表）

- Fig2 **仅一张合并图**：A elbow · B scatter+hull · C mean±SE（禁止只交 2A/2B/2C 分图）
- Table1 小节：Demographics → Labs → Comorbidities → Exposure
- Table2/S1：Variable · Total · Events · Model1–3；Class2 Reference 在前
- Table3：Class2 Reference · Class1 · Class3 · Class4 · P trend · P int
- 连续森林（S2/S3）：per 1-SD；主文 Table2 连续仍为 per 1-unit
