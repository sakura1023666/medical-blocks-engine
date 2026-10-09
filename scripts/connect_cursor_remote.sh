#!/usr/bin/env bash
# 一键：Cursor 登录 → 创建远端仓库 → git push
# 用法：bash scripts/connect_cursor_remote.sh [repo-name]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

export PATH="$ROOT/.tools/bin:${PATH:-}"

if ! command -v origin >/dev/null 2>&1; then
  echo "未找到 origin CLI。请先确认存在: $ROOT/.tools/bin/origin"
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "当前目录不是 git 仓库。请先 git init。"
  exit 1
fi

REPO_NAME="${1:-01block-new-final}"
REPO_NAME="$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"

echo "=== 1/4 检查 Cursor 登录 ==="
# 勿用 pipe + pipefail：未登录时 origin auth status 退出码为 1，会令整条管道失败
if ! origin auth status >/dev/null 2>&1; then
  echo "尚未登录 Cursor。"
  echo "将打开浏览器完成登录（若未弹出，请复制终端里的链接到浏览器打开）。"
  if ! origin auth login; then
    echo ""
    echo "登录未完成。请在本终端手动执行后重跑本脚本："
    echo "  export PATH=\"$ROOT/.tools/bin:\$PATH\""
    echo "  origin auth login"
    exit 1
  fi
fi
origin auth status

echo ""
echo "=== 2/4 创建 Cursor 远端仓库: ${REPO_NAME} ==="
CREATE_OUT="$(origin repo create --repo "$REPO_NAME" 2>&1 || true)"
echo "$CREATE_OUT"

# 若仓库已存在，create 可能报错；仍尝试从 list 取 URL
CLONE_URL="$(echo "$CREATE_OUT" | grep -oE 'https://[^[:space:]]+\.git' | head -1 || true)"
if [[ -z "${CLONE_URL:-}" ]]; then
  LIST_OUT="$(origin repo list 2>&1 || true)"
  CLONE_URL="$(echo "$LIST_OUT" | grep -i "$REPO_NAME" | grep -oE 'https://[^[:space:]]+\.git' | head -1 || true)"
fi

if [[ -z "${CLONE_URL:-}" ]]; then
  echo ""
  echo "未能自动解析 clone URL。请从 Cursor Codebase 页面复制 HTTPS 地址，例如："
  echo "  https://origin.cursor.com/<你的命名空间>/${REPO_NAME}.git"
  read -rp "粘贴 clone URL: " CLONE_URL
fi

echo ""
echo "=== 3/4 配置 git remote origin ==="
if git remote get-url origin >/dev/null 2>&1; then
  CURRENT="$(git remote get-url origin)"
  echo "已存在 origin: $CURRENT"
  read -rp "是否改为新地址? [y/N] " yn
  if [[ "${yn:-N}" =~ ^[Yy]$ ]]; then
    git remote set-url origin "$CLONE_URL"
  fi
else
  git remote add origin "$CLONE_URL"
fi
echo "origin -> $(git remote get-url origin)"

echo ""
echo "=== 4/4 推送 main ==="
if ! git rev-parse --verify main >/dev/null 2>&1; then
  echo "没有 main 分支，请检查当前分支: $(git branch --show-current)"
  exit 1
fi

git push -u origin main

echo ""
echo "完成。远端仓库已连接并推送 main。"
echo "仓库页面一般在: https://cursor.com/codebase （在列表中找到 ${REPO_NAME}）"
echo ""
echo "提示：工作区里未提交的改动不会自动推送；需要时先 git add / git commit。"
