# scripts/

仅保留**跨研究、程序员接口**相关工具（勿再往本目录堆项目一次性脚本）。

| 文件 | 用途 |
|------|------|
| `export_block_catalog.R` | 导出只读 Block 目录供检索（`docs/block_catalog/`） |
| `update_blocks_catalog.py` | 同步写 config 用选型字典 `docs/Blocks_catalog.md` |
| `run_programmer_block_hooks_cli.R` | programmer hooks CLI（search/list/add/remove） |
| `deploy_block_hooks_to_studies.sh` | 向各 study 区部署 hooks / catalog |

项目专用脚本请放：
- 入口：`run/<project>/`
- 工具/smoke：`Blocks/<nn>_*/scripts/`
