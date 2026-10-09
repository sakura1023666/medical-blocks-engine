# TST scripts — 正式可复用工具（非 _tmp）

由 `tst_summary_results` / 手工重跑调用。路径均相对引擎根 `01Block-new-Final/`。

## 汇总主入口

```bash
python Blocks/71_two_stage_transformer_stroke/scripts/build_summary_results.py \
  --project-root /path/to/study_output
```

会串联：Table1 SCI 拷贝、插补 S1 重建、Features S2、Table2/3、SHAP、S6/S7、Figure1。

## 单点重跑

```bash
# 插补前后 Table S1（对齐时序删人后队列）
Rscript Blocks/71_two_stage_transformer_stroke/scripts/rebuild_imputation_table_s1.R \
  --project-root /path/to/study_output --repo /path/to/01Block-new-Final

# Figure 1 CONSORT
python Blocks/71_two_stage_transformer_stroke/scripts/draw_fig1_consort.py \
  --project-root /path/to/study_output --db-name MIMIC

# Table 2（Day1–5）
python Blocks/71_two_stage_transformer_stroke/scripts/rebuild_table2_yang_layout.py \
  --project-root /path/to/study_output --landmark 120

# eICU 外验 Figure S7（自动识别 data/eicu/*_eicu_*_hourly_full_*.csv；缺 dabiao 则从小时表生成）
# 可选：eicu_static_features.csv 广播 static_*；TBI 示例见 37_TBI/.../data/eicu/
PYTHON=/mnt/c/ProgramData/Miniconda3/envs/torch/python.exe \
  $PYTHON Blocks/71_two_stage_transformer_stroke/scripts/prepare_eicu_external_and_eval.py \
  --project-root G:/02block_result/37_TBI/two_stage_transformer_40041421 \
  --landmark 120 --day 5 --repo E:/01block/01Block-new-Final
```

## 发表补充（只增不改主表）

校准 / DCA / NRI·IDI / eICU 分层与域偏移（Table S3–S7 + Figure S8–S11 一类）：

```bash
PYTHON=/mnt/c/ProgramData/Miniconda3/envs/torch/python.exe
$PYTHON Blocks/71_two_stage_transformer_stroke/scripts/add_pub_supplements_midterm.py \
  --project-root /path/to/tst_study_output \
  --landmark 120
```

- **引擎唯一副本**：本路径。勿在 `02block_result` 课题目录另存脚本。  
- 复用地图：`docs/reuse/2026-10-08-nature-pub-qc-tst-reuse-map.md`

`run/two_stage_transformer_stroke/_tmp_*` 已废弃，勿再引用。
