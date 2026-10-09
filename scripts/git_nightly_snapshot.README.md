# Nightly git snapshot (`git_nightly_snapshot.sh`)

每天 **01:00（Asia/Shanghai）** 自动把引擎工作区可跟踪改动提交到 GitHub 私有仓的 `nightly` 分支，并打当日 tag `nightly-YYYY-MM-DD`。

## 行为

- 有可跟踪改动 → `commit` + `push origin nightly` + 移动当日 tag
- 工作区干净 → 日志写 `skip: clean`，退出 0
- **不** push `main`，**不** 自动开 PR
- 发现 `.env` / `engine.env` / `*.pem` 等敏感路径 → 拒绝提交

## Cron

```cron
TZ=Asia/Shanghai
0 1 * * * /mnt/e/01block/01Block-new-Final/scripts/git_nightly_snapshot.sh >> /mnt/e/01block/01Block-new-Final/logs/git_nightly/cron.log 2>&1
```

日志目录：`logs/git_nightly/`（已被 `.gitignore` 忽略）。

## WSL 保活

WSL 未启动时 cron 不会跑。Windows「任务计划程序」建议加一条 **用户登录时**：

```bat
wsl -u root -- service cron start
```

笔记本睡眠导致漏跑可接受：开机后等下一个 01:00。

## 手工试跑

```bash
bash /mnt/e/01block/01Block-new-Final/scripts/git_nightly_snapshot.sh
tail -n 50 /mnt/e/01block/01Block-new-Final/logs/git_nightly/$(date +%F).log
```

## 停用

```bash
crontab -l | grep -v git_nightly_snapshot | crontab -
```

## 认证

脚本依赖本机已配置的 `git`/`gh` 凭据（`gh auth login` 或 `credential.helper`）。换机后需重新登录。
