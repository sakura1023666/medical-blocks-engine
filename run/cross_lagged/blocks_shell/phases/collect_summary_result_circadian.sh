#!/usr/bin/env bash
# Back-compat alias: circadian-specific collect is now the generic collector.
# mosaic/export 在 generic 末尾调用 export_summary_figures.R
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/collect_summary_result_generic.sh" "$@"
