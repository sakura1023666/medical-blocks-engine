# 唯一可写的引擎文件：复合指标 `index`

本目录是程序员编辑引擎 **index** block 的**唯一入口**。

## 链接目标

`01block_index.R` → 引擎  
`MEDICAL_BLOCKS_ROOT/Blocks/00_index/01block_index.R`

用编辑器打开本目录下的 `01block_index.R` 即在改引擎原文件。

## 警告（必读）

- **一改全局**：5001 / 5003 / 5006 及所有研究共用同一份公式。
- **不要**改其它 `Blocks/**`、`R/`、`engine.env`。
- 改公式前建议先备份或确认 git 可回滚。
- 改完用某研究冒烟：`run_study.bat <研究名> --shared-only` 或 `--only-index BMI`。

## 运行时

流水线仍从引擎路径加载 index；本链接**只是编辑入口**，不是按研究隔离的副本。

设计说明：引擎仓库  
`docs/superpowers/specs/2026-07-17-programmer-writable-index-block-design.md`
