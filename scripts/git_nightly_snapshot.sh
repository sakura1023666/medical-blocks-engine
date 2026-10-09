#!/usr/bin/env bash
# Nightly engine snapshot → branch nightly + tag nightly-YYYY-MM-DD
# Only commits when the worktree has trackable changes. Never force-pushes main.
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

cd "${REPO_ROOT}"

if [[ ! -d .git ]]; then
  log "ERROR: not a git repo: ${REPO_ROOT}"
  exit 1
fi

if [[ -d .git/rebase-merge || -d .git/rebase-apply || -f .git/MERGE_HEAD ]]; then
  log "ERROR: rebase/merge in progress; aborting"
  exit 1
fi

# Coarse secret filename guard (never add these even if somehow un-ignored)
secret_hits="$(git status --porcelain -uall 2>/dev/null | awk '{print $NF}' | grep -E '(^|/)\.env($|\.)|(^|/)engine\.env$|\.pem$|id_rsa|credentials\.json|secrets?\.ya?ml$' || true)"
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

# Preserve local worktree across branch switches
STASHED=0
if [[ -n "$(git status --porcelain)" ]]; then
  git stash push -u -m "nightly-auto-stash ${STAMP}" >>"${LOG_FILE}" 2>&1 || true
  STASHED=1
fi

# Ensure local nightly tracks origin/nightly (create from main if missing)
if git show-ref --verify --quiet "refs/remotes/origin/${BRANCH}"; then
  git checkout -B "${BRANCH}" "origin/${BRANCH}" >>"${LOG_FILE}" 2>&1
elif git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git checkout "${BRANCH}" >>"${LOG_FILE}" 2>&1
  git push -u origin "${BRANCH}" >>"${LOG_FILE}" 2>&1 || true
else
  base="main"
  git show-ref --verify --quiet refs/remotes/origin/main || base="master"
  git checkout -B "${BRANCH}" "origin/${base}" >>"${LOG_FILE}" 2>&1
  git push -u origin "${BRANCH}" >>"${LOG_FILE}" 2>&1
fi

# Fast-forward main into nightly when possible (ignore failure)
if git show-ref --verify --quiet refs/remotes/origin/main; then
  git merge --ff-only origin/main >>"${LOG_FILE}" 2>&1 || log "INFO: ff-only merge origin/main skipped"
fi

if [[ "${STASHED}" -eq 1 ]]; then
  if ! git stash pop >>"${LOG_FILE}" 2>&1; then
    log "ERROR: stash pop conflict; leaving stash; aborting without push"
    exit 1
  fi
fi

if [[ -z "$(git status --porcelain)" ]]; then
  log "skip: clean"
  git checkout main >/dev/null 2>&1 || true
  exit 0
fi

git add -A

# Re-check secrets staged
staged_secrets="$(git diff --cached --name-only | grep -E '(^|/)\.env($|\.)|(^|/)engine\.env$|\.pem$|id_rsa|credentials\.json' || true)"
if [[ -n "${staged_secrets}" ]]; then
  log "ERROR: secret-like paths staged; aborting"
  git reset HEAD -- >/dev/null 2>&1 || true
  exit 1
fi

if git diff --cached --quiet; then
  log "skip: clean (nothing staged after add)"
  git checkout main >/dev/null 2>&1 || true
  exit 0
fi

git -c user.name="${GIT_AUTHOR_NAME:-01Block}" \
    -c user.email="${GIT_AUTHOR_EMAIL:-01block@users.noreply.github.com}" \
    commit -m "nightly: snapshot ${STAMP} (auto)" >>"${LOG_FILE}" 2>&1

git push origin "${BRANCH}" >>"${LOG_FILE}" 2>&1

git tag -f "${TAG}"
git push -f origin "refs/tags/${TAG}" >>"${LOG_FILE}" 2>&1

log "OK: pushed ${BRANCH} + tag ${TAG}"

git checkout main >/dev/null 2>&1 || true
exit 0
