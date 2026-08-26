# Task 6 Report: 发表图四目录约定文档

**Status:** 完成

**Date:** 2026-08-20

## 任务

在 `docs/Blocks_catalog.md` MANUAL「常见坑」区补充发表图四目录交付约定。

## 变更

| 文件 | 操作 |
|---|---|
| `docs/Blocks_catalog.md` | MANUAL:PITFALLS 段新增一条 bullet（紧接双库 Figures 拼图坑点之后） |

新增内容：

> 汇总 `Figures/`（及交叉滞后 `summary_result/figure`）顶层只保留 `pdf/` `png/` `tiff/` `image_information/`；多库先拼图再导出；TIFF=LZW。

## 未执行

- `python3 scripts/update_blocks_catalog.py` — 未改 `register_block` 头，无需重跑 AUTO 段。
- `git commit` — 按 global constraints 与任务说明跳过（workspace 无 `.git`）。

## 验收

- [x] 仅修改 MANUAL:PITFALLS，未手改 AUTO 段
- [x] 约定与 `pubfig-global-constraints.md` 一致（四目录、LZW、多库先拼图）
