# Git 远程工作流（私有 GitHub）

仓库：`medical-blocks-engine`（private）  
本机路径：`/mnt/e/01block/01Block-new-Final`

## 分支角色

| 分支 | 用途 |
|------|------|
| `main` | 稳定主线；通过 PR 合并 |
| `feature/*` | 日常功能 / 修 bug |
| `nightly` | 凌晨自动快照（脚本直推）；需收口时再开 PR 到 `main` |

## 日常改动（推荐）

```bash
cd /mnt/e/01block/01Block-new-Final
git checkout main
git pull --ff-only origin main
git checkout -b feature/short-description
# …编辑…
git add -A
git status   # 确认无 .env / 结果目录 / dabiao
git commit -m "简述 why"
git push -u origin HEAD
gh pr create --base main --fill
```

合并后删除本地分支即可。

## Agent / Cursor

- **仅在你明确要求 commit 时**才提交；不要默认 commit。
- 唯一自动 commit 入口：`scripts/git_nightly_snapshot.sh`（见同目录 README）。

## 夜间快照

- 时间：每天 01:00 `Asia/Shanghai`
- 有改动 → push `nightly` + tag `nightly-YYYY-MM-DD`
- 无改动 → `skip: clean`
- 不自动开 PR；需要时：

```bash
gh pr create --base main --head nightly --title "Nightly absorb YYYY-MM-DD"
```

## 部署关系

5006 / 34 等主机仍用 **rsync**（排除 `.git`）。GitHub 负责版本与协作，**不替代**现有部署路径。

## 首次登录 / 建私有仓（本机网络口径）

实测：WSL 访问 **`github.com:443` 常超时**，但 **`api.github.com`** 与 **`ssh.github.com:443`** 可用。因此：

- `gh` API / 建仓：用 **PAT**（走 api.github.com）
- `git push/pull`：用 **SSH（443 端口）**（本机已配置 `~/.ssh/config` → `ssh.github.com:443`）
- 公钥已落盘：[`docs/dev/github_ssh_pubkey.txt`](github_ssh_pubkey.txt)

### 推荐一步到位（PAT）

1. 在能打开 GitHub 的浏览器创建 classic PAT（**repo** + **admin:public_key**）  
2. 本机执行：

```bash
umask 077
printf '%s' 'ghp_你的token' > /mnt/e/01block/01Block-new-Final/.gh_token
export PATH="/root/.local/bin:$PATH"
bash /mnt/e/01block/01Block-new-Final/scripts/git_setup_remote.sh
```

脚本会：`gh auth` → 上传 SSH 公钥 → 建 private `medical-blocks-engine` → SSH 推送 `main` + `nightly`。

### 手工备用（无 PAT）

1. 网页添加 SSH key（粘贴 `github_ssh_pubkey.txt`）  
2. 网页新建 **private** 空仓 `medical-blocks-engine`（不要勾选 README）  
3. 本机：

```bash
cd /mnt/e/01block/01Block-new-Final
git remote add origin git@github.com:<你的用户名>/medical-blocks-engine.git
git push -u origin main
git checkout -b nightly && git push -u origin nightly && git checkout main
```
