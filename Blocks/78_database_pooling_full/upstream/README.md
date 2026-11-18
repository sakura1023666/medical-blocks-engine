# upstream — 公开代码归档（可复用）

本目录存放文献配套**公开代码原样镜像**，供 `Blocks/78_database_pooling_full` 复用。

| 子目录 | 来源 | 用途 |
|---|---|---|
| `BlendedICU/` | https://github.com/USM-CHU-FGuyon/BlendedICU tag v0.3.2 | 四库协调（先于训练）。本机没有 HiRID / Amsterdam 官方原库，协调落在 RealExtraction 上，规则对齐 v0.3.2 |
| `BlendedLoS/` | https://github.com/CIC-1410/BlendedLoS | Allyn et al. Critical Care 2026 训练/评估/出表（TPC/LSTM/Transformer） |

## 约定

1. **canonical 路径**：`Blocks/78_database_pooling_full/upstream/BlendedLoS/`（引擎与 batch 一律指这里）。
2. **不要改上游业务逻辑**做课题私改；适配层写在 `../scripts/`。
3. 升级上游：重新 clone/rsync 覆盖本目录，并更新下方 provenance。
4. 四库协调结果留在 Aiya-Linux `/mnt/sda/BlendedICU/data/`。新课题先用 `run/database_pooling/run_blendedicu_hourly.sh` 得到每人小时表，再把 `blended_out` 指到 `blendedlos_ready`。不要按课题重抽官方原库。

## Provenance

- Repo: `CIC-1410/BlendedLoS`
- Paper DOI: `10.1186/s13054-026-06034-5`
- BlendedICU tag v0.3.2 commit `7843836` mirrored 2026-10-13
- Mirrored into Blocks/78: 2026-10-10 (BlendedLoS)
- Local entry scripts: `../scripts/adapt_realextraction_to_blendedlos.py`, `../scripts/run_dbpool_experiment.py`
