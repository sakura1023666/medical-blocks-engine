# Blocks 双向合并报告（2026-11-24）

范围：`/mnt/e/01block/01Block` ↔ `/mnt/e/01block/01Block-new-Final`

## 原则
- **只增不删**：从未覆盖已有同路径文件；未删除任何功能
- 同路径内容不同（约 60 个 `.R`）**保持各自原样**，避免打断现有套路
- 路径改名（`*_full` / `16_weightcox` 等）用**兼容软链**补齐 `pipeline_runner` 映射，不改既有实现

## Skill
- 已把 `update-blocks-catalog`（含 `split-medical-block` 门控句）同步到：
  - `01Block-new-Final/.cursor/skills/update-blocks-catalog/`
  - `~/.cursor/skills/update-blocks-catalog/`
  - `01Block/.cursor/skills/update-blocks-catalog/`

## Blocks 文件
- OLD→NEW：补入缺失文件约 197 个（另有 11 个因父目录已是软链而跳过，功能已由目标目录覆盖）
- NEW→OLD：补入缺失文件约 387 个
- `register_block` id：两侧对齐（372 共同，差分 0）

## pipeline_runner
- NEW 增补 51 个仅 OLD 有的 map key；OLD 增补 61 个仅 NEW 有的 map key
- 两侧 map key 集合对齐；`b("…")` 路径解析 miss=0
- 备份：`R/pipeline_runner.R.bak_blocks_merge`

## 其它
- 同步 `run/environment/blocks_shell` 的 glide 块到 NEW，并建 `Blocks/74_glide_sol/` 软链
- 两侧已跑 `python3 scripts/update_blocks_catalog.py` 刷新 `docs/Blocks_catalog.md`

## 未自动合并（有意保留）
- 约 60 个同相对路径、内容不同的 `.R`（清单见合并当时 `/tmp/blocks_content_diff.txt`）
- 若后续要对齐某一文件的「新功能补丁」，需人工 diff 后外科合并，禁止整文件覆盖
