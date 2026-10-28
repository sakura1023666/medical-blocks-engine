#!/usr/bin/env bash
# 四库协调长表 → 每人一张小时宽表。
# 在 Aiya-Linux (192.168.68.29) 上跑，数据默认就在本机 /mnt/sda。
# 别的课题复用同一份 blended_data，只改 --out，不要重抽官方原库。
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PY="${BLENDEDICU_PYTHON:-/mnt/sda/BlendedICU/env/bin/python}"
if [[ ! -x "$PY" ]]; then
  PY="${ROOT}/.venv_dbpool/bin/python"
fi
exec "$PY" "${ROOT}/Blocks/78_database_pooling_full/scripts/build_blendedlos_hourly.py" "$@"
