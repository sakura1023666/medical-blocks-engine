# 数据库池化（BlendedLoS）跑法

- 决策树：`Decisiontree/decision_tree_database_pooling.md`
- 模板：`configs/templates/config_database_pooling_batch.template.R`
- 公开代码归档（进 Block 库）：`Blocks/78_database_pooling_full/upstream/BlendedLoS/`
- 适配/实验封装：`Blocks/78_database_pooling_full/scripts/`
- （兼容 shim）`python/database_pooling/*.py` → 自动转到上述 scripts

## 保留流程：先 BlendedICU，再下游

四库官方原库和协调结果留在 **Aiya-Linux `192.168.68.29`**，不进各个课题目录。以后换课题，仍然先用这一层，再把 `config$dbpool$blended_out` 指到协调结果。

| 步骤 | 位置 |
|---|---|
| 官方原库 | 29：`/mnt/sda/HIRID`、`/mnt/sda/AMUMCDB`；133：`G:\FTP\database` 的 MIMIC-IV 3.1 与 eICU 2.0 |
| 已协调长表 | 29：`/mnt/sda/BlendedICU/data/blended_data`（BlendedICU，2026-10-09） |
| 每人小时宽表 | 29：`/mnt/sda/BlendedICU/data/blendedlos_ready` |
| 展开脚本 | `Blocks/78_database_pooling_full/scripts/build_blendedlos_hourly.py` |

在 29 上展开（协调长表还在、只缺每人一张表时）：

```bash
bash run/database_pooling/run_blendedicu_hourly.sh
```

脚本默认读 `blended_data`，写出 `blendedlos_ready`。换输出目录：

```bash
bash run/database_pooling/run_blendedicu_hourly.sh \
  --base /mnt/sda/BlendedICU/data/blended_data \
  --out  /mnt/sda/BlendedICU/data/blendedlos_ready
```

下游课题把 `blended_out` 设成 `blendedicu_ready`。不要再从 RealExtraction 重抽，除非 29 上的协调库不在。

## 文献级默认（交稿口径）

- `config$dbpool$fast_train = FALSE` → `n_epochs=200`, `batch=32`, `alpha=20`
- 训练侧：训练集 q5/q95，`x = 2*(x-q5)/(q95-q5)-1`，再截断到 [-4, 4]，然后 ffill + mask
- 测试集比例默认 100（`percentage_test`）。缺列按 NaN 补上，再前向填充并记观测掩码，不从 37 列里删
- 仅调试：`fast_train=TRUE` 或 `DBPOOL_FAST_TRAIN=1`（40/64，**非交稿**）
- 缩小样本（机器内存或磁盘不够时）：在 config 里设 `stays_per_db`、`max_n_batch`，并把 `n_epochs` 改小。留 `NULL` 就是全文。不要另写一套训练脚本
- 表和图：`Blocks/78_database_pooling_full/scripts/build_publication.py`，由 `dbpool_pub_tables` 调用。只写 xlsx
- Methods：`Output.../_shared/.../Methods_literature_mode.txt`

正式代码只在本仓库的 `Blocks/78_database_pooling_full/`。29 上的协调数据可以留；不要把 `logs/run_deadline.sh` 或 `meta/block78` 当成另一份源码。

## 环境

```bash
python3 -m venv .venv_dbpool
.venv_dbpool/bin/pip install -U pip
.venv_dbpool/bin/pip install torch pandas pyarrow numpy scikit-learn tqdm matplotlib
```

## 飞书

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" run/feishu/run_feishu_setup_database_pooling_tables.R
```

把打印的 table_id 回填到 config`$feishu`。

## 跑批

```bash
"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/database_pooling/run_database_pooling_batch.R --shared-only

"/mnt/c/Program Files/R/R-4.5.1/bin/x64/Rscript.exe" \
  run/database_pooling/run_database_pooling_batch.R --workers auto
```

## 发表收口（summary_results 白名单）

训练/定稿表图之后，交付根只留 Figures / Tables / Methods_*.md|txt / 中期 PDF。

```bash
Rscript run/dbpool/finalize_summary_delivery.R \
  --dir ".../summary_results" \
  --cohort "ACG-style enzyme elevation (ALT/AST ≥2×ULN)"
```

- 引擎：`run/pub/finalize_delivery_root.R --study-type dbpool` + `R/pub_dbpool_methods.R`
- batch 末尾已挂：`09block_dbpool_batch_finalize.R`
- 定稿脚本末尾已挂：`scripts/finalize_easl_paper_pub.py` → `_finalize_delivery_root`
- 复用地图：`docs/reuse/2026-10-26-dbpool-delivery-midterm-reuse-map.md`
- **禁止**用 `/tmp` 里的旧 finalize 副本