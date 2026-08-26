# 一次性脚本清理与复用入口（2026-08-14）

## 目标

把对话/调试产生的散落脚本收拢：引擎可复用逻辑留在 `R/`/`Blocks/`/`tests/`；课题一次性 peek 不进仓库；通用「抽全指标关键表」进 `run/incidence/`；历史重画草稿进 `_archive/`。

## 决策（用户选 C）

1. **删除** `/tmp/peek_ra_tables.R`、`/tmp/extract_ra_all.R`（及 `/tmp/ra_index_extract.csv` 若存在）——硬编码课题路径，不进引擎。
2. **新增** `run/incidence/summarize_index_tables.R`：按 `--root` 扫描 `by_index/【success】*` 汇总 Tables，按**表题/文件名角色**识别（不用死绑 S 号）。
3. **归档** `tmp_bar_figfix/` → `_archive/tmp_bar_figfix/`（不删内容，避免误伤旧重画稿）。
4. **不改**本轮已进引擎的正式修复（汇总禁 `.tex`、中介 `.M_z`、finalize purge、guards）。

## 非目标

- 不把 RA 课题特有 prep 挪出 `run/rheumatoid_ascvd/`。
- 不自动提交 git（本工作区未必是 git 根）。
