# Blocks/78 — 数据库池化（BlendedLoS）

预后地基后缀：多源池化 / 迁移学习 + TPC。公开代码**进本目录**，便于跨课题复用。

## 目录

```
78_database_pooling_full/
├── 00dbpool_common.R … 09block_*.R     # register_block 流水线
├── upstream/
│   ├── README.md                       # provenance
│   └── BlendedLoS/                     # ★ 公开代码镜像 (CIC-1410/BlendedLoS)
│       ├── 1_split_train_test.py
│       ├── 2_run_experiment.py
│       ├── 3_generate_table.py …
│       ├── models/  database/  utils/
│       └── env.yml
└── scripts/
    ├── adapt_realextraction_to_blendedlos.py
    └── run_dbpool_experiment.py        # 封装上游实验单元
```

## 复用约定

1. 训练/评估只调 `upstream/BlendedLoS/`，勿课题私改上游。
2. 数据适配、batch 单元、发表收口写在 `scripts/` + `0*.R`。
3. config：`dbpool$upstream_dir` 默认同本路径。
4. 兼容：`python/blended_los_upstream` → symlink 到本 `upstream/BlendedLoS`。
