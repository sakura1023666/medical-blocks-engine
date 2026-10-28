#!/usr/bin/env bash
# One-shot: authenticate (if needed), create private origin, push main+nightly.
# Usage:
#   export GH_TOKEN=ghp_xxx   # classic PAT with repo scope, OR run: gh auth login
#   bash scripts/git_setup_remote.sh [owner/repo]
set -euo pipefail
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export TZ=Asia/Shanghai

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

DEFAULT_NAME="medical-blocks-engine"
TARGET="${1:-}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh not found; install to /root/.local/bin/gh" >&2
  exit 1
fi

TOKEN_FILE="${REPO_ROOT}/.gh_token"
if ! gh auth status >/dev/null 2>&1; then
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s\n' "${GH_TOKEN}" | gh auth login --hostname github.com --with-token
  elif [[ -f "${TOKEN_FILE}" ]]; then
    gh auth login --hostname github.com --with-token < "${TOKEN_FILE}"
  else
    echo "ERROR: not logged in. Run one of:" >&2
    echo "  printf '%s' 'ghp_xxx' > ${TOKEN_FILE} && bash scripts/git_setup_remote.sh" >&2
    echo "  GH_TOKEN=ghp_xxx bash scripts/git_setup_remote.sh" >&2
    echo "  gh auth login --hostname github.com --git-protocol https --web" >&2
    exit 1
  fi
fi
# Prefer API host for gh; git HTTPS still uses github.com (needs network reachability)
gh config set git_protocol https -h github.com >/dev/null 2>&1 || true

OWNER="$(gh api user -q .login)"
REPO_SLUG="${TARGET:-${OWNER}/${DEFAULT_NAME}}"
echo "Using repo: ${REPO_SLUG} (private)"

# Ensure baseline identity
git config user.name >/dev/null 2>&1 || git config user.name "01Block"
git config user.email >/dev/null 2>&1 || git config user.email "01block@users.noreply.github.com"

# Prefer SSH over port 443 (ssh.github.com). WSL often cannot TCP to github.com:443.
SSH_URL="git@github.com:${REPO_SLUG}.git"
PUBKEY="${HOME}/.ssh/id_ed25519_github.pub"
if [[ -f "${PUBKEY}" ]]; then
  # Upload host key if not already present (idempotent best-effort)
  TITLE="01block-wsl-medical-blocks"
  if ! gh ssh-key list 2>/dev/null | grep -q "${TITLE}"; then
    gh ssh-key add "${PUBKEY}" --title "${TITLE}" || true
  fi
fi

# Create remote repo if missing
if ! gh repo view "${REPO_SLUG}" >/dev/null 2>&1; then
  gh repo create "${REPO_SLUG}" --private --disable-wiki --description "Medical Blocks engine (private)"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "${SSH_URL}"
else
  git remote add origin "${SSH_URL}"
fi
echo "origin -> $(git remote get-url origin)"

# Push main
git checkout main
git push -u origin main

# nightly branch
if git show-ref --verify --quiet refs/heads/nightly; then
  git checkout nightly
else
  git checkout -b nightly
fi
git push -u origin nightly
git checkout main

echo "OK: origin=$(git remote get-url origin)"
gh repo view "${REPO_SLUG}" --json name,visibility,url -q .
