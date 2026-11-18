#!/usr/bin/env bash
# Nightly engine snapshot → branch nightly + tag nightly-YYYY-MM-DD
# Commits a full worktree snapshot onto nightly WITHOUT checkout/stash
# (avoids stash-pop conflicts when nightly diverged). Never force-pushes main.
set -euo pipefail

export TZ="${TZ:-Asia/Shanghai}"
export PATH="/root/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${REPO_ROOT}/logs/git_nightly"
mkdir -p "${LOG_DIR}"
DAY="$(date +%F)"
STAMP="$(date '+%F %H:%M')"
LOG_FILE="${LOG_DIR}/${DAY}.log"
TAG="nightly-${DAY}"
BRANCH="nightly"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" | tee -a "${LOG_FILE}"; }

# True secret-like paths only (exclude venv / site-packages / public CA bundles)
_secret_paths_from() {
  grep -E '(^|/)\.env($|\.)|(^|/)engine\.env$|(^|/)id_rsa($|\.)|(^|/)credentials\.json$|(^|/)secrets?\.ya?ml$|(^|/)[^/]*(private|secret|id_rsa)[^/]*\.pem$' \
    | grep -Ev '(^|/)\.venv(_[^/]*)?(/|$)|(^|/)venv(/|$)|/site-packages/|(^|/)node_modules(/|$)|/certifi/cacert\.pem$' \
    || true
}

cd "${REPO_ROOT}"

if [[ ! -d .git ]]; then
  log "ERROR: not a git repo: ${REPO_ROOT}"
  exit 1
fi

if [[ -d .git/rebase-merge || -d .git/rebase-apply || -f .git/MERGE_HEAD ]]; then
  log "ERROR: rebase/merge in progress; aborting"
  exit 1
fi

# Prefer staying on main for interactive work after the run
start_branch="$(git branch --show-current 2>/dev/null || true)"

# No trackable local changes → skip (do not fetch / push)
if [[ -z "$(git status --porcelain)" ]]; then
  log "skip: no local changes"
  exit 0
fi

# Coarse secret filename guard (never add these even if somehow un-ignored)
secret_hits="$(git status --porcelain -uall 2>/dev/null | awk '{print $NF}' | _secret_paths_from)"
if [[ -n "${secret_hits}" ]]; then
  log "ERROR: refusing to snapshot; secret-like paths present:"
  log "${secret_hits}"
  exit 1
fi

if ! git remote get-url origin >/dev/null 2>&1; then
  log "ERROR: no origin remote; skip"
  exit 1
fi

if ! git fetch origin 2>>"${LOG_FILE}"; then
  log "ERROR: git fetch origin failed"
  exit 1
fi

# Parent for the snapshot commit: existing nightly tip, else main
if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"; then
  parent="$(git rev-parse "refs/remotes/origin/${BRANCH}")"
elif git show-ref --verify --quiet "refs/remotes/origin/main"; then
  parent="$(git rev-parse refs/remotes/origin/main)"
else
  parent="$(git rev-parse refs/remotes/origin/master)"
fi

# Stage everything trackable into the index, then snapshot the tree.
# Stay on the current branch: do NOT checkout nightly / do NOT stash.
git add -A

staged_secrets="$(git diff --cached --name-only | _secret_paths_from)"
if [[ -n "${staged_secrets}" ]]; then
  log "ERROR: secret-like paths staged; aborting"
  git reset HEAD -- >/dev/null 2>&1 || true
  exit 1
fi

if git diff --cached --quiet; then
  log "skip: no local changes (nothing staged after add)"
  git reset HEAD -- >/dev/null 2>&1 || true
  exit 0
fi

tree="$(git write-tree)"
export GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-01Block}"
export GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-01block@users.noreply.github.com}"
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-$GIT_AUTHOR_NAME}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-$GIT_AUTHOR_EMAIL}"

commit="$(git commit-tree "${tree}" -p "${parent}" -m "nightly: snapshot ${STAMP} (auto)")"
git update-ref "refs/heads/${BRANCH}" "${commit}"
git push origin "refs/heads/${BRANCH}:refs/heads/${BRANCH}" >>"${LOG_FILE}" 2>&1

git tag -f "${TAG}" "${commit}"
git push -f origin "refs/tags/${TAG}" >>"${LOG_FILE}" 2>&1

# Unstage relative to current HEAD; keep worktree files as they were
git reset HEAD -- >/dev/null 2>&1 || true

if [[ -n "${start_branch}" && "${start_branch}" != "$(git branch --show-current 2>/dev/null || true)" ]]; then
  git checkout "${start_branch}" >/dev/null 2>&1 || true
fi

log "OK: pushed ${BRANCH} (${commit:0:7}) + tag ${TAG}"
exit 0
