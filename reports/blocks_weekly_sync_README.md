# 01Block ↔ 01Block-new-Final 每周六自动同步

## 调度
- **时间**：每周六 **09:00**（`TZ=Asia/Shanghai`）
- **命令**：`/mnt/e/01block/01Block-new-Final/scripts/sync_01block_weekly.sh`
- **crontab**：`0 9 * * 6 …/sync_01block_weekly.sh`
- **日志**：`logs/blocks_weekly_sync/cron.log` 与 `logs/blocks_weekly_sync/YYYY-MM-DD.log`
- **报告**：`reports/blocks_weekly_sync_YYYY-MM-DD.md`

## 同步范围（只增不删、不覆盖）
`Blocks/`、`R/`、`scripts/`、`configs/templates|indices|study_interface/`、`python/`、`run/`（代码类）、`.cursor/skills`（文案/脚本，不含 assets 图）、`tests/`  
另：合并缺失的 `pipeline_runner` map key、补 map 软链、刷新两侧 `Blocks_catalog.md`。

## 手工跑
```bash
# 预览
python3 scripts/sync_01block_bidirectional.py --dry-run

# 正式
bash scripts/sync_01block_weekly.sh
# 或
python3 scripts/sync_01block_bidirectional.py
```

## 注意
1. WSL 在周六 09:00 须处于运行状态，否则 cron 不会触发（开机后 `@reboot` 会尝试拉起 cron）。
2. 同路径内容不同的文件**不会**自动覆盖；需人工 diff 后再合。
3. 查看任务：`crontab -l | grep sync_01block`
