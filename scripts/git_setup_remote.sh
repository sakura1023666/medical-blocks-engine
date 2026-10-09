#!/usr/bin/env bash
# One-shot: authenticate via GH_TOKEN env (no gh auth login / no read:org required),
# ensure remote exists, upload SSH key if possible, push main+nightly over SSH:443.
# Usage:
#   printf '%s' 'ghp_xxx' > .gh_token   # classic: repo (+ admin:public_key to auto-upload key)
#   bash scripts/git_setup_remote.sh [owner/repo]
set -euo pipefail
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export TZ=Asia/Shanghai

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

DEFAULT_NAME="medical-blocks-engine"
TARGET="${1:-}"
TOKEN_FILE="${REPO_ROOT}/.gh_token"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: gh not found; install to /root/.local/bin/gh" >&2
  exit 1
fi

# Prefer env GH_TOKEN; else load from file. Do NOT use `gh auth login --with-token`
# (that path requires read:org even when unused).
if [[ -z "${GH_TOKEN:-}" ]]; then
  if [[ -f "${TOKEN_FILE}" ]]; then
    GH_TOKEN="$(tr -d '\r\n' < "${TOKEN_FILE}")"
    export GH_TOKEN
  else
    echo "ERROR: set GH_TOKEN or write ${TOKEN_FILE}" >&2
    exit 1
  fi
fi

if ! OWNER="$(gh api user -q .login 2>/dev/null)"; then
  echo "ERROR: token cannot call api.github.com/user (check repo scope / token validity)" >&2
  exit 1
fi
REPO_SLUG="${TARGET:-${OWNER}/${DEFAULT_NAME}}"
echo "Using repo: ${REPO_SLUG} (login=${OWNER})"

git config user.name >/dev/null 2>&1 || git config user.name "01Block"
git config user.email >/dev/null 2>&1 || git config user.email "01block@users.noreply.github.com"

SSH_URL="git@github.com:${REPO_SLUG}.git"
PUBKEY="${HOME}/.ssh/id_ed25519_github.pub"
TITLE="01block-wsl-medical-blocks"
if [[ -f "${PUBKEY}" ]]; then
  if ! gh api user/keys --jq '.[].title' 2>/dev/null | grep -qx "${TITLE}"; then
    echo "Uploading SSH public key (${TITLE})..."
    gh ssh-key add "${PUBKEY}" --title "${TITLE}" || \
      echo "WARN: SSH key upload failed (need admin:public_key, or add key manually on GitHub)."
  else
    echo "SSH key already on account: ${TITLE}"
  fi
fi

if ! gh repo view "${REPO_SLUG}" >/dev/null 2>&1; then
  echo "Creating public repo ${REPO_SLUG}..."
  gh repo create "${REPO_SLUG}" --public --disable-wiki --description "Medical Blocks engine"
else
  echo "Remote repo already exists."
fi

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "${SSH_URL}"
else
  git remote add origin "${SSH_URL}"
fi
echo "origin -> $(git remote get-url origin)"

# Ensure ssh config uses port 443
mkdir -p "${HOME}/.ssh"
chmod 700 "${HOME}/.ssh"
if ! grep -q 'Host github.com' "${HOME}/.ssh/config" 2>/dev/null; then
  cat >> "${HOME}/.ssh/config" <<'EOF'
Host github.com
  HostName ssh.github.com
  Port 443
  User git
  IdentityFile ~/.ssh/id_ed25519_github
  IdentitiesOnly yes
EOF
  chmod 600 "${HOME}/.ssh/config"
fi

echo "Testing SSH to GitHub..."
ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -T git@github.com 2>&1 | tee /tmp/gh_ssh_test.txt || true
if ! grep -qi 'successfully authenticated' /tmp/gh_ssh_test.txt; then
  echo "ERROR: SSH auth failed. Add pubkey from docs/dev/github_ssh_pubkey.txt to GitHub → Settings → SSH keys, then re-run." >&2
  exit 1
fi

git checkout main
git push -u origin main

if git show-ref --verify --quiet refs/heads/nightly; then
  git checkout nightly
else
  git checkout -b nightly
fi
git push -u origin nightly
git checkout main

echo "OK: origin=$(git remote get-url origin)"
gh repo view "${REPO_SLUG}" --json name,visibility,url -q .
