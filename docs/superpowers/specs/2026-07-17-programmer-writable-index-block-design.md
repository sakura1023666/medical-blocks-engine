# 设计：程序员唯一可写引擎文件 — index block（方案 B）

> 日期：2026-07-17  
> 状态：已批准实施实施  
> 范围：5001 / 5003 / 5006 程序员研究区 + 引擎 `Blocks/00_index/01block_index.R`

## 1. 问题

隔离模式下程序员不能写 `Blocks/`。业务需要允许改复合指标公式（BMI、SII、CONUT 等），且明确：**只能改这一个文件，其它 Blocks 一律不能改**；改动对所有研究/端口共用。

## 2. 方案 B（已选）

在研究区根提供**唯一编辑入口**，用符号链接指向引擎共用文件：

```text
medical-blocks-studies/editable/01block_index.R
  → MEDICAL_BLOCKS_ROOT/Blocks/00_index/01block_index.R
```

- 程序员只编辑 `editable/01block_index.R`
- 运行时仍从引擎路径 `source`（`pipeline_block_sources()` 不变）
- 链接只是编辑入口，不是按研究隔离的副本

## 3. 红线

| 能改 | 不能改 |
|------|--------|
| `editable/01block_index.R`（实为引擎 index） | 其它 `Blocks/**` |
| `studies/<研究>/config.R`、`Data/` | `R/`、`engine.env` |
| CLI 生成的 `extensions.json`、`tree_v*.md` | 母版决策树；手改 `pipeline_*$blocks` |

一改 index → **5001/5003/5006 及所有研究立刻共用新公式**。回滚靠 git/备份。

## 4. 部署

`scripts/deploy_block_hooks_to_studies.sh`（或同脚本内逻辑）对每个端口：

1. `mkdir -p editable/`
2. `ln -sfn "$ENGINE/Blocks/00_index/01block_index.R" editable/01block_index.R`
3. 写入 `editable/README.md`（全局影响警告）

引擎路径：优先读研究区 `engine.env` 的 `MEDICAL_BLOCKS_ROOT`，否则用部署时的仓库根。

## 5. 非目标

- 不按研究覆盖 index
- 不硬校验「是否改了其它 Blocks 文件」
- 不开放 `column_mapping` 等其它 block
- 不改 `register_block` / runner 加载路径

## 6. 验收

- 各端口 `editable/01block_index.R` 解析后等于引擎该文件
- 手册「能改/不能改」与例外表述一致
- 经入口保存后，任意研究加载到的仍是引擎同一 inode/路径
